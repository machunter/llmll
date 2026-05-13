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
  , buildTrustReport
  , formatTrustReport
  , formatTrustReportJson
  , effectiveLevel     -- v0.10: for obligation trust labels (F9)
  , aggregateTiers     -- v0.10.4: fixed-arity tier-count profile (R6d)
  , aggregateTiersPre  -- OBLIG-PBT-3: per-pre-clause tier-count profile
  , aggregateTiersPost -- OBLIG-PBT-3: per-post-clause tier-count profile
  , liveCheckHashes    -- OBLIG-PBT-3: live property-body SHA set
  , trustReportEmitVersion
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, catMaybes)
import Data.List (nub, sortOn, foldl')
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Aeson (encode, object, (.=), Value(..))
import qualified Data.ByteString.Lazy.Char8 as BLC

import LLMLL.Syntax
import LLMLL.Module (mergeCS)
import LLMLL.PBT (canonicalPropBodyHash)

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
  , teEffectiveLevel :: Maybe DisplayLevel    -- ^ v0.8.1b: meet(self, transitive deps)
  -- OBLIG-PBT-3: per-clause effective levels — each clause meets its own ER
  -- with the transitive-callee effective level. Nothing iff the clause is
  -- absent in the source contract.
  , teEffectivePreLevel  :: Maybe DisplayLevel
  , teEffectivePostLevel :: Maybe DisplayLevel
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
trustReportEmitVersion :: Text
trustReportEmitVersion = "1.1.0"

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
      allCS       = Map.unionWith mergeCS sidecar' baseCS
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
      -- Compute summary
      summary = computeSummary enrichedEntries
      -- v0.10.4 (R6d): tier-count profile over the same enriched entries
      tierProfile = aggregateTiers enrichedEntries
      -- OBLIG-PBT-3: parallel per-clause aggregates (proposal §9)
      tierProfilePre  = aggregateTiersPre  enrichedEntries
      tierProfilePost = aggregateTiersPost enrichedEntries
  in TrustReport
       { trEntries         = enrichedEntries
       , trSummary         = summary
       , trSuppressions    = suppressions
       , trTierProfile     = tierProfile
       , trTierProfilePre  = tierProfilePre
       , trTierProfilePost = tierProfilePost
       , trStaleDowngrades = stales
       }

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
                in (Just (er { erDisplayLevel = DLAsserted, erPbtWitnesses = [] }), [diag])

-- | v0.6: Extract weakness-ok suppressions from statements.
-- Deduplicates by name (WO-3 idempotence).
extractSuppressions :: [Statement] -> [(Name, Text)]
extractSuppressions stmts = nubBy' [(n, r) | SWeaknessOk n r <- stmts]
  where nubBy' = nub

-- | Collect contract statuses from all cached modules + entry statements.
collectAllContractStatus :: ModuleCache -> [Statement] -> Map Name ContractStatus
collectAllContractStatus cache entryStmts =
  let cacheCS = Map.foldlWithKey' (\acc path menv ->
        let prefix = T.intercalate "." path <> "."
            qualified = Map.mapKeys (prefix <>) (meContractStatus menv)
        in Map.union qualified acc) Map.empty cache
      entryCS = Map.fromList $ mapMaybe extractCS entryStmts
  in Map.union entryCS cacheCS
  where
    extractCS (SDefLogic name _ _ c _)  = mkCS name c
    extractCS (SLetrec name _ _ c _ _)  = mkCS name c
    extractCS _                         = Nothing
    mkCS name c
      | contractPre c /= Nothing || contractPost c /= Nothing =
          Just (name, ContractStatus
            { csPre  = fmap (const (EvidenceRecord DLAsserted False Nothing [])) (contractPre c)
            , csPost = fmap (const (EvidenceRecord DLAsserted False Nothing [])) (contractPost c)
            , csAssumptions = []
            })
      | otherwise = Nothing

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
      -- Compute effective level = meet(self, all transitive callees)
      selfLevel = effectiveLevel ownCS
      calleeMinLevel = foldl' minLevel Nothing
        [ effectiveLevel cs
        | callee <- Set.toList transitiveCallees
        , Just cs <- [Map.lookup callee allCS]
        ]
      eff = case (selfLevel, calleeMinLevel) of
              (Nothing, _) -> Nothing
              (_, Nothing) -> selfLevel
              (Just s, Just c) -> Just (evidenceMeet s c)
      -- OBLIG-PBT-3: per-clause effective level (proposal §9).
      preLevel  = fmap erDisplayLevel (csPre ownCS)
      postLevel = fmap erDisplayLevel (csPost ownCS)
      effPre  = clauseEff preLevel  calleeMinLevel
      effPost = clauseEff postLevel calleeMinLevel
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
-- Summary
-- ---------------------------------------------------------------------------

computeSummary :: [TrustEntry] -> TrustSummary
computeSummary entries =
  -- v0.8.1b: use teEffectiveLevel for classification when available
  let classify e = case teEffectiveLevel e of
                     Just lvl -> Just lvl
                     Nothing  -> effectiveLevel (ContractStatus (tePre e) (tePost e) [])
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
-- Classification uses the same path as 'computeSummary' — 'teEffectiveLevel'
-- (meet of self pre/post and transitive callees), falling back to the local
-- ContractStatus meet when enrichment did not populate the field.
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
  let classify e = case teEffectiveLevel e of
                     Just lvl -> Just lvl
                     Nothing  -> effectiveLevel (ContractStatus (tePre e) (tePost e) [])
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
  let classify e = case teEffectivePostLevel e of
                     Just lvl -> Just lvl
                     Nothing  -> fmap erDisplayLevel (tePost e)
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
  in T.unlines ([header, separator] ++ entryLines ++ suppressionLines ++ staleLines ++ [separator] ++ summaryLines)

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
formatTrustReportJson :: TrustReport -> Text
formatTrustReportJson report =
  T.pack . BLC.unpack . encode $ object
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
    ]
  where
    entryJson e = object $
      [ "name"       .= teName e
      , "pre_level"  .= fmap (dlLabel . erDisplayLevel) (tePre e)
      , "post_level" .= fmap (dlLabel . erDisplayLevel) (tePost e)
      , "dependencies" .= map depJson (teDeps e)
      , "drifts"     .= teDrifts e
      ] ++
      maybe [] (\s -> ["pre_source" .= s]) (tePre e >>= erSource) ++
      maybe [] (\s -> ["post_source" .= s]) (tePost e >>= erSource) ++
      maybe [] (\l -> ["effective_level" .= dlLabel l]) (teEffectiveLevel e)
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

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = T.pack . show
