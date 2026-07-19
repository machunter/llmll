-- |
-- Module      : LLMLL.TrustReport
-- Description : v0.3.2: Trust report — transitive trust closure analysis.
--
-- Produces a per-function trust summary showing verification levels and
-- transitive trust dependencies. Used by @llmll verify --trust-report@.
--
-- The core question answered: "Which proven conclusions depend on asserted
-- assumptions upstream?"
module LLMLL.TrustReport
  ( TrustReport(..)
  , TrustEntry(..)
  , TrustDependency(..)
  , TrustSummary(..)
  , TierProfile(..)
  , OverAnnotationInfo(..)      -- F-001 (adv-spec-weaken-0): module-level over-annotation JSON surface
  , CallerObligation(..)        -- TRUST-PRE (Part 2): per-function caller-obligation axis
  , callerObligationJson        -- TRUST-PRE: shared JSON shape (report + sidecar persistence)
  , renderRequiresPredicate     -- TRUST-PRE: s-expr rendering of a 'requires' predicate
  , buildTrustReport
  , buildTrustReportWithCDP   -- LT-CDP (v0.11): variant carrying the CDP map
  , computeDecompMeet         -- Cascade L3(d) (Rev 8): decomposition-trust meet
  , contractVouched           -- Cascade L3(d) (Rev 8): :source vouched predicate
  , formatTrustReport
  , formatTrustReportJson
  , effectiveLevel     -- v0.10: for obligation trust labels (F9)
  , aggregateTiers     -- v0.10.4: fixed-arity tier-count profile (R6d)
  , aggregateTiersPre  -- OBLIG-PBT-3: per-pre-clause tier-count profile
  , aggregateTiersPost -- OBLIG-PBT-3: per-post-clause tier-count profile
  , liveCheckHashes    -- OBLIG-PBT-3: live property-body SHA set
  , downgradeStaleVerifiedSidecar -- ADMIT-VERIFIED: drop body-faithful evidence on hash drift / absence
  , computeJointHashes -- OBLIG-PBT-5a: joint witness hash detection
  , markJointPostWitness -- OBLIG-PBT-5a: per-entry joint flag setter
  , markRefuted        -- VERIFY-RPT-1: stamp refuted + depends-on-refuted post-solver
  , markMeasureNotDecreasing  -- REC-DESCENT: stamp measure-not-decreasing post-solver
  , markDescentDischarged  -- REC-DESCENT Phase 3: drop the mark for descent-discharged SCCs
  , sidecarDischargedSet   -- TERM-REPORT-PLAIN: persisted discharge for the render-only path
  , entryHeadlineLevel  -- COVERAGE-TIER: the one per-function tier notion (post-side, met + joint-demoted)
  , refutedClosure     -- VERIFY-RPT-1: refuted ∪ transitive callers (strict-core gate)
  , injectOpenedAliases -- XMOD-CG-BRIEF: bare-alias opened imports in any qualified-keyed map
  , trustReportEmitVersion
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, catMaybes, maybeToList, isJust)
import Data.List (nub, sortOn, foldl')
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Graph (stronglyConnComp, SCC(..))
import Data.Aeson (object, (.=), Value(..))
import Data.Aeson.Text (encodeToLazyText)
import qualified Data.Text.Lazy as TL

import LLMLL.Syntax
import LLMLL.Module (mergeCS)
import LLMLL.PBT (canonicalPropBodyHash, canonicalDefEvidenceHash)
import LLMLL.FixpointEmit (augmentContractPost, buildAliasMap)  -- DEF-RET Unit 2
import LLMLL.CDP (CDPResult(..), CDPWarning(..), cdpWarningLabel, overAnnotationRatio, overAnnotationThreshold, DecompQuality(..), UnvouchedMeet(..), cdpQuality, dqMeet, dqLabel, dqNumScore)
import LLMLL.AstEmit (exprToJson)
import LLMLL.HoleAnalysis (buildCallGraph)  -- REC-PARTIAL-MARK: SCC over the call graph
                                            -- (recursiveNames is reimplemented locally
                                            -- to avoid the TrustReport↔ObligationAssembly
                                            -- import cycle)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A single function's trust entry in the report.
data TrustEntry = TrustEntry
  { teName           :: Name                  -- ^ Fully-qualified function name
  , tePre            :: Maybe EvidenceRecord
  , tePost           :: Maybe EvidenceRecord
  , teDeps           :: [TrustDependency]     -- ^ Cross-module calls with their trust levels
  , teDrifts         :: [Text]                -- ^ Epistemic drift warnings
  -- v0.8.1b originally: meet(self pre⊓post, transitive deps). TRUST-PRE
  -- (transitive-callee Position B): now the POST-side effective level —
  -- identical to 'teEffectivePostLevel'. The own pre and the transitive callees'
  -- pres are excluded (they live on the 'caller_obligations' axis); a weak callee
  -- POST is still inherited. Consumed by ObligationAssembly's 'callee_tier' lever
  -- and the 'TrustChannel' tier, both of which want the post-side notion.
  , teEffectiveLevel :: Maybe DisplayLevel

  -- OBLIG-PBT-3: per-clause effective levels — each clause meets its own ER
  -- with the transitive-callee effective level. Nothing iff the clause is
  -- absent in the source contract.
  , teEffectivePreLevel  :: Maybe DisplayLevel
  , teEffectivePostLevel :: Maybe DisplayLevel
  -- OBLIG-PBT-5a (v0.10.7): True iff this entry's post-clause evidence is
  -- DLTested AND every witness hash on it is shared with at least one other
  -- subject's evidence record. When set, the scalar tested-count classifiers
  -- ('computeSummary' / 'aggregateTiers' / 'aggregateTiersPost') demote the
  -- entry from DLTested to DLAsserted so multi-subject lifts via
  -- ':subjects [...]' do not produce N scalar credits from one property body.
  -- The underlying ER is left intact for JSON emit; only the scalar
  -- classification changes.
  , teJointPostWitness   :: Bool
  -- TRUST-PRE (Part 2): the per-function caller-obligation axis. Carries the
  -- 'requires' predicate(s) a caller must establish to invoke this function
  -- soundly. An obligation is present iff THIS function declares the pre, OR it
  -- calls a callee whose pre it neither discharges (SAFE call-pre VC) nor lifts
  -- to its own 'requires' (the second disjunct is non-strict-core-only — see
  -- 'computeCallerObligations'). Sourced from the function's own 'csPre'
  -- contract, NOT the caller-side 'erCallPreFns' dual. Always populated when a
  -- 'requires' exists, on every report path; persisted to '.verified.json' (a
  -- static contract property — it cannot go stale like a solver verdict, the
  -- deliberate inverse of the non-persisted 'refuted' axis).
  , teCallerObligations  :: [CallerObligation]
  } deriving (Show, Eq)

-- | TRUST-PRE (Part 2): one caller-precondition obligation carried on a
-- function's 'teCallerObligations' axis. 'coObFn' is the function whose
-- precondition must be established (the function itself for a declared pre, or a
-- callee for an escaped transitive obligation); 'coObRequires' is the rendered
-- 'requires' predicate (an s-expr, e.g. @(>= balance amount)@), not a count or
-- a bare name — the caller needs the predicate to discharge it.
data CallerObligation = CallerObligation
  { coObFn       :: Name   -- ^ Function whose precondition must be established
  , coObRequires :: Text   -- ^ Rendered 'requires' predicate (s-expr surface form)
  } deriving (Show, Eq)

-- | A dependency on another function with its trust level.
data TrustDependency = TrustDependency
  { tdName      :: Name                -- ^ Callee function name (qualified)
  , tdPreLevel  :: Maybe DisplayLevel
  , tdPostLevel :: Maybe DisplayLevel
  } deriving (Show, Eq)

-- | The complete trust report.
data TrustReport = TrustReport
  { trEntries          :: [TrustEntry]
  , trSummary          :: TrustSummary
  , trSuppressions     :: [(Name, Text)]  -- ^ v0.6: (function name, reason) from SWeaknessOk
  , trTierProfile      :: TierProfile     -- ^ v0.10.4: fixed-arity tier-count aggregate (R6d)
  -- OBLIG-PBT-3: parallel per-clause tier-count profiles. Exposes the post-side
  -- empirical evidence directly, sidestepping the per-function meet that pins
  -- 'trTierProfile' to DLAsserted on a contracted function with an unproved
  -- pre clause (proposal §9).
  , trTierProfilePre   :: TierProfile
  , trTierProfilePost  :: TierProfile
  -- OBLIG-PBT-3: per-clause downgrade diagnostics (stale pbt_witnesses).
  , trStaleDowngrades  :: [Text]
  -- OBLIG-PBT-5a (v0.10.7): grouped joint-PBT witness map for emit. Each
  -- entry is a (witness hash, [subject names]) pair where the same
  -- canonical-property-body hash appears on the post-clause evidence of two
  -- or more distinct subjects (a ':subjects [f g …]' lift). Empty when no
  -- such sharing exists; surfaced in the trust-report JSON under the
  -- additive 'joint_pbt_witnesses' key (no 'trust_report_version' bump per
  -- the 2026-05-23 critique-triage routing).
  , trJointWitnesses   :: [(Text, [Name])]
  -- LT-CDP (v0.11): per-function discriminative-power measurement. Map from
  -- the function's (possibly qualified) name to its CDP result. The map is
  -- empty when '--cdp' was not requested; downstream consumers detect this
  -- and emit a single 'WarnNotRequested' entry per function so the JSON
  -- shape stays uniform (proposal §5).
  , trCDP              :: Map Name CDPResult
  -- VERIFY-RPT-1 (Commit 4): body-faithful functions whose body VC the solver
  -- reported UNSAFE (refuted). A verify-time-only status (never persisted to
  -- '.verified.json'); the base 'buildTrustReport' leaves it empty and the
  -- post-solver path populates it via 'markRefuted'. Orthogonal to the
  -- 'DisplayLevel' diamond — refutation is negative evidence, off the
  -- evidence-strength axis (verified-contract-refuted-status-proposal §3.2).
  , trRefutedFns       :: Set Name
  -- REC-PARTIAL-MARK (1.5.0): functions in a cyclic call-graph SCC, i.e.
  -- recursive/mutually-recursive functions whose postconditions hold only at
  -- PARTIAL correctness (termination unverified; REC-BODY-VC increment (a),
  -- docs/design/rec-body-vc-proposal.md §(a)). DERIVED at build time from the
  -- live statements (entry + cached modules) via the call-graph SCC — never
  -- persisted to '.verified.json', so it is present on every report path
  -- including a solver-less render (unlike 'trRefutedFns', which is empty
  -- without a solver). Informational only: like 'trRefutedFns' / overflow-taint
  -- it does NOT feed the trust meet, 'DisplayLevel', or admission. Descent
  -- discharge (REC-BODY-VC (c), REC-DESCENT) will later clear a member.
  , trPartialFns       :: Set Name
  -- Cascade Refinement L3(d) (Rev 8, docs/design/cascading-refinement-proposal.md
  -- §194-204): per-function decomposition-trust meet over the function's
  -- UNVOUCHED (:source-absent) transitive-callee subtree. Report-only, like
  -- 'trPartialFns' — does NOT feed the trust meet, 'DisplayLevel', or admission
  -- (§194 normative invariant). Empty without '--cdp'; emitted inside the
  -- per-entry 'discriminative_axis' block, never as a tier field.
  , trDecompMeet       :: Map Name UnvouchedMeet
  -- REC-DESCENT (v0.14.25): functions whose declared 'decreases' measure the
  -- solver disproved — a failing well-foundedness (e ≥ 0) or strict-descent
  -- (eᵍ[a] < eᶠ) constraint. DISTINCT from 'trRefutedFns': refuted = the
  -- postcondition is disproved; measure-not-decreasing = the DECLARED measure
  -- does not decrease (the function may still terminate under another measure).
  -- Verify-time only (empty on a solver-less render), populated post-solver by
  -- 'markMeasureNotDecreasing' from the descent/decreases-clause origins.
  , trMeasureNotDecreasingFns :: Set Name
  -- F-001 (adv-spec-weaken-0): module-level '(spec-entropy :intentional)'
  -- density, mirroring the text-only diagnostic at Main.hs's CDP branch
  -- ('over-annotation-warning', CDP.hs Risk #3). Computed here (pure
  -- function of 'entryStmts', no solver dependency) so every trust-report
  -- JSON emit carries it regardless of which flag (--cdp, --weakness-check,
  -- --strict-verify) triggered the report — previously this ratio was only
  -- ever printed as a stdout line under 'unless json', so no JSON consumer
  -- could observe it. Never persisted to '.verified.json' (verify-time-only,
  -- like 'trRefutedFns').
  , trOverAnnotation   :: OverAnnotationInfo
  } deriving (Show, Eq)

-- | F-001 (adv-spec-weaken-0): module-level over-annotation ratio + the
-- fixed threshold it's compared against (CDP proposal §10 Risk #3).
data OverAnnotationInfo = OverAnnotationInfo
  { oaiRatio     :: Double
  , oaiThreshold :: Double
  , oaiFired     :: Bool
  } deriving (Show, Eq)

data TrustSummary = TrustSummary
  { tsVerified :: Int  -- ^ Functions with body-faithful verified evidence
  , tsContractChecked :: Int  -- ^ Functions with contract-checked (non-body) evidence
  , tsTested   :: Int  -- ^ Functions with tested (but not solver-backed) clauses
  , tsAsserted :: Int  -- ^ Functions with asserted clauses
  , tsNone     :: Int  -- ^ Functions with no contracts
  , tsDrifts   :: Int  -- ^ Total epistemic drift warnings
  } deriving (Show, Eq)

-- | v0.10.4 (R6d): Fixed-arity tier-count profile over the trust report.
--
-- Six independent counts of per-function effective tier classifications. Never
-- reduced to a scalar — the harness composes its own Cred(R) predicate over
-- these six fields. Component-wise dominance is the only legitimate ordering;
-- the diamond-incomparability of contract-checked vs tested (LLMLL.md:344) is
-- preserved by refusing to total-order the components.
--
-- The 'tpProved' slot is reserved for a future Lean-discharged tier and is
-- zero by construction in the current emit — no DLProved constructor exists.
data TierProfile = TierProfile
  { tpVerified        :: Int
  , tpProved          :: Int
  , tpContractChecked :: Int
  , tpTested          :: Int
  , tpAsserted        :: Int
  , tpNoContract      :: Int
  } deriving (Show, Eq)

-- | Version string for the trust-report JSON emit shape.
-- Independent of the source JSON-AST 'expectedSchemaVersion'; the trust report
-- is emit-only and never re-parsed.
--
-- OBLIG-PBT-3 (1.1.0): parallel 'tier_profile_pre' and 'tier_profile_post'
-- emitted alongside the unchanged scalar 'tier_profile'; existing 'tier_profile'
-- consumers ignore the new fields. No source-AST schema delta.
--
-- LT-CDP (v0.11) (1.2.0): per-function 'discriminative_axis' block carrying
-- the contract-discriminative-power score, candidate counts, and the typed
-- warning enumeration per 'contract-discriminative-power-proposal.md' §5.
-- The block is optional in the schema and populated under '--cdp' or with a
-- single 'WarnNotRequested' marker otherwise.
--
-- VERIFY-RPT-1 (1.3.0): additive 'refuted' per-entry flag, top-level
-- 'refuted_fns', and the 'depends-on-refuted' drift kind. No 'DisplayLevel'
-- change, no 'evidenceMeet'/'evidenceCovers' change; existing consumers ignore
-- the new keys (verified-contract-refuted-status-proposal §6).
--
-- TRUST-PRE (1.4.0): additive per-entry 'caller_obligations' axis (the
-- 'requires' predicate a caller must establish) + the co-located
-- 'carries_caller_obligations' boolean. The tier classifier also stops meeting
-- in 'csPre' (Position B, summary-only) so a precondition no longer floors a
-- function's verified tier — but that is a classification fix, not a JSON-shape
-- change. The new keys are additive; existing 1.3.0 consumers ignore them.
-- Unlike 'refuted', the obligation axis is PERSISTED to '.verified.json' (a
-- static contract property, the safety-polarity inverse of the solver verdict).
--
-- REC-PARTIAL-MARK (1.5.0): additive top-level 'partial_fns' list + per-entry
-- 'termination_unverified' flag (only-on-true). Derived from the call-graph SCC,
-- never persisted; existing 1.4.0 consumers ignore the new keys.
trustReportEmitVersion :: Text
trustReportEmitVersion = "1.5.0"

-- ---------------------------------------------------------------------------
-- Report Building
-- ---------------------------------------------------------------------------

-- | Build a trust report from a module cache, entry-point statements,
-- and an optional sidecar ContractStatus map (from .verified.json).
-- For each function with contracts, identifies:
--   1. Its own verification level (from ContractStatus, upgraded by sidecar)
--   2. Which cross-module functions it calls (from the AST)
--   3. Whether those callees have lower trust levels (epistemic drift)
buildTrustReport :: ModuleCache -> [Statement] -> Map Name ContractStatus -> TrustReport
buildTrustReport cache entryStmts sidecar =
  buildTrustReportWithCDP cache entryStmts sidecar Map.empty

-- | LT-CDP (v0.11): variant that threads the per-function CDP result map
-- into the trust report. When the map is empty, the JSON emit substitutes a
-- 'WarnNotRequested' marker per function so consumers see a uniform shape.
buildTrustReportWithCDP
  :: ModuleCache
  -> [Statement]
  -> Map Name ContractStatus
  -> Map Name CDPResult
  -> TrustReport
buildTrustReportWithCDP cache entryStmts sidecar cdpMap =
  let -- OBLIG-PBT-3: read-side validation. Compute the set of live property-body
      -- hashes (local + cached modules); downgrade any sidecar evidence record
      -- whose pbt_witnesses do not intersect the live set. The downgrade is
      -- strict (DLTested → DLAsserted) and surfaces as a diagnostic.
      liveSet            = liveCheckHashes cache entryStmts
      (sidecar', stales) = downgradeStaleSidecar liveSet sidecar
      -- Collect all contract statuses: qualified names from cache + entry module
      baseCS      = collectAllContractStatus cache entryStmts
      -- v0.9.0: merge sidecar evidence (verified, contract-checked, etc.)
      -- into the base contract status map. Sidecar upgrades; base defaults remain
      -- if the sidecar is missing a clause.
      mergedCS    = Map.unionWith mergeCS sidecar' baseCS
      -- XMOD-TIER: resolve the entry module's bare calls to opened imports so a
      -- cross-module caller's callee-meet sees the imported verified evidence
      -- (which is keyed qualified in 'mergedCS'). Entry-module-only; never
      -- overwrites a local bare entry. See 'injectOpenedAliases'.
      allCS       = injectOpenedAliases entryStmts mergedCS
      -- Collect all exports from cache for type-checking call resolution
      allExports  = collectAllExports cache
      -- Build entries for every function that has contracts
      entryModule = buildModuleEntries "" entryStmts allCS
      cacheEntries = concatMap (\(path, menv) ->
        buildModuleEntries (T.intercalate "." path <> ".") (meStatements menv) allCS
        ) (Map.toList cache)
      allEntries = entryModule ++ cacheEntries
      -- v0.6.3 (BUG-3): build transitive call graph and reachable set
      callGraph = Map.fromList
        [ (teName e, map tdName (teDeps e)) | e <- allEntries ]
      reachable = transitiveClose callGraph
      -- v0.6.3: recompute drifts and effective levels using transitive deps
      enrichedEntries = map (enrichEntry allCS reachable) allEntries
      -- v0.6: collect weakness-ok suppressions
      suppressions = extractSuppressions entryStmts
      -- OBLIG-PBT-5a (v0.10.7): joint-witness detection. A canonical-property-
      -- body hash appearing on the post-clause witnesses of two or more
      -- distinct subject names is a ':subjects [...]' joint lift; in scalar
      -- tier counts we exclude the joint-only credit so N subjects sharing
      -- one property body do not contribute N to the 'tested' count.
      jointHashes  = computeJointHashes allCS
      jointGroups  = buildJointWitnessGroups allCS jointHashes
      -- TRUST-PRE (Part 2): rendered 'requires' per (qualified) function name,
      -- from the LIVE source contracts (so the predicate is available on every
      -- report path, independent of the sidecar). Keyed identically to the
      -- entry names ('buildModuleEntries' prefixing).
      declaredReqs = collectDeclaredRequires cache entryStmts
      jointMarked  = map (markJointPostWitness jointHashes) enrichedEntries
      markedEntries = markCallerObligations declaredReqs jointMarked
      -- Compute summary
      summary = computeSummary markedEntries
      -- v0.10.4 (R6d): tier-count profile over the same enriched entries
      tierProfile = aggregateTiers markedEntries
      -- OBLIG-PBT-3: parallel per-clause aggregates (proposal §9)
      tierProfilePre  = aggregateTiersPre  markedEntries
      tierProfilePost = aggregateTiersPost markedEntries
      -- F-001 (adv-spec-weaken-0): entry-module-only scope, matching the
      -- ratio's sole pre-existing call site (Main.hs's CDP branch, which
      -- also passes entry-module 'stmts' only — not cache-module statements).
      oaiRatio'  = overAnnotationRatio entryStmts
      overAnnotation = OverAnnotationInfo
        { oaiRatio     = oaiRatio'
        , oaiThreshold = overAnnotationThreshold
        , oaiFired     = oaiRatio' > overAnnotationThreshold
        }
      -- REC-PARTIAL-MARK: cyclic-SCC members of the WHOLE-PROGRAM call graph
      -- (entry ∪ cached modules), so an imported recursive callee that appears
      -- in the report is marked too. Reimplements 'ObligationAssembly.recursiveNames'
      -- locally (the import back would cycle: ObligationAssembly already imports
      -- TrustReport). Precedent for a locally-kept helper to break an import
      -- cycle: 'FixpointEmit.admissibleDatatype'.
      partialFns = cyclicSccMembers
                     (entryStmts ++ concatMap meStatements (Map.elems cache))
      -- Cascade L3(d) (Rev 8): vouched (:source-anchored) function names over the
      -- whole program, and the per-function decomposition-trust meet over each
      -- function's unvouched transitive-callee subtree. Pure fold over 'cdpMap';
      -- 'reachable' and 'partialFns' are already computed above.
      vouchedSet = Set.fromList
        [ n | s <- entryStmts ++ concatMap meStatements (Map.elems cache)
            , Just (n, _, _, c, _) <- [normalizeDefStmt s]
            , contractVouched c ]
      decompMeetMap
        | Map.null cdpMap = Map.empty  -- '--cdp'-gated: no meet without CDP scores
        | otherwise = Map.fromList
            [ (teName e, computeDecompMeet reachable vouchedSet cdpMap partialFns (teName e))
            | e <- markedEntries ]
  in TrustReport
       { trEntries         = markedEntries
       , trSummary         = summary
       , trSuppressions    = suppressions
       , trTierProfile     = tierProfile
       , trTierProfilePre  = tierProfilePre
       , trTierProfilePost = tierProfilePost
       , trStaleDowngrades = stales
       , trJointWitnesses  = jointGroups
       , trCDP             = cdpMap
       , trRefutedFns      = Set.empty  -- VERIFY-RPT-1: populated by markRefuted post-solver
       , trPartialFns      = partialFns  -- REC-PARTIAL-MARK: derived, present on every path
       , trDecompMeet      = decompMeetMap  -- Cascade L3(d) (Rev 8): decomposition-trust meet
       , trMeasureNotDecreasingFns = Set.empty  -- REC-DESCENT: populated by markMeasureNotDecreasing post-solver
       , trOverAnnotation  = overAnnotation
       }
  where
    -- REC-PARTIAL-MARK: mirror of 'ObligationAssembly.recursiveNames:286-290'
    -- (kept local to avoid the TrustReport↔ObligationAssembly import cycle).
    cyclicSccMembers ss =
      let cg   = buildCallGraph ss
          sccs = stronglyConnComp [(n, n, deps) | (n, deps) <- Map.toList cg]
      in Set.fromList [n | CyclicSCC ns <- sccs, n <- ns]

-- | VERIFY-RPT-1 (Commit 4): refusal set for '--strict-verified-core' conjunct
-- (c). Returns the directly-refuted functions together with every function that
-- transitively calls one (depends-on-refuted). The transitive closure is taken
-- because assume-guarantee composition (LLMLL.md §0.1) makes a caller of a
-- refuted callee unsound — its own SAFE VC rests on a disproved assumption.
refutedClosure :: Set Name -> TrustReport -> Set Name
refutedClosure refuted report =
  let callGraph = Map.fromList [ (teName e, map tdName (teDeps e)) | e <- trEntries report ]
      reachable = transitiveClose callGraph
      callers   = Set.fromList
        [ teName e
        | e <- trEntries report
        , not (Set.null (Set.intersection
                           (Map.findWithDefault Set.empty (teName e) reachable)
                           refuted))
        ]
  in Set.union refuted callers

-- | VERIFY-RPT-1 (Commit 4): stamp a solver-derived refuted set onto a report.
-- Sets 'trRefutedFns' (the directly-refuted functions, driving the per-entry
-- 'refuted' flag and top-level 'refuted_fns' at JSON emit) and appends drift
-- lines: a 'refuted' note on each directly-refuted entry and a
-- 'depends-on-refuted' note on each transitive caller. Verify-time only.
markRefuted :: Set Name -> TrustReport -> TrustReport
markRefuted refuted report =
  let closure   = refutedClosure refuted report
      dependsOn = Set.difference closure refuted
      stamp e
        | Set.member (teName e) refuted =
            e { teDrifts = teDrifts e ++
                  ["refuted: body VC disproved by liquid-fixpoint (solver UNSAFE); implementation contradicts its contract"] }
        | Set.member (teName e) dependsOn =
            e { teDrifts = teDrifts e ++
                  ["depends-on-refuted: transitively calls a refuted function; assume-guarantee proof rests on a disproved postcondition"] }
        | otherwise = e
  in report { trEntries    = map stamp (trEntries report)
            , trRefutedFns = refuted
            }

-- | REC-DESCENT (v0.14.25): stamp measure-not-decreasing functions post-solver.
-- Sets 'trMeasureNotDecreasingFns' and adds a per-entry drift note. Distinct
-- from 'markRefuted': this is a measure verdict, not a postcondition refutation,
-- so it does NOT propagate a 'depends-on' closure (a caller of a
-- measure-unfit function is not itself measure-unfit).
markMeasureNotDecreasing :: Set Name -> TrustReport -> TrustReport
markMeasureNotDecreasing mnd report =
  let stamp e
        | Set.member (teName e) mnd =
            e { teDrifts = teDrifts e ++
                  ["measure-not-decreasing: the declared decreases measure was disproved by liquid-fixpoint (solver UNSAFE on a well-foundedness or strict-descent constraint); termination under this measure does not hold"] }
        | otherwise = e
  in report { trEntries                 = map stamp (trEntries report)
            , trMeasureNotDecreasingFns = mnd
            }

-- | REC-DESCENT Phase 3: drop the 'termination_unverified' mark for the
-- descent-discharged (total-correctness) functions. Post-solver, like
-- 'markRefuted' / 'markMeasureNotDecreasing' — discharge is a solver fact.
-- A solver-less '--trust-report' render feeds this from the PERSISTED sidecar
-- instead ('sidecarDischargedSet', TERM-REPORT-PLAIN): the render-only path
-- already trusts staleness-gated sidecar evidence for 'verified' posts, and
-- ignoring the same sidecar's 'termination_verified' made it contradict the
-- strict/CDP paths. Subtracts from 'trPartialFns'; the per-entry
-- 'termination_unverified' flag and the top-level 'partial_fns' list are both
-- projected from that set, so both clear.
markDescentDischarged :: Set Name -> TrustReport -> TrustReport
markDescentDischarged discharged report =
  report { trPartialFns = trPartialFns report `Set.difference` discharged }

-- | TERM-REPORT-PLAIN: the functions whose persisted post evidence is
-- descent-discharged ('erTerminationVerified'). The render-only trust-report
-- path feeds this to 'markDescentDischarged' so a sidecar-recorded total
-- verdict survives a solver-less render. Staleness gating is the caller's
-- job — pass the gated sidecar (Main.hs 'entrySidecar'), never a raw reload.
-- 'measure-not-decreasing' has no analog here: it is a same-run solver
-- verdict, never persisted — solver-path-only, exactly like 'refuted'.
sidecarDischargedSet :: Map Name ContractStatus -> Set Name
sidecarDischargedSet =
  Map.keysSet . Map.filter (maybe False erTerminationVerified . csPost)

-- | OBLIG-PBT-3: collect SHA-256 hashes of every live property body across
-- the entry module and the cached module set. Used by 'buildTrustReport' on
-- read to detect property-body drift / deletion and downgrade stale
-- 'DLTested' entries to 'DLAsserted'. Includes 'SDefInterface' law bodies
-- defensively in anticipation of OBLIG-PBT-4's law-lift admission.
liveCheckHashes :: ModuleCache -> [Statement] -> Set Text
liveCheckHashes cache entryStmts =
  let entryHashes = collect entryStmts
      cacheHashes = Set.unions
        [ collect (meStatements menv) | (_, menv) <- Map.toList cache ]
  in Set.union entryHashes cacheHashes
  where
    collect stmts = Set.fromList $
      [ canonicalPropBodyHash (propBody p) | SCheck p <- stmts ]
      ++
      [ canonicalPropBodyHash (propBody p)
      | SDefInterface _ _ laws <- stmts, p <- laws ]

-- | OBLIG-PBT-3: walk every sidecar ContractStatus and downgrade any
-- 'EvidenceRecord' whose 'erPbtWitnesses' is non-empty but disjoint from the
-- live-hash set. Strict: 'DLTested' → 'DLAsserted'; 'DLVerified' /
-- 'DLContractChecked' records are not produced by PBT writeback and so
-- their witness lists are empty, so they are unaffected. Returns the
-- downgraded map and a per-clause diagnostic list (qualified-name + cached
-- description).
downgradeStaleSidecar :: Set Text -> Map Name ContractStatus -> (Map Name ContractStatus, [Text])
downgradeStaleSidecar liveSet =
  Map.foldlWithKey' step (Map.empty, [])
  where
    step (mAcc, dAcc) name cs =
      let (cs', ds) = downgradeCS name cs
      in (Map.insert name cs' mAcc, dAcc ++ ds)

    downgradeCS name cs =
      let (mPre,  dPre)  = downgradeER name "pre"  (csPre cs)
          (mPost, dPost) = downgradeER name "post" (csPost cs)
      in (cs { csPre = mPre, csPost = mPost }, dPre ++ dPost)

    downgradeER _    _      Nothing   = (Nothing, [])
    downgradeER name clause (Just er) =
      let ws = erPbtWitnesses er
          live = any (\w -> Set.member (pwHash w) liveSet) ws
      in if null ws || live
           then (Just er, [])
           else let descs = T.intercalate ", " (map (\w -> "\"" <> pwDescription w <> "\"") ws)
                    diag  = name <> "." <> clause <> " was previously tested by property "
                          <> descs <> "; no live property body matches the cached hash. "
                          <> "Evidence downgraded to asserted."
                in (Just (er { erDisplayLevel = DLAsserted, erPbtWitnesses = [], erOverflowTainted = False }), [diag])

-- | ADMIT-VERIFIED (Option 2, §3 seam 3): downgrade any persisted body-faithful
-- 'EvidenceRecord' whose 'erVerifiedHash' does not match the hash recomputed
-- from the *live* def @(body, pre, post)@ + semantics tag. Mirrors the PBT
-- 'downgradeStaleSidecar' precedent: 'DLVerified'/'erBodyFaithful' → 'DLAsserted'
-- with the flag cleared.
--
-- The live hash is keyed by bare def name from the supplied statement list.
-- A record is downgraded when EITHER:
--   (a) 'erVerifiedHash' is 'Nothing' — soundness (iv) fail-closed: a
--       pre-ADMIT-VERIFIED sidecar (no hash) is NOT admissible; OR
--   (b) the live def is present and its recomputed hash differs (body or
--       contract drift, or a semantics-tag bump); OR
--   (c) the def name is absent from the live statements (the function the
--       evidence describes no longer exists / was renamed) — fail closed.
--
-- Records that are not 'erBodyFaithful' are passed through untouched (they make
-- no body-faithful admission claim). The downgrade is keyed off the bare name;
-- callers that hold qualified-keyed sidecars should run this over the live
-- module's own statements where the keys are bare (the entry-file warm-path),
-- which is exactly the same-file admission seam.
downgradeStaleVerifiedSidecar
  :: [Statement]                 -- ^ live statements (source of truth for body+contract)
  -> Map Name ContractStatus     -- ^ persisted sidecar evidence (bare-keyed)
  -> (Map Name ContractStatus, [Text])
downgradeStaleVerifiedSidecar stmts =
  Map.foldlWithKey' step (Map.empty, [])
  where
    -- DEF-RET Unit 2: the staleness hash covers the return refinement folded into
    -- the effective post (augmentContractPost), so editing a `-> RetType`
    -- annotation (or redefining the alias predicate) invalidates a stale verified
    -- sidecar. Must match the write-side basis (Main provenCS). Recompute is
    -- same-module (alias map in scope), so the augmented hash is reproducible.
    am = buildAliasMap stmts
    -- Live (form, body, pre, augmented-post) hash per bare def name.
    -- REC-HASH-FORM (b0): the 'defFormTag s' leg makes a def-shell -> def rename
    -- drift the hash so the stale sidecar is downgraded (probe E), read-side dual
    -- of the write-side stamp in Main.hs.
    liveHashes :: Map Name Text
    liveHashes = Map.fromList
      [ (n, canonicalDefEvidenceHash (defFormTag s) body (contractPre c) (contractPost (augmentContractPost am mRet c)) (case s of SDefShell _ _ _ _ _ d -> d; _ -> []))
      | s <- stmts
      , Just (n, _, mRet, c, body) <- [normalizeDefStmt s]
      ]

    step (mAcc, dAcc) name cs =
      let (cs', ds) = downgradeCS name cs
      in (Map.insert name cs' mAcc, dAcc ++ ds)

    downgradeCS name cs =
      let (mPre,  dPre)  = downgradeER name "pre"  (csPre cs)
          (mPost, dPost) = downgradeER name "post" (csPost cs)
      in (cs { csPre = mPre, csPost = mPost }, dPre ++ dPost)

    downgradeER _    _      Nothing   = (Nothing, [])
    downgradeER name clause (Just er)
      | not (erBodyFaithful er) = (Just er, [])   -- no body-faithful claim
      | otherwise =
          let live = Map.lookup name liveHashes
              stale = case (erVerifiedHash er, live) of
                        (Nothing, _)          -> True   -- (a) fail closed on absent hash
                        (_, Nothing)          -> True   -- (c) live def gone
                        (Just h, Just lh)     -> h /= lh -- (b) drift
              reason = case (erVerifiedHash er, live) of
                        (Nothing, _) -> "no persisted verified_hash (pre-ADMIT-VERIFIED sidecar)"
                        (_, Nothing) -> "no live definition for this name"
                        _            -> "body or contract drift since verification"
          in if not stale
               then (Just er, [])
               else let diag = name <> "." <> clause
                          <> " carried body-faithful verified evidence but it is stale ("
                          <> reason <> "). Evidence downgraded to asserted."
                    in ( Just (er { erDisplayLevel = DLAsserted
                                  , erBodyFaithful = False
                                  , erVerifiedHash = Nothing })
                       , [diag] )

-- | v0.6: Extract weakness-ok suppressions from statements.
-- Deduplicates by name (WO-3 idempotence).
extractSuppressions :: [Statement] -> [(Name, Text)]
extractSuppressions stmts = nubBy' [(n, r) | SWeaknessOk n r <- stmts]
  where nubBy' = nub

-- | Collect contract statuses from all cached modules + entry statements.
--
-- XMOD-TIER (soundness): each cached module's persisted 'meContractStatus' (the
-- module's own '.verified.json', merged at load time in 'Module.loadFromFile')
-- carries body-faithful verified evidence that — for an IMPORTED module —
-- upgrades a cross-module caller's callee-meet tier. That evidence is admitted
-- here ONLY if it is hash-valid against the cached module's LIVE def
-- (body,pre,post)+semantics tag: we run 'downgradeStaleVerifiedSidecar' over each
-- cached module's own bare-keyed status against its own statements before
-- qualifying the keys. This applies the SAME staleness discipline the
-- same-file ADMIT-VERIFIED admission uses (Main.hs seam 6): a stale/absent
-- 'erVerifiedHash' on an imported sidecar is demoted to 'asserted' and cannot
-- upgrade a tier. The entry module's own statuses are NOT revalidated here — the
-- entry sidecar's staleness gate already ran upstream (Main.hs:1108) and is
-- passed in via the 'sidecar' argument to 'buildTrustReport'.
collectAllContractStatus :: ModuleCache -> [Statement] -> Map Name ContractStatus
collectAllContractStatus cache entryStmts =
  let cacheCS = Map.foldlWithKey' (\acc path menv ->
        let prefix = T.intercalate "." path <> "."
            -- XMOD-TIER: hash-validate this cached module's verified evidence
            -- against its OWN live statements before it can upgrade a tier.
            (validated, _diags) = downgradeStaleVerifiedSidecar
                                    (meStatements menv) (meContractStatus menv)
            qualified = Map.mapKeys (prefix <>) validated
        in Map.union qualified acc) Map.empty cache
      entryCS = Map.fromList $ mapMaybe extractCS entryStmts
  in Map.union entryCS cacheCS
  where
    extractCS (SDefLogic name _ mRet c _)  = mkCS name mRet c
    extractCS (SLetrec name _ mRet c _ _)  = mkCS name mRet c
    -- LT-INV (v0.11)
    extractCS (SDef      name _ mRet c _)  = mkCS name mRet c
    extractCS (SDefShell name _ mRet c _ _)  = mkCS name mRet c
    extractCS _                            = Nothing
    -- DEF-RET Unit 2: fold the return refinement into the effective post so a
    -- bare `-> RetType` function (no explicit `post`) gets a csPost slot for the
    -- sidecar's verified evidence to surface. Matches the write-side basis.
    am = buildAliasMap entryStmts
    -- BUG-4 (v0.14.3): mkER now takes the clause's :source provenance
    -- (contractPreSource / contractPostSource) and threads it into
    -- erSource, instead of hard-coding Nothing on every path. The parser
    -- (ParserJSON.hs) already reads pre_source/post_source into Contract,
    -- and the trust-report formatter (formatEntry, the JSON emitter) was
    -- already correctly wired to display erSource when present — this was
    -- the one missing link, present since a v0.11-era commit (3391713),
    -- that silently dropped it before it ever reached either. augmentContractPost
    -- only ever record-updates `contractPost`, so `contractPostSource cAug`
    -- always equals `contractPostSource c` (the return-refinement synthesis
    -- carries no citation of its own to merge in).
    mkCS name mRet c =
      let cAug = augmentContractPost am mRet c
      in if contractPre c /= Nothing || contractPost cAug /= Nothing
           then Just (name, ContractStatus
                  { csPre  = fmap (mkER (contractPreSource c)) (contractPre c)
                  , csPost = fmap (mkER (contractPostSource cAug)) (contractPost cAug)
                  , csAssumptions = []
                  })
           else Nothing
    -- LT-PPR (v0.11): populate predicate fields when clause is a
    -- predicate-carrying ?proof-required hole; otherwise use defaults.
    mkER :: Maybe Text -> Expr -> EvidenceRecord
    mkER src (EHole (HProofRequired _ (Just pred))) =
      EvidenceRecord DLAsserted False src [] False
        (Just "runtime")
        (Just (TL.toStrict (encodeToLazyText (exprToJson pred))))
        True
        Nothing
        False
    mkER src _ = EvidenceRecord DLAsserted False src [] False Nothing Nothing False Nothing False

-- | XMOD-TIER: inject bare-name aliases into the contract-status map for every
-- name brought into scope by an @(open M)@ in the entry module, mirroring the
-- type-checker's SOpen handling (TypeCheck.hs:893-931, ADMIT-VERIFIED seam 5).
--
-- The entry module calls an opened import by its BARE name (e.g. @(withdraw …)@),
-- but 'collectAllContractStatus' keys the imported function's verified evidence
-- under its QUALIFIED name (@core.withdraw@). 'extractCalls' yields the bare
-- name, so 'mkEntry'/'enrichEntry' look it up bare and miss the qualified
-- verified record — the imported callee dependency is silently dropped, and the
-- caller's post-side callee meet never inherits the verified post. We resolve
-- this here ONLY for the entry module (the sole place bare calls to opened
-- imports occur), keyed off the entry module's own @(open …)@ declarations, with
-- the SAME discipline as the type-checker:
--   * a bare alias is added only when a matching qualified key exists in 'allCS';
--   * the selective @(open M (f g))@ name filter is honored;
--   * an existing BARE entry (the entry module's own local def of the same name)
--     is never overwritten — local evidence shadows the import, matching SOpen.
-- Cache modules are unaffected (they resolve their own deps by their own keys),
-- so the same-module / single-file / no-open paths are byte-identical.
--
-- Polymorphic in the value (pure key manipulation), so the same discipline
-- serves any qualified-keyed per-function map — the contract-status map here
-- and the checkout brief's trust-entry map (XMOD-CG-BRIEF 'callee_tier').
injectOpenedAliases :: [Statement] -> Map Name a -> Map Name a
injectOpenedAliases entryStmts allCS =
  foldl' addOpen allCS [ (openPath, mNames) | SOpen openPath mNames <- entryStmts ]
  where
    addOpen acc (openPath, mNames) =
      let prefix     = T.intercalate "." openPath <> "."
          qualifying = Map.filterWithKey (\k _ -> prefix `T.isPrefixOf` k) acc
          bareCS     = Map.mapKeys (T.drop (T.length prefix)) qualifying
          filtered   = case mNames of
            Nothing -> bareCS
            Just ns -> Map.filterWithKey (\k _ -> k `elem` ns) bareCS
      -- 'insertWith (\_new old -> old)' keeps an existing bare (local) entry —
      -- the local def shadows the import, identical to the SOpen shadow direction.
      in Map.foldlWithKey' (\m k cs -> Map.insertWith (\_new old -> old) k cs m)
                           acc filtered

-- | TRUST-PRE (Part 2): rendered 'requires' predicate per (qualified) function
-- name, from the live source contracts. Same key convention as
-- 'collectAllContractStatus' / 'buildModuleEntries' so it joins against the
-- entry names. A function contributes iff it declares a pre clause.
collectDeclaredRequires :: ModuleCache -> [Statement] -> Map Name Text
collectDeclaredRequires cache entryStmts =
  let cacheReqs = Map.foldlWithKey' (\acc path menv ->
        let prefix = T.intercalate "." path <> "."
        in Map.union (Map.mapKeys (prefix <>) (fromStmts (meStatements menv))) acc)
        Map.empty cache
      entryReqs = fromStmts entryStmts
  in Map.union entryReqs cacheReqs
  where
    fromStmts stmts = Map.fromList (mapMaybe declaredReq stmts)
    declaredReq s = case contractOf s of
      Just (name, c) -> fmap (\pre -> (name, renderRequiresPredicate pre)) (contractPre c)
      Nothing        -> Nothing
    contractOf (SDefLogic     name _ _ c _) = Just (name, c)
    contractOf (SLetrec       name _ _ c _ _) = Just (name, c)
    contractOf (SDef          name _ _ c _) = Just (name, c)
    contractOf (SDefShell     name _ _ c _ _) = Just (name, c)
    contractOf (SDefInvariant name _ _ c _) = Just (name, c)
    contractOf _                            = Nothing

-- | Collect all exports from cached modules.
collectAllExports :: ModuleCache -> Map Name Type
collectAllExports cache = Map.foldlWithKey' (\acc path menv ->
  let prefix = T.intercalate "." path <> "."
      qualified = Map.mapKeys (prefix <>) (meExports menv)
  in Map.union qualified acc) Map.empty cache

-- | Build trust entries for functions in one module.
buildModuleEntries :: Text -> [Statement] -> Map Name ContractStatus -> [TrustEntry]
buildModuleEntries prefix stmts allCS =
  mapMaybe (buildEntry prefix allCS) stmts

buildEntry :: Text -> Map Name ContractStatus -> Statement -> Maybe TrustEntry
buildEntry prefix allCS stmt = case stmt of
  SDefLogic name _ _ contract body ->
    let qname = prefix <> name
    in Just (mkEntry qname contract body allCS)
  SLetrec name _ _ contract _ body ->
    let qname = prefix <> name
    in Just (mkEntry qname contract body allCS)
  -- LT-INV (v0.11): SDef and SDefShell contribute to trust report identically.
  SDef      name _ _ contract body ->
    let qname = prefix <> name
    in Just (mkEntry qname contract body allCS)
  SDefShell name _ _ contract body _ ->
    let qname = prefix <> name
    in Just (mkEntry qname contract body allCS)
  -- v0.12.1: def-invariant contributes to trust report identically to SDefLogic.
  SDefInvariant name _ _ contract body ->
    let qname = prefix <> name
    in Just (mkEntry qname contract body allCS)
  _ -> Nothing

mkEntry :: Name -> Contract -> Expr -> Map Name ContractStatus -> TrustEntry
mkEntry qname contract body allCS =
  let ownCS = Map.findWithDefault (ContractStatus Nothing Nothing []) qname allCS
      -- Find all function calls in the body
      callees = nub $ extractCalls body
      -- Build dependencies for cross-module callees that have contract status
      deps = mapMaybe (\callee ->
        case Map.lookup callee allCS of
          Nothing -> Nothing
          Just cs -> Just (TrustDependency callee
                     (fmap erDisplayLevel (csPre cs))
                     (fmap erDisplayLevel (csPost cs)))
        ) callees
      -- Compute epistemic drift: this function is solver-backed but depends on non-solver-backed
      drifts = computeDrifts qname ownCS deps
  in TrustEntry
       { teName               = qname
       , tePre                = csPre ownCS
       , tePost               = csPost ownCS
       , teDeps               = deps
       , teDrifts             = drifts
       , teEffectiveLevel     = Nothing  -- computed later by enrichEntry
       , teEffectivePreLevel  = Nothing  -- OBLIG-PBT-3: computed by enrichEntry
       , teEffectivePostLevel = Nothing  -- OBLIG-PBT-3: computed by enrichEntry
       , teJointPostWitness   = False    -- OBLIG-PBT-5a: marked by markJointEntries
       , teCallerObligations  = []       -- TRUST-PRE: filled by markCallerObligations
       }

-- | Extract all function call names from an expression (recursive walk).
extractCalls :: Expr -> [Name]
extractCalls (EApp name args)   = name : concatMap extractCalls args
extractCalls (ELit _)           = []
extractCalls (EVar _)           = []
extractCalls (ELet binds body)  = concatMap (\(_, _, e) -> extractCalls e) binds ++ extractCalls body
extractCalls (EIf c t e)        = extractCalls c ++ extractCalls t ++ extractCalls e
extractCalls (EMatch e cases)   = extractCalls e ++ concatMap (\(_, b) -> extractCalls b) cases
extractCalls (EOp _ args)       = concatMap extractCalls args
extractCalls (EPair a b)        = extractCalls a ++ extractCalls b
extractCalls (EHole _)          = []
extractCalls (EAwait e)         = extractCalls e
extractCalls (ELambda _ body)   = extractCalls body
extractCalls (EDo steps)        = concatMap (\(DoStep _ e) -> extractCalls e) steps

-- | Compute epistemic drift warnings.
-- v0.8.1b: Drift uses isSolverBacked and the transitive reachable set.
computeDrifts :: Name -> ContractStatus -> [TrustDependency] -> [Text]
computeDrifts fname ownCS deps =
  let ownLevel = effectiveLevel ownCS
  in case ownLevel of
       Just vl | isSolverBacked vl ->
         -- Check each dependency: is any callee below solver-backed?
         concatMap (\dep ->
           let calleeLevel = effectiveLevelFromDep dep
           in case calleeLevel of
                Just vl' | isSolverBacked vl' -> []
                Just vl' -> [fname <> " is " <> dlLabel vl <> ", but depends on " <> tdName dep
                           <> " which is " <> dlLabel vl']
                Nothing -> []
           ) deps
       _ -> []  -- Not solver-backed: no drift possible

-- | v0.6.3 (BUG-3): Compute transitive closure of a call graph.
-- Uses fixed-point iteration. Handles cycles safely.
transitiveClose :: Map Name [Name] -> Map Name (Set Name)
transitiveClose graph = fixpoint initial
  where
    initial = Map.map Set.fromList graph
    fixpoint current =
      let next = Map.mapWithKey (\_ reachable ->
            Set.foldl' (\acc callee ->
              case Map.lookup callee current of
                Nothing      -> acc
                Just calleeR -> Set.union acc calleeR
              ) reachable reachable
            ) current
      in if next == current then current else fixpoint next

-- | Cascade L3(d) (Rev 8): a contract is VOUCHED iff it has at least one
-- present clause and every present clause carries a ':source' provenance
-- annotation (LLMLL.md §4.6 — traceability to an originating standard).
-- Unvouched (the meet's scope) = some present clause lacks ':source', or no
-- clause is present. A cooperative-author heuristic, not soundness-grade
-- vouching: a ':source' string is unvalidated free-form metadata, so an
-- adversarial exclusion is caught by R5, not this predicate (Rev-8 threat model).
contractVouched :: Contract -> Bool
contractVouched c =
  let present =
        [ isJust src
        | (mClause, src) <- [ (contractPre  c, contractPreSource  c)
                            , (contractPost c, contractPostSource c) ]
        , isJust mClause ]
  in not (null present) && and present

-- | Cascade L3(d) (Rev 8): the decomposition-trust meet for 'fn' over its
-- UNVOUCHED transitive-callee subtree, EXCLUDING 'fn' itself (the anchored
-- root is not part of its own invented decomposition). Vouched members are
-- excluded but named; the measured members' quality is met; abstain/epistemic
-- members are counted unmeasured (never folded); a cyclic-SCC member sets the
-- floor flag WITHOUT collapsing the quality meet (Rev-8 round-3). Pure — no solver.
computeDecompMeet
  :: Map Name (Set Name)  -- ^ transitive-callee closure ('transitiveClose')
  -> Set Name             -- ^ vouched (:source-anchored) function names
  -> Map Name CDPResult   -- ^ per-function CDP results
  -> Set Name             -- ^ partial (cyclic-SCC) members ('trPartialFns')
  -> Name                 -- ^ the function whose decomposition is scored
  -> UnvouchedMeet
computeDecompMeet reachable vouched cdp partial fn =
  let subtree     = Set.delete fn (Map.findWithDefault Set.empty fn reachable)
      (vouchedMs, unvouchedMs) = Set.partition (`Set.member` vouched) subtree
      unvouchedL  = Set.toList unvouchedMs
      classified  = [ (m, q) | m <- unvouchedL, Just q <- [Map.lookup m cdp >>= cdpQuality] ]
      meetPair    = case classified of
                      []     -> Nothing
                      (x:xs) -> Just (foldl weaker x xs)
      weaker a@(_, qa) b@(_, qb) = if dqMeet qa qb == qa then a else b
      floored     = not (Set.null (Set.intersection unvouchedMs partial))
  in UnvouchedMeet
       { umQualityMeet     = fmap snd meetPair
       , umWeakestFn       = fmap fst meetPair
       , umFlooredByCycle  = floored
       , umMeasured        = length classified
       , umUnmeasured      = length unvouchedL - length classified
       , umInScopeTotal    = length unvouchedL
       , umExcludedVouched = Set.size vouchedMs
       , umExcludedFns     = Set.toList vouchedMs
       }

-- | v0.8.1b: Enrich an entry with transitive drift and effective level.
-- OBLIG-PBT-3: also populates per-clause effective levels (pre and post
-- each meet only their own ER with the transitive-callee effective level,
-- not with the sibling clause).
enrichEntry :: Map Name ContractStatus -> Map Name (Set Name) -> TrustEntry -> TrustEntry
enrichEntry allCS reachable entry =
  let qname = teName entry
      ownCS = Map.findWithDefault (ContractStatus Nothing Nothing []) qname allCS
      -- Build TrustDependency for each transitively reachable callee
      transitiveCallees = maybe Set.empty id (Map.lookup qname reachable)
      transitiveDeps = mapMaybe (\callee ->
        case Map.lookup callee allCS of
          Nothing -> Nothing
          Just cs -> Just (TrustDependency callee
                     (fmap erDisplayLevel (csPre cs))
                     (fmap erDisplayLevel (csPost cs)))
        ) (Set.toList transitiveCallees)
      -- Recompute drifts using transitive set
      drifts = computeDrifts qname ownCS transitiveDeps
      -- TRUST-PRE (Position B, transitive-callee fix): the transitive-callee
      -- contribution to a caller's tier is the callee's POST-side level
      -- ('csPost'), NOT its pre-inclusive 'effectiveLevel cs'. A callee's
      -- precondition is the CALLER's call-site obligation, discharged by the
      -- SAFE 'call-pre:' VC (FixpointEmit.hs:617-619) — it is NOT a floor the
      -- caller inherits. Folding 'effectiveLevel cs' (which includes the always-
      -- 'asserted' 'csPre') dragged every caller of a pre-bearing callee down to
      -- 'asserted' even after the caller correctly discharged the pre. We fold
      -- 'csPost' instead so the caller's effective post-tier excludes BOTH its
      -- own pre and its transitive callees' pres (all on the caller_obligations
      -- axis), while STILL inheriting any genuinely weak callee POST (the
      -- invariant: never ignore a weak callee post — refuted/asserted/
      -- contract-checked posts still propagate). Because 'transitiveClose'
      -- flattens the call graph (every transitive callee is in the set) and
      -- 'evidenceMeet' is associative/commutative/idempotent, this fold over the
      -- flattened set equals the recursive post-side meet and is well-defined over
      -- SCCs (a self-edge meets a level with itself: idempotent).
      calleeMinLevel = foldl' minLevel Nothing
        [ fmap erDisplayLevel (csPost cs)
        | callee <- Set.toList transitiveCallees
        , Just cs <- [Map.lookup callee allCS]
        ]
      -- OBLIG-PBT-3: per-clause effective level (proposal §9).
      preLevel  = fmap erDisplayLevel (csPre ownCS)
      postLevel = fmap erDisplayLevel (csPost ownCS)
      effPre  = clauseEff preLevel  calleeMinLevel
      effPost = clauseEff postLevel calleeMinLevel
      -- TRUST-PRE convergence (soundness check 4): 'teEffectiveLevel' is now the
      -- POST-side effective level ('effPost'), identical to 'teEffectivePostLevel'.
      -- Its only two consumers — ObligationAssembly's 'callee_tier' soundness lever
      -- and the 'TrustChannel' tier — both want the callee's post-side tier (a
      -- consumer leans on the callee's POST, not its pre, which is the consumer's
      -- own obligation). Keeping the old pre-inclusive meet here would re-create the
      -- exact inconsistency this fix removes (a verified-post pre-bearing callee
      -- reading 'asserted' to its consumers). There is no remaining consumer of the
      -- pre-inclusive meet, so the two notions converge rather than contradict.
      eff = effPost
  in entry
       { teDrifts             = drifts
       , teEffectiveLevel     = eff
       , teEffectivePreLevel  = effPre
       , teEffectivePostLevel = effPost
       }
  where
    minLevel Nothing b  = b
    minLevel a Nothing  = a
    minLevel (Just a) (Just b) = Just (evidenceMeet a b)

    clauseEff Nothing  _              = Nothing
    clauseEff (Just s) Nothing        = Just s
    clauseEff (Just s) (Just c)       = Just (evidenceMeet s c)

-- | The effective (minimum) display level for a contract status.
effectiveLevel :: ContractStatus -> Maybe DisplayLevel
effectiveLevel cs =
  case (fmap erDisplayLevel (csPre cs), fmap erDisplayLevel (csPost cs)) of
    (Nothing, Nothing) -> Nothing
    (Just a, Nothing)  -> Just a
    (Nothing, Just b)  -> Just b
    (Just a, Just b)   -> Just (evidenceMeet a b)

-- | Effective level from a TrustDependency.
effectiveLevelFromDep :: TrustDependency -> Maybe DisplayLevel
effectiveLevelFromDep dep =
  case (tdPreLevel dep, tdPostLevel dep) of
    (Nothing, Nothing) -> Nothing
    (Just a, Nothing)  -> Just a
    (Nothing, Just b)  -> Just b
    (Just a, Just b)   -> Just (evidenceMeet a b)

-- ---------------------------------------------------------------------------
-- OBLIG-PBT-5a (v0.10.7): joint PBT witness detection
-- ---------------------------------------------------------------------------
--
-- A ':subjects [f g …]' lift writes one EvidenceRecord per declared subject
-- ('PBT.hs:processRun' OBLIG-PBT-4 branch), each sharing the same
-- canonical-property-body hash via 'erPbtWitnesses'. The 2026-05-23 triage
-- (`docs/design/critique-2026-05-23-triage.md` row 8b) calls this
-- joint-evidence over-credit: N subjects each contribute +1 to the scalar
-- 'tested' count from a single property body. v0.10.7 excludes joint-only
-- evidence from the scalar count (demotes DLTested → DLAsserted at classify
-- time) while preserving the raw EvidenceRecord on the entry for JSON emit.
-- The clean fix (OBLIG-PBT-5b) introduces a 'tested-joint' display level
-- and bumps 'trust_report_version'; that is explicitly post-freeze. Until
-- then, the v0.10.7 patch ships under the additive (no version bump)
-- constraint by demoting to an existing slot.

-- | Hash 'h' is joint iff it appears in 'erPbtWitnesses' of post-clause
-- EvidenceRecords belonging to two or more distinct subject names. Pre-
-- clause witnesses do not exist (PBT-Lift is post-only per
-- 'LLMLL.md §4.4.5'), so we only consult 'csPost'.
computeJointHashes :: Map Name ContractStatus -> Set Text
computeJointHashes allCS =
  let pairs = Map.foldlWithKey' (\acc name cs ->
                case csPost cs of
                  Just er -> [(pwHash w, name) | w <- erPbtWitnesses er] ++ acc
                  Nothing -> acc) [] allCS
      byHash = Map.fromListWith Set.union [(h, Set.singleton n) | (h, n) <- pairs]
  in Map.keysSet (Map.filter (\subjects -> Set.size subjects >= 2) byHash)

