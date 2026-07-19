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
    -- * Cascade L3(d): decomposition-trust meet (Rev 8)
  , DecompQuality(..)
  , UnvouchedMeet(..)
  , cdpQuality
  , dqMeet
  , dqLabel
  , dqNumScore
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
  , cdpExcludedCandidateCount :: Int
    -- ^ CDP deep-dive Rev 5 (item 5): count of candidates whose own synthetic
    -- body fell outside the QF-LIA-translatable fragment ('erBodyFallback')
    -- and were therefore excluded from both 'cdpCandidateCount' and
    -- 'cdpSatisfyingCount' — a solver verdict on a body-fallback emission
    -- asserts nothing about whether the candidate satisfies the contract.
    -- Nonzero triggers 'WarnBodyUnfaithfulCandidatesExcluded'.
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
  | WarnSpecInconsistentOrUnproven
    -- ^ CDP deep-dive Rev 5 (item 1): renamed from 'WarnSpecInconsistent'.
    -- Zero Omega candidates satisfied the contract and there is no
    -- independent verification evidence for the post-condition. This is an
    -- EPISTEMIC condition, not a semantic one: F-005 Rev 4 (the archived
    -- contract-discriminative-power-proposal.md §"F-005 scope-policy
    -- adjudication") reserved "spec-inconsistent" for a solver-UNSAT-on-
    -- pre∧post check, independent of Omega — no such check exists here.
    -- This condition is Omega-relative and cannot distinguish a genuinely
    -- vacuous contract from one that is merely tight for the closed §4.3.1
    -- candidate set and unverified by other means. The reserved true
    -- Omega-independent semantic-UNSAT check — a structurally different
    -- existential SAT query, not an extension of the per-candidate
    -- Horn-refutation loop this module runs — is now realized for the refine
    -- feasibility gate by 'LLMLL.Feasibility' (∃input. pre ∧ ∀result. ¬post,
    -- discharged by z3 under the qsat tactic). Score is suppressed.
  | WarnSpecTooTightForOmega
    -- ^ The post-condition carries DLVerified or DLContractChecked evidence
    -- (the spec is provably correct), but no trivial-body candidate from the
    -- §4.3.1 enumeration satisfies it — the spec is tight with respect to the
    -- candidate set Ω, not vacuous. Score is suppressed; consumers should
    -- treat this as a strong-spec signal, not a spec defect.
    -- Wire-line label: "spec-too-tight-for-omega" (renamed from
    -- "vacuous-over-omega" per F-005 adjudication, CDP proposal Rev 4 §5).
  | WarnEnumerationTooNarrow
    -- ^ |B_{T,U,Ω}| ≤ 1 — fewer than two distinct observable behaviors;
    -- score formula is degenerate, score reported as undefined.
  | WarnDefShellOutOfScope
    -- ^ Function is def-shell (or, pre-LT-INV, classified as out-of-scope by
    -- the active 'CDPScope'). Score is NOT measured — distinct from undefined.
  | WarnCandidatesEmptyUnderLimit
    -- ^ Zero type-compatible candidates from the §4.3.1 enumeration applied.
    -- A v0.12+ widening may close this case.
  | WarnBodyUnfaithfulCandidatesExcluded
    -- ^ CDP deep-dive Rev 5 (item 5): one or more type-compatible candidates
    -- were excluded from measurement because their own synthetic body fell
    -- outside the QF-LIA-translatable fragment ('FixpointEmit.erBodyFallback')
    -- — a solver-SAFE verdict on such an emission is not evidence the
    -- candidate satisfies the contract (confirmed mechanism: list-valued
    -- return expressions like '(list-empty)' are not in the translatable
    -- fragment; see 'WeaknessCheck.hs' catalog). Distinct from
    -- 'WarnCandidatesEmptyUnderLimit' (no type-compatible candidates existed
    -- at all) — this fires when candidates existed but could not be reliably
    -- checked. See 'cdpExcludedCandidateCount' for the raw count.
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
cdpWarningLabel WarnSpecInconsistentOrUnproven = "spec-inconsistent-or-unproven"
cdpWarningLabel WarnSpecTooTightForOmega      = "spec-too-tight-for-omega"
cdpWarningLabel WarnEnumerationTooNarrow      = "enumeration-too-narrow"
cdpWarningLabel WarnDefShellOutOfScope        = "def-shell-out-of-scope"
cdpWarningLabel WarnCandidatesEmptyUnderLimit = "candidates-empty-under-limit"
cdpWarningLabel WarnBodyUnfaithfulCandidatesExcluded = "body-unfaithful-candidates-excluded"
cdpWarningLabel WarnOverAnnotationModule      = "over-annotation-warning"
cdpWarningLabel WarnNotRequested              = "not-requested"

-- ---------------------------------------------------------------------------
-- Cascade Refinement L3(d): decomposition-trust meet
-- docs/design/cascading-refinement-proposal.md §194-204 (Rev 8).
-- Report-only (never feeds effectiveLevel / DisplayLevel / admission /
-- --strict-verified-core, §194 normative invariant). No solver, no SMT
-- fragment: a pure fold over the already-computed 'CDPResult' map.
-- ---------------------------------------------------------------------------

-- | The QUALITY axis of a MEASURED CDP verdict (the bilattice truth order,
-- kept separate from the knowledge/coverage axis, professor Rev-6 finding 1).
-- Ordered 'DQHollow' ⊏ 'DQScored s' (by s) ⊏ 'DQStrong': a hollow verdict (a
-- trivial identity/const body already satisfies the invented contract) is the
-- bottom, a tight-and-independently-verified spec ('WarnSpecTooTightForOmega')
-- the top, a real discriminative score orders between.
data DecompQuality = DQHollow | DQScored Double | DQStrong
  deriving (Show, Eq)

-- | Classify a 'CDPResult' onto the quality axis, or 'Nothing' when it sits on
-- the knowledge axis as UNMEASURED — the abstain warnings AND the epistemic
-- 'WarnSpecInconsistentOrUnproven' (which, post the v0.14.52 feasibility gate,
-- cannot be classified hollow-vs-tight from Ω alone; professor Rev-6 finding 3).
-- Unmeasured members are counted in coverage, never folded into the meet.
cdpQuality :: CDPResult -> Maybe DecompQuality
cdpQuality r
  | any isHollowW (cdpWarnings r)                 = Just DQHollow
  | WarnSpecTooTightForOmega `elem` cdpWarnings r = Just DQStrong
  | Just s <- cdpScore r                          = Just (DQScored s)
  | otherwise                                     = Nothing
  where
    isHollowW WarnIdentitySatisfiesPost = True
    isHollowW WarnConstSatisfiesPost    = True
    isHollowW _                         = False

-- | Meet (weakest) on the quality order. Total: 'DQHollow' < 'DQScored s' < 'DQStrong'.
dqMeet :: DecompQuality -> DecompQuality -> DecompQuality
dqMeet a b = if dqLe a b then a else b
  where
    dqLe DQHollow     _            = True
    dqLe _            DQHollow     = False
    dqLe _            DQStrong     = True
    dqLe DQStrong     _            = False
    dqLe (DQScored x) (DQScored y) = x <= y

-- | Wire-line label for the quality point.
dqLabel :: DecompQuality -> Text
dqLabel DQHollow     = "hollow"
dqLabel (DQScored _) = "scored"
dqLabel DQStrong     = "strong"

-- | The numeric score, present only for a graded 'DQScored'.
dqNumScore :: DecompQuality -> Maybe Double
dqNumScore (DQScored s) = Just s
dqNumScore _            = Nothing

-- | The decomposition-trust meet for one function over its UNVOUCHED
-- transitive-callee subtree (Rev 8). Two-axis: 'umQualityMeet' meets the
-- MEASURED members' quality (or 'Nothing' = null when none is measured, kept
-- distinct from 'DQHollow' the way 'effectiveLevel' keeps its 'Nothing'); the
-- knowledge axis is the coverage counts. 'umExcludedFns' name the ':source'-
-- anchored (vouched) subtree members excluded from the meet, so a forged
-- exclusion is self-revealing (professor Rev-8 round 3). 'umFlooredByCycle'
-- flags a contract-only cyclic-SCC member in scope WITHOUT collapsing the
-- quality meet (Rev-8 round-3 finding 3: the boolean carries the termination
-- degradation; the meet still reports the member's real discrimination).
data UnvouchedMeet = UnvouchedMeet
  { umQualityMeet     :: Maybe DecompQuality
  , umWeakestFn       :: Maybe Name
  , umFlooredByCycle  :: Bool
  , umMeasured        :: Int
  , umUnmeasured      :: Int
  , umInScopeTotal    :: Int
  , umExcludedVouched :: Int
  , umExcludedFns     :: [Name]
  } deriving (Show, Eq)

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
    go (SDefLogic _ _ _ c _)   = [resolveSpecEntropy c]
    go (SLetrec   _ _ _ c _ _) = [resolveSpecEntropy c]
    -- LT-INV (v0.11)
    go (SDef      _ _ _ c _)   = [resolveSpecEntropy c]
    go (SDefShell _ _ _ c _ _)   = [resolveSpecEntropy c]
    -- v0.12.1
    go (SDefInvariant _ _ _ c _) = [resolveSpecEntropy c]
    go _ = []

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
--     statement and returns 'Just True'/'Just False' iff the solver reports
--     SAFE/not-SAFE on a body-faithful emission, or 'Nothing' when the
--     candidate's own synthetic body fell outside the QF-LIA-translatable
--     fragment ('FixpointEmit.erBodyFallback') — CDP deep-dive Rev 5 (item 5):
--     a solver verdict on such an emission is not evidence of satisfaction.
--     Owned by Main.hs which holds the liquid-fixpoint binary path.
--
-- Returns a per-function map; entries are populated for every contracted
-- function so the trust-report shape is uniform.
computeCDPFor
  :: GrammarMode
  -> CDPScope
  -> (WeaknessCandidate -> IO (Maybe Bool))
  -> Map Name Bool
  -> [Statement]
  -> IO (Map Name CDPResult)
computeCDPFor gm scope runCandidate verifMap stmts = do
  -- Split contracted functions into in-scope (measure) and out-of-scope
  -- (emit WarnDefShellOutOfScope, no solver call).  Per
  -- 'v0.11-cross-proposal-rollback-discipline.md' §2.1 (Outcome 0):
  -- CDPScopeCoreOnly / CDPScopeFlagGated → SDef only;
  -- CDPScopeAllDefLogic → all four forms (legacy path).
  --
  -- CDP deep-dive Rev 5 (item 3): the 768ab11 Omega-adequacy gate that used
  -- to split 'TResult'-returning functions off BEFORE candidate generation
  -- (routing them to 'WarnDatatypeReturnOutOfScope' unconditionally) has been
  -- removed. It suppressed a symptom: 'WeaknessCheck.cdpCatalog' derived
  -- trivial-body sum candidates via the raw internal constructor names
  -- ("Success"/"Error"), unregistered in 'builtinEnv', so a type-unsound
  -- candidate reached the solver unvalidated. The candidate basis now emits
  -- real 'ok'/'err' candidates (registered, type-correct payloads) — closing
  -- the mechanism instead of gating around it (confirmed empirically:
  -- CDP-CANDBASIS-1 shows the fixed candidate produces zero diagnostics
  -- under the same independent re-typecheck that used to only warn). The
  -- item-5 'erBodyFallback' gate in 'resultFor' remains as the general
  -- defense against any candidate — datatype-returning or otherwise — whose
  -- own synthetic body fails to translate.
  let inScopeAll = [ (n, mRet, c)
                   | s <- stmts, Just (n, mRet, c) <- [inScopeFunc scope s] ]
      outOfScopeFuncs = [ (n, c)
                        | s <- stmts, Just (n, _mRet, c) <- [outOfScopeFunc scope s] ]
  measured <- mapM (\(name, _mRet, contract) ->
                       let verifies  = Map.findWithDefault False name verifMap
                           candidates = candidatesFor name stmts
                       in fmap ((,) name) (resultFor runCandidate verifies contract candidates))
                   inScopeAll
  let skipped = [ (name, outOfScopeResult contract)
                | (name, contract) <- outOfScopeFuncs ]
  pure (Map.fromList (measured ++ skipped))
  where
    -- In-scope: forms that enter the measurement pipeline. Now carries the
    -- return-type annotation so the Omega-adequacy gate can inspect it.
    inScopeFunc CDPScopeAllDefLogic s = allContractedFunc s
    inScopeFunc CDPScopeCoreOnly    s = coreOnlyFunc s
    inScopeFunc CDPScopeFlagGated   s = coreOnlyFunc s

    -- Out-of-scope contracted forms: emit WarnDefShellOutOfScope, no score.
    outOfScopeFunc CDPScopeAllDefLogic _ = Nothing
    outOfScopeFunc _                   s = nonCoreContractedFunc s

    -- CDPScopeAllDefLogic: legacy — all four forms in scope.
    allContractedFunc (SDefLogic n _ mRet c _)   | hasContracts c = Just (n, mRet, c)
    allContractedFunc (SLetrec   n _ mRet c _ _) | hasContracts c = Just (n, mRet, c)
    allContractedFunc (SDef      n _ mRet c _)   | hasContracts c = Just (n, mRet, c)
    allContractedFunc (SDefShell n _ mRet c _ _)   | hasContracts c = Just (n, mRet, c)
    allContractedFunc _ = Nothing

    -- CDPScopeCoreOnly / CDPScopeFlagGated: only def (strict-core) form.
    coreOnlyFunc (SDef n _ mRet c _) | hasContracts c = Just (n, mRet, c)
    coreOnlyFunc _                                    = Nothing

    -- Contracted forms that are out of scope under CDPScopeCoreOnly.
    nonCoreContractedFunc (SDefLogic n _ mRet c _)   | hasContracts c = Just (n, mRet, c)
    nonCoreContractedFunc (SLetrec   n _ mRet c _ _) | hasContracts c = Just (n, mRet, c)
    nonCoreContractedFunc (SDefShell n _ mRet c _ _)   | hasContracts c = Just (n, mRet, c)
    nonCoreContractedFunc _                                           = Nothing

    -- Out-of-scope result: no score, WarnDefShellOutOfScope, annotation preserved.
    outOfScopeResult contract =
      let annotation = resolveSpecEntropy contract
      in CDPResult
           { cdpCandidateCount        = 0
           , cdpSatisfyingCount       = 0
           , cdpDistinctBehaviorCount = 0
           , cdpScore                 = Nothing
           , cdpWarnings              = [WarnDefShellOutOfScope]
           , cdpDistinguishingInputs  = []
           , cdpSpecEntropyAnnotation = annotation
           , cdpExcludedCandidateCount = 0
           }

    candidatesFor n ss = filter (\wc -> wcFunctionName wc == n) (generateCDPCandidates gm ss)
    hasContracts (Contract pre _ post _ _) =
      pre /= Nothing || post /= Nothing

-- | Compute the per-function result for an in-scope function, given its
-- candidates and the IO solver runner.  Scope filtering has already been
-- applied by 'computeCDPFor'; every function reaching here is in scope.
-- Candidate-empty cases fire 'WarnCandidatesEmptyUnderLimit'; inconsistent
-- contracts fire 'WarnSpecInconsistentOrUnproven' or 'WarnSpecTooTightForOmega' per
-- 'buildWarnings'; observational equivalence is the per-candidate
-- 'trivialLabel' partition (proposal §4.3 corpus-bias caveat applies).
resultFor
  :: (WeaknessCandidate -> IO (Maybe Bool))
  -> Bool
  -> Contract
  -> [WeaknessCandidate]
  -> IO CDPResult
resultFor runCandidate functionVerifies contract candidates = do
  let annotation = resolveSpecEntropy contract
  if null candidates
    then pure CDPResult
      { cdpCandidateCount = 0
      , cdpSatisfyingCount = 0
      , cdpDistinctBehaviorCount = 0
      , cdpScore = Nothing
      , cdpWarnings = [WarnCandidatesEmptyUnderLimit]
      , cdpDistinguishingInputs = []
      , cdpSpecEntropyAnnotation = annotation
      , cdpExcludedCandidateCount = 0
      }
    else do
      passes <- mapM (\wc -> fmap ((,) wc) (runCandidate wc)) candidates
      -- CDP deep-dive Rev 5 (item 5): a candidate whose own synthetic body
      -- fell outside the QF-LIA-translatable fragment ('Nothing') is
      -- excluded from both the numerator and denominator — a solver verdict
      -- on a body-fallback emission is not evidence either way.
      let reliable      = [(wc, b) | (wc, Just b) <- passes]
          excludedCount = length passes - length reliable
          reliableCands = map fst reliable
          candCount    = length reliable
          satisfying   = [wc | (wc, True)  <- reliable]
          nonSatisfying = [wc | (wc, False) <- reliable]
          satCount     = length satisfying
          distinctSat  = length (equivalenceClasses (map wcTrivialLabel satisfying))
          distinctAll  = length (equivalenceClasses (map wcTrivialLabel reliableCands))
          warns        = buildWarnings reliableCands satisfying distinctAll annotation functionVerifies
                           ++ [WarnBodyUnfaithfulCandidatesExcluded | excludedCount > 0]
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
        , cdpExcludedCandidateCount = excludedCount
        }

