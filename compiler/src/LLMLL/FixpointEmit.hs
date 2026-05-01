-- |
-- Module      : LLMLL.FixpointEmit
-- Description : Walk LLMLL typed AST → .fq constraint file + ConstraintTable.
--
-- D4: Decoupled verification backend.
--
-- Coverage: QF linear integer arithmetic only.
--   - Integer params / return types
--   - Linear pre/post predicates (+, -, =, <, <=, >=, >)
--   - Simple letrec termination measures (single-variable or constant)
--   - TSumType sort declarations
--
-- Non-linear sites (HProofRequired holes from D3) are skipped — the compiler
-- already flagged them; the verifier simply omits them from the .fq output.
--
-- FAITHFULNESS INVARIANT (v0.3, updated v0.8.0):
-- This module's output is trusted by --contracts=unproven. If emitFixpoint
-- reports SAFE for a contract, the runtime assertion for that contract must
-- be semantically redundant for all well-typed inputs. Any extension to
-- exprToPred must preserve this invariant: never translate a contract to a
-- weaker .fq constraint that the solver accepts trivially.
--
-- BODY-VC (v0.8.0):
-- When EmitOptions.emitBodyVCs is True, function bodies in the supported
-- QF-LIA fragment are translated to verification conditions via bodyToPredM.
-- Body VCs prove: P ∧ (result = ⟦body⟧) ⟹ Q (postcondition faithfulness).
-- Functions outside the fragment fall back to contract-only verification.

module LLMLL.FixpointEmit
  ( -- * Top-level emitter
    emitFixpoint
  , emitFixpointWith
    -- * Configuration
  , EmitOptions(..)
  , defaultEmitOptions
    -- * Result
  , EmitResult(..)
    -- * Alias map (v0.8.0)
  , AliasMap
  , buildAliasMap
  , isIntLike
    -- * Body-VC types (exported for testing)
  , BodyVC(..)
  , LetBinding(..)
  , FlatPath
  , SortEnv
    -- * Body-VC engine (exported for testing)
  , bodyToPredFrom
  , flattenBodyVC
  , countPathsBounded
    -- * Contract translation (exported for testing)
  , exprToPred
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.IORef
import Data.Maybe (fromMaybe, mapMaybe, isJust, catMaybes)
import Control.Monad (forM_, forM, when, unless)
import Control.Monad.State.Strict (State, evalState, get, put)

import LLMLL.Syntax
import LLMLL.FixpointIR
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable)
import LLMLL.Diagnostic (Diagnostic, mkWarning)

-- ---------------------------------------------------------------------------
-- Configuration (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Options controlling what the emitter generates.
data EmitOptions = EmitOptions
  { emitBodyVCs :: Bool   -- ^ Emit body-faithful verification conditions
  } deriving (Show, Eq)

defaultEmitOptions :: EmitOptions
defaultEmitOptions = EmitOptions { emitBodyVCs = False }

-- ---------------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------------

data EmitResult = EmitResult
  { erFQFile          :: FQFile           -- ^ the assembled .fq data structure
  , erFQText          :: Text             -- ^ .fq text ready to write to disk
  , erConstraintTable :: ConstraintTable  -- ^ ID → origin (for DiagnosticFQ)
  , erSkipped         :: [Text]           -- ^ names of skipped non-linear functions
  , erBodyFaithfulFns :: [Text]           -- ^ v0.8.0: functions with successful body VCs
  , erBodyFallback    :: [Text]           -- ^ v0.8.0: functions that fell back
  , erDiagnostics     :: [Diagnostic]     -- ^ v0.8.0: path-limit warnings, etc.
  , erEmittedPre      :: [Text]           -- ^ v0.8.0: functions whose pre emitted a constraint
  , erEmittedPost     :: [Text]           -- ^ v0.8.0: functions whose post emitted a constraint
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Body-VC types (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Sort environment: maps variable names to their FQ sorts.
-- Used by bodyToPredM to reject non-int vars in the QF-LIA fragment.
type SortEnv = Map Name FQSort

-- | A body verification condition tree.
data BodyVC
  = SimpleVC [LetBinding] FQPred
    -- ^ A straight-line sequence of let-bindings followed by a result predicate
  | BranchVC FQPred BodyVC BodyVC
    -- ^ An if-then-else: guard, then-VC, else-VC
  deriving (Show, Eq)

-- | A single let-binding in the body VC.
data LetBinding = LetBinding
  { lbName :: Text     -- ^ Alpha-renamed variable name
  , lbSort :: FQSort   -- ^ Sort of the binding
  , lbRhs  :: FQPred   -- ^ RHS predicate (what the variable equals)
  } deriving (Show, Eq)

-- | A flattened path through the body-VC tree:
-- (path guard conjunction, accumulated let-bindings, result predicate)
type FlatPath = (FQPred, [LetBinding], FQPred)

-- ---------------------------------------------------------------------------
-- Built-in qualifier safety net
-- ---------------------------------------------------------------------------

builtinQualifiers :: [FQQualifier]
builtinQualifiers =
  [ FQQualifier "True"  [("v", FQInt)]                       FQTrue
  , FQQualifier "GEZ"   [("v", FQInt)]                       (FQBinPred FQGe (FQVar "v") (FQLit 0))
  , FQQualifier "GTZ"   [("v", FQInt)]                       (FQBinPred FQGt (FQVar "v") (FQLit 0))
  , FQQualifier "EqZ"   [("v", FQInt)]                       (FQBinPred FQEq (FQVar "v") (FQLit 0))
  , FQQualifier "Eq"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQEq (FQVar "v") (FQVar "w"))
  , FQQualifier "GE"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQGe (FQVar "v") (FQVar "w"))
  , FQQualifier "GT"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQGt (FQVar "v") (FQVar "w"))
  ]