-- | Build the (hash, [subjects]) emit groups for 'trJointWitnesses'. Subjects
-- are sorted for deterministic output.
buildJointWitnessGroups :: Map Name ContractStatus -> Set Text -> [(Text, [Name])]
buildJointWitnessGroups allCS jointHashes =
  let pairs = Map.foldlWithKey' (\acc name cs ->
                case csPost cs of
                  Just er -> [(pwHash w, name)
                             | w <- erPbtWitnesses er
                             , Set.member (pwHash w) jointHashes ] ++ acc
                  Nothing -> acc) [] allCS
      grouped = Map.fromListWith Set.union [(h, Set.singleton n) | (h, n) <- pairs]
  in sortOn fst [(h, Set.toAscList ns) | (h, ns) <- Map.toList grouped]

-- | Mark an entry as joint-post-witness iff its post-clause evidence has
-- non-empty 'erPbtWitnesses' AND every hash on that record is in the
-- joint-hash set. The "every" predicate (not "any") is load-bearing: if a
-- subject is also tested by a solo property, the solo witness's hash is
-- absent from 'jointHashes', so the entry is not demoted. This preserves
-- the +1 credit for subjects that earn it independently of the joint lift.
markJointPostWitness :: Set Text -> TrustEntry -> TrustEntry
markJointPostWitness jointHashes e =
  let isJoint = case tePost e of
        Nothing -> False
        Just er ->
          let ws = erPbtWitnesses er
          in case erDisplayLevel er of
               DLTested _ -> not (null ws)
                          && all (\w -> Set.member (pwHash w) jointHashes) ws
               _          -> False
  in e { teJointPostWitness = isJoint }

