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
-- FAITHFULNESS INVARIANT (v0.3):
-- This module's output is trusted by --contracts=unproven. If emitFixpoint
-- reports SAFE for a contract, the runtime assertion for that contract must
-- be semantically redundant for all well-typed inputs. Any extension to
-- exprToPred must preserve this invariant: never translate a contract to a
-- weaker .fq constraint that the solver accepts trivially.

module LLMLL.FixpointEmit
  ( emitFixpoint
  , EmitResult(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.IORef
import Data.Maybe (fromMaybe, mapMaybe)
import Control.Monad (forM_, when)

import LLMLL.Syntax
import LLMLL.FixpointIR
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable)

-- ---------------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------------

data EmitResult = EmitResult
  { erFQFile          :: FQFile           -- ^ the assembled .fq data structure
  , erFQText          :: Text             -- ^ .fq text ready to write to disk
  , erConstraintTable :: ConstraintTable  -- ^ ID → origin (for DiagnosticFQ)
  , erSkipped         :: [Text]           -- ^ names of skipped non-linear functions
  } deriving (Show)

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
emitFixpoint :: FilePath -> [Statement] -> IO EmitResult
emitFixpoint srcFile stmts = do
  ctrRef    <- newIORef (0 :: Int)  -- constraint ID counter
  bindRef   <- newIORef (0 :: Int)  -- binder ID counter
  tableRef  <- newIORef (Map.empty :: ConstraintTable)
  skippedRef<- newIORef ([] :: [Text])
  bindsRef  <- newIORef ([] :: [FQBind])
  constsRef <- newIORef ([] :: [FQConstraint])
  qualsRef  <- newIORef builtinQualifiers
  dataRef   <- newIORef ([] :: [FQDataDecl])

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

  -- Process each statement
  forM_ (zip [0..] stmts) $ \(idx, stmt) ->
    case stmt of
      STypeDef name body ->
        -- Emit ADT sorts for TSumType members
        forM_ (typeSorts name body) addData

      SDefLogic name params mRet contract body ->
        emitFnConstraints srcFile freshCid freshBid addBind addConst addQuals addSkip addOrigin
          name params mRet contract Nothing idx

      SLetrec name params mRet contract dec body ->
        emitFnConstraints srcFile freshCid freshBid addBind addConst addQuals addSkip addOrigin
          name params mRet contract (Just dec) idx

      _ -> pure ()

  -- Assemble result
  dataDecs  <- readIORef dataRef
  quals     <- readIORef qualsRef
  binds     <- readIORef bindsRef
  consts    <- readIORef constsRef
  table     <- readIORef tableRef
  skipped   <- readIORef skippedRef
  let fqFile = FQFile dataDecs quals binds consts
  return EmitResult
    { erFQFile          = fqFile
    , erFQText          = emitFQFile fqFile
    , erConstraintTable = table
    , erSkipped         = skipped
    }

-- ---------------------------------------------------------------------------
-- Per-function constraint emission
-- ---------------------------------------------------------------------------

emitFnConstraints
  :: FilePath
  -> IO FQConstraintId    -- fresh constraint ID
  -> IO FQBindId          -- fresh binder ID
  -> (FQBind       -> IO ())
  -> (FQConstraint -> IO ())
  -> ([FQQualifier] -> IO ())
  -> (Text -> IO ())       -- record skipped function
  -> (FQConstraintId -> ConstraintOrigin -> IO ())
  -> Name
  -> [(Name, Type)]
  -> Maybe Type
  -> Contract
  -> Maybe Expr            -- Just dec = letrec :decreases
  -> Int                   -- statement index (for JSON Pointer)
  -> IO ()
emitFnConstraints srcFile freshCid freshBid addBind addConst addQuals addSkip addOrigin
    name params mRet contract mDec stmtIdx = do

  -- Only handle integer-typed parameters (linear arithmetic fragment)
  let intParams = [ (n, t) | (n, t) <- params, isIntType t ]
  when (null intParams && null (maybeToList (contractPre contract))
        && null (maybeToList (contractPost contract))) $
    return ()  -- nothing to verify

  -- Emit binders for all int-typed params
  paramBinds <- mapM (emitParamBind freshBid addBind) intParams
  let envIds = map bindId paramBinds

  -- Emit qualifiers extracted from pre/post
  let preQuals  = maybe [] (extractQualifiers "pre"  name) (contractPre contract)
      postQuals = maybe [] (extractQualifiers "post" name) (contractPost contract)
  addQuals (preQuals ++ postQuals)

  -- Emit pre-condition constraint
  case contractPre contract of
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
          let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/pre"
          addOrigin cid (ConstraintOrigin name "pre" ptr srcFile)

  -- Emit post-condition constraint
  case contractPost contract of
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

emitParamBind :: IO FQBindId -> (FQBind -> IO ()) -> (Name, Type) -> IO FQBind
emitParamBind freshBid addBind (n, t) = do
  bid <- freshBid
  let b = FQBind bid n (FQReft "v" (typeToSort t) FQTrue)
  addBind b
  return b

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isIntType :: Type -> Bool
isIntType TInt = True
isIntType _    = False

typeToSort :: Type -> FQSort
typeToSort TInt  = FQInt
typeToSort TBool = FQBool
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
  | op `elem` ["/=", "≠"] = (\a b -> FQBinPred FQNeq a b) <$> exprToPred l <*> exprToPred r
  | op == "+"              = (\a b -> FQBinArith FQAdd a b) <$> exprToPred l <*> exprToPred r
  | op == "-"              = (\a b -> FQBinArith FQSub a b) <$> exprToPred l <*> exprToPred r
  -- non-linear ops: reject
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = Nothing
exprToPred (EApp "and" args) = FQAnd <$> mapM exprToPred args
exprToPred (EApp "or"  args) = FQOr  <$> mapM exprToPred args
exprToPred (EApp "not" [a])  = FQNot <$> exprToPred a
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
