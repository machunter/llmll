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
    -- * Environment
  , TypeEnv
  , emptyEnv
  , extendEnv
    -- * Results
  , TypeCheckResult(..)
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, fromMaybe)
import Control.Monad (forM_, forM, when, unless)
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
  , ("pair",   TFn [TVar "a", TVar "b"] (TResult (TVar "a") (TVar "b")))
  , ("first",  TFn [TResult (TVar "a") (TVar "b")] (TVar "a"))
  , ("second", TFn [TResult (TVar "a") (TVar "b")] (TVar "b"))
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
  , ("range",         TFn [TInt, TInt] (TList TInt))
  -- §13.6 String operations
  , ("string-length",   TFn [TString] TInt)
  , ("string-contains", TFn [TString, TString] TBool)
  , ("string-concat",   TFn [TString, TString] TString)
  , ("string-slice",    TFn [TString, TInt, TInt] TString)
  , ("string-char-at",  TFn [TString, TInt] TString)
  , ("string-split",    TFn [TString, TString] (TList TString))
  , ("regex-match",     TFn [TString, TString] TBool)
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
  -- §13.misc Misc
  , ("is-valid?", TFn [TBool] TBool)
  ]

emptyEnv :: TypeEnv
emptyEnv = builtinEnv

extendEnv :: Name -> Type -> TypeEnv -> TypeEnv
extendEnv = Map.insert

-- ---------------------------------------------------------------------------
-- Type Checker Monad
-- ---------------------------------------------------------------------------

data TCState = TCState
  { tcEnv    :: TypeEnv
  , tcErrors :: [Diagnostic]
  } deriving (Show)

type TC a = State TCState a

-- | Emit a type error.
tcError :: Text -> TC ()
tcError msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkError Nothing msg] }

-- | Emit a type warning.
tcWarn :: Text -> TC ()
tcWarn msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkWarning Nothing msg] }

-- | Look up a name in the environment.
tcLookup :: Name -> TC (Maybe Type)
tcLookup name = gets (Map.lookup name . tcEnv)

-- | Run a computation in an extended environment.
withEnv :: [(Name, Type)] -> TC a -> TC a
withEnv bindings action = do
  old <- gets tcEnv
  modify $ \s -> s { tcEnv = foldr (uncurry Map.insert) old bindings }
  result <- action
  modify $ \s -> s { tcEnv = old }
  pure result

-- | Run the type checker monad.
runTC :: TypeEnv -> TC a -> (a, [Diagnostic])
runTC env action =
  let (result, st) = runState action (TCState env [])
  in (result, tcErrors st)

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

-- ---------------------------------------------------------------------------
-- Statement Checking
-- ---------------------------------------------------------------------------

-- | Build top-level environment from definitions, then check each statement.
checkStatements :: [Statement] -> TC ()
checkStatements stmts = do
  -- First pass: collect all top-level function and type names
  let topLevel = mapMaybe collectTopLevel stmts
  withEnv topLevel $ do
    -- Second pass: check each statement in order
    mapM_ checkStatement stmts

-- | Extract (name, type) for top-level definitions (for forward references).
collectTopLevel :: Statement -> Maybe (Name, Type)
collectTopLevel (SDefLogic name params mRet _contract _body) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet  -- no annotation => polymorphic wildcard
  in Just (name, TFn argTypes retType)
collectTopLevel (SDefInterface name fns) =
  Just (name, TCustom name)  -- interfaces register as custom types
collectTopLevel (STypeDef name body) =
  Just (name, TCustom name)  -- type aliases register as custom types
collectTopLevel _ = Nothing

checkStatement :: Statement -> TC ()
checkStatement (SDefLogic name params mRet contract body) = do
  let paramBindings = params
  withEnv paramBindings $ do
    -- Infer body type
    bodyType <- inferExpr body
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

checkStatement (SDefInterface name fns) = do
  -- Register interface function signatures
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $
        "interface '" <> name <> "' function '" <> fname
        <> "' must have fn type, got " <> typeLabel other

checkStatement (STypeDef name body) = do
  -- Check that dependent type constraints are well-formed
  case body of
    TDependent base constraint -> do
      -- Constraint should be boolean
      ctype <- inferExpr constraint
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
-- Expression Type Inference
-- ---------------------------------------------------------------------------

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
  -- Process bindings sequentially, each can refer to previous
  resolvedBindings <- forM bindings $ \(n, mAnnot, expr) -> do
    inferredTy <- inferExpr expr
    let ty = case mAnnot of
              Nothing -> inferredTy
              Just annotTy -> annotTy  -- trust annotation; unify below
    case mAnnot of
      Nothing -> pure ()
      Just annotTy -> unify n annotTy inferredTy
    pure (n, ty)
  withEnv resolvedBindings (inferExpr body)

