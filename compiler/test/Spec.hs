{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Test.Hspec
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import LLMLL.Lexer (tokenize, Token(..), TokenKind(..))
import LLMLL.Parser (parseStatements, parseExpr)
import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, emptyEnv, runSketch, SketchResult(..), SketchHole(..), HoleStatus(..))
import LLMLL.Diagnostic (reportSuccess, reportDiagnostics, diagKind, diagMessage, diagSeverity, Severity(..))
import LLMLL.CodegenHs (generateHaskell, cgMainHs, cgHsSource)
import LLMLL.HoleAnalysis (analyzeHoles, holeEntries, holeKind)
import LLMLL.ParserJSON (parseJSONAST)
import LLMLL.AstEmit (stmtToJson)
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Aeson (encode, decode, Value(..))
import qualified Data.Map.Strict as DM

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

    it "S-expression: pair-type parameter parsed as TResult TInt TString" $ do
      let src = "(def-logic f [acc: (int, string)] (first acc))"
      case parseStatements "<test>" src of
        Left err -> expectationFailure (show err)
        Right [SDefLogic _ params _ _ _] ->
          snd (head params) `shouldBe` TResult TInt TString
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

    it "JSON-AST: pair-type param_type decodes to TResult TInt TString" $ do
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
          snd (head params) `shouldBe` TResult TInt TString
        Right other -> expectationFailure $ "Expected SDefLogic, got " ++ show (length other) ++ " stmts"

  -- -----------------------------------------------------------------------
  -- N2: string-concat arity hint
  -- -----------------------------------------------------------------------
  describe "N2 string-concat arity hint" $ do
    it "string-concat with 3 args emits error mentioning string-concat-many" $ do
      let src = T.pack $ unlines
            [ "(def-logic f [a: string b: string c: string]"
            , "  (string-concat a b c))"
            ]
      case parseStatements "<test>" src of
        Left err    -> expectationFailure (show err)
        Right stmts -> do
          let report = typeCheck emptyEnv stmts
          let errs = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
          length errs `shouldBe` 1
          diagMessage (head errs) `shouldSatisfy` T.isInfixOf "string-concat-many"

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


