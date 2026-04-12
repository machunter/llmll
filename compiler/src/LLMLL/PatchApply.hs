-- |
-- Module      : LLMLL.PatchApply
-- Description : RFC 6902 JSON-Patch application with scope validation and re-verification.
--
-- The LLMLL patch lifecycle:
--   1. Validate token against lock file (auto-expire stale)
--   2. Scope check: all op paths are descendant-or-self of checkout pointer
--   3. Load source .ast.json as Value
--   4. Apply RFC 6902 ops (replace/add/remove/test)
--   5. Re-parse Value → [Statement] via parseJSONASTValue
--   6. Re-typecheck
--   7. On success: write updated .ast.json, clear lock entry
--
-- Advisory flock held for the entire read→verify→write cycle (§2.3).
module LLMLL.PatchApply
  ( PatchRequest(..)
  , PatchOp(..)
  , PatchResult(..)
  , applyPatch
  , applyOp
  , applyOps
  , validateScope
  , parsePatchRequest
  , parsePatchOp
  , toPatchOpInfos
  ) where

import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), withObject, (.:), (.=), object)
import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.Types as AT
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import LLMLL.JsonPointer (resolvePointer, setAtPointer, removeAtPointer, parsePointer)
import LLMLL.Checkout (loadLock, saveLock, expireStale, CheckoutToken(..), CheckoutLock(..))
import LLMLL.ParserJSON (parseJSONASTValue)
import LLMLL.TypeCheck (typeCheck, emptyEnv)
import LLMLL.Diagnostic (Diagnostic(..), DiagnosticReport(..), PatchOpInfo(..), rebaseToPatch)
import LLMLL.Syntax (Statement)

import Data.Time.Clock (getCurrentTime)

-- ---------------------------------------------------------------------------
-- Data Types
-- ---------------------------------------------------------------------------

data PatchRequest = PatchRequest
  { prToken :: Text
  , prPatch :: [PatchOp]
  } deriving (Show, Eq, Generic)

data PatchOp
  = PatchReplace Text Value   -- "replace" path value
  | PatchAdd     Text Value   -- "add"     path value
  | PatchRemove  Text         -- "remove"  path
  | PatchTest    Text Value   -- "test"    path expected-value
  deriving (Show, Eq, Generic)

data PatchResult
  = PatchSuccess Int               -- number of statements in result
  | PatchTypeError DiagnosticReport -- type errors from re-verification
  | PatchApplyError Text           -- structural error, test failure, move/copy rejection
  | PatchAuthError Text            -- invalid/expired/scope-violation
  deriving (Show)

instance ToJSON PatchResult where
  toJSON (PatchSuccess n) = object
    [ "result"     .= ("PatchSuccess" :: Text)
    , "statements" .= n
    ]
  toJSON (PatchTypeError report) = object
    [ "result"      .= ("PatchTypeError" :: Text)
    , "diagnostics" .= reportDiagnostics report
    ]
  toJSON (PatchApplyError msg) = object
    [ "result"  .= ("PatchApplyError" :: Text)
    , "message" .= msg
    ]
  toJSON (PatchAuthError msg) = object
    [ "result"  .= ("PatchAuthError" :: Text)
    , "message" .= msg
    ]

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

parsePatchRequest :: Value -> Either Text PatchRequest
parsePatchRequest val = case AT.parseEither parser val of
  Left err -> Left (T.pack err)
  Right pr -> Right pr
  where
    parser = withObject "PatchRequest" $ \o -> do
      tok   <- o .: "token"
      opArr <- o .: "patch" :: AT.Parser [Value]
      -- Parse each op, collecting errors
      ops <- mapM (\v -> case parsePatchOp v of
                     Left err -> fail (T.unpack err)
                     Right op -> pure op) opArr
      pure PatchRequest { prToken = tok, prPatch = ops }

-- | Parse a single RFC 6902 patch operation.
-- Rejects move/copy with clear error (§3.1).
parsePatchOp :: Value -> Either Text PatchOp
parsePatchOp = \val -> case AT.parseEither parser val of
  Left err -> Left (T.pack err)
  Right op -> Right op
  where
    parser = withObject "PatchOp" $ \o -> do
      opStr <- o .: "op" :: AT.Parser Text
      path  <- o .: "path" :: AT.Parser Text
      case opStr of
        "replace" -> PatchReplace path <$> o .: "value"
        "add"     -> PatchAdd path     <$> o .: "value"
        "remove"  -> pure $ PatchRemove path
        "test"    -> PatchTest path    <$> o .: "value"
        "move"    -> fail "RFC 6902 'move' is not supported in v0.3; use 'remove' + 'add' instead"
        "copy"    -> fail "RFC 6902 'copy' is not supported in v0.3; use 'add' with the source value instead"
        _         -> fail $ "unknown patch op: " ++ T.unpack opStr

-- ---------------------------------------------------------------------------
-- Scope Validation (§2.2)
-- ---------------------------------------------------------------------------

