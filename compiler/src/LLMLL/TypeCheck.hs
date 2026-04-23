-- |
-- Module      : LLMLL.TypeCheck
-- Description : Bidirectional type checker for LLMLL v0.1.
--
-- Implements a simple bidirectional type checker that:
--   * Builds a type environment from top-level definitions
--   * Infers types for expressions bottom-up
--   * Checks types top-down against annotations
--   * Validates pre/post contract expressions are boolean
--   * Reports structured diagnostics for each error
--
-- Dependent types (TDependent) are partially supported: the constraint
-- expression is well-formedness checked but not evaluated at compile time.
module LLMLL.TypeCheck
  ( -- * Entry Points
    typeCheck
  , typeCheckModule
  , typeCheckWithCache
  , runSketch
    -- * Environment
  , TypeEnv
  , builtinEnv
  , emptyEnv
  , extendEnv
    -- * Results
  , TypeCheckResult(..)
  , SketchResult(..)
  , SketchHole(..)
  , HoleStatus(..)
    -- * v0.3.5: Scope provenance for context-aware checkout (Phase C)
  , ScopeSource(..)
  , ScopeBinding(..)
    -- * v0.4: Invariant pattern registry (re-export)
  , InvariantSuggestion(..)
    -- * v0.5: U-Full internal exports (for direct unit testing)
  , structuralUnify
  , runTC
  , occursIn
  , TC
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, fromMaybe)
import Control.Monad (forM_, forM, foldM, when, unless, void)
import LLMLL.InvariantRegistry (InvariantPattern, InvariantSuggestion(..), matchPatterns)
import Control.Monad.State.Strict

import LLMLL.Syntax
import LLMLL.Diagnostic

-- ---------------------------------------------------------------------------
-- Type Environment
-- ---------------------------------------------------------------------------

-- | Maps names to their types.
type TypeEnv = Map Name Type

-- | Built-in operators and stdlib functions, always in scope (LLMLL.md §13).
-- TVar "a" / TVar "b" stand for polymorphic type parameters;
-- compatibleWith (TVar _) _ = True so they unify with anything.
builtinEnv :: TypeEnv
builtinEnv = Map.fromList $
  -- §13.1 Arithmetic operators
  [ ("+",   TFn [TInt, TInt] TInt)
  , ("-",   TFn [TInt, TInt] TInt)
  , ("*",   TFn [TInt, TInt] TInt)
  , ("/",   TFn [TInt, TInt] TInt)
  , ("mod", TFn [TInt, TInt] TInt)
  -- §13.2 Comparison & equality (polymorphic — TVar matches any type)
  , ("=",   TFn [TVar "a", TVar "a"] TBool)
  , ("!=",  TFn [TVar "a", TVar "a"] TBool)
  , ("<",   TFn [TInt, TInt] TBool)
  , (">",   TFn [TInt, TInt] TBool)
  , ("<=",  TFn [TInt, TInt] TBool)
  , (">=",  TFn [TInt, TInt] TBool)
  -- §13.3 Logic
  , ("and", TFn [TBool, TBool] TBool)
  , ("or",  TFn [TBool, TBool] TBool)
  , ("not", TFn [TBool] TBool)
  -- §13.4 Pair / record
  -- U2-lite (v0.4): first/second retyped to require TPair argument.
  -- Before U-lite, these used TVar "p" (any type) because the checker couldn't
  -- express the pair constraint. With per-call-site substitution, TPair a b works.
  , ("pair",   TFn [TVar "a", TVar "b"] (TPair (TVar "a") (TVar "b")))
  , ("first",  TFn [TPair (TVar "a") (TVar "b")] (TVar "a"))
  , ("second", TFn [TPair (TVar "a") (TVar "b")] (TVar "b"))
  -- §13.5 List operations
  , ("list-empty",    TFn [] (TList (TVar "a")))
  , ("list-append",   TFn [TList (TVar "a"), TVar "a"] (TList (TVar "a")))
  , ("list-prepend",  TFn [TVar "a", TList (TVar "a")] (TList (TVar "a")))
  , ("list-contains", TFn [TList (TVar "a"), TVar "a"] TBool)
  , ("list-length",   TFn [TList (TVar "a")] TInt)
  , ("list-head",     TFn [TList (TVar "a")] (TResult (TVar "a") TString))
  , ("list-tail",     TFn [TList (TVar "a")] (TResult (TList (TVar "a")) TString))
  , ("list-map",      TFn [TList (TVar "a"), TFn [TVar "a"] (TVar "b")] (TList (TVar "b")))
  , ("list-filter",   TFn [TList (TVar "a"), TFn [TVar "a"] TBool] (TList (TVar "a")))
  , ("list-fold",     TFn [TList (TVar "a"), TVar "b", TFn [TVar "b", TVar "a"] (TVar "b")] (TVar "b"))
  , ("list-nth",      TFn [TList (TVar "a"), TInt] (TResult (TVar "a") TString))
  , ("range",         TFn [TInt, TInt] (TList TInt))
  -- §13.6 String operations
  , ("string-length",   TFn [TString] TInt)
  , ("string-contains", TFn [TString, TString] TBool)
  , ("string-concat",   TFn [TString, TString] TString)
  , ("string-slice",    TFn [TString, TInt, TInt] TString)
  , ("string-char-at",  TFn [TString, TInt] TString)
  , ("string-split",    TFn [TString, TString] (TList TString))
  , ("string-trim",     TFn [TString] TString)
  , ("string-concat-many", TFn [TList TString] TString)
  , ("regex-match",     TFn [TString, TString] TBool)
  , ("string-empty?",   TFn [TString] TBool)
  -- §13.7 Numeric utilities
  , ("int-to-string",  TFn [TInt] TString)
  , ("string-to-int",  TFn [TString] (TResult TInt TString))
  , ("abs",            TFn [TInt] TInt)
  , ("min",            TFn [TInt, TInt] TInt)
  , ("max",            TFn [TInt, TInt] TInt)
  -- §13.8 Result helpers
  , ("ok",         TFn [TVar "a"] (TResult (TVar "a") (TVar "e")))
  , ("err",        TFn [TVar "e"] (TResult (TVar "a") (TVar "e")))
  , ("is-ok",      TFn [TResult (TVar "a") (TVar "e")] TBool)
  , ("unwrap",     TFn [TResult (TVar "a") (TVar "e")] (TVar "a"))
  , ("unwrap-or",  TFn [TResult (TVar "a") (TVar "e"), TVar "a"] (TVar "a"))
  -- §13.9 Standard command constructors (require capability imports, but sigs are known)
  , ("wasi.io.stdout",     TFn [TString] (TCustom "Command"))
  , ("wasi.io.stderr",     TFn [TString] (TCustom "Command"))
  , ("wasi.http.response", TFn [TInt, TString] (TCustom "Command"))
  , ("wasi.http.post",     TFn [TString, TString] (TCustom "Command"))
  , ("wasi.fs.read",       TFn [TString] (TCustom "Command"))
  , ("wasi.fs.write",      TFn [TString, TString] (TCustom "Command"))
  , ("wasi.fs.delete",     TFn [TString] (TCustom "Command"))
  , ("seq-commands",       TFn [TCustom "Command", TCustom "Command"] (TCustom "Command"))
  ]

emptyEnv :: TypeEnv
emptyEnv = builtinEnv

extendEnv :: Name -> Type -> TypeEnv -> TypeEnv
extendEnv = Map.insert

-- ---------------------------------------------------------------------------
-- Sketch Mode Types (Phase 2c)
-- ---------------------------------------------------------------------------

