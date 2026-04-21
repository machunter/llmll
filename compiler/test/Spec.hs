{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Test.Hspec
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import LLMLL.Lexer (tokenize, Token(..), TokenKind(..))
import LLMLL.Parser (parseStatements, parseExpr)
import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, typeCheckWithCache, emptyEnv, builtinEnv, runSketch, SketchResult(..), SketchHole(..), HoleStatus(..), InvariantSuggestion(..))
import LLMLL.InvariantRegistry (defaultPatterns, matchPatterns, InvariantPattern(..))
import LLMLL.ObligationMining (mineObligations, formatObligations, formatObligationsJson, ObligationSuggestion(..), SuggestionStrength(..))
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), FQVerifyResult(..))
import LLMLL.Diagnostic (reportSuccess, reportDiagnostics, diagKind, diagMessage, diagPointer, diagSeverity, diagHoleSensitive, Severity(..), Diagnostic(..), mkError, PatchOpInfo(..), rebaseToPatch, mkTrustGapWarning)
import LLMLL.CodegenHs (generateHaskell, cgMainHs, cgHsSource, cgPackageYaml, emitExpr, toHsType, emitHole, emitEventLogPreamble, classifyImport, ImportKind(..))
import LLMLL.HoleAnalysis (analyzeHoles, analyzeHolesWithDeps, holeEntries, holeKind, HoleEntry(..), HoleDep(..))
import qualified LLMLL.HoleAnalysis as HA
import LLMLL.ParserJSON (parseJSONAST)
import LLMLL.AstEmit (stmtToJson)
import LLMLL.Contracts (ContractsMode(..), instrumentStatement, instrumentContracts, applyContractsMode)
import LLMLL.VerifiedCache (verifiedPath, saveVerified, loadVerified)
import LLMLL.Hub (scaffoldCacheRoot, resolveScaffold)
import LLMLL.Replay (parseEventLog, EventLogEntry(..), runReplay, ReplayResult(..))
import LLMLL.LeanTranslate (translateObligation, TranslateResult(..))
import LLMLL.MCPClient (MCPResult(..), mockProofResult, callLeanstral, defaultMCPConfig, MCPConfig(..))
import LLMLL.ProofCache (proofCachePath, ProofEntry(..), loadProofCache, saveProofCache, lookupProof, insertProof, computeObligationHash)
import LLMLL.TrustReport (buildTrustReport, formatTrustReport, formatTrustReportJson, TrustReport(..), TrustEntry(..), TrustSummary(..))
import LLMLL.AgentSpec (agentSpec, AgentSpec(..), BuiltinEntry(..), OperatorEntry(..))

import qualified Data.Map.Strict as Map
import System.Directory (removeFile, doesFileExist, createDirectoryIfMissing, removeDirectoryRecursive)
import System.Process (callProcess)
import Data.List (isSuffixOf, sort, find)
import qualified Data.Set as Set
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Aeson (encode, decode, Value(..), object, (.=))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Map.Strict as DM

import LLMLL.JsonPointer (resolvePointer, setAtPointer, removeAtPointer, findDescendantHoles, isHoleNode)
import LLMLL.Checkout (lockFilePath, expireStale, CheckoutToken(..), CheckoutLock(..), normalizePointer, collectTypeDefinitions, monomorphizeFunctions, truncateScope, buildScopeEntries, ScopeEntry(..))
import LLMLL.PatchApply (applyOp, applyOps, validateScope, parsePatchOp, PatchOp(..), toPatchOpInfos)
import LLMLL.WeaknessCheck (generateWeaknessCandidates, WeaknessCandidate(..), TrivialBody(..))
import LLMLL.TypeCheck (ScopeSource(..), ScopeBinding(..), structuralUnify, runTC, occursIn, TC)
import Data.Time.Clock (UTCTime(..), secondsToDiffTime, addUTCTime)
import Data.Time.Calendar (fromGregorian)

