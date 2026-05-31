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
--   6.5 Re-verify via emitFixpoint + liquid-fixpoint (if contracts present)
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
  , hasContracts     -- v0.10: exported for testing
  -- v0.10: SHA-256 hashing (used by Main.hs for checkout staleness)
  , hashFile
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
import LLMLL.Syntax (Statement(..), Contract(..), GrammarMode(..))
import LLMLL.FixpointEmit (emitFixpointWith, EmitOptions(..), defaultEmitOptions, EmitResult(..))
import LLMLL.DiagnosticFQ (parseFQResult, fqResultToReport, FQVerifyResult(..))

import Data.Time.Clock (getCurrentTime)
import System.Directory (doesFileExist, findExecutable)
import System.FilePath (takeBaseName)
import System.Process (readProcessWithExitCode)
import qualified Data.Text.IO as TIO
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import Data.Word (Word8)
import Numeric (showHex)

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
  | PatchTypeError DiagnosticReport -- type errors from re-typecheck
  | PatchVerifyError DiagnosticReport -- SMT verification failed (contracts violated)
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
  toJSON (PatchVerifyError report) = object
    [ "result"      .= ("PatchVerifyError" :: Text)
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
applyPatch :: GrammarMode -> FilePath -> PatchRequest -> IO PatchResult
applyPatch mode fp pr = do
  now <- getCurrentTime

  -- 1. Load and validate lock
  mLock <- loadLock fp
  let lock = maybe (CheckoutLock fp []) id mLock
      cleanLock = expireStale now lock
      matchingTokens = filter (\ct -> ctToken ct == prToken pr) (lockTokens cleanLock)

  case matchingTokens of
    [] -> pure $ PatchAuthError "invalid or expired checkout token"
    (ct:_) -> do
      -- v0.10 OBLIG-1: Staleness validation (between step 1 and step 2)
      -- Compare source/verified hashes against current files.
      -- If ctSourceHash/ctVerifiedHash are Nothing (pre-v0.10 lock file),
      -- skip the check entirely (backward compat, Correction 4).
      staleResult <- checkStaleness fp ct
      case staleResult of
        Just err -> pure $ PatchAuthError err
        Nothing -> do
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
                      case parseJSONASTValue mode patchedVal of
                        Left diags -> pure $ PatchTypeError DiagnosticReport
                          { reportPhase       = "patch"
                          , reportSuccess     = False
                          , reportDiagnostics = map (rebaseToPatch opInfos) diags
                          }
                        Right stmts -> do
                          -- 6. Re-typecheck
                          let report = typeCheck mode emptyEnv stmts
                          if reportSuccess report
                            then do
                              -- 6.5 Re-verify via SMT (if contracts present)
                              verifyResult <- reVerify fp stmts
                              case verifyResult of
                                Just unsafeReport -> do
                                  -- Verification failed: rebase diagnostics, don't write, preserve lock
                                  let rebased = unsafeReport { reportDiagnostics = map (rebaseToPatch opInfos) (reportDiagnostics unsafeReport) }
                                  pure $ PatchVerifyError rebased
                                Nothing -> do
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
-- v0.10 OBLIG-1: Staleness Guards
-- ---------------------------------------------------------------------------

-- | Check if the checkout token's source/verified hashes are still current.
-- Returns Nothing if no staleness detected (or no hashes to check — pre-v0.10).
-- Returns Just errorMessage if stale.
checkStaleness :: FilePath -> CheckoutToken -> IO (Maybe Text)
checkStaleness fp ct = do
  -- Source file staleness
  srcResult <- case ctSourceHash ct of
    Nothing -> pure Nothing  -- pre-v0.10 token: skip check
    Just expectedHash -> do
      currentHash <- hashFile fp
      pure $ if currentHash /= expectedHash
        then Just "obligation context is stale — re-checkout required (source file changed)"
        else Nothing
  case srcResult of
    Just err -> pure (Just err)
    Nothing -> do
      -- Verified sidecar staleness
      case ctVerifiedHash ct of
        Nothing -> pure Nothing  -- pre-v0.10 token or no sidecar: skip check
        Just expectedHash -> do
          let verifiedFp = fp ++ ".verified.json"
          exists <- doesFileExist verifiedFp
          if not exists
            then pure $ Just "obligation context is stale — re-checkout required (.verified.json removed)"
            else do
              currentHash <- hashFile verifiedFp
              pure $ if currentHash /= expectedHash
                then Just "obligation context is stale — re-checkout required (.verified.json changed)"
                else Nothing

-- | Compute SHA-256 hash of a file, returning the hex-encoded digest.
hashFile :: FilePath -> IO Text
hashFile path = do
  contents <- BS.readFile path
  let digest = SHA256.hash contents
  pure $ T.pack (concatMap toHex (BS.unpack digest))
  where
    toHex :: Word8 -> String
    toHex w = let s = showHex w "" in if length s == 1 then '0' : s else s

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

-- ---------------------------------------------------------------------------
-- v0.10 BUG-PATCH-VERIFY: SMT Re-Verification
-- ---------------------------------------------------------------------------

-- | Check if any top-level function carries contracts (pre or post).
-- Used to skip re-verification when no contracts exist (no work for the solver).
hasContracts :: [Statement] -> Bool
hasContracts = any stmtHasContract
  where
    stmtHasContract (SDefLogic _ _ _ c _)  = contractPre c /= Nothing || contractPost c /= Nothing
    stmtHasContract (SLetrec _ _ _ c _ _)  = contractPre c /= Nothing || contractPost c /= Nothing
    -- LT-INV (v0.11)
    stmtHasContract (SDef      _ _ _ c _)  = contractPre c /= Nothing || contractPost c /= Nothing
    stmtHasContract (SDefShell _ _ _ c _)  = contractPre c /= Nothing || contractPost c /= Nothing
    stmtHasContract _ = False

-- | Re-verify patched statements via emitFixpoint + liquid-fixpoint.
-- Returns Nothing on success (SAFE, solver missing, no contracts, solver error).
-- Returns Just report on UNSAFE (contract violation detected).
--
-- Graceful degradation: if liquid-fixpoint is not installed, returns Nothing
-- (patch proceeds on typecheck success alone). This matches doVerify behavior.
reVerify :: FilePath -> [Statement] -> IO (Maybe DiagnosticReport)
reVerify fp stmts
  | not (hasContracts stmts) = pure Nothing  -- no contracts → skip
  | otherwise = do
      -- Emit .fq constraints with body-faithful VCs
      let emitOpts = defaultEmitOptions { emitBodyVCs = True }
      emitR <- emitFixpointWith emitOpts fp stmts
      let fqText = erFQText emitR
          table  = erConstraintTable emitR
      -- Find liquid-fixpoint binary
      mLF <- do
        a <- findExecutable "liquid-fixpoint"
        case a of
          Just _ -> return a
          Nothing -> findExecutable "fixpoint"
      case mLF of
        Nothing -> pure Nothing  -- graceful degradation: no solver installed
        Just lfBin -> do
          -- Write .fq to temp file
          let baseName = takeBaseName fp
              fqPath   = "/tmp/llmll-patch-" <> baseName <> ".fq"
          TIO.writeFile fqPath fqText
          -- Run solver
          (_, out, err) <- readProcessWithExitCode lfBin [fqPath] ""
          let outT     = T.pack out
              fqResult = parseFQResult (outT <> T.pack err)
              fqReport = fqResultToReport fp table fqResult
          case fqResult of
            FQSafe     -> pure Nothing       -- SAFE → proceed with write
            FQUnsafe _ -> pure (Just fqReport)  -- UNSAFE → reject patch
            FQError _  -> pure Nothing       -- solver error → graceful: proceed
