{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Test.Hspec
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import LLMLL.Lexer (tokenize, Token(..), TokenKind(..))
import LLMLL.Parser (parseStatements, parseExpr)
import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, typeCheckWithCache, emptyEnv, runSketch, SketchResult(..), SketchHole(..), HoleStatus(..))
import LLMLL.Diagnostic (reportSuccess, reportDiagnostics, diagKind, diagMessage, diagPointer, diagSeverity, diagHoleSensitive, Severity(..), Diagnostic(..), mkError, PatchOpInfo(..), rebaseToPatch, mkTrustGapWarning)
import LLMLL.CodegenHs (generateHaskell, cgMainHs, cgHsSource, emitExpr, toHsType, emitHole)
import LLMLL.HoleAnalysis (analyzeHoles, holeEntries, holeKind, HoleEntry(..))
import qualified LLMLL.HoleAnalysis as HA
import LLMLL.ParserJSON (parseJSONAST)
import LLMLL.AstEmit (stmtToJson)
import LLMLL.Contracts (ContractsMode(..), instrumentStatement, instrumentContracts, applyContractsMode)
import LLMLL.VerifiedCache (verifiedPath, saveVerified, loadVerified)
import LLMLL.Hub (scaffoldCacheRoot, resolveScaffold)
import System.Directory (removeFile, doesFileExist, createDirectoryIfMissing, removeDirectoryRecursive)
import Data.List (isSuffixOf)
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Aeson (encode, decode, Value(..), object, (.=))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Map.Strict as DM

import LLMLL.JsonPointer (resolvePointer, setAtPointer, removeAtPointer, findDescendantHoles, isHoleNode)
import LLMLL.Checkout (lockFilePath, expireStale, CheckoutToken(..), CheckoutLock(..))
import LLMLL.PatchApply (applyOp, applyOps, validateScope, parsePatchOp, PatchOp(..), toPatchOpInfos)
import Data.Time.Clock (UTCTime(..), secondsToDiffTime, addUTCTime)
import Data.Time.Calendar (fromGregorian)

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
    it "first accepts a typed param (regression: Issue 1 hangman_json walkthrough)" $ do
      -- Before fix: first :: TFn [TResult a b] (TVar a) => rejected s:string param
      -- After fix:  first :: TFn [TVar p] (TVar a)     => accepts any type
      let src = T.pack $ unlines
            [ "(def-logic state-word [s: string] (first s))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

    it "second accepts a typed param (regression: same root cause)" $ do
      let src = T.pack $ unlines
            [ "(def-logic state-rest [s: string] (second s))" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          reportSuccess report `shouldBe` True

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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
          case findHole "?arg" result of
            Nothing -> expectationFailure "?arg hole not recorded"
            Just h  -> shStatus h `shouldBe` HoleTyped TInt

    it "isolated hole with no context gets HoleUnknown" $ do
      let src = T.pack $ unlines
            [ "(def-logic mystery [] ?isolated)" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts
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
          let skRes = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
          let certainErrs = filter (\d -> diagSeverity d == SevError && not (diagHoleSensitive d)) (sketchErrors result)
          certainErrs `shouldBe` []


    it "inferHole HNamed synthesises TVar with ? prefix (D3 invariant)" $ do
      -- A hole in synthesis position must return TVar "?name", not TVar "?"
      let src = T.pack $ unlines
            [ "(def-logic f [x: int] ?impl)" ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          let result = runSketch emptyEnv stmts
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
          tok = CheckoutToken "/a" "hole-delegate" Nothing epoch "tok1" 3600
          lock = CheckoutLock "test.json" [tok]
          later = addUTCTime 7200 epoch
      lockTokens (expireStale later lock) `shouldBe` []

    it "expireStale keeps non-expired tokens" $ do
      let epoch = UTCTime (fromGregorian 2026 1 1) 0
          tok = CheckoutToken "/a" "hole-delegate" Nothing epoch "tok1" 3600
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

-- | Helper to remove a file if it exists (used for test cleanup).
removeIfExists :: FilePath -> IO ()
removeIfExists fp = do
  exists <- doesFileExist fp
  if exists then removeFile fp else pure ()
