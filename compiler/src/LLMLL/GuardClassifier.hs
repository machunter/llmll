-- |
-- Module      : LLMLL.GuardClassifier
-- Description : Shared guard classification logic (v0.10, OBLIG-0 §4.2.4).
--
-- Sort-aware predicate classification extracted from FixpointEmit.guardToPredM.
-- Both the verification consumer (FixpointEmit) and the presentation consumer
-- (ObligationAssembly) call classifyGuardM, preventing drift between the two
-- codepaths. The shared core handles variable lookup, operator dispatch, and
-- recursive structure; consumers differ only in what they do with the result.
--
-- Depends on FixpointIR.FQPred (stable since v0.8.0, no IO, no dependencies
-- beyond Text). This coupling is accepted — see Language Team Finding 3.
module LLMLL.GuardClassifier
  ( -- * Shared guard classification core
    classifyGuardM
    -- * Operator lookup tables (moved from FixpointEmit)
  , lookupPredOp
  , lookupArithOp
    -- * SIGMA-CONST-ARITH-1: shared emission of admitted constant-linear forms
  , constArithTerm
    -- * GENERIC-COMPARE-1: the reflected compare terms, shared with the body channel
  , intBuiltinTag
  , reflectCompare
  , isReflectedCompare
    -- * MINMAX-GUARD-1: the min/max/abs terms, shared with the body channel
  , reflectMinMaxAbs
    -- * GENERIC-COMPARE-PAIR-1: the order shape a compare name encodes
  , OrdShape(..)
  , compareShapeName
  , parseCompareName
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, catMaybes)
import Control.Monad.State.Strict (State)
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.Syntax (Name, Expr(..), Literal(..), ConstArith(..), groundInt, constArith)
import LLMLL.FixpointIR (FQPred(..), FQBinOp(..), FQSort(..), strlitConst)
-- F1: SortEnv is a type alias defined in FixpointEmit. We import it
-- as Map Name FQSort directly since it's just a type alias.
-- The canonical import path is LLMLL.FixpointEmit.SortEnv.

-- | SortEnv maps variable names to their FQ sorts.
-- Duplicated from FixpointEmit to avoid circular imports.
-- Both definitions are identical: @type SortEnv = Map Name FQSort@.
type SortEnv = Map Name FQSort

-- ---------------------------------------------------------------------------
-- Shared guard classification core (v0.8.0 origin, v0.10 extraction)
-- ---------------------------------------------------------------------------

-- | Translates guard expressions to FQPred, consulting BOTH the renaming
-- environment AND SortEnv. Variables are checked against sortEnv; non-int
-- or unknown vars cause fallback. This prevents the soundness bug where
-- exprToPred would silently assign FQInt to bool/string variables.
--
-- This is the shared core called by:
--   * FixpointEmit.guardToPredM (verification — uses FQPred for solver)
--   * ObligationAssembly.guardToPredPresentation (presentation — checks isJust)
classifyGuardM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
classifyGuardM env sortEnv (EVar v) =
  let renamed = fromMaybe v (Map.lookup v env)
  in case Map.lookup renamed sortEnv of
       Just FQInt  -> return (Just (FQVar renamed))
       Just FQBool -> return (Just (FQVar renamed))  -- BOOL-FRAG: bool var as a guard atom (path-split on b / ¬b)
       -- STRLIT (body-channel flip): a Str-sorted var (an ANF-hoisted string
       -- map-get result, or a seeded string param) as a comparison OPERAND —
       -- `(if (= t "active") …)`. A BARE Str guard atom is ill-typed upstream
       -- (an if-condition must be bool), so admitting FQStr here can only
       -- produce =/≠ operands, which meet the Str literal below well-sorted.
       Just FQStr  -> return (Just (FQVar renamed))
       _           -> return Nothing  -- non-scalar or unknown → fallback