-- ---------------------------------------------------------------------------
-- Top-level emitter
-- ---------------------------------------------------------------------------

-- | Walk a list of top-level statements and emit a .fq constraint file.
-- The function is pure in terms of result, but uses IORef internally for
-- the sequential constraint-ID counter and ConstraintTable accumulator.
-- | Emit constraints using default options (no body VCs).
emitFixpoint :: FilePath -> [Statement] -> IO EmitResult
emitFixpoint = emitFixpointWith defaultEmitOptions

-- | Emit constraints with explicit options.
emitFixpointWith :: EmitOptions -> FilePath -> [Statement] -> IO EmitResult
emitFixpointWith opts srcFile stmts = do
  -- v0.8.0: build alias map from STypeDef statements for isIntLike resolution
  let aliases = buildAliasMap stmts
  ctrRef    <- newIORef (0 :: Int)  -- constraint ID counter
  bindRef   <- newIORef (0 :: Int)  -- binder ID counter
  tableRef  <- newIORef (Map.empty :: ConstraintTable)
  skippedRef<- newIORef ([] :: [Text])
  bindsRef  <- newIORef ([] :: [FQBind])
  constsRef <- newIORef ([] :: [FQConstraint])
  qualsRef  <- newIORef builtinQualifiers
  dataRef   <- newIORef ([] :: [FQDataDecl])
  -- v0.8.0: body-VC global alpha-renaming counter (E08: shared across functions)
  bodyCounterRef <- newIORef (0 :: Int)
  bodyFaithfulRef <- newIORef ([] :: [Text])
  bodyFallbackRef <- newIORef ([] :: [Text])
  diagsRef <- newIORef ([] :: [Diagnostic])
  emittedPreRef <- newIORef ([] :: [Text])
  emittedPostRef <- newIORef ([] :: [Text])

  let freshCid = do
        n <- readIORef ctrRef
        modifyIORef' ctrRef (+1)
        return n

  let freshBid = do
        n <- readIORef bindRef
        modifyIORef' bindRef (+1)
        return n

  let addBind b   = modifyIORef' bindsRef (++ [b])
  let addConst c  = modifyIORef' constsRef (++ [c])
  let addQuals qs = modifyIORef' qualsRef (++ qs)
  let addData  d  = modifyIORef' dataRef  (++ [d])
  let addSkip  n  = modifyIORef' skippedRef (++ [n])
  let addOrigin cid orig = modifyIORef' tableRef (Map.insert cid orig)
  let addBodyFaithful n = modifyIORef' bodyFaithfulRef (++ [n])
  let addBodyFallback n = modifyIORef' bodyFallbackRef (++ [n])
  let addDiag d = modifyIORef' diagsRef (++ [d])
  let addEmittedPre n = modifyIORef' emittedPreRef (++ [n])
  let addEmittedPost n = modifyIORef' emittedPostRef (++ [n])

  -- Process each statement
  forM_ (zip [0..] stmts) $ \(idx, stmt) ->
    case stmt of
      STypeDef name body ->
        -- Emit ADT sorts for TSumType members
        forM_ (typeSorts name body) addData

      SDefLogic name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost bodyCounterRef aliases
          name params mRet contract (Just body) Nothing idx

      SLetrec name params mRet contract dec body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost bodyCounterRef aliases
          name params mRet contract Nothing (Just dec) idx

      _ -> pure ()

  -- Assemble result
  dataDecs  <- readIORef dataRef
  quals     <- readIORef qualsRef
  binds     <- readIORef bindsRef
  consts    <- readIORef constsRef
  table     <- readIORef tableRef
  skipped   <- readIORef skippedRef
  bfaithful <- readIORef bodyFaithfulRef
  bfallback <- readIORef bodyFallbackRef
  diags     <- readIORef diagsRef
  emPre     <- readIORef emittedPreRef
  emPost    <- readIORef emittedPostRef
  let fqFile = FQFile dataDecs quals binds consts
  return EmitResult
    { erFQFile          = fqFile
    , erFQText          = emitFQFile fqFile
    , erConstraintTable = table
    , erSkipped         = skipped
    , erBodyFaithfulFns = bfaithful
    , erBodyFallback    = bfallback
    , erDiagnostics     = diags
    , erEmittedPre      = emPre
    , erEmittedPost     = emPost
    }