-- | Apply the OBLIG-PBT-5a demotion to a classified level. DLTested entries
-- whose 'teJointPostWitness' flag is set classify as DLAsserted instead,
-- so the scalar 'tested' count excludes joint-only credit. All other
-- levels and entries pass through unchanged.
demoteJointTested :: TrustEntry -> Maybe DisplayLevel -> Maybe DisplayLevel
demoteJointTested e (Just (DLTested _)) | teJointPostWitness e = Just DLAsserted
demoteJointTested _ lvl                                        = lvl

-- | COVERAGE-TIER: the single per-function tier notion the summary classifies
-- on. TRUST-PRE (Position B): the post-side effective level ('teEffectivePostLevel',
-- already met against transitive callees' posts and excluding 'csPre'), falling
-- back to the own raw post when no effective level was computed, then joint-tested
-- demoted (OBLIG-PBT-5a). This is the value that produces the trust-report
-- 'verified'/'contract-checked'/'tested'/'asserted' summary — 'computeSummary'
-- and the JSON 'effective_level' both go through it, and 'SpecCoverage' consumes
-- it (via Main) so '--spec-coverage' tiers agree with '--trust-report' by
-- construction rather than by a parallel recount.
entryHeadlineLevel :: TrustEntry -> Maybe DisplayLevel
entryHeadlineLevel e = demoteJointTested e $ case teEffectivePostLevel e of
                         Just lvl -> Just lvl
                         Nothing  -> fmap erDisplayLevel (tePost e)

-- ---------------------------------------------------------------------------
-- TRUST-PRE (Part 2): caller-obligation axis
-- ---------------------------------------------------------------------------
--
-- The 'requires' predicate a caller must establish to invoke a function
-- soundly. Sourced from the function's OWN 'csPre' contract (the same 'FQPred'
-- the per-call-site obligation reads in 'FixpointEmit.collectCallPreObligations'
-- — this is the per-FUNCTION-contract dual), NOT the caller-side 'erCallPreFns'.
--
-- An obligation is on F's axis iff:
--   (declares)   F declares the pre as 'requires'; OR
--   (transitive) F calls a callee C whose pre F neither discharges (a SAFE
--                call-pre VC) nor lifts to its own 'requires'.
--
-- SOUNDNESS (TRUST-PRE Rev 3, rule 5): the (transitive) disjunct is reachable
-- ONLY for non-strict-core F. Inside the strict-verified core a body-faithful F
-- emits a PROVE-polarity call-pre VC for every callee pre ('FixpointEmit.hs:617')
-- gated SAFE/UNSAFE by the solver; an undischarged callee pre makes that VC
-- UNSAFE, so F is refuted and never reaches 'verified'. We approximate "F
-- discharged C's pre" by "F is itself verified (body-faithful post)": a verified
-- F necessarily discharged (or assume-guarantee-lifted) every callee pre on its
-- proven paths, so it carries no escaped transitive obligation. A non-verified F
-- (body fell back → no call-pre VC emitted) may carry one — which is exactly the
-- non-strict-core case. If a verified F were ever observed carrying a transitive
-- obligation, that would be a call-pre-VC soundness gap, not a reporting bug.