-- | Status of a named hole after sketch inference.
data HoleStatus
  = HoleTyped Type          -- ^ constraint successfully resolved to a concrete type
  | HoleAmbiguous Type Type -- ^ conflicting constraints (first vs second observed)
  | HoleUnknown             -- ^ no constraint reached this hole
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- v0.3.5: Scope provenance for context-aware checkout (Phase C)
-- ---------------------------------------------------------------------------

-- | Classification of where a scope binding originated.
-- The Ord instance gives truncation priority: lower ordinal = higher priority
-- = truncated last. SrcParam < SrcLetBinding < SrcMatchArm < SrcOpenImport.
data ScopeSource
  = SrcParam
  | SrcLetBinding
  | SrcMatchArm
  | SrcOpenImport
  deriving (Show, Eq, Ord)

-- | A binding in the typing environment with its provenance tag.
data ScopeBinding = ScopeBinding
  { sbType   :: Type
  , sbSource :: ScopeSource
  } deriving (Show, Eq)

-- | A named hole with its inferred status, RFC 6901 JSON Pointer location,
-- and the local typing context (Γ delta) captured at the hole site.
data SketchHole = SketchHole
  { shName    :: Name       -- ^ hole name with \"?\" prefix (e.g. \"?win_message\")
  , shStatus  :: HoleStatus
  , shPointer :: Text       -- ^ RFC 6901 JSON Pointer (e.g. \"/statements/3/body/else\")
  , shEnv     :: Map Name ScopeBinding  -- ^ v0.3.5: Γ delta (tcEnv \\ builtinEnv) with provenance
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Type Checker Monad
-- ---------------------------------------------------------------------------

data TCState = TCState
  { tcEnv          :: TypeEnv
  , tcErrors       :: [Diagnostic]
  , tcAliasMap     :: Map Name Type   -- ^ alias name → structural body (from STypeDef)
  , tcCurrentFn    :: Maybe Name      -- ^ enclosing def-logic/letrec name
  , tcIsLetrec     :: Bool            -- ^ True when inside a letrec (has explicit :decreases)
  -- Sketch mode (Phase 2c --sketch)
  , tcSketchMode   :: Bool            -- ^ True when called from runSketch
  , tcHoles        :: [SketchHole]    -- ^ accumulator (prepend; reversed at runSketch exit)
  , tcPointerStack :: [Text]          -- ^ RFC 6901 pointer segments; [] in check mode (D4)
  -- v0.3: Stratified verification trust-gap tracking
  , tcContractStatus :: Map Name ContractStatus  -- ^ imported function → contract status
  , tcTrusts         :: Map Name VerificationLevel -- ^ acknowledged trust declarations
  -- v0.3.5: Scope provenance tracking (Phase C)
  , tcProvenance     :: Map Name ScopeSource  -- ^ per-binding source classification for checkout context
  -- v0.4: CAP-1 capability enforcement
  , tcModuleStmts    :: [Statement]  -- ^ module's top-level statements, for capability import checks
  } deriving (Show)

type TC a = State TCState a

-- | Emit a type error.
tcError :: Text -> TC ()
tcError msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkError Nothing msg] }

-- | Emit a hole-sensitive type error (holeSensitive = True).
-- Used in unify when at least one type is a hole variable.
tcErrorHS :: Text -> TC ()
tcErrorHS msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [(mkError Nothing msg) { diagHoleSensitive = True }] }

-- | Emit a structured type-mismatch error with expected/got fields.
-- holeSensitive is set if either type is a hole variable (D3).
tcTypeMismatch :: Text -> Type -> Type -> TC ()
tcTypeMismatch ctx expected actual = modify $ \s -> s
  { tcErrors = tcErrors s ++
      [ (mkError Nothing msg)
          { diagKind          = Just "type-mismatch"
          , diagExpected      = Just (typeLabel expected)
          , diagGot           = Just (typeLabel actual)
          , diagHoleSensitive = isHoleSensitive expected actual
          } ] }
  where
    msg = "type mismatch in '" <> ctx <> "': expected " <> typeLabel expected
            <> ", got " <> typeLabel actual

-- | True if a type is a hole variable (TVar with "?" prefix).
isHoleVar :: Type -> Bool
isHoleVar (TVar n) = "?" `T.isPrefixOf` n
isHoleVar _        = False

-- | True if either type is a hole variable — signals that a unification
-- failure may disappear once the hole resolves (D3).
isHoleSensitive :: Type -> Type -> Bool
isHoleSensitive t1 t2 = isHoleVar t1 || isHoleVar t2

-- | Emit a type warning.
tcWarn :: Text -> TC ()
tcWarn msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkWarning Nothing msg] }

-- | Look up a name in the environment.
tcLookup :: Name -> TC (Maybe Type)
tcLookup name = gets (Map.lookup name . tcEnv)

-- | Insert a binding into the current environment (persistent within this monad run).
tcInsert :: Name -> Type -> TC ()
tcInsert name ty = modify $ \s -> s { tcEnv = Map.insert name ty (tcEnv s) }

-- | Run a computation in an extended environment.
withEnv :: [(Name, Type)] -> TC a -> TC a
withEnv bindings action = do
  old <- gets tcEnv
  modify $ \s -> s { tcEnv = foldr (uncurry Map.insert) old bindings }
  result <- action
  modify $ \s -> s { tcEnv = old }
  pure result

-- | v0.3.5 (Phase C): Run a computation in an extended environment,
-- also recording provenance tags for context-aware checkout.
-- Provenance is scope-restoring: tags pushed here are popped on exit.
withTaggedEnv :: ScopeSource -> [(Name, Type)] -> TC a -> TC a
withTaggedEnv source bindings action = do
  oldEnv <- gets tcEnv
  oldProv <- gets tcProvenance
  let newProv = foldr (\(n, _) acc -> Map.insert n source acc) oldProv bindings
  modify $ \s -> s
    { tcEnv = foldr (uncurry Map.insert) oldEnv bindings
    , tcProvenance = newProv
    }
  result <- action
  modify $ \s -> s { tcEnv = oldEnv, tcProvenance = oldProv }
  pure result

-- | Emit a structured non-exhaustive-match error using the registered diagnostic.
tcEmitNonExhaustive :: Name -> [Name] -> [Name] -> TC ()
tcEmitNonExhaustive typeName missing covered = do
  fn <- gets (maybe "<top>" id . tcCurrentFn)
  modify $ \s -> s
    { tcErrors = tcErrors s ++ [mkNonExhaustiveMatch fn typeName missing covered] }

-- | Run the type checker monad.
runTC :: TypeEnv -> TC a -> (a, [Diagnostic])
runTC env action =
  let (result, st) = runState action (TCState env [] Map.empty Nothing False False [] [] Map.empty Map.empty Map.empty [])
  in (result, tcErrors st)

-- | Run the type checker in sketch mode — collects hole types.
runTCSketch :: TypeEnv -> TC a -> (a, TCState)
runTCSketch env action =
  runState action (TCState env [] Map.empty Nothing False True [] [] Map.empty Map.empty Map.empty [])

-- | v0.3: Emit a trust-gap warning if a contract clause is unproven and
-- not covered by a (trust ...) declaration.
emitTrustGap :: Name -> Map Name VerificationLevel -> Maybe VerificationLevel -> TC ()
emitTrustGap _ _ Nothing = pure ()
emitTrustGap _ _ (Just (VLProven _)) = pure ()  -- proven: no gap
emitTrustGap func trusts (Just vl) =
  case Map.lookup func trusts of
    Just tl | tl >= vl -> pure ()  -- trust level sufficient
    _ -> do
      ptr <- gets tcPointerStack
      let ptrText = "/" <> T.intercalate "/" (reverse ptr)
          levelText = case vl of
            VLAsserted  -> "asserted"
            VLTested _  -> "tested"
            _           -> "unknown"
      modify $ \s -> s { tcErrors = tcErrors s ++ [mkTrustGapWarning func levelText ptrText] }