-- ---------------------------------------------------------------------------
-- Per-function constraint emission
-- ---------------------------------------------------------------------------

emitFnConstraints
  :: EmitOptions
  -> FilePath
  -> IO FQConstraintId    -- fresh constraint ID
  -> IO FQBindId          -- fresh binder ID
  -> (FQBind       -> IO ())
  -> (FQConstraint -> IO ())
  -> ([FQQualifier] -> IO ())
  -> (Text -> IO ())       -- record skipped function
  -> (FQConstraintId -> ConstraintOrigin -> IO ())
  -> (Text -> IO ())       -- record body-faithful function
  -> (Text -> IO ())       -- record body-fallback function
  -> (Diagnostic -> IO ()) -- emit diagnostics
  -> (Text -> IO ())       -- v0.8.0: record emitted pre clause
  -> (Text -> IO ())       -- v0.8.0: record emitted post clause
  -> IORef Int             -- body-VC alpha-renaming counter
  -> AliasMap              -- v0.8.0: type alias map for isIntLike
  -> Name
  -> [(Name, Type)]
  -> Maybe Type
  -> Contract
  -> Maybe Expr            -- Just body = function body (Nothing for letrec)
  -> Maybe Expr            -- Just dec = letrec :decreases
  -> Int                   -- statement index (for JSON Pointer)
  -> IO ()