-- | TRUST-PRE: render a contract predicate to its s-expr surface form
-- (e.g. @(>= balance amount)@). Mirrors the LLMLL surface syntax so the
-- 'requires' a consumer reads matches what the author wrote.
renderRequiresPredicate :: Expr -> Text
renderRequiresPredicate = go
  where
    go (ELit l)            = renderLit l
    go (EVar n)            = n
    go (EOp op args)       = sexpr op args
    go (EApp f args)       = sexpr f args
    go (EPair a b)         = "(pair " <> go a <> " " <> go b <> ")"
    go (EIf c t e)         = "(if " <> go c <> " " <> go t <> " " <> go e <> ")"
    go (EAwait e)          = "(await " <> go e <> ")"
    -- Predicates rarely contain the remaining shapes; fall back to a compact
    -- show so the field is never silently empty for an exotic pre.
    go other               = T.pack (show other)
    sexpr h []   = "(" <> h <> ")"
    sexpr h as   = "(" <> h <> " " <> T.intercalate " " (map go as) <> ")"
    renderLit (LitInt n)    = T.pack (show n)
    renderLit (LitFloat f)  = T.pack (show f)
    renderLit (LitString s) = "\"" <> s <> "\""
    renderLit (LitBool b)   = if b then "true" else "false"
    renderLit LitUnit       = "()"

