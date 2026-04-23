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
  , buildTrustReport
  , formatTrustReport
  , formatTrustReportJson
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, catMaybes)
import Data.List (nub, sortOn)
import Data.Aeson (encode, object, (.=), Value(..))
import qualified Data.ByteString.Lazy.Char8 as BLC

import LLMLL.Syntax

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A single function's trust entry in the report.
data TrustEntry = TrustEntry
  { teName       :: Name                  -- ^ Fully-qualified function name
  , tePreLevel   :: Maybe VerificationLevel
  , tePostLevel  :: Maybe VerificationLevel
  , tePreSource  :: Maybe Text            -- ^ v0.6.1: :source provenance on pre clause
  , tePostSource :: Maybe Text            -- ^ v0.6.1: :source provenance on post clause
  , teDeps       :: [TrustDependency]     -- ^ Cross-module calls with their trust levels
  , teDrifts     :: [Text]                -- ^ Epistemic drift warnings
  } deriving (Show, Eq)

-- | A dependency on another function with its trust level.
data TrustDependency = TrustDependency
  { tdName     :: Name                   -- ^ Callee function name (qualified)
  , tdPreLevel :: Maybe VerificationLevel
  , tdPostLevel :: Maybe VerificationLevel
  } deriving (Show, Eq)

-- | The complete trust report.
data TrustReport = TrustReport
  { trEntries      :: [TrustEntry]
  , trSummary      :: TrustSummary
  , trSuppressions :: [(Name, Text)]  -- ^ v0.6: (function name, reason) from SWeaknessOk
  } deriving (Show, Eq)

