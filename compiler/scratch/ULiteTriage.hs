-- | U-Lite Regression Triage: diagnostic-only scan of type errors
-- that the current wildcard-based compatibleWith silently accepts.
-- Run with: stack runghc compiler/test/ULiteTriage.hs
{-# LANGUAGE OverloadedStrings #-}
module Main where

import qualified Data.Text as T
import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, emptyEnv)
import LLMLL.Diagnostic (reportSuccess, reportDiagnostics, diagSeverity, diagMessage, Severity(..))

-- | A test case: name, statements, expected_passes_currently, should_fail_under_ulite
data TriageCase = TriageCase
  { tcName :: String
  , tcStmts :: [Statement]
  , tcCategory :: String  -- "cross-arg" | "first-second" | "sum-type" | "return-type"
  }

triage :: [TriageCase]
triage =
  -- Cross-argument consistency bugs
  [ TriageCase "equal(42, \"hello\"): int vs string"
      [ SDefLogic "f" [] (Just TBool) (Contract Nothing Nothing)
          (EApp "=" [ELit (LitInt 42), ELit (LitString "hello")])
      ] "cross-arg"

  , TriageCase "list-contains([1,2,3], \"hello\"): list[int] elem vs string"
      [ SDefLogic "f" [("xs", TList TInt)] (Just TBool) (Contract Nothing Nothing)
          (EApp "list-contains" [EVar "xs", ELit (LitString "hello")])
      ] "cross-arg"

  , TriageCase "list-append([1,2,3], \"hello\"): list[int] elem vs string"
      [ SDefLogic "f" [("xs", TList TInt)] (Just (TList TInt)) (Contract Nothing Nothing)
          (EApp "list-append" [EVar "xs", ELit (LitString "hello")])
      ] "cross-arg"

  , TriageCase "list-prepend(\"hello\", [1,2,3]): string elem vs list[int]"
      [ SDefLogic "f" [("xs", TList TInt)] (Just (TList TInt)) (Contract Nothing Nothing)
          (EApp "list-prepend" [ELit (LitString "hello"), EVar "xs"])
      ] "cross-arg"

  , TriageCase "unwrap-or(ok-val, \"fallback\"): Result[int,e] with string default"
      [ SDefLogic "f" [("r", TResult TInt TString)] (Just TInt) (Contract Nothing Nothing)
          (EApp "unwrap-or" [EVar "r", ELit (LitString "fallback")])
      ] "cross-arg"

  -- first/second retype bugs
  , TriageCase "first(42): int is not a pair"
      [ SDefLogic "f" [] (Just (TVar "a")) (Contract Nothing Nothing)
          (EApp "first" [ELit (LitInt 42)])
      ] "first-second"

  , TriageCase "second(\"hello\"): string is not a pair"
      [ SDefLogic "f" [] (Just (TVar "b")) (Contract Nothing Nothing)
          (EApp "second" [ELit (LitString "hello")])
      ] "first-second"

  -- TSumType wildcarding bugs
  , TriageCase "Color where GameInput expected: different sum types"
      [ STypeDef "Color" (TSumType [("Red", Nothing), ("Green", Nothing), ("Blue", Nothing)])
      , STypeDef "Shape" (TSumType [("Circle", Just TInt), ("Rect", Nothing)])
      , SDefLogic "f" [("c", TCustom "Color")] (Just (TCustom "Shape")) (Contract Nothing Nothing)
          (EVar "c")
      ] "sum-type"

  -- list-head on non-list (verify this IS already caught)
  , TriageCase "list-head(42): int is not a list"
      [ SDefLogic "f" [] (Just (TResult TInt TString)) (Contract Nothing Nothing)
          (EApp "list-head" [ELit (LitInt 42)])
      ] "non-list"

  -- list-map element mismatch
  , TriageCase "list-map([1,2,3], fn[x:string]x): element type mismatch"
      [ SDefLogic "f" [("xs", TList TInt)] (Just (TList TString)) (Contract Nothing Nothing)
          (EApp "list-map" [EVar "xs", ELambda [("x", TString)] (EVar "x")])
      ] "cross-arg"
  ]

main :: IO ()
main = do
  putStrLn "=== U-Lite Regression Triage ==="
  putStrLn ""
  mapM_ runCase triage
  putStrLn ""
  putStrLn "=== Summary ==="
  let silentBugs = filter (\tc -> passesCurrently tc) triage
  putStrLn $ "Silent type errors (currently pass, U-Lite would catch): " ++ show (length silentBugs)
  mapM_ (\tc -> putStrLn $ "  [BUG] " ++ tcName tc ++ " (" ++ tcCategory tc ++ ")") silentBugs
  let alreadyCaught = filter (\tc -> not (passesCurrently tc)) triage
  putStrLn $ "Already caught (no U-Lite change needed): " ++ show (length alreadyCaught)
  mapM_ (\tc -> putStrLn $ "  [OK]  " ++ tcName tc) alreadyCaught

passesCurrently :: TriageCase -> Bool
passesCurrently tc =
  let report = typeCheck emptyEnv (tcStmts tc)
      errors = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
  in null errors

runCase :: TriageCase -> IO ()
runCase tc = do
  let report = typeCheck emptyEnv (tcStmts tc)
      errors = filter (\d -> diagSeverity d == SevError) (reportDiagnostics report)
      warnings = filter (\d -> diagSeverity d == SevWarning) (reportDiagnostics report)
      status = if null errors then "PASSES (silent bug)" else "FAILS (already caught)"
  putStrLn $ "[" ++ tcCategory tc ++ "] " ++ tcName tc
  putStrLn $ "  Status: " ++ status
  mapM_ (\d -> putStrLn $ "  Error: " ++ T.unpack (diagMessage d)) errors
  mapM_ (\d -> putStrLn $ "  Warn:  " ++ T.unpack (diagMessage d)) warnings
  putStrLn ""
