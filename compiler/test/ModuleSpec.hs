{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : ModuleSpec
-- Description : Module system tests (M-01 through M-07)
--
-- Tests for the LLMLL module system covering:
--   M-01: import + open + bare call succeeds strict typecheck
--   M-02: import without open fails strict typecheck
--   M-03: export filtering at typecheck (unexported names not injected by open)
--   M-04: selective open (open with name list)
--   M-05: open collision warning (duplicate bare names)
--   M-06: cycle detection with correct visit-order path
--   M-07: checkInterfaceMismatch unit test
module ModuleSpec (moduleSpec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheckStrictWithCache, emptyEnv)
import LLMLL.Diagnostic (reportSuccess, reportDiagnostics, diagKind, diagMessage, diagSeverity, Severity(..))
import LLMLL.Module (loadModule, buildModuleEnv, mergeModuleEnvs, checkInterfaceMismatch)
import LLMLL.PBT
  ( runPropertyTests, assembleTestStatements
  , PBTResult(..), PBTRun(..), PBTStatus(..)
  , pbtTrustWriteback
  )

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Build a simple ModuleEnv from a module path and statements, with no
-- imported modules (empty base env).
mkEnv :: ModulePath -> [Statement] -> ModuleEnv
mkEnv path stmts = buildModuleEnv path stmts emptyEnv

-- | A simple def-logic that returns its parameter.
defLogic :: T.Text -> [(T.Text, Type)] -> Maybe Type -> Expr -> Statement
defLogic name params mRet body =
  SDefLogic name params mRet (Contract Nothing Nothing Nothing Nothing Nothing) body

-- | Module A: defines f and g, no export restriction.
modA_stmts :: [Statement]
modA_stmts =
  [ defLogic "f" [("x", TInt)] (Just TInt) (EOp "+" [EVar "x", ELit (LitInt 1)])
  , defLogic "g" [("x", TInt)] (Just TInt) (EOp "+" [EVar "x", ELit (LitInt 2)])
  ]

modA_env :: ModuleEnv
modA_env = mkEnv ["modA"] modA_stmts

-- | Module A_export: defines f and g, exports only f.
modA_export_stmts :: [Statement]
modA_export_stmts =
  [ SExport ["f"]
  , defLogic "f" [("x", TInt)] (Just TInt) (EOp "+" [EVar "x", ELit (LitInt 1)])
  , defLogic "g" [("x", TInt)] (Just TInt) (EOp "+" [EVar "x", ELit (LitInt 2)])
  ]

modA_export_env :: ModuleEnv
modA_export_env = mkEnv ["modA_export"] modA_export_stmts

-- | A second module that also exports f (for collision testing).
modE_stmts :: [Statement]
modE_stmts =
  [ defLogic "f" [("y", TInt)] (Just TInt) (EOp "*" [EVar "y", ELit (LitInt 2)])
  ]

modE_env :: ModuleEnv
modE_env = mkEnv ["modE"] modE_stmts

-- | Build a ModuleCache from a list of ModuleEnvs.
mkCache :: [ModuleEnv] -> ModuleCache
mkCache envs = Map.fromList [(mePath e, e) | e <- envs]

-- ---------------------------------------------------------------------------
-- Test suite
-- ---------------------------------------------------------------------------

moduleSpec :: Spec
moduleSpec = describe "Module System" $ do

  -- -----------------------------------------------------------------------
  -- M-01: import + open + bare call succeeds strict typecheck
  -- -----------------------------------------------------------------------
  describe "M-01: import + open + bare call" $ do
    it "succeeds under strict typecheck when open is present" $ do
      -- Entry module: (import modA) (open modA) (def-logic h [x: int] (f x))
      let entryStmts =
            [ SImport (Import "modA" Nothing Nothing)
            , SOpen ["modA"] Nothing   -- open all exports
            , defLogic "h" [("x", TInt)] (Just TInt) (EApp "f" [EVar "x"])
            ]
          cache = mkCache [modA_env]
          report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
      reportSuccess report `shouldBe` True

  -- -----------------------------------------------------------------------
  -- M-02: import without open fails strict typecheck
  -- -----------------------------------------------------------------------
  describe "M-02: import without open fails strict" $ do
    it "bare call to imported function fails without open" $ do
      -- Entry module: (import modA) (def-logic h [x: int] (f x))
      -- No (open modA) — bare "f" is not in scope
      let entryStmts =
            [ SImport (Import "modA" Nothing Nothing)
            , defLogic "h" [("x", TInt)] (Just TInt) (EApp "f" [EVar "x"])
            ]
          cache = mkCache [modA_env]
          report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
      reportSuccess report `shouldBe` False
      -- Should have at least one error referencing unbound "f"
      let errs = filter ((== SevError) . diagSeverity) (reportDiagnostics report)
      length errs `shouldSatisfy` (>= 1)

  -- -----------------------------------------------------------------------
  -- M-03: export filtering at typecheck
  -- -----------------------------------------------------------------------
  describe "M-03: export filtering at typecheck" $ do
    it "g is not in meExports when module exports only f" $ do
      Map.member "f" (meExports modA_export_env) `shouldBe` True
      Map.member "g" (meExports modA_export_env) `shouldBe` False

    it "open with unexported name g fails — SOpen finds no qualified modA_export.g" $ do
      -- Entry: (import modA_export) (open modA_export (g)) (def-logic h [x: int] (g x))
      -- Since g is not in meExports, SOpen finds no qualified "modA_export.g"
      -- in the env, so no bare "g" is injected. The bare call to g fails.
      let entryStmts =
            [ SImport (Import "modA_export" Nothing Nothing)
            , SOpen ["modA_export"] (Just ["g"])  -- selective: only g
            , defLogic "h" [("x", TInt)] (Just TInt) (EApp "g" [EVar "x"])
            ]
          cache = mkCache [modA_export_env]
          report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
      reportSuccess report `shouldBe` False

  -- -----------------------------------------------------------------------
  -- M-04: selective open
  -- -----------------------------------------------------------------------
  describe "M-04: selective open" $ do
    it "(open modA (f)) makes f available but not g" $ do
      -- Entry: (import modA) (open modA (f)) (def-logic h [x: int] (f x))
      let entryStmts_ok =
            [ SImport (Import "modA" Nothing Nothing)
            , SOpen ["modA"] (Just ["f"])  -- selective: only f
            , defLogic "h" [("x", TInt)] (Just TInt) (EApp "f" [EVar "x"])
            ]
          cache = mkCache [modA_env]
          report_ok = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts_ok
      reportSuccess report_ok `shouldBe` True

    it "(open modA (f)) leaves g unresolvable under strict typecheck" $ do
      let entryStmts_fail =
            [ SImport (Import "modA" Nothing Nothing)
            , SOpen ["modA"] (Just ["f"])
            , defLogic "h" [("x", TInt)] (Just TInt) (EApp "g" [EVar "x"])
            ]
          cache = mkCache [modA_env]
          report_fail = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts_fail
      reportSuccess report_fail `shouldBe` False

  -- -----------------------------------------------------------------------
  -- M-05: open collision warning
  -- -----------------------------------------------------------------------
  describe "M-05: open collision warning" $ do
    it "two opens with overlapping name 'f' emit a shadow warning" $ do
      -- Both modA and modE export "f". Opening both should shadow.
      let entryStmts =
            [ SImport (Import "modA" Nothing Nothing)
            , SImport (Import "modE" Nothing Nothing)
            , SOpen ["modA"] Nothing  -- injects f, g
            , SOpen ["modE"] Nothing  -- injects f again -> shadow
            , defLogic "h" [("x", TInt)] (Just TInt) (EApp "f" [EVar "x"])
            ]
          cache = mkCache [modA_env, modE_env]
          report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv entryStmts
      -- Should have at least one warning with "open-shadow-warning" in the message.
      -- NOTE: tcWarn in TypeCheck.hs:609 leaves diagKind as Nothing,
      -- so we assert only on severity + message text.
      let shadowWarns = filter
            (\d -> diagSeverity d == SevWarning
                && T.isInfixOf "open-shadow-warning" (diagMessage d))
            (reportDiagnostics report)
      length shadowWarns `shouldSatisfy` (>= 1)

  -- -----------------------------------------------------------------------
  -- M-06: cycle detection with correct visit-order path
  -- -----------------------------------------------------------------------
  describe "M-06: cycle detection" $ do
    it "circular import returns diagnostic with kind circular-import" $ do
      -- Use loadModule with actual fixture files.
      let srcRoot = "test/fixtures/modules"
      result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["modC_cycle"]
      case result of
        Left diags -> do
          length diags `shouldSatisfy` (>= 1)
          let cycleDiag = head diags
          diagKind cycleDiag `shouldBe` Just "circular-import"
          -- The message should contain the cycle in visit order.
          -- modC_cycle imports modD_cycle, modD_cycle imports modC_cycle.
          -- So cycle should be: modC_cycle → modD_cycle → modC_cycle
          -- (sliced to just the cycle participants).
          let msg = diagMessage cycleDiag
          msg `shouldSatisfy` T.isInfixOf "modC_cycle"
          msg `shouldSatisfy` T.isInfixOf "modD_cycle"
          -- Verify the cycle appears in visit order (modD_cycle before the
          -- second modC_cycle occurrence)
          msg `shouldSatisfy` T.isInfixOf "modD_cycle \x2192 modC_cycle"
        Right _ ->
          expectationFailure "Expected circular-import error, got success"

  -- -----------------------------------------------------------------------
  -- M-07: checkInterfaceMismatch unit test
  -- -----------------------------------------------------------------------
  describe "M-07: checkInterfaceMismatch" $ do
    it "returns diagnostic for method with wrong type" $ do
      -- Module A exports f :: int -> int.
      -- The importer expects f :: int -> string.
      let expected = [("f", TFn [TInt] TString)]
          diags = checkInterfaceMismatch ["importer"] "TestIface" expected modA_env
      length diags `shouldBe` 1
      diagKind (head diags) `shouldBe` Just "interface-mismatch"
      diagMessage (head diags) `shouldSatisfy` T.isInfixOf "f"

    it "returns no diagnostic when types match" $ do
      let expected = [("f", TFn [TInt] TInt)]
          diags = checkInterfaceMismatch ["importer"] "TestIface" expected modA_env
      diags `shouldBe` []

    it "returns diagnostic for missing method" $ do
      let expected = [("nonexistent", TFn [TInt] TInt)]
          diags = checkInterfaceMismatch ["importer"] "TestIface" expected modA_env
      length diags `shouldBe` 1
      diagMessage (head diags) `shouldSatisfy` T.isInfixOf "not exported"

  -- -----------------------------------------------------------------------
  -- M-08: PBT cross-module FuncEnv via (open ...) — F-018 / MOD-PBT-1
  -- -----------------------------------------------------------------------
  describe "M-08: PBT cross-module FuncEnv via (open ...)" $ do
    let plusOneStmt =
          defLogic "plus-one" [("n", TInt)] (Just TInt)
            (EOp "+" [EVar "n", ELit (LitInt 1)])
        timesTwoStmt =
          defLogic "times-two" [("n", TInt)] (Just TInt)
            (EOp "*" [EVar "n", ELit (LitInt 2)])
        checkProp desc body = SCheck (Property desc [] body [])

    it "M-08.1: (open imported) makes imported def-logic resolve in FuncEnv" $ do
      -- Imported: (def-logic plus-one [n: int] (+ n 1))
      -- Local:    (import imported) (open imported) (check (= (plus-one 1) 2))
      let importedEnv = mkEnv ["imported"] [plusOneStmt]
          localStmts =
            [ SImport (Import "imported" Nothing Nothing)
            , SOpen ["imported"] Nothing
            , checkProp "plus-one-of-1-is-2"
                (EOp "=" [EApp "plus-one" [ELit (LitInt 1)], ELit (LitInt 2)])
            ]
          cache  = mkCache [importedEnv]
          merged = assembleTestStatements localStmts cache
      result <- runPropertyTests merged
      case pbtResults result of
        [run] -> pbtStatus run `shouldBe` PBTPassed
        rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

    it "M-08.2: selective (open imported (plus-one)) forwards plus-one but not times-two" $ do
      let importedEnv = mkEnv ["imported"] [plusOneStmt, timesTwoStmt]
          localStmts =
            [ SImport (Import "imported" Nothing Nothing)
            , SOpen ["imported"] (Just ["plus-one"])
            , checkProp "plus-one-passes"
                (EOp "=" [EApp "plus-one" [ELit (LitInt 1)], ELit (LitInt 2)])
            , checkProp "times-two-not-resolved"
                (EOp "=" [EApp "times-two" [ELit (LitInt 3)], ELit (LitInt 6)])
            ]
          cache  = mkCache [importedEnv]
          merged = assembleTestStatements localStmts cache
      result <- runPropertyTests merged
      let byName n = head [r | r <- pbtResults result, pbtDescription r == n]
      length (pbtResults result) `shouldBe` 2
      pbtStatus (byName "plus-one-passes")       `shouldBe` PBTPassed
      pbtStatus (byName "times-two-not-resolved") `shouldNotBe` PBTPassed

    it "M-08.3: non-exported def-logic is not forwarded even under full (open)" $ do
      -- Imported module exports only plus-one. times-two is defined but excluded.
      let importedStmts =
            [ SExport ["plus-one"]
            , plusOneStmt
            , timesTwoStmt
            ]
          importedEnv = mkEnv ["imported"] importedStmts
          localStmts =
            [ SImport (Import "imported" Nothing Nothing)
            , SOpen ["imported"] Nothing  -- "open all exports"
            , checkProp "plus-one-passes"
                (EOp "=" [EApp "plus-one" [ELit (LitInt 1)], ELit (LitInt 2)])
            , checkProp "times-two-not-exported"
                (EOp "=" [EApp "times-two" [ELit (LitInt 3)], ELit (LitInt 6)])
            ]
          cache  = mkCache [importedEnv]
          merged = assembleTestStatements localStmts cache
      result <- runPropertyTests merged
      let byName n = head [r | r <- pbtResults result, pbtDescription r == n]
      pbtStatus (byName "plus-one-passes")        `shouldBe` PBTPassed
      pbtStatus (byName "times-two-not-exported") `shouldNotBe` PBTPassed

    it "M-08.4: local def-logic shadows imported def-logic of the same name" $ do
      -- Imported f returns 1; local f returns 0. Local must win.
      let importedF = defLogic "f" [] (Just TInt) (ELit (LitInt 1))
          localF    = defLogic "f" [] (Just TInt) (ELit (LitInt 0))
          importedEnv = mkEnv ["imported"] [importedF]
          localStmts =
            [ SImport (Import "imported" Nothing Nothing)
            , SOpen ["imported"] Nothing
            , localF
            , checkProp "local-f-wins"
                (EOp "=" [EApp "f" [], ELit (LitInt 0)])
            ]
          cache  = mkCache [importedEnv]
          merged = assembleTestStatements localStmts cache
      result <- runPropertyTests merged
      case pbtResults result of
        [run] -> pbtStatus run `shouldBe` PBTPassed
        rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

    -- OBLIG-PBT-4 S8 (proposal §11.1, 2026-05-14): cross-module subjects.
    -- A ':subjects [localF importedG]' annotation must resolve through
    -- qualMap so the imported subject keys the writeback under its
    -- qualified path. The local subject stays bare-local.
    it "M-08.6: :subjects [local imported] writeback uses qualified key for imported" $ do
      let importedG = defLogic "g" [("x", TInt)] (Just TInt) (EVar "x")
          -- Add a postcondition so writeback has a slot to lift on g.
          importedGContracted =
            case importedG of
              SDefLogic n p r _c b ->
                SDefLogic n p r
                  (Contract Nothing Nothing
                     (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  b
              other -> other
          localF =
            case defLogic "f" [("x", TInt)] (Just TInt) (EVar "x") of
              SDefLogic n p r _c b ->
                SDefLogic n p r
                  (Contract Nothing Nothing
                     (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  b
              other -> other
          importedEnv = mkEnv ["imported"] [importedGContracted]
          localStmts =
            [ SImport (Import "imported" Nothing Nothing)
            , SOpen ["imported"] Nothing
            , localF
            , SCheck (Property "cross-mod" []
                        (EOp "and" [EApp "f" [ELit (LitInt 1)], EApp "g" [ELit (LitInt 2)]])
                        ["f", "g"])
            ]
          cache  = mkCache [importedEnv]
          result = PBTResult 1 1 0 0 [PBTRun "cross-mod" PBTPassed 100 Nothing]
          (m, _ds) = pbtTrustWriteback localStmts cache result
      Map.size m `shouldBe` 2
      Map.member "f" m         `shouldBe` True   -- bare-local
      Map.member "imported.g" m `shouldBe` True  -- qualified import

    it "M-08.5: fixture-driven loadModule + PBT closes F-018 acceptance criterion" $ do
      -- Files: test/fixtures/pbt-cross-module/{imported,local}.llmll
      -- Local: (import imported) (open imported) (check (= (plus-one 1) 2))
      let srcRoot = "test/fixtures/pbt-cross-module"
      result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["local"]
      case result of
        Left diags -> expectationFailure $
          "Failed to load fixture: " ++ show (length diags) ++ " diagnostics"
        Right (cache, _loadOrder, _path) -> do
          case Map.lookup ["local"] cache of
            Nothing -> expectationFailure "local module missing from cache"
            Just localEnv -> do
              let localStmts = meStatements localEnv
                  merged    = assembleTestStatements localStmts cache
              pbtResult <- runPropertyTests merged
              pbtPassed pbtResult  `shouldBe` 1
              pbtSkipped pbtResult `shouldBe` 0
              pbtFailed pbtResult  `shouldBe` 0
