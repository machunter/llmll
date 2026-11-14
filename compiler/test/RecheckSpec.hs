-- | MUL-VAR-1 (Rev 3a), Steps 3 to 6: the product pass in the emitter, the
-- product mark, the native recheck (LLMLL.ProductRecheck), and Step 6: the
-- callers' step ('recheckVerdict'), the messages and the Rev 3a
-- core-admission text.
module RecheckSpec (recheckSpec) where

import Test.Hspec

import Data.IORef
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (findExecutable)

import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheckStrictWithCacheAndStatus, emptyEnv)
import LLMLL.TrustReport (downgradeStaleVerifiedSidecar)
import LLMLL.Diagnostic (Diagnostic(..), DiagnosticReport(..))
import LLMLL.PatchApply (PatchedFn(..), notProvedMessage)
import LLMLL.Parser (parseTopLevel)
import LLMLL.FixpointIR
import LLMLL.FixpointEmit (EmitResult(..), EmitOptions(..), FallbackCause(..), emitFixpointWith)
import LLMLL.DiagnosticFQ (FQVerifyResult(..), ConstraintOrigin(..))
import LLMLL.AbstractionVerdict (AbstractionOutcome(..), applyAbstractionVerdict, productRepair)
import qualified LLMLL.ProductNF as PNF
import qualified LLMLL.ProductFacts as PF
import LLMLL.ProductRecheck

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

emitSrc :: Text -> IO EmitResult
emitSrc src = case parseTopLevel GrammarCoreInversion "<mul-var>" src of
  Left err    -> error ("parse failed: " <> show err)
  Right stmts -> emitFixpointWith (EmitOptions True Nothing) "mul-var.llmll" stmts

constraintsOf :: EmitResult -> [FQConstraint]
constraintsOf = fqConstraints . erFQFile

-- | The constraint whose goal names a monomial symbol.
productGoal :: EmitResult -> FQConstraint
productGoal er = case [ c | c <- constraintsOf er, any (PNF.mulSymPrefix `T.isPrefixOf`) (Set.toList (predSymbols (reftPred (conRhs c)))) ] of
  (c : _) -> c
  [] -> error ("no product goal in:\n" <> T.unpack (erFQText er))

flatAnd :: FQPred -> [FQPred]
flatAnd (FQAnd ps) = concatMap flatAnd ps
flatAnd p = [p]

-- | A byte-range fact: @0 <= Map_select ...@ or @Map_select ... <= 255@.
isByteRange :: FQPred -> Bool
isByteRange = \case
  FQBinPred _ (FQApp "Map_select" _) (FQLit k) -> k `elem` [0, 255]
  FQBinPred _ (FQLit k) (FQApp "Map_select" _) -> k `elem` [0, 255]
  _ -> False

readOne :: Text -> Either Text Value
readOne t = case parseSexps t of
  Right [s] -> readValue Map.empty s
  Right _ -> Left "not one form"
  Left e -> Left e

origin :: Text -> Text -> ConstraintOrigin
origin f cl = ConstraintOrigin f cl "/statements/0" "x.llmll" Nothing

-- | An emit result with only the fields the budget reads set.
budgetEmit :: EmitResult -> [(FQConstraintId, Text, Text)] -> EmitResult
budgetEmit er rows = er
  { erProductMarked = Set.fromList [ i | (i, _, _) <- rows ]
  , erConstraintTable = Map.fromList [ (i, origin f cl) | (i, f, cl) <- rows ]
  , erAbstracted = Map.empty
  , erPostUnassumed = Map.empty }

b1Src, m1Src, w3Src :: Text
b1Src = T.unlines
  [ "(module mv-b1 (export mv-b1)"
  , "  (def-shell mv-b1 [v: int i: int b: bytes[64]] -> int"
  , "    (pre (and (>= i 0) (and (< i 64) (= v (bytes-get b i)))))"
  , "    (post (<= (* v v) 65025))"
  , "    0))" ]
m1Src = T.unlines
  [ "(module mv-m1 (export mv-m1)"
  , "  (def-shell mv-m1 [w: int h: int y: int x: int] -> int"
  , "    (pre (and (>= y 0) (and (< y h) (and (>= x 0) (<= x w)))))"
  , "    (post (< (+ (* y w) x) (* w h)))"
  , "    0))" ]
w3Src = T.unlines
  [ "(module mv-w3 (export mv-w3)"
  , "  (def-shell mv-w3 [w: int h: int y: int x: int r: int] -> int"
  , "    (pre (and (>= y 0) (and (< y h) (and (>= x 0) (and (< x w) (= r (+ (* y w) x)))))))"
  , "    (post (and (>= r 0) (< r (* w h))))"
  , "    0))" ]

-- | Statements of one module, parsed.
parseMod :: Text -> [Statement]
parseMod src = case parseTopLevel GrammarCoreInversion "<mul-var>" src of
  Left err    -> error ("parse failed: " <> show err)
  Right stmts -> stmts