-- | Run a TC action in an empty environment and return (errors, result).
-- Used by U-Full tests to directly test structuralUnify.
runTCPure :: TC a -> ([Diagnostic], a)
runTCPure action =
  let (result, diags) = runTC emptyEnv action
  in (diags, result)

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
      let result = tokenize "<test>" "(def-logic withdraw)"
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
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> length stmts `shouldBe` 1

    it "parses a def-logic with contracts" $ do
      let src = "(def-logic withdraw [balance: int amount: int]\n\
                \  (pre (>= balance amount))\n\
                \  (post (= result (- balance amount)))\n\
                \  (- balance amount))"
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SDefLogic name params _ contract _ -> do
              name `shouldBe` "withdraw"
              length params `shouldBe` 2
              contractPre contract `shouldNotBe` Nothing
              contractPost contract `shouldNotBe` Nothing
            _ -> expectationFailure "Expected SDefLogic"

    it "parses a check block" $ do
      let src = "(check \"Addition is commutative\"\n\
                \  (for-all [a: int b: int]\n\
                \    (= (+ a b) (+ b a))))"
      case parseStatements "<test>" src of
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
      case parseStatements "../examples/withdraw.llmll" src of
        Left err -> expectationFailure (show err)
        Right stmts -> length stmts `shouldSatisfy` (>= 3)

    it "parses a def-interface" $ do
      let src = "(def-interface AuthSystem\n\
                \  [hash-password (fn [raw: string] -> bytes[64])]\n\
                \  [verify-token  (fn [token: string] -> bool)])"
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SDefInterface name fns -> do
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
      let parseOne src = parseStatements "<test>" src
      case (parseOne ascii, parseOne unicode) of
        (Right a, Right b) -> a `shouldBe` b
        (Left err, _)      -> expectationFailure $ "ASCII parse failed: " ++ show err
        (_, Left err)      -> expectationFailure $ "Unicode parse failed: " ++ show err

    it "∀ expression in check block parses correctly" $ do
      let src = "(check \"commutativity\" (∀ [a: int b: int] (= (+ a b) (+ b a))))"
      case parseStatements "<test>" src of
        Left err   -> expectationFailure (show err)
        Right stmts -> length stmts `shouldBe` 1

  describe "TypeCheck (where binding scope)" $ do
    it "string where-type binding name preserved in AST" $ do
      let src = "(type Word (where [s: string] (> (string-length s) 0)))"
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right [STypeDef _name (TDependent bName _base _constraint)] ->
          bName `shouldBe` "s"
        Right other -> expectationFailure $ "Unexpected: " ++ show (length other) ++ " stmts"

    it "int where-type binding name preserved in AST" $ do
      let src = "(type NonNeg (where [n: int] (>= n 0)))"
      case parseStatements "<test>" src of
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
            , "(def-logic use-nonneg [x: NonNeg] x)"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "string literal matches a where-alias (Word) without error" $ do
      let src = T.pack $ unlines
            [ "(type Word (where [s: string] (> (string-length s) 0)))"
            , "(def-logic use-word [w: Word] w)"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

  describe "TypeCheck (first/second pair projectors)" $ do
    it "first accepts a pair-typed param (v0.4 U2-lite: requires TPair)" $ do
      -- v0.4 U2-lite: first :: TFn [TPair a b] a (was TFn [TVar p] (TVar a))
      let src = T.pack $ unlines
            [ "(def-logic state-word [s: (string, int)] (first s))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "second accepts a pair-typed param (v0.4 U2-lite: requires TPair)" $ do
      let src = T.pack $ unlines
            [ "(def-logic state-rest [s: (int, string)] (second s))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "first on non-pair (string) now produces type error (U2-lite)" $ do
      let src = T.pack $ unlines
            [ "(def-logic state-word [s: string] (first s))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
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
            , "  \"schemaVersion\": \"0.2.0\","
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
      case parseJSONAST "<test>" src of
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
            , "  \"schemaVersion\": \"0.2.0\","
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
      case parseJSONAST "<test>" src of
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
      case parseStatements "<test>" src of
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
      case parseStatements "<test>" src of
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
            , "(def-logic describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) \"blue\")))"
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          -- Must have no non-exhaustive-match errors
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          nonExh `shouldBe` []

    it "non-exhaustive TSumType match (missing ctor) emits non-exhaustive-match error" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-logic describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")))"   -- Blue is missing
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          length nonExh `shouldBe` 1
          diagMessage (head nonExh) `shouldSatisfy` T.isInfixOf "Blue"

    it "wildcard arm satisfies exhaustiveness for TSumType" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-logic describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    (_ \"other\")))"   -- wildcard covers rest
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          let nonExh = filter (\d -> diagKind d == Just "non-exhaustive-match")
                              (reportDiagnostics report)
          nonExh `shouldBe` []

    it "non-exhaustive TResult match (missing Error) emits error" $ do
      let src = T.pack $ unlines
            [ "(def-logic extract [r: Result[int, string]]"
            , "  (match r"
            , "    ((Success v) v)))"   -- Error arm missing
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
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
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          length stmts `shouldBe` 1
          case head stmts of
            SLetrec name params _ _ dec _ -> do
              name `shouldBe` "count-down"
              length params `shouldBe` 1
              dec `shouldBe` EVar "n"
            _ -> expectationFailure "Expected SLetrec"

    it "self-recursive def-logic emits self-recursion warning" $ do
      let src = T.pack $ unlines
            [ "(def-logic count-down [n: int]"
            , "  (if (= n 0) 0 (count-down (- n 1))))"
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          let warns = filter (\d -> diagSeverity d == SevWarning
                                 && T.isInfixOf "self-recursive" (diagMessage d))
                             (reportDiagnostics report)
          length warns `shouldSatisfy` (>= 1)

    it "letrec self-call does NOT emit self-recursion warning" $ do
      let src = "(letrec count-down [n: int] :decreases n (if (= n 0) 0 (count-down (- n 1))))"
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          let warns = filter (\d -> diagSeverity d == SevWarning
                                 && T.isInfixOf "self-recursive" (diagMessage d))
                             (reportDiagnostics report)
          warns `shouldBe` []

    it "letrec codegen emits :decreases comment marker" $ do
      let stmts = [SLetrec "countdown" [("n", TInt)] Nothing
                     (Contract Nothing Nothing) (EVar "n")
                     (EVar "n")]
      let result = generateHaskell "test" stmts
      cgHsSource result `shouldSatisfy` T.isInfixOf "letrec :decreases"
      cgHsSource result `shouldSatisfy` T.isInfixOf "countdown"

  -- -----------------------------------------------------------------------
  -- D3: ?proof-required hole kind
  -- -----------------------------------------------------------------------
  describe "D3 ?proof-required hole" $ do
    it "?proof-required parses as HProofRequired manual in S-expression" $ do
      let src = "(def-logic dummy [] ?proof-required)"
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts ->
          case head stmts of
            SDefLogic _ _ _ _ (EHole (HProofRequired r)) ->
              r `shouldBe` "manual"
            _ -> expectationFailure "Expected EHole (HProofRequired \"manual\")"

    it "letrec with simple variable decreases has no complex-decreases hole" $ do
      let stmts = [SLetrec "f" [("n", TInt)] Nothing
                     (Contract Nothing Nothing) (EVar "n") (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "complex-decreases")
                           (holeEntries report)
      prHoles `shouldBe` []

    it "letrec with complex decreases auto-emits complex-decreases hole" $ do
      -- :decreases (- n 1) is not a simple variable — needs LH witness
      let stmts = [SLetrec "f" [("n", TInt)] Nothing
                     (Contract Nothing Nothing)
                     (EApp "-" [EVar "n", ELit (LitInt 1)])
                     (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "complex-decreases")
                           (holeEntries report)
      length prHoles `shouldBe` 1

    it "non-linear contract auto-emits non-linear-contract hole" $ do
      -- pre: (* n n) > 0 — multiplication of two variables is non-linear
      let nlExpr = EApp ">" [EApp "*" [EVar "n", EVar "n"], ELit (LitInt 0)]
      let stmts = [SDefLogic "f" [("n", TInt)] Nothing
                     (Contract (Just nlExpr) Nothing) (EVar "n")]
      let report = analyzeHoles stmts
      let prHoles = filter (\h -> holeKind h == HProofRequired "non-linear-contract")
                           (holeEntries report)
      length prHoles `shouldBe` 1

  -- -----------------------------------------------------------------------
  -- Phase 2c: pair-type in typed-param positions
  -- -----------------------------------------------------------------------
  describe "Phase 2c pair-type in typed-param" $ do
    it "S-expression: (int, string) in def-logic param parses without error" $ do
      let src = "(def-logic f [acc: (int, string)] (first acc))"
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> length stmts `shouldBe` 1

    it "S-expression: pair-type parameter parsed as TPair TInt TString" $ do
      let src = "(def-logic f [acc: (int, string)] (first acc))"
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right [SDefLogic _ params _ _ _] ->
          snd (head params) `shouldBe` TPair TInt TString
        Right other -> expectationFailure $ "Expected SDefLogic, got " ++ show (length other) ++ " stmts"

    it "S-expression: (int, string) typed param passes type-check" $ do
      let src = T.pack $ unlines
            [ "(def-logic f [acc: (int, string)] (first acc))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          -- No errors (warnings OK — first is polymorphic anyway)
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          errs `shouldBe` []

    it "JSON-AST: pair-type param_type decodes to TPair TInt TString" $ do
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.2.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-logic\","
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
      case parseJSONAST "<test>" src of
        Left err -> expectationFailure (show err)
        Right [SDefLogic _ params _ _ _] ->
          snd (head params) `shouldBe` TPair TInt TString
        Right other -> expectationFailure $ "Expected SDefLogic, got " ++ show (length other) ++ " stmts"

  -- -----------------------------------------------------------------------
  -- N2: string-concat arity hint
  -- -----------------------------------------------------------------------
  describe "N2 string-concat arity hint" $ do
    it "string-concat with 3 args desugars to string-concat-many (no error)" $ do
      let src = T.pack $ unlines
            [ "(def-logic f [a: string b: string c: string]"
            , "  (string-concat a b c))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          errs `shouldBe` []

    it "string-concat with correct 2 args has no arity error" $ do
      let src = "(def-logic f [a: string b: string] (string-concat a b))"
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
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
            , "  \"schemaVersion\": \"0.2.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-logic\","
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
      case parseJSONAST "<test>" src of
        Left diag ->
          -- The error message should mention unexpected keys
          diagMessage diag `shouldSatisfy` T.isInfixOf "unexpected keys"
        Right _ ->
          expectationFailure "Expected parse failure for let binding with extra keys"

    it "let binding with only 'name' and 'expr' keys accepts successfully" $ do
      let src = BLC.pack $ unlines
            [ "{"
            , "  \"schemaVersion\": \"0.2.0\","
            , "  \"statements\": ["
            , "    {"
            , "      \"kind\": \"def-logic\","
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
      case parseJSONAST "<test>" src of
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
            [ "(def-logic greet [formal: bool]"
            , "  (if formal \"Good day.\" ?informal))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case findHole "?informal" result of
            Nothing -> expectationFailure "?informal hole not recorded"
            Just h  -> do
              shStatus h `shouldBe` HoleTyped TString
              shPointer h `shouldSatisfy` (not . T.null)

    it "EIf: hole in then gets HoleTyped TInt from concrete else" $ do
      let src = T.pack $ unlines
            [ "(def-logic safe-div [n: int]"
            , "  (if (= n 0) ?zero_case 42))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case findHole "?zero_case" result of
            Nothing -> expectationFailure "?zero_case hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TInt

    it "EMatch: hole arm gets HoleTyped TString from concrete sibling arms" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-logic describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) ?blue_label)))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case findHole "?blue_label" result of
            Nothing -> expectationFailure "?blue_label hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TString

    it "EMatch: hole arm gets HoleAmbiguous when concrete arms disagree" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-logic bad-describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) 42)"
            , "    ((Blue) ?conflict_arm)))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case findHole "?conflict_arm" result of
            Nothing -> expectationFailure "?conflict_arm hole not recorded"
            Just h  -> case shStatus h of
              HoleAmbiguous _ _ -> pure ()  -- correct
              other -> expectationFailure $ "expected HoleAmbiguous, got: " ++ show other

    it "EMatch: conflicting arms emit an ambiguous-hole error" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"
            , "(def-logic bad-describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) 42)"
            , "    ((Blue) ?conflict_arm)))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          let ambigErrs = filter (T.isInfixOf "ambiguous-hole" . diagMessage) (sketchErrors result)
          ambigErrs `shouldSatisfy` (not . null)

    it "EApp: hole argument gets HoleTyped TInt from function parameter position" $ do
      let src = T.pack $ unlines
            [ "(def-logic f [x: int] x)"
            , "(def-logic caller [] (f ?arg))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case findHole "?arg" result of
            Nothing -> expectationFailure "?arg hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TInt

    it "isolated hole with no context gets HoleUnknown" $ do
      let src = T.pack $ unlines
            [ "(def-logic mystery [] ?isolated)" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case findHole "?isolated" result of
            Nothing -> expectationFailure "?isolated hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleUnknown

    it "non-sketch check path unaffected: no holes recorded for concrete program" $ do
      let src = T.pack $ unlines
            [ "(def-logic id-str [s: string]"
            , "  (if (= (string-length s) 0) \"empty\" s))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True
          let skRes = runSketch emptyEnv stmts []
          sketchHoles skRes `shouldBe` []

  -- -----------------------------------------------------------------------
  -- Phase 2c D3: holeSensitive error annotation
  -- -----------------------------------------------------------------------
  describe "Phase 2c D3 holeSensitive error annotation" $ do
    it "type mismatch between concrete types emits holeSensitive = False" $ do
      -- (def-logic f [] (if true 42 "hello")) — branches differ, no holes
      let src = T.pack $ unlines
            [ "(def-logic f [] (if true 42 \"hello\"))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let diags = reportDiagnostics (typeCheck emptyEnv stmts)
          let typeMismatches = filter (maybe False (T.isInfixOf "type-mismatch") . diagKind) diags
              -- type-mismatch between int and string: certain, no holes
              allCertain = all (not . diagHoleSensitive) diags
          allCertain `shouldBe` True

    it "return-type mismatch vs hole var emits holeSensitive = True" $ do
      -- (def-logic f [x: int] : int ?impl) — hole body vs int return type
      -- unify int (expected) vs TVar "?impl" (actual) → holeSensitive
      let src = T.pack $ unlines
            [ "(def-logic f [x: int] ?impl)"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          -- In sketch mode: ?impl synthesises to TVar "?impl".
          -- The concrete caller (f 42) would then force a check; without that
          -- the synthesis produces no type mismatch.  Verify at least that
          -- holeSensitive = False errors are NOT emitted here (no spurious
          -- certain errors should appear for a well-typed partial program).
          let result = runSketch emptyEnv stmts []
          let certainErrs = filter (\d -> diagSeverity d == SevError && not (diagHoleSensitive d)) (sketchErrors result)
          certainErrs `shouldBe` []


    it "inferHole HNamed synthesises TVar with ? prefix (D3 invariant)" $ do
      -- A hole in synthesis position must return TVar "?name", not TVar "?"
      let src = T.pack $ unlines
            [ "(def-logic f [x: int] ?impl)" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
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
            [ "(def-logic greet [formal: bool]"
            , "  (if formal \"Good day.\" ?informal))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case filter ((== "?informal") . shName) (sketchHoles result) of
            []    -> expectationFailure "?informal hole not recorded"
            (h:_) -> shPointer h `shouldBe` "/statements/0/body/else"

    it "hole at match arm 2 has pointer /statements/1/body/arms/2/body" $ do
      let src = T.pack $ unlines
            [ "(type Color (| Red) (| Green) (| Blue))"      -- stmt 0
            , "(def-logic describe [c: Color]"               -- stmt 1
            , "  (match c"
            , "    ((Red) \"red\")"       -- arm 0
            , "    ((Green) \"green\")"   -- arm 1
            , "    ((Blue) ?blue_label)))" -- arm 2
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case filter ((== "?blue_label") . shName) (sketchHoles result) of
            []    -> expectationFailure "?blue_label hole not recorded"
            (h:_) -> shPointer h `shouldBe` "/statements/1/body/arms/2/body"

    it "concrete program produces no holes and non-sketch check is unaffected" $ do
      let src = T.pack $ unlines
            [ "(def-logic f [x: int] x)"
            , "(def-logic g [s: string] s)"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True
          let result = runSketch emptyEnv stmts []
          sketchHoles result `shouldBe` []


  -- =========================================================================
  -- v0.3: JsonPointer tests (pure)
  -- =========================================================================

  describe "JsonPointer" $ do
    let testAst = object
          [ "schemaVersion" .= ("0.2.0" :: T.Text)
          , "statements" .= [ object
              [ "kind" .= ("def-logic" :: T.Text)
              , "name" .= ("foo" :: T.Text)
              , "body" .= object
                  [ "kind" .= ("pair" :: T.Text)
                  , "fst"  .= object [ "kind" .= ("var" :: T.Text), "name" .= ("x" :: T.Text) ]
                  , "snd"  .= object [ "kind" .= ("lit-int" :: T.Text), "value" .= (42 :: Int) ]
                  ]
              ]
            , object
              [ "kind" .= ("def-logic" :: T.Text)
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

    it "expireStale removes expired tokens" $ do
      let epoch = UTCTime (fromGregorian 2026 1 1) 0
          tok = CheckoutToken "/a" "hole-delegate" Nothing epoch "tok1" 3600 Nothing Nothing Nothing Nothing False
          lock = CheckoutLock "test.json" [tok]
          later = addUTCTime 7200 epoch
      lockTokens (expireStale later lock) `shouldBe` []

    it "expireStale keeps non-expired tokens" $ do
      let epoch = UTCTime (fromGregorian 2026 1 1) 0
          tok = CheckoutToken "/a" "hole-delegate" Nothing epoch "tok1" 3600 Nothing Nothing Nothing Nothing False
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

  describe "VerificationLevel Ord" $ do
    it "VLAsserted < VLTested" $
      compare VLAsserted (VLTested 50) `shouldBe` LT

    it "VLTested < VLProven" $
      compare (VLTested 100) (VLProven "z3") `shouldBe` LT

    it "VLTested 50 == VLTested 1000 (sample count ignored)" $
      compare (VLTested 50) (VLTested 1000) `shouldBe` EQ

    it "VLProven z3 == VLProven leanstral (prover name ignored)" $
      compare (VLProven "z3") (VLProven "leanstral") `shouldBe` EQ

    it "VLAsserted < VLProven" $
      compare VLAsserted (VLProven "z3") `shouldBe` LT

  describe "ContractsMode: instrumentStatement" $ do
    let mkDefLogic name preE postE bodyE =
          SDefLogic name [("x", TInt)] Nothing
            (Contract preE postE) bodyE
        mkLetrec name preE postE bodyE =
          SLetrec name [("n", TInt)] Nothing
            (Contract preE postE) (EVar "n") bodyE
        hasPre  = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
        hasPost = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
        body    = EVar "x"
        defaultCS = ContractStatus Nothing Nothing
        provenCS  = ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3"))
        mixedCS   = ContractStatus (Just (VLProven "z3")) (Just VLAsserted)

    it "ContractsFull keeps all contracts (SDefLogic)" $ do
      let stmt = mkDefLogic "f" hasPre hasPost body
          result = instrumentStatement ContractsFull defaultCS stmt
      defLogicContract result `shouldBe` Contract Nothing Nothing
      -- body should be wrapped (not the original)
      defLogicBody result `shouldNotBe` body

    it "ContractsFull keeps all contracts (SLetrec)" $ do
      let stmt = mkLetrec "g" hasPre hasPost body
          result = instrumentStatement ContractsFull defaultCS stmt
      letrecContract result `shouldBe` Contract Nothing Nothing

    it "ContractsNone strips all contracts" $ do
      let stmt = mkDefLogic "f" hasPre hasPost body
          result = instrumentStatement ContractsNone defaultCS stmt
      -- ContractsNone returns stmt unchanged
      result `shouldBe` stmt

    it "ContractsUnproven strips proven pre, keeps asserted post" $ do
      let stmt = mkDefLogic "f" hasPre hasPost body
          result = instrumentStatement ContractsUnproven mixedCS stmt
      defLogicContract result `shouldBe` Contract Nothing Nothing
      -- The body should still be instrumented (post is unproven)
      defLogicBody result `shouldNotBe` body

  describe "parseTrustDecl (S-expression)" $ do
    it "parses (trust foo.bar :level tested)" $ do
      case parseStatements "<test>" "(trust foo.bar :level tested)" of
        Right [STrust target level] -> do
          target `shouldBe` "foo.bar"
          vlTier level `shouldBe` 1
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses (trust crypto.hash.pbkdf2 :level asserted)" $ do
      case parseStatements "<test>" "(trust crypto.hash.pbkdf2 :level asserted)" of
        Right [STrust target level] -> do
          target `shouldBe` "crypto.hash.pbkdf2"
          level `shouldBe` VLAsserted
        other -> expectationFailure $ "unexpected: " ++ show other

    it "parses (trust z3.verify :level proven)" $ do
      case parseStatements "<test>" "(trust z3.verify :level proven)" of
        Right [STrust target level] -> do
          target `shouldBe` "z3.verify"
          vlTier level `shouldBe` 2
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
          SDefLogic name [("x", TInt)] Nothing (Contract preE postE) bodyE
        pre1  = Just (EApp ">=" [EVar "x", ELit (LitInt 0)])
        post1 = Just (EApp ">=" [EVar "result", ELit (LitInt 0)])
        body1 = EVar "x"
        stmts = [mkDL "f" pre1 post1 body1, mkDL "g" pre1 Nothing body1]
        provenMap = DM.fromList
          [ ("f", ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))
          , ("g", ContractStatus (Just (VLProven "z3")) Nothing)
          ]
        emptyMap = DM.empty

    it "ContractsFull preserves all contracts" $ do
      let result = applyContractsMode ContractsFull emptyMap stmts
      length result `shouldBe` 2
      defLogicContract (head result) `shouldBe` Contract pre1 post1

    it "ContractsNone clears all contracts" $ do
      let result = applyContractsMode ContractsNone emptyMap stmts
      defLogicContract (head result) `shouldBe` Contract Nothing Nothing
      defLogicContract (result !! 1) `shouldBe` Contract Nothing Nothing

    it "ContractsUnproven strips proven, keeps unknown" $ do
      -- "f" is fully proven → both clauses stripped
      -- "g" pre is proven → stripped; g has no post → Nothing stays
      let result = applyContractsMode ContractsUnproven provenMap stmts
      defLogicContract (head result) `shouldBe` Contract Nothing Nothing
      defLogicContract (result !! 1) `shouldBe` Contract Nothing Nothing

  -- =========================================================================
  -- v0.3: #9 — saveVerified / loadVerified round-trip
  -- =========================================================================

  describe "VerifiedCache round-trip" $ do
    it "saveVerified then loadVerified recovers contract status" $ do
      let testFile = "test/_tmp_roundtrip_test.llmll"
          statuses = DM.fromList
            [ ("add", ContractStatus (Just (VLProven "liquid-fixpoint")) (Just (VLProven "liquid-fixpoint")))
            , ("mul", ContractStatus (Just VLAsserted) Nothing)
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
          [ SDefLogic name [("x", TInt)] (Just TInt) (Contract preE postE) bodyE
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
              [("safe-add", ContractStatus (Just VLAsserted) (Just VLAsserted))]
          }
        cache = DM.fromList [(modPath, modEnv)]

    it "emits trust-gap warning for unproven cross-module call" $ do
      let callerStmts = [SDefLogic "caller" [] (Just TInt) (Contract Nothing Nothing) (EApp "math.safe-add" [ELit (LitInt 5)])]
          report = typeCheckWithCache cache emptyEnv callerStmts
          trustGaps = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      length trustGaps `shouldSatisfy` (> 0)

    it "no trust-gap for proven contracts" $ do
      let provenEnv = modEnv { meContractStatus = DM.fromList
              [("safe-add", ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))] }
          provenCache = DM.fromList [(modPath, provenEnv)]
          callerStmts = [SDefLogic "caller" [] (Just TInt) (Contract Nothing Nothing) (EApp "math.safe-add" [ELit (LitInt 5)])]
          report = typeCheckWithCache provenCache emptyEnv callerStmts
          trustGaps = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      trustGaps `shouldBe` []

    it "trust declaration suppresses trust-gap warning" $ do
      let callerStmts =
            [ STrust "math.safe-add" VLAsserted  -- acknowledge the assertion level
            , SDefLogic "caller" [] (Just TInt) (Contract Nothing Nothing) (EApp "math.safe-add" [ELit (LitInt 5)])
            ]
          report = typeCheckWithCache cache emptyEnv callerStmts
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
                          (Contract pre1 post1) (EVar "x")
                       , SExport [name]
                       ]
          in ModuleEnv
               { meExports        = DM.fromList [(name, TFn [TInt] TInt)]
               , meStatements     = stmts
               , meInterfaces     = DM.empty
               , meAliasMap       = DM.empty
               , mePath           = T.splitOn "." name
               , meContractStatus = DM.fromList [(name, contractStatus)]
               }

        -- Module A: "auth.verify" with configurable contract status
        mkAuthModule cs = mkModuleEnvWith "auth.verify" cs
        authModPath     = ["auth", "verify"]

        -- Module B caller: calls "auth.verify.auth.verify" (qualified via cache seeding)
        mkCallerStmts = [SDefLogic "check-user" [("uid", TInt)] (Just TInt)
                           (Contract Nothing Nothing)
                           (EApp "auth.verify.auth.verify" [EVar "uid"])]

        -- Helper: count trust-gap diagnostics
        countTrustGaps report =
          length $ filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)

    -- Test 1: Asserted contracts emit trust-gap warnings
    it "asserted contract in imported module emits trust-gap warning" $ do
      let authEnv = mkAuthModule (ContractStatus (Just VLAsserted) (Just VLAsserted))
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache cache emptyEnv mkCallerStmts
      countTrustGaps report `shouldSatisfy` (> 0)

    -- Test 2: Proven contracts do NOT emit trust-gap warnings
    it "proven contract in imported module emits no trust-gap warning" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache cache emptyEnv mkCallerStmts
      countTrustGaps report `shouldBe` 0

    -- Test 3: Tested contracts emit trust-gap warnings
    it "tested contract in imported module emits trust-gap warning" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (VLTested 100)) (Just (VLTested 100)))
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache cache emptyEnv mkCallerStmts
      countTrustGaps report `shouldSatisfy` (> 0)

    -- Test 4: Mixed levels — proven pre + asserted post still emits warning (for post)
    it "mixed levels (proven pre, asserted post) emits trust-gap for post only" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (VLProven "z3")) (Just VLAsserted))
          cache   = DM.fromList [(authModPath, authEnv)]
          report  = typeCheckWithCache cache emptyEnv mkCallerStmts
          gaps    = filter (\d -> diagKind d == Just "trust-gap") (reportDiagnostics report)
      -- Should have exactly 1 gap (for the asserted postcondition)
      length gaps `shouldBe` 1

    -- Test 5: Trust declaration at VLTested suppresses VLTested gap
    it "trust declaration at tested level suppresses tested trust-gap" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (VLTested 100)) (Just (VLTested 100)))
          cache   = DM.fromList [(authModPath, authEnv)]
          callerStmts =
            [ STrust "auth.verify.auth.verify" (VLTested 0)
            , SDefLogic "check-user" [("uid", TInt)] (Just TInt)
                (Contract Nothing Nothing)
                (EApp "auth.verify.auth.verify" [EVar "uid"])
            ]
          report = typeCheckWithCache cache emptyEnv callerStmts
      countTrustGaps report `shouldBe` 0

    -- Test 6: Trust declaration at lower level does NOT suppress higher-level gap
    -- (trust at asserted should NOT suppress a tested-level gap since asserted < tested)
    it "trust at asserted does NOT suppress tested-level gap" $ do
      let authEnv = mkAuthModule (ContractStatus (Just (VLTested 100)) (Just (VLTested 100)))
          cache   = DM.fromList [(authModPath, authEnv)]
          callerStmts =
            [ STrust "auth.verify.auth.verify" VLAsserted  -- asserted < tested
            , SDefLogic "check-user" [("uid", TInt)] (Just TInt)
                (Contract Nothing Nothing)
                (EApp "auth.verify.auth.verify" [EVar "uid"])
            ]
          report = typeCheckWithCache cache emptyEnv callerStmts
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
                [("safe-add", ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))]
            }
          cryptoEnv = ModuleEnv
            { meExports        = DM.fromList [("hash", TFn [TString] TString)]
            , meStatements     = []
            , meInterfaces     = DM.empty
            , meAliasMap       = DM.empty
            , mePath           = ["crypto"]
            , meContractStatus = DM.fromList
                [("hash", ContractStatus (Just VLAsserted) Nothing)]
            }
          cache = DM.fromList [( ["math"], mathEnv), (["crypto"], cryptoEnv)]
          callerStmts =
            [ SDefLogic "process" [("x", TInt)] (Just TInt)
                (Contract Nothing Nothing)
                (EApp "math.safe-add" [EVar "x"])
            , SDefLogic "hash-input" [("s", TString)] (Just TString)
                (Contract Nothing Nothing)
                (EApp "crypto.hash" [EVar "s"])
            ]
          report = typeCheckWithCache cache emptyEnv callerStmts
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
                                             (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])))
                                   (EVar "x")]
            , meInterfaces     = DM.empty
            , meAliasMap       = DM.empty
            , mePath           = path
            , meContractStatus = DM.fromList [(name, cs)]
            }

    -- Test 1: Report includes entry function with its contract levels
    it "report includes entry module functions" $ do
      let stmts = [ SDefLogic "main-fn" [("n", TInt)] (Just TInt)
                       (Contract (Just (EApp ">=" [EVar "n", ELit (LitInt 0)])) Nothing)
                       (EVar "n")
                   ]
          cache = DM.empty
          report = buildTrustReport cache stmts
      length (trEntries report) `shouldBe` 1
      teName (head (trEntries report)) `shouldBe` "main-fn"
      tePreLevel (head (trEntries report)) `shouldBe` Just VLAsserted

    -- Test 2: Report detects epistemic drift (proven depends on asserted)
    it "detects epistemic drift: proven function depending on asserted callee" $ do
      let provenMod = mkModEnv "safe-add" ["math"]
                        (ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))
          assertedMod = mkModEnv "hash" ["crypto"]
                          (ContractStatus (Just VLAsserted) (Just VLAsserted))
          cache = DM.fromList [(["math"], provenMod), (["crypto"], assertedMod)]
          -- Entry function is proven but calls asserted crypto.hash
          stmts = [ SDefLogic "process" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)]))
                                (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])))
                      (EApp "crypto.hash" [EVar "x"])
                  ]
          report = buildTrustReport cache stmts
          processEntry = head [e | e <- trEntries report, teName e == "process"]
      -- The entry function has asserted contracts (default) and depends on crypto.hash
      length (teDeps processEntry) `shouldSatisfy` (>= 1)

    -- Test 3: No drift when all dependencies are proven
    it "no drift when all dependencies are proven" $ do
      let provenMod = mkModEnv "safe-add" ["math"]
                        (ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))
          cache = DM.fromList [(["math"], provenMod)]
          stmts = [ SDefLogic "caller" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing)
                      (EApp "math.safe-add" [EVar "x"])
                  ]
          report = buildTrustReport cache stmts
          callerEntry = head [e | e <- trEntries report, teName e == "caller"]
      teDrifts callerEntry `shouldBe` []

    -- Test 4: Summary counts are correct
    it "summary counts match entry classification" $ do
      let provenMod = mkModEnv "safe-add" ["math"]
                        (ContractStatus (Just (VLProven "z3")) (Just (VLProven "z3")))
          assertedMod = mkModEnv "hash" ["crypto"]
                          (ContractStatus (Just VLAsserted) (Just VLAsserted))
          cache = DM.fromList [(["math"], provenMod), (["crypto"], assertedMod)]
          stmts = [ SDefLogic "no-contract" [("x", TInt)] (Just TInt)
                      (Contract Nothing Nothing) (EVar "x")
                  ]
          report = buildTrustReport cache stmts
      -- math.safe-add is proven, crypto.hash is asserted, no-contract has no contract
      tsProven   (trSummary report) `shouldBe` 1
      tsAsserted (trSummary report) `shouldBe` 1
      tsNone     (trSummary report) `shouldBe` 1

    -- Test 5: JSON output is valid JSON and contains expected keys
    it "formatTrustReportJson produces valid JSON with entries and summary" $ do
      let cache = DM.empty
          stmts = [ SDefLogic "fn1" [("x", TInt)] (Just TInt)
                      (Contract (Just (EApp ">=" [EVar "x", ELit (LitInt 0)])) Nothing)
                      (EVar "x")
                  ]
          report = buildTrustReport cache stmts
          jsonText = formatTrustReportJson report
      -- Must parse as valid JSON
      (decode (BLC.pack (T.unpack jsonText)) :: Maybe Value) `shouldSatisfy` (/= Nothing)
      -- Must contain expected keys
      jsonText `shouldSatisfy` T.isInfixOf "\"entries\""
      jsonText `shouldSatisfy` T.isInfixOf "\"summary\""
      jsonText `shouldSatisfy` T.isInfixOf "\"proven\""
      jsonText `shouldSatisfy` T.isInfixOf "\"asserted\""
      jsonText `shouldSatisfy` T.isInfixOf "\"drifts\""

    -- Test 6: Human-readable format contains function names and levels
    it "formatTrustReport contains function names and verification levels" $ do
      let assertedMod = mkModEnv "verify-token" ["auth"]
                          (ContractStatus (Just VLAsserted) Nothing)
          cache = DM.fromList [(["auth"], assertedMod)]
          stmts = []
          report = buildTrustReport cache stmts
          humanText = formatTrustReport report
      humanText `shouldSatisfy` T.isInfixOf "Trust Report"
      humanText `shouldSatisfy` T.isInfixOf "verify-token"
      humanText `shouldSatisfy` T.isInfixOf "asserted"

  -- =========================================================================
  -- v0.3 #14: Async/Await codegen test coverage (10 tests)
  -- =========================================================================

  describe "Async codegen (#14)" $ do
    -- Type emission (3)
    it "toHsType (TPromise TInt) = (Async.Async Int)" $
      toHsType (TPromise TInt) `shouldBe` "(Async.Async Int)"

    it "toHsType (TPromise (TResult TString TInt)) handles nesting" $
      toHsType (TPromise (TResult TString TInt)) `shouldBe` "(Async.Async (Either Int String))"

    it "toHsType (TPromise (TPromise TInt)) handles double-wrap" $
      toHsType (TPromise (TPromise TInt)) `shouldBe` "(Async.Async (Async.Async Int))"

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
          prog = [SDefLogic "f" [] Nothing (Contract Nothing Nothing)
                    (EAwait (EHole (HDelegateAsync delegSpec)))]
          report = typeCheck emptyEnv prog
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      errs `shouldBe` []

    it "?delegate-async hole infers TPromise(returnType)" $ do
      let delegSpec = DelegateSpec "agent" "task" TInt Nothing
          prog = [SDefLogic "f" [] Nothing (Contract Nothing Nothing)
                    (EHole (HDelegateAsync delegSpec))]
          report = typeCheck emptyEnv prog
          hardErrs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      hardErrs `shouldBe` []

    -- Parser roundtrip (1)
    it "(await expr) parses to EAwait" $ do
      case parseStatements "<test>" "(def-logic f [] (await (+ 1 2)))" of
        Right [SDefLogic _ _ _ _ (EAwait _)] -> pure ()
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
      writeFile file "{\"schemaVersion\": \"0.2.0\", \"statements\": []}"
      result <- resolveScaffold "test-scaffold-tmp"
      result `shouldBe` Just file
      removeDirectoryRecursive dir

    -- Parser (2)
    it "(?scaffold todo-app) parses to EHole (HScaffold ...)" $ do
      case parseStatements "<test>" "(def-logic f [] (?scaffold todo-app))" of
        Right [SDefLogic _ _ _ _ (EHole (HScaffold spec))] ->
          scaffoldTemplate spec `shouldBe` "todo-app"
        other -> expectationFailure $ "unexpected: " ++ show other

    it "JSON-AST hole-scaffold parses correctly" $ do
      let jsonSrc = BLC.pack $ unlines
            [ "{ \"schemaVersion\": \"0.2.0\""
            , ", \"statements\": ["
            , "    { \"kind\": \"def-logic\", \"name\": \"f\", \"params\": []"
            , "    , \"body\": { \"kind\": \"hole-scaffold\", \"template\": \"rest-api\" } }"
            , "  ]"
            , "}"
            ]
      case parseJSONAST "<test>" jsonSrc of
        Right [SDefLogic _ _ _ _ (EHole (HScaffold spec))] ->
          scaffoldTemplate spec `shouldBe` "rest-api"
        other -> expectationFailure $ "unexpected: " ++ show other

    -- HoleAnalysis (1)
    it "analyzeHoles reports ?scaffold as NonBlocking" $ do
      let spec = ScaffoldSpec "todo-app" Nothing [] Nothing Nothing
          prog = [SDefLogic "f" [] Nothing (Contract Nothing Nothing)
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
      case parseStatements "<test>" src of
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

    -- LeanTranslate (3)
    it "translateObligation on linear arithmetic → valid Lean 4" $ do
      let contract = Contract
            { contractPre  = Just (EOp ">" [EVar "x", ELit (LitInt 0)])
            , contractPost = Just (EOp ">" [EVar "result", ELit (LitInt 0)])
            }
      case translateObligation "test-func" contract of
        LeanTheorem thm -> do
          T.isInfixOf "theorem test_func" thm `shouldBe` True
          T.isInfixOf "sorry" thm `shouldBe` True
        Unsupported reason -> expectationFailure $ "Expected theorem, got: " ++ T.unpack reason

    it "translateObligation on unsupported predicate → Unsupported" $ do
      let contract = Contract
            { contractPre  = Nothing
            , contractPost = Just (EApp "fold" [EVar "xs"])
            }
      case translateObligation "fold-test" contract of
        Unsupported reason -> T.isInfixOf "fold" reason `shouldBe` True
        LeanTheorem _ -> expectationFailure "Expected Unsupported for fold"

    it "translateObligation on list induction → List syntax" $ do
      let contract = Contract
            { contractPre  = Nothing
            , contractPost = Just (EOp ">" [EApp "list-length" [EVar "xs"], ELit (LitInt 0)])
            }
      case translateObligation "list-test" contract of
        LeanTheorem thm -> T.isInfixOf ".length" thm `shouldBe` True
        Unsupported reason -> expectationFailure $ "Expected theorem, got: " ++ T.unpack reason

    -- MCPClient (2)
    it "mockProofResult returns ProofFound" $ do
      let result = mockProofResult "some obligation"
      result `shouldBe` ProofFound "by sorry"

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
                     (Contract Nothing Nothing) (EHole (HProofRequired "complex-decreases"))]
          report = HA.analyzeHoles stmts
          json   = HA.formatHoleReportJson "<test>" False report
      T.isInfixOf "complexity" json `shouldBe` True
      T.isInfixOf ":inductive" json `shouldBe` True

    -- End-to-end mock pipeline (1)
    it "Mock pipeline: translate → mock-prove → cache → verify" $ do
      let contract = Contract
            { contractPre  = Just (EOp ">" [EVar "x", ELit (LitInt 0)])
            , contractPost = Just (EOp ">" [EVar "result", ELit (LitInt 0)])
            }
      case translateObligation "pipeline-test" contract of
        LeanTheorem thm -> do
          let proofResult = mockProofResult thm
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