emitFnConstraints opts srcFile freshCid freshBid addBind addConst addQuals
    addSkip addOrigin addBodyFaithful addBodyFallback addDiag
    addEmittedPre addEmittedPost bodyCounterRef aliases
    name params mRet contract mBody mDec stmtIdx = do

  -- Only handle integer-typed parameters (linear arithmetic fragment)
  let intParams = [ (n, t) | (n, t) <- params, isIntLike aliases t ]
  -- v0.8.0: Fix dead early-exit — check condition and exit early if nothing to verify.
  let hasContract = isJust (contractPre contract) || isJust (contractPost contract)
      hasIntParams = not (null intParams)
  -- Only proceed if there are int params or contracts to verify
  if not hasIntParams && not hasContract
    then pure ()
    else do

    -- Emit binders for all int-typed params
    paramBinds <- mapM (emitParamBind freshBid addBind) intParams
    let envIds = map bindId paramBinds

    -- Emit qualifiers extracted from pre/post
    let preQuals  = maybe [] (extractQualifiers "pre"  name) (contractPre contract)
        postQuals = maybe [] (extractQualifiers "post" name) (contractPost contract)
    addQuals (preQuals ++ postQuals)

    -- Emit standalone pre-condition constraint (legacy, non-body-VC mode only)
    -- v0.8.0: When body VCs are active, standalone pre/post constraints are
    -- suppressed. Body VCs encode the correct proof obligation:
    --   P ∧ (result = ⟦body⟧) ⟹ Q
    -- Standalone constraints (lhs true, rhs P) are not sound proof obligations.
    unless (emitBodyVCs opts) $ case contractPre contract of
      Nothing  -> pure ()
      Just pre ->
        case exprToPred pre of
          Nothing   -> addSkip name  -- non-linear: skip with note
          Just pred -> do
            cid  <- freshCid
            let lhs = FQReft "v" FQInt FQTrue   -- no lhs restriction
                rhs = FQReft "v" FQInt pred
                c   = FQConstraint cid envIds lhs rhs [name, "pre"]
            addConst c
            addEmittedPre name  -- v0.8.0: track that this pre actually emitted
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/pre"
            addOrigin cid (ConstraintOrigin name "pre" ptr srcFile)

    -- Emit standalone post-condition constraint (legacy, non-body-VC mode only)
    unless (emitBodyVCs opts) $ case contractPost contract of
      Nothing   -> pure ()
      Just post ->
        case exprToPred post of
          Nothing   -> addSkip name
          Just pred -> do
            cid    <- freshCid
            -- 'result' binder: type inferred from return annotation
            let retSort = maybe FQInt typeToSort mRet
            rbid   <- freshBid
            let resultBind = FQBind rbid "result" (FQReft "v" retSort FQTrue)
            addBind resultBind
            let lhs = FQReft "result" retSort FQTrue
                rhs = FQReft "result" retSort pred
                c   = FQConstraint cid (envIds ++ [rbid]) lhs rhs [name, "post"]
            addConst c
            addEmittedPost name  -- v0.8.0: track that this post actually emitted
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/post"
            addOrigin cid (ConstraintOrigin name "post" ptr srcFile)

    -- Emit termination constraint for letrec :decreases
    case mDec of
      Nothing  -> pure ()
      Just dec ->
        case exprToPred dec of
          Nothing   -> addSkip name  -- complex decrease: D3 already flagged ?proof-required
          Just decPred -> do
            cid  <- freshCid
            -- well-foundedness: decreases >= 0 (necessary condition for termination)
            let lhs = FQReft "v" FQInt decPred
                rhs = FQReft "v" FQInt (FQBinPred FQGe (FQVar "v") (FQLit 0))
                c   = FQConstraint cid envIds lhs rhs [name, "decreases"]
            addConst c
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/decreases"
            addOrigin cid (ConstraintOrigin name "decreases" ptr srcFile)

    -- v0.8.0: Emit body-faithful verification conditions
    -- Body VCs prove: P ∧ (result = ⟦body⟧) ⟹ Q
    when (emitBodyVCs opts) $ case mBody of
      Nothing -> pure ()  -- letrec: no body VC (recursive, excluded from BODY-VC-0)
      Just body -> do
        -- Fallback policy (§0.7): require translatable post. If pre exists, it must
        -- also be translatable, otherwise fallback conservatively.
        let mPostPred = contractPost contract >>= exprToPred
            mPrePred  = case contractPre contract of
                          Nothing  -> Just Nothing       -- no pre is fine
                          Just pre -> case exprToPred pre of
                                        Nothing -> Nothing    -- pre exists but untranslatable → fallback
                                        Just p  -> Just (Just p)
        case (mPostPred, mPrePred) of
          (Nothing, _) -> addBodyFallback name  -- no translatable post → fallback
          (_, Nothing) -> addBodyFallback name  -- untranslatable pre → fallback
          (Just postPred, Just mPre) -> do
            -- Build SortEnv from int-typed parameters
            let sortEnv = buildSortEnv aliases params
            -- Translate body
            seed <- readIORef bodyCounterRef
            let (newSeed, mBodyVC) = bodyToPredFrom seed sortEnv body
            writeIORef bodyCounterRef newSeed
            case mBodyVC of
              Nothing -> addBodyFallback name  -- body outside QF-LIA fragment
              Just bvc -> do
                -- Path count check (bounded)
                let pathCount = countPathsBounded 4097 bvc  -- stop at 4097
                if pathCount > 4096
                  then do
                    -- >4096: fallback, not error
                    addBodyFallback name
                    addDiag $ mkWarning Nothing $
                      "body VC for '" <> name <> "' exceeded 4096 path limit — "
                      <> "falling back to contract-only verification"
                  else do
                    -- Warn at 257-4096
                    when (pathCount > 256) $
                      addDiag $ mkWarning Nothing $
                        "body VC for '" <> name <> "' has "
                        <> T.pack (show pathCount) <> " paths (high path count may slow solver)"
                    -- Flatten and emit constraints
                    let paths = flattenBodyVC bvc
                        retSort = maybe FQInt typeToSort mRet
                    forM_ (zip [0::Int ..] paths) $ \(pathIdx, (guard, lbs, resultPred)) -> do
                      -- Emit binders for each let-binding in this path
                      lbBindIds <- mapM (\lb -> do
                        bid <- freshBid
                        let b = FQBind bid (lbName lb) (FQReft "v" (lbSort lb)
                                  (FQBinPred FQEq (FQVar "v") (lbRhs lb)))
                        addBind b
                        return bid) lbs
                      -- Emit result binder
                      rbid <- freshBid
                      let resultBind = FQBind rbid "result" (FQReft "v" retSort FQTrue)
                      addBind resultBind
                      -- Build LHS: guard ∧ pre ∧ (result = body-result)
                      let resultEq = FQBinPred FQEq (FQVar "result") resultPred
                          lhsPred  = conjoinAll $ [guard | guard /= FQTrue]
                                                ++ maybe [] (:[]) mPre
                                                ++ [resultEq]
                          lhs = FQReft "result" retSort lhsPred
                          rhs = FQReft "result" retSort postPred
                      -- Determine tag based on guard
                      let tag = case guard of
                                  FQTrue -> "body-post"
                                  _      -> if pathIdx < length (flattenBodyVC bvc) `div` 2
                                             then "body-post-then"
                                             else "body-post-else"
                      cid <- freshCid
                      let allEnvIds = envIds ++ lbBindIds ++ [rbid]
                          c = FQConstraint cid allEnvIds lhs rhs [name, tag]
                      addConst c
                      let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                      addOrigin cid (ConstraintOrigin name tag ptr srcFile)
                    -- Mark as body-faithful
                    addBodyFaithful name