classifyGuardM _ _ (ELit (LitBool True))  = return (Just FQTrue)
classifyGuardM _ _ (ELit (LitBool False)) = return (Just FQFalse)
classifyGuardM _ _ (ELit (LitInt n))      = return (Just (FQLit n))
-- STRLIT (body-channel flip): a string literal in guard position interns to its
-- nullary Str constant, exactly as the contract channel (exprToPred) does —
-- `(= (map-get m k) "active")` as an if-guard now reflects (the get is ANF-
-- hoisted to a Str-sorted var first). Distinctness/length facts ride the
-- addConst passes (constraint-derived, position-independent).
classifyGuardM _ _ (ELit (LitString s))   = return (Just (FQApp (strlitConst s) []))

-- GENERIC-COMPARE-1: a reflected `compare` at int or bool (written by the
-- specialization pass, tagged by FixpointEmit.markIntBuiltins) unfolds to the
-- same definitional term the body channel uses ('reflectCompare'), so
-- `(if (<= (compare x y) 0) x y)` keeps its guard.
-- GENERIC-COMPARE-PAIR-1: at a pair shape the operands may be pair-sorted,
-- which 'compareOperandM' admits here and nowhere else.
classifyGuardM env se (EApp op args)
  | Just b <- T.stripPrefix intBuiltinTag op
  , isReflectedCompare b = do
      ps <- mapM (compareOperandM env se) args
      return (sequence ps >>= reflectCompare b)

-- MINMAX-GUARD-1: a tagged `min`, `max` or `abs` (a builtin call no binder
-- shadows; FixpointEmit.markIntBuiltins) unfolds to its `if` definition over
-- int operands, as in a body, so `(if (< (min a b) 0) …)` keeps its guard.
classifyGuardM env se (EApp op args)
  | Just b <- T.stripPrefix intBuiltinTag op
  , b `elem` ["min", "max", "abs"] = do
      ps <- mapM (classifyGuardM env se) args
      return (sequence ps >>= reflectMinMaxAbs b)

-- Comparison operators (including Unicode aliases)
classifyGuardM env se (EApp op [l, r])
  | Just binOp <- lookupPredOp op = do
      lp <- classifyGuardM env se l
      rp <- classifyGuardM env se r
      return $ FQBinPred binOp <$> lp <*> rp

-- Arithmetic in guards
classifyGuardM env se (EApp op [l, r])
  | Just binOp <- lookupArithOp op = do
      lp <- classifyGuardM env se l
      rp <- classifyGuardM env se r
      return $ FQBinArith binOp <$> lp <*> rp

-- SIGMA-CONST-ARITH-1: an admitted constant-linear form (a parity test such as
-- `(= (mod x 2) 0)`) classifies; every other `*`, `/`, `mod` refuses below.
classifyGuardM env se (EApp op args)
  | Just m <- constArithTerm (classifyGuardM env se) op args = m

-- Non-linear in guards
classifyGuardM _ _ (EApp op [_, _])
  | op `elem` ["*", "/", "mod", "rem"] = return Nothing

classifyGuardM env se (EApp "not" [a]) = do
  ap <- classifyGuardM env se a
  return $ FQNot <$> ap