-- | The W-BODY-FALLBACK diagnostics of an emit result.
bodyFallbackMsgs :: EmitResult -> [Text]
bodyFallbackMsgs er = [ diagMessage d | d <- erDiagnostics er, diagCode d == Just "W-BODY-FALLBACK" ]

-- | MUL-VAR-1 Rev 3a: a caller module @c@ of the imported @m.f@ whose
-- sidecar entry is the given one (or none), checked under strict core.
coreAdmission :: Text -> Maybe ContractStatus -> [Diagnostic]
coreAdmission fSrc mcs =
  let mStmts = parseMod fSrc
      menv = ModuleEnv
        { meExports        = Map.fromList [("f", TFn [TInt, TInt, TInt] TBool)]
        , meStatements     = mStmts
        , meInterfaces     = Map.empty
        , meAliasMap       = Map.empty
        , mePath           = ["m"]
        , meContractStatus = maybe Map.empty (\cs -> Map.fromList [("f", cs)]) mcs
        , meContracts      = Map.empty
        , meRetTypes       = Map.empty
        , meBuiltinAxioms  = Nothing, meGenericSites = Map.empty }
      cStmts = parseMod $ T.unlines
        [ "(module c (import m)"
        , "  (def c [a: int] -> bool (pre (> a 0)) (post true) (m.f a a a)))" ]
  in reportDiagnostics (typeCheckStrictWithCacheAndStatus GrammarCoreInversion
                          (Map.fromList [(["m"], menv)]) Map.empty emptyEnv cStmts)

-- | A sidecar entry that is not admissible: verify ran and asserted the post.
assertedCS :: ContractStatus
assertedCS = ContractStatus Nothing
  (Just (EvidenceRecord DLAsserted False Nothing [] False Nothing Nothing False Nothing False [])) []

-- | The design's positive witness (mul-var-proposal.md, "Caller, at core
-- admission"): the facts cannot prove the cubic inequality, so verify falls
-- back on f.
cubicSrc :: Text
cubicSrc = T.unlines
  [ "(module m (export f)"
  , "  (def f [x: int y: int z: int] -> bool"
  , "    (pre (and (> x 0) (and (> y 0) (> z 0))))"
  , "    (post (= result true))"
  , "    (!= (+ (* x (* x x)) (* y (* y y))) (* z (* z z)))))" ]

coreKinds :: [Diagnostic] -> [Diagnostic]
coreKinds ds = [ d | d <- ds, diagKind d == Just "core-membership-violation" ]

nonlinearText :: Text
nonlinearText = "def 'c': callee 'm.f' was verified but is not body-faithful. Its body holds a product of two non-constant terms at (* x (* x x)); verify may fall back on such a product. Only verified functions are admissible in strict-core bodies."

-- ---------------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------------