-- | Push a path segment onto the pointer stack, run action, then pop (D4).
-- Structurally identical to withEnv: push/run/pop.
-- Safe pop guards against underflow on programming errors.
withSegment :: Text -> TC a -> TC a
withSegment seg action = do
  modify $ \s -> s { tcPointerStack = tcPointerStack s ++ [seg] }
  result <- action
  modify $ \s -> s { tcPointerStack =
    case tcPointerStack s of { [] -> []; xs -> init xs } }
  pure result

-- | Reconstruct the RFC 6901 JSON Pointer from the current segment stack.
currentPointer :: TC Text
currentPointer = do
  stack <- gets tcPointerStack
  pure $ "/" <> T.intercalate "/" stack

-- | Record a named hole with its status and local typing context (sketch mode only).
-- v0.3.5 (Phase C): snapshots the env delta (tcEnv \\ builtinEnv) with provenance
-- at the hole site. This is the complete Γ visible to the agent filling this hole.
recordHole :: Name -> HoleStatus -> TC ()
recordHole name status = do
  sketch <- gets tcSketchMode
  when sketch $ do
    ptr <- currentPointer   -- reads tcPointerStack via currentPointer
    -- v0.3.5 C2: snapshot tcEnv delta with provenance
    env <- gets tcEnv
    prov <- gets tcProvenance
    let delta = Map.difference env builtinEnv
        -- Build ScopeBinding map: join type from env with source from provenance.
        -- Default to SrcLetBinding for bindings without explicit provenance
        -- (e.g. top-level definitions registered in checkStatements).
        scopedDelta = Map.mapWithKey (\k t ->
          ScopeBinding t (Map.findWithDefault SrcLetBinding k prov)) delta
    modify $ \s -> s { tcHoles = SketchHole ("?" <> name) status ptr scopedDelta : tcHoles s }

-- | Emit an ambiguous-hole diagnostic to the error accumulator.
emitAmbiguous :: Name -> Type -> Type -> TC ()
emitAmbiguous name t1 t2 = do
  let msg = "conflicting constraints: " <> typeLabel t1 <> " vs " <> typeLabel t2
  modify $ \s -> s { tcErrors = tcErrors s ++
    [(mkError Nothing ("ambiguous-hole \"?" <> name <> "\" — " <> msg))
       { diagKind = Just "ambiguous-hole"
       , diagHole = Just ("?" <> name)
       }] }

-- ---------------------------------------------------------------------------
-- Entry Points
-- ---------------------------------------------------------------------------

-- | Type-check a list of top-level statements.
typeCheck :: TypeEnv -> [Statement] -> DiagnosticReport
typeCheck env stmts =
  let (_, diags) = runTC env (checkStatements stmts)
      hasErrors  = any ((== SevError) . diagSeverity) diags
  in DiagnosticReport
    { reportPhase       = "typecheck"
    , reportDiagnostics = diags
    , reportSuccess     = not hasErrors
    }

-- | Type-check a full Module.
typeCheckModule :: TypeEnv -> Module -> DiagnosticReport
typeCheckModule env m = typeCheck env (moduleBody m)

-- | Type-check with an existing ModuleCache.
-- Seeds the TypeEnv with all qualified names from imported modules before
-- running the standard single-file check. Empty cache = single-file path.
-- This is the Phase 2a cross-module entry point.
-- v0.3: also seeds tcContractStatus for trust-gap warnings.
typeCheckWithCache :: ModuleCache -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckWithCache cache baseEnv stmts =
  let -- Inject qualified names from all cached modules
      seededEnv = Map.foldlWithKey' seedModule baseEnv cache
      -- v0.3: merge contract status from all cached modules (qualified names)
      seededCS  = Map.foldlWithKey' seedStatus Map.empty cache
      (_, st) = runState (checkStatements stmts)
        (TCState seededEnv [] Map.empty Nothing False False [] [] seededCS Map.empty Map.empty [])
      diags = tcErrors st
      hasErrors = any ((== SevError) . diagSeverity) diags
  in DiagnosticReport
    { reportPhase       = "typecheck"
    , reportDiagnostics = diags
    , reportSuccess     = not hasErrors
    }
  where
    seedModule acc path menv =
      let prefix = T.intercalate "." path <> "."
          qualified = Map.mapKeys (prefix <>) (meExports menv)
      in Map.union qualified acc
    seedStatus acc path menv =
      let prefix = T.intercalate "." path <> "."
          qualified = Map.mapKeys (prefix <>) (meContractStatus menv)
      in Map.union qualified acc

-- ---------------------------------------------------------------------------
-- Statement Checking
-- ---------------------------------------------------------------------------

-- | Build top-level environment from definitions, then check each statement.
checkStatements :: [Statement] -> TC ()
checkStatements stmts = do
  -- First pass: collect all top-level function and type names
  let topLevel  = mapMaybe collectTopLevel stmts
      aliasMap  = Map.fromList [(n, body) | STypeDef n body <- stmts]
      -- v0.3: collect trust declarations into tcTrusts
      trustMap  = Map.fromList [(trustTarget s, trustLevel s) | s@STrust{} <- stmts]
  -- Populate alias map so expandAlias can resolve TCustom aliases in unify
  -- v0.4 CAP-1: store top-level statements for capability checks in inferExpr
  modify $ \s -> s { tcAliasMap = aliasMap, tcTrusts = Map.union trustMap (tcTrusts s), tcModuleStmts = stmts }
  withEnv topLevel $ do
    -- Second pass: check each statement with its RFC 6901 pointer context.
    -- Each segment is one RFC 6901 token: "statements" and "N" are separate.
    forM_ (zip [0 :: Int ..] stmts) $ \(i, stmt) ->
      withSegment "statements" $ withSegment (tshow i) (checkStatement stmt)

-- | Extract (name, type) for top-level definitions (for forward references).
collectTopLevel :: Statement -> Maybe (Name, Type)
collectTopLevel (SDefLogic name params mRet _contract _body) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet
  in Just (name, TFn argTypes retType)
collectTopLevel (SLetrec name params mRet _contract _dec _body) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet
  in Just (name, TFn argTypes retType)
collectTopLevel (SDefInterface name fns _laws) =
  Just (name, TCustom name)  -- interfaces register as custom types
collectTopLevel (STypeDef name body) =
  Just (name, TCustom name)  -- type aliases register as custom types
collectTopLevel _ = Nothing

checkStatement :: Statement -> TC ()
checkStatement (SDefLogic name params mRet contract body) = do
  -- Track enclosing function for exhaustiveness (D1) and self-recursion (D2)
  modify $ \s -> s { tcCurrentFn = Just name, tcIsLetrec = False }
  let paramBindings = params
  withTaggedEnv SrcParam paramBindings $ do
    -- Infer body type: push "body" segment for pointer precision
    bodyType <- withSegment "body" (inferExpr body)
    -- Check return type annotation if present
    case mRet of
      Nothing -> pure ()
      Just retTy -> unify name retTy bodyType
    -- Check pre-condition is boolean
    case contractPre contract of
      Nothing -> pure ()
      Just pre -> do
        preType <- withEnv [("result", fromMaybe bodyType mRet)] (inferExpr pre)
        unless (compatibleWith preType TBool) $
          tcError $ "pre condition of '" <> name <> "' must be bool, got " <> typeLabel preType
    -- Check post-condition is boolean (has access to 'result')
    case contractPost contract of
      Nothing -> pure ()
      Just post -> do
        let resultType = fromMaybe bodyType mRet
        postType <- withEnv [("result", resultType)] (inferExpr post)
        unless (compatibleWith postType TBool) $
          tcError $ "post condition of '" <> name <> "' must be bool, got " <> typeLabel postType

