-- |
-- Module      : LLMLL.ObligationMining
-- Description : v0.4: Downstream obligation mining.
--
-- When @llmll verify@ reports UNSAFE at a cross-function boundary,
-- this module extracts the unsatisfied constraint and suggests
-- postcondition strengthening on the callee.
--
-- Example output:
-- @
--   ✗ Caller requires: uniqueIds(result)
--     Producer normalizeUsers does not guarantee this.
--     Candidate strengthening: postcondition uniqueIds(output)
-- @
--
-- Leverages 'TrustReport.hs' transitive closure infrastructure
-- and 'DiagnosticFQ.hs' constraint origin tables.

module LLMLL.ObligationMining
  ( ObligationSuggestion(..)
  , SuggestionStrength(..)
  , mineObligations
  , formatObligations
  , formatObligationsJson
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)
import Data.Aeson (encode, object, (.=), Value(..))
import qualified Data.ByteString.Lazy.Char8 as BLC

import LLMLL.Syntax (Name, Contract(..), Expr(..), Literal(..), Statement(..), VerificationLevel(..))
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable, FQVerifyResult(..))
import LLMLL.TrustReport (TrustReport(..), TrustEntry(..), TrustDependency(..))

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Whether the suggestion is mechanically verified or heuristic.
data SuggestionStrength
  = Verified   -- ^ The constraint is in QF-LIA; adding this postcondition
               -- will resolve the UNSAFE result.
  | Advisory   -- ^ The constraint is outside QF-LIA; the suggestion is
               -- heuristic and may not fully resolve the UNSAFE.
  deriving (Show, Eq)