emitParamBind :: IO FQBindId -> (FQBind -> IO ()) -> (Name, Type) -> IO FQBind
emitParamBind freshBid addBind (n, t) = do
  bid <- freshBid
  let b = FQBind bid n (FQReft "v" (typeToSort t) FQTrue)
  addBind b
  return b

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | v0.8.0: Type alias map, built from STypeDef statements.
-- Maps alias names to their structural bodies for isIntLike resolution.
type AliasMap = Map Name Type

-- | Build an alias map from top-level type definitions.
buildAliasMap :: [Statement] -> AliasMap
buildAliasMap stmts = Map.fromList [(n, body) | STypeDef n body <- stmts]

-- | Check if a type is int-like after resolving aliases.
-- Handles TDependent refinements and TCustom aliases.
-- Unresolved TCustom falls back to False (sound: rejects unknown types).
isIntLike :: AliasMap -> Type -> Bool
isIntLike _  TInt                  = True
isIntLike am (TDependent _ base _) = isIntLike am base
isIntLike am (TCustom n)           = case Map.lookup n am of
                                        Just t  -> isIntLike am t
                                        Nothing -> False  -- unresolved: reject
isIntLike _  _                     = False

typeToSort :: Type -> FQSort
typeToSort TInt  = FQInt
typeToSort TBool = FQBool
typeToSort (TDependent _ base _) = typeToSort base
typeToSort _     = FQInt  -- conservative default

typeSorts :: Name -> Type -> [FQDataDecl]
typeSorts name (TSumType ctors) =
  [FQDataDecl name 0 [(c, 0) | (c, _) <- ctors]]
typeSorts _ _ = []

maybeToList :: Maybe a -> [a]
maybeToList Nothing  = []
maybeToList (Just x) = [x]

