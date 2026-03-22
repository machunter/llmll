-- |
-- Module      : LLMLL.HoleAnalysis
-- Description : Catalog and classify all holes in an LLMLL AST.
--
-- Traverses the full AST to find every hole, classify it by kind,
-- determine if it blocks execution, infer what type it must satisfy,
-- and produce a structured report suitable for displaying to agents
-- or for the build system to reject incomplete modules.
module LLMLL.HoleAnalysis
  ( analyzeHoles
  , analyzeHolesModule
  , HoleReport(..)
  , HoleEntry(..)
  , HoleStatus(..)
  , totalHoles
  , blockingHoles
  , holeEntries
  , formatHoleReport
  , formatHoleReportSExp
  , formatHoleReportJson
  , holeDensityWarnings
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Aeson (encode, object, (.=), Value)
import qualified Data.ByteString.Lazy.Char8 as BL

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

-- | A single hole found in the AST.
data HoleEntry = HoleEntry
  { holeName        :: Text            -- ^ Human-readable label
  , holeKind        :: HoleKind        -- ^ Raw kind from AST
  , holeContext     :: Text            -- ^ Where it was found (function name, etc.)
  , holeInferredType :: Maybe Type     -- ^ Type the hole must produce
  , holeAgent       :: Maybe Name      -- ^ Target agent for delegate holes
  , holeStatus      :: HoleStatus      -- ^ Blocking / NonBlocking / AgentTask
  , holeDescription :: Text            -- ^ What the hole is asking for
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
analyzeHoles :: [Statement] -> HoleReport
analyzeHoles stmts =
  let entries = concatMap (collectHolesStmt "top-level") stmts
  in buildReport entries

-- | Analyze all holes in a Module.
analyzeHolesModule :: Module -> HoleReport
analyzeHolesModule m = analyzeHoles (moduleBody m)

-- ---------------------------------------------------------------------------
-- Traversal — Statements
-- ---------------------------------------------------------------------------

collectHolesStmt :: Text -> Statement -> [HoleEntry]
collectHolesStmt _ctx (SDefLogic name params _ret contract body) =
  let ctx = "def-logic " <> name
      bodyHoles = collectHolesExpr ctx body
      preHoles  = maybe [] (collectHolesExpr (ctx <> " [pre]"))  (contractPre contract)
      postHoles = maybe [] (collectHolesExpr (ctx <> " [post]")) (contractPost contract)
  in bodyHoles ++ preHoles ++ postHoles

collectHolesStmt _ctx (SDefInterface _ _) = []

collectHolesStmt _ctx (STypeDef name body) =
  collectHolesType ("type " <> name) body

collectHolesStmt _ctx (SCheck prop) =
  let ctx = "check: " <> propDescription prop
  in collectHolesExpr ctx (propBody prop)

collectHolesStmt _ctx (SImport _)  = []
collectHolesStmt ctx  (SExpr expr) = collectHolesExpr ctx expr

collectHolesStmt _ctx (SDefMain _ mInit step _mRead mDone mOnDone) =
  let ctx' = "def-main"
      stepHoles = collectHolesExpr ctx' step
      initHoles = maybe [] (collectHolesExpr (ctx' <> " [init]")) mInit
      doneHoles = maybe [] (collectHolesExpr (ctx' <> " [done?]")) mDone
      onDoneH   = maybe [] (collectHolesExpr (ctx' <> " [on-done]")) mOnDone
  in stepHoles ++ initHoles ++ doneHoles ++ onDoneH

-- ---------------------------------------------------------------------------
-- Traversal — Expressions
-- ---------------------------------------------------------------------------

collectHolesExpr :: Text -> Expr -> [HoleEntry]
collectHolesExpr ctx expr = case expr of
  ELit _       -> []
  EVar _       -> []

  ELet bindings body ->
    concatMap (\(n, _, e) -> collectHolesExpr (ctx <> " let " <> n) e) bindings
    ++ collectHolesExpr ctx body

  EIf cond t f ->
    collectHolesExpr ctx cond
    ++ collectHolesExpr (ctx <> " [then]") t
    ++ collectHolesExpr (ctx <> " [else]") f

  EMatch scrut cases ->
    collectHolesExpr ctx scrut
    ++ concatMap (\(_, e) -> collectHolesExpr ctx e) cases

  EApp _ args ->
    concatMap (collectHolesExpr ctx) args

  EOp _ args ->
    concatMap (collectHolesExpr ctx) args

  EPair a b ->
    collectHolesExpr (ctx <> " [fst]") a
    ++ collectHolesExpr (ctx <> " [snd]") b

  EHole hk -> [classifyHole ctx Nothing hk]

  EAwait e -> collectHolesExpr ctx e

  ELambda _ body -> collectHolesExpr ctx body

  EDo steps ->
    concatMap (collectHolesDoStep ctx) steps

collectHolesDoStep :: Text -> DoStep -> [HoleEntry]
collectHolesDoStep ctx (DoBind _ e) = collectHolesExpr ctx e
collectHolesDoStep ctx (DoExpr e)   = collectHolesExpr ctx e

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
collectHolesType ctx (TPromise a) =
  collectHolesType ctx a
collectHolesType _ _ = []

-- ---------------------------------------------------------------------------
-- Hole Classification
-- ---------------------------------------------------------------------------

classifyHole :: Text -> Maybe Type -> HoleKind -> HoleEntry
classifyHole ctx mType hk = HoleEntry
  { holeName         = holeKindLabel hk
  , holeKind         = hk
  , holeContext      = ctx
  , holeInferredType = mType
  , holeAgent        = holeAgent' hk
  , holeStatus       = holeStatus' hk
  , holeDescription  = holeDesc hk
  }

holeAgent' :: HoleKind -> Maybe Name
holeAgent' (HDelegate spec)      = Just (delegateAgent spec)
holeAgent' (HDelegateAsync spec) = Just (delegateAgent spec)
holeAgent' _                     = Nothing

holeStatus' :: HoleKind -> HoleStatus
holeStatus' HDelegatePending{}    = Blocking
holeStatus' HConflictResolution{} = Blocking
holeStatus' HDelegate{}           = AgentTask
holeStatus' HDelegateAsync{}      = AgentTask
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

holeDesc :: HoleKind -> Text
holeDesc (HNamed n)           = "Named implementation hole: " <> n
holeDesc (HChoose opts)       = "Choose one of: " <> T.intercalate ", " opts
holeDesc (HRequestCap cap)    = "Missing capability: " <> cap
holeDesc (HScaffold spec)     = "Scaffold template: " <> scaffoldTemplate spec
holeDesc (HDelegate spec)     = delegateDescription spec
holeDesc (HDelegateAsync spec) = delegateDescription spec <> " (async)"
holeDesc (HDelegatePending t) = "Pending delegate returning " <> typeLabel t
holeDesc HConflictResolution  = "Unresolved merge conflict — manual resolution required"

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

-- | Format the hole report as a JSON array matching the roadmap spec:
-- [ { "kind": "named", "pointer": "/statements/0/body",
--     "message": "hole: ?impl", "inferred-type": null,
--     "module-path": "<context>", "agent": null, "status": "non-blocking" } ]
formatHoleReportJson :: FilePath -> HoleReport -> Text
formatHoleReportJson _fp report =
  T.pack . BL.unpack . encode $ map entryToJson (_holeEntries report)
  where
    entryToJson e = object
      [ "kind"          .= holeKindTag (holeKind e)
      , "pointer"       .= ("/" <> T.replace " " "/" (holeContext e))
      , "message"       .= ("hole: " <> holeName e)
      , "inferred-type" .= fmap typeLabel (holeInferredType e)
      , "module-path"   .= holeContext e
      , "agent"         .= holeAgent e
      , "status"        .= statusStr (holeStatus e)
      ]

    holeKindTag (HNamed _)          = "named"          :: Text
    holeKindTag (HChoose _)         = "choose"
    holeKindTag (HRequestCap _)     = "request-cap"
    holeKindTag (HScaffold _)       = "scaffold"
    holeKindTag (HDelegate _)       = "delegate"
    holeKindTag (HDelegateAsync _)  = "delegate-async"
    holeKindTag (HDelegatePending _)= "delegate-pending"
    holeKindTag HConflictResolution = "conflict"

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