checkStatement (SLetrec name params mRet contract dec body) = do
  -- letrec: like def-logic but tcIsLetrec=True supresses the self-recursion warning
  modify $ \s -> s { tcCurrentFn = Just name, tcIsLetrec = True }
  let paramBindings = params
  withTaggedEnv SrcParam paramBindings $ do
    -- Validate :decreases is integer-typed (QF linear arithmetic restriction)
    decType <- inferExpr dec
    unless (compatibleWith decType TInt) $
      tcWarn $ "letrec '" <> name <> "': :decreases must be int-typed, got " <> typeLabel decType
    -- Infer body type: push "body" segment for pointer precision
    bodyType <- withSegment "body" (inferExpr body)
    case mRet of
      Nothing -> pure ()
      Just retTy -> unify name retTy bodyType
    -- Check pre-condition
    case contractPre contract of
      Nothing -> pure ()
      Just pre -> do
        preType <- withEnv [("result", fromMaybe bodyType mRet)] (inferExpr pre)
        unless (compatibleWith preType TBool) $
          tcError $ "pre condition of '" <> name <> "' must be bool, got " <> typeLabel preType
    -- Check post-condition
    case contractPost contract of
      Nothing -> pure ()
      Just post -> do
        let resultType = fromMaybe bodyType mRet
        postType <- withEnv [("result", resultType)] (inferExpr post)
        unless (compatibleWith postType TBool) $
          tcError $ "post condition of '" <> name <> "' must be bool, got " <> typeLabel postType

checkStatement (SDefInterface name fns _laws) = do
  -- Register interface function signatures
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $
        "interface '" <> name <> "' function '" <> fname
        <> "' must have fn type, got " <> typeLabel other
  -- v0.6: type-check :laws expressions (must be Bool under interface context)
  -- Laws are parsed but not tested in v0.6 (LAWS-PO-1)
  forM_ _laws $ \lawExpr -> do
    let ifaceBindings = fns  -- interface method signatures as env
    lawType <- withEnv ifaceBindings (inferExpr lawExpr)
    unless (compatibleWith lawType TBool) $
      tcError $ "interface '" <> name <> "' :laws clause must be bool, got " <> typeLabel lawType

checkStatement (STypeDef name body) = do
  -- Check that dependent type constraints are well-formed
  case body of
    TDependent bindName base constraint -> do
      -- Bring binding variable into scope before checking the constraint
      ctype <- withEnv [(bindName, base)] (inferExpr constraint)
      unless (compatibleWith ctype TBool) $
        tcWarn $ "type '" <> name <> "' constraint should be bool, got " <> typeLabel ctype
    _ -> pure ()

checkStatement (SCheck prop) = do
  -- Property bindings become forall quantifiers
  withEnv (propBindings prop) $ do
    bodyType <- inferExpr (propBody prop)
    unless (compatibleWith bodyType TBool) $
      tcError $ "check property '" <> propDescription prop
        <> "': body must be bool, got " <> typeLabel bodyType

checkStatement (SImport imp) = do
  -- Register imported interface functions if specified
  case importInterface imp of
    Nothing -> pure ()
    Just fns -> forM_ fns $ \(fname, ftype) ->
      modify $ \s -> s { tcEnv = Map.insert fname ftype (tcEnv s) }

-- | SOpen: inject exported names from the referenced module as bare names.
-- Qualified names (module.path.f) must already be in the env via typeCheckWithCache.
-- We look for any key of the form "<dotted-path>.<name>" and add bare aliases.
-- Emits open-shadow-warning when a name collision occurs.
checkStatement (SOpen openPath_ mNames) = do
  let prefix = T.intercalate "." openPath_ <> "."
  env <- gets tcEnv
  let qualifying = Map.filterWithKey (\k _ -> prefix `T.isPrefixOf` k) env
      -- Strip prefix to get bare name
      bareExports = Map.mapKeys (T.drop (T.length prefix)) qualifying
      -- Apply selective open filter if present
      filtered = case mNames of
        Nothing -> bareExports
        Just ns -> Map.filterWithKey (\k _ -> k `elem` ns) bareExports
  -- Detect collisions and emit warnings
  forM_ (Map.toList filtered) $ \(bareName, ty) -> do
    mExisting <- tcLookup bareName
    case mExisting of
      Just _ -> tcWarn $
        "open-shadow-warning: '" <> bareName <> "' from " <> T.intercalate "." openPath_
        <> " shadows an existing binding"
      Nothing -> pure ()
    tcInsert bareName ty
    -- v0.3.5 (Phase C): tag open-imported bindings for checkout context
    modify $ \s -> s { tcProvenance = Map.insert bareName SrcOpenImport (tcProvenance s) }

-- | SExport is a compile-time annotation only; no type-checking action needed.
checkStatement (SExport _) = pure ()

-- | v0.3: STrust is already collected in checkStatements; no per-statement action.
checkStatement (STrust _ _) = pure ()

-- | v0.6: SWeaknessOk is collected by SpecCoverage; no per-statement type-check action.
checkStatement (SWeaknessOk _ _) = pure ()

checkStatement (SExpr expr) = do
  _ <- inferExpr expr
  pure ()

checkStatement (SDefMain { defMainStep = stepE, defMainDone = doneE }) = do
  -- Type-check the step and done? expressions
  _ <- inferExpr stepE
  case doneE of
    Nothing -> pure ()
    Just de -> do
      doneType <- inferExpr de
      unless (compatibleWith doneType TBool) $
        tcWarn ":done? should return bool; found non-bool type (ignored in v0.2)"

-- ---------------------------------------------------------------------------
-- v0.4 CAP-1: Capability Enforcement Helpers
-- ---------------------------------------------------------------------------

-- | Extract the WASI namespace from a fully-qualified function name.
-- e.g., "wasi.io.stdout" → "wasi.io", "wasi.fs.write" → "wasi.fs"
-- Takes the first two segments of the dotted path.
extractWasiNamespace :: Name -> Name
extractWasiNamespace func =
  T.intercalate "." (take 2 (T.splitOn "." func))

-- | CAP-1: Verify that a wasi.* function call has a matching capability import
-- in the current module's statement list. Capabilities are non-transitive:
-- module B importing module A does NOT inherit A's wasi capabilities.
-- Emits a structured missing-capability error if no matching import is found.
checkWasiCapability :: Name -> TC ()
checkWasiCapability func = do
  stmts <- gets tcModuleStmts
  let namespace = extractWasiNamespace func
      hasImport = any (matchesWasiImport namespace) stmts
  unless hasImport $
    modify $ \s -> s { tcErrors = tcErrors s ++ [mkMissingCapability func namespace] }
  where
    matchesWasiImport ns (SImport imp) = importPath imp == ns
    matchesWasiImport _ _ = False

-- ---------------------------------------------------------------------------
-- Expression Type Inference
-- ---------------------------------------------------------------------------

-- | True when an expression is a hole of any kind.
isHole :: Expr -> Bool
isHole (EHole _) = True
isHole _         = False

