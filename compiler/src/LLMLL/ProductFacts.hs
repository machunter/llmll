-- | MUL-VAR-1: the fixed fact set of a constraint that holds a product.
--
-- Design record: @docs/design/mul-var-proposal.md@ (Rev 3a), sections
-- "Rules", "Fact set", "Invariance" and "Limits". This module is pure. It is
-- a port of @facts()@ in @scripts/mulvar/rev3.py@ (SHA-256
-- 14e9441d20f55f4025ae33eb5029114e0ef1fb5ac59a90efa33b884c6b4cda12), over
-- 'FQPred' terms and the normal form of "LLMLL.ProductNF".
--
-- * Rules: each top-level equation whose side is one variable or application
--   atom with coefficient 1 gives @atom -> other side@, in both directions where
--   both sides qualify, unless the atom occurs in the other side. No rule reads
--   order, and none is chosen over another.
-- * Closure: every monomial reached by any sequence of rules, a least fixed
--   point. Over 'maxDegree' or 'maxClosure' the constraint refuses.
-- * Settled: a monomial of degree 2 or more in a bottom strongly connected
--   component of the rule graph, unless its rules resolve it to degree 1.
-- * Pairs @P@: each written product with each factor in each settled form, and
--   each binary split of each settled monomial, recursively.
-- * Facts F1 to F11 as the design's table states. Over 'maxPairs' pairs, F4,
--   F5 and F10 are omitted.
--
-- A fact whose premise is a true constant loses that premise. A fact with a
-- false constant premise, or a true constant conclusion, is dropped. Facts are
-- deduplicated on their canonical relations; the first family to add one
-- names it.
module LLMLL.ProductFacts
  ( Family(..)
  , familyName
  , Fact(..)
  , FactResult(..)
  , Rule(..)
  , productFacts
  , productFactsWith
  , RuleReading(..)
  , flatConjuncts
  , factPred
  , monoNames
  , renderFacts
  , factMonos
  , canonRel
  , hasProduct
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Graph (stronglyConnComp, flattenSCC)
import Data.List (foldl', sortOn, subsequences)
import Data.Text (Text)
import qualified Data.Text as T
import Control.Monad (foldM, forM_, when)

import LLMLL.FixpointIR (FQPred(..), FQBinOp(..), emitPred)
import LLMLL.ProductNF

-- ---------------------------------------------------------------------------
-- Facts
-- ---------------------------------------------------------------------------

data Family = F1 | F2 | F3 | F4 | F5 | F7 | F7b | F8 | F9 | F10 | F11
  deriving (Show, Eq, Ord, Enum, Bounded)

familyName :: Family -> Text
familyName = T.pack . show

-- | A fact: premises (each @op p 0@, canonical, sorted) imply the conclusion.
data Fact = Fact
  { factFamily :: !Family
  , factPrem   :: [(RelOp, Poly)]
  , factConc   :: (RelOp, Poly)
  } deriving (Show, Eq)

-- | A rule @atom -> rhs@, from the equation @eqn = 0@.
data Rule = Rule
  { ruleAtom :: Atom
  , ruleRhs  :: Poly
  , ruleEqn  :: Poly
  } deriving (Show, Eq)

data FactResult = FactResult
  { frFacts    :: [Fact]     -- ^ in generation order; 'renderFacts' sorts by text
  , frPairs    :: !Int       -- ^ |P|
  , frCapped   :: !Bool      -- ^ |P| > 'maxPairs': F4, F5 and F10 omitted
  , frClosure  :: !Int       -- ^ monomials in the closure
  , frMaxDeg   :: !Int
  , frSettled  :: !Int
  , frRules    :: [Rule]
  } deriving (Show)

-- | How rules are read. 'AllRules' is the language. 'FirstRulePerAtom' is
-- Rev 2's reading (one rule per atom, in conjunct order); it exists only as the
-- control that the invariance test must be able to fail.
data RuleReading = AllRules | FirstRulePerAtom
  deriving (Show, Eq)

-- | The top-level conjuncts of a predicate list, with nested 'FQAnd' spliced.
flatConjuncts :: [FQPred] -> [FQPred]
flatConjuncts = concatMap go
  where
    go (FQAnd ps) = concatMap go ps
    go FQTrue = []
    go p = [p]

-- | Does the predicate hold a product of two non-constant terms?
hasProduct :: FQPred -> Bool
hasProduct = \case
  FQBinArith FQMul l r ->
    (nonConst l && nonConst r) || hasProduct l || hasProduct r
  FQBinArith _ l r -> hasProduct l || hasProduct r
  FQBinPred _ l r -> hasProduct l || hasProduct r
  FQAnd ps -> any hasProduct ps
  FQOr ps -> any hasProduct ps
  FQNot p -> hasProduct p
  FQApp _ as -> any hasProduct as
  FQKVar _ as -> any hasProduct as
  FQIte c a b -> hasProduct c || hasProduct a || hasProduct b
  _ -> False
  where
    nonConst p = case groundValue p of
      Just _ -> False
      Nothing -> True

-- | The fact set of one constraint, from its hypotheses (binder refinements
-- and @lhs@ conjuncts, with the ground-fact families the emitter adds) and its
-- goal. A refusal refuses the whole constraint.
productFacts :: [FQPred] -> FQPred -> Either Refusal FactResult
productFacts = productFactsWith AllRules

productFactsWith :: RuleReading -> [FQPred] -> FQPred -> Either Refusal FactResult
productFactsWith reading hyps0 goal = do
  let hyps = flatConjuncts hyps0
  forM_ (hyps ++ [goal]) $ \t -> maybe (Right ()) Left (refusalScan t)
  rules <- readRules reading hyps
  -- occurrences: the two sides of each relation, and each written product
  (polys, written) <- collect (hyps ++ [goal])
  let seeds = monosDeep polys
  graph <- closure rules (Set.toList seeds)
  let closureSize = Map.size graph
      maxDeg = maximum (0 : map monoDegree (Map.keys graph))
  -- F9: one link for each rule at each monomial
  let f9 = [ mk F9 [(REq, ruleEqn r)] (REq, psub (monoPoly m) q)
           | (m, edges) <- Map.toAscList graph, (r, q) <- edges ]
      settled = settledSet graph
  -- pairs from written products
  writtenPairs <- fmap concat $ mapM (\(a, b) -> do
      fa <- forms rules a
      fb <- forms rules b
      case (fa, fb) of
        (Just xs, Just ys) -> do
          Right [ (x, y) | x <- xs, y <- ys, Map.size x * Map.size y <= maxPolySize ]
        _ -> Right []) written
  let (splitPairs, done) = splits settled
      pairMap = foldl' addPair Map.empty (writtenPairs ++ splitPairs)
      items = Map.elems pairMap
      nPairs = length items
      capped = nPairs > maxPairs
      lits = literals polys
      zero = Map.empty
      one = polyConst 1
      rel o l r = (o, psub l r)
  pairFacts <- fmap concat $ mapM (\(a, b) -> do
      t <- pmulRaw a b
      perOrder <- fmap concat $ mapM (\(x, y) -> do
          f11 <- if isSingle x
                   then mapM (\k -> do
                          ky <- pmulRaw (polyConst k) y
                          Right (mk F11 [rel REq x (polyConst k)] (rel REq t ky))) lits
                   else Right []
          Right $
            [ mk F1 [rel RGe x zero, rel RGe y zero] (rel RGe t zero)
            , mk F1 [rel RLe x zero, rel RGe y zero] (rel RLe t zero)
            , mk F2 [rel REq x zero] (rel REq t zero)
            , mk F2 [rel REq x one] (rel REq t y)
            , mk F3 [rel RGe x one, rel RGe y zero] (rel RGe t y)
            ] ++ f11) [(a, b), (b, a)]
      let f8 = [ mk F8 [] (rel RGe t zero) | a == b ]
      Right (perOrder ++ f8)) items
  crossFacts <- if capped then Right [] else fmap concat $ mapM (\((a, b), (c, d)) -> do
      t1 <- pmulRaw a b
      t2 <- pmulRaw c d
      Right $ concat
        [ [ mk F4 [rel RLe p r, rel RLe q s, rel RGe q zero, rel RGe r zero] (rel RLe t1 t2)
          , mk F5 [rel RLt p r, rel RLe q s, rel RGe q zero, rel RGe r zero] (rel RLe (padd t1 q) t2)
          , mk F10 [rel REq p r, rel REq q s] (rel REq t1 t2) ]
        | (p, q, r, s) <- [(a, b, c, d), (a, b, d, c), (b, a, c, d), (b, a, d, c)] ])
      [ (x, y) | (i, x) <- zip [0 :: Int ..] items, (j, y) <- zip [0 ..] items, i /= j ]
  -- literal bounds: top level, closed over atom-to-atom rules, plus mod bounds
  let alias = Map.fromListWith Set.union
        [ (ruleAtom r, Set.singleton s) | r <- rules, Just s <- [singleAtom (ruleRhs r)] ]
      aliases a = go (Set.singleton a) [a]
        where go seen [] = seen
              go seen (x : xs) =
                let nxt = [ y | y <- Set.toList (Map.findWithDefault Set.empty x alias), not (Set.member y seen) ]
                in go (foldl' (flip Set.insert) seen nxt) (nxt ++ xs)
  explicitBounds <- fmap concat $ mapM (\h -> case h of
      FQBinPred op l r | Just o <- boundOp op -> do
        lp <- toPoly l
        rp <- toPoly r
        Right [ (b, o', constOf y)
              | (x, y, o') <- [(lp, rp, o), (rp, lp, flipOp o)]
              , isConstPoly y, Just at <- [singleAtom x]
              , b <- Set.toList (aliases at) ]
      _ -> Right []) hyps
  let ubE = Map.fromListWith Set.union
        [ (b, Set.singleton k') | (b, o, k) <- explicitBounds
        , Just k' <- [case o of RLe -> Just k; REq -> Just k; RLt -> Just (k - 1); _ -> Nothing] ]
      lbE = Map.fromListWith Set.union
        [ (b, Set.singleton k') | (b, o, k) <- explicitBounds
        , Just k' <- [case o of RGe -> Just k; REq -> Just k; RGt -> Just (k + 1); _ -> Nothing] ]
      modB a = case atomKind a of
        AMod _ k -> Just k
        _ -> Nothing
      ub a = Set.union (Map.findWithDefault Set.empty a ubE) (maybe Set.empty (\k -> Set.singleton (k - 1)) (modB a))
      lb a = Set.union (Map.findWithDefault Set.empty a lbE) (maybe Set.empty (const (Set.singleton 0)) (modB a))
  f7b <- fmap concat $ mapM (\(a, b) -> do
      t <- pmulRaw a b
      fmap concat $ mapM (\(x, y) -> case singleAtom x of
          Just at -> do
            ups <- mapM (\k -> do
                     ky <- pmulRaw (polyConst k) y
                     Right (mk F7b [rel RLe x (polyConst k), rel RGe y zero] (rel RLe t ky)))
                   (Set.toAscList (ub at))
            los <- mapM (\k -> do
                     ky <- pmulRaw (polyConst k) y
                     Right (mk F7b [rel RGe x (polyConst k), rel RGe y zero] (rel RGe t ky)))
                   (filter (>= 0) (Set.toAscList (lb at)))
            Right (ups ++ los)
          Nothing -> Right []) [(a, b), (b, a)]) items
  let f7 = concat
        [ [ mk F7 (concat [ [rel RGe (polyAtom a) zero, rel RLe (polyAtom a) (polyConst k)]
                          | (a, k) <- zip (monoAtoms m) combo ])
                  (rel RLe (monoPoly m) (polyConst (product combo)))
          | combo <- mapM (Set.toAscList . ub) (monoAtoms m)
          , all (>= 0) combo ]
        | m <- Set.toAscList done
        , all (not . Set.null . ub) (monoAtoms m) ]
  let facts = dedupe (f9 ++ pairFacts ++ crossFacts ++ f7b ++ f7)
  Right FactResult
    { frFacts = facts
    , frPairs = nPairs
    , frCapped = capped
    , frClosure = closureSize
    , frMaxDeg = maxDeg
    , frSettled = Set.size settled
    , frRules = rules
    }
  where
    isSingle x = case Map.toList x of
      [(Mono [_], 1)] -> True
      _ -> False
    boundOp = \case
      FQLt -> Just RLt
      FQLe -> Just RLe
      FQGt -> Just RGt
      FQGe -> Just RGe
      FQEq -> Just REq
      _ -> Nothing
    flipOp = \case
      RLt -> RGt
      RLe -> RGe
      RGt -> RLt
      RGe -> RLe
      o -> o

monoPoly :: Mono -> Poly
monoPoly m = Map.singleton m 1

-- | A fact before canonical simplification: 'Nothing' when it is dropped.
mk :: Family -> [(RelOp, Poly)] -> (RelOp, Poly) -> Maybe Fact
mk fam prem (co, cp) = do
  ps <- foldM keep Map.empty prem
  when (isConstPoly cp && relHolds co (constOf cp)) Nothing
  Just (Fact fam (Map.elems ps) (canonRel co cp))
  where
    keep acc (o, p)
      | isConstPoly p = if relHolds o (constOf p) then Just acc else Nothing
      | otherwise = let c = canonRel o p in Just (Map.insert c c acc)

-- | The canonical relation: @>@ and @>=@ turn into @<@ and @<=@ on the negated
-- polynomial; for @=@ and @!=@ the smaller of @p@ and @-p@ is kept.
canonRel :: RelOp -> Poly -> (RelOp, Poly)
canonRel o p = case o of
  RGt -> (RLt, pneg p)
  RGe -> (RLe, pneg p)
  REq -> (REq, min p (pneg p))
  RNe -> (RNe, min p (pneg p))
  _ -> (o, p)

-- | Keep the first fact of each canonical key, in generation order.
dedupe :: [Maybe Fact] -> [Fact]
dedupe = go Set.empty
  where
    go _ [] = []
    go seen (Nothing : rest) = go seen rest
    go seen (Just f : rest) =
      let k = (factPrem f, factConc f)
      in if Set.member k seen then go seen rest else f : go (Set.insert k seen) rest

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- | Is this atom a rule head: a variable or a function application?
ruleHead :: Atom -> Bool
ruleHead a = case atomKind a of
  AVar _ -> True
  AApp _ _ -> True
  _ -> False

readRules :: RuleReading -> [FQPred] -> Either Refusal [Rule]
readRules reading hyps = do
  cands <- fmap concat $ mapM (\case
      FQBinPred FQEq l r -> do
        lp <- toPoly l
        rp <- toPoly r
        let eqn = psub lp rp
        Right [ Rule v e eqn
              | (side, e) <- [(lp, rp), (rp, lp)]
              , Just v <- [singleAtom side], ruleHead v
              , not (polyContains v e) ]
      _ -> Right []) hyps
  Right $ case reading of
    AllRules -> Map.elems (Map.fromList [ ((ruleAtom r, ruleRhs r), r) | r <- cands ])
    FirstRulePerAtom ->
      let pick (seen, acc) r
            | Set.member (ruleAtom r) seen = (seen, acc)
            | otherwise = (Set.insert (ruleAtom r) seen, r : acc)
      in sortOn (\r -> (ruleAtom r, ruleRhs r)) (snd (foldl' pick (Set.empty, []) cands))

relevantRules :: [Rule] -> Poly -> [Rule]
relevantRules rules p = [ r | r <- rules, polyContains (ruleAtom r) p ]

substAtom :: Atom -> Atom -> Poly -> Either Refusal Poly
substAtom a x e
  | a == x = Right e
  | not (atomContains x a) = Right (polyAtom a)
  | otherwise = case atomKind a of
      ADiv f k -> (`mkDiv` k) <$> subst f x e
      AMod f k -> (`mkMod` k) <$> subst f x e
      AApp g as -> mkApp g <$> mapM substArg as
      _ -> Right (polyAtom a)
  where
    substArg (ArgP p) = ArgP <$> subst p x e
    substArg c = Right c

-- | Substitute @e@ for atom @x@ in @p@, with the degree and size limits.
subst :: Poly -> Atom -> Poly -> Either Refusal Poly
subst p x e = foldM step Map.empty (Map.toList p)
  where
    step out (m, c) = do
      let n = length (filter (== x) (monoAtoms m))
      when (n > 0 && (monoDegree m - n + n * polyDegree e) > maxDegree) $
        Left (Refusal "nonlinear:*" ("degree over " <> tshow maxDegree <> " after resolution"))
      when (n > 0 && Map.size e ^ n > maxPolySize) $
        Left (Refusal "nonlinear:*" ("expansion over " <> tshow maxPolySize <> " monomials after resolution"))
      t <- foldM (\acc a -> substAtom a x e >>= pmulRaw acc) (polyConst c) (monoAtoms m)
      Right (padd out t)

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Occurrences
-- ---------------------------------------------------------------------------

-- | The two sides of each relation, and each written product, at any depth.
collect :: [FQPred] -> Either Refusal ([Poly], [(Poly, Poly)])
collect ts = do
  rs <- mapM go ts
  Right (concatMap fst rs, concatMap snd rs)
  where
    go t = case t of
      FQBinPred op l r
        | op `elem` [FQGe, FQGt, FQLe, FQLt, FQEq, FQNeq] -> do
            ps <- polySide l
            qs <- polySide r
            (a, b) <- both l r
            Right (ps ++ qs ++ a, b)
      FQBinArith FQMul l r -> do
        lp <- toPoly l
        rp <- toPoly r
        (a, b) <- both l r
        Right (a, (lp, rp) : b)
      FQBinArith _ l r -> both l r
      FQBinPred _ l r -> both l r
      FQAnd ps -> many ps
      FQOr ps -> many ps
      FQNot p -> go p
      FQApp _ as -> many as
      FQIte c a b -> many [c, a, b]
      _ -> Right ([], [])
    both l r = many [l, r]
    many ps = do
      rs <- mapM go ps
      Right (concatMap fst rs, concatMap snd rs)
    -- a predicate-shaped side (a bool equation) is not an integer polynomial
    polySide p
      | isPredShaped p = Right []
      | otherwise = (: []) <$> toPoly p
    isPredShaped = \case
      FQBinPred op _ _ -> op `elem` [FQGe, FQGt, FQLe, FQLt, FQEq, FQNeq]
      FQNot _ -> True
      FQAnd _ -> True
      FQOr _ -> True
      FQTrue -> True
      FQFalse -> True
      _ -> False

-- | A monomial is a node of the rule graph when it has degree 2 or more, or is
-- one atom that is not a variable.
nodeKind :: Mono -> Bool
nodeKind m = case monoAtoms m of
  [a] -> case atomKind a of
    AVar _ -> False
    _ -> True
  as -> length as >= 2

-- | The closure: every monomial the rules reach, with each rule's result.
closure :: [Rule] -> [Mono] -> Either Refusal (Map.Map Mono [(Rule, Poly)])
closure rules seeds = go Map.empty (filter nodeKind seeds)
  where
    go graph [] = Right graph
    go graph (m : stack)
      | Map.member m graph = go graph stack
      | monoDegree m > maxDegree =
          Left (Refusal "nonlinear:*" ("degree " <> tshow (monoDegree m) <> " over " <> tshow maxDegree <> " after resolution"))
      | Map.size graph + 1 > maxClosure =
          Left (Refusal "nonlinear:*" ("closure over " <> tshow maxClosure <> " monomials"))
      | otherwise = do
          edges <- mapM (\r -> (r,) <$> subst (monoPoly m) (ruleAtom r) (ruleRhs r))
                        (relevantRules rules (monoPoly m))
          let fromRules = concatMap (\(_, q) -> Set.toList (monosDeep [q])) edges
              fromInner = Set.toList (monosDeep (concatMap innerPolys (monoAtoms m)))
              graph' = Map.insert m edges graph
              new = [ n | n <- fromRules ++ fromInner, nodeKind n, not (Map.member n graph') ]
          go graph' (new ++ stack)

-- | The nodes in a bottom strongly connected component of @succ@.
bottomNodes :: Ord k => Map.Map k [k] -> Set.Set k
bottomNodes succs =
  let sccs = map flattenSCC (stronglyConnComp [ (k, k, vs) | (k, vs) <- Map.toList succs ])
      compOf = Map.fromList [ (v, i) | (i, vs) <- zip [0 :: Int ..] sccs, v <- vs ]
      leaves = Set.fromList
        [ i | (i, vs) <- zip [0 :: Int ..] sccs
        , all (\v -> all (\w -> Map.lookup w compOf == Just i) (Map.findWithDefault [] v succs)) vs ]
  in Set.fromList [ v | (v, i) <- Map.toList compOf, Set.member i leaves ]

-- | Settled monomials: degree 2 or more, in a bottom component, and not
-- resolved by a rule whose results all have degree 1 or less.
settledSet :: Map.Map Mono [(Rule, Poly)] -> Set.Set Mono
settledSet graph =
  let nodes = [ m | m <- Map.keys graph, monoDegree m >= 2 ]
      succs = Map.fromList
        [ (m, Set.toList (Set.fromList [ n | (_, q) <- Map.findWithDefault [] m graph
                                            , n <- Map.keys q, monoDegree n >= 2, Map.member n graph ]))
        | m <- nodes ]
      bottom = bottomNodes succs
  in Set.filter (\m -> not (not (null (Map.findWithDefault [] m graph)) && null (Map.findWithDefault [] m succs))) bottom

-- | The settled forms of a written factor, or 'Nothing' over 'maxForms'.
forms :: [Rule] -> Poly -> Either Refusal (Maybe [Poly])
forms rules p0 = go Map.empty [p0]
  where
    go nodes [] = Right (Just (finish nodes))
    go nodes (x : stack)
      | Map.member x nodes = go nodes stack
      | Map.size nodes + 1 > maxForms = Right Nothing
      | otherwise = do
          ys <- mapM (\r -> subst x (ruleAtom r) (ruleRhs r)) (relevantRules rules x)
          go (Map.insert x ys nodes) (ys ++ stack)
    finish nodes =
      let succs = Map.map (Set.toList . Set.fromList) nodes
      in Set.toAscList (bottomNodes succs)

-- | Pairs from each binary split of each settled monomial, recursively, and
-- every monomial visited.
splits :: Set.Set Mono -> ([(Poly, Poly)], Set.Set Mono)
splits settled = go (Set.toList settled) Set.empty []
  where
    go [] done acc = (reverse acc, done)
    go (m : todo) done acc
      | Set.member m done = go todo done acc
      | otherwise =
          let as = monoAtoms m
              idx = [0 .. length as - 1]
              subsets = [ c | c <- subsequences idx, not (null c), length c < length as ]
              parts = [ (Mono [ as !! i | i <- c ], Mono [ as !! i | i <- idx, i `notElem` c ]) | c <- subsets ]
              prs = [ (monoPoly a, monoPoly b) | (a, b) <- parts ]
              more = concat [ [ a | monoDegree a >= 2 ] ++ [ b | monoDegree b >= 2 ] | (a, b) <- parts ]
          in go (more ++ todo) (Set.insert m done) (reverse prs ++ acc)

-- | Add a pair, ordered, skipping one with a constant side.
addPair :: Map.Map (Poly, Poly) (Poly, Poly) -> (Poly, Poly) -> Map.Map (Poly, Poly) (Poly, Poly)
addPair acc (a, b)
  | isConstPoly a || isConstPoly b = acc
  | otherwise =
      let (x, y) = if a <= b then (a, b) else (b, a)
      in Map.insertWith (\_ old -> old) (x, y) (x, y) acc

-- | Each integer in the constraint other than 0 and 1: every coefficient and
-- constant of a relation side, and of every atom argument inside one.
literals :: [Poly] -> [Integer]
literals polys =
  let allm = monosDeep polys
      inner = concatMap (concatMap innerPolys . monoAtoms) (Set.toList allm)
      cs = Set.fromList (concatMap Map.elems (polys ++ inner))
  in Set.toAscList (Set.difference cs (Set.fromList [0, 1]))

-- ---------------------------------------------------------------------------
-- Printing
-- ---------------------------------------------------------------------------

-- | Every monomial of degree 2 or more in the facts, at any depth.
factMonos :: [Fact] -> Set.Set Mono
factMonos fs = Set.filter ((>= 2) . monoDegree) $ monosDeep
  [ p | f <- fs, (_, p) <- factConc f : factPrem f ]

-- | @mul##k@ for each monomial of degree 2 or more, numbered in sorted order.
monoNames :: Set.Set Mono -> Map.Map Mono Text
monoNames ms = Map.fromList
  [ (m, mulSymPrefix <> T.pack (show k)) | (k, m) <- zip [0 :: Int ..] (Set.toAscList (Set.filter ((>= 2) . monoDegree) ms)) ]

-- | A fact as a predicate. A fact with premises prints as
-- @(not (p1 && p2)) || c@; the comparisons inside have no parens of their own.
factPred :: Map.Map Mono Text -> Fact -> FQPred
factPred names f =
  let nm m = FQVar <$> Map.lookup m names
      c = uncurry (relPred nm) (factConc f)
  in case factPrem f of
       [] -> c
       ps -> FQOr [FQNot (FQAnd [ relPred nm o p | (o, p) <- ps ]), c]

-- | The facts as predicates, sorted by their printed text.
renderFacts :: Map.Map Mono Text -> [Fact] -> [FQPred]
renderFacts names fs = map snd (sortOn fst [ (emitPred p, p) | p <- map (factPred names) fs ])
