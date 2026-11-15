-- | MUL-VAR-1: the normal form of a product of two non-constant terms.
--
-- Design record: @docs/design/mul-var-proposal.md@ (Rev 3a), sections
-- "Refusal scan", "Normal form" and "Limits". This module is pure.
--
-- An 'Atom' is a variable, a function application, @(/ e k)@ or @(mod e k)@
-- with @k@ a positive ground constant, or an 'FQIte'. Anything else that the
-- emitter can put in an integer position (a boolean predicate, a @$k@
-- variable) is an opaque atom: it is never a rule's head and never split.
-- Each atom is keyed by its printed 'FQPred' text, rebuilt from the normal
-- form of its arguments, so @(w + 1) / 2@ and @(1 + w) / 2@ are one atom.
--
-- A 'Mono' is a sorted multiset of atoms and a 'Poly' maps each monomial to
-- its non-zero integer coefficient. Commutativity, associativity and
-- distribution hold by construction. The sort order only prints; no decision
-- reads it.
--
-- Each limit refuses the whole constraint with the construct @nonlinear:*@ and
-- never truncates. 'toPoly' checks degree and size before each
-- multiplication.
module LLMLL.ProductNF
  ( -- * Limits (normative, design "Limits")
    maxDegree
  , maxClosure
  , maxPolySize
  , maxForms
  , maxPairs
    -- * Refusals
  , Refusal(..)
  , refusalScan
  , groundValue
    -- * Atoms, monomials, polynomials
  , Atom(..)
  , AtomKind(..)
  , Arg(..)
  , Cond(..)
  , RelOp(..)
  , Mono(..)
  , Poly
  , monoDegree
  , polyDegree
  , isConstPoly
  , constOf
  , polyConst
  , polyAtom
  , singleAtom
  , padd
  , psub
  , pneg
  , pscale
  , pmul
  , pmulRaw
    -- * Normal form
  , toPoly
  , toCond
  , mkDiv
  , mkMod
  , mkApp
  , mkIte
  , relHolds
    -- * Walking
  , innerPolys
  , condPolys
  , monosDeep
  , atomContains
  , polyContains
    -- * Printing
  , atomPred
  , polyPred
  , condPred
  , relPred
  , relOpBin
  , mulSymPrefix
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.List (sort, foldl')
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.FixpointIR (FQPred(..), FQBinOp(..), emitPred)

-- ---------------------------------------------------------------------------
-- Limits
-- ---------------------------------------------------------------------------

-- | Degree of a monomial in the closure, and of any product 'toPoly' builds.
maxDegree :: Int
maxDegree = 6

-- | Monomials in the closure of one constraint.
maxClosure :: Int
maxClosure = 256

-- | Size of a polynomial at any step of expansion (checked before a multiplication).
maxPolySize :: Int
maxPolySize = 256

-- | Settled forms of one written factor. Over it, that written product gives no pair.
maxForms :: Int
maxForms = 32

-- | Pairs in one constraint. Over it, F4, F5 and F10 are omitted.
maxPairs :: Int
maxPairs = 64

-- | The prefix of a monomial binder, @mul##k@. A source name cannot hold @#@.
mulSymPrefix :: Text
mulSymPrefix = "mul##"

-- ---------------------------------------------------------------------------
-- Refusals
-- ---------------------------------------------------------------------------

-- | A refusal of the whole constraint. 'refConstruct' is the fallback construct
-- (@nonlinear:*@, @nonlinear:/@, @nonlinear:mod@); 'refWhy' names the limit.
data Refusal = Refusal
  { refConstruct :: !Text
  , refWhy       :: !Text
  } deriving (Show, Eq)

refuseStar :: Text -> Either Refusal a
refuseStar = Left . Refusal "nonlinear:*"

-- | The value of a ground term: an integer literal, or a closed term under
-- @+@, @-@, @*@, @/@ and @mod@, with Haskell 'div' and 'mod'. A @/@ or @mod@
-- folds only when its divisor folds to a value @> 0@.
groundValue :: FQPred -> Maybe Integer
groundValue (FQLit n) = Just n
groundValue (FQBinArith op l r) = do
  a <- groundValue l
  b <- groundValue r
  case op of
    FQAdd -> Just (a + b)
    FQSub -> Just (a - b)
    FQMul -> Just (a * b)
    FQDiv | b > 0 -> Just (a `div` b)
    FQMod | b > 0 -> Just (a `mod` b)
    _ -> Nothing
groundValue _ = Nothing

-- | The refusal scan, on the term as written, before any expansion. A @/@ or
-- @mod@ whose divisor is not a positive ground constant refuses the constraint,
-- so a cancellation (@(* 0 (/ x y))@) cannot delete a refused term. The first
-- refusal in a left-to-right walk is returned.
refusalScan :: FQPred -> Maybe Refusal
refusalScan = go
  where
    go p = case p of
      FQBinArith FQDiv l r -> firstOf [divisor "/" r, go l, go r]
      FQBinArith FQMod l r -> firstOf [divisor "mod" r, go l, go r]
      FQBinArith _ l r     -> firstOf [go l, go r]
      FQBinPred _ l r      -> firstOf [go l, go r]
      FQAnd ps             -> firstOf (map go ps)
      FQOr ps              -> firstOf (map go ps)
      FQNot q              -> go q
      FQApp _ as           -> firstOf (map go as)
      FQKVar _ as          -> firstOf (map go as)
      FQIte c a b          -> firstOf [go c, go a, go b]
      _                    -> Nothing
    firstOf = foldr (\x acc -> maybe acc Just x) Nothing
    divisor nm r = case groundValue r of
      Just k | k > 0 -> Nothing
      _ -> Just (Refusal ("nonlinear:" <> nm)
                 ("divisor " <> emitPred r <> " is not a positive ground constant"))

-- ---------------------------------------------------------------------------
-- Atoms, monomials, polynomials
-- ---------------------------------------------------------------------------

-- | The comparison operators of a normal-form relation.
data RelOp = RLt | RLe | RGt | RGe | REq | RNe
  deriving (Show, Eq, Ord)

-- | A normal-form condition, as in an 'FQIte' guard. A relation is
-- @op (l - r) 0@. A leaf the form does not read is kept opaque.
data Cond
  = CRel RelOp Poly
  | CAnd [Cond]
  | COr [Cond]
  | CNot Cond
  | CLeaf FQPred
  deriving (Show, Eq)

-- | A function argument: an integer term in normal form, or a predicate.
data Arg = ArgP Poly | ArgC Cond
  deriving (Show, Eq)

data AtomKind
  = AVar Text
  | AApp Text [Arg]
  | ADiv Poly Integer
  | AMod Poly Integer
  | AIte Cond Poly Poly
  | AOpaque FQPred
  deriving (Show, Eq)

-- | An atom. Equality and order read the key only.
data Atom = Atom
  { atomKey  :: !Text
  , atomKind :: AtomKind
  } deriving (Show)

instance Eq Atom where
  a == b = atomKey a == atomKey b

instance Ord Atom where
  compare a b = compare (atomKey a) (atomKey b)

-- | A sorted multiset of atoms. The empty monomial is the constant 1.
newtype Mono = Mono { monoAtoms :: [Atom] }
  deriving (Show, Eq, Ord)

type Poly = Map.Map Mono Integer

monoDegree :: Mono -> Int
monoDegree = length . monoAtoms

polyDegree :: Poly -> Int
polyDegree p = maximum (0 : map monoDegree (Map.keys p))

isConstPoly :: Poly -> Bool
isConstPoly = all (null . monoAtoms) . Map.keys

constOf :: Poly -> Integer
constOf = Map.findWithDefault 0 (Mono [])

polyConst :: Integer -> Poly
polyConst 0 = Map.empty
polyConst c = Map.singleton (Mono []) c

polyAtom :: Atom -> Poly
polyAtom a = Map.singleton (Mono [a]) 1

-- | The atom of a polynomial that is one atom with coefficient 1.
singleAtom :: Poly -> Maybe Atom
singleAtom p = case Map.toList p of
  [(Mono [a], 1)] -> Just a
  _ -> Nothing

clean :: Poly -> Poly
clean = Map.filter (/= 0)

padd :: Poly -> Poly -> Poly
padd a b = clean (Map.unionWith (+) a b)

pneg :: Poly -> Poly
pneg = Map.map negate

psub :: Poly -> Poly -> Poly
psub a b = padd a (pneg b)

pscale :: Integer -> Poly -> Poly
pscale 0 _ = Map.empty
pscale c p = Map.map (* c) p

monoMul :: Mono -> Mono -> Mono
monoMul (Mono a) (Mono b) = Mono (sort (a ++ b))

-- | A product in 'toPoly', with the size and degree checks before it.
pmul :: Poly -> Poly -> Either Refusal Poly
pmul a b
  | not (isConstPoly a) && not (isConstPoly b)
  , polyDegree a + polyDegree b > maxDegree =
      refuseStar ("degree " <> tshow (polyDegree a + polyDegree b) <> " over " <> tshow maxDegree)
  | otherwise = pmulRaw a b

-- | A product with the size check only. The fact generator uses it: its
-- degrees are bounded by the closure, which checks them itself.
pmulRaw :: Poly -> Poly -> Either Refusal Poly
pmulRaw a b
  | Map.size a * Map.size b > maxPolySize =
      refuseStar ("expansion over " <> tshow maxPolySize <> " monomials")
  | otherwise = Right $ clean $ Map.fromListWith (+)
      [ (monoMul m1 m2, c1 * c2) | (m1, c1) <- Map.toList a, (m2, c2) <- Map.toList b ]

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Normal form
-- ---------------------------------------------------------------------------

-- | The normal form of an integer term. Run 'refusalScan' first: a @/@ or
-- @mod@ with a divisor that is not a positive ground constant is refused here
-- too, with the same construct.
toPoly :: FQPred -> Either Refusal Poly
toPoly p = case p of
  FQLit n -> Right (polyConst n)
  FQVar v -> Right (polyAtom (mkVar v))
  FQBinArith FQAdd l r -> padd <$> toPoly l <*> toPoly r
  FQBinArith FQSub l r -> psub <$> toPoly l <*> toPoly r
  FQBinArith FQMul l r -> do
    a <- toPoly l
    b <- toPoly r
    pmul a b
  FQBinArith FQDiv l r -> do
    k <- divisorOf "/" r
    a <- toPoly l
    Right (mkDiv a k)
  FQBinArith FQMod l r -> do
    k <- divisorOf "mod" r
    a <- toPoly l
    Right (mkMod a k)
  FQApp f as -> mkApp f <$> mapM toArg as
  FQIte c a b -> mkIte <$> toCond c <*> toPoly a <*> toPoly b
  _ -> Right (polyAtom (opaque p))
  where
    divisorOf nm r = case groundValue r of
      Just k | k > 0 -> Right k
      _ -> Left (Refusal ("nonlinear:" <> nm)
                 ("divisor " <> emitPred r <> " is not a positive ground constant"))

toArg :: FQPred -> Either Refusal Arg
toArg p
  | predShaped p = ArgC <$> toCond p
  | otherwise    = ArgP <$> toPoly p

predShaped :: FQPred -> Bool
predShaped = \case
  FQBinPred op _ _ -> isRel op
  FQNot _ -> True
  FQAnd _ -> True
  FQOr _ -> True
  FQTrue -> True
  FQFalse -> True
  _ -> False

isRel :: FQBinOp -> Bool
isRel op = op `elem` [FQGe, FQGt, FQLe, FQLt, FQEq, FQNeq]

relOf :: FQBinOp -> Maybe RelOp
relOf = \case
  FQLt -> Just RLt
  FQLe -> Just RLe
  FQGt -> Just RGt
  FQGe -> Just RGe
  FQEq -> Just REq
  FQNeq -> Just RNe
  _ -> Nothing

-- | A condition in normal form. A relation between two integer terms becomes
-- @op (l - r)@. A relation whose side is itself a predicate stays opaque.
toCond :: FQPred -> Either Refusal Cond
toCond p = case p of
  FQBinPred op l r
    | Just o <- relOf op, not (predShaped l), not (predShaped r) ->
        CRel o <$> (psub <$> toPoly l <*> toPoly r)
  FQAnd ps -> CAnd <$> mapM toCond ps
  FQOr ps -> COr <$> mapM toCond ps
  FQNot q -> CNot <$> toCond q
  _ -> Right (CLeaf p)

-- | Does @op c 0@ hold?
relHolds :: RelOp -> Integer -> Bool
relHolds o c = case o of
  RLt -> c < 0
  RLe -> c <= 0
  RGt -> c > 0
  RGe -> c >= 0
  REq -> c == 0
  RNe -> c /= 0

mkVar :: Text -> Atom
mkVar v = Atom (emitPred (FQVar v)) (AVar v)

opaque :: FQPred -> Atom
opaque p = Atom (emitPred p) (AOpaque p)

mkAtom :: AtomKind -> Atom
mkAtom k = Atom (emitPred (kindPred keyMono k)) k

-- | @(/ f k)@, folded when @f@ is constant.
mkDiv :: Poly -> Integer -> Poly
mkDiv f k
  | isConstPoly f = polyConst (constOf f `div` k)
  | otherwise     = polyAtom (mkAtom (ADiv f k))

-- | @(mod f k)@, folded when @f@ is constant.
mkMod :: Poly -> Integer -> Poly
mkMod f k
  | isConstPoly f = polyConst (constOf f `mod` k)
  | otherwise     = polyAtom (mkAtom (AMod f k))

mkApp :: Text -> [Arg] -> Poly
mkApp f as = polyAtom (mkAtom (AApp f as))

-- | An 'FQIte' atom, folded when both branches are one term or the guard is a
-- constant relation.
mkIte :: Cond -> Poly -> Poly -> Poly
mkIte c a b
  | a == b = a
  | CRel o q <- c, isConstPoly q = if relHolds o (constOf q) then a else b
  | otherwise = polyAtom (mkAtom (AIte c a b))

-- ---------------------------------------------------------------------------
-- Walking
-- ---------------------------------------------------------------------------

-- | The polynomials directly inside an atom.
innerPolys :: Atom -> [Poly]
innerPolys a = case atomKind a of
  ADiv f _ -> [f]
  AMod f _ -> [f]
  AApp _ as -> concatMap argPolys as
  AIte c x y -> [x, y] ++ condPolys c
  _ -> []
  where
    argPolys (ArgP p) = [p]
    argPolys (ArgC c) = condPolys c

condPolys :: Cond -> [Poly]
condPolys = \case
  CRel _ p -> [p]
  CAnd cs -> concatMap condPolys cs
  COr cs -> concatMap condPolys cs
  CNot c -> condPolys c
  CLeaf _ -> []

-- | Every monomial reachable from the given polynomials, through atom arguments.
monosDeep :: [Poly] -> Set.Set Mono
monosDeep = go Set.empty
  where
    go seen [] = seen
    go seen (p : rest) =
      let new = [ m | m <- Map.keys p, not (Set.member m seen) ]
          seen' = foldl' (flip Set.insert) seen new
          more = concatMap (concatMap innerPolys . monoAtoms) new
      in go seen' (more ++ rest)

-- | Does atom @v@ occur in @p@, at any depth? An 'FQIte' is opaque to rules,
-- so an occurrence inside one does not count.
polyContains :: Atom -> Poly -> Bool
polyContains v p = any (any (\a -> a == v || atomContains v a) . monoAtoms) (Map.keys p)

atomContains :: Atom -> Atom -> Bool
atomContains v a = case atomKind a of
  ADiv f _ -> polyContains v f
  AMod f _ -> polyContains v f
  AApp _ as -> any argHas as
  _ -> False
  where
    argHas (ArgP p) = polyContains v p
    argHas (ArgC _) = False

-- ---------------------------------------------------------------------------
-- Printing
-- ---------------------------------------------------------------------------

-- | How a monomial of degree 2 or more prints inside an atom key: a nested
-- product of its atoms. The key does not depend on any numbering.
keyMono :: Mono -> Maybe FQPred
keyMono (Mono (a : b : rest)) =
  Just (foldl' (\acc x -> FQBinArith FQMul acc (atomPred keyMono x)) (FQBinArith FQMul (atomPred keyMono a) (atomPred keyMono b)) rest)
keyMono _ = Nothing

-- | An atom as a predicate. The first argument names a monomial of degree 2 or
-- more (with @mul##k@ at emission).
atomPred :: (Mono -> Maybe FQPred) -> Atom -> FQPred
atomPred nm a = kindPred nm (atomKind a)

kindPred :: (Mono -> Maybe FQPred) -> AtomKind -> FQPred
kindPred nm = \case
  AVar v -> FQVar v
  AApp f as -> FQApp f (map argPred as)
  ADiv f k -> FQBinArith FQDiv (polyPred nm f) (FQLit k)
  AMod f k -> FQBinArith FQMod (polyPred nm f) (FQLit k)
  AIte c x y -> FQIte (condPred nm c) (polyPred nm x) (polyPred nm y)
  AOpaque p -> p
  where
    argPred (ArgP p) = polyPred nm p
    argPred (ArgC c) = condPred nm c

monoPred :: (Mono -> Maybe FQPred) -> Mono -> FQPred
monoPred nm m@(Mono as) = case as of
  [] -> FQLit 1
  [a] -> atomPred nm a
  _ -> case nm m of
         Just p -> p
         Nothing -> case keyMono m of
           Just p -> p
           Nothing -> FQLit 1

-- | A polynomial as one flat chain: positive terms summed, negative ones
-- subtracted, in monomial order. The printer prints it with no inner parens.
polyPred :: (Mono -> Maybe FQPred) -> Poly -> FQPred
polyPred nm p =
  let terms = Map.toAscList p
      pos = [ term m c | (m, c) <- terms, c > 0 ]
      neg = [ term m (negate c) | (m, c) <- terms, c < 0 ]
      term m c
        | null (monoAtoms m) = FQLit c
        | c == 1 = monoPred nm m
        | otherwise = FQBinArith FQMul (FQLit c) (monoPred nm m)
      start = case pos of
        [] -> (FQLit 0, [])
        (x : xs) -> (x, xs)
      withPos = foldl' (FQBinArith FQAdd) (fst start) (snd start)
  in foldl' (FQBinArith FQSub) withPos neg

condPred :: (Mono -> Maybe FQPred) -> Cond -> FQPred
condPred nm = \case
  CRel o p -> relPred nm o p
  CAnd cs -> FQAnd (map (condPred nm) cs)
  COr cs -> FQOr (map (condPred nm) cs)
  CNot c -> FQNot (condPred nm c)
  CLeaf p -> p

relOpBin :: RelOp -> FQBinOp
relOpBin = \case
  RLt -> FQLt
  RLe -> FQLe
  RGt -> FQGt
  RGe -> FQGe
  REq -> FQEq
  RNe -> FQNeq

-- | @op p 0@, printed with the positive terms on the left and the negated
-- negative terms on the right. A constant relation prints as @true@ or @false@.
relPred :: (Mono -> Maybe FQPred) -> RelOp -> Poly -> FQPred
relPred nm o p
  | Map.null p = if relHolds o 0 then FQTrue else FQFalse
  | otherwise =
      let l = Map.filter (> 0) p
          r = Map.map negate (Map.filter (< 0) p)
      in FQBinPred (relOpBin o) (polyPred nm l) (polyPred nm r)