-- | TRUST-PRE: shared JSON object for one obligation — used by BOTH the
-- trust-report emit and the '.verified.json' persistence so the two surfaces
-- never drift. Carries the predicate, not a count/name.
callerObligationJson :: CallerObligation -> Value
callerObligationJson o = object
  [ "fn"       .= coObFn o
  , "requires" .= coObRequires o
  ]

-- | TRUST-PRE: populate every entry's 'teCallerObligations'.
--
-- 'declaredReqs' maps each (qualified) function name to the rendered 'requires'
-- of its own pre clause (from the live source contract). 'isVerified' is True
-- for a function whose own post is body-faithful 'verified' — the gate for the
-- (transitive) disjunct: a verified F discharged its callee pres, so it carries
-- no escaped obligation (the strict-core backstop, see the note above).
markCallerObligations :: Map Name Text -> [TrustEntry] -> [TrustEntry]
markCallerObligations declaredReqs entries = map mark entries
  where
    -- The gate is F's OWN body-faithful verified post — NOT 'teEffectivePostLevel'
    -- (which meets in transitive callees and would drag a verified F down to
    -- 'asserted' merely because a callee is asserted, a call-graph concern, not a
    -- statement about whether F discharged its own call-pre VCs). A body-faithful
    -- verified F necessarily emitted a PROVE-polarity call-pre VC for every callee
    -- pre and the solver returned SAFE; so it carries no escaped obligation.
    isVerified e = case tePost e of
                     Just er -> isVerifiedLevel (erDisplayLevel er) && erBodyFaithful er
                     Nothing -> False
    mark e =
      let -- (declares): F's own pre, if any.
          own = case Map.lookup (teName e) declaredReqs of
                  Just req -> [CallerObligation (teName e) req]
                  Nothing  -> []
          -- (transitive): callee pres F neither discharges nor lifts. Gated to
          -- the non-strict-core case: only a NON-verified F can carry one (a
          -- verified F's call-pre VCs were all SAFE). 'F lifts C's pre to its
          -- own requires' is folded out here — when F declares any pre we treat
          -- its own clause as the lift surface, so we do not also re-list a
          -- callee whose pre F republishes; the conservative inclusion is sound
          -- (an extra honest obligation never under-warns).
          transitive
            | isVerified e = []          -- strict-core / verified: no escaped obligation
            | otherwise =
                [ CallerObligation (tdName d) req
                | d <- teDeps e
                , Just req <- [Map.lookup (tdName d) declaredReqs]
                , tdName d /= teName e
                ]
          combined = own ++ [ o | o <- transitive, coObFn o `notElem` map coObFn own ]
      in e { teCallerObligations = combined }

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

computeSummary :: [TrustEntry] -> TrustSummary
computeSummary entries =
  -- TRUST-PRE (Part 1, Position B summary-only): classify on the POST-side
  -- effective level ('teEffectivePostLevel'), which already excludes 'csPre'
  -- and meets the post against transitive callees. A precondition no longer
  -- floors a function's tier — but a WEAK post is never ignored: when the body
  -- fell back (post 'asserted'/'contract_checked'), 'teEffectivePostLevel' is
  -- that weak level and the function classifies there. The change is strictly
  -- "stop meeting in 'csPre'," never "promote a weak post." TRUST-PRE
  -- (transitive-callee fix) extended this to the CALL GRAPH: 'teEffectivePostLevel'
  -- now meets the post against the transitive callees' POSTS (not their pre-
  -- inclusive 'effectiveLevel'), so a caller that discharged a pre-bearing
  -- callee's pre no longer floors via that callee's pre. 'teEffectiveLevel'
  -- converged onto the same post-side value (its 'callee_tier' / 'TrustChannel'
  -- consumers want the post-side notion); there is no longer a pre-inclusive
  -- whole-function meet anywhere.
  -- OBLIG-PBT-5a: demote joint-only DLTested to DLAsserted at classify time.
  let classify e = entryHeadlineLevel e  -- COVERAGE-TIER: shared per-function tier
      verified = length [e | e <- entries, isVer (classify e)]
      contractChecked = length [e | e <- entries, isCC (classify e)]
      tested   = length [e | e <- entries, isTst (classify e)]
      asserted = length [e | e <- entries, isAss (classify e)]
      none     = length [e | e <- entries, classify e == Nothing]
      drifts   = sum (map (length . teDrifts) entries)
  in TrustSummary verified contractChecked tested asserted none drifts
  where
    isVer (Just dl) = isVerifiedLevel dl
    isVer _         = False
    isCC (Just DLContractChecked{}) = True
    isCC _                          = False
    isTst (Just DLTested{}) = True
    isTst _                 = False
    isAss (Just DLAsserted) = True
    isAss _                 = False

