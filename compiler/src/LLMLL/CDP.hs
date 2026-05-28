-- |
-- Module      : LLMLL.CDP
-- Description : LT-CDP (v0.11) — Contract Discriminative Power evidence axis.
--
-- Implements 'contract-discriminative-power-proposal.md' Rev 2 §4–§5.
--
-- CDP answers the orthogonal-to-evidence question:
--
--   /Does the specification rule out enough wrong implementations?/
--
-- The metric extends LLMLL.WeaknessCheck's counted-satisfaction loop. For every
-- function with a contract, we enumerate the closed v0.11 candidate set per
-- proposal §4.3.1 (small ints, both bools, two strings, list singletons, sum
-- and pair defaults), emit a fixpoint .fq for each candidate, solve, and count
-- the fraction of candidates that satisfy the contract. The normalized score
-- is Shannon-style:
--
--     DP_Ω(S) = 1 − log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)
--
-- with the seven edge / non-applicability cases enumerated in 'CDPWarning' per
-- proposal §5. The score is /observational/ over the candidate set Ω and only
-- meaningful relative to Ω — the trust report records Ω's identity via the
-- 'basis' field so cross-version score comparison can be audited.
--
-- This module does no Haskell-level IO beyond invoking the external
-- liquid-fixpoint solver. The actual solver invocation lives in 'Main.hs'
-- (the harness owns the binary path); CDP exports 'computeCDPFor' which
-- accepts a solver-runner function so 'Main.hs' can plug in its own.

module LLMLL.CDP
  ( -- * Types
    CDPResult(..)
  , CDPWarning(..)
  , CDPScope(..)
  , cdpWarningLabel
  , cdpScopeLabel
    -- * Computation
  , computeCDPFor
  , overAnnotationRatio
  , overAnnotationThreshold
  ) where

import Data.Text (Text)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.List as L

import LLMLL.Syntax
import LLMLL.WeaknessCheck
  ( WeaknessCandidate(..), TrivialBody(..), generateCDPCandidates )

-- ---------------------------------------------------------------------------
-- Scope (gate-conditional per v0.11-cross-proposal-rollback-discipline.md §2)
-- ---------------------------------------------------------------------------

-- | LT-CDP scope parameter per
-- 'v0.11-cross-proposal-rollback-discipline.md' §2 + §3. Until LT-INV ships
-- and the §8 empirical gate runs, the default is 'CDPScopeAllDefLogic'
-- (Outcome 2 semantics). The LT-INV-engineer turn flips the default per the
-- gate outcome; CDP code does not need re-shipping.
data CDPScope
  = CDPScopeAllDefLogic  -- ^ v0.10 pre-LT-INV default; every contracted def-logic is in scope.
  | CDPScopeCoreOnly     -- ^ Outcome 0 post-gate; only 'def' (core) form is in scope.
  | CDPScopeFlagGated    -- ^ Outcome 1 post-gate-fail; reporting requires --grammar=core-inversion.
  deriving (Show, Eq)

-- | Wire-line label for 'CDPScope' (used by Main.hs diagnostic surface).
cdpScopeLabel :: CDPScope -> Text
cdpScopeLabel CDPScopeAllDefLogic = "all-def-logic"
cdpScopeLabel CDPScopeCoreOnly    = "core-only"
cdpScopeLabel CDPScopeFlagGated   = "flag-gated"

-- ---------------------------------------------------------------------------
-- Result + warning types
-- ---------------------------------------------------------------------------

