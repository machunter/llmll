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
  , isQfLia             -- spec §12: shared QF-LIA check
  , CandidateExpr(..)   -- OBLIG-4: repair suggestions
  , generateCandidates
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)
import qualified Data.List
import Data.Aeson (object, (.=))
import Data.Aeson.Text (encodeToLazyText)
import qualified Data.Text.Lazy as TL

import LLMLL.Syntax (Name, Contract(..), Expr(..), Literal(..), Statement(..), DisplayLevel(..), Type, normalizeDefStmt)
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable, FQVerifyResult(..))
import LLMLL.TrustReport (TrustReport(..), TrustEntry(..), TrustDependency(..))
-- LEVER-A3: classification derives from the emitter's own predicates (§6.1).
import LLMLL.FixpointEmit (buildAliasMap, contractArrGuardsBlock, contractMentionsArrOp, exprMentionsArrOp)

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
  case findDefSig fnName stmts of
    Nothing -> Advisory  -- No contract found, can't determine
    Just (params, mRet, contract, mBody) ->
      let targetExpr = case clause of
            "pre"  -> contractPre contract
            "post" -> contractPost contract
            _      -> Nothing
          -- LEVER-A3: the emitter's own type-level array guards re-demote what
          -- the structural check admits (whole-array `=`, inadmissible map
          -- classes), applied under the same contract-or-body relevance as the
          -- activation gate — classification cannot claim Verified where the
          -- contract channel would fall back (§6.1).
          arrRelevant = contractMentionsArrOp contract
                        || maybe False exprMentionsArrOp mBody
          arrBlocked  = arrRelevant
                        && contractArrGuardsBlock (buildAliasMap stmts) params mRet contract
      in case targetExpr of
           Nothing -> Advisory
           Just expr -> if isQfLia expr && not arrBlocked then Verified else Advisory

-- | A function's params, return type, contract, and body (signature for the
-- typed classifier guards). First match wins, like 'findContract'.
findDefSig :: Name -> [Statement] -> Maybe ([(Name, Type)], Maybe Type, Contract, Maybe Expr)
findDefSig name stmts =
  case [ (ps, mRet, c, Just b) | stmt <- stmts
                               , Just (n, ps, mRet, c, b) <- [normalizeDefStmt stmt]
                               , n == name ] of
    (x:_) -> Just x
    []    -> case findContract name stmts of   -- SLetrec/SDefInvariant fallback
               Just c  -> Just ([], Nothing, c, Nothing)
               Nothing -> Nothing

-- | Check if an expression is in the QF-LIA fragment (linear integer arithmetic).
-- This is a simplified check matching what FixpointEmit.exprToPred accepts.
isQfLia :: Expr -> Bool
isQfLia expr = case expr of
  -- Literals
  ELit _      -> True
  EVar _      -> True
  -- CLASSIFY-EOP: both parsers emit an operator node as 'EOp' (S-expr
  -- 'Parser.hs:897', JSON 'ParserJSON.hs:558'), but every operator case below
  -- matches 'EApp'. Without this, a normal operator-bearing contract predicate
  -- (e.g. '(>= x 0)') falls through to the 'not in fragment' default and
  -- mis-classifies as non-QF-LIA — even though it verifies fine (FixpointEmit
  -- normalizes EOp→EApp at ':1916'). Treat 'EOp' as the equivalent 'EApp'.
  EOp op args -> isQfLia (EApp op args)
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
  -- IMPL-SUGAR: implication / biconditional of QF-LIA atoms stays QF-LIA
  EApp "=>"  args -> all isQfLia args
  EApp "<=>" args -> all isQfLia args
  -- LEVER-A3: the array-op family is in the auto-discharge fragment (the
  -- Σ_auto array class, LLMLL.md §5.3.3) — these cases mirror exprToPred's
  -- A1/A2 contract-channel cases EXACTLY (same ops, same map-root shapes; a
  -- bare map-put/map-empty outside a map-has/map-get root has no case there,
  -- so none here). Structural only: the type-level guards (whole-array `=`,
  -- inadmissible map value classes, non-int put values) are the emitter's own
  -- 'contractArrGuardsBlock', applied at the CONTRACT level by
  -- 'classifyContractFragmentTyped' — mirroring how the emitter itself splits
  -- exprToPred (syntactic) from wholeArrEqClause/mapClauseBlocked (typed).
  EApp "bytes-length" [b]       -> isQfLia b
  EApp "bytes-get"    [b, i]    -> isQfLia b && isQfLia i
  EApp "bytes-set"    [b, i, v] -> isQfLia b && isQfLia i && isQfLia v
  EApp "map-has"      [m, k]    -> mapRootQf m && isQfLia k
  EApp "map-get"      [m, k]    -> mapRootQf m && isQfLia k
  -- Anything else: not in fragment
  _ -> False
  where
    -- The mapPairTermsC root shapes (FixpointEmit): a variable, a map-put
    -- chain over such a root, or map-empty. Anything else falls back there,
    -- so it classifies out here.
    mapRootQf (EVar _)                   = True
    mapRootQf (EApp "map-put" [m, k, v]) = mapRootQf m && isQfLia k && isQfLia v
    mapRootQf (EApp "map-empty" [])      = True
    mapRootQf (EOp f as)                 = mapRootQf (EApp f as)
    mapRootQf _                          = False