-- LEVER-A2: `(map-has m k)` as an if-guard — the presence-gated defensive-read
-- shape `(if (map-has m k) (map-get m k) d)`. Reflects to the int-0/1 presence
-- equation `Map_select(m$has, k) = 1` (proposal §5 Rev 1.1) so the then-path's
-- presence obligation discharges from the path condition. Gated on the split
-- binder existing in the SortEnv (seeded only for admissible gated map[int,int]
-- params in FixpointEmit) — anything else falls back. Variable scrutinee only;
-- composite scrutinees in guard position are out of the v1 class.
classifyGuardM env se (EApp "map-has" [EVar m, kE]) = do
  let m' = fromMaybe m (Map.lookup m env)
  if Map.member (m' <> "$has") se
    then do
      mk <- classifyGuardM env se kE
      return $ (\k -> FQBinPred FQEq (FQApp "Map_select" [FQVar (m' <> "$has"), k])
                                     (FQLit 1)) <$> mk
    else return Nothing

classifyGuardM env se (EApp "and" args) = do
  ps <- mapM (classifyGuardM env se) args
  return $ if all isJust ps then Just (FQAnd (catMaybes ps)) else Nothing

classifyGuardM env se (EApp "or" args) = do
  ps <- mapM (classifyGuardM env se) args
  return $ if all isJust ps then Just (FQOr (catMaybes ps)) else Nothing

-- IMPL-SUGAR: desugar =>/<=> before classifying (byte-identical to or/not/and)
classifyGuardM env se (EApp "=>" [p, q]) =
  classifyGuardM env se (EApp "or" [EApp "not" [p], q])
classifyGuardM env se (EApp "<=>" [p, q]) =
  classifyGuardM env se (EApp "and" [EApp "or" [EApp "not" [p], q], EApp "or" [EApp "not" [q], p]])

-- Normalize EOp
classifyGuardM env se (EOp name args) = classifyGuardM env se (EApp name args)

-- PAIR-GUARD-PROJ-1: `(first p)` / `(second p)` of a pair-sorted variable, at
-- any depth, when the projected component is int, bool or Str (the sorts the
-- EVar arm admits). A selector on the one-constructor Pair2 is total and exact,
-- so the guard is the projection's value. A pair-valued component is no guard
-- operand here; inside a reflected compare 'compareOperandM' takes it.
classifyGuardM env se e@(EApp p [_])
  | p == "first" || p == "second" =
      return $ case projTerm env se e of
        Just (t, s) | s `elem` [FQInt, FQBool, FQStr] -> Just t
        _ -> Nothing

-- Everything else in guard position: ELet, EIf, etc. → fallback
classifyGuardM _ _ _ = return Nothing

-- ---------------------------------------------------------------------------
-- GENERIC-COMPARE-1: reflected compare (one definition for both channels)
-- ---------------------------------------------------------------------------

-- | MINMAX-FRAG-1: the prefix of the internal name a reflected builtin call
-- takes. `%` cannot appear in an LLMLL identifier, so no user name carries it.
-- Defined here so the guard channel and FixpointEmit read the same tag.
intBuiltinTag :: Text
intBuiltinTag = "builtin%"

-- | GENERIC-COMPARE-PAIR-1: the order shape of a compare operand type, after
-- aliases and refinements: int, bool, or a pair of shapes. The specialization
-- pass writes it into the call name ('compareShapeName'), and the emitter and
-- the guard channel read it back ('parseCompareName').
data OrdShape = OSInt | OSBool | OSPair OrdShape OrdShape
  deriving (Eq, Show)

-- | `compare%int`, `compare%bool`, `compare%(int,bool)`, `compare%((int,bool),int)`.
-- `%`, `(`, `,` and `)` cannot appear in an LLMLL identifier, so no user name
-- or binder carries one of these names.
compareShapeName :: OrdShape -> Name
compareShapeName sh = "compare%" <> render sh
  where
    render OSInt        = "int"
    render OSBool       = "bool"
    render (OSPair a b) = "(" <> render a <> "," <> render b <> ")"

-- | The inverse of 'compareShapeName'; 'Nothing' for any other name.
parseCompareName :: Name -> Maybe OrdShape
parseCompareName n = do
  t <- T.stripPrefix "compare%" n
  (sh, rest) <- shape t
  if T.null rest then Just sh else Nothing
  where
    shape t
      | Just r <- T.stripPrefix "int" t  = Just (OSInt, r)
      | Just r <- T.stripPrefix "bool" t = Just (OSBool, r)
      | Just r <- T.stripPrefix "(" t    = do
          (a, r1) <- shape r
          r2      <- T.stripPrefix "," r1
          (b, r3) <- shape r2
          r4      <- T.stripPrefix ")" r3
          Just (OSPair a b, r4)
      | otherwise = Nothing

-- | MINMAX-FRAG-1: the `if` definition of an int builtin over translated operands.
-- `max` follows the Prelude's argument order (`if x <= y then y else x`); on
-- integers a tie returns equal values, so the order cannot change the result.
-- MINMAX-GUARD-1: moved here from FixpointEmit.reflectIntBuiltin, so the body,
-- contract and guard channels read one definition.
reflectMinMaxAbs :: Name -> [FQPred] -> Maybe FQPred
reflectMinMaxAbs "min" [a, b] = Just (FQIte (FQBinPred FQLe a b) a b)
reflectMinMaxAbs "max" [a, b] = Just (FQIte (FQBinPred FQLe a b) b a)
reflectMinMaxAbs "abs" [a]    = Just (FQIte (FQBinPred FQLt a (FQLit 0)) (FQBinArith FQSub (FQLit 0) a) a)
reflectMinMaxAbs _ _          = Nothing

-- | The specialized compare names that unfold definitionally.
isReflectedCompare :: Name -> Bool
isReflectedCompare = isJust . parseCompareName

-- | `compare` at int and at bool, after specialization, as the definition
-- `llmll_compare` computes (`compare` on Integer and on Bool, false < true,
-- mapped to -1, 0, 1). Definitional terms: no assumed post and no axiom. -1
-- is written 0 - 1, as `abs` writes its negation. Read by both
-- FixpointEmit.reflectIntBuiltin (body and contract) and 'classifyGuardM'.
--
-- GENERIC-COMPARE-PAIR-1: at a pair, the derived tuple order (first
-- components, then second; LLMLL.md §13.5) through the Pair2 selectors, as
-- `ite(lt, -1, ite(eq, 0, 1))`. 'shapeLt' and 'shapeEq' compare only at int
-- and bool leaves, never at the datatype sort, and the term grows linearly
-- with the nesting (a `c0 /= 0` form would repeat c0 at each level).
reflectCompare :: Name -> [FQPred] -> Maybe FQPred
reflectCompare n [a, b] = case parseCompareName n of
  Just OSInt  ->
    Just (FQIte (FQBinPred FQLt a b) minusOne (FQIte (FQBinPred FQEq a b) (FQLit 0) (FQLit 1)))
  Just OSBool ->
    Just (FQIte (FQBinPred FQEq a b) (FQLit 0) (FQIte a (FQLit 1) minusOne))
  Just sh     ->
    Just (FQIte (shapeLt sh a b) minusOne (FQIte (shapeEq sh a b) (FQLit 0) (FQLit 1)))
  Nothing     -> Nothing
reflectCompare _ _ = Nothing

-- | GENERIC-COMPARE-PAIR-1: equality at a shape, leaf by leaf.
shapeEq :: OrdShape -> FQPred -> FQPred -> FQPred
shapeEq (OSPair s t) a b = FQAnd [shapeEq s (sel0 a) (sel0 b), shapeEq t (sel1 a) (sel1 b)]
shapeEq _ a b            = FQBinPred FQEq a b

-- | GENERIC-COMPARE-PAIR-1: strict order at a shape (false < true at bool).
shapeLt :: OrdShape -> FQPred -> FQPred -> FQPred
shapeLt OSInt a b        = FQBinPred FQLt a b
shapeLt OSBool a b       = FQAnd [FQNot a, b]
shapeLt (OSPair s t) a b =
  FQOr [shapeLt s (sel0 a) (sel0 b), FQAnd [shapeEq s (sel0 a) (sel0 b), shapeLt t (sel1 a) (sel1 b)]]

sel0, sel1 :: FQPred -> FQPred
sel0 x = FQApp "pair2_0" [x]
sel1 x = FQApp "pair2_1" [x]

-- | PAIR-GUARD-PROJ-1: the term and sort of a pair-sorted variable or a
-- `first` / `second` chain over one. Each step reads the component sort off
-- the applied `Pair2 s0 s1`.
projTerm :: Map Name Name -> SortEnv -> Expr -> Maybe (FQPred, FQSort)
projTerm env se e = case e of
  EVar v
    | let r = fromMaybe v (Map.lookup v env)
    , Just s@(FQDataApp "Pair2" _) <- Map.lookup r se -> Just (FQVar r, s)
  EApp "first" [a]
    | Just (t, FQDataApp "Pair2" [s0, _]) <- projTerm env se a -> Just (sel0 t, s0)
  EApp "second" [a]
    | Just (t, FQDataApp "Pair2" [_, s1]) <- projTerm env se a -> Just (sel1 t, s1)
  EOp n as -> projTerm env se (EApp n as)
  _ -> Nothing

-- | GENERIC-COMPARE-PAIR-1: an operand of a reflected compare in a guard. A
-- pair-sorted variable, a `pair` of operands and a `first` / `second` of one
-- are admitted here only; a bare pair is still no guard atom. Everything else
-- is 'classifyGuardM', so the int and bool operands are unchanged.
compareOperandM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
compareOperandM env se e = case e of
  EVar v
    | let r = fromMaybe v (Map.lookup v env)
    , Just (FQDataApp "Pair2" _) <- Map.lookup r se -> return (Just (FQVar r))
  EPair a b -> do
    pa <- compareOperandM env se a
    pb <- compareOperandM env se b
    return ((\x y -> FQApp "pair2" [x, y]) <$> pa <*> pb)
  EApp "first" [a]  -> fmap sel0 <$> compareOperandM env se a
  EApp "second" [a] -> fmap sel1 <$> compareOperandM env se a
  _ -> classifyGuardM env se e

minusOne :: FQPred
minusOne = FQBinArith FQSub (FQLit 0) (FQLit 1)

-- ---------------------------------------------------------------------------
-- Operator lookup tables (moved from FixpointEmit, v0.8.0)
-- ---------------------------------------------------------------------------

-- | Look up an arithmetic binary operator (including Unicode aliases).
lookupArithOp :: Name -> Maybe FQBinOp
lookupArithOp "+" = Just FQAdd
lookupArithOp "-" = Just FQSub
lookupArithOp _   = Nothing

-- | SIGMA-CONST-ARITH-1 (docs/design/sigma-const-arith-1-proposal.md): the one
-- emission rule for `*`, `/` and `mod`, shared by 'classifyGuardM' and by
-- FixpointEmit's 'exprToPred' and 'bodyToPredM'. Given a translator for the
-- one non-constant operand, it returns 'Nothing' when the node is not
-- admitted (the caller then refuses as before, so the refusal label does not
-- change), or the action that emits it:
--
--   * a ground term folds to one literal ('groundInt', Haskell semantics);
--   * @(* c e)@ / @(* e c)@ emit @c * e@ / @e * c@ with @c@ as a numeral;
--   * @(/ e c)@ / @(mod e c)@ with @c > 0@ emit @e / c@ / @e mod c@.
--
-- Folding happens only inside a `*`, `/` or `mod` node. A ground term built
-- from `+` and `-` alone never reaches here, so it keeps its existing
-- emission and no previously translated clause changes a byte.
--
-- Deliberately NOT a 'lookupArithOp' entry: FixpointEmit reads that table to
-- recognise built-in operators on the callee path, which must not change.
constArithTerm :: Monad m => (Expr -> m (Maybe FQPred)) -> Name -> [Expr] -> Maybe (m (Maybe FQPred))
constArithTerm tr op args
  | op `notElem` (["*", "/", "mod"] :: [Name]) = Nothing
  | Just v <- groundInt (EOp op args) = Just (return (Just (FQLit v)))
  | Just form <- constArith op args = Just $ case form of
      MulL c e -> fmap (FQBinArith FQMul (FQLit c)) <$> tr e
      MulR e c -> fmap (\p -> FQBinArith FQMul p (FQLit c)) <$> tr e
      DivC e c -> fmap (\p -> FQBinArith FQDiv p (FQLit c)) <$> tr e
      ModC e c -> fmap (\p -> FQBinArith FQMod p (FQLit c)) <$> tr e
  | otherwise = Nothing

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