-- | Build the typed warning list for a per-function CDP result per proposal §5.
buildWarnings
  :: [WeaknessCandidate]   -- ^ all candidates
  -> [WeaknessCandidate]   -- ^ satisfying candidates
  -> Int                   -- ^ distinct candidate behaviors over Ω
  -> SpecEntropy           -- ^ spec-entropy annotation
  -> Bool                  -- ^ True when post carries DLVerified / DLContractChecked evidence
  -> [CDPWarning]
buildWarnings candidates satisfying distinctAll annotation functionVerifies =
  let identityOk   = any (isIdentity . wcTrivialBody) satisfying
      constOk      = any (isConst    . wcTrivialBody) satisfying
      inconsistent = null satisfying && not (null candidates)
      narrow       = distinctAll <= 1
      -- §4.4.6: ':strict' raises the low-DP diagnostic; ':intentional' and
      -- ':unknown' both suppress it (self-attested permissiveness-by-design,
      -- or spec-in-flux). This gate applies ONLY to the two low-DP warnings
      -- below — 'WarnSpecInconsistentOrUnproven'/'WarnSpecTooTightForOmega'
      -- report a possible-inconsistency condition (a different axis) and
      -- must NOT be suppressible by an annotation never meant to cover it.
      raises = raiseLowDP annotation
  in concat
       [ [WarnIdentitySatisfiesPost | identityOk && raises]
       , [WarnConstSatisfiesPost    | constOk && raises]
       , [if functionVerifies then WarnSpecTooTightForOmega else WarnSpecInconsistentOrUnproven | inconsistent]
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
computeScore s _ | s <= 0 = Nothing  -- spec-inconsistent-or-unproven
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