-- | Checking mode entry point.
-- At EHole (HNamed): records HoleTyped in sketch mode; reads JSON Pointer from TCState.
-- At other exprs: infer, then unify against expected (identical to existing behaviour).
checkExpr :: Expr -> Type -> TC ()
checkExpr (EHole (HNamed name)) expected =
  recordHole name (HoleTyped expected)
checkExpr (EHole hk) _ = void (inferHole hk)
checkExpr e expected   = inferExpr e >>= \actual -> unify "<check>" expected actual

-- | Infer the type of an expression.
inferExpr :: Expr -> TC Type
inferExpr (ELit lit) = pure (inferLiteral lit)

inferExpr (EVar name) = do
  mTy <- tcLookup name
  case mTy of
    Just ty -> pure ty
    Nothing -> do
      tcWarn $ "unbound variable '" <> name <> "' (may be in scope at runtime)"
      pure (TVar name)  -- Return type variable for unbound — not a hard error

inferExpr (ELet bindings body) = do
  -- EC-1: Save env before processing. The foldM below uses tcInsert to make
  -- each binding visible to subsequent bindings, which mutates tcEnv.
  -- We must restore to pre-let env after the let completes, so bindings
  -- don't leak to sibling expressions (e.g. else-branches in if).
  savedEnv <- gets tcEnv
  savedProv <- gets tcProvenance
  -- Process bindings sequentially: each binding extends the scope for the next
  -- PR 4: binding head is now Pattern, not Name.
  resolvedBindings <- foldM (\acc (pat, mAnnot, expr) -> do
    inferredTy <- inferExpr expr
    newBindings <- case pat of
      -- Simple variable binding (hot path — identical to old semantics)
      PVar n -> do
        let ty = case mAnnot of
                   Nothing     -> inferredTy
                   Just annotTy -> annotTy  -- trust annotation; unify below
        case mAnnot of
          Nothing     -> pure ()
          Just annotTy -> unify n annotTy inferredTy
        pure [(n, ty)]
      -- All other patterns (pair destructuring, nested, future extensions)
      _ -> checkPattern pat inferredTy
    -- Extend scope for subsequent bindings
    mapM_ (uncurry tcInsert) newBindings
    pure (acc ++ newBindings)
    ) [] bindings
  -- Restore to pre-let env, then use withTaggedEnv for the body only.
  -- This ensures foldM's tcInsert mutations don't leak to sibling expressions.
  modify $ \s -> s { tcEnv = savedEnv, tcProvenance = savedProv }
  withTaggedEnv SrcLetBinding resolvedBindings (inferExpr body)

inferExpr (EIf cond thenE elseE) = do
  condType <- inferExpr cond
  unless (compatibleWith condType TBool) $
    tcError $ "if condition must be bool, got " <> typeLabel condType
  -- Sketch propagation: if one branch is a hole, constrain it from the other.
  -- withSegment threads one RFC 6901 token per call so the stack stays clean.
  case (isHole thenE, isHole elseE) of
    (False, False) -> do
      -- Standard path (both concrete)
      thenType <- withSegment "then" (inferExpr thenE)
      elseType <- withSegment "else" (inferExpr elseE)
      if compatibleWith thenType elseType
        then pure thenType
        else do
          tcWarn $ "if branches have different types: " <> typeLabel thenType
                    <> " vs " <> typeLabel elseType
          pure thenType
    (False, True) -> do
      -- else is a hole: infer then, propagate into else
      thenType <- withSegment "then" (inferExpr thenE)
      withSegment "else" (checkExpr elseE thenType)
      pure thenType
    (True, False) -> do
      -- then is a hole: infer else, propagate into then
      elseType <- withSegment "else" (inferExpr elseE)
      withSegment "then" (checkExpr thenE elseType)
      pure elseType
    (True, True) -> do
      -- both holes: infer each (will emit HoleUnknown)
      withSegment "then" (void $ inferExpr thenE)
      withSegment "else" (void $ inferExpr elseE)
      pure (TVar "?")