-- | Scope containment check.
-- All op paths must be descendant-or-self of the checkout pointer.
-- NOTE: test ops are also scope-checked in v0.3. Cross-scope test
-- (e.g., asserting a sibling function's signature) is deferred to v0.4.
-- Agents can read the JSON-AST independently to assert pre-conditions
-- outside the checkout subtree.
validateScope :: Text -> [PatchOp] -> Either Text ()
validateScope checkoutPtr ops = mapM_ checkOp ops
  where
    checkoutSegs = parsePointer checkoutPtr
    checkOp op =
      let opPath = opPathOf op
          opSegs = parsePointer opPath
      in if checkoutSegs `isPrefixOf'` opSegs || opSegs `isPrefixOf'` checkoutSegs
           then Right ()
           else Left $ "scope violation: op path " <> opPath
                       <> " is outside checkout scope " <> checkoutPtr

    opPathOf (PatchReplace p _) = p
    opPathOf (PatchAdd p _)     = p
    opPathOf (PatchRemove p)    = p
    opPathOf (PatchTest p _)    = p

    isPrefixOf' [] _          = True
    isPrefixOf' _ []          = False
    isPrefixOf' (x:xs) (y:ys) = x == y && isPrefixOf' xs ys

-- ---------------------------------------------------------------------------
-- Single Op Application
-- ---------------------------------------------------------------------------

-- | Apply a single patch op to a JSON Value.
applyOp :: PatchOp -> Value -> Either Text Value
applyOp (PatchReplace path newVal) root =
  case resolvePointer path root of
    Nothing -> Left $ "replace: path " <> path <> " does not exist"
    Just _  -> setAtPointer path newVal root
applyOp (PatchAdd path newVal) root =
  -- For existing paths: set. For new keys in objects: insert.
  setAtPointer path newVal root
applyOp (PatchRemove path) root =
  removeAtPointer path root
applyOp (PatchTest path expected) root =
  case resolvePointer path root of
    Nothing  -> Left $ "test: path " <> path <> " does not exist"
    Just val ->
      if val == expected
        then Right root  -- test passes, value unchanged
        else Left $ "test: value at " <> path <> " does not match expected"

-- | Apply all ops in sequence; short-circuit on first failure.
applyOps :: [PatchOp] -> Value -> Either Text Value
applyOps []     val = Right val
applyOps (o:os) val = case applyOp o val of
  Left err   -> Left err
  Right val' -> applyOps os val'

-- ---------------------------------------------------------------------------
-- Full Lifecycle
-- ---------------------------------------------------------------------------

-- | Full patch lifecycle.
-- 1. Validate token against lock file
-- 2. Scope check
-- 3. Load and patch JSON Value
-- 4. Re-parse and re-typecheck
-- 5. On success: write file, clear lock
applyPatch :: FilePath -> PatchRequest -> IO PatchResult
applyPatch fp pr = do
  now <- getCurrentTime

  -- 1. Load and validate lock
  mLock <- loadLock fp
  let lock = maybe (CheckoutLock fp []) id mLock
      cleanLock = expireStale now lock
      matchingTokens = filter (\ct -> ctToken ct == prToken pr) (lockTokens cleanLock)

  case matchingTokens of
    [] -> pure $ PatchAuthError "invalid or expired checkout token"
    (ct:_) -> do
      -- 2. Scope check
      case validateScope (ctPointer ct) (prPatch pr) of
        Left err -> pure $ PatchAuthError err
        Right () -> do
          -- 3. Load source JSON
          raw <- BL.readFile fp
          case A.decode raw of
            Nothing -> pure $ PatchApplyError "cannot parse source file as JSON"
            Just astVal -> do
              -- 4. Apply ops
              case applyOps (prPatch pr) astVal of
                Left err -> pure $ PatchApplyError err
                Right patchedVal -> do
                  -- Build patch op info for diagnostic rebasing
                  let opInfos = toPatchOpInfos (prPatch pr)
                  -- 5. Re-parse patched JSON → statements
                  case parseJSONASTValue patchedVal of
                    Left diags -> pure $ PatchTypeError DiagnosticReport
                      { reportPhase       = "patch"
                      , reportSuccess     = False
                      , reportDiagnostics = map (rebaseToPatch opInfos) diags
                      }
                    Right stmts -> do
                      -- 6. Re-typecheck
                      let report = typeCheck emptyEnv stmts
                      if reportSuccess report
                        then do
                          -- 7. Write patched JSON and clear lock entry
                          BL.writeFile fp (A.encode patchedVal)
                          let remaining = filter (\t -> ctToken t /= prToken pr) (lockTokens cleanLock)
                              newLock = cleanLock { lockTokens = remaining }
                          saveLock fp newLock
                          pure $ PatchSuccess (length stmts)
                        else do
                          -- Type errors: rebase pointers, don't write, preserve lock for retry
                          let rebased = report { reportDiagnostics = map (rebaseToPatch opInfos) (reportDiagnostics report) }
                          pure $ PatchTypeError rebased

-- ---------------------------------------------------------------------------
-- Patch Op Info Construction
-- ---------------------------------------------------------------------------

-- | Build PatchOpInfo list from patch ops.
-- Only mutation ops (replace/add/remove) get entries; test ops are excluded
-- because they cannot introduce type errors.
toPatchOpInfos :: [PatchOp] -> [PatchOpInfo]
toPatchOpInfos ops = concatMap toInfo (zip [0..] ops)
  where
    toInfo (i, PatchReplace p _) = [PatchOpInfo i p "replace"]
    toInfo (i, PatchAdd p _)     = [PatchOpInfo i p "add"]
    toInfo (i, PatchRemove p)    = [PatchOpInfo i p "remove"]
    toInfo (_, PatchTest _ _)    = []  -- test ops can't introduce errors