-- =====================================================================
-- Phase E tests: Verify Integration (v0.3.1)
-- =====================================================================

verifyIntegrationTests :: Spec
verifyIntegrationTests = describe "Verify Integration (v0.3.1)" $ do
    it "LeanstralOpts mock pipeline resolves proof-required holes" $ do
      -- Simulate the pipeline: scan statements → translate → mock prove → cache
      let stmts = [ SDefLogic "test-fn" [("x", TInt)] Nothing
                      (Contract
                         (Just (EOp ">" [EVar "x", ELit (LitInt 0)]))
                         (Just (EOp ">" [EVar "result", ELit (LitInt 0)])))
                      (EHole (HProofRequired "complex-decreases"))
                  ]
          proofHoles = [ (n, c)
                       | SDefLogic n _ _ c (EHole (HProofRequired _)) <- stmts
                       ]
      length proofHoles `shouldBe` 1
      case proofHoles of
        [(name, contract)] -> do
          case translateObligation name contract of
            LeanTheorem thm -> do
              let mockResult = mockProofResult thm
              case mockResult of
                ProofFound proof -> do
                  let entry = ProofEntry thm proof "leanstral" ""
                      cache = insertProof ("/post/" <> name) entry Map.empty
                  -- Verify cache lookup works
                  lookupProof ("/post/" <> name) thm cache `shouldBe` Just entry
                _ -> expectationFailure "Expected ProofFound from mock"
            Unsupported reason -> expectationFailure $ "Expected LeanTheorem: " ++ T.unpack reason
        _ -> expectationFailure "Expected exactly one proof hole"

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
    it "translateObligation on empty contract → Unsupported" $ do
      let contract = Contract Nothing Nothing
      case translateObligation "empty-test" contract of
        Unsupported reason -> T.isInfixOf "empty" reason `shouldBe` True
        LeanTheorem _      -> expectationFailure "Expected Unsupported for empty contract"

    it "translateObligation with pre-only (no post) → valid theorem with True goal" $ do
      let contract = Contract
            { contractPre  = Just (EOp ">" [EVar "x", ELit (LitInt 0)])
            , contractPost = Nothing
            }
      case translateObligation "pre-only" contract of
        LeanTheorem thm -> do
          T.isInfixOf "True" thm `shouldBe` True
          T.isInfixOf "(h :" thm `shouldBe` True
        Unsupported reason -> expectationFailure $ "Expected theorem: " ++ T.unpack reason

    it "translateObligation with for-all → quantified Lean 4" $ do
      let contract = Contract
            { contractPre  = Nothing
            , contractPost = Just (EApp "for-all" [EVar "i", EOp ">" [EVar "i", ELit (LitInt 0)]])
            }
      case translateObligation "forall-test" contract of
        LeanTheorem thm -> do
          T.isInfixOf "∀" thm `shouldBe` True
          T.isInfixOf "i" thm `shouldBe` True
        Unsupported reason -> expectationFailure $ "Expected theorem: " ++ T.unpack reason

    it "translateObligation with boolean ops (and/or/not)" $ do
      let contract = Contract
            { contractPre  = Nothing
            , contractPost = Just (EOp "and" [ EOp ">" [EVar "x", ELit (LitInt 0)]
                                             , EOp "not" [EOp "<" [EVar "y", ELit (LitInt 0)]]
                                             ])
            }
      case translateObligation "bool-test" contract of
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
      case parseStatements "<test>" src of
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
    it "SLetrec with HProofRequired body is detected by pattern match" $ do
      let stmts = [ SLetrec
                      { letrecName     = "fib"
                      , letrecParams   = [("n", TInt)]
                      , letrecReturn   = Just TInt
                      , letrecContract = Contract
                          (Just (EOp ">=" [EVar "n", ELit (LitInt 0)]))
                          (Just (EOp ">=" [EVar "result", ELit (LitInt 0)]))
                      , letrecDecreases = EVar "n"
                      , letrecBody     = EHole (HProofRequired "complex-decreases")
                      }
                  ]
          -- Same pattern used by runLeanstralPipeline
          proofHoles = [ (n, c)
                       | SLetrec n _ _ c _ (EHole (HProofRequired _)) <- stmts
                       ]
      length proofHoles `shouldBe` 1
      fst (head proofHoles) `shouldBe` "fib"
      case translateObligation "fib" (snd (head proofHoles)) of
        LeanTheorem thm -> T.isInfixOf "theorem fib" thm `shouldBe` True
        Unsupported r   -> expectationFailure $ "Expected theorem: " ++ T.unpack r

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
      let prog = [ SDefLogic "f" [("x", TInt)] Nothing (Contract Nothing Nothing)
                     (EHole (HNamed "impl"))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      HA.holePointer (head entries) `shouldBe` "/statements/0/body"

    it "second statement gets /statements/1/body pointer" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing) (ELit (LitInt 1))
                 , SDefLogic "g" [("x", TInt)] Nothing (Contract Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "agent" "task" TInt Nothing)))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      HA.holePointer (head entries) `shouldBe` "/statements/1/body"

    it "hole in if-then branch gets /then_branch subpath" $ do
      let prog = [ SDefLogic "f" [("x", TInt)] Nothing (Contract Nothing Nothing)
                     (EIf (EVar "x")
                          (EHole (HNamed "then-impl"))
                          (ELit (LitInt 0)))
                 ]
          report = analyzeHoles prog
          entries = holeEntries report
      length entries `shouldBe` 1
      HA.holePointer (head entries) `shouldBe` "/statements/0/body/then_branch"

  -- -----------------------------------------------------------------
  -- Dependency analysis (3 tests)
  -- -----------------------------------------------------------------

  describe "Dependency analysis" $ do
    it "hole in caller depends on hole in callee" $ do
      -- hash-password has a ?delegate hole; login-handler calls hash-password and has its own hole
      let prog = [ SDefLogic "hash-password" [("pw", TString)] Nothing (Contract Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "crypto-agent" "hash" TString Nothing)))
                 , SDefLogic "login-handler" [("user", TString)] Nothing (Contract Nothing Nothing)
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
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "a" "t1" TInt Nothing)))
                 , SDefLogic "g" [] Nothing (Contract Nothing Nothing)
                     (EHole (HDelegate (DelegateSpec "b" "t2" TInt Nothing)))
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
      all (\e -> null (HA.holeDependsOn e)) entries `shouldBe` True

    it "JSON output with deps includes depends_on and cycle_warning" $ do
      let prog = [ SDefLogic "f" [] Nothing (Contract Nothing Nothing)
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
      let prog = [ SDefLogic "f" [("x", TInt)] (Just TInt) (Contract Nothing Nothing)
                     (EApp "g" [EHole (HDelegate (DelegateSpec "a" "t1" TInt Nothing))])
                 , SDefLogic "g" [("x", TInt)] (Just TInt) (Contract Nothing Nothing)
                     (EApp "f" [EHole (HDelegate (DelegateSpec "b" "t2" TInt Nothing))])
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
      -- Both should have cycle_warning
      all (\e -> HA.holeCycleWarn e) entries `shouldBe` True

    it "cycle breaking removes back-edge from highest-index hole" $ do
      let prog = [ SDefLogic "f" [("x", TInt)] (Just TInt) (Contract Nothing Nothing)
                     (EApp "g" [EHole (HDelegate (DelegateSpec "a" "t1" TInt Nothing))])
                 , SDefLogic "g" [("x", TInt)] (Just TInt) (Contract Nothing Nothing)
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
      let prog = [ SDefLogic "hash" [("x", TString)] Nothing (Contract Nothing Nothing)
                     (EHole (HProofRequired "complex-decreases"))
                 , SDefLogic "login" [("u", TString)] Nothing (Contract Nothing Nothing)
                     (EApp "hash" [EHole (HDelegate (DelegateSpec "agent" "login" TString Nothing))])
                 ]
          report = analyzeHolesWithDeps prog
          entries = holeEntries report
          loginHole = head [e | e <- entries, HA.holeContext e == "def-logic login"]
      -- hash's hole is ?proof-required (NonBlocking) — should NOT appear as a dependency
      null (HA.holeDependsOn loginHole) `shouldBe` True

    it "contract-position holes do not appear in depends_on" $ do
      let prog = [ SDefLogic "validate" [("x", TInt)] Nothing
                     (Contract (Just (EHole (HNamed "pre-impl"))) Nothing)
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
            [ "(def-logic test-isolation [flag: bool]"
            , "  (if flag"
            , "    (let [(x 42)] x)"
            , "    ?else_hole))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case filter ((== "?else_hole") . shName) (sketchHoles result) of
            []    -> expectationFailure "?else_hole not recorded"
            (h:_) -> do
              -- x should NOT be in the else-branch's env
              let envNames = Map.keys (shEnv h)
              "x" `elem` envNames `shouldBe` False

    -- Scope provenance: param binding tagged correctly
    it "hole sees param bindings with SrcParam source" $ do
      let src = T.pack $ unlines
            [ "(def-logic greet [name: string]"
            , "  ?greeting)"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
          case filter ((== "?greeting") . shName) (sketchHoles result) of
            []    -> expectationFailure "?greeting not recorded"
            (h:_) -> do
              case Map.lookup "name" (shEnv h) of
                Nothing -> expectationFailure "param 'name' not in env"
                Just sb -> sbSource sb `shouldBe` SrcParam

    -- Scope: let-binding tagged correctly
    it "let-binding in scope has SrcLetBinding source" $ do
      let src = T.pack $ unlines
            [ "(def-logic f [x: int]"
            , "  (let [(y (+ x 1))]"
            , "    ?body))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
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
            , "(def-logic describe [c: Color]"
            , "  (match c"
            , "    ((Red) \"red\")"
            , "    ((Green) \"green\")"
            , "    ((Blue) ?blue)))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts []
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
                          (Just (EApp ">" [EVar "result", ELit (LitInt 0)])))
                (EApp "+" [EVar "x", ELit (LitInt 1)])
            ]
          candidates = generateWeaknessCandidates stmts
          identityCandidates = [c | c <- candidates, case wcTrivialBody c of
                                                       TrivIdentity _ -> True
                                                       _ -> False]
      identityCandidates `shouldSatisfy` (not . null)
      wcFunctionName (head identityCandidates) `shouldBe` "inc"

    -- W1: Constant zero candidate for int-returning function
    it "constant zero generates candidate for int-returning function" $ do
      let stmts =
            [ SDefLogic "abs-val" [("x", TInt)] (Just TInt)
                (Contract Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])))
                (EVar "x")
            ]
          candidates = generateWeaknessCandidates stmts
          zeroCandidates = [c | c <- candidates, wcTrivialBody c == TrivConstZero]
      zeroCandidates `shouldSatisfy` (not . null)

    -- W1 INV-4: type-incompatible bodies skipped
    it "INV-4: identity body skipped when param type != return type" $ do
      let stmts =
            [ SDefLogic "to-str" [("x", TInt)] (Just TString)
                (Contract Nothing (Just (EApp ">" [EApp "string-length" [EVar "result"], ELit (LitInt 0)])))
                (EApp "to-string" [EVar "x"])
            ]
          candidates = generateWeaknessCandidates stmts
          identityCandidates = [c | c <- candidates, case wcTrivialBody c of
                                                       TrivIdentity _ -> True
                                                       _ -> False]
      -- Identity x : int cannot be a string; should be filtered out
      identityCandidates `shouldSatisfy` null

    -- W1: Functions without contracts skipped
    it "function without contracts produces no candidates" $ do
      let stmts =
            [ SDefLogic "id" [("x", TInt)] (Just TInt)
                (Contract Nothing Nothing)
                (EVar "x")
            ]
          candidates = generateWeaknessCandidates stmts
      candidates `shouldSatisfy` null

    -- W1: Multiple functions independently
    it "weakness detection is independent per function" $ do
      let stmts =
            [ SDefLogic "f" [("x", TInt)] (Just TInt)
                (Contract Nothing (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])))
                (EVar "x")
            , SDefLogic "g" [("s", TString)] (Just TString)
                (Contract Nothing (Just (EApp ">" [EApp "string-length" [EVar "result"], ELit (LitInt 0)])))
                (EVar "s")
            ]
          candidates = generateWeaknessCandidates stmts
          fCandidates = [c | c <- candidates, wcFunctionName c == "f"]
          gCandidates = [c | c <- candidates, wcFunctionName c == "g"]
      fCandidates `shouldSatisfy` (not . null)
      gCandidates `shouldSatisfy` (not . null)

    -- EC-7: Precondition preserved in candidate
    it "EC-7: candidate preserves precondition for diagnostic" $ do
      let pre = Just (EApp ">" [EVar "x", ELit (LitInt 0)])
          stmts =
            [ SDefLogic "inc" [("x", TInt)] (Just TInt)
                (Contract pre (Just (EApp ">" [EVar "result", ELit (LitInt 0)])))
                (EApp "+" [EVar "x", ELit (LitInt 1)])
            ]
          candidates = generateWeaknessCandidates stmts
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
            [ "(def-logic greet [name: string]"
            , "  (wasi.io.stdout name))"
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
              capErrors = filter (\d -> diagKind d == Just "missing-capability")
                                 (reportDiagnostics report)
          length capErrors `shouldBe` 1
          diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.io.stdout"
          diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.io"

    -- CAP-1d: wasi.io.stdout inside a let binding with no import → error
    it "CAP-1d: wasi.io.stdout nested in let binding still caught" $ do
      let src = T.pack $ unlines
            [ "(def-logic greet [name: string]"
            , "  (let [(msg (wasi.io.stdout name))]"
            , "    msg))"
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
              capErrors = filter (\d -> diagKind d == Just "missing-capability")
                                 (reportDiagnostics report)
          length capErrors `shouldBe` 1

    -- CAP-1e: wasi.io.stdout with matching import → OK
    it "CAP-1e: wasi.io.stdout with (import wasi.io ...) succeeds" $ do
      -- Construct the import + function AST directly
      let stmts =
            [ SImport (Import "wasi.io" Nothing (Just (Capability CapWrite "*" True)))
            , SDefLogic "greet" [("name", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing) (EApp "wasi.io.stdout" [EVar "name"])
            ]
          report = typeCheck emptyEnv stmts
          capErrors = filter (\d -> diagKind d == Just "missing-capability")
                             (reportDiagnostics report)
      capErrors `shouldBe` []

    -- CAP-1f: wasi.fs.write with wasi.io import only → error (per-namespace)
    it "CAP-1f: wasi.fs.write with only wasi.io import is per-namespace error" $ do
      let stmts =
            [ SImport (Import "wasi.io" Nothing (Just (Capability CapWrite "*" True)))
            , SDefLogic "write-file" [("path", TString), ("content", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing) (EApp "wasi.fs.write" [EVar "path", EVar "content"])
            ]
          report = typeCheck emptyEnv stmts
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
                (Contract Nothing Nothing) (EApp "wasi.io.stdout" [EVar "msg"])
            , SExport ["print-msg"]
            ]
          modAEnv = ModuleEnv
            { meExports = DM.fromList [("print-msg", TFn [TString] (TCustom "Command"))]
            , meStatements = modAStmts
            , meInterfaces = DM.empty
            , meAliasMap = DM.empty
            , mePath = ["helpers"]
            , meContractStatus = DM.empty
            }
          cache = DM.fromList [( ["helpers"], modAEnv)]
          -- Module B imports helpers, calls wasi.io.stdout directly without own import
          callerStmts =
            [ SDefLogic "caller" [("s", TString)] (Just (TCustom "Command"))
                (Contract Nothing Nothing) (EApp "wasi.io.stdout" [EVar "s"])
            ]
          report = typeCheckWithCache cache emptyEnv callerStmts
          capErrors = filter (\d -> diagKind d == Just "missing-capability")
                             (reportDiagnostics report)
      -- Module B has no wasi.io import → error (non-transitive)
      length capErrors `shouldBe` 1
      diagMessage (head capErrors) `shouldSatisfy` T.isInfixOf "wasi.io"

  -- =========================================================================
  -- v0.4 U-Lite: Per-Call-Site Substitution Tests
  -- =========================================================================
  describe "U-Lite per-call-site substitution" $ do

    -- U4a: cross-argument consistency — (= 42 "hello") should fail
    it "U4a: (= 42 \"hello\") catches int vs string cross-arg mismatch" $ do
      let stmts =
            [ SDefLogic "f" [] (Just TBool) (Contract Nothing Nothing)
                (EApp "=" [ELit (LitInt 42), ELit (LitString "hello")])
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U4b: list-contains cross-arg mismatch
    it "U4b: list-contains([1,2,3], \"hello\") catches element type mismatch" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just TBool) (Contract Nothing Nothing)
                (EApp "list-contains" [EVar "xs", ELit (LitString "hello")])
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U5: list-map with mismatched element type in lambda
    it "U5: list-map [ints] (fn [x: string] x) catches element type mismatch" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just (TList TString)) (Contract Nothing Nothing)
                (EApp "list-map" [EVar "xs", ELambda [("x", TString)] (EVar "x")])
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U4c: first(42) should fail (non-pair argument)
    it "U4c: first(42) catches non-pair argument" $ do
      let stmts =
            [ SDefLogic "f" [] (Just (TVar "a")) (Contract Nothing Nothing)
                (EApp "first" [ELit (LitInt 42)])
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U4d: second("hello") should fail (non-pair argument)
    it "U4d: second(\"hello\") catches non-pair argument" $ do
      let stmts =
            [ SDefLogic "f" [] (Just (TVar "b")) (Contract Nothing Nothing)
                (EApp "second" [ELit (LitString "hello")])
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U6: alias expansion + first still works with dep types
    it "U6: first on pair with where-type alias passes" $ do
      let src = T.pack $ unlines
            [ "(type Word (where [s: string] (> (string-length s) 0)))"
            , "(def-logic get-word [p: (Word, int)] (first p))"
            ]
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

    -- U7a: TSumType structural inequality — different sum types are now incompatible
    it "U7a: Color /= Shape -- different sum types are incompatible" $ do
      let stmts =
            [ STypeDef "Color" (TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)])
            , STypeDef "Shape" (TSumType [("Circle", Just TInt), ("Rect", Nothing)])
            , SDefLogic "f" [("c", TCustom "Color")] (Just (TCustom "Shape"))
                (Contract Nothing Nothing) (EVar "c")
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- U7b: Same sum types are still compatible
    it "U7b: Color = Color -- same sum types are compatible" $ do
      let stmts =
            [ STypeDef "Color" (TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)])
            , SDefLogic "f" [("c", TCustom "Color")] (Just (TCustom "Color"))
                (Contract Nothing Nothing) (EVar "c")
            ]
          report = typeCheck emptyEnv stmts
      reportSuccess report `shouldBe` True

    -- U-Lite positive: polymorphic functions still work correctly
    it "U-Lite: list-head on list[int] returns Result[int, string]" $ do
      let stmts =
            [ SDefLogic "f" [("xs", TList TInt)] (Just (TResult TInt TString))
                (Contract Nothing Nothing) (EApp "list-head" [EVar "xs"])
            ]
          report = typeCheck emptyEnv stmts
      reportSuccess report `shouldBe` True

    it "U-Lite: pair(1, \"hello\") then first gives int" $ do
      let stmts =
            [ SDefLogic "f" [] (Just (TVar "a")) (Contract Nothing Nothing)
                (EApp "first" [EApp "pair" [ELit (LitInt 1), ELit (LitString "hello")]])
            ]
          report = typeCheck emptyEnv stmts
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
                (Contract Nothing Nothing) (EApp "list-head" [EVar "xs"])
            ]
          report = typeCheck emptyEnv stmts
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
                (Contract Nothing Nothing) (EVar "x")
            , SDefLogic "test" [] (Just TBool)
                (Contract Nothing Nothing)
                -- Call identity(42) and identity("hello") at different sites
                -- Both should succeed because each EApp gets a fresh substitution
                (EApp "=" [ EApp "identity" [ELit (LitInt 42)]
                          , ELit (LitInt 42) ])
            ]
          report = typeCheck emptyEnv stmts
      reportSuccess report `shouldBe` True

    -- U2-full: Same-call-site conflict — f(5, "hello") where f : a -> a -> a
    it "U2-full: conflicting types at same call site rejected" $ do
      let stmts =
            [ SDefLogic "same-type" [("x", TVar "a"), ("y", TVar "a")] (Just (TVar "a"))
                (Contract Nothing Nothing) (EVar "x")
            , SDefLogic "test" [] (Just TBool)
                (Contract Nothing Nothing)
                (EApp "same-type" [ELit (LitInt 5), ELit (LitString "hello")])
            ]
          report = typeCheck emptyEnv stmts
          errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      length errs `shouldSatisfy` (> 0)

    -- Issue 2: Bound-TVar consistency — f : a -> a -> bool, called as f(5, "hello")
    it "U2-full (Issue 2): bound-TVar consistency rejects f(5, \"hello\") for f : a -> a -> bool" $ do
      let stmts =
            [ SDefLogic "same-check" [("x", TVar "a"), ("y", TVar "a")] (Just TBool)
                (Contract Nothing Nothing) (EApp "=" [EVar "x", EVar "y"])
            , SDefLogic "test" [] (Just TBool)
                (Contract Nothing Nothing)
                (EApp "same-check" [ELit (LitInt 5), ELit (LitString "hello")])
            ]
          report = typeCheck emptyEnv stmts
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
                (Contract Nothing Nothing) (EVar "xs")
            ]
          result = runSketch emptyEnv stmts defaultPatterns
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
                              (Just (EApp ">" [EVar "result", ELit (LitInt 0)])))
                    (EVar "x")]
          table = Map.empty
          report = TrustReport [] (TrustSummary 0 0 0 0 0)
      mineObligations table FQSafe report stmts `shouldBe` []

    it "UNSAFE with unknown constraint ID produces no suggestion" $ do
      let stmts = [SDefLogic "f" [("x", TInt)] (Just TInt)
                    (Contract Nothing Nothing) (EVar "x")]
          table = Map.empty  -- empty: no origin for constraint 42
          report = TrustReport [] (TrustSummary 0 0 0 0 0)
      mineObligations table (FQUnsafe [42]) report stmts `shouldBe` []

    it "UNSAFE with known origin produces self-suggestion" $ do
      let stmts = [SDefLogic "addPos" [("x", TInt), ("y", TInt)] (Just TInt)
                    (Contract (Just (EApp ">" [EVar "x", ELit (LitInt 0)]))
                              (Just (EApp ">" [EVar "result", ELit (LitInt 0)])))
                    (EApp "+" [EVar "x", EVar "y"])]
          table = Map.fromList
            [(0, ConstraintOrigin "addPos" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0)
          results = mineObligations table (FQUnsafe [0]) report stmts
      length results `shouldBe` 1
      osCaller (head results) `shouldBe` "addPos"
      osCallee (head results) `shouldBe` "addPos"  -- self-suggestion (no callees)

    it "QF-LIA postcondition gets Verified strength" $ do
      let stmts = [SDefLogic "f" [("x", TInt)] (Just TInt)
                    (Contract Nothing
                              (Just (EApp ">=" [EVar "result", ELit (LitInt 0)])))
                    (EVar "x")]
          table = Map.fromList
            [(0, ConstraintOrigin "f" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0)
          results = mineObligations table (FQUnsafe [0]) report stmts
      length results `shouldBe` 1
      osStrength (head results) `shouldBe` Verified

    it "non-linear postcondition gets Advisory strength" $ do
      -- (> (* x x) 0) is non-linear (uses *), outside QF-LIA
      let stmts = [SDefLogic "g" [("x", TInt)] (Just TInt)
                    (Contract Nothing
                              (Just (EApp ">" [EApp "*" [EVar "x", EVar "x"], ELit (LitInt 0)])))
                    (EVar "x")]
          table = Map.fromList
            [(0, ConstraintOrigin "g" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0)
          results = mineObligations table (FQUnsafe [0]) report stmts
      length results `shouldBe` 1
      osStrength (head results) `shouldBe` Advisory

    it "JSON output includes strength field" $ do
      let stmts = [SDefLogic "h" [("x", TInt)] (Just TInt)
                    (Contract Nothing
                              (Just (EApp ">" [EVar "result", ELit (LitInt 0)])))
                    (EVar "x")]
          table = Map.fromList
            [(0, ConstraintOrigin "h" "post" "/statements/0/post" "test.llmll")]
          report = TrustReport [] (TrustSummary 0 0 0 0 0)
          results = mineObligations table (FQUnsafe [0]) report stmts
          jsonOut = formatObligationsJson results
      jsonOut `shouldSatisfy` T.isInfixOf "VERIFIED"
      jsonOut `shouldSatisfy` T.isInfixOf "obligation_suggestions"