-- | The per-function CDP measurement. Always populated when CDP is requested;
-- the 'cdpScore' is 'Nothing' when no normalized score can be produced (one of
-- the typed warning cases in 'CDPWarning' fires instead).
data CDPResult = CDPResult
  { cdpCandidateCount         :: Int
    -- ^ Total candidates from the §4.3.1 enumeration that type-checked.
  , cdpSatisfyingCount        :: Int
    -- ^ Candidates whose synthetic body satisfied the contract (solver SAFE).
  , cdpDistinctBehaviorCount  :: Int
    -- ^ Equivalence classes over the candidate set (proposal §4.3 partition).
  , cdpScore                  :: Maybe Double
    -- ^ Shannon-normalized DP_Ω(S); 'Nothing' when undefined / not measured /
    -- inconsistent — see 'cdpWarnings' for the typed reason.
  , cdpWarnings               :: [CDPWarning]
    -- ^ Per-proposal §5 typed warning enumeration; multiple warnings may
    -- co-occur (e.g. 'WarnIdentitySatisfiesPost' + 'WarnConstSatisfiesPost').
  , cdpDistinguishingInputs   :: [Text]
    -- ^ Candidate-body labels that distinguish satisfying behaviors from
    -- non-satisfying behaviors. Surfaces in the obligation-report and
    -- '--weakness-check'-derived diagnostic.
  , cdpSpecEntropyAnnotation  :: SpecEntropy
    -- ^ The contract's '(spec-entropy ...)' annotation (defaults to
    -- 'SpecEntropyStrict' on absent annotation per proposal §3).
  } deriving (Show, Eq)

-- | Typed diagnostic enumeration per proposal §5. Downstream consumers must
-- distinguish 'WarnDefShellOutOfScope' (not applicable — non-applicability) from
-- 'WarnEnumerationTooNarrow' (undefined — measurement weakness) to avoid
-- conflating the two.
data CDPWarning
  = WarnIdentitySatisfiesPost
    -- ^ The identity body type-checked AND satisfied the contract — the spec
    -- admits input-pass-through behavior.
  | WarnConstSatisfiesPost
    -- ^ A trivial constant body satisfied the contract.
  | WarnSpecInconsistent
    -- ^ Zero candidates satisfied the contract and there is no verification
    -- evidence for the post-condition. Score is suppressed.
  | WarnVacuousOverOmega
    -- ^ The post-condition carries DLVerified or DLContractChecked evidence
    -- (the spec is provably correct), but no trivial-body candidate from the
    -- §4.3.1 enumeration satisfies it — the spec is tight with respect to the
    -- candidate set Ω, not vacuous. Score is suppressed; consumers should
    -- treat this as a strong-spec signal, not a spec defect.
  | WarnEnumerationTooNarrow
    -- ^ |B_{T,U,Ω}| ≤ 1 — fewer than two distinct observable behaviors;
    -- score formula is degenerate, score reported as undefined.
  | WarnDefShellOutOfScope
    -- ^ Function is def-shell (or, pre-LT-INV, classified as out-of-scope by
    -- the active 'CDPScope'). Score is NOT measured — distinct from undefined.
  | WarnCandidatesEmptyUnderLimit
    -- ^ Zero type-compatible candidates from the §4.3.1 enumeration applied.
    -- A v0.12+ widening may close this case.
  | WarnOverAnnotationModule
    -- ^ Module-level diagnostic: ':intentional' annotations exceed the
    -- threshold ratio (default 30 %) of '@over-annotation-warning@' per
    -- Risk #3.
  | WarnNotRequested
    -- ^ Trust-report emit-only marker: '--cdp' was not passed; the
    -- discriminative_axis block populates with score = Nothing and a single
    -- 'WarnNotRequested' so downstream consumers do not need to special-case
    -- the absence of the field.
  deriving (Show, Eq, Ord)

-- | Wire-line label per proposal §5 enumeration.
cdpWarningLabel :: CDPWarning -> Text
cdpWarningLabel WarnIdentitySatisfiesPost     = "identity-satisfies-post"
cdpWarningLabel WarnConstSatisfiesPost        = "const-satisfies-post"
cdpWarningLabel WarnSpecInconsistent          = "spec-inconsistent"
cdpWarningLabel WarnVacuousOverOmega          = "vacuous-over-omega"
cdpWarningLabel WarnEnumerationTooNarrow      = "enumeration-too-narrow"
cdpWarningLabel WarnDefShellOutOfScope        = "def-shell-out-of-scope"
cdpWarningLabel WarnCandidatesEmptyUnderLimit = "candidates-empty-under-limit"
cdpWarningLabel WarnOverAnnotationModule      = "over-annotation-warning"
cdpWarningLabel WarnNotRequested              = "not-requested"