-- | A suggestion to add or strengthen a postcondition on a callee function.
data ObligationSuggestion = ObligationSuggestion
  { osCaller       :: Name              -- ^ Function whose contract failed
  , osCallee       :: Name              -- ^ Function that needs strengthening
  , osClause       :: Text              -- ^ "pre" | "post" | "decreases"
  , osConstraintId :: Int               -- ^ The constraint ID that failed
  , osSuggestion   :: Text              -- ^ Human-readable suggestion text
  , osJsonPointer  :: Maybe Text        -- ^ JSON Pointer to the failed constraint site
  , osStrength     :: SuggestionStrength -- ^ v0.4 amendment: Verified or Advisory
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Mining
-- ---------------------------------------------------------------------------

-- | Mine downstream obligations from a failed verification result.
--
-- For each UNSAFE constraint, cross-reference:
--   1. 'ConstraintOrigin' → which function's clause failed (the caller)
--   2. 'TrustReport' → which callees the caller depends on
--
-- If the failed clause is a postcondition, the callee likely needs
-- a stronger postcondition. If it's a precondition, the caller's
-- environment doesn't provide the needed guarantee.
mineObligations
  :: ConstraintTable
  -> FQVerifyResult
  -> TrustReport
  -> [Statement]       -- ^ Top-level statements (for contract expression lookup)
  -> [ObligationSuggestion]
mineObligations _table FQSafe _report _stmts = []
mineObligations _table (FQError _) _report _stmts = []
mineObligations table (FQUnsafe cids) report stmts =
  concatMap (suggestForConstraint table report stmts) cids

suggestForConstraint
  :: ConstraintTable
  -> TrustReport
  -> [Statement]
  -> Int
  -> [ObligationSuggestion]
suggestForConstraint table report stmts cid =
  case Map.lookup cid table of
    Nothing -> []  -- Unknown constraint: can't suggest anything
    Just origin ->
      let caller    = coFunction origin
          clause    = coClause origin
          pointer   = coJsonPtr origin
          -- Find the caller's entry in the trust report to get its callees
          callerEntry = findEntry caller (trEntries report)
          -- For post-condition failures: suggest strengthening on callees
          suggestions = case clause of
            "post" ->
              case callerEntry of
                Nothing -> [selfSuggestion caller clause cid pointer stmts]
                Just entry ->
                  if null (teDeps entry)
                  then [selfSuggestion caller clause cid pointer stmts]
                  else map (calleeSuggestion caller clause cid pointer stmts) (teDeps entry)
            -- For pre-condition failures: the caller itself needs fixing
            _ -> [selfSuggestion caller clause cid pointer stmts]
      in suggestions

-- | Suggest strengthening on a callee whose postcondition is insufficient.
calleeSuggestion :: Name -> Text -> Int -> Text -> [Statement] -> TrustDependency -> ObligationSuggestion
calleeSuggestion caller clause cid pointer stmts dep =
  let callee = tdName dep
      -- Determine strength by checking if the caller's failed clause is in QF-LIA
      strength = clauseStrength caller clause stmts
  in ObligationSuggestion
    { osCaller       = caller
    , osCallee       = callee
    , osClause       = clause
    , osConstraintId = cid
    , osSuggestion   = "Producer '" <> callee <> "' does not guarantee the " <> clause
                     <> "-condition required by '" <> caller <> "'. "
                     <> "Candidate strengthening: add postcondition on '" <> callee <> "'."
    , osJsonPointer  = Just pointer
    , osStrength     = strength
    }

-- | Suggest that the function itself needs a stronger contract.
selfSuggestion :: Name -> Text -> Int -> Text -> [Statement] -> ObligationSuggestion
selfSuggestion caller clause cid pointer stmts =
  let strength = clauseStrength caller clause stmts
  in ObligationSuggestion
    { osCaller       = caller
    , osCallee       = caller
    , osClause       = clause
    , osConstraintId = cid
    , osSuggestion   = clause <> "-condition of '" <> caller
                     <> "' could not be verified (constraint #" <> T.pack (show cid) <> "). "
                     <> "Consider strengthening the postcondition."
    , osJsonPointer  = Just pointer
    , osStrength     = strength
    }

-- | Check whether a function's clause expression is in the QF-LIA fragment.
-- Reuses the same logic as FixpointEmit: if `exprToPred` would succeed,
-- the constraint is Verified; otherwise Advisory.
clauseStrength :: Name -> Text -> [Statement] -> SuggestionStrength
clauseStrength fnName clause stmts =
  case findContract fnName stmts of
    Nothing -> Advisory  -- No contract found, can't determine
    Just contract ->
      let targetExpr = case clause of
            "pre"  -> contractPre contract
            "post" -> contractPost contract
            _      -> Nothing
      in case targetExpr of
           Nothing -> Advisory
           Just expr -> if isQfLia expr then Verified else Advisory

-- | Check if an expression is in the QF-LIA fragment (linear integer arithmetic).
-- This is a simplified check matching what FixpointEmit.exprToPred accepts.
isQfLia :: Expr -> Bool
isQfLia expr = case expr of
  -- Literals
  ELit _      -> True
  EVar _      -> True
  -- Linear arithmetic + comparisons
  EApp op [l, r]
    | op `elem` [">=", "≥", ">", "<=", "≤", "<", "=", "==", "/=", "≠",
                  "+", "-"]
    -> isQfLia l && isQfLia r
  -- Non-linear: reject
  EApp op [_, _]
    | op `elem` ["*", "/", "mod", "rem", "^", "**"]
    -> False
  -- Boolean connectors
  EApp "and" args -> all isQfLia args
  EApp "or"  args -> all isQfLia args
  EApp "not" [a]  -> isQfLia a
  -- Anything else: not in fragment
  _ -> False

-- | Find a function's contract by name in the statement list.
findContract :: Name -> [Statement] -> Maybe Contract
findContract name stmts =
  let matches = [ c | SDefLogic n _ _ c _ <- stmts, n == name ]
             ++ [ c | SLetrec   n _ _ c _ _ <- stmts, n == name ]
  in case matches of
    (c:_) -> Just c
    []    -> Nothing

-- | Find a trust entry by function name.
findEntry :: Name -> [TrustEntry] -> Maybe TrustEntry
findEntry name entries =
  case filter (\e -> teName e == name) entries of
    (e:_) -> Just e
    []    -> Nothing

-- ---------------------------------------------------------------------------
-- Formatting (human-readable)
-- ---------------------------------------------------------------------------

-- | Format obligation suggestions as human-readable text.
formatObligations :: [ObligationSuggestion] -> Text
formatObligations [] = "No obligation suggestions."
formatObligations sugs = T.unlines $
  ["", "Obligation Suggestions", T.replicate 60 "─"] ++
  concatMap formatOne (zip [1..] sugs) ++
  [T.replicate 60 "─"]

formatOne :: (Int, ObligationSuggestion) -> [Text]
formatOne (i, s) =
  [ "  " <> T.pack (show i) <> ". [" <> strengthLabel (osStrength s) <> "] "
    <> osSuggestion s
  , "     Caller: " <> osCaller s
  , "     Callee: " <> osCallee s
  , "     Clause: " <> osClause s
  ] ++ maybe [] (\p -> ["     At: " <> p]) (osJsonPointer s)
  ++ [""]

strengthLabel :: SuggestionStrength -> Text
strengthLabel Verified = "VERIFIED"
strengthLabel Advisory = "ADVISORY"

-- ---------------------------------------------------------------------------
-- Formatting (JSON)
-- ---------------------------------------------------------------------------

-- | Format obligation suggestions as JSON.
formatObligationsJson :: [ObligationSuggestion] -> Text
formatObligationsJson sugs =
  T.pack . BLC.unpack . encode $ object
    [ "obligation_suggestions" .= map sugJson sugs
    , "count"                  .= length sugs
    ]
  where
    sugJson s = object
      [ "caller"        .= osCaller s
      , "callee"        .= osCallee s
      , "clause"        .= osClause s
      , "constraint_id" .= osConstraintId s
      , "suggestion"    .= osSuggestion s
      , "json_pointer"  .= osJsonPointer s
      , "strength"      .= strengthLabel (osStrength s)
      ]
