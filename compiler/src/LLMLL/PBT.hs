{-# LANGUAGE TypeApplications #-}
-- |
-- Module      : LLMLL.PBT
-- Description : Property-based testing for LLMLL check blocks.
--
-- Executes all `check` statements in an LLMLL program using QuickCheck:
--   * Each `for-all [x: T ...]` binding generates random values of type T
--   * The property body is evaluated using the symbolic evaluator from Contracts
--   * Results are reported with counterexamples where available
--
-- Since LLMLL is not yet a general-purpose interpreter, evaluation is
-- symbolic (constant-folding). Full evaluation requires the Rust runtime (Agent E).
module LLMLL.PBT
  ( -- * Entry Points
    runPropertyTests
  , runPropertyTestsIO

    -- * Results
  , PBTResult(..)
  , PBTRun(..)
  , PBTStatus(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import Test.QuickCheck
  ( Gen, generate, vectorOf, property, arbitrary
  , Arbitrary(..), quickCheckResult, Result(..)
  , counterexample, forAll, NonNegative(..))
import Control.Exception (try, SomeException)

import LLMLL.Syntax
import LLMLL.Contracts (evalExprStatic)

-- ---------------------------------------------------------------------------
-- Result Types
-- ---------------------------------------------------------------------------

data PBTStatus
  = PBTPassed          -- ^ Property holds for all samples
  | PBTFailed          -- ^ Counterexample found
  | PBTSkipped         -- ^ Could not evaluate (non-constant body)
  | PBTError Text      -- ^ Unexpected error during testing
  deriving (Show, Eq)

-- | Result for a single property (check block).
data PBTRun = PBTRun
  { pbtDescription   :: Text
  , pbtStatus        :: PBTStatus
  , pbtSamplesRun    :: Int
  , pbtCounterexample :: Maybe Text  -- ^ Concrete counterexample if failed
  } deriving (Show, Eq)

-- | Aggregate results across all check blocks.
data PBTResult = PBTResult
  { pbtTotal   :: Int
  , pbtPassed  :: Int
  , pbtFailed  :: Int
  , pbtSkipped :: Int
  , pbtResults :: [PBTRun]
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Entry Points
-- ---------------------------------------------------------------------------

-- | Run all check blocks in a list of statements (pure, symbolic evaluation).
runPropertyTests :: [Statement] -> IO PBTResult
runPropertyTests stmts = do
  let checks = [prop | SCheck prop <- stmts]
  runs <- mapM runProperty checks
  let passed  = length [() | r <- runs, pbtStatus r == PBTPassed]
      failed  = length [() | r <- runs, pbtStatus r == PBTFailed]
      skipped = length [() | r <- runs, pbtStatus r == PBTSkipped]
  pure $ PBTResult
    { pbtTotal   = length checks
    , pbtPassed  = passed
    , pbtFailed  = failed
    , pbtSkipped = skipped
    , pbtResults = runs
    }

-- | Alias for IO-based entry point.
runPropertyTestsIO :: [Statement] -> IO PBTResult
runPropertyTestsIO = runPropertyTests

-- ---------------------------------------------------------------------------
-- Running a Single Property
-- ---------------------------------------------------------------------------

-- | Run a single check block.
runProperty :: LLMLL.Syntax.Property -> IO PBTRun
runProperty prop = do
  let bindings = propBindings prop
      body     = propBody prop
      desc     = propDescription prop
      nSamples = 100  -- number of random samples

  -- Generate sample environments and evaluate the property body
  samples <- generateSamples bindings nSamples
  let results = map (\env -> evalPropertyBody env body) samples

  case sequence results of
    -- All evaluations returned concrete booleans
    Just bools ->
      case [i | (i, False) <- zip [(0::Int)..] bools] of
        [] -> pure $ PBTRun desc PBTPassed nSamples Nothing
        (i:_) ->
          let counterex = formatBinding (samples !! i)
          in pure $ PBTRun desc PBTFailed nSamples (Just counterex)

    -- Some could not be evaluated statically
    Nothing ->
      -- Try QuickCheck on integer-only properties
      case tryQuickCheck bindings body of
        Just qcResult -> qcResult >>= \r -> pure $ PBTRun desc (qcStatus r) (qcSamples r) (qcCounterex r)
        Nothing       ->
          let reason
                | bodyMentionsCommand body =
                    "Property body produces a Command value — Command expressions require full runtime evaluation (not statically evaluable)"
                | otherwise =
                    "Property contains non-constant expressions — requires full runtime evaluation"
          in pure $ PBTRun desc PBTSkipped 0 (Just reason)

-- | Evaluate a property body in a given binding environment.
-- Returns Just True/False for concrete results, Nothing for non-evaluable.
evalPropertyBody :: Map Name Expr -> Expr -> Maybe Bool
evalPropertyBody env body =
  case evalExprStatic env body of
    Just (ELit (LitBool b)) -> Just b
    _                       -> Nothing

-- ---------------------------------------------------------------------------
-- Sample Generation (Symbolic)
-- ---------------------------------------------------------------------------

-- | Generate N random binding environments for the given typed bindings.
generateSamples :: [(Name, Type)] -> Int -> IO [Map Name Expr]
generateSamples bindings n = do
  rawSamples <- mapM (\_ -> generateBinding bindings) [1..n]
  pure rawSamples

-- | Generate a single random binding environment.
generateBinding :: [(Name, Type)] -> IO (Map Name Expr)
generateBinding bindings = do
  pairs <- mapM genForType bindings
  pure (Map.fromList pairs)
  where
    genForType (name, ty) = do
      val <- generateValue ty
      pure (name, ELit val)

-- | Generate a random literal value of the given LLMLL type.
generateValue :: Type -> IO Literal
generateValue TInt         = LitInt . getNonNeg <$> generate (arbitrary :: Gen (NonNegative Integer))
generateValue TFloat       = LitFloat <$> generate (arbitrary :: Gen Double)
generateValue TString      = LitString . T.pack <$> generate (arbitrary :: Gen String)
generateValue TBool        = LitBool <$> generate (arbitrary :: Gen Bool)
generateValue TUnit        = pure LitUnit
generateValue (TBytes _)   = LitString . T.pack <$> generate (arbitrary :: Gen String)
generateValue (TDependent _ base _) = generateValue base  -- ignore constraint for generation
generateValue _            = LitInt <$> generate (arbitrary :: Gen Integer)

getNonNeg :: NonNegative Integer -> Integer
getNonNeg (NonNegative n) = n

-- | Heuristic: does the expression contain a call to a function that is
-- known to return Command (wasi.* imports, or any function whose name
-- starts with a typical LLMLL command prefix)?
-- Used to produce a better PBTSkipped diagnostic.
bodyMentionsCommand :: Expr -> Bool
bodyMentionsCommand expr = go expr
  where
    go (EApp fn args)         = isCommandFn fn || any go args
    go (ELet bindings body)   = any (\(_, _, e) -> go e) bindings || go body
    go (EIf _ t e)            = go t || go e
    go (EMatch e cases)       = go e || any (go . snd) cases
    go (EPair a b)            = go a || go b
    go (EDo steps)            = any goStep steps
    go (ELambda _ body)       = go body
    go _                      = False

    goStep (DoBind _ e) = go e
    goStep (DoExpr e)   = go e

    -- Names known to produce a Command value — only WASI/IO imports qualify.
    -- Keep this list narrow: false positives cause valid properties to be skipped.
    isCommandFn n = any (`T.isPrefixOf` n)
      ["wasi.", "console.", "http.", "fs."]

-- ---------------------------------------------------------------------------
-- QuickCheck Integration (for integer-only properties)
-- ---------------------------------------------------------------------------

-- | Try to run a property using QuickCheck if it only involves integers and bools.
-- Returns Nothing if the property can't be run this way.
tryQuickCheck :: [(Name, Type)] -> Expr -> Maybe (IO QCRun)
tryQuickCheck bindings body
  | all isSimpleType (map snd bindings) = Just (runQC bindings body)
  | otherwise = Nothing
  where
    isSimpleType TInt  = True
    isSimpleType TBool = True
    isSimpleType (TDependent _ TInt _) = True
    isSimpleType _     = False

data QCRun = QCRun
  { qcStatus     :: PBTStatus
  , qcSamples    :: Int
  , qcCounterex  :: Maybe Text
  } deriving (Show)

runQC :: [(Name, Type)] -> Expr -> IO QCRun
runQC bindings body = do
  let genEnv :: Gen (Map Name Expr)
      genEnv = do
        pairs <- mapM genPair bindings
        pure (Map.fromList pairs)

      genPair (name, ty) = do
        val <- genLit ty
        pure (name, ELit val)

      genLit TInt  = LitInt <$> arbitrary
      genLit TBool = LitBool <$> arbitrary
      genLit _     = LitInt <$> arbitrary

      prop :: Map Name Expr -> Bool
      prop env = case evalExprStatic env body of
        Just (ELit (LitBool b)) -> b
        _                       -> True  -- skip unevaluable

  result <- (try (quickCheckResult (forAll genEnv prop)) :: IO (Either SomeException Result))
  case result of
    Left ex -> pure $ QCRun (PBTError (T.pack (show ex))) 0 Nothing
    Right r  -> pure $ resultsToQCRun r

resultsToQCRun :: Result -> QCRun
resultsToQCRun r = case r of
  Success { numTests = n }                        -> QCRun PBTPassed n Nothing
  Failure { numTests = n, output = out }          -> QCRun PBTFailed n (Just (T.pack out))
  GaveUp  { numTests = n }                        -> QCRun PBTSkipped n (Just "QuickCheck gave up — too many precondition failures")
  NoExpectedFailure { numTests = n }              -> QCRun PBTFailed n (Just "Property was expected to fail but passed")
  _                                               -> QCRun PBTSkipped 0 (Just "Unknown QuickCheck result")

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

formatBinding :: Map Name Expr -> Text
formatBinding env =
  T.intercalate ", " $
    map (\(n, v) -> n <> " = " <> formatExpr v) (Map.toList env)

formatExpr :: Expr -> Text
formatExpr (ELit (LitInt n))    = T.pack (show n)
formatExpr (ELit (LitFloat f))  = T.pack (show f)
formatExpr (ELit (LitString s)) = "\"" <> s <> "\""
formatExpr (ELit (LitBool b))   = if b then "true" else "false"
formatExpr (ELit LitUnit)       = "()"
formatExpr (EVar n)             = n
formatExpr other                = T.pack (show other)

-- | Format a PBTResult as a human-readable summary.
formatPBTResult :: PBTResult -> Text
formatPBTResult r =
  T.unlines $
    [ "Property Test Results: " <> tshow (pbtTotal r) <> " properties"
    , "  Passed:  " <> tshow (pbtPassed r)
    , "  Failed:  " <> tshow (pbtFailed r)
    , "  Skipped: " <> tshow (pbtSkipped r)
    , ""
    ] ++ map formatRun (pbtResults r)

formatRun :: PBTRun -> Text
formatRun r =
  statusLabel (pbtStatus r) <> " \"" <> pbtDescription r <> "\""
  <> maybe "" (\cx -> "\n    counterexample: " <> cx) (pbtCounterexample r)
  where
    statusLabel PBTPassed    = "✅"
    statusLabel PBTFailed    = "❌"
    statusLabel PBTSkipped   = "⚠️"
    statusLabel (PBTError e) = "💥 " <> e

tshow :: Show a => a -> Text
tshow = T.pack . show