-- | v0.10.4 (R6d): Aggregate per-function effective tiers into a six-Int profile.
--
-- Classification uses the same path as 'computeSummary' — the POST-side
-- effective level ('teEffectivePostLevel', the post met against the transitive
-- callees' posts), falling back to the local 'csPost' level when enrichment did
-- not populate the field.
--
-- Diamond meet (LLMLL.md:344) is honored: an entry whose effective level is
-- DLAsserted because pre and post sit in incomparable diamond branches
-- increments 'tpAsserted', not both 'tpContractChecked' and 'tpTested'.
--
-- 'tpProved' is zero by construction in the current emit: there is no
-- DLProved constructor in 'DisplayLevel'. The field is reserved for a future
-- Lean-discharged tier.
aggregateTiers :: [TrustEntry] -> TierProfile
aggregateTiers entries =
  -- TRUST-PRE (Position B): classify on the POST-side effective level, identical
  -- to 'computeSummary'. Neither the function's own 'csPre' nor its transitive
  -- callees' pres floor its tier (all on the caller_obligations axis); a weak
  -- post — own or inherited from a callee — is still respected.
  -- OBLIG-PBT-5a: demote joint-only DLTested to DLAsserted before classify.
  let classify e = entryHeadlineLevel e  -- COVERAGE-TIER: shared per-function tier
  in classifyToProfile classify entries

-- | OBLIG-PBT-3: per-pre-clause tier profile. Each entry contributes by
-- its 'teEffectivePreLevel' (pre clause meets transitive-callee effective);
-- absent pre clauses increment 'tpNoContract'. Distinguished from
-- 'aggregateTiers' which meets pre and post per entry — the per-clause
-- split surfaces a 'DLTested' post that would otherwise be hidden behind
-- a 'DLAsserted' pre under the per-function meet (proposal §9, Gap 4).
aggregateTiersPre :: [TrustEntry] -> TierProfile
aggregateTiersPre entries =
  let classify e = case teEffectivePreLevel e of
                     Just lvl -> Just lvl
                     Nothing  -> fmap erDisplayLevel (tePre e)
  in classifyToProfile classify entries

-- | OBLIG-PBT-3: per-post-clause tier profile. Symmetric to
-- 'aggregateTiersPre'. PBT-derived 'DLTested' evidence is structurally
-- post-only (proposal §4 side condition 6); this aggregate is the one the
-- downstream H1-Assurance discriminator should consume.
aggregateTiersPost :: [TrustEntry] -> TierProfile
aggregateTiersPost entries =
  -- OBLIG-PBT-5a: demote joint-only DLTested to DLAsserted before classify.
  -- This is the aggregate the H1-Assurance discriminator consumes; joint
  -- credit must not inflate 'tpTested' here.
  let classify e = entryHeadlineLevel e  -- COVERAGE-TIER: shared per-function tier
  in classifyToProfile classify entries

-- | Shared classification kernel for the three aggregate functions.
-- Honors the diamond meet at 'LLMLL.md:344': an entry whose classification
-- is 'DLAsserted' because pre and post sit in incomparable diamond branches
-- increments 'tpAsserted', not both 'tpContractChecked' and 'tpTested'.
classifyToProfile :: (TrustEntry -> Maybe DisplayLevel) -> [TrustEntry] -> TierProfile
classifyToProfile classify entries =
  let verified        = length [e | e <- entries, isVer (classify e)]
      contractChecked = length [e | e <- entries, isCC  (classify e)]
      tested          = length [e | e <- entries, isTst (classify e)]
      asserted        = length [e | e <- entries, isAss (classify e)]
      noContract      = length [e | e <- entries, classify e == Nothing]
  in TierProfile
       { tpVerified        = verified
       , tpProved          = 0
       , tpContractChecked = contractChecked
       , tpTested          = tested
       , tpAsserted        = asserted
       , tpNoContract      = noContract
       }
  where
    isVer (Just dl) = isVerifiedLevel dl
    isVer _         = False
    isCC (Just DLContractChecked{}) = True
    isCC _                          = False
    isTst (Just DLTested{}) = True
    isTst _                 = False
    isAss (Just DLAsserted) = True
    isAss _                 = False

-- ---------------------------------------------------------------------------
-- Formatting (human-readable)
-- ---------------------------------------------------------------------------

formatTrustReport :: TrustReport -> Text
formatTrustReport report =
  let header = "Trust Report"
      separator = T.replicate 60 "─"
      entryLines = concatMap formatEntry (sortOn teName (trEntries report))
      suppressionLines = formatSuppressions (trSuppressions report)
      summaryLines = formatSummary (trSummary report)
      staleLines = case trStaleDowngrades report of
                     []  -> []
                     dgs -> "" : "PBT staleness:" : map ("  ⚠ " <>) dgs
      -- OBLIG-PBT-5a: surface joint witnesses in text mode so reviewers can
      -- see which subjects share a property body before scrutinising the
      -- summary's 'tested' delta.
      jointLines = case trJointWitnesses report of
                     []  -> []
                     grs -> "" : "Joint PBT witnesses:" :
                            map (\(h, subs) -> "  ⊗ " <> shortHash h
                                            <> " ⇒ " <> T.intercalate ", " subs) grs
      -- REC-PARTIAL-MARK: surface recursive-cycle members whose posts hold only
      -- at partial correctness (termination unverified), matching the report-level
      -- section style of 'staleLines'/'jointLines' (formatEntry has no report handle).
      partialLines = case Set.toList (trPartialFns report) of
                       []  -> []
                       fns -> "" : "Termination-unverified (recursive, partial correctness):" :
                              map ("  ↻ " <>) (sortOn id fns)
  in T.unlines ([header, separator] ++ entryLines ++ suppressionLines ++ staleLines ++ jointLines ++ partialLines ++ [separator] ++ summaryLines)

-- | Display the leading 12 hex chars after the 'sha256:' prefix; the full
-- hash remains in the JSON emit.
shortHash :: Text -> Text
shortHash h
  | "sha256:" `T.isPrefixOf` h = "sha256:" <> T.take 12 (T.drop 7 h) <> "…"
  | otherwise                  = T.take 16 h <> "…"

formatEntry :: TrustEntry -> [Text]
formatEntry e =
  let preLbl  = maybe "—" (dlLabel . erDisplayLevel) (tePre e)
      postLbl = maybe "—" (dlLabel . erDisplayLevel) (tePost e)
      line1   = "  " <> teName e <> ":"
      line2   = "    pre:  " <> preLbl <> "  |  post: " <> postLbl
      sourceLines = catMaybes
        [ (tePre e >>= erSource) >>= \s -> Just ("    source (pre):  " <> s)
        , (tePost e >>= erSource) >>= \s -> Just ("    source (post): " <> s)
        ]
      depLines = map (\d -> "    ↳ calls " <> tdName d <> " (pre: "
                           <> maybe "—" dlLabel (tdPreLevel d)
                           <> ", post: " <> maybe "—" dlLabel (tdPostLevel d) <> ")")
                     (teDeps e)
      driftLines = map ("    ⚠ " <>) (teDrifts e)
  in [line1, line2] ++ sourceLines ++ depLines ++ driftLines

formatSummary :: TrustSummary -> [Text]
formatSummary s =
  [ "Summary:"
  , "  verified:         " <> tshow (tsVerified s)
  , "  contract-checked: " <> tshow (tsContractChecked s)
  , "  tested:           " <> tshow (tsTested s)
  , "  asserted:         " <> tshow (tsAsserted s)
  , "  no contract:      " <> tshow (tsNone s)
  ] ++ if tsDrifts s > 0
       then ["  ⚠ epistemic drifts: " <> tshow (tsDrifts s)]
       else []

-- | v0.6: Format weakness-ok suppressions section.
formatSuppressions :: [(Name, Text)] -> [Text]
formatSuppressions [] = []
formatSuppressions supps =
  ["", "Intentional Underspecification:"]
  ++ map (\(name, reason) -> "  ⊘ " <> name <> " — \"" <> reason <> "\"") supps

-- ---------------------------------------------------------------------------
-- Formatting (JSON)
-- ---------------------------------------------------------------------------

-- | JSON emit for the trust report. Emit-only — no parser ingests this; round-trip
-- is JSON-level (re-decode as 'Value'), not Haskell-level.
--
-- BUG-5 (v0.14.3): was 'T.pack . BLC.unpack . encode' -- 'encode' produces
-- UTF-8 bytes, but 'Data.ByteString.Lazy.Char8.unpack' reinterprets each byte
-- as a Latin-1 codepoint (not a UTF-8 decode), so any multi-byte UTF-8
-- sequence (e.g. '§' -> 0xC2 0xA7) becomes two separate high codepoints in
-- the resulting Text; re-encoding that Text as UTF-8 downstream then
-- double-encodes it into mojibake ('§' -> "Â§"). 'encodeToLazyText' builds
-- Text directly from the aeson 'Value' with no byte-level round-trip, so it
-- cannot suffer this class of corruption.
formatTrustReportJson :: TrustReport -> Text
formatTrustReportJson report =
  TL.toStrict . encodeToLazyText $ object
    [ "trust_report_version" .= trustReportEmitVersion
    , "entries"      .= map entryJson (trEntries report)
    , "summary"      .= summaryJson (trSummary report)
    , "tier_profile"      .= tierProfileJson (trTierProfile     report)
    -- OBLIG-PBT-3 (1.1.0): parallel per-clause aggregates. Existing v1.0.0
    -- consumers ignore unknown keys; new consumers may read either profile.
    , "tier_profile_pre"  .= tierProfileJson (trTierProfilePre  report)
    , "tier_profile_post" .= tierProfileJson (trTierProfilePost report)
    , "suppressions"      .= map suppJson (trSuppressions report)
    , "stale_downgrades"  .= trStaleDowngrades report
    -- OBLIG-PBT-5a (v0.10.7): additive joint-witness emit. No
    -- 'trust_report_version' bump per the 2026-05-23 critique-triage
    -- routing; existing v1.1.0 consumers ignore the new key.
    , "joint_pbt_witnesses" .= map jointWitnessJson (trJointWitnesses report)
    -- INT-1 (v0.10.8): top-level list of body-faithful functions whose verified
    -- evidence carries unbounded-Int arithmetic. Strict-verified-core consumers
    -- refuse these; non-strict consumers see the flag per-entry below.
    -- 'trust_report_version' stays "1.1.0" per the additive-field precedent at
    -- :712 — readers ignore unknown keys, the JSON shape grows monotonically.
    , "overflow_tainted_fns" .= [ teName e
                                | e <- trEntries report
                                , taintedFns e
                                ]
    -- VERIFY-RPT-1 (1.3.0): top-level list of refuted functions (body VC the
    -- solver reported UNSAFE). Verify-time only; empty on a solver-less render.
    , "refuted_fns" .= Set.toList (trRefutedFns report)
    -- REC-DESCENT (v0.14.25): measure-not-decreasing functions (verify-time only).
    , "measure_not_decreasing_fns" .= Set.toList (trMeasureNotDecreasingFns report)
    -- REC-PARTIAL-MARK (1.5.0): recursive-cycle members verified only at partial
    -- correctness (termination unverified). Derived from the call-graph SCC, so
    -- unlike 'refuted_fns' it is populated even on a solver-less render.
    , "partial_fns" .= Set.toList (trPartialFns report)
    -- F-001 (adv-spec-weaken-0): module-level '(spec-entropy :intentional)'
    -- density + threshold + fired flag. No 'trust_report_version' bump, same
    -- additive-field precedent as 'joint_pbt_witnesses'/'overflow_tainted_fns'
    -- above — existing consumers ignore the new key.
    , "over_annotation" .= overAnnotationJson (trOverAnnotation report)
    ]
  where
    overAnnotationJson oai = object
      [ "ratio"     .= oaiRatio oai
      , "threshold" .= oaiThreshold oai
      , "warning"   .= oaiFired oai
      ]
    -- INT-1: an entry is overflow-tainted at the report level iff any of its
    -- evidence records carries the flag. Today the flag only lives on the
    -- DLVerified body-faithful post (the only site that emits it in Main.hs);
    -- the predicate is written generally so future placements (e.g. pre on a
    -- call-site VC) compose naturally.
    taintedFns e = any erOverflowTainted (maybeERs e)
    maybeERs e   = maybeToList (tePre e) ++ maybeToList (tePost e)
    -- TRUST-PRE: the headline tier = the Position-B post-side level, with the
    -- OBLIG-PBT-5a joint-only demotion applied, identical to 'computeSummary'.
    headlineLevel e = entryHeadlineLevel e  -- COVERAGE-TIER: shared per-function tier
    entryJson e = object $
      [ "name"       .= teName e
      , "pre_level"  .= fmap (dlLabel . erDisplayLevel) (tePre e)
      , "post_level" .= fmap (dlLabel . erDisplayLevel) (tePost e)
      , "dependencies" .= map depJson (teDeps e)
      , "drifts"     .= teDrifts e
      ] ++
      maybe [] (\s -> ["pre_source" .= s]) (tePre e >>= erSource) ++
      maybe [] (\s -> ["post_source" .= s]) (tePost e >>= erSource) ++
      -- TRUST-PRE (Position B): the consumer-facing 'effective_level' HEADLINE is
      -- the post-side tier (same classification the summary counts), so a
      -- pre-bearing post-verified function reads 'verified' here — and so does a
      -- caller that discharged that callee's pre, since the transitive-callee meet
      -- now folds the callee's POST, not its pre-inclusive level. Neither the own
      -- pre nor a transitive callee's pre floors this. (Refutation propagation is
      -- independent: 'refutedClosure' keys on the call graph 'teDeps', not on this
      -- tier, so 'depends-on-refuted' is unaffected by the pre exclusion.)
      maybe [] (\l -> ["effective_level" .= dlLabel l]) (headlineLevel e) ++
      -- OBLIG-PBT-5a: per-entry joint-post flag, emitted only when true.
      [ "joint_pbt_witness" .= True | teJointPostWitness e ] ++
      -- INT-1 (v0.10.8): per-entry overflow-taint flag, emitted only when
      -- True on any clause. Mirrors the joint-witness emit shape (only-on-true)
      -- so unchanged trust-report JSON for non-tainting fns stays byte-identical.
      [ "overflow_tainted" .= True | taintedFns e ] ++
      -- VERIFY-RPT-1 (1.3.0): per-entry refuted flag, emitted only when true,
      -- mirroring the only-on-true shape so non-refuted JSON stays byte-identical.
      [ "refuted" .= True | Set.member (teName e) (trRefutedFns report) ] ++
      -- REC-PARTIAL-MARK (1.5.0): per-entry partial-correctness flag, only-on-true,
      -- mirroring the 'refuted' shape so non-recursive entries stay byte-identical.
      -- Orthogonal to 'refuted'/'overflow_tainted' — a refuted recursive fn shows
      -- both. Informational; does not touch 'effective_level'.
      [ "termination_unverified" .= True | Set.member (teName e) (trPartialFns report) ] ++
      [ "measure_not_decreasing" .= True | Set.member (teName e) (trMeasureNotDecreasingFns report) ] ++
      -- TRUST-PRE (1.4.0): per-entry caller-obligation axis. Emission discipline
      -- is the OPPOSITE of 'refuted': present whenever a 'requires' exists, on
      -- EVERY path (solver-less, sidecar-reload), and persisted. The co-located
      -- 'carries_caller_obligations' boolean is the cheapest single-field
      -- self-scoping read — it exposes the conditionality without touching the
      -- 'effective_level' tier (which stays 'verified'). The predicate list sits
      -- one field deeper for the consumer that needs to discharge it.
      [ "carries_caller_obligations" .= not (null (teCallerObligations e)) ] ++
      [ "caller_obligations" .= map callerObligationJson (teCallerObligations e)
      | not (null (teCallerObligations e)) ] ++
      -- LT-CDP (v0.11): per-entry discriminative_axis. Emitted only on
      -- contracted entries; populated from 'trCDP report' when present,
      -- otherwise a single 'not-requested' warning so consumers see a uniform
      -- shape (proposal §5). The block is additive over v1.1.0 — consumers
      -- ignoring 'discriminative_axis' continue to work.
      [ "discriminative_axis" .= cdpAxisJson (Map.lookup (teName e) (trCDP report)) (Map.lookup (teName e) (trDecompMeet report))
      | tePre e /= Nothing || tePost e /= Nothing
      ] ++
      -- LT-PPR (v0.11): predicate enrichment fields — emitted only when a
      -- predicate-carrying ?proof-required clause is present. Additive over
      -- v1.2.0; consumers ignoring these fields continue to work.
      maybe [] (\f -> ["pre_predicate_form" .= f])  (tePre e  >>= erPredicateForm) ++
      maybe [] (\t -> ["pre_predicate_text" .= t])  (tePre e  >>= erPredicateText) ++
      maybe [] (\f -> ["post_predicate_form" .= f]) (tePost e >>= erPredicateForm) ++
      maybe [] (\t -> ["post_predicate_text" .= t]) (tePost e >>= erPredicateText) ++
      [ "pre_runtime_check_emitted"  .= True | maybe False erRuntimeCheckEmitted (tePre e)  ] ++
      [ "post_runtime_check_emitted" .= True | maybe False erRuntimeCheckEmitted (tePost e) ]
    depJson d = object
      [ "name"       .= tdName d
      , "pre_level"  .= fmap dlLabel (tdPreLevel d)
      , "post_level" .= fmap dlLabel (tdPostLevel d)
      ]
    summaryJson s = object
      [ "verified"         .= tsVerified s
      , "contract_checked" .= tsContractChecked s
      , "tested"           .= tsTested s
      , "asserted"         .= tsAsserted s
      , "no_contract"      .= tsNone s
      , "drifts"           .= tsDrifts s
      ]
    -- v0.10.4 (R6d): six-Int tier-count aggregate, never scalarized.
    tierProfileJson tp = object
      [ "verified"         .= tpVerified tp
      , "proved"           .= tpProved tp
      , "contract_checked" .= tpContractChecked tp
      , "tested"           .= tpTested tp
      , "asserted"         .= tpAsserted tp
      , "no_contract"      .= tpNoContract tp
      ]
    suppJson (name, reason) = object
      [ "name"   .= name
      , "reason" .= reason
      ]
    -- OBLIG-PBT-5a: emit one object per joint-witness grouping. 'subjects'
    -- lists the names whose post-clause evidence carries this hash; the
    -- order is deterministic (ascending) per 'buildJointWitnessGroups'.
    jointWitnessJson (h, subs) = object
      [ "hash"     .= h
      , "subjects" .= subs
      ]
    -- LT-CDP (v0.11): per-function discriminative_axis JSON block per
    -- proposal §5. 'Nothing' input means '--cdp' was not requested for this
    -- function; the emit substitutes a single 'not-requested' warning so the
    -- shape is uniform and consumers do not need to special-case the absence
    -- of the field. 'Just r' input populates the full block with score,
    -- candidate counts, distinguishing inputs, and typed warnings.
    -- Cascade L3(d) (Rev 8): the 'unvouched_cdp_meet' block nested inside each
    -- per-entry 'discriminative_axis'. Uniform shape (a "none" quality label +
    -- zeroed coverage when '--cdp' was not requested or no meet applies),
    -- matching the block's uniform-shape discipline.
    decompMeetJson mum = object
      [ "meet" .= object
          [ "label" .= maybe ("none" :: Text) dqLabel mq
          , "score" .= (mq >>= dqNumScore) ]
      , "weakest_fn"       .= (mum >>= umWeakestFn)
      , "floored_by_cycle" .= maybe False umFlooredByCycle mum
      , "coverage" .= object
          [ "measured"         .= maybe 0 umMeasured        mum
          , "unmeasured"       .= maybe 0 umUnmeasured      mum
          , "in_scope_total"   .= maybe 0 umInScopeTotal    mum
          , "excluded_vouched" .= maybe 0 umExcludedVouched mum
          , "excluded_fns"     .= maybe [] umExcludedFns    mum ] ]
      where mq = mum >>= umQualityMeet
    cdpAxisJson Nothing mum = object
      [ "score"                      .= Null
      , "basis"                      .= ("not-measured" :: Text)
      , "candidate_count"            .= (0 :: Int)
      , "satisfying_candidate_count" .= (0 :: Int)
      , "distinct_observed_behavior_count" .= (0 :: Int)
      , "excluded_candidate_count"   .= (0 :: Int)
      , "distinguishing_inputs"      .= ([] :: [Text])
      , "spec_entropy_annotation"    .= ("strict" :: Text)
      , "warnings"                   .= [cdpWarningLabel WarnNotRequested]
      -- CDP deep-dive Rev 5 (item 2): additive headline field — the typed
      -- flag/witness a consumer should read first, per the professor's
      -- flag-not-score recommendation; the graded 'score' is advisory.
      , "headline"                   .= cdpWarningLabel WarnNotRequested
      , "unvouched_cdp_meet"         .= decompMeetJson mum
      ]
    cdpAxisJson (Just r) mum = object
      [ "score"                      .= cdpScore r
      , "basis"                      .= ("observational-candidate-set" :: Text)
      , "candidate_count"            .= cdpCandidateCount r
      , "satisfying_candidate_count" .= cdpSatisfyingCount r
      -- CDP deep-dive Rev 5 (item 5): 'candidate_count' narrows post-fix to
      -- mean "type-compatible AND body-VC-translatable"; this field exposes
      -- how many type-compatible candidates were excluded as unreliable, so
      -- cross-version comparison doesn't need to infer the narrowing from
      -- 'basis' alone (which intentionally does not change — Ω's identity
      -- is unchanged, only which members were reliably checkable this run).
      , "excluded_candidate_count"   .= cdpExcludedCandidateCount r
      , "distinct_observed_behavior_count" .= cdpDistinctBehaviorCount r
      , "distinguishing_inputs"      .= cdpDistinguishingInputs r
      , "spec_entropy_annotation"    .= specEntropyLabel (cdpSpecEntropyAnnotation r)
      , "warnings"                   .= map cdpWarningLabel (cdpWarnings r)
      -- CDP deep-dive Rev 5 (item 2): first warning when any fired, else
      -- "measured" for a genuine 1<=s<b loose-contract score with no warning.
      , "headline"                   .= case cdpWarnings r of
                                           (w : _) -> cdpWarningLabel w
                                           []      -> "measured" :: Text
      , "unvouched_cdp_meet"         .= decompMeetJson mum
      ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = T.pack . show