data TrustSummary = TrustSummary
  { tsProven   :: Int  -- ^ Functions with all clauses proven
  , tsTested   :: Int  -- ^ Functions with tested (but not proven) clauses
  , tsAsserted :: Int  -- ^ Functions with asserted clauses
  , tsNone     :: Int  -- ^ Functions with no contracts
  , tsDrifts   :: Int  -- ^ Total epistemic drift warnings
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Report Building
-- ---------------------------------------------------------------------------

-- | Build a trust report from a module cache and the entry-point statements.
-- For each function with contracts, identifies:
--   1. Its own verification level (from ContractStatus)
--   2. Which cross-module functions it calls (from the AST)
--   3. Whether those callees have lower trust levels (epistemic drift)
buildTrustReport :: ModuleCache -> [Statement] -> TrustReport
buildTrustReport cache entryStmts =
  let -- Collect all contract statuses: qualified names from cache + entry module
      allCS       = collectAllContractStatus cache entryStmts
      -- Collect all exports from cache for type-checking call resolution
      allExports  = collectAllExports cache
      -- Build entries for every function that has contracts
      entryModule = buildModuleEntries "" entryStmts allCS
      cacheEntries = concatMap (\(path, menv) ->
        buildModuleEntries (T.intercalate "." path <> ".") (meStatements menv) allCS
        ) (Map.toList cache)
      allEntries = entryModule ++ cacheEntries
      -- v0.6: collect weakness-ok suppressions
      suppressions = extractSuppressions entryStmts
      -- Compute summary
      summary = computeSummary allEntries
  in TrustReport allEntries summary suppressions

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
            { csPreLevel  = fmap (const VLAsserted) (contractPre c)
            , csPostLevel = fmap (const VLAsserted) (contractPost c)
            , csPreSource  = contractPreSource c
            , csPostSource = contractPostSource c
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
  let ownCS = Map.findWithDefault (ContractStatus Nothing Nothing Nothing Nothing) qname allCS
      -- Find all function calls in the body
      callees = nub $ extractCalls body
      -- Build dependencies for cross-module callees that have contract status
      deps = mapMaybe (\callee ->
        case Map.lookup callee allCS of
          Nothing -> Nothing
          Just cs -> Just (TrustDependency callee (csPreLevel cs) (csPostLevel cs))
        ) callees
      -- Compute epistemic drift: this function is "proven" but depends on non-proven
      drifts = computeDrifts qname ownCS deps
  in TrustEntry
       { teName       = qname
       , tePreLevel   = csPreLevel ownCS
       , tePostLevel  = csPostLevel ownCS
       , tePreSource  = csPreSource ownCS
       , tePostSource = csPostSource ownCS
       , teDeps       = deps
       , teDrifts     = drifts
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
-- Drift = a function's own contract is proven, but it depends on a callee
-- whose contract is not proven.
computeDrifts :: Name -> ContractStatus -> [TrustDependency] -> [Text]
computeDrifts fname ownCS deps =
  let ownLevel = effectiveLevel ownCS
  in case ownLevel of
       Just (VLProven _) ->
         -- Check each dependency: is any callee below proven?
         concatMap (\dep ->
           let calleeLevel = effectiveLevel (ContractStatus (tdPreLevel dep) (tdPostLevel dep) Nothing Nothing)
           in case calleeLevel of
                Just (VLProven _) -> []
                Just vl -> [fname <> " is proven, but depends on " <> tdName dep
                           <> " which is " <> vlLabel vl]
                Nothing -> []
           ) deps
       _ -> []  -- Not proven: no drift possible

-- | The effective (minimum) verification level for a contract status.
effectiveLevel :: ContractStatus -> Maybe VerificationLevel
effectiveLevel cs =
  case (csPreLevel cs, csPostLevel cs) of
    (Nothing, Nothing) -> Nothing
    (Just a, Nothing)  -> Just a
    (Nothing, Just b)  -> Just b
    (Just a, Just b)   -> Just (min a b)

-- | Human label for a verification level.
vlLabel :: VerificationLevel -> Text
vlLabel VLAsserted    = "asserted"
vlLabel (VLTested n)  = "tested (" <> tshow n <> " samples)"
vlLabel (VLProven p)  = "proven (" <> p <> ")"

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

computeSummary :: [TrustEntry] -> TrustSummary
computeSummary entries =
  let classify e = effectiveLevel (ContractStatus (tePreLevel e) (tePostLevel e) (tePreSource e) (tePostSource e))
      proven   = length [e | e <- entries, isProven (classify e)]
      tested   = length [e | e <- entries, isTested (classify e)]
      asserted = length [e | e <- entries, isAsserted (classify e)]
      none     = length [e | e <- entries, classify e == Nothing]
      drifts   = sum (map (length . teDrifts) entries)
  in TrustSummary proven tested asserted none drifts
  where
    isProven (Just (VLProven _)) = True
    isProven _                   = False
    isTested (Just (VLTested _)) = True
    isTested _                   = False
    isAsserted (Just VLAsserted) = True
    isAsserted _                 = False

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
  in T.unlines ([header, separator] ++ entryLines ++ suppressionLines ++ [separator] ++ summaryLines)

formatEntry :: TrustEntry -> [Text]
formatEntry e =
  let preLbl  = maybe "—" vlLabel (tePreLevel e)
      postLbl = maybe "—" vlLabel (tePostLevel e)
      line1   = "  " <> teName e <> ":"
      line2   = "    pre:  " <> preLbl <> "  |  post: " <> postLbl
      sourceLines = catMaybes
        [ fmap (\s -> "    source (pre):  " <> s) (tePreSource e)
        , fmap (\s -> "    source (post): " <> s) (tePostSource e)
        ]
      depLines = map (\d -> "    ↳ calls " <> tdName d <> " (pre: "
                           <> maybe "—" vlLabel (tdPreLevel d)
                           <> ", post: " <> maybe "—" vlLabel (tdPostLevel d) <> ")")
                     (teDeps e)
      driftLines = map ("    ⚠ " <>) (teDrifts e)
  in [line1, line2] ++ sourceLines ++ depLines ++ driftLines

formatSummary :: TrustSummary -> [Text]
formatSummary s =
  [ "Summary:"
  , "  proven:   " <> tshow (tsProven s)
  , "  tested:   " <> tshow (tsTested s)
  , "  asserted: " <> tshow (tsAsserted s)
  , "  no contract: " <> tshow (tsNone s)
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

formatTrustReportJson :: TrustReport -> Text
formatTrustReportJson report =
  T.pack . BLC.unpack . encode $ object
    [ "entries" .= map entryJson (trEntries report)
    , "summary" .= summaryJson (trSummary report)
    , "suppressions" .= map suppJson (trSuppressions report)
    ]
  where
    entryJson e = object $
      [ "name"       .= teName e
      , "pre_level"  .= fmap vlLabel (tePreLevel e)
      , "post_level" .= fmap vlLabel (tePostLevel e)
      , "dependencies" .= map depJson (teDeps e)
      , "drifts"     .= teDrifts e
      ] ++
      maybe [] (\s -> ["pre_source" .= s]) (tePreSource e) ++
      maybe [] (\s -> ["post_source" .= s]) (tePostSource e)
    depJson d = object
      [ "name"       .= tdName d
      , "pre_level"  .= fmap vlLabel (tdPreLevel d)
      , "post_level" .= fmap vlLabel (tdPostLevel d)
      ]
    summaryJson s = object
      [ "proven"      .= tsProven s
      , "tested"      .= tsTested s
      , "asserted"    .= tsAsserted s
      , "no_contract" .= tsNone s
      , "drifts"      .= tsDrifts s
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
