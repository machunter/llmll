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

    -- * OBLIG-PBT-3: trust-report write-back
  , HeadResolution(..)
  , headContractedSubject
  , canonicalPropBodyHash
  , pbtTrustWriteback

    -- * Results
  , PBTResult(..)
  , PBTRun(..)
  , PBTStatus(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.List (foldl')
import qualified Data.ByteString as BS
import Numeric (showHex)

import qualified Test.QuickCheck as QC
import Test.QuickCheck
  ( Gen, generate, vectorOf, arbitrary, choose
  , Arbitrary(..), quickCheckResult, Result(..)
  , counterexample, forAll, NonNegative(..))
import Control.Exception (try, SomeException)
import Data.IORef (IORef, newIORef, modifyIORef', readIORef)
import qualified Crypto.Hash.SHA256 as SHA256

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
                 , isExported n, nameFilter n ]
             ++ [ s | s@SDef{defName = n} <- meStatements menv
                    , isExported n, nameFilter n ]
             ++ [ s | s@SDefShell{defShellName = n} <- meStatements menv
                    , isExported n, nameFilter n ]

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
  -- F-033: count body-evaluator discards out of band so PBTSkipped can
  -- distinguish "body never reduced to a bool" (likely an unmodeled
  -- builtin in the property body) from "precondition kept failing"
  -- (a useful signal, not a compiler gap). 'forAll' calls 'prop' once
  -- per sample inside QC's IO scope, so an IORef closed over here is
  -- safe and correct.
  bodyDiscardCount <- newIORef (0 :: Int)
  let prop :: Map Name Expr -> QC.Property
      prop env = case evalExprStaticWith funcEnv maxFuel env body of
        Just (ELit (LitBool b)) -> QC.property b
        _                       -> QC.ioProperty $ do
                                      modifyIORef' bodyDiscardCount (+1)
                                      pure (QC.discard :: QC.Property)

      -- forAll the pre-built samples by indexing — QuickCheck picks an int
      -- in [0, len-1] and we project to the corresponding env.
      genIdx :: Gen (Map Name Expr)
      genIdx = do
        i <- choose (0, length preSamples - 1)
        pure (preSamples !! i)

  result <- (try (quickCheckResult (forAll genIdx prop)) :: IO (Either SomeException Result))
  bodyDiscards <- readIORef bodyDiscardCount
  case result of
    Left ex -> pure $ QCRun (PBTError (T.pack (show ex))) 0 Nothing
    Right r  -> pure $ resultsToQCRun bodyDiscards r

-- | Convert a QC 'Result' to a 'QCRun'. The 'bodyDiscards' argument is the
-- out-of-band count of samples whose body did not reduce to a 'LitBool'
-- (F-033 discard-classification); used to refine the GaveUp diagnostic.
resultsToQCRun :: Int -> Result -> QCRun
resultsToQCRun bodyDiscards r = case r of
  Success { numTests = n }                        -> QCRun PBTPassed n Nothing
  Failure { numTests = n, output = out }          -> QCRun PBTFailed n (Just (T.pack out))
  GaveUp  { numTests = n }                        -> QCRun PBTSkipped n (Just (gaveUpDiag bodyDiscards n))
  NoExpectedFailure { numTests = n }              -> QCRun PBTFailed n (Just "Property was expected to fail but passed")
  _                                               -> QCRun PBTSkipped 0 (Just "Unknown QuickCheck result")

-- | F-033 GaveUp diagnostic: classify by whether the body evaluator or the
-- precondition path dominated the discards. If the body discarded on every
-- attempted sample (samples_run = 0, bodyDiscards > 0), the proximate cause
-- is almost certainly an unmodeled builtin or an unreduced callee body in
-- the property body — not a hard-to-satisfy precondition.
gaveUpDiag :: Int -> Int -> Text
gaveUpDiag bodyDiscards samplesRun
  | samplesRun == 0 && bodyDiscards > 0 =
      "property body did not reduce on any sample ("
      <> T.pack (show bodyDiscards)
      <> " evaluated, 0 returned bool — likely unmodeled builtin or unreduced callee body in property body)"
  | otherwise =
      "QuickCheck gave up — too many precondition failures"

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

-- ---------------------------------------------------------------------------
-- OBLIG-PBT-3: PBT-to-trust-report write-back
-- ---------------------------------------------------------------------------

-- | Resolution outcome for the singleton-head-position subject linkage rule
-- (proposal §3). A @(check ...)@ block lifts at most one function; the
-- contracted callees mentioned in head position determine which.
data HeadResolution
  = HRNone               -- ^ No contracted callee in head position; no lift
  | HRSingleton Name     -- ^ Exactly one contracted callee; lift target
  | HRMulti [Name]       -- ^ ≥2 distinct contracted callees; diagnostic, no lift
  deriving (Show, Eq)

-- | Resolve the contracted subject of a property body against the assembled
-- (post-'assembleTestStatements') statement list. Walks head-position 'EApp'
-- operators reachable through 'EApp'-args, 'ELet', 'EIf', 'EMatch', 'EPair',
-- 'ELambda', 'EDo', 'EOp'-args (proposal §3 — same shape set as
-- 'TrustReport.extractCalls'). Filters to operators that resolve to an
-- 'SDefLogic'/'SLetrec' with @contractPost /= Nothing@; returns 'HRSingleton'
-- iff that set is exactly one name.
headContractedSubject :: [Statement] -> Expr -> HeadResolution
headContractedSubject mergedStmts body =
  let contractedPostNames = Set.fromList
        [ n | SDefLogic{defLogicName=n, defLogicContract=c} <- mergedStmts
            , contractPost c /= Nothing ]
        `Set.union` Set.fromList
        [ n | SLetrec{letrecName=n, letrecContract=c} <- mergedStmts
            , contractPost c /= Nothing ]
        -- LT-INV (v0.11)
        `Set.union` Set.fromList
        [ n | SDef{defName=n, defContract=c} <- mergedStmts
            , contractPost c /= Nothing ]
        `Set.union` Set.fromList
        [ n | SDefShell{defShellName=n, defShellContract=c} <- mergedStmts
            , contractPost c /= Nothing ]
      mentioned = Set.fromList (collectHeadOps body)
      hits = Set.toList (Set.intersection mentioned contractedPostNames)
  in case hits of
       []   -> HRNone
       [x]  -> HRSingleton x
       xs   -> HRMulti xs

-- | Collect every 'EApp' operator name reachable by recursive descent through
-- the shapes listed in proposal §3. 'EOp' is not collected — operators
-- (@+@, @=@, etc.) cannot be contracted user functions.
collectHeadOps :: Expr -> [Name]
collectHeadOps = go
  where
    go (EApp n args)        = n : concatMap go args
    go (EOp _ args)         = concatMap go args
    go (ELet binds body)    = concatMap (\(_, _, e) -> go e) binds ++ go body
    go (EIf c t e)          = go c ++ go t ++ go e
    go (EMatch e cases)     = go e ++ concatMap (go . snd) cases
    go (EPair a b)          = go a ++ go b
    go (ELambda _ b)        = go b
    go (EDo steps)          = concatMap (\(DoStep _ e) -> go e) steps
    go (EAwait e)           = go e
    go (ELit _)             = []
    go (EVar _)             = []
    go (EHole _)            = []

-- | SHA-256 of the canonical s-expression serialization of a property body.
-- Output shape: @\"sha256:\" <> 64 hex chars@. The canonical serializer
-- ('canonicalExpr' below) is exhaustive over every 'Expr' constructor — it is
-- deliberately independent of 'ObligationAssembly.exprToSExpr', which falls
-- through to Haskell @show@ for several shapes that occur in property bodies
-- ('ELet'/'EIf'/'EMatch'/'EPair'/'ELambda'/'EDo'). The hash is used by
-- 'TrustReport.buildTrustReport' on read to detect property-body drift and
-- downgrade stale 'DLTested n' entries to 'DLAsserted' (proposal §7).
canonicalPropBodyHash :: Expr -> Text
canonicalPropBodyHash e =
  let bytes = SHA256.hash (TE.encodeUtf8 (canonicalExpr e))
      hex   = T.pack $ concatMap (\b -> let h = showHex b "" in if length h == 1 then '0':h else h)
                                 (BS.unpack bytes)
  in "sha256:" <> hex

-- | Exhaustive canonical serialization. Total over 'Expr'. Structurally
-- stable: alpha-equivalent variations in 'ELambda' bindings are NOT
-- normalized (the user-visible binding names are part of the hash), so
-- renaming a bound variable in a property invalidates the cached hash —
-- the conservative direction, consistent with §7's "editing a property
-- body invalidates the cached DLTested."
canonicalExpr :: Expr -> Text
canonicalExpr (ELit (LitInt n))    = "(int " <> T.pack (show n) <> ")"
canonicalExpr (ELit (LitFloat f))  = "(float " <> T.pack (show f) <> ")"
canonicalExpr (ELit (LitString s)) = "(str " <> escapeText s <> ")"
canonicalExpr (ELit (LitBool b))   = if b then "(true)" else "(false)"
canonicalExpr (ELit LitUnit)       = "(unit)"
canonicalExpr (EVar n)             = "(var " <> n <> ")"
canonicalExpr (EApp n args)        = "(app " <> n <> spaceList (map canonicalExpr args) <> ")"
canonicalExpr (EOp n args)         = "(op " <> n <> spaceList (map canonicalExpr args) <> ")"
canonicalExpr (EIf c t e)          = "(if " <> canonicalExpr c <> " " <> canonicalExpr t <> " " <> canonicalExpr e <> ")"
canonicalExpr (ELet binds body)    = "(let " <> spaceList (map canonicalBinding binds) <> " " <> canonicalExpr body <> ")"
canonicalExpr (EMatch e cases)     = "(match " <> canonicalExpr e <> spaceList (map canonicalCase cases) <> ")"
canonicalExpr (EPair a b)          = "(pair " <> canonicalExpr a <> " " <> canonicalExpr b <> ")"
canonicalExpr (EHole h)            = "(hole " <> T.pack (show h) <> ")"
canonicalExpr (EAwait e)           = "(await " <> canonicalExpr e <> ")"
canonicalExpr (ELambda params b)   = "(lam " <> spaceList (map canonicalParam params) <> " " <> canonicalExpr b <> ")"
canonicalExpr (EDo steps)          = "(do " <> spaceList (map canonicalStep steps) <> ")"

canonicalBinding :: (Pattern, Maybe Type, Expr) -> Text
canonicalBinding (p, mTy, e) =
  "(bind " <> canonicalPattern p <> " " <> maybe "_" (T.pack . show) mTy <> " " <> canonicalExpr e <> ")"

canonicalCase :: (Pattern, Expr) -> Text
canonicalCase (p, e) = "(case " <> canonicalPattern p <> " " <> canonicalExpr e <> ")"

canonicalPattern :: Pattern -> Text
canonicalPattern (PConstructor n ps) = "(ctor " <> n <> spaceList (map canonicalPattern ps) <> ")"
canonicalPattern (PVar n)            = "(pvar " <> n <> ")"
canonicalPattern (PLiteral l)        = canonicalExpr (ELit l)
canonicalPattern PWildcard           = "(_)"

canonicalParam :: (Name, Type) -> Text
canonicalParam (n, ty) = "(param " <> n <> " " <> T.pack (show ty) <> ")"

canonicalStep :: DoStep -> Text
canonicalStep (DoStep mName e) = "(step " <> maybe "_" id mName <> " " <> canonicalExpr e <> ")"

spaceList :: [Text] -> Text
spaceList [] = ""
spaceList xs = " " <> T.intercalate " " xs

escapeText :: Text -> Text
escapeText s = "\"" <> T.replace "\"" "\\\"" s <> "\""

-- | Build the PBT-derived contract-status map and the informational
-- diagnostics for non-lifting cases (multi-subject, skipped, error,
-- no-contracted-callee, no-post-clause). Pure; called by 'doTest' which
-- handles the file I/O.
--
-- Takes the *local* statement list (pre-'assembleTestStatements') and the
-- 'ModuleCache' separately, so that name attribution (local vs imported)
-- is precise: a name defined in 'localStmts' is local; a name reachable
-- only through an 'SOpen' is imported and qualified for the sidecar key.
--
-- Per proposal §6 the within-channel join across multiple 'PBTPassed'
-- properties on the same subject uses @max@ on sample counts and union on
-- 'erPbtWitnesses' (deduplicated by 'pwHash'). This is @mergePbtWriteback@
-- below — distinct from 'Module.mergeCS' which is the sidecar-vs-base
-- lattice-monotonic merge.
--
-- Per proposal §8 the sidecar key is the qualified import path when the
-- subject came from @(open path …)@, bare-local otherwise.
pbtTrustWriteback :: [Statement]
                  -> ModuleCache
                  -> PBTResult
                  -> (Map Name ContractStatus, [Text])
pbtTrustWriteback localStmts cache result =
  let -- Local names: only those defined in the local file. SOpen-forwarded
      -- imports do not appear here even after 'assembleTestStatements'
      -- because we work off 'localStmts' directly.
      localNames = Set.fromList
        ([n | SDefLogic{defLogicName=n} <- localStmts] ++
         [n | SLetrec{letrecName=n} <- localStmts] ++
         -- LT-INV (v0.11)
         [n | SDef{defName=n} <- localStmts] ++
         [n | SDefShell{defShellName=n} <- localStmts])
      qualMap     = buildQualMap localStmts cache localNames
      mergedStmts = assembleTestStatements localStmts cache
      -- Subject resolution happens against the merged list so imported
      -- def-logic statements are visible. Right-bias of the iteration order
      -- ('importedDLs ++ localStmts' in 'assembleTestStatements') means
      -- 'Map.fromList' gives local-shadows-import semantics, matching the
      -- type-checker.
      contractByName = Map.fromList $
        [ (n, c) | SDefLogic{defLogicName=n, defLogicContract=c} <- mergedStmts ]
        ++
        [ (n, c) | SLetrec{letrecName=n, letrecContract=c} <- mergedStmts ]
        -- LT-INV (v0.11)
        ++
        [ (n, c) | SDef{defName=n, defContract=c} <- mergedStmts ]
        ++
        [ (n, c) | SDefShell{defShellName=n, defShellContract=c} <- mergedStmts ]
      -- SCheck blocks stay with the owning module (assembleTestStatements
      -- comment line 124-126); property descriptions are local-only.
      propsByDesc = Map.fromList $
        [ (propDescription p, p)
        | SCheck p <- localStmts
        ] ++
        [ (ifName <> "_law_" <> T.pack (show idx), p)
        | SDefInterface ifName _ laws <- localStmts
        , (idx, p) <- zip [(1::Int)..] laws
        ]
      processed = map (processRun contractByName qualMap propsByDesc) (pbtResults result)
      (mapsList, diagsList) = unzip processed
      mergedMap = foldl' (Map.unionWith mergePbtWriteback) Map.empty mapsList
  in (mergedMap, concat diagsList)

-- | Process a single PBTRun: lift on PBTPassed.
--
-- OBLIG-PBT-4: when the property carries an explicit ':subject f' or
-- ':subjects [f₁ … fₖ]' annotation ('propSubjects' non-empty), the
-- head-position scan is bypassed entirely and each declared subject with a
-- post-condition receives its own 'DLTested n' record, all sharing the same
-- 'pbt_witnesses' hash (per proposal §11.1 inference rule, 2026-05-14). On
-- absence of the annotation, the v0.10.5 singleton-head-position semantics
-- continue to apply unchanged.
processRun :: Map Name Contract
           -> Map Name Name      -- ^ bare → qualified sidecar key
           -> Map Name LLMLL.Syntax.Property
           -> PBTRun
           -> (Map Name ContractStatus, [Text])
processRun contractByName qualMap propsByDesc run =
  case pbtStatus run of
    PBTPassed ->
      case Map.lookup (pbtDescription run) propsByDesc of
        Nothing -> (Map.empty, [])  -- no matching property body; cannot lift
        Just prop ->
          let body = propBody prop
              subjects = propSubjects prop
              n      = pbtSamplesRun run
              desc   = pbtDescription run
              h      = canonicalPropBodyHash body
              w      = PbtWitness h desc
              mkEntry f =
                let er  = EvidenceRecord (DLTested n) False Nothing [w] False Nothing Nothing False
                    cs  = ContractStatus { csPre = Nothing, csPost = Just er, csAssumptions = [] }
                    key = Map.findWithDefault f f qualMap
                in (key, cs)
          in if not (null subjects)
               then
                 -- OBLIG-PBT-4 path: explicit annotation. For each declared
                 -- subject: (a) absent from contractByName → silent skip; the
                 -- type-checker is the source of truth for resolution and
                 -- already rejects unbound names. (b) present but post=Nothing
                 -- → S3 informational diagnostic. (c) present with post → lift.
                 let go f (accMap, accDiags) =
                       case Map.lookup f contractByName of
                         Just c | contractPost c /= Nothing ->
                           let (k, cs) = mkEntry f
                           in (Map.insert k cs accMap, accDiags)
                         Just _ ->
                           let d = "property \"" <> desc
                                 <> "\" declares subject \"" <> f
                                 <> "\" which has no postcondition; no slot to lift"
                           in (accMap, d : accDiags)
                         Nothing -> (accMap, accDiags)
                     (m, ds) = foldr go (Map.empty, []) subjects
                 in (m, reverse ds)
               else
                 -- v0.10.5 path: singleton-head-position scan, unchanged.
                 let contractedNames = Map.keysSet (Map.filter (\c -> contractPost c /= Nothing) contractByName)
                     mentioned       = Set.fromList (collectHeadOps body)
                     hits            = Set.toList (Set.intersection mentioned contractedNames)
                 in case hits of
                      [] -> (Map.empty, [])
                      [f] ->
                        let (key, cs) = mkEntry f
                        in (Map.singleton key cs, [])
                      fs ->
                        let diag = "property \"" <> desc
                                 <> "\" covers multiple contracted callees ("
                                 <> T.intercalate ", " fs
                                 <> "); no trust evidence recorded — split the property or wait for :subject metadata in OBLIG-PBT-4"
                        in (Map.empty, [diag])
    PBTFailed -> (Map.empty, ["property \"" <> pbtDescription run <> "\" failed; no trust evidence recorded"])
    PBTSkipped -> (Map.empty, [])
    PBTError _ -> (Map.empty, [])

-- | Within-channel join across PBTPassed properties on the same subject
-- (proposal §6). @max@ on 'DLTested' sample counts; union of
-- 'erPbtWitnesses' deduplicated by 'pwHash'. Falls through to a
-- 'mergeCS'-like lattice rule on asymmetric / non-tested inputs (defensive;
-- @pbtTrustWriteback@ only produces 'DLTested' clauses).
mergePbtWriteback :: ContractStatus -> ContractStatus -> ContractStatus
mergePbtWriteback a b = ContractStatus
  { csPre  = mergePbtER (csPre a) (csPre b)
  , csPost = mergePbtER (csPost a) (csPost b)
  , csAssumptions = case csAssumptions a of [] -> csAssumptions b; xs -> xs
  }
  where
    mergePbtER Nothing y = y
    mergePbtER x Nothing = x
    mergePbtER (Just x) (Just y) = Just (joinER x y)

    joinER x y =
      let lvl = case (erDisplayLevel x, erDisplayLevel y) of
                  (DLTested n1, DLTested n2) -> DLTested (max n1 n2)
                  (lx, ly) | evidenceCovers lx ly -> lx
                           | otherwise            -> ly
          ws  = dedupWitnesses (erPbtWitnesses x ++ erPbtWitnesses y)
      in EvidenceRecord
           { erDisplayLevel    = lvl
           , erBodyFaithful    = erBodyFaithful x || erBodyFaithful y
           , erSource          = case erSource x of { Just s -> Just s; Nothing -> erSource y }
           , erPbtWitnesses    = ws
           -- INT-1: join propagates taint (either side tainted ⇒ join tainted).
           -- DLTested evidence never sets the flag in v0.10.8, so the OR is
           -- effectively dormant on the PBT joiner; written explicitly so a
           -- future verifier-side taint join inherits the right semantics.
           , erOverflowTainted     = erOverflowTainted x || erOverflowTainted y
           -- LT-PPR (v0.11): predicate fields not carried through PBT join;
           -- PBT evidence is never predicate-carrying (asserted origin only).
           , erPredicateForm       = Nothing
           , erPredicateText       = Nothing
           , erRuntimeCheckEmitted = False
           }

    dedupWitnesses ws =
      let go _    []     = []
          go seen (w:rest)
            | Set.member (pwHash w) seen = go seen rest
            | otherwise = w : go (Set.insert (pwHash w) seen) rest
      in go Set.empty ws

-- | Build a map @bare name → qualified sidecar key@ for names that came from
-- an @(open path)@ import. Local names are excluded so locally-shadowed
-- imports use the bare key, matching 'assembleTestStatements' right-bias
-- semantics. Qualified key is @T.intercalate \".\" path <> \".\" <> name@,
-- consistent with 'TrustReport.collectAllContractStatus'.
buildQualMap :: [Statement] -> ModuleCache -> Set Name -> Map Name Name
buildQualMap localStmts cache localNames =
  Map.fromList
    [ (n, qual)
    | SOpen{openPath = path, openNames = mNames} <- localStmts
    , Just menv <- [Map.lookup path cache]
    , s <- meStatements menv
    , Just n <- [extractContractedName s]
    , Map.member n (meExports menv)
    , maybe True (n `elem`) mNames
    , not (Set.member n localNames)
    , let qual = T.intercalate "." path <> "." <> n
    ]
  where
    extractContractedName (SDefLogic{defLogicName=n, defLogicContract=c})
      | contractPost c /= Nothing = Just n
    extractContractedName (SLetrec{letrecName=n, letrecContract=c})
      | contractPost c /= Nothing = Just n
    -- LT-INV (v0.11)
    extractContractedName (SDef{defName=n, defContract=c})
      | contractPost c /= Nothing = Just n
    extractContractedName (SDefShell{defShellName=n, defShellContract=c})
      | contractPost c /= Nothing = Just n
    extractContractedName _ = Nothing