recheckSpec :: Spec
recheckSpec = describe "MUL-VAR-1 product pass, mark and native recheck" $ do

  describe "printing (FixpointIR)" $ do
    it "prints a fact as an implication, comparisons bare: ((a >= 0 && b >= 0) => m >= 0)" $ do
      let a = FQVar "a"; b = FQVar "b"; m = FQVar "mul##0"
      emitPred (FQImplies (FQAnd [FQBinPred FQGe a (FQLit 0), FQBinPred FQGe b (FQLit 0)]) (FQBinPred FQGe m (FQLit 0)))
        `shouldBe` "((a >= 0 && b >= 0) => mul##0 >= 0)"
      emitPred (FQImplies (FQBinPred FQEq a (FQLit 1)) (FQBinPred FQEq m b))
        `shouldBe` "(a = 1 => mul##0 = b)"
      emitPred (FQAnd [FQBinPred FQGe a (FQLit 0), FQImplies (FQBinPred FQEq a (FQLit 0)) (FQBinPred FQEq m (FQLit 0))])
        `shouldBe` "a >= 0 && (a = 0 => mul##0 = 0)"
    it "passes mul##k through sanitizeFQId, and a source mul_0 or mul stays apart from it" $ do
      emitPred (FQVar "mul##3") `shouldBe` "mul##3"
      predSymbols (FQAnd [FQVar "mul##0", FQVar "mul_0", FQVar "mul"])
        `shouldBe` Set.fromList ["mul##0", "mul_0", "mul"]
      emitPred (FQVar "mul-0") `shouldBe` "mul_0"

  describe "the product pass (FixpointEmit)" $ do
    it "W3: the goal and pre print in normal form with mul##k binders; the lhs carries the facts" $ do
      er <- emitSrc w3Src
      let txt = erFQText er
      T.unpack txt `shouldContain` "mul##0"
      T.unpack txt `shouldContain` " => "
      -- no product of two non-constant terms reaches the solver
      any (PF.hasProduct . reftPred . conLhs) (constraintsOf er) `shouldBe` False
      any (PF.hasProduct . reftPred . conRhs) (constraintsOf er) `shouldBe` False
      any (PF.hasProduct . reftPred . bindReft) (fqBinds (erFQFile er)) `shouldBe` False
      lookup "mv-w3" (erGroundFactFamilies er) `shouldSatisfy` maybe False ("product-facts" `elem`)
    it "every constraint that names mul##k has an owner, is marked, and has a monomial table entry" $ do
      ers <- mapM emitSrc [w3Src, m1Src, b1Src]
      let bad = [ (conId c, T.unpack (erFQText er))
                | er <- ers, c <- constraintsOf er
                , let syms = Set.toList (Set.unions (map predSymbols [reftPred (conLhs c), reftPred (conRhs c)]))
                , any (PNF.mulSymPrefix `T.isPrefixOf`) syms
                , not (Map.member (conId c) (erConstraintTable er))
                  || not (conId c `Set.member` erProductMarked er)
                  || not (Map.member (conId c) (erMonoTable er)) ]
      map fst bad `shouldBe` []
      sum (map (Set.size . erProductMarked) ers) `shouldSatisfy` (> 0)
    it "names every degree-2 monomial of the whole constraint, not only those in the facts" $ do
      er <- emitSrc w3Src
      let file = erFQFile er
          bmap = Map.fromList [ (bindId b, b) | b <- fqBinds file ]
      sequence_
        [ do let named = Set.fromList [ n | i <- conEnv c, Just b <- [Map.lookup i bmap], let n = bindName b
                                          , PNF.mulSymPrefix `T.isPrefixOf` n ]
                 used = Set.filter (PNF.mulSymPrefix `T.isPrefixOf`)
                          (Set.unions (map predSymbols [reftPred (conLhs c), reftPred (conRhs c)]))
                 table = Map.findWithDefault Map.empty (conId c) (erMonoTable er)
             used `shouldSatisfy` (`Set.isSubsetOf` named)
             Map.keysSet table `shouldBe` named
        | c <- constraintsOf er, conId c `Set.member` erProductMarked er ]
    it "monoNames gets the goal's monomials, not only the facts' (decision 3)" $ do
      -- (* x y) appears only in the goal. Every probe so far has facts naming
      -- each written monomial too, so this checks the naming end to end
      -- rather than separating the two sources. (An `if` in a contract is not
      -- translated, so the goal cannot hold the product in an FQIte branch.)
      let x = FQVar "x"; y = FQVar "y"
      xy <- case PNF.toPoly (FQBinArith FQMul x y) of
        Right p | [(m, 1)] <- Map.toList p -> pure m
        other -> expectationFailure (show other) >> fail "no monomial"
      er <- emitSrc $ T.unlines
        [ "(module mv-ite (export mv-ite)"
        , "  (def-shell mv-ite [x: int y: int z: int] -> int"
        , "    (post (>= (+ (* x y) z) (- 0 5)))"
        , "    0))" ]
      any (PF.hasProduct . reftPred . conRhs) (constraintsOf er) `shouldBe` False
      let tables = Map.elems (erMonoTable er)
      tables `shouldSatisfy` (not . null)
      tables `shouldSatisfy` all (elem xy . Map.elems)
    it "a product in a body guard reaches the product pass (design Rev 3b, amendment 4)" $ do
      -- The dispatch witness: (post true) gives no constraint, so it shows
      -- only that the guard no longer sends g to body fallback.
      er <- emitSrc $ T.unlines
        [ "(module mv-guard (export g)"
        , "  (def-shell g [y: int w: int n: int] -> bool"
        , "    (pre (and (>= y 0) (>= w 0)))"
        , "    (post true)"
        , "    (if (< (* y w) n) true false)))" ]
      "g" `elem` erBodyFallback er `shouldBe` False
      -- An int result, so the guard is a path condition of a real constraint
      er2 <- emitSrc $ T.unlines
        [ "(module mv-guard2 (export g2)"
        , "  (def-shell g2 [y: int w: int n: int] -> int"
        , "    (pre (and (>= y 0) (>= w 0)))"
        , "    (post (>= result 0))"
        , "    (if (< (* y w) n) (- n (* y w)) 0)))" ]
      let holds c = "mul##0" `Set.member` Set.unions
            (map predSymbols [reftPred (conLhs c), reftPred (conRhs c)])
      filter holds (constraintsOf er2) `shouldSatisfy` ((== 2) . length)
      "g2" `elem` erBodyFallback er2 `shouldBe` False
      any (PF.hasProduct . reftPred . conLhs) (constraintsOf er2) `shouldBe` False
      T.unpack (erFQText er2) `shouldContain` "mul##0 < n"
    it "a product-free source prints no mul##, no implication and no product-facts family" $ do
      er <- emitSrc $ T.unlines
        [ "(module lin (export lin)"
        , "  (def-shell lin [w: int y: int x: int r: int] -> int"
        , "    (pre (and (>= y 0) (and (>= x 0) (= r (+ (* 3 y) x)))))"
        , "    (post (>= r 0))"
        , "    0))" ]
      T.unpack (erFQText er) `shouldNotContain` "mul##"
      T.unpack (erFQText er) `shouldNotContain` "=>"
      erProductMarked er `shouldBe` Set.empty
      erMonoTable er `shouldBe` Map.empty
      concatMap snd (erGroundFactFamilies er) `shouldNotContain` ["product-facts"]
    it "a goal that reduces to true sends no constraint for it (P1, an identity)" $ do
      er <- emitSrc $ T.unlines
        [ "(module mv-p1 (export mv-p1)"
        , "  (def-shell mv-p1 [a: int b: int] -> int"
        , "    (post (= (* a b) (* b a)))"
        , "    0))" ]
      [ c | c <- constraintsOf er, conId c `Set.member` erProductMarked er ] `shouldBe` []
      any (PF.hasProduct . reftPred . conRhs) (constraintsOf er) `shouldBe` False
    it "a degree-8 chain refuses the whole function with nonlinear:* and no constraint of it is kept" $ do
      er <- emitSrc $ T.unlines
        [ "(module mv-chain (export mv-chain)"
        , "  (def-shell mv-chain [x0: int x1: int x2: int] -> int"
        , "    (pre (and (= x1 (+ (* x0 x0) 1)) (= x2 (+ (* x1 x1) 1))))"
        , "    (post (>= (* x2 x2) 0))"
        , "    0))" ]
      lookup "mv-chain" (erFallbackConstructs er) `shouldBe` Just ["nonlinear:*"]
      "mv-chain" `elem` erBodyFallback er `shouldBe` True
      [ c | c <- constraintsOf er, Just o <- [Map.lookup (conId c) (erConstraintTable er)], coFunction o == "mv-chain" ]
        `shouldBe` []
    it "a decreases measure with a product stays refused (design edge case 16)" $ do
      er <- emitSrc $ T.unlines
        [ "(module mv-dec (export mv-dec)"
        , "  (def-shell mv-dec [a: int b: int] -> int"
        , "    (pre (and (>= a 0) (>= b 0)))"
        , "    (post (>= result 0))"
        , "    (decreases (* a b))"
        , "    (if (= a 0) 0 (mv-dec (- a 1) b))))" ]
      [ c | c <- constraintsOf er, "decreases" `elem` conTag c ] `shouldBe` []

  describe "the verdict (AbstractionVerdict)" $ do
    it "a product-marked failing id with no other mark falls back as abstraction:nonlinear:*" $ do
      er <- emitSrc w3Src
      let c = productGoal er
          av = applyAbstractionVerdict Set.empty er (FQUnsafe [conId c])
      aoResult av `shouldBe` FQSafe
      lookup "mv-w3" (erFallbackConstructs (aoEmit av)) `shouldBe` Just ["abstraction:nonlinear:*"]
      lookup "mv-w3" (erBodyFallbackCauses (aoEmit av)) `shouldSatisfy` (/= Nothing)
    it "a cleared id loses the product mark, so the function is refuted" $ do
      er <- emitSrc w3Src
      let c = productGoal er
          av = applyAbstractionVerdict (Set.singleton (conId c)) er (FQUnsafe [conId c])
      aoResult av `shouldBe` FQUnsafe [conId c]
      aoRefuted av `shouldBe` Set.fromList ["mv-w3"]
    it "a function already in fallback keeps its first cause, with no second entry" $ do
      er0 <- emitSrc w3Src
      let c = productGoal er0
          er = er0 { erBodyFaithfulFns = [], erBodyFallback = ["mv-w3"]
                   , erBodyFallbackCauses = [ (n, k) | (n, k) <- [("mv-w3", FallbackBody)] ] }
          av = applyAbstractionVerdict Set.empty er (FQUnsafe [conId c])
      aoResult av `shouldBe` FQSafe
      erBodyFallback (aoEmit av) `shouldBe` ["mv-w3"]
      erBodyFallbackCauses (aoEmit av) `shouldBe` erBodyFallbackCauses er
      aoRefuted av `shouldBe` Set.empty

  describe "the model reader" $ do
    it "reads integers, a negative integer and booleans" $ do
      readOne "42" `shouldBe` Right (VInt 42)
      readOne "(- 7)" `shouldBe` Right (VInt (-7))
      readOne "true" `shouldBe` Right (VBool True)
      readOne "false" `shouldBe` Right (VBool False)
    it "reads (as const (Array Int Int)) and nested store as a finite map with a default" $ do
      readOne "((as const (Array Int Int)) 8)" `shouldBe` Right (VMap (VInt 8) Map.empty)
      readOne "(store (store ((as const (Array Int Int)) 2) 0 4) 3 1)"
        `shouldBe` Right (VMap (VInt 2) (Map.fromList [(VInt 0, VInt 4), (VInt 3, VInt 1)]))
      -- an exception equal to the default is not stored: equal maps compare equal
      readOne "(store ((as const (Array Int Int)) 5) 1 5)" `shouldBe` Right (VMap (VInt 5) Map.empty)
    it "reads Str!val!k as a token, and an array of tokens (BF8)" $ do
      readOne "Str!val!0" `shouldBe` Right (VTok "Str!val!0")
      readOne "(store ((as const (Array Int Str)) Str!val!0) (- 1) Str!val!1)"
        `shouldBe` Right (VMap (VTok "Str!val!0") (Map.fromList [(VInt (-1), VTok "Str!val!1")]))
    it "reads let, lambda, and (_ as-array f) through a get-model definition" $ do
      readOne "(let ((a!1 (store ((as const (Array Int Int)) 0) 1 9))) (store a!1 2 3))"
        `shouldBe` Right (VMap (VInt 0) (Map.fromList [(VInt 1, VInt 9), (VInt 2, VInt 3)]))
      readOne "(lambda ((x!1 Int)) (ite (= x!1 3) 5 (ite (= 4 x!1) 6 0)))"
        `shouldBe` Right (VMap (VInt 0) (Map.fromList [(VInt 3, VInt 5), (VInt 4, VInt 6)]))
      case parseSexps "((define-fun k!0 ((x!0 Int)) Int (ite (= x!0 2) 7 1)))" of
        Right forms -> do
          let defs = readModelDefs forms
          case parseSexps "(_ as-array k!0)" of
            Right [s] -> readValue defs s `shouldBe` Right (VMap (VInt 1) (Map.fromList [(VInt 2, VInt 7)]))
            other -> expectationFailure (show other)
        Left e -> expectationFailure (show e)
    it "refuses anything else: a real, a bit-vector, an unknown atom, an as-array with no definition" $ do
      readOne "1.5" `shouldSatisfy` isLeft
      readOne "(_ bv5 8)" `shouldSatisfy` isLeft
      readOne "foo" `shouldSatisfy` isLeft
      readOne "(_ as-array k!9)" `shouldSatisfy` isLeft
      readOne "(lambda ((x!1 Int)) (ite (> x!1 3) 5 0))" `shouldSatisfy` isLeft
    it "parses z3's printed get-value line (design measurement 7, BF5)" $ do
      let out = "sat\n((hs (store ((as const (Array Int Int)) 2) 0 4)) (k 0) (w 3) ((bytesLen b) 2))\n"
      case parseSexps out of
        Right [SAtom "sat", SList pairs] -> do
          length pairs `shouldBe` 4
          [ readValue Map.empty v | SList [_, v] <- pairs ]
            `shouldBe` [ Right (VMap (VInt 2) (Map.fromList [(VInt 0, VInt 4)])), Right (VInt 0), Right (VInt 3), Right (VInt 2) ]
        other -> expectationFailure (show other)

  describe "the evaluator" $ do
    let s = FQVar "s"; t = FQVar "t"
        lenS = FQApp "strLen" [s]; lenT = FQApp "strLen" [t]
        q = Query [("s", SStr), ("t", SStr)] [("strLen", [SStr], SInt)]
                  [FQBinPred FQEq s t] (FQBinPred FQEq lenS lenT) [lenS, lenT]
        vars = Map.fromList [("s", VTok "Str!val!0"), ("t", VTok "Str!val!0")]
    it "function consistency (BF6 control): equal arguments with different results fail" $ do
      validateModel q vars [(lenS, VInt 0), (lenT, VInt 1)] `shouldSatisfy` isLeftWith "function consistency"
    it "the same model with consistent results is not a counterexample to s = t => strLen s = strLen t" $
      validateModel q vars [(lenS, VInt 0), (lenT, VInt 0)] `shouldSatisfy` isLeft
    it "uses Haskell div and mod on a negative dividend, and exact products" $ do
      let m = Model (Map.fromList [("x", VInt (-3)), ("y", VInt 12345678901)]) Map.empty
      evalPred m (FQBinArith FQDiv (FQVar "x") (FQLit 2)) `shouldBe` Right (VInt (-2))
      evalPred m (FQBinArith FQMod (FQVar "x") (FQLit 2)) `shouldBe` Right (VInt 1)
      evalPred m (FQBinArith FQMul (FQVar "y") (FQVar "y")) `shouldBe` Right (VInt (12345678901 * 12345678901))
    it "expands mul##k to the product of its atoms" $ do
      case PNF.toPoly (FQBinArith FQMul (FQVar "w") (FQVar "h")) of
        Right p | [(m, 1)] <- Map.toList p ->
          emitPred (expandMonos (Map.fromList [("mul##0", m)]) (FQBinPred FQLt (FQVar "r") (FQVar "mul##0")))
            `shouldBe` "(r < (h * w))"
        other -> expectationFailure (show other)

  describe "the budget" $ do
    it "rechecks at most 8 ids per function per partition, in id order" $ do
      er0 <- emitSrc w3Src
      let rows = [ (i, "f", "post") | i <- [100 .. 119] ] ++ [ (i, "f", "wd-post") | i <- [200 .. 202] ]
                 ++ [ (i, "g", "post") | i <- [300 .. 309] ]
          er = budgetEmit er0 rows
          cands = recheckCandidates er (FQUnsafe (map (\(i, _, _) -> i) rows))
      map (length . snd) cands `shouldSatisfy` all (<= 8)
      lookup ("f", PTruth) cands `shouldBe` Just [100 .. 107]
      lookup ("f", PDefinedness) cands `shouldBe` Just [200 .. 202]
      lookup ("g", PTruth) cands `shouldBe` Just [300 .. 307]
    it "stops each partition at its first validated id, and runs the other partitions" $ do
      er0 <- emitSrc w3Src
      let rows = [ (i, "f", "post") | i <- [100 .. 119] ] ++ [ (i, "f", "wd-post") | i <- [200 .. 209] ]
          er = budgetEmit er0 rows
      calls <- newIORef []
      let run i = do
            modifyIORef' calls (i :)
            pure (if i == 102 then RValidated [] else RUnsat)
      (cleared, _) <- recheckProductsWith run er (FQUnsafe (map (\(i, _, _) -> i) rows))
      cs <- reverse <$> readIORef calls
      cleared `shouldBe` Set.fromList [102]
      filter (< 200) cs `shouldBe` [100, 101, 102]
      filter (>= 200) cs `shouldBe` [200 .. 207]
    it "does not recheck an id that carries another mark as well" $ do
      er0 <- emitSrc w3Src
      let er = (budgetEmit er0 [(100, "f", "post"), (101, "f", "post")]) { erAbstracted = Map.fromList [(100, "g")] }
      recheckCandidates er (FQUnsafe [100, 101]) `shouldBe` [(("f", PTruth), [101])]
    it "with no z3, every mark stays" $ do
      er <- emitSrc w3Src
      let c = productGoal er
      (cleared, answers) <- recheckProducts Nothing er (FQUnsafe [conId c])
      cleared `shouldBe` Set.empty
      map snd answers `shouldBe` [RNoSolver]

  describe "z3 on the emitted constraint (through the solver guard)" $ do
    it "M1 (false): native sat, the model validates, so the id is cleared" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just z3 -> do
          er <- emitSrc m1Src
          let c = productGoal er
          (cleared, answers) <- recheckProducts (Just z3) er (FQUnsafe [conId c])
          map snd answers `shouldSatisfy` all isValidated
          cleared `shouldBe` Set.singleton (conId c)
    it "W3 (true): native unsat keeps the mark" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just z3 -> do
          er <- emitSrc w3Src
          let c = productGoal er
          (cleared, answers) <- recheckProducts (Just z3) er (FQUnsafe [conId c])
          cleared `shouldBe` Set.empty
          map snd answers `shouldBe` [RUnsat]
    it "B1: byte-range stays in the query; dropping it gives a false refuted at a byte outside 0..255" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just z3 -> do
          er <- emitSrc b1Src
          let c = productGoal er
              cid = conId c
              base = Map.findWithDefault FQTrue cid (erProductLhs er)
          -- the family is in the lhs the recheck reads
          filter isByteRange (flatAnd base) `shouldSatisfy` (not . null)
          case buildQuery er cid of
            Left why -> expectationFailure (T.unpack why)
            Right q -> do
              any isByteRange (concatMap flatAnd (qHyps q)) `shouldBe` True
              a <- recheckQuery z3 q
              a `shouldBe` RUnsat
          -- the control: without the family the VC has a model at a negative byte
          let er' = er { erProductLhs = Map.insert cid (FQAnd (filter (not . isByteRange) (flatAnd base))) (erProductLhs er) }
          case buildQuery er' cid of
            Left why -> expectationFailure (T.unpack why)
            Right q' -> do
              a' <- recheckQuery z3 q'
              case a' of
                RValidated vals -> lookup "v" vals `shouldSatisfy` maybe False (\case VInt n -> n < 0 || n > 255; _ -> False)
                other -> expectationFailure ("expected a validated model, got " <> show other)

  describe "Step 6: the callers' step and the messages" $ do
    it "recheckVerdict: M1's validated model clears the id, so the function is refuted" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just _ -> do
          er <- emitSrc m1Src
          let c = productGoal er
          (av, answers) <- recheckVerdict er (FQUnsafe [conId c])
          map snd answers `shouldSatisfy` all isValidated
          aoResult av `shouldBe` FQUnsafe [conId c]
          aoRefuted av `shouldBe` Set.fromList ["mv-m1"]
          aoAbstractionConstructs av `shouldBe` []
    it "recheckVerdict: a native unsat keeps the mark, so the function falls back (never verified)" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just _ -> do
          er <- emitSrc w3Src
          let c = productGoal er
          (av, answers) <- recheckVerdict er (FQUnsafe [conId c])
          map snd answers `shouldBe` [RUnsat]
          aoRefuted av `shouldBe` Set.empty
          "mv-w3" `elem` erBodyFaithfulFns (aoEmit av) `shouldBe` False
          aoAbstractionConstructs av `shouldBe` [("mv-w3", "abstraction:nonlinear:*")]
    it "recheckVerdict: an answer with no product-marked failing id runs no recheck" $ do
      er <- emitSrc w3Src
      (av, answers) <- recheckVerdict er FQSafe
      answers `shouldBe` []
      aoResult av `shouldBe` FQSafe
      (av2, answers2) <- recheckVerdict er (FQUnsafe [9999])
      answers2 `shouldBe` []
      aoResult av2 `shouldBe` FQUnsafe [9999]
    it "F11: a product prints abstraction:nonlinear:*, never abstraction:app: or ''; W-BODY-FALLBACK has the product text" $ do
      er <- emitSrc w3Src
      let c = productGoal er
          av = applyAbstractionVerdict Set.empty er (FQUnsafe [conId c])
          msgs = bodyFallbackMsgs (aoEmit av)
      aoAbstractionConstructs av `shouldBe` [("mv-w3", "abstraction:nonlinear:*")]
      msgs `shouldBe`
        [ T.intercalate "\n"
            [ "W-BODY-FALLBACK mv-w3: the post is not proved. A product is in the failing constraint."
            , "  Refused by: abstraction:nonlinear:*   at " <> maybe "" coJsonPtr (Map.lookup (conId c) (erConstraintTable er))
            , "  Product facts did not prove it. Native z3 found no counterexample."
            , "  The post stays a run-time check. A strict-core def that calls mv-w3 will be refused." ] ]
      any (\m -> "''" `T.isInfixOf` m || "abstraction:app:" `T.isInfixOf` m) msgs `shouldBe` False
    it "over the pair limit, the W-BODY-FALLBACK names the pair count and the limit" $ do
      er0 <- emitSrc w3Src
      let c = productGoal er0
          er = er0 { erProductPairs = Map.singleton (conId c) 65 }
          msgs = bodyFallbackMsgs (aoEmit (applyAbstractionVerdict Set.empty er (FQUnsafe [conId c])))
      msgs `shouldSatisfy` any (T.isInfixOf "  This constraint holds 65 product pairs, including any unrelated product in scope; the limit is 64, so monotonicity and congruence facts were not added.")
      msgs `shouldSatisfy` all (not . T.isInfixOf "Product facts did not prove it")
    it "F11: a definedness-only product fallback gets the product repair, not \"two calls to ''\"" $ do
      er0 <- emitSrc w3Src
      let c = productGoal er0
          er = er0 { erConstraintTable = Map.adjust (\o -> o { coClause = "wd-post" }) (conId c) (erConstraintTable er0) }
          av = applyAbstractionVerdict Set.empty er (FQUnsafe [conId c])
          msgs = bodyFallbackMsgs (aoEmit av)
      aoWelldefUnproved av `shouldBe` [("mv-w3", "welldef:abstraction:nonlinear:*")]
      msgs `shouldSatisfy` any (productRepair `T.isSuffixOf`)
      any ("''" `T.isInfixOf`) msgs `shouldBe` False
    it "a limit refusal prints W-BODY-FALLBACK with the over-the-limit line (it was silent)" $ do
      er <- emitSrc $ T.unlines
        [ "(module mv-chain (export mv-chain)"
        , "  (def-shell mv-chain [x0: int x1: int x2: int] -> int"
        , "    (pre (and (= x1 (+ (* x0 x0) 1)) (= x2 (+ (* x1 x1) 1))))"
        , "    (post (>= (* x2 x2) 0))"
        , "    0))" ]
      case bodyFallbackMsgs er of
        [m] -> do
          T.lines m !! 0 `shouldBe` "W-BODY-FALLBACK mv-chain: the post is not proved. A product is in the failing constraint."
          T.lines m !! 1 `shouldSatisfy` T.isPrefixOf "  Refused by: nonlinear:*   at /statements/"
          T.lines m !! 2 `shouldBe` "  This constraint is over the limit for products after its equations are applied."
        other -> expectationFailure ("expected one W-BODY-FALLBACK, got " <> show other)
    it "finding 4: a product refused inside a pre (pre-d7) is contract-pre-outside-fragment" $ do
      er <- emitSrc $ T.unlines
        [ "(module pre-d7 (export pd7)"
        , "  (def-shell pd7 [x: int y: int] -> int"
        , "    (pre (> (* x (* x (* x (* x (* x (* x (* x y))))))) 0))"
        , "    (post (>= result 0))"
        , "    (+ y 1)))" ]
      lookup "pd7" (erBodyFallbackCauses er) `shouldBe` Just FallbackContractPre
      lookup "pd7" (erFallbackConstructs er) `shouldBe` Just ["nonlinear:*"]
    it "finding 4 control: the same product in the body stays body-outside-fragment" $ do
      er <- emitSrc $ T.unlines
        [ "(module body-d7 (export bd7)"
        , "  (def-shell bd7 [x: int y: int] -> int"
        , "    (pre (> y 0))"
        , "    (post (>= result 0))"
        , "    (* x (* x (* x (* x (* x (* x (* x y)))))))))" ]
      lookup "bd7" (erBodyFallbackCauses er) `shouldBe` Just FallbackBody
    it "the refuted line prints integer and boolean values in name order, in the one allowed form" $ do
      counterexampleLine [("y", VInt 24), ("h", VInt 25), ("b", VMap (VInt 0) Map.empty), ("w", VInt 21), ("x", VInt (-1)), ("p", VBool True)]
        `shouldBe` "VC counterexample: h=25 p=true w=21 x=-1 y=24. Callee results in it are assumed, not computed."
    it "patch: notProvedMessage names the product, not two calls" $ do
      notProvedMessage (PatchedFn "f" False (Just "abstraction-unsafe") ["abstraction:nonlinear:*"])
        `shouldBe` "'f' was not proved: a product is in the failing constraint, and native z3 found no counterexample (abstraction:nonlinear:*). Its postcondition was assumed."

  describe "Step 6: core admission (Rev 3a, caller of an imported callee with a product)" $ do
    it "positive witness: an asserted sidecar entry and the cubic body give the product text" $ do
      let ds = coreKinds (coreAdmission cubicSrc (Just assertedCS))
      map diagMessage ds `shouldBe` [nonlinearText]
      map diagSuggestion ds `shouldBe`
        [Just "run (llmll verify) on m.f's module and read W-BODY-FALLBACK for the cause; restate m.f's contract, or write 'c' as a def-shell."]
    it "a callee in the same file keeps the Local text" $ do
      let stmts = parseMod $ T.unlines
            [ "(module m"
            , "  (def f [x: int y: int z: int] -> bool"
            , "    (pre (and (> x 0) (and (> y 0) (> z 0))))"
            , "    (post (= result true))"
            , "    (!= (+ (* x (* x x)) (* y (* y y))) (* z (* z z))))"
            , "  (def c [a: int] -> bool (pre (> a 0)) (post true) (f a a a)))" ]
          ds = coreKinds (reportDiagnostics (typeCheckStrictWithCacheAndStatus GrammarCoreInversion
                 Map.empty (Map.fromList [("f", assertedCS)]) emptyEnv stmts))
      map diagMessage ds `shouldSatisfy` all (T.isInfixOf "is defined in this file")
      length ds `shouldBe` 1
    it "a callee with a product and no sidecar entry keeps today's text" $ do
      let ds = coreKinds (coreAdmission cubicSrc Nothing)
      map diagMessage ds `shouldBe`
        ["def 'c': callee 'm.f' is not body-faithful and not in the trusted prelude; only verified (body-faithful) functions and trusted builtins are admissible in strict-core bodies"]
    it "a callee whose fallback has another cause but whose body holds a product gets the product text" $ do
      let src = T.unlines
            [ "(module m (export f)"
            , "  (def-shell f [x: int y: int z: int] -> bool"
            , "    (post (= result true))"
            , "    (let [(s (string-concat \"a\" \"b\"))]"
            , "      (> (+ (string-length s) (* x y)) z))))" ]
          ds = coreKinds (coreAdmission src (Just assertedCS))
      map diagMessage ds `shouldSatisfy` all (T.isInfixOf "holds a product of two non-constant terms at (* x y);")
      length ds `shouldBe` 1
    it "a stale sidecar entry (hash no longer matches) gets the product text" $ do
      let staleER = EvidenceRecord (DLVerified "liquid-fixpoint") True Nothing [] False Nothing Nothing False
                      (Just "0000000000000000000000000000000000000000000000000000000000000000") False []
          raw = Map.fromList [("f", ContractStatus Nothing (Just staleER) [])]
          (validated, _) = downgradeStaleVerifiedSidecar (parseMod cubicSrc) raw
      fmap erBodyFaithful (csPost (validated Map.! "f")) `shouldBe` Just False
      map diagMessage (coreKinds (coreAdmission cubicSrc (Map.lookup "f" validated))) `shouldBe` [nonlinearText]
    it "a constant-folded product does not match: (* 3 x) and (* (+ 1 2) x) keep today's text" $ do
      let src = T.unlines
            [ "(module m (export f)"
            , "  (def f [x: int y: int z: int] -> bool"
            , "    (post (= result true))"
            , "    (> (+ (* 3 x) (* (+ 1 2) y)) z)))" ]
          ds = coreKinds (coreAdmission src (Just assertedCS))
      map diagMessage ds `shouldSatisfy` all (T.isInfixOf "is not body-faithful and not in the trusted prelude")
      length ds `shouldBe` 1
  where
    isLeft = either (const True) (const False)
    isLeftWith frag = either (\e -> T.unpack frag `isInfixOf` T.unpack e) (const False)