-- | Convert a linear arithmetic LLMLL Expr to a FQPred.
-- Returns Nothing for non-linear or unsupported expressions (→ skip/proof-required).
exprToPred :: Expr -> Maybe FQPred
exprToPred (EVar v)   = Just (FQVar v)
exprToPred (ELit (LitInt n)) = Just (FQLit n)
exprToPred (ELit (LitBool True))  = Just FQTrue
exprToPred (ELit (LitBool False)) = Just FQFalse
exprToPred (EApp op [l, r])
  | op `elem` [">=", "≥"] = (\a b -> FQBinPred FQGe  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` [">"]        = (\a b -> FQBinPred FQGt  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["<=", "≤"] = (\a b -> FQBinPred FQLe  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["<"]        = (\a b -> FQBinPred FQLt  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["=", "=="]  = (\a b -> FQBinPred FQEq  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["/=", "!=", "≠"] = (\a b -> FQBinPred FQNeq a b) <$> exprToPred l <*> exprToPred r
  | op == "+"              = (\a b -> FQBinArith FQAdd a b) <$> exprToPred l <*> exprToPred r
  | op == "-"              = (\a b -> FQBinArith FQSub a b) <$> exprToPred l <*> exprToPred r
  -- non-linear ops: reject
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = Nothing
exprToPred (EApp "and" args) = FQAnd <$> mapM exprToPred args
exprToPred (EApp "or"  args) = FQOr  <$> mapM exprToPred args
exprToPred (EApp "not" [a])  = FQNot <$> exprToPred a
-- v0.8.0: Parser emits operators as EOp; delegate to EApp for uniform handling.
exprToPred (EOp op args)     = exprToPred (EApp op args)
exprToPred _ = Nothing  -- lambda, let, match, etc. → not in QF linear arith

-- | Extract qualifiers from an expression (auto-synthesis from pre/post).
-- Each atomic comparison at the top level becomes a qualifier template.
extractQualifiers :: Text -> Name -> Expr -> [FQQualifier]
extractQualifiers clause fnName expr =
  case exprToPred expr of
    Nothing   -> []  -- non-linear, no qualifiers
    Just pred -> atomicQualifiers fnName clause pred

atomicQualifiers :: Name -> Text -> FQPred -> [FQQualifier]
atomicQualifiers fn clause pred =
  case pred of
    FQBinPred op l r ->
      let vars = nubT (predVars l ++ predVars r)
          params = map (\v -> (v, FQInt)) ("v" : vars)
          qname  = "Q_" <> fn <> "_" <> clause <> "_" <> T.pack (show (hashPred pred))
      in [FQQualifier qname params pred]
    FQAnd ps -> concatMap (atomicQualifiers fn clause) ps
    FQOr  ps -> concatMap (atomicQualifiers fn clause) ps
    _ -> []

predVars :: FQPred -> [Text]
predVars (FQVar v)            = [v]
predVars (FQLit _)            = []
predVars FQTrue               = []
predVars FQFalse              = []
predVars (FQBinPred _ l r)   = predVars l ++ predVars r
predVars (FQBinArith _ l r)  = predVars l ++ predVars r
predVars (FQAnd ps)           = concatMap predVars ps
predVars (FQOr  ps)           = concatMap predVars ps
predVars (FQNot p)            = predVars p
predVars (FQKVar _ args)      = concatMap predVars args

nubT :: [Text] -> [Text]
nubT [] = []
nubT (x:xs) = x : nubT (filter (/= x) xs)

-- Simple hash for unique qualifier names (not cryptographic)
hashPred :: FQPred -> Int
hashPred = T.length . T.pack . show

-- ---------------------------------------------------------------------------
-- Body-VC translation engine (v0.8.0 BODY-VC-1)
-- ---------------------------------------------------------------------------

-- | Pure entry point: translates a function body to a BodyVC tree.
-- Takes a seed counter value and a sort environment (built from int params).
-- Returns (updatedCounter, Maybe BodyVC). Nothing = unsupported expression.
bodyToPredFrom :: Int -> SortEnv -> Expr -> (Int, Maybe BodyVC)
bodyToPredFrom seed sortEnv expr =
  let (result, finalCounter) = runStateFrom seed (bodyToPredM Map.empty sortEnv expr)
  in (finalCounter, result)
  where
    -- Run a State Int computation with a given starting value.
    -- Returns (result, finalState).
    runStateFrom :: Int -> State Int a -> (a, Int)
    runStateFrom s action =
      let go = do { r <- action; c <- get; return (r, c) }
      in evalState go s

-- | Fresh name generator for alpha-renaming.
freshName :: Name -> State Int Text
freshName base = do
  n <- get
  put (n + 1)
  return ("_bv_" <> base <> "_" <> T.pack (show n))

-- | Core body-to-predicate translation. Handles all operators directly
-- (NOT delegating to exprToPred) to preserve the alpha-renaming environment.
--
-- exprToPred does not consult the renaming env — it translates EVar v as
-- FQVar v using the original name. If a let-bound variable (renamed to
-- _bv_x_0) appears inside an operator expression and we delegate to
-- exprToPred, the .fq output will reference the un-renamed name, which
-- the solver cannot resolve.
bodyToPredM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe BodyVC)

-- Literals
bodyToPredM _ _ (ELit (LitInt n)) = return (Just (SimpleVC [] (FQLit n)))
bodyToPredM _ _ (ELit (LitBool True))  = return (Just (SimpleVC [] FQTrue))
bodyToPredM _ _ (ELit (LitBool False)) = return (Just (SimpleVC [] FQFalse))

-- Variables: look up renamed name, check sort env
bodyToPredM env sortEnv (EVar v) =
  let renamed = fromMaybe v (Map.lookup v env)
  in case Map.lookup renamed sortEnv of
       Just FQInt -> return (Just (SimpleVC [] (FQVar renamed)))
       _          -> return Nothing  -- non-int or unknown sort → fallback

-- Binary arithmetic operators (+, -)
bodyToPredM env se (EApp op [l, r])
  | Just binOp <- lookupArithOp op = do
      lvc <- bodyToPredM env se l
      rvc <- bodyToPredM env se r
      case (lvc, rvc) of
        (Just (SimpleVC [] lp), Just (SimpleVC [] rp)) ->
          return . Just $ SimpleVC [] (FQBinArith binOp lp rp)
        _ -> return Nothing

-- Binary comparison operators (>=, >, <=, <, =, /=, plus Unicode)
bodyToPredM env se (EApp op [l, r])
  | Just binOp <- lookupPredOp op = do
      lvc <- bodyToPredM env se l
      rvc <- bodyToPredM env se r
      case (lvc, rvc) of
        (Just (SimpleVC [] lp), Just (SimpleVC [] rp)) ->
          return . Just $ SimpleVC [] (FQBinPred binOp lp rp)
        _ -> return Nothing

-- Non-linear operators: reject
bodyToPredM _ _ (EApp op [_, _])
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = return Nothing

-- Logical operators: not, and, or
bodyToPredM env se (EApp "not" [a]) = do
  avc <- bodyToPredM env se a
  case avc of
    Just (SimpleVC [] p) -> return . Just $ SimpleVC [] (FQNot p)
    _ -> return Nothing

bodyToPredM env se (EApp "and" args) = do
  avcs <- mapM (bodyToPredM env se) args
  let preds = [p | Just (SimpleVC [] p) <- avcs]
  if length preds == length args
    then return . Just $ SimpleVC [] (FQAnd preds)
    else return Nothing

bodyToPredM env se (EApp "or" args) = do
  avcs <- mapM (bodyToPredM env se) args
  let preds = [p | Just (SimpleVC [] p) <- avcs]
  if length preds == length args
    then return . Just $ SimpleVC [] (FQOr preds)
    else return Nothing

-- Normalize EOp to EApp
bodyToPredM env se (EOp name args) = bodyToPredM env se (EApp name args)

-- EIf: branch into guard + then-VC + else-VC
bodyToPredM env se (EIf guard thenE elseE) = do
  mGuard <- guardToPredM env se guard
  case mGuard of
    Nothing -> return Nothing
    Just gp -> do
      mthen <- bodyToPredM env se thenE
      melse <- bodyToPredM env se elseE
      case (mthen, melse) of
        (Just tvc, Just evc) -> return (Just (BranchVC gp tvc evc))
        _                    -> return Nothing

-- ELet with single PVar binding: alpha-rename, emit LetBinding, recurse
bodyToPredM env se (ELet [(PVar v, _mType, rhs)] body) = do
  -- Translate the RHS
  mRhsVC <- bodyToPredM env se rhs
  case mRhsVC of
    Nothing -> return Nothing
    Just (SimpleVC [] rhsPred) -> do
      -- Alpha-rename the bound variable
      renamed <- freshName v
      let env'  = Map.insert v renamed env
          sort  = predSortOf rhsPred
          se'   = Map.insert renamed sort se
          lb    = LetBinding renamed sort rhsPred
      -- Recurse on body with updated env
      mBodyVC <- bodyToPredM env' se' body
      case mBodyVC of
        Nothing -> return Nothing
        Just (SimpleVC lbs resultP) ->
          return (Just (SimpleVC (lb : lbs) resultP))
        Just (BranchVC gp tvc evc) ->
          -- Prepend this binding to both branches
          return (Just (BranchVC gp (prependLB lb tvc) (prependLB lb evc)))
    -- RHS is a branch (EIf in let RHS) — hoist via flattening.
    -- Single-path degenerate branches are handled; multi-path falls back.
    Just bvc@(BranchVC _ _ _) -> do
      renamed <- freshName v
      let env'  = Map.insert v renamed env
          se'   = Map.insert renamed FQInt se
          paths = flattenBodyVC bvc
      case paths of
        -- Degenerate single-path: the branch always takes one path
        [(_, pathLBs, pathResult)] -> do
          let lb = LetBinding renamed FQInt pathResult
          mBodyVC <- bodyToPredM env' se' body
          case mBodyVC of
            Nothing -> return Nothing
            Just (SimpleVC lbs resultP) ->
              return (Just (SimpleVC (pathLBs ++ [lb] ++ lbs) resultP))
            Just (BranchVC gp tvc evc) ->
              return (Just (BranchVC gp
                (prependLBs (pathLBs ++ [lb]) tvc)
                (prependLBs (pathLBs ++ [lb]) evc)))
        -- Multi-path: fall back (conservative, sound)
        _ -> return Nothing
    _ -> return Nothing

-- ELet with multiple bindings: desugar to nested single-binding ELets
bodyToPredM env se (ELet (b:bs) body) =
  bodyToPredM env se (ELet [b] (ELet bs body))

-- ELet with no bindings (degenerate): just translate the body
bodyToPredM env se (ELet [] body) = bodyToPredM env se body

-- Everything else: match, app (user-defined), lambda, etc. → fallback
bodyToPredM _ _ _ = return Nothing

-- ---------------------------------------------------------------------------
-- Guard translation (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Translates guard expressions to FQPred, consulting BOTH the renaming
-- environment AND SortEnv. Variables are checked against sortEnv; non-int
-- or unknown vars cause fallback. This prevents the soundness bug where
-- exprToPred would silently assign FQInt to bool/string variables.
guardToPredM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
guardToPredM env sortEnv (EVar v) =
  let renamed = fromMaybe v (Map.lookup v env)
  in case Map.lookup renamed sortEnv of
       Just FQInt  -> return (Just (FQVar renamed))
       _           -> return Nothing  -- non-int or unknown → fallback

guardToPredM _ _ (ELit (LitBool True))  = return (Just FQTrue)
guardToPredM _ _ (ELit (LitBool False)) = return (Just FQFalse)
guardToPredM _ _ (ELit (LitInt n))      = return (Just (FQLit n))

-- Comparison operators (including Unicode aliases)
guardToPredM env se (EApp op [l, r])
  | Just binOp <- lookupPredOp op = do
      lp <- guardToPredM env se l
      rp <- guardToPredM env se r
      return $ FQBinPred binOp <$> lp <*> rp

-- Arithmetic in guards
guardToPredM env se (EApp op [l, r])
  | Just binOp <- lookupArithOp op = do
      lp <- guardToPredM env se l
      rp <- guardToPredM env se r
      return $ FQBinArith binOp <$> lp <*> rp

-- Non-linear in guards
guardToPredM _ _ (EApp op [_, _])
  | op `elem` ["*", "/", "mod", "rem"] = return Nothing

guardToPredM env se (EApp "not" [a]) = do
  ap <- guardToPredM env se a
  return $ FQNot <$> ap

guardToPredM env se (EApp "and" args) = do
  ps <- mapM (guardToPredM env se) args
  return $ if all isJust ps then Just (FQAnd (catMaybes ps)) else Nothing

guardToPredM env se (EApp "or" args) = do
  ps <- mapM (guardToPredM env se) args
  return $ if all isJust ps then Just (FQOr (catMaybes ps)) else Nothing

-- Normalize EOp
guardToPredM env se (EOp name args) = guardToPredM env se (EApp name args)

-- Everything else in guard position: ELet, EIf, etc. → fallback
guardToPredM _ _ _ = return Nothing

-- ---------------------------------------------------------------------------
-- Flattening and path counting (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Flatten a BodyVC tree into a list of paths.
-- Each path is (guard, let-bindings, result predicate).
-- For SimpleVC, the guard is FQTrue (unconditional).
-- For BranchVC, each branch produces paths with guard conjunction.
flattenBodyVC :: BodyVC -> [FlatPath]
flattenBodyVC (SimpleVC lbs result) = [(FQTrue, lbs, result)]
flattenBodyVC (BranchVC guard thenVC elseVC) =
  let thenPaths = [(conjoin guard g, lbs, r) | (g, lbs, r) <- flattenBodyVC thenVC]
      elsePaths = [(conjoin (FQNot guard) g, lbs, r) | (g, lbs, r) <- flattenBodyVC elseVC]
  in thenPaths ++ elsePaths

-- | Count paths in a BodyVC tree with an upper bound.
-- Stops counting once the limit is exceeded (avoids state explosion).
countPathsBounded :: Int -> BodyVC -> Int
countPathsBounded limit = go
  where
    go (SimpleVC _ _) = 1
    go (BranchVC _ tvc evc) =
      let tc = go tvc
      in if tc >= limit then tc
         else let ec = go evc
              in min limit (tc + ec)

-- ---------------------------------------------------------------------------
-- Predicate helpers (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Conjoin two predicates, simplifying FQTrue identity.
conjoin :: FQPred -> FQPred -> FQPred
conjoin FQTrue q     = q
conjoin p      FQTrue = p
conjoin p      q      = FQAnd [p, q]

-- | Conjoin a list of predicates.
conjoinAll :: [FQPred] -> FQPred
conjoinAll = foldr conjoin FQTrue

-- | Prepend a let-binding to a BodyVC.
prependLB :: LetBinding -> BodyVC -> BodyVC
prependLB lb (SimpleVC lbs r) = SimpleVC (lb : lbs) r
prependLB lb (BranchVC g t e) = BranchVC g (prependLB lb t) (prependLB lb e)

prependLBs :: [LetBinding] -> BodyVC -> BodyVC
prependLBs lbs bvc = foldr prependLB bvc lbs

-- | Infer the FQSort of a predicate result.
-- In BODY-VC-0, we only support int-typed results.
predSortOf :: FQPred -> FQSort
predSortOf (FQLit _)         = FQInt
predSortOf (FQVar _)         = FQInt  -- in BODY-VC-0, all vars in SortEnv are FQInt
predSortOf (FQBinArith _ _ _) = FQInt
predSortOf (FQBinPred _ _ _) = FQBool  -- comparisons return bool
predSortOf FQTrue            = FQBool
predSortOf FQFalse           = FQBool
predSortOf (FQNot _)         = FQBool
predSortOf (FQAnd _)         = FQBool
predSortOf (FQOr _)          = FQBool
predSortOf (FQKVar _ _)      = FQInt  -- fallback

-- | Build a SortEnv from function parameters (int-typed only for BODY-VC-0).
-- v0.8.0: uses isIntLike with alias map to resolve type aliases.
buildSortEnv :: AliasMap -> [(Name, Type)] -> SortEnv
buildSortEnv aliases params = Map.fromList
  [ (n, typeToSort t) | (n, t) <- params, isIntLike aliases t ]

-- ---------------------------------------------------------------------------
-- Operator lookup tables (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Look up an arithmetic binary operator (including Unicode aliases).
lookupArithOp :: Name -> Maybe FQBinOp
lookupArithOp "+" = Just FQAdd
lookupArithOp "-" = Just FQSub
lookupArithOp _   = Nothing

-- | Look up a predicate binary operator (including Unicode aliases).
lookupPredOp :: Name -> Maybe FQBinOp
lookupPredOp ">="  = Just FQGe
lookupPredOp "≥"   = Just FQGe
lookupPredOp ">"   = Just FQGt
lookupPredOp "<="  = Just FQLe
lookupPredOp "≤"   = Just FQLe
lookupPredOp "<"   = Just FQLt
lookupPredOp "="   = Just FQEq
lookupPredOp "=="  = Just FQEq
lookupPredOp "/="  = Just FQNeq
lookupPredOp "!="  = Just FQNeq
lookupPredOp "≠"   = Just FQNeq
lookupPredOp _     = Nothing