inferExpr (EMatch expr cases) = do
  scrutType <- inferExpr expr
  -- Resolve through type aliases so we can see the structural TSumType body
  resolvedScrutType <- expandAlias scrutType
  -- Exhaustiveness check: only for TSumType where the full constructor set is known
  checkExhaustive resolvedScrutType cases
  -- Index all cases for reliable pointer paths
  let indexedCases = zip [0 :: Int ..] cases
      nonHoleArms  = [(i, pat, body) | (i, (pat, body)) <- indexedCases, not (isHole body)]
      holeArms     = [(i, pat, body) | (i, (pat, body)) <- indexedCases,     isHole body]
  -- Pass 1: synthesise non-hole arm bodies; track conflict.
  -- Each arm pointer uses three clean tokens: "arms" / i / "body"
  nonHoleResults <- forM nonHoleArms $ \(i, pat, body) -> do
    patBindings <- checkPattern pat resolvedScrutType
    t <- withTaggedEnv SrcMatchArm patBindings $
           withSegment "arms" $ withSegment (tshow i) $ withSegment "body" $
             inferExpr body
    pure t
  -- Unify non-hole arm types; on first mismatch record the conflicting pair
  (armT, mConflict) <- case nonHoleResults of
    [] -> pure (TVar "?", Nothing)
    (t:ts) -> foldM (\(acc, mc) t' ->
        if mc /= Nothing then pure (acc, mc)
        else if compatibleWith acc t' then pure (acc, Nothing)
             else do
               tcWarn $ "match arms have different types: " <> typeLabel acc <> " vs " <> typeLabel t'
               pure (acc, Just (acc, t'))
      ) (t, Nothing) ts
  -- Pass 2: check hole arm bodies against unified arm type (or record conflict/unknown)
  forM_ holeArms $ \(i, pat, body) -> do
    patBindings <- checkPattern pat resolvedScrutType
    withTaggedEnv SrcMatchArm patBindings $
      withSegment "arms" $ withSegment (tshow i) $ withSegment "body" $ do
        case body of
          EHole (HNamed name) -> do
            let status = case mConflict of
                  Just (t1, t2) -> HoleAmbiguous t1 t2
                  Nothing       -> if armT == TVar "?" then HoleUnknown else HoleTyped armT
            recordHole name status
            -- Emit ambiguous-hole diagnostic if conflict
            case mConflict of
              Just (t1, t2) -> emitAmbiguous name t1 t2
              Nothing       -> pure ()
          _ -> checkExpr body armT  -- non-named hole kinds
  pure $ if mConflict /= Nothing then TVar "?" else armT

inferExpr (EApp func args) = do
  -- v0.4 CAP-1: capability enforcement for wasi.* calls.
  -- Check is here (in inferExpr, not checkStatement) because EApp can appear
  -- in any nesting context: let RHS, if branches, match arms, do steps, contracts.
  when ("wasi." `T.isPrefixOf` func) $ checkWasiCapability func
  mFuncTy <- tcLookup func
  let nArgs = length args
  -- D2: warn when a plain def-logic calls itself recursively without :decreases
  isLetrec <- gets tcIsLetrec
  mCurrent <- gets tcCurrentFn
  when (mCurrent == Just func && not isLetrec) $
    tcWarn $ "self-recursive call to '" <> func <> "' inside def-logic; "
              <> "use (letrec " <> func <> " [...] :decreases ...) to provide a termination measure"
  -- v0.3: trust-gap warning for cross-module calls with unproven contracts
  do csMap  <- gets tcContractStatus
     trusts <- gets tcTrusts
     case Map.lookup func csMap of
       Nothing -> pure ()  -- no contract status known (local or unknown)
       Just cs -> do
         -- Check pre-condition
         emitTrustGap func trusts (csPreLevel cs)
         -- Check post-condition
         emitTrustGap func trusts (csPostLevel cs)
  case mFuncTy of
    Nothing -> do
      tcWarn $ "call to unknown function '" <> func <> "'"
      pure (TVar "?")  -- wildcard: don't inject false type mismatch downstream
    Just (TFn paramTypes retType) -> do
      when (nArgs /= length paramTypes) $ do
        let hint = if func == "string-concat" && nArgs > length paramTypes
                     then " \x2014 use string-concat-many for joining more than 2 strings"
                     else ""
        tcError $ "function '" <> func <> "' expects " <> tshow (length paramTypes)
                  <> " args, got " <> tshow nArgs <> hint
      -- v0.4 U-Lite: per-call-site substitution.
      -- Each call gets its own substitution map. When a polymorphic parameter
      -- (TVar "a") first encounters a concrete type, it binds a → T.
      -- Subsequent uses of the same TVar check consistency.
      finalSubst <- foldM (\subst (j, expected, arg) ->
        withSegment "args" $ withSegment (tshow (j :: Int)) $ do
          case arg of
            EHole hk -> do
              -- Holes: record with substituted type, don't contribute to subst
              checkExpr (EHole hk) (applySubst subst expected)
              pure subst
            _ -> do
              actual <- inferExpr arg
              expected' <- expandAlias expected
              actual'   <- expandAlias actual
              structuralUnify func subst (stripDep expected') (stripDep actual')
        ) Map.empty (zip3' [0 :: Int ..] paramTypes args)
      pure (applySubst finalSubst retType)
    Just (TCustom _) ->
      -- Might be a constructor call
      pure TUnit
    Just other -> do
      tcError $ "'" <> func <> "' is not a function, it has type " <> typeLabel other
      pure TUnit

inferExpr (EOp op _args) = do
  case Map.lookup op builtinEnv of
    Just (TFn _paramTypes retType) -> do
      -- Relax checking for polymorphic operators — just return their result type
      pure retType
    _ -> do
      -- Unknown operator — warn and return bool (most ops are comparisons)
      tcWarn $ "unknown operator '" <> op <> "'"
      pure TBool

inferExpr (EPair a b) = do
  ta <- inferExpr a
  tb <- inferExpr b
  pure (TPair ta tb)  -- PR 1: correct product type; was TResult (unsound)

inferExpr (EHole holeKind) = inferHole holeKind

inferExpr (EAwait expr) = do
  innerType <- inferExpr expr
  case innerType of
    TPromise t -> pure (TResult t TDelegationError)  -- v0.3 §3.2: await returns Result[t, DelegationError]
    other -> do
      tcWarn $ "await applied to non-Promise type " <> typeLabel other
      pure other  -- Best-effort: unwrap whatever

inferExpr (ELambda params body) = do
  bodyType <- withTaggedEnv SrcParam params (inferExpr body)
  pure (TFn (map snd params) bodyType)

inferExpr (EDo steps) = do
  case steps of
    [] -> pure TUnit
    _  -> inferDoSteps steps

-- | Infer the type of a hole expression.
inferHole :: HoleKind -> TC Type
inferHole (HNamed name) = do
  -- Synthesis context: no expected type reached this hole.
  -- Return TVar (\"?\" <> name) so isHoleVar fires on downstream unification
  -- failures, classifying them as holeSensitive (D3 invariant).
  recordHole name HoleUnknown
  tcWarn $ "unresolved named hole"
  pure (TVar ("?" <> name))  -- D3 canonical form: must use ?-prefixed TVar

inferHole (HChoose _options) = do
  tcWarn "unresolved ?choose hole"
  pure (TVar "?")

inferHole (HRequestCap cap) = do
  tcWarn $ "capability request hole for: " <> cap
  pure TUnit

inferHole (HScaffold spec) = do
  tcWarn $ "scaffold hole for template: " <> scaffoldTemplate spec
  pure TUnit

inferHole (HDelegate spec) = pure (delegateReturnType spec)

inferHole (HDelegateAsync spec) = pure (TPromise (delegateReturnType spec))

inferHole (HDelegatePending retType) = do
  tcError "blocking delegate hole — execution will stall"
  pure retType

inferHole HConflictResolution = do
  tcError "unresolved merge conflict hole"
  pure (TVar "?")

inferHole (HProofRequired reason) = do
  tcWarn $ "proof-required hole [" <> reason <> "]: needs formal verification"
  pure (TVar "?")

-- | Infer type from do-steps with pair-thread enforcement (PR 2).
-- Every step must return (S, Command) i.e. TPair S (TCustom "Command").
-- The state type S is unified across all steps.
inferDoSteps :: [DoStep] -> TC Type
inferDoSteps [] = pure TUnit
inferDoSteps steps = do
  let (DoStep mName0 e0) = head steps
  t0 <- withSegment "steps" $ withSegment "0" $ inferExpr e0
  (s0, _) <- expectPairType "do-block step 0" t0
  let binding0 = case mName0 of
        Just n  -> [(n, s0)]
        Nothing -> [("_s_0", s0)]
  withEnv binding0 $ go s0 (1 :: Int) (tail steps)
  where
    go sType _ [] = pure (TPair sType (TCustom "Command"))
    go sType i (DoStep mName e : rest) = do
      t <- withSegment "steps" $ withSegment (tshow i) $ inferExpr e
      (si, _) <- expectPairType ("do-block step " <> tshow i) t
      -- Unify S: all steps must thread the same state type
      unify ("do-block step " <> tshow i) sType si
      let bindName = case mName of
            Just n  -> n
            Nothing -> "_s_" <> tshow i
      withEnv [(bindName, si)] $ go sType (i + 1) rest

-- | Expect a TPair; emit "do-step-type-error" and return wildcard components
-- on failure so one bad step doesn't cascade and suppress subsequent errors.
expectPairType :: Text -> Type -> TC (Type, Type)
expectPairType _ (TPair a b) = pure (a, b)
expectPairType ctx t = do
  modify $ \s -> s { tcErrors = tcErrors s ++
    [(mkError Nothing ("do-step-type-error in " <> ctx <>
      ": step must return (S, Command), got " <> typeLabel t))
      { diagKind = Just "do-step-type-error" }] }
  pure (TVar "?", TCustom "Command")  -- wildcards; don't cascade

-- ---------------------------------------------------------------------------
-- Pattern Checking
-- ---------------------------------------------------------------------------
-- Exhaustiveness Checking (D1)
-- ---------------------------------------------------------------------------

-- | Check that a match expression is exhaustive for known sum types.
-- Only fires for TSumType, TResult, and TBool — all other types pass silently.
-- A wildcard (PWildcard) or variable (PVar) arm satisfies coverage for any type.
checkExhaustive :: Type -> [(Pattern, Expr)] -> TC ()
checkExhaustive scrutTy arms = do
  -- If any arm is a wildcard or variable, it catches everything
  let hasWildcard = any (isWild . fst) arms
  unless hasWildcard $ do
    let covered = [c | (PConstructor c _, _) <- arms]
    case scrutTy of
      TSumType ctors -> do
        let allCtors  = map fst ctors
            missing   = filter (`notElem` covered) allCtors
        unless (null missing) $
          tcEmitNonExhaustive (typeLabel scrutTy) missing covered
      TResult _ _ -> do
        -- Built-in: Success / Error must both be present
        -- NOTE: TPair is handled by the fallthrough `_ -> pure ()` case below;
        -- pair-typed scrutinees have no known constructor set to check exhaustively.
        let missing = filter (`notElem` covered) ["Success", "Error"]
        unless (null missing) $
          tcEmitNonExhaustive "Result" missing covered
      TBool -> do
        -- Built-in: True / False must both be present (if using ctor patterns)
        let boolCtors = filter (`elem` ["True", "False"]) covered
        unless (null boolCtors) $ do  -- only fire if they're using ctor patterns
          let missing = filter (`notElem` covered) ["True", "False"]
          unless (null missing) $
            tcEmitNonExhaustive "Bool" missing covered
      _ -> pure ()   -- unknown type — no false positives
  where
    isWild PWildcard = True
    isWild (PVar _)  = True
    isWild _         = False

-- ---------------------------------------------------------------------------
-- Pattern Checking
-- ---------------------------------------------------------------------------

-- | Type-check a pattern against a scrutinee type, returning new bindings.
checkPattern :: Pattern -> Type -> TC [(Name, Type)]
checkPattern PWildcard _ = pure []
checkPattern (PVar name) ty = pure [(name, ty)]
checkPattern (PLiteral lit) scrutTy = do
  let litTy = inferLiteral lit
  unless (compatibleWith litTy scrutTy) $
    tcWarn $ "literal pattern type " <> typeLabel litTy
              <> " may not match scrutinee type " <> typeLabel scrutTy
  pure []
checkPattern (PConstructor ctor subPats) scrutTy = do
  -- Built-in constructors: Success(v), Error(e)
  case (ctor, scrutTy) of
    ("Success", TResult t _) ->
      case subPats of
        [p] -> checkPattern p t
        _   -> do { tcError "Success takes one argument"; pure [] }
    ("Error", TResult _ e) ->
      case subPats of
        [p] -> checkPattern p e
        _   -> do { tcError "Error takes one argument"; pure [] }
    -- TSumType: look up the constructor in the known-good constructor list
    (_, TSumType ctorList) ->
      case lookup ctor ctorList of
        Nothing ->
          do { tcWarn $ "unknown constructor '" <> ctor <> "' for sum type"; pure [] }
        Just Nothing ->
          -- Nullary constructor
          if null subPats then pure []
          else do { tcWarn $ "constructor '" <> ctor <> "' takes no arguments"; pure [] }
        Just (Just payload) ->
          case subPats of
            [p] -> checkPattern p payload
            _   -> do { tcWarn $ "constructor '" <> ctor <> "' takes one argument"; pure [] }
    -- PR 4: Built-in pair constructor: (pair fst snd)
    ("pair", TPair a b) ->
      case subPats of
        [p1, p2] -> do
          bs1 <- checkPattern p1 a
          bs2 <- checkPattern p2 b
          pure (bs1 ++ bs2)
        _ -> do { tcError "pair destructor takes exactly two sub-patterns"; pure [] }
    _ -> do
      -- Unknown constructor — bind sub patterns as type vars
      bindings <- forM (zip [0..] subPats) $ \(i, p) ->
        checkPattern p (TVar (ctor <> tshow (i :: Int)))
      pure (concat bindings)

-- ---------------------------------------------------------------------------
-- v0.4 U-Lite / v0.5 U-Full: Per-Call-Site Substitution Helpers
-- ---------------------------------------------------------------------------

-- | Apply a type variable substitution map to a type, recursively.
applySubst :: Map Name Type -> Type -> Type
applySubst subst t@(TVar a)       = Map.findWithDefault t a subst
applySubst subst (TList t)        = TList (applySubst subst t)
applySubst subst (TResult a b)    = TResult (applySubst subst a) (applySubst subst b)
applySubst subst (TPair a b)      = TPair (applySubst subst a) (applySubst subst b)
applySubst subst (TFn ps r)       = TFn (map (applySubst subst) ps) (applySubst subst r)
applySubst subst (TPromise t)     = TPromise (applySubst subst t)
applySubst subst (TMap k v)       = TMap (applySubst subst k) (applySubst subst v)
applySubst subst (TDependent n b e) = TDependent n (applySubst subst b) e
applySubst _     t                = t  -- TInt, TString, TBool, TUnit, TBytes, TCustom, TSumType, TFloat

-- | Strip TDependent to its base type (ignores the constraint).
stripDep :: Type -> Type
stripDep (TDependent _ base _) = base
stripDep t = t

-- | v0.5 U1-full: Check if a type variable occurs in a type (infinite type guard).
-- Must be structurally total over the Type ADT (Language Team review, 2026-04-21).
occursIn :: Name -> Type -> Bool
occursIn a (TVar b)           = a == b
occursIn a (TList t)          = occursIn a t
occursIn a (TResult x y)      = occursIn a x || occursIn a y
occursIn a (TPair x y)        = occursIn a x || occursIn a y
occursIn a (TFn ps r)         = any (occursIn a) ps || occursIn a r
occursIn a (TPromise t)       = occursIn a t
occursIn a (TMap k v)         = occursIn a k || occursIn a v
occursIn a (TDependent _ b _) = occursIn a b
occursIn a (TSumType ctors)   = any (\(_, mT) -> maybe False (occursIn a) mT) ctors
occursIn _ _                  = False  -- TInt, TString, TBool, TUnit, TBytes, TCustom, TFloat, TDelegationError

-- | Structural unification with substitution tracking.
-- When a TVar in the expected type first encounters a concrete actual type,
-- it's bound in the substitution map. If the same TVar is encountered again
-- with a different concrete type, a type-mismatch error is emitted.
--
-- v0.5 U-Full: TVar-TVar now binds (wildcard closure). Occurs check prevents
-- infinite types. Bound-TVar consistency uses recursive structuralUnify
-- instead of compatibleWith (Language Team Issue 2, 2026-04-21).
structuralUnify :: Name -> Map Name Type -> Type -> Type -> TC (Map Name Type)
structuralUnify func subst expected actual =
  case (expected, actual) of
    -- TVar expected: check or bind in substitution
    (TVar a, _) ->
      case Map.lookup a subst of
        -- v0.5 U2-full (Issue 2): Already bound — recursively unify the bound
        -- type against the actual. This ensures that TVar-TVar bindings are
        -- enforced: if a → TVar "b" and actual = TString, the recursive call
        -- will extend the substitution with b → TString. Using compatibleWith
        -- here would silently wildcard (TVar _ matches anything) and defeat
        -- the substitution mechanism.
        --
        -- SUBSTITUTION CYCLE RISK (Language Team, 2026-04-21): If subst
        -- contains a → TVar "b" AND b → TVar "a", this recursive call will
        -- loop forever (a → b → a → ...). The occurs check (occursIn) does
        -- NOT cover this — it inspects structural occurrence in the Type AST,
        -- not cycles in the substitution map. Currently safe because:
        --   (1) The reflexive guard at L1076 blocks a → TVar "a".
        --   (2) Per-call-site scoping means subst is fresh per EApp, limiting
        --       the window for transitive TVar chains.
        -- If global substitution or cross-EApp constraint sharing is ever
        -- introduced, add a visited-set parameter or path-compression pass.
        Just bound -> structuralUnify func subst bound actual
        Nothing ->
          case actual of
            -- v0.5 U2-full: TVar-TVar wildcard closure.
            -- Bind TVar to TVar so constraints propagate through chains.
            -- Reflexive case (a == b) produces no new information.
            TVar b
              | a == b    -> pure subst  -- reflexive: no new info
              | otherwise -> pure (Map.insert a actual subst)  -- bind TVar to TVar
            -- v0.5 U1-full: Occurs check before binding.
            -- Prevents infinite types like a ~ list[a].
            _      -> if occursIn a actual
                        then do
                          tcError $ "infinite type: " <> a <> " occurs in " <> typeLabel actual
                          pure subst
                        else pure (Map.insert a actual subst)  -- bind

    -- TVar actual: wildcard (can't constrain from the expected-type side).
    -- SAFETY (Language Team review, 2026-04-21): This is correct only because
    -- substitution scope is per-call-site. The substitution map created in
    -- inferExpr (EApp ...) does NOT escape the EApp boundary. If we ever move
    -- to global substitution, this line becomes a soundness hole — actual TVars
    -- from return types would need to participate in the global constraint set.
    (_, TVar _) -> pure subst

    -- Structural recursion for compound types
    (TList a, TList b) -> structuralUnify func subst a b

    (TResult a b, TResult c d) -> do
      s1 <- structuralUnify func subst a c
      structuralUnify func s1 b d

    (TPair a b, TPair c d) -> do
      s1 <- structuralUnify func subst a c
      structuralUnify func s1 b d

    (TPromise a, TPromise b) -> structuralUnify func subst a b

    (TMap k1 v1, TMap k2 v2) -> do
      s1 <- structuralUnify func subst k1 k2
      structuralUnify func s1 v1 v2

    (TFn as r, TFn bs s) ->
      if length as == length bs then do
        s1 <- foldM (\st (a, b) -> structuralUnify func st a b) subst (zip as bs)
        structuralUnify func s1 r s
      else do
        tcTypeMismatch func expected actual
        pure subst

    -- TDependent: strip and compare base type
    (TDependent _ a _, b) -> structuralUnify func subst a b
    (a, TDependent _ b _) -> structuralUnify func subst a b

    -- TCustom wildcard
    (TCustom "_", _) -> pure subst
    (_, TCustom "_") -> pure subst

    -- Fallback: structural equality via compatibleWith
    _ ->
      if compatibleWith expected actual
        then pure subst
        else do
          tcTypeMismatch func expected actual
          pure subst

-- | Zip three lists (truncating to shortest).
zip3' :: [a] -> [b] -> [c] -> [(a, b, c)]
zip3' (a:as) (b:bs) (c:cs) = (a, b, c) : zip3' as bs cs
zip3' _ _ _ = []

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------

-- | Infer type of a literal.
inferLiteral :: Literal -> Type
inferLiteral (LitInt _)    = TInt
inferLiteral (LitFloat _)  = TFloat
inferLiteral (LitString _) = TString
inferLiteral (LitBool _)   = TBool
inferLiteral LitUnit       = TUnit

-- | Check if two types are compatible (structural equality, with TVar wildcard).
-- TDependent is checked by its base type only (constraint not evaluated).
compatibleWith :: Type -> Type -> Bool
compatibleWith (TVar _) _            = True  -- type variable matches anything
compatibleWith _ (TVar _)            = True
compatibleWith (TCustom "_") _       = True  -- untyped param wildcard
compatibleWith _ (TCustom "_")       = True
compatibleWith (TCustom a) (TCustom b) = a == b
compatibleWith (TDependent _ a _) b   = compatibleWith a b
compatibleWith a (TDependent _ b _)   = compatibleWith a b
compatibleWith (TList a) (TList b)  = compatibleWith a b
compatibleWith (TMap k1 v1) (TMap k2 v2) = compatibleWith k1 k2 && compatibleWith v1 v2
compatibleWith (TResult a b) (TResult c d) = compatibleWith a c && compatibleWith b d
-- PR 1: TPair structural equality (both components must match)
compatibleWith (TPair a b) (TPair c d) = compatibleWith a c && compatibleWith b d
compatibleWith (TPromise a) (TPromise b) = compatibleWith a b
compatibleWith (TFn as r) (TFn bs s) =
  length as == length bs && all (uncurry compatibleWith) (zip as bs) && compatibleWith r s
compatibleWith (TBytes m) (TBytes n) = m == n
-- TSumType: compatible with itself and with TCustom of the same registered name
-- TSumType: structural constructor equality (v0.4 U7-lite)
-- Before U-lite: any sum ≡ any sum (unsound). Now requires matching constructors.
compatibleWith (TSumType a) (TSumType b) = map fst a == map fst b
compatibleWith (TCustom _)  (TSumType _) = True  -- aliases resolved via expandAlias
compatibleWith (TSumType _)  (TCustom _) = True  -- aliases resolved via expandAlias
compatibleWith a b = a == b

-- | Unify two types, emitting an error if they are incompatible.
-- | Expand a TCustom alias to its structural body if one is registered.
-- Leaves all other types unchanged.
expandAlias :: Type -> TC Type
expandAlias (TCustom n) = do
  am <- gets tcAliasMap
  pure $ fromMaybe (TCustom n) (Map.lookup n am)
expandAlias t = pure t

unify :: Name -> Type -> Type -> TC ()
unify ctx expected actual = do
  expected' <- expandAlias expected
  actual'   <- expandAlias actual
  unless (compatibleWith expected' actual') $
    -- Use structured type-mismatch error with separate expected/got fields (D5).
    tcTypeMismatch ctx expected' actual'

-- | zipWithM_ with indices.
zipWithM_ :: Monad m => (a -> b -> m c) -> [a] -> [b] -> m ()
zipWithM_ f xs ys = sequence_ (zipWith f xs ys)

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Result Type
-- ---------------------------------------------------------------------------

-- | Extended result that includes the inferred type environment.
data TypeCheckResult = TypeCheckResult
  { tcrReport :: DiagnosticReport
  , tcrEnv    :: TypeEnv   -- ^ Environment after processing (with top-level defs)
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Sketch Mode (Phase 2c: --sketch)
-- ---------------------------------------------------------------------------

-- | Result of running the type checker in sketch mode.
data SketchResult = SketchResult
  { sketchHoles      :: [SketchHole]           -- ^ holes in source order
  , sketchErrors     :: [Diagnostic]           -- ^ type errors present in partial program
  , sketchInvariants :: [InvariantSuggestion]  -- ^ v0.4: matched invariant suggestions
  } deriving (Show)

-- | Run the type checker in sketch mode.
-- Accepts partial programs with holes everywhere. Returns each named hole's
-- status (Typed / Ambiguous / Unknown) and JSON Pointer, plus any type errors.
-- v0.4: Also matches function signatures against the invariant pattern registry.
runSketch :: TypeEnv -> [Statement] -> [InvariantPattern] -> SketchResult
runSketch env stmts patterns =
  let action          = checkStatements stmts
      (_, finalState) = runTCSketch env action
      -- v0.4: Match each def-logic / letrec against invariant patterns
      invariants = concatMap (matchStmt (tcEnv finalState)) stmts
  in SketchResult
       { sketchHoles      = reverse (tcHoles finalState)
       , sketchErrors     = tcErrors finalState
       , sketchInvariants = invariants
       }
  where
    matchStmt _ (SDefLogic name params mRetType _ _) =
      let paramTypes = map snd params
          retType    = fromMaybe (TCustom "_") mRetType
          fnType     = TFn paramTypes retType
      in matchPatterns name fnType patterns
    matchStmt _ (SLetrec name params mRetType _ _ _) =
      let paramTypes = map snd params
          retType    = fromMaybe (TCustom "_") mRetType
          fnType     = TFn paramTypes retType
      in matchPatterns name fnType patterns
    matchStmt _ _ = []
