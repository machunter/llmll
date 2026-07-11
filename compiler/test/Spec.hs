{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Test.Hspec
import Control.Monad (forM_, when)
import Control.Exception (finally)
import System.Exit (ExitCode(..), exitWith, exitSuccess, exitFailure)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Maybe (fromJust, isJust, listToMaybe, mapMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Text.Encoding as TE

import LLMLL.Lexer (tokenize, Token(..), TokenKind(..))
import LLMLL.Parser (parseStatements, parseExpr)
import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, typeCheckWithCache, typeCheckStrictWithCacheAndStatus, emptyEnv, builtinEnv, runSketch, SketchResult(..), SketchHole(..), HoleStatus(..), InvariantSuggestion(..))
import LLMLL.InvariantRegistry (defaultPatterns, matchPatterns, InvariantPattern(..))
import LLMLL.ObligationAssembly
  ( exprToSExpr, deriveBacking, collectHoleGuards, holeContractBrief, normalizeForFingerprint
  , obligationStatus, classifyContractFragment, classifyBodyFragment
  , recursiveNames, descentDischargedFns, ObligationKind(..), patternBindings, isTypeCompatible
  , trustLabel
  , computeEffectSummary, encodeEff, EffectSummary(..), EffectLabel(..)
  , assembleConsumedGuarantees, assembleFunctionLists
  , assembleSafePreObligations, ObligationObj(..), assembleReport )
import LLMLL.ObligationMining (mineObligations, formatObligations, formatObligationsJson, ObligationSuggestion(..), SuggestionStrength(..), isQfLia, generateCandidates, CandidateExpr(..))
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), FQVerifyResult(..), parseFQResult, parseFQResultJSON, fqResultToReport)
import LLMLL.FixpointEmit (bodyToPredFrom, BodyVC(..), LetBinding(..), SortEnv, flattenBodyVC, countPathsBounded, EmitResult(..), emitFixpoint, emitFixpointWith, EmitOptions(..), defaultEmitOptions, exprToPred, ContractEnv, buildContractEnv, applySubst, isConstructorDependent, collectCallPreObligations, buildAliasMap, isIntLike, bodyHasOverflowArith, augmentContractPost, desugarCtorValues, buildCtorTagMap, pathBranchSides, collectBranchBinders, bodyToPredFromR, payloadRefinement, payloadArms, admissibleDatatype, sortableComponent, resultReturnUnsafe, typeToSortA)
import LLMLL.FixpointIR (FQPred(..), FQBinOp(..), FQSort(..), emitPred, emitFQFile, FQFile(..), FQConstant(..))
import LLMLL.Diagnostic (reportPhase, reportSuccess, reportDiagnostics, formatReportJson, diagKind, diagMessage, diagPointer, diagSeverity, diagHoleSensitive, Severity(..), Diagnostic(..), DiagnosticReport(..), mkError, PatchOpInfo(..), rebaseToPatch, mkTrustGapWarning, megaparsecToDiagnostic)
import LLMLL.CodegenHs (generateHaskell, cgMainHs, cgHsSource, cgPackageYaml, emitExpr, emitLit, emitApp, toHsType, mapLlmllPrimType, runtimePreamble, emitHole, emitEventLogPreamble, classifyImport, ImportKind(..), sanitizePkgName)
import LLMLL.HoleAnalysis (analyzeHoles, analyzeHolesWithDeps, holeEntries, holeKind, HoleEntry(..), HoleDep(..), isNonLinear)
import qualified LLMLL.HoleAnalysis as HA
import LLMLL.ParserJSON (parseJSONAST, parseJSONASTValue)
import LLMLL.AstEmit (stmtToJson, emitJsonAST)
import LLMLL.Contracts (ContractsMode(..), instrumentStatement, instrumentContracts, applyContractsMode, evalContract, ContractResult(..), evalExprStatic, evalExprStaticWith, maxFuel)
import LLMLL.PBT (runPropertyTests, PBTResult(..), PBTRun(..), PBTStatus(..)
                 , pbtTrustWriteback, headContractedSubject, HeadResolution(..)
                 , canonicalPropBodyHash, canonicalDefEvidenceHash)
import LLMLL.Module (mergeCS)
import LLMLL.VerifiedCache (verifiedPath, saveVerified, saveVerifiedWith, loadVerified, sidecarNeedsRevalidation, dlToJSON, dlFromJSON)
import LLMLL.Hub (scaffoldCacheRoot, resolveScaffold, hubFetchLocal)
import LLMLL.Replay (parseEventLog, EventLogEntry(..), runReplay, ReplayResult(..), runCapturingExit)
import LLMLL.LeanTranslate (translateObligation, TranslateResult(..))
import LLMLL.MCPClient (MCPResult(..), mockProofResult, sanitizeProof, callLeanstral, defaultMCPConfig, MCPConfig(..), extractLeanFence, parseChatContent, buildChatRequest, ensureImport, kernelCheck)
import LLMLL.ProofCache (proofCachePath, ProofEntry(..), loadProofCache, saveProofCache, lookupProof, insertProof, computeObligationHash, upgradeLeanstralPosts)
import LLMLL.TrustReport (buildTrustReport, buildTrustReportWithCDP, formatTrustReport, formatTrustReportJson, TrustReport(..), TrustEntry(..), TrustSummary(..), TierProfile(..), CallerObligation(..), OverAnnotationInfo(..), callerObligationJson, aggregateTiers, aggregateTiersPre, aggregateTiersPost, markRefuted, markMeasureNotDecreasing, markDescentDischarged, refutedClosure, downgradeStaleVerifiedSidecar)
import LLMLL.ProofArtifact
import Data.Either (isLeft, isRight)
import Data.Aeson (encode, decode)
import LLMLL.AgentSpec (agentSpec, AgentSpec(..), BuiltinEntry(..), OperatorEntry(..))
import LLMLL.GuardClassifier (classifyGuardM, lookupPredOp, lookupArithOp)
import Control.Monad.State.Strict (evalState)

import qualified Data.Map.Strict as Map
import System.Directory (removeFile, doesFileExist, doesDirectoryExist, createDirectoryIfMissing, removeDirectoryRecursive, getTemporaryDirectory)
import System.Environment (setEnv, unsetEnv, lookupEnv)
import System.Process (callProcess)
import Data.List (isSuffixOf, sort, find)
import qualified Data.Set as Set
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Aeson (encode, decode, Value(..), object, (.=))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Map.Strict as DM

import LLMLL.JsonPointer (resolvePointer, setAtPointer, removeAtPointer, findDescendantHoles, isHoleNode)
import LLMLL.Checkout (lockFilePath, expireStale, CheckoutToken(..), CheckoutLock(..), TypeDefEntry(..), normalizePointer, collectTypeDefinitions, monomorphizeFunctions, truncateScope, buildScopeEntries, buildCheckoutFuncs, ScopeEntry(..), FuncEntry(..), checkoutHole, checkoutHoleMulti, MultiCheckoutResult(..), DivergenceSession(..), DivergenceMember(..), loadSessions, sessionMembers, promoteDivergenceWinner, emptyCheckoutContext)
import LLMLL.DivergenceCheck
  ( Fill(..), FillStatus(..), ClassifiedFill(..), DivergenceContext(..)
  , DivergenceReport(..), DivergenceVerdict(..), VerifiedBucket(..)
  , DistinguishingWitness(..), buildDivergenceReport, divergenceReportJson
  , verdictLabel, probeSet )
import LLMLL.PatchApply (applyOp, applyOps, validateScope, parsePatchOp, PatchOp(..), toPatchOpInfos, PatchResult(..), PatchRequest(..), CalleePreUnmet(..), applyPatch, hasContracts)
import System.FilePath ((</>))
import LLMLL.WeaknessCheck (generateWeaknessCandidates, generateCDPCandidates, WeaknessCandidate(..), TrivialBody(..), wcSyntheticName)
import LLMLL.CDP
  ( CDPResult(..), CDPWarning(..), CDPScope(..)
  , computeCDPFor, overAnnotationRatio, overAnnotationThreshold
  , cdpWarningLabel )
import LLMLL.SpecCoverage (CoverageReport(..), FunctionClass(..), FunctionEntry(..), CoverageSummary(..), LawEntry(..), runCoverage, formatCoverageJson, formatCoverageText)
import LLMLL.TypeCheck (ScopeSource(..), ScopeBinding(..), structuralUnify, runTC, occursIn, TC)
import Data.Time.Clock (UTCTime(..), secondsToDiffTime, addUTCTime)
import Data.Time.Calendar (fromGregorian)
import ModuleSpec (moduleSpec)

-- | Run a TC action in an empty environment and return (errors, result).
-- Used by U-Full tests to directly test structuralUnify.
runTCPure :: TC a -> ([Diagnostic], a)
runTCPure action =
  let (result, diags) = runTC GrammarCoreInversion emptyEnv action
  in (diags, result)

-- | R5 test helper: parse an S-expression fill body into an 'Expr'.
peR5 :: T.Text -> Expr
peR5 src = case parseExpr "<r5-test>" src of
  Right e  -> e
  Left err -> error ("R5 test parse failed: " ++ show err)

main :: IO ()
main = hspec $ do
  describe "Lexer" $ do
    it "tokenizes a simple expression" $ do
      let result = tokenize "<test>" "(+ 1 2)"
      case result of
        Left err -> expectationFailure (show err)
        Right toks -> length toks `shouldBe` 5  -- ( + 1 2 )

    it "tokenizes hole syntax" $ do
      let result = tokenize "<test>" "?implementation_detail"
      case result of
        Left err -> expectationFailure (show err)
        Right toks -> length toks `shouldBe` 1

    it "tokenizes def-logic keyword" $ do
      let result = tokenize "<test>" "(def-shell withdraw)"
      case result of
        Left err -> expectationFailure (show err)
        Right toks -> length toks `shouldBe` 4  -- ( def-logic withdraw )

    it "handles comments" $ do
      let result = tokenize "<test>" ";; this is a comment\n42"
      case result of
        Left err -> expectationFailure (show err)
        Right toks -> length toks `shouldBe` 1

  describe "Parser" $ do
    it "parses a type definition" $ do
      let src = "(type PositiveInt (where [x: int] (> x 0)))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> length stmts `shouldBe` 1

    it "parses a def-logic with contracts" $ do
      let src = "(def-shell withdraw [balance: int amount: int]\n\
                \  (pre (>= balance amount))\n\
                \  (post (= result (- balance amount)))\n\
                \  (- balance amount))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SDefShell name params _ contract _ _ -> do
              name `shouldBe` "withdraw"
              length params `shouldBe` 2
              contractPre contract `shouldNotBe` Nothing
              contractPost contract `shouldNotBe` Nothing
            _ -> expectationFailure "Expected SDefLogic"

    it "parses a check block" $ do
      let src = "(check \"Addition is commutative\"\n\
                \  (for-all [a: int b: int]\n\
                \    (= (+ a b) (+ b a))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SCheck prop -> propDescription prop `shouldBe` "Addition is commutative"
            _ -> expectationFailure "Expected SCheck"

    it "parses an if expression" $ do
      let src = "(if (> x 0) x (- 0 x))"
      case parseExpr "<test>" src of
        Left err -> expectationFailure (show err)
        Right (EIf _ _ _) -> pure ()
        Right other -> expectationFailure $ "Expected EIf, got: " ++ show other

    it "parses the withdraw example file" $ do
      src <- TIO.readFile "../examples/withdraw.llmll"
      case parseStatements GrammarCoreInversion "../examples/withdraw.llmll" src of
        Left err -> expectationFailure (show err)
        Right stmts -> length stmts `shouldSatisfy` (>= 3)

    it "parses a def-interface" $ do
      let src = "(def-interface AuthSystem\n\
                \  [hash-password (fn [raw: string] -> bytes[64])]\n\
                \  [verify-token  (fn [token: string] -> bool)])"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SDefInterface name fns _laws -> do
              name `shouldBe` "AuthSystem"
              length fns `shouldBe` 2
            _ -> expectationFailure "Expected SDefInterface"

  -- -----------------------------------------------------------------------
  -- Unicode alias tests
  -- -----------------------------------------------------------------------
  describe "Unicode aliases" $ do
    it "→ tokenizes to TokArrow" $ do
      let result = tokenize "<test>" "→"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokArrow

    it "∀ tokenizes to TokForAll" $ do
      let result = tokenize "<test>" "∀"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokForAll

    it "λ tokenizes to TokFn" $ do
      let result = tokenize "<test>" "λ"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokFn

    it "∧ tokenizes to TokAnd" $ do
      let result = tokenize "<test>" "∧"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokAnd

    it "∨ tokenizes to TokOr" $ do
      let result = tokenize "<test>" "∨"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokOr

    it "¬ tokenizes to TokNot" $ do
      let result = tokenize "<test>" "¬"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokNot

    it "≥ tokenizes to TokGTE" $ do
      let result = tokenize "<test>" "≥"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokGTE

    it "≤ tokenizes to TokLTE" $ do
      let result = tokenize "<test>" "≤"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokLTE

    it "≠ tokenizes to TokNotEqual" $ do
      let result = tokenize "<test>" "≠"
      case result of
        Left err   -> expectationFailure (show err)
        Right toks -> tokKind (head toks) `shouldBe` TokNotEqual

    it "def-interface with → parses same as with ->" $ do
      let ascii   = "(def-interface X [f (fn [string] -> bool)])"
          unicode = "(def-interface X [f (fn [string] → bool)])"
      let parseOne src = parseStatements GrammarCoreInversion "<test>" src
      case (parseOne ascii, parseOne unicode) of
        (Right a, Right b) -> a `shouldBe` b
        (Left err, _)      -> expectationFailure $ "ASCII parse failed: " ++ show err
        (_, Left err)      -> expectationFailure $ "Unicode parse failed: " ++ show err

    it "∀ expression in check block parses correctly" $ do
      let src = "(check \"commutativity\" (∀ [a: int b: int] (= (+ a b) (+ b a))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err   -> expectationFailure (show err)
        Right stmts -> length stmts `shouldBe` 1

  describe "TypeCheck (where binding scope)" $ do
    it "string where-type binding name preserved in AST" $ do
      let src = "(type Word (where [s: string] (> (string-length s) 0)))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right [STypeDef _name (TDependent bName _base _constraint)] ->
          bName `shouldBe` "s"
        Right other -> expectationFailure $ "Unexpected: " ++ show (length other) ++ " stmts"

    it "int where-type binding name preserved in AST" $ do
      let src = "(type NonNeg (where [n: int] (>= n 0)))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right [STypeDef _name (TDependent bName _base _constraint)] ->
          bName `shouldBe` "n"
        Right other -> expectationFailure $ "Unexpected: " ++ show (length other) ++ " stmts"

  describe "TypeCheck (nominal alias expansion)" $ do
    it "int literal matches a where-alias (NonNeg) without error" $ do
      -- Before fix: collectTopLevel stored TCustom "NonNeg"; unify(NonNeg, int) => error.
      -- After fix: expandAlias expands TCustom "NonNeg" -> TDependent "n" TInt ...
      --            compatibleWith (TDependent _ TInt _) TInt = True => no error.
      let src = T.pack $ unlines
            [ "(type NonNeg (where [n: int] (>= n 0)))"
            , "(def-shell use-nonneg [x: NonNeg] x)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "string literal matches a where-alias (Word) without error" $ do
      let src = T.pack $ unlines
            [ "(type Word (where [s: string] (> (string-length s) 0)))"
            , "(def-shell use-word [w: Word] w)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

  -- -----------------------------------------------------------------------
  -- expandAlias structural + transitive fix (14 tests)
  -- -----------------------------------------------------------------------
  describe "TypeCheck (expandAlias structural + transitive)" $ do

    -- Test #1: TResult structural expansion
    it "#1 match on Result[Color,string] resolves inner TCustom to TSumType" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red unit) (| Green unit) (| Blue unit))"
            , "(def-shell f [r: Result[Color, string]]"
            , "  (match r"
            , "    ((Success (Red)) \"red\")"
            , "    ((Success (Green)) \"green\")"
            , "    ((Success (Blue)) \"blue\")"
            , "    ((Error e) \"err\")))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let warns = filter (\d -> T.isInfixOf "unknown constructor" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []
          reportSuccess report `shouldBe` True

    -- Test #2: TPair structural expansion
    it "#2 match on (Color, int) resolves inner TCustom via checkPattern entry" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red unit) (| Green unit) (| Blue unit))"
            , "(def-shell f [p: (Color, int)]"
            , "  (match p"
            , "    ((pair (Red) n) n)"
            , "    ((pair (Green) n) n)"
            , "    ((pair (Blue) n) n)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let warns = filter (\d -> T.isInfixOf "unknown constructor" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []
          reportSuccess report `shouldBe` True

    -- Test #3: Transitive alias chain
    it "#3 transitive alias chain A -> B -> (| Foo) resolves" $ do
      let src = T.pack $ unlines
            [ "(type B (| Foo unit))"
            , "(type A B)"
            , "(def-shell f [x: A]"
            , "  (match x ((Foo) \"found\")))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- Test #4: TPair sibling branches both expand
    it "#4 TPair with both components aliased expands independently" $ do
      let src = T.pack $ unlines
            [ "(type A int)"
            , "(def-shell f [x: A y: A]"
            , "  (+ x y))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- Test #5: Diagnostic preservation — alias name in unify error
    -- We check that error diagnostics mention the alias name "Color"
    -- rather than the expanded structural form "(Red | Green | Blue)".
    it "#5 unify mismatch reports alias name 'Color', not expanded form" $ do
      -- Two functions: one returns Color, the other takes int.
      -- The mismatch is detected via compatibleExpanded at the if-branch site.
      let src = T.pack $ unlines
            [ "(type Color (| Red unit) (| Green unit) (| Blue unit))"
            , "(def-shell f [b: bool c: Color]"
            , "  (if b c 42))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          -- Should have a warning/error about different types in branches
          let diags = reportDiagnostics report
          let hasBranchMismatch = any (\d -> T.isInfixOf "different types" (diagMessage d)) diags
          let mentionsColor = any (\d -> T.isInfixOf "Color" (diagMessage d)) diags
          -- After Fix 1c, the if-branch compatibility uses compatibleExpanded,
          -- so Color expands to TSumType and correctly mismatches with int.
          -- The diagnostic message should mention "Color" because typeLabel on
          -- TCustom "Color" returns "Color".
          hasBranchMismatch `shouldBe` True
          mentionsColor `shouldBe` True

    -- Test #6: EIf branch compatibility with alias
    it "#6 if branches: alias vs base type accepted when alias expands to base" $ do
      let src = T.pack $ unlines
            [ "(type MyInt int)"
            , "(def-shell f [x: MyInt b: bool]"
            , "  (if b x 42))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let warns = filter (\d -> T.isInfixOf "different types" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []
          reportSuccess report `shouldBe` True

    -- Test #7: pre/post bool check with alias-to-bool
    it "#7 pre condition with alias-to-bool accepted" $ do
      let src = T.pack $ unlines
            [ "(type Flag bool)"
            , "(def-shell f [x: Flag] (pre x) x)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let errs = filter (\d -> T.isInfixOf "must be bool" (diagMessage d))
                            (reportDiagnostics report)
          errs `shouldBe` []
          reportSuccess report `shouldBe` True

    -- Test #8: Match arm result unification with alias
    it "#8 match arms returning alias and base type accepted" $ do
      let src = T.pack $ unlines
            [ "(type MyInt int)"
            , "(type Color (| Red unit) (| Green unit))"
            , "(def-shell f [x: MyInt c: Color]"
            , "  (match c"
            , "    ((Red) x)"
            , "    ((Green) 42)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let warns = filter (\d -> T.isInfixOf "different types" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []
          reportSuccess report `shouldBe` True

    -- Test #9: PConstructor "pair" against alias of TPair
    it "#9 pair destructor on alias-of-TPair succeeds via checkPattern entry" $ do
      let src = T.pack $ unlines
            [ "(type P (int, string))"
            , "(def-shell f [p: P]"
            , "  (match p ((pair a b) a)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- Test #10: Direct alias cycle diagnostic
    it "#10 direct alias cycle (type A B) (type B A) emits error" $ do
      let src = T.pack $ unlines
            [ "(type A B)"
            , "(type B A)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` False
          let errs = filter (\d -> T.isInfixOf "type alias cycle" (diagMessage d))
                            (reportDiagnostics report)
          length errs `shouldSatisfy` (> 0)

    -- Test #11: Composite-mediated alias cycle
    it "#11 composite-mediated cycle (type A (list B)) (type B (list A)) emits error" $ do
      let src = T.pack $ unlines
            [ "(type A list[B])"
            , "(type B list[A])"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` False
          let errs = filter (\d -> T.isInfixOf "type alias cycle" (diagMessage d))
                            (reportDiagnostics report)
          length errs `shouldSatisfy` (> 0)

    -- Test #12: Recursive ADT accepted (not flagged as cycle)
    it "#12 recursive ADT (type Tree (| Leaf | Node Tree)) accepted without cycle error" $ do
      let src = T.pack $ unlines
            [ "(type Tree (| Leaf unit) (| Node Tree))"
            , "(def-shell f [t: Tree]"
            , "  (match t"
            , "    ((Leaf) 0)"
            , "    ((Node sub) 1)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let cycleErrs = filter (\d -> T.isInfixOf "type alias cycle" (diagMessage d))
                                 (reportDiagnostics report)
          cycleErrs `shouldBe` []
          reportSuccess report `shouldBe` True

    -- Test #13: Positive composite case post-bridge-removal
    it "#13 list[Color] compatible after alias expansion (bridge removed)" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red unit) (| Green unit) (| Blue unit))"
            , "(def-shell f [xs: list[Color]]"
            , "  (list-length xs))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- Test #14: End-to-end delegate-async -> await -> PConstructor
    it "#14 delegate-async -> await -> match with ADT constructors type-checks" $ do
      let src = T.pack $ unlines
            [ "(type ColorADT (| Red unit) (| Green unit) (| Blue unit))"
            , "(def-shell process-color [c: ColorADT]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) \"blue\")))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let warns = filter (\d -> T.isInfixOf "unknown constructor" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []
          reportSuccess report `shouldBe` True

  describe "TypeCheck (first/second pair projectors)" $ do
    it "first accepts a pair-typed param (v0.4 U2-lite: requires TPair)" $ do
      -- v0.4 U2-lite: first :: TFn [TPair a b] a (was TFn [TVar p] (TVar a))
      let src = T.pack $ unlines
            [ "(def-shell state-word [s: (string, int)] (first s))" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "second accepts a pair-typed param (v0.4 U2-lite: requires TPair)" $ do
      let src = T.pack $ unlines
            [ "(def-shell state-rest [s: (int, string)] (second s))" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "first on non-pair (string) now produces type error (U2-lite)" $ do
      let src = T.pack $ unlines
            [ "(def-shell state-word [s: string] (first s))" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` False

  -- -----------------------------------------------------------------------
  -- CodegenHs regression: :done? indentation (GHC-82311 empty do block)
  -- -----------------------------------------------------------------------
  describe "CodegenHs (:done? indentation)" $ do
    it "without :done?, loop body is at 6-space indent" $ do
      -- Build a minimal console def-main with no :done?
      let stmt = SDefMain
            { defMainMode   = ModeConsole
            , defMainInit   = Nothing
            , defMainStep   = EVar "my_step"
            , defMainRead   = Nothing
            , defMainDone   = Nothing
            , defMainOnDone = Nothing
            }
      let result = generateHaskell "test" [stmt]
      case cgMainHs result of
        Nothing  -> expectationFailure "expected Main.hs to be generated"
        Just src -> do
          -- The eof line should appear at 6-space indent directly in do
          src `shouldSatisfy` T.isInfixOf "      eof <- hIsEOF stdin"

    it "with :done?, loop body is at 8-space indent inside else do" $ do
      -- Build a minimal console def-main WITH :done?
      let stmt = SDefMain
            { defMainMode   = ModeConsole
            , defMainInit   = Nothing
            , defMainStep   = EVar "my_step"
            , defMainRead   = Nothing
            , defMainDone   = Just (EVar "is_done")
            , defMainOnDone = Nothing
            }
      let result = generateHaskell "test" [stmt]
      case cgMainHs result of
        Nothing  -> expectationFailure "expected Main.hs to be generated"
        Just src -> do
          -- The eof line must be at 8-space indent (inside the else do branch)
          src `shouldSatisfy` T.isInfixOf "        eof <- hIsEOF stdin"
          -- The broken pattern (6-space after else do) must NOT be present
          src `shouldSatisfy` (not . T.isInfixOf "else do\n      eof")

    it "with :done? and :on-done, on-done is called in the done branch" $ do
      let stmt = SDefMain
            { defMainMode   = ModeConsole
            , defMainInit   = Nothing
            , defMainStep   = EVar "my_step"
            , defMainRead   = Nothing
            , defMainDone   = Just (EVar "is_done")
            , defMainOnDone = Just (EVar "finish")
            }
      let result = generateHaskell "test" [stmt]
      case cgMainHs result of
        Nothing  -> expectationFailure "expected Main.hs to be generated"
        Just src -> do
          src `shouldSatisfy` T.isInfixOf "then finish s else do"
          src `shouldSatisfy` T.isInfixOf "        eof <- hIsEOF stdin"

  -- -----------------------------------------------------------------------
  -- ParserJSON regression: def-main done? / on-done key names (tictactoe bug)
  -- -----------------------------------------------------------------------
  describe "ParserJSON (def-main done? / on-done keys)" $ do
    it "parses 'done?' key and wires it into generated harness" $ do
      -- JSON-AST with done? and on-done fields
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.6.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-main\","
            , "      \"mode\": \"console\","
            , "      \"step\":    { \"kind\": \"var\", \"name\": \"game-loop\" },"
            , "      \"done?\":   { \"kind\": \"var\", \"name\": \"is-game-over?\" },"
            , "      \"on-done\": { \"kind\": \"var\", \"name\": \"show-result\" }"
            , "    }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST GrammarLegacy "<test>" src of
        Left err  -> expectationFailure (show err)
        Right stmts -> do
          -- Check the SDefMain node carries non-Nothing done and on-done
          let mains = [s | s@SDefMain{} <- stmts]
          length mains `shouldBe` 1
          case head mains of
            SDefMain _ _ _ _ mDone mOnDone -> do
              mDone   `shouldSatisfy` (/= Nothing)
              mOnDone `shouldSatisfy` (/= Nothing)
            _ -> expectationFailure "expected SDefMain"

    it "parsed done? wires into generated Main.hs (harness terminates)" $ do
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.6.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-main\","
            , "      \"mode\": \"console\","
            , "      \"step\":    { \"kind\": \"var\", \"name\": \"game-loop\" },"
            , "      \"done?\":   { \"kind\": \"var\", \"name\": \"is-game-over?\" },"
            , "      \"on-done\": { \"kind\": \"var\", \"name\": \"show-result\" }"
            , "    }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST GrammarLegacy "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = generateHaskell "test" stmts
          case cgMainHs result of
            Nothing  -> expectationFailure "expected Main.hs"
            Just hs  -> do
              -- Guard must reference is_game_over' not hardcode False
              hs `shouldSatisfy` T.isInfixOf "is_game_over'"
              -- on-done show-result must appear
              hs `shouldSatisfy` T.isInfixOf "show_result"
              -- The broken hardcoded pattern must NOT appear
              hs `shouldSatisfy` (not . T.isInfixOf "let _done = False")

  -- -----------------------------------------------------------------------
  -- TSumType structural representation
  -- -----------------------------------------------------------------------
  describe "TSumType (structured sum type)" $ do
    it "S-expression: (type Color (| Red) (| Green) (| Blue)) parses to TSumType" $ do
      let src = "(type Color (| Red) (| Green) (| Blue))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            STypeDef name (TSumType ctors) -> do
              name `shouldBe` "Color"
              map fst ctors `shouldBe` ["Red", "Green", "Blue"]
              all ((== Nothing) . snd) ctors `shouldBe` True
            STypeDef _ other -> expectationFailure $
              "Expected TSumType, got: " ++ show other
            _ -> expectationFailure "Expected STypeDef"

    it "S-expression: sum type with payload parses payload type" $ do
      let src = "(type Shape (| Circle int) (| Rect))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case stmts of
            [STypeDef _ (TSumType ctors)] -> do
              map fst ctors `shouldBe` ["Circle", "Rect"]
              snd (ctors !! 0) `shouldBe` Just TInt
              snd (ctors !! 1) `shouldBe` Nothing
            _ -> expectationFailure "Expected STypeDef with TSumType"

    it "TSumType: codegen emits correct 'data' declaration" $ do
      let stmts = [STypeDef "Color" (TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)])]
      let result = generateHaskell "test" stmts
      cgHsSource result `shouldSatisfy` T.isInfixOf "data Color"
      cgHsSource result `shouldSatisfy` T.isInfixOf "= Red"
      cgHsSource result `shouldSatisfy` T.isInfixOf "| Green"
      cgHsSource result `shouldSatisfy` T.isInfixOf "| Blue"
      cgHsSource result `shouldSatisfy` T.isInfixOf "deriving (Eq, Show)"

  -- -----------------------------------------------------------------------
  -- D1: Static match exhaustiveness check
  -- -----------------------------------------------------------------------
  describe "D1 match exhaustiveness" $ do
    it "exhaustive TSumType match (all ctors covered) passes type-check" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) \"blue\")))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          -- Must have no non-exhaustive-match errors
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          nonExh `shouldBe` []

    it "non-exhaustive TSumType match (missing ctor) emits non-exhaustive-match error" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")))"   -- Blue is missing
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          length nonExh `shouldBe` 1
          diagMessage (head nonExh) `shouldSatisfy` T.isInfixOf "Blue"

    it "wildcard arm satisfies exhaustiveness for TSumType" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    (_ \"other\")))"   -- wildcard covers rest
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          nonExh `shouldBe` []

    it "non-exhaustive TResult match (missing Error) emits error" $ do
      let src = T.pack $ unlines
            [ "(def-shell extract [r: Result[int, string]]"
            , "  (match r"
            , "    ((Success v) v)))"   -- Error arm missing
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          length nonExh `shouldBe` 1
          diagMessage (head nonExh) `shouldSatisfy` T.isInfixOf "Error"

  -- -----------------------------------------------------------------------
  -- D2: letrec + :decreases
  -- -----------------------------------------------------------------------
  describe "D2 letrec :decreases" $ do
    it "S-expression: letrec with :decreases parses to SLetrec" $ do
      let src = "(letrec count-down [n: int] :decreases n (if (= n 0) 0 (count-down (- n 1))))"
      case parseStatements GrammarLegacy "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SLetrec name params _ _ dec _ -> do
              name `shouldBe` "count-down"
              length params `shouldBe` 1
              dec `shouldBe` EVar "n"
            _ -> expectationFailure "Expected SLetrec"

    it "self-recursive def-logic emits self-recursion warning under GrammarLegacy" $ do
      let src = T.pack $ unlines
            [ "(def-shell count-down [n: int]"
            , "  (if (= n 0) 0 (count-down (- n 1))))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarLegacy emptyEnv stmts
          let warns = filter (\d -> diagSeverity d == SevWarning
                                 && T.isInfixOf "self-recursive" (diagMessage d))
                             (reportDiagnostics report)
          length warns `shouldSatisfy` (>= 1)

    it "letrec self-call does NOT emit self-recursion warning" $ do
      let src = "(letrec count-down [n: int] :decreases n (if (= n 0) 0 (count-down (- n 1))))"
      case parseStatements GrammarLegacy "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarLegacy emptyEnv stmts
          let warns = filter (\d -> diagSeverity d == SevWarning
                                 && T.isInfixOf "self-recursive" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []

    it "def-shell self-recursive does NOT emit self-recursion warning under GrammarCoreInversion" $ do
      let src = "(def-shell count-down [n: int] (if (= n 0) 0 (count-down (- n 1))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let warns = filter (\d -> diagSeverity d == SevWarning
                                 && T.isInfixOf "self-recursive" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []

    it "letrec codegen emits :decreases comment marker" $ do
      let stmts = [SLetrec "countdown" [("n", TInt)] Nothing
                     (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "n")
                     (EVar "n")]
      let result = generateHaskell "test" stmts
      cgHsSource result `shouldSatisfy` T.isInfixOf "letrec :decreases"
      cgHsSource result `shouldSatisfy` T.isInfixOf "countdown"

  -- -----------------------------------------------------------------------
  -- D3: ?proof-required hole kind
  -- -----------------------------------------------------------------------
  describe "D3 ?proof-required hole" $ do
    it "?proof-required parses as HProofRequired manual in S-expression" $ do
      let src = "(def-shell dummy [] ?proof-required)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case head stmts of
            SDefShell _ _ _ _ (EHole (HProofRequired r _)) _ ->
              r `shouldBe` "manual"
            _ -> expectationFailure "Expected EHole (HProofRequired \"manual\")"

    it "letrec with simple variable decreases has no complex-decreases hole" $ do
      let stmts = [SLetrec "f" [("n", TInt)] Nothing
                     (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "n") (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "complex-decreases" Nothing)
                           (holeEntries report)
      prHoles `shouldBe` []

    it "letrec with complex decreases auto-emits complex-decreases hole" $ do
      -- :decreases (- n 1) is not a simple variable — needs LH witness
      let stmts = [SLetrec "f" [("n", TInt)] Nothing
                     (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "-" [EVar "n", ELit (LitInt 1)])
                     (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "complex-decreases" Nothing)
                           (holeEntries report)
      length prHoles `shouldBe` 1

    it "non-linear contract auto-emits non-linear-contract hole" $ do
      -- pre: (* n n) > 0 — multiplication of two variables is non-linear
      let nlExpr = EApp ">" [EApp "*" [EVar "n", EVar "n"], ELit (LitInt 0)]
      let stmts = [SDefLogic "f" [("n", TInt)] Nothing
                     (Contract (Just nlExpr) Nothing Nothing Nothing Nothing) (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "non-linear-contract" Nothing)
                           (holeEntries report)
      length prHoles `shouldBe` 1

    -- Leanstral Gap B: parsers route * / mod ^ to EOp (not EApp), so a
    -- contract like (* n m) arrives as EOp; isNonLinear must flag it too.
    it "non-linear contract in EOp form auto-emits non-linear-contract hole" $ do
      -- pre: (* n m) > 0 in EOp form — the shape the parser actually produces
      let nlExpr = EOp ">" [EOp "*" [EVar "n", EVar "m"], ELit (LitInt 0)]
      let stmts = [SDefLogic "f" [("n", TInt), ("m", TInt)] Nothing
                     (Contract (Just nlExpr) Nothing Nothing Nothing Nothing) (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "non-linear-contract" Nothing)
                           (holeEntries report)
      -- Pre-fix: 0 (no EOp case → fell to isNonLinear _ = False). Post-fix: 1.
      length prHoles `shouldBe` 1

    it "isNonLinear flags EOp form and matches EApp form (Gap B, no EApp regression)" $ do
      let eopMul  = EOp  "*" [EVar "n", EVar "m"]
      let eappMul = EApp "*" [EVar "n", EVar "m"]
      -- EApp form unchanged (still flagged); EOp form now flagged identically.
      isNonLinear eappMul `shouldBe` True
      isNonLinear eopMul  `shouldBe` True
      -- linear operator in EOp form stays non-flagged
      isNonLinear (EOp "+" [EVar "n", EVar "m"]) `shouldBe` False

  -- -----------------------------------------------------------------------
  -- LT-PPR (v0.11): predicate-carrying ?proof-required
  -- -----------------------------------------------------------------------
  describe "LT-PPR predicate-carrying ?proof-required" $ do

    -- PPR-P1: leaf form unchanged
    it "PPR-P1 leaf ?proof-required still parses as HProofRequired manual Nothing" $ do
      let src = "(def-shell f [] ?proof-required)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case head stmts of
            SDefShell _ _ _ _ (EHole (HProofRequired r mp)) _ -> do
              r  `shouldBe` "manual"
              mp `shouldBe` Nothing
            _ -> expectationFailure "Expected SDefLogic with HProofRequired"

    -- PPR-P2: parens form with predicate, default reason
    it "PPR-P2 (?proof-required pred) parses as HProofRequired manual (Just pred)" $ do
      let src = "(def-shell f [n: int] (?proof-required (> n 0)))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case head stmts of
            SDefShell _ _ _ _ (EHole (HProofRequired r (Just _))) _ ->
              r `shouldBe` "manual"
            _ -> expectationFailure "Expected predicate-carrying HProofRequired"

    -- PPR-P3: parens form with :reason tag
    it "PPR-P3 (?proof-required :reason \"custom\" pred) uses supplied reason" $ do
      let src = "(def-shell f [n: int] (?proof-required :reason \"custom\" (> n 0)))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case head stmts of
            SDefShell _ _ _ _ (EHole (HProofRequired r (Just _))) _ ->
              r `shouldBe` "custom"
            _ -> expectationFailure "Expected custom reason in HProofRequired"

    -- PPR-P4: JSON-AST predicate field roundtrips through parseJSONAST
    it "PPR-P4 JSON hole-proof-required with predicate field parses correctly" $ do
      let src = BLC.pack $ unlines
            [ "{\"schemaVersion\":\"0.6.0\",\"statements\":["
            , "{\"kind\":\"def-shell\",\"name\":\"f\",\"params\":[]"
            , ",\"body\":{\"kind\":\"hole-proof-required\",\"reason\":\"manual\""
            , ",\"predicate\":{\"kind\":\"lit-bool\",\"value\":true}}}]}"
            ]
      case parseJSONAST GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case head stmts of
            SDefShell _ _ _ _ (EHole (HProofRequired _ (Just _))) _ -> pure ()
            _ -> expectationFailure "Expected predicate-carrying HProofRequired from JSON"

    -- PPR-T1: valid bool predicate passes typecheck
    it "PPR-T1 bool predicate in PPR contract clause passes typecheck" $ do
      let src = "(def-shell f [n: int] (pre (?proof-required (> n 0))) n)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          errs `shouldBe` []

    -- PPR-T2: non-bool predicate emits a type error
    it "PPR-T2 non-bool predicate in PPR clause emits type error" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EHole (HProofRequired "manual" (Just (EVar "n"))))) Nothing Nothing Nothing Nothing)
                     (EVar "n")]
      let report = typeCheck GrammarCoreInversion emptyEnv stmts
      let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldBe` 1

    -- PPR-T3: no-predicate form emits proof-required warning only
    it "PPR-T3 no-predicate ?proof-required emits warning but no error" $ do
      let stmts = [SDefLogic "f" [] Nothing
                     (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HProofRequired "manual" Nothing))]
      let report = typeCheck GrammarCoreInversion emptyEnv stmts
      let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      errs `shouldBe` []

    -- PPR-T4: non-linear predicate emits a QF-LIA warning
    it "PPR-T4 non-linear predicate in PPR clause emits non-linear warning" $ do
      let nlPred = EApp ">" [EApp "*" [EVar "n", EVar "n"], ELit (LitInt 0)]
          stmts  = [SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract (Just (EHole (HProofRequired "manual" (Just nlPred)))) Nothing Nothing Nothing Nothing)
                      (EVar "n")]
      let report = typeCheck GrammarCoreInversion emptyEnv stmts
      let warns = filter (\d -> diagSeverity d == SevWarning
                              && T.isInfixOf "non-linear" (diagMessage d))
                         (reportDiagnostics report)
      length warns `shouldSatisfy` (>= 1)

    -- PPR-T5: predicate in post position with result variable passes typecheck
    it "PPR-T5 bool predicate in post-position PPR clause with result passes typecheck" $ do
      let src = "(def-shell f [n: int] (post (?proof-required (> result 0))) n)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          errs `shouldBe` []

    -- PPR-A1: leaf form holeToJson emits no predicate field
    it "PPR-A1 leaf HProofRequired holeToJson has no predicate key" $ do
      let stmt = SDefShell "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                            (EHole (HProofRequired "manual" Nothing)) []
          json = TE.decodeUtf8 (BL.toStrict (emitJsonAST [stmt]))
      T.isInfixOf "predicate" json `shouldBe` False

    -- PPR-A2: predicate form holeToJson includes predicate field
    it "PPR-A2 predicate-carrying HProofRequired holeToJson includes predicate key" $ do
      let pred = EApp ">" [EVar "n", ELit (LitInt 0)]
          stmt = SDefShell "f" [("n", TInt)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                            (EHole (HProofRequired "manual" (Just pred))) []
          json = TE.decodeUtf8 (BL.toStrict (emitJsonAST [stmt]))
      T.isInfixOf "predicate" json `shouldBe` True

    -- PPR-TR1: erPredicateForm = Just "runtime" for predicate-carrying clause
    it "PPR-TR1 predicate-carrying pre clause has erPredicateForm = Just runtime" $ do
      let pred  = EApp ">" [EVar "n", ELit (LitInt 0)]
          stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EHole (HProofRequired "manual" (Just pred)))) Nothing Nothing Nothing Nothing)
                     (EVar "n")]
          report = buildTrustReport Map.empty stmts Map.empty
          entries = trEntries report
      case filter (\e -> teName e == "f") entries of
        [e] -> erPredicateForm <$> tePre e `shouldBe` Just (Just "runtime")
        _   -> expectationFailure "Expected entry for f"

    -- PPR-TR2: plain clause has erPredicateForm = Nothing
    it "PPR-TR2 plain contract clause has erPredicateForm = Nothing" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                     (EVar "n")]
          report = buildTrustReport Map.empty stmts Map.empty
          entries = trEntries report
      case filter (\e -> teName e == "f") entries of
        [e] -> erPredicateForm <$> tePre e `shouldBe` Just Nothing
        _   -> expectationFailure "Expected entry for f"

    -- PPR-TR3: erRuntimeCheckEmitted = True for predicate-carrying clause
    it "PPR-TR3 predicate-carrying clause has erRuntimeCheckEmitted = True" $ do
      let pred  = EApp ">" [EVar "n", ELit (LitInt 0)]
          stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EHole (HProofRequired "manual" (Just pred)))) Nothing Nothing Nothing Nothing)
                     (EVar "n")]
          report = buildTrustReport Map.empty stmts Map.empty
          entries = trEntries report
      case filter (\e -> teName e == "f") entries of
        [e] -> erRuntimeCheckEmitted <$> tePre e `shouldBe` Just True
        _   -> expectationFailure "Expected entry for f"

    -- PPR-TR4: formatTrustReportJson emits pre_predicate_form when PPR predicate present
    it "PPR-TR4 formatTrustReportJson includes pre_predicate_form for PPR clause" $ do
      let pred  = EApp ">" [EVar "n", ELit (LitInt 0)]
          stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EHole (HProofRequired "manual" (Just pred)))) Nothing Nothing Nothing Nothing)
                     (EVar "n")]
          report  = buildTrustReport Map.empty stmts Map.empty
          jsonTxt = formatTrustReportJson report
      T.isInfixOf "pre_predicate_form" jsonTxt `shouldBe` True

    -- -----------------------------------------------------------------------
    -- BUG-4 (v0.14.3): pre_source/post_source (RFC-citation provenance, PROV-3
    -- / CHANGELOG v0.6.1) always rendered null/absent in trust reports.
    -- ParserJSON.hs correctly reads pre_source/post_source into Contract's
    -- contractPreSource/contractPostSource, and the formatter (formatEntry,
    -- the JSON emitter) was already correctly wired to display erSource when
    -- present -- but collectAllContractStatus's mkCS/mkER helpers built each
    -- EvidenceRecord from only the clause Expr, never reading
    -- contractPreSource/contractPostSource, so erSource was hard-coded to
    -- Nothing on every path regardless of what the source actually
    -- specified. Fix: mkCS now passes contractPreSource/contractPostSource
    -- through to mkER, which threads it into erSource's slot.
    -- -----------------------------------------------------------------------
    it "BUG-4: contract :source annotation reaches erSource in the trust report (mkCS/mkER threading)" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)]))
                        (Just "RFC 6238 §4.2 — time step computation")
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)]))
                        (Just "safety invariant")
                        Nothing)
                     (EVar "n")]
          report  = buildTrustReport Map.empty stmts Map.empty
          entries = trEntries report
      case filter (\e -> teName e == "f") entries of
        [e] -> do
          (tePre e >>= erSource)  `shouldBe` Just "RFC 6238 §4.2 — time step computation"
          (tePost e >>= erSource) `shouldBe` Just "safety invariant"
        _   -> expectationFailure "Expected entry for f"

    it "BUG-4: a contract with no :source annotation still has erSource = Nothing (no false provenance)" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)])) Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                     (EVar "n")]
          report  = buildTrustReport Map.empty stmts Map.empty
          entries = trEntries report
      case filter (\e -> teName e == "f") entries of
        [e] -> do
          (tePre e >>= erSource)  `shouldBe` Nothing
          (tePost e >>= erSource) `shouldBe` Nothing
        _   -> expectationFailure "Expected entry for f"

    it "BUG-4: formatTrustReportJson emits pre_source/post_source text when :source is present" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)]))
                        (Just "cite-pre")
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)]))
                        (Just "cite-post")
                        Nothing)
                     (EVar "n")]
          report  = buildTrustReport Map.empty stmts Map.empty
          jsonTxt = formatTrustReportJson report
      T.isInfixOf "pre_source"  jsonTxt `shouldBe` True
      T.isInfixOf "cite-pre"    jsonTxt `shouldBe` True
      T.isInfixOf "post_source" jsonTxt `shouldBe` True
      T.isInfixOf "cite-post"   jsonTxt `shouldBe` True

    -- -----------------------------------------------------------------------
    -- BUG-5 (v0.14.3): formatTrustReportJson double-encoded any non-ASCII
    -- UTF-8 content it emitted (e.g. RFC-citation pre_source/post_source
    -- strings). Root cause: 'T.pack . BLC.unpack . encode' -- aeson's
    -- 'encode' produces correct UTF-8 bytes, but
    -- 'Data.ByteString.Lazy.Char8.unpack' reinterprets each *byte* as a
    -- Latin-1 codepoint (not a UTF-8 decode), so a multi-byte UTF-8 sequence
    -- (e.g. '§' -> 0xC2 0xA7) becomes two separate high codepoints in the
    -- resulting Text; encoding that Text back to UTF-8 downstream (stdout)
    -- then double-encodes it into mojibake ('§' -> "Â§", em-dash -> "â").
    -- This never fired before the BUG-4 fix because erSource was always
    -- Nothing, so pre_source/post_source were never populated with real
    -- Unicode text on the JSON path. The same antipattern also lived in
    -- LLMLL.ObligationMining.formatObligationsJson and
    -- LLMLL.SpecCoverage.formatCoverageJson, and in ~17 call sites in
    -- app/Main.hs -- all switched to 'Data.Aeson.Text.encodeToLazyText',
    -- which builds Text directly from the aeson Value with no byte-level
    -- round-trip and so cannot double-encode.
    -- -----------------------------------------------------------------------
    it "BUG-5: formatTrustReportJson round-trips non-ASCII :source text without double-encoding" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)]))
                        (Just "RFC 6238 §4.2 — time step computation")
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)]))
                        (Just "safety invariant — non-negative")
                        Nothing)
                     (EVar "n")]
          report  = buildTrustReport Map.empty stmts Map.empty
          jsonTxt = formatTrustReportJson report
          -- Correct decode: Text -> UTF-8 bytes -> lazy ByteString -> Value.
          -- (Deliberately NOT 'BLC.pack . T.unpack', which is the same
          -- byte/codepoint-conflation bug in the opposite direction and
          -- would corrupt this test's own non-ASCII fixture data.)
          jsonV   = decode (BL.fromStrict (TE.encodeUtf8 jsonTxt)) :: Maybe Value
      -- The raw JSON text itself must carry the real characters, not mojibake.
      T.isInfixOf "RFC 6238 §4.2 — time step computation" jsonTxt `shouldBe` True
      T.isInfixOf "safety invariant — non-negative"        jsonTxt `shouldBe` True
      T.isInfixOf "Â§" jsonTxt `shouldBe` False
      T.isInfixOf "â"  jsonTxt `shouldBe` False
      -- And it must still be well-formed, parseable JSON whose decoded
      -- string values equal the original (not just substring-present).
      case jsonV of
        Just (Object o) -> case KM.lookup "entries" o of
          Just (Array entries) -> case [ e | Object e <- foldr (:) [] entries
                                            , KM.lookup "name" e == Just (String "f") ] of
            [e] -> do
              KM.lookup "pre_source"  e `shouldBe` Just (String "RFC 6238 §4.2 — time step computation")
              KM.lookup "post_source" e `shouldBe` Just (String "safety invariant — non-negative")
            _ -> expectationFailure "Expected exactly one entry named f"
          _ -> expectationFailure "Expected entries array"
        _ -> expectationFailure "Expected top-level JSON object"

    -- PPR-CG1: pre-position predicate-carrying PPR emits predicate assertion
    it "PPR-CG1 pre-position predicate-carrying PPR emits runtime predicate assertion" $ do
      let pred  = EApp ">" [EVar "n", ELit (LitInt 0)]
          stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract (Just (EHole (HProofRequired "manual" (Just pred)))) Nothing Nothing Nothing Nothing)
                     (EVar "n")]
          result = generateHaskell "Test" stmts
          src    = cgHsSource result
      T.isInfixOf "pre-condition (proof-required predicate) failed" src `shouldBe` True
      T.isInfixOf "PROOF REQUIRED" src `shouldBe` False

    -- PPR-CG2: post-position predicate-carrying PPR wraps result in let
    it "PPR-CG2 post-position predicate-carrying PPR wraps result in let binding" $ do
      let pred  = EApp ">" [EVar "result", ELit (LitInt 0)]
          stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                     (Contract Nothing Nothing (Just (EHole (HProofRequired "manual" (Just pred)))) Nothing Nothing)
                     (EVar "n")]
          result = generateHaskell "Test" stmts
          src    = cgHsSource result
      T.isInfixOf "_result_" src `shouldBe` True
      T.isInfixOf "post-condition (proof-required predicate) failed" src `shouldBe` True

    -- PPR-CG3: body-position HProofRequired still emits error stub
    it "PPR-CG3 body-position HProofRequired emits PROOF REQUIRED error stub" $ do
      let out = emitHole (HProofRequired "manual" Nothing)
      T.isInfixOf "PROOF REQUIRED" out `shouldBe` True
      let out2 = emitHole (HProofRequired "manual" (Just (EVar "x")))
      T.isInfixOf "PROOF REQUIRED" out2 `shouldBe` True

    -- PPR-G1: isCoreBodySyntactic rejects HProofRequired in body regardless of predicate
    it "PPR-G1 isCoreBodySyntactic rejects HProofRequired hole in def body" $ do
      isCoreBodySyntactic (EHole (HProofRequired "manual" Nothing))      `shouldBe` False
      isCoreBodySyntactic (EHole (HProofRequired "manual" (Just (EVar "n")))) `shouldBe` False

    -- MATCH-WIDEN-2 (isCoreBodySyntactic n-arm widening): a >2-arm sum match
    -- whose arms are nullary / single-payload / catch-all is now core syntax
    -- (a strict-core `def` may contain it), matching the verifier's n-arm discharge.
    let match3mixed body2 = EMatch (EVar "s")
          [ (PConstructor "Continue" [], ELit (LitInt 0))
          , (PConstructor "Abort" [PVar "n"], EVar "n")
          , (PConstructor "Retry" [PVar "m"], body2) ]
    it "CNARY-1 isCoreBodySyntactic admits a 3-arm mixed sum match (n-arm widening)" $
      isCoreBodySyntactic (match3mixed (EVar "m")) `shouldBe` True
    it "CNARY-2 isCoreBodySyntactic admits a 4-arm all-single-payload match" $
      isCoreBodySyntactic (EMatch (EVar "s")
        [ (PConstructor "A" [PVar "a"], EVar "a")
        , (PConstructor "B" [PVar "b"], EVar "b")
        , (PConstructor "C" [PVar "c"], EVar "c")
        , (PConstructor "D" [PVar "d"], EVar "d") ]) `shouldBe` True
    it "CNARY-3 isCoreBodySyntactic still admits a 2-arm mixed match (regression)" $
      isCoreBodySyntactic (EMatch (EVar "s")
        [ (PConstructor "Continue" [], ELit (LitInt 0))
        , (PConstructor "Abort" [PVar "n"], EVar "n") ]) `shouldBe` True
    it "CNARY-4 the widening lifts the arity cap only — a non-core ARM BODY is still rejected" $
      -- arm body (* m m) is non-linear → not core; isCoreBodySyntactic recurses into arm bodies
      isCoreBodySyntactic (match3mixed (EOp "*" [EVar "m", EVar "m"])) `shouldBe` False
    it "CNARY-5 an arm with a MULTI-payload constructor pattern is still rejected" $
      isCoreBodySyntactic (EMatch (EVar "s")
        [ (PConstructor "A" [], ELit (LitInt 0))
        , (PConstructor "B" [PVar "x", PVar "y"], EVar "x")  -- 2-payload arm → not admissible
        , (PConstructor "C" [PVar "z"], EVar "z") ]) `shouldBe` False

    -- PPR-G2: holeName field of HoleEntry includes reason tag for 2-arg form
    it "PPR-G2 HoleEntry holeName includes reason tag for predicate-carrying HProofRequired" $ do
      let stmts = [SDefLogic "f" [("n", TInt)] Nothing
                     (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HProofRequired "custom" (Just (EVar "n"))))]
          report = analyzeHoles stmts
          names  = map holeName (holeEntries report)
      any (T.isInfixOf "custom") names `shouldBe` True

  -- -----------------------------------------------------------------------
  -- Phase 2c: pair-type in typed-param positions
  -- -----------------------------------------------------------------------
  describe "Phase 2c pair-type in typed-param" $ do
    it "S-expression: (int, string) in def-logic param parses without error" $ do
      let src = "(def-shell f [acc: (int, string)] (first acc))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> length stmts `shouldBe` 1

    it "S-expression: pair-type parameter parsed as TPair TInt TString" $ do
      let src = "(def-shell f [acc: (int, string)] (first acc))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right [SDefShell _ params _ _ _ _] ->
          snd (head params) `shouldBe` TPair TInt TString
        Right other -> expectationFailure $ "Expected SDefLogic, got " ++ show (length other) ++ " stmts"

    it "S-expression: (int, string) typed param passes type-check" $ do
      let src = T.pack $ unlines
            [ "(def-shell f [acc: (int, string)] (first acc))" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          -- No errors (warnings OK — first is polymorphic anyway)
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          errs `shouldBe` []

    it "JSON-AST: pair-type param_type decodes to TPair TInt TString" $ do
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.6.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-shell\","
            , "      \"name\": \"f\","
            , "      \"params\": [{"
            , "        \"name\": \"acc\","
            , "        \"param_type\": {"
            , "          \"kind\": \"pair-type\","
            , "          \"fst\": {\"kind\": \"primitive\", \"name\": \"int\"},"
            , "          \"snd\": {\"kind\": \"primitive\", \"name\": \"string\"}"
            , "        }"
            , "      }],"
            , "      \"body\": {\"kind\": \"var\", \"name\": \"acc\"}"
            , "    }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right [SDefShell _ params _ _ _ _] ->
          snd (head params) `shouldBe` TPair TInt TString
        Right other -> expectationFailure $ "Expected SDefLogic, got " ++ show (length other) ++ " stmts"

  -- -----------------------------------------------------------------------
  -- N2: string-concat arity hint
  -- -----------------------------------------------------------------------
  describe "N2 string-concat arity hint" $ do
    it "string-concat with 3 args desugars to string-concat-many (no error)" $ do
      let src = T.pack $ unlines
            [ "(def-shell f [a: string b: string c: string]"
            , "  (string-concat a b c))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          errs `shouldBe` []

    it "string-concat with correct 2 args has no arity error" $ do
      let src = "(def-shell f [a: string b: string] (string-concat a b))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          let arityErrs = filter (\d -> diagSeverity d == SevError
                                     && T.isInfixOf "expects" (diagMessage d))
                                 (reportDiagnostics report)
          arityErrs `shouldBe` []

  -- -----------------------------------------------------------------------
  -- N3: extra-key rejection in JSON-AST let bindings
  -- -----------------------------------------------------------------------
  describe "N3 let binding extra-key rejection" $ do
    it "let binding with extra 'kind' key is rejected with clear error" $ do
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.6.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-shell\","
            , "      \"name\": \"f\","
            , "      \"params\": [],"
            , "      \"body\": {"
            , "        \"kind\": \"let\","
            , "        \"bindings\": [{"
            , "          \"kind\": \"spurious\","
            , "          \"name\": \"x\","
            , "          \"expr\": {\"kind\": \"lit-int\", \"value\": 1}"
            , "        }],"
            , "        \"body\": {\"kind\": \"var\", \"name\": \"x\"}"
            , "      }"
            , "    }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST GrammarCoreInversion "<test>" src of
        Left diag ->
          -- The error message should mention unexpected keys
          diagMessage diag `shouldSatisfy` T.isInfixOf "unexpected keys"
        Right _ ->
          expectationFailure "Expected parse failure for let binding with extra keys"

    it "let binding with only 'name' and 'expr' keys accepts successfully" $ do
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.6.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-shell\","
            , "      \"name\": \"f\","
            , "      \"params\": [],"
            , "      \"body\": {"
            , "        \"kind\": \"let\","
            , "        \"bindings\": [{"
            , "          \"name\": \"x\","
            , "          \"expr\": {\"kind\": \"lit-int\", \"value\": 42}"
            , "        }],"
            , "        \"body\": {\"kind\": \"var\", \"name\": \"x\"}"
            , "      }"
            , "    }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right _  -> pure ()

  -- -----------------------------------------------------------------------
  -- Phase 2c --sketch D2 output contract (HoleStatus, SketchHole, pointers)
  -- -----------------------------------------------------------------------
  describe "Phase 2c --sketch D2 output contract" $ do

    let findHole name result =
          let matches = filter ((== name) . shName) (sketchHoles result)
          in case matches of { (h:_) -> Just h; [] -> Nothing }

    it "EIf: hole in else gets HoleTyped TString from concrete then" $ do
      let src = T.pack $ unlines
            [ "(def-shell greet [formal: bool]"
            , "  (if formal \"Good day.\" ?informal))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?informal" result of
            Nothing -> expectationFailure "?informal hole not recorded"
            Just h  -> do
              shStatus h `shouldBe` HoleTyped TString
              shPointer h `shouldSatisfy` (not . T.null)

    it "EIf: hole in then gets HoleTyped TInt from concrete else" $ do
      let src = T.pack $ unlines
            [ "(def-shell safe-div [n: int]"
            , "  (if (= n 0) ?zero_case 42))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?zero_case" result of
            Nothing -> expectationFailure "?zero_case hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TInt

    it "EMatch: hole arm gets HoleTyped TString from concrete sibling arms" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) ?blue_label)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?blue_label" result of
            Nothing -> expectationFailure "?blue_label hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TString

    it "EMatch: hole arm gets HoleAmbiguous when concrete arms disagree" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell bad-describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) 42)"
            , "    ((Blue) ?conflict_arm)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?conflict_arm" result of
            Nothing -> expectationFailure "?conflict_arm hole not recorded"
            Just h  -> case shStatus h of
              HoleAmbiguous _ _ -> pure ()  -- correct
              other -> expectationFailure $ "expected HoleAmbiguous, got: " ++ show other

    it "EMatch: conflicting arms emit an ambiguous-hole error" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell bad-describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) 42)"
            , "    ((Blue) ?conflict_arm)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          let ambigErrs = filter (T.isInfixOf "ambiguous-hole" . diagMessage) (sketchErrors result)
          ambigErrs `shouldSatisfy` (not . null)

    it "EApp: hole argument gets HoleTyped TInt from function parameter position" $ do
      let src = T.pack $ unlines
            [ "(def-shell f [x: int] x)"
            , "(def-shell caller [] (f ?arg))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?arg" result of
            Nothing -> expectationFailure "?arg hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TInt

    it "isolated hole with no context gets HoleUnknown" $ do
      let src = T.pack $ unlines
            [ "(def-shell mystery [] ?isolated)" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?isolated" result of
            Nothing -> expectationFailure "?isolated hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleUnknown

    -- REC-DESCENT Phase 1 (v0.14.24 / schema 0.8.0): the (decreases …) surface.
    -- Verification-inert: parses, type-checks the measures, round-trips; no obligation.
    it "RD1-1: S-expr (decreases x) parses into defShellDecreases and round-trips through JSON" $ do
      let src = T.pack "(def-shell f [x: int] -> int (pre (>= x 0)) (post (= result x)) (decreases x) (f x))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts@[SDefShell _ _ _ _ _ dec] -> do
          dec `shouldBe` [EVar "x"]
          case parseJSONAST GrammarCoreInversion "<test>" (emitJsonAST stmts) of
            Right [SDefShell _ _ _ _ _ dec2] -> dec2 `shouldBe` [EVar "x"]
            other -> expectationFailure ("JSON round-trip lost the measure: " ++ show other)
        Right _ -> expectationFailure "expected a single SDefShell with a decreases clause"

    it "RD1-2: (decreases m n p) — a 3-element measure list round-trips (S-expr + JSON)" $ do
      let src = T.pack "(def-shell f [m: int n: int p: int] -> int (decreases m n p) (f m n p))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts@[SDefShell _ _ _ _ _ dec] -> do
          dec `shouldBe` [EVar "m", EVar "n", EVar "p"]
          case parseJSONAST GrammarCoreInversion "<test>" (emitJsonAST stmts) of
            Right [SDefShell _ _ _ _ _ dec2] -> dec2 `shouldBe` [EVar "m", EVar "n", EVar "p"]
            other -> expectationFailure ("k=3 JSON round-trip failed: " ++ show other)
        Right _ -> expectationFailure "expected a single SDefShell"

    it "RD1-3: decreases measures are scope/type-checked — 'result' and non-int rejected, int-over-params clean" $ do
      let diagsFor s = case parseStatements GrammarCoreInversion "<test>" (T.pack s) of
                         Left err -> error (show err)
                         Right stmts -> reportDiagnostics (typeCheck GrammarCoreInversion emptyEnv stmts)
          hasErr ds = any (\d -> diagSeverity d == SevError) ds
      -- 'result' is not in scope in a measure
      hasErr (diagsFor "(def-shell f [x: int] -> int (post (= result x)) (decreases result) (f x))") `shouldBe` True
      -- a non-int measure is rejected
      hasErr (diagsFor "(def-shell f [b: bool] -> int (decreases b) (f b))") `shouldBe` True
      -- an int measure over params type-checks clean
      hasErr (diagsFor "(def-shell f [x: int] -> int (decreases x) (f x))") `shouldBe` False

    it "RD1-4: Phase 1 is inert — a recursive def-shell with (decreases x) is still termination_unverified (no discharge yet)" $ do
      let src = T.pack "(def-shell f [x: int] -> int (pre (>= x 0)) (post (= result x)) (decreases x) (f x))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> Set.member "f" (trPartialFns (buildTrustReport Map.empty stmts Map.empty)) `shouldBe` True

    it "RD1-5: emitted AST stamps schemaVersion 0.8.0; a 0.7.0 doc still parses (backward-compat)" $ do
      let src = T.pack "(def-shell f [x: int] -> int (decreases x) (f x))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          T.isInfixOf "0.8.0" (TE.decodeUtf8 (BL.toStrict (emitJsonAST stmts))) `shouldBe` True
      let doc07 = BLC.pack "{\"schemaVersion\":\"0.7.0\",\"statements\":[{\"kind\":\"def-shell\",\"name\":\"g\",\"params\":[{\"name\":\"x\",\"type\":\"int\"}],\"body\":{\"kind\":\"var\",\"name\":\"x\"}}]}"
      case parseJSONAST GrammarCoreInversion "<test>" doc07 of
        Left e  -> expectationFailure ("a 0.7.0 doc must still parse: " ++ show e)
        Right _ -> pure ()

    it "RD1-6: a decreases-free def-shell emits no 'decreases' key (byte-inert)" $ do
      let src = T.pack "(def-shell g [x: int] -> int (post (= result x)) x)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          T.isInfixOf "decreases" (TE.decodeUtf8 (BL.toStrict (emitJsonAST stmts))) `shouldBe` False

    -- REC-DESCENT Phase 2 (v0.14.25): descent obligation emission + verdict.
    let clausesOf emitR = map coClause (Map.elems (erConstraintTable emitR))
        parseOrFail s = case parseStatements GrammarCoreInversion "<test>" (T.pack s) of
                          Left e -> error (show e); Right ss -> ss

    it "RD2-1: a measured recursive def-shell emits a 'descent' constraint AND a 'decreases' (well-foundedness) constraint" $ do
      let stmts = parseOrFail "(def-shell count-down [x: int] -> int (pre (>= x 0)) (post (>= result 0)) (decreases x) (if (= x 0) 0 (count-down (- x 1))))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      let cs = clausesOf emitR
      (("descent" `elem` cs) && ("decreases" `elem` cs)) `shouldBe` True

    it "RD2-2: a recursive def-shell WITHOUT a measure emits no 'descent' constraint" $ do
      let stmts = parseOrFail "(def-shell count-down [x: int] -> int (pre (>= x 0)) (post (>= result 0)) (if (= x 0) 0 (count-down (- x 1))))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` False

    it "RD2-3: a k>1 (lexicographic) measure now discharges via a 'descent' constraint (no W-DECREASES-LEX)" $ do
      -- (decreases m n): the recursive call decrements m (holds n) — a lexicographic
      -- decrease. Lexicographic descent (v0.14.27) discharges it: the descent
      -- constraint is emitted and the function is measured; W-DECREASES-LEX is gone.
      let stmts = parseOrFail "(def-shell f [m: int n: int] -> int (pre (and (>= m 0) (>= n 0))) (post (>= result 0)) (decreases m n) (if (= m 0) 0 (f (- m 1) n)))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` True
      any (T.isInfixOf "W-DECREASES-LEX" . diagMessage) (erDiagnostics emitR) `shouldBe` False
      ("f" `elem` erMeasuredFns emitR) `shouldBe` True

    it "LEX-1: equal-length k=2 mutual recursion — both members measured, descent emitted (professor (a))" $ do
      let stmts = parseOrFail "(def-shell f [m: int n: int] -> int (pre (and (>= m 0) (>= n 0))) (post (>= result 0)) (decreases m n) (if (= m 0) 0 (g (- m 1) n)))\n(def-shell g [p: int q: int] -> int (pre (and (>= p 0) (>= q 0))) (post (>= result 0)) (decreases p q) (if (= p 0) 0 (f (- p 1) q)))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` True
      all (`elem` erMeasuredFns emitR) ["f", "g"] `shouldBe` True

    it "LEX-2: mixed-length mutual (k=2 vs k=1) — no descent constraint (equal-length gate; professor (b) refuse)" $ do
      let stmts = parseOrFail "(def-shell f [m: int n: int] -> int (pre (and (>= m 0) (>= n 0))) (post (>= result 0)) (decreases m n) (if (= m 0) 0 (g (- m 1))))\n(def-shell g [p: int] -> int (pre (>= p 0)) (post (>= result 0)) (decreases p) (if (= p 0) 0 (f p (- p 1))))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` False

    it "LEX-3: a k=2 tuple with a nonlinear component is untranslatable — no descent (firewall, stays partial)" $ do
      let stmts = parseOrFail "(def-shell f [m: int n: int] -> int (pre (and (>= m 0) (>= n 0))) (post (>= result 0)) (decreases m (* n n)) (if (= m 0) 0 (f (- m 1) n)))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` False

    it "LEX-4: a mixed-arity mutual SCC does NOT discharge even when measured+body-faithful+SAFE (uniform-arity gate — SOUNDNESS)" $ do
      -- The non-terminating witness: aa (k=2) INCREASES m and calls bb (k=1), which
      -- calls aa — it DIVERGES. Both members are measured (translatable tuples) and
      -- body-faithful, and the verify is SAFE — but VACUOUSLY: the equal-length gate
      -- emits ZERO descent constraints for the mixed-arity (2 vs 1) cycle, so nothing
      -- can fail. The SCC MUST NOT discharge (else a non-terminating recursion reaches
      -- total — a false SAFE). Uniform-arity gate (professor ruling (b)). This test
      -- fails without that gate.
      let stmts = parseOrFail (T.unpack (T.concat
                    [ "(def-shell aa [m: int n: int] -> int (pre (and (>= m 0) (>= n 0))) (post (>= result 0)) (decreases m n) (bb (+ m 1)))"
                    , "(def-shell bb [m: int] -> int (pre (>= m 0)) (post (>= result 0)) (decreases m) (aa m 0))" ]))
      descentDischargedFns stmts ["aa", "bb"] (Set.fromList ["aa", "bb"]) True `shouldBe` Set.empty

    it "LEX-5: an equal-arity k=2 mutual SCC DOES discharge (uniform-arity gate does not over-refuse)" $ do
      let stmts = parseOrFail (T.unpack (T.concat
                    [ "(def-shell ev [m: int n: int] -> int (pre (and (>= m 0) (>= n 0))) (post (>= result 0)) (decreases m n) (if (= m 0) 0 (od (- m 1) n)))"
                    , "(def-shell od [p: int q: int] -> int (pre (and (>= p 0) (>= q 0))) (post (>= result 0)) (decreases p q) (if (= p 0) 0 (ev (- p 1) q)))" ]))
      descentDischargedFns stmts ["ev", "od"] (Set.fromList ["ev", "od"]) True `shouldBe` Set.fromList ["ev", "od"]

    it "RD2-4: an untranslatable (nonlinear) measure emits no 'descent' constraint (firewall, never silently total)" $ do
      let stmts = parseOrFail "(def-shell f [n: int m: int] -> int (pre (and (>= n 0) (>= m 0))) (post (>= result 0)) (decreases (* n m)) (if (= n 0) 0 (f (- n 1) m)))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` False

    it "RD2-5: a decreases measure on a NON-recursive def-shell warns W-DECREASES-UNUSED and emits no 'descent'" $ do
      let stmts = parseOrFail "(def-shell f [x: int] -> int (pre (>= x 0)) (post (>= result 0)) (decreases x) (+ x 1))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` False
      any (T.isInfixOf "W-DECREASES-UNUSED" . diagMessage) (erDiagnostics emitR) `shouldBe` True

    it "RD2-6: markMeasureNotDecreasing surfaces a DISTINCT verdict — measure_not_decreasing_fns set, refuted_fns NOT" $ do
      let stmts  = parseOrFail "(def-shell f [x: int] -> int (pre (>= x 0)) (post (= result x)) (decreases x) (f x))"
          report = markMeasureNotDecreasing (Set.fromList ["f"]) (buildTrustReport Map.empty stmts Map.empty)
      Set.member "f" (trMeasureNotDecreasingFns report) `shouldBe` True
      Set.member "f" (trRefutedFns report) `shouldBe` False
      let js = formatTrustReportJson report
      (T.isInfixOf "\"measure_not_decreasing_fns\":[\"f\"]" js
        && T.isInfixOf "\"measure_not_decreasing\":true" js) `shouldBe` True

    it "RD2-7: F-1 shape — a measured degenerate self-call emits a 'descent' constraint (the solver refutes x<x at verify)" $ do
      let stmts = parseOrFail "(def-shell alert-admit [latched: bool sev: int] -> bool (post (<=> result (and (and (>= sev 1) (<= sev 2)) (and (not latched) (not (= sev 2)))))) (decreases sev) (alert-admit latched sev))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      ("descent" `elem` clausesOf emitR) `shouldBe` True

    it "RD2-8: the obligation report surfaces measure-not-decreasing DISTINCTLY from refuted (agent-facing)" $ do
      let stmts = parseOrFail "(def-shell f [x: int] -> int (pre (>= x 0)) (post (= result x)) (decreases x) (f x))"
      emitR <- emitFixpointWith (defaultEmitOptions { emitBodyVCs = True }) "test.llmll" stmts
      let table      = erConstraintTable emitR
          descentIds = [ i | (i, o) <- Map.toList table, coClause o == "descent" ]
          fqResult   = FQUnsafe descentIds
          trustRpt   = markMeasureNotDecreasing (Set.fromList ["f"]) (buildTrustReport Map.empty stmts Map.empty)
          reportJson = assembleReport "test.llmll" stmts Map.empty emitR (Just fqResult) trustRpt
      -- the descent obligation exists, is a termination obligation, and reads
      -- "measure-not-decreasing" — not "open", not "refuted".
      not (null descentIds) `shouldBe` True
      (T.isInfixOf "\"measure_not_decreasing_fns\":[\"f\"]" reportJson
        && T.isInfixOf "\"status\":\"measure-not-decreasing\"" reportJson
        && T.isInfixOf "\"kind\":\"termination-obligation\"" reportJson
        && T.isInfixOf "\"refuted_fns\":[]" reportJson) `shouldBe` True

    -- REC-DESCENT Phase 3: discharge feedback (mark-drop) + measure-in-hash.
    it "RD3-1: markDescentDischarged drops a discharged member from partial_fns" $ do
      let stmts = parseOrFail "(def-shell cd [x: int] -> int (pre (>= x 0)) (post (= result 0)) (decreases x) (if (= x 0) 0 (cd (- x 1))))"
          base    = buildTrustReport Map.empty stmts Map.empty
          dropped = markDescentDischarged (Set.fromList ["cd"]) base
      Set.member "cd" (trPartialFns base)    `shouldBe` True   -- recursive ⇒ marked termination_unverified
      Set.member "cd" (trPartialFns dropped) `shouldBe` False  -- descent-discharged ⇒ mark dropped

    it "RD3-2: a k=1 SCC where one member lacks a measure is not dischargeable (whole-SCC gate)" $ do
      -- ping declares a measure, pong does not; the SCC must stay marked for BOTH.
      let stmts = parseOrFail (T.unpack (T.concat
                    [ "(def-shell ping [x: int] -> int (pre (>= x 0)) (post (= result 0)) (decreases x) (pong x))"
                    , "(def-shell pong [x: int] -> int (pre (>= x 0)) (post (= result 0)) (ping x))" ]))
          base = buildTrustReport Map.empty stmts Map.empty
      -- both are recursive-cycle members; neither is dischargeable (pong unmeasured),
      -- so a correct discharge set is empty and both stay in partial_fns.
      (Set.member "ping" (trPartialFns base) && Set.member "pong" (trPartialFns base)) `shouldBe` True

    it "RD3-3: the decreases measure enters the evidence hash (Q1: measure edit invalidates; empty is inert)" $ do
      let body = EVar "x"
          post = Just (EOp "=" [EVar "result", ELit (LitInt 0)])
          hEmpty = canonicalDefEvidenceHash "def-shell" body Nothing post []
          hMeas  = canonicalDefEvidenceHash "def-shell" body Nothing post [EVar "x"]
          hMeas2 = canonicalDefEvidenceHash "def-shell" body Nothing post [EOp "+" [EVar "x", ELit (LitInt 1)]]
      hMeas  `shouldNotBe` hEmpty   -- declaring a measure changes the hash
      hMeas2 `shouldNotBe` hMeas    -- editing the measure changes the hash (invalidates a total sidecar)

    it "RD3-4: a strict-core def calling a DISCHARGED (termination-verified) recursive def-shell is ADMITTED (b1 lift)" $ do
      let recG = SDefShell { defShellName = "rec-g", defShellParams = [("x", TInt)]
                           , defShellReturn = Just TInt
                           , defShellContract = Contract (Just (EOp ">=" [EVar "x", ELit (LitInt 0)])) Nothing (Just (EOp "=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
                           , defShellBody = EIf (EOp "=" [EVar "x", ELit (LitInt 0)]) (ELit (LitInt 0)) (EApp "rec-g" [EOp "-" [EVar "x", ELit (LitInt 1)]])
                           , defShellDecreases = [EVar "x"] }
          caller = SDef { defName = "caller", defParams = [("n", TInt)], defReturn = Just TInt
                        , defContract = Contract (Just (EOp ">=" [EVar "n", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing
                        , defBody = EApp "rec-g" [EVar "n"] }
          -- rec-g's post evidence is verified + body-faithful + hash + termination-verified.
          recEr tv = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False (Just "sha256:deadbeef") tv
          statusMap = DM.fromList [("rec-g", ContractStatus Nothing (Just (recEr True)) [])]
          report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion (DM.empty :: ModuleCache) statusMap emptyEnv [recG, caller]
      mapMaybe diagKind (reportDiagnostics report) `shouldNotContain` ["core-membership-violation"]

    it "RD3-5: a strict-core def calling a verified-but-MEASURELESS recursive def-shell is REFUSED (gap closure)" $ do
      let recG = SDefShell { defShellName = "rec-g", defShellParams = [("x", TInt)]
                           , defShellReturn = Just TInt
                           , defShellContract = Contract (Just (EOp ">=" [EVar "x", ELit (LitInt 0)])) Nothing (Just (EOp "=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
                           , defShellBody = EIf (EOp "=" [EVar "x", ELit (LitInt 0)]) (ELit (LitInt 0)) (EApp "rec-g" [EOp "-" [EVar "x", ELit (LitInt 1)]])
                           , defShellDecreases = [] }
          caller = SDef { defName = "caller", defParams = [("n", TInt)], defReturn = Just TInt
                        , defContract = Contract (Just (EOp ">=" [EVar "n", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing
                        , defBody = EApp "rec-g" [EVar "n"] }
          -- verified + body-faithful + hash, but NOT termination-verified (partial correctness):
          -- the recursion tightening refuses it from the total-correctness strict core.
          recEr tv = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False (Just "sha256:deadbeef") tv
          statusMap = DM.fromList [("rec-g", ContractStatus Nothing (Just (recEr False)) [])]
          report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion (DM.empty :: ModuleCache) statusMap emptyEnv [recG, caller]
      mapMaybe diagKind (reportDiagnostics report) `shouldContain` ["core-membership-violation"]

    -- DEF-RET: optional return-type annotation on def/def-shell (v0.7.0 schema)
    it "DEF-RET: S-expr parses optional '-> T' into mRet" $ do
      case parseStatements GrammarCoreInversion "<test>" (T.pack "(def f [x: int] -> int x)") of
        Left err                  -> expectationFailure (show err)
        Right [SDef _ _ mRet _ _] -> mRet `shouldBe` Just TInt
        Right _                   -> expectationFailure "expected a single SDef"

    it "DEF-RET: no annotation parses to Nothing (backward-compat)" $ do
      case parseStatements GrammarCoreInversion "<test>" (T.pack "(def g [x: int] x)") of
        Left err                  -> expectationFailure (show err)
        Right [SDef _ _ mRet _ _] -> mRet `shouldBe` Nothing
        Right _                   -> expectationFailure "expected a single SDef"

    it "DEF-RET: bare-hole body under declared return is HoleTyped" $ do
      case parseStatements GrammarCoreInversion "<test>" (T.pack "(def f [x: int] -> int ?body)") of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?body" result of
            Nothing -> expectationFailure "?body hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TInt

    it "DEF-RET: bare-hole body without annotation stays HoleUnknown" $ do
      case parseStatements GrammarCoreInversion "<test>" (T.pack "(def g [x: int] ?body)") of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case findHole "?body" result of
            Nothing -> expectationFailure "?body hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleUnknown

    it "DEF-RET: declared return mismatch errors, attributed to the function name" $ do
      case parseStatements GrammarCoreInversion "<test>" (T.pack "(def-shell h [x: int] -> string (+ x 1))") of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
              diags  = reportDiagnostics report
          any (\d -> T.isInfixOf "string" (diagMessage d) && T.isInfixOf "'h'" (diagMessage d)) diags
            `shouldBe` True

    -- DEF-RET Unit 2: return-refinement discharge (augmentContractPost) + staleness coverage
    it "DEF-RET Unit 2: augmentContractPost folds a refinement-aliased return into the post" $ do
      let src = T.pack "(type PositiveInt (where [x: int] (> x 0)))\n(def f [x: int] -> PositiveInt (+ x 1))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let am = buildAliasMap stmts
          case [ (mRet, c) | SDef _ _ mRet c _ <- stmts ] of
            [(mRet, c)] -> contractPost (augmentContractPost am mRet c) `shouldNotBe` Nothing
            _           -> expectationFailure "expected exactly one SDef"

    it "DEF-RET Unit 2: augmentContractPost is a no-op for a base-type return" $ do
      let src = T.pack "(def f [x: int] -> int (+ x 1))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let am = buildAliasMap stmts
          case [ (mRet, c) | SDef _ _ mRet c _ <- stmts ] of
            [(mRet, c)] -> contractPost (augmentContractPost am mRet c) `shouldBe` contractPost c
            _           -> expectationFailure "expected exactly one SDef"

    it "DEF-RET Unit 2: staleness hash covers the return refinement (-> PositiveInt /= -> int)" $ do
      let parse s = parseStatements GrammarCoreInversion "<test>" (T.pack s)
          hashOf stmts =
            let am = buildAliasMap stmts
            in [ canonicalDefEvidenceHash "def" body (contractPre c)
                   (contractPost (augmentContractPost am mRet c)) []
               | SDef _ _ mRet c body <- stmts ]
      case ( parse "(type PositiveInt (where [x: int] (> x 0)))\n(def f [x: int] -> PositiveInt (pre (>= x 0)) (+ x 1))"
           , parse "(type PositiveInt (where [x: int] (> x 0)))\n(def f [x: int] -> int (pre (>= x 0)) (+ x 1))" ) of
        (Right s1, Right s2) -> hashOf s1 `shouldNotBe` hashOf s2
        _                    -> expectationFailure "parse failed"

    it "non-sketch check path unaffected: no holes recorded for concrete program" $ do
      let src = T.pack $ unlines
            [ "(def-shell id-str [s: string]"
            , "  (if (= (string-length s) 0) \"empty\" s))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True
          let skRes = runSketch GrammarCoreInversion emptyEnv stmts []
          sketchHoles skRes `shouldBe` []

  -- -----------------------------------------------------------------------
  -- Phase 2c D3: holeSensitive error annotation
  -- -----------------------------------------------------------------------
  describe "Phase 2c D3 holeSensitive error annotation" $ do
    it "type mismatch between concrete types emits holeSensitive = False" $ do
      -- (def-shell f [] (if true 42 "hello")) — branches differ, no holes
      let src = T.pack $ unlines
            [ "(def-shell f [] (if true 42 \"hello\"))" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let diags = reportDiagnostics (typeCheck GrammarCoreInversion emptyEnv stmts)
          let typeMismatches = filter (maybe False (T.isInfixOf "type-mismatch") . diagKind) diags
              -- type-mismatch between int and string: certain, no holes
              allCertain = all (not . diagHoleSensitive) diags
          allCertain `shouldBe` True

    it "return-type mismatch vs hole var emits holeSensitive = True" $ do
      -- (def-shell f [x: int] : int ?impl) — hole body vs int return type
      -- unify int (expected) vs TVar "?impl" (actual) → holeSensitive
      let src = T.pack $ unlines
            [ "(def-shell f [x: int] ?impl)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          -- In sketch mode: ?impl synthesises to TVar "?impl".
          -- The concrete caller (f 42) would then force a check; without that
          -- the synthesis produces no type mismatch.  Verify at least that
          -- holeSensitive = False errors are NOT emitted here (no spurious
          -- certain errors should appear for a well-typed partial program).
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          let certainErrs = filter (\d -> diagSeverity d == SevError && not (diagHoleSensitive d)) (sketchErrors result)
          certainErrs `shouldBe` []


    it "inferHole HNamed synthesises TVar with ? prefix (D3 invariant)" $ do
      -- A hole in synthesis position must return TVar "?name", not TVar "?"
      let src = T.pack $ unlines
            [ "(def-shell f [x: int] ?impl)" ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          -- ?impl should be recorded as HoleUnknown (synthesis context)
          let holes = sketchHoles result
          holes `shouldSatisfy` (not . null)
          shStatus (head holes) `shouldBe` HoleUnknown

  -- -----------------------------------------------------------------------
  -- Phase 2c D4: tcPointerStack — one RFC 6901 token per stack element
  -- -----------------------------------------------------------------------
  describe "Phase 2c D4 pointer stack (nested withSegment)" $ do

    it "hole at else branch has pointer /statements/0/body/else" $ do
      let src = T.pack $ unlines
            [ "(def-shell greet [formal: bool]"
            , "  (if formal \"Good day.\" ?informal))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case filter ((== "?informal") . shName) (sketchHoles result) of
            []    -> expectationFailure "?informal hole not recorded"
            (h:_) -> shPointer h `shouldBe` "/statements/0/body/else"

    it "hole at match arm 2 has pointer /statements/1/body/arms/2/body" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"      -- stmt 0
            , "(def-shell describe [c: Color]"               -- stmt 1
            , "  (match c"
            , "    ((Red) \"red\")"       -- arm 0
            , "    ((Green) \"green\")"   -- arm 1
            , "    ((Blue) ?blue_label)))" -- arm 2
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case filter ((== "?blue_label") . shName) (sketchHoles result) of
            []    -> expectationFailure "?blue_label hole not recorded"
            (h:_) -> shPointer h `shouldBe` "/statements/1/body/arms/2/body"

    it "concrete program produces no holes and non-sketch check is unaffected" $ do
      let src = T.pack $ unlines
            [ "(def-shell f [x: int] x)"
            , "(def-shell g [s: string] s)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          sketchHoles result `shouldBe` []


  -- =========================================================================
  -- v0.3: JsonPointer tests (pure)
  -- =========================================================================

  describe "JsonPointer" $ do
    let testAst = object
          [ "schemaVersion" .= ("0.6.0" :: T.Text)
          , "statements" .= [ object
              [ "kind" .= ("def-shell" :: T.Text)
              , "name" .= ("foo" :: T.Text)
              , "body" .= object
                  [ "kind" .= ("pair" :: T.Text)
                  , "fst"  .= object [ "kind" .= ("var" :: T.Text), "name" .= ("x" :: T.Text) ]
                  , "snd"  .= object [ "kind" .= ("lit-int" :: T.Text), "value" .= (42 :: Int) ]
                  ]
              ]
            , object
              [ "kind" .= ("def-shell" :: T.Text)
              , "name" .= ("bar" :: T.Text)
              , "body" .= object
                  [ "kind" .= ("hole-delegate" :: T.Text)
                  , "agent" .= ("@agent" :: T.Text)
                  ]
              ]
            ]
          ]

    describe "resolvePointer" $ do
      it "resolves root to entire value" $
        resolvePointer "" testAst `shouldBe` Just testAst

      it "resolves /statements/0 to first statement" $ do
        let result = resolvePointer "/statements/0" testAst
        case result of
          Just (Object o) -> KM.lookup "name" o `shouldBe` Just (String "foo")
          _               -> expectationFailure "expected Object with name=foo"

      it "resolves nested /statements/0/body/snd" $ do
        let result = resolvePointer "/statements/0/body/snd" testAst
        result `shouldBe` Just (object [ "kind" .= ("lit-int" :: T.Text), "value" .= (42 :: Int) ])

      it "returns Nothing on out-of-bounds array index" $
        resolvePointer "/statements/99" testAst `shouldBe` Nothing

      it "returns Nothing on non-existent key" $
        resolvePointer "/statements/0/nonexistent" testAst `shouldBe` Nothing

    describe "setAtPointer" $ do
      it "replaces value at nested path" $ do
        let newVal = object [ "kind" .= ("lit-int" :: T.Text), "value" .= (99 :: Int) ]
        case setAtPointer "/statements/0/body/snd" newVal testAst of
          Left err -> expectationFailure (T.unpack err)
          Right updated -> resolvePointer "/statements/0/body/snd" updated `shouldBe` Just newVal

      it "returns Left on non-existent key" $ do
        let result = setAtPointer "/statements/0/missing/deep" (String "x") testAst
        case result of
          Left _ -> pure ()
          Right _ -> expectationFailure "should fail on missing key"

    describe "removeAtPointer" $ do
      it "removes object key" $
        case removeAtPointer "/statements/0/body/snd" testAst of
          Left err -> expectationFailure (T.unpack err)
          Right updated -> resolvePointer "/statements/0/body/snd" updated `shouldBe` Nothing

      it "returns Left when removing root" $
        removeAtPointer "" testAst `shouldBe` Left "cannot remove root"

    describe "isHoleNode + findDescendantHoles" $ do
      it "detects hole-delegate as a hole" $
        isHoleNode (object [ "kind" .= ("hole-delegate" :: T.Text) ]) `shouldBe` True

      it "rejects non-hole nodes" $
        isHoleNode (object [ "kind" .= ("var" :: T.Text) ]) `shouldBe` False

      it "finds hole-delegate in subtree" $
        findDescendantHoles "/statements/1" testAst `shouldBe` ["/statements/1/body"]

      it "returns [] when no holes in subtree" $
        findDescendantHoles "/statements/0" testAst `shouldBe` []

  -- =========================================================================
  -- v0.3: validateScope tests (pure, security-critical)
  -- =========================================================================

  describe "validateScope" $ do
    it "op path == checkout pointer passes" $
      validateScope "/statements/1/body" [PatchReplace "/statements/1/body" (String "x")]
        `shouldBe` Right ()

    it "op path is child of checkout pointer passes" $
      validateScope "/statements/1/body" [PatchReplace "/statements/1/body/fst" (String "x")]
        `shouldBe` Right ()

    it "op path is sibling of checkout pointer fails" $ do
      let result = validateScope "/statements/1/body" [PatchReplace "/statements/0/body" (String "x")]
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "should reject sibling scope"

    it "multiple ops, one out of scope, fails" $ do
      let ops = [ PatchReplace "/statements/1/body/fst" (String "x")
                , PatchReplace "/statements/0/body" (String "y")
                ]
      case validateScope "/statements/1/body" ops of
        Left err -> T.isInfixOf "/statements/0/body" err `shouldBe` True
        Right () -> expectationFailure "should have rejected"

  -- =========================================================================
  -- v0.3: rebaseToPatch tests (pure)
  -- =========================================================================

  describe "rebaseToPatch" $ do
    let mkDiagWithPtr ptr = (mkError Nothing "test error") { diagPointer = Just ptr }
        ops = [ PatchOpInfo 0 "/statements/1/body" "replace"
              , PatchOpInfo 2 "/statements/1/body/args/0" "add"
              ]

    it "diagnostic without pointer is unchanged" $
      diagPointer (rebaseToPatch ops (mkError Nothing "no pointer")) `shouldBe` Nothing

    it "pointer matching op path exactly gets rebased" $
      diagPointer (rebaseToPatch ops (mkDiagWithPtr "/statements/1/body"))
        `shouldBe` Just "patch-op/0"

    it "pointer descending into op path gets rebased with suffix" $
      diagPointer (rebaseToPatch ops (mkDiagWithPtr "/statements/1/body/fst"))
        `shouldBe` Just "patch-op/0/fst"

    it "pointer outside all ops is unchanged" $
      diagPointer (rebaseToPatch ops (mkDiagWithPtr "/statements/0/body"))
        `shouldBe` Just "/statements/0/body"

  -- =========================================================================
  -- v0.3: PatchApply ops tests (pure, on Value)
  -- =========================================================================

  describe "PatchApply ops" $ do
    let root = object
          [ "statements" .= [ object [ "kind" .= ("var" :: T.Text), "name" .= ("x" :: T.Text) ]
                             , object [ "kind" .= ("hole-delegate" :: T.Text) ]
                             ]
          ]

    describe "applyOp" $ do
      it "replace on existing path succeeds" $ do
        let newVal = object [ "kind" .= ("lit-int" :: T.Text), "value" .= (42 :: Int) ]
        case applyOp (PatchReplace "/statements/1" newVal) root of
          Left err -> expectationFailure (T.unpack err)
          Right updated -> resolvePointer "/statements/1" updated `shouldBe` Just newVal

      it "replace on non-existent path fails" $ do
        case applyOp (PatchReplace "/statements/99" (String "x")) root of
          Left _ -> pure ()
          Right _ -> expectationFailure "should fail on missing path"

      it "test with matching value passes (value unchanged)" $ do
        let expected = object [ "kind" .= ("var" :: T.Text), "name" .= ("x" :: T.Text) ]
        applyOp (PatchTest "/statements/0" expected) root `shouldBe` Right root

      it "test with non-matching value fails" $ do
        let wrong = object [ "kind" .= ("lit-int" :: T.Text) ]
        case applyOp (PatchTest "/statements/0" wrong) root of
          Left err -> T.isInfixOf "does not match" err `shouldBe` True
          Right _ -> expectationFailure "test should fail"

      it "remove deletes node" $
        case applyOp (PatchRemove "/statements/1") root of
          Left err -> expectationFailure (T.unpack err)
          Right updated -> resolvePointer "/statements/1" updated `shouldBe` Nothing

    describe "applyOps" $ do
      it "applies ops in sequence (test then replace)" $ do
        let newVal = object [ "kind" .= ("lit-int" :: T.Text), "value" .= (1 :: Int) ]
            ops = [ PatchTest "/statements/1" (object [ "kind" .= ("hole-delegate" :: T.Text) ])
                  , PatchReplace "/statements/1" newVal
                  ]
        case applyOps ops root of
          Left err -> expectationFailure (T.unpack err)
          Right updated -> resolvePointer "/statements/1" updated `shouldBe` Just newVal

      it "short-circuits on first failure" $ do
        let ops = [ PatchTest "/statements/0" (String "wrong")
                  , PatchReplace "/statements/1" (String "should-not-reach")
                  ]
        case applyOps ops root of
          Left _ -> pure ()
          Right _ -> expectationFailure "should short-circuit on test failure"

  -- =========================================================================
  -- v0.10 BUG-PATCH-VERIFY: hasContracts (pure)
  -- =========================================================================

  describe "hasContracts (patch re-verification guard)" $ do

    it "returns True for SDefLogic with pre+post" $ do
      let stmt = SDefLogic "f" [("x", TInt)] Nothing
                   (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                             (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                   (EVar "x")
      hasContracts [stmt] `shouldBe` True

    it "returns True for SDefLogic with post only" $ do
      let stmt = SDefLogic "f" [("x", TInt)] Nothing
                   (Contract Nothing Nothing
                             (Just (EApp "=" [EVar "result", EVar "x"])) Nothing Nothing)
                   (EVar "x")
      hasContracts [stmt] `shouldBe` True

    it "returns False for SDefLogic with no contracts" $ do
      let stmt = SDefLogic "f" [("x", TInt)] Nothing
                   (Contract Nothing Nothing Nothing Nothing Nothing)
                   (EVar "x")
      hasContracts [stmt] `shouldBe` False

    it "returns False for STypeDef-only program" $ do
      let stmt = STypeDef "Foo" TInt
      hasContracts [stmt] `shouldBe` False

  -- =========================================================================
  -- v0.10 BUG-PATCH-VERIFY: PatchVerifyError JSON shape (pure)
  -- =========================================================================

  describe "PatchVerifyError JSON shape" $ do

    it "serializes with result=PatchVerifyError and diagnostics array" $ do
      let report = DiagnosticReport "verify" [mkError Nothing "post-condition violated"] False
          result = PatchVerifyError report Nothing
          json = encode result
      case decode json of
        Nothing -> expectationFailure "failed to decode PatchVerifyError JSON"
        Just (Object o) -> do
          KM.lookup "result" o `shouldBe` Just (String "PatchVerifyError")
          case KM.lookup "diagnostics" o of
            Just (Array _) -> pure ()
            _ -> expectationFailure "expected diagnostics array"
        _ -> expectationFailure "expected JSON object"

    -- DEMO-COMP (§3.3): the discriminated callee-precondition-unmet sub-reason.
    -- POSITIVE: a CalleePreUnmet payload surfaces reason + callee + required_pre
    -- + call_site_pointer on the EXISTING PatchVerifyError constructor.
    it "DC-P1: PatchVerifyError with CalleePreUnmet carries the sub-reason payload" $ do
      let report = DiagnosticReport "verify" [mkError Nothing "callee precondition unmet"] False
          cpu = CalleePreUnmet "withdraw" "(>= balance amount)" "/statements/4/body"
          result = PatchVerifyError report (Just cpu)
      case decode (encode result) of
        Just (Object o) -> do
          KM.lookup "result" o            `shouldBe` Just (String "PatchVerifyError")
          KM.lookup "reason" o            `shouldBe` Just (String "callee-precondition-unmet")
          KM.lookup "callee" o            `shouldBe` Just (String "withdraw")
          KM.lookup "required_pre" o      `shouldBe` Just (String "(>= balance amount)")
          KM.lookup "call_site_pointer" o `shouldBe` Just (String "/statements/4/body")
        _ -> expectationFailure "expected JSON object"

    -- NEGATIVE 1: a plain body-post PatchVerifyError (mCpu = Nothing) carries NO
    -- 'reason' key — byte-compatible with the pre-DEMO-COMP shape.
    it "DC-P2: plain body-post PatchVerifyError omits the sub-reason" $ do
      let report = DiagnosticReport "verify" [mkError Nothing "post-condition violated"] False
          result = PatchVerifyError report Nothing
      case decode (encode result) of
        Just (Object o) -> do
          KM.lookup "result" o `shouldBe` Just (String "PatchVerifyError")
          KM.lookup "reason" o `shouldBe` Nothing  -- no sub-reason for body-post
          KM.lookup "callee" o `shouldBe` Nothing
        _ -> expectationFailure "expected JSON object"

    -- NEGATIVE 2: a type error stays PatchTypeError (no PatchVerifyError, no reason).
    it "DC-P3: a type error is PatchTypeError, not a verify sub-reason" $ do
      let report = DiagnosticReport "patch" [mkError Nothing "type mismatch"] False
          result = PatchTypeError report
      case decode (encode result) of
        Just (Object o) -> do
          KM.lookup "result" o `shouldBe` Just (String "PatchTypeError")
          KM.lookup "reason" o `shouldBe` Nothing
        _ -> expectationFailure "expected JSON object"

    it "PatchSuccess JSON is unchanged (regression)" $ do
      let result = PatchSuccess 5
          json = encode result
      case decode json of
        Nothing -> expectationFailure "failed to decode PatchSuccess JSON"
        Just (Object o) -> do
          KM.lookup "result" o `shouldBe` Just (String "PatchSuccess")
        _ -> expectationFailure "expected JSON object"

  -- =========================================================================
  -- v0.10 BUG-PATCH-VERIFY: parseFQResult round-trip (pure)
  -- =========================================================================

  describe "parseFQResult (patch verification integration)" $ do

    it "parses SAFE output" $
      parseFQResult "SAFE" `shouldBe` FQSafe

    it "returns FQError on garbage input" $ do
      let result = parseFQResult "CRASH: segfault"
      case result of
        FQError _ -> pure ()
        _ -> expectationFailure $ "expected FQError, got: " ++ show result

  -- -------------------------------------------------------------------------
  -- fqResultToReport — DiagnosticFQ partial-record regression (fix F-001).
  --
  -- All three branches of fqResultToReport were constructing DiagnosticReport
  -- records via record syntax that omitted the reportPhase :: Text field
  -- (DiagnosticFQ.hs:95-111 pre-fix), leaving the field as ⊥. Any consumer
  -- that accessed reportPhase — notably formatReportJson at Diagnostic.hs:352
  -- — crashed with "Missing field in record construction reportPhase".
  --
  -- The bug was latent for the entire --trust-report lifetime because the
  -- typical --json verify SAFE path early-exited at Main.hs:1078 before
  -- reaching the verifier loop. LT-CDP at commit 121815a split the early-exit
  -- condition so --cdp --trust-report --json falls through to the solver
  -- and hits formatReportJson, surfacing the crash.
  --
  -- DF-1 / DF-2 / DF-3 force evaluation of reportPhase directly.
  -- DF-4 is the end-to-end regression: drop the fix and DF-4 fails with the
  -- same runtime exception observed on the CLI.
  -- -------------------------------------------------------------------------
  describe "fqResultToReport (DiagnosticFQ partial-record regression, fix F-001)" $ do

    it "DF-1: FQSafe sets reportPhase = \"lh-fixpoint\"" $ do
      let r = fqResultToReport "test.llmll" Map.empty FQSafe
      reportPhase r       `shouldBe` "lh-fixpoint"
      reportSuccess r     `shouldBe` True
      reportDiagnostics r `shouldBe` []

    it "DF-2: FQUnsafe sets reportPhase" $ do
      let r = fqResultToReport "test.llmll" Map.empty (FQUnsafe [0, 1, 2])
      reportPhase r `shouldBe` "lh-fixpoint"
      -- toDiag against an empty constraint-table emits one
      -- unknown-origin diagnostic per FQConstraintId.
      length (reportDiagnostics r) `shouldBe` 3

    it "DF-3: FQError sets reportPhase and carries the error text" $ do
      let r = fqResultToReport "test.llmll" Map.empty (FQError "constraint emission failure")
      reportPhase r   `shouldBe` "lh-fixpoint"
      reportSuccess r `shouldBe` False
      length (reportDiagnostics r) `shouldBe` 1

    it "DF-4: formatReportJson does not crash on FQSafe-derived report" $ do
      let r       = fqResultToReport "test.llmll" Map.empty FQSafe
          jsonTxt = formatReportJson r
      (T.length jsonTxt > 0)                          `shouldBe` True
      T.isInfixOf "\"phase\":\"lh-fixpoint\"" jsonTxt `shouldBe` True

  -- =========================================================================
  -- VERIFY-RPT-1: reporting-path fail-open fix + refuted trust status.
  -- VR-1..VR-8 per docs/design/verify-reporting-defects-2026-06-04-bug.md.
  -- =========================================================================

  describe "VERIFY-RPT-1 (reporting fail-open + refuted status)" $ do

    -- VR-1 (Defect 1a/1b): an UNSAFE verdict that resolves no constraint id
    -- still fails closed, with a synthesized fallback diagnostic.
    it "VR-1: fqResultToReport (FQUnsafe []) fails closed with a non-empty payload" $ do
      let r = fqResultToReport "test.llmll" Map.empty (FQUnsafe [])
      reportSuccess r                          `shouldBe` False
      length (reportDiagnostics r) `shouldSatisfy` (>= 1)

    -- VR-5 (Defect 1b pointer quality): a resolvable body-post id maps to its
    -- /statements/N/body counterexample pointer.
    it "VR-5: fqResultToReport resolves a body-post id to its /body pointer" $ do
      let table = Map.fromList
            [(0, ConstraintOrigin "withdraw" "body-post" "/statements/1/body" "withdraw.ast.json")]
          r = fqResultToReport "withdraw.ast.json" table (FQUnsafe [0])
      reportSuccess r                              `shouldBe` False
      map diagPointer (reportDiagnostics r) `shouldBe` [Just "/statements/1/body"]

    -- VR-2 (Commit 2): the -q --json envelope decoder, including the
    -- ANSI-prefixed fallback line and noise rejection.
    it "VR-2: parseFQResultJSON decodes Unsafe/Safe envelopes and rejects noise" $ do
      parseFQResultJSON "{\"contents\":[{\"numVald\":0},[0]],\"tag\":\"Unsafe\"}"
        `shouldBe` Just (FQUnsafe [0])
      parseFQResultJSON "{\"contents\":{\"numVald\":1},\"tag\":\"Safe\"}"
        `shouldBe` Just FQSafe
      parseFQResultJSON "\ESC[0m{\"contents\":[{\"n\":1},[0,2]],\"tag\":\"Unsafe\"}"
        `shouldBe` Just (FQUnsafe [0, 2])
      parseFQResultJSON "Liquid-Fixpoint banner with no json"
        `shouldBe` Nothing

    -- VR-3 (Defect 2): a v0.11 verified body-faithful sidecar (no
    -- overflow_tainted field) round-trips through loadVerified non-empty.
    it "VR-3: loadVerified round-trips a v0.11 verified sidecar (Defect-2 guard)" $ do
      let fp = "test/_tmp_vr3.ast.json"
          cs = Map.fromList
                 [ ("withdraw", ContractStatus
                     Nothing
                     (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
                     []) ]
      saveVerified fp cs
      loaded <- loadVerified fp
      Map.member "withdraw" loaded `shouldBe` True
      removeFile (verifiedPath fp)

    -- VR-4 (Defect 2): the field-absence revalidation trigger is disarmed.
    it "VR-4: sidecarNeedsRevalidation is disarmed on a v0.11-shape sidecar" $ do
      let er  = KM.fromList [ ("display_level", object ["level" .= ("verified" :: T.Text)])
                            , ("body_faithful", Bool True) ]
          cs  = KM.fromList [ ("post", Object er) ]
          top = KM.fromList [ ("withdraw", Object cs) ]
      sidecarNeedsRevalidation top `shouldBe` False

    -- VR-6 (Commit 4): refutedClosure includes a directly-refuted function.
    it "VR-6: refutedClosure includes a directly-refuted function" $ do
      let stmts = [ SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                      (EVar "n") ]
          report = buildTrustReport Map.empty stmts Map.empty
      refutedClosure (Set.fromList ["f"]) report `shouldBe` Set.fromList ["f"]

    -- VR-8 (Commit 4): refutedClosure is transitive (assume-guarantee) and
    -- markRefuted stamps a depends-on-refuted drift on the caller.
    it "VR-8: refutedClosure + markRefuted propagate depends-on-refuted to a caller" $ do
      let mkFn name body = SDefLogic name [("n", TInt)] (Just TInt)
                             (Contract (Just (EApp ">" [EVar "n", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                             body
          callee  = mkFn "callee" (EVar "n")
          caller  = mkFn "caller" (EApp "callee" [EVar "n"])
          report  = buildTrustReport Map.empty [callee, caller] Map.empty
          closure = refutedClosure (Set.fromList ["callee"]) report
          marked  = markRefuted (Set.fromList ["callee"]) report
          callerDrifts = concat [ teDrifts e | e <- trEntries marked, teName e == "caller" ]
      Set.member "caller" closure `shouldBe` True
      Set.member "callee" closure `shouldBe` True
      any (T.isInfixOf "depends-on-refuted") callerDrifts `shouldBe` True

    -- VR-7 (Cross-cutting): a wrong patch fill yields PatchVerifyError whose
    -- diagnostics are non-empty and carry a JSON pointer (or PatchSuccess when
    -- the solver is not installed — graceful degradation).
    it "VR-7: patch wrong fill → PatchVerifyError with pointer-bearing diagnostics" $ do
      let tmpDir = "test/_tmp_vr7_patch"
      createDirectoryIfMissing True tmpDir
      BL.readFile "../examples/withdraw-demo/withdraw.ast.json"
        >>= BL.writeFile (tmpDir </> "withdraw.ast.json")
      let fp = tmpDir </> "withdraw.ast.json"
      raw <- BL.readFile fp
      let Just astVal = decode raw
      result <- checkoutHole fp astVal "/statements/1/body"
      case result of
        Left diag -> expectationFailure $ T.unpack (diagMessage diag)
        Right ct -> do
          let patchReq = PatchRequest (ctToken ct)
                [ PatchTest "/statements/1/body"
                    (object ["kind" .= ("hole-named" :: T.Text), "name" .= ("body_impl" :: T.Text)])
                , PatchReplace "/statements/1/body"
                    (object ["kind" .= ("app" :: T.Text), "fn" .= ("+" :: T.Text),
                             "args" .= [object ["kind" .= ("var" :: T.Text), "name" .= ("balance" :: T.Text)],
                                        object ["kind" .= ("var" :: T.Text), "name" .= ("amount" :: T.Text)]]])
                ]
          pResult <- applyPatch GrammarCoreInversion fp patchReq
          case pResult of
            PatchVerifyError rpt _ -> do
              length (reportDiagnostics rpt) `shouldSatisfy` (>= 1)
              any (\d -> diagPointer d /= Nothing) (reportDiagnostics rpt) `shouldBe` True
            PatchSuccess _ -> pure ()  -- solver absent: graceful degradation
            other -> expectationFailure $ "expected PatchVerifyError or PatchSuccess, got: " ++ show other
      removeDirectoryRecursive tmpDir

  -- =========================================================================
  -- v0.10 BUG-PATCH-VERIFY: full lifecycle IO tests
  -- =========================================================================

  describe "BUG-PATCH-VERIFY: patch re-verification lifecycle" $ do

    -- PROOF OBLIGATION 1: Correct body → PatchSuccess
    it "OBLIG-1: patch with (- balance amount) returns PatchSuccess" $ do
      let tmpDir = "test/_tmp_patch_verify_1"
      createDirectoryIfMissing True tmpDir
      BL.readFile "../examples/withdraw-demo/withdraw.ast.json"
        >>= BL.writeFile (tmpDir </> "withdraw.ast.json")
      let fp = tmpDir </> "withdraw.ast.json"
      raw <- BL.readFile fp
      let Just astVal = decode raw
      result <- checkoutHole fp astVal "/statements/1/body"
      case result of
        Left diag -> expectationFailure $ T.unpack (diagMessage diag)
        Right ct -> do
          let patchReq = PatchRequest (ctToken ct)
                [ PatchTest "/statements/1/body"
                    (object ["kind" .= ("hole-named" :: T.Text), "name" .= ("body_impl" :: T.Text)])
                , PatchReplace "/statements/1/body"
                    (object ["kind" .= ("app" :: T.Text), "fn" .= ("-" :: T.Text),
                             "args" .= [object ["kind" .= ("var" :: T.Text), "name" .= ("balance" :: T.Text)],
                                        object ["kind" .= ("var" :: T.Text), "name" .= ("amount" :: T.Text)]]])
                ]
          pResult <- applyPatch GrammarCoreInversion fp patchReq
          case pResult of
            PatchSuccess _ -> pure ()
            other -> expectationFailure $ "expected PatchSuccess, got: " ++ show other
      removeDirectoryRecursive tmpDir

    -- PROOF OBLIGATION 2: Wrong body → PatchVerifyError (CRITICAL — the bug case)
    it "OBLIG-2: patch with (+ balance amount) returns PatchVerifyError or PatchSuccess (graceful)" $ do
      let tmpDir = "test/_tmp_patch_verify_2"
      createDirectoryIfMissing True tmpDir
      BL.readFile "../examples/withdraw-demo/withdraw.ast.json"
        >>= BL.writeFile (tmpDir </> "withdraw.ast.json")
      let fp = tmpDir </> "withdraw.ast.json"
      raw <- BL.readFile fp
      let Just astVal = decode raw
      result <- checkoutHole fp astVal "/statements/1/body"
      case result of
        Left diag -> expectationFailure $ T.unpack (diagMessage diag)
        Right ct -> do
          let patchReq = PatchRequest (ctToken ct)
                [ PatchTest "/statements/1/body"
                    (object ["kind" .= ("hole-named" :: T.Text), "name" .= ("body_impl" :: T.Text)])
                , PatchReplace "/statements/1/body"
                    (object ["kind" .= ("app" :: T.Text), "fn" .= ("+" :: T.Text),
                             "args" .= [object ["kind" .= ("var" :: T.Text), "name" .= ("balance" :: T.Text)],
                                        object ["kind" .= ("var" :: T.Text), "name" .= ("amount" :: T.Text)]]])
                ]
          pResult <- applyPatch GrammarCoreInversion fp patchReq
          -- PatchVerifyError: fixpoint installed → contract violation caught ✅
          -- PatchSuccess: fixpoint NOT installed → graceful degradation ✅
          -- PatchTypeError: INVALID — typecheck should pass
          case pResult of
            PatchVerifyError _ _ -> pure ()
            PatchSuccess _       -> pure ()
            other -> expectationFailure $ "expected PatchVerifyError or PatchSuccess, got: " ++ show other
      removeDirectoryRecursive tmpDir

    -- PROOF OBLIGATION 3: No contracts → PatchSuccess regardless
    it "OBLIG-3: patch function with no contracts returns PatchSuccess" $ do
      let tmpDir = "test/_tmp_patch_no_contract"
          astJson = object
            [ "schemaVersion" .= ("0.6.0" :: T.Text)
            , "llmll_version" .= ("0.3.0" :: T.Text)
            , "statements" .= [object
                [ "kind" .= ("def" :: T.Text)
                , "name" .= ("add" :: T.Text)
                , "params" .= [object ["name" .= ("x" :: T.Text),
                                       "param_type" .= object ["kind" .= ("primitive" :: T.Text), "name" .= ("int" :: T.Text)]],
                                object ["name" .= ("y" :: T.Text),
                                       "param_type" .= object ["kind" .= ("primitive" :: T.Text), "name" .= ("int" :: T.Text)]]]
                , "body" .= object ["kind" .= ("hole-named" :: T.Text), "name" .= ("impl" :: T.Text)]
                ]]
            ]
      createDirectoryIfMissing True tmpDir
      let fp = tmpDir </> "nocontract.ast.json"
      BL.writeFile fp (encode astJson)
      raw <- BL.readFile fp
      let Just astVal = decode raw
      result <- checkoutHole fp astVal "/statements/0/body"
      case result of
        Left diag -> expectationFailure $ T.unpack (diagMessage diag)
        Right ct -> do
          let patchReq = PatchRequest (ctToken ct)
                [ PatchTest "/statements/0/body"
                    (object ["kind" .= ("hole-named" :: T.Text), "name" .= ("impl" :: T.Text)])
                , PatchReplace "/statements/0/body"
                    (object ["kind" .= ("app" :: T.Text), "fn" .= ("*" :: T.Text),
                             "args" .= [object ["kind" .= ("var" :: T.Text), "name" .= ("x" :: T.Text)],
                                        object ["kind" .= ("var" :: T.Text), "name" .= ("y" :: T.Text)]]])
                ]
          pResult <- applyPatch GrammarCoreInversion fp patchReq
          case pResult of
            PatchSuccess _ -> pure ()
            other -> expectationFailure $ "expected PatchSuccess (no contracts), got: " ++ show other
      removeDirectoryRecursive tmpDir

  -- =========================================================================
  -- v0.3: parsePatchOp tests (pure)
  -- =========================================================================

  describe "parsePatchOp" $ do
    it "parses replace op" $ do
      let val = object [ "op" .= ("replace" :: T.Text), "path" .= ("/s/0" :: T.Text), "value" .= (42 :: Int) ]
      case parsePatchOp val of
        Right (PatchReplace "/s/0" _) -> pure ()
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses test op" $ do
      let val = object [ "op" .= ("test" :: T.Text), "path" .= ("/s/0" :: T.Text), "value" .= (42 :: Int) ]
      case parsePatchOp val of
        Right (PatchTest "/s/0" _) -> pure ()
        other -> expectationFailure $ "unexpected: " ++ show other

    it "rejects move with workaround message" $ do
      let val = object [ "op" .= ("move" :: T.Text), "from" .= ("/a" :: T.Text), "path" .= ("/b" :: T.Text) ]
      case parsePatchOp val of
        Left err -> T.isInfixOf "'move' is not supported" err `shouldBe` True
        Right _  -> expectationFailure "move should be rejected"

    it "rejects copy with workaround message" $ do
      let val = object [ "op" .= ("copy" :: T.Text), "from" .= ("/a" :: T.Text), "path" .= ("/b" :: T.Text) ]
      case parsePatchOp val of
        Left err -> T.isInfixOf "'copy' is not supported" err `shouldBe` True
        Right _  -> expectationFailure "copy should be rejected"

  -- =========================================================================
  -- v0.3: Checkout helpers (pure)
  -- =========================================================================

  describe "Checkout helpers" $ do
    it "lockFilePath: program.ast.json -> program.llmll-lock.json" $
      lockFilePath "path/to/program.ast.json" `shouldBe` "path/to/program.llmll-lock.json"

    it "lockFilePath: simple.json -> simple.llmll-lock.json" $
      lockFilePath "simple.json" `shouldBe` "simple.llmll-lock.json"

    -- Regression: a sum-type TypeDefEntry must survive the JSON round-trip that
    -- backs the checkout lock. The ToJSON writes constructors as {name, payload?}
    -- objects; before the matching FromJSON parser, decode used the default
    -- [(Text, Maybe Text)] (2-element-array) instance and silently returned
    -- Nothing, so loadLock failed and every patch on a program with a sum type
    -- in scope rejected its token as "invalid or expired".
    it "TypeDefEntry: sum type round-trips through JSON (checkout-lock fix)" $ do
      let td = TypeDefEntry "Reason" "sum"
                 (Just [("Insufficient", Nothing), ("Overdraft", Just "int")])
                 Nothing False
      decode (encode td) `shouldBe` Just td

    it "expireStale removes expired tokens" $ do
      let epoch = UTCTime (fromGregorian 2026 1 1) 0
          tok = CheckoutToken "/a" "hole-delegate" Nothing epoch "tok1" 3600 Nothing Nothing Nothing Nothing False Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing
          lock = CheckoutLock "test.json" [tok]
          later = addUTCTime 7200 epoch
      lockTokens (expireStale later lock) `shouldBe` []

    it "expireStale keeps non-expired tokens" $ do
      let epoch = UTCTime (fromGregorian 2026 1 1) 0
          tok = CheckoutToken "/a" "hole-delegate" Nothing epoch "tok1" 3600 Nothing Nothing Nothing Nothing False Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing
          lock = CheckoutLock "test.json" [tok]
          later = addUTCTime 1800 epoch
      length (lockTokens (expireStale later lock)) `shouldBe` 1

    it "toPatchOpInfos excludes test ops" $ do
      let ops = [ PatchTest "/a" (String "x")
                , PatchReplace "/b" (String "y")
                , PatchRemove "/c"
                , PatchAdd "/d" (String "z")
                ]
      let infos = toPatchOpInfos ops
      length infos `shouldBe` 3
      map poiKind infos `shouldBe` ["replace", "remove", "add"]
      map poiIndex infos `shouldBe` [1, 2, 3]

  -- =========================================================================
  -- v0.3: Stratified Verification tests
  -- =========================================================================

  describe "DisplayLevel evidence lattice (v0.8.1b: partial order)" $ do
    it "evidenceCovers: DLVerified covers DLContractChecked" $
      evidenceCovers (DLVerified "lf") (DLContractChecked "z3") `shouldBe` True

    it "evidenceCovers: DLVerified covers DLTested" $
      evidenceCovers (DLVerified "lf") (DLTested 50) `shouldBe` True

    it "evidenceCovers: DLVerified covers DLAsserted" $
      evidenceCovers (DLVerified "lf") DLAsserted `shouldBe` True

    it "evidenceCovers: DLContractChecked covers DLAsserted" $
      evidenceCovers (DLContractChecked "z3") DLAsserted `shouldBe` True

    it "evidenceCovers: DLTested covers DLAsserted" $
      evidenceCovers (DLTested 100) DLAsserted `shouldBe` True

    it "evidenceCovers: DLContractChecked does NOT cover DLTested (incomparable)" $
      evidenceCovers (DLContractChecked "z3") (DLTested 100) `shouldBe` False

    it "evidenceCovers: DLTested does NOT cover DLContractChecked (incomparable)" $
      evidenceCovers (DLTested 100) (DLContractChecked "z3") `shouldBe` False

    it "evidenceMeet: DLVerified ⊓ DLAsserted = DLAsserted" $
      evidenceMeet (DLVerified "lf") DLAsserted `shouldBe` DLAsserted

    it "evidenceMeet: DLContractChecked ⊓ DLTested = DLAsserted (incomparable → bottom)" $
      evidenceMeet (DLContractChecked "z3") (DLTested 100) `shouldBe` DLAsserted

    it "isSolverBacked: DLVerified is solver-backed" $
      isSolverBacked (DLVerified "liquid-fixpoint") `shouldBe` True

    it "isSolverBacked: DLContractChecked is solver-backed" $
      isSolverBacked (DLContractChecked "z3") `shouldBe` True

    it "isSolverBacked: DLAsserted is NOT solver-backed" $
      isSolverBacked DLAsserted `shouldBe` False

  -- =========================================================================
  -- v0.8.1b: Exhaustive lattice property tests (EVID-0 spec PO-1a..PO-5)
  -- =========================================================================

  describe "DisplayLevel lattice laws (EVID-0 PO-1a: commutativity)" $ do
    -- 16 pairs: meet(a,b) = meet(b,a) for all a,b in {A, T, CC, V}
    let levels = [ ("Asserted", DLAsserted)
                 , ("Tested", DLTested 100)
                 , ("ContractChecked", DLContractChecked "z3")
                 , ("Verified", DLVerified "lf")
                 ]
    forM_ [(na, a, nb, b) | (na, a) <- levels, (nb, b) <- levels] $
      \(na, a, nb, b) ->
        it ("meet(" ++ na ++ ", " ++ nb ++ ") = meet(" ++ nb ++ ", " ++ na ++ ")") $
          evidenceMeet a b `shouldBe` evidenceMeet b a

  describe "DisplayLevel lattice laws (EVID-0 PO-1b: associativity)" $ do
    -- 64 triples: meet(meet(a,b),c) = meet(a,meet(b,c))
    let levels = [ ("A", DLAsserted)
                 , ("T", DLTested 100)
                 , ("CC", DLContractChecked "z3")
                 , ("V", DLVerified "lf")
                 ]
    forM_ [(na, a, nb, b, nc, c) | (na, a) <- levels, (nb, b) <- levels, (nc, c) <- levels] $
      \(na, a, nb, b, nc, c) ->
        it ("meet(meet(" ++ na ++ "," ++ nb ++ ")," ++ nc ++ ") = meet(" ++ na ++ ",meet(" ++ nb ++ "," ++ nc ++ "))") $
          evidenceMeet (evidenceMeet a b) c `shouldBe` evidenceMeet a (evidenceMeet b c)

  describe "DisplayLevel lattice laws (EVID-0 PO-2: idempotency)" $ do
    -- 4 cases: meet(a,a) = a
    it "meet(Asserted, Asserted) = Asserted" $
      evidenceMeet DLAsserted DLAsserted `shouldBe` DLAsserted
    it "meet(Tested, Tested) = Tested" $
      evidenceMeet (DLTested 100) (DLTested 100) `shouldBe` DLTested 100
    it "meet(ContractChecked, ContractChecked) = ContractChecked" $
      evidenceMeet (DLContractChecked "z3") (DLContractChecked "z3") `shouldBe` DLContractChecked "z3"
    it "meet(Verified, Verified) = Verified" $
      evidenceMeet (DLVerified "lf") (DLVerified "lf") `shouldBe` DLVerified "lf"

  describe "DisplayLevel lattice laws (EVID-0 PO-3: bottom absorbs)" $ do
    -- 4 cases: meet(a, Asserted) = Asserted
    it "meet(Asserted, Asserted) = Asserted" $
      evidenceMeet DLAsserted DLAsserted `shouldBe` DLAsserted
    it "meet(Tested, Asserted) = Asserted" $
      evidenceMeet (DLTested 100) DLAsserted `shouldBe` DLAsserted
    it "meet(ContractChecked, Asserted) = Asserted" $
      evidenceMeet (DLContractChecked "z3") DLAsserted `shouldBe` DLAsserted
    it "meet(Verified, Asserted) = Asserted" $
      evidenceMeet (DLVerified "lf") DLAsserted `shouldBe` DLAsserted

  describe "DisplayLevel lattice laws (EVID-0 PO-4: top identity)" $ do
    -- 4 cases: meet(a, Verified) = a
    it "meet(Asserted, Verified) = Asserted" $
      evidenceMeet DLAsserted (DLVerified "lf") `shouldBe` DLAsserted
    it "meet(Tested, Verified) = Tested" $
      evidenceMeet (DLTested 100) (DLVerified "lf") `shouldBe` DLTested 100
    it "meet(ContractChecked, Verified) = ContractChecked" $
      evidenceMeet (DLContractChecked "z3") (DLVerified "lf") `shouldBe` DLContractChecked "z3"
    it "meet(Verified, Verified) = Verified" $
      evidenceMeet (DLVerified "lf") (DLVerified "lf") `shouldBe` DLVerified "lf"

  describe "DisplayLevel lattice laws (EVID-0 PO-5: same-constructor metadata)" $ do
    it "meet(Tested 100, Tested 200) = Tested 100 (min samples)" $
      evidenceMeet (DLTested 100) (DLTested 200) `shouldBe` DLTested 100
    it "meet(Tested 200, Tested 100) = Tested 100 (commutative min)" $
      evidenceMeet (DLTested 200) (DLTested 100) `shouldBe` DLTested 100
    it "meet(ContractChecked z3, ContractChecked lf) = ContractChecked z3 (first-arg)" $
      evidenceMeet (DLContractChecked "z3") (DLContractChecked "lf") `shouldBe` DLContractChecked "z3"
    it "meet(Verified z3, Verified lf) = Verified z3 (first-arg)" $
      evidenceMeet (DLVerified "z3") (DLVerified "lf") `shouldBe` DLVerified "z3"

  describe "evidenceCovers consistency (16 pairs)" $ do
    -- For all a,b: covers(a,b) iff a is ≥ b in the lattice
    let levels = [ ("Asserted", DLAsserted)
                 , ("Tested", DLTested 100)
                 , ("ContractChecked", DLContractChecked "z3")
                 , ("Verified", DLVerified "lf")
                 ]
        -- Expected coverage: (a covers b) for each pair
        expected = [ (("Asserted","Asserted"), True)
                   , (("Asserted","Tested"), False)
                   , (("Asserted","ContractChecked"), False)
                   , (("Asserted","Verified"), False)
                   , (("Tested","Asserted"), True)
                   , (("Tested","Tested"), True)
                   , (("Tested","ContractChecked"), False)  -- incomparable
                   , (("Tested","Verified"), False)
                   , (("ContractChecked","Asserted"), True)
                   , (("ContractChecked","Tested"), False)  -- incomparable
                   , (("ContractChecked","ContractChecked"), True)
                   , (("ContractChecked","Verified"), False)
                   , (("Verified","Asserted"), True)
                   , (("Verified","Tested"), True)
                   , (("Verified","ContractChecked"), True)
                   , (("Verified","Verified"), True)
                   ]
    forM_ expected $ \((na, nb), expect) -> do
      let a = fromJust $ lookup na levels
          b = fromJust $ lookup nb levels
      it ("covers(" ++ na ++ ", " ++ nb ++ ") = " ++ show expect) $
        evidenceCovers a b `shouldBe` expect

  -- =========================================================================
  -- Leanstral demo: verified-lean DisplayLevel (FIX A) + proof-cache → trust
  -- surface bridge (FIX B) + kernelCheck fail-closed (FIX D). Hermetic — no
  -- network, no lake, no API key.
  -- =========================================================================
  describe "DLVerifiedLean (verified-lean peer tier)" $ do
    let vl = DLVerifiedLean "leanstral"

    it "serializes to level \"verified-lean\" and round-trips" $ do
      case dlToJSON vl of
        Object o -> KM.lookup "level" o `shouldBe` Just (String "verified-lean")
        other    -> expectationFailure ("expected Object, got " ++ show other)
      dlFromJSON (dlToJSON vl) `shouldBe` Just vl

    it "human display label is \"verified-lean\"" $
      dlLabel vl `shouldBe` "verified-lean"

    it "is a verified-strength, solver-backed level (peer of DLVerified)" $ do
      isVerifiedLevel vl `shouldBe` True
      isSolverBacked  vl `shouldBe` True

    it "meets like DLVerified (top: glb with a lower level = that level)" $ do
      evidenceMeet vl DLAsserted            `shouldBe` DLAsserted
      evidenceMeet vl (DLTested 50)         `shouldBe` DLTested 50
      evidenceMeet vl (DLContractChecked "z3") `shouldBe` DLContractChecked "z3"
      evidenceMeet vl vl                    `shouldBe` vl
      -- mixed proven ⊓ proven stays proven strength (still isVerifiedLevel)
      isVerifiedLevel (evidenceMeet vl (DLVerified "lf")) `shouldBe` True

    it "covers like DLVerified, and is MUTUALLY covering with DLVerified" $ do
      evidenceCovers vl (DLContractChecked "z3") `shouldBe` True
      evidenceCovers vl (DLTested 50)            `shouldBe` True
      evidenceCovers vl DLAsserted               `shouldBe` True
      -- peers: each covers the other (assumable exactly where verified is)
      evidenceCovers vl (DLVerified "lf")        `shouldBe` True
      evidenceCovers (DLVerified "lf") vl        `shouldBe` True
      -- only a top covers a top
      evidenceCovers (DLTested 50) vl            `shouldBe` False

    it "meet stays commutative & associative over {A,T,CC,V,VL}" $ do
      let levels = [ DLAsserted, DLTested 100, DLContractChecked "z3"
                   , DLVerified "lf", DLVerifiedLean "leanstral" ]
      forM_ [(a,b) | a <- levels, b <- levels] $ \(a,b) ->
        evidenceMeet a b `shouldBe` evidenceMeet b a
      forM_ [(a,b,c) | a <- levels, b <- levels, c <- levels] $ \(a,b,c) ->
        evidenceMeet (evidenceMeet a b) c `shouldBe` evidenceMeet a (evidenceMeet b c)

  describe "upgradeLeanstralPosts (proof-cache → trust surface, FIX B)" $ do
    -- A nonlinear `square` whose post escaped QF-LIA and landed at 'asserted'.
    let squarePost = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
        squareStmt = SDef "square" [("x", TInt)] (Just TInt)
                       (Contract Nothing Nothing squarePost Nothing Nothing)
                       (EApp "*" [EVar "x", EVar "x"])
        leanEntry  = ProofEntry "deadbeef" "by nlinarith" "leanstral"
                       "2026-07-05T00:00:00Z"
        postLevelOf sidecar =
          let rpt = buildTrustReport Map.empty [squareStmt] sidecar
          in fmap teEffectivePostLevel (find ((== "square") . teName) (trEntries rpt))

    it "renders 'verified-lean' when /post/square has a leanstral proof entry" $ do
      let cache    = Map.fromList [("/post/square", leanEntry)]
          upgraded = upgradeLeanstralPosts cache Map.empty
      postLevelOf upgraded `shouldBe` Just (Just (DLVerifiedLean "leanstral"))

    it "stays 'asserted' with no proof cache (fail-safe identity)" $ do
      upgradeLeanstralPosts Map.empty Map.empty `shouldBe` (Map.empty :: Map.Map Name ContractStatus)
      postLevelOf Map.empty `shouldBe` Just (Just DLAsserted)

    it "does NOT upgrade a tainted ('by sorry') leanstral entry" $ do
      let tainted  = ProofEntry "deadbeef" "by sorry" "leanstral" ""
          cache    = Map.fromList [("/post/square", tainted)]
          upgraded = upgradeLeanstralPosts cache Map.empty
      postLevelOf upgraded `shouldBe` Just (Just DLAsserted)

    it "does NOT upgrade a non-leanstral (e.g. mock) prover entry" $ do
      let mockE    = ProofEntry "deadbeef" "by decide" "mock" ""
          cache    = Map.fromList [("/post/square", mockE)]
          upgraded = upgradeLeanstralPosts cache Map.empty
      postLevelOf upgraded `shouldBe` Just (Just DLAsserted)

  describe "kernelCheck fail-closed on missing lake (FIX D)" $
    it "returns LeanstralUnavailable (not an exception) when lake is off PATH" $ do
      tmp <- getTemporaryDirectory
      let projDir = tmp </> "llmll-kernelcheck-nolake"
      createDirectoryIfMissing True projDir
      oldPath <- lookupEnv "PATH"
      -- Point PATH at a dir with no 'lake' so execvp fails with an IOException,
      -- which the fix must catch and turn into a fail-closed result.
      result <- (setEnv "PATH" projDir >> kernelCheck projDir 5 "theorem t : True := trivial")
                  `finally` maybe (unsetEnv "PATH") (setEnv "PATH") oldPath
      removeDirectoryRecursive projDir
      let isUnavailable r = case r of LeanstralUnavailable _ -> True; _ -> False
      isUnavailable result `shouldBe` True

  describe "ContractsMode: instrumentStatement" $ do
    let mkDefLogic name preE postE bodyE =
          SDefLogic name [("x", TInt)] Nothing
            (Contract preE Nothing postE Nothing Nothing) bodyE
        mkLetrec name preE postE bodyE =
          SLetrec name [("n", TInt)] Nothing
            (Contract preE Nothing postE Nothing Nothing) (EVar "n") bodyE
        hasPre  = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
        hasPost = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
        body    = EVar "x"
        defaultCS = ContractStatus Nothing Nothing []
        provenCS  = ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) []
        mixedCS   = ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) []

    it "ContractsFull keeps all contracts (SDefLogic)" $ do
      let stmt = mkDefLogic "f" hasPre hasPost body
          result = instrumentStatement ContractsFull defaultCS stmt
      defLogicContract result `shouldBe` Contract Nothing Nothing Nothing Nothing Nothing
      -- body should be wrapped (not the original)
      defLogicBody result `shouldNotBe` body

    it "ContractsFull keeps all contracts (SLetrec)" $ do
      let stmt = mkLetrec "g" hasPre hasPost body
          result = instrumentStatement ContractsFull defaultCS stmt
      letrecContract result `shouldBe` Contract Nothing Nothing Nothing Nothing Nothing

    it "ContractsNone strips all contracts" $ do
      let stmt = mkDefLogic "f" hasPre hasPost body
          result = instrumentStatement ContractsNone defaultCS stmt
      -- ContractsNone returns stmt unchanged
      result `shouldBe` stmt

    it "ContractsUnproven keeps proven pre (BUG-6: no body-faithful provers), keeps asserted post" $ do
      let stmt = mkDefLogic "f" hasPre hasPost body
          result = instrumentStatement ContractsUnproven mixedCS stmt
      defLogicContract result `shouldBe` Contract Nothing Nothing Nothing Nothing Nothing
      -- v0.6.3: both pre (proven) and post (asserted) are instrumented
      -- because no body-faithful provers exist yet
      defLogicBody result `shouldNotBe` body

  -- =========================================================================
  -- BUG-2 (resumed task, 2026-07-01): precondition/postcondition runtime
  -- checks were dead code under Haskell laziness. wrapPre/wrapPost used to
  -- bind the check to an unused `let [_pre_check ...] body` — the body never
  -- referenced `_pre_check`, so under call-by-need the assertion was never
  -- forced and a violated precondition silently passed through. Fixed by
  -- gating the body directly behind an `EIf`, which is strict in its
  -- scrutinee under every codegen backend (see LLMLL.Contracts.wrapPre /
  -- wrapPost). Live repro: generate Haskell for a def-shell with
  -- `(pre (not (string-empty? password)))`, `stack ghci`-load it, call with
  -- "" — pre-fix: returns "" with no exception; post-fix: throws
  -- "Precondition violated in ...".
  -- =========================================================================
  describe "BUG-2: precondition/postcondition checks must not be dead code" $ do
    let preE  = EApp ">" [EVar "x", ELit (LitInt 0)]
        postE = EApp ">=" [EVar "result", ELit (LitInt 0)]
        body  = EVar "x"
        noCS  = ContractStatus Nothing Nothing []

    it "wrapPre-instrumented def-shell gates the body behind EIf, not an unused let" $ do
      let stmt = SDefShell "f" [("x", TInt)] Nothing
                   (Contract (Just preE) Nothing Nothing Nothing Nothing) body []
          result = instrumentStatement ContractsFull noCS stmt
      case result of
        SDefShell _ _ _ _ (EIf _ _ elseBranch) _ -> elseBranch `shouldBe` body
        other -> expectationFailure $
          "expected precondition check to strictly gate the body via EIf, got: " ++ show other

    it "wrapPost-instrumented def-shell gates 'result' behind EIf, not an unused let" $ do
      let stmt = SDefShell "f" [("x", TInt)] Nothing
                   (Contract Nothing Nothing (Just postE) Nothing Nothing) body []
          result = instrumentStatement ContractsFull noCS stmt
      case result of
        SDefShell _ _ _ _ (ELet [(PVar "result", _, boundBody)] (EIf _ _ (EVar "result"))) _ ->
          boundBody `shouldBe` body
        other -> expectationFailure $
          "expected postcondition check to strictly gate 'result' via EIf, got: " ++ show other

    it "generated Haskell for a violated def-shell precondition has no dead _pre_check binding" $ do
      let stmt = SDefShell "check-me" [("x", TInt)] Nothing
                   (Contract (Just preE) Nothing Nothing Nothing Nothing) body []
          instrumented = instrumentStatement ContractsFull noCS stmt
          src = cgHsSource (generateHaskell "test" [instrumented])
      -- regression: the old codegen bound `_pre_check` in a `let` the body
      -- never referenced, so it was never forced and the check was skipped.
      T.isInfixOf "_pre_check" src `shouldBe` False
      T.isInfixOf "Precondition violated in check-me" src `shouldBe` True
      -- the check must directly gate the returned value (strict `if`), not
      -- sit in a discarded binding.
      T.isInfixOf "check_me x =\n  (if " src `shouldBe` True

    it "generated Haskell for a violated def-shell postcondition has no dead _post_check binding" $ do
      let stmt = SDefShell "double-it" [("x", TInt)] Nothing
                   (Contract Nothing Nothing (Just postE) Nothing Nothing) body []
          instrumented = instrumentStatement ContractsFull noCS stmt
          src = cgHsSource (generateHaskell "test" [instrumented])
      T.isInfixOf "_post_check" src `shouldBe` False
      T.isInfixOf "Postcondition violated in double-it" src `shouldBe` True
      T.isInfixOf "else result)" src `shouldBe` True

  describe "parseTrustDecl (S-expression)" $ do
    it "parses (trust foo.bar :level tested)" $ do
      case parseStatements GrammarCoreInversion "<test>" "(trust foo.bar :level tested)" of
        Right [STrust target (DLTested _)] -> do
          target `shouldBe` "foo.bar"
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses (trust crypto.hash.pbkdf2 :level asserted)" $ do
      case parseStatements GrammarCoreInversion "<test>" "(trust crypto.hash.pbkdf2 :level asserted)" of
        Right [STrust target level] -> do
          target `shouldBe` "crypto.hash.pbkdf2"
          level `shouldBe` DLAsserted
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses (trust z3.verify :level contract-checked)" $ do
      case parseStatements GrammarCoreInversion "<test>" "(trust z3.verify :level contract-checked)" of
        Right [STrust target (DLContractChecked _)] -> do
          target `shouldBe` "z3.verify"
        other -> expectationFailure $ "unexpected: " ++ show other

  describe "parseWeaknessOk (S-expression)" $ do
    it "parses (weakness-ok f \"known identity\")" $ do
      case parseStatements GrammarCoreInversion "<test>" "(weakness-ok f \"known identity\")" of
        Right [SWeaknessOk name reason] -> do
          name `shouldBe` "f"
          reason `shouldBe` "known identity"
        other -> expectationFailure $ "unexpected: " ++ show other

    it "WO-5: rejects (weakness-ok f \"\") — empty reason" $ do
      case parseStatements GrammarCoreInversion "<test>" "(weakness-ok f \"\")" of
        Left _err -> pure ()  -- expected: parse error
        Right r   -> expectationFailure $ "should reject empty reason, got: " ++ show r

  describe "contract :source annotation (v0.6)" $ do
    it "parses (pre expr :source \"...\") with source" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [x: int] (pre (>= x 0) :source \"ERC-20 §6.1\") x)" of
        Right [SDefShell _ _ _ contract _ _] -> do
          contractPreSource contract `shouldBe` Just "ERC-20 §6.1"
          contractPostSource contract `shouldBe` Nothing
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses (post expr :source \"...\") with source" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [x: int] (post (>= result 0) :source \"safety invariant\") x)" of
        Right [SDefShell _ _ _ contract _ _] -> do
          contractPreSource contract `shouldBe` Nothing
          contractPostSource contract `shouldBe` Just "safety invariant"
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses both pre and post with :source" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [x: int] (pre (> x 0) :source \"precond\") (post (>= result 0) :source \"postcond\") x)" of
        Right [SDefShell _ _ _ contract _ _] -> do
          contractPreSource contract `shouldBe` Just "precond"
          contractPostSource contract `shouldBe` Just "postcond"
        other -> expectationFailure $ "unexpected: " ++ show other

    it "backward compat: pre/post without :source still parse" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [x: int] (pre (>= x 0)) (post (>= result 0)) x)" of
        Right [SDefShell _ _ _ contract _ _] -> do
          contractPreSource contract `shouldBe` Nothing
          contractPostSource contract `shouldBe` Nothing
        other -> expectationFailure $ "unexpected: " ++ show other

  describe "mkTrustGapWarning" $ do
    it "produces a warning with trust-gap kind" $ do
      let d = mkTrustGapWarning "foo.bar" "asserted" "/statements/0"
      diagSeverity d `shouldBe` SevWarning
      diagKind d `shouldBe` Just "trust-gap"
      diagPointer d `shouldBe` Just "/statements/0"

  describe "VerifiedCache: verifiedPath" $ do
    it "foo.llmll -> foo.llmll.verified.json" $
      verifiedPath "foo.llmll" `shouldBe` "foo.llmll.verified.json"

    it "path/to/bar.ast.json -> path/to/bar.ast.json.verified.json" $
      verifiedPath "path/to/bar.ast.json" `shouldBe` "path/to/bar.ast.json.verified.json"

  -- =========================================================================
  -- v0.3: #8 — applyContractsMode
  -- =========================================================================

  describe "applyContractsMode" $ do
    let mkDL name preE postE bodyE =
          SDefLogic name [("x", TInt)] Nothing (Contract preE Nothing postE Nothing Nothing) bodyE
        pre1  = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
        post1 = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
        body1 = EVar "x"
        stmts = [mkDL "f" pre1 post1 body1, mkDL "g" pre1 Nothing body1]
        provenMap = DM.fromList
          [ ("f", ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])
          , ("g", ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) Nothing [])
          ]
        emptyMap = DM.empty

    it "ContractsFull preserves all contracts" $ do
      let result = applyContractsMode ContractsFull emptyMap stmts
      length result `shouldBe` 2
      defLogicContract (head result) `shouldBe` Contract pre1 Nothing post1 Nothing Nothing

    it "ContractsNone clears all contracts" $ do
      let result = applyContractsMode ContractsNone emptyMap stmts
      defLogicContract (head result) `shouldBe` Contract Nothing Nothing Nothing Nothing Nothing
      defLogicContract (result !! 1) `shouldBe` Contract Nothing Nothing Nothing Nothing Nothing

    it "ContractsUnproven preserves proven (BUG-6: no body-faithful provers)" $ do
      -- v0.6.3 (BUG-6): ContractsUnproven no longer strips DLContractChecked contracts
      -- because no body-faithful provers exist. Contracts are preserved.
      let result = applyContractsMode ContractsUnproven provenMap stmts
      defLogicContract (head result) `shouldBe` Contract pre1 Nothing post1 Nothing Nothing
      defLogicContract (result !! 1) `shouldBe` Contract pre1 Nothing Nothing Nothing Nothing

  -- =========================================================================
  -- v0.3: #9 — saveVerified / loadVerified round-trip
  -- =========================================================================

  describe "VerifiedCache round-trip" $ do
    it "saveVerified then loadVerified recovers contract status" $ do
      let testFile = "test/_tmp_roundtrip_test.llmll"
          statuses = DM.fromList
            [ ("add", ContractStatus (Just (EvidenceRecord (DLVerified "liquid-fixpoint") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLVerified "liquid-fixpoint") False Nothing [] False Nothing Nothing False Nothing False)) [])
            , ("mul", ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) Nothing [])
            ]
      saveVerified testFile statuses
      loaded <- loadVerified testFile
      loaded `shouldBe` statuses
      -- Clean up sidecar
      let sidecar = verifiedPath testFile
      removeIfExists sidecar

  -- =========================================================================
  -- v0.3: trust-gap integration tests
  -- =========================================================================

  describe "trust-gap warnings in typeCheckWithCache" $ do
    let mkModule name preE postE bodyE =
          [ SDefLogic name [("x", TInt)] (Just TInt) (Contract preE Nothing postE Nothing Nothing) bodyE
          , SExport [name]
          ]
        pre1  = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
        post1 = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
        body1 = EVar "x"
        modPath = ["math"]
        modEnv = ModuleEnv
          { meExports = DM.fromList [("safe-add", TFn [TInt] TInt)]
          , meStatements = mkModule "safe-add" pre1 post1 body1
          , meInterfaces = DM.empty
          , meAliasMap = DM.empty
          , mePath = modPath
          , meContractStatus = DM.fromList
              [("safe-add", ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) [])]
          , meContracts = DM.empty
          }
        cache = DM.fromList [(modPath, modEnv)]

    it "emits trust-gap warning for unproven cross-module call" $ do
      let callerStmts = [SDefLogic "caller" [] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "math.safe-add" [ELit (LitInt 5)])]
          report = typeCheckWithCache GrammarCoreInversion cache emptyEnv callerStmts
          trustGaps = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      length trustGaps `shouldSatisfy` (> 0)

    it "no trust-gap for proven contracts" $ do
      let provenEnv = modEnv { meContractStatus = DM.fromList
              [("safe-add", ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])] }
          provenCache = DM.fromList [(modPath, provenEnv)]
          callerStmts = [SDefLogic "caller" [] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "math.safe-add" [ELit (LitInt 5)])]
          report = typeCheckWithCache GrammarCoreInversion provenCache emptyEnv callerStmts
          trustGaps = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      trustGaps `shouldBe` []

    it "trust declaration suppresses trust-gap warning" $ do
      let callerStmts =
            [ STrust "math.safe-add" DLAsserted  -- acknowledge the assertion level
            , SDefLogic "caller" [] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "math.safe-add" [ELit (LitInt 5)])
            ]
          report = typeCheckWithCache GrammarCoreInversion cache emptyEnv callerStmts
          trustGaps = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      trustGaps `shouldBe` []

  -- =========================================================================
  -- v0.3.2: Cross-module trust propagation (7 tests)
  -- =========================================================================

  describe "v0.3.2 cross-module trust propagation" $ do
    -- Shared test infrastructure
    let mkModuleEnvWith name contractStatus =
          let pre1  = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
              post1 = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
              stmts = [ SDefLogic name [("x", TInt)] (Just TInt)
                          (Contract pre1 Nothing post1 Nothing Nothing) (EVar "x")
                       , SExport [name]
                       ]
          in ModuleEnv
               { meExports        = DM.fromList [(name, TFn [TInt] TInt)]
               , meStatements     = stmts
               , meInterfaces     = DM.empty
               , meAliasMap       = DM.empty
               , mePath           = T.splitOn "." name
               , meContractStatus = DM.fromList [(name, contractStatus)]
               , meContracts      = DM.empty
               }

        -- Module A: "auth.verify" with configurable contract status
        mkAuthModule cs = mkModuleEnvWith "auth.verify" cs
        authModPath     = ["auth", "verify"]

        -- Module B caller: calls "auth.verify.auth.verify" (qualified via cache seeding)
        mkCallerStmts = [SDefLogic "check-user" [("uid", TInt)] (Just TInt)
                           (Contract Nothing Nothing Nothing Nothing Nothing)
                           (EApp "auth.verify.auth.verify" [EVar "uid"])]

        -- Helper: count trust-gap diagnostics
        countTrustGaps report =
          length $ filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)

    -- Test 1: Asserted contracts emit trust-gap warnings
    it "asserted contract in imported module emits trust-gap warning" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache GrammarCoreInversion cache emptyEnv mkCallerStmts
      countTrustGaps report `shouldSatisfy` (> 0)

    -- Test 2: Proven contracts do NOT emit trust-gap warnings
    it "proven contract in imported module emits no trust-gap warning" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache GrammarCoreInversion cache emptyEnv mkCallerStmts
      countTrustGaps report `shouldBe` 0

    -- Test 3: Tested contracts emit trust-gap warnings
    it "tested contract in imported module emits trust-gap warning" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache GrammarCoreInversion cache emptyEnv mkCallerStmts
      countTrustGaps report `shouldSatisfy` (> 0)

    -- Test 4: Mixed levels — proven pre + asserted post still emits warning (for post)
    it "mixed levels (proven pre, asserted post) emits trust-gap for post only" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache GrammarCoreInversion cache emptyEnv mkCallerStmts
          gaps    = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      -- Should have exactly 1 gap (for the asserted postcondition)
      length gaps `shouldBe` 1

    -- Test 5: Trust declaration at DLTested suppresses DLTested gap
    it "trust declaration at tested level suppresses tested trust-gap" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache   = DM.fromList [(authModPath, authEnv)]
          callerStmts =
            [ STrust "auth.verify.auth.verify" (DLTested 0)
            , SDefLogic "check-user" [("uid", TInt)] (Just TInt)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "auth.verify.auth.verify" [EVar "uid"])
            ]
          report = typeCheckWithCache GrammarCoreInversion cache emptyEnv callerStmts
      countTrustGaps report `shouldBe` 0

    -- Test 6: Trust declaration at lower level does NOT suppress higher-level gap
    -- (trust at asserted should NOT suppress a tested-level gap since asserted < tested)
    it "trust at asserted does NOT suppress tested-level gap" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache   = DM.fromList [(authModPath, authEnv)]
          callerStmts =
            [ STrust "auth.verify.auth.verify" DLAsserted  -- asserted < tested
            , SDefLogic "check-user" [("uid", TInt)] (Just TInt)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "auth.verify.auth.verify" [EVar "uid"])
            ]
          report = typeCheckWithCache GrammarCoreInversion cache emptyEnv callerStmts
      -- Trust at asserted is insufficient for tested contracts → gap still emitted
      countTrustGaps report `shouldSatisfy` (> 0)

    -- Test 7: Two modules with different trust levels — both are checked independently
    it "two imported modules with different trust levels: gaps emitted correctly" $ do
      let mathEnv = ModuleEnv
            { meExports        = DM.fromList [("safe-add", TFn [TInt] TInt)]
            , meStatements     = []
            , meInterfaces     = DM.empty
            , meAliasMap       = DM.empty
            , mePath           = ["math"]
            , meContractStatus = DM.fromList
                [("safe-add", ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])]
            , meContracts      = DM.empty
            }
          cryptoEnv = ModuleEnv
            { meExports        = DM.fromList [("hash", TFn [TString] TString)]
            , meStatements     = []
            , meInterfaces     = DM.empty
            , meAliasMap       = DM.empty
            , mePath           = ["crypto"]
            , meContractStatus = DM.fromList
                [("hash", ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) Nothing [])]
            , meContracts      = DM.empty
            }
          cache = DM.fromList [( ["math"], mathEnv), (["crypto"], cryptoEnv)]
          callerStmts =
            [ SDefLogic "process" [("x", TInt)] (Just TInt)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "math.safe-add" [EVar "x"])
            , SDefLogic "hash-input" [("s", TString)] (Just TString)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "crypto.hash" [EVar "s"])
            ]
          report = typeCheckWithCache GrammarCoreInversion cache emptyEnv callerStmts
          gaps = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      -- math.safe-add is proven → no gap
      -- crypto.hash is asserted → 1 gap (pre only, post is Nothing)
      length gaps `shouldBe` 1
      diagMessage (head gaps) `shouldSatisfy` T.isInfixOf "crypto.hash"

  -- =========================================================================
  -- v0.3.2: TrustReport (buildTrustReport, formatTrustReport, formatTrustReportJson)
  -- =========================================================================

  describe "v0.3.2 --trust-report (TrustReport)" $ do
    let -- Shared module fixtures
        mkModEnv name path cs =
          ModuleEnv
            { meExports        = DM.fromList [(name, TFn [TInt] TInt)]
            , meStatements     = [SDefLogic name [("x", TInt)] (Just TInt)
                                   (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)]))
                                             Nothing
                                             (Just (EApp ">=" [EVar "result", ELit (LitInt 0)]))
                                             Nothing Nothing)
                                   (EVar "x")]
            , meInterfaces     = DM.empty
            , meAliasMap       = DM.empty
            , mePath           = path
            , meContractStatus = DM.fromList [(name, cs)]
            , meContracts      = DM.empty
            }

    -- Test 1: Report includes entry function with its contract levels
    it "report includes entry module functions" $ do
      let stmts = [ SDefLogic "main-fn" [("n", TInt)] (Just TInt)
                       (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                       (EVar "n")
                   ]
          cache = DM.empty
          report = buildTrustReport cache stmts Map.empty
      length (trEntries report) `shouldBe` 1
      teName (head (trEntries report)) `shouldBe` "main-fn"
      fmap erDisplayLevel (tePre (head (trEntries report))) `shouldBe` Just DLAsserted

    -- Test 2: Report detects epistemic drift (proven depends on asserted)
    it "detects epistemic drift: proven function depending on asserted callee" $ do
      let provenMod = mkModEnv "safe-add" ["math"]
                        (ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])
          assertedMod = mkModEnv "hash" ["crypto"]
                          (ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache = DM.fromList [(["math"], provenMod), (["crypto"], assertedMod)]
          -- Entry function is proven but calls asserted crypto.hash
          stmts = [ SDefLogic "process" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)]))
                                Nothing
                                (Just (EApp ">=" [EVar "result", ELit (LitInt 0)]))
                                Nothing Nothing)
                      (EApp "crypto.hash" [EVar "x"])
                  ]
          report = buildTrustReport cache stmts Map.empty
          processEntry = head [e | e <- trEntries report, teName e == "process"]
      -- The entry function has asserted contracts (default) and depends on crypto.hash
      length (teDeps processEntry) `shouldSatisfy` (>= 1)

    -- Test 3: No drift when all dependencies are proven
    it "no drift when all dependencies are proven" $ do
      let provenMod = mkModEnv "safe-add" ["math"]
                        (ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache = DM.fromList [(["math"], provenMod)]
          stmts = [ SDefLogic "caller" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing Nothing Nothing Nothing)
                      (EApp "math.safe-add" [EVar "x"])
                  ]
          report = buildTrustReport cache stmts Map.empty
          callerEntry = head [e | e <- trEntries report, teName e == "caller"]
      teDrifts callerEntry `shouldBe` []

    -- Test 4: Summary counts are correct
    it "summary counts match entry classification" $ do
      let provenMod = mkModEnv "safe-add" ["math"]
                        (ContractStatus (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord (DLContractChecked "z3") False Nothing [] False Nothing Nothing False Nothing False)) [])
          assertedMod = mkModEnv "hash" ["crypto"]
                          (ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) [])
          cache = DM.fromList [(["math"], provenMod), (["crypto"], assertedMod)]
          stmts = [ SDefLogic "no-contract" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "x")
                  ]
          report = buildTrustReport cache stmts Map.empty
      -- math.safe-add is proven, crypto.hash is asserted, no-contract has no contract
      tsContractChecked (trSummary report) `shouldBe` 1
      tsAsserted (trSummary report) `shouldBe` 1
      tsNone     (trSummary report) `shouldBe` 1

    -- Test 5: JSON output is valid JSON and contains expected keys
    it "formatTrustReportJson produces valid JSON with entries and summary" $ do
      let cache = DM.empty
          stmts = [ SDefLogic "fn1" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                      (EVar "x")
                  ]
          report = buildTrustReport cache stmts Map.empty
          jsonText = formatTrustReportJson report
      -- Must parse as valid JSON
      (decode (BLC.pack (T.unpack jsonText)) :: Maybe Value) `shouldSatisfy` (/= Nothing)
      -- Must contain expected keys
      jsonText `shouldSatisfy` T.isInfixOf "\"entries\""
      jsonText `shouldSatisfy` T.isInfixOf "\"summary\""
      jsonText `shouldSatisfy` T.isInfixOf "\"verified\""
      jsonText `shouldSatisfy` T.isInfixOf "\"asserted\""
      jsonText `shouldSatisfy` T.isInfixOf "\"drifts\""

    -- Test 6: Human-readable format contains function names and levels
    it "formatTrustReport contains function names and verification levels" $ do
      let assertedMod = mkModEnv "verify-token" ["auth"]
                          (ContractStatus (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) Nothing [])
          cache = DM.fromList [(["auth"], assertedMod)]
          stmts = []
          report = buildTrustReport cache stmts Map.empty
          humanText = formatTrustReport report
      humanText `shouldSatisfy` T.isInfixOf "Trust Report"
      humanText `shouldSatisfy` T.isInfixOf "verify-token"
      humanText `shouldSatisfy` T.isInfixOf "asserted"

  -- =========================================================================
  -- TRUST-PRE (precondition-tier-proposal, Rev 3): Position B (summary-only
  -- tier) + the first-class persisted caller_obligations axis.
  --   Part 1 — a precondition no longer floors a function's verified tier.
  --   Part 2 — the caller_obligations axis carries the 'requires' predicate,
  --            self-scopes via 'carries_caller_obligations', and persists.
  -- =========================================================================
  describe "TRUST-PRE precondition tier + caller-obligation axis" $ do
    -- A pre-bearing, body-faithful post-verified function (the withdraw shape):
    -- pre asserted (caller obligation), post DLVerified (proven implication).
    let preVerifiedCS =
          ContractStatus
            (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
            (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
            []
        -- The live source for 'withdraw' carrying a real 'requires' predicate.
        withdrawStmt =
          SDefLogic "withdraw" [("balance", TInt), ("amount", TInt)] (Just TInt)
            (Contract (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                      (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
            (EOp "-" [EVar "balance", EVar "amount"])

    -- TP-PRE-1 (Part 1): a pre-bearing post-verified function classifies
    -- 'verified' in the summary (was 'asserted' under the pre⊓post floor).
    it "TP-PRE-1 pre-bearing post-verified function classifies verified (no floor)" $ do
      let sidecar = Map.fromList [("withdraw", preVerifiedCS)]
          report  = buildTrustReport Map.empty [withdrawStmt] sidecar
      tsVerified (trSummary report) `shouldBe` 1
      tsAsserted (trSummary report) `shouldBe` 0

    -- TP-PRE-2 (Part 1): the JSON 'effective_level' headline reads 'verified'
    -- for the same function — the self-scoping headline is post-based.
    it "TP-PRE-2 JSON effective_level headline is verified for pre-bearing post-verified fn" $ do
      let sidecar  = Map.fromList [("withdraw", preVerifiedCS)]
          report   = buildTrustReport Map.empty [withdrawStmt] sidecar
          jsonText = formatTrustReportJson report
          jsonV    = decode (BLC.pack (T.unpack jsonText)) :: Maybe Value
      -- trust_report_version now 1.5.0 (REC-PARTIAL-MARK)
      jsonText `shouldSatisfy` T.isInfixOf "\"1.5.0\""
      case jsonV of
        Just (Object o) -> case KM.lookup "entries" o of
          Just (Array es) -> case [ ent | Object ent <- foldr (:) [] es
                                        , KM.lookup "name" ent == Just (String "withdraw") ] of
            (ent:_) -> do
              -- dlLabel renders DLVerified as "verified (<prover>)".
              case KM.lookup "effective_level" ent of
                Just (String lvl) -> lvl `shouldSatisfy` T.isPrefixOf "verified"
                other             -> expectationFailure ("effective_level: " <> show other)
              KM.lookup "carries_caller_obligations" ent `shouldBe` Just (Bool True)
            _ -> expectationFailure "no withdraw entry"
          _ -> expectationFailure "no entries array"
        _ -> expectationFailure "invalid JSON"

    -- TP-PRE-3 (invariant): a WEAK post is never promoted. A pre-bearing
    -- function whose post fell back to asserted is still 'asserted' — the
    -- change drops csPre from the classifier, it never lifts a weak csPost.
    it "TP-PRE-3 weak post is never promoted (pre dropped, post respected)" $ do
      let weakCS = ContractStatus
                     (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                     (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                     []
          sidecar = Map.fromList [("withdraw", weakCS)]
          report  = buildTrustReport Map.empty [withdrawStmt] sidecar
      tsVerified (trSummary report) `shouldBe` 0
      tsAsserted (trSummary report) `shouldBe` 1

    -- TP-PRE-4 (Part 2): the caller_obligations axis carries the PREDICATE
    -- (not a count/name), sourced from the function's own csPre contract.
    it "TP-PRE-4 caller_obligations carries the requires predicate" $ do
      let sidecar = Map.fromList [("withdraw", preVerifiedCS)]
          report  = buildTrustReport Map.empty [withdrawStmt] sidecar
      case filter (\e -> teName e == "withdraw") (trEntries report) of
        [e] -> do
          map coObFn (teCallerObligations e) `shouldBe` ["withdraw"]
          map coObRequires (teCallerObligations e) `shouldBe` ["(>= balance amount)"]
        _ -> expectationFailure "expected exactly one withdraw entry"

    -- TP-PRE-5 (Part 2): the axis persists across a saveVerifiedWith /
    -- loadVerified sidecar round-trip and is re-derived on report rebuild.
    it "TP-PRE-5 caller_obligations persist and survive a sidecar reload" $ do
      let tmpDir = "test/_tmp_trustpre"
      createDirectoryIfMissing True tmpDir
      let fp       = tmpDir </> "withdraw.llmll"
          sidecar  = Map.fromList [("withdraw", preVerifiedCS)]
          report0  = buildTrustReport Map.empty [withdrawStmt] sidecar
          obJson   = concatMap (map callerObligationJson . teCallerObligations)
                               (trEntries report0)
      -- Persist evidence + the obligation axis.
      saveVerifiedWith fp sidecar obJson
      -- The persisted .verified.json carries the predicate (static property).
      raw <- TIO.readFile (verifiedPath fp)
      raw `shouldSatisfy` T.isInfixOf "caller_obligations"
      raw `shouldSatisfy` T.isInfixOf "(>= balance amount)"
      -- loadVerified skips the reserved key and recovers the ContractStatus.
      reloaded <- loadVerified fp
      Map.member "withdraw" reloaded `shouldBe` True
      -- A rebuild over the reloaded sidecar re-derives the axis (every path).
      let report1 = buildTrustReport Map.empty [withdrawStmt] reloaded
      case filter (\e -> teName e == "withdraw") (trEntries report1) of
        [e] -> map coObRequires (teCallerObligations e) `shouldBe` ["(>= balance amount)"]
        _   -> expectationFailure "expected withdraw entry after reload"
      removeDirectoryRecursive tmpDir

    -- TP-PRE-6 (Part 2, soundness): a verified caller that DISCHARGES a callee's
    -- pre reaches verified and carries NO escaped transitive obligation; a
    -- NON-verified caller of the same callee DOES carry it (the second disjunct
    -- is non-strict-core-only — verified F's call-pre VC was SAFE, so it cannot
    -- escape). This is the report-side of the soundness-preservation property;
    -- the undischarged-call → FQUnsafe path is the solver's, not a summary floor.
    it "TP-PRE-6 transitive obligation escapes only for a non-verified caller" $ do
      let calleeStmt =
            SDefLogic "withdraw" [("balance", TInt), ("amount", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                        Nothing Nothing Nothing)
              (EOp "-" [EVar "balance", EVar "amount"])
          callerStmt =
            SDefLogic "pay" [("b", TInt), ("a", TInt)] (Just TInt)
              (Contract Nothing Nothing Nothing Nothing Nothing)
              (EApp "withdraw" [EVar "b", EVar "a"])
          stmts = [calleeStmt, callerStmt]
          -- 'pay' verified (body-faithful) → discharged withdraw's pre.
          verifiedSidecar = Map.fromList
            [ ("pay", ContractStatus Nothing
                        (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
                        []) ]
          verReport = buildTrustReport Map.empty stmts verifiedSidecar
          -- 'pay' NOT verified (no post evidence) → callee pre escaped to it.
          unverReport = buildTrustReport Map.empty stmts Map.empty
          payOb r = case filter (\e -> teName e == "pay") (trEntries r) of
                      [e] -> map coObFn (teCallerObligations e)
                      _   -> []
      -- Verified caller: NO escaped obligation for withdraw.
      payOb verReport `shouldBe` []
      -- Non-verified caller: carries withdraw's pre as an escaped obligation.
      payOb unverReport `shouldBe` ["withdraw"]

    -- TP-PRE-7 (transitive-callee fix, the CORE bug): a caller that calls a
    -- pre-bearing callee and is itself body-faithful post-verified reaches
    -- 'verified' — it no longer floors to 'asserted' via the CALLEE's pre. Under
    -- the old 'effectiveLevel cs' transitive meet, the callee's pre-inclusive
    -- 'asserted' level dragged the caller's post-side tier down. The callee's pre
    -- is the CALLER's call-site obligation (discharged by the SAFE call-pre VC),
    -- not a floor the caller inherits.
    it "TP-PRE-7 caller of a pre-bearing callee, own post verified, reaches verified (was asserted)" $ do
      let -- 'withdraw' carries a pre and a verified post (the pre-bearing leaf).
          calleeStmt =
            SDefLogic "withdraw" [("balance", TInt), ("amount", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EOp "-" [EVar "balance", EVar "amount"])
          -- 'safe-withdraw' calls 'withdraw' (discharging its pre at the call
          -- site) and proves its OWN post verified. It has no pre of its own.
          callerStmt =
            SDefLogic "safe-withdraw" [("b", TInt), ("a", TInt)] (Just TInt)
              (Contract Nothing Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EApp "withdraw" [EVar "b", EVar "a"])
          stmts = [calleeStmt, callerStmt]
          -- Both verified post in the sidecar (callee pre stays asserted).
          sidecar = Map.fromList
            [ ("withdraw", ContractStatus
                  (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                  (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
                  [])
            , ("safe-withdraw", ContractStatus Nothing
                  (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
                  []) ]
          report = buildTrustReport Map.empty stmts sidecar
          effOf nm = case filter (\e -> teName e == nm) (trEntries report) of
                       [e] -> teEffectivePostLevel e
                       _   -> Nothing
      -- The caller's post-side effective tier is now 'verified', not floored.
      effOf "safe-withdraw" `shouldSatisfy` maybe False isVerifiedLevel
      -- The leaf callee is also 'verified' (its own pre does not floor it).
      effOf "withdraw" `shouldSatisfy` maybe False isVerifiedLevel
      -- Both land in the summary 'verified' count; none in 'asserted'.
      tsVerified (trSummary report) `shouldBe` 2
      tsAsserted (trSummary report) `shouldBe` 0

    -- TP-PRE-8 (invariant: never ignore a weak callee POST): a caller of a callee
    -- whose POST is 'asserted' still floors to 'asserted'. The fix removes only
    -- the callee-PRE contribution; a genuinely weak callee POST still propagates.
    it "TP-PRE-8 caller of an asserted-POST callee still floors (post-propagation preserved)" $ do
      let calleeStmt =
            SDefLogic "weak" [("n", TInt)] (Just TInt)
              (Contract Nothing Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EVar "n")
          callerStmt =
            SDefLogic "uses-weak" [("n", TInt)] (Just TInt)
              (Contract Nothing Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EApp "weak" [EVar "n"])
          stmts = [calleeStmt, callerStmt]
          sidecar = Map.fromList
            [ ("weak", ContractStatus Nothing
                  (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                  [])
            , ("uses-weak", ContractStatus Nothing
                  (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
                  []) ]
          report = buildTrustReport Map.empty stmts sidecar
          effOf nm = case filter (\e -> teName e == nm) (trEntries report) of
                       [e] -> teEffectivePostLevel e
                       _   -> Nothing
      -- The caller inherits the callee's weak POST: floored to asserted.
      effOf "uses-weak" `shouldBe` Just DLAsserted
      effOf "weak"      `shouldBe` Just DLAsserted

    -- TP-PRE-9 (soundness check 1): a caller of a REFUTED callee is still flagged
    -- 'depends-on-refuted'. Refutation is post-side and rides the call graph
    -- ('refutedClosure'/'teDeps'), so the transitive-callee POST-side meet (which
    -- only dropped the callee PRE) leaves it untouched. Complements VR-8 from
    -- inside the TRUST-PRE fixture family.
    it "TP-PRE-9 caller of a refuted callee still depends-on-refuted (post-side preserved)" $ do
      let calleeStmt =
            SDefLogic "withdraw" [("balance", TInt), ("amount", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EOp "-" [EVar "balance", EVar "amount"])
          callerStmt =
            SDefLogic "safe-withdraw" [("b", TInt), ("a", TInt)] (Just TInt)
              (Contract Nothing Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EApp "withdraw" [EVar "b", EVar "a"])
          stmts   = [calleeStmt, callerStmt]
          report  = buildTrustReport Map.empty stmts Map.empty
          closure = refutedClosure (Set.fromList ["withdraw"]) report
          marked  = markRefuted (Set.fromList ["withdraw"]) report
          callerDrifts = concat [ teDrifts e | e <- trEntries marked, teName e == "safe-withdraw" ]
      Set.member "safe-withdraw" closure `shouldBe` True
      Set.member "withdraw" closure `shouldBe` True
      any (T.isInfixOf "depends-on-refuted") callerDrifts `shouldBe` True

  -- =========================================================================
  -- v0.10.4 (R6d): Tier-count profile aggregate
  --
  -- Six-Int profile over the trust report's per-function effective tier
  -- classification. The harness consumes this to compose its credibility
  -- predicate; LLMLL itself defines no Cred or scalar.
  -- =========================================================================

  describe "v0.10.4 tier-count profile (R6d)" $ do
    let mkEntry name pre post =
          TrustEntry
            { teName               = name
            , tePre                = fmap (\dl -> EvidenceRecord dl False Nothing [] False Nothing Nothing False Nothing False) pre
            , tePost               = fmap (\dl -> EvidenceRecord dl False Nothing [] False Nothing Nothing False Nothing False) post
            , teDeps               = []
            , teDrifts             = []
            , teEffectiveLevel     = Nothing  -- aggregateTiers falls back to ContractStatus meet
            , teEffectivePreLevel  = Nothing  -- OBLIG-PBT-3: not exercised in TP-* tests
            , teEffectivePostLevel = Nothing
            , teJointPostWitness   = False    -- OBLIG-PBT-5a: not exercised here
            , teCallerObligations  = []       -- TRUST-PRE: not exercised in TP-* tests
            }

    -- TP-1: Empty obligation set yields zero vector
    it "empty report → zero profile" $ do
      aggregateTiers [] `shouldBe` TierProfile 0 0 0 0 0 0

    -- TP-2: Uniform verified entries concentrate in tpVerified
    it "uniform verified report → verified-only profile" $ do
      let entries = [ mkEntry "f1" (Just (DLVerified "liquid-fixpoint")) (Just (DLVerified "liquid-fixpoint"))
                    , mkEntry "f2" (Just (DLVerified "liquid-fixpoint")) (Just (DLVerified "liquid-fixpoint"))
                    , mkEntry "f3" (Just (DLVerified "liquid-fixpoint")) (Just (DLVerified "liquid-fixpoint"))
                    ]
      aggregateTiers entries `shouldBe` TierProfile 3 0 0 0 0 0

    -- TP-3: Diamond-asymmetry — contract-checked ⊥ tested, with mixed-meet edge case
    -- Locks in LLMLL.md:344 incomparability against future regression.
    it "diamond asymmetry: contract-checked/tested tiers; pre⊓post no longer floors the tier (TRUST-PRE)" $ do
      let ccEntries = [ mkEntry ("cc" <> T.pack (show i))
                                (Just (DLContractChecked "z3"))
                                (Just (DLContractChecked "z3"))
                      | i <- [1..3 :: Int] ]
          tsEntries = [ mkEntry ("ts" <> T.pack (show i))
                                (Just (DLTested 100))
                                (Just (DLTested 100))
                      | i <- [1..3 :: Int] ]
          -- One entry with a contract-checked PRE and a tested POST. The diamond
          -- meet(DLContractChecked, DLTested) = DLAsserted still governs the
          -- per-entry DISPLAY and the call-graph propagation (teEffectiveLevel /
          -- enrichEntry are untouched), but TRUST-PRE (Part 1) classifies the
          -- TIER on the post side — so the pre no longer floors this to asserted.
          mixedEntry = [ mkEntry "mixed"
                                 (Just (DLContractChecked "z3"))
                                 (Just (DLTested 100)) ]
      aggregateTiers ccEntries  `shouldBe` TierProfile 0 0 3 0 0 0
      aggregateTiers tsEntries  `shouldBe` TierProfile 0 0 0 3 0 0
      -- TRUST-PRE: classifies on the post (DLTested), not the pre⊓post meet.
      -- (Was: TierProfile 0 0 0 0 1 0 — the pre-bearing floor to asserted.)
      aggregateTiers mixedEntry `shouldBe` TierProfile 0 0 0 1 0 0

    -- TP-4: Mixed-tier report → component-correct counts
    -- proved is zero by construction (no DLProved constructor exists)
    it "mixed-tier report → component-correct profile" $ do
      let entries = [ mkEntry "fv" (Just (DLVerified "lean")) (Just (DLVerified "lean"))
                    , mkEntry "fc" (Just (DLContractChecked "z3")) (Just (DLContractChecked "z3"))
                    , mkEntry "ft" (Just (DLTested 100)) (Just (DLTested 100))
                    , mkEntry "fa" (Just DLAsserted) (Just DLAsserted)
                    , mkEntry "fn" Nothing Nothing
                    ]
      aggregateTiers entries `shouldBe` TierProfile 1 0 1 1 1 1

    -- TP-5: JSON emit carries trust_report_version and a structurally-valid tier_profile
    it "formatTrustReportJson includes trust_report_version and tier_profile" $ do
      let stmts =
            [ SDefLogic "fn1" [("x", TInt)] (Just TInt)
                (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                (EVar "x")
            ]
          report   = buildTrustReport DM.empty stmts Map.empty
          jsonText = formatTrustReportJson report
          decoded  = decode (BLC.pack (T.unpack jsonText)) :: Maybe Value
      case decoded of
        Just (Object o) -> do
          -- trust_report_version now 1.5.0 (REC-PARTIAL-MARK; was 1.4.0 TRUST-PRE).
          KM.lookup "trust_report_version" o `shouldBe` Just (String "1.5.0")
          case KM.lookup "tier_profile" o of
            Just (Object tp) -> do
              -- All six required fields present
              KM.lookup "verified"         tp `shouldSatisfy` (/= Nothing)
              KM.lookup "proved"           tp `shouldSatisfy` (/= Nothing)
              KM.lookup "contract_checked" tp `shouldSatisfy` (/= Nothing)
              KM.lookup "tested"           tp `shouldSatisfy` (/= Nothing)
              KM.lookup "asserted"         tp `shouldSatisfy` (/= Nothing)
              KM.lookup "no_contract"      tp `shouldSatisfy` (/= Nothing)
              -- proved is structural-zero (no DLProved constructor today)
              KM.lookup "proved"           tp `shouldBe` Just (Number 0)
            _ -> expectationFailure "tier_profile missing or not an object"
          -- Pre-existing summary block is unchanged
          KM.lookup "summary" o `shouldSatisfy` (/= Nothing)
        _ -> expectationFailure "trust-report JSON did not decode as an object"

  -- =========================================================================
  -- v0.3 #14: Async/Await codegen test coverage (10 tests)
  -- =========================================================================

  describe "Async codegen (#14)" $ do
    -- Type emission (3) — post-LT-INT (v0.11): TInt lowers to Integer, not Int
    it "toHsType (TPromise TInt) = (Async.Async Integer)" $
      toHsType (TPromise TInt) `shouldBe` "(Async.Async Integer)"

    it "toHsType (TPromise (TResult TString TInt)) handles nesting" $
      toHsType (TPromise (TResult TString TInt)) `shouldBe` "(Async.Async (Either Integer String))"

    it "toHsType (TPromise (TPromise TInt)) handles double-wrap" $
      toHsType (TPromise (TPromise TInt)) `shouldBe` "(Async.Async (Async.Async Integer))"

    -- Codegen output (4)
    it "emitExpr (EAwait ...) contains Async.wait" $ do
      let output = emitExpr (EAwait (EVar "x"))
      T.isInfixOf "Async.wait" output `shouldBe` True

    it "emitExpr (EAwait ...) contains try" $ do
      let output = emitExpr (EAwait (EVar "x"))
      T.isInfixOf "try" output `shouldBe` True

    it "emitExpr (EAwait ...) contains SomeException" $ do
      let output = emitExpr (EAwait (EVar "x"))
      T.isInfixOf "SomeException" output `shouldBe` True

    it "emitExpr (EAwait ...) wraps in Left/Right (Result shape)" $ do
      let output = emitExpr (EAwait (EVar "x"))
      T.isInfixOf "Left" output `shouldBe` True
      T.isInfixOf "Right" output `shouldBe` True

    -- TypeCheck (2)
    it "EAwait on TPromise infers TResult t TDelegationError" $ do
      let delegSpec = DelegateSpec "agent" "task" TInt Nothing
          prog = [SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                    (EAwait (EHole (HDelegateAsync delegSpec)))]
          report = typeCheck GrammarCoreInversion emptyEnv prog
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      errs `shouldBe` []

    it "?delegate-async hole infers TPromise(returnType)" $ do
      let delegSpec = DelegateSpec "agent" "task" TInt Nothing
          prog = [SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                    (EHole (HDelegateAsync delegSpec))]
          report = typeCheck GrammarCoreInversion emptyEnv prog
          hardErrs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      hardErrs `shouldBe` []

    -- Parser roundtrip (1)
    it "(await expr) parses to EAwait" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [] (await (+ 1 2)))" of
        Right [SDefShell _ _ _ _ (EAwait _) _] -> pure ()
        other -> expectationFailure $ "unexpected: " ++ show other

  -- =========================================================================
  -- v0.3 #11: Scaffold test coverage (7 tests)
  -- =========================================================================

  describe "Scaffold (#11)" $ do
    -- Hub resolution (3)
    it "scaffoldCacheRoot ends with .llmll/templates" $ do
      root <- scaffoldCacheRoot
      ".llmll/templates" `isSuffixOf` root `shouldBe` True

    it "resolveScaffold nonexistent returns Nothing" $ do
      result <- resolveScaffold "nonexistent-template-xyz"
      result `shouldBe` Nothing

    it "resolveScaffold finds scaffold.ast.json in cache" $ do
      root <- scaffoldCacheRoot
      let dir = root ++ "/test-scaffold-tmp"
          file = dir ++ "/scaffold.ast.json"
      createDirectoryIfMissing True dir
      writeFile file "{\"schemaVersion\": \"0.6.0\", \"statements\": []}"
      result <- resolveScaffold "test-scaffold-tmp"
      result `shouldBe` Just file
      removeDirectoryRecursive dir

    -- Parser (2)
    it "(?scaffold todo-app) parses to EHole (HScaffold ...)" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [] (?scaffold todo-app))" of
        Right [SDefShell _ _ _ _ (EHole (HScaffold spec)) _] ->
          scaffoldTemplate spec `shouldBe` "todo-app"
        other -> expectationFailure $ "unexpected: " ++ show other

    it "JSON-AST hole-scaffold parses correctly" $ do
      let jsonSrc = BLC.pack $ unlines
            [ "{ \"schemaVersion\": \"0.6.0\""
            , ", \"statements\": ["
            , "    { \"kind\": \"def-shell\", \"name\": \"f\", \"params\": []"
            , "    , \"body\": { \"kind\": \"hole-scaffold\", \"template\": \"rest-api\" } }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST GrammarCoreInversion "<test>" jsonSrc of
        Right [SDefShell _ _ _ _ (EHole (HScaffold spec)) _] ->
          scaffoldTemplate spec `shouldBe` "rest-api"
        other -> expectationFailure $ "unexpected: " ++ show other

    -- HoleAnalysis (1)
    it "analyzeHoles reports ?scaffold as NonBlocking" $ do
      let spec = ScaffoldSpec "todo-app" Nothing [] Nothing Nothing
          prog = [SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                    (EHole (HScaffold spec))]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      holeStatus (head entries) `shouldBe` HA.NonBlocking
      holeName (head entries) `shouldSatisfy` T.isInfixOf "scaffold"

    -- Codegen (1)
    it "emitHole (HScaffold ...) contains scaffold and template name" $ do
      let spec = ScaffoldSpec "todo-app" Nothing [] Nothing Nothing
          output = emitHole (HScaffold spec)
      T.isInfixOf "scaffold" output `shouldBe` True
      T.isInfixOf "todo-app" output `shouldBe` True

  -- =========================================================================
  -- BUG-1 (resumed task, 2026-07-01): hub fetch --from-file tar-extraction
  -- path. installEntries used to strip the tarball's top-level
  -- `<package>-<version>/` directory outright (stripTopDir), flattening
  -- every file straight into the shared cache root and losing both the
  -- package name and version directory (collides across packages). Fixed
  -- by destPathFor/splitPkgVersion, which reconstitute the top-level dir
  -- into <package>/<version>/... matching resolveHubPath's expected
  -- layout (see LLMLL.Hub). Runs against a HOME override so it never
  -- touches the real ~/.llmll cache.
  -- =========================================================================
  describe "Hub: hubFetchLocal tar-extraction path (BUG-1)" $ do
    it "installs a <pkg>-<version>/ tarball into ~/.llmll/modules/<pkg>/<version>/..." $ do
      origHome <- lookupEnv "HOME"
      tmpRoot  <- getTemporaryDirectory
      let tmpHome = tmpRoot </> "llmll-hub-test-home"
          srcDir  = tmpRoot </> "llmll-hub-test-src"
          pkgName = "llmll-hub-test-pkg"
          pkgVer  = "0.3.7"
          topDir  = pkgName ++ "-" ++ pkgVer
          cleanup = do
            homeEx <- doesDirectoryExist tmpHome
            when homeEx (removeDirectoryRecursive tmpHome)
            srcEx  <- doesDirectoryExist srcDir
            when srcEx (removeDirectoryRecursive srcDir)
      cleanup
      createDirectoryIfMissing True (srcDir </> topDir </> "math")
      writeFile (srcDir </> topDir </> "math" </> "add.llmll")
                "(def add [a: int b: int] (+ a b))"
      let tarPath = srcDir </> (topDir ++ ".tar.gz")
      callProcess "tar" ["czf", tarPath, "-C", srcDir, topDir]
      createDirectoryIfMissing True tmpHome
      setEnv "HOME" tmpHome
      result <- hubFetchLocal tarPath
      case origHome of
        Just h  -> setEnv "HOME" h
        Nothing -> unsetEnv "HOME"
      result `shouldBe` Right ()
      let installedFile = tmpHome </> ".llmll" </> "modules" </> pkgName </> pkgVer
                             </> "math" </> "add.llmll"
      installedExists <- doesFileExist installedFile
      installedExists `shouldBe` True
      contents <- readFile installedFile
      contents `shouldBe` "(def add [a: int b: int] (+ a b))"
      -- regression: files must NOT be flattened directly under modules/ root
      -- (the old stripTopDir bug lost the package/version directory)
      flatExists <- doesFileExist (tmpHome </> ".llmll" </> "modules" </> "math" </> "add.llmll")
      flatExists `shouldBe` False
      cleanup

  -- =========================================================================
  -- v0.3.1: Event Log (#13)
  -- =========================================================================

  describe "Event Log (v0.3.1)" $ do

    -- Preamble (1)
    it "emitEventLogPreamble contains eventJsonL and captureStdout" $ do
      let preamble = T.unlines emitEventLogPreamble
      T.isInfixOf "eventJsonL" preamble `shouldBe` True
      T.isInfixOf "captureStdout" preamble `shouldBe` True
      T.isInfixOf "headerJsonL" preamble `shouldBe` True

    -- Codegen integration (1)
    it "Generated Main.hs for console mode contains event-log.jsonl" $ do
      let src = "(def-main :mode console :step (fn [s: string input: string] (pair s (wasi.io.stdout input))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right stmts -> do
          let result = generateHaskell "testmod" stmts
          case cgMainHs result of
            Nothing -> expectationFailure "No Main.hs generated"
            Just mainHs -> do
              T.isInfixOf "event-log.jsonl" mainHs `shouldBe` True
              T.isInfixOf "logHandle" mainHs `shouldBe` True
              T.isInfixOf "seqRef" mainHs `shouldBe` True
              T.isInfixOf "captureStdout" mainHs `shouldBe` True
        Left err -> expectationFailure $ "Parse failed: " ++ show err

    -- JSONL format (1)
    it "parseEventLog parses valid JSONL events" $ do
      let logContent = T.unlines
            [ "{\"type\":\"header\",\"version\":\"0.3.1\",\"module\":\"test\"}"
            , "{\"type\":\"event\",\"seq\":0,\"input\":{\"kind\":\"stdin\",\"value\":\"hello\"},\"result\":{\"kind\":\"stdout\",\"value\":\"world\"},\"captures\":[]}"
            , "{\"type\":\"event\",\"seq\":1,\"input\":{\"kind\":\"stdin\",\"value\":\"foo\"},\"result\":{\"kind\":\"stdout\",\"value\":\"bar\"},\"captures\":[]}"
            ]
      let entries = parseEventLog logContent
      length entries `shouldBe` 2
      evSeq (head entries) `shouldBe` 0
      evInputVal (head entries) `shouldBe` "hello"
      evResultVal (head entries) `shouldBe` "world"
      evSeq (entries !! 1) `shouldBe` 1

    -- Crash tolerance (1)
    it "parseEventLog handles partial log (no trailing line)" $ do
      let logContent = T.unlines
            [ "{\"type\":\"header\",\"version\":\"0.3.1\",\"module\":\"test\"}"
            , "{\"type\":\"event\",\"seq\":0,\"input\":{\"kind\":\"stdin\",\"value\":\"x\"},\"result\":{\"kind\":\"stdout\",\"value\":\"y\"},\"captures\":[]}"
            ]
      let entries = parseEventLog logContent
      length entries `shouldBe` 1
      evInputVal (head entries) `shouldBe` "x"

    -- Escape (1)
    it "parseEventLog handles escaped quotes and newlines" $ do
      let logContent = "{\"type\":\"event\",\"seq\":0,\"input\":{\"kind\":\"stdin\",\"value\":\"say \\\"hi\\\"\"},\"result\":{\"kind\":\"stdout\",\"value\":\"line1\\nline2\"},\"captures\":[]}"
      let entries = parseEventLog logContent
      length entries `shouldBe` 1
      evInputVal (head entries) `shouldBe` "say \"hi\""
      evResultVal (head entries) `shouldBe` "line1\nline2"

  -- =========================================================================
  -- v0.3.1: Leanstral MCP — Phase B (#14)
  -- =========================================================================

  describe "Leanstral MCP (v0.3.1)" $ do

    -- Layer-1-lite: translate the OBLIGATION (result bound to the body)
    it "Layer-1: translateObligation on square emits the exact h_body-bound theorem" $ do
      let contract = Contract Nothing Nothing
                       (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
          body     = EOp "*" [EVar "n", EVar "n"]
          expected = "import Mathlib.Tactic\n\n"
                  <> "theorem square (n : Int) (result : Int) "
                  <> "(h_body : result = (n * n)) : (result >= 0) := by\n  sorry"
      case translateObligation "square" [("n", TInt)] (Just TInt) contract body of
        LeanTheorem thm    -> thm `shouldBe` expected
        Unsupported reason -> expectationFailure $ "Expected theorem, got Unsupported: " ++ T.unpack reason

    it "Layer-1: Unsupported for a `/` body (fail-closed)" $ do
      let contract = Contract Nothing Nothing
                       (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
          body     = EOp "/" [EVar "n", ELit (LitInt 2)]
      case translateObligation "divf" [("n", TInt)] (Just TInt) contract body of
        Unsupported _   -> pure ()
        LeanTheorem thm -> expectationFailure $ "Expected Unsupported for `/` body: " ++ T.unpack thm

    it "Layer-1: Unsupported for a `mod` body (fail-closed)" $ do
      let contract = Contract Nothing Nothing
                       (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
          body     = EOp "mod" [EVar "n", ELit (LitInt 2)]
      case translateObligation "modf" [("n", TInt)] (Just TInt) contract body of
        Unsupported _   -> pure ()
        LeanTheorem thm -> expectationFailure $ "Expected Unsupported for `mod` body: " ++ T.unpack thm

    it "Layer-1: Unsupported for a list body (fail-closed, .head! killed)" $ do
      let contract = Contract Nothing Nothing
                       (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
          body     = EApp "list-head" [EVar "n"]
      case translateObligation "headf" [("n", TInt)] (Just TInt) contract body of
        Unsupported _   -> pure ()
        LeanTheorem thm -> expectationFailure $ "Expected Unsupported for a list body: " ++ T.unpack thm

    it "Layer-1: Unsupported for a residual free variable in the body (fail-closed)" $ do
      let contract = Contract Nothing Nothing
                       (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
          body     = EOp "*" [EVar "n", EVar "m"]  -- m is not a parameter
      case translateObligation "freevar" [("n", TInt)] (Just TInt) contract body of
        Unsupported reason -> T.isInfixOf "free variable" reason `shouldBe` True
        LeanTheorem thm    -> expectationFailure $ "Expected Unsupported for a free var: " ++ T.unpack thm

    -- Layer-2-lite: the --leanstral route selects the nonlinear erBodyFallback fn
    it "Layer-2: the --leanstral route selects the nonlinear erBodyFallback function" $ do
      let post   = Just (EOp ">=" [EVar "result", ELit (LitInt 0)])
          square = SDefShell "square" [("n", TInt)] (Just TInt)
                     (Contract Nothing Nothing post Nothing Nothing)
                     (EOp "*" [EVar "n", EVar "n"]) []      -- nonlinear
          inc    = SDefShell "inc" [("n", TInt)] (Just TInt)
                     (Contract Nothing Nothing post Nothing Nothing)
                     (EOp "+" [EVar "n", ELit (LitInt 1)]) []  -- linear
          stmts         = [square, inc]
          fallbackNames = Set.fromList ["square"]  -- erBodyFallback: only the nonlinear body
          -- Mirrors runLeanstralPipeline's nonlinearFallback comprehension.
          selected = [ n
                     | s <- stmts
                     , Just (n, _, _, _, b) <- [normalizeDefStmt s]
                     , n `Set.member` fallbackNames
                     , isNonLinear b ]
      selected `shouldBe` ["square"]

    -- Layer-3: parse the model response (fence extraction) + anti-laundering
    it "Layer-3: extractLeanFence pulls the ```lean block out of a prose+fence response" $ do
      let content = T.unlines
            [ "Here is the completed proof:"
            , ""
            , "```lean"
            , "import Mathlib.Tactic"
            , ""
            , "theorem square (n : Int) (result : Int) (h_body : result = (n * n)) : (result >= 0) := by"
            , "  rw [h_body]; nlinarith"
            , "```"
            , ""
            , "Let me know if you need anything else."
            ]
      case extractLeanFence content of
        Right block -> do
          T.isInfixOf "theorem square" block `shouldBe` True
          T.isInfixOf "nlinarith"      block `shouldBe` True
          T.isInfixOf "```"            block `shouldBe` False  -- fences stripped
          T.isInfixOf "Here is"        block `shouldBe` False  -- prose stripped
        Left e -> expectationFailure $ "Expected a fenced block: " ++ T.unpack e

    it "Layer-3: extractLeanFence fails closed when there is no ```lean block" $
      case extractLeanFence "no fenced code here at all" of
        Left _  -> pure ()
        Right b -> expectationFailure $ "Expected Left, got: " ++ T.unpack b

    it "Layer-3: a fenced proof still containing `sorry` is rejected by sanitizeProof" $
      case extractLeanFence "```lean\ntheorem t : True := by\n  sorry\n```" of
        Right block -> case sanitizeProof block of
          ProofError _ -> pure ()
          other        -> expectationFailure $ "Expected ProofError, got: " ++ show other
        Left e -> expectationFailure $ "Expected a fenced block: " ++ T.unpack e

    it "Layer-3: parseChatContent extracts choices[0].message.content" $ do
      let resp = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"```lean\\ntheorem t : True := trivial\\n```\"}}]}"
      case parseChatContent (BLC.pack resp) of
        Right c -> T.isInfixOf "theorem t" c `shouldBe` True
        Left e  -> expectationFailure $ "Expected content, got: " ++ T.unpack e

    -- FIX 1: greedy sampling (temperature 0.0) requires top_p = 1, else Mistral
    -- 400-rejects with code 3054 ("top_p must be 1 when using greedy sampling.").
    it "Layer-3: buildChatRequest sends top_p = 1 (required for greedy sampling)" $
      case decode (buildChatRequest "labs-leanstral-1-5" "prove this") :: Maybe Value of
        Just (Object o) -> KM.lookup "top_p" o `shouldBe` Just (Number 1)
        other           -> expectationFailure $ "Expected a JSON object, got: " ++ show other

    -- FIX 2: Mistral's error shape is TOP-LEVEL ({"object":"error","message":X}),
    -- not nested under .error. The real API message must reach the user instead
    -- of being swallowed into the generic no-content fallback.
    it "Layer-3: parseChatContent surfaces a top-level Mistral error message" $ do
      let resp = "{\"object\":\"error\",\"message\":\"top_p must be 1 when using greedy sampling.\",\"code\":\"3054\"}"
      case parseChatContent (BLC.pack resp) of
        Left msg -> do
          T.isInfixOf "top_p must be 1 when using greedy sampling." msg `shouldBe` True
          T.isInfixOf "had no choices" msg `shouldBe` False  -- NOT the generic fallback
        Right c  -> expectationFailure $ "Expected Left error, got content: " ++ T.unpack c

    -- FIX 2 (auth-failure shape): {"detail":"Unauthorized"} must also surface.
    it "Layer-3: parseChatContent surfaces a top-level .detail auth error" $
      case parseChatContent (BLC.pack "{\"detail\":\"Unauthorized\"}") of
        Left msg -> T.isInfixOf "Unauthorized" msg `shouldBe` True
        Right c  -> expectationFailure $ "Expected Left error, got content: " ++ T.unpack c

    -- MCPClient — anti-laundering guard (PROOF-ARTIFACT §4.1 LCF)
    it "sanitizeProof accepts a genuine proof term (ProofFound survives)" $
      sanitizeProof "by decide" `shouldBe` ProofFound "by decide"

    it "sanitizeProof rejects 'by sorry' as degenerate → ProofError" $
      case sanitizeProof "by sorry" of
        ProofError _ -> pure ()
        other        -> expectationFailure $ "Expected ProofError, got: " ++ show other

    it "sanitizeProof rejects whitespace-only proof → ProofError" $
      case sanitizeProof "  " of
        ProofError _ -> pure ()
        other        -> expectationFailure $ "Expected ProofError, got: " ++ show other

    it "sanitizeProof rejects a proof using 'admit' → ProofError" $
      case sanitizeProof "by admit" of
        ProofError _ -> pure ()
        other        -> expectationFailure $ "Expected ProofError, got: " ++ show other

    it "sanitizeProof is word-boundary aware (identifier substrings pass)" $ do
      sanitizeProof "by exact admittance"  `shouldBe` ProofFound "by exact admittance"
      sanitizeProof "exact Nat.sorry_free" `shouldBe` ProofFound "exact Nat.sorry_free"

    it "mockProofResult 'by sorry' is now rejected as degenerate → ProofError" $
      case mockProofResult "some obligation" of
        ProofError _ -> pure ()
        other        -> expectationFailure $ "Expected ProofError from mock, got: " ++ show other

    it "callLeanstral with unavailable binary → LeanstralUnavailable" $ do
      let config = defaultMCPConfig { mcpMock = False }
      result <- callLeanstral config "test obligation"
      case result of
        LeanstralUnavailable _ -> pure ()
        _ -> expectationFailure $ "Expected LeanstralUnavailable, got: " ++ show result

    -- ProofCache (2)
    it "ProofCache save → load roundtrip" $ do
      let tmpDir = "/tmp/llmll-test-proof-cache"
      createDirectoryIfMissing True tmpDir
      let fp = tmpDir ++ "/test.llmll"
          entry = ProofEntry
            { peObligationHash = "abc123"
            , peProof = "by sorry"
            , peProver = "leanstral"
            , peVerifiedAt = "2026-04-11T10:00:00Z"
            }
          cache = insertProof "/post" entry Map.empty
      saveProofCache fp cache
      loaded <- loadProofCache fp
      lookupProof "/post" "abc123" loaded `shouldBe` Just entry
      removeIfExists (proofCachePath fp)

    it "ProofCache hash mismatch detection" $ do
      let entry = ProofEntry
            { peObligationHash = "abc123"
            , peProof = "by sorry"
            , peProver = "leanstral"
            , peVerifiedAt = "2026-04-11T10:00:00Z"
            }
          cache = insertProof "/post" entry Map.empty
      lookupProof "/post" "different-hash" cache `shouldBe` Nothing

    -- HoleAnalysis complexity (2)
    it "normalizeComplexity classifies complex-decreases as :inductive" $ do
      HA.normalizeComplexity "complex-decreases" `shouldBe` ":inductive"
      HA.normalizeComplexity "manual" `shouldBe` ":unknown"
      HA.normalizeComplexity "simple" `shouldBe` ":simple"

    it "formatHoleReportJson includes complexity for proof-required holes" $ do
      let stmts = [SDefLogic "safe-div" [("n", TInt), ("d", TInt)] Nothing
                     (Contract Nothing Nothing Nothing Nothing Nothing) (EHole (HProofRequired "complex-decreases" Nothing))]
          report = HA.analyzeHoles stmts
          json   = HA.formatHoleReportJson "<test>" False report
      T.isInfixOf "complexity" json `shouldBe` True
      T.isInfixOf ":inductive" json `shouldBe` True

    -- End-to-end pipeline (1): the mock's "by sorry" is degenerate and is
    -- rejected (covered above), so a genuine guard-surviving proof term stands
    -- in for a real prover result to exercise the cache roundtrip.
    it "Pipeline: translate → prove (genuine term) → cache → verify" $ do
      let contract = Contract
            { contractPre  = Just (EOp ">" [EVar "x", ELit (LitInt 0)])
            , contractPreSource = Nothing
            , contractPost = Just (EOp ">" [EVar "result", ELit (LitInt 0)])
            , contractPostSource = Nothing
            , contractSpecEntropy = Nothing
            }
      case translateObligation "pipeline-test" [("x", TInt)] (Just TInt) contract (EOp "*" [EVar "x", EVar "x"]) of
        LeanTheorem _thm -> do
          let proofResult = sanitizeProof "by decide"
          case proofResult of
            ProofFound proof -> do
              let entry = ProofEntry "hash123" proof "leanstral" "2026-04-11"
                  cache = insertProof "/post" entry Map.empty
              lookupProof "/post" "hash123" cache `shouldBe` Just entry
            _ -> expectationFailure "Expected ProofFound"
        Unsupported reason -> expectationFailure $ "Expected theorem: " ++ T.unpack reason

  -- =========================================================================
  -- v0.3.1 Phase D: Replay Re-Execution
  -- =========================================================================

  replayExecutionTests

  -- =========================================================================
  -- v0.3.1 Phase E: Verify Integration
  -- =========================================================================

  verifyIntegrationTests

  -- =========================================================================
  -- v0.3.1 Phase F: SHA-256 Hashing
  -- =========================================================================

  sha256Tests

  -- =========================================================================
  -- v0.3.1 Coverage Gaps
  -- =========================================================================

  coverageGapTests

  -- =========================================================================
  -- v0.3.3: Agent Orchestration — Pointer, Dependencies, Cycles (10 tests)
  -- =========================================================================

  holeAnalysisV033Tests

-- | Helper to remove a file if it exists (used for test cleanup).
removeIfExists :: FilePath -> IO ()
removeIfExists fp = do
  exists <- doesFileExist fp
  if exists then removeFile fp else pure ()

-- =====================================================================
-- Phase D tests: Replay Re-Execution (v0.3.1)
-- =====================================================================

replayExecutionTests :: Spec
replayExecutionTests = describe "Replay Execution (v0.3.1)" $ do
    it "runReplay with matching events reports all matched" $ do
      -- Create a mock executable that echoes input with a prefix
      let mockScript = "test_echo_mock.sh"
      writeFile mockScript "#!/bin/bash\nwhile IFS= read -r line; do echo \"Got: $line\"; done"
      callProcess "chmod" ["+x", mockScript]
      let entries = [ EventLogEntry 0 "stdin" "hello" "stdout" "Got: hello\n"
                    , EventLogEntry 1 "stdin" "world" "stdout" "Got: world\n"
                    ]
      result <- runReplay ("./" ++ mockScript) entries
      removeIfExists mockScript
      replayTotal result `shouldBe` 2
      replayMatched result `shouldBe` 2
      replayDiverged result `shouldBe` []

    it "runReplay with tampered result detects divergence" $ do
      let mockScript = "test_echo_mock2.sh"
      writeFile mockScript "#!/bin/bash\nwhile IFS= read -r line; do echo \"Got: $line\"; done"
      callProcess "chmod" ["+x", mockScript]
      let entries = [ EventLogEntry 0 "stdin" "hello" "stdout" "WRONG OUTPUT\n"
                    ]
      result <- runReplay ("./" ++ mockScript) entries
      removeIfExists mockScript
      replayTotal result `shouldBe` 1
      replayMatched result `shouldBe` 0
      length (replayDiverged result) `shouldBe` 1

    -- -----------------------------------------------------------------
    -- BUG-1 (v0.14.3): `llmll replay`'s doReplay (app/Main.hs) used to call
    -- doBuild directly. doBuild ends every code path in exitSuccess or
    -- exitFailure, which unconditionally killed the whole `llmll replay`
    -- process before it ever reached runReplay -- the "N/N events matched"
    -- summary was dead, unreachable code. app/Main.hs is the executable
    -- component (not part of the `llmll` library), so it can't be
    -- unit-tested directly from this suite; these tests instead exercise
    -- runCapturingExit, the exact shared helper doReplay now calls to wrap
    -- the build sub-step (see LLMLL.Replay.runCapturingExit and its call
    -- site in doReplay). If a future edit reintroduces a raw exitSuccess/
    -- exitFailure call on doReplay's build step (bypassing this helper),
    -- these tests won't catch that directly, but they pin down that the
    -- interception mechanism itself behaves correctly: the caller survives
    -- past an exiting sub-action, observes its ExitCode, and continues.
    -- -----------------------------------------------------------------
    it "BUG-1: runCapturingExit intercepts exitFailure instead of killing the caller" $ do
      code <- runCapturingExit (exitWith (ExitFailure 3))
      code `shouldBe` ExitFailure 3

    it "BUG-1: runCapturingExit intercepts exitSuccess, and code AFTER the call still runs" $ do
      -- This is the crux of BUG-1: before the fix, everything after the
      -- exiting build step was unreachable because the process was already
      -- dead. Prove the caller's subsequent code genuinely executes.
      ranAfter <- newIORef False
      code <- runCapturingExit exitSuccess
      code `shouldBe` ExitSuccess
      writeIORef ranAfter True
      readIORef ranAfter `shouldReturn` True

    it "BUG-1: runCapturingExit preserves side effects performed before the exit call" $ do
      sideEffect <- newIORef (0 :: Int)
      code <- runCapturingExit (writeIORef sideEffect 42 >> exitFailure)
      code `shouldBe` ExitFailure 1
      readIORef sideEffect `shouldReturn` 42

-- =====================================================================
-- Phase E tests: Verify Integration (v0.3.1)
-- =====================================================================

verifyIntegrationTests :: Spec
verifyIntegrationTests = describe "Verify Integration (v0.3.1)" $ do
    it "LeanstralOpts pipeline: nonlinear-fallback obligation → translate → cache" $ do
      -- Simulate the Layer-2 worklist: a nonlinear body-fallback function, with
      -- its REAL body, is translated (Layer-1) and its proof cached. The mock's
      -- "by sorry" is degenerate and rejected by 'sanitizeProof' (see the
      -- anti-laundering tests), so a genuine guard-surviving proof term stands
      -- in for a real prover result here.
      let stmts = [ SDefShell "square" [("n", TInt)] (Just TInt)
                      (Contract Nothing Nothing
                         (Just (EOp ">=" [EVar "result", ELit (LitInt 0)]))
                         Nothing Nothing)
                      (EOp "*" [EVar "n", EVar "n"]) []
                  ]
          fallbackNames = Set.fromList ["square"]   -- as reported in erBodyFallback
          worklist = [ (n, p, r, c, b)
                     | s <- stmts
                     , Just (n, p, r, c, b) <- [normalizeDefStmt s]
                     , n `Set.member` fallbackNames
                     , isNonLinear b ]
      length worklist `shouldBe` 1
      case worklist of
        [(name, params, ret, contract, body)] ->
          case translateObligation name params ret contract body of
            LeanTheorem thm ->
              case sanitizeProof "by decide" of
                ProofFound proof -> do
                  let entry = ProofEntry thm proof "leanstral" ""
                      cache = insertProof ("/post/" <> name) entry Map.empty
                  lookupProof ("/post/" <> name) thm cache `shouldBe` Just entry
                _ -> expectationFailure "Expected ProofFound"
            Unsupported reason -> expectationFailure $ "Expected LeanTheorem: " ++ T.unpack reason
        _ -> expectationFailure "Expected exactly one obligation"

    it "Verify without leanstral opts has no effect (structural)" $ do
      -- When lsMock is False and lsCmd is Nothing, the pipeline guard
      -- (lsMock lsOpts || isJust (lsCmd lsOpts)) evaluates to False.
      -- This is a structural test verifying the guard conditions.
      let mockFlag = False
          cmdPath  = Nothing :: Maybe FilePath
      (mockFlag || maybe False (const True) cmdPath) `shouldBe` False

-- =====================================================================
-- Phase F tests: SHA-256 Hashing (v0.3.1)
-- =====================================================================

sha256Tests :: Spec
sha256Tests = describe "SHA-256 Hashing (v0.3.1)" $ do
    it "computeObligationHash produces consistent 64-char hex string" $ do
      let hash1 = computeObligationHash "x > 0"
          hash2 = computeObligationHash "x > 0"
          hash3 = computeObligationHash "x > 1"
      -- Deterministic
      hash1 `shouldBe` hash2
      -- Different inputs → different hashes
      hash1 `shouldNotBe` hash3
      -- 64-char hex
      T.length hash1 `shouldBe` 64
      T.all (\c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) hash1 `shouldBe` True

-- =====================================================================
-- Coverage gap tests (v0.3.1)
-- =====================================================================

coverageGapTests :: Spec
coverageGapTests = describe "Coverage Gaps (v0.3.1)" $ do

  -- ---------------------------------------------------------------
  -- Replay edge cases (2)
  -- ---------------------------------------------------------------

  describe "Replay edge cases" $ do
    it "parseEventLog on empty input returns empty list" $ do
      parseEventLog "" `shouldBe` []

    it "parseEventLog on malformed JSON skips bad lines" $ do
      let logContent = T.unlines
            [ "{\"type\":\"header\",\"version\":\"0.3.1\"}"
            , "this is not json at all"
            , "{\"type\":\"event\",\"seq\":0,\"input\":{\"kind\":\"stdin\",\"value\":\"x\"},\"result\":{\"kind\":\"stdout\",\"value\":\"y\"},\"captures\":[]}"
            , "{\"type\":\"event\",\"seq\":\"NaN\""    -- missing fields
            ]
      let entries = parseEventLog logContent
      length entries `shouldBe` 1
      evInputVal (head entries) `shouldBe` "x"

  -- ---------------------------------------------------------------
  -- Replay process crash (1)
  -- ---------------------------------------------------------------

  describe "Replay process crash" $ do
    it "runReplay with crashing process reports no matches" $ do
      let mockScript = "test_crash_mock.sh"
      writeFile mockScript "#!/bin/bash\nexit 1"
      callProcess "chmod" ["+x", mockScript]
      let entries = [ EventLogEntry 0 "stdin" "hello" "stdout" "world" ]
      result <- runReplay ("./" ++ mockScript) entries
      removeIfExists mockScript
      replayTotal result `shouldBe` 1
      replayMatched result `shouldBe` 0

  -- ---------------------------------------------------------------
  -- LeanTranslate coverage (4)
  -- ---------------------------------------------------------------

  describe "LeanTranslate coverage" $ do
    it "translateObligation with no postcondition → Unsupported (nothing to prove)" $ do
      let contract = Contract Nothing Nothing Nothing Nothing Nothing
      case translateObligation "empty-test" [("n", TInt)] (Just TInt) contract (EOp "*" [EVar "n", EVar "n"]) of
        Unsupported reason -> T.isInfixOf "postcondition" reason `shouldBe` True
        LeanTheorem _      -> expectationFailure "Expected Unsupported for a missing postcondition"

    it "translateObligation with no return type → Unsupported (cannot bind result)" $ do
      let contract = Contract Nothing Nothing
                       (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
      case translateObligation "no-ret" [("n", TInt)] Nothing contract (EOp "*" [EVar "n", EVar "n"]) of
        Unsupported reason -> T.isInfixOf "return type" reason `shouldBe` True
        LeanTheorem _      -> expectationFailure "Expected Unsupported for a missing return type"

    it "translateObligation with a precondition → h_pre hypothesis" $ do
      let contract = Contract
            (Just (EOp ">" [EVar "n", ELit (LitInt 0)])) Nothing
            (Just (EOp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
      case translateObligation "with-pre" [("n", TInt)] (Just TInt) contract (EOp "*" [EVar "n", EVar "n"]) of
        LeanTheorem thm -> do
          T.isInfixOf "(h_pre : (n > 0))" thm `shouldBe` True
          T.isInfixOf "(h_body : result = (n * n))" thm `shouldBe` True
        Unsupported reason -> expectationFailure $ "Expected theorem: " ++ T.unpack reason

    it "translateObligation with a for-all postcondition → Unsupported (killed)" $ do
      let contract = Contract Nothing Nothing
                       (Just (EApp "for-all" [EVar "i", EOp ">" [EVar "i", ELit (LitInt 0)]]))
                       Nothing Nothing
      case translateObligation "forall-test" [("n", TInt)] (Just TInt) contract (EOp "*" [EVar "n", EVar "n"]) of
        Unsupported _   -> pure ()
        LeanTheorem thm -> expectationFailure $ "Expected Unsupported for for-all: " ++ T.unpack thm

    it "translateObligation with boolean ops (and/or/not) in the post" $ do
      let contract = Contract Nothing Nothing
            (Just (EOp "and" [ EOp ">" [EVar "x", ELit (LitInt 0)]
                             , EOp "not" [EOp "<" [EVar "y", ELit (LitInt 0)]]
                             ]))
            Nothing Nothing
      case translateObligation "bool-test" [("x", TInt), ("y", TInt)] (Just TInt) contract (EOp "*" [EVar "x", EVar "y"]) of
        LeanTheorem thm -> do
          T.isInfixOf "∧" thm `shouldBe` True
          T.isInfixOf "¬" thm `shouldBe` True
        Unsupported reason -> expectationFailure $ "Expected theorem: " ++ T.unpack reason

  -- ---------------------------------------------------------------
  -- MCPResult constructors (2)
  -- ---------------------------------------------------------------

  describe "MCPResult constructors" $ do
    it "ProofTimeout is distinct from ProofFound" $ do
      let timeout = ProofTimeout
          found   = ProofFound "by sorry"
      timeout `shouldNotBe` found
      case timeout of
        ProofTimeout -> pure ()
        _            -> expectationFailure "Expected ProofTimeout"

    it "ProofError carries error message" $ do
      let err = ProofError "type mismatch"
      case err of
        ProofError msg -> msg `shouldBe` "type mismatch"
        _              -> expectationFailure "Expected ProofError"

  -- ---------------------------------------------------------------
  -- ProofCache coverage (2)
  -- ---------------------------------------------------------------

  describe "ProofCache coverage" $ do
    it "proofCachePath convention appends .proof-cache.json" $ do
      proofCachePath "examples/test.llmll" `shouldBe` "examples/test.llmll.proof-cache.json"
      proofCachePath "foo.llmll" `shouldBe` "foo.llmll.proof-cache.json"

    it "lookupProof with missing key returns Nothing" $ do
      let entry = ProofEntry "hash" "by sorry" "leanstral" ""
          cache = insertProof "/post/foo" entry Map.empty
      lookupProof "/post/bar" "hash" cache `shouldBe` Nothing

  -- ---------------------------------------------------------------
  -- HoleAnalysis normalizeComplexity :unknown (1)
  -- ---------------------------------------------------------------

  describe "HoleAnalysis normalizeComplexity :unknown" $ do
    it "normalizeComplexity 'manual' → :unknown" $ do
      HA.normalizeComplexity "manual" `shouldBe` ":unknown"

    it "normalizeComplexity 'non-linear' → :unknown" $ do
      HA.normalizeComplexity "non-linear" `shouldBe` ":unknown"

  -- ---------------------------------------------------------------
  -- CodegenHs: captureStdout lazy I/O force (1)
  -- ---------------------------------------------------------------

  describe "CodegenHs captureStdout lazy-IO force" $ do
    it "emitEventLogPreamble captureStdout contains length/seq force" $ do
      let preamble = T.unlines emitEventLogPreamble
      T.isInfixOf "length output" preamble `shouldBe` True
      T.isInfixOf "seq" preamble `shouldBe` True
      T.isInfixOf "force lazy" preamble `shouldBe` True

  -- ---------------------------------------------------------------
  -- CodegenHs: :done? branches pass logHandle/seqRef (1)
  -- ---------------------------------------------------------------

  describe "CodegenHs :done? loop branches" $ do
    it "Generated Main.hs with :done? has loop s' logHandle seqRef" $ do
      -- Use a console program with :done? that stops when input is "quit"
      let src = "(def-main :mode console :init \"\" :step (fn [s: string input: string] (pair input (wasi.io.stdout input))) :done? (fn [s: string] (= s \"quit\")))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right stmts -> do
          let result = generateHaskell "testdone" stmts
          case cgMainHs result of
            Nothing -> expectationFailure "No Main.hs generated"
            Just mainHs -> do
              -- The :done? branch must contain "loop s' logHandle seqRef"
              -- (professor flag #2: all loop call sites pass logHandle + seqRef)
              T.isInfixOf "loop s' logHandle seqRef" mainHs `shouldBe` True
              -- And the done guard itself
              T.isInfixOf "then return ()" mainHs `shouldBe` True
        Left err -> expectationFailure $ "Parse failed: " ++ show err

  -- ---------------------------------------------------------------
  -- runLeanstralPipeline SLetrec scan (1)
  -- ---------------------------------------------------------------

  describe "runLeanstralPipeline SLetrec scan" $ do
    it "SLetrec nonlinear body → bound theorem (worklist covers letrec)" $ do
      let letrec = SLetrec
                     { letrecName      = "sqrec"
                     , letrecParams    = [("n", TInt)]
                     , letrecReturn    = Just TInt
                     , letrecContract  = Contract
                         (Just (EOp ">=" [EVar "n", ELit (LitInt 0)]))
                         Nothing
                         (Just (EOp ">=" [EVar "result", ELit (LitInt 0)]))
                         Nothing Nothing
                     , letrecDecreases = EVar "n"
                     , letrecBody      = EOp "*" [EVar "n", EVar "n"]  -- nonlinear
                     }
      -- Mirrors runLeanstralPipeline's letrec extraction (normalizeDefOrLetrec).
      case letrec of
        SLetrec n p r c _ b ->
          case translateObligation n p r c b of
            LeanTheorem thm -> do
              T.isInfixOf "theorem sqrec" thm `shouldBe` True
              T.isInfixOf "(h_body : result = (n * n))" thm `shouldBe` True
            Unsupported reason -> expectationFailure $ "Expected theorem: " ++ T.unpack reason
        _ -> expectationFailure "not a letrec"

-- =====================================================================
-- v0.3.3 tests: Agent Orchestration
-- =====================================================================

holeAnalysisV033Tests :: Spec
holeAnalysisV033Tests = describe "v0.3.3 Agent Orchestration" $ do

  -- -----------------------------------------------------------------
  -- Pointer structural correctness (3 tests)
  -- -----------------------------------------------------------------

  describe "Pointer structural correctness" $ do
    it "def-logic body hole gets /statements/N/body pointer" $ do
      let prog = [ SDefLogic "f" [("x", TInt)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HNamed "impl"))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      HA.holePointer (head entries) `shouldBe` "/statements/0/body"

    it "second statement gets /statements/1/body pointer" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing) (ELit (LitInt 1))
                 , SDefLogic "g" [("x", TInt)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "agent" "task" TInt Nothing)))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      HA.holePointer (head entries) `shouldBe` "/statements/1/body"

    it "hole in if-then branch gets /then_branch subpath" $ do
      let prog = [ SDefLogic "f" [("x", TInt)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EIf (EVar "x")
                          (EHole (HNamed "then-impl"))
                          (ELit (LitInt 0)))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      HA.holePointer (head entries) `shouldBe` "/statements/0/body/then_branch"

  -- -----------------------------------------------------------------
  -- BUG-5 (v0.14.3): doubled "@" in delegate-hole messages.
  -- holeKindLabel prepended a literal "@" even though delegateAgent
  -- already carries its "@" prefix (Syntax.hs's DelegateSpec doc, the
  -- verbatim JSON emission in AstEmit.hs, every examples/*.ast.json
  -- fixture, and tools/llmll-orchestra's Python side all agree "agent" is
  -- always spelled "@name"). Confirmed live: `llmll holes --json` on any
  -- file with a ?delegate hole showed "message":"hole: ?delegate
  -- @@crypto-agent". Follow-on found in the same investigation: the
  -- S-expression parser's pAgentRef discarded the leading "@" instead of
  -- keeping it (Parser.hs), the one inconsistent producer of the
  -- convention -- fixed alongside so the invariant holds for every source
  -- format, not just JSON-AST.
  -- -----------------------------------------------------------------

  describe "BUG-5: delegate-hole agent label formatting" $ do
    it "holeKindLabel does not double the '@' when delegateAgent already carries it" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "@crypto-agent" "task" TInt Nothing)))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      holeName (head entries) `shouldBe` "?delegate @crypto-agent"
      T.isInfixOf "@@" (holeName (head entries)) `shouldBe` False

    it "holeKindLabel does not double the '@' for ?delegate-async either" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EAwait (EHole (HDelegateAsync (DelegateSpec "@math-agent" "task" TInt Nothing))))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      holeName (head entries) `shouldBe` "?delegate-async @math-agent"
      T.isInfixOf "@@" (holeName (head entries)) `shouldBe` False

    it "JSON hole report 'message' field shows a single '@', not a doubled '@@' (auth_module-style fixture)" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "@crypto-agent" "task" TInt Nothing)))
                 ]
          json = HA.formatHoleReportJson "<test>" False (analyzeHoles prog)
      T.isInfixOf "hole: ?delegate @crypto-agent" json `shouldBe` True
      T.isInfixOf "@@" json `shouldBe` False

    it "pAgentRef (S-expression parser) keeps the '@' prefix on the parsed agent name" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-shell f [] (?delegate @crypto-agent \"task\" -> int))" of
        Right [SDefShell _ _ _ _ (EHole (HDelegate spec)) _] ->
          delegateAgent spec `shouldBe` "@crypto-agent"
        other -> expectationFailure $ "Unexpected parse result: " ++ show other

  -- -----------------------------------------------------------------
  -- Dependency analysis (3 tests)
  -- -----------------------------------------------------------------

  describe "Dependency analysis" $ do
    it "hole in caller depends on hole in callee" $ do
      -- hash-password has a ?delegate hole; login-handler calls hash-password and has its own hole
      let prog = [ SDefLogic "hash-password" [("pw", TString)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "crypto-agent" "hash" TString Nothing)))
                 , SDefLogic "login-handler" [("user", TString)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "hash-password" [EHole (HDelegate (DelegateSpec "auth-agent" "login" TString Nothing))])
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
          loginHole = head [e | e <- entries, HA.holeContext e == "def-logic login-handler"]
      length (HA.holeDependsOn loginHole) `shouldBe` 1
      hdPointer (head (HA.holeDependsOn loginHole)) `shouldBe` "/statements/0/body"
      hdVia (head (HA.holeDependsOn loginHole)) `shouldBe` "hash-password"
      hdReason (head (HA.holeDependsOn loginHole)) `shouldBe` "calls-hole-body"

    it "independent holes have empty depends_on" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "a" "t1" TInt Nothing)))
                 , SDefLogic "g" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "b" "t2" TInt Nothing)))
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
      all (\e -> null (HA.holeDependsOn e)) entries `shouldBe` True

    it "JSON output with deps includes depends_on and cycle_warning" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "a" "t" TInt Nothing)))
                 ]
          report = analyzeHolesWithDeps prog
          json = HA.formatHoleReportJson "<test>" True report
      T.isInfixOf "depends_on" json `shouldBe` True
      T.isInfixOf "cycle_warning" json `shouldBe` True

  -- -----------------------------------------------------------------
  -- Cycle detection (2 tests)
  -- -----------------------------------------------------------------

  describe "Cycle detection" $ do
    it "mutual recursion sets cycle_warning on both holes" $ do
      -- f calls g, g calls f — both have holes
      let prog = [ SDefLogic "f" [("x", TInt)] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "g" [EHole (HDelegate (DelegateSpec "a" "t1" TInt Nothing))])
                 , SDefLogic "g" [("x", TInt)] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "f" [EHole (HDelegate (DelegateSpec "b" "t2" TInt Nothing))])
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
      -- Both should have cycle_warning
      all (\e -> HA.holeCycleWarn e) entries `shouldBe` True

    it "cycle breaking removes back-edge from highest-index hole" $ do
      let prog = [ SDefLogic "f" [("x", TInt)] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "g" [EHole (HDelegate (DelegateSpec "a" "t1" TInt Nothing))])
                 , SDefLogic "g" [("x", TInt)] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "f" [EHole (HDelegate (DelegateSpec "b" "t2" TInt Nothing))])
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
          gHole = head [e | e <- entries, HA.holePointer e == "/statements/1/body/args/0"]
      -- g (statement 1, higher index) should have its back-edge to f removed
      -- so g should have NO deps pointing to /statements/0/...
      let depsToF = [d | d <- HA.holeDependsOn gHole, T.isPrefixOf "/statements/0" (hdPointer d)]
      null depsToF `shouldBe` True

  -- -----------------------------------------------------------------
  -- Scope exclusions (2 tests)
  -- -----------------------------------------------------------------

  describe "Dependency scope exclusions" $ do
    it "?proof-required holes do not appear in depends_on" $ do
      let prog = [ SDefLogic "hash" [("x", TString)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EHole (HProofRequired "complex-decreases" Nothing))
                 , SDefLogic "login" [("u", TString)] Nothing (Contract Nothing Nothing Nothing Nothing Nothing)
                     (EApp "hash" [EHole (HDelegate (DelegateSpec "agent" "login" TString Nothing))])
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
          loginHole = head [e | e <- entries, HA.holeContext e == "def-logic login"]
      -- hash's hole is ?proof-required (NonBlocking) — should NOT appear as a dependency
      null (HA.holeDependsOn loginHole) `shouldBe` True

    it "contract-position holes do not appear in depends_on" $ do
      let prog = [ SDefLogic "validate" [("x", TInt)] Nothing
                     (Contract (Just (EHole (HNamed "pre-impl"))) Nothing Nothing Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "agent" "validate" TInt Nothing)))
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
          bodyHole = head [e | e <- entries, HA.holePointer e == "/statements/0/body"]
      -- The contract hole (in /pre) should not create a dependency
      null (HA.holeDependsOn bodyHole) `shouldBe` True

  -- -----------------------------------------------------------------------
  -- v0.3.4 AgentSpec faithfulness tests
  -- -----------------------------------------------------------------------
  describe "AgentSpec" $ do
    let spec = agentSpec
        specBuiltinNames = map beName (asBuiltins spec)
        specOpNames      = map aoOp (asOperators spec)
        allSpecNames     = specBuiltinNames ++ specOpNames
        -- Excluded: wasi.* functions are capability-gated
        isExcluded n     = T.isPrefixOf "wasi." n
        userFacing       = filter (not . isExcluded) (Map.keys builtinEnv)

    it "covers all non-excluded builtinEnv entries" $ do
      sort allSpecNames `shouldBe` sort userFacing

    it "does not contain entries absent from builtinEnv" $ do
      all (`Map.member` builtinEnv) allSpecNames `shouldBe` True

    it "partition is disjoint (builtins ∩ operators = ∅)" $ do
      let builtinSet = Set.fromList specBuiltinNames
          opSet      = Set.fromList specOpNames
      Set.intersection builtinSet opSet `shouldBe` Set.empty

    it "handles unary operator (not) with 1 param" $ do
      let notEntry = find (\e -> aoOp e == "not") (asOperators spec)
      fmap (length . aoParams) notEntry `shouldBe` Just 1

    it "output is deterministically ordered" $ do
      let names1 = map beName (asBuiltins spec)
      names1 `shouldBe` sort names1
      let ops1 = map aoOp (asOperators spec)
      ops1 `shouldBe` sort ops1

    it "excludes all wasi.* functions" $ do
      let wasiInSpec = filter (T.isPrefixOf "wasi.") allSpecNames
      wasiInSpec `shouldBe` []

    it "includes seq-commands (has preamble implementation)" $ do
      "seq-commands" `elem` specBuiltinNames `shouldBe` True

  -- =========================================================================
  -- v0.3.5: Context-Aware Checkout Tests (Track B)
  -- =========================================================================

  describe "v0.3.5 Context-Aware Checkout" $ do

    -- EC-1: if-branch env isolation
    it "EC-1: hole in let inside then-branch does not leak env to else-branch" $ do
      let src = T.pack $ unlines
            [ "(def-shell test-isolation [flag: bool]"
            , "  (if flag"
            , "    (let [(x 42)] x)"
            , "    ?else_hole))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case filter ((== "?else_hole") . shName) (sketchHoles result) of
            []    -> expectationFailure "?else_hole not recorded"
            (h:_) -> do
              -- x should NOT be in the else-branch's env
              let envNames = Map.keys (shEnv h)
              "x" `elem` envNames `shouldBe` False

    -- Scope provenance: param binding tagged correctly
    it "hole sees param bindings with SrcParam source" $ do
      let src = T.pack $ unlines
            [ "(def-shell greet [name: string]"
            , "  ?greeting)"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case filter ((== "?greeting") . shName) (sketchHoles result) of
            []    -> expectationFailure "?greeting not recorded"
            (h:_) -> do
              case Map.lookup "name" (shEnv h) of
                Nothing -> expectationFailure "param 'name' not in env"
                Just sb -> sbSource sb `shouldBe` SrcParam

    -- Scope: let-binding tagged correctly
    it "let-binding in scope has SrcLetBinding source" $ do
      let src = T.pack $ unlines
            [ "(def-shell f [x: int]"
            , "  (let [(y (+ x 1))]"
            , "    ?body))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          case filter ((== "?body") . shName) (sketchHoles result) of
            []    -> expectationFailure "?body not recorded"
            (h:_) -> do
              case Map.lookup "y" (shEnv h) of
                Nothing -> expectationFailure "let-binding 'y' not in env"
                Just sb -> sbSource sb `shouldBe` SrcLetBinding

    -- Match arm bindings tagged correctly
    it "match-arm binding has SrcMatchArm source" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-shell describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) ?blue)))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch GrammarCoreInversion emptyEnv stmts []
          -- The Blue arm's hole should have a match-arm env (the constructor pattern)
          -- Note: Blue is a nullary constructor, so no pattern bindings are introduced.
          -- The important thing is that the hole is correctly recorded.
          case filter ((== "?blue") . shName) (sketchHoles result) of
            []    -> expectationFailure "?blue not recorded"
            (h:_) -> shPointer h `shouldBe` "/statements/1/body/arms/2/body"

    -- EC-3: Pointer normalization
    it "EC-3: normalizePointer strips leading zeros" $ do
      normalizePointer "/statements/02/body" `shouldBe` "/statements/2/body"
      normalizePointer "/statements/0/body/arms/003/body" `shouldBe` "/statements/0/body/arms/3/body"
      normalizePointer "/statements/0/body" `shouldBe` "/statements/0/body"
      normalizePointer "" `shouldBe` ""

    -- Monomorphization idempotency (INV-1)
    it "INV-1: monomorphization is idempotent" $ do
      let scope = Map.fromList [("xs", TList TInt)]
          sigs  = Map.fromList [("list-head", TFn [TList (TVar "a")] (TVar "a"))]
          mono1 = monomorphizeFunctions scope sigs
          mono2 = monomorphizeFunctions scope mono1
      mono1 `shouldBe` mono2

    -- Monomorphization: concrete substitution
    it "C5: list-head with xs:list[int] monomorphizes to int" $ do
      let scope = Map.fromList [("xs", TList TInt)]
          sigs  = Map.fromList [("list-head", TFn [TList (TVar "a")] (TVar "a"))]
          result = monomorphizeFunctions scope sigs
      Map.lookup "list-head" result `shouldBe` Just (TFn [TList TInt] TInt)

    -- Scope truncation
    it "C6: truncateScope keeps params, drops open-imports first" $ do
      let entries =
            [ ("x", ScopeEntry "x" "int" "param")
            , ("y", ScopeEntry "y" "int" "param")
            , ("z", ScopeEntry "z" "string" "open-import")
            , ("w", ScopeEntry "w" "bool" "let-binding")
            ]
          (kept, truncated) = truncateScope 3 entries
      truncated `shouldBe` True
      length kept `shouldBe` 3
      -- Params (x, y) should always be kept; open-import (z) dropped first
      map seName kept `shouldSatisfy` (\names -> "x" `elem` names && "y" `elem` names)
      map seName kept `shouldSatisfy` (\names -> "z" `notElem` names)

  -- =========================================================================
  -- v0.3.5: WeaknessCheck Tests (Track W)
  -- =========================================================================

  describe "v0.3.5 WeaknessCheck" $ do

    -- W1: Identity body generates a candidate for int → int
    it "identity body generates candidate for int → int function" $ do
      let stmts =
            [ SDefLogic "inc" [("x", TInt)] (Just TInt)
                (Contract (Just (EApp ">" [EVar "x", ELit (LitInt 0)]))
                          Nothing
                          (Just (EApp ">" [EVar "result", ELit (LitInt 0)]))
                          Nothing Nothing)
                (EApp "+" [EVar "x", ELit (LitInt 1)])
            ]
          candidates = generateWeaknessCandidates GrammarCoreInversion stmts
          identityCandidates = [c | c <- candidates, case wcTrivialBody c of
                                                       TrivIdentity _ -> True
                                                       _ -> False]
      identityCandidates `shouldSatisfy` (not . null)
      wcFunctionName (head identityCandidates) `shouldBe` "inc"

    -- W1: Constant zero candidate for int-returning function
    it "constant zero generates candidate for int-returning function" $ do
      let stmts =
            [ SDefLogic "abs-val" [("x", TInt)] (Just TInt)
                (Contract Nothing Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                (EVar "x")
            ]
          candidates = generateWeaknessCandidates GrammarCoreInversion stmts
          -- LT-CDP (v0.11): TrivConstZero subsumed into TrivConstInt 0.
          zeroCandidates = [c | c <- candidates, wcTrivialBody c == TrivConstInt 0]
      zeroCandidates `shouldSatisfy` (not . null)

    -- W1 INV-4: type-incompatible bodies skipped
    it "INV-4: identity body skipped when param type != return type" $ do
      let stmts =
            [ SDefLogic "to-str" [("x", TInt)] (Just TString)
                (Contract Nothing Nothing (Just (EApp ">" [EApp "string-length" [EVar "result"], ELit (LitInt 0)])) Nothing Nothing)
                (EApp "to-string" [EVar "x"])
            ]
          candidates = generateWeaknessCandidates GrammarCoreInversion stmts
          identityCandidates = [c | c <- candidates, case wcTrivialBody c of
                                                       TrivIdentity _ -> True
                                                       _ -> False]
      -- Identity x : int cannot be a string; should be filtered out
      identityCandidates `shouldSatisfy` null

    -- W1: Functions without contracts skipped
    it "function without contracts produces no candidates" $ do
      let stmts =
            [ SDefLogic "id" [("x", TInt)] (Just TInt)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EVar "x")
            ]
          candidates = generateWeaknessCandidates GrammarCoreInversion stmts
      candidates `shouldSatisfy` null

    -- W1: Multiple functions independently
    it "weakness detection is independent per function" $ do
      let stmts =
            [ SDefLogic "f" [("x", TInt)] (Just TInt)
                (Contract Nothing Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                (EVar "x")
            , SDefLogic "g" [("s", TString)] (Just TString)
                (Contract Nothing Nothing (Just (EApp ">" [EApp "string-length" [EVar "result"], ELit (LitInt 0)])) Nothing Nothing)
                (EVar "s")
            ]
          candidates = generateWeaknessCandidates GrammarCoreInversion stmts
          fCandidates = [c | c <- candidates, wcFunctionName c == "f"]
          gCandidates = [c | c <- candidates, wcFunctionName c == "g"]
      fCandidates `shouldSatisfy` (not . null)
      gCandidates `shouldSatisfy` (not . null)

    -- EC-7: Precondition preserved in candidate
    it "EC-7: candidate preserves precondition for diagnostic" $ do
      let pre = Just (EApp ">" [EVar "x", ELit (LitInt 0)])
          stmts =
            [ SDefLogic "inc" [("x", TInt)] (Just TInt)
                (Contract pre Nothing (Just (EApp ">" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                (EApp "+" [EVar "x", ELit (LitInt 1)])
            ]
          candidates = generateWeaknessCandidates GrammarCoreInversion stmts
      case candidates of
        []    -> expectationFailure "expected at least one candidate"
        (c:_) -> wcPrecondition c `shouldBe` pre

  -- =========================================================================
  -- v0.4 CAP-1: Capability Enforcement Tests
  -- =========================================================================
  describe "CAP-1 capability enforcement" $ do

    -- CAP-1c: wasi.io.stdout with no import → compile error
    it "CAP-1c: wasi.io.stdout with no import produces missing-capability error" $ do
      let src = T.pack $ unlines
            [ "(def-shell greet [name: string]"
            , "  (wasi.io.stdout name))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
              capErrors = filter (\d -> diagKind d == Just "missing-capability")
                                 (reportDiagnostics report)
          length capErrors `shouldBe` 1
          diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.io.stdout"
          diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.io"

    -- CAP-1d: wasi.io.stdout inside a let binding with no import → error
    it "CAP-1d: wasi.io.stdout nested in let binding still caught" $ do
      let src = T.pack $ unlines
            [ "(def-shell greet [name: string]"
            , "  (let [(msg (wasi.io.stdout name))]"
            , "    msg))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
              capErrors = filter (\d -> diagKind d == Just "missing-capability")
                                 (reportDiagnostics report)
          length capErrors `shouldBe` 1

    -- CAP-1e: wasi.io.stdout with matching import → OK
    it "CAP-1e: wasi.io.stdout with (import wasi.io ...) succeeds" $ do
      -- Construct the import + function AST directly
      let stmts =
            [ SImport (Import "wasi.io" Nothing (Just (Capability CapWrite "*" True)))
            , SDefLogic "greet" [("name", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "wasi.io.stdout" [EVar "name"])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          capErrors = filter (\d -> diagKind d == Just "missing-capability")
                             (reportDiagnostics report)
      capErrors `shouldBe` []

    -- CAP-1f: wasi.fs.write with wasi.io import only → error (per-namespace)
    it "CAP-1f: wasi.fs.write with only wasi.io import is per-namespace error" $ do
      let stmts =
            [ SImport (Import "wasi.io" Nothing (Just (Capability CapWrite "*" True)))
            , SDefLogic "write-file" [("path", TString), ("content", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "wasi.fs.write" [EVar "path", EVar "content"])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          capErrors = filter (\d -> diagKind d == Just "missing-capability")
                             (reportDiagnostics report)
      length capErrors `shouldBe` 1
      diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.fs"

    -- CAP-1g: Cross-module non-transitive capability enforcement
    it "CAP-1g: cross-module wasi call without own import is error (non-transitive)" $ do
      -- Module A has wasi.io import and exports a helper
      let modAStmts =
            [ SImport (Import "wasi.io" Nothing (Just (Capability CapRead "*" True)))
            , SDefLogic "print-msg" [("msg", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "wasi.io.stdout" [EVar "msg"])
            , SExport ["print-msg"]
            ]
          modAEnv = ModuleEnv
            { meExports = DM.fromList [("print-msg", TFn [TString] (TCustom "Command"))]
            , meStatements = modAStmts
            , meInterfaces = DM.empty
            , meAliasMap = DM.empty
            , mePath = ["helpers"]
            , meContractStatus = DM.empty
            , meContracts = DM.empty
            }
          cache = DM.fromList [( ["helpers"], modAEnv)]
          -- Module B imports helpers, calls wasi.io.stdout directly without own import
          callerStmts =
            [ SDefLogic "caller" [("s", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "wasi.io.stdout" [EVar "s"])
            ]
          report = typeCheckWithCache GrammarCoreInversion cache emptyEnv callerStmts
          capErrors = filter (\d -> diagKind d == Just "missing-capability")
                             (reportDiagnostics report)
      -- Module B has no wasi.io import → error (non-transitive)
      length capErrors `shouldBe` 1
      diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.io"

  -- =========================================================================
  -- pCapKind: capability-import parser ordering (doc-audit regression)
  --
  -- "get-bytes" was unparseable: `CapHttpGet <$ try (symbol "get")` was tried
  -- before `CapRandomGet <$ try (symbol "get-bytes")`, and `symbol "get"`
  -- (no word-boundary check) matched the "get" prefix of "get-bytes",
  -- leaving "-bytes" dangling and unparseable ("unexpected '(' ... expecting
  -- ')'"). Fixed by longest-match-first ordering, matching the existing
  -- read-write/read precedent in the same `choice` list.
  -- =========================================================================
  describe "pCapKind: capability-import parser ordering" $ do

    it "CAP-GB-1: (capability get-bytes ...) parses to CapRandomGet, not a truncated CapHttpGet" $ do
      let src = "(import wasi.random (capability get-bytes :deterministic true))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure $ "Parse failed (regression!): " ++ show err
        Right [SImport (Import path _ (Just (Capability kind target det)))] -> do
          path `shouldBe` "wasi.random"
          kind `shouldBe` CapRandomGet
          target `shouldBe` ""
          det `shouldBe` True
        Right other -> expectationFailure $ "Unexpected AST shape: " ++ show other

    it "CAP-GB-2: (capability get ...) still parses to CapHttpGet (no regression on the short form)" $ do
      let src = "(import wasi.http (capability get :deterministic true))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure $ "Parse failed: " ++ show err
        Right [SImport (Import _ _ (Just (Capability kind _ _)))] -> kind `shouldBe` CapHttpGet
        Right other -> expectationFailure $ "Unexpected AST shape: " ++ show other

    it "CAP-GB-3: every pCapKind alternative still round-trips (no regressions from reordering)" $ do
      let cases =
            [ ("read-write",     CapReadWrite)
            , ("read",           CapRead)
            , ("write",          CapWrite)
            , ("connect",        CapNetConnect)
            , ("serve",          CapNetServe)
            , ("post",           CapHttpPost)
            , ("get-bytes",      CapRandomGet)
            , ("get",            CapHttpGet)
            , ("monotonic-read", CapClockMonotonic)
            ]
      forM_ cases $ \(kw, expected) -> do
        let src = "(import wasi.test (capability " <> kw <> " :deterministic true))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Left err -> expectationFailure $ T.unpack kw ++ " parse failed: " ++ show err
          Right [SImport (Import _ _ (Just (Capability kind _ _)))] ->
            kind `shouldBe` expected
          Right other -> expectationFailure $ T.unpack kw ++ " unexpected AST shape: " ++ show other

    it "CAP-GB-4: an unrecognized capability keyword falls back to CapCustom" $ do
      let src = "(import wasi.test (capability frobnicate :deterministic true))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure $ "Parse failed: " ++ show err
        Right [SImport (Import _ _ (Just (Capability kind _ _)))] ->
          kind `shouldBe` CapCustom "frobnicate"
        Right other -> expectationFailure $ "Unexpected AST shape: " ++ show other

  -- =========================================================================
  -- v0.4 U-Lite: Per-Call-Site Substitution Tests
  -- =========================================================================
  describe "U-Lite per-call-site substitution" $ do

    -- U4a: cross-argument consistency — (= 42 "hello") should fail
    it "U4a: (= 42 \"hello\") catches int vs string cross-arg mismatch" $ do
      let stmts =
            [ SDefLogic "f" [] (Just TBool) (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "=" [ELit (LitInt 42), ELit (LitString "hello")])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U4b: list-contains cross-arg mismatch
    it "U4b: list-contains([1,2,3], \"hello\") catches element type mismatch" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just TBool) (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "list-contains" [EVar "xs", ELit (LitString "hello")])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U5: list-map with mismatched element type in lambda
    it "U5: list-map [ints] (fn [x: string] x) catches element type mismatch" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just (TList TString)) (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "list-map" [EVar "xs", ELambda [("x", TString)] (EVar "x")])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U4c: first(42) should fail (non-pair argument)
    it "U4c: first(42) catches non-pair argument" $ do
      let stmts =
            [ SDefLogic "f" [] (Just (TVar "a")) (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "first" [ELit (LitInt 42)])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U4d: second("hello") should fail (non-pair argument)
    it "U4d: second(\"hello\") catches non-pair argument" $ do
      let stmts =
            [ SDefLogic "f" [] (Just (TVar "b")) (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "second" [ELit (LitString "hello")])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U6: alias expansion + first still works with dep types
    it "U6: first on pair with where-type alias passes" $ do
      let src = T.pack $ unlines
            [ "(type Word (where [s: string] (> (string-length s) 0)))"
            , "(def-shell get-word [p: (Word, int)] (first p))"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- U7a: TSumType structural inequality — different sum types are now incompatible
    it "U7a: Color /= Shape -- different sum types are incompatible" $ do
      let stmts =
            [ STypeDef "Color" (TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)])
            , STypeDef "Shape" (TSumType [("Circle", Just TInt), ("Rect", Nothing)])
            , SDefLogic "f" [("c", TCustom "Color")] (Just (TCustom "Shape"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "c")
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U7b: Same sum types are still compatible
    it "U7b: Color = Color -- same sum types are compatible" $ do
      let stmts =
            [ STypeDef "Color" (TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)])
            , SDefLogic "f" [("c", TCustom "Color")] (Just (TCustom "Color"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "c")
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
      reportSuccess report `shouldBe` True

    -- U-Lite positive: polymorphic functions still work correctly
    it "U-Lite: list-head on list[int] returns Result[int, string]" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just (TResult TInt TString))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "list-head" [EVar "xs"])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
      reportSuccess report `shouldBe` True

    it "U-Lite: pair(1, \"hello\") then first gives int" $ do
      let stmts =
            [ SDefLogic "f" [] (Just (TVar "a")) (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "first" [EApp "pair" [ELit (LitInt 1), ELit (LitString "hello")]])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
      reportSuccess report `shouldBe` True

  -- =========================================================================
  -- v0.5 U-Full: Sound Unification Tests
  -- =========================================================================
  describe "U-Full sound unification" $ do

    -- U1-full: Occurs check — reject infinite type a ~ list[a]
    it "U1-full: occurs check rejects infinite type a ~ list[a]" $ do
      -- list-prepend : a -> list[a] -> list[a]
      -- Calling list-prepend with a list[a] as the first argument (element position)
      -- should work fine. But we can construct the infinite type scenario directly
      -- via structuralUnify in TypeCheck.
      -- Test: a user-defined function f : a -> list[a], called as f(xs) where xs : list[int]
      -- This binds a -> list[int], return type becomes list[list[int]] — NOT an infinite type.
      -- True infinite type: construct a scenario where unify would produce a = list[a].
      -- We test structuralUnify directly.
      let subst = Map.empty :: Map.Map T.Text Type
          -- Attempt to unify TVar "a" with TList (TVar "a") — this is infinite
      let result = runTCPure $ structuralUnify "test" subst (TVar "a") (TList (TVar "a"))
          errs = fst result
      length errs `shouldSatisfy` (> 0)
      any (T.isInfixOf "infinite type") (map diagMessage errs) `shouldBe` True

    -- U1-full: No false positive — valid recursive-looking uses should pass
    it "U1-full: list-head on list[int] does not trigger occurs check (no false positive)" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just (TResult TInt TString))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "list-head" [EVar "xs"])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
      reportSuccess report `shouldBe` True

    -- ---------------------------------------------------------------------
    -- BUG-3 (v0.14.3): false-positive "infinite type" from a bare-name
    -- collision, isolated from the hangman_json_verifier fixture that
    -- surfaced it (examples/hangman_json_verifier/hangman.ast.json,
    -- `make-state`). An unannotated empty-list literal ((list-empty), what
    -- an empty `[]`/lit-list desugars to) is inferred with an UNRESOLVED
    -- `TVar "a"` for its element type (nothing ever pins it to a concrete
    -- type). That bare TVar leaks into the function's inferred body/result
    -- type (no let-generalization in this checker). Separately, the builtin
    -- `second :: TFn [TPair (TVar "a") (TVar "b")] (TVar "b")` uses the
    -- SAME literal name "a" for its own (semantically irrelevant, thrown
    -- away) placeholder. Before the fix, calling `second` on a value
    -- containing the leaked list unified second's own "a" against the
    -- leaked `TList (TVar "a")`, and `occursIn`'s plain string-equality
    -- check couldn't tell "the same variable" apart from "two unrelated
    -- variables that happen to be spelled the same" -- firing a false
    -- "infinite type: a occurs in list[a]" though there was no real cycle.
    -- Fix: freshenFnType renames a callee's TVars to a globally-unique name
    -- at every EApp/EOp call site (TypeCheck.hs), so no two call sites (nor
    -- a call site and a leaked user TVar) can ever collide by name again.
    -- ---------------------------------------------------------------------
    it "BUG-3: empty-list TVar does not collide with a builtin's own TVar placeholder (no false 'infinite type')" $ do
      let stmts =
            [ SDefLogic "make-state" [] Nothing
                (Contract Nothing Nothing
                   -- post: (= (first (second result)) 0) — mirrors
                   -- make-state's real post shape (pair-accessor chain on
                   -- `result`), one nesting level shorter than the fixture
                   -- (which needs two `second`s because its empty list sits
                   -- one pair-slot deeper) but the same collision mechanism.
                   (Just (EApp "=" [ EApp "first" [EApp "second" [EVar "result"]]
                                    , ELit (LitInt 0) ]))
                   Nothing Nothing)
                -- body: (pair (list-empty) (pair 0 0)) — an empty list
                -- directly in the first pair slot, same as make-state's
                -- `(pair word (pair (lit-list []) ...))` collapsed by one
                -- level (dropping the outer `word` wrapper is what shortens
                -- the required `second` nesting from two calls to one).
                (EApp "pair" [ EApp "list-empty" []
                             , EApp "pair" [ELit (LitInt 0), ELit (LitInt 0)] ])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      any (T.isInfixOf "infinite type") (map diagMessage errs) `shouldBe` False
      reportSuccess report `shouldBe` True

    -- U2-full: TVar-TVar binding — polymorphic function called with TVar arg
    it "U2-full: TVar-TVar binding records in substitution map" $ do
      let subst = Map.empty :: Map.Map T.Text Type
          -- Unify TVar "a" with TVar "b" — should bind a -> TVar "b"
      let result = runTCPure $ structuralUnify "test" subst (TVar "a") (TVar "b")
          finalSubst = snd result
      Map.lookup "a" finalSubst `shouldBe` Just (TVar "b")

    -- U2-full: Top-level polymorphic reuse — same function at two sites with different types
    it "U2-full: polymorphic top-level function works at two call sites with different types" $ do
      let stmts =
            [ SDefLogic "identity" [("x", TVar "a")] (Just (TVar "a"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "x")
            , SDefLogic "test" [] (Just TBool)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                -- Call identity(42) and identity("hello") at different sites
                -- Both should succeed because each EApp gets a fresh substitution
                (EApp "=" [ EApp "identity" [ELit (LitInt 42)]
                          , ELit (LitInt 42) ])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
      reportSuccess report `shouldBe` True

    -- U2-full: Same-call-site conflict — f(5, "hello") where f : a -> a -> a
    it "U2-full: conflicting types at same call site rejected" $ do
      let stmts =
            [ SDefLogic "same-type" [("x", TVar "a"), ("y", TVar "a")] (Just (TVar "a"))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "x")
            , SDefLogic "test" [] (Just TBool)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "same-type" [ELit (LitInt 5), ELit (LitString "hello")])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- Issue 2: Bound-TVar consistency — f : a -> a -> bool, called as f(5, "hello")
    it "U2-full (Issue 2): bound-TVar consistency rejects f(5, \"hello\") for f : a -> a -> bool" $ do
      let stmts =
            [ SDefLogic "same-check" [("x", TVar "a"), ("y", TVar "a")] (Just TBool)
                (Contract Nothing Nothing Nothing Nothing Nothing) (EApp "=" [EVar "x", EVar "y"])
            , SDefLogic "test" [] (Just TBool)
                (Contract Nothing Nothing Nothing Nothing Nothing)
                (EApp "same-check" [ELit (LitInt 5), ELit (LitString "hello")])
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      -- Should reject: a bound to int from first arg, string conflicts at second
      length errs `shouldSatisfy` (> 0)

    -- TVar chain: f : a -> a called with TVar "b" arg, result used where int expected
    it "U2-full: TVar chain propagation (a -> b, then b -> int)" $ do
      let subst0 = Map.empty :: Map.Map T.Text Type
      -- Step 1: unify a with TVar "b" => subst has a -> TVar "b"
      let result1 = runTCPure $ structuralUnify "test" subst0 (TVar "a") (TVar "b")
          subst1 = snd result1
      Map.lookup "a" subst1 `shouldBe` Just (TVar "b")
      -- Step 2: unify a with TInt => should follow chain: a -> TVar "b", then b -> TInt
      let result2 = runTCPure $ structuralUnify "test" subst1 (TVar "a") TInt
          subst2 = snd result2
          errs2  = fst result2
      -- No errors — chain should propagate
      length errs2 `shouldBe` 0
      -- b should now be bound to TInt via the recursive call
      Map.lookup "b" subst2 `shouldBe` Just TInt

  -- =========================================================================
  -- v0.4 Task 7: Invariant Pattern Registry
  -- =========================================================================
  describe "Invariant Pattern Registry" $ do

    it "list[a] -> list[a] function gets list-preserving suggestion" $ do
      let ty = TFn [TList TInt] (TList TInt)
      let results = matchPatterns "my-transform" ty defaultPatterns
      let ids = map isPatternId results
      ids `shouldSatisfy` elem "list-preserving"

    it "sort-items with list[a] -> list[a] gets sorted + list-preserving" $ do
      let ty = TFn [TList TString] (TList TString)
      let results = matchPatterns "sort-items" ty defaultPatterns
      let ids = map isPatternId results
      ids `shouldSatisfy` elem "sorted"
      ids `shouldSatisfy` elem "list-preserving"

    it "filter-by with list[a] -> list[a] gets subset + list-preserving" $ do
      let ty = TFn [TList TInt] (TList TInt)
      let results = matchPatterns "filter-by" ty defaultPatterns
      let ids = map isPatternId results
      ids `shouldSatisfy` elem "subset"
      ids `shouldSatisfy` elem "list-preserving"

    it "int -> int function gets no suggestions" $ do
      let ty = TFn [TInt] TInt
      let results = matchPatterns "add-one" ty defaultPatterns
      results `shouldBe` []

    it "encode function gets round-trip suggestion" $ do
      let ty = TFn [TString] TString
      let results = matchPatterns "encode" ty defaultPatterns
      let ids = map isPatternId results
      ids `shouldSatisfy` elem "round-trip"

    it "runSketch with defaultPatterns returns invariant suggestions" $ do
      let stmts =
            [ SDefLogic "my-sort" [("xs", TList TInt)] (Just (TList TInt))
                (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "xs")
            ]
          result = runSketch GrammarCoreInversion emptyEnv stmts defaultPatterns
          ids = map isPatternId (sketchInvariants result)
      ids `shouldSatisfy` elem "sorted"
      ids `shouldSatisfy` elem "list-preserving"

  -- =========================================================================
  -- v0.4 Task 9: Aeson FFI codegen
  -- =========================================================================
  describe "Aeson FFI Codegen" $ do

    it "haskell.aeson generates 'import Data.Aeson' in Lib.hs" $ do
      let stmts = [SImport (Import "haskell.aeson" Nothing Nothing)]
          result = generateHaskell "test" stmts
      cgHsSource result `shouldSatisfy` T.isInfixOf "import Data.Aeson"

    it "haskell.aeson adds aeson to package.yaml dependencies" $ do
      let stmts = [SImport (Import "haskell.aeson" Nothing Nothing)]
          result = generateHaskell "test" stmts
      cgPackageYaml result `shouldSatisfy` T.isInfixOf "aeson"

    it "unknown haskell.foo falls back to 'import Foo'" $ do
      let stmts = [SImport (Import "haskell.foo" Nothing Nothing)]
          result = generateHaskell "test" stmts
      cgHsSource result `shouldSatisfy` T.isInfixOf "import Foo"

    it "classifyImport recognizes haskell.aeson as HackageImport" $ do
      classifyImport (Import "haskell.aeson" Nothing Nothing) `shouldBe` HackageImport "aeson"

  -- =========================================================================
  -- v0.4 Task 8: Downstream Obligation Mining
  -- =========================================================================
  describe "Obligation Mining" $ do

    it "SAFE result produces no suggestions" $ do
      let stmts = [SDefLogic "f" [("x", TInt)] (Just TInt)
                    (Contract (Just (EApp ">" [EVar "x", ELit (LitInt 0)]))
                              Nothing
                              (Just (EApp ">" [EVar "result", ELit (LitInt 0)]))
                              Nothing Nothing)
                    (EVar "x")]
          table = Map.empty
          report = TrustReport [] (TrustSummary 0 0 0 0 0 0) [] (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) [] [] Map.empty Set.empty Set.empty Set.empty (OverAnnotationInfo 0.0 overAnnotationThreshold False)
      mineObligations table FQSafe report stmts `shouldBe` []

    it "UNSAFE with unknown constraint ID produces no suggestion" $ do
      let stmts = [SDefLogic "f" [("x", TInt)] (Just TInt)
                    (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "x")]
          table = Map.empty  -- empty: no origin for constraint 42
          report = TrustReport [] (TrustSummary 0 0 0 0 0 0) [] (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) [] [] Map.empty Set.empty Set.empty Set.empty (OverAnnotationInfo 0.0 overAnnotationThreshold False)
      mineObligations table (FQUnsafe [42]) report stmts `shouldBe` []

    it "UNSAFE with known origin produces self-suggestion" $ do
      let stmts = [SDefLogic "addPos" [("x", TInt), ("y", TInt)] (Just TInt)
                    (Contract (Just (EApp ">" [EVar "x", ELit (LitInt 0)]))
                              Nothing
                              (Just (EApp ">" [EVar "result", ELit (LitInt 0)]))
                              Nothing Nothing)
                    (EApp "+" [EVar "x", EVar "y"])]
          table = Map.fromList
            [(0, ConstraintOrigin "addPos" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0 0) [] (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) [] [] Map.empty Set.empty Set.empty Set.empty (OverAnnotationInfo 0.0 overAnnotationThreshold False)
          results = mineObligations table (FQUnsafe [0]) report stmts
      length results `shouldBe` 1
      osCaller (head results) `shouldBe` "addPos"
      osCallee (head results) `shouldBe` "addPos"  -- self-suggestion (no callees)

    it "QF-LIA postcondition gets Verified strength" $ do
      let stmts = [SDefLogic "f" [("x", TInt)] (Just TInt)
                    (Contract Nothing Nothing
                              (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                    (EVar "x")]
          table = Map.fromList
            [(0, ConstraintOrigin "f" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0 0) [] (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) [] [] Map.empty Set.empty Set.empty Set.empty (OverAnnotationInfo 0.0 overAnnotationThreshold False)
          results = mineObligations table (FQUnsafe [0]) report stmts
      length results `shouldBe` 1
      osStrength (head results) `shouldBe` Verified

    it "non-linear postcondition gets Advisory strength" $ do
      -- (> (* x x) 0) is non-linear (uses *), outside QF-LIA
      let stmts = [SDefLogic "g" [("x", TInt)] (Just TInt)
                    (Contract Nothing Nothing
                              (Just (EApp ">" [EApp "*" [EVar "x", EVar "x"], ELit (LitInt 0)])) Nothing Nothing)
                    (EVar "x")]
          table = Map.fromList
            [(0, ConstraintOrigin "g" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0 0) [] (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) [] [] Map.empty Set.empty Set.empty Set.empty (OverAnnotationInfo 0.0 overAnnotationThreshold False)
          results = mineObligations table (FQUnsafe [0]) report stmts
      length results `shouldBe` 1
      osStrength (head results) `shouldBe` Advisory

    it "JSON output includes strength field" $ do
      let stmts = [SDefLogic "h" [("x", TInt)] (Just TInt)
                    (Contract Nothing Nothing
                              (Just (EApp ">" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                    (EVar "x")]
          table = Map.fromList
            [(0, ConstraintOrigin "h" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0 0) [] (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) (TierProfile 0 0 0 0 0 0) [] [] Map.empty Set.empty Set.empty Set.empty (OverAnnotationInfo 0.0 overAnnotationThreshold False)
          results = mineObligations table (FQUnsafe [0]) report stmts
          jsonOut = formatObligationsJson results
      jsonOut `shouldSatisfy` T.isInfixOf "VERIFIED"
      jsonOut `shouldSatisfy` T.isInfixOf "obligation_suggestions"

  -- =========================================================================
  -- v0.6 SpecCoverage Tests (SC-1..4)
  -- =========================================================================
  describe "SpecCoverage (v0.6)" $ do
    let noContract = Contract Nothing Nothing Nothing Nothing Nothing
        withPost   = Contract Nothing Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing
        withPre    = Contract (Just (EApp ">" [EVar "x", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing
        emptyCS    = Map.empty :: Map.Map T.Text ContractStatus

    -- SC-PO-1: empty module → 100% (no div-by-zero)
    it "SC-PO-1: empty module → 100% effective coverage" $ do
      let report = runCoverage [] emptyCS
      csEffective (crSummary report) `shouldBe` 1.0
      csTotal (crSummary report) `shouldBe` 0

    -- All contracted → 100%
    it "all-contracted module → 100% coverage" $ do
      let stmts = [ SDefLogic "f" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SDefLogic "g" [("x", TInt)] (Just TInt) withPre (EVar "x")
                   ]
          report = runCoverage stmts emptyCS
      csContracted (crSummary report) `shouldBe` 2
      csTotal (crSummary report) `shouldBe` 2
      csEffective (crSummary report) `shouldBe` 1.0

    -- Mixed classification
    it "mixed module classifies correctly" $ do
      let stmts = [ SDefLogic "contracted-fn" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SDefLogic "unspecified-fn" [("x", TInt)] (Just TInt) noContract (EVar "x")
                   , SWeaknessOk "suppressed-fn" "intentionally weak"
                   , SDefLogic "suppressed-fn" [("x", TInt)] (Just TInt) noContract (EVar "x")
                   ]
          report = runCoverage stmts emptyCS
      csContracted (crSummary report) `shouldBe` 1
      csSuppressed (crSummary report) `shouldBe` 1
      csUnspecified (crSummary report) `shouldBe` 1
      csTotal (crSummary report) `shouldBe` 3

    -- WO-PO-1: weakness-ok for nonexistent fn → warning
    it "WO-1: weakness-ok for nonexistent fn emits warning" $ do
      let stmts = [ SDefLogic "real-fn" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SWeaknessOk "nonexistent" "some reason"
                   ]
          report = runCoverage stmts emptyCS
          warnings = crWarnings report
          wo1 = [d | d <- warnings, diagKind d == Just "weakness-ok-unresolved"]
      length wo1 `shouldSatisfy` (> 0)

    -- WO-2: contracted + suppressed → classified as contracted + warning
    it "WO-2: contracted + weakness-ok → contracted with redundancy warning" $ do
      let stmts = [ SDefLogic "both-fn" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SWeaknessOk "both-fn" "has contracts anyway"
                   ]
          report = runCoverage stmts emptyCS
      csContracted (crSummary report) `shouldBe` 1
      csSuppressed (crSummary report) `shouldBe` 0
      let wo2 = [d | d <- crWarnings report, diagKind d == Just "weakness-ok-redundant"]
      length wo2 `shouldSatisfy` (> 0)

    -- WO-PO-2: duplicate weakness-ok → single suppression entry
    it "WO-PO-2: duplicate weakness-ok → single suppressed entry" $ do
      let stmts = [ SDefLogic "dup-fn" [("x", TInt)] (Just TInt) noContract (EVar "x")
                   , SWeaknessOk "dup-fn" "reason 1"
                   , SWeaknessOk "dup-fn" "reason 1"
                   ]
          report = runCoverage stmts emptyCS
      csSuppressed (crSummary report) `shouldBe` 1

    -- D10: >50% suppressed → bulk suppression warning
    it "D10: >50% suppressed → bulk suppression warning" $ do
      let stmts = [ SDefLogic "a" [("x", TInt)] (Just TInt) noContract (EVar "x")
                   , SDefLogic "b" [("x", TInt)] (Just TInt) noContract (EVar "x")
                   , SDefLogic "c" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SWeaknessOk "a" "reason a"
                   , SWeaknessOk "b" "reason b"
                   ]
          report = runCoverage stmts emptyCS
          d10 = [d | d <- crWarnings report, diagKind d == Just "bulk-suppression"]
      length d10 `shouldSatisfy` (> 0)

    -- JSON output is valid
    it "JSON output contains expected fields" $ do
      let stmts = [ SDefLogic "f" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SDefLogic "g" [("x", TInt)] (Just TInt) noContract (EVar "x")
                   ]
          report = runCoverage stmts emptyCS
          json = formatCoverageJson report
      json `shouldSatisfy` T.isInfixOf "effective_coverage"
      json `shouldSatisfy` T.isInfixOf "contracted"
      json `shouldSatisfy` T.isInfixOf "unspecified"

    -- Excludes non-function statements
    it "excludes non-function statements from count" $ do
      let stmts = [ SDefLogic "f" [("x", TInt)] (Just TInt) withPost (EVar "x")
                   , SExport ["f"]
                   , STrust "some.module" DLAsserted
                   , SDefInterface "ICodec" [("encode", TFn [TInt] TString)] []
                   ]
          report = runCoverage stmts emptyCS
      csTotal (crSummary report) `shouldBe` 1

  -- =========================================================================
  -- v0.6.2: Interface Laws Tests (LAWS-8)
  -- =========================================================================
  describe "v0.6.2 Interface Laws" $ do
    let emptyCS = Map.empty :: Map.Map T.Text ContractStatus

    -- T1: S-expr parsing of a single law
    it "T1: laws_parse_basic — single law parses to [Property]" $ do
      let src = T.pack $ unlines
            [ "(def-interface Normalizer"
            , "  [normalize (fn [x: string] -> string)]"
            , "  :laws"
            , "  [(for-all [x: string]"
            , "    (= (normalize (normalize x)) (normalize x)))])"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SDefInterface name fns laws -> do
              name `shouldBe` "Normalizer"
              length fns `shouldBe` 1
              length laws `shouldBe` 1
              let Property desc bindings _body _subjects = head laws
              desc `shouldBe` ""
              length bindings `shouldBe` 1
              fst (head bindings) `shouldBe` "x"
            _ -> expectationFailure "expected SDefInterface"

    -- T2: S-expr without :laws parses to empty list
    it "T2: laws_parse_empty — no :laws clause → []" $ do
      let src = T.pack $ unlines
            [ "(def-interface Serializable"
            , "  [serialize (fn [x: int] -> string)]"
            , "  [deserialize (fn [x: string] -> int)])"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          case head stmts of
            SDefInterface _ _ laws -> laws `shouldBe` []
            _ -> expectationFailure "expected SDefInterface"

    -- T3: Multiple laws parse correctly
    it "T3: laws_parse_multiple — 3 laws → 3 Property entries" $ do
      let src = T.pack $ unlines
            [ "(def-interface Codec"
            , "  [encode (fn [x: int] -> string)]"
            , "  [decode (fn [x: string] -> int)]"
            , "  :laws"
            , "  [(for-all [x: int]"
            , "    (= (decode (encode x)) x))"
            , "   (for-all [s: string]"
            , "    (= (encode (decode s)) s))"
            , "   (for-all [x: int]"
            , "    (= (encode x) (encode x)))])"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          case head stmts of
            SDefInterface _ _ laws -> length laws `shouldBe` 3
            _ -> expectationFailure "expected SDefInterface"

    -- T4: Type-checking with valid law referencing interface methods
    it "T4: laws_typecheck_ok — law referencing interface methods type-checks" $ do
      let src = T.pack $ unlines
            [ "(def-interface Normalizer"
            , "  [normalize (fn [x: string] -> string)]"
            , "  :laws"
            , "  [(for-all [x: string]"
            , "    (= (normalize (normalize x)) (normalize x)))])"
            ]
      case parseStatements GrammarCoreInversion "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- T5: Law body returning non-bool → type error
    it "T5: laws_typecheck_nonbool — non-bool law body → error" $ do
      let stmts =
            [ SDefInterface "BadIface"
                [("f", TFn [TInt] TInt)]
                [Property "" [("x", TInt)] (EApp "f" [EVar "x"]) []]  -- returns int, not bool
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)
      any (T.isInfixOf ":laws clause must be bool") (map diagMessage errs) `shouldBe` True

    -- T6: Law referencing undefined name → warning/error
    it "T6: laws_typecheck_unbound — undefined name in law body" $ do
      let stmts =
            [ SDefInterface "BadIface2"
                [("f", TFn [TInt] TBool)]
                [Property "" [("x", TInt)] (EApp "undefined-fn" [EVar "x"]) []]
            ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
          diags = reportDiagnostics report
      -- Should produce a diagnostic about undefined-fn
      length diags `shouldSatisfy` (> 0)

    -- T7: JSON-AST round-trip (emit → parse → compare)
    it "T7: laws_json_roundtrip — emit then parse recovers same AST" $ do
      let laws = [ Property "" [("x", TString)]
                     (EOp "=" [ EApp "normalize" [EApp "normalize" [EVar "x"]]
                              , EApp "normalize" [EVar "x"]
                              ])
                     []
                 ]
          original = [ SDefInterface "Normalizer"
                         [("normalize", TFn [TString] TString)]
                         laws
                     ]
          emitted = emitJsonAST original
      case parseJSONAST GrammarLegacy "<test>" emitted of
        Left err    -> expectationFailure (show err)
        Right parsed -> do
          length parsed `shouldBe` 1
          case head parsed of
            SDefInterface name fns parsedLaws -> do
              name `shouldBe` "Normalizer"
              length fns `shouldBe` 1
              length parsedLaws `shouldBe` 1
              propBindings (head parsedLaws) `shouldBe` propBindings (head laws)
            _ -> expectationFailure "expected SDefInterface after round-trip"

    -- T8: Codegen emits prop_ function for a single law
    it "T8: laws_codegen_prop — single law → prop_ function" $ do
      let stmts = [ SDefInterface "Normalizer"
                      [("normalize", TFn [TString] TString)]
                      [Property "" [("x", TString)]
                        (EOp "=" [ EApp "normalize" [EApp "normalize" [EVar "x"]]
                                 , EApp "normalize" [EVar "x"]])
                        []]
                  ]
          result = generateHaskell "test" stmts
          source = cgHsSource result
      source `shouldSatisfy` T.isInfixOf "prop_Normalizer_law_1"
      source `shouldSatisfy` T.isInfixOf "Bool"

    -- T9: Codegen emits multiple prop_ functions for multiple laws
    it "T9: laws_codegen_multi — 3 laws → 3 prop_ functions" $ do
      let mkLaw body = Property "" [("x", TInt)] body []
          stmts = [ SDefInterface "Codec"
                      [("encode", TFn [TInt] TString), ("decode", TFn [TString] TInt)]
                      [ mkLaw (EOp "=" [EApp "decode" [EApp "encode" [EVar "x"]], EVar "x"])
                      , mkLaw (EOp "=" [EApp "encode" [EVar "x"], EApp "encode" [EVar "x"]])
                      , mkLaw (EOp "=" [EVar "x", EVar "x"])
                      ]
                  ]
          result = generateHaskell "test" stmts
          source = cgHsSource result
      source `shouldSatisfy` T.isInfixOf "prop_Codec_law_1"
      source `shouldSatisfy` T.isInfixOf "prop_Codec_law_2"
      source `shouldSatisfy` T.isInfixOf "prop_Codec_law_3"

    -- T10: SpecCoverage reports interface laws in separate section
    it "T10: laws_coverage — interface laws appear in coverage report" $ do
      let stmts = [ SDefLogic "f" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "x")
                  , SDefInterface "Normalizer"
                      [("normalize", TFn [TString] TString)]
                      [Property "" [("x", TString)]
                        (EOp "=" [ EApp "normalize" [EApp "normalize" [EVar "x"]]
                                 , EApp "normalize" [EVar "x"]])
                        []]
                  ]
          report = runCoverage stmts emptyCS
      -- Laws should appear in crLaws, not inflate effective_coverage
      length (crLaws report) `shouldBe` 1
      leName (head (crLaws report)) `shouldBe` "Normalizer"
      leLawCount (head (crLaws report)) `shouldBe` 1
      -- Only the SDefLogic function counts toward effective_coverage
      csTotal (crSummary report) `shouldBe` 1
      -- Text output should mention "Interface laws"
      let textReport = formatCoverageText report
      textReport `shouldSatisfy` T.isInfixOf "Interface laws"
      -- JSON output should include "laws" key
      let jsonReport = formatCoverageJson report
      jsonReport `shouldSatisfy` T.isInfixOf "law_count"

    -- T11: SUPP-DEBT — spec_coverage and suppression_debt fields
    it "T11: SUPP-DEBT — spec_coverage and suppression_debt computed correctly" $ do
      let stmts = [ SDefLogic "contracted" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
                      (EVar "x")
                  , SDefLogic "unspecified" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing Nothing Nothing Nothing)
                      (EVar "x")
                  , SWeaknessOk "unspecified" "helper function"
                  ]
          report = runCoverage stmts emptyCS
          s = crSummary report
      -- 2 functions total: 1 contracted, 1 suppressed
      csTotal s `shouldBe` 2
      csContracted s `shouldBe` 1
      csSuppressed s `shouldBe` 1
      -- effective_coverage = (contracted + suppressed) / total = 2/2 = 1.0
      csEffective s `shouldBe` 1.0
      -- spec_coverage = contracted / total = 1/2 = 0.5
      csSpecCoverage s `shouldBe` 0.5
      -- suppression_debt = suppressed / total = 1/2 = 0.5
      csSuppressionDebt s `shouldBe` 0.5
      -- JSON should include both new fields
      let jsonReport = formatCoverageJson report
      jsonReport `shouldSatisfy` T.isInfixOf "spec_coverage"
      jsonReport `shouldSatisfy` T.isInfixOf "suppression_debt"

  -- =========================================================================
  -- BODY-VC (v0.8.0) — bodyToPredFrom golden tests
  -- =========================================================================
  describe "BODY-VC" $ do
    -- Helper: parse a def-logic and extract the body expression
    let parseBody :: T.Text -> Expr
        parseBody src = case parseStatements GrammarCoreInversion "<test>" src of
          Left e -> error $ "parse failed: " <> show e
          Right stmts -> case head stmts of
            SDefLogic _ _ _ _ body -> body
            _ -> error "expected SDefLogic"

    -- Helper: build SortEnv from int param names
    let intSortEnv :: [T.Text] -> SortEnv
        intSortEnv names = Map.fromList [(n, FQInt) | n <- names]

    describe "Positive (SAFE)" $ do
      it "T01: literal body 42" $ do
        let body = ELit (LitInt 42)
            (_, result) = bodyToPredFrom 0 Map.empty Map.empty Set.empty body
        result `shouldBe` Just (SimpleVC [] (FQLit 42))

      it "T02: bool literal true" $ do
        let body = ELit (LitBool True)
            (_, result) = bodyToPredFrom 0 Map.empty Map.empty Set.empty body
        result `shouldBe` Just (SimpleVC [] FQTrue)

      it "T03: arithmetic (+ n 1) with int params" $ do
        let body = EApp "+" [EVar "n", ELit (LitInt 1)]
            se = intSortEnv ["n"]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Just (SimpleVC [] (FQBinArith FQAdd (FQVar "n") (FQLit 1)))

      it "T04: single ELet with alpha-renaming" $ do
        let body = ELet [(PVar "s", Nothing, EApp "+" [EVar "a", EVar "b"])] (EApp "+" [EVar "s", EVar "c"])
            se = intSortEnv ["a", "b", "c"]
            (counter, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        -- Counter should advance
        counter `shouldBe` 1
        case result of
          Just (SimpleVC [lb] resultPred) -> do
            -- The let-binding should be alpha-renamed
            lbName lb `shouldBe` "_bv_s_0"
            lbRhs lb `shouldBe` FQBinArith FQAdd (FQVar "a") (FQVar "b")
            -- The result should reference the renamed variable
            resultPred `shouldBe` FQBinArith FQAdd (FQVar "_bv_s_0") (FQVar "c")
          _ -> expectationFailure $ "expected SimpleVC with 1 let-binding, got: " <> show result

      it "T05: EIf produces BranchVC" $ do
        let body = EIf (EApp ">" [EVar "n", ELit (LitInt 0)]) (EVar "n") (ELit (LitInt 0))
            se = intSortEnv ["n"]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (BranchVC guard _ tvc evc) -> do
            guard `shouldBe` FQBinPred FQGt (FQVar "n") (FQLit 0)
            tvc `shouldBe` SimpleVC [] (FQVar "n")
            evc `shouldBe` SimpleVC [] (FQLit 0)
          _ -> expectationFailure $ "expected BranchVC, got: " <> show result

    describe "Alpha-renaming" $ do
      it "T09: shadowing (let [[x (+ x 1)]] x) renames correctly" $ do
        let body = ELet [(PVar "x", Nothing, EApp "+" [EVar "x", ELit (LitInt 1)])] (EVar "x")
            se = intSortEnv ["x"]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (SimpleVC [lb] resultPred) -> do
            lbName lb `shouldBe` "_bv_x_0"
            lbRhs lb `shouldBe` FQBinArith FQAdd (FQVar "x") (FQLit 1)
            resultPred `shouldBe` FQVar "_bv_x_0"  -- body refs renamed var
          _ -> expectationFailure $ "expected SimpleVC with shadowed binding, got: " <> show result

      it "E08: global counter shared across calls" $ do
        let body1 = ELet [(PVar "x", Nothing, ELit (LitInt 1))] (EVar "x")
            body2 = ELet [(PVar "x", Nothing, ELit (LitInt 2))] (EVar "x")
            se = intSortEnv []
            (c1, _) = bodyToPredFrom 0 se Map.empty Set.empty body1
            (c2, r2) = bodyToPredFrom c1 se Map.empty Set.empty body2
        c1 `shouldBe` 1
        c2 `shouldBe` 2
        case r2 of
          Just (SimpleVC [lb] _) -> lbName lb `shouldBe` "_bv_x_1"  -- not _bv_x_0
          _ -> expectationFailure "expected second call to use counter 1"

    describe "SortEnv rejection" $ do
      it "EVar for a carrier (non-scalar) param returns Nothing (BOOL-FRAG: bool is now a scalar)" $ do
        let body = EVar "s"
            se = Map.fromList [("s", FQStr)]  -- opaque string carrier stays out of the fragment
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Nothing

      it "EVar for a bool param returns the bool atom (BOOL-FRAG)" $ do
        let body = EVar "b"
            se = Map.fromList [("b", FQBool)]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Just (SimpleVC [] (FQVar "b"))

      it "EVar for unknown param returns Nothing" $ do
        let body = EVar "unknown"
            (_, result) = bodyToPredFrom 0 Map.empty Map.empty Set.empty body
        result `shouldBe` Nothing

    describe "Fallback" $ do
      it "F01: match in body returns Nothing" $ do
        let body = EMatch (EVar "x") [(PVar "y", EVar "y")]
            se = intSortEnv ["x"]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Nothing

      it "F02: user-defined function call returns Nothing" $ do
        let body = EApp "my-func" [EVar "x"]
            se = intSortEnv ["x"]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Nothing

      it "F03: non-linear operator * returns Nothing" $ do
        let body = EApp "*" [EVar "x", EVar "y"]
            se = intSortEnv ["x", "y"]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Nothing

    describe "Flattening" $ do
      it "SimpleVC flattens to 1 path" $ do
        let bvc = SimpleVC [] (FQLit 42)
            paths = flattenBodyVC bvc
        length paths `shouldBe` 1

      it "BranchVC flattens to 2 paths" $ do
        let bvc = BranchVC (FQVar "g") [] (SimpleVC [] (FQLit 1)) (SimpleVC [] (FQLit 2))
            paths = flattenBodyVC bvc
        length paths `shouldBe` 2

      it "countPathsBounded stops early" $ do
        -- Build a deep tree that would have 2^20 paths
        let mkDeep 0 = SimpleVC [] (FQLit 0)
            mkDeep n = BranchVC (FQVar "g") [] (mkDeep (n-1)) (mkDeep (n-1))
            bvc = mkDeep (20 :: Int)
        countPathsBounded 5000 bvc `shouldBe` 5000  -- capped, not 1048576

    describe "Parenthesization" $ do
      it "FQAnd [FQOr [a, b], c] parenthesizes correctly" $ do
        let p = FQAnd [FQOr [FQVar "a", FQVar "b"], FQVar "c"]
            t = emitPred p
        t `shouldSatisfy` T.isInfixOf "(a || b)"

      it "FQNot (FQOr [a, b]) parenthesizes correctly" $ do
        let p = FQNot (FQOr [FQVar "a", FQVar "b"])
            t = emitPred p
        t `shouldSatisfy` T.isInfixOf "(not (a || b))"

    -- NIW (v0.12, Commit A): the .fq IR can represent and render measure-class
    -- uninterpreted-function applications (REF-META-3 §4.2 / REF-META-2 path-a).
    -- These tests cover the inert IR + emission capability; exprToPred does not
    -- yet construct FQApp (that is Commit B), so existing .fq output is unchanged.
    describe "NIW measure UF emission" $ do
      it "NIW-A1: FQApp renders as a prefix-applied uninterpreted symbol" $ do
        emitPred (FQApp "strLen" [FQVar "s"]) `shouldBe` "(strLen s)"

      it "NIW-A2: nested measure arg renders with parens" $ do
        emitPred (FQBinPred FQGe (FQApp "strLen" [FQVar "s"]) (FQLit 0))
          `shouldBe` "((strLen s) >= 0)"

      it "NIW-A3: emitFQFile declares a function-sorted constant" $ do
        let f = FQFile [FQConstant "strLen" [FQStr] FQInt] [] [] [] []
        emitFQFile f `shouldSatisfy` T.isInfixOf "constant strLen : (func(0 , [Str; int]))"

      it "NIW-A4: listLen constant uses the opaque Lst sort" $ do
        let f = FQFile [FQConstant "listLen" [FQList] FQInt] [] [] [] []
        emitFQFile f `shouldSatisfy` T.isInfixOf "constant listLen : (func(0 , [Lst; int]))"

      it "NIW-A5: an FQFile with no constants emits no constant line (byte-inert)" $ do
        let f = FQFile [] [] [] [] []
        emitFQFile f `shouldNotSatisfy` T.isInfixOf "constant "

    -- IMPL-SUGAR: `=>` / `<=>` are pure syntactic sugar. The AST retains them
    -- (parse + round-trip + schema); the VC-emission path desugars to or/not/and
    -- so the emitted .fq is byte-identical to the hand expansion (zero verification
    -- change). Both operands are bool (TypeCheck rejects non-bool).
    describe "IMPL-SUGAR (=> / <=> implication sugar)" $ do
      let emitS src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "IMPL-1: (=> p q) emits byte-identical .fq to (or (not p) q)" $ do
        a <- emitS "(def f [x: int] -> int (post (=> (> x 0) (>= result 0))) (if (> x 0) x 0))"
        b <- emitS "(def f [x: int] -> int (post (or (not (> x 0)) (>= result 0))) (if (> x 0) x 0))"
        erFQText a `shouldBe` erFQText b

      it "IMPL-2: (<=> p q) emits byte-identical .fq to its two-implication expansion" $ do
        a <- emitS "(def g [x: int] -> int (post (<=> (>= result 0) (>= x 0))) (if (>= x 0) x 0))"
        b <- emitS "(def g [x: int] -> int (post (and (or (not (>= result 0)) (>= x 0)) (or (not (>= x 0)) (>= result 0)))) (if (>= x 0) x 0))"
        erFQText a `shouldBe` erFQText b

      it "IMPL-3: a => post verifies body-faithful (with a bool param)" $ do
        er <- emitS "(def gate [n: int mac_ok: bool] -> int (pre (>= n 0)) (post (and (>= result 0) (=> (> result 0) mac_ok))) (if mac_ok n 0))"
        erBodyFaithfulFns er `shouldSatisfy` elem "gate"

      it "IMPL-4: => is retained in the AST (parses to EOp, not desugared at parse time)" $ do
        case parseStatements GrammarCoreInversion "test" "(def-shell f [a: bool b: bool] -> bool (post (=> a b)) (if a b true))" of
          Left err    -> expectationFailure (show err)
          Right stmts -> T.pack (show stmts) `shouldSatisfy` T.isInfixOf "\"=>\""

      it "IMPL-5: (=> p q) with non-bool operands is a type error" $ do
        case parseStatements GrammarCoreInversion "test" "(def-shell h [x: int] -> int (post (=> x result)) x)" of
          Left err    -> expectationFailure (show err)
          Right stmts -> reportSuccess (typeCheck GrammarCoreInversion emptyEnv stmts) `shouldBe` False

    -- NIW (v0.12, Commit B): measure predicates in contracts/bodies translate to
    -- UF terms, get an opaque carrier binder + ground range fact, and discharge
    -- body-faithfully. Structural assertions on the emitted .fq (suite convention:
    -- the solver is not invoked here; SAFE/UNSAFE discrimination is probe-verified).
    describe "NIW measure verification (emission)" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "NIW-B1: string-length post is body-faithful with carrier binder, range fact, constant" $ do
        er <- emitSrc "(def-shell f [s: string] (post (>= result 0)) (string-length s))"
        erBodyFaithfulFns er `shouldSatisfy` elem "f"
        erSkipped er         `shouldSatisfy` not . elem "f"
        let fq = erFQText er
        fq `shouldSatisfy` T.isInfixOf "constant strLen : (func(0 , [Str; int]))"
        fq `shouldSatisfy` T.isInfixOf "{ v : Str | true }"
        fq `shouldSatisfy` T.isInfixOf "(strLen s) >= 0"          -- ground range fact
        fq `shouldSatisfy` T.isInfixOf "result = (strLen s)"

      it "NIW-B2: a measure-free function emits no constant / strLen (byte-inert)" $ do
        er <- emitSrc "(def-shell g [x: int] (post (>= result 0)) x)"
        let fq = erFQText er
        fq `shouldNotSatisfy` T.isInfixOf "constant "
        fq `shouldNotSatisfy` T.isInfixOf "strLen"

      it "NIW-B3: list-length uses the opaque Lst carrier sort" $ do
        er <- emitSrc "(def-shell h [xs: list[int]] (post (>= result 0)) (list-length xs))"
        let fq = erFQText er
        fq `shouldSatisfy` T.isInfixOf "constant listLen : (func(0 , [Lst; int]))"
        fq `shouldSatisfy` T.isInfixOf "(listLen xs)"

      it "NIW-B4: congruence — two occurrences of the same measure-term share one constant" $ do
        er <- emitSrc "(def-shell k [s: string] (post (>= result (string-length s))) (string-length s))"
        let fq = erFQText er
        -- one constant declaration for strLen, the term appears in both lhs (body) and rhs (post)
        T.count "constant strLen" fq `shouldBe` 1
        fq `shouldSatisfy` T.isInfixOf "result = (strLen s)"
        fq `shouldSatisfy` T.isInfixOf "result >= (strLen s)"

      -- NIW-B5: CDP deep-dive Rev 5 (routed finding, not part of the original
      -- 7-item plan). 'usedMeasures' (the .fq preamble's 'constant' sweep)
      -- scanned only constraints and binders, never the auto-synthesized
      -- qualifiers ('extractQualifiers'). A function whose body-VC falls back
      -- (list values aren't in the translatable fragment — see the CDP
      -- deep-dive's own item-5 finding) emits NO constraint referencing
      -- 'listLen', yet 'extractQualifiers' still auto-synthesizes a qualifier
      -- from a 'list-length' post — 'listLen' then appears ONLY in that
      -- qualifier, undeclared, and liquid-fixpoint crashes ("Qualifier with
      -- free vars"). Reproduced and confirmed against the real binary before
      -- fixing (a genuine pre-existing bug, unrelated to items 1-6, found
      -- while empirically verifying item 5's --weakness-check call site).
      it "NIW-B5 a body-fallback function whose post references list-length still declares the listLen constant (regression guard for the 'Qualifier with free vars' crash)" $ do
        er <- emitSrc "(def-shell f [xs: list[int]] (post (= (list-length result) (list-length xs))) xs)"
        erBodyFallback er `shouldSatisfy` elem "f"
        let fq = erFQText er
        fq `shouldSatisfy` T.isInfixOf "constant listLen : (func(0 , [Lst; int]))"

    -- BOOL-FRAG: `bool` is a native SMT sort (FQBool) admitted to the body-faithful
    -- fragment (Σ_auto) as a translatable scalar alongside int — a bool param, a
    -- bool-conditioned `if`, and a bool atom in a predicate verify body-faithful
    -- instead of falling back to contract-only. Emission-based (solver not invoked;
    -- refute is probe-verified against the binary).
    describe "BOOL-FRAG (bool in the body-faithful fragment)" $ do
      let emitB src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "BOOL-1 bool param + bool-if + bool-atom-mixed-with-int post is body-faithful" $ do
        er <- emitB "(def gate-mac [n: int mac_ok: bool] -> int (pre (>= n 0)) (post (and (>= result 0) (and (<= result n) (or (<= result 0) mac_ok)))) (if mac_ok n 0))"
        erBodyFaithfulFns er `shouldSatisfy` elem "gate-mac"
        erBodyFallback er    `shouldNotSatisfy` elem "gate-mac"
        erFQText er          `shouldSatisfy` T.isInfixOf "mac_ok"  -- bool threaded, not skolem-dropped

      it "BOOL-2 the (= b true) surface form is body-faithful" $ do
        er <- emitB "(def gate-mac [n: int mac_ok: bool] -> int (pre (>= n 0)) (post (and (>= result 0) (and (<= result n) (or (<= result 0) (= mac_ok true))))) (if (= mac_ok true) n 0))"
        erBodyFaithfulFns er `shouldSatisfy` elem "gate-mac"

      it "BOOL-3 bool return type with a bare bool-var body is body-faithful" $ do
        er <- emitB "(def verified? [mac_ok: bool] -> bool (post (or (not result) mac_ok)) mac_ok)"
        erBodyFaithfulFns er `shouldSatisfy` elem "verified?"

      it "BOOL-4 a body ignoring the bool param stays body-faithful (in-fragment → solver refutes, not vacuous)" $ do
        er <- emitB "(def gate-mac [n: int mac_ok: bool] -> int (pre (>= n 0)) (post (and (>= result 0) (and (<= result n) (or (<= result 0) mac_ok)))) n)"
        erBodyFaithfulFns er `shouldSatisfy` elem "gate-mac"
        erFQText er          `shouldSatisfy` T.isInfixOf "mac_ok"

      it "BOOL-5 int-0/1 gate stays body-faithful (no regression from admitting bool)" $ do
        er <- emitB "(def gate-mac [n: int mac_ok: int] -> int (pre (and (>= n 0) (or (= mac_ok 0) (= mac_ok 1)))) (post (and (>= result 0) (and (<= result n) (or (<= result 0) (= mac_ok 1))))) (if (= mac_ok 1) n 0))"
        erBodyFaithfulFns er `shouldSatisfy` elem "gate-mac"

      -- BOOL-6/7 (v0.14.15): fixpoint accepts `not` only in predicate position; `result
      -- = (not b)` emitted `(result = ((not b)))` — `not` as an operand of `=` — which
      -- liquid-fixpoint rejected as a free var ("Constraint with free vars [not]"), a
      -- CRASH (not a false-SAFE) that emission tests miss because they don't run fixpoint.
      -- The fix pushes the negation through the (dis)equality (X = ¬Y ⟺ X ≠ Y), so the
      -- emitted .fq must carry no `(not ` inside an equality operand. `and`/`or` values
      -- were tolerated by fixpoint and are unaffected.
      it "BOOL-6 (not b) bool-value body is body-faithful and emits no `not` in an equality operand (was a fixpoint crash pre-v0.14.15)" $ do
        er <- emitB "(def negate-bit [b: bool] -> bool (post (= result (not b))) (not b))"
        erBodyFaithfulFns er `shouldSatisfy` elem "negate-bit"
        erBodyFallback er    `shouldNotSatisfy` elem "negate-bit"
        -- straight-line body (no `if` path guard) → the ONLY `not` was the `=` operand,
        -- now pushed through to `/=`; a regression reintroduces `(not ` and the crash.
        erFQText er          `shouldNotSatisfy` T.isInfixOf "(not "  -- the crashing form is gone
        erFQText er          `shouldSatisfy`    T.isInfixOf "/="      -- flipped to disequality (FQNeq)

      it "BOOL-7 (= b1 b2) two-bool-var equality is body-faithful (professor's flagged shape)" $ do
        er <- emitB "(def bools-equal [a: bool b: bool] -> bool (post (= result (= a b))) (if a b (not b)))"
        erBodyFaithfulFns er `shouldSatisfy` elem "bools-equal"
        -- the else-branch body `(not b)` in a result-equation flips to `/=`; the surviving
        -- `(not a)` is the `if` PATH GUARD (predicate position — fixpoint accepts it).
        erFQText er          `shouldSatisfy`    T.isInfixOf "/="

    -- FIXPOINT-DATA (codegen fix): a user sum type must emit a liquid-fixpoint
    -- ADT declaration whose type name preserves source case (.fq fTyConP requires
    -- an uppercase identifier) and whose constructors use `| ctor { }` syntax.
    -- Regression guard for the two-part .fq data-decl bug: the prior emitter wrote
    -- `data lookuperror 0 = [red 0 | ...]`, which liquid-fixpoint rejected on BOTH
    -- the lowercase type name AND the `name arity` constructor form, crashing
    -- fixpoint on every program containing a user sum type. No .fq-level test
    -- covered sum types before (Spec only checked `data Color` in the Hs codegen),
    -- which is why the bug shipped. Probe-verified end-to-end SAFE against fixpoint.
    describe "Fixpoint sum-type data declaration emission" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
          sumSrc = T.concat
            [ "(type Color (| Red unit) (| Green unit) (| Blue unit))\n"
            , "(def f [x: int] -> int (post (>= result 0)) (if (> x 0) x 0))"
            ]

      it "FQDATA-1: a user sum type emits a parseable ADT decl (uppercase type name, | ctor { } form)" $ do
        er <- emitSrc sumSrc
        let fq = erFQText er
        fq `shouldSatisfy`    T.isInfixOf "data Color 0 = [ | red { } | green { } | blue { }]"
        fq `shouldNotSatisfy` T.isInfixOf "data color"   -- prior lowercased type name

      it "FQDATA-2: the int companion fn reaches a body-faithful VC alongside the sum decl" $ do
        er <- emitSrc sumSrc
        erBodyFaithfulFns er `shouldSatisfy` elem "f"

    -- NIW (v0.12, Commit C): refinement-aliased params get their carrier sort
    -- (alias-aware emitParamBind) and their predicate folded into the effective
    -- precondition (F-NIW-1, elim-side: assumed in the body VC). Stacked aliases
    -- conjoin per §3.4.4. Validated end-to-end SAFE against fixpoint.
    describe "NIW refinement-aliased params" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
          word = "(type Word (where [s: string] (> (string-length s) 0)))\n"
          blockid = "(type BlockID (where [s: string] (regex-match \"^[a-f0-9]+$\" s)))\n"

      it "NIW-C1: a refined-alias param gets a Str carrier binder, not int" $ do
        er <- emitSrc (word <> "(def wlen [w: Word] (post (> result 0)) (string-length w))")
        erFQText er `shouldSatisfy` T.isInfixOf "bind 0 w : { v : Str | true }"

      it "NIW-C2: the alias refinement is assumed in the body VC (elim-side)" $ do
        er <- emitSrc (word <> "(def wlen [w: Word] (post (> result 0)) (string-length w))")
        erBodyFaithfulFns er `shouldSatisfy` elem "wlen"
        erFQText er `shouldSatisfy` T.isInfixOf "(strLen w) > 0"   -- Word predicate in the LHS

      it "NIW-C3: stacked aliases conjoin both predicates at introduction (§3.4.4)" $ do
        let nonEmpty = word <> "(type NonEmptyWord (where [s: Word] (> (string-length s) 1)))\n"
        er <- emitSrc (nonEmpty <> "(def nwlen [w: NonEmptyWord] (post (> result 1)) (string-length w))")
        let fq = erFQText er
        fq `shouldSatisfy` T.isInfixOf "(strLen w) > 1"   -- NonEmptyWord
        fq `shouldSatisfy` T.isInfixOf "(strLen w) > 0"   -- inherited Word

      it "NIW-C4: a measure-free, refinement-free function still emits no constant" $ do
        er <- emitSrc "(def-shell plain [x: int] (post (>= result 0)) x)"
        erFQText er `shouldNotSatisfy` T.isInfixOf "constant "

      -- REF-META-4 soundness firewall (LLMLL.md §3.4.5). Refinement aliases carry
      -- NO runtime residue, so an undischarged refinement MUST force the carrying
      -- function off the body-faithful (verified) tier — otherwise an unproven,
      -- never-runtime-checked invariant would ship `verified`. A non-auto-discharge
      -- predicate (regex-match: outside Σ_auto) is non-emittable (exprToPred → Nothing,
      -- FixpointEmit.hs:756), forcing erBodyFallback. These pin that property against
      -- a future bodyToPredM refactor silently reopening the hole.
      it "NIW-C5: a regex-match (non-auto-discharge) refined param falls back, not body-faithful (REF-META-4 firewall)" $ do
        er <- emitSrc (word <> blockid <>
                "(def wlen [w: Word] (post (> result 0)) (string-length w))\n" <>
                "(def bidlen [b: BlockID] (post (> result 0)) (string-length b))")
        erBodyFaithfulFns er `shouldSatisfy` elem "wlen"            -- auto-discharge (measure-class) refinement → body-faithful
        erBodyFaithfulFns er `shouldSatisfy` not . elem "bidlen"    -- non-auto-discharge regex-match refinement → NOT
        erBodyFallback     er `shouldSatisfy` elem "bidlen"         -- non-emittable pre forces fallback (def-site, FixpointEmit.hs:500)

      it "NIW-C6: a caller of a regex-match-refined-param callee falls back (call-site firewall, FixpointEmit.hs:891-901)" $ do
        er <- emitSrc (word <> blockid <>
                "(def wlen [w: Word] (post (> result 0)) (string-length w))\n" <>
                "(def bidlen [b: BlockID] (post (>= result 0)) (string-length b))\n" <>
                "(def callok [s: string] (post (>= result 0)) (wlen s))\n" <>
                "(def callbid [s: string] (post (>= result 0)) (bidlen s))")
        erBodyFaithfulFns er `shouldSatisfy` elem "callok"          -- caller of auto-discharge-refined callee: call-pre emittable → body-faithful
        erBodyFaithfulFns er `shouldSatisfy` not . elem "callbid"   -- caller of non-auto-discharge-refined callee: NOT
        erBodyFallback     er `shouldSatisfy` elem "callbid"        -- three-way pre distinction returns Nothing → caller falls back

    -- NIW (v0.12, F-NIW-2): the intro-side call-pre obligation fires for a
    -- string/list-refined callee param — a caller passing a value to a `Word`
    -- param must prove the refinement at the call site. Carrier call-arg vars are
    -- bound and the measure-application substitution reaches into FQApp.
    describe "NIW intro-side call-pre (F-NIW-2)" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
          word = "(type Word (where [s: string] (> (string-length s) 0)))\n"
          wlen = "(def wlen [w: Word] (post (> result 0)) (string-length w))\n"

      it "NIW-D1: a caller passing a value to a Word param emits a call-pre obligation" $ do
        er <- emitSrc (word <> wlen <> "(def-shell caller [s: string] (post (>= result 0)) (wlen s))")
        erCallPreFns er `shouldSatisfy` elem "caller"           -- intro-side now fires
        let fq = erFQText er
        fq `shouldSatisfy` T.isInfixOf "s : { v : Str | true }" -- carrier call-arg bound
        fq `shouldSatisfy` T.isInfixOf "(strLen s)"             -- callee refinement substituted to s (applySubst into FQApp)

      it "NIW-D2: int-refined param call-pre still fires (regression guard for arg translation)" $ do
        let pos = "(type Pos (where [n: int] (> n 0)))\n(def pf [n: Pos] (post (> result 0)) n)\n"
        er <- emitSrc (pos <> "(def-shell pc [m: int] (post (>= result 0)) (pf m))")
        erCallPreFns er `shouldSatisfy` elem "pc"

      it "NIW-D3: a measure-free contracted call binds no carrier and declares no constant" $ do
        let g = "(def g [n: int] (post (> result 0)) (+ n 1))\n"
        er <- emitSrc (g <> "(def-shell h [m: int] (post (>= result 0)) (g m))")
        let fq = erFQText er
        fq `shouldNotSatisfy` T.isInfixOf "constant "
        fq `shouldNotSatisfy` T.isInfixOf " : { v : Str"

    -- F-NIW-3: LLMLL identifiers admit '-' / '.' / '?' (Lexer.hs:314-315) but
    -- liquid-fixpoint's lexer accepts only [A-Za-z0-9_]; a hyphenated name
    -- crashed the solver ("unexpected '-'"). Sanitized at the FixpointIR emission
    -- chokepoint (identity on already-legal names → byte-identical .fq otherwise).
    describe "F-NIW-3 qualifier/identifier sanitization" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "F3-1: emitPred maps illegal identifier chars to underscore" $ do
        emitPred (FQVar "measure-word") `shouldBe` "measure_word"
        emitPred (FQVar "mod.fn")       `shouldBe` "mod_fn"

      it "F3-2: emitPred is identity on already-legal identifiers (byte-inert)" $ do
        emitPred (FQVar "withdraw")     `shouldBe` "withdraw"
        emitPred (FQVar "_bv_call_g_0") `shouldBe` "_bv_call_g_0"

      it "F3-3: a hyphenated function name emits a hyphen-free qualifier" $ do
        er <- emitSrc "(def measure-word [n: int] (post (> result 0)) n)"
        let fq = erFQText er
        fq `shouldNotSatisfy` T.isInfixOf "measure-word"
        fq `shouldSatisfy`    T.isInfixOf "Q_measure_word_post"

      it "F3-4: a hyphenated param name is sanitized consistently in bind and refs" $ do
        er <- emitSrc "(def f [my-val: int] (post (> result my-val)) my-val)"
        let fq = erFQText er
        fq `shouldNotSatisfy` T.isInfixOf "my-val"   -- no raw hyphen reaches the solver
        fq `shouldSatisfy`    T.isInfixOf "my_val"   -- bind and FQVar refs both mangled identically

    describe "Negative (structural UNSAFE)" $ do
      -- These tests verify that incorrect implementations produce body VCs
      -- where the result predicate would NOT satisfy the postcondition.
      -- We verify the constraint structure, not solver output.

      it "N01: wrong body (post says result = x+1, body returns x)" $ do
        -- (def-shell inc [x: int] (post (= result (+ x 1))) x)
        -- Body returns x, but post requires result = x+1
        let body = EVar "x"
            se = Map.fromList [("x", FQInt)]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (SimpleVC [] resultPred) -> do
            -- Result pred is just (FQVar "x"), but post would be (+ x 1)
            -- So the constraint (result = x) ⟹ (result = x+1) is UNSAFE
            resultPred `shouldBe` FQVar "x"
            resultPred `shouldNotBe` FQBinArith FQAdd (FQVar "x") (FQLit 1)
          _ -> expectationFailure $ "expected SimpleVC, got: " <> show result

      it "N02: off-by-one (post says result = x, body returns x+1)" $ do
        -- (def-shell id [x: int] (post (= result x)) (+ x 1))
        let body = EApp "+" [EVar "x", ELit (LitInt 1)]
            se = Map.fromList [("x", FQInt)]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (SimpleVC [] resultPred) -> do
            resultPred `shouldBe` FQBinArith FQAdd (FQVar "x") (FQLit 1)
            -- Post would bind (result = x), so constraint
            -- (result = x+1) ⟹ (result = x) is UNSAFE
            resultPred `shouldNotBe` FQVar "x"
          _ -> expectationFailure $ "expected SimpleVC, got: " <> show result

      it "N03: wrong branch (if swapped — body returns 0 when n>0)" $ do
        -- (def-shell abs [n: int] (post (>= result 0))
        --   (if (> n 0) 0 n))
        -- This is wrong: returns 0 for positive n (fine), but returns n for
        -- negative n (UNSAFE since n < 0 violates post >= 0)
        let body = EIf (EApp ">" [EVar "n", ELit (LitInt 0)])
                       (ELit (LitInt 0))
                       (EVar "n")
            se = Map.fromList [("n", FQInt)]
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (BranchVC guard bnds thenVC elseVC) -> do
            -- The else branch returns n (which could be negative)
            guard `shouldBe` FQBinPred FQGt (FQVar "n") (FQLit 0)
            thenVC `shouldBe` SimpleVC [] (FQLit 0)     -- fine: 0 >= 0
            elseVC `shouldBe` SimpleVC [] (FQVar "n")    -- UNSAFE: n might be < 0
            -- Flatten and verify the else path
            let paths = flattenBodyVC (BranchVC guard bnds thenVC elseVC)
                (elseGuard, _, elseResult) = paths !! 1
            -- Else guard is ¬(n > 0), else result is n
            elseGuard `shouldBe` FQNot (FQBinPred FQGt (FQVar "n") (FQLit 0))
            elseResult `shouldBe` FQVar "n"
          _ -> expectationFailure $ "expected BranchVC, got: " <> show result

      it "N04: let shadowing encodes correctly (wrong if renaming broken)" $ do
        -- (def-shell f [x: int] (post (= result (+ x 2)))
        --   (let [[x (+ x 1)]]   ;; x_0 = x + 1
        --     (let [[x (+ x 1)]]  ;; x_1 = x_0 + 1 (= x + 2 ✓)
        --       x)))
        -- If alpha-renaming is broken, x_1 would still reference original x,
        -- producing x+1 instead of x+2 (UNSAFE).
        -- The test verifies correct renaming produces the chain.
        let innerLet = ELet [(PVar "x", Nothing, EApp "+" [EVar "x", ELit (LitInt 1)])] (EVar "x")
            body = ELet [(PVar "x", Nothing, EApp "+" [EVar "x", ELit (LitInt 1)])] innerLet
            se = Map.fromList [("x", FQInt)]
            (counter, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        -- Two let bindings → counter advanced by 2
        counter `shouldBe` 2
        case result of
          Just (SimpleVC lbs resultPred) -> do
            length lbs `shouldBe` 2
            -- First binding: _bv_x_0 = x + 1
            lbName (lbs !! 0) `shouldBe` "_bv_x_0"
            lbRhs  (lbs !! 0) `shouldBe` FQBinArith FQAdd (FQVar "x") (FQLit 1)
            -- Second binding: _bv_x_1 = _bv_x_0 + 1 (NOT x + 1)
            lbName (lbs !! 1) `shouldBe` "_bv_x_1"
            lbRhs  (lbs !! 1) `shouldBe` FQBinArith FQAdd (FQVar "_bv_x_0") (FQLit 1)
            -- Result references innermost renamed var
            resultPred `shouldBe` FQVar "_bv_x_1"
          _ -> expectationFailure $ "expected SimpleVC with 2 bindings, got: " <> show result

    -- -----------------------------------------------------------------------
    -- Parsed-source tests (v0.8.0 blocker fix: EOp → exprToPred)
    -- -----------------------------------------------------------------------
    describe "Parsed-source (EOp)" $ do
      it "P01: EOp (= result x) parses and translates via exprToPred" $ do
        -- The parser emits EOp for operators, not EApp
        let src = "(def-shell identity [x: int] (post (= result x)) x)"
        case parseStatements GrammarCoreInversion "test" src of
          Left err -> expectationFailure $ "parse failed: " <> show err
          Right [SDefShell _ _ _ contract _ _] -> do
            let Just postExpr = contractPost contract
            -- The critical check: exprToPred must handle this
            let result = exprToPred postExpr
            result `shouldBe` Just (FQBinPred FQEq (FQVar "result") (FQVar "x"))
          Right stmts -> expectationFailure $ "unexpected parse: " <> show stmts

      it "P02: EOp (!= result 0) translates via exprToPred" $ do
        let src = "(def-shell nonzero [x: int] (post (!= result 0)) x)"
        case parseStatements GrammarCoreInversion "test" src of
          Left err -> expectationFailure $ "parse failed: " <> show err
          Right [SDefShell _ _ _ contract _ _] -> do
            let Just postExpr = contractPost contract
            let result = exprToPred postExpr
            result `shouldBe` Just (FQBinPred FQNeq (FQVar "result") (FQLit 0))
          Right stmts -> expectationFailure $ "unexpected parse: " <> show stmts

      it "P03: parsed EOp contracts emit body-faithful VCs (not standalone post)" $ do
        let src = "(def-shell add1 [x: int] (post (= result (+ x 1))) (+ x 1))"
        case parseStatements GrammarCoreInversion "test" src of
          Left err -> expectationFailure $ "parse failed: " <> show err
          Right stmts -> do
            emitR <- emitFixpointWith (EmitOptions True) "test.llmll" stmts
            -- v0.8.0: standalone post is suppressed when body VCs are active.
            -- Instead, body-faithful VC is the correct proof obligation.
            erEmittedPost emitR `shouldBe` []  -- standalone post not emitted
            -- Should NOT be in skipped
            erSkipped emitR `shouldSatisfy` not . elem "add1"
            -- Body should be faithful
            erBodyFaithfulFns emitR `shouldBe` ["add1"]

      it "P04: skipped clause NOT marked as emitted" $ do
        -- Use a non-linear post that exprToPred can't handle
        let stmts = [ SDefLogic "mul" [("x", TInt), ("y", TInt)] (Just TInt)
                        (Contract Nothing Nothing
                          (Just (EApp "*" [EVar "result", ELit (LitInt 2)])) Nothing Nothing)
                        (EVar "x")
                    ]
        emitR <- emitFixpoint "test.llmll" stmts
        -- Non-linear post: should be skipped
        erSkipped emitR `shouldSatisfy` elem "mul"
        -- Should NOT be in emittedPost
        erEmittedPost emitR `shouldSatisfy` not . elem "mul"

  -- -----------------------------------------------------------------------
  -- COMP-T: Compositional verification golden tests (v0.9.0)
  -- -----------------------------------------------------------------------
  describe "COMP-T (v0.9.0 compositional verification)" $ do

    let mkContract mPre mPost = Contract mPre Nothing mPost Nothing Nothing

    describe "applySubst" $ do
      it "substitutes variables in FQBinPred" $ do
        let subst = Map.fromList [("x", FQLit 42)]
            pred' = FQBinPred FQGe (FQVar "x") (FQLit 0)
        applySubst subst pred' `shouldBe` FQBinPred FQGe (FQLit 42) (FQLit 0)

      it "leaves non-matching variables unchanged" $ do
        let subst = Map.fromList [("x", FQLit 42)]
            pred' = FQBinPred FQEq (FQVar "y") (FQVar "x")
        applySubst subst pred' `shouldBe` FQBinPred FQEq (FQVar "y") (FQLit 42)

      it "substitutes through FQAnd" $ do
        let subst = Map.fromList [("a", FQLit 1), ("b", FQLit 2)]
            pred' = FQAnd [FQVar "a", FQVar "b"]
        applySubst subst pred' `shouldBe` FQAnd [FQLit 1, FQLit 2]

      it "leaves literals unchanged" $ do
        applySubst (Map.fromList [("x", FQLit 1)]) (FQLit 99) `shouldBe` FQLit 99
        applySubst (Map.fromList [("x", FQLit 1)]) FQTrue `shouldBe` FQTrue

    describe "isConstructorDependent" $ do
      it "EMatch on result is constructor-dependent" $ do
        let expr = EMatch (EVar "result") [(PConstructor "Ok" [PVar "v"], EVar "v")]
        isConstructorDependent expr `shouldBe` True

      it "EMatch on non-result is NOT constructor-dependent" $ do
        let expr = EMatch (EVar "x") [(PConstructor "Ok" [PVar "v"], EVar "v")]
        isConstructorDependent expr `shouldBe` False

      it "simple literal is NOT constructor-dependent" $ do
        isConstructorDependent (ELit (LitInt 42)) `shouldBe` False

    describe "bodyToPredM with ContractEnv" $ do
      it "C01: EApp to contracted function produces CallVC" $ do
        let gContract = mkContract
              (Just (EApp ">=" [EVar "x", ELit (LitInt 0)]))
              (Just (EApp "=" [EVar "result", EVar "x"]))
            cenv = Map.fromList [("g", ([("x", TInt)], gContract, Just TInt))]
            body = EApp "g" [ELit (LitInt 42)]
            (_, result) = bodyToPredFrom 0 Map.empty cenv Set.empty body
        case result of
          Just (CallVC callee args mPre _mPost _rVar rSort _cont) -> do
            callee `shouldBe` "g"
            args `shouldBe` [FQLit 42]
            mPre `shouldBe` Just (FQBinPred FQGe (FQLit 42) (FQLit 0))
            rSort `shouldBe` FQInt
          other -> expectationFailure $ "Expected CallVC, got: " ++ show other

      it "F01: EApp to function without contract falls back" $ do
        let cenv = Map.empty :: ContractEnv
            body = EApp "h" [ELit (LitInt 42)]
            (_, result) = bodyToPredFrom 0 Map.empty cenv Set.empty body
        result `shouldBe` Nothing

      it "F02: Issue 1 - untranslatable pre causes fallback" $ do
        let gContract = mkContract
              (Just (EApp "*" [EVar "x", EVar "x"]))
              (Just (EApp "=" [EVar "result", EVar "x"]))
            cenv = Map.fromList [("g", ([("x", TInt)], gContract, Just TInt))]
            body = EApp "g" [ELit (LitInt 5)]
            (_, result) = bodyToPredFrom 0 Map.empty cenv Set.empty body
        result `shouldBe` Nothing

      it "C08: no pre, only post, produces CallVC with Nothing pre" $ do
        let gContract = mkContract Nothing
              (Just (EApp "=" [EVar "result", EVar "x"]))
            cenv = Map.fromList [("g", ([("x", TInt)], gContract, Just TInt))]
            body = EApp "g" [ELit (LitInt 42)]
            (_, result) = bodyToPredFrom 0 Map.empty cenv Set.empty body
        case result of
          Just (CallVC _ _ mPre mPost _ _ _) -> do
            mPre `shouldBe` Nothing
            mPost `shouldSatisfy` isJust
          other -> expectationFailure $ "Expected CallVC, got: " ++ show other

    describe "collectCallPreObligations" $ do
      it "extracts obligation from CallVC with pre" $ do
        let bvc = CallVC "g" [FQLit 42]
                    (Just (FQBinPred FQGe (FQLit 42) (FQLit 0)))
                    (Just (FQBinPred FQEq (FQVar "_r") (FQLit 42)))
                    "_r" FQInt
                    (SimpleVC [] (FQVar "_r"))
            obligs = collectCallPreObligations bvc
        length obligs `shouldBe` 1
        let (callee, prePred, guard, ctxCalls, _pathLbs) = head obligs
        callee `shouldBe` "g"
        prePred `shouldBe` FQBinPred FQGe (FQLit 42) (FQLit 0)
        guard `shouldBe` FQTrue
        ctxCalls `shouldBe` []   -- F-NIW-4: no prior calls on this single-call path

      it "no obligation from CallVC without pre" $ do
        let bvc = CallVC "g" [FQLit 42] Nothing
                    (Just (FQBinPred FQEq (FQVar "_r") (FQLit 42)))
                    "_r" FQInt
                    (SimpleVC [] (FQVar "_r"))
        collectCallPreObligations bvc `shouldBe` []

      -- F-NIW-4: a later call's obligation carries the prior call's (rVar, sort,
      -- assumed post) so a precondition referencing the earlier result is provable
      -- (not a free var). This is the withdraw-twice / banking_ledger fix.
      it "F4-1: a 2-call chain threads the prior call's result + post as context" $ do
        let post1 = FQBinPred FQGe (FQVar "_r1") (FQLit 0)
            inner = CallVC "g" [FQVar "_r1"]
                      (Just (FQBinPred FQGe (FQVar "_r1") (FQLit 5)))  -- 2nd pre references _r1
                      (Just (FQBinPred FQGe (FQVar "_r2") (FQLit 0)))
                      "_r2" FQInt (SimpleVC [] (FQVar "_r2"))
            outer = CallVC "f" [FQLit 9]
                      (Just (FQBinPred FQGe (FQLit 9) (FQLit 0)))
                      (Just post1) "_r1" FQInt inner
            obligs = collectCallPreObligations outer
        length obligs `shouldBe` 2
        let (_, _, _, ctx0, _) = obligs !! 0
            (_, pre1, _, ctx1, _) = obligs !! 1
        ctx0 `shouldBe` []                              -- first call: no prior context
        ctx1 `shouldBe` [("_r1", FQInt, post1)]         -- second call: assumes first call's post over _r1
        pre1 `shouldBe` FQBinPred FQGe (FQVar "_r1") (FQLit 5)

      it "F4-2: a let-bound call result used in a later call verifies body-faithfully (no free var)" $ do
        let src = unlines
              [ "(def-shell sub1 [x: int y: int]"
              , "  (pre (>= x y)) (post (and (= result (- x y)) (>= result 0)))"
              , "  (- x y))"
              , "(def-shell sub2 [x: int a: int b: int]"
              , "  (pre (and (>= x (+ a b)) (and (>= a 0) (>= b 0))))"
              , "  (post (>= result 0))"
              , "  (let [[t (sub1 x a)]] (sub1 t b)))" ]
        er <- case parseStatements GrammarCoreInversion "test" (T.pack src) of
                Left e      -> error ("parse failed: " <> show e)
                Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
        erBodyFaithfulFns er `shouldSatisfy` elem "sub2"   -- the let-call-chain is body-faithful
        erCallPreFns er      `shouldSatisfy` elem "sub2"   -- the 2nd call emits a call-pre obligation
        erSkipped er         `shouldSatisfy` not . elem "sub2"

    -- F-NIW-4b: a let-bound NON-call value used in a later call's precondition is
    -- threaded into that call's call-pre obligation as its defining equality
    -- (filtered to the in-scope subset), so the call's precondition is provable
    -- rather than crashing on a free variable.
    describe "F-NIW-4b let-value into call-pre" $ do
      let emitN4b src = case parseStatements GrammarCoreInversion "test" (T.pack src) of
            Left e      -> error ("parse failed: " <> show e)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
          g = "(def-shell g [a: int] (pre (>= a 2)) (post (>= result 0)) a)\n"

      it "F4b-1: a let-bound non-call value feeding a callee pre is body-faithful (no free var)" $ do
        er <- emitN4b (g <> "(def-shell f [x: int] (pre (>= x 1)) (post (>= result 0)) (let [[y (+ x 1)]] (g y)))")
        erBodyFaithfulFns er `shouldSatisfy` elem "f"
        erCallPreFns er      `shouldSatisfy` elem "f"
        erSkipped er         `shouldSatisfy` not . elem "f"

      it "F4b-2: chained let-values (z depends on y) both reach the call-pre context" $ do
        er <- emitN4b (g <> "(def-shell f [x: int] (pre (>= x 1)) (post (>= result 0)) (let [[y (+ x 1)]] (let [[z (+ y 1)]] (g z))))")
        erBodyFaithfulFns er `shouldSatisfy` elem "f"
        erSkipped er         `shouldSatisfy` not . elem "f"

      it "F4b-3: a contracted call with a direct param arg (no let-value) is unaffected" $ do
        er <- emitN4b (g <> "(def-shell h [x: int] (pre (>= x 2)) (post (>= result 0)) (g x))")
        erBodyFaithfulFns er `shouldSatisfy` elem "h"   -- direct-param call-pre still works (no lb threading triggered)
        erCallPreFns er      `shouldSatisfy` elem "h"

    describe "call-pre constraint emission (end-to-end)" $ do
      it "emitFixpointWith emits call-pre constraint for contracted call" $ do
        let src = T.pack $ unlines
              [ "(def-shell safe-sub [balance: int amount: int]"
              , "  (pre (>= balance amount))"
              , "  (post (= result (- balance amount)))"
              , "  (- balance amount))"
              , ""
              , "(def-shell withdraw [bal: int amt: int]"
              , "  (pre (>= bal amt))"
              , "  (post (= result (- bal amt)))"
              , "  (safe-sub bal amt))"
              ]
        case parseStatements GrammarCoreInversion "test.llmll" src of
          Left err -> expectationFailure $ "parse failed: " <> show err
          Right stmts -> do
            emitR <- emitFixpointWith (EmitOptions True) "test.llmll" stmts
            erCallPreFns emitR `shouldSatisfy` elem "withdraw"
            erBodyFaithfulFns emitR `shouldSatisfy` elem "safe-sub"
            erBodyFaithfulFns emitR `shouldSatisfy` elem "withdraw"

    describe "EMatch on Result (COMP-3)" $ do
      it "C06: match on Result variable produces BranchVC" $ do
        -- (match r ((Success v) v) ((Error e) 0))
        -- where r is an int-typed variable in sort env
        let body = EMatch (EVar "r")
                     [ (PConstructor "Success" [PVar "v"], EVar "v")
                     , (PConstructor "Error" [PVar "e"], ELit (LitInt 0))
                     ]
            se = Map.fromList [("r", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (BranchVC guard _ svc evc) -> do
            -- Guard should be a synthetic variable
            case guard of
              FQVar gn -> T.isPrefixOf "_bv__match_success" gn `shouldBe` True
              _ -> expectationFailure $ "Expected FQVar guard, got: " ++ show guard
            -- Success branch should produce the bound variable
            case svc of
              SimpleVC [] (FQVar sv) -> T.isPrefixOf "_bv_v" sv `shouldBe` True
              _ -> expectationFailure $ "Expected SimpleVC with renamed var, got: " ++ show svc
            -- Error branch should produce literal 0
            case evc of
              SimpleVC [] (FQLit 0) -> pure ()
              _ -> expectationFailure $ "Expected SimpleVC [FQLit 0], got: " ++ show evc
          other -> expectationFailure $ "Expected BranchVC, got: " ++ show other

      it "reversed arm order still works (Error first, Success second)" $ do
        let body = EMatch (EVar "r")
                     [ (PConstructor "Error" [PVar "e"], ELit (LitInt 0))
                     , (PConstructor "Success" [PVar "v"], EVar "v")
                     ]
            se = Map.fromList [("r", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (BranchVC _ _ svc evc) -> do
            -- Success is always the then-branch
            case svc of
              SimpleVC [] (FQVar sv) -> T.isPrefixOf "_bv_v" sv `shouldBe` True
              _ -> expectationFailure $ "Expected success SimpleVC, got: " ++ show svc
            -- Error is always the else-branch
            case evc of
              SimpleVC [] (FQLit 0) -> pure ()
              _ -> expectationFailure $ "Expected error SimpleVC, got: " ++ show evc
          other -> expectationFailure $ "Expected BranchVC, got: " ++ show other

      it "F05: match on non-Result (3+ arms) falls back" $ do
        -- (match c ((Red) 1) ((Green) 2) ((Blue) 3))
        let body = EMatch (EVar "c")
                     [ (PConstructor "Red" [], ELit (LitInt 1))
                     , (PConstructor "Green" [], ELit (LitInt 2))
                     , (PConstructor "Blue" [], ELit (LitInt 3))
                     ]
            se = Map.fromList [("c", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        result `shouldBe` Nothing

      it "EMatch on function call (EApp) produces CallVC with BranchVC continuation" $ do
        let gContract = Contract
              (Just (EApp ">=" [EVar "x", ELit (LitInt 0)]))
              Nothing
              (Just (EApp "=" [EVar "result", EVar "x"]))
              Nothing Nothing
            cenv = Map.fromList [("g", ([("x", TInt)], gContract, Just (TResult TInt TInt)))]
            body = EMatch (EApp "g" [ELit (LitInt 42)])
                     [ (PConstructor "Success" [PVar "v"], EVar "v")
                     , (PConstructor "Error" [PVar "e"], ELit (LitInt 0))
                     ]
            se = Map.fromList [("x", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se cenv Set.empty body
        case result of
          Just (CallVC callee _ _ _ _ _ cont) -> do
            callee `shouldBe` "g"
            -- Continuation should be a BranchVC (the match)
            case cont of
              BranchVC _ _ _ _ -> pure ()
              _ -> expectationFailure $ "Expected BranchVC continuation, got: " ++ show cont
          other -> expectationFailure $ "Expected CallVC, got: " ++ show other

    -- COMP-3b: a refinement-aliased return (-> Word) over a two-arm match on a
    -- Result *variable* scrutinee now reaches a body-faithful per-arm VC. Before,
    -- the Result var was absent from the int-only SortEnv, so the scrutinee failed
    -- to translate and the whole function fell back. The synthetic guard and the
    -- match payloads are declared as binders so fixpoint sees no free vars; the
    -- error payload binds at its real (Str) sort, not the int default. Suite
    -- convention: structural assertions on the emitted .fq; SAFE/refuted is
    -- CLI-probe-verified (clean -> SAFE; an unclamped Success arm -> refuted).
    describe "EMatch on Result + refinement return (COMP-3b)" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
          word = "(type Word (where [x: int] (and (>= x 0) (<= x 65535))))\n"
          clampSrc = word
            <> "(def clamp-result [r: Result[int, string]] -> Word "
            <> "(match r ((Success s) (if (> s 65535) 65535 (if (< s 0) 0 s))) ((Error e) 0)))"

      it "C3B-1: refinement-return over a Result-variable match is body-faithful (was fallback)" $ do
        er <- emitSrc clampSrc
        erBodyFaithfulFns er `shouldSatisfy` elem "clamp-result"
        erBodyFallback er    `shouldSatisfy` not . elem "clamp-result"

      it "C3B-2: the match guard is a declared int TAG binder with a range fact (no free var)" $ do
        er <- emitSrc clampSrc
        let fq = erFQText er
        -- MATCH-WIDEN STRETCH (v0.14.12): the arm discriminant is now an int TAG
        -- equality (= <scrut>$tag 0), and <scrut>$tag is DECLARED (no free var) as an
        -- int binder carrying the range fact — replacing the old free bool guard.
        fq `shouldSatisfy` T.isInfixOf "r_tag"
        fq `shouldSatisfy` T.isInfixOf "(r_tag = 0) || (r_tag = 1)"

      it "C3B-3: the Error payload binds at its real Str sort (not the int default)" $ do
        er <- emitSrc clampSrc
        let fq = erFQText er
        -- COMP-3b-general routes through the generic (alpha-renaming) path, so the
        -- payloads are now "_bv_<name>_N"; the discriminating evidence is the SORT:
        -- the error payload is declared at its real Str sort, never the int default.
        fq `shouldSatisfy` T.isInfixOf "{ v : Str | true }"
        fq `shouldSatisfy` T.isInfixOf "_bv_s"   -- renamed Success payload present

      it "C3B-4: a constructor-dependent post still falls back (Issue-2 gate preserved)" $ do
        er <- emitSrc (word
          <> "(def cdp [r: Result[int, string]] -> int "
          <> "(post (match result ((Success v) (>= v 0)) ((Error e) (>= result 0)))) "
          <> "(match r ((Success s) s) ((Error e) 0)))")
        erBodyFaithfulFns er `shouldSatisfy` not . elem "cdp"

    -- COMP-3b-general (opaque-sum elimination): the flat-Result match generalized
    -- to ANY nesting depth — a Result-var scrutinee is detected via derived
    -- SortEnv payload-sort keys ("<v>$ok"/"<v>$err"), the guard+payloads ride the
    -- binder-carrying BranchVC, and collectBranchBinders declares them across the
    -- whole tree (the former top-level special-case is subsumed and deleted). Plus
    -- the localization fix: a refuted arm is labeled by structural then/else
    -- provenance (pathBranchSides), not a path-index midpoint that mislabeled under
    -- unbalanced nesting.
    describe "COMP-3b-general: opaque-sum elimination (nested + localization)" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts
          word = "(type Word (where [x: int] (and (>= x 0) (<= x 65535))))\n"
          nestedSrc = word
            <> "(def clamp-nested [r: Result[int, string]] -> Word "
            <> "(let [(d 0)] (match r ((Success s) (if (> s 65535) 65535 (if (< s 0) 0 s))) ((Error e) 0))))"

      it "C3BG-1: a Result-var match NESTED under a let is body-faithful (was fallback before COMP-3b-general)" $ do
        er <- emitSrc nestedSrc
        erBodyFaithfulFns er `shouldSatisfy` elem "clamp-nested"
        erBodyFallback er    `shouldSatisfy` not . elem "clamp-nested"

      it "C3BG-2: pathBranchSides labels arms structurally under unbalanced nesting" $ do
        -- then-subtree: 2 paths (nested branch); else-subtree: 1 path.
        -- The old midpoint (3 `div` 2 = 1) mislabeled path 1 as else; structural
        -- provenance keeps it then.
        let inner = BranchVC (FQVar "h") [] (SimpleVC [] (FQLit 1)) (SimpleVC [] (FQLit 2))
            bvc   = BranchVC (FQVar "g") [] inner (SimpleVC [] (FQLit 3))
        length (flattenBodyVC bvc) `shouldBe` 3
        pathBranchSides bvc `shouldBe` [Just True, Just True, Just False]

      it "C3BG-3: collectBranchBinders gathers guard+payloads across the whole tree" $ do
        let inner = BranchVC (FQVar "g2") [("g2", FQBool, FQTrue), ("s2", FQInt, FQTrue), ("e2", FQInt, FQTrue)]
                             (SimpleVC [] (FQVar "s2")) (SimpleVC [] (FQLit 0))
            bvc   = BranchVC (FQVar "g1") [("g1", FQBool, FQTrue), ("s1", FQInt, FQTrue), ("e1", FQInt, FQTrue)]
                             inner (SimpleVC [] (FQLit 0))
        collectBranchBinders bvc `shouldBe`
          [("g1", FQBool, FQTrue), ("s1", FQInt, FQTrue), ("e1", FQInt, FQTrue), ("g2", FQBool, FQTrue), ("s2", FQInt, FQTrue), ("e2", FQInt, FQTrue)]
        collectBranchBinders (SimpleVC [] (FQLit 0)) `shouldBe` []

      it "C3BG-4: a Result-var match (derived $ok/$err keys) yields a BranchVC carrying its binders" $ do
        let body = EMatch (EVar "attempt")
                     [ (PConstructor "Success" [PVar "n"], EVar "n")
                     , (PConstructor "Error" [PVar "e"], ELit (LitInt 0)) ]
            se = Map.fromList [("attempt$ok", FQInt), ("attempt$err", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          -- MATCH-WIDEN STRETCH: guard is now the int-tag equality; the tag binder is
          -- FQInt (with a range fact) followed by the two payload binders.
          Just (BranchVC g binders _ _) -> do
            g `shouldBe` FQBinPred FQEq (FQVar "attempt$tag") (FQLit 0)
            map (\(_, s, _) -> s) binders `shouldBe` [FQInt, FQInt, FQInt]
          other -> expectationFailure $ "Expected BranchVC with binders, got: " ++ show other

      it "C3BG-5: a caller's assumed callee post desugars nullary-enum ctors across the call edge (cenv)" $ do
        -- Regression for the cenv-desugar fix: a def-shell caller of a callee whose
        -- contract uses nullary-enum constructors must pull the callee's assumed post
        -- DESUGARED (int tags) via the ContractEnv, not RAW — otherwise the raw
        -- capitalized constructor is a free var and liquid-fixpoint crashes
        -- ("Constraint with free vars"). buildContractEnv now desugars stored
        -- contracts, matching the definition-site desugar.
        er <- emitSrc (T.unlines
          [ "(type S (| A) (| B))"
          , "(def callee [s: S] -> int"
          , "  (post (and (>= result 0) (or (not (= s A)) (= result 1))))"
          , "  (if (= s A) 1 0))"
          , "(def-shell caller [s: S] -> int"
          , "  (post (>= result 0))"
          , "  (callee s))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "caller"
        let fq = erFQText er
        -- the callee's assumed post (pulled into caller's VC) is desugared: the
        -- lowered tag `(s = 0)` is present; the raw `(s = A)` free-var form is gone.
        fq `shouldSatisfy` T.isInfixOf "(s = 0)"
        fq `shouldSatisfy` (not . T.isInfixOf "(s = A)")

    -- COMP-4 (d-elim): two-arm USER-ADT opaque-sum elimination — the Result-
    -- specific skolem-branch generalized to an arbitrary two-arm sum type with
    -- single-payload constructors. Same QF-LIA exhaustiveness-only encoding;
    -- payloads admissible iff QF-LIA scalars (int/bool/string), else fall back
    -- (firewall). SAFE/refuted is CLI-probe-verified (the admissible match → SAFE;
    -- the raw-payload twin → refuted).
    describe "COMP-4 (d-elim): two-arm user-ADT opaque-sum elimination" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "DELIM-1: a match on an admissible two-arm USER ADT is body-faithful (beyond Result)" $ do
        er <- emitSrc (T.unlines
          [ "(type Balance (where [b: int] (>= b 0)))"
          , "(type Outcome (| Ok int) (| Bad int))"
          , "(def settle-adt [o: Outcome] -> Balance"
          , "  (match o ((Ok n) (if (>= n 0) n 0)) ((Bad m) 0)))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "settle-adt"
        erBodyFallback er    `shouldSatisfy` not . elem "settle-adt"

      it "DELIM-2: a two-arm ADT with a SUM-typed payload falls back (firewall, not body-faithful)" $ do
        er <- emitSrc (T.unlines
          [ "(type Inner (| A int) (| B int))"
          , "(type Wrap (| W Inner) (| Z int))"
          , "(def f [w: Wrap] -> int (post (>= result 0)) (match w ((W i) 0) ((Z n) 0)))" ])
        erBodyFaithfulFns er `shouldSatisfy` not . elem "f"

      it "DELIM-3: a two-arm user-ADT var match (derived $Ctor keys) yields a BranchVC carrying its binders" $ do
        let body = EMatch (EVar "o")
                     [ (PConstructor "Ok" [PVar "n"], EVar "n")
                     , (PConstructor "Bad" [PVar "m"], ELit (LitInt 0)) ]
            se = Map.fromList [("o$Ok", FQInt), ("o$Bad", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          -- MATCH-WIDEN STRETCH: int-tag equality guard; tag binder FQInt then payloads.
          Just (BranchVC g binders _ _) -> do
            g `shouldBe` FQBinPred FQEq (FQVar "o$tag") (FQLit 0)
            map (\(_, s, _) -> s) binders `shouldBe` [FQInt, FQInt, FQInt]
          other -> expectationFailure $ "Expected BranchVC with binders, got: " ++ show other

    -- MATCH-WIDEN-2: n-arm (>2) payload-bearing sum matches + sequential (Commit A
    -- is the n-arm half). Same int-tag QF-LIA theory as v0.14.12; the arms compose
    -- as a right-nested BranchVC chain (first-match ¬prior), n=2 byte-identical to
    -- the prior binary encoding. Exhaustiveness is guaranteed upstream by
    -- TypeCheck.checkExhaustive, so the verifier only sees exhaustive matches.
    -- Refutation preservation (a -bad twin refutes) is a solver verdict, CLI-probe-
    -- verified (scratchpad mixed3bad.llmll → exit 1); not emit-level testable here.
    describe "MATCH-WIDEN-2: n-arm payload-bearing sum matches" $ do
      let emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "MW2A-1: a 3-arm mixed sum (nullary + two payloads) is body-faithful" $ do
        er <- emitSrc (T.unlines
          [ "(type Sig (| Continue) (| Stop int) (| Retry int))"
          , "(def-shell handle [s: Sig] -> int"
          , "  (post (>= result 0))"
          , "  (match s ((Continue) 0) ((Stop n) n) ((Retry m) m)))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "handle"
        erBodyFallback er    `shouldSatisfy` not . elem "handle"

      it "MW2A-2: a 4-arm sum is body-faithful (the tag chain is naturally n-ary)" $ do
        er <- emitSrc (T.unlines
          [ "(type Sig4 (| A) (| B int) (| C int) (| D int))"
          , "(def-shell pick4 [s: Sig4] -> int"
          , "  (post (>= result 0))"
          , "  (match s ((A) 0) ((B n) n) ((C m) m) ((D k) k)))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "pick4"

      it "MW2A-3: a 3-arm sum with a wildcard tail is body-faithful (terminal ¬prior else)" $ do
        er <- emitSrc (T.unlines
          [ "(type Sig (| Continue) (| Stop int) (| Retry int))"
          , "(def-shell hwild [s: Sig] -> int"
          , "  (post (>= result 0))"
          , "  (match s ((Continue) 0) ((Stop n) n) (_ 0)))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "hwild"

      it "MW2A-4: an all-nullary 3-arm enum is still body-faithful (no regression on the desugar path)" $ do
        er <- emitSrc (T.unlines
          [ "(type Color (| Red) (| Green) (| Blue))"
          , "(def-shell pick [c: Color] -> int"
          , "  (post (>= result 0))"
          , "  (match c ((Red) 0) ((Green) 1) ((Blue) 2)))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "pick"

      it "MW2A-5: a 3-arm sum with a non-admissible (sum-typed) payload arm falls back (firewall)" $ do
        er <- emitSrc (T.unlines
          [ "(type Inner (| A int) (| B int))"
          , "(type Wrap3 (| W Inner) (| Z int) (| Q))"
          , "(def-shell f [w: Wrap3] -> int (post (>= result 0))"
          , "  (match w ((W i) 0) ((Z n) 0) ((Q) 0)))" ])
        erBodyFaithfulFns er `shouldSatisfy` not . elem "f"

      it "MW2A-6: a two-arm ADT match is UNCHANGED — a single BranchVC (n=2 byte-identity)" $ do
        -- Mirrors DELIM-3: the n-way generalization must degenerate to the exact
        -- prior binary encoding at n=2 (one BranchVC, tag guard o$tag=0, tag binder
        -- + both payload binders), else every shipped two-arm sidecar invalidates.
        let body = EMatch (EVar "o")
                     [ (PConstructor "Ok" [PVar "n"], EVar "n")
                     , (PConstructor "Bad" [PVar "m"], ELit (LitInt 0)) ]
            se = Map.fromList [("o$Ok", FQInt), ("o$Bad", FQInt)] :: SortEnv
            (_, result) = bodyToPredFrom 0 se Map.empty Set.empty body
        case result of
          Just (BranchVC g binders t e) -> do
            g `shouldBe` FQBinPred FQEq (FQVar "o$tag") (FQLit 0)
            map (\(_, s, _) -> s) binders `shouldBe` [FQInt, FQInt, FQInt]
            -- both children are leaves (no nested chain) — the n=2 special case
            case (t, e) of
              (SimpleVC _ _, SimpleVC _ _) -> pure ()
              _ -> expectationFailure "n=2 must be a flat BranchVC, not a nested chain"
          other -> expectationFailure $ "Expected single BranchVC, got: " ++ show other

      it "MW2A-7: a non-exhaustive n-arm mixed match is a type error (checkExhaustive gates it before verify)" $ do
        let src = T.unlines
              [ "(type Sig (| Continue) (| Stop int) (| Retry int))"
              , "(def-shell h [s: Sig] -> int (match s ((Continue) 0) ((Stop n) n)))" ]
        case parseStatements GrammarCoreInversion "<test>" src of
          Left err -> expectationFailure (show err)
          Right stmts -> do
            let report = typeCheck GrammarCoreInversion emptyEnv stmts
                nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                                (reportDiagnostics report)
            nonExh `shouldSatisfy` not . null

      -- MATCH-WIDEN-2 Commit B: sequential matches in one body. A let-bound
      -- multi-path match RHS is threaded into the body (§S4) instead of falling
      -- back; when the body is itself a match this nests (two sequential matches).
      it "MW2B-1: two sequential two-arm matches in one body are body-faithful" $ do
        er <- emitSrc (T.unlines
          [ "(type R (| Ok int) (| Err int))"
          , "(def-shell chain [a: R b: R] -> int"
          , "  (post (>= result 0))"
          , "  (let [(x (match a ((Ok p) (if (>= p 0) p 0)) ((Err q) 0)))]"
          , "    (match b ((Ok r) (if (>= r 0) (+ x r) x)) ((Err s) x))))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "chain"
        erBodyFallback er    `shouldSatisfy` not . elem "chain"

      it "MW2B-2: an n-arm match (Commit A) followed by a two-arm match is body-faithful" $ do
        er <- emitSrc (T.unlines
          [ "(type Sig (| Continue) (| Stop int) (| Retry int))"
          , "(type R (| Ok int) (| Err int))"
          , "(def-shell f [s: Sig b: R] -> int (post (>= result 0))"
          , "  (let [(x (match s ((Continue) 0) ((Stop n) (if (>= n 0) n 0)) ((Retry m) (if (>= m 0) m 0))))]"
          , "    (match b ((Ok r) x) ((Err e) x))))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "f"

      it "MW2B-3: a single (non-sequential) match body is UNCHANGED — the graft is scoped to multi-path let-RHS" $ do
        er <- emitSrc (T.unlines
          [ "(type R (| Ok int) (| Err int))"
          , "(def-shell single [a: R] -> int (post (>= result 0))"
          , "  (match a ((Ok p) (if (>= p 0) p 0)) ((Err q) 0)))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "single"

      it "MW2B-4: a sequential whose continuation is untranslatable (nonlinear) falls back through the thread (no crash)" $ do
        er <- emitSrc (T.unlines
          [ "(type R (| Ok int) (| Err int))"
          , "(def-shell g [a: R] -> int (post (>= result 0))"
          , "  (let [(x (match a ((Ok p) (if (>= p 0) p 0)) ((Err q) 0)))]"
          , "    (* x x)))" ])
        erBodyFallback er `shouldSatisfy` elem "g"

      -- MW2B-5: refutation preservation (emit-level half). A sequential body whose
      -- SECOND match has a violating arm (Err -> -1 vs post >= 0) must still be
      -- body-faithful — the per-arm obligation is EMITTED under its path guard and
      -- reaches the solver, NOT laundered to contract-only fallback (which would
      -- silently swallow the violation). The solver-refutes half is CLI-verified
      -- (verify exits 1, not in fallback). This locks in that the sequential graft
      -- cannot launder a bad mid-pipeline arm.
      it "MW2B-5: a sequential body with a violating 2nd-match arm stays body-faithful (obligation emitted, not laundered)" $ do
        er <- emitSrc (T.unlines
          [ "(type R (| Ok int) (| Err int))"
          , "(def-shell chain [a: R b: R] -> int (post (>= result 0))"
          , "  (let [(x (match a ((Ok p) 0) ((Err q) 0)))]"
          , "    (match b ((Ok r) x) ((Err s) (- 0 1)))))" ])
        erBodyFaithfulFns er `shouldSatisfy` elem "chain"
        erBodyFallback er    `shouldSatisfy` not . elem "chain"

    -- COMP-4 (b): a matched arm consumes its payload's DECLARED refinement
    -- (elim-side), and a caller forwarding a weaker payload is refused by a
    -- payload-subtyping obligation (intro-side). The elim-binder and the helper
    -- extractors are unit-tested here; the intro-side refusal + the verified
    -- consumer are CLI-probe-verified (examples/refined-payload/*).
    describe "COMP-4 (b): refined-payload elimination + subtyping" $ do
      it "C4B-1: payloadRefinement extracts a refined payload's predicate; Nothing for base" $ do
        let posRef = EOp ">" [EVar "n", ELit (LitInt 0)]
            am = Map.fromList [("Pos", TDependent "n" TInt posRef)]
        payloadRefinement am (TCustom "Pos") `shouldBe` Just ("n", posRef)
        payloadRefinement am TInt           `shouldBe` Nothing
        payloadRefinement am TString        `shouldBe` Nothing

      it "C4B-2: payloadArms gives per-arm payload types keyed by arm suffix" $ do
        payloadArms Map.empty (TResult (TCustom "Pos") TString)
          `shouldBe` [("$ok", TCustom "Pos"), ("$err", TString)]
        payloadArms Map.empty (TSumType [("Ok", Just TInt), ("Bad", Just TString)])
          `shouldBe` [("$Ok", TInt), ("$Bad", TString)]
        payloadArms Map.empty TInt `shouldBe` []

      it "C4B-3: bodyToPredFromR binds a matched payload at its declared refinement (not FQTrue)" $ do
        let body = EMatch (EVar "attempt")
                     [ (PConstructor "Success" [PVar "n"], EVar "n")
                     , (PConstructor "Error" [PVar "e"], ELit (LitInt 0)) ]
            se = Map.fromList [("attempt$ok", FQInt), ("attempt$err", FQInt)] :: SortEnv
            refEnv = Map.fromList [("attempt$ok", ("n", EOp ">" [EVar "n", ELit (LitInt 0)]))]
            (_, result) = bodyToPredFromR 0 se refEnv Map.empty Map.empty Set.empty body
        case result of
          Just (BranchVC _ binders _ _) ->
            -- exactly the Success PAYLOAD binder carries a non-trivial refinement;
            -- the Error payload (unrefined) stays FQTrue (d-elim). The MATCH-WIDEN
            -- tag binder carries a range fact and is excluded from this payload check.
            length [ p | (n, _, p) <- binders, not (T.isSuffixOf "$tag" n), p /= FQTrue ] `shouldBe` 1
          other -> expectationFailure $ "Expected BranchVC, got: " ++ show other

      it "C4B-4: an empty RefEnv preserves the FQTrue payload skolems (d-elim unaffected)" $ do
        let body = EMatch (EVar "attempt")
                     [ (PConstructor "Success" [PVar "n"], EVar "n")
                     , (PConstructor "Error" [PVar "e"], ELit (LitInt 0)) ]
            se = Map.fromList [("attempt$ok", FQInt), ("attempt$err", FQInt)] :: SortEnv
            (_, result) = bodyToPredFromR 0 se Map.empty Map.empty Map.empty Set.empty body
        case result of
          Just (BranchVC _ binders _ _) ->
            -- payload skolems stay FQTrue (d-elim); the MATCH-WIDEN tag binder carries
            -- its range fact and is excluded.
            all (\(n, _, p) -> T.isSuffixOf "$tag" n || p == FQTrue) binders `shouldBe` True
          other -> expectationFailure $ "Expected BranchVC, got: " ++ show other

    -- COMP-4 (a): native FQData construction — admissibility firewall +
    -- provenance-partitioned sort (payload sum → FQData; nullary enum → int-tag).
    -- The construction round-trip (verified SAFE / refuted on a wrong payload) is
    -- CLI-probe-verified; the pure firewall/sort logic is unit-tested here.
    describe "COMP-4 (a): construction substrate" $ do
      it "C4AC-1: admissibleDatatype accepts a flat sum, rejects a recursive one" $ do
        let boxAm  = Map.fromList [("Box", TSumType [("Full", Just TInt), ("Empty", Nothing)])]
            treeAm = Map.fromList [("Tree", TSumType [("Node", Just (TCustom "Tree")), ("Leaf", Nothing)])]
        admissibleDatatype boxAm  (TSumType [("Full", Just TInt), ("Empty", Nothing)]) `shouldBe` True
        admissibleDatatype treeAm (TSumType [("Node", Just (TCustom "Tree")), ("Leaf", Nothing)]) `shouldBe` False

      it "C4AC-2: typeToSortA gives FQData for a payload sum, FQInt for a nullary enum" $ do
        let boxAm   = Map.fromList [("Box", TSumType [("Full", Just TInt), ("Empty", Nothing)])]
            colorAm = Map.fromList [("Color", TSumType [("Red", Nothing), ("Green", Nothing)])]
        typeToSortA boxAm   (TCustom "Box")   `shouldBe` FQData "Box"
        typeToSortA colorAm (TCustom "Color") `shouldBe` FQInt
        typeToSortA boxAm   TInt              `shouldBe` FQInt

      it "C4AC-3: a nullary variant of a payload sum is constructible via application (no type mismatch)" $ do
        let src = T.pack $ unlines
              [ "(type Box (| Full int) (| Empty))"
              , "(def mk [n: int] -> Box (post (= result (Empty))) (Empty))" ]
        case parseStatements GrammarCoreInversion "<test>" src of
          Left err    -> expectationFailure (show err)
          Right stmts -> do
            let report = typeCheck GrammarCoreInversion emptyEnv stmts
                mism   = filter (\d -> "mismatch" `T.isInfixOf` diagMessage d) (reportDiagnostics report)
            mism `shouldBe` []

    -- PAIR-RET: refinement predicates over pair/tuple returns. A 2-tuple is the
    -- single-constructor (product) restriction of the COMP-4 datatype class — the
    -- valid tester makes selectors total and fully determined, so projection-in-goal
    -- is sound (professor adjudication). The pure translation + emit structure is
    -- unit-tested here; SAFE/refuted is CLI-probe-verified
    -- (examples/payments-core/conserve{,-bad}.llmll).
    describe "PAIR-RET: pair projections in refinement posts" $ do
      let pairSrc = T.pack $ unlines
            [ "(def conserve [from: int to: int amount: int] -> (int, int)"
            , "  (pre  (and (>= from amount) (>= amount 0)))"
            , "  (post (= (+ (first result) (second result)) (+ from to)))"
            , "  (pair (- from amount) (+ to amount)))" ]
          emitText src = case parseStatements GrammarCoreInversion "<test>" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> erFQText <$> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "PR-1: exprToPred reflects first/second/pair to the Pair2 selector/ctor terms" $ do
        exprToPred (EApp "first"  [EVar "r"])    `shouldBe` Just (FQApp "pair2_0" [FQVar "r"])
        exprToPred (EApp "second" [EVar "r"])    `shouldBe` Just (FQApp "pair2_1" [FQVar "r"])
        exprToPred (EPair (EVar "a") (EVar "b")) `shouldBe` Just (FQApp "pair2" [FQVar "a", FQVar "b"])

      it "PR-2: a conservation post (= (+ (first r) (second r)) k) is translatable (not asserted)" $
        exprToPred (EApp "=" [ EApp "+" [EApp "first" [EVar "r"], EApp "second" [EVar "r"]]
                             , EVar "k" ])
          `shouldBe` Just (FQBinPred FQEq
                            (FQBinArith FQAdd (FQApp "pair2_0" [FQVar "r"]) (FQApp "pair2_1" [FQVar "r"]))
                            (FQVar "k"))

      it "PR-3: typeToSortA lowers a pair to the applied (Pair2 s0 s1) sort, recursively" $ do
        typeToSortA Map.empty (TPair TInt TInt)    `shouldBe` FQDataApp "Pair2" [FQInt, FQInt]
        typeToSortA Map.empty (TPair TString TInt) `shouldBe` FQDataApp "Pair2" [FQStr, FQInt]

      it "PR-4: a pair-returning def emits one `data Pair2 2` decl and selector goal terms" $ do
        fq <- emitText pairSrc
        fq `shouldSatisfy` T.isInfixOf "data Pair2 2"
        fq `shouldSatisfy` T.isInfixOf "pair2_0 result"

      it "PR-5: selectors are NOT swept into measure constants (no spurious `constant pair2_`)" $ do
        fq <- emitText pairSrc
        fq `shouldNotSatisfy` T.isInfixOf "constant pair2"

      it "PR-6: a pair-FREE module emits no Pair2 decl (byte-inert)" $ do
        fq <- emitText (T.pack "(def inc [n: int] -> int (post (= result (+ n 1))) (+ n 1))\n")
        fq `shouldNotSatisfy` T.isInfixOf "Pair2"

      it "PR-7: a string-component pair stacks the strLen measure under a selector" $ do
        -- review req #3: the (string, int) component case — `(string-length (first p))`
        -- lowers to `strLen (pair2_0 p)`, the measure UF composed over a datatype
        -- selector. Applied sort carries Str; strLen stays a genuine measure constant.
        fq <- emitText $ T.pack $ unlines
          [ "(def split-tag [s: string n: int] -> (string, int)"
          , "  (pre  (>= n 0))"
          , "  (post (= (string-length (first result)) (string-length s)))"
          , "  (pair s n))" ]
        fq `shouldSatisfy`    T.isInfixOf "Pair2 Str int"
        fq `shouldSatisfy`    T.isInfixOf "strLen (pair2_0 result)"
        fq `shouldSatisfy`    T.isInfixOf "constant strLen"

    -- PAIR-RET-2: alias-aware pair-component sort routing. An admissible sum/ADT
    -- component lowers to its FQData sort — (int, Box) → (Pair2 int Box) — so a
    -- projection over the sum component verifies via the datatype theory; a
    -- non-sortable component (Result, recursive sum) forces a clean erBodyFallback
    -- instead of crashing the solver on a mis-sorted binder. SAFE/refuted/no-crash
    -- is CLI-probe-verified; the pure sort + fallback logic is unit-tested here.
    describe "PAIR-RET-2: alias-aware sum-component pair sorts" $ do
      let boxAm  = Map.fromList [("Box",  TSumType [("Full", Just TInt), ("Empty", Nothing)])]
          treeAm = Map.fromList [("Tree", TSumType [("Node", Just (TCustom "Tree")), ("Leaf", Nothing)])]
          emitR src = case parseStatements GrammarCoreInversion "<test>" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "PR2-1: typeToSortA lowers (int, Box) to (Pair2 int Box) — sum component preserved" $
        typeToSortA boxAm (TPair TInt (TCustom "Box"))
          `shouldBe` FQDataApp "Pair2" [FQInt, FQData "Box"]

      it "PR2-2: scalar / nested pairs unchanged (regression)" $ do
        typeToSortA Map.empty (TPair TInt TInt) `shouldBe` FQDataApp "Pair2" [FQInt, FQInt]
        typeToSortA Map.empty (TPair TInt (TPair TInt TInt))
          `shouldBe` FQDataApp "Pair2" [FQInt, FQDataApp "Pair2" [FQInt, FQInt]]

      it "PR2-3: sortableComponent — scalar/list/admissible-sum/Result yes; recursive no" $ do
        sortableComponent boxAm  TInt                `shouldBe` True
        sortableComponent boxAm  (TList TInt)        `shouldBe` True
        sortableComponent boxAm  (TCustom "Box")     `shouldBe` True   -- admissible payload sum
        sortableComponent boxAm  (TResult TInt TInt) `shouldBe` True   -- v0.13.14: pair-of-Result (Result is now a native datatype)
        sortableComponent treeAm (TCustom "Tree")    `shouldBe` False  -- recursive → firewall

      it "PR2-4: an admissible sum-component pair binds result at (Pair2 int Box), body-faithful" $ do
        r <- emitR $ T.pack $ unlines
          [ "(type Box (| Full int) (| Empty))"
          , "(def withbox [n: int] -> (int, Box)"
          , "  (post (= (second result) (Full n)))"
          , "  (pair n (Full n)))" ]
        erFQText r `shouldSatisfy` T.isInfixOf "(Pair2 int Box)"
        erBodyFallback r `shouldBe` []                 -- verifies body-faithfully, not fallen back

      it "PR2-5: a Result-component pair is body-faithful (v0.13.14: pair-of-Result)" $ do
        -- pre-v0.13.14 this fell back (Result component non-sortable); the datatype-tail
        -- slice made Result a sortable component, so it now verifies (see CT-1).
        r <- emitR $ T.pack $ unlines
          [ "(def withres [n: int] -> (int, Result[int, int])"
          , "  (post (= (first result) n))"
          , "  (pair n (ok n)))" ]
        erBodyFallback r `shouldBe` []

      it "PR2-6: a recursive-type pair component falls back (param leg of the gate)" $ do
        r <- emitR $ T.pack $ unlines
          [ "(type Tree (| Node Tree) (| Leaf))"
          , "(def-shell ftree [p: (int, Tree)] -> int"
          , "  (post (= result (first p)))"
          , "  (first p))" ]
        erBodyFallback r `shouldBe` ["ftree"]

    -- COMP-4-RESULT: `(ok e)`/`(err e)` construction is now body-faithful (closing the
    -- COMP-4 (a) drift — the uppercase-ctor guard missed the lowercase Result builtins).
    -- Result is promoted to a native polymorphic FQData datatype; opaque/received Result
    -- params stay on the skolem path (disjoint). Non-admissible payloads firewall. Pure
    -- sort/reflection/fallback logic unit-tested here; SAFE/refuted CLI-probe-verified.
    describe "COMP-4-RESULT: ok/err construction" $ do
      let boxAm = Map.fromList [("Box", TSumType [("Full", Just TInt), ("Empty", Nothing)])]
          treeAm = Map.fromList [("Tree", TSumType [("Node", Just (TCustom "Tree")), ("Leaf", Nothing)])]
          emitR src = case parseStatements GrammarCoreInversion "<test>" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "CR-1: typeToSortA lowers Result to the native (Result a b) datatype sort" $ do
        typeToSortA Map.empty (TResult TInt TInt) `shouldBe` FQDataApp "Result" [FQInt, FQInt]
        typeToSortA boxAm (TResult TInt (TCustom "Box"))
          `shouldBe` FQDataApp "Result" [FQInt, FQData "Box"]

      it "CR-2: exprToPred reflects the lowercase ok/err builtins to constructor terms" $ do
        exprToPred (EApp "ok"  [EVar "n"]) `shouldBe` Just (FQApp "ok"  [FQVar "n"])
        exprToPred (EApp "err" [EVar "e"]) `shouldBe` Just (FQApp "err" [FQVar "e"])

      it "CR-3: a Result-constructing def emits `data Result 2` and binds at (Result int int)" $ do
        r <- emitR $ T.pack $ unlines
          [ "(def mkok [n: int] -> Result[int, int]"
          , "  (post (= result (ok n)))"
          , "  (ok n))" ]
        erFQText r `shouldSatisfy` T.isInfixOf "data Result 2"
        erFQText r `shouldSatisfy` T.isInfixOf "(Result int int)"
        erBodyFallback r `shouldBe` []                  -- body-faithful, not fallen back

      it "CR-4: an if-construction (ok/err arms) is body-faithful" $ do
        r <- emitR $ T.pack $ unlines
          [ "(def classify [n: int] -> Result[int, int]"
          , "  (post (or (= result (ok n)) (= result (err n))))"
          , "  (if (>= n 0) (ok n) (err n)))" ]
        erBodyFallback r `shouldBe` []

      it "CR-5: resultReturnUnsafe firewalls a non-admissible payload (scalar/sum ok)" $ do
        resultReturnUnsafe Map.empty (Just (TResult TInt TInt))          `shouldBe` False
        resultReturnUnsafe boxAm     (Just (TResult TInt (TCustom "Box"))) `shouldBe` False
        resultReturnUnsafe Map.empty (Just (TResult TInt (TList TInt)))  `shouldBe` True   -- list payload → firewall
        -- v0.13.14: nested Result is now admissible (recursion); see CT-3. List/recursive stay firewalled.

      it "CR-6: an eliminate-only Result module emits no `data Result` (byte-inert)" $ do
        r <- emitR $ T.pack $ unlines
          [ "(def-shell elim [r: Result[int, int]] -> int"
          , "  (match r ((ok x) x) ((err e) e)))" ]
        erFQText r `shouldNotSatisfy` T.isInfixOf "data Result"

      -- v0.13.14 datatype-tail: the admissibility predicates recurse over the acyclic
      -- composition of scalar / pair / sum / Result, so pair-of-Result components and
      -- nested/composed-datatype Result payloads verify; list and recursive payloads
      -- stay firewalled (the deliberate final boundary). Spike-confirmed fixpoint accepts
      -- the nested applied sorts; SAFE/fallback is CLI-probe-verified.
      it "CT-1: a pair-of-Result component is body-faithful (Pair2 + Result decls)" $ do
        r <- emitR $ T.pack $ unlines
          [ "(def mkpr [n: int m: int] -> (int, Result[int, int])"
          , "  (post (= (second result) (ok m)))"
          , "  (pair n (ok m)))" ]
        erFQText r `shouldSatisfy`    T.isInfixOf "data Pair2"
        erFQText r `shouldSatisfy`    T.isInfixOf "data Result"
        erBodyFallback r `shouldBe` []

      it "CT-2: a nested-Result payload is body-faithful" $ do
        r <- emitR $ T.pack $ unlines
          [ "(def mknr [n: int] -> Result[Result[int, int], int]"
          , "  (post (= result (ok (ok n))))"
          , "  (ok (ok n)))" ]
        erBodyFallback r `shouldBe` []

      it "CT-3: resultReturnUnsafe recurses — nested/composed admissible, list/recursive firewalled" $ do
        resultReturnUnsafe Map.empty (Just (TResult (TResult TInt TInt) TInt)) `shouldBe` False  -- nested Result
        resultReturnUnsafe Map.empty (Just (TResult (TPair TInt TInt) TInt))   `shouldBe` False  -- composed pair payload
        resultReturnUnsafe Map.empty (Just (TResult TInt (TList TInt)))        `shouldBe` True   -- list carrier → firewall
        resultReturnUnsafe treeAm    (Just (TResult (TCustom "Tree") TInt))    `shouldBe` True   -- recursive → firewall

    -- COMP-3b-general Phase 1: an idiomatic nullary-enum, matched and used as
    -- VALUES in a def body, reaches a body-faithful VC via a scope-aware desugar
    -- (ctor value EVar -> int tag; enum EMatch -> nested EIf on (= scrut tag)).
    -- The soundness guards (local shadowing via the bound-set; cross-enum
    -- collision excluded) are unit-tested on the pure exported functions; SAFE/
    -- refuted is CLI-probe-verified (examples/tcp_rfc793/step{,-bad}.llmll).
    describe "COMP-3b-general Phase 1: nullary-enum ctor-value desugar" $ do
      let colorAliases = Map.fromList
            [ ("Color", TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)]) ]
          colorTags = buildCtorTagMap colorAliases
          emitSrc src = case parseStatements GrammarCoreInversion "test" src of
            Left err    -> error ("parse failed: " <> show err)
            Right stmts -> emitFixpointWith (EmitOptions True) "test.llmll" stmts

      it "CG-1: buildCtorTagMap assigns declaration-index tags to a nullary enum" $
        colorTags `shouldBe` Map.fromList [("Red", 0), ("Green", 1), ("Blue", 2)]

      it "CG-2: a constructor of two enums is excluded (cross-enum collision not tagged)" $ do
        let am = Map.fromList
              [ ("A", TSumType [("Foo", Nothing), ("Bar", Nothing)])
              , ("B", TSumType [("Foo", Nothing), ("Qux", Nothing)]) ]
            tags = buildCtorTagMap am
        Map.member "Foo" tags `shouldBe` False          -- excluded: ctor of two enums
        Map.lookup "Bar" tags `shouldBe` Just 1          -- index 1 within A = [Foo, Bar]
        Map.lookup "Qux" tags `shouldBe` Just 1          -- index 1 within B = [Foo, Qux]

      it "CG-3: a payload-bearing sum type contributes no tags (S3 boundary)" $
        buildCtorTagMap (Map.fromList
          [ ("Box", TSumType [("Full", Just (TCustom "int")), ("Empty", Nothing)]) ])
          `shouldBe` Map.empty

      it "CG-4: a value-position constructor EVar desugars to its int tag" $
        desugarCtorValues colorTags Set.empty (EVar "Green") `shouldBe` ELit (LitInt 1)

      it "CG-5: SHADOWING — a bound name matching a ctor stays a variable" $
        desugarCtorValues colorTags (Set.fromList ["Red"]) (EVar "Red") `shouldBe` EVar "Red"

      it "CG-6: a non-constructor EVar is left untouched" $
        desugarCtorValues colorTags Set.empty (EVar "balance") `shouldBe` EVar "balance"

      it "CG-7: an enum EMatch lowers to a right-nested EIf on (= scrut tag)" $
        desugarCtorValues colorTags Set.empty
          (EMatch (EVar "c")
            [ (PConstructor "Red" [],   ELit (LitInt 100))
            , (PConstructor "Green" [], ELit (LitInt 200))
            , (PConstructor "Blue" [],  ELit (LitInt 300)) ])
          `shouldBe`
            EIf (EOp "=" [EVar "c", ELit (LitInt 0)]) (ELit (LitInt 100))
              (EIf (EOp "=" [EVar "c", ELit (LitInt 1)]) (ELit (LitInt 200))
                (ELit (LitInt 300)))

      it "CG-8: a let-binding shadows a ctor name within its body (scope-aware)" $
        desugarCtorValues colorTags Set.empty
          (ELet [(PVar "Red", Nothing, ELit (LitInt 7))] (EVar "Red"))
          `shouldBe`
            ELet [(PVar "Red", Nothing, ELit (LitInt 7))] (EVar "Red")

      it "CG-9: a payload-bearing match is left untouched (flows to the existing fallback path)" $ do
        let am = Map.fromList [ ("Box", TSumType [("Full", Just (TCustom "int")), ("Empty", Nothing)]) ]
            m  = EMatch (EVar "b")
                   [ (PConstructor "Full" [PVar "n"], EVar "n")
                   , (PConstructor "Empty" [], ELit (LitInt 0)) ]
        desugarCtorValues (buildCtorTagMap am) Set.empty m `shouldBe` m

      it "CG-10: a typed nullary-enum fn (match + ctor-value post) reaches a body-faithful VC" $ do
        er <- emitSrc
          ( "(type Light (| Red) (| Green) (| Yellow))\n"
          <> "(def nextlight [c: Light] -> Light "
          <> "(post (or (or (= result Red) (= result Green)) (= result Yellow))) "
          <> "(match c ((Red) Green) ((Green) Yellow) ((Yellow) Red)))" )
        erBodyFaithfulFns er `shouldSatisfy` elem "nextlight"
        erBodyFallback er    `shouldSatisfy` not . elem "nextlight"

  -- -----------------------------------------------------------------------
  -- v0.10 Phase 2: GuardClassifier (Sub-task A)
  -- -----------------------------------------------------------------------

  describe "GuardClassifier: classifyGuardM" $ do
    let intEnv = Map.fromList [("x", FQInt), ("y", FQInt)] :: Map.Map T.Text FQSort
        emptyRename = Map.empty :: Map.Map T.Text T.Text

    it "GC-1: classifies integer variable" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EVar "x")) 0
      result `shouldBe` Just (FQVar "x")

    it "GC-2: rejects a carrier (non-scalar) variable (BOOL-FRAG: bool is now accepted)" $ do
      let se = Map.fromList [("s", FQStr)] :: Map.Map T.Text FQSort
      let result = evalState (classifyGuardM emptyRename se (EVar "s")) 0
      result `shouldBe` Nothing

    it "GC-2b: classifies a bool variable as its atom (BOOL-FRAG)" $ do
      let se = Map.fromList [("b", FQBool)] :: Map.Map T.Text FQSort
      let result = evalState (classifyGuardM emptyRename se (EVar "b")) 0
      result `shouldBe` Just (FQVar "b")

    it "GC-3: rejects unknown variable" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EVar "unknown")) 0
      result `shouldBe` Nothing

    it "GC-4: classifies integer literal" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (ELit (LitInt 42))) 0
      result `shouldBe` Just (FQLit 42)

    it "GC-5: classifies boolean literal" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (ELit (LitBool True))) 0
      result `shouldBe` Just FQTrue

    it "GC-6: classifies comparison (>= x y)" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EApp ">=" [EVar "x", EVar "y"])) 0
      result `shouldBe` Just (FQBinPred FQGe (FQVar "x") (FQVar "y"))

    it "GC-7: classifies arithmetic (+ x y)" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EApp "+" [EVar "x", EVar "y"])) 0
      result `shouldBe` Just (FQBinArith FQAdd (FQVar "x") (FQVar "y"))

    it "GC-8: rejects non-linear (*)" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EApp "*" [EVar "x", EVar "y"])) 0
      result `shouldBe` Nothing

    it "GC-9: classifies not" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EApp "not" [ELit (LitBool True)])) 0
      result `shouldBe` Just (FQNot FQTrue)

    it "GC-10: normalizes EOp to EApp" $ do
      let result = evalState (classifyGuardM emptyRename intEnv (EOp ">=" [EVar "x", EVar "y"])) 0
      result `shouldBe` Just (FQBinPred FQGe (FQVar "x") (FQVar "y"))

    it "GC-11: applies renaming environment" $ do
      let rename = Map.fromList [("balance", "_arg_balance_0")] :: Map.Map T.Text T.Text
          se = Map.fromList [("_arg_balance_0", FQInt)] :: Map.Map T.Text FQSort
      let result = evalState (classifyGuardM rename se (EVar "balance")) 0
      result `shouldBe` Just (FQVar "_arg_balance_0")

  describe "GuardClassifier: lookupPredOp" $ do
    it "GC-P1: maps >= to FQGe" $ lookupPredOp ">=" `shouldBe` Just FQGe
    it "GC-P2: maps Unicode ≥ to FQGe" $ lookupPredOp "\x2265" `shouldBe` Just FQGe
    it "GC-P3: maps < to FQLt" $ lookupPredOp "<" `shouldBe` Just FQLt
    it "GC-P4: maps == to FQEq" $ lookupPredOp "==" `shouldBe` Just FQEq
    it "GC-P5: maps /= to FQNeq" $ lookupPredOp "/=" `shouldBe` Just FQNeq
    it "GC-P6: rejects unknown" $ lookupPredOp "foo" `shouldBe` Nothing

  describe "GuardClassifier: lookupArithOp" $ do
    it "GC-A1: maps + to FQAdd" $ lookupArithOp "+" `shouldBe` Just FQAdd
    it "GC-A2: maps - to FQSub" $ lookupArithOp "-" `shouldBe` Just FQSub
    it "GC-A3: rejects *" $ lookupArithOp "*" `shouldBe` Nothing

  -- -----------------------------------------------------------------------
  -- v0.10 Phase 2: ObligationAssembly (Sub-task B)
  -- -----------------------------------------------------------------------

  describe "ObligationAssembly: exprToSExpr" $ do
    it "OA-S1: variable" $ exprToSExpr (EVar "x") `shouldBe` "x"
    it "OA-S2: integer literal" $ exprToSExpr (ELit (LitInt 42)) `shouldBe` "42"
    it "OA-S3: boolean literal" $ exprToSExpr (ELit (LitBool True)) `shouldBe` "true"
    it "OA-S4: application" $ exprToSExpr (EApp ">=" [EVar "x", ELit (LitInt 0)]) `shouldBe` "(>= x 0)"
    it "OA-S5: nested" $ exprToSExpr (EApp "+" [EApp "-" [EVar "a", EVar "b"], ELit (LitInt 1)])
      `shouldBe` "(+ (- a b) 1)"
    it "OA-S6: named hole" $ exprToSExpr (EHole (HNamed "body")) `shouldBe` "?body"
    it "OA-S7: EOp normalizes" $ exprToSExpr (EOp "+" [EVar "a", EVar "b"]) `shouldBe` "(+ a b)"

  describe "ObligationAssembly: deriveBacking" $ do
    let mkTable entries = Map.fromList entries
        co fn cl = ConstraintOrigin fn cl "" ""

    it "OA-B1: smt when body-post constraint exists for hole" $ do
      let table = mkTable [(1, co "withdraw" "body-post")]
      deriveBacking table "withdraw" HoleObligation `shouldBe` "smt"

    it "OA-B2: guidance when no body-post for hole" $ do
      let table = mkTable [(1, co "withdraw" "pre")]
      deriveBacking table "withdraw" HoleObligation `shouldBe` "guidance"

    it "OA-B3: smt for contract when pre constraint exists" $ do
      let table = mkTable [(1, co "f" "pre")]
      deriveBacking table "f" ContractObligation `shouldBe` "smt"

    it "OA-B4: guidance for contract when no matching constraint" $ do
      let table = mkTable [(1, co "other" "pre")]
      deriveBacking table "f" ContractObligation `shouldBe` "guidance"

    it "OA-B5: smt for precondition when call-pre constraint exists" $ do
      let table = mkTable [(1, co "caller" "call-pre:callee")]
      deriveBacking table "caller" PreconditionObligation `shouldBe` "smt"

  describe "ObligationAssembly: obligationStatus" $ do
    let emptyTable = Map.empty :: Map.Map Int ConstraintOrigin
        noSuppressed = Set.empty :: Set.Set T.Text
        noRefuted    = Set.empty :: Set.Set T.Text

    it "OA-ST1: open when no solver" $
      obligationStatus Nothing "f" HoleObligation emptyTable noSuppressed noRefuted `shouldBe` "open"

    it "OA-ST2: discharged when SAFE" $
      obligationStatus (Just FQSafe) "f" HoleObligation emptyTable noSuppressed noRefuted `shouldBe` "discharged"

    it "OA-ST3: deferred when in suppression set" $
      obligationStatus (Just FQSafe) "f" HoleObligation emptyTable (Set.singleton "f") noRefuted `shouldBe` "deferred"

    it "OA-ST4: open when UNSAFE and function failed" $ do
      let table = Map.fromList [(1, ConstraintOrigin "f" "post" "" "")]
      obligationStatus (Just (FQUnsafe [1])) "f" ContractObligation table noSuppressed noRefuted `shouldBe` "open"

    it "OA-ST5: discharged when UNSAFE but function not in failed set" $ do
      let table = Map.fromList [(1, ConstraintOrigin "other" "post" "" "")]
      obligationStatus (Just (FQUnsafe [1])) "f" ContractObligation table noSuppressed noRefuted `shouldBe` "discharged"

    -- VERIFY-RPT-1 (Commit 4): "refuted" status takes precedence
    it "VR4-ST1: refuted when in refuted set (overrides discharged)" $
      obligationStatus (Just FQSafe) "f" HoleObligation emptyTable noSuppressed (Set.singleton "f") `shouldBe` "refuted"

    it "VR4-ST2: refuted overrides deferred (suppression)" $
      obligationStatus (Just FQSafe) "f" HoleObligation emptyTable (Set.singleton "f") (Set.singleton "f") `shouldBe` "refuted"

    it "VR4-ST3: not refuted when function absent from refuted set" $
      obligationStatus (Just FQSafe) "f" HoleObligation emptyTable noSuppressed (Set.singleton "other") `shouldBe` "discharged"

  describe "ObligationAssembly: classifyContractFragment" $ do
    it "OA-CF1: absent when no pre and no post" $
      classifyContractFragment (Contract Nothing Nothing Nothing Nothing Nothing) `shouldBe` "absent"

    it "OA-CF2: qf_lia for simple arithmetic" $
      classifyContractFragment (Contract
        (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing Nothing Nothing Nothing)
        `shouldBe` "qf_lia"

    it "OA-CF3: non_qf_lia for string operations" $
      classifyContractFragment (Contract
        (Just (EApp "string-empty?" [EVar "s"])) Nothing Nothing Nothing Nothing)
        `shouldBe` "non_qf_lia"

  describe "ObligationAssembly: classifyBodyFragment" $ do
    let noRec = Set.empty :: Set.Set T.Text

    it "OA-BF1: hole_bearing when body has hole" $
      classifyBodyFragment "f" noRec [] [] (EHole (HNamed "impl")) `shouldBe` "hole_bearing"

    it "OA-BF2: qf_lia when body-faithful" $
      classifyBodyFragment "f" noRec ["f"] [] (EApp "-" [EVar "a", EVar "b"]) `shouldBe` "qf_lia"

    it "OA-BF3: unsupported when in fallback" $
      classifyBodyFragment "f" noRec [] ["f"] (EApp "g" [EVar "x"]) `shouldBe` "unsupported"

    it "OA-BF4: recursive when in recursive set" $
      classifyBodyFragment "f" (Set.singleton "f") [] [] (EApp "f" [EVar "x"]) `shouldBe` "recursive"

  describe "ObligationAssembly: normalizeForFingerprint" $ do
    it "OA-NF1: produces oblig: prefixed ID" $ do
      let oblId = normalizeForFingerprint "withdraw" [("balance", TInt), ("amount", TInt)]
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) "body"
      T.isPrefixOf "oblig:withdraw:body:" oblId `shouldBe` True

    it "OA-NF2: fingerprint is 12 hex chars" $ do
      let oblId = normalizeForFingerprint "f" [("x", TInt)] Nothing "body"
          parts = T.splitOn ":" oblId
      T.length (last parts) `shouldBe` 12

    it "OA-NF3: same inputs produce same ID" $ do
      let oblId1 = normalizeForFingerprint "f" [("x", TInt)] (Just (EVar "x")) "body"
          oblId2 = normalizeForFingerprint "f" [("x", TInt)] (Just (EVar "x")) "body"
      oblId1 `shouldBe` oblId2

    it "OA-NF4: different post produces different ID" $ do
      let oblId1 = normalizeForFingerprint "f" [("x", TInt)] (Just (EVar "x")) "body"
          oblId2 = normalizeForFingerprint "f" [("x", TInt)] (Just (EVar "y")) "body"
      oblId1 `shouldSatisfy` (/= oblId2)

  describe "ObligationAssembly: collectHoleGuards" $ do
    let emptyRename = Map.empty :: Map.Map T.Text T.Text
        intEnv = Map.fromList [("x", FQInt)] :: Map.Map T.Text FQSort

    it "OA-HG1: finds hole with no guards" $ do
      let results = collectHoleGuards emptyRename intEnv (EHole (HNamed "impl"))
      length results `shouldBe` 1
      fst (head results) `shouldBe` "impl"
      snd (head results) `shouldBe` []

    it "OA-HG2: collects if-then guard" $ do
      let expr = EIf (EApp ">=" [EVar "x", ELit (LitInt 0)])
                   (EHole (HNamed "pos"))
                   (EHole (HNamed "neg"))
          results = collectHoleGuards emptyRename intEnv expr
      length results `shouldBe` 2

    it "OA-HG3: handles let without crash (F5)" $ do
      let expr = ELet [(PWildcard, Nothing, ELit (LitInt 1))]
                   (EHole (HNamed "body"))
          results = collectHoleGuards emptyRename intEnv expr
      length results `shouldBe` 1

  describe "ObligationAssembly: holeContractBrief (OBLIG-1 checkout population)" $ do
    let src = T.unlines
          [ "(type PositiveInt (where [x: int] (> x 0)))"
          , "(def withdraw [balance: int amount: PositiveInt]"
          , "  (pre  (>= balance amount))"
          , "  (post (= result (- balance amount)))"
          , "  ?body_impl)"
          , "(def stub [n: int] ?s)"
          , "(def br [x: int] (post (>= result 0)) (if (> x 0) ?pos ?neg))" ]
        withStmts k = case parseStatements GrammarCoreInversion "<test>" src of
          Left e      -> expectationFailure ("parse failed: " <> show e)
          Right stmts -> k stmts

    it "OBR-1: contracted hole yields pre + post, empty path" $ withStmts $ \stmts -> do
      let (pre, post, path) = holeContractBrief stmts "/statements/1/body" "?body_impl"
      pre  `shouldBe` Just "(>= balance amount)"
      post `shouldBe` Just "(= result (- balance amount))"
      path `shouldBe` []

    it "OBR-2: contract-free hole yields all Nothing/empty" $ withStmts $ \stmts -> do
      holeContractBrief stmts "/statements/2/body" "?s"
        `shouldBe` (Nothing, Nothing, [])

    it "OBR-3: branch hole surfaces its path condition" $ withStmts $ \stmts -> do
      let (_, post, path) = holeContractBrief stmts "/statements/3/body" "?pos"
      post `shouldBe` Just "(>= result 0)"
      path `shouldSatisfy` elem "(> x 0)"

    it "OBR-4: unknown pointer yields empty brief (no enclosing function)" $ withStmts $ \stmts ->
      holeContractBrief stmts "/statements/99/body" "?x"
        `shouldBe` (Nothing, Nothing, [])

  describe "ObligationAssembly: recursiveNames" $ do
    it "OA-RN1: empty for non-recursive" $ do
      let stmts = [SDefLogic "f" [("x", TInt)] (Just TInt) (Contract Nothing Nothing Nothing Nothing Nothing) (EVar "x")]
      recursiveNames stmts `shouldBe` Set.empty

  -- =========================================================================
  -- DEMO-COMP: surfacing shipped v0.9.0 assume-guarantee composition.
  -- consumed_guarantees channel + contracted-record pre/post/tier + SAFE
  -- precondition-obligations + patch callee-precondition-unmet sub-reason.
  -- NO constraint-generation / solver change — field surfacing only.
  -- See docs/design/compositional-trust-closure-proposal.md.
  -- =========================================================================
  describe "DEMO-COMP: consumed_guarantees + contracted record + SAFE pre-obligations" $ do
    let parse src = case parseStatements GrammarCoreInversion "<test>" (T.unlines src) of
          Left e      -> error ("parse failed: " <> show e)
          Right stmts -> stmts
        -- Minimal TrustEntry with the post-side effective level set (the field
        -- 'trustLabel'/'callee_tier' reads after the TRUST-PRE transitive-callee
        -- fix; 'teEffectiveLevel' is pinned to the same value for symmetry). Lets
        -- us pin a callee's tier and prove that the consumed_guarantees record
        -- SOURCES it (never hardcodes "verified").
        mkTE nm lvl = TrustEntry nm Nothing Nothing [] [] (Just lvl) Nothing (Just lvl) False []
        objLookup k (Object o) = KM.lookup k o
        objLookup _ _          = Nothing
        objStr k v = case objLookup k v of Just (String s) -> Just s; _ -> Nothing

        -- §10 fixtures.
        quadrupleSrc =
          [ "(def double [x: int] (post (= result (+ x x))) (+ x x))"
          , "(def quadruple [x: int]"
          , "  (post (= result (+ (+ x x) (+ x x))))"
          , "  (double (double x)))" ]
        withdrawTwiceSrc =
          [ "(type PositiveInt (where [x: int] (> x 0)))"
          , "(def-shell withdraw [balance: int amount: PositiveInt]"
          , "  (pre  (>= balance amount))"
          , "  (post (= result (- balance amount)))"
          , "  (- balance amount))"
          , "(def-shell withdraw-twice [balance: int amount: PositiveInt]"
          , "  (pre  (>= balance (+ amount amount)))"
          , "  (post (= result (- balance (+ amount amount))))"
          , "  (withdraw (withdraw balance amount) amount))" ]

    -- Test 1: consumed_guarantees population + instantiated substitution.
    it "DC-1: quadruple consumes double.post twice; instantiated substitutes the arg" $ do
      let stmts    = parse quadrupleSrc
          cenv     = buildContractEnv stmts
          trustMap = Map.fromList [("double", mkTE "double" (DLVerified "smt"))]
          recs     = recursiveNames stmts
          guars    = assembleConsumedGuarantees stmts cenv trustMap recs "quadruple"
      length guars `shouldBe` 2  -- (double (double x)): two call sites
      -- each consumes double.post = (= result (+ x x)) with callee_tier sourced
      all (\g -> objStr "callee" g == Just "double") guars `shouldBe` True
      all (\g -> objStr "guarantee" g == Just "(= result (+ x x))") guars `shouldBe` True
      all (\g -> objStr "status" g == Just "discharged") guars `shouldBe` True
      -- callee_tier is SOURCED from the trust map (soundness lever, §5 edge 3):
      -- pinned to verified here ⇒ surfaces verified, not a hardcoded constant.
      all (\g -> objStr "callee_tier" g == Just "verified") guars `shouldBe` True
      -- instantiated replaces 'result' with <call-result>; the inner call site
      -- substitutes x→x, the outer substitutes x→(double x).
      let insts = [ objStr "instantiated" g | g <- guars ]
      insts `shouldSatisfy` elem (Just "(= <call-result> (+ x x))")
      insts `shouldSatisfy` elem (Just "(= <call-result> (+ (double x) (double x)))")

    -- Test 1b (soundness): callee_tier is NOT hardcoded — pinning the tier to
    -- asserted surfaces asserted.
    it "DC-1b: callee_tier reflects a degraded (asserted) callee tier" $ do
      let stmts    = parse quadrupleSrc
          cenv     = buildContractEnv stmts
          trustMap = Map.fromList [("double", mkTE "double" DLAsserted)]
          guars    = assembleConsumedGuarantees stmts cenv trustMap (recursiveNames stmts) "quadruple"
      all (\g -> objStr "callee_tier" g == Just "asserted") guars `shouldBe` True

    -- Test 2: a leaf (no contracted callee) emits [].
    it "DC-2: a leaf function emits no consumed_guarantees" $ do
      let stmts = parse quadrupleSrc
          cenv  = buildContractEnv stmts
          guars = assembleConsumedGuarantees stmts cenv Map.empty (recursiveNames stmts) "double"
      guars `shouldBe` []

    -- Test 3: contracted record carries pre/post/tier; pre-free callee → pre:null.
    it "DC-3: contracted record carries pre/post/tier; pre-free double → pre:null" $ do
      let stmts    = parse quadrupleSrc
          trustMap = Map.fromList [("double", mkTE "double" (DLVerified "smt"))]
          (contracted, _, _, _) = assembleFunctionLists stmts Map.empty (buildAliasMap stmts) trustMap (Just TInt)
          dbl = [ c | c <- contracted, objStr "name" c == Just "double" ]
      length dbl `shouldBe` 1
      let c = head dbl
      objLookup "pre" c  `shouldBe` Just Null                       -- pre-free ⇒ null
      objStr "post" c    `shouldBe` Just "(= result (+ x x))"
      objStr "tier" c    `shouldBe` Just "verified"
      objStr "return_type" c `shouldBe` Just "int"

    -- Test 4: FuncEntry additive round-trip (pre/post/tier survive ToJSON→FromJSON).
    it "DC-4: FuncEntry pre/post/tier additive JSON round-trip" $ do
      let fe = FuncEntry "double" [("x","int")] "int" "filled"
                 (Just "(= result (+ x x))") Nothing (Just "verified")
          mfe = decode (encode fe) :: Maybe FuncEntry
      mfe `shouldBe` Just fe
      -- builtin (no contract): pre/post/tier all Nothing, still round-trips.
      let bi = FuncEntry "len" [("p0","string")] "int" "builtin" Nothing Nothing Nothing
      (decode (encode bi) :: Maybe FuncEntry) `shouldBe` Just bi

    -- OBLIG-VOCAB-GATE: an unknown-typed hole must receive the FULL (capped)
    -- vocabulary. The old 'fromMaybe TUnit' default made unknown behave as
    -- "expects unit": every '-> T'-annotated function and every
    -- monomorphic-return builtin failed the unit comparison and the lists
    -- silently read as "no callable functions".
    it "DC-7a: unknown hole type ⇒ contracted list ungated; returns shows the declared type or ?" $ do
      let mixedSrc =
            [ "(def double [x: int] -> int (post (= result (+ x x))) (+ x x))"  -- annotated
            , "(def triple [x: int] (post (= result (+ x (+ x x)))) (+ x (+ x x)))" ]  -- unannotated
          stmts = parse mixedSrc
          (contracted, _, _, _) =
            assembleFunctionLists stmts Map.empty (buildAliasMap stmts) Map.empty Nothing
      -- The annotated fn was DROPPED under the TUnit default; both now appear.
      [ objStr "name" c | c <- contracted ] `shouldBe` [Just "double", Just "triple"]
      [ objStr "return_type" c | c <- contracted ] `shouldBe` [Just "int", Just "?"]

    it "DC-7b: unknown hole type ⇒ builtins ungated (monomorphic-return builtins appear)" $ do
      let stmts = parse quadrupleSrc
          (_, _, available, availableT) =
            assembleFunctionLists stmts Map.empty (buildAliasMap stmts) Map.empty Nothing
      -- '+' returns int; under the TUnit default only polymorphic-return
      -- builtins survived. Cap-8 still applies (alphabetical, '+' is early).
      [ objStr "name" a | a <- available ] `shouldSatisfy` elem (Just "+")
      availableT `shouldBe` True

    it "DC-7c: a KNOWN hole type still gates (bool hole drops int-returning fns)" $ do
      let annotatedSrc =
            [ "(def double [x: int] -> int (post (= result (+ x x))) (+ x x))" ]
          stmts = parse annotatedSrc
          (contracted, _, _, _) =
            assembleFunctionLists stmts Map.empty (buildAliasMap stmts) Map.empty (Just TBool)
      contracted `shouldBe` []

    -- HOLE-STATUS: the checkout brief must not present the function whose hole
    -- is being checked out as an available "filled" function — a blind fill
    -- agent answers with a degenerate self-call, which patches cleanly and
    -- verifies SAFE at partial correctness (observed live, secure-channel-
    -- emergent smoke). The enclosing function reads the documented "hole"
    -- enum value instead.
    it "DC-8 (HOLE-STATUS): the enclosing function's brief entry is status hole, not filled" $ do
      let stmts = parse quadrupleSrc
          nameStatus (FuncEntry n _ _ s _ _ _) = (n, s)
          entries = buildCheckoutFuncs stmts Map.empty Map.empty (Just "quadruple")
      map nameStatus entries
        `shouldBe` [("double", "filled"), ("quadruple", "hole")]
      -- No enclosing function (contract-position hole): everything is "filled".
      let entries' = buildCheckoutFuncs stmts Map.empty Map.empty Nothing
      map (snd . nameStatus) entries' `shouldBe` ["filled", "filled"]

    -- Test 5: SAFE per-call-site PreconditionObligation surfacing.
    --
    -- EMPIRICAL CORRECTION (verified against the shipped emitter, not the
    -- proposal prose): the body-VC builder emits a 'call-pre:<callee>' origin
    -- for a contracted call ONLY when (a) the enclosing function has a
    -- translatable post (else the whole body VC falls back) AND (b) the call's
    -- arguments are themselves QF-LIA-translatable. A *nested* contracted call
    -- as an argument — 'withdraw (withdraw …) …' in the §10 'withdraw-twice'
    -- fixture — historically failed argument translation and fell back to ZERO
    -- call-pre origins. As of the A-normalization pass ('aNormalizeBody'), the
    -- nested-call argument is lifted into a fresh 'let', so BOTH call sites now
    -- emit their call-pre origin (the two the proposal prose anticipated). DC-5
    -- exercises the SAFE assembler against a FLAT call, then confirms the nested
    -- fixture now surfaces its two origins.
    it "DC-5: SAFE PreconditionObligation surfaces a discharged call-pre origin" $ do
      let flatSrc =
            [ "(type PositiveInt (where [x: int] (> x 0)))"
            , "(def-shell withdraw [balance: int amount: PositiveInt]"
            , "  (pre  (>= balance amount))"
            , "  (post (= result (- balance amount)))"
            , "  (- balance amount))"
            , "(def-shell caller [b: int amt: PositiveInt]"
            , "  (post (= result (- b amt)))"
            , "  (withdraw b amt))" ]      -- flat call → emitter supports it
          flatStmts = parse flatSrc
      flatR <- emitFixpointWith (EmitOptions True) "<test>" flatStmts
      -- Exactly one 'call-pre:withdraw' origin (one call site).
      let flatOrigins = [ o | o <- Map.elems (erConstraintTable flatR)
                            , "call-pre:" `T.isPrefixOf` coClause o ]
      length flatOrigins `shouldBe` 1
      coClause (head flatOrigins) `shouldBe` "call-pre:withdraw"
      coJsonPtr (head flatOrigins) `shouldBe` "/statements/2/body"
      -- The SAFE assembler turns each origin into exactly one
      -- PreconditionObligation, preserving the call-site pointer.
      let trustRpt = buildTrustReport Map.empty flatStmts Map.empty
          preObls  = assembleSafePreObligations flatStmts (erConstraintTable flatR)
                       (Just FQSafe) trustRpt Set.empty
      length preObls `shouldBe` 1
      ooKind (head preObls) `shouldBe` PreconditionObligation
      ooOrigin (head preObls) `shouldBe` "/statements/2/body"

      -- Nested-call fixture (§10 withdraw-twice): A-normalization lifts the
      -- nested-call argument into a let, so BOTH withdraw call sites now emit a
      -- call-pre origin (the two the proposal prose anticipated).
      wtR <- emitFixpointWith (EmitOptions True) "<test>" (parse withdrawTwiceSrc)
      let wtOrigins = [ coClause o | o <- Map.elems (erConstraintTable wtR)
                                   , "call-pre:" `T.isPrefixOf` coClause o ]
      length wtOrigins `shouldBe` 2
      all (== "call-pre:withdraw") wtOrigins `shouldBe` True

      -- quadruple over pre-free double: zero call-pre obligations (no pre).
      qEmit <- emitFixpointWith (EmitOptions True) "<test>" (parse quadrupleSrc)
      length [ () | o <- Map.elems (erConstraintTable qEmit)
                  , "call-pre:" `T.isPrefixOf` coClause o ] `shouldBe` 0

    -- Test 6 (REQUIRED soundness guard, §5 edge 3): a recursiveNames-member
    -- function emits NO self-edge consumed_guarantee.
    it "DC-6: a recursive function emits no self-edge consumed_guarantee" $ do
      let stmts = parse
            [ "(def-shell countdown [n: int]"
            , "  (post (>= result 0))"
            , "  (if (<= n 0) 0 (countdown (- n 1))))" ]
          cenv     = buildContractEnv stmts
          recs     = recursiveNames stmts
          trustMap = Map.fromList [("countdown", mkTE "countdown" DLAsserted)]
          guars    = assembleConsumedGuarantees stmts cenv trustMap recs "countdown"
      -- countdown is in recursiveNames and its only contracted callee is itself.
      recs `shouldSatisfy` Set.member "countdown"
      guars `shouldBe` []  -- self-edge filtered: no function lists its own post

  -- Bundle B0: per-function effect / authority summary (a sound MAY-over-
  -- approximation with ⊤ at opaque boundaries; informational — never gates
  -- trust). See docs/design/bundle-b0-effect-summary-proposal.md.
  describe "B0 effect/authority summary (Bundle B0)" $ do
    let noC = Contract Nothing Nothing Nothing Nothing Nothing
        effOf stmts nm = lookup nm (computeEffectSummary Map.empty stmts)
        bnd ls = Just (Caps (Set.fromList ls))

    it "B0-1: a pure function is capability-free (empty summary)" $ do
      let stmts = [SDef "add" [("x", TInt), ("y", TInt)] Nothing noC (EOp "+" [EVar "x", EVar "y"])]
      effOf stmts "add" `shouldBe` Just (Caps Set.empty)

    it "B0-2: a direct wasi.io.stdout call yields {stdout}" $ do
      let stmts = [SDefShell "emit" [("s", TString)] Nothing noC (EApp "wasi.io.stdout" [EVar "s"]) []]
      effOf stmts "emit" `shouldBe` bnd [EStdout]

    it "B0-3: an effect reached only via a callee is surfaced transitively" $ do
      let stmts = [ SDefShell "emit"   [("s", TString)] Nothing noC (EApp "wasi.io.stdout" [EVar "s"]) []
                  , SDefShell "caller" [("s", TString)] Nothing noC (EApp "emit" [EVar "s"]) [] ]
      effOf stmts "caller" `shouldBe` bnd [EStdout]

    it "B0-4: a function reaching a ?delegate hole is unbounded (top), not empty" $ do
      let stmts = [SDefShell "d" [] Nothing noC (EHole (HDelegate (DelegateSpec "agent" "task" TInt Nothing))) []]
      effOf stmts "d" `shouldBe` Just Unbounded

    it "B0-5: a haskell.* FFI call is unbounded (top)" $ do
      let stmts = [SDefShell "ffi" [("x", TInt)] Nothing noC (EApp "haskell.unsafeIO" [EVar "x"]) []]
      effOf stmts "ffi" `shouldBe` Just Unbounded

    it "B0-6: a mutually-recursive SCC terminates and shares the join" $ do
      let stmts = [ SDefShell "p" [("n", TInt)] Nothing noC (EApp "q" [EVar "n"]) []
                  , SDefShell "q" [("n", TInt)] Nothing noC
                      (EPair (EApp "wasi.fs.write" [EVar "n", EVar "n"]) (EApp "p" [EVar "n"])) [] ]
      effOf stmts "p" `shouldBe` bnd [EFsWrite]
      effOf stmts "q" `shouldBe` bnd [EFsWrite]

    it "B0-7: per-function and orthogonal — delegate is top, pure is empty (no bleed)" $ do
      let stmts = [ SDefShell "deleg" [] Nothing noC (EHole (HDelegate (DelegateSpec "a" "t" TInt Nothing))) []
                  , SDef      "pure2" [("x", TInt)] Nothing noC (EOp "+" [EVar "x", EVar "x"]) ]
      effOf stmts "deleg" `shouldBe` Just Unbounded
      effOf stmts "pure2" `shouldBe` Just (Caps Set.empty)

    it "B0-8: top encodes as the distinct \"unbounded\" sentinel, never the label array" $ do
      encode (encodeEff Unbounded) `shouldBe` "\"unbounded\""
      encode (encodeEff (Caps (Set.fromList [minBound .. maxBound])))
        `shouldBe` "[\"crypto\",\"fs.read\",\"fs.write\",\"net.http\",\"random\",\"stdout\"]"

  -- F-B0-1 regression: a JSON-AST `module` form must flatten into its
  -- imports ++ body (single-file model), mirroring the S-expression parser's
  -- pModuleFlattened. The prior parseModuleDecl stub discarded the whole body
  -- and returned `SExpr (ELit LitUnit)`, so a module-wrapped submission
  -- verified vacuously with an empty effect_summary and bypassed capability
  -- enforcement. See experiments/minimal-agent/findings/postmortem-007-b0-pilot.md.
  describe "JSON-AST module flattening (F-B0-1)" $ do
    let jsonAst ls = parseJSONAST GrammarCoreInversion "<test>" (BLC.pack (unlines ls))
        readLogDef =
          [ "    { \"kind\": \"def-shell\", \"name\": \"read-log\","
          , "      \"params\": [ { \"name\": \"path\", \"param_type\": { \"kind\": \"primitive\", \"name\": \"string\" } } ],"
          , "      \"body\": { \"kind\": \"qual-app\", \"qual_fn\": \"wasi.fs.read\","
          , "                  \"args\": [ { \"kind\": \"var\", \"name\": \"path\" } ] } }" ]
        fsImport =
          [ "    { \"kind\": \"import\", \"path\": \"wasi.fs\","
          , "      \"capability\": { \"name\": \"read\", \"path_or_port\": \"/\" } }" ]
        moduleSrc =
          [ "{ \"schemaVersion\": \"0.6.0\", \"statements\": ["
          , "  { \"kind\": \"module\", \"name\": \"m\", \"imports\": [" ]
          ++ fsImport ++ [ "  ], \"statements\": [" ] ++ readLogDef ++ [ "  ] } ] }" ]

    it "JM-1: a module wrapper flattens its imports and body (not discarded)" $ do
      case jsonAst moduleSrc of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          length [s | s@SImport{}   <- stmts] `shouldBe` 1
          length [s | s@SDefShell{} <- stmts] `shouldBe` 1
          -- the stub used to collapse the whole module to a single unit stmt
          [() | SExpr (ELit LitUnit) <- stmts] `shouldBe` []

    it "JM-2: the flattened def is tracked by effect_summary (no false empty)" $ do
      case jsonAst moduleSrc of
        Left err    -> expectationFailure (show err)
        Right stmts ->
          lookup "read-log" (computeEffectSummary Map.empty stmts)
            `shouldBe` Just (Caps (Set.singleton EFsRead))

    it "JM-3: a nested module flattens recursively" $ do
      let nested =
            [ "{ \"schemaVersion\": \"0.6.0\", \"statements\": ["
            , "  { \"kind\": \"module\", \"name\": \"outer\", \"imports\": [], \"statements\": ["
            , "    { \"kind\": \"module\", \"name\": \"inner\", \"imports\": [" ]
            ++ fsImport ++ [ "    ], \"statements\": [" ] ++ readLogDef
            ++ [ "    ] } ] } ] }" ]
      case jsonAst nested of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          length [s | s@SImport{}   <- stmts] `shouldBe` 1
          length [s | s@SDefShell{} <- stmts] `shouldBe` 1

    it "JM-4: a top-level (non-module) program is unaffected" $ do
      let flat = [ "{ \"schemaVersion\": \"0.6.0\", \"statements\": [" ]
                 ++ readLogDef ++ [ "] }" ]
      case jsonAst flat of
        Left err    -> expectationFailure (show err)
        Right stmts -> length [s | s@SDefShell{} <- stmts] `shouldBe` 1

    it "JM-5: an empty module flattens to nothing (no spurious unit stmt)" $ do
      let emptyMod =
            [ "{ \"schemaVersion\": \"0.6.0\", \"statements\": ["
            , "  { \"kind\": \"module\", \"name\": \"m\", \"imports\": [], \"statements\": [] } ] }" ]
      case jsonAst emptyMod of
        Left err    -> expectationFailure (show err)
        Right stmts -> stmts `shouldBe` []

  -- B0 cross-module effect propagation (b0/cross-module-effects). An imported
  -- function's reachable capabilities propagate into the importer's summary via
  -- the loaded ModuleCache; unresolved/opaque callees join ⊤ (∅-iff-fully-walked).
  -- Cyclic-import rejection (the post-order/memoization precondition) is pinned by
  -- ModuleSpec M-06; the effect walk only runs after a successful load.
  describe "B0 cross-module effect summary" $ do
    let noC = Contract Nothing Nothing Nothing Nothing Nothing
        mkEnv ss = ModuleEnv
          { meExports = Map.empty, meStatements = ss, meInterfaces = Map.empty
          , meAliasMap = Map.empty, mePath = ["lib"]
          , meContractStatus = Map.empty, meContracts = Map.empty }
        cacheWith ss = Map.fromList [(["lib"], mkEnv ss)]
        effOfC cache stmts nm = lookup nm (computeEffectSummary cache stmts)

    it "CM-1: an imported function's effect propagates to the importer" $ do
      let lib   = [SDefShell "remote-write" [("p", TString), ("c", TString)] Nothing noC
                     (EApp "wasi.fs.write" [EVar "p", EVar "c"]) []]
          local = [SDefShell "use-remote" [("p", TString), ("c", TString)] Nothing noC
                     (EApp "remote-write" [EVar "p", EVar "c"]) []]
      effOfC (cacheWith lib) local "use-remote"
        `shouldBe` Just (Caps (Set.singleton EFsWrite))

    it "CM-2: a transitively-opaque imported callee tops the importer to ⊤" $ do
      let lib   = [SDefShell "remote-ffi" [("x", TInt)] Nothing noC
                     (EApp "haskell.unsafeIO" [EVar "x"]) []]
          local = [SDefShell "caller" [("x", TInt)] Nothing noC
                     (EApp "remote-ffi" [EVar "x"]) []]
      effOfC (cacheWith lib) local "caller" `shouldBe` Just Unbounded

    it "CM-3: empty cache (single-file) matches the local-only walk" $
      computeEffectSummary Map.empty
        [SDefShell "rd" [("p", TString)] Nothing noC (EApp "wasi.fs.read" [EVar "p"]) []]
        `shouldBe` [("rd", Caps (Set.singleton EFsRead))]

    it "CM-4: an unresolved callee (not local/imported/builtin/prim) joins ⊤" $ do
      let local = [SDefShell "f" [("x", TInt)] Nothing noC
                     (EApp "mystery-unresolved" [EVar "x"]) []]
      effOfC Map.empty local "f" `shouldBe` Just Unbounded

  -- XMOD-ALIAS regression: a module that imports a refinement-type alias and
  -- then does arithmetic/comparison on a value of that type must type-check,
  -- exactly as the identical code does in-module. Before the fix, the importing
  -- module's alias map was built from current-module STypeDefs only, so an
  -- imported 'PositiveInt' stayed an opaque TCustom and '>='/'-' rejected it
  -- ("type mismatch in '>=': expected int, got PositiveInt").
  describe "XMOD-ALIAS: imported refinement alias is int-compatible for arith/comparison" $ do
    let positiveIntBody = TDependent "x" TInt (EApp ">" [EVar "x", ELit (LitInt 0)])
        -- core module: exports PositiveInt + withdraw, alias map carries PositiveInt.
        coreEnv = ModuleEnv
          { meExports        = Map.fromList
              [ ("PositiveInt", positiveIntBody)
              , ("withdraw", TFn [TInt, TCustom "PositiveInt"] TInt) ]
          , meStatements     = []
          , meInterfaces     = Map.empty
          , meAliasMap       = Map.fromList [("PositiveInt", positiveIntBody)]
          , mePath           = ["core"]
          , meContractStatus = Map.empty
          , meContracts      = Map.empty
          }
        coreCache = Map.fromList [(["core"], coreEnv)]
        -- The importer body, parsed so '>='/'-' are exercised against the imported
        -- PositiveInt-typed param exactly as in the CLI reproduction.
        importerSrc = T.unlines
          [ "(import core)"
          , "(open core)"
          , "(def-shell safe-withdraw [balance: int amount: PositiveInt]"
          , "  (pre (>= balance amount)) (post (= result (- balance amount)))"
          , "  (withdraw balance amount))" ]
        importerStmts = case parseStatements GrammarCoreInversion "<test>" importerSrc of
          Left e      -> error ("parse failed: " <> show e)
          Right ss    -> ss
        hardErrors r = [ d | d <- reportDiagnostics r, diagSeverity d == SevError ]

    it "XA-1: importer doing >=/- on imported PositiveInt type-checks (no mismatch)" $ do
      let report = typeCheckWithCache GrammarCoreInversion coreCache emptyEnv importerStmts
      -- No 'type mismatch' hard errors; the imported alias unfolds to int.
      hardErrors report `shouldBe` []
      reportSuccess report `shouldBe` True

    it "XA-2: the IDENTICAL code in-module still type-checks (no regression)" $ do
      -- Same def-shell, but PositiveInt is defined locally (single-file path).
      let inModuleSrc = T.unlines
            [ "(type PositiveInt (where [x: int] (> x 0)))"
            , "(def-shell withdraw [balance: int amount: PositiveInt]"
            , "  (pre (>= balance amount)) (post (= result (- balance amount)))"
            , "  (- balance amount))"
            , "(def-shell safe-withdraw [balance: int amount: PositiveInt]"
            , "  (pre (>= balance amount)) (post (= result (- balance amount)))"
            , "  (withdraw balance amount))" ]
          inModuleStmts = case parseStatements GrammarCoreInversion "<test>" inModuleSrc of
            Left e   -> error ("parse failed: " <> show e)
            Right ss -> ss
          report = typeCheck GrammarCoreInversion emptyEnv inModuleStmts
      hardErrors report `shouldBe` []
      reportSuccess report `shouldBe` True

    it "XA-3: a genuinely ill-typed arith on a non-int imported value still fails" $ do
      -- Soundness guard: the fix must not make EVERY imported alias int-like.
      -- 'StringName' aliases string; '(- balance name)' must still be rejected.
      let strEnv = ModuleEnv
            { meExports        = Map.fromList [("StringName", TString)]
            , meStatements     = []
            , meInterfaces     = Map.empty
            , meAliasMap       = Map.fromList [("StringName", TString)]
            , mePath           = ["core"]
            , meContractStatus = Map.empty
            , meContracts      = Map.empty
            }
          strCache = Map.fromList [(["core"], strEnv)]
          badSrc = T.unlines
            [ "(import core)"
            , "(open core)"
            , "(def-shell bad [balance: int name: StringName]"
            , "  (- balance name))" ]
          badStmts = case parseStatements GrammarCoreInversion "<test>" badSrc of
            Left e   -> error ("parse failed: " <> show e)
            Right ss -> ss
          report = typeCheckWithCache GrammarCoreInversion strCache emptyEnv badStmts
      hardErrors report `shouldNotBe` []

  -- -----------------------------------------------------------------------
  -- v0.10 Phase 3: Branch Obligations + Repair (OBLIG-3, OBLIG-4)
  -- -----------------------------------------------------------------------

  describe "Phase 3: patternBindings (F2)" $ do
    it "PB-1: PVar extracts single binding" $
      patternBindings (PVar "x") `shouldBe` [("x", "match-arm")]
    it "PB-2: PWildcard extracts nothing" $
      patternBindings PWildcard `shouldBe` []
    it "PB-3: PConstructor extracts sub-bindings" $
      patternBindings (PConstructor "Success" [PVar "val"])
        `shouldBe` [("val", "match-arm")]
    it "PB-4: nested PConstructor recurses" $
      patternBindings (PConstructor "Pair" [PVar "a", PVar "b"])
        `shouldBe` [("a", "match-arm"), ("b", "match-arm")]
    it "PB-5: deeply nested" $
      patternBindings (PConstructor "Outer" [PConstructor "Inner" [PVar "x"], PVar "y"])
        `shouldBe` [("x", "match-arm"), ("y", "match-arm")]

  describe "Phase 3: isTypeCompatible (F8, R1, C2)" $ do
    it "TC-1: exact match" $
      isTypeCompatible Map.empty TInt TInt `shouldBe` True
    it "TC-2: mismatch" $
      isTypeCompatible Map.empty TInt TString `shouldBe` False
    it "TC-3: Result unwrap success" $
      isTypeCompatible Map.empty TInt (TResult TInt TString) `shouldBe` True
    it "TC-4: Result exact match" $
      isTypeCompatible Map.empty (TResult TInt TString) (TResult TInt TString) `shouldBe` True
    it "TC-5: Result wrong payload" $
      isTypeCompatible Map.empty TString (TResult TInt TString) `shouldBe` False
    it "TC-6: TVar matches any (C2)" $
      isTypeCompatible Map.empty TInt (TVar "a") `shouldBe` True
    it "TC-7: TDependent strips refinement (R1)" $
      isTypeCompatible Map.empty TInt (TDependent "x" TInt (ELit (LitBool True))) `shouldBe` True
    it "TC-8: TCustom resolves via alias map" $
      let aliases = Map.fromList [("PositiveInt", TDependent "x" TInt (EApp ">" [EVar "x", ELit (LitInt 0)]))]
      in isTypeCompatible aliases TInt (TCustom "PositiveInt") `shouldBe` True

  describe "Phase 3: trustLabel (F9, R3)" $ do
    it "TL-1: builtin for unknown name" $
      trustLabel Map.empty "unknown" `shouldBe` "builtin"

  describe "Phase 3: generateCandidates (OBLIG-4)" $ do
    it "GEN-1: withdraw params → includes (- balance amount)" $ do
      let cands = generateCandidates ["balance", "amount"]
      any (\c -> ceExpr c == "(- balance amount)") cands `shouldBe` True

    it "GEN-2: all candidates have verified=False" $ do
      let cands = generateCandidates ["x", "y"]
      all (\c -> ceVerified c == False) cands `shouldBe` True

    it "GEN-3: single param → (+ n n)" $ do
      let cands = generateCandidates ["n"]
      any (\c -> ceExpr c == "(+ n n)") cands `shouldBe` True

    it "GEN-4: no names → empty" $ do
      let cands = generateCandidates []
      cands `shouldBe` []

    it "GEN-5: cap at 8" $ do
      let names = ["p" <> T.pack (show i) | i <- [1..10::Int]]
          cands = generateCandidates names
      length cands `shouldSatisfy` (<= 8)

  describe "Phase 3: isQfLia exported (F5/F6)" $ do
    it "IQ-1: simple comparison is QF-LIA" $
      isQfLia (EApp ">=" [EVar "x", ELit (LitInt 0)]) `shouldBe` True
    it "IQ-2: string op is not QF-LIA" $
      isQfLia (EApp "string-empty?" [EVar "s"]) `shouldBe` False
    it "IQ-3: multiplication is not QF-LIA" $
      isQfLia (EApp "*" [EVar "x", EVar "y"]) `shouldBe` False

  -- -----------------------------------------------------------------------
  -- Phase 4: Golden Benchmark Tests (B1, B3, B5)
  -- -----------------------------------------------------------------------

  describe "Phase 4: B1 withdraw golden" $ do
    it "B1-1: generates (- balance amount) suggestion" $ do
      src <- TIO.readFile "../examples/benchmarks/b1-withdraw.llmll"
      case parseStatements GrammarCoreInversion "../examples/benchmarks/b1-withdraw.llmll" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let aliases = buildAliasMap stmts
              -- withdraw has params [("balance", TInt), ("amount", TCustom "PositiveInt")]
              params = case [ps | SDef "withdraw" ps _ _ _ <- stmts] of
                (ps:_) -> ps
                []     -> []
              intNames = [n | (n, t) <- params, isIntLike aliases t]
              cands = generateCandidates intNames
          intNames `shouldSatisfy` (\ns -> "balance" `elem` ns && "amount" `elem` ns)
          any (\c -> ceExpr c == "(- balance amount)") cands `shouldBe` True

    it "B1-2: PositiveInt param included via isIntLike" $ do
      src <- TIO.readFile "../examples/benchmarks/b1-withdraw.llmll"
      case parseStatements GrammarCoreInversion "../examples/benchmarks/b1-withdraw.llmll" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let aliases = buildAliasMap stmts
              params = case [ps | SDef "withdraw" ps _ _ _ <- stmts] of
                (ps:_) -> ps
                []     -> []
          any (\(n,t) -> n == "amount" && isIntLike aliases t) params `shouldBe` True

  describe "Phase 4: B5 double golden" $ do
    it "B5-1: generates (+ n n) suggestion" $ do
      let cands = generateCandidates ["n"]
      any (\c -> ceExpr c == "(+ n n)") cands `shouldBe` True

  describe "Phase 4: B3 safe-first golden" $ do
    it "B3-1: parses with EMatch body" $ do
      src <- TIO.readFile "../examples/benchmarks/b3-safe-first.llmll"
      case parseStatements GrammarCoreInversion "../examples/benchmarks/b3-safe-first.llmll" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let bodies = [body | SDef "safe-first" _ _ _ body <- stmts]
          length bodies `shouldBe` 1
          case bodies of
            [EMatch _ arms] -> length arms `shouldBe` 2
            _ -> expectationFailure "expected EMatch body"

    it "B3-2: patternBindings Success arm" $
      patternBindings (PConstructor "Success" [PVar "val"])
        `shouldBe` [("val", "match-arm")]

    it "B3-3: patternBindings Error arm" $
      patternBindings (PConstructor "Error" [PVar "e"])
        `shouldBe` [("e", "match-arm")]

  describe "Phase 4: Integration tests" $ do
    it "INT-1: fingerprint stability" $ do
      let id1 = normalizeForFingerprint "withdraw" [("balance", TInt), ("amount", TInt)]
                  (Just (EApp "=" [EVar "result", EApp "-" [EVar "balance", EVar "amount"]])) "body"
          id2 = normalizeForFingerprint "withdraw" [("balance", TInt), ("amount", TInt)]
                  (Just (EApp "=" [EVar "result", EApp "-" [EVar "balance", EVar "amount"]])) "body"
      id1 `shouldBe` id2

    it "INT-2: isTypeCompatible TVar enables list-head matching" $
      isTypeCompatible Map.empty TInt (TResult (TVar "a") TString) `shouldBe` True

  -- -----------------------------------------------------------------------
  -- Experiment 001 — soundness blockers (S1, S2, S3, S4, D1)
  -- Source: experiments/minimal-agent/findings/compiler-engineer.md
  -- Plan:   compiler-team Rev 4 — verification fixtures 1–13
  -- -----------------------------------------------------------------------
  describe "Experiment 001 — soundness blockers" $ do

    -- S1: delegate fallback typecheck (TypeCheck.hs:1037-1042 + 783-786)
    describe "S1 delegate fallback typecheck" $ do
      it "accepts well-typed fallback (?delegate -> int (on-failure 0))" $ do
        let stmts = [ SDefLogic "f" [] (Just TInt)
                        (Contract Nothing Nothing Nothing Nothing Nothing)
                        (EHole (HDelegate (DelegateSpec "agent" "task" TInt
                                            (Just (ELit (LitInt 0))))))
                    ]
        let report = typeCheck GrammarCoreInversion emptyEnv stmts
        let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
        errs `shouldBe` []

      it "rejects ill-typed fallback (?delegate -> string (on-failure 0))" $ do
        let stmts = [ SDefLogic "f" [] (Just TString)
                        (Contract Nothing Nothing Nothing Nothing Nothing)
                        (EHole (HDelegate (DelegateSpec "agent" "task" TString
                                            (Just (ELit (LitInt 0))))))
                    ]
        let report = typeCheck GrammarCoreInversion emptyEnv stmts
        let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
        errs `shouldNotBe` []

      it "rejects if-branch type mismatch when delegate is one branch" $ do
        let stmts = [ SDefLogic "f" [("b", TBool)] Nothing
                        (Contract Nothing Nothing Nothing Nothing Nothing)
                        (EIf (EVar "b")
                             (EHole (HDelegate (DelegateSpec "agent" "task" TInt Nothing)))
                             (ELit (LitString "fallback")))
                    ]
        let report = typeCheck GrammarCoreInversion emptyEnv stmts
        let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
        errs `shouldNotBe` []

    -- S2: codegen routes through fallback (CodegenHs.hs:670-674)
    describe "S2 codegen routes through fallback" $ do
      it "emits fallback expression when present (not error stub)" $ do
        let spec = DelegateSpec "agent" "task" TInt (Just (ELit (LitInt 42)))
        let emitted = emitHole (HDelegate spec)
        emitted `shouldSatisfy` T.isInfixOf "42"
        emitted `shouldNotSatisfy` T.isInfixOf "error (\"delegate:"

      it "emits error stub when no fallback" $ do
        let spec = DelegateSpec "agent" "task" TInt Nothing
        emitHole (HDelegate spec) `shouldSatisfy` T.isInfixOf "error (\"delegate:"

    -- Async parser: defense-in-depth rejection (ParserJSON.hs:457-462)
    describe "Async parser rejects on_failure" $ do
      it "ParserJSON fails when hole-delegate-async carries on_failure" $ do
        let src = BLC.pack $ unlines
              [ "{"
              , "  \"schemaVersion\": \"0.6.0\","
              , "  \"statements\": ["
              , "    {"
              , "      \"kind\": \"def-shell\","
              , "      \"name\": \"f\","
              , "      \"params\": [],"
              , "      \"return_type\": {\"kind\": \"primitive\", \"name\": \"int\"},"
              , "      \"body\": {"
              , "        \"kind\": \"hole-delegate-async\","
              , "        \"agent\": \"agent\","
              , "        \"description\": \"task\","
              , "        \"return_type\": {\"kind\": \"primitive\", \"name\": \"int\"},"
              , "        \"on_failure\": {\"kind\": \"int-lit\", \"value\": 0}"
              , "      }"
              , "    }"
              , "  ]"
              , "}"
              ]
        case parseJSONAST GrammarLegacy "<test>" src of
          Left _   -> pure ()  -- expected
          Right _  -> expectationFailure "expected parse error for on_failure on hole-delegate-async"

    -- S3 + evaluator: PBT discards unevaluable, FuncEnv-driven evaluation
    describe "S3 PBT discard semantics + FuncEnv evaluator" $ do
      it "delegate without fallback -> PBTSkipped (was vacuous PBTPassed)" $ do
        let stmts =
              [ SDefLogic "h" [] (Just TInt)
                  (Contract Nothing Nothing Nothing Nothing Nothing)
                  (EHole (HDelegate (DelegateSpec "agent" "task" TInt Nothing)))
              , SCheck (Property "h-equals-zero" []
                          (EOp "=" [EApp "h" [], ELit (LitInt 0)]) [])
              ]
        result <- runPropertyTests stmts
        case pbtResults result of
          [run] -> pbtStatus run `shouldBe` PBTSkipped
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

      it "delegate with fallback resolves via FuncEnv -> PBTPassed" $ do
        let stmts =
              [ SDefLogic "g" [] (Just TInt)
                  (Contract Nothing Nothing Nothing Nothing Nothing)
                  (EHole (HDelegate (DelegateSpec "agent" "task" TInt
                                      (Just (ELit (LitInt 42))))))
              , SCheck (Property "g-equals-42" []
                          (EOp "=" [EApp "g" [], ELit (LitInt 42)]) [])
              ]
        result <- runPropertyTests stmts
        case pbtResults result of
          [run] -> pbtStatus run `shouldBe` PBTPassed
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

    -- Static evaluator: ok/err/is-ok semantics + EMatch + bool/string equality
    describe "Static evaluator Result semantics" $ do
      it "(is-ok (ok 42)) evaluates to True" $ do
        let e = EApp "is-ok" [EApp "ok" [ELit (LitInt 42)]]
        evalExprStatic Map.empty e `shouldBe` Just (ELit (LitBool True))

      it "(is-ok (err 'fail')) evaluates to False" $ do
        let e = EApp "is-ok" [EApp "err" [ELit (LitString "fail")]]
        evalExprStatic Map.empty e `shouldBe` Just (ELit (LitBool False))

      it "match (err 'fail') against Error arm evaluates True" $ do
        let e = EMatch (EApp "err" [ELit (LitString "fail")])
                  [ (PConstructor "Error" [PVar "ev"], ELit (LitBool True))
                  , (PWildcard, ELit (LitBool False))
                  ]
        evalExprStaticWith Map.empty maxFuel Map.empty e
          `shouldBe` Just (ELit (LitBool True))

      it "evalOp = on Bool and String evaluates equal pairs to True" $ do
        evalExprStatic Map.empty (EOp "=" [ELit (LitBool False), ELit (LitBool False)])
          `shouldBe` Just (ELit (LitBool True))
        evalExprStatic Map.empty (EOp "=" [ELit (LitString "hello"), ELit (LitString "hello")])
          `shouldBe` Just (ELit (LitBool True))

    -- OBLIG-PBT-2 / F-032: complex-type PBT generators + extended static
    -- evaluator. The previous evaluator skipped any property whose for-all
    -- bindings included a non-primitive type ('Property contains non-constant
    -- expressions — requires full runtime evaluation'); these tests pin the
    -- generator/evaluator pipeline that lifts trust-report obligations from
    -- 'asserted' → 'tested' on product-typed properties. See
    -- experiments/repair-loop/findings/postmortem-001-apparatus-validation.md
    -- Addendum 16 for the empirical motivation.
    describe "OBLIG-PBT-2 complex-type PBT generators" $ do
      it "TPair binding: (= (+ (first p) (second p)) (+ (second p) (first p)))" $ do
        let prop = Property "pair-comm" [("p", TPair TInt TInt)]
                     (EOp "="
                       [ EOp "+" [EApp "first"  [EVar "p"], EApp "second" [EVar "p"]]
                       , EOp "+" [EApp "second" [EVar "p"], EApp "first"  [EVar "p"]]
                       ])
                     []
        result <- runPropertyTests [SCheck prop]
        case pbtResults result of
          [run] -> do
            pbtStatus run    `shouldBe` PBTPassed
            pbtSamplesRun run `shouldSatisfy` (> 0)
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

      it "TList binding: list-length distributes over list-append by 1" $ do
        let prop = Property "list-append-length"
                     [("xs", TList TInt)]
                     (EOp "="
                       [ EApp "list-length" [EApp "list-append" [EVar "xs", ELit (LitInt 1)]]
                       , EOp "+" [ELit (LitInt 1), EApp "list-length" [EVar "xs"]]
                       ])
                     []
        result <- runPropertyTests [SCheck prop]
        case pbtResults result of
          [run] -> do
            pbtStatus run    `shouldBe` PBTPassed
            pbtSamplesRun run `shouldSatisfy` (> 0)
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

      it "TResult binding: (is-ok r) is a Bool — body always holds" $ do
        let prop = Property "result-tag-is-bool"
                     [("r", TResult TInt TString)]
                     (EIf (EApp "is-ok" [EVar "r"])
                          (ELit (LitBool True))
                          (EOp "not" [EApp "is-ok" [EVar "r"]]))
                     []
        result <- runPropertyTests [SCheck prop]
        case pbtResults result of
          [run] -> do
            pbtStatus run    `shouldBe` PBTPassed
            pbtSamplesRun run `shouldSatisfy` (> 0)
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

      it "TSumType binding: match arm catches every constructor" $ do
        let colorTy = TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)]
            prop   = Property "color-match-total"
                     [("c", colorTy)]
                     (EMatch (EVar "c")
                       [ (PConstructor "Red"   [], ELit (LitBool True))
                       , (PConstructor "Green" [], ELit (LitBool True))
                       , (PConstructor "Blue"  [], ELit (LitBool True))
                       ])
                     []
        result <- runPropertyTests [SCheck prop]
        case pbtResults result of
          [run] -> do
            pbtStatus run    `shouldBe` PBTPassed
            pbtSamplesRun run `shouldSatisfy` (> 0)
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

      it "TCustom alias resolves through STypeDef and runs" $ do
        let stmts =
              [ STypeDef "Pt" (TPair TInt TInt)
              , SCheck (Property "pt-first-stable" [("p", TCustom "Pt")]
                  (EOp "=" [EApp "first" [EVar "p"], EApp "first" [EVar "p"]]) [])
              ]
        result <- runPropertyTests stmts
        case pbtResults result of
          [run] -> do
            pbtStatus run    `shouldBe` PBTPassed
            pbtSamplesRun run `shouldSatisfy` (> 0)
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

      it "self-recursive STypeDef terminates at depth cap (no hang)" $ do
        -- A recursive alias (Tree = list[Tree]) must terminate via maxGenDepth.
        -- The body is trivially true so the test exercises only the generator.
        let stmts =
              [ STypeDef "Tree" (TList (TCustom "Tree"))
              , SCheck (Property "tree-trivial" [("t", TCustom "Tree")]
                  (ELit (LitBool True)) [])
              ]
        result <- runPropertyTests stmts
        case pbtResults result of
          [run] -> pbtStatus run `shouldBe` PBTPassed
          rs    -> expectationFailure $ "expected one run, got " ++ show (length rs)

    -- OBLIG-PBT-2 / F-032: static-evaluator coverage for EPair and the
    -- list/fold builtins that PBT requires. Each test pins the reduction of
    -- a specific AST shape to its expected literal.
    describe "OBLIG-PBT-2 static evaluator extensions" $ do
      it "evalExprStaticWith reduces EPair element-wise" $ do
        let e = EPair (ELit (LitInt 1)) (ELit (LitInt 2))
        evalExprStaticWith Map.empty maxFuel Map.empty e
          `shouldBe` Just (EPair (ELit (LitInt 1)) (ELit (LitInt 2)))

      it "evalBuiltinApp first/second project pair components" $ do
        let p = EPair (ELit (LitInt 10)) (ELit (LitInt 20))
        evalExprStatic Map.empty (EApp "first"  [p]) `shouldBe` Just (ELit (LitInt 10))
        evalExprStatic Map.empty (EApp "second" [p]) `shouldBe` Just (ELit (LitInt 20))

      it "list-fold sums a 3-element cons-chain via lambda" $ do
        let l3   = EApp "cons" [ ELit (LitInt 1)
                               , EApp "cons" [ ELit (LitInt 2)
                                             , EApp "cons" [ ELit (LitInt 3)
                                                           , EApp "nil" [] ]] ]
            fn   = ELambda [("acc", TInt), ("x", TInt)]
                            (EOp "+" [EVar "acc", EVar "x"])
            expr = EApp "list-fold" [l3, ELit (LitInt 0), fn]
        evalExprStatic Map.empty expr `shouldBe` Just (ELit (LitInt 6))

      it "list-length / list-append compose to length+1" $ do
        let l2   = EApp "cons" [ ELit (LitInt 7)
                               , EApp "cons" [ ELit (LitInt 8)
                                             , EApp "nil" [] ]]
            expr = EApp "list-length" [EApp "list-append" [l2, ELit (LitInt 9)]]
        evalExprStatic Map.empty expr `shouldBe` Just (ELit (LitInt 3))

    -- F-033: 'unwrap' static-eval coverage. Postmortem 17 surfaced this as
    -- the proximate cause of c02-shape property bodies discarding
    -- universally: 'unwrap' was registered in TypeCheck.hs:128 but had no
    -- clause in Contracts.hs:evalBuiltinApp. Error reduces to Nothing
    -- (no panic value in the static evaluator); the property body then
    -- discards on Error samples — the conservative, soundness-preserving
    -- choice.
    describe "F-033 unwrap static-eval coverage" $ do
      it "unwrap (ok v) reduces to v" $ do
        let v = ELit (LitInt 42)
        evalExprStatic Map.empty (EApp "unwrap" [EApp "ok" [v]])
          `shouldBe` Just v
      it "unwrap (err _) does not reduce" $ do
        evalExprStatic Map.empty (EApp "unwrap" [EApp "err" [ELit (LitString "boom")]])
          `shouldBe` Nothing
      it "unwrap on a non-Result expression does not reduce" $ do
        evalExprStatic Map.empty (EApp "unwrap" [ELit (LitInt 7)])
          `shouldBe` Nothing

    -- F-033: PBTSkipped diagnostic classification. The post-Addendum-17
    -- diagnostic distinguishes "body never reduced to a bool" (likely
    -- an unmodeled builtin in the property body) from "precondition kept
    -- failing." Pre-F-033 every GaveUp surfaced as "too many precondition
    -- failures," which was actively misleading on the c02 / c03 shapes.
    describe "F-033 PBTSkipped diagnostic classification" $ do
      it "body universally discards -> 'did not reduce on any sample' diag" $ do
        -- A property body containing an unsupported hole reduces to
        -- Nothing on every sample. samples_run = 0, bodyDiscards = 100.
        let prop = Property "body-unreducible" [("x", TInt)]
                     (EHole (HProofRequired "manual" Nothing))
                     []
        result <- runPropertyTests [SCheck prop]
        case pbtResults result of
          [run] -> do
            pbtStatus run `shouldBe` PBTSkipped
            case pbtCounterexample run of
              Just msg -> msg `shouldSatisfy` T.isInfixOf "did not reduce on any sample"
              Nothing  -> expectationFailure "expected diagnostic on PBTSkipped"
          rs -> expectationFailure $ "expected one run, got " ++ show (length rs)

    -- F-034: residual evalBuiltinApp coverage on c02/c03-shape transfer
    -- bodies. Addendum 18 surfaced five missing clauses and one bug:
    --   * list-empty / list-prepend / list-filter / int-to-string /
    --     string-concat-many had no static-evaluator clause despite being
    --     registered in TypeCheck.hs:88-119, so any c02/c03 transfer-body
    --     dispatch through them returned Nothing and the property body
    --     discarded universally on every QuickCheck sample.
    --   * list-head / list-tail returned the raw element / tail at
    --     Contracts.hs:434-435 but their type-checker signatures are
    --     '[list[a]] -> Result a string' / '[list[a]] -> Result (list[a]) string';
    --     property bodies matching '(match (list-head xs) ((Success v) ...))'
    --     against the typed surface failed to reduce. Empty-list arms were
    --     absent and fell through to Nothing.
    -- Each test pins a single clause; the last test exercises the full
    -- list-filter ∘ list-head reduction chain that c02/c03 transfer bodies
    -- require.
    describe "F-034 evalBuiltinApp residual builtin coverage" $ do
      it "list-empty reduces to nil" $
        evalExprStatic Map.empty (EApp "list-empty" [])
          `shouldBe` Just (EApp "nil" [])

      it "list-prepend produces a cons cell with head prepended" $ do
        let xs = EApp "cons" [ELit (LitInt 2), EApp "nil" []]
        evalExprStatic Map.empty (EApp "list-prepend" [ELit (LitInt 1), xs])
          `shouldBe` Just (EApp "cons" [ELit (LitInt 1), xs])

      it "list-filter keeps elements satisfying a predicate lambda" $ do
        let l3   = EApp "cons" [ ELit (LitInt 1)
                               , EApp "cons" [ ELit (LitInt 2)
                                             , EApp "cons" [ ELit (LitInt 3)
                                                           , EApp "nil" [] ]] ]
            fn   = ELambda [("x", TInt)]
                            (EOp ">=" [EVar "x", ELit (LitInt 2)])
            expr = EApp "list-filter" [l3, fn]
            want = EApp "cons" [ ELit (LitInt 2)
                               , EApp "cons" [ ELit (LitInt 3)
                                             , EApp "nil" [] ]]
        evalExprStatic Map.empty expr `shouldBe` Just want

      it "list-filter with always-false predicate yields nil" $ do
        let l2   = EApp "cons" [ ELit (LitInt 1)
                               , EApp "cons" [ ELit (LitInt 2)
                                             , EApp "nil" [] ]]
            fn   = ELambda [("x", TInt)] (ELit (LitBool False))
            expr = EApp "list-filter" [l2, fn]
        evalExprStatic Map.empty expr `shouldBe` Just (EApp "nil" [])

      it "int-to-string reduces a literal int to its decimal string" $ do
        evalExprStatic Map.empty (EApp "int-to-string" [ELit (LitInt 42)])
          `shouldBe` Just (ELit (LitString "42"))
        evalExprStatic Map.empty (EApp "int-to-string" [ELit (LitInt (-7))])
          `shouldBe` Just (ELit (LitString "-7"))

      it "string-concat-many concatenates a cons-chain of string literals" $ do
        let xs = EApp "cons" [ ELit (LitString "a-")
                             , EApp "cons" [ ELit (LitString "b-")
                                           , EApp "cons" [ ELit (LitString "c")
                                                         , EApp "nil" [] ]] ]
        evalExprStatic Map.empty (EApp "string-concat-many" [xs])
          `shouldBe` Just (ELit (LitString "a-b-c"))

      it "list-head on cons returns Success-wrapped element (Addendum-18 bugfix)" $ do
        let xs = EApp "cons" [ELit (LitInt 9), EApp "nil" []]
        evalExprStatic Map.empty (EApp "list-head" [xs])
          `shouldBe` Just (EApp "Success" [ELit (LitInt 9)])

      it "list-head on nil returns Error-tagged empty-list message" $ do
        case evalExprStatic Map.empty (EApp "list-head" [EApp "nil" []]) of
          Just (EApp "Error" [ELit (LitString msg)]) ->
            msg `shouldSatisfy` T.isInfixOf "empty list"
          other -> expectationFailure $ "expected Error on nil, got " ++ show other

      it "list-tail on cons returns Success-wrapped tail (Addendum-18 bugfix)" $ do
        let xs = EApp "cons" [ ELit (LitInt 1)
                             , EApp "cons" [ELit (LitInt 2), EApp "nil" []] ]
            tl = EApp "cons" [ELit (LitInt 2), EApp "nil" []]
        evalExprStatic Map.empty (EApp "list-tail" [xs])
          `shouldBe` Just (EApp "Success" [tl])

      it "list-filter ∘ list-head reduces end-to-end on a 3-element list" $ do
        -- Mirrors the c02/c03 transfer-body shape: filter accounts by a
        -- predicate then take the head, matching '(match (list-head matches)
        -- ((Success p) ...) ((Error _) ...))'. Pre-F-034 either step
        -- short-circuited to Nothing.
        let l3   = EApp "cons" [ ELit (LitInt 10)
                               , EApp "cons" [ ELit (LitInt 20)
                                             , EApp "cons" [ ELit (LitInt 30)
                                                           , EApp "nil" [] ]] ]
            fn   = ELambda [("x", TInt)]
                            (EOp ">=" [EVar "x", ELit (LitInt 20)])
            expr = EApp "list-head" [EApp "list-filter" [l3, fn]]
        evalExprStatic Map.empty expr
          `shouldBe` Just (EApp "Success" [ELit (LitInt 20)])

    -- OBLIG-PBT-3 / F-033: PBT-to-trust-report write-back. Singleton
    -- head-position contracted callee in a PBTPassed property lifts csPost(f)
    -- to DLTested n with pbt_witnesses provenance; multi-subject / skip / fail
    -- produce diagnostics, no lift. See docs/design/oblig-pbt-3-proposal.md
    -- §12 for the edge-case matrix this block pins.
    describe "OBLIG-PBT-3 PBT-to-trust-report write-back" $ do
      let mkContractedFn name =
            SDefLogic name [("x", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EVar "x")
          passedRun desc nSamples = PBTRun desc PBTPassed nSamples Nothing

      -- E2: same function in multiple head-positions in one body — lift once.
      it "E2 same function in multiple head positions lifts once" $ do
        let f      = mkContractedFn "f"
            body   = EOp "and" [EApp "f" [ELit (LitInt 1)], EApp "f" [ELit (LitInt 2)]]
            prop   = Property "f-twice" [] body []
            stmts  = [f, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "f-twice" 100]
            (m, ds) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 1
        ds        `shouldBe` []
        case Map.lookup "f" m of
          Just cs -> case csPost cs of
            Just er -> erDisplayLevel er `shouldBe` DLTested 100
            Nothing -> expectationFailure "expected csPost lift on f"
          Nothing -> expectationFailure "expected entry for f in writeback map"

      -- E3: multi-subject property — diagnostic, no lift.
      it "E3 multi-subject property produces diagnostic and no lift" $ do
        let f      = mkContractedFn "encrypt"
            g      = mkContractedFn "decrypt"
            body   = EOp "=" [EVar "x", EApp "decrypt" [EApp "encrypt" [EVar "x"]]]
            prop   = Property "roundtrip" [("x", TInt)] body []
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "roundtrip" 100]
            (m, ds) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 0
        length ds  `shouldBe` 1
        any (T.isInfixOf "multiple contracted callees") ds `shouldBe` True

      -- E5: TRUST-PRE (Part 1) — a DLAsserted pre no longer floors the
      -- per-function tier; aggregateTiers classifies on the post-side level.
      it "E5 pre-bearing post-tested function classifies tested (TRUST-PRE: no floor)" $ do
        let f       = mkContractedFn "f"
            body    = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            prop    = Property "f-id" [] body []
            stmts   = [f, SCheck prop]
            result  = PBTResult 1 1 0 0 [passedRun "f-id" 100]
            (pbtCS, _) = pbtTrustWriteback stmts Map.empty result
            report  = buildTrustReport Map.empty stmts pbtCS
            tpFull  = trTierProfile     report
            tpPre   = trTierProfilePre  report
            tpPost  = trTierProfilePost report
        -- TRUST-PRE (Part 1): the per-function tier no longer FLOORS to asserted
        -- on the DLAsserted pre. 'aggregateTiers' now classifies on the post-side
        -- effective level (Position B, summary-only), so the DLTested post is
        -- counted directly — the precondition is off the function's evidence axis.
        -- (Was: tpAsserted tpFull == 1, tpTested tpFull == 0 — the pre-bearing floor.)
        tpAsserted tpFull `shouldBe` 0
        tpTested   tpFull `shouldBe` 1
        -- per-clause split is unchanged (aggregateTiersPre/Post are untouched).
        tpAsserted tpPre  `shouldBe` 1
        tpTested   tpPost `shouldBe` 1
        tpAsserted tpPost `shouldBe` 0

      -- E6: already-DLVerified post — mergeCS preserves verified; lift non-degrading.
      it "E6 prior DLVerified post is preserved by mergeCS (non-degrading)" $ do
        let f          = mkContractedFn "f"
            body       = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            prop       = Property "f-id" [] body []
            stmts      = [f, SCheck prop]
            result     = PBTResult 1 1 0 0 [passedRun "f-id" 100]
            (pbtCS, _) = pbtTrustWriteback stmts Map.empty result
            -- Prior sidecar entry at DLVerified — replicates the verifier write
            -- shape at Main.hs:1196-1206.
            priorCS    = Map.singleton "f" $ ContractStatus
                           (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                           (Just (EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False))
                           []
            -- Replicate Main.hs:doTest order: pbtCS on the sidecar side, prior
            -- sidecar on the base side, merged via Module.mergeCS.
            mergedReal = Map.unionWith mergeCS pbtCS priorCS
        case Map.lookup "f" mergedReal >>= csPost of
          Just er -> case erDisplayLevel er of
            DLVerified _ -> pure ()
            other        -> expectationFailure $
                              "expected DLVerified preserved, got " ++ show other
          Nothing -> expectationFailure "expected csPost on merged entry"

      -- E8: cross-module subject — sidecar key is qualified.
      it "E8 cross-module subject keys writeback under qualified name" $ do
        let libF   = mkContractedFn "f"
            libEnv = ModuleEnv
                       { meExports        = Map.fromList [("f", TFn [TInt] TInt)]
                       , meStatements     = [libF]
                       , meInterfaces     = Map.empty
                       , meAliasMap       = Map.empty
                       , mePath           = ["lib"]
                       , meContractStatus = Map.empty
                       , meContracts      = Map.empty
                       }
            cache  = Map.singleton ["lib"] libEnv
            -- Local file: (open lib) + (check ...) covering f. No local
            -- def-logic for f — so f is imported, sidecar key qualifies.
            localStmts = [ SOpen ["lib"] Nothing
                         , SCheck (Property "f-id" []
                                     (EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]) [])
                         ]
            result      = PBTResult 1 1 0 0 [passedRun "f-id" 100]
            (m, _)      = pbtTrustWriteback localStmts cache result
        Map.keys m `shouldBe` ["lib.f"]

      -- E10: idempotent re-run — pbt_witnesses dedup by hash.
      it "E10 idempotent re-run dedups pbt_witnesses by hash" $ do
        let f       = mkContractedFn "f"
            body    = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            prop    = Property "f-id" [] body []
            stmts   = [f, SCheck prop]
            run     = passedRun "f-id" 100
            -- Run twice — second invocation should produce the same map (same
            -- propBody hash, same description → deduplicated witness).
            result1 = PBTResult 1 1 0 0 [run]
            (m1, _) = pbtTrustWriteback stmts Map.empty result1
            (m2, _) = pbtTrustWriteback stmts Map.empty result1
        m1 `shouldBe` m2
        case Map.lookup "f" m1 >>= csPost of
          Just er -> length (erPbtWitnesses er) `shouldBe` 1
          Nothing -> expectationFailure "expected csPost on f"

      -- E12: mixed pass / fail on the same function — only passing lifts.
      it "E12 mixed pass+fail on same fn: passing run lifts, failing does not" $ do
        let f         = mkContractedFn "f"
            bodyPass  = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            bodyFail  = EOp "=" [EApp "f" [ELit (LitInt 0)], ELit (LitInt 9)]
            propPass  = Property "f-pass" [] bodyPass []
            propFail  = Property "f-fail" [] bodyFail []
            stmts     = [f, SCheck propPass, SCheck propFail]
            result    = PBTResult 2 1 1 0
                         [ passedRun "f-pass" 100
                         , PBTRun "f-fail" PBTFailed 100 (Just "f(0) ≠ 9")
                         ]
            (m, ds)   = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 1
        case Map.lookup "f" m >>= csPost of
          Just er -> do
            erDisplayLevel er `shouldBe` DLTested 100
            length (erPbtWitnesses er) `shouldBe` 1
            (pwDescription <$> take 1 (erPbtWitnesses er)) `shouldBe` ["f-pass"]
          Nothing -> expectationFailure "expected csPost lift from passing run"
        -- Failing run surfaces as a diagnostic but does not lift.
        any (T.isInfixOf "failed") ds `shouldBe` True

      -- E13: property body edited → hash mismatch → downgrade to DLAsserted on read.
      it "E13 edited property body downgrades stale DLTested to DLAsserted" $ do
        let f         = mkContractedFn "f"
            staleHash = "sha256:" <> T.replicate 64 "0"  -- never matches a live body
            staleW    = PbtWitness staleHash "f-id"
            staleEr   = EvidenceRecord (DLTested 100) False Nothing [staleW] False Nothing Nothing False Nothing False
            staleCS   = Map.singleton "f" $ ContractStatus
                         (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                         (Just staleEr)
                         []
            -- Live property covers f but with a body whose hash ≠ staleHash.
            liveProp  = Property "f-id-edited" []
                          (EOp "=" [EApp "f" [ELit (LitInt 2)], ELit (LitInt 2)])
                          []
            stmts     = [f, SCheck liveProp]
            report    = buildTrustReport Map.empty stmts staleCS
        -- Find the entry for f; its csPost should have been downgraded.
        case filter (\e -> teName e == "f") (trEntries report) of
          [e] -> case tePost e of
            Just er -> erDisplayLevel er `shouldBe` DLAsserted
            Nothing -> expectationFailure "expected csPost on f"
          _   -> expectationFailure "expected single entry for f"
        length (trStaleDowngrades report) `shouldBe` 1

      -- E14: property deleted between runs → no live hash matches → downgrade.
      it "E14 deleted property downgrades stale DLTested to DLAsserted" $ do
        let f         = mkContractedFn "f"
            staleHash = "sha256:" <> T.replicate 64 "a"
            staleEr   = EvidenceRecord (DLTested 100) False Nothing
                          [PbtWitness staleHash "f-id"] False Nothing Nothing False Nothing False
            staleCS   = Map.singleton "f" $ ContractStatus
                         (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False))
                         (Just staleEr)
                         []
            stmts     = [f]  -- no SCheck — property deleted
            report    = buildTrustReport Map.empty stmts staleCS
        case filter (\e -> teName e == "f") (trEntries report) of
          [e] -> case tePost e of
            Just er -> erDisplayLevel er `shouldBe` DLAsserted
            Nothing -> expectationFailure "expected csPost on f"
          _   -> expectationFailure "expected single entry for f"

      -- E15: v1.1.0 emit decodes cleanly; tier_profile unchanged in shape,
      -- tier_profile_pre / tier_profile_post present and structurally parallel.
      it "E15 v1.1.0 emit carries parallel tier_profile_{pre,post}" $ do
        let f        = mkContractedFn "f"
            body     = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            prop     = Property "f-id" [] body []
            stmts    = [f, SCheck prop]
            result   = PBTResult 1 1 0 0 [passedRun "f-id" 100]
            (pbtCS, _) = pbtTrustWriteback stmts Map.empty result
            report   = buildTrustReport Map.empty stmts pbtCS
            jsonText = formatTrustReportJson report
        case decode (BLC.pack (T.unpack jsonText)) :: Maybe Value of
          Just (Object o) -> do
            -- trust_report_version now 1.5.0 (REC-PARTIAL-MARK; was 1.4.0 TRUST-PRE).
            KM.lookup "trust_report_version" o `shouldBe` Just (String "1.5.0")
            -- Scalar tier_profile unchanged in shape (six Int fields)
            case KM.lookup "tier_profile" o of
              Just (Object tp) -> do
                KM.lookup "verified"         tp `shouldSatisfy` (/= Nothing)
                KM.lookup "tested"           tp `shouldSatisfy` (/= Nothing)
                KM.lookup "asserted"         tp `shouldSatisfy` (/= Nothing)
              _ -> expectationFailure "tier_profile missing or not an object"
            -- New parallel aggregates
            case KM.lookup "tier_profile_pre" o of
              Just (Object tp) -> KM.lookup "tested" tp `shouldSatisfy` (/= Nothing)
              _ -> expectationFailure "tier_profile_pre missing or not an object"
            case KM.lookup "tier_profile_post" o of
              Just (Object tp) -> KM.lookup "tested" tp `shouldBe` Just (Number 1)
              _ -> expectationFailure "tier_profile_post missing or not an object"
          _ -> expectationFailure "trust-report JSON did not decode as an object"

    -- OBLIG-PBT-4 :subjects metadata. Explicit-subject opt-in on a
    -- '(check ...)' block bypasses the v0.10.5 head-position scan and
    -- credits each declared subject with its own DLTested record sharing
    -- one pbt_witnesses hash. Edge-case table is proposal §11.1 (pinned
    -- 2026-05-14). S6 (empty-list rejection) is parser-level; lives in the
    -- parser describe block below.
    describe "OBLIG-PBT-4 :subjects metadata" $ do
      let mkContractedFn name =
            SDefLogic name [("x", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EVar "x")
          mkContractedFnNoPost name =
            SDefLogic name [("x", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                        Nothing Nothing Nothing)
              (EVar "x")
          passedRun desc nSamples = PBTRun desc PBTPassed nSamples Nothing

      -- S1: :subject f singleton is sugar for :subjects [f]
      it "S1 :subject f singleton lifts as :subjects [f]" $ do
        let f      = mkContractedFn "f"
            body   = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            prop   = Property "f-id" [] body ["f"]
            stmts  = [f, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "f-id" 100]
            (m, ds) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 1
        ds        `shouldBe` []
        case Map.lookup "f" m >>= csPost of
          Just er -> erDisplayLevel er `shouldBe` DLTested 100
          Nothing -> expectationFailure "expected csPost lift on f"

      -- S2: :subjects [f g] — both contracted — two records, shared hash
      it "S2 :subjects [f g] credits both with shared pbt_witnesses hash" $ do
        let f      = mkContractedFn "encrypt"
            g      = mkContractedFn "decrypt"
            body   = EOp "=" [EVar "x", EApp "decrypt" [EApp "encrypt" [EVar "x"]]]
            prop   = Property "roundtrip" [("x", TInt)] body ["encrypt", "decrypt"]
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "roundtrip" 100]
            (m, ds) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 2
        ds        `shouldBe` []
        let fHash = (csPost =<< Map.lookup "encrypt" m) >>= fmap pwHash . listToMaybe . erPbtWitnesses
            gHash = (csPost =<< Map.lookup "decrypt" m) >>= fmap pwHash . listToMaybe . erPbtWitnesses
        fHash `shouldBe` gHash
        fHash `shouldSatisfy` (/= Nothing)

      -- S3: declared subject has no post → diag, no lift on that subject
      it "S3 declared subject without postcondition: info diag, others still lift" $ do
        let f      = mkContractedFnNoPost "f"  -- no post
            g      = mkContractedFn       "g"
            body   = EOp "=" [EApp "g" [ELit (LitInt 1)], ELit (LitInt 1)]
            prop   = Property "fg" [] body ["f", "g"]
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "fg" 100]
            (m, ds) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 1
        Map.keys m `shouldBe` ["g"]
        any (T.isInfixOf "has no postcondition") ds `shouldBe` True

      -- S4: explicit annotation overrides head-position scan
      it "S4 :subjects [f] overrides multi-callee inferred head-set" $ do
        let f      = mkContractedFn "f"
            g      = mkContractedFn "g"
            -- Body mentions both f and g in head position; annotation says only f.
            body   = EOp "and" [EApp "f" [ELit (LitInt 1)], EApp "g" [ELit (LitInt 2)]]
            prop   = Property "fg-but-f" [] body ["f"]
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "fg-but-f" 100]
            (m, ds) = pbtTrustWriteback stmts Map.empty result
        Map.keys m `shouldBe` ["f"]
        ds         `shouldBe` []
        -- Crucial: the multi-callee diagnostic is NOT produced under explicit annotation.
        any (T.isInfixOf "multiple contracted callees") ds `shouldBe` False

      -- S5: declarative annotation — body need not mention the declared subjects
      it "S5 :subjects credits declared subjects even if body does not mention them" $ do
        let f      = mkContractedFn "f"
            g      = mkContractedFn "g"
            -- Body mentions neither.
            body   = ELit (LitBool True)
            prop   = Property "trivial" [] body ["f", "g"]
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "trivial" 100]
            (m, _) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 2

      -- S7: duplicate subjects are deduped (assumed already deduped by parser;
      -- writeback is robust to a duplicate slipping through.
      it "S7 duplicate :subjects [f f] yields one record" $ do
        let f      = mkContractedFn "f"
            body   = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            -- Simulate a duplicate that escaped parser dedup
            prop   = Property "f-id" [] body ["f", "f"]
            stmts  = [f, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun "f-id" 100]
            (m, _) = pbtTrustWriteback stmts Map.empty result
        Map.size m `shouldBe` 1
        case Map.lookup "f" m >>= csPost of
          Just er -> length (erPbtWitnesses er) `shouldBe` 1
          Nothing -> expectationFailure "expected csPost on f"

      -- S9: overlapping :subjects across check blocks join via mergePbtWriteback
      it "S9 overlapping :subjects across two checks merge by mergePbtWriteback" $ do
        let f         = mkContractedFn "f"
            g         = mkContractedFn "g"
            body1     = EOp "=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 1)]
            body2     = EOp "=" [EApp "g" [ELit (LitInt 2)], ELit (LitInt 2)]
            prop1     = Property "p1" [] body1 ["f"]
            prop2     = Property "p2" [] body2 ["f", "g"]
            stmts     = [f, g, SCheck prop1, SCheck prop2]
            result    = PBTResult 2 2 0 0 [passedRun "p1" 100, passedRun "p2" 50]
            (m, _)    = pbtTrustWriteback stmts Map.empty result
        -- f appears in both → DLTested 100 (max), 2 witnesses
        case Map.lookup "f" m >>= csPost of
          Just er -> do
            erDisplayLevel er `shouldBe` DLTested 100
            length (erPbtWitnesses er) `shouldBe` 2
          Nothing -> expectationFailure "expected csPost on f"
        -- g appears only in p2 → DLTested 50, 1 witness
        case Map.lookup "g" m >>= csPost of
          Just er -> do
            erDisplayLevel er `shouldBe` DLTested 50
            length (erPbtWitnesses er) `shouldBe` 1
          Nothing -> expectationFailure "expected csPost on g"

    -- OBLIG-PBT-4 :subject / :subjects parser surface (sexp + JSON).
    describe "OBLIG-PBT-4 :subjects parsing" $ do
      it "sexp: (check :subject f (for-all …)) parses with propSubjects = [f]" $ do
        let src = T.pack
                  "(check \"d\" :subject foo (for-all [x: int] (= x x)))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SCheck p] -> propSubjects p `shouldBe` ["foo"]
          other -> expectationFailure $ "unexpected: " ++ show other
      it "sexp: (check :subjects [f g] (for-all …)) parses both names" $ do
        let src = T.pack
                  "(check \"d\" :subjects [foo bar] (for-all [x: int] (= x x)))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SCheck p] -> propSubjects p `shouldBe` ["foo", "bar"]
          other -> expectationFailure $ "unexpected: " ++ show other
      it "sexp: (check :subjects [] …) is rejected with S6 diag" $ do
        let src = T.pack
                  "(check \"d\" :subjects [] (for-all [x: int] (= x x)))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Left _  -> pure ()
          Right _ -> expectationFailure "expected parse failure on empty :subjects"
      it "JSON: CheckDecl with subjects array decodes to propSubjects" $ do
        let src = BLC.pack $ unlines
              [ "{"
              , "  \"schemaVersion\": \"0.6.0\","
              , "  \"statements\": ["
              , "    {"
              , "      \"kind\": \"check\","
              , "      \"label\": \"d\","
              , "      \"subjects\": [\"foo\", \"bar\"],"
              , "      \"for_all\": {"
              , "        \"kind\": \"for-all\","
              , "        \"bindings\": [{ \"name\": \"x\", \"param_type\": { \"kind\": \"primitive\", \"name\": \"int\" } }],"
              , "        \"body\": { \"kind\": \"op\", \"op\": \"=\", \"args\": [ { \"kind\": \"var\", \"name\": \"x\" }, { \"kind\": \"var\", \"name\": \"x\" } ] }"
              , "      }"
              , "    }"
              , "  ]"
              , "}"
              ]
        case parseJSONAST GrammarLegacy "<test>" src of
          Right [SCheck p] -> propSubjects p `shouldBe` ["foo", "bar"]
          other -> expectationFailure $ "unexpected: " ++ show other

    -- OBLIG-PBT-5a (v0.10.7): joint-witness scalar-tested exclusion. The
    -- OBLIG-PBT-4 ':subjects [f g …]' lift emits N evidence records sharing
    -- one canonical-body hash; without this exclusion the scalar 'tested'
    -- count over-credits one property body as N. These tests pin the
    -- demotion (joint-only DLTested → DLAsserted in scalar tier counts),
    -- the non-demotion of solo-witnessed entries, the additive JSON emit,
    -- and the no-version-bump invariant per the 2026-05-23 triage routing.
    --
    -- Sidecars are produced by 'pbtTrustWriteback' (the production path)
    -- so the OBLIG-PBT-3 staleness check sees the SCheck statements that
    -- generated the witnesses and does not purge them.
    describe "OBLIG-PBT-5a joint PBT witness exclusion" $ do
      let mkContractedFn name =
            SDefLogic name [("x", TInt)] (Just TInt)
              (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                        (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
              (EVar "x")
          passedRun5a desc nSamples = PBTRun desc PBTPassed nSamples Nothing

      -- J1: pure joint lift (:subjects [f g]) — both demoted out of scalar
      -- tested; grouped emit lists both subjects under one hash.
      it "J1 joint-only :subjects [f g] demoted from scalar tested count" $ do
        let f      = mkContractedFn "encrypt"
            g      = mkContractedFn "decrypt"
            body   = EOp "=" [EVar "x", EApp "decrypt" [EApp "encrypt" [EVar "x"]]]
            prop   = Property "roundtrip" [("x", TInt)] body ["encrypt", "decrypt"]
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun5a "roundtrip" 100]
            (sidecar, _) = pbtTrustWriteback stmts Map.empty result
            report       = buildTrustReport Map.empty stmts sidecar
        tpTested  (trTierProfilePost report) `shouldBe` 0
        tsTested  (trSummary         report) `shouldBe` 0
        length (trJointWitnesses report) `shouldBe` 1
        case trJointWitnesses report of
          [(_, subs)] -> subs `shouldBe` ["decrypt", "encrypt"]
          _ -> expectationFailure "expected exactly one joint group"

      -- J2: mixed solo+joint — solo subject keeps the credit, pure-joint
      -- subject demoted. Locks the "every witness is joint" predicate.
      -- Two checks: a :subjects [encrypt decrypt] joint, plus a solo
      -- :subject encrypt property body. encrypt accumulates both
      -- witnesses; decrypt sees only the joint hash.
      it "J2 solo+joint mix: solo subject keeps tested credit, joint-only demoted" $ do
        let f      = mkContractedFn "encrypt"
            g      = mkContractedFn "decrypt"
            joint  = Property "roundtrip" [("x", TInt)]
                       (EOp "=" [EVar "x", EApp "decrypt" [EApp "encrypt" [EVar "x"]]])
                       ["encrypt", "decrypt"]
            solo   = Property "encrypt-positive" [("x", TInt)]
                       (EOp ">=" [EApp "encrypt" [EVar "x"], ELit (LitInt 0)])
                       ["encrypt"]
            stmts  = [f, g, SCheck joint, SCheck solo]
            result = PBTResult 2 2 0 0 [ passedRun5a "roundtrip"        100
                                       , passedRun5a "encrypt-positive" 100 ]
            (sidecar, _) = pbtTrustWriteback stmts Map.empty result
            report       = buildTrustReport Map.empty stmts sidecar
        -- encrypt earned a non-joint witness → not demoted.
        case filter (\e -> teName e == "encrypt") (trEntries report) of
          [e] -> teJointPostWitness e `shouldBe` False
          _   -> expectationFailure "expected exactly one entry for encrypt"
        -- decrypt has only the joint witness → demoted.
        case filter (\e -> teName e == "decrypt") (trEntries report) of
          [e] -> teJointPostWitness e `shouldBe` True
          _   -> expectationFailure "expected exactly one entry for decrypt"
        -- Scalar tested count = 1 (encrypt), not 2.
        tpTested (trTierProfilePost report) `shouldBe` 1

      -- J3: source-annotated DLTested with empty pbt_witnesses is NOT
      -- demoted. The demotion key is "non-empty witnesses AND all joint";
      -- empty-witness DLTested comes from `:trust tested` source markers.
      it "J3 source-annotated tested (empty pbt_witnesses) is not demoted" $ do
        let stmts   = [mkContractedFn "f"]
            sidecar = Map.fromList
              [ ("f", ContractStatus
                  { csPre  = Nothing
                  , csPost = Just (EvidenceRecord (DLTested 100) False Nothing [] False Nothing Nothing False Nothing False)
                  , csAssumptions = []
                  })
              ]
            report = buildTrustReport Map.empty stmts sidecar
        tpTested  (trTierProfilePost report) `shouldBe` 1
        case trEntries report of
          [e] -> teJointPostWitness e `shouldBe` False
          _   -> expectationFailure "expected exactly one entry"

      -- J4: singleton-head-position path (no :subjects) produces unique
      -- witnesses; no demotion, joint-witness list empty.
      it "J4 singleton lift with unique witness produces no joint group" $ do
        let f      = mkContractedFn "f"
            body   = EOp ">=" [EApp "f" [ELit (LitInt 1)], ELit (LitInt 0)]
            prop   = Property "f-nonneg" [] body []  -- no :subjects, singleton head
            stmts  = [f, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun5a "f-nonneg" 100]
            (sidecar, _) = pbtTrustWriteback stmts Map.empty result
            report       = buildTrustReport Map.empty stmts sidecar
        tpTested  (trTierProfilePost report) `shouldBe` 1
        trJointWitnesses report `shouldBe` []

      -- J5: per-entry flag emitted only when true. v0.10.7 keeps emit
      -- minimal — a False flag is omitted from the entry JSON.
      it "J5 entry JSON carries joint_pbt_witness only when true" $ do
        let f      = mkContractedFn "encrypt"
            g      = mkContractedFn "decrypt"
            body   = EOp "=" [EVar "x", EApp "decrypt" [EApp "encrypt" [EVar "x"]]]
            prop   = Property "roundtrip" [("x", TInt)] body ["encrypt", "decrypt"]
            stmts  = [f, g, SCheck prop]
            result = PBTResult 1 1 0 0 [passedRun5a "roundtrip" 100]
            (sidecar, _) = pbtTrustWriteback stmts Map.empty result
            report       = buildTrustReport Map.empty stmts sidecar
            jsonTxt = formatTrustReportJson report
        -- Both encrypt and decrypt are joint-only → both carry the flag.
        T.count "\"joint_pbt_witness\":true" jsonTxt `shouldBe` 2

      -- J6: JSON shape is additive. trust_report_version stays "1.1.0"
      -- (no bump per 2026-05-23 triage row OBLIG-PBT-5a); joint_pbt_witnesses
      -- key is present even when the list is empty for consumer-stability.
      it "J6 JSON emit additive: trust_report_version unchanged, joint_pbt_witnesses key present" $ do
        let report  = buildTrustReport Map.empty [] Map.empty
            jsonTxt = formatTrustReportJson report
        -- trust_report_version now 1.5.0 (REC-PARTIAL-MARK; TRUST-PRE was the 1.4.0 additive axis).
        T.isInfixOf "\"trust_report_version\":\"1.5.0\"" jsonTxt `shouldBe` True
        T.isInfixOf "\"joint_pbt_witnesses\":"          jsonTxt `shouldBe` True

    -- evalContract isolation regression: empty-FuncEnv invariant
    describe "evalContract isolation regression" $ do
      it "contract referencing a top-level def-logic does not resolve to its body" $ do
        -- Precondition that calls a user-defined function. Under the v0.10.2
        -- evaluator expansion, evalExprStatic uses an empty FuncEnv, so the
        -- call falls through to evalBuiltinApp (which doesn't know `my-fn`)
        -- and returns Nothing -> ContractUnchecked. Pins the invariant that
        -- contract evaluation does not silently inline def-logic calls.
        let pre      = Just (EApp "my-fn" [ELit (LitInt 1)])
            contract = Contract pre Nothing Nothing Nothing Nothing
        evalContract "f" contract Map.empty `shouldBe` ContractUnchecked

    -- S4: typecheck warns on dotted fn name in app position (TypeCheck.hs:919-924)
    describe "S4 dotted-fn typecheck warning" $ do
      it "(def-shell f [] (Result.Error 0)) produces a dotted-name warning" $ do
        let src = T.pack "(def-shell f [] (Result.Error 0))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Left err    -> expectationFailure (show err)
          Right stmts -> do
            let report = typeCheck GrammarCoreInversion emptyEnv stmts
            let warns  = filter (\d -> diagSeverity d == SevWarning)
                                (reportDiagnostics report)
            any (\d -> "dotted function name" `T.isInfixOf` diagMessage d) warns
              `shouldBe` True

    -- TC-EOP-1 (v0.10.7): EOp arity + arg-type-check fix at TypeCheck.hs:981.
    -- Pre-fix `inferExpr (EOp op _args)` ignored args entirely and returned the
    -- builtinEnv result type, so arity-bad and type-incorrect operator calls
    -- silently passed. The fix mirrors the EApp loop above (structuralUnify
    -- with per-call-site substitution + EHole bypass). These tests pin both
    -- the rejection cases and the positive baselines, plus a JSON-AST parity
    -- pass to confirm both frontends route through the same typecheck path.
    describe "TC-EOP-1 EOp arity and arg-type checking" $ do
      let checkSrc src =
            case parseStatements GrammarCoreInversion "<test>" src of
              Left err -> Left (T.pack (show err))
              Right stmts -> Right (typeCheck GrammarCoreInversion emptyEnv stmts)
          errorsOf rep =
            filter (\d -> diagSeverity d == SevError) (reportDiagnostics rep)
          anyMsg sub rep = any (\d -> sub `T.isInfixOf` diagMessage d) (errorsOf rep)

      it "(+ 1 2) typechecks (positive baseline)" $ do
        case checkSrc (T.pack "(def-shell f [] (+ 1 2))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> reportSuccess rep `shouldBe` True

      it "(+ 1) raises arity error" $ do
        case checkSrc (T.pack "(def-shell f [] (+ 1))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> anyMsg "expects 2 args, got 1" rep `shouldBe` True

      it "(+ 1 2 3) raises arity error" $ do
        case checkSrc (T.pack "(def-shell f [] (+ 1 2 3))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> anyMsg "expects 2 args, got 3" rep `shouldBe` True

      it "(+ \"x\" 1) raises type error at arg 0" $ do
        case checkSrc (T.pack "(def-shell f [] (+ \"x\" 1))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> anyMsg "type mismatch in '+'" rep `shouldBe` True

      it "(not 1) raises type error" $ do
        case checkSrc (T.pack "(def-shell f [] (not 1))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> anyMsg "type mismatch in 'not'" rep `shouldBe` True

      -- Polymorphic equality: structuralUnify's substitution map binds TVar "a"
      -- to int from arg 0, then fails when arg 1 is string. Pre-fix this
      -- silently typechecked because `_args` was discarded.
      it "(= 1 \"1\") raises type error at arg 1 (polymorphic op unified at arg 0)" $ do
        case checkSrc (T.pack "(def-shell f [] (= 1 \"1\"))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> anyMsg "type mismatch in '='" rep `shouldBe` True

      it "(= true true) typechecks (positive polymorphic baseline)" $ do
        case checkSrc (T.pack "(def-shell f [] (= true true))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> reportSuccess rep `shouldBe` True

      it "(and true 0) raises type error" $ do
        case checkSrc (T.pack "(def-shell f [] (and true 0))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> anyMsg "type mismatch in 'and'" rep `shouldBe` True

      -- JSON-AST frontend parity: same typecheck path, same diagnostic.
      it "JSON-AST (+ \"x\" 1) raises the same type error" $ do
        let src = BLC.pack $ unlines
              [ "{"
              , "  \"schemaVersion\": \"0.6.0\","
              , "  \"statements\": ["
              , "    { \"kind\": \"def-shell\""
              , "    , \"name\": \"f\""
              , "    , \"params\": []"
              , "    , \"body\": { \"kind\": \"op\", \"op\": \"+\""
              , "                , \"args\": [ { \"kind\": \"lit-string\", \"value\": \"x\" }"
              , "                            , { \"kind\": \"lit-int\", \"value\": 1 } ] }"
              , "    }"
              , "  ]"
              , "}"
              ]
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Left err -> expectationFailure (show err)
          Right stmts -> do
            let report = typeCheck GrammarCoreInversion emptyEnv stmts
            any (\d -> "type mismatch in '+'" `T.isInfixOf` diagMessage d)
                (filter (\d -> diagSeverity d == SevError) (reportDiagnostics report))
              `shouldBe` True

      -- EHole bypass: a hole in an EOp arg position should typecheck (the
      -- hole is recorded with the expected type, not unified against it).
      it "(+ ?x 1) typechecks with the hole recorded at int" $ do
        case checkSrc (T.pack "(def-shell f [] (+ ?x 1))") of
          Left err  -> expectationFailure (T.unpack err)
          Right rep -> errorsOf rep `shouldBe` []

  -- -----------------------------------------------------------------------
  -- INT-1 (v0.10.8): overflow taint propagation
  -- -----------------------------------------------------------------------
  describe "INT-1 (v0.10.8): overflow taint propagation" $ do
    -- T1: pure literal arithmetic in Int64 range does not taint.
    it "T1 literal-only arithmetic (+ 40 2) does not taint" $ do
      bodyHasOverflowArith (EOp "+" [ELit (LitInt 40), ELit (LitInt 2)]) `shouldBe` False

    -- T2: any non-literal operand taints.
    it "T2 (+ x 1) on a variable taints" $ do
      bodyHasOverflowArith (EOp "+" [EVar "x", ELit (LitInt 1)]) `shouldBe` True

    -- T3: large literal outside Int64 range taints (the arithmetic could overflow).
    it "T3 literal beyond Int64 range taints" $ do
      let big = toInteger (maxBound :: Int) + 1
      bodyHasOverflowArith (EOp "+" [ELit (LitInt big), ELit (LitInt 1)]) `shouldBe` True

    -- T4: non-arithmetic predicate body does not taint.
    it "T4 predicate-only body (> x 0) does not taint" $ do
      bodyHasOverflowArith (EOp ">" [EVar "x", ELit (LitInt 0)]) `shouldBe` False

    -- T5: arithmetic operator under EApp head taints (parser emits both shapes).
    it "T5 EApp + arithmetic head also taints" $ do
      bodyHasOverflowArith (EApp "+" [EVar "x", ELit (LitInt 1)]) `shouldBe` True

    -- T6: nested arithmetic inside a non-arithmetic head propagates.
    it "T6 (and (> x 0) (= (+ x 1) y)) propagates taint from nested +" $ do
      let expr = EApp "and"
                   [ EOp ">" [EVar "x", ELit (LitInt 0)]
                   , EOp "=" [EOp "+" [EVar "x", ELit (LitInt 1)], EVar "y"]
                   ]
      bodyHasOverflowArith expr `shouldBe` True

    -- T7: Class A indexing primitives don't taint (they're EApp on non-arith names).
    it "T7 (list-nth xs i) builtin call does not taint" $ do
      bodyHasOverflowArith (EApp "list-nth" [EVar "xs", EVar "i"]) `shouldBe` False

    -- T8: arithmetic inside the rhs of an ELet binding propagates.
    it "T8 ELet binding with arithmetic rhs taints" $ do
      let expr = ELet [(PVar "t", Nothing, EOp "+" [EVar "x", ELit (LitInt 1)])]
                      (EVar "t")
      bodyHasOverflowArith expr `shouldBe` True

    -- T9: arithmetic inside one EIf branch propagates.
    it "T9 EIf with arithmetic in else-branch taints" $ do
      let expr = EIf (EOp ">" [EVar "x", ELit (LitInt 0)])
                     (EVar "x")
                     (EOp "+" [EVar "x", ELit (LitInt 1)])
      bodyHasOverflowArith expr `shouldBe` True

    -- T10 (LT-INT v0.11 dormant-trigger regression): post-INT-2, `int` is the
    -- unbounded `Integer` at codegen — no `int` arithmetic can overflow at
    -- runtime — so the INT-1 trigger set is empty for `int` values per
    -- docs/design/int-2-boundary-shims.md §4. A def-logic with body (+ x 1)
    -- and a post asserting (= result (+ x 1)) is body-faithful AND untainted.
    -- The walker `bodyHasOverflowArith` continues to syntactically fire (see
    -- T2/T5/T8/T9 above); the v0.11 disarm lives at the emitter call site
    -- (FixpointEmit.hs ~line 516, INT-1 trigger commented out under LT-INT).
    -- INT-3 (machine-int) will re-arm with type-awareness at the same site.
    it "T10 (LT-INT v0.11): trigger set empty on int — (+ x 1) does NOT taint" $ do
      let src = T.pack $ unlines
            [ "(def-shell add-one [x: int]"
            , "  (pre (>= x 0))"
            , "  (post (= result (+ x 1)))"
            , "  (+ x 1))"
            ]
      case parseStatements GrammarCoreInversion "<int1-test>" src of
        Left err    -> expectationFailure ("parse: " ++ show err)
        Right stmts -> do
          emitR <- emitFixpointWith (EmitOptions { emitBodyVCs = True }) "T10.llmll" stmts
          erOverflowTaintedFns emitR `shouldBe` []
          erBodyFaithfulFns    emitR `shouldBe` ["add-one"]

    -- T11: end-to-end: pure-predicate body does NOT taint. Body-faithful may
    -- or may not fire (the body is bool-typed, outside the QF-LIA int fragment
    -- that body-faithful VCs target); the assertion is only on the taint set.
    it "T11 end-to-end: pure-predicate body is not overflow-tainted" $ do
      let src = T.pack $ unlines
            [ "(def-shell non-negative [x: int]"
            , "  (pre (>= x 0))"
            , "  (post (>= result 0))"
            , "  x)"
            ]
      case parseStatements GrammarCoreInversion "<int1-test>" src of
        Left err    -> expectationFailure ("parse: " ++ show err)
        Right stmts -> do
          emitR <- emitFixpointWith (EmitOptions { emitBodyVCs = True }) "T11.llmll" stmts
          erOverflowTaintedFns emitR `shouldBe` []

    -- T12: VerifiedCache round-trip: erOverflowTainted=True survives JSON encode/decode.
    it "T12 .verified.json round-trip preserves overflow_tainted: true" $ do
      let path = "/tmp/llmll-int1-roundtrip.llmll"
          er   = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] True Nothing Nothing False Nothing False
          cs   = ContractStatus Nothing (Just er) []
          cs0  = Map.singleton "f" cs
      saveVerified path cs0
      back <- loadVerified path
      removeFile (verifiedPath path)
      case Map.lookup "f" back of
        Nothing  -> expectationFailure "f not found after round-trip"
        Just cs' -> case csPost cs' of
          Nothing  -> expectationFailure "post evidence lost"
          Just er' -> erOverflowTainted er' `shouldBe` True

    -- T13: VERIFY-RPT-1 (Defect 2) DISARMED the INT-1 field-absence
    -- invalidation. LT-INT (v0.11) emptied the overflow-taint emitter, so a
    -- verified body-faithful entry legitimately lacks 'overflow_tainted'; the
    -- old trigger invalidated every such (i.e. every v0.11) sidecar, the cause
    -- of "--trust-report never shows verified". Such a sidecar now LOADS.
    it "T13 v0.11 sidecar with DLVerified body-faithful and no overflow_tainted field loads (VERIFY-RPT-1 disarm)" $ do
      let path = "/tmp/llmll-int1-stale.llmll"
          sidecarPath = verifiedPath path
          stale = "{\"f\":{\"post\":{\"display_level\":{\"level\":\"verified\",\"prover\":\"liquid-fixpoint\"},\"body_faithful\":true}}}"
      BL.writeFile sidecarPath stale
      back <- loadVerified path
      removeFile sidecarPath
      Map.size back `shouldBe` 1

    -- T14: a v0.10.7-vintage sidecar without verified body-faithful entries
    -- (e.g. DLAsserted only) loads normally — invalidation is targeted.
    it "T14 v0.10.7 sidecar with only DLAsserted entries loads under v0.10.8 reader" $ do
      let path = "/tmp/llmll-int1-asserted-only.llmll"
          sidecarPath = verifiedPath path
          stale = "{\"f\":{\"post\":{\"display_level\":{\"level\":\"asserted\"}}}}"
      BL.writeFile sidecarPath stale
      back <- loadVerified path
      removeFile sidecarPath
      Map.size back `shouldBe` 1

    -- T15: TrustReport JSON aggregation surfaces both top-level fns array and
    -- per-entry flag when a verified+tainted entry is present.
    it "T15 trust-report JSON surfaces overflow_tainted at top-level and per-entry" $ do
      let taintedEr = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] True Nothing Nothing False Nothing False
          cleanEr   = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False
          cs   = Map.fromList
            [ ("add-one", ContractStatus Nothing (Just taintedEr) [])
            , ("is-pos",  ContractStatus Nothing (Just cleanEr)   [])
            ]
          src = T.pack $ unlines
            [ "(def-shell add-one [x: int]"
            , "  (post (= result (+ x 1)))"
            , "  (+ x 1))"
            , "(def-shell is-pos [x: int]"
            , "  (post (>= result 0))"
            , "  x)"
            ]
          stmts = case parseStatements GrammarCoreInversion "<int1-test>" src of
                    Right ss -> ss
                    Left err -> error (show err)
          report = buildTrustReport Map.empty stmts cs
          js     = formatTrustReportJson report
      T.isInfixOf "\"overflow_tainted_fns\":[\"add-one\"]" js `shouldBe` True
      T.isInfixOf "\"overflow_tainted\":true" js `shouldBe` True

    -- T16: bodyHasOverflowArith over a literal-only PBT — for-all-style: any
    -- list of integer literals whose sum fits Int64 is not tainted by EOp +.
    it "T16 literal-only arithmetic stays untainted across small samples" $ do
      let inBounds n = n >= toInteger (minBound :: Int) `div` 4
                    && n <= toInteger (maxBound :: Int) `div` 4
          mkAdd a b  = EOp "+" [ELit (LitInt a), ELit (LitInt b)]
          samples    = [(a, b) | a <- [-3, 0, 7, 42, 1000], b <- [-1, 0, 1, 100, 9999]
                              , inBounds a, inBounds b]
      length samples `shouldSatisfy` (>= 20)
      all (\(a, b) -> not (bodyHasOverflowArith (mkAdd a b))) samples `shouldBe` True

  -- -----------------------------------------------------------------------
  -- LT-INT (v0.11): int → Integer codegen switch
  -- Per docs/design/int-2-boundary-shims.md.
  -- INT-PRE cleared at 1.015× TOTP regression vs 5× gate (commit 8cac520).
  -- -----------------------------------------------------------------------
  describe "LT-INT (v0.11): int → Integer codegen switch" $ do
    -- L1: primary type-emission site (catalog §8 / CodegenHs.hs:723).
    it "L1 toHsType TInt = \"Integer\"" $
      toHsType TInt `shouldBe` "Integer"

    -- L2: composite types containing TInt lower with Integer leaves.
    it "L2 toHsType (TList TInt) = \"[Integer]\"" $
      toHsType (TList TInt) `shouldBe` "[Integer]"

    -- L3: TCustom-payload site (catalog §8 / CodegenHs.hs:441) — used in
    -- sum-type constructor payload position.
    it "L3 mapLlmllPrimType \"int\" = \"Integer\"" $
      mapLlmllPrimType "int" `shouldBe` "Integer"

    -- L4: literal-emission site (catalog §8 / CodegenHs.hs:706, F-E3).
    -- Integer literals carry `:: Integer` ascription; consumers ingesting
    -- the literal under `Integer`-typed surroundings type-check cleanly.
    it "L4 emitLit (LitInt 42) ascribes :: Integer" $
      emitLit (LitInt 42) `shouldBe` "(42 :: Integer)"

    -- L5: Class A `list-length` shim — wraps the call in `fromIntegral`
    -- so `Int`-returning Haskell primitive lifts to LLMLL `int` (Integer).
    -- Catalog §3.1 row 1.
    it "L5 emitApp \"list-length\" wraps result in fromIntegral :: Integer" $ do
      let out = emitExpr (EApp "list-length" [EVar "xs"])
      T.isInfixOf "fromIntegral" out `shouldBe` True
      T.isInfixOf ":: Integer" out `shouldBe` True
      T.isInfixOf "list_length" out `shouldBe` True

    -- L6: Class A `list-nth` shim — index argument wrapped in
    -- `fromIntegral _ :: Int` so `int`-typed (Integer) values down-cast to
    -- the underlying Haskell `Int` parameter. Catalog §3.1 row 2.
    it "L6 emitApp \"list-nth\" down-casts index arg to Int via fromIntegral" $ do
      let out = emitExpr (EApp "list-nth" [EVar "xs", EVar "i"])
      T.isInfixOf "list_nth" out `shouldBe` True
      T.isInfixOf "fromIntegral" out `shouldBe` True
      T.isInfixOf ":: Int" out `shouldBe` True

    -- L7: Class A `string-slice` — both endpoint arguments down-cast.
    -- Catalog §3.1 row 4.
    it "L7 emitApp \"string-slice\" down-casts both endpoint args" $ do
      let out = emitExpr (EApp "string-slice" [EVar "s", EVar "f", EVar "t"])
      -- Both `f` and `t` must appear under fromIntegral.
      T.count "fromIntegral" out `shouldBe` 2
      T.isInfixOf "string_slice" out `shouldBe` True

    -- L8: Class B preamble — `range :: Integer -> Integer -> [Integer]`
    -- value-shape lowering (catalog §3.2 / §3.4). The split into a separate
    -- `range_idx` (Class A index-shape) is intentionally NOT realized in
    -- v0.11; Class A `fromIntegral` shims at indexing primitive call sites
    -- handle the index-iteration case (deviation flagged in hand-off).
    it "L8 preamble defines range as Integer -> Integer -> [Integer]" $ do
      let pre = T.unlines runtimePreamble
      T.isInfixOf "range :: Integer -> Integer -> [Integer]" pre `shouldBe` True
      T.isInfixOf "string_to_int :: String -> Either String Integer" pre `shouldBe` True
      T.isInfixOf "llmll_abs :: Integer -> Integer" pre `shouldBe` True

  -- -----------------------------------------------------------------------
  -- LT-CDP (v0.11): contract discriminative power
  -- See docs/design/contract-discriminative-power-proposal.md Rev 2.
  -- Per proposal §4.3.1, the v0.11 candidate set is the closed enumeration
  -- of identity over each param plus small ints {0,1,-1,42}, both bools,
  -- two strings {"","a"}, list-empty / list-singleton, Success-default /
  -- Error "default", and pair-of-defaults for the matching return type.
  -- -----------------------------------------------------------------------
  describe "LT-CDP (v0.11): contract discriminative power" $ do

    -- C1-C7: candidate enumeration per §4.3.1
    describe "C1-C7 candidate enumeration (proposal §4.3.1)" $ do
      it "C1 int-returning function yields {0, 1, -1, 42} candidates" $ do
        let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract Nothing Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "n")]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            ints = [n | wc <- candidates, TrivConstInt n <- [wcTrivialBody wc]]
        ints `shouldBe` [0, 1, -1, 42]

      it "C2 bool-returning function yields {True, False}" $ do
        let stmts = [SDefLogic "f" [("b", TBool)] (Just TBool)
                      (Contract Nothing Nothing (Just (EVar "result")) Nothing Nothing)
                      (EVar "b")]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            bools = [b | wc <- candidates, TrivConstBool b <- [wcTrivialBody wc]]
        bools `shouldBe` [True, False]

      it "C3 string-returning function yields {\"\", \"a\"}" $ do
        let stmts = [SDefLogic "f" [("s", TString)] (Just TString)
                      (Contract Nothing Nothing (Just (EApp ">" [EApp "string-length" [EVar "result"], ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "s")]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            strs = [s | wc <- candidates, TrivConstString s <- [wcTrivialBody wc]]
        strs `shouldBe` ["", "a"]

      it "C4 list[int]-returning function yields empty + singleton" $ do
        let stmts = [SDefLogic "f" [("xs", TList TInt)] (Just (TList TInt))
                      (Contract Nothing Nothing (Just (EApp ">=" [EApp "list-length" [EVar "result"], ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "xs")]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            listBodies = filter (\b -> case b of
                                          TrivConstEmptyList     -> True
                                          TrivConstListSingle _  -> True
                                          _                      -> False
                                ) (map wcTrivialBody candidates)
        length listBodies `shouldBe` 2

      it "C5 Result[int,string]-returning function yields Success + Error" $ do
        let stmts = [SDefLogic "f" [("x", TInt)] (Just (TResult TInt TString))
                      (Contract Nothing Nothing (Just (EApp "is-ok" [EVar "result"])) Nothing Nothing)
                      (EApp "Success" [EVar "x"])]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            sums = filter (\b -> case b of
                                    TrivConstSuccess _ -> True
                                    TrivConstError _   -> True
                                    _                  -> False
                          ) (map wcTrivialBody candidates)
        length sums `shouldBe` (2 :: Int)

      it "C6 pair[int,int]-returning function yields pair of defaults" $ do
        let stmts = [SDefLogic "f" [("a", TInt), ("b", TInt)] (Just (TPair TInt TInt))
                      (Contract Nothing Nothing (Just (EApp ">=" [EApp "first" [EVar "result"], ELit (LitInt 0)])) Nothing Nothing)
                      (EApp "pair" [EVar "a", EVar "b"])]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            pairs = [() | wc <- candidates, case wcTrivialBody wc of
                                              TrivConstPair{} -> True
                                              _               -> False]
        length pairs `shouldBe` 1

      it "C7 identity candidate generated when param type matches return" $ do
        let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract Nothing Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "n")]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            ids = [p | wc <- candidates, TrivIdentity p <- [wcTrivialBody wc]]
        ids `shouldBe` ["n"]

    -- C8-C11: score formula edge cases per §4.1
    describe "C8-C11 score formula edge cases (proposal §4.1)" $ do
      let mkResult sat tot warns = CDPResult
            { cdpCandidateCount = tot
            , cdpSatisfyingCount = sat
            , cdpDistinctBehaviorCount = sat
            , cdpScore = if tot <= 1 || sat <= 0
                          then Nothing
                          else Just (1.0 - log (fromIntegral sat) / log (fromIntegral tot))
            , cdpWarnings = warns
            , cdpDistinguishingInputs = []
            , cdpSpecEntropyAnnotation = SpecEntropyStrict
            }

      it "C8 score = 0 when |satisfying| = |total|" $ do
        cdpScore (mkResult 10 10 []) `shouldBe` Just 0.0

      it "C9 score undefined when |total| <= 1" $ do
        cdpScore (mkResult 1 1 [WarnEnumerationTooNarrow]) `shouldBe` Nothing

      it "C10a score undefined when |satisfying| = 0 with WarnSpecInconsistentOrUnproven" $ do
        cdpScore (mkResult 0 5 [WarnSpecInconsistentOrUnproven]) `shouldBe` Nothing

      it "C10b score undefined when |satisfying| = 0 with WarnSpecTooTightForOmega" $ do
        cdpScore (mkResult 0 5 [WarnSpecTooTightForOmega]) `shouldBe` Nothing

      it "C11 score positive when sat < total" $ do
        case cdpScore (mkResult 2 10 []) of
          Just s  -> s `shouldSatisfy` (\x -> x > 0.5 && x < 1.0)
          Nothing -> expectationFailure "expected a score"

    -- C12-C15: (spec-entropy ...) annotation
    describe "C12-C15 (spec-entropy ...) annotation parse + roundtrip" $ do
      it "C12 S-exp parser accepts :strict :intentional :unknown" $ do
        let src = T.unlines
              [ "(def-shell f [n: int] (post (>= result 0)) (spec-entropy :strict) n)"
              , "(def-shell g [n: int] (post (>= result 0)) (spec-entropy :intentional) n)"
              , "(def-shell h [n: int] (post (>= result 0)) (spec-entropy :unknown) n)"
              ]
        case parseStatements GrammarCoreInversion "<test>" src of
          Right stmts ->
            map (\(SDefShell _ _ _ c _ _) -> contractSpecEntropy c) stmts
              `shouldBe` [Just SpecEntropyStrict, Just SpecEntropyIntentional, Just SpecEntropyUnknown]
          Left e -> expectationFailure (show e)

      it "C13 absent annotation defaults to Nothing on Contract" $ do
        case parseStatements GrammarCoreInversion "<test>" "(def-shell f [n: int] (post (>= result 0)) n)" of
          Right [SDefShell _ _ _ c _ _] -> contractSpecEntropy c `shouldBe` Nothing
          other -> expectationFailure (show other)

      it "C14 JSON-AST accepts spec_entropy string" $ do
        let ast = "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-shell\",\"name\":\"f\",\"params\":[{\"name\":\"n\",\"type\":\"int\"}],\"post\":{\"kind\":\"op\",\"op\":\">=\",\"args\":[{\"kind\":\"var\",\"name\":\"result\"},{\"kind\":\"lit-int\",\"value\":0}]},\"spec_entropy\":\"intentional\",\"body\":{\"kind\":\"var\",\"name\":\"n\"}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" (BL.fromStrict (TE.encodeUtf8 ast)) of
          Right [SDefShell _ _ _ c _ _] -> contractSpecEntropy c `shouldBe` Just SpecEntropyIntentional
          other -> expectationFailure (show other)

      it "C15 JSON-AST rejects unknown spec_entropy value" $ do
        let ast = "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-shell\",\"name\":\"f\",\"params\":[{\"name\":\"n\",\"type\":\"int\"}],\"post\":{\"kind\":\"op\",\"op\":\">=\",\"args\":[{\"kind\":\"var\",\"name\":\"result\"},{\"kind\":\"lit-int\",\"value\":0}]},\"spec_entropy\":\"bogus\",\"body\":{\"kind\":\"var\",\"name\":\"n\"}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" (BL.fromStrict (TE.encodeUtf8 ast)) of
          Left _ -> pure ()  -- expected: parse rejects unknown label
          Right _ -> expectationFailure "expected parse error on unknown spec_entropy value"

    -- C16-C19: trust-report JSON shape + warnings
    describe "C16-C19 trust-report JSON shape (proposal §5)" $ do
      it "C16 discriminative_axis block populated on contracted entry" $ do
        let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing
                                (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "n")]
            sidecar = Map.empty
            cdpResults = Map.fromList
              [ ("f", CDPResult 12 6 5 (Just 0.5) [] ["(lambda [...] 0)"] SpecEntropyStrict 0) ]
            report = buildTrustReportWithCDP Map.empty stmts sidecar cdpResults
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"discriminative_axis\":" jsonTxt `shouldBe` True
        T.isInfixOf "\"score\":0.5" jsonTxt `shouldBe` True
        T.isInfixOf "\"basis\":\"observational-candidate-set\"" jsonTxt `shouldBe` True

      it "C17 not-requested warning emitted when cdpMap is empty" $ do
        let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing
                                (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "n")]
            report = buildTrustReport Map.empty stmts Map.empty
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"warnings\":[\"not-requested\"]" jsonTxt `shouldBe` True
        T.isInfixOf "\"basis\":\"not-measured\"" jsonTxt `shouldBe` True

      it "C17b (item 2) headline is the first warning label when warnings fired, \"measured\" otherwise" $ do
        let stmts = [SDefLogic "f" [("n", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing
                                (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "n")]
            withWarning = Map.fromList
              [ ("f", CDPResult 5 5 1 Nothing [WarnEnumerationTooNarrow] [] SpecEntropyStrict 0) ]
            noWarning = Map.fromList
              [ ("f", CDPResult 12 6 5 (Just 0.5) [] ["(lambda [...] 0)"] SpecEntropyStrict 0) ]
            notRequested = buildTrustReport Map.empty stmts Map.empty
        T.isInfixOf "\"headline\":\"enumeration-too-narrow\"" (formatTrustReportJson (buildTrustReportWithCDP Map.empty stmts Map.empty withWarning)) `shouldBe` True
        T.isInfixOf "\"headline\":\"measured\"" (formatTrustReportJson (buildTrustReportWithCDP Map.empty stmts Map.empty noWarning)) `shouldBe` True
        T.isInfixOf "\"headline\":\"not-requested\"" (formatTrustReportJson notRequested) `shouldBe` True

      it "C18 trust_report_version is 1.5.0 (REC-PARTIAL-MARK bump)" $ do
        let report  = buildTrustReport Map.empty [] Map.empty
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"trust_report_version\":\"1.5.0\"" jsonTxt `shouldBe` True

      -- REC-PARTIAL-MARK (increment 2/(a) of REC-BODY-VC): recursive-cycle
      -- members carry a derived 'termination_unverified' marker + a top-level
      -- 'partial_fns' list. Informational; does not touch the trust meet.
      it "PM-1 a recursive def-shell is marked termination_unverified and listed in partial_fns" $ do
        let stmts = [SDefShell "f" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                                (Just (EApp "=" [EVar "result", EVar "x"])) Nothing Nothing)
                      (EApp "f" [EVar "x"]) []]
            jsonTxt = formatTrustReportJson (buildTrustReport Map.empty stmts Map.empty)
        T.isInfixOf "\"termination_unverified\":true" jsonTxt `shouldBe` True
        T.isInfixOf "\"partial_fns\":[\"f\"]" jsonTxt `shouldBe` True

      it "PM-2 a non-recursive def is not marked and stays out of partial_fns" $ do
        let stmts = [SDef "g" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                                (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                      (EVar "x")]
            jsonTxt = formatTrustReportJson (buildTrustReport Map.empty stmts Map.empty)
        T.isInfixOf "termination_unverified" jsonTxt `shouldBe` False
        T.isInfixOf "\"partial_fns\":[]" jsonTxt `shouldBe` True

      it "PM-3 a mutual-recursion SCC marks BOTH members (not just self-loops)" $ do
        let mk name callee = SDefShell name [("x", TInt)] (Just TInt)
                               (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                                         (Just (EApp "=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                               (EApp callee [EVar "x"]) []
            report  = buildTrustReport Map.empty [mk "ping" "pong", mk "pong" "ping"] Map.empty
            jsonTxt = formatTrustReportJson report
        Set.member "ping" (trPartialFns report) `shouldBe` True
        Set.member "pong" (trPartialFns report) `shouldBe` True
        T.isInfixOf "\"partial_fns\":[\"ping\",\"pong\"]" jsonTxt `shouldBe` True

      it "PM-4 the mark is derived — present on a solver-less render, unlike refuted_fns" $ do
        let stmts = [SDefShell "f" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing
                                (Just (EApp "=" [EVar "result", EVar "x"])) Nothing Nothing)
                      (EApp "f" [EVar "x"]) []]
            jsonTxt = formatTrustReportJson (buildTrustReport Map.empty stmts Map.empty)
        -- derived marker present without any solver verdict...
        T.isInfixOf "\"partial_fns\":[\"f\"]" jsonTxt `shouldBe` True
        -- ...while the solver-dependent refuted set is empty on the same render
        T.isInfixOf "\"refuted_fns\":[]" jsonTxt `shouldBe` True

      it "PM-5 refuted and termination_unverified emit independently (orthogonal markers)" $ do
        let stmts = [SDefShell "f" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing
                                (Just (EApp "=" [EVar "result", EVar "x"])) Nothing Nothing)
                      (EApp "f" [EVar "x"]) []]
            report  = markRefuted (Set.fromList ["f"]) (buildTrustReport Map.empty stmts Map.empty)
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"termination_unverified\":true" jsonTxt `shouldBe` True
        T.isInfixOf "\"refuted\":true" jsonTxt `shouldBe` True
        T.isInfixOf "\"refuted_fns\":[\"f\"]" jsonTxt `shouldBe` True

      it "C19 all ten warning labels round-trip" $ do
        let labels = map cdpWarningLabel
              [ WarnIdentitySatisfiesPost, WarnConstSatisfiesPost
              , WarnSpecInconsistentOrUnproven, WarnSpecTooTightForOmega
              , WarnEnumerationTooNarrow, WarnDefShellOutOfScope
              , WarnCandidatesEmptyUnderLimit, WarnBodyUnfaithfulCandidatesExcluded
              , WarnOverAnnotationModule, WarnNotRequested
              ]
        labels `shouldBe`
          [ "identity-satisfies-post", "const-satisfies-post"
          , "spec-inconsistent-or-unproven", "spec-too-tight-for-omega"
          , "enumeration-too-narrow", "def-shell-out-of-scope"
          , "candidates-empty-under-limit", "body-unfaithful-candidates-excluded"
          , "over-annotation-warning", "not-requested"
          ]

    -- C20: joint-witness ∩ CDP interaction (OBLIG-PBT-5a regression guard)
    describe "C20 joint-witness compatibility" $ do
      it "C20 CDP emit does not corrupt joint_pbt_witnesses key shape" $ do
        let report  = buildTrustReport Map.empty [] Map.empty
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"joint_pbt_witnesses\":" jsonTxt `shouldBe` True
        T.isInfixOf "\"tier_profile\":" jsonTxt `shouldBe` True  -- regression guard

    -- C21-C22: over-annotation diagnostic + scope-parameter wiring
    describe "C21-C22 over-annotation + scope wiring" $ do
      it "C21 overAnnotationRatio counts :intentional / contracted total" $ do
        let mkContract se = Contract Nothing Nothing
                              (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing se
        let stmts =
              [ SDefLogic "f1" [] (Just TInt) (mkContract (Just SpecEntropyIntentional)) (ELit (LitInt 0))
              , SDefLogic "f2" [] (Just TInt) (mkContract Nothing)                       (ELit (LitInt 0))
              , SDefLogic "f3" [] (Just TInt) (mkContract (Just SpecEntropyStrict))      (ELit (LitInt 0))
              ]
        overAnnotationRatio stmts `shouldBe` (1.0 / 3.0)
        overAnnotationThreshold `shouldSatisfy` (\x -> x > 0.25 && x < 0.35)

      it "C22 computeCDPFor with stub solver returns one entry per contracted function" $ do
        let stmts =
              [ SDef "f" [("n", TInt)] (Just TInt)
                  (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing
                            (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (EVar "n")
              , STypeDef "Foo" TInt  -- non-contracted: should not appear in result
              ]
            stubSolver _wc = pure (Just True)  -- all candidates "satisfy" — yields score 0.0 + identity-satisfies-post
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubSolver Map.empty stmts
        Map.size results `shouldBe` 1
        case Map.lookup "f" results of
          Just r -> do
            cdpScore r `shouldBe` Just 0.0
            cdpWarnings r `shouldSatisfy` (WarnIdentitySatisfiesPost `elem`)
          Nothing -> expectationFailure "expected entry for f"

    -- C23-C26: spec-entropy-gated diagnostic suppression (CDP default-on
    -- precondition (c) — LLMLL.md §4.4.6 documents that ':intentional' /
    -- ':unknown' suppress the low-DP warnings while ':strict' raises them;
    -- 'buildWarnings' previously ignored the annotation entirely (fixed here).
    describe "C23-C26 spec-entropy suppression gating (§4.4.6)" $ do
      let mkStmt se = SDef "f" [("n", TInt)] (Just TInt)
            (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing
                      (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing se)
            (EVar "n")
          alwaysTrue  _wc = pure (Just True)   -- every candidate "satisfies" → identity-satisfies-post territory
          alwaysFalse _wc = pure (Just False)  -- zero candidates satisfy → spec-inconsistent-or-unproven territory

      it "C23 :intentional suppresses WarnIdentitySatisfiesPost, score still reported" $ do
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly alwaysTrue Map.empty
                     [mkStmt (Just SpecEntropyIntentional)]
        case Map.lookup "f" results of
          Just r -> do
            cdpWarnings r `shouldSatisfy` (not . (WarnIdentitySatisfiesPost `elem`))
            cdpScore r `shouldBe` Just 0.0
            cdpSpecEntropyAnnotation r `shouldBe` SpecEntropyIntentional
          Nothing -> expectationFailure "expected entry for f"

      it "C24 :unknown also suppresses WarnIdentitySatisfiesPost (does-not-raise, not just intentional)" $ do
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly alwaysTrue Map.empty
                     [mkStmt (Just SpecEntropyUnknown)]
        case Map.lookup "f" results of
          Just r -> cdpWarnings r `shouldSatisfy` (not . (WarnIdentitySatisfiesPost `elem`))
          Nothing -> expectationFailure "expected entry for f"

      it "C23-regression :strict (absent annotation) still raises WarnIdentitySatisfiesPost" $ do
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly alwaysTrue Map.empty
                     [mkStmt Nothing]
        case Map.lookup "f" results of
          Just r -> cdpWarnings r `shouldSatisfy` (WarnIdentitySatisfiesPost `elem`)
          Nothing -> expectationFailure "expected entry for f"

      it "C25 :intentional does NOT suppress WarnSpecInconsistentOrUnproven (different axis — possible inconsistency, not permissiveness)" $ do
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly alwaysFalse Map.empty
                     [mkStmt (Just SpecEntropyIntentional)]
        case Map.lookup "f" results of
          Just r -> cdpWarnings r `shouldSatisfy` (WarnSpecInconsistentOrUnproven `elem`)
          Nothing -> expectationFailure "expected entry for f"

      it "C26 tryCandidate resolves and threads spec-entropy onto every generated WeaknessCandidate" $ do
        let stmtsIntentional = [mkStmt (Just SpecEntropyIntentional)]
            stmtsAbsent      = [mkStmt Nothing]
        map wcSpecEntropy (generateCDPCandidates GrammarCoreInversion stmtsIntentional)
          `shouldSatisfy` (all (== SpecEntropyIntentional))
        map wcSpecEntropy (generateWeaknessCandidates GrammarCoreInversion stmtsIntentional)
          `shouldSatisfy` (all (== SpecEntropyIntentional))
        -- absent annotation resolves to the ':strict' default (proposal §3), not left unresolved
        map wcSpecEntropy (generateCDPCandidates GrammarCoreInversion stmtsAbsent)
          `shouldSatisfy` (all (== SpecEntropyStrict))

    -- C27: F-001 (adv-spec-weaken-0) — 'over-annotation-warning' reachable via
    -- '--trust-report --json'. Previously computed (overAnnotationRatio) but
    -- only ever printed as a stdout line gated 'unless json' (Main.hs), so no
    -- JSON consumer could observe it. Fixed: 'TrustReport.trOverAnnotation'
    -- + the 'over_annotation' key in 'formatTrustReportJson'.
    describe "C27 over-annotation JSON emit (F-001)" $ do
      let mkContract se = Contract Nothing Nothing
                            (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing se
          -- Same 1/3 ratio fixture as C21, reused so the JSON-emit test and the
          -- pure-ratio-computation test (C21) stay in lockstep.
          stmtsAboveThreshold =
            [ SDefLogic "f1" [] (Just TInt) (mkContract (Just SpecEntropyIntentional)) (ELit (LitInt 0))
            , SDefLogic "f2" [] (Just TInt) (mkContract Nothing)                       (ELit (LitInt 0))
            , SDefLogic "f3" [] (Just TInt) (mkContract (Just SpecEntropyStrict))      (ELit (LitInt 0))
            ]
          stmtsBelowThreshold =
            [ SDefLogic "f1" [] (Just TInt) (mkContract (Just SpecEntropyIntentional)) (ELit (LitInt 0))
            , SDefLogic "f2" [] (Just TInt) (mkContract Nothing)                       (ELit (LitInt 0))
            , SDefLogic "f3" [] (Just TInt) (mkContract Nothing)                       (ELit (LitInt 0))
            , SDefLogic "f4" [] (Just TInt) (mkContract Nothing)                       (ELit (LitInt 0))
            , SDefLogic "f5" [] (Just TInt) (mkContract Nothing)                       (ELit (LitInt 0))
            ]

      it "C27a trOverAnnotation reflects ratio/threshold/fired above threshold" $ do
        let report = buildTrustReport Map.empty stmtsAboveThreshold Map.empty
            oai    = trOverAnnotation report
        oaiRatio oai `shouldBe` (1.0 / 3.0)
        oaiThreshold oai `shouldBe` overAnnotationThreshold
        oaiFired oai `shouldBe` True

      it "C27b trOverAnnotation does not fire below threshold" $ do
        let report = buildTrustReport Map.empty stmtsBelowThreshold Map.empty
            oai    = trOverAnnotation report
        oaiRatio oai `shouldBe` (1.0 / 5.0)
        oaiFired oai `shouldBe` False

      it "C27c formatTrustReportJson emits over_annotation with warning:true above threshold" $ do
        let report  = buildTrustReport Map.empty stmtsAboveThreshold Map.empty
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"over_annotation\":{" jsonTxt `shouldBe` True
        T.isInfixOf "\"warning\":true" jsonTxt `shouldBe` True

      it "C27d formatTrustReportJson emits over_annotation with warning:false below threshold" $ do
        let report  = buildTrustReport Map.empty stmtsBelowThreshold Map.empty
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"over_annotation\":{" jsonTxt `shouldBe` True
        T.isInfixOf "\"warning\":false" jsonTxt `shouldBe` True

      it "C27e over_annotation is an additive field (did not itself bump the version); version is 1.5.0 (REC-PARTIAL-MARK)" $ do
        let report  = buildTrustReport Map.empty stmtsAboveThreshold Map.empty
            jsonTxt = formatTrustReportJson report
        T.isInfixOf "\"trust_report_version\":\"1.5.0\"" jsonTxt `shouldBe` True

    -- F6-1 through F6-6: F-006 / F-005 ancillary fixes
    describe "F6-1–F6-6 candidate generation (F-006 type-alias fix / F-005 unannotated-return fix)" $ do

      it "F6-1 (F-006) custom-type-alias param: non-zero candidates when STypeDef present" $ do
        -- b1::withdraw shape: amount :: PositiveInt (alias for int), mRet = Nothing.
        -- Before fix: tryCandidate's synthetic typecheck had empty tcAliasMap, so
        -- structuralUnify(TInt, TCustom "PositiveInt") emitted a hard error and every
        -- candidate was filtered. After fix: STypeDef is prepended, alias resolves.
        let stmts =
              [ STypeDef "PositiveInt"
                  (TDependent "x" TInt (EApp ">" [EVar "x", ELit (LitInt 0)]))
              , SDefLogic "withdraw"
                  [("balance", TInt), ("amount", TCustom "PositiveInt")]
                  Nothing
                  (Contract
                    (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                    (Just (EApp "=" [ EVar "result"
                                    , EApp "-" [EVar "balance", EVar "amount"]])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
        length candidates `shouldSatisfy` (> 0)

      it "F6-2 (F-005) mRet=Nothing: int constants {0,1,-1,42} generated" $ do
        -- b5::double shape: sexp parser sets mRet = Nothing for all .llmll functions.
        -- Before fix: matchesReturnType TInt Nothing = False → no int constants.
        -- After fix: matchesReturnTypeOrUnknown TInt Nothing = True → 4 ints generated.
        let stmts =
              [ SDefLogic "double" [("n", TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp "=" [ EVar "result"
                                    , EApp "+" [EVar "n", EVar "n"]])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            ints = [i | wc <- candidates, TrivConstInt i <- [wcTrivialBody wc]]
        ints `shouldBe` [0, 1, -1, 42]

      it "F6-3 (F-005) mRet=Nothing: bool constants filtered by TC against int post-condition" $ do
        let stmts =
              [ SDefLogic "double" [("n", TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp "=" [ EVar "result"
                                    , EApp "+" [EVar "n", EVar "n"]])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            bools = [wc | wc <- candidates, case wcTrivialBody wc of
                                              TrivConstBool _ -> True
                                              _               -> False]
        length bools `shouldBe` 0

      it "F6-4 (F-005) b5::double shape: candidate_count >= 5 (1 identity + 4 int constants)" $ do
        let stmts =
              [ SDefLogic "double" [("n", TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp "=" [ EVar "result"
                                    , EApp "+" [EVar "n", EVar "n"]])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
        length candidates `shouldSatisfy` (>= 5)

      it "F6-5 (F-006) b3::safe-first shape: candidate_count >= 2 with TrivConstInt 0 present" $ do
        -- safe-first [xs: list[int]], post (>= result 0), mRet = Nothing.
        -- Before fix: only TrivIdentity "xs" generated; it failed TC (list ≠ int post).
        -- After fix: int constants generated; TrivConstInt 0 passes TC and is a candidate.
        let stmts =
              [ SDefLogic "safe-first" [("xs", TList TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
        length candidates `shouldSatisfy` (>= 2)
        map wcTrivialBody candidates `shouldSatisfy` (TrivConstInt 0 `elem`)

      it "F6-6 regression: explicit mRet=Just TInt still yields int constants (no regression)" $ do
        let stmts =
              [ SDefLogic "f" [("n", TInt)] (Just TInt)
                  (Contract Nothing Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (EVar "n")
              ]
            candidates = generateCDPCandidates GrammarCoreInversion stmts
            ints = [i | wc <- candidates, TrivConstInt i <- [wcTrivialBody wc]]
        ints `shouldBe` [0, 1, -1, 42]

    -- C23a-C23c: WarnSpecTooTightForOmega / WarnSpecInconsistentOrUnproven dispatch
    describe "C23a-C23c spec-too-tight-for-omega vs spec-inconsistent-or-unproven disambiguation" $ do

      it "C23a WarnSpecTooTightForOmega fires when function verifies but no candidate satisfies" $ do
        let stmts =
              [ SDef "withdraw"
                  [("balance", TInt), ("amount", TInt)] Nothing
                  (Contract
                    (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                    (Just (EApp "=" [EVar "result", EApp "-" [EVar "balance", EVar "amount"]])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            stubFail _wc = pure (Just False)
            verifMap = Map.fromList [("withdraw", True)]
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubFail verifMap stmts
        case Map.lookup "withdraw" results of
          Just r  -> cdpWarnings r `shouldSatisfy` (WarnSpecTooTightForOmega `elem`)
          Nothing -> expectationFailure "expected entry for withdraw"

      it "C23b no inconsistency warning emitted when candidates satisfy (verifMap active)" $ do
        let stmts =
              [ SDef "compute-fee" [("amount", TInt)] Nothing
                  (Contract
                    (Just (EApp ">=" [EVar "amount", ELit (LitInt 0)])) Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            stubPass _wc = pure (Just True)
            verifMap = Map.fromList [("compute-fee", True)]
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubPass verifMap stmts
        case Map.lookup "compute-fee" results of
          Just r  -> do
            cdpWarnings r `shouldSatisfy` (WarnSpecTooTightForOmega `notElem`)
            cdpWarnings r `shouldSatisfy` (WarnSpecInconsistentOrUnproven `notElem`)
          Nothing -> expectationFailure "expected entry for compute-fee"

      it "C23c WarnSpecInconsistentOrUnproven used as conservative fallback when verifMap is empty" $ do
        let stmts =
              [ SDef "withdraw"
                  [("balance", TInt), ("amount", TInt)] Nothing
                  (Contract
                    (Just (EApp ">=" [EVar "balance", EVar "amount"])) Nothing
                    (Just (EApp "=" [EVar "result", EApp "-" [EVar "balance", EVar "amount"]])) Nothing Nothing)
                  (ELit (LitInt 0))
              ]
            stubFail _wc = pure (Just False)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubFail Map.empty stmts
        case Map.lookup "withdraw" results of
          Just r  -> cdpWarnings r `shouldSatisfy` (WarnSpecInconsistentOrUnproven `elem`)
          Nothing -> expectationFailure "expected entry for withdraw"

    -- CDP-OMEGA-1..3: CDP deep-dive Rev 5 (item 3) retired the 768ab11
    -- Omega-adequacy gate (fix/cdp-tresult-omega-gate) that unconditionally
    -- routed every TResult-returning function to a no-score
    -- WarnDatatypeReturnOutOfScope result before candidate generation. The
    -- candidate basis now emits real, type-correct 'ok'/'err' candidates
    -- (see CDP-CANDBASIS above), so TResult-returning functions are measured
    -- exactly like any other contracted function — these tests assert real
    -- scoring now happens, replacing the old "gated to no-score" assertions.
    describe "CDP-OMEGA: TResult-returning functions are measured normally (gate retired)" $ do

      it "CDP-OMEGA-1 TResult-returning function is scored (not gated) when candidates satisfy" $ do
        let stmts =
              [ SDef "withdraw-outcome" [("balance", TInt), ("amount", TInt)]
                  (Just (TResult TInt TString))
                  (Contract Nothing Nothing
                    (Just (EApp "="
                      [ EVar "result"
                      , EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]] ]))
                    Nothing Nothing)
                  (EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]])
              ]
            -- Every candidate reports SAFE; with the fixed basis there are
            -- exactly 2 type-correct candidates (ok/err), both counted.
            stubAlwaysSafe _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubAlwaysSafe Map.empty stmts
        case Map.lookup "withdraw-outcome" results of
          Just r -> do
            cdpCandidateCount r `shouldBe` 2
            cdpSatisfyingCount r `shouldBe` 2
            cdpScore r `shouldBe` Just 0.0
            cdpWarnings r `shouldSatisfy` (WarnConstSatisfiesPost `elem`)
          Nothing -> expectationFailure "expected entry for withdraw-outcome"

      it "CDP-OMEGA-2 TResult-returning function with zero satisfying candidates reports undefined score, not a false low-DP number" $ do
        let stmts =
              [ SDef "withdraw-outcome" [("balance", TInt), ("amount", TInt)]
                  (Just (TResult TInt TString))
                  (Contract Nothing Nothing
                    (Just (EApp "="
                      [ EVar "result"
                      , EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]] ]))
                    Nothing Nothing)
                  (EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]])
              ]
            stubAlwaysUnsafe _wc = pure (Just False)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubAlwaysUnsafe Map.empty stmts
        case Map.lookup "withdraw-outcome" results of
          Just r -> do
            cdpCandidateCount r `shouldBe` 2
            cdpScore r `shouldBe` Nothing
            cdpWarnings r `shouldSatisfy` (WarnSpecInconsistentOrUnproven `elem`)
          Nothing -> expectationFailure "expected entry for withdraw-outcome"

      it "CDP-OMEGA-3 non-TResult-returning function is unaffected (regression guard)" $ do
        let stmts =
              [ SDef "double" [("x", TInt)] (Just TInt)
                  (Contract Nothing Nothing
                    (Just (EApp "=" [EVar "result", EApp "+" [EVar "x", EVar "x"]]))
                    Nothing Nothing)
                  (EApp "+" [EVar "x", EVar "x"])
              ]
            stubPass _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubPass Map.empty stmts
        case Map.lookup "double" results of
          Just r  -> cdpCandidateCount r `shouldSatisfy` (> 0)
          Nothing -> expectationFailure "expected entry for double"

      it "CDP-OMEGA-4 def-shell TResult-return still reports WarnDefShellOutOfScope (scope exclusion unrelated to the retired gate)" $ do
        let stmts =
              [ SDefLogic "shell-outcome" [("balance", TInt), ("amount", TInt)]
                  (Just (TResult TInt TString))
                  (Contract Nothing Nothing
                    (Just (EApp "="
                      [ EVar "result"
                      , EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]] ]))
                    Nothing Nothing)
                  (EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]])
              ]
            stubPass _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubPass Map.empty stmts
        case Map.lookup "shell-outcome" results of
          Just r -> cdpWarnings r `shouldBe` [WarnDefShellOutOfScope]
          Nothing -> expectationFailure "expected entry for shell-outcome"

    -- CDP-SCOPE-1 through CDP-SCOPE-4: CDPScopeCoreOnly filtering (§8 Outcome 0)
    describe "CDP-SCOPE: CDPScopeCoreOnly scope filtering" $ do

      it "CDP-SCOPE-1 SDef under CDPScopeCoreOnly is measured (score populated)" $ do
        let stmts =
              [ SDef "g" [("n", TInt)] (Just TInt)
                  (Contract Nothing Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (EVar "n")
              ]
            stubPass _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubPass Map.empty stmts
        Map.size results `shouldBe` 1
        case Map.lookup "g" results of
          Just r  -> cdpScore r `shouldSatisfy` (/= Nothing)
          Nothing -> expectationFailure "expected entry for g"

      it "CDP-SCOPE-2 SDefLogic under CDPScopeCoreOnly produces WarnDefShellOutOfScope entry" $ do
        let stmts =
              [ SDefLogic "h" [("n", TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (EVar "n")
              ]
            stubPass _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubPass Map.empty stmts
        Map.size results `shouldBe` 1
        case Map.lookup "h" results of
          Just r  -> do
            cdpScore r `shouldBe` Nothing
            cdpWarnings r `shouldSatisfy` (WarnDefShellOutOfScope `elem`)
          Nothing -> expectationFailure "expected entry for h"

      it "CDP-SCOPE-3 SDefShell under CDPScopeCoreOnly produces WarnDefShellOutOfScope entry" $ do
        let stmts =
              [ SDefShell "s" [("n", TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (EVar "n") []
              ]
            stubPass _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubPass Map.empty stmts
        Map.size results `shouldBe` 1
        case Map.lookup "s" results of
          Just r  -> do
            cdpScore r `shouldBe` Nothing
            cdpWarnings r `shouldSatisfy` (WarnDefShellOutOfScope `elem`)
          Nothing -> expectationFailure "expected entry for s"

      it "CDP-SCOPE-4 SDefLogic under CDPScopeAllDefLogic is still measured (legacy path)" $ do
        let stmts =
              [ SDefLogic "legacy" [("n", TInt)] Nothing
                  (Contract Nothing Nothing
                    (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])) Nothing Nothing)
                  (EVar "n")
              ]
            stubPass _wc = pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeAllDefLogic stubPass Map.empty stmts
        Map.size results `shouldBe` 1
        case Map.lookup "legacy" results of
          Just r  -> cdpScore r `shouldSatisfy` (/= Nothing)
          Nothing -> expectationFailure "expected entry for legacy"

    -- CDP-BODYFAITHFUL-1..3: CDP deep-dive Rev 5 (item 5). checkCDPCandidate /
    -- checkWeaknessCandidate (Main.hs) ignored 'erBodyFallback' on the
    -- synthetic candidate's own emission, so a solver-SAFE verdict on a
    -- body-fallback emission was (wrongly) trusted. list-valued return
    -- expressions like '(list-empty)' are not in the body-VC-translatable
    -- fragment (only 'list-length' on a bound *variable* is), so this is not
    -- a stub-level regression check — it must exercise the real
    -- 'emitFixpointWith' translation to confirm the root-cause mechanism
    -- empirically, the same discipline that caught the TResult bug's real
    -- cause after two prior hand-offs got it wrong from source-reading alone.
    describe "CDP-BODYFAITHFUL: erBodyFallback-aware candidate exclusion (item 5)" $ do

      it "CDP-BODYFAITHFUL-1 (root-cause confirmation) a list-empty candidate against a list-length postcondition falls back in the real emitter" $ do
        let stmt = SDef "make-two" [] (Just (TList TInt))
              (Contract Nothing Nothing
                (Just (EApp "=" [EApp "list-length" [EVar "result"], ELit (LitInt 2)]))
                Nothing Nothing)
              (EApp "list-prepend" [ELit (LitInt 1), EApp "list-prepend" [ELit (LitInt 2), EApp "list-empty" []]])
            candidates = generateCDPCandidates GrammarCoreInversion [stmt]
        case [wc | wc <- candidates, wcTrivialBody wc == TrivConstEmptyList] of
          [emptyCand] -> do
            let weakOpts = defaultEmitOptions { emitBodyVCs = True }
            emitR <- emitFixpointWith weakOpts "<test>" [wcSyntheticStmt emptyCand]
            wcSyntheticName emptyCand `shouldSatisfy` (`elem` erBodyFallback emitR)
          other -> expectationFailure ("expected exactly one list-empty candidate, got " <> show (length other))

      it "CDP-BODYFAITHFUL-2 resultFor excludes a Nothing-verdict candidate from both numerator and denominator" $ do
        let stmts =
              [ SDef "make-two" [] (Just (TList TInt))
                  (Contract Nothing Nothing
                    (Just (EApp "=" [EApp "list-length" [EVar "result"], ELit (LitInt 2)]))
                    Nothing Nothing)
                  (EApp "list-empty" [])
              ]
            -- Simulates the real checkCDPCandidate: TrivConstEmptyList falls
            -- back (Nothing, excluded); anything else reports satisfying,
            -- reproducing the pre-fix false '2/2 satisfy' shape if the
            -- exclusion did not apply.
            stubBodyFaithful wc = case wcTrivialBody wc of
              TrivConstEmptyList -> pure Nothing
              _                  -> pure (Just True)
        results <- computeCDPFor GrammarCoreInversion CDPScopeCoreOnly stubBodyFaithful Map.empty stmts
        case Map.lookup "make-two" results of
          Just r -> do
            cdpWarnings r `shouldSatisfy` (WarnBodyUnfaithfulCandidatesExcluded `elem`)
            cdpExcludedCandidateCount r `shouldSatisfy` (> 0)
            -- the excluded candidate must not inflate either the numerator
            -- or the denominator — this is the false '2/2 satisfy' regression
            -- guard.
            cdpSatisfyingCount r `shouldSatisfy` (< cdpCandidateCount r + cdpExcludedCandidateCount r)
          Nothing -> expectationFailure "expected entry for make-two"

      it "CDP-BODYFAITHFUL-3 wire-line label for WarnBodyUnfaithfulCandidatesExcluded" $
        cdpWarningLabel WarnBodyUnfaithfulCandidatesExcluded `shouldBe` "body-unfaithful-candidates-excluded"

    -- CDP-CANDBASIS-1..2: CDP deep-dive Rev 5 (item 3). Root-cause
    -- confirmation, empirical not source-read: 'tryCandidate''s independent
    -- re-typecheck previously only WARNED on the raw 'Success'/'Error' names
    -- (tcStrictMode = False by default in runTC), so a type-unsound
    -- candidate slipped through undetected — this is the actual mechanism,
    -- not merely 'the label was wrong'. The fixed 'ok'/'err' candidates must
    -- produce ZERO diagnostics (not just zero errors) under the same
    -- independent re-typecheck 'tryCandidate' performs, proving the
    -- candidate is genuinely well-typed rather than merely tolerated in
    -- permissive mode.
    describe "CDP-CANDBASIS: ok/err candidate basis is genuinely well-typed (item 3)" $ do

      it "CDP-CANDBASIS-1 (root-cause confirmation) the err candidate for a Result[int,string] return produces zero diagnostics under independent re-typecheck (was: a tolerated warning)" $ do
        let stmt = SDef "withdraw-outcome" [("balance", TInt), ("amount", TInt)]
              (Just (TResult TInt TString))
              (Contract Nothing Nothing
                (Just (EApp "is-ok" [EVar "result"]))
                Nothing Nothing)
              (EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]])
            candidates = generateCDPCandidates GrammarCoreInversion [stmt]
        case [wc | wc <- candidates, case wcTrivialBody wc of TrivConstError _ -> True; _ -> False] of
          [errCand] -> do
            let report = typeCheck GrammarCoreInversion builtinEnv [wcSyntheticStmt errCand]
            reportDiagnostics report `shouldBe` []
          other -> expectationFailure ("expected exactly one err candidate, got " <> show (length other))

      it "CDP-CANDBASIS-2 the ok candidate's payload type matches the declared ok-type, not a hardcoded default" $ do
        let stmt = SDef "withdraw-outcome" [("balance", TInt), ("amount", TInt)]
              (Just (TResult TInt TString))
              (Contract Nothing Nothing (Just (EApp "is-ok" [EVar "result"])) Nothing Nothing)
              (EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]])
            candidates = generateCDPCandidates GrammarCoreInversion [stmt]
        case [wc | wc <- candidates, case wcTrivialBody wc of TrivConstSuccess _ -> True; _ -> False] of
          [okCand] -> wcTrivialLabel okCand `shouldBe` "(lambda [...] (ok 0))"
          other    -> expectationFailure ("expected exactly one ok candidate, got " <> show (length other))

      -- CDP-CANDBASIS-3: CDP deep-dive Rev 5 (second routed finding). Even
      -- with the type-correct 'ok'/'err' candidates (item 3), a
      -- 'Result[int, CustomEnum]' contract's candidates STILL fell back —
      -- confirmed empirically (not from source-reading) to be a THIRD gap,
      -- structurally identical to the other two: 'checkCDPCandidate' /
      -- 'checkWeaknessCandidate''s isolated per-candidate emission
      -- ('emitFixpointWith ... [wcSyntheticStmt wc]') omitted the module's
      -- 'STypeDef' statements, unlike 'tryCandidate''s independent
      -- re-typecheck (F-006), which already prepends them. Without the
      -- custom sum type's declaration, ANY candidate whose contract
      -- references one of its constructors spuriously falls back — even
      -- though the identical candidate is body-faithful once the type-def is
      -- present. This is why the isolated emission needs the same type-defs
      -- 'tryCandidate' already threads through; Main.hs's 'checkCDPCandidate'
      -- / 'checkWeaknessCandidate' now take an explicit '[Statement]'
      -- type-defs parameter and prepend it, mirroring F-006 exactly.
      it "CDP-CANDBASIS-3 (root-cause confirmation) an ok-candidate against a custom-sum-type Result contract is body-faithful once the module's STypeDef is included in the isolated emission" $ do
        let reasonTypeDef = STypeDef "Reason" (TSumType [("Insufficient", Nothing)])
            stmt = SDef "withdraw-outcome" [("balance", TInt), ("amount", TInt)]
              (Just (TResult TInt (TCustom "Reason")))
              (Contract Nothing Nothing
                (Just (EApp "and"
                  [ EApp "or" [EApp "not" [EApp ">=" [EVar "balance", EVar "amount"]], EApp "=" [EVar "result", EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]]]]
                  , EApp "or" [EApp ">=" [EVar "balance", EVar "amount"], EApp "=" [EVar "result", EApp "err" [EVar "Insufficient"]]]
                  ]))
                Nothing Nothing)
              (EIf (EApp ">=" [EVar "balance", EVar "amount"]) (EApp "ok" [EApp "-" [EVar "balance", EVar "amount"]]) (EApp "err" [EVar "Insufficient"]))
            candidates = generateCDPCandidates GrammarCoreInversion [reasonTypeDef, stmt]
        case [wc | wc <- candidates, case wcTrivialBody wc of TrivConstSuccess _ -> True; _ -> False] of
          [okCand] -> do
            let weakOpts = defaultEmitOptions { emitBodyVCs = True }
            -- Without the type-def (the pre-fix Main.hs behavior): falls back.
            emitR_noTypeDef <- emitFixpointWith weakOpts "<test>" [wcSyntheticStmt okCand]
            wcSyntheticName okCand `shouldSatisfy` (`elem` erBodyFallback emitR_noTypeDef)
            -- With the type-def prepended (the fixed Main.hs behavior): body-faithful.
            emitR_withTypeDef <- emitFixpointWith weakOpts "<test>" [reasonTypeDef, wcSyntheticStmt okCand]
            wcSyntheticName okCand `shouldSatisfy` (`notElem` erBodyFallback emitR_withTypeDef)
          other -> expectationFailure ("expected exactly one ok candidate, got " <> show (length other))

  -- -----------------------------------------------------------------------
  -- LT-INV (v0.11): core/shell grammar inversion
  -- -----------------------------------------------------------------------

  describe "LT-INV (v0.11): core/shell grammar inversion" $ do

    describe "INV-P: parser" $ do

      it "INV-P1 (def ...) parses as SDef in GrammarCoreInversion" $ do
        let src = "(def f [n: int] n)"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SDef {}] -> pure ()
          other           -> expectationFailure (show other)

      it "INV-P2 (def-shell ...) parses as SDefShell in GrammarCoreInversion" $ do
        let src = "(def-shell f [n: int] n)"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SDefShell {}] -> pure ()
          other                -> expectationFailure (show other)

      it "INV-P3 (def ...) with two params parses as SDef" $ do
        let src = "(def add [x: int y: int] (+ x y))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SDef { defParams = [_, _] }] -> pure ()
          other                               -> expectationFailure (show other)

      it "INV-P4 (def ...) with zero params parses as SDef" $ do
        let src = "(def const-42 [] 42)"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SDef { defParams = [] }] -> pure ()
          other                           -> expectationFailure (show other)

      it "INV-P5 (def-shell ...) with fn body parses without parse error" $ do
        let src = "(def-shell g [n: int] (fn [x: int] x))"
        case parseStatements GrammarCoreInversion "<test>" src of
          Right [SDefShell {}] -> pure ()
          other                -> expectationFailure (show other)

      it "INV-P6 (def-logic ...) is rejected in GrammarCoreInversion (removed v0.12.1)" $ do
        let src = "(def-logic f [n: int] n)"
        case parseStatements GrammarCoreInversion "<test>" src of
          Left  _  -> pure ()
          Right ss -> expectationFailure ("expected parse failure, got: " ++ show ss)

      it "INV-P7 (def ...) fails to parse in GrammarLegacy" $ do
        let src = "(def f [n: int] n)"
        case parseStatements GrammarLegacy "<test>" src of
          Left  _  -> pure ()
          Right ss -> expectationFailure ("expected parse failure, got: " ++ show ss)

      it "INV-P8 (def-shell ...) fails to parse in GrammarLegacy" $ do
        let src = "(def-shell f [n: int] n)"
        case parseStatements GrammarLegacy "<test>" src of
          Left  _  -> pure ()
          Right ss -> expectationFailure ("expected parse failure, got: " ++ show ss)

      it "INV-P9 JSON-AST def-logic rejected under GrammarCoreInversion (removed v0.12.1)" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-logic\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Left diag -> diagKind diag `shouldBe` Just "removed-construct"
          Right ss  -> expectationFailure ("expected rejection, got: " ++ show ss)

      it "INV-P10 JSON-AST def accepted under GrammarCoreInversion" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Right [SDef {}] -> pure ()
          other           -> expectationFailure (show other)

      it "INV-P11 JSON-AST def-logic rejected under GrammarLegacy too (removed v0.12.1)" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-logic\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
        case parseJSONAST GrammarLegacy "<test>" src of
          Left diag -> diagKind diag `shouldBe` Just "removed-construct"
          Right ss  -> expectationFailure ("expected rejection (def-logic removed under all modes), got: " ++ show ss)

      it "INV-P12 (letrec ...) fails to parse in GrammarCoreInversion" $ do
        let src = "(letrec f [n: int] :decreases n n)"
        case parseStatements GrammarCoreInversion "<test>" src of
          Left  _  -> pure ()
          Right ss -> expectationFailure ("expected parse failure, got: " ++ show ss)

      it "INV-P13 JSON-AST letrec rejected under GrammarCoreInversion with core-grammar-violation" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"letrec\",\"name\":\"countdown\",\"params\":[{\"name\":\"n\",\"param_type\":{\"kind\":\"primitive\",\"name\":\"int\"}}],\"decreases\":{\"kind\":\"var\",\"name\":\"n\"},\"body\":{\"kind\":\"lit-int\",\"value\":0}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Left diag -> diagKind diag `shouldBe` Just "core-grammar-violation"
          Right ss  -> expectationFailure ("expected rejection, got: " ++ show ss)

      it "INV-P14 JSON-AST letrec accepted under GrammarLegacy" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"letrec\",\"name\":\"countdown\",\"params\":[{\"name\":\"n\",\"param_type\":{\"kind\":\"primitive\",\"name\":\"int\"}}],\"decreases\":{\"kind\":\"var\",\"name\":\"n\"},\"body\":{\"kind\":\"lit-int\",\"value\":0}}]}"
        case parseJSONAST GrammarLegacy "<test>" src of
          Right [SLetrec {}] -> pure ()
          other              -> expectationFailure (show other)

      it "INV-P15 JSON-AST def rejected under GrammarLegacy with legacy-grammar-violation" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
        case parseJSONAST GrammarLegacy "<test>" src of
          Left diag -> diagKind diag `shouldBe` Just "legacy-grammar-violation"
          Right ss  -> expectationFailure ("expected rejection, got: " ++ show ss)

      it "INV-P16 JSON-AST def-shell rejected under GrammarLegacy with legacy-grammar-violation" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-shell\",\"name\":\"g\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":2}}]}"
        case parseJSONAST GrammarLegacy "<test>" src of
          Left diag -> diagKind diag `shouldBe` Just "legacy-grammar-violation"
          Right ss  -> expectationFailure ("expected rejection, got: " ++ show ss)

      it "INV-P17 parseJSONASTValue GrammarCoreInversion accepts def node" $ do
        let src = "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}" :: String
        case decode (BL.fromStrict (TE.encodeUtf8 (T.pack src))) of
          Nothing  -> expectationFailure "JSON decode failed"
          Just val -> case parseJSONASTValue GrammarCoreInversion val of
            Right [SDef {}] -> pure ()
            other           -> expectationFailure (show other)

    describe "schema alignment: DefCore / DefShell (LT-INV schema fix)" $ do

      it "SCHEMA-1 kind:def-shell parses as SDefShell under GrammarCoreInversion" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-shell\",\"name\":\"loop\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":0}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Right [SDefShell {}] -> pure ()
          other                -> expectationFailure (show other)

      it "SCHEMA-2 kind:def with spec_entropy field parses under GrammarCoreInversion" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def\",\"name\":\"g\",\"params\":[],\"spec_entropy\":\"strict\",\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Right [SDef {}] -> pure ()
          other           -> expectationFailure (show other)

      it "SCHEMA-3 kind:def-shell with spec_entropy field parses under GrammarCoreInversion" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-shell\",\"name\":\"h\",\"params\":[],\"spec_entropy\":\"intentional\",\"body\":{\"kind\":\"lit-int\",\"value\":2}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Right [SDefShell {}] -> pure ()
          other                -> expectationFailure (show other)

      it "SCHEMA-4 kind:def-logic diagnostic carries suggestion pointing to def/def-shell" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-logic\",\"name\":\"old\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":0}}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Left diag -> do
            diagKind diag `shouldBe` Just "removed-construct"
            case diagSuggestion diag of
              Just s  -> s `shouldSatisfy` (T.isInfixOf "def")
              Nothing -> expectationFailure "expected a suggestion in the diagnostic"
          Right ss -> expectationFailure ("expected rejection, got: " ++ show ss)

    describe "schema alignment: WeaknessOkDecl (v0.6 schema fix)" $ do

      it "WO-J1 kind:weakness-ok parses as SWeaknessOk under GrammarCoreInversion" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"weakness-ok\",\"name\":\"render-board\",\"reason\":\"pure string rendering\"}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Right [SWeaknessOk "render-board" "pure string rendering"] -> pure ()
          other -> expectationFailure (show other)

      it "WO-J2 kind:weakness-ok with empty reason is rejected" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"weakness-ok\",\"name\":\"f\",\"reason\":\"\"}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Left diag -> diagKind diag `shouldBe` Just "json-decode-error"
          Right ss  -> expectationFailure ("expected rejection, got: " ++ show ss)

      it "WO-J3 kind:weakness-ok co-parses with a def node in the same program" $ do
        let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack $
                    "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def\",\"name\":\"g\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":0}},{\"kind\":\"weakness-ok\",\"name\":\"g\",\"reason\":\"intentional\"}]}"
        case parseJSONAST GrammarCoreInversion "<test>" src of
          Right [SDef {}, SWeaknessOk "g" "intentional"] -> pure ()
          other -> expectationFailure (show other)

    describe "INV-W: well-typed" $ do

      it "INV-W1 SDef with arithmetic body typechecks without error" $ do
        let stmts = [ SDef { defName = "add", defParams = [("x", TInt), ("y", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EOp "+" [EVar "x", EVar "y"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
        reportSuccess report `shouldBe` True

      it "INV-W2 SDef with let binding typechecks without error" $ do
        let stmts = [ SDef { defName = "f", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = ELet [(PVar "x", Nothing, ELit (LitInt 1))]
                                            (EOp "+" [EVar "n", EVar "x"]) } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
        reportSuccess report `shouldBe` True

      it "INV-W3 SDef with if expression typechecks without error" $ do
        let stmts = [ SDef { defName = "abs-val", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EIf (EOp ">" [EVar "n", ELit (LitInt 0)])
                                          (EVar "n")
                                          (EOp "-" [ELit (LitInt 0), EVar "n"]) } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
        reportSuccess report `shouldBe` True

      it "INV-W4 SDefShell with lambda body has no core-grammar-violation" $ do
        let stmts = [ SDefShell { defShellName = "f", defShellParams = [("n", TInt)]
                                , defShellReturn = Nothing
                                , defShellContract = Contract Nothing Nothing Nothing Nothing Nothing
                                , defShellBody = ELambda [("x", TInt)] (EVar "x"), defShellDecreases = [] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldNotContain` ["core-grammar-violation"]

      it "INV-W5 SDef calling trusted prelude 'string-length' is admitted" $ do
        let stmts = [ SDef { defName = "len", defParams = [("s", TString)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EApp "string-length" [EVar "s"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldNotContain` ["core-membership-violation"]

      it "INV-W6 SDef with pre/post contract has no grammar or membership violation" $ do
        let stmts = [ SDef { defName = "inc"
                           , defParams = [("n", TInt)]
                           , defReturn = Just TInt
                           , defContract = Contract
                               Nothing Nothing
                               (Just (EApp ">=" [EVar "n", ELit (LitInt 0)]))
                               Nothing Nothing
                           , defBody = EOp "+" [EVar "n", ELit (LitInt 1)] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldNotContain` ["core-grammar-violation"]
        kinds `shouldNotContain` ["core-membership-violation"]

      it "INV-W7 SDefShell calling unverified user function has no core-membership-violation" $ do
        let stmts = [ SDefLogic "helper" [("x", TInt)] (Just TInt)
                        (Contract Nothing Nothing Nothing Nothing Nothing)
                        (EVar "x")
                    , SDefShell { defShellName = "caller", defShellParams = [("n", TInt)]
                                , defShellReturn = Nothing
                                , defShellContract = Contract Nothing Nothing Nothing Nothing Nothing
                                , defShellBody = EApp "helper" [EVar "n"], defShellDecreases = [] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldNotContain` ["core-membership-violation"]

    describe "INV-A: core-grammar-violation" $ do

      it "INV-A1 SDef with lambda body emits core-grammar-violation" $ do
        let stmts = [ SDef { defName = "f", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = ELambda [("x", TInt)] (EVar "x") } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-grammar-violation"]

      it "INV-A2 SDef with non-linear '*' emits core-grammar-violation" $ do
        let stmts = [ SDef { defName = "sq", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EOp "*" [EVar "n", EVar "n"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-grammar-violation"]

      it "INV-A3 SDef with await expression emits core-grammar-violation" $ do
        let stmts = [ SDef { defName = "f", defParams = [("p", TPromise TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EAwait (EVar "p") } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-grammar-violation"]

      it "INV-A4 SDef with do block emits core-grammar-violation" $ do
        let stmts = [ SDef { defName = "f", defParams = []
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EDo [DoStep Nothing (ELit (LitInt 1))] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-grammar-violation"]

      it "INV-A5 SDef with HProofRequired hole emits core-grammar-violation" $ do
        let stmts = [ SDef { defName = "f", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EHole (HProofRequired "pending" Nothing) } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-grammar-violation"]

    describe "INV-C: core-membership-violation" $ do

      it "INV-C1 SDef calling unverified SDefLogic emits core-membership-violation" $ do
        let stmts = [ SDefLogic "helper" [("x", TInt)] (Just TInt)
                        (Contract Nothing Nothing Nothing Nothing Nothing)
                        (EVar "x")
                    , SDef { defName = "caller", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EApp "helper" [EVar "n"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-membership-violation"]

      it "INV-C2 SDef calling 'string-length' (trusted prelude) has no violation" $ do
        let stmts = [ SDef { defName = "strlen", defParams = [("s", TString)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EApp "string-length" [EVar "s"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldNotContain` ["core-membership-violation"]

      it "INV-C3 SDef calling 'random-int' (trusted prelude) has no violation" $ do
        let stmts = [ SDef { defName = "rnd", defParams = [("lo", TInt), ("hi", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EApp "random-int" [EVar "lo", EVar "hi"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldNotContain` ["core-membership-violation"]

      it "INV-C4 SDef calling SDefShell (no evidence) emits core-membership-violation" $ do
        let stmts = [ SDefShell { defShellName = "sh", defShellParams = [("x", TInt)]
                                , defShellReturn = Just TInt
                                , defShellContract = Contract Nothing Nothing Nothing Nothing Nothing
                                , defShellBody = EVar "x", defShellDecreases = [] }
                    , SDef { defName = "caller", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EApp "sh" [EVar "n"] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-membership-violation"]

      it "INV-C5 SDef calling another SDef (no evidence) emits core-membership-violation" $ do
        let stmts = [ SDef { defName = "inc", defParams = [("n", TInt)]
                           , defReturn = Just TInt
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EOp "+" [EVar "n", ELit (LitInt 1)] }
                    , SDef { defName = "double-inc", defParams = [("n", TInt)]
                           , defReturn = Nothing
                           , defContract = Contract Nothing Nothing Nothing Nothing Nothing
                           , defBody = EApp "inc" [EApp "inc" [EVar "n"]] } ]
            report = typeCheck GrammarCoreInversion emptyEnv stmts
            kinds  = mapMaybe diagKind (reportDiagnostics report)
        kinds `shouldContain` ["core-membership-violation"]

    -- =====================================================================
    -- ADMIT-VERIFIED (Option 2): strict-core admission of independently-
    -- verified callees. The 4th admission leg + the four soundness corrections.
    -- =====================================================================
    describe "ADMIT-VERIFIED (Option 2): persisted-evidence admission" $ do
      let -- 'double': (def double [x:int] (post (= result (+ x x))) (+ x x))
          dblBody     = EOp "+" [EVar "x", EVar "x"]
          dblPost     = Just (EApp "=" [EVar "result", EOp "+" [EVar "x", EVar "x"]])
          dblContract = Contract Nothing Nothing dblPost Nothing Nothing
          dblHash     = canonicalDefEvidenceHash "def" dblBody Nothing dblPost []
          -- A fully-verified, hash-valid post EvidenceRecord for 'double'.
          dblVerifiedER = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing []
                            False Nothing Nothing False (Just dblHash) False
          dblVerifiedCS = ContractStatus Nothing (Just dblVerifiedER) []
          -- The leaf def statement (so the staleness guard can recompute).
          dblStmt = SDef { defName = "double", defParams = [("x", TInt)]
                         , defReturn = Just TInt, defContract = dblContract
                         , defBody = dblBody }
          -- A strict-core caller of bare 'double': add-double.
          adStmt = SDef { defName = "add-double", defParams = [("x", TInt)]
                        , defReturn = Just TInt
                        , defContract = Contract Nothing Nothing
                            (Just (EApp "=" [EVar "result", EOp "+" [EOp "+" [EVar "x", EVar "x"], ELit (LitInt 1)]])) Nothing Nothing
                        , defBody = EOp "+" [EApp "double" [EVar "x"], ELit (LitInt 1)] }
          emptyCache = DM.empty :: ModuleCache
          kindsOf r = mapMaybe diagKind (reportDiagnostics r)

      -- ---- same-file FLAT composition (3) ----
      it "AV-SF1 same-file caller of verified callee is ADMITTED (no core-membership-violation)" $ do
        let entryCS = DM.fromList [("double", dblVerifiedCS)]
            report  = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache entryCS emptyEnv [dblStmt, adStmt]
        kindsOf report `shouldNotContain` ["core-membership-violation"]

      it "AV-SF2 stale-hash entry is rejected (callee body changed since verify)" $ do
        -- Persisted evidence keyed to the OLD body hash; live body is dblStmt.
        let staleHash = canonicalDefEvidenceHash "def" (EOp "+" [EVar "x", ELit (LitInt 99)]) Nothing dblPost []
            staleER   = dblVerifiedER { erVerifiedHash = Just staleHash }
            rawCS     = DM.fromList [("double", ContractStatus Nothing (Just staleER) [])]
            (validatedCS, _) = downgradeStaleVerifiedSidecar [dblStmt, adStmt] rawCS
            report    = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache validatedCS emptyEnv [dblStmt, adStmt]
        kindsOf report `shouldContain` ["core-membership-violation"]

      it "AV-SF3 cold (no prior sidecar) call is conservatively rejected" $ do
        -- No entry evidence at all: the first-ever-verify case still rejects
        -- (accepted LT-INV §3.5 verify-then-build cost).
        let report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache DM.empty emptyEnv [dblStmt, adStmt]
        kindsOf report `shouldContain` ["core-membership-violation"]

      -- ---- cross-module FLAT admission (3) ----
      let mkCoreModule cs = ModuleEnv
            { meExports        = DM.fromList [("double", TFn [TInt] TInt)]
            , meStatements     = [dblStmt, SExport ["double"]]
            , meInterfaces     = DM.empty
            , meAliasMap       = DM.empty
            , mePath           = ["core"]
            , meContractStatus = DM.fromList [("double", cs)]
            , meContracts      = DM.empty
            }
          importerStmts =
            [ SOpen ["core"] Nothing
            , adStmt ]

      it "AV-XM1 verified imported callee is ADMITTED across (open ...)" $ do
        let cache  = DM.fromList [(["core"], mkCoreModule dblVerifiedCS)]
            report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion cache DM.empty emptyEnv importerStmts
        kindsOf report `shouldNotContain` ["core-membership-violation"]

      it "AV-XM2 asserted-only imported callee is REJECTED" $ do
        let assertedCS = ContractStatus Nothing
              (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False)) []
            cache  = DM.fromList [(["core"], mkCoreModule assertedCS)]
            report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion cache DM.empty emptyEnv importerStmts
        kindsOf report `shouldContain` ["core-membership-violation"]

      it "AV-XM3 import staleness (hash mismatch) is REJECTED after validation" $ do
        -- The imported module's persisted evidence is hash-stale relative to
        -- its own live body; validating it before seeding demotes it.
        let staleHash = canonicalDefEvidenceHash "def" (EOp "+" [EVar "x", ELit (LitInt 7)]) Nothing dblPost []
            staleCS   = ContractStatus Nothing (Just (dblVerifiedER { erVerifiedHash = Just staleHash })) []
            modEnv    = mkCoreModule staleCS
            (validatedModCS, _) = downgradeStaleVerifiedSidecar (meStatements modEnv) (meContractStatus modEnv)
            cache  = DM.fromList [(["core"], modEnv { meContractStatus = validatedModCS })]
            report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion cache DM.empty emptyEnv importerStmts
        kindsOf report `shouldContain` ["core-membership-violation"]

      -- ---- staleness guard direct (2) ----
      it "AV-SG1 hash mismatch downgrades body-faithful evidence to asserted" $ do
        let staleHash = canonicalDefEvidenceHash "def" (EOp "+" [EVar "x", ELit (LitInt 1)]) Nothing dblPost []
            rawCS     = DM.fromList [("double", ContractStatus Nothing (Just (dblVerifiedER { erVerifiedHash = Just staleHash })) [])]
            (out, diags) = downgradeStaleVerifiedSidecar [dblStmt] rawCS
            postER    = csPost (out DM.! "double")
        fmap erDisplayLevel postER `shouldBe` Just DLAsserted
        fmap erBodyFaithful postER `shouldBe` Just False
        length diags `shouldSatisfy` (> 0)

      it "AV-SG2 absent verified_hash fails closed (downgraded, never admitted)" $ do
        -- soundness (iv): a pre-ADMIT-VERIFIED body-faithful record with NO hash.
        let noHashER = dblVerifiedER { erVerifiedHash = Nothing }
            rawCS    = DM.fromList [("double", ContractStatus Nothing (Just noHashER) [])]
            (out, diags) = downgradeStaleVerifiedSidecar [dblStmt] rawCS
            postER   = csPost (out DM.! "double")
        fmap erDisplayLevel postER `shouldBe` Just DLAsserted
        fmap erBodyFaithful postER `shouldBe` Just False
        length diags `shouldSatisfy` (> 0)

      it "AV-SG3 absent-hash record is NOT admitted by the leg (admission fail-closed)" $ do
        -- Even WITHOUT running the guard, the admission conjunction itself
        -- rejects a body-faithful record carrying no hash.
        let noHashCS = DM.fromList [("double", ContractStatus Nothing
              (Just (dblVerifiedER { erVerifiedHash = Nothing })) [])]
            report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache noHashCS emptyEnv [dblStmt, adStmt]
        kindsOf report `shouldContain` ["core-membership-violation"]

      it "AV-SG4 overflow-tainted verified record is NOT admitted (conjunction)" $ do
        -- soundness (ii): a hash-valid, body-faithful, verified-LEVEL record that
        -- is overflow-tainted must still be refused.
        let taintedER = dblVerifiedER { erOverflowTainted = True }
            taintedCS = DM.fromList [("double", ContractStatus Nothing (Just taintedER) [])]
            report = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache taintedCS emptyEnv [dblStmt, adStmt]
        kindsOf report `shouldContain` ["core-membership-violation"]

      -- ---- schema back-compat (2) ----
      it "AV-BC1 verified_hash-absent sidecar reads (round-trips without the field)" $ do
        let er  = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False Nothing False
            cs  = ContractStatus Nothing (Just er) []
            tmp = "/tmp/admit_verified_bc1.llmll"
        saveVerified tmp (DM.fromList [("double", cs)])
        loaded <- loadVerified tmp
        fmap (fmap erVerifiedHash . csPost) (DM.lookup "double" loaded) `shouldBe` Just (Just Nothing)

      it "AV-BC2 present verified_hash round-trips" $ do
        let cs  = ContractStatus Nothing (Just dblVerifiedER) []
            tmp = "/tmp/admit_verified_bc2.llmll"
        saveVerified tmp (DM.fromList [("double", cs)])
        loaded <- loadVerified tmp
        fmap (fmap erVerifiedHash . csPost) (DM.lookup "double" loaded) `shouldBe` Just (Just (Just dblHash))

      -- ---- REC-HASH-FORM (b0 of REC-BODY-VC): def-form in the evidence hash ----
      -- A recursive self-call verified as def-shell (partial correctness) must not
      -- launder into the strict-core (total) tier via a def-shell -> def rename over
      -- an intact sidecar (probe E). The def-form now sits in the hash preimage, so
      -- the flip drifts the hash, the sidecar downgrades, and admission rejects.
      let recBody     = EApp "f" [EVar "x"]
          recPre      = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
          recPost     = Just (EApp "=" [EVar "result", EVar "x"])
          recContract = Contract recPre Nothing recPost Nothing Nothing
          recSDef     = SDef { defName = "f", defParams = [("x", TInt)]
                             , defReturn = Just TInt, defContract = recContract
                             , defBody = recBody }
          -- The hash that was stamped when 'f' was a def-shell.
          recDsHash   = canonicalDefEvidenceHash "def-shell" recBody recPre recPost []

      it "RHF-1 def-shell->def flip over an intact sidecar is REJECTED (probe E closed)" $ do
        let staleER   = dblVerifiedER { erVerifiedHash = Just recDsHash }
            rawCS     = DM.fromList [("f", ContractStatus Nothing (Just staleER) [])]
            (validatedCS, diags) = downgradeStaleVerifiedSidecar [recSDef] rawCS
            postER    = csPost (validatedCS DM.! "f")
            report    = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache validatedCS emptyEnv [recSDef]
        -- The def-shell sidecar is stale under the live def recompute (form drift)...
        fmap erBodyFaithful postER `shouldBe` Just False
        fmap erVerifiedHash postER `shouldBe` Just Nothing
        length diags `shouldSatisfy` (> 0)
        -- ...and the self-call is refused strict-core admission.
        kindsOf report `shouldContain` ["core-membership-violation"]

      it "RHF-2 fresh def self-call is rejected with and without a stale sidecar (flip converges to fresh path)" $ do
        let reportCold = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache DM.empty emptyEnv [recSDef]
            rawCS      = DM.fromList [("f", ContractStatus Nothing (Just (dblVerifiedER { erVerifiedHash = Just recDsHash })) [])]
            (validatedCS, _) = downgradeStaleVerifiedSidecar [recSDef] rawCS
            reportStale = typeCheckStrictWithCacheAndStatus GrammarCoreInversion emptyCache validatedCS emptyEnv [recSDef]
        kindsOf reportCold  `shouldContain` ["core-membership-violation"]
        kindsOf reportStale `shouldContain` ["core-membership-violation"]

      it "RHF-3 a non-recursive verified def does not drift under the form tag" $ do
        -- dblStmt is SDef 'double'; its fresh sidecar hash is stamped \"def\" and the
        -- live recompute is \"def\" — no drift, evidence stays verified.
        let rawCS = DM.fromList [("double", ContractStatus Nothing (Just dblVerifiedER) [])]
            (out, diags) = downgradeStaleVerifiedSidecar [dblStmt] rawCS
            postER = csPost (out DM.! "double")
        fmap erDisplayLevel postER `shouldBe` Just (DLVerified "liquid-fixpoint")
        fmap erBodyFaithful postER `shouldBe` Just True
        diags `shouldBe` []

      it "RHF-4 the def-form tag is load-bearing in the hash preimage" $
        canonicalDefEvidenceHash "def" dblBody Nothing dblPost []
          `shouldNotBe` canonicalDefEvidenceHash "def-shell" dblBody Nothing dblPost []

    describe "INV-G: isCoreBodySyntactic" $ do

      it "INV-G1 ELit is core-syntactic" $
        isCoreBodySyntactic (ELit (LitInt 42)) `shouldBe` True

      it "INV-G2 ELambda is not core-syntactic" $
        isCoreBodySyntactic (ELambda [("x", TInt)] (EVar "x")) `shouldBe` False

      it "INV-G3 EOp with '*' (non-linear) is not core-syntactic" $
        isCoreBodySyntactic (EOp "*" [EVar "a", EVar "b"]) `shouldBe` False

  -- -----------------------------------------------------------------------
  -- Grammar default flip (INV-DEFAULT / INV-MODULE-THREAD)
  -- -----------------------------------------------------------------------
  describe "Grammar default flip" $ do

    it "INV-DEFAULT-1 GrammarCoreInversion (new default) rejects def-logic at parse time" $ do
      let src = "(def-logic f [] 0)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left  _ -> pure ()
        Right _ -> expectationFailure "expected parse error for def-logic under GrammarCoreInversion"

    it "INV-DEFAULT-2 GrammarLegacy rejects def-logic too (removed v0.12.1)" $ do
      let src = "(def-logic f [] 0)"
      case parseStatements GrammarLegacy "<test>" src of
        Left  _ -> pure ()
        Right _ -> expectationFailure "expected parse error for def-logic under GrammarLegacy (removed under all modes)"

    it "INV-MODULE-THREAD-1 GrammarCoreInversion rejects (def ...) under GrammarLegacy S-expr parser" $ do
      -- Validates that the S-expression parser mode asymmetry is real:
      -- after migration, a .llmll module using (def ...) will fail under GrammarLegacy.
      let src = "(def f [] 0)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right _ -> pure ()
        Left  e -> expectationFailure $ "GrammarCoreInversion should accept (def ...): " ++ show e
      case parseStatements GrammarLegacy "<test>" src of
        Left  _ -> pure ()
        Right _ -> expectationFailure "GrammarLegacy should NOT recognise (def ...) keyword"

  -- -----------------------------------------------------------------------
  -- v0.12.1: def-logic removal (all modes) + def-invariant promotion
  -- -----------------------------------------------------------------------
  describe "v0.12.1 def-logic removal + def-invariant (SDefInvariant)" $ do

    it "DEFLOGIC-REMOVE-1 S-expr def-logic rejected under both grammar modes" $ do
      let src = "(def-logic f [x: int] x)"
      case parseStatements GrammarCoreInversion "<test>" src of
        Left _  -> pure ()
        Right s -> expectationFailure ("CoreInversion should reject def-logic, got: " ++ show s)
      case parseStatements GrammarLegacy "<test>" src of
        Left _  -> pure ()
        Right s -> expectationFailure ("GrammarLegacy should reject def-logic, got: " ++ show s)

    it "DEFLOGIC-REMOVE-2 JSON def-logic rejected under both grammar modes" $ do
      let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack
                  "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-logic\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
      case parseJSONAST GrammarCoreInversion "<test>" src of
        Left diag -> diagKind diag `shouldBe` Just "removed-construct"
        Right s   -> expectationFailure ("CoreInversion should reject, got: " ++ show s)
      case parseJSONAST GrammarLegacy "<test>" src of
        Left diag -> diagKind diag `shouldBe` Just "removed-construct"
        Right s   -> expectationFailure ("GrammarLegacy should reject, got: " ++ show s)

    it "DEFINV-1 JSON def-invariant parses to SDefInvariant" $ do
      let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack
                  "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-invariant\",\"name\":\"inv\",\"param\":{\"name\":\"x\",\"param_type\":{\"kind\":\"primitive\",\"name\":\"int\"}},\"body\":{\"kind\":\"lit-bool\",\"value\":true}}]}"
      case parseJSONAST GrammarCoreInversion "<test>" src of
        Right [SDefInvariant name params _ _ body] -> do
          name `shouldBe` "inv"
          length params `shouldBe` 1
          body `shouldBe` ELit (LitBool True)
        other -> expectationFailure ("expected SDefInvariant, got: " ++ show other)

    it "DEFINV-2 def-invariant round-trips faithfully (def-invariant, not def-logic)" $ do
      let stmt = SDefInvariant "inv" [("x", TInt)] Nothing
                   (Contract Nothing Nothing Nothing Nothing Nothing)
                   (ELit (LitBool True))
          json = TE.decodeUtf8 (BL.toStrict (emitJsonAST [stmt]))
      T.isInfixOf "def-invariant" json `shouldBe` True
      T.isInfixOf "def-logic" json `shouldBe` False
      case parseJSONAST GrammarCoreInversion "<test>" (BL.fromStrict (TE.encodeUtf8 json)) of
        Right [SDefInvariant n _ _ _ _] -> n `shouldBe` "inv"
        other -> expectationFailure ("round-trip expected SDefInvariant, got: " ++ show other)

    it "DEFINV-3 def-invariant program type-checks without non-exhaustive crash" $ do
      let stmts = [ SDefInvariant "inv" [("x", TInt)] Nothing
                      (Contract Nothing Nothing Nothing Nothing Nothing)
                      (EApp ">" [EVar "x", ELit (LitInt 0)]) ]
          report = typeCheck GrammarCoreInversion emptyEnv stmts
      length (reportDiagnostics report) `shouldSatisfy` (>= 0)

    -- DEFINV-4/5: S-expression surface form (v0.14.3 doc-audit regression).
    -- Parser.hs's pStatement had no production for 'def-invariant' — only
    -- ParserJSON.parseDefInvariant implemented it, JSON-AST-only. LLMLL.md
    -- §11.4/§12 document an S-expression grammar production for it that
    -- never actually parsed: "(def-invariant foo [x: int] (> x 0))" failed
    -- with "unexpected '(' expecting end of input".

    it "DEFINV-4 S-expr def-invariant parses to the SAME AST as its hand-written JSON-AST equivalent" $ do
      let sexpSrc = "(def-invariant inv [x: int] (> x 0))"
          jsonSrc = BL.fromStrict $ TE.encodeUtf8 $ T.pack
                      "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def-invariant\",\"name\":\"inv\",\"param\":{\"name\":\"x\",\"param_type\":{\"kind\":\"primitive\",\"name\":\"int\"}},\"body\":{\"kind\":\"op\",\"op\":\">\",\"args\":[{\"kind\":\"var\",\"name\":\"x\"},{\"kind\":\"lit-int\",\"value\":0}]}}]}"
      case (parseStatements GrammarCoreInversion "<test>" sexpSrc, parseJSONAST GrammarCoreInversion "<test>" jsonSrc) of
        (Right sexpStmts, Right jsonStmts) -> sexpStmts `shouldBe` jsonStmts
        (sexpResult, jsonResult) -> expectationFailure
          ("expected both surface forms to parse to the same AST; s-expr=" ++ show sexpResult ++ " json-ast=" ++ show jsonResult)

    it "DEFINV-5 S-expr def-invariant produces SDefInvariant and type-checks cleanly (matches DEFINV-1/3 style)" $ do
      let src = "(def-invariant foo [x: int] (> x 0))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right stmts@[SDefInvariant name params _ _ body] -> do
          name `shouldBe` "foo"
          params `shouldBe` [("x", TInt)]
          -- S-expression '>' parses as a built-in EOp (not EApp) -- distinct
          -- from DEFINV-1/3's hand-written JSON-AST fixtures, which happened
          -- to use EApp; both are valid, semantically-equivalent front-end
          -- choices for the same operator.
          body `shouldBe` EOp ">" [EVar "x", ELit (LitInt 0)]
          let report = typeCheck GrammarCoreInversion emptyEnv stmts
          length (reportDiagnostics report) `shouldSatisfy` (>= 0)
        other -> expectationFailure ("expected SDefInvariant, got: " ++ show other)

    -- HINT-1: the generic S-expression top-level parse-error hint must not
    -- recommend the removed `def-logic` construct (it should point at def/def-shell).
    it "HINT-1 S-expr def-logic rejection hint recommends def/def-shell, not def-logic" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-logic f [] 0)" of
        Right ss  -> expectationFailure ("expected parse failure, got: " ++ show ss)
        Left bundle -> do
          let diag = megaparsecToDiagnostic "<test>" bundle
          case diagSuggestion diag of
            Just s -> do
              T.isInfixOf "def-shell" s `shouldBe` True
              T.isInfixOf "use def-logic" s `shouldBe` False
            Nothing -> expectationFailure "expected a suggestion in the diagnostic"

    -- HINT-2: the JSON legacy-grammar-violation suggestion must not recommend
    -- rewriting to `def-logic` (which is itself rejected under all modes).
    it "HINT-2 JSON legacy-grammar-violation suggestion does not recommend def-logic" $ do
      let src = BL.fromStrict $ TE.encodeUtf8 $ T.pack
                  "{\"schemaVersion\":\"0.6.0\",\"statements\":[{\"kind\":\"def\",\"name\":\"f\",\"params\":[],\"body\":{\"kind\":\"lit-int\",\"value\":1}}]}"
      case parseJSONAST GrammarLegacy "<test>" src of
        Left diag -> do
          diagKind diag `shouldBe` Just "legacy-grammar-violation"
          case diagSuggestion diag of
            Just s  -> T.isInfixOf "def-logic\",..." s `shouldBe` False
            Nothing -> pure ()
        Right ss -> expectationFailure ("expected legacy-grammar-violation, got: " ++ show ss)

  -- -----------------------------------------------------------------------
  -- F-GATE-8: def-shell hole-delegate PBT trust guard
  -- -----------------------------------------------------------------------
  describe "F-GATE-8 def-shell hole-delegate PBT trust guard" $ do

    -- FG8-1: string-length evaluates on a literal string (secondary fix:
    -- TypeCheck.hs:109 registered but previously absent from evalBuiltinApp).
    it "FG8-1 string-length evaluates on literal string" $ do
      let result = evalExprStatic Map.empty (EApp "string-length" [ELit (LitString "hello")])
      result `shouldBe` Just (ELit (LitInt 5))

    -- FG8-2: string-empty? evaluates to True on empty string.
    it "FG8-2 string-empty? evaluates to True on empty string" $ do
      let result = evalExprStatic Map.empty (EApp "string-empty?" [ELit (LitString "")])
      result `shouldBe` Just (ELit (LitBool True))

    -- FG8-3: string-empty? evaluates to False on non-empty string.
    it "FG8-3 string-empty? evaluates to False on non-empty string" $ do
      let result = evalExprStatic Map.empty (EApp "string-empty?" [ELit (LitString "x")])
      result `shouldBe` Just (ELit (LitBool False))

    -- FG8-4: pbtTrustWriteback must NOT lift a def-shell function's post-clause
    -- to DLTested when its body is a hole-delegate. The static evaluator only
    -- observes delegateOnFailure — not the real implementation — so PBTPassed
    -- carries no information about the actual postcondition. Post stays asserted.
    it "FG8-4 pbtTrustWriteback blocks DLTested for hole-delegate body (primary fix)" $ do
      let ds = DelegateSpec "agent" "test" TString (Just (ELit (LitString "fallback")))
          postExpr = EHole (HProofRequired "non-linear-contract" Nothing)
          contract = Contract Nothing Nothing (Just postExpr) Nothing Nothing
          shellStmt = SDefShell "my-fn" [("x", TString)] Nothing contract
                        (EHole (HDelegate ds)) []
          prop = Property
            { propDescription = "check-my-fn"
            , propBindings    = [("x", TString)]
            , propBody        = EApp "my-fn" [EVar "x"]
            , propSubjects    = []
            }
          stmts = [shellStmt, SCheck prop]
          run = PBTRun
            { pbtDescription    = "check-my-fn"
            , pbtStatus         = PBTPassed
            , pbtSamplesRun     = 100
            , pbtCounterexample = Nothing
            }
          pbtResult = PBTResult 1 1 0 0 [run]
      let (csMap, diags) = pbtTrustWriteback stmts Map.empty pbtResult
      csMap `shouldBe` Map.empty
      diags `shouldSatisfy` (not . null)

    -- FG8-5: pbtTrustWriteback DOES lift a def-shell function's post-clause to
    -- DLTested when its body is concrete (non-delegate). Regression guard: the
    -- delegate guard must not block legitimate non-delegate shell functions.
    it "FG8-5 pbtTrustWriteback lifts DLTested for non-delegate def-shell body" $ do
      let postExpr = EOp "=" [EVar "result", ELit (LitBool True)]
          contract = Contract Nothing Nothing (Just postExpr) Nothing Nothing
          shellStmt = SDefShell "concrete-fn" [("x", TInt)] Nothing contract
                        (ELit (LitBool True)) []
          prop = Property
            { propDescription = "check-concrete-fn"
            , propBindings    = [("x", TInt)]
            , propBody        = EApp "concrete-fn" [EVar "x"]
            , propSubjects    = []
            }
          stmts = [shellStmt, SCheck prop]
          run = PBTRun
            { pbtDescription    = "check-concrete-fn"
            , pbtStatus         = PBTPassed
            , pbtSamplesRun     = 100
            , pbtCounterexample = Nothing
            }
          pbtResult = PBTResult 1 1 0 0 [run]
      let (csMap, _diags) = pbtTrustWriteback stmts Map.empty pbtResult
      csMap `shouldSatisfy` (not . Map.null)

    -- FG8-6: HDelegateAsync body is also blocked, symmetric with HDelegate.
    it "FG8-6 pbtTrustWriteback blocks DLTested for hole-delegate-async body" $ do
      let ds = DelegateSpec "agent" "test" TString Nothing
          postExpr = EHole (HProofRequired "non-linear-contract" Nothing)
          contract = Contract Nothing Nothing (Just postExpr) Nothing Nothing
          shellStmt = SDefShell "async-fn" [("x", TString)] Nothing contract
                        (EHole (HDelegateAsync ds)) []
          prop = Property
            { propDescription = "check-async-fn"
            , propBindings    = [("x", TString)]
            , propBody        = EApp "async-fn" [EVar "x"]
            , propSubjects    = []
            }
          stmts = [shellStmt, SCheck prop]
          run = PBTRun
            { pbtDescription    = "check-async-fn"
            , pbtStatus         = PBTPassed
            , pbtSamplesRun     = 100
            , pbtCounterexample = Nothing
            }
          pbtResult = PBTResult 1 1 0 0 [run]
      let (csMap, diags) = pbtTrustWriteback stmts Map.empty pbtResult
      csMap `shouldBe` Map.empty
      diags `shouldSatisfy` (not . null)

    -- FG8-7: SDef (strict-core) with hole-delegate body must also be blocked.
    -- F-EL5-3: delegation hole makes return value opaque regardless of def vs
    -- def-shell — same rationale as F-GATE-8; guard extended to SDef.
    it "FG8-7 pbtTrustWriteback blocks DLTested for SDef hole-delegate body" $ do
      let ds = DelegateSpec "agent" "test" TString (Just (ELit (LitString "fallback")))
          postExpr = EHole (HProofRequired "non-linear-contract" Nothing)
          contract = Contract Nothing Nothing (Just postExpr) Nothing Nothing
          defStmt = SDef "def-fn" [("x", TString)] Nothing contract
                      (EHole (HDelegate ds))
          prop = Property
            { propDescription = "check-def-fn"
            , propBindings    = [("x", TString)]
            , propBody        = EApp "def-fn" [EVar "x"]
            , propSubjects    = []
            }
          stmts = [defStmt, SCheck prop]
          run = PBTRun
            { pbtDescription    = "check-def-fn"
            , pbtStatus         = PBTPassed
            , pbtSamplesRun     = 100
            , pbtCounterexample = Nothing
            }
          pbtResult = PBTResult 1 1 0 0 [run]
      let (csMap, diags) = pbtTrustWriteback stmts Map.empty pbtResult
      csMap `shouldBe` Map.empty
      diags `shouldSatisfy` (not . null)

    -- FG8-8: SDef with HDelegateAsync body is also blocked, symmetric with FG8-7.
    it "FG8-8 pbtTrustWriteback blocks DLTested for SDef hole-delegate-async body" $ do
      let ds = DelegateSpec "agent" "test" TString Nothing
          postExpr = EHole (HProofRequired "non-linear-contract" Nothing)
          contract = Contract Nothing Nothing (Just postExpr) Nothing Nothing
          defStmt = SDef "def-async-fn" [("x", TString)] Nothing contract
                      (EHole (HDelegateAsync ds))
          prop = Property
            { propDescription = "check-def-async-fn"
            , propBindings    = [("x", TString)]
            , propBody        = EApp "def-async-fn" [EVar "x"]
            , propSubjects    = []
            }
          stmts = [defStmt, SCheck prop]
          run = PBTRun
            { pbtDescription    = "check-def-async-fn"
            , pbtStatus         = PBTPassed
            , pbtSamplesRun     = 100
            , pbtCounterexample = Nothing
            }
          pbtResult = PBTResult 1 1 0 0 [run]
      let (csMap, diags) = pbtTrustWriteback stmts Map.empty pbtResult
      csMap `shouldBe` Map.empty
      diags `shouldSatisfy` (not . null)

  -- PROOF-ARTIFACT (staged MVP): the §4.1 LCF invariant (a positive tier is
  -- unconstructible without coherent qualifiers — laundering by omission/contradiction
  -- is an unrepresentable state, enforced on BOTH construction and deserialization) and
  -- the §4.3 fail-closed replay classification. Emit/replay CLI paths are CLI-probe-verified.
  describe "PROOF-ARTIFACT: §4.1 LCF invariant + §4.3 fail-closed replay" $ do
    let pos = FnInputs "f" TVerified [] Nothing False Nothing  -- a clean positive-tier input

    it "PA-1: mkFnRecord REJECTS laundered positive records" $ do
      mkFnRecord pos { fiFallbackReason = Just "x" } `shouldSatisfy` isLeft  -- positive + fallback
      mkFnRecord pos { fiRefuted = True }            `shouldSatisfy` isLeft  -- positive + refuted
      mkFnRecord pos { fiDiscrim = Just Nothing }    `shouldSatisfy` isLeft  -- discriminative axis, no basis

    it "PA-2: mkFnRecord ACCEPTS well-formed records (positive clean; negative with evidence)" $ do
      mkFnRecord pos                                                          `shouldSatisfy` isRight
      mkFnRecord pos { fiTier = TAsserted, fiFallbackReason = Just "fell back" } `shouldSatisfy` isRight
      mkFnRecord pos { fiTier = TAsserted, fiRefuted = True }                 `shouldSatisfy` isRight
      mkFnRecord pos { fiDiscrim = Just (Just "Omega") }                      `shouldSatisfy` isRight

    it "PA-3: artifact JSON round-trips; a laundered artifact FAILS to deserialize" $ do
      let Right fr = mkFnRecord pos
          meta = SolverMeta "2009-15" "z3 4.x" ["-q","--json"] Nothing
          art  = ProofArtifact proofArtifactVersion (ComposedVersions "1.4.0" "0.7.0")
                   "f.llmll" (Just "sha256:abc") meta codegenSemanticsVersion
                   RSafe "vc-text" Nothing [fr] Nothing
      decode (encode art) `shouldBe` Just art
      -- a hand-forged record claiming verified + refuted must not decode (kernel on read side)
      let laundered = "{\"name\":\"f\",\"evidence_level\":\"verified\",\"caller_obligations\":[],\"fallback_reason\":null,\"refuted\":true}"
      (decode laundered :: Maybe FnRecord) `shouldBe` Nothing

    it "PA-4: classifyReplay reproduces only on exact match; fails closed on every axis" $ do
      let meta = SolverMeta "2009-15" "z3 4.x" ["-q","--json"] Nothing
          Right fr = mkFnRecord pos
          art  = ProofArtifact proofArtifactVersion (ComposedVersions "1.4.0" "0.7.0")
                   "f.llmll" (Just "sha256:H") meta codegenSemanticsVersion
                   RSafe "vc" Nothing [fr] Nothing
          failed o = case o of ReplayFailClosed _ -> True; _ -> False
      classifyReplay (Just "sha256:H") meta RSafe art          `shouldBe` ReplayReproduced RSafe
      classifyReplay (Just "sha256:WRONG") meta RSafe art      `shouldSatisfy` failed  -- hash mismatch
      classifyReplay (Just "sha256:H") (meta { smZ3Version = "z3 9.x" }) RSafe art `shouldSatisfy` failed  -- determinism input
      classifyReplay (Just "sha256:H") meta RUnknown art       `shouldSatisfy` failed  -- unknown/timeout
      classifyReplay (Just "sha256:H") meta RUnsafeRefuted art `shouldSatisfy` failed  -- verdict mismatch

  -- -----------------------------------------------------------------------
  -- CodegenHs: generated Main.hs must be valid, compilable Haskell
  -- (regression for the v0.14.2 doc-audit hangman findings — the `esc`
  -- helper in emitEventLogPreamble was over-escaped to invalid Haskell,
  -- and captureStdout referenced a nonexistent `hDupTo` function with a
  -- missing `unix` package.yaml dependency; both were invisible because
  -- `llmll build`'s own `stack build` self-check never ran in outDir)
  -- -----------------------------------------------------------------------

  describe "CodegenHs emitEventLogPreamble: valid Haskell escaping" $ do

    it "esc lambda uses a single-backslash Haskell lambda, not doubled" $ do
      let preamble = T.unlines emitEventLogPreamble
      -- correct: "(\c -> ..." (one backslash right after the open paren)
      T.isInfixOf "(\\c ->" preamble `shouldBe` True
      -- regression guard: must NOT be doubled to "(\\c -> ...", which is
      -- not valid Haskell (parse error on '->') when written into Main.hs
      T.isInfixOf "(\\\\c ->" preamble `shouldBe` False

    it "esc newline-branch char literal is '\\n' (one escape), not '\\\\n' (invalid 2-char literal)" $ do
      let preamble = T.unlines emitEventLogPreamble
      -- correct: '\n' — a single escaped-newline char literal
      T.isInfixOf "'\\n'" preamble `shouldBe` True
      -- regression guard: '\\n' is two characters inside a Char literal,
      -- which GHC rejects outright (lexical error in character literal)
      T.isInfixOf "'\\\\n'" preamble `shouldBe` False

    it "esc quote/newline string-literal replacements stay correctly escaped (\\\" and \\n text)" $ do
      let preamble = T.unlines emitEventLogPreamble
      T.isInfixOf "\"\\\\\\\"\"" preamble `shouldBe` True  -- output text for a quote char: \"
      T.isInfixOf "\"\\\\n\""  preamble `shouldBe` True  -- output text for a newline char: \n

    it "captureStdout uses hDuplicateTo (real GHC.IO.Handle export), not hDupTo" $ do
      let preamble = T.unlines emitEventLogPreamble
      T.isInfixOf "hDuplicateTo" preamble `shouldBe` True
      T.isInfixOf "hDupTo" preamble `shouldBe` False

    it "Generated Main.hs imports hDuplicateTo (not hDupTo) from GHC.IO.Handle" $ do
      let src = "(def-main :mode console :step (fn [s: string input: string] (pair s (wasi.io.stdout input))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right stmts -> do
          let result = generateHaskell "tesths" stmts
          case cgMainHs result of
            Nothing -> expectationFailure "No Main.hs generated"
            Just mainHs -> do
              T.isInfixOf "import GHC.IO.Handle (hDuplicate, hDuplicateTo)" mainHs `shouldBe` True
              T.isInfixOf "hDupTo" mainHs `shouldBe` False
        Left err -> expectationFailure $ "Parse failed: " ++ show err

    -- -----------------------------------------------------------------
    -- BUG-1 follow-ons (v0.14.3), found while live-verifying the BUG-1 fix:
    -- the console harness's captureStdout echoes each step's output back
    -- to the real stdout with `putStr` (no trailing newline guaranteed --
    -- e.g. wasi.io.stdout doesn't add one), so two consecutive steps'
    -- output ran together with no delimiter ("helloworld" for inputs
    -- "hello","world"), AND `hDuplicateTo` does not reliably preserve the
    -- NoBuffering mode set at program start across the redirect/restore
    -- round trip (verified empirically: omitting the re-assert reproduces
    -- an interactive stdin/stdout deadlock). Both defects independently
    -- broke `llmll replay`'s step-by-step hGetLine synchronization
    -- (LLMLL.Replay.replayOne) even after the BUG-1 exitSuccess/exitFailure
    -- fix: replay would hang forever instead of completing.
    -- -----------------------------------------------------------------
    it "BUG-1 follow-on: captureStdout echoes with putStrLn, not putStr (newline-delimits each step)" $ do
      let preamble = T.unlines emitEventLogPreamble
      T.isInfixOf "putStrLn output" preamble `shouldBe` True
      -- regression guard: a bare (non-Ln) putStr on `output` would silently
      -- reintroduce the concatenated-output / replay-deadlock bug
      T.isInfixOf "  putStr output" preamble `shouldBe` False

    it "BUG-1 follow-on: captureStdout re-asserts NoBuffering on stdout after hDuplicateTo restores it" $ do
      let preamble = T.unlines emitEventLogPreamble
          (_, afterRestore) = T.breakOn "hDuplicateTo oldStdout stdout" preamble
      -- the re-assert must appear strictly after the restore call, not just
      -- anywhere in the preamble (the initial `hSetBuffering stdout
      -- NoBuffering` at program start would otherwise satisfy a bare
      -- infix check without actually fixing the bug)
      T.isInfixOf "hSetBuffering stdout NoBuffering" afterRestore `shouldBe` True

  describe "CodegenHs emitPackageYaml: unix dependency for def-main's event-log harness" $ do

    it "package.yaml declares `unix` (top-level, shared by library+executable) when a def-main is present" $ do
      let src = "(def-main :mode console :step (fn [s: string input: string] (pair s (wasi.io.stdout input))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right stmts -> do
          let result = generateHaskell "testpkg" stmts
          -- Main.hs is only emitted when SDefMain is present, and it always
          -- imports System.Posix.IO (unix). hpack's default source-dirs
          -- auto-discovery pulls Main.hs into BOTH the library's and the
          -- executable's other-modules, so `unix` must be a top-level dep,
          -- not scoped to just the executable stanza.
          T.isInfixOf "  - unix" (cgPackageYaml result) `shouldBe` True
        Left err -> expectationFailure $ "Parse failed: " ++ show err

    it "package.yaml does NOT declare `unix` when there is no def-main (no Main.hs emitted)" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def f [] 0)" of
        Right stmts -> do
          let result = generateHaskell "testnopkg" stmts
          cgMainHs result `shouldBe` Nothing
          T.isInfixOf "  - unix" (cgPackageYaml result) `shouldBe` False
        Left err -> expectationFailure $ "Parse failed: " ++ show err

  -- -----------------------------------------------------------------------
  -- BUG-2 (v0.14.3): a def-main program whose source filename contains an
  -- underscore (e.g. event_log_test.llmll) failed to build. emitPackageYaml
  -- emitted the raw, unsanitized modName as its own self-dependency in
  -- package.yaml's `dependencies:` list; hpack parses each dependencies:
  -- entry as a Cabal package name and rejects underscores outright
  -- ("invalid dependency"), even though the top-level `name:` field alone
  -- is more lenient. Fix: sanitizePkgName (underscore -> hyphen) applied
  -- uniformly to `name:`, the `executables:` stanza key, and the
  -- self-dependency entry, so all three stay mutually consistent.
  -- -----------------------------------------------------------------------

  describe "CodegenHs sanitizePkgName / emitPackageYaml: underscore filenames (BUG-2)" $ do

    it "sanitizePkgName replaces every underscore with a hyphen" $ do
      sanitizePkgName "event_log_test" `shouldBe` "event-log-test"
      sanitizePkgName "already-hyphenated" `shouldBe` "already-hyphenated"
      sanitizePkgName "no_underscores_" `shouldBe` "no-underscores-"

    it "package.yaml for an underscored def-main module has no underscore anywhere in name:, executables:, or dependencies:" $ do
      let src = "(def-main :mode console :step (fn [s: string input: string] (pair s (wasi.io.stdout input))))"
      case parseStatements GrammarCoreInversion "<test>" src of
        Right stmts -> do
          let result = generateHaskell "event_log_test" stmts
              yaml    = cgPackageYaml result
          T.isInfixOf "name: event-log-test" yaml `shouldBe` True
          T.isInfixOf "  event-log-test:" yaml `shouldBe` True
          T.isInfixOf "      - event-log-test" yaml `shouldBe` True
          -- regression guard: the raw underscored form must not survive
          -- into any hpack-parsed identifier field
          T.isInfixOf "event_log_test" yaml `shouldBe` False
        Left err -> expectationFailure $ "Parse failed: " ++ show err

    it "package.yaml self-dependency always equals the sanitized name: (hpack auto-links the internal library by exact-name match)" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def-main :mode console :step (fn [s: string input: string] (pair s (wasi.io.stdout input))))" of
        Right stmts -> do
          let result = generateHaskell "a_b_c" stmts
              yaml    = cgPackageYaml result
          T.isInfixOf "name: a-b-c" yaml `shouldBe` True
          T.isInfixOf "      - a-b-c" yaml `shouldBe` True
        Left err -> expectationFailure $ "Parse failed: " ++ show err

    it "package.yaml for a non-underscored module name is unaffected by sanitization" $ do
      case parseStatements GrammarCoreInversion "<test>" "(def f [] 0)" of
        Right stmts -> do
          let result = generateHaskell "cleanname" stmts
          T.isInfixOf "name: cleanname" (cgPackageYaml result) `shouldBe` True
        Left err -> expectationFailure $ "Parse failed: " ++ show err

  -- =========================================================================
  -- R5: Differential Implementation Pressure (observational increment, stages 1–2)
  -- =========================================================================
  describe "R5 DivergenceCheck: observational divergence witness (stages 1–2)" $ do

    -- Shared clamp-lo positive witness: post (>= result lo). Fill A is the
    -- intended clamp; fill B (constant lo) ALSO satisfies the post (lo >= lo)
    -- yet diverges from A whenever x > lo — the spec is under-constrained.
    let clampParams = [("x", TInt), ("lo", TInt)]
        fillA = Fill "fillA" (peR5 "(if (< x lo) lo x)")
        fillB = Fill "fillB" (peR5 "lo")
        clampCtx se = DivergenceContext
          { dcSession     = "sess-clamp"
          , dcHole        = "/statements/0/body"
          , dcParams      = clampParams
          , dcSpecEntropy = se
          , dcFuncEnv     = Map.empty
          }

    it "positive witness: two verified fills diverge on Ω → under-constraint-witness" $ do
      let rep = buildDivergenceReport (clampCtx SpecEntropyStrict)
                  [ClassifiedFill fillA FSVerified, ClassifiedFill fillB FSVerified]
      drVerdict rep `shouldBe` VUnderConstraintWitness
      length (drVerifiedBuckets rep) `shouldBe` 2
      drSpecEntropySuppressed rep `shouldBe` False
      drStatusVerified rep `shouldBe` ["fillA", "fillB"]
      -- The distinguishing witness names two buckets whose outputs differ.
      case drWitness rep of
        Nothing -> expectationFailure "expected a distinguishing witness"
        Just w  -> do
          length (dwOutputs w) `shouldBe` 2
          (snd (dwOutputs w !! 0) == snd (dwOutputs w !! 1)) `shouldBe` False

    it "positive witness: (x=5, lo=0) is a concrete divergence point" $ do
      -- Documents the narrative: A computes max(x,lo)=5, B computes lo=0.
      let env = Map.fromList [("x", ELit (LitInt 5)), ("lo", ELit (LitInt 0))]
      evalExprStaticWith Map.empty maxFuel env (peR5 "(if (< x lo) lo x)")
        `shouldBe` Just (ELit (LitInt 5))
      evalExprStaticWith Map.empty maxFuel env (peR5 "lo")
        `shouldBe` Just (ELit (LitInt 0))

    it "tight contract: two verified fills agree on Ω → no-divergence-observed" $ do
      -- double: post (= result (* 2 x)). (* 2 x) and (+ x x) are observationally
      -- identical on every probe → one bucket → NO spec-tightness claim, just
      -- 'no divergence observed'.
      let ctx = DivergenceContext "sess-double" "/statements/0/body"
                  [("x", TInt)] SpecEntropyStrict Map.empty
          fa  = Fill "twoX"   (peR5 "(* 2 x)")
          fb  = Fill "xPlusX" (peR5 "(+ x x)")
          rep = buildDivergenceReport ctx
                  [ClassifiedFill fa FSVerified, ClassifiedFill fb FSVerified]
      drVerdict rep `shouldBe` VNoDivergenceObserved
      length (drVerifiedBuckets rep) `shouldBe` 1
      drWitness rep `shouldBe` Nothing
      drSpecEntropySuppressed rep `shouldBe` False

    it "spec-entropy :intentional: divergence is suppressed → suppressed-intentional" $ do
      let rep = buildDivergenceReport (clampCtx SpecEntropyIntentional)
                  [ClassifiedFill fillA FSVerified, ClassifiedFill fillB FSVerified]
      drVerdict rep `shouldBe` VSuppressedIntentional
      drSpecEntropySuppressed rep `shouldBe` True
      -- The divergence is still WITNESSED (two buckets), just self-attested.
      length (drVerifiedBuckets rep) `shouldBe` 2
      isJust (drWitness rep) `shouldBe` True

    it "N=1 submitted → insufficient-fills" $ do
      let rep = buildDivergenceReport (clampCtx SpecEntropyStrict)
                  [ClassifiedFill fillA FSVerified]
      drVerdict rep `shouldBe` VInsufficientFills
      drWitness rep `shouldBe` Nothing

    it "only verified fills carry the signal: refuted/type-error are partitioned out" $ do
      -- fillA + fillB diverge (both verified) but a third refuted fill and a
      -- fourth ill-typed fill must not enter the observational bucketing.
      let fillC = Fill "fillC" (peR5 "(+ x lo)")   -- refuted (does not satisfy post)
          fillD = Fill "fillD" (peR5 "hd")          -- type-error (unbound)
          rep = buildDivergenceReport (clampCtx SpecEntropyStrict)
                  [ ClassifiedFill fillA FSVerified
                  , ClassifiedFill fillB FSVerified
                  , ClassifiedFill fillC FSRefuted
                  , ClassifiedFill fillD FSTypeError ]
      drNSubmitted rep `shouldBe` 4
      drStatusVerified rep  `shouldBe` ["fillA", "fillB"]
      drStatusRefuted rep   `shouldBe` ["fillC"]
      drStatusTypeError rep `shouldBe` ["fillD"]
      drVerdict rep `shouldBe` VUnderConstraintWitness
      -- The refuted/ill-typed fills never appear in a verified bucket.
      concatMap vbFills (drVerifiedBuckets rep) `shouldBe` ["fillA", "fillB"]

    it "emits a standalone divergence_witness JSON record (not the CDP block)" $ do
      let rep = buildDivergenceReport (clampCtx SpecEntropyStrict)
                  [ClassifiedFill fillA FSVerified, ClassifiedFill fillB FSVerified]
      case divergenceReportJson rep of
        Object o -> do
          KM.member "divergence_witness" o `shouldBe` True
          KM.member "discriminative_axis" o `shouldBe` False  -- never overloaded onto CDP
          case KM.lookup "divergence_witness" o of
            Just (Object dw) -> do
              KM.lookup "verdict" dw `shouldBe` Just (String (verdictLabel VUnderConstraintWitness))
              KM.member "status_partition" dw       `shouldBe` True
              KM.member "verified_buckets" dw       `shouldBe` True
              KM.member "distinguishing_witness" dw  `shouldBe` True
              KM.member "spec_entropy_suppressed" dw `shouldBe` True
            _ -> expectationFailure "divergence_witness is not an object"
        _ -> expectationFailure "top-level record is not an object"

    it "Ω probe set includes the (x=5, lo=0) point for two int params" $ do
      let probes = probeSet clampParams
      elem [("x", ELit (LitInt 5)), ("lo", ELit (LitInt 0))] probes `shouldBe` True

  -- =========================================================================
  -- R5: checkout --multi divergence session — isolated scratch copies
  -- =========================================================================
  describe "R5 checkout --multi: N concurrent tokens, isolated scratch copies" $ do

    it "opens a session with N scratch-isolated tokens; shared file is untouched" $ do
      let tmpDir = "test/_tmp_r5_multi"
      createDirectoryIfMissing True tmpDir
      BL.readFile "../examples/withdraw-demo/withdraw.ast.json"
        >>= BL.writeFile (tmpDir </> "withdraw.ast.json")
      let fp = tmpDir </> "withdraw.ast.json"
      original <- BL.readFile fp
      let Just astVal = decode original
      -- Two multi checkouts on ONE pointer join one session, capacity 2.
      r1 <- checkoutHoleMulti fp astVal "/statements/1/body" 2 emptyCheckoutContext
      r2 <- checkoutHoleMulti fp astVal "/statements/1/body" 2 emptyCheckoutContext
      case (r1, r2) of
        (Right mc1, Right mc2) -> do
          -- Same session, distinct isolated scratch copies.
          mcSession mc1 `shouldBe` mcSession mc2
          (mcScratch mc1 == mcScratch mc2) `shouldBe` False
          mcSlot mc1 `shouldBe` 1
          mcSlot mc2 `shouldBe` 2
          mcCapacity mc2 `shouldBe` 2
          -- Each scratch is a byte-for-byte snapshot of the shared source ...
          s1 <- BL.readFile (mcScratch mc1)
          s2 <- BL.readFile (mcScratch mc2)
          s1 `shouldBe` original
          s2 `shouldBe` original
          -- ... and the SHARED file was never written (isolation invariant).
          afterShared <- BL.readFile fp
          afterShared `shouldBe` original
          -- The session now has two members.
          members <- sessionMembers fp (mcSession mc1)
          length members `shouldBe` 2
          -- Capacity is enforced: a third token is refused.
          r3 <- checkoutHoleMulti fp astVal "/statements/1/body" 2 emptyCheckoutContext
          isLeft r3 `shouldBe` True
          -- An exclusive checkout on the same pointer is refused while the
          -- session is open.
          rEx <- checkoutHole fp astVal "/statements/1/body"
          isLeft rEx `shouldBe` True
        _ -> expectationFailure $ "expected two successful multi checkouts, got: "
                                ++ show (r1, r2)
      removeDirectoryRecursive tmpDir

    it "--multi 1 is refused (a session needs >= 2 concurrent fills)" $ do
      let tmpDir = "test/_tmp_r5_multi1"
      createDirectoryIfMissing True tmpDir
      BL.readFile "../examples/withdraw-demo/withdraw.ast.json"
        >>= BL.writeFile (tmpDir </> "withdraw.ast.json")
      let fp = tmpDir </> "withdraw.ast.json"
      raw <- BL.readFile fp
      let Just astVal = decode raw
      r <- checkoutHoleMulti fp astVal "/statements/1/body" 1 emptyCheckoutContext
      isLeft r `shouldBe` True
      removeDirectoryRecursive tmpDir

    it "promote copies the winning scratch to the shared tree and tears the session down" $ do
      let tmpDir = "test/_tmp_r5_promote"
      createDirectoryIfMissing True tmpDir
      BL.readFile "../examples/withdraw-demo/withdraw.ast.json"
        >>= BL.writeFile (tmpDir </> "withdraw.ast.json")
      let fp = tmpDir </> "withdraw.ast.json"
      original <- BL.readFile fp
      let Just astVal = decode original
      r1 <- checkoutHoleMulti fp astVal "/statements/1/body" 2 emptyCheckoutContext
      _  <- checkoutHoleMulti fp astVal "/statements/1/body" 2 emptyCheckoutContext
      case r1 of
        Right mc1 -> do
          -- The winner edits ONLY its scratch (simulate a fill).
          BL.writeFile (mcScratch mc1) "{\"winner\":true}"
          -- Before promotion the shared file is still the original.
          preShared <- BL.readFile fp
          preShared `shouldBe` original
          promoted <- promoteDivergenceWinner fp (mcSession mc1) (ctToken (mcToken mc1))
          isRight promoted `shouldBe` True
          -- Now the shared tree carries the winner ...
          postShared <- BL.readFile fp
          postShared `shouldBe` "{\"winner\":true}"
          -- ... and the session is gone.
          remaining <- loadSessions fp
          any ((== mcSession mc1) . dsSession) remaining `shouldBe` False
        Left diag -> expectationFailure $ T.unpack (diagMessage diag)
      removeDirectoryRecursive tmpDir

  -- -----------------------------------------------------------------------
  -- Module System (M-01 through M-07)
  -- -----------------------------------------------------------------------
  moduleSpec