inferExpr (EIf cond thenE elseE) = do
  condType <- inferExpr cond
  unless (compatibleWith condType TBool) $
    tcError $ "if condition must be bool, got " <> typeLabel condType
  thenType <- inferExpr thenE
  elseType <- inferExpr elseE
  -- Both branches should have compatible types
  if compatibleWith thenType elseType
    then pure thenType
    else do
      tcWarn $ "if branches have different types: " <> typeLabel thenType
                <> " vs " <> typeLabel elseType
      pure thenType

inferExpr (EMatch expr cases) = do
  scrutType <- inferExpr expr
  caseTypes <- forM cases $ \(pat, body) -> do
    patBindings <- checkPattern pat scrutType
    withEnv patBindings (inferExpr body)
  case caseTypes of
    []     -> pure TUnit
    (t:ts) -> do
      forM_ ts $ \t' ->
        unless (compatibleWith t t') $
          tcWarn $ "match arms have different types: " <> typeLabel t <> " vs " <> typeLabel t'
      pure t

inferExpr (EApp func args) = do
  mFuncTy <- tcLookup func
  argTypes <- mapM inferExpr args
  case mFuncTy of
    Nothing -> do
      tcWarn $ "call to unknown function '" <> func <> "'"
      pure (TVar "?")  -- wildcard: don't inject false type mismatch downstream
    Just (TFn paramTypes retType) -> do
      when (length argTypes /= length paramTypes) $
        tcError $ "function '" <> func <> "' expects " <> tshow (length paramTypes)
                  <> " args, got " <> tshow (length argTypes)
      zipWithM_ (\expected actual -> unify func expected actual) paramTypes argTypes
      pure retType
    Just (TCustom _) ->
      -- Might be a constructor call
      pure TUnit
    Just other -> do
      tcError $ "'" <> func <> "' is not a function, it has type " <> typeLabel other
      pure TUnit

inferExpr (EOp op args) = do
  argTypes <- mapM inferExpr args
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
  pure (TResult ta tb)  -- Pair used as (state, command) — approximate as Result

inferExpr (EHole holeKind) = inferHole holeKind

inferExpr (EAwait expr) = do
  innerType <- inferExpr expr
  case innerType of
    TPromise t -> pure t
    other -> do
      tcWarn $ "await applied to non-Promise type " <> typeLabel other
      pure other  -- Best-effort: unwrap whatever

inferExpr (ELambda params body) = do
  bodyType <- withEnv params (inferExpr body)
  pure (TFn (map snd params) bodyType)

inferExpr (EDo steps) = do
  case steps of
    [] -> pure TUnit
    _  -> inferDoSteps steps

-- | Infer the type of a hole expression.
inferHole :: HoleKind -> TC Type
inferHole (HNamed _name) = do
  tcWarn $ "unresolved named hole"
  pure (TVar "?")  -- Unknown type, will be resolved when hole is filled

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

-- | Infer type from do-steps (chained monadic computation).
inferDoSteps :: [DoStep] -> TC Type
inferDoSteps [] = pure TUnit
inferDoSteps [DoExpr e] = inferExpr e
inferDoSteps [DoBind _ e] = inferExpr e
inferDoSteps (DoExpr e : rest) = do
  _ <- inferExpr e
  inferDoSteps rest
inferDoSteps (DoBind name e : rest) = do
  ty <- inferExpr e
  -- Unwrap Promise if needed
  let innerTy = case ty of { TPromise t -> t; t -> t }
  withEnv [(name, innerTy)] (inferDoSteps rest)

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
    _ -> do
      -- Unknown constructor — bind sub patterns as type vars
      bindings <- forM (zip [0..] subPats) $ \(i, p) ->
        checkPattern p (TVar (ctor <> tshow (i :: Int)))
      pure (concat bindings)

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
compatibleWith (TDependent a _) b   = compatibleWith a b
compatibleWith a (TDependent b _)   = compatibleWith a b
compatibleWith (TList a) (TList b)  = compatibleWith a b
compatibleWith (TMap k1 v1) (TMap k2 v2) = compatibleWith k1 k2 && compatibleWith v1 v2
compatibleWith (TResult a b) (TResult c d) = compatibleWith a c && compatibleWith b d
compatibleWith (TPromise a) (TPromise b) = compatibleWith a b
compatibleWith (TFn as r) (TFn bs s) =
  length as == length bs && all (uncurry compatibleWith) (zip as bs) && compatibleWith r s
compatibleWith (TBytes m) (TBytes n) = m == n
compatibleWith a b = a == b

-- | Unify two types, emitting an error if they are incompatible.
unify :: Name -> Type -> Type -> TC ()
unify ctx expected actual =
  unless (compatibleWith expected actual) $
    tcError $ "type mismatch in '" <> ctx <> "': expected " <> typeLabel expected
              <> ", got " <> typeLabel actual

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
