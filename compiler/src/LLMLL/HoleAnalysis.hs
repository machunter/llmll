-- |
-- Module      : LLMLL.HoleAnalysis
-- Description : Catalog and classify all holes in an LLMLL AST.
--
-- Traverses the full AST to find every hole, classify it by kind,
-- determine if it blocks execution, infer what type it must satisfy,
-- and produce a structured report suitable for displaying to agents
-- or for the build system to reject incomplete modules.
--
-- v0.3.3: Adds structural RFC 6901 pointers, dependency analysis
-- via call-graph walking, and cycle detection via Tarjan's SCC.
module LLMLL.HoleAnalysis
  ( analyzeHoles
  , analyzeHolesModule
  , analyzeHolesWithDeps
  , HoleReport(..)
  , HoleEntry(..)
  , HoleStatus(..)
  , HoleDep(..)
  , totalHoles
  , blockingHoles
  , holeEntries
  , formatHoleReport
  , formatHoleReportSExp
  , formatHoleReportJson
  , holeDensityWarnings
    -- * v0.3.1: complexity classification
  , holeComplexity
  , normalizeComplexity
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Aeson (encode, object, (.=), Value, ToJSON(..))
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.List (nub, sortOn)
import Data.Maybe (mapMaybe)
import Data.Graph (stronglyConnComp, SCC(..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Text.Read (readMaybe)

import LLMLL.Syntax
import LLMLL.Diagnostic (Diagnostic, mkWarning)

-- ---------------------------------------------------------------------------
-- Data Types
-- ---------------------------------------------------------------------------

-- | Execution impact of a hole.
data HoleStatus
  = Blocking      -- ^ Stops execution: pending delegate, conflict
  | NonBlocking   -- ^ Informational: named, choose, scaffold (can run partial)
  | AgentTask     -- ^ Needs an agent to fill in: delegate/delegate-async
  deriving (Show, Eq, Ord)

-- | v0.3.3: An annotated dependency edge between holes.
data HoleDep = HoleDep
  { hdPointer :: Text   -- ^ JSON pointer of the hole this depends on
  , hdVia     :: Text   -- ^ Function name that creates the edge
  , hdReason  :: Text   -- ^ "calls-hole-body" (v0.3.3 only)
  } deriving (Show, Eq)

instance ToJSON HoleDep where
  toJSON d = object
    [ "pointer" .= hdPointer d
    , "via"     .= hdVia d
    , "reason"  .= hdReason d
    ]

-- | A single hole found in the AST.
data HoleEntry = HoleEntry
  { holeName        :: Text            -- ^ Human-readable label
  , holeKind        :: HoleKind        -- ^ Raw kind from AST
  , holeContext     :: Text            -- ^ Where it was found (function name, etc.)
  , holePointer     :: Text            -- ^ v0.3.3: RFC 6901 JSON pointer (e.g. "/statements/2/body")
  , holeInferredType :: Maybe Type     -- ^ Type the hole must produce
  , holeAgent       :: Maybe Name      -- ^ Target agent for delegate holes
  , holeStatus      :: HoleStatus      -- ^ Blocking / NonBlocking / AgentTask
  , holeDescription :: Text            -- ^ What the hole is asking for
  , holeComplexity  :: Maybe Text      -- ^ v0.3.1: :simple, :inductive, :unknown (proof-required only)
  , holeDependsOn   :: [HoleDep]       -- ^ v0.3.3: dependency edges (filled by analyzeHolesWithDeps)
  , holeCycleWarn   :: Bool            -- ^ v0.3.3: True if involved in a broken dependency cycle
  } deriving (Show, Eq)

-- | Complete hole report for a module/program.
data HoleReport = HoleReport
  { _holeEntries    :: [HoleEntry]
  , _totalHoles     :: Int
  , _blockingHoles  :: Int
  , _agentTaskHoles :: Int    -- ^ Count of delegate holes
  , _namedHoles     :: Int    -- ^ Count of ?name holes
  } deriving (Show, Eq)

-- Accessor functions (public)
holeEntries :: HoleReport -> [HoleEntry]
holeEntries = _holeEntries

totalHoles :: HoleReport -> Int
totalHoles = _totalHoles

blockingHoles :: HoleReport -> Int
blockingHoles = _blockingHoles

-- ---------------------------------------------------------------------------
-- Entry Points
-- ---------------------------------------------------------------------------

-- | Analyze all holes in a list of top-level statements.
-- v0.3.3: Uses structural index traversal for RFC 6901 pointers.
analyzeHoles :: [Statement] -> HoleReport
analyzeHoles stmts =
  let entries = concat $ zipWith collectHolesStmtIdx [0..] stmts
  in buildReport entries

-- | Analyze all holes in a Module.
analyzeHolesModule :: Module -> HoleReport
analyzeHolesModule m = analyzeHoles (moduleBody m)

-- | v0.3.3: Analyze holes with dependency graph and cycle detection.
-- Only body-level AgentTask/Blocking holes participate in the dependency graph.
-- Contract-position holes and ?proof-required holes are excluded.
analyzeHolesWithDeps :: [Statement] -> HoleReport
analyzeHolesWithDeps stmts =
  let baseEntries = concat $ zipWith collectHolesStmtIdx [0..] stmts
      withDeps    = computeHoleDeps stmts baseEntries
      withCycles  = detectCycles stmts withDeps
  in buildReport withCycles

-- ---------------------------------------------------------------------------
-- Traversal — Statements
-- ---------------------------------------------------------------------------

-- | v0.3.3: Traverse a statement at a known index, producing RFC 6901 pointers.
collectHolesStmtIdx :: Int -> Statement -> [HoleEntry]
collectHolesStmtIdx idx (SDefLogic name _params _ret contract body) =
  let base = "statements/" <> tshow idx
      ctx  = "def-logic " <> name
      bodyHoles = collectHolesExprPath (base <> "/body") ctx body
      preHoles  = maybe [] (collectHolesExprPath (base <> "/pre") (ctx <> " [pre]"))  (contractPre contract)
      postHoles = maybe [] (collectHolesExprPath (base <> "/post") (ctx <> " [post]")) (contractPost contract)
      -- D3: auto-emit proof-required for non-linear pre/post constraints
      nlPreH  = maybe [] (\e -> if isNonLinear e
                  then [classifyHoleP (base <> "/pre") (ctx <> " [pre]") Nothing (HProofRequired "non-linear-contract")]
                  else []) (contractPre contract)
      nlPostH = maybe [] (\e -> if isNonLinear e
                  then [classifyHoleP (base <> "/post") (ctx <> " [post]") Nothing (HProofRequired "non-linear-contract")]
                  else []) (contractPost contract)
  in bodyHoles ++ preHoles ++ postHoles ++ nlPreH ++ nlPostH

collectHolesStmtIdx _idx (SDefInterface _ _ _) = []

collectHolesStmtIdx idx (SLetrec name _params _ret contract dec body) =
  let base = "statements/" <> tshow idx
      ctx  = "letrec " <> name
      bodyHoles = collectHolesExprPath (base <> "/body") ctx body
      decHoles  = collectHolesExprPath (base <> "/decreases") (ctx <> " [decreases]") dec
      preHoles  = maybe [] (collectHolesExprPath (base <> "/pre") (ctx <> " [pre]"))  (contractPre contract)
      postHoles = maybe [] (collectHolesExprPath (base <> "/post") (ctx <> " [post]")) (contractPost contract)
      -- D3: complex :decreases
      complexDecH = if not (isSimpleDecreases dec)
                    then [classifyHoleP (base <> "/decreases") (ctx <> " [decreases]") Nothing (HProofRequired "complex-decreases")]
                    else []
      -- D3: non-linear contract constraints
      nlPreH  = maybe [] (\e -> if isNonLinear e
                  then [classifyHoleP (base <> "/pre") (ctx <> " [pre]") Nothing (HProofRequired "non-linear-contract")]
                  else []) (contractPre contract)
      nlPostH = maybe [] (\e -> if isNonLinear e
                  then [classifyHoleP (base <> "/post") (ctx <> " [post]") Nothing (HProofRequired "non-linear-contract")]
                  else []) (contractPost contract)
  in bodyHoles ++ decHoles ++ preHoles ++ postHoles
      ++ complexDecH ++ nlPreH ++ nlPostH

collectHolesStmtIdx idx (STypeDef name body) =
  collectHolesType ("type " <> name) body

collectHolesStmtIdx idx (SCheck prop) =
  let base = "statements/" <> tshow idx
      ctx  = "check: " <> propDescription prop
  in collectHolesExprPath (base <> "/body") ctx (propBody prop)

collectHolesStmtIdx _idx (SImport _)  = []
collectHolesStmtIdx idx  (SExpr expr) =
  collectHolesExprPath ("statements/" <> tshow idx) "expr" expr
collectHolesStmtIdx _idx (SOpen _ _)  = []
collectHolesStmtIdx _idx (SExport _)  = []
collectHolesStmtIdx _idx (STrust _ _) = []
collectHolesStmtIdx _idx (SWeaknessOk _ _) = []

collectHolesStmtIdx idx (SDefMain _ mInit step _mRead mDone mOnDone) =
  let base = "statements/" <> tshow idx
      ctx  = "def-main"
      stepHoles = collectHolesExprPath (base <> "/step") ctx step
      initHoles = maybe [] (collectHolesExprPath (base <> "/init") (ctx <> " [init]")) mInit
      doneHoles = maybe [] (collectHolesExprPath (base <> "/done") (ctx <> " [done?]")) mDone
      onDoneH   = maybe [] (collectHolesExprPath (base <> "/on-done") (ctx <> " [on-done]")) mOnDone
  in stepHoles ++ initHoles ++ doneHoles ++ onDoneH

-- | Legacy wrapper for backward-compatible callers.
collectHolesStmt :: Text -> Statement -> [HoleEntry]
collectHolesStmt _ctx = collectHolesStmtIdx 0

-- ---------------------------------------------------------------------------
-- Traversal — Expressions
-- ---------------------------------------------------------------------------

-- | v0.3.3: Traverse expressions tracking structural AST path.
collectHolesExprPath :: Text -> Text -> Expr -> [HoleEntry]
collectHolesExprPath path ctx expr = case expr of
  ELit _       -> []
  EVar _       -> []

  ELet bindings body ->
    concat (zipWith (\i (pat, _, e) ->
      collectHolesExprPath (path <> "/bindings/" <> tshow i <> "/value")
                           (ctx <> " let " <> patLabel pat) e
      ) [0..] bindings)
    ++ collectHolesExprPath (path <> "/body") ctx body

  EIf cond t f ->
    collectHolesExprPath (path <> "/cond") ctx cond
    ++ collectHolesExprPath (path <> "/then_branch") (ctx <> " [then]") t
    ++ collectHolesExprPath (path <> "/else_branch") (ctx <> " [else]") f

  EMatch scrut cases ->
    collectHolesExprPath (path <> "/scrutinee") ctx scrut
    ++ concat (zipWith (\i (_, e) ->
      collectHolesExprPath (path <> "/arms/" <> tshow i <> "/body") ctx e
      ) [0..] cases)

  EApp _ args ->
    concat (zipWith (\i a ->
      collectHolesExprPath (path <> "/args/" <> tshow i) ctx a
      ) [0..] args)

  EOp _ args ->
    concat (zipWith (\i a ->
      collectHolesExprPath (path <> "/args/" <> tshow i) ctx a
      ) [0..] args)

  EPair a b ->
    collectHolesExprPath (path <> "/first") (ctx <> " [fst]") a
    ++ collectHolesExprPath (path <> "/second") (ctx <> " [snd]") b

  EHole hk -> [classifyHoleP path ctx Nothing hk]

  EAwait e -> collectHolesExprPath path ctx e

  ELambda _ body -> collectHolesExprPath (path <> "/body") ctx body

  EDo steps ->
    concat (zipWith (\i (DoStep _ e) ->
      collectHolesExprPath (path <> "/steps/" <> tshow i <> "/expr") ctx e
      ) [0..] steps)

-- | Legacy wrapper for backward-compatible callers.
collectHolesExpr :: Text -> Expr -> [HoleEntry]
collectHolesExpr ctx = collectHolesExprPath "unknown" ctx

-- | PR 4: Extract a label from a pattern for context strings.
patLabel :: Pattern -> Text
patLabel (PVar n) = n
patLabel (PConstructor c _) = "(" <> c <> " ...)"
patLabel PWildcard = "_"
patLabel (PLiteral _) = "<literal>"

-- ---------------------------------------------------------------------------
-- Traversal — Types (for dependent type constraints)
-- ---------------------------------------------------------------------------

collectHolesType :: Text -> Type -> [HoleEntry]
collectHolesType ctx (TDependent _ _ constraintExpr) =
  collectHolesExpr (ctx <> " [constraint]") constraintExpr
collectHolesType ctx (TList inner) =
  collectHolesType ctx inner
collectHolesType ctx (TMap k v) =
  collectHolesType ctx k ++ collectHolesType ctx v
collectHolesType ctx (TResult a b) =
  collectHolesType ctx a ++ collectHolesType ctx b
collectHolesType ctx (TPair a b) =   -- PR 2: pair types may contain dependent parts
  collectHolesType ctx a ++ collectHolesType ctx b
collectHolesType ctx (TPromise a) =
  collectHolesType ctx a
collectHolesType ctx (TSumType ctors) =
  concatMap (\(_, mTy) -> maybe [] (collectHolesType ctx) mTy) ctors
collectHolesType _ _ = []

-- ---------------------------------------------------------------------------
-- D3: Proof-Required Auto-Detection Helpers
-- ---------------------------------------------------------------------------

-- | Returns True if the expression has a 'simple' termination measure
-- (a variable or literal). Simple decreases are trivially handled by LH.
-- Complex expressions need a manual proof witness.
isSimpleDecreases :: Expr -> Bool
isSimpleDecreases (EVar _)  = True
isSimpleDecreases (ELit _)  = True
isSimpleDecreases _         = False

-- | Returns True if the expression contains non-linear arithmetic.
-- Heuristic: any EApp of (* / mod) applied to two non-literal sub-expressions.
-- This is a sufficient (not necessary) condition — false negatives are safe;
-- the worst outcome is a missing proof-required hole (user can add manually).
isNonLinear :: Expr -> Bool
isNonLinear (EApp op args)
  | op `elem` ["*", "/", "mod", "rem", "^", "**"]
  , length args == 2
  , not (all isLit args) = True  -- e.g. (* n m) where n, m are not both literals
  | otherwise            = any isNonLinear args
  where isLit (ELit _) = True; isLit _ = False
isNonLinear (ELet _ body)   = isNonLinear body
isNonLinear (EIf c t f)     = isNonLinear c || isNonLinear t || isNonLinear f
isNonLinear (EMatch s arms) = isNonLinear s || any (isNonLinear . snd) arms
isNonLinear _               = False

-- ---------------------------------------------------------------------------
-- Hole Classification
-- ---------------------------------------------------------------------------

-- | v0.3.3: Classify a hole with its structural path.
classifyHoleP :: Text -> Text -> Maybe Type -> HoleKind -> HoleEntry
classifyHoleP path ctx mType hk = HoleEntry
  { holeName         = holeKindLabel hk
  , holeKind         = hk
  , holeContext      = ctx
  , holePointer      = "/" <> path
  , holeInferredType = mType
  , holeAgent        = holeAgent' hk
  , holeStatus       = holeStatus' hk
  , holeDescription  = holeDesc hk
  , holeComplexity   = case hk of
      HProofRequired reason -> Just (normalizeComplexity reason)
      _                     -> Nothing
  , holeDependsOn    = []     -- filled later by computeHoleDeps
  , holeCycleWarn    = False  -- filled later by detectCycles
  }

-- | Legacy wrapper.
classifyHole :: Text -> Maybe Type -> HoleKind -> HoleEntry
classifyHole = classifyHoleP "unknown"

holeAgent' :: HoleKind -> Maybe Name
holeAgent' (HDelegate spec)      = Just (delegateAgent spec)
holeAgent' (HDelegateAsync spec) = Just (delegateAgent spec)
holeAgent' _                     = Nothing

holeStatus' :: HoleKind -> HoleStatus
holeStatus' HDelegatePending{}    = Blocking
holeStatus' HConflictResolution{} = Blocking
holeStatus' HDelegate{}           = AgentTask
holeStatus' HDelegateAsync{}      = AgentTask
holeStatus' HProofRequired{}      = NonBlocking  -- non-blocking: code runs; LH verifies statically
holeStatus' _                     = NonBlocking

holeKindLabel :: HoleKind -> Text
holeKindLabel (HNamed n)          = "?" <> n
holeKindLabel (HChoose opts)      = "?choose(" <> T.intercalate ", " opts <> ")"
holeKindLabel (HRequestCap cap)   = "?request-cap(" <> cap <> ")"
holeKindLabel (HScaffold spec)    = "?scaffold(" <> scaffoldTemplate spec <> ")"
holeKindLabel (HDelegate spec)    = "?delegate @" <> delegateAgent spec
holeKindLabel (HDelegateAsync s)  = "?delegate-async @" <> delegateAgent s
holeKindLabel (HDelegatePending t) = "?pending(" <> typeLabel t <> ")"
holeKindLabel HConflictResolution = "?conflict"
holeKindLabel (HProofRequired r)  = "?proof-required(" <> r <> ")"

holeDesc :: HoleKind -> Text
holeDesc (HNamed n)           = "Named implementation hole: " <> n
holeDesc (HChoose opts)       = "Choose one of: " <> T.intercalate ", " opts
holeDesc (HRequestCap cap)    = "Missing capability: " <> cap
holeDesc (HScaffold spec)     = "Scaffold template: " <> scaffoldTemplate spec
holeDesc (HDelegate spec)     = delegateDescription spec
holeDesc (HDelegateAsync spec) = delegateDescription spec <> " (async)"
holeDesc (HDelegatePending t) = "Pending delegate returning " <> typeLabel t
holeDesc HConflictResolution  = "Unresolved merge conflict — manual resolution required"
holeDesc (HProofRequired r)   = "LiquidHaskell proof required [" <> r <> "]: this site cannot be statically verified without LH"

-- ---------------------------------------------------------------------------
-- Report Builder
-- ---------------------------------------------------------------------------

buildReport :: [HoleEntry] -> HoleReport
buildReport entries = HoleReport
  { _holeEntries    = entries
  , _totalHoles     = length entries
  , _blockingHoles  = length (filter ((== Blocking)  . holeStatus) entries)
  , _agentTaskHoles = length (filter ((== AgentTask) . holeStatus) entries)
  , _namedHoles     = length (filter isNamed entries)
  }
  where
    isNamed e = case holeKind e of { HNamed _ -> True; _ -> False }

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

-- | Human-readable hole report.
formatHoleReport :: HoleReport -> Text
formatHoleReport r =
  T.unlines $
    [ "Hole Report: " <> tshow (_totalHoles r) <> " total"
    , "  Blocking:   " <> tshow (_blockingHoles r)
    , "  Agent tasks:" <> tshow (_agentTaskHoles r)
    , "  Named:      " <> tshow (_namedHoles r)
    , ""
    ] ++ map formatEntry (_holeEntries r)
  where
    formatEntry e =
      "[" <> statusLabel (holeStatus e) <> "] "
      <> holeName e
      <> " in " <> holeContext e
      <> " — " <> holeDescription e

    statusLabel Blocking    = "BLOCK"
    statusLabel AgentTask   = "AGENT"
    statusLabel NonBlocking = " INFO"

-- | S-expression hole report (for machine consumption).
formatHoleReportSExp :: HoleReport -> Text
formatHoleReportSExp r =
  "(hole-report"
  <> " :total " <> tshow (_totalHoles r)
  <> " :blocking " <> tshow (_blockingHoles r)
  <> " :agent-tasks " <> tshow (_agentTaskHoles r)
  <> "\n  :holes (" <> T.intercalate "\n           " (map fmtEntry (_holeEntries r)) <> "))"
  where
    fmtEntry e =
      "(hole :name " <> quote (holeName e)
      <> " :context " <> quote (holeContext e)
      <> " :status " <> statusStr (holeStatus e)
      <> maybe "" (\a -> " :agent " <> quote a) (holeAgent e)
      <> " :desc " <> quote (holeDescription e)
      <> ")"

    statusStr Blocking    = "blocking"
    statusStr AgentTask   = "agent-task"
    statusStr NonBlocking = "informational"

    quote t = "\"" <> T.replace "\"" "\\\"" t <> "\""

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- JSON Output (roadmap-specified shape)
-- ---------------------------------------------------------------------------

-- | Format the hole report as a JSON array.
-- v0.3.3: Uses structural holePointer. When includeDeps is True, emits
-- depends_on edges and cycle_warning per hole.
formatHoleReportJson :: FilePath -> Bool -> HoleReport -> Text
formatHoleReportJson _fp includeDeps report =
  T.pack . BL.unpack . encode $ map entryToJson (_holeEntries report)
  where
    entryToJson e = object $
      [ "kind"          .= holeKindTag (holeKind e)
      , "pointer"       .= holePointer e
      , "message"       .= ("hole: " <> holeName e)
      , "inferred-type" .= fmap typeLabel (holeInferredType e)
      , "module-path"   .= holeContext e
      , "agent"         .= holeAgent e
      , "status"        .= statusStr (holeStatus e)
      ] ++ maybe [] (\c -> ["complexity" .= c]) (holeComplexity e)
        ++ if includeDeps
           then [ "depends_on"    .= holeDependsOn e
                , "cycle_warning" .= holeCycleWarn e
                ]
           else []

    holeKindTag (HNamed _)          = "named"          :: Text
    holeKindTag (HChoose _)         = "choose"
    holeKindTag (HRequestCap _)     = "request-cap"
    holeKindTag (HScaffold _)       = "scaffold"
    holeKindTag (HDelegate _)       = "delegate"
    holeKindTag (HDelegateAsync _)  = "delegate-async"
    holeKindTag (HDelegatePending _)= "delegate-pending"
    holeKindTag HConflictResolution = "conflict"
    holeKindTag (HProofRequired _)  = "proof-required"

    statusStr Blocking    = "blocking"      :: Text
    statusStr AgentTask   = "agent-task"
    statusStr NonBlocking = "non-blocking"

-- ---------------------------------------------------------------------------
-- Hole Density Validator
-- ---------------------------------------------------------------------------

-- | Post-parse pass: warn when a 'def-logic' body is entirely a single named
-- hole (hole-to-construct ratio = 1.0). This nudges agents toward targeted
-- holes rather than wholesale stubs.
--
-- Per roadmap: threshold is 1.0 (whole body is one named hole).
holeDensityWarnings :: [Statement] -> [Diagnostic]
holeDensityWarnings = concatMap checkStmt
  where
    checkStmt (SDefLogic name _params _ret _contract body) =
      case body of
        EHole (HNamed holeName_) ->
          [ (mkWarning Nothing $
              "def-logic '" <> name <> "' body is entirely a single named hole (?" <> holeName_ <> "). "
              <> "Prefer targeted holes over wholesale stubs.")
          ]
        _ -> []
    checkStmt _ = []

-- ---------------------------------------------------------------------------
-- Complexity Classification (v0.3.1)
-- ---------------------------------------------------------------------------

-- | Normalize a proof-required reason to a complexity class.
--   Used by @llmll holes --json@ to guide Leanstral strategy selection.
normalizeComplexity :: Text -> Text
normalizeComplexity reason
  | T.isInfixOf "complex-decreases" reason = ":inductive"
  | T.isInfixOf "inductive" reason         = ":inductive"
  | T.isInfixOf "manual" reason            = ":unknown"
  | T.isInfixOf "non-linear" reason        = ":unknown"
  | otherwise                              = ":simple"

-- ---------------------------------------------------------------------------
-- v0.3.3: Dependency Analysis
-- ---------------------------------------------------------------------------

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

-- | Build call graph: function name → list of called function names.
buildCallGraph :: [Statement] -> Map.Map Name [Name]
buildCallGraph stmts = Map.fromList $ mapMaybe go stmts
  where
    go (SDefLogic name _ _ _ body)  = Just (name, nub $ extractCalls body)
    go (SLetrec name _ _ _ _ body)  = Just (name, nub $ extractCalls body)
    go _                            = Nothing

-- | Build map: function name → list of body holes (only AgentTask/Blocking).
-- Contract-position holes and ?proof-required holes are excluded.
buildFuncBodyHoles :: [Statement] -> [HoleEntry] -> Map.Map Name [HoleEntry]
buildFuncBodyHoles stmts entries =
  let qualifying = filter isDepCandidate entries
  in  Map.fromListWith (++) $ mapMaybe (\e -> do
        fname <- enclosingFunc (holePointer e) stmts
        Just (fname, [e])) qualifying
  where
    isDepCandidate e =
      holeStatus e `elem` [AgentTask, Blocking]
      && not (isContractPointer (holePointer e))
    isContractPointer p =
         "/pre" `T.isSuffixOf` p
      || "/post" `T.isSuffixOf` p
      || "/decreases" `T.isSuffixOf` p

-- | Extract the enclosing function name from a pointer.
-- "/statements/2/body/..." → look up statement 2.
enclosingFunc :: Text -> [Statement] -> Maybe Name
enclosingFunc pointer stmts =
  let segs = T.splitOn "/" (T.drop 1 pointer)  -- drop leading /
  in case segs of
    ("statements" : idxStr : _) ->
      case readMaybe (T.unpack idxStr) :: Maybe Int of
        Just idx | idx < length stmts -> stmtName (stmts !! idx)
        _ -> Nothing
    _ -> Nothing
  where
    stmtName (SDefLogic name _ _ _ _)    = Just name
    stmtName (SLetrec name _ _ _ _ _)    = Just name
    stmtName _                           = Nothing

-- | Compute dependency edges for all holes.
-- For each body hole H in function F: if F calls G, and G has body holes,
-- then H depends on each of G's holes.
computeHoleDeps :: [Statement] -> [HoleEntry] -> [HoleEntry]
computeHoleDeps stmts entries =
  let callGraph  = buildCallGraph stmts
      funcHoles  = buildFuncBodyHoles stmts entries
  in map (addDeps callGraph funcHoles stmts) entries
  where
    addDeps cg fh ss entry
      | not (isDepCandidate entry) = entry  -- non-candidates keep empty deps
      | otherwise =
        case enclosingFunc (holePointer entry) ss of
          Nothing    -> entry
          Just fname ->
            let callees   = Map.findWithDefault [] fname cg
                depHoles  = concatMap (\callee ->
                  case Map.lookup callee fh of
                    Nothing -> []
                    Just hs -> map (\h -> HoleDep
                      { hdPointer = holePointer h
                      , hdVia     = callee
                      , hdReason  = "calls-hole-body"
                      }) hs
                  ) callees
                -- Don't depend on yourself
                filtered = filter (\d -> hdPointer d /= holePointer entry) depHoles
            in entry { holeDependsOn = nub filtered }

    isDepCandidate e =
      holeStatus e `elem` [AgentTask, Blocking]
      && not (isContractPointer (holePointer e))
    isContractPointer p =
         "/pre" `T.isSuffixOf` p
      || "/post" `T.isSuffixOf` p
      || "/decreases" `T.isSuffixOf` p

-- ---------------------------------------------------------------------------
-- v0.3.3: Cycle Detection (Tarjan's SCC)
-- ---------------------------------------------------------------------------

-- | Detect dependency cycles via SCC analysis.
-- Cycles are broken deterministically by removing the back-edge whose
-- source has the highest statement index.
detectCycles :: [Statement] -> [HoleEntry] -> [HoleEntry]
detectCycles stmts entries =
  let -- Build graph for SCC: (node, key, [dep-keys])
      depEntries = filter (not . null . holeDependsOn) entries
      allPtrs    = Set.fromList $ map holePointer entries
      graphNodes = map (\e ->
        (e, holePointer e, filter (`Set.member` allPtrs) $ map hdPointer (holeDependsOn e))
        ) entries
      sccs = stronglyConnComp graphNodes
      -- Find all pointers involved in cycles
      cyclePtrs = Set.fromList $ concatMap getCycleMembers sccs
      -- For each cycle SCC, break the back-edge from the highest-index member
      brokenEdges = Set.fromList $ concatMap (getEdgesToBreak stmts) sccs
  in map (\e ->
    if holePointer e `Set.member` cyclePtrs
    then e { holeCycleWarn = True
           , holeDependsOn = filter (\d -> (holePointer e, hdPointer d) `Set.notMember` brokenEdges)
                                    (holeDependsOn e)
           }
    else e
    ) entries
  where
    getCycleMembers (AcyclicSCC _) = []
    getCycleMembers (CyclicSCC es) = map holePointer es

    getEdgesToBreak _ (AcyclicSCC _) = []
    getEdgesToBreak ss (CyclicSCC es) =
      let sorted = sortOn (stmtIndex . holePointer) es
          -- The last entry (highest statement index) has its back-edges removed
          lastE  = last sorted
          earlierPtrs = Set.fromList $ map holePointer (init sorted)
      in [(holePointer lastE, hdPointer d)
         | d <- holeDependsOn lastE
         , hdPointer d `Set.member` earlierPtrs
         ]

    stmtIndex :: Text -> Int
    stmtIndex ptr =
      let segs = T.splitOn "/" (T.drop 1 ptr)
      in case segs of
        ("statements" : idxStr : _) ->
          case readMaybe (T.unpack idxStr) :: Maybe Int of
            Just n  -> n
            Nothing -> maxBound
        _ -> maxBound
