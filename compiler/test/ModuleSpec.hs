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
import LLMLL.Parser (parseTopLevel)
import LLMLL.TypeCheck
  ( typeCheckStrictWithCache, emptyEnv
  , runSketch, seedCacheEnv, builtinEnv, SketchResult(..), SketchHole(..)
  , ScopeBinding(..), ScopeSource(..)
  )
import LLMLL.InvariantRegistry (defaultPatterns)
import LLMLL.Diagnostic (reportSuccess, reportDiagnostics, diagKind, diagMessage, diagSeverity, Severity(..))
import LLMLL.Module (loadModule, buildModuleEnv, mergeModuleEnvs, checkInterfaceMismatch)
import LLMLL.PBT
  ( runPropertyTests, assembleTestStatements
  , PBTResult(..), PBTRun(..), PBTStatus(..)
  , pbtTrustWriteback
  , canonicalDefEvidenceHash
  )
import LLMLL.TrustReport (buildTrustReport, TrustReport(..), TrustEntry(..), TrustDependency(..), injectOpenedAliases)
import LLMLL.FixpointEmit (emitFixpointWith, emitFixpointWithCache, EmitOptions(..), EmitResult(..), buildContractEnv, cacheAwareAliasMap, cacheAwareContractEnv)
import LLMLL.ObligationAssembly (assembleConsumedGuarantees, recursiveNames, importedContractedFns)
import Data.Aeson (Value(..))
import qualified Data.Aeson.KeyMap as KM
import LLMLL.VerifiedCache (verifiedPath, saveVerified)
import Control.Exception (finally)
import Data.List (find)
import System.Directory (removeFile)

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

  -- -----------------------------------------------------------------------
  -- XMOD-ALIAS: cross-module refinement-alias resolution (on-disk, end-to-end).
  -- 'use' imports the PositiveInt refinement alias from 'core' and does
  -- arithmetic/comparison (>=, -) on a value of that type. This exercises the
  -- SAME real file-loading path the CLI 'check'/'verify'/'build' use:
  -- loadModule -> buildModuleEnv -> ModuleCache -> typeCheckStrictWithCache.
  -- Before the fix, loadModule returned Left with two "type mismatch" errors
  -- ("expected int, got PositiveInt"); the identical code in-module type-checks.
  -- Files: test/fixtures/xmod-alias/{core,use}.llmll
  -- -----------------------------------------------------------------------
  describe "XMOD-ALIAS: imported refinement alias is int-compatible (on-disk)" $ do
    it "XA-DISK-1: loadModule of an importer doing >=/- on imported PositiveInt succeeds" $ do
      let srcRoot = "test/fixtures/xmod-alias"
      result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["use"]
      case result of
        Left diags -> expectationFailure $
          "Cross-module refinement-alias load failed (XMOD-ALIAS regression): "
          ++ show (length diags) ++ " diagnostics: "
          ++ show (map diagMessage diags)
        Right (cache, _loadOrder, _path) ->
          case Map.lookup ["use"] cache of
            Nothing -> expectationFailure "use module missing from cache"
            Just useEnv -> do
              -- Re-run the entry type-check through the CLI's strict path; the
              -- imported PositiveInt must unfold to int for '>=' and '-'.
              let report = typeCheckStrictWithCache GrammarCoreInversion cache emptyEnv
                             (meStatements useEnv)
                  errs   = filter ((== SevError) . diagSeverity) (reportDiagnostics report)
              errs `shouldBe` []
              reportSuccess report `shouldBe` True

  -- -----------------------------------------------------------------------
  -- XMOD-TIER: a module importing an independently-VERIFIED function and
  -- composing with it must surface the imported function at 'verified' in the
  -- importing module's trust report, and the cross-module caller's post-side
  -- callee meet must inherit that verified tier (rather than dropping the bare
  -- callee edge, which both hides the dependency and — for a weaker callee —
  -- silently over-credits the caller). Runs the SAME real CLI path:
  -- loadModule -> buildModuleEnv -> ModuleCache -> buildTrustReport.
  --
  -- Files: test/fixtures/xmod-tier/{core,compose}.llmll. 'core.withdraw' carries
  -- a pre+post; the test seeds core.llmll.verified.json with a body-faithful
  -- verified_hash (recovered from the live parsed def so the hash matches
  -- exactly) and then varies the imported evidence per case.
  -- -----------------------------------------------------------------------
  describe "XMOD-TIER: imported verified evidence reaches the importer's trust report" $ do
    let srcRoot   = "test/fixtures/xmod-tier"
        coreFp    = srcRoot ++ "/core.llmll"
        coreSidecarFp = verifiedPath coreFp
        -- Recover the live parsed (body,pre,post) of core.withdraw so a seeded
        -- verified_hash matches the live def exactly (and a deliberately wrong
        -- hash is provably stale).
        recoverWithdraw coreEnv =
          case find (\s -> case s of SDef "withdraw" _ _ _ _ -> True; _ -> False)
                    (meStatements coreEnv) of
            Just (SDef _ _ _ c b) -> (canonicalDefEvidenceHash "def" b (contractPre c) (contractPost c))
            _                     -> error "core.withdraw def not found in fixture"
        mkER dl bf vh =
          EvidenceRecord dl bf Nothing [] False Nothing Nothing False vh
        -- Build a compose sidecar making safe-withdraw's OWN post verified (the
        -- realistic verify-time state once it has discharged withdraw's pre and
        -- proved its own post). The hash is recovered from the live def-shell.
        composeOwnSidecar composeEnv =
          case find (\s -> case s of SDefShell "safe-withdraw" _ _ _ _ _ -> True; _ -> False)
                    (meStatements composeEnv) of
            Just (SDefShell _ _ _ c b _) ->
              let h = canonicalDefEvidenceHash "def-shell" b (contractPre c) (contractPost c)
                  v = mkER (DLVerified "liquid-fixpoint") True (Just h)
              in Map.fromList [("safe-withdraw", ContractStatus (Just v) (Just v) [])]
            _ -> Map.empty
        -- Entry of a trust report by (qualified) name.
        entryByName nm rpt = find (\e -> teName e == nm) (trEntries rpt)

    it "XMOD-TIER-POS: imported withdraw reads verified; composer reaches verified via callee meet" $ do
      coreOnly <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["core"]
      let Right (coreCache, _, _) = coreOnly
          Just coreEnv = Map.lookup ["core"] coreCache
          vh = recoverWithdraw coreEnv
          ver = mkER (DLVerified "liquid-fixpoint") True (Just vh)
      saveVerified coreFp (Map.fromList [("withdraw", ContractStatus (Just ver) (Just ver) [])])
      flip finally (removeFile coreSidecarFp) $ do
        result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["compose"]
        case result of
          Left diags -> expectationFailure $ "load failed: " ++ show (map diagMessage diags)
          Right (cache, _ord, composeEnv) -> do
            let report = buildTrustReport cache (meStatements composeEnv)
                           (composeOwnSidecar composeEnv)
            -- (a) imported core.withdraw reads verified in compose's report.
            case entryByName "core.withdraw" report >>= teEffectivePostLevel of
              Just (DLVerified _) -> pure ()
              other -> expectationFailure $
                "imported core.withdraw should read verified, got " ++ show other
            -- (b) the cross-module callee dependency is captured (not dropped):
            -- the bare 'withdraw' call resolves to the opened import.
            case entryByName "safe-withdraw" report of
              Nothing -> expectationFailure "safe-withdraw entry missing"
              Just sw -> do
                map tdName (teDeps sw) `shouldContain` ["withdraw"]
                -- (c) safe-withdraw (own post verified) reaches verified — the
                -- meet against the (verified) imported callee does NOT floor it.
                case teEffectivePostLevel sw of
                  Just (DLVerified _) -> pure ()
                  other -> expectationFailure $
                    "safe-withdraw should reach verified, got " ++ show other

    it "XMOD-TIER-NEG: an ASSERTED imported callee floors the verified-own-post caller (no over-credit)" $ do
      -- Soundness direction: now that the dep is captured, a WEAK imported callee
      -- must drag the caller's effective post down. (Before the fix the bare edge
      -- was dropped and the caller silently kept its own verified post.)
      coreOnly <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["core"]
      let Right (coreCache, _, _) = coreOnly
          Just coreEnv = Map.lookup ["core"] coreCache
          _vh = recoverWithdraw coreEnv  -- unused: asserted evidence carries no hash
          asserted = mkER DLAsserted False Nothing
      saveVerified coreFp (Map.fromList [("withdraw", ContractStatus (Just asserted) (Just asserted) [])])
      flip finally (removeFile coreSidecarFp) $ do
        result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["compose"]
        case result of
          Left diags -> expectationFailure $ "load failed: " ++ show (map diagMessage diags)
          Right (cache, _ord, composeEnv) -> do
            let report = buildTrustReport cache (meStatements composeEnv)
                           (composeOwnSidecar composeEnv)
            case entryByName "core.withdraw" report >>= teEffectivePostLevel of
              Just DLAsserted -> pure ()
              other -> expectationFailure $
                "asserted imported withdraw should read asserted, got " ++ show other
            case entryByName "safe-withdraw" report of
              Nothing -> expectationFailure "safe-withdraw entry missing"
              Just sw -> do
                map tdName (teDeps sw) `shouldContain` ["withdraw"]
                teEffectivePostLevel sw `shouldBe` Just DLAsserted

    it "XMOD-TIER-STALE: a stale imported verified_hash does NOT upgrade the tier" $ do
      -- The imported sidecar claims verified but carries a verified_hash that
      -- does not match the live core.withdraw body+contract. The cross-module
      -- staleness guard ('downgradeStaleVerifiedSidecar' over the cached module's
      -- own statements) must demote it to asserted, so it cannot upgrade a tier.
      coreOnly <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["core"]
      let Right (coreCache, _, _) = coreOnly
          Just coreEnv = Map.lookup ["core"] coreCache
          _liveHash = recoverWithdraw coreEnv
          -- A deliberately wrong hash (any value distinct from the live one).
          staleHash = "sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
          staleVer  = mkER (DLVerified "liquid-fixpoint") True (Just staleHash)
      _liveHash `shouldNotBe` staleHash
      saveVerified coreFp (Map.fromList [("withdraw", ContractStatus (Just staleVer) (Just staleVer) [])])
      flip finally (removeFile coreSidecarFp) $ do
        result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["compose"]
        case result of
          Left diags -> expectationFailure $ "load failed: " ++ show (map diagMessage diags)
          Right (cache, _ord, composeEnv) -> do
            let report = buildTrustReport cache (meStatements composeEnv)
                           (composeOwnSidecar composeEnv)
            -- Stale verified evidence demoted: imported withdraw reads asserted.
            case entryByName "core.withdraw" report >>= teEffectivePostLevel of
              Just DLAsserted -> pure ()
              other -> expectationFailure $
                "stale imported withdraw should be downgraded to asserted, got " ++ show other
            -- And it does not upgrade the caller: safe-withdraw floors to asserted.
            case entryByName "safe-withdraw" report >>= teEffectivePostLevel of
              Just DLAsserted -> pure ()
              other -> expectationFailure $
                "stale callee must not upgrade caller; expected asserted, got " ++ show other

  -- -----------------------------------------------------------------------
  -- XMOD-AG (cross-module assume-guarantee): the BODY-VC side of cross-module
  -- verification. XMOD-TIER above covers the trust TIER (imported evidence +
  -- staleness). These cases cover the complementary body-faithfulness: a caller
  -- of an IMPORTED contracted function discharges its body VC via
  -- assume-guarantee against the imported CONTRACT (seedImportedContracts feeds
  -- the imported contracts into the body-VC ContractEnv), instead of falling
  -- back to contract-only. Runs the real CLI emit path:
  -- loadModule -> ModuleCache -> emitFixpointWithCache.
  --
  -- Files: test/fixtures/xmod-ag/{lib,use_double,use_double_qual,lib_gate,use_gate}.llmll.
  -- -----------------------------------------------------------------------
  describe "XMOD-AG: cross-module callers verify body-faithful (assume-guarantee across imports)" $ do
    let srcRoot = "test/fixtures/xmod-ag"
        -- Load the entry module (+ imports) and emit the body-VC WITH the
        -- resulting cache; returns the EmitResult. Mirrors doVerify.
        emitWithCacheOf entry = do
          result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] [entry]
          case result of
            Left diags -> error $ "load failed: " ++ show (map diagMessage diags)
            Right (cache, _ord, env) ->
              emitFixpointWithCache (EmitOptions True)
                (srcRoot ++ "/" ++ T.unpack entry ++ ".llmll") cache (meStatements env)

    it "XMOD-AG-OPEN: opened-import caller (double) is body-faithful, not a fallback" $ do
      er <- emitWithCacheOf "use_double"
      erBodyFaithfulFns er `shouldContain` ["use-double"]
      ("use-double" `elem` erBodyFallback er) `shouldBe` False

    it "XMOD-AG-STRICT: opened-import caller leaves no fallback (--strict-verified-core would pass)" $ do
      er <- emitWithCacheOf "use_double"
      erBodyFallback er `shouldBe` []

    it "XMOD-AG-QUAL: qualified-access caller (lib.double) is body-faithful via dual-keying" $ do
      er <- emitWithCacheOf "use_double_qual"
      erBodyFaithfulFns er `shouldContain` ["use-double-qual"]

    it "XMOD-AG-CALLPRE: caller emits the imported callee's precondition obligation" $ do
      -- Soundness: assume-guarantee is not a free pass — the caller must PROVE
      -- the imported callee's pre (>= x 0) at the call site.
      er <- emitWithCacheOf "use_double"
      erCallPreFns er `shouldContain` ["use-double"]

    it "XMOD-AG-CONTRAST: the same caller with an EMPTY cache falls back (seeding is the cause)" $ do
      -- The pre-fix behavior, and the guard that genuine fallbacks still fire:
      -- with no cache the imported 'double' is absent from cenv, so the call
      -- cannot discharge via assume-guarantee and the whole body falls back.
      result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] ["use_double"]
      case result of
        Left diags -> expectationFailure $ "load failed: " ++ show (map diagMessage diags)
        Right (_cache, _ord, env) -> do
          er <- emitFixpointWith (EmitOptions True) (srcRoot ++ "/use_double.llmll") (meStatements env)
          erBodyFallback er `shouldContain` ["use-double"]
          ("use-double" `elem` erBodyFaithfulFns er) `shouldBe` False

    it "XMOD-AG-CRASHGUARD: imported nullary-ctor post desugars coherently (no solver crash)" $ do
      -- gate-for's post references the nullary ctor 'Open'; the caller assuming
      -- it must desugar 'Open' to the SAME int tag its own match uses — one
      -- merged alias map. Body-faithful (not raw → no "Constraint with free vars").
      er <- emitWithCacheOf "use_gate"
      erBodyFaithfulFns er `shouldContain` ["use-gate"]
      ("use-gate" `elem` erBodyFallback er) `shouldBe` False

  -- -----------------------------------------------------------------------
  -- XMOD-CG-BRIEF: the checkout brief's consumed_guarantees channel is
  -- cache-aware — an IMPORTED contracted callee's guarantee appears in the
  -- brief (the same-file-only cenv silently dropped it; XMOD-COMP layer 5),
  -- with callee_tier resolved through the qualified trust entry instead of
  -- falling through to "builtin". Mirrors Main.assembleCheckoutContext's
  -- construction 1:1. Files: test/fixtures/xmod-ag/ (reused).
  -- -----------------------------------------------------------------------
  describe "XMOD-CG-BRIEF: checkout consumed_guarantees sees imported callees" $ do
    let srcRoot = "test/fixtures/xmod-ag"
        -- Main's checkout loader (loadStatementsMulti) caches the entry's
        -- IMPORTS only, not the entry module itself — drop the entry from
        -- loadModule's cache so the construction mirrors the shipped path.
        loadEntry entry = do
          result <- loadModule GrammarCoreInversion False srcRoot [] Map.empty [] [entry]
          case result of
            Left diags -> error $ "load failed: " ++ show (map diagMessage diags)
            Right (cache, _ord, env) ->
              pure (Map.delete (mePath env) cache, meStatements env)
        -- The brief-side construction under test (Main.assembleCheckoutContext).
        consumedOf cache stmts fn =
          let trustRpt = buildTrustReport cache stmts Map.empty
              trustMap = injectOpenedAliases stmts $
                           Map.fromList [(teName e, e) | e <- trEntries trustRpt]
              aliases  = cacheAwareAliasMap stmts cache
              cenv     = cacheAwareContractEnv aliases stmts cache
          in assembleConsumedGuarantees stmts cenv trustMap (recursiveNames stmts) fn
        objStr k (Object o) = case KM.lookup k o of
          Just (String s) -> Just s
          _               -> Nothing
        objStr _ _          = Nothing

    it "XMOD-CG-OPEN: opened-import callee (double) reaches the brief with a real tier" $ do
      (cache, stmts) <- loadEntry "use_double"
      let guars = consumedOf cache stmts "use-double"
      map (objStr "callee") guars `shouldBe` [Just "double"]
      map (objStr "guarantee") guars `shouldBe` [Just "(= result (+ x x))"]
      map (objStr "instantiated") guars `shouldBe` [Just "(= <call-result> (+ x x))"]
      -- callee_tier resolves through the qualified 'lib.double' trust entry
      -- (bare-aliased by injectOpenedAliases) — never the "builtin" fallthrough.
      map (objStr "callee_tier") guars `shouldBe` [Just "asserted"]

    it "XMOD-CG-QUAL: qualified callee (lib.double) reaches the brief with a real tier" $ do
      (cache, stmts) <- loadEntry "use_double_qual"
      let guars = consumedOf cache stmts "use-double-qual"
      map (objStr "callee") guars `shouldBe` [Just "lib.double"]
      map (objStr "callee_tier") guars `shouldBe` [Just "asserted"]

    it "XMOD-CG-CONTRAST: the same-file-only cenv drops the imported callee (pre-fix behavior)" $ do
      -- The pre-fix construction, kept as the causal control: with the
      -- same-file cenv the imported callee never reaches the channel.
      (cache, stmts) <- loadEntry "use_double"
      let trustRpt = buildTrustReport cache stmts Map.empty
          trustMap = Map.fromList [(teName e, e) | e <- trEntries trustRpt]
          guars    = assembleConsumedGuarantees stmts (buildContractEnv stmts)
                       trustMap (recursiveNames stmts) "use-double"
      guars `shouldBe` []

    it "XMOD-CG-KEYS: the brief cenv = same-file keys ∪ dual-keyed imports" $ do
      -- Same-file entries are preserved (no regression) and the import is
      -- seeded under BOTH its bare (opened) and qualified name, matching the
      -- verify path's dual-keying.
      (cache, stmts) <- loadEntry "use_double"
      let aliases = cacheAwareAliasMap stmts cache
          cenv    = cacheAwareContractEnv aliases stmts cache
      Map.keys cenv `shouldBe` ["double", "lib.double", "use-double"]
      Map.keys (buildContractEnv stmts) `shouldBe` ["use-double"]

  -- -----------------------------------------------------------------------
  -- XMOD-SCOPE-BRIEF: the brief's callable-vocabulary channels are
  -- cache-aware — 'available_functions' lists imported exported contracted
  -- functions under the name the entry module calls them by, and the hole's
  -- 'in_scope' (seeded sketch env) carries imported names. Sibling of
  -- XMOD-CG-BRIEF (which fixed consumed_guarantees).
  -- -----------------------------------------------------------------------
  describe "XMOD-SCOPE-BRIEF: brief scope/function channels see imported names" $ do
    let parseSrc src = case parseTopLevel GrammarCoreInversion "<xmod-scope>" src of
          Left e      -> error ("parse failed: " ++ show e)
          Right stmts -> stmts
        libCache = Map.singleton ["lib"] $
          buildModuleEnv ["lib"] (parseSrc (T.unlines
            [ "(def double [x: int] -> int"
            , "  (pre (>= x 0))"
            , "  (post (= result (+ x x)))"
            , "  (+ x x))" ])) emptyEnv
        names = map (\(n, _, _, _) -> n)

    it "XMOD-SCOPE-OPEN: an opened import is listed under its bare name" $ do
      let entry = parseSrc "(import lib)\n(open lib)"
      names (importedContractedFns entry libCache) `shouldBe` ["double"]

    it "XMOD-SCOPE-QUAL: without (open) the import is listed qualified" $ do
      let entry = parseSrc "(import lib)"
      names (importedContractedFns entry libCache) `shouldBe` ["lib.double"]

    it "XMOD-SCOPE-SHADOW: a same-named local def pushes the import to its qualified name" $ do
      let entry = parseSrc (T.unlines
            [ "(import lib)"
            , "(open lib)"
            , "(def double [x: int] -> int (post (= result x)) x)" ])
      names (importedContractedFns entry libCache) `shouldBe` ["lib.double"]

    it "XMOD-SCOPE-EXPORT: a non-exported contracted function is never listed" $ do
      -- 'meContracts' is unfiltered; the meExports membership gate must drop
      -- 'priv' entirely (a brief must not suggest an untypecheckable call).
      let cache' = Map.singleton ["lib"] $
            buildModuleEnv ["lib"] (parseSrc (T.unlines
              [ "(export pub)"
              , "(def pub [x: int] -> int (post (>= result 0)) x)"
              , "(def priv [x: int] -> int (post (>= result 0)) x)" ])) emptyEnv
          entry = parseSrc "(import lib)\n(open lib)"
      names (importedContractedFns entry cache') `shouldBe` ["pub"]

    it "XMOD-SCOPE-SELECTIVE: (open lib (f)) leaves the unselected name qualified" $ do
      let cache' = Map.singleton ["lib"] $
            buildModuleEnv ["lib"] (parseSrc (T.unlines
              [ "(def f [x: int] -> int (post (>= result 0)) x)"
              , "(def g [x: int] -> int (post (>= result 0)) x)" ])) emptyEnv
          entry = parseSrc "(import lib)\n(open lib (f))"
      names (importedContractedFns entry cache') `shouldMatchList` ["f", "lib.g"]

    it "XMOD-SCOPE-INSCOPE: the hole env carries the opened import (open-import source) and its qualified name" $ do
      -- The Main.assembleCheckoutContext construction: seed the sketch env
      -- with qualified cache exports; the walk's SOpen handler adds the bare
      -- alias with SrcOpenImport provenance.
      let entry = parseSrc (T.unlines
            [ "(import lib)"
            , "(open lib)"
            , "(def-shell use [x: int] -> int (post (>= result 0)) ?rest)" ])
          sketch = runSketch GrammarCoreInversion (seedCacheEnv builtinEnv libCache)
                     entry defaultPatterns
      case sketchHoles sketch of
        [h] -> do
          fmap sbSource (Map.lookup "double" (shEnv h)) `shouldBe` Just SrcOpenImport
          Map.member "lib.double" (shEnv h) `shouldBe` True
        hs  -> expectationFailure ("expected exactly one hole, got " ++ show (length hs))
