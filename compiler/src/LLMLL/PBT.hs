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

    -- * Driver helpers
  , assembleTestStatements

    -- * Results
  , PBTResult(..)
  , PBTRun(..)
  , PBTStatus(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import qualified Test.QuickCheck as QC
import Test.QuickCheck
  ( Gen, generate, vectorOf, arbitrary, choose
  , Arbitrary(..), quickCheckResult, Result(..)
  , counterexample, forAll, NonNegative(..))
import Control.Exception (try, SomeException)

import LLMLL.Syntax
import LLMLL.Contracts (evalExprStaticWith, FuncEnv, buildFuncEnv, maxFuel)

-- ---------------------------------------------------------------------------
-- Type-alias environment (OBLIG-PBT-2 / F-032)
-- ---------------------------------------------------------------------------

-- | Map from user-defined type name to its underlying type body. Built from
-- the module's 'STypeDef' statements so 'generateValue' can resolve 'TCustom'
-- references (e.g. @(type Ledger (Accounts, TransactionLog))@) before
-- generating samples.
type TypeAliasEnv = Map Name Type

-- | Build the alias env from a statement list.
buildTypeAliasEnv :: [Statement] -> TypeAliasEnv
buildTypeAliasEnv stmts = Map.fromList
  [ (n, body) | STypeDef n body <- stmts ]

-- | Resolve a 'TCustom' name through the alias env, with a cycle guard.
-- Mirrors 'LLMLL.TypeCheck.expandAlias' in pure form (no TC monad), bounded
-- by 'maxAliasDepth' to keep generation termination certain on self-referential
-- aliases (e.g. @(type Tree (list[Tree]))@).
expandAliasPure :: TypeAliasEnv -> Type -> Type
expandAliasPure aliases = go Set.empty
  where
    go seen (TCustom n)
      | Set.member n seen = TCustom n              -- cycle detected; stop
      | Just body <- Map.lookup n aliases = go (Set.insert n seen) body
      | otherwise = TCustom n                       -- unknown alias; pass through
    go _ ty = ty

-- | Maximum depth for recursive type generation (e.g. lists of pairs of lists).
-- Combined with 'listMaxLen' this bounds generator runtime for arbitrarily
-- nested type expressions.
maxGenDepth :: Int
maxGenDepth = 5

-- | Maximum list length the generator will emit. Small constant keeps
-- per-sample evaluation cheap; QuickCheck's existing shrinking is not in
-- scope for the static-eval path.
listMaxLen :: Int
listMaxLen = 8

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
-- Driver helpers
-- ---------------------------------------------------------------------------

-- | Assemble the statement list that the PBT runner should see, given the
-- local module's statements and the module cache produced by
-- 'LLMLL.Module.loadModule' / 'loadStatementsMulti'.
--
-- F-018 / MOD-PBT-1: extends PBT FuncEnv visibility to honor @(open path)@ —
-- imported modules' @def-logic@ declarations are concatenated ahead of the
-- local statement list so that 'buildFuncEnv' (which extracts SDefLogic only)
-- picks them up. Restrictions:
--
--   * Only 'SDefLogic' is forwarded from imports — 'SCheck' blocks and
--     'SDefInterface' laws from imported modules stay with their owning
--     module; running them from @llmll test local.llmll@ would surprise the
--     user (their own test target).
--   * Each forwarded name must be in 'meExports' of the source module
--     (respects the imported module's @(export ...)@ clause).
--   * If @(open path (names))@ restricts the open, only those names are
--     forwarded.
--   * Imports come first, local stmts last — 'Map.fromList' right-bias gives
--     local-shadows-import semantics matching the type-checker.
--
-- Qualified-name resolution (@solution.plus-one@) is intentionally out of
-- scope: per @LLMLL.md §8.5@, qualified names do not resolve at runtime
-- under the flat-codegen model; PBT honoring them would over-promise
-- relative to the rest of the runtime.
assembleTestStatements :: [Statement] -> ModuleCache -> [Statement]
assembleTestStatements localStmts cache =
  let openSpecs   = [(openPath o, openNames o) | o@SOpen{} <- localStmts]
      importedDLs = concatMap importedDefLogics openSpecs
  in importedDLs ++ localStmts
  where
    importedDefLogics (path, mNames) =
      case Map.lookup path cache of
        Nothing   -> []
        Just menv ->
          let nameFilter = case mNames of
                Nothing -> const True
                Just ns -> let s = Set.fromList ns in (`Set.member` s)
              isExported n = Map.member n (meExports menv)
          in [ s | s@SDefLogic{defLogicName = n} <- meStatements menv
                 , isExported n
                 , nameFilter n
                 ]

-- ---------------------------------------------------------------------------
-- Entry Points
-- ---------------------------------------------------------------------------

-- | Run all check blocks and interface laws in a list of statements (pure, symbolic evaluation).
runPropertyTests :: [Statement] -> IO PBTResult
runPropertyTests stmts = do
  let funcEnv     = buildFuncEnv stmts
      aliasEnv    = buildTypeAliasEnv stmts
      checks      = [prop | SCheck prop <- stmts]
      -- v0.6.2: extract interface laws as properties (auto-numbered descriptions)
      lawProps    = [ prop { propDescription = ifName <> "_law_" <> T.pack (show idx) }
                    | SDefInterface ifName _ laws <- stmts
                    , (idx, prop) <- zip [(1::Int)..] laws
                    ]
      allProps    = checks ++ lawProps
  runs <- mapM (runPropertyWith funcEnv aliasEnv) allProps
  let passed  = length [() | r <- runs, pbtStatus r == PBTPassed]
      failed  = length [() | r <- runs, pbtStatus r == PBTFailed]
      skipped = length [() | r <- runs, pbtStatus r == PBTSkipped]
  pure $ PBTResult
    { pbtTotal   = length allProps
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

-- | Run a single check block with a top-level function environment.
--
-- OBLIG-PBT-2 / F-032: takes a 'TypeAliasEnv' so 'generateValue' can resolve
-- @TCustom@ aliases declared via @(type Foo (..))@ in the same module
-- (or imported via 'assembleTestStatements').
runPropertyWith :: FuncEnv -> TypeAliasEnv -> LLMLL.Syntax.Property -> IO PBTRun
runPropertyWith funcEnv aliasEnv prop = do
  let bindings = propBindings prop
      body     = propBody prop
      desc     = propDescription prop
      nSamples = 100  -- number of random samples

  -- Generate sample environments and evaluate the property body
  samples <- generateSamples aliasEnv bindings nSamples
  let results = map (\env -> evalPropertyBodyWith funcEnv env body) samples

  case sequence results of
    -- All evaluations returned concrete booleans
    Just bools ->
      case [i | (i, False) <- zip [(0::Int)..] bools] of
        [] -> pure $ PBTRun desc PBTPassed nSamples Nothing
        (i:_) ->
          let counterex = formatBinding (samples !! i)
          in pure $ PBTRun desc PBTFailed nSamples (Just counterex)

    -- Some could not be evaluated statically: fall back to QuickCheck so
    -- shrinking can produce a minimised counterexample. The broadened
    -- generator (post F-032) makes this path productive on most well-formed
    -- properties rather than the previous TInt|TBool-only whitelist.
    Nothing ->
      case tryQuickCheck funcEnv aliasEnv bindings body of
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
evalPropertyBodyWith :: FuncEnv -> Map Name Expr -> Expr -> Maybe Bool
evalPropertyBodyWith funcEnv env body =
  case evalExprStaticWith funcEnv maxFuel env body of
    Just (ELit (LitBool b)) -> Just b
    _                       -> Nothing

-- ---------------------------------------------------------------------------
-- Sample Generation (Symbolic)
-- ---------------------------------------------------------------------------

-- | Generate N random binding environments for the given typed bindings.
generateSamples :: TypeAliasEnv -> [(Name, Type)] -> Int -> IO [Map Name Expr]
generateSamples aliasEnv bindings n =
  mapM (\_ -> generateBinding aliasEnv bindings) [1..n]

-- | Generate a single random binding environment.
generateBinding :: TypeAliasEnv -> [(Name, Type)] -> IO (Map Name Expr)
generateBinding aliasEnv bindings = do
  pairs <- mapM genForType bindings
  pure (Map.fromList pairs)
  where
    genForType (name, ty) = do
      val <- generateValue aliasEnv maxGenDepth ty
      pure (name, val)

-- | Generate a random sample expression of the given LLMLL type.
--
-- OBLIG-PBT-2 / F-032: returns 'Expr' (not 'Literal') so complex types
-- can produce 'EPair' / @EApp \"cons\" [..]@ / @EApp ConstructorName [..]@
-- shapes that downstream builtins ('first', 'list-fold', etc.) can
-- pattern-match. Recursion depth is bounded by 'maxGenDepth' to guarantee
-- termination on self-referential aliases; 'TCustom' is resolved via
-- 'expandAliasPure' against the supplied 'TypeAliasEnv'.
generateValue :: TypeAliasEnv -> Int -> Type -> IO Expr
generateValue _ _ TInt         = ELit . LitInt . getNonNeg <$> generate (arbitrary :: Gen (NonNegative Integer))
generateValue _ _ TFloat       = ELit . LitFloat <$> generate (arbitrary :: Gen Double)
generateValue _ _ TString      = ELit . LitString . T.pack <$> generate (arbitrary :: Gen String)
generateValue _ _ TBool        = ELit . LitBool <$> generate (arbitrary :: Gen Bool)
generateValue _ _ TUnit        = pure (ELit LitUnit)
generateValue _ _ (TBytes _)   = ELit . LitString . T.pack <$> generate (arbitrary :: Gen String)
generateValue aliases depth (TDependent _ base _) =
  -- ignore the refinement constraint for generation; tracked as a future
  -- improvement (filter-and-retry) outside F-032 scope.
  generateValue aliases depth base

-- Complex types
generateValue aliases depth (TPair a b) = do
  va <- generateValue aliases (depth - 1) a
  vb <- generateValue aliases (depth - 1) b
  pure (EPair va vb)
generateValue aliases depth (TList elt)
  | depth <= 0 = pure (EApp "nil" [])
  | otherwise  = do
      len <- generate (choose (0, listMaxLen))
      elts <- mapM (\_ -> generateValue aliases (depth - 1) elt) [1..(len :: Int)]
      pure (foldr (\e acc -> EApp "cons" [e, acc]) (EApp "nil" []) elts)
generateValue aliases depth (TResult okTy errTy)
  | depth <= 0 = pure (EApp "Error" [ELit LitUnit])
  | otherwise = do
      tag <- generate (arbitrary :: Gen Bool)
      if tag
        then do v <- generateValue aliases (depth - 1) okTy
                pure (EApp "Success" [v])
        else do v <- generateValue aliases (depth - 1) errTy
                pure (EApp "Error" [v])
generateValue aliases depth (TSumType ctors)
  | null ctors = pure (ELit LitUnit)  -- empty sum is unreachable; surface a unit
  | depth <= 0 =
      -- prefer nullary constructors at depth-cap to guarantee termination on
      -- recursive ADTs; if none exist, emit a unit-payload placeholder.
      case [c | (c, Nothing) <- ctors] of
        (nullaryName : _) -> pure (EApp nullaryName [])
        []                -> pure (ELit LitUnit)
  | otherwise = do
      idx <- generate (choose (0, length ctors - 1))
      let (cname, mPayload) = ctors !! idx
      case mPayload of
        Nothing       -> pure (EApp cname [])
        Just payloadTy -> do
          v <- generateValue aliases (depth - 1) payloadTy
          pure (EApp cname [v])
generateValue aliases depth (TCustom n)
  -- Resolve through the alias env. If it resolves to itself (cycle or
  -- unknown), fall back to an int so generation does not loop.
  | depth <= 0 = ELit . LitInt . getNonNeg <$> generate (arbitrary :: Gen (NonNegative Integer))
  | otherwise =
      case expandAliasPure aliases (TCustom n) of
        TCustom m | m == n -> ELit . LitInt . getNonNeg <$> generate (arbitrary :: Gen (NonNegative Integer))
        resolved          -> generateValue aliases (depth - 1) resolved

-- Catch-all: TFn / TPromise / TVar / TDelegationError / TMap. These types do
-- not have natural value generators (functions cannot be randomly synthesized
-- here; promises and free type variables would require unification). Fall back
-- to a non-negative int and let downstream evaluation skip if the body can't
-- reduce. Tracked outside F-032 scope.
generateValue _ _ _ = ELit . LitInt <$> generate (arbitrary :: Gen Integer)

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

    goStep (DoStep _ e) = go e  -- PR 2: unified constructor

    -- Names known to produce a Command value — only WASI/IO imports qualify.
    -- Keep this list narrow: false positives cause valid properties to be skipped.
    isCommandFn n = any (`T.isPrefixOf` n)
      ["wasi.", "console.", "http.", "fs."]

-- ---------------------------------------------------------------------------
-- QuickCheck Integration (for integer-only properties)
-- ---------------------------------------------------------------------------

-- | Run a property under QuickCheck with the broadened sample generator.
--
-- OBLIG-PBT-2 / F-032: the prior 'isSimpleType' whitelist (TInt|TBool|
-- TDependent TInt only) excluded most realistic properties; now the same
-- 'generateValue' shape used by the static-eval path is lifted into
-- QuickCheck's 'Gen' via 'unsafePerformIO'-free composition. Always returns
-- 'Just' — fallback is universal; the only previous role of returning
-- 'Nothing' was to gate on simple-type bindings, which is no longer the
-- discriminator.
tryQuickCheck :: FuncEnv -> TypeAliasEnv -> [(Name, Type)] -> Expr -> Maybe (IO QCRun)
tryQuickCheck funcEnv aliasEnv bindings body = Just (runQC funcEnv aliasEnv bindings body)

data QCRun = QCRun
  { qcStatus     :: PBTStatus
  , qcSamples    :: Int
  , qcCounterex  :: Maybe Text
  } deriving (Show)

runQC :: FuncEnv -> TypeAliasEnv -> [(Name, Type)] -> Expr -> IO QCRun
runQC funcEnv aliasEnv bindings body = do
  -- Pre-generate sample environments in IO using the same generator used by
  -- the static-eval path, then drive QuickCheck over the pre-built batch.
  -- This keeps the generator implementation single-source (no Gen-monad
  -- duplicate) while still letting QuickCheck report sample counts.
  preSamples <- generateSamples aliasEnv bindings 100
  let prop :: Map Name Expr -> QC.Property
      prop env = case evalExprStaticWith funcEnv maxFuel env body of
        Just (ELit (LitBool b)) -> QC.property b
        _                       -> QC.discard

      -- forAll the pre-built samples by indexing — QuickCheck picks an int
      -- in [0, len-1] and we project to the corresponding env.
      genIdx :: Gen (Map Name Expr)
      genIdx = do
        i <- choose (0, length preSamples - 1)
        pure (preSamples !! i)

  result <- (try (quickCheckResult (forAll genIdx prop)) :: IO (Either SomeException Result))
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