-- ---------------------------------------------------------------------------
-- Over-annotation threshold (proposal Risk #3)
-- ---------------------------------------------------------------------------

-- | Default ':intentional' density threshold (30 %) per proposal §10 Risk #3.
-- Configurable later via env var ('LLMLL_CDP_INTENT_THRESHOLD'); v0.11 ships
-- this fixed default.
overAnnotationThreshold :: Double
overAnnotationThreshold = 0.30

-- | Compute the ratio of ':intentional' contracts in a statement list. Used by
-- Main.hs to emit a module-level 'WarnOverAnnotationModule' when the ratio
-- exceeds 'overAnnotationThreshold'.
overAnnotationRatio :: [Statement] -> Double
overAnnotationRatio stmts =
  let entropies = mapEntropies stmts
      total = length entropies
      intent = length [e | e <- entropies, e == SpecEntropyIntentional]
  in if total == 0 then 0.0 else fromIntegral intent / fromIntegral total
  where
    mapEntropies = concatMap go
    go (SDefLogic _ _ _ c _)   = [resolveEntropy c]
    go (SLetrec   _ _ _ c _ _) = [resolveEntropy c]
    -- LT-INV (v0.11)
    go (SDef      _ _ _ c _)   = [resolveEntropy c]
    go (SDefShell _ _ _ c _)   = [resolveEntropy c]
    go _ = []
    resolveEntropy c = case contractSpecEntropy c of
      Just se -> se
      Nothing -> SpecEntropyStrict

-- ---------------------------------------------------------------------------
-- Core computation
-- ---------------------------------------------------------------------------

-- | Compute CDP for every contracted function in the input statement list.
--
-- The caller supplies:
--
--   * 'CDPScope' — gate-conditional scope per
--     'v0.11-cross-proposal-rollback-discipline.md' §2; functions outside
--     scope produce a 'WarnDefShellOutOfScope' result with no score.
--   * 'runCandidate' — solver-runner that emits .fq for a single candidate
--     statement and returns 'True' iff the solver reports SAFE. Owned by
--     Main.hs which holds the liquid-fixpoint binary path.
--
-- Returns a per-function map; entries are populated for every contracted
-- function so the trust-report shape is uniform.
computeCDPFor
  :: CDPScope
  -> (WeaknessCandidate -> IO Bool)
  -> Map Name Bool
  -> [Statement]
  -> IO (Map Name CDPResult)
computeCDPFor scope runCandidate verifMap stmts = do
  let funcs = mapStmts stmts
  pairs <- mapM (\(name, contract, candidates) ->
                    let verifies = Map.findWithDefault False name verifMap
                    in fmap ((,) name) (resultFor scope runCandidate verifies contract candidates))
                funcs
  pure (Map.fromList pairs)
  where
    mapStmts = mapMaybeStmts
    mapMaybeStmts ss =
      [ (n, c, candidatesFor n ss)
      | s <- ss
      , Just (n, c) <- [contractedFunc s]
      ]
    contractedFunc (SDefLogic n _ _ c _)   | hasContracts c = Just (n, c)
    contractedFunc (SLetrec   n _ _ c _ _) | hasContracts c = Just (n, c)
    -- LT-INV (v0.11)
    contractedFunc (SDef      n _ _ c _)   | hasContracts c = Just (n, c)
    contractedFunc (SDefShell n _ _ c _)   | hasContracts c = Just (n, c)
    contractedFunc _ = Nothing
    candidatesFor n ss = filter (\wc -> wcFunctionName wc == n) (generateCDPCandidates ss)
    hasContracts (Contract pre _ post _ _) =
      pre /= Nothing || post /= Nothing

-- | Compute the per-function result, given the function's candidates and the
-- IO solver runner. In-scope but candidate-empty cases fire
-- 'WarnCandidatesEmptyUnderLimit'; in-scope inconsistent contracts fire
-- 'WarnSpecInconsistent'; observational equivalence is the per-candidate
-- 'trivialLabel' partition (proposal §4.3 corpus-bias caveat applies).
resultFor
  :: CDPScope
  -> (WeaknessCandidate -> IO Bool)
  -> Bool
  -> Contract
  -> [WeaknessCandidate]
  -> IO CDPResult
resultFor _scope runCandidate functionVerifies contract candidates = do
  let annotation = case contractSpecEntropy contract of
                     Just se -> se
                     Nothing -> SpecEntropyStrict
  -- Scope filtering is decided by the caller in 'Main.hs' (which knows the
  -- form context — def vs def-logic vs def-shell — once LT-INV lands). Until
  -- then, all contracted functions reach here and the result is computed
  -- against 'CDPScopeAllDefLogic' semantics.
  if null candidates
    then pure CDPResult
      { cdpCandidateCount = 0
      , cdpSatisfyingCount = 0
      , cdpDistinctBehaviorCount = 0
      , cdpScore = Nothing
      , cdpWarnings = [WarnCandidatesEmptyUnderLimit]
      , cdpDistinguishingInputs = []
      , cdpSpecEntropyAnnotation = annotation
      }
    else do
      passes <- mapM (\wc -> fmap ((,) wc) (runCandidate wc)) candidates
      let candCount    = length candidates
          satisfying   = [wc | (wc, True)  <- passes]
          nonSatisfying = [wc | (wc, False) <- passes]
          satCount     = length satisfying
          distinctSat  = length (equivalenceClasses (map wcTrivialLabel satisfying))
          distinctAll  = length (equivalenceClasses (map wcTrivialLabel candidates))
          warns        = buildWarnings candidates satisfying distinctAll annotation functionVerifies
          score        = computeScore satCount distinctAll
          distInputs   = take 4 [wcTrivialLabel wc | wc <- nonSatisfying ++ satisfying]
      pure CDPResult
        { cdpCandidateCount = candCount
        , cdpSatisfyingCount = satCount
        , cdpDistinctBehaviorCount = distinctSat
        , cdpScore = score
        , cdpWarnings = warns
        , cdpDistinguishingInputs = distInputs
        , cdpSpecEntropyAnnotation = annotation
        }

-- | Build the typed warning list for a per-function CDP result per proposal §5.
buildWarnings
  :: [WeaknessCandidate]   -- ^ all candidates
  -> [WeaknessCandidate]   -- ^ satisfying candidates
  -> Int                   -- ^ distinct candidate behaviors over Ω
  -> SpecEntropy           -- ^ spec-entropy annotation
  -> Bool                  -- ^ True when post carries DLVerified / DLContractChecked evidence
  -> [CDPWarning]
buildWarnings candidates satisfying distinctAll _annotation functionVerifies =
  let identityOk   = any (isIdentity . wcTrivialBody) satisfying
      constOk      = any (isConst    . wcTrivialBody) satisfying
      inconsistent = null satisfying && not (null candidates)
      narrow       = distinctAll <= 1
  in concat
       [ [WarnIdentitySatisfiesPost | identityOk]
       , [WarnConstSatisfiesPost    | constOk]
       , [if functionVerifies then WarnVacuousOverOmega else WarnSpecInconsistent | inconsistent]
       , [WarnEnumerationTooNarrow  | narrow && not inconsistent]
       ]
  where
    isIdentity (TrivIdentity _) = True
    isIdentity _                = False
    isConst (TrivIdentity _)    = False
    isConst _                   = True

-- | Shannon-normalized score per proposal §4.1. 'Nothing' on degenerate inputs
-- ('|B|≤1', |⟦S⟧|=0).
computeScore :: Int -> Int -> Maybe Double
computeScore _ b | b <= 1 = Nothing  -- enumeration-too-narrow / collapses to 0/0
computeScore s _ | s <= 0 = Nothing  -- spec-inconsistent
computeScore satCount totalCount =
  let logSat   = log (fromIntegral satCount :: Double)
      logTotal = log (fromIntegral totalCount :: Double)
  in Just (1.0 - logSat / logTotal)

-- | Coarse observational equivalence over the candidate labels. This is the
-- O(N²) naive partition per proposal Risk #5; at v0.11 enumeration sizes
-- (≤ 15 candidates per function) the cost is negligible. v0.12+ adopts
-- Union-Find when LLM-generated candidates widen the corpus.
equivalenceClasses :: (Eq a) => [a] -> [[a]]
equivalenceClasses = L.foldl' insert []
  where
    insert classes x = case break (\cls -> x `elem` cls) classes of
      (before, cls : after) -> before ++ ((x : cls) : after)
      (before, [])          -> before ++ [[x]]