-- | Find a function's contract by name in the statement list.
findContract :: Name -> [Statement] -> Maybe Contract
findContract name stmts =
  let matches = [ c | SDefLogic n _ _ c _   <- stmts, n == name ]
             ++ [ c | SLetrec   n _ _ c _ _ <- stmts, n == name ]
             -- LT-INV (v0.11)
             ++ [ c | SDef      n _ _ c _   <- stmts, n == name ]
             ++ [ c | SDefShell n _ _ c _ _   <- stmts, n == name ]
             -- v0.12.1
             ++ [ c | SDefInvariant n _ _ c _ <- stmts, n == name ]
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
--
-- BUG-5 (v0.14.3): use 'encodeToLazyText' rather than
-- 'T.pack . BLC.unpack . encode' -- the latter reinterprets each UTF-8 byte
-- of aeson's 'encode' output as a Latin-1 codepoint via
-- 'Data.ByteString.Lazy.Char8.unpack', double-encoding any non-ASCII content
-- on re-serialization (see LLMLL.TrustReport.formatTrustReportJson).
formatObligationsJson :: [ObligationSuggestion] -> Text
formatObligationsJson sugs =
  TL.toStrict . encodeToLazyText $ object
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

-- ---------------------------------------------------------------------------
-- OBLIG-4: Candidate Expression Search
-- ---------------------------------------------------------------------------

-- | Maximum number of candidate expressions to generate.
maxCandidateSearchDepth :: Int
maxCandidateSearchDepth = 8

-- | A candidate expression for hole filling.
data CandidateExpr = CandidateExpr
  { ceExpr     :: Text    -- ^ S-expression, e.g. "(- balance amount)"
  , ceVerified :: Bool    -- ^ Always False for v0.10 (F7)
  , ceKind     :: Text    -- ^ Always "candidate-expression"
  } deriving (Show, Eq)

-- | Generate candidate expressions from pre-filtered int param names.
-- O(n²) bounded arithmetic search: for each pair emit
-- (- a b), (- b a), (+ a b). For single param: (+ n n).
-- Capped at maxCandidateSearchDepth.
-- Caller must pre-filter params via isIntLike (F1: avoids type alias bugs).
generateCandidates :: [Name] -> [CandidateExpr]
generateCandidates intNames =
  let uniquePairs = dedupPairs [(a, b) | a <- intNames, b <- intNames, a /= b]
      singles = [mk ("(+ " <> n <> " " <> n <> ")") | n <- intNames]
      pairCands = concatMap (\(a, b) ->
        [ mk ("(- " <> a <> " " <> b <> ")")
        , mk ("(- " <> b <> " " <> a <> ")")
        , mk ("(+ " <> a <> " " <> b <> ")")
        ]) uniquePairs
      allCands = dedupCands (pairCands ++ singles)
  in take maxCandidateSearchDepth allCands
  where
    mk expr = CandidateExpr expr False "candidate-expression"
    dedupPairs ps = Data.List.nub [(min a b, max a b) | (a, b) <- ps]
    dedupCands [] = []
    dedupCands (x:xs) = x : dedupCands (filter (\y -> ceExpr y /= ceExpr x) xs)

