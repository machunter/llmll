-- | MUL-VAR-1 (Rev 3a), Steps 1 and 2: the pure normal form and fact set.
--
-- The witness table and its rev3.py statistics are exported by
-- @scripts/mulvar/export_witnesses.py@ into
-- @test/fixtures/mul_var_1/witnesses.json@. Each row is an s-expression VC
-- (hypotheses as rev3's VC holds them, ground facts included) and what the
-- rev3.py generator gave for it.
module ProductSpec (productSpec) where

import Test.Hspec
import Test.QuickCheck

import Control.Monad (forM, forM_)
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as AKM
import qualified Data.ByteString.Lazy as BL
import Data.Char (isDigit)
import Data.List (foldl', sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Vector as V
import System.Directory (findExecutable, getTemporaryDirectory, removeFile)
import System.Exit (ExitCode(..))
import System.IO (hClose, openTempFile)

import LLMLL.FixpointIR (FQPred(..), FQBinOp(..), emitPred)
import LLMLL.ProductNF
import LLMLL.ProductFacts
import LLMLL.SolverGuard (runSolverGuarded)
import LLMLL.FixpointIR (FQSort(..))
import LLMLL.ProductRecheck (mkQuery, expandMonos, recheckQuery, RecheckAnswer(..))

-- ---------------------------------------------------------------------------
-- s-expressions, as rev3.py writes them
-- ---------------------------------------------------------------------------

data Sx = SAtom Text | SList [Sx]

parseSx :: Text -> Sx
parseSx t = case go (tokens t) of
  (x, _) -> x
  where
    tokens = filter (not . T.null) . T.words . T.replace "(" " ( " . T.replace ")" " ) "
    go ("(" : rest) = list [] rest
    go (a : rest) = (SAtom a, rest)
    go [] = (SList [], [])
    list acc (")" : rest) = (SList (reverse acc), rest)
    list acc rest = let (x, r) = go rest in list (x : acc) r

-- | rev3.py's source operators as the emitter prints them: @=>@ is @(not p) || q@,
-- @abs@, @max@ and @min@ are an 'FQIte', any other head is an application.
toPred :: Sx -> FQPred
toPred (SAtom a)
  | isInt a = FQLit (read (T.unpack a))
  | a == "true" = FQTrue
  | a == "false" = FQFalse
  | otherwise = FQVar a
  where isInt s = case T.uncons s of
          Just ('-', r) -> not (T.null r) && T.all isDigit r
          _ -> not (T.null s) && T.all isDigit s
toPred (SList (SAtom op : args)) =
  let ps = map toPred args in
  case (op, ps) of
    ("+", x : xs) -> foldl' (FQBinArith FQAdd) x xs
    ("-", [x]) -> FQBinArith FQSub (FQLit 0) x
    ("-", x : xs) -> foldl' (FQBinArith FQSub) x xs
    ("*", x : xs) -> foldl' (FQBinArith FQMul) x xs
    ("/", [x, y]) -> FQBinArith FQDiv x y
    ("mod", [x, y]) -> FQBinArith FQMod x y
    ("<", [x, y]) -> FQBinPred FQLt x y
    ("<=", [x, y]) -> FQBinPred FQLe x y
    (">", [x, y]) -> FQBinPred FQGt x y
    (">=", [x, y]) -> FQBinPred FQGe x y
    ("=", [x, y]) -> FQBinPred FQEq x y
    ("!=", [x, y]) -> FQBinPred FQNeq x y
    ("and", xs) -> FQAnd xs
    ("or", xs) -> FQOr xs
    ("not", [x]) -> FQNot x
    ("=>", [x, y]) -> FQOr [FQNot x, y]
    ("if", [c, x, y]) -> FQIte c x y
    ("abs", [x]) -> FQIte (FQBinPred FQLt x (FQLit 0)) (FQBinArith FQSub (FQLit 0) x) x
    ("max", [x, y]) -> FQIte (FQBinPred FQGe x y) x y
    ("min", [x, y]) -> FQIte (FQBinPred FQLe x y) x y
    _ -> FQApp op ps
toPred (SList _) = FQTrue

-- ---------------------------------------------------------------------------
-- The exported table
-- ---------------------------------------------------------------------------

data Row = Row
  { rowName     :: Text
  , rowHyps     :: [FQPred]
  , rowGoal     :: FQPred
  , rowVars     :: [Text]
  , rowRefused  :: Maybe Text
  , rowFacts    :: Int
  , rowT        :: Int
  , rowCapped   :: Bool
  , rowClosure  :: Int
  , rowMaxDeg   :: Int
  , rowFamilies :: Map.Map Text Int
  }

loadRows :: IO ([Row], [Row])
loadRows = do
  bs <- BL.readFile "test/fixtures/mul_var_1/witnesses.json"
  case A.decode bs of
    Just (A.Object o) -> pure (rowsOf (AKM.lookup "witnesses" o), rowsOf (AKM.lookup "extra" o))
    _ -> fail "witnesses.json does not parse"
  where
    rowsOf (Just (A.Array xs)) = mapMaybe row (V.toList xs)
    rowsOf _ = []
    row (A.Object o) = do
      A.String n <- AKM.lookup "name" o
      A.Array hs <- AKM.lookup "hyps" o
      A.String g <- AKM.lookup "goal" o
      A.Array vs <- AKM.lookup "vars" o
      let str (A.String s) = Just s
          str _ = Nothing
          int k = case AKM.lookup k o of
            Just (A.Number x) -> round x
            _ -> 0 :: Int
          bool k = case AKM.lookup k o of
            Just (A.Bool b) -> b
            _ -> False
          fams = case AKM.lookup "families" o of
            Just (A.Object fo) -> Map.fromList [ (AK.toText k, n') | (k, A.Number x) <- AKM.toList fo, let n' = round x ]
            _ -> Map.empty
      Just Row
        { rowName = n
        , rowHyps = map (toPred . parseSx) (mapMaybe str (V.toList hs))
        , rowGoal = toPred (parseSx g)
        , rowVars = mapMaybe str (V.toList vs)
        , rowRefused = case AKM.lookup "refused" o of
            Just (A.String c) -> Just c
            _ -> Nothing
        , rowFacts = int "facts"
        , rowT = int "T"
        , rowCapped = bool "capped"
        , rowClosure = int "closure"
        , rowMaxDeg = int "maxdeg"
        , rowFamilies = fams
        }
    row _ = Nothing

familyCounts :: [Fact] -> Map.Map Text Int
familyCounts fs = Map.fromListWith (+) [ (familyName (factFamily f), 1) | f <- fs ]

-- | What one row gives here, in the exported shape.
summarize :: FactResult -> (Int, Int, Bool, Int, Int, Map.Map Text Int)
summarize r = (length (frFacts r), frPairs r, frCapped r, frClosure r, frMaxDeg r, familyCounts (frFacts r))

expectedOf :: Row -> (Int, Int, Bool, Int, Int, Map.Map Text Int)
expectedOf r = (rowFacts r, rowT r, rowCapped r, rowClosure r, rowMaxDeg r, rowFamilies r)

-- ---------------------------------------------------------------------------
-- Variants: π (conjunct permutation), φ (equation flip), ρ (renaming)
-- ---------------------------------------------------------------------------

flipEq :: FQPred -> FQPred
flipEq = \case
  FQBinPred FQEq l r -> FQBinPred FQEq (flipEq r) (flipEq l)
  FQBinPred op l r -> FQBinPred op (flipEq l) (flipEq r)
  FQBinArith op l r -> FQBinArith op (flipEq l) (flipEq r)
  FQAnd ps -> FQAnd (map flipEq ps)
  FQOr ps -> FQOr (map flipEq ps)
  FQNot p -> FQNot (flipEq p)
  FQApp f as -> FQApp f (map flipEq as)
  FQIte c a b -> FQIte (flipEq c) (flipEq a) (flipEq b)
  p -> p

renameP :: Map.Map Text Text -> FQPred -> FQPred
renameP m = \case
  FQVar v -> FQVar (Map.findWithDefault v v m)
  FQBinPred op l r -> FQBinPred op (renameP m l) (renameP m r)
  FQBinArith op l r -> FQBinArith op (renameP m l) (renameP m r)
  FQAnd ps -> FQAnd (map (renameP m) ps)
  FQOr ps -> FQOr (map (renameP m) ps)
  FQNot p -> FQNot (renameP m p)
  FQApp f as -> FQApp f (map (renameP m) as)
  FQIte c a b -> FQIte (renameP m c) (renameP m a) (renameP m b)
  p -> p

-- | A renaming that reverses the order of the names, so that every sort order
-- the generator could read changes.
renaming :: Text -> [Text] -> Map.Map Text Text
renaming pre vs = Map.fromList (zip vs [ pre <> T.pack (show i) | i <- reverse [0 .. length vs - 1] ])

rotate :: Int -> [a] -> [a]
rotate _ [] = []
rotate k xs = let n = k `mod` length xs in drop n xs ++ take n xs

-- | (label, hypotheses, goal, renaming) for each variant of a row.
variants :: Row -> [(Text, [FQPred], FQPred, Map.Map Text Text)]
variants r =
  let hs = flatConjuncts (rowHyps r)
      g = rowGoal r
      m1 = renaming "v" (rowVars r)
      m2 = renaming "u" (reverse (rowVars r))
  in [ ("reversed", reverse hs, g, Map.empty)
     , ("rotated", rotate 3 hs, g, Map.empty)
     , ("flipped", map flipEq hs, flipEq g, Map.empty)
     , ("renamed", map (renameP m1) hs, renameP m1 g, m1)
     , ("combined", map (renameP m2 . flipEq) (rotate 2 (reverse hs)), renameP m2 (flipEq g), m2)
     ]

-- | A fact as a name-free set key, after the renaming: premises as a set,
-- each relation canonical over the renamed polynomial.
factKey :: Map.Map Text Text -> Fact -> (Set.Set (RelOp, Poly), (RelOp, Poly))
factKey m f = (Set.fromList (map rn (factPrem f)), rn (factConc f))
  where
    rn (o, p) = canonRel o (renamePoly p)
    renamePoly p
      | Map.null m = p
      | otherwise = either (error . show) id (toPoly (renameP m (polyPred (const Nothing) p)))

factSet :: Map.Map Text Text -> [Fact] -> Set.Set (Set.Set (RelOp, Poly), (RelOp, Poly))
factSet m = Set.fromList . map (factKey m)

factBlock :: [Fact] -> Text
factBlock fs = T.unlines (map emitPred (renderFacts (monoNames (factMonos fs)) fs))

-- ---------------------------------------------------------------------------
-- Exact evaluation, for the ring identity
-- ---------------------------------------------------------------------------

evalTerm :: Map.Map Text Integer -> FQPred -> Integer
evalTerm env = \case
  FQLit n -> n
  FQVar v -> Map.findWithDefault 0 v env
  FQBinArith op l r ->
    let a = evalTerm env l; b = evalTerm env r in
    case op of
      FQAdd -> a + b
      FQSub -> a - b
      FQMul -> a * b
      FQDiv -> a `div` b
      FQMod -> a `mod` b
      _ -> 0
  FQIte c a b -> if evalCondP env c then evalTerm env a else evalTerm env b
  _ -> 0

evalCondP :: Map.Map Text Integer -> FQPred -> Bool
evalCondP env = \case
  FQBinPred op l r ->
    let a = evalTerm env l; b = evalTerm env r in
    case op of
      FQLt -> a < b
      FQLe -> a <= b
      FQGt -> a > b
      FQGe -> a >= b
      FQEq -> a == b
      FQNeq -> a /= b
      _ -> False
  FQAnd ps -> all (evalCondP env) ps
  FQOr ps -> any (evalCondP env) ps
  FQNot p -> not (evalCondP env p)
  FQTrue -> True
  _ -> False

evalPoly :: Map.Map Text Integer -> Poly -> Integer
evalPoly env p = sum [ c * product (map (evalAtom env) (monoAtoms m)) | (m, c) <- Map.toList p ]

evalAtom :: Map.Map Text Integer -> Atom -> Integer
evalAtom env a = case atomKind a of
  AVar v -> Map.findWithDefault 0 v env
  ADiv f k -> evalPoly env f `div` k
  AMod f k -> evalPoly env f `mod` k
  AIte c x y -> if evalCond env c then evalPoly env x else evalPoly env y
  _ -> 0

evalCond :: Map.Map Text Integer -> Cond -> Bool
evalCond env = \case
  CRel o p -> relHolds o (evalPoly env p)
  CAnd cs -> all (evalCond env) cs
  COr cs -> any (evalCond env) cs
  CNot c -> not (evalCond env c)
  CLeaf p -> evalCondP env p

newtype Term = Term FQPred
instance Show Term where
  show (Term p) = T.unpack (emitPred p)

genTerm :: Int -> Gen FQPred
genTerm 0 = oneof [FQVar <$> elements ["a", "b", "c", "d"], FQLit <$> choose (-5, 5)]
genTerm n = frequency
  [ (2, genTerm 0)
  , (3, FQBinArith FQAdd <$> genTerm (n - 1) <*> genTerm (n - 1))
  , (2, FQBinArith FQSub <$> genTerm (n - 1) <*> genTerm (n - 1))
  , (4, FQBinArith FQMul <$> genTerm (n - 1) <*> genTerm (n - 1))
  , (1, FQBinArith FQDiv <$> genTerm (n - 1) <*> (FQLit <$> choose (1, 4)))
  , (1, FQBinArith FQMod <$> genTerm (n - 1) <*> (FQLit <$> choose (1, 4)))
  , (1, (\x y z -> FQIte (FQBinPred FQLt x (FQLit 0)) y z) <$> genTerm (n - 1) <*> genTerm (n - 1) <*> genTerm (n - 1))
  ]

instance Arbitrary Term where
  arbitrary = Term <$> sized (\s -> genTerm (min 4 (s `div` 20 + 1)))

-- ---------------------------------------------------------------------------
-- z3
-- ---------------------------------------------------------------------------

-- | Each schema of "Fact set" and the mod bound, negated: z3 must answer
-- unsat. The controls must answer sat.
schemaQueries :: [(Text, Text, Text)]
schemaQueries =
  [ ("F1 sign, nonneg", "Int", "(=> (and (>= a 0) (>= b 0)) (>= (* a b) 0))")
  , ("F1 sign, nonpos", "Int", "(=> (and (<= a 0) (>= b 0)) (<= (* a b) 0))")
  , ("F2 zero", "Int", "(=> (= a 0) (= (* a b) 0))")
  , ("F2 one", "Int", "(=> (= a 1) (= (* a b) b))")
  , ("F3 growth", "Int", "(=> (and (>= a 1) (>= b 0)) (>= (* a b) b))")
  , ("F4 monotone", "Int", "(=> (and (<= a c) (<= b d) (>= b 0) (>= c 0)) (<= (* a b) (* c d)))")
  , ("F5 row", "Int", "(=> (and (< a c) (<= b d) (>= b 0) (>= c 0)) (<= (+ (* a b) b) (* c d)))")
  , ("F7 literal bound", "Int", "(=> (and (>= a 0) (<= a k) (>= b 0) (<= b e) (>= k 0) (>= e 0)) (<= (* a b) (* k e)))")
  , ("F7b upper", "Int", "(=> (and (<= a k) (>= b 0)) (<= (* a b) (* k b)))")
  , ("F7b lower", "Int", "(=> (and (>= k 0) (>= a k) (>= b 0)) (>= (* a b) (* k b)))")
  , ("F8 square", "Int", "(>= (* a a) 0)")
  , ("F9 link", "Int", "(=> (= a (+ c d)) (= (* a b) (* (+ c d) b)))")
  , ("F10 congruence", "Int", "(=> (and (= a c) (= b d)) (= (* a b) (* c d)))")
  , ("F11 literal factor", "Int", "(=> (= a k) (= (* a b) (* k b)))")
  , ("mod bound", "Int", "(=> (> k 0) (and (<= 0 (mod a k)) (<= (mod a k) (- k 1))))")
  ]

controlQueries :: [(Text, Text, Text)]
controlQueries =
  [ ("F5 without b >= 0", "Int", "(=> (and (< a c) (<= b d) (>= c 0)) (<= (+ (* a b) b) (* c d)))")
  , ("F7b without b >= 0", "Int", "(=> (<= a k) (<= (* a b) (* k b)))")
  , ("F11 with a wrong k", "Int", "(=> (= a 3) (= (* a b) (* 4 b)))")
  , ("F5 on Real", "Real", "(=> (and (< a c) (<= b d) (>= b 0) (>= c 0)) (<= (+ (* a b) b) (* c d)))")
  ]

smtScript :: [(Text, Text, Text)] -> Text
smtScript qs = T.unlines $ concat
  [ [ "(push)" ]
    ++ [ "(declare-const " <> v <> " " <> s <> ")" | v <- ["a", "b", "c", "d", "e", "k"] ]
    ++ [ "(assert (not " <> body <> "))", "(check-sat)", "(pop)" ]
  | (_, s, body) <- qs ]

-- ---------------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------------

lookupRow :: [Row] -> Text -> Row
lookupRow rs n = case filter ((== n) . rowName) rs of
  (r : _) -> r
  [] -> error ("no row " <> T.unpack n)

factsOf :: Row -> Either Refusal FactResult
factsOf r = productFacts (rowHyps r) (rowGoal r)

productSpec :: Spec
productSpec = describe "MUL-VAR-1 normal form and fact set (ProductNF, ProductFacts)" $ do
  (ws, extra) <- runIO loadRows

  it "the exported table has the 132 witnesses of the design (93 true, 39 false)" $ do
    length ws `shouldBe` 132

  describe "normal form" $ do
    it "is a ring identity: the polynomial evaluates to the term (random terms)" $
      withMaxSuccess 400 $ \(Term t) (a, b, c, d) ->
        let env = Map.fromList (zip ["a", "b", "c", "d"] [a, b, c, d :: Integer]) in
        case toPoly t of
          Left _ -> property True  -- a limit refusal; counted by the limit tests
          Right p -> counterexample (show (Term t)) (evalPoly env p === evalTerm env t)

    it "makes (* w (* h c)) and (* (* w h) c) one term, and (w + 1) / 2 and (1 + w) / 2 one atom" $ do
      let v = FQVar
          mul = FQBinArith FQMul
          add = FQBinArith FQAdd
      toPoly (mul (v "w") (mul (v "h") (v "c"))) `shouldBe` toPoly (mul (mul (v "w") (v "h")) (v "c"))
      toPoly (FQBinArith FQDiv (add (v "w") (FQLit 1)) (FQLit 2))
        `shouldBe` toPoly (FQBinArith FQDiv (add (FQLit 1) (v "w")) (FQLit 2))

    it "refuses degree 8 (monotone, degree 7 and 8) and 343 monomials (7 x 7 x 7), whole, with nonlinear:*" $ do
      forM_ ["monotone-7", "monotone-8", "expand-7x7x7"] $ \n -> do
        let r = lookupRow extra n
        fmap refConstruct (either Just (const Nothing) (factsOf r)) `shouldBe` Just "nonlinear:*"
      let r8 = lookupRow extra "monotone-8"
      case toPoly (case rowGoal r8 of FQBinPred _ l _ -> l; p -> p) of
        Left e -> refWhy e `shouldSatisfy` T.isInfixOf "over 6"
        Right _ -> expectationFailure "a degree-8 product was expanded"
      let r7 = lookupRow extra "expand-7x7x7"
          rhsOfEq = \case
            FQBinPred FQEq _ x -> x
            p -> p
      case toPoly (rhsOfEq (last (rowHyps r7))) of
        Left e -> refWhy e `shouldBe` "expansion over 256 monomials"
        Right _ -> expectationFailure "343 monomials were expanded"

    it "stops the square and mixed chains in the generator (design measurement 5)" $ do
      forM_ [ r | r <- extra, rowName r `elem` ["sq1-1", "sq1-2", "sq1-3", "sq1-6", "mix-1", "mix-2", "mix-3", "mix-6"] ] $ \r ->
        case (rowRefused r, factsOf r) of
          (Just c, Left e) -> refConstruct e `shouldBe` c
          (Nothing, Right fr) -> (rowName r, summarize fr) `shouldBe` (rowName r, expectedOf r)
          (want, got) -> expectationFailure (T.unpack (rowName r) <> ": rev3 " <> show want <> ", here " <> either show (show . summarize) got)

    it "applies the pair cap at 64: crux K=62 keeps F4, F5, F10; K=63 omits them" $ do
      let k62 = lookupRow extra "crux-62"
          k63 = lookupRow extra "crux-63"
      fmap summarize (factsOf k62) `shouldBe` Right (expectedOf k62)
      fmap summarize (factsOf k63) `shouldBe` Right (expectedOf k63)
      case factsOf k63 of
        Right fr -> do
          frCapped fr `shouldBe` True
          [ f | f <- frFacts fr, factFamily f `elem` [F4, F5, F10] ] `shouldSatisfy` null
        Left e -> expectationFailure (show e)

  describe "refusal scan (design measurement 6)" $ do
    it "refuses a variable or non-positive divisor before cancellation, with its operator" $ do
      forM_ ["C1", "C2", "C3", "C4", "C5", "C6"] $ \n -> do
        let r = lookupRow extra n
        fmap refConstruct (either Just (const Nothing) (factsOf r)) `shouldBe` rowRefused r
    it "names / first in (* 0 (/ x y)), and mod in (* 0 (mod x y))" $ do
      let x = FQVar "x"; y = FQVar "y"
      fmap refConstruct (refusalScan (FQBinArith FQMul (FQLit 0) (FQBinArith FQDiv x y))) `shouldBe` Just "nonlinear:/"
      fmap refConstruct (refusalScan (FQBinArith FQMul (FQLit 0) (FQBinArith FQMod x y))) `shouldBe` Just "nonlinear:mod"
      -- the normal form alone would cancel the term
      toPoly (FQBinArith FQMul (FQLit 0) (FQBinArith FQDiv x (FQLit 2))) `shouldBe` Right Map.empty
    it "accepts the controls: (* 0 (/ x 2)) cancels to 0 facts; a ground divisor (+ 1 2) gives 10" $ do
      forM_ ["C7", "C8"] $ \n -> do
        let r = lookupRow extra n
        fmap summarize (factsOf r) `shouldBe` Right (expectedOf r)
      fmap (length . frFacts) (factsOf (lookupRow extra "C7")) `shouldBe` Right 0
      fmap (length . frFacts) (factsOf (lookupRow extra "C8")) `shouldBe` Right 10

  describe "fact set" $ do
    it "W3 crux: 34 facts, T 2, as the design and rev3.py state" $ do
      let r = lookupRow ws "W3"
      fmap summarize (factsOf r) `shouldBe` Right (expectedOf r)
      fmap (length . frFacts) (factsOf r) `shouldBe` Right 34
      fmap frPairs (factsOf r) `shouldBe` Right 2
    it "P3 offset: 1383 facts, T 13, as the design and rev3.py state" $ do
      let r = lookupRow ws "P3"
      fmap summarize (factsOf r) `shouldBe` Right (expectedOf r)
      fmap (length . frFacts) (factsOf r) `shouldBe` Right 1383
      fmap frPairs (factsOf r) `shouldBe` Right 13
    it "W22 monotone degree 4: 21432 facts, T 50, as the design and rev3.py state" $ do
      let r = lookupRow ws "W22"
      fmap summarize (factsOf r) `shouldBe` Right (expectedOf r)
      fmap (length . frFacts) (factsOf r) `shouldBe` Right 21432
      fmap frPairs (factsOf r) `shouldBe` Right 50
    it "every witness: facts, T, cap, closure, degree and families equal rev3.py's (58487 facts in all)" $ do
      diffs <- fmap concat $ forM ws $ \r -> pure $ case (rowRefused r, factsOf r) of
        (Nothing, Right fr) | summarize fr == expectedOf r -> []
        (Just c, Left e) | refConstruct e == c -> []
        (_, got) -> [(rowName r, either show (show . summarize) got, show (expectedOf r))]
      diffs `shouldBe` []
      sum [ either (const 0) (length . frFacts) (factsOf r) | r <- ws ] `shouldBe` 58487
    it "prints facts sorted by text, mul##k numbered in sorted monomial order, sums flat" $ do
      let r = lookupRow ws "W3"
      case factsOf r of
        Right fr -> do
          let names = monoNames (factMonos (frFacts fr))
              txt = map emitPred (renderFacts names (frFacts fr))
          txt `shouldBe` sort txt
          Map.elems names `shouldBe` [ "mul##" <> T.pack (show i) | i <- [0 .. Map.size names - 1] ]
          Map.keys names `shouldBe` Set.toAscList (Set.fromList (Map.keys names))
          -- a fact prints as ((p1 && p2) => c) or (p => c): the one "((" is
          -- the implication's opener, and no comparison has a pair of its own
          all (\t -> T.count "((" t == (if "((" `T.isPrefixOf` t then 1 else 0)) txt `shouldBe` True
          any (T.isInfixOf "(((") txt `shouldBe` False
          take 1 [ t | t <- txt, " && " `T.isInfixOf` t ] `shouldSatisfy` all ("((" `T.isPrefixOf`)
          [ t | t <- txt, "not " `T.isInfixOf` t || " || " `T.isInfixOf` t ] `shouldBe` []
        Left e -> expectationFailure (show e)

  describe "the literal set (design Rev 3b, amendment 3: relation sides at any depth)" $ do
    -- rev3.py on (>= (* (max x 5) w) 0) with (>= w 0): 13 facts,
    -- F1 3, F2 4, F3 2, F11 4. On a written (if (> x 7) x 5): 15 facts,
    -- F1 3, F2 4, F3 2, F11 6 (literals -7, 5 and 7). The emitter prints max
    -- as (if x <= 5 then 5 else x); rev3.py's form is (if x >= 5 then x else 5).
    let x = FQVar "x"; w = FQVar "w"
        hyp = [FQBinPred FQGe w (FQLit 0)]
        goalOf ite = FQBinPred FQGe (FQBinArith FQMul ite w) (FQLit 0)
        rev3Max = Map.fromList [("F1", 3), ("F11", 4), ("F2", 4), ("F3", 2)]
        rev3If7 = Map.fromList [("F1", 3), ("F11", 6), ("F2", 4), ("F3", 2)]
        superset want got =
          all (\(k, n) -> Map.findWithDefault 0 k got >= n) (Map.toList want)
            && all (\k -> k == "F11" || Map.lookup k got == Map.lookup k want) (Map.keys got)
        -- each fact, with mul##k expanded, is valid over the integers: z3
        -- finds no model of its negation
        theorems fr = do
          mz3 <- findExecutable "z3"
          case mz3 of
            Nothing -> pendingWith "z3 not installed"
            Just z3 -> do
              let names = monoNames (factMonos (frFacts fr))
                  back = Map.fromList [ (n, m) | (m, n) <- Map.toList names ]
                  sorts = Map.fromList [("x", FQInt), ("w", FQInt)]
              answers <- forM (renderFacts names (frFacts fr)) $ \f ->
                case mkQuery sorts Map.empty [] (expandMonos back f) of
                  Left why -> pure (emitPred f, Left why)
                  Right q -> (\a -> (emitPred f, Right a)) <$> recheckQuery z3 q
              [ a | a@(_, r) <- answers, r /= Right RUnsat ] `shouldBe` []
    it "a written if (if x > 7 then x else 5) gives rev3.py's 15 facts" $ do
      fmap (familyCounts . frFacts) (productFacts hyp (goalOf (FQIte (FQBinPred FQGt x (FQLit 7)) x (FQLit 5))))
        `shouldBe` Right rev3If7
    it "max x 5, in the emitter's form and in rev3's form, holds rev3.py's facts (extra ones are F11) and every fact is a theorem" $ do
      forM_ [ FQIte (FQBinPred FQLe x (FQLit 5)) (FQLit 5) x
            , FQIte (FQBinPred FQGe x (FQLit 5)) x (FQLit 5) ] $ \ite ->
        case productFacts hyp (goalOf ite) of
          Left e -> expectationFailure (show e)
          Right fr -> do
            familyCounts (frFacts fr) `shouldSatisfy` superset rev3Max
            theorems fr

  describe "invariance (design \"Invariance\")" $ do
    it "F(pi C) = F(C), F(phi C) = F(C), F(rho C) = rho(F(C)) and their composition, on all 132 witnesses" $ do
      let bad = [ (rowName r, lbl)
                | r <- ws
                , Right base <- [factsOf r]
                , (lbl, hs, g, m) <- variants r
                , let v = productFacts hs g
                , case v of
                    Right fr -> factSet Map.empty (frFacts fr) /= factSet m (frFacts base)
                    Left _ -> True ]
      bad `shouldBe` []
    it "prints a byte-identical fact block under pi and phi, on all 132 witnesses" $ do
      let bad = [ (rowName r, lbl)
                | r <- ws
                , Right base <- [factsOf r]
                , (lbl, hs, g, m) <- variants r, Map.null m
                , Right fr <- [productFacts hs g]
                , factBlock (frFacts fr) /= factBlock (frFacts base) ]
      bad `shouldBe` []
    it "control: one rule per atom in conjunct order (Rev 2's reading) fails the same test" $ do
      let bad = [ (rowName r, lbl)
                | r <- ws, rowName r `elem` ["O1", "O2", "O3", "W18", "P6"]
                , Right base <- [productFactsWith FirstRulePerAtom (rowHyps r) (rowGoal r)]
                , (lbl, hs, g, m) <- variants r
                , Right fr <- [productFactsWith FirstRulePerAtom hs g]
                , factSet Map.empty (frFacts fr) /= factSet m (frFacts base) ]
      bad `shouldSatisfy` (not . null)

  describe "the schemas are theorems of integer arithmetic" $ do
    it "z3 (through SolverGuard): each F schema negated is unsat on Int; each control is sat" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just z3 -> do
          tmp <- getTemporaryDirectory
          (path, h) <- openTempFile tmp "mulvar-schemas.smt2"
          TIO.hPutStr h (smtScript (schemaQueries ++ controlQueries))
          hClose h
          res <- runSolverGuarded z3 [path]
          removeFile path
          case res of
            Left stop -> expectationFailure ("solver guard stopped z3: " <> show stop)
            Right (code, out, _) -> do
              code `shouldBe` ExitSuccess
              let answers = filter (`elem` ["sat", "unsat", "unknown"]) (lines out)
                  queryNames = [ l | (l, _, _) <- schemaQueries ++ controlQueries ]
                  want = map (const "unsat") schemaQueries ++ map (const "sat") controlQueries
              zip queryNames answers `shouldBe` zip queryNames want
