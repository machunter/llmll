-- | DIV-VAR-1 step 1b: division and @mod@ by a divisor that is not ground, in
-- the emitter (the clause arm, the body arm, the ANF hoist, the product pass),
-- at each other reader of 'exprToPred', and in the native recheck. The pure
-- normal form and the facts are in "ProductSpec" (step 1a); the witness table
-- through @llmll verify@ is @scripts/tests/test_div_var_1.py@.
module DivSpec (divSpec, divStep2Spec) where

import Test.Hspec

import Control.Monad (forM, forM_)
import Control.Monad.State.Strict (evalState)
import Data.List (isPrefixOf, isSuffixOf, sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (findExecutable, listDirectory)

import LLMLL.Syntax
import LLMLL.Diagnostic (Diagnostic(..))
import LLMLL.Parser (parseTopLevel)
import LLMLL.Feasibility (fqPredToSMT)
import qualified LLMLL.Feasibility as Feas
import LLMLL.FixpointIR
import LLMLL.FixpointEmit
  ( EmitResult(..), EmitOptions(..), FallbackCause(..), BodyVC(..), CallBinder(..)
  , emitFixpointWith, exprToPred, exprToPredWD, WDObl(..), PartialOp(..), partialPre, wdSiteText
  , refusedConstructs, bodyToPredFrom, aNormalizeBody, collectCallBinders, exactDivBuiltins
  , sealedAxiomBuiltins, sigmaAutoPred, measureToPred, extractQualifiers, exprHasVarDiv )
import LLMLL.DiagnosticFQ (FQVerifyResult(..), ConstraintOrigin(..), isWdClause
  , fqResultToReportWD, emptyWdReportCtx, WdReportCtx(..), divisionObligationText)
import LLMLL.Diagnostic (mkBodyFallbackProduct, ProductWhy(..), DiagnosticReport(..), Severity(..))
import LLMLL.HoleAnalysis (isNonLinear, leanWorklistSelects)
import LLMLL.PatchApply (notProvedMessage, PatchedFn(..))
import LLMLL.AbstractionVerdict (AbstractionOutcome(..), applyAbstractionVerdict, divisionConstruct)
import qualified LLMLL.ProductNF as PNF
import qualified LLMLL.ProductFacts as PF
import LLMLL.ProductRecheck

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

emitSrc :: Text -> IO EmitResult
emitSrc src = case parseTopLevel GrammarCoreInversion "<div-var>" src of
  Left err    -> error ("parse failed: " <> show err)
  Right stmts -> emitFixpointWith (EmitOptions True Nothing) "div-var.llmll" stmts

constraintsOf :: EmitResult -> [FQConstraint]
constraintsOf = fqConstraints . erFQFile

tagged :: Text -> EmitResult -> [FQConstraint]
tagged t er = [ c | c <- constraintsOf er, t `elem` conTag c ]

v :: Name -> Expr
v = EVar

i :: Integer -> Expr
i = ELit . LitInt

app :: Name -> [Expr] -> Expr
app = EApp

op :: Name -> [Expr] -> Expr
op = EOp

intSe :: Map.Map Name FQSort
intSe = Map.fromList [ (n, FQInt) | n <- ["x", "y", "d", "w", "c"] ]

-- | Every symbol a constraint names: its environment, lhs and rhs.
predsOf :: EmitResult -> FQConstraint -> [FQPred]
predsOf er c = reftPred (conLhs c) : reftPred (conRhs c)
  : [ reftPred (bindReft b) | k <- conEnv c, Just b <- [Map.lookup k bmap] ]
  where bmap = Map.fromList [ (bindId b, b) | b <- fqBinds (erFQFile er) ]

-- | A division by anything but a positive literal.
rawDivision :: FQPred -> Bool
rawDivision p = case p of
  FQBinArith o _ (FQLit k) | o `elem` [FQDiv, FQMod], k <= 0 -> True
  FQBinArith o a (FQLit _) | o `elem` [FQDiv, FQMod] -> rawDivision a
  FQBinArith o _ _ | o `elem` [FQDiv, FQMod] -> True
  FQBinArith _ a b -> rawDivision a || rawDivision b
  FQBinPred _ a b  -> rawDivision a || rawDivision b
  FQAnd ps         -> any rawDivision ps
  FQOr ps          -> any rawDivision ps
  FQNot q          -> rawDivision q
  FQApp _ as       -> any rawDivision as
  FQKVar _ as      -> any rawDivision as
  FQIte a b e      -> any rawDivision [a, b, e]
  FQImplies a b    -> rawDivision a || rawDivision b
  _                -> False

callVC :: Expr -> Maybe BodyVC
callVC e = case snd (bodyToPredFrom 0 intSe Map.empty Set.empty e) of
  Just vc@CallVC{} -> Just vc
  _                -> Nothing

-- | A bare conjunct in a predicate, spliced.
flatAnd :: FQPred -> [FQPred]
flatAnd (FQAnd ps) = concatMap flatAnd ps
flatAnd p = [p]

rowOfSrc, unguardedSrc, colOfSrc :: Text
rowOfSrc = T.unlines
  [ "(module g (export row-of)"
  , "  (def row-of [w: int c: int h: int i: int] -> int"
  , "    (pre (and (>= w 1) (and (>= c 1) (and (>= h 1) (and (>= i 0) (< i (* (* w h) c)))))))"
  , "    (post (and (= result (/ i (* w c))) (and (>= result 0) (< result h))))"
  , "    (/ i (* w c))))" ]
colOfSrc = T.unlines
  [ "(module g (export col-of)"
  , "  (def col-of [w: int c: int h: int i: int] -> int"
  , "    (pre (and (>= w 1) (and (>= c 1) (and (>= h 1) (and (>= i 0) (< i (* (* w h) c)))))))"
  , "    (post (and (= result (/ (mod i (* w c)) c)) (and (>= result 0) (< result w))))"
  , "    (/ (mod i (* w c)) c)))" ]
unguardedSrc = T.unlines
  [ "(module u (export f)"
  , "  (def f [e: int d: int q: int] -> int (pre (= (/ e d) q)) (post (= result e)) e))" ]

-- | One division with an obligation the solver can decide either way: the
-- @call-pre:/@ id and the @body-post@ id.
negSrc :: Text
negSrc = T.unlines
  [ "(module n (export f)"
  , "  (def f [x: int w: int] -> int (pre (>= w 1)) (post (= result 0)) (/ x (- 0 w))))" ]

ids :: Text -> EmitResult -> [FQConstraintId]
ids t = map conId . tagged t

-- ---------------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------------

divSpec :: Spec
divSpec = describe "DIV-VAR-1 step 1b: the emitter, the gates and the recheck" $ do

  describe "the clause arm" $ do
    it "DV-E-1 a division by a variable gives its term and one obligation, the operands' obligations first" $ do
      exprToPredWD [] (op "/" [v "e", v "d"])
        `shouldBe` Just (FQBinArith FQDiv (FQVar "e") (FQVar "d"), [WDObl [] (FQBinPred FQGe (FQVar "d") (FQLit 1)) (app "/" [v "e", v "d"])])
      exprToPredWD [] (app "mod" [v "e", v "d"])
        `shouldBe` Just (FQBinArith FQMod (FQVar "e") (FQVar "d"), [WDObl [] (partialPre (PDivVar (FQVar "d"))) (app "mod" [v "e", v "d"])])
      fmap (map woGoal . snd) (exprToPredWD [] (op "/" [op "mod" [v "e", v "w"], v "c"]))
        `shouldBe` Just [partialPre (PDivVar (FQVar "w")), partialPre (PDivVar (FQVar "c"))]
      -- the context is the earlier conjuncts
      fmap (map woCtx . snd) (exprToPredWD [] (op "and" [op ">=" [v "d", i 1], op "=" [op "/" [v "e", v "d"], v "q"]]))
        `shouldBe` Just [[FQBinPred FQGe (FQVar "d") (FQLit 1)]]
    it "DV-E-2 a constant divisor adds no obligation; a ground divisor <= 0 and rem, quot refuse with their label" $ do
      exprToPredWD [] (op "/" [v "e", i 3]) `shouldBe` Just (FQBinArith FQDiv (FQVar "e") (FQLit 3), [])
      forM_ [ (op "/" [v "e", i 0], "nonlinear:/"), (op "mod" [v "e", i (-3)], "nonlinear:mod")
            , (op "/" [v "e", op "-" [i 0, i 2]], "nonlinear:/"), (app "mod" [v "e", op "-" [i 2, i 2]], "nonlinear:mod")
            , (op "/" [v "e", op "/" [i 1, i 2]], "nonlinear:/"), (op "rem" [v "e", v "d"], "nonlinear:rem")
            , (app "quot" [v "e", v "d"], "app:quot") ] $ \(e, label) -> do
        exprToPred e `shouldBe` Nothing
        refusedConstructs (op "=" [v "result", e]) `shouldBe` [label]
    it "DV-E-3 the site text names the divisor: (/ e d) needs (>= d 1)" $ do
      fmap (map wdSiteText . snd) (exprToPredWD [] (op "/" [v "e", v "d"])) `shouldBe` Just ["(/ e d) needs (>= d 1)"]
      fmap (map wdSiteText . snd) (exprToPredWD [] (app "mod" [v "e", op "*" [v "w", v "c"]]))
        `shouldBe` Just ["(mod e (* w c)) needs (>= (* w c) 1)"]
    it "DV-E-4 edge case 6: an unguarded division in a pre gives one wd-pre constraint with goal d >= 1" $ do
      er <- emitSrc unguardedSrc
      map (reftPred . conRhs) (tagged "wd-pre" er) `shouldBe` [FQBinPred FQGe (FQVar "d") (FQLit 1)]
      -- the guarded form is a tautology (its goal is in its context), so it is not sent
      er2 <- emitSrc (T.replace "(pre (= (/ e d) q))" "(pre (=> (>= d 1) (= (/ e d) q)))" unguardedSrc)
      tagged "wd-pre" er2 `shouldBe` []
      "f" `elem` erBodyFaithfulFns er2 `shouldBe` True
    it "DV-E-4b a clause `mod` that a function-typed parameter shadows is not the builtin" $ do
      er <- emitSrc $ T.unlines
        [ "(module s (export f)"
        , "  (def-shell f [mod: (fn [int int] -> int) x: int d: int] -> int (pre (>= d 1)) (post (>= (mod x d) 0)) 0))" ]
      lookup "f" (erFallbackConstructs er) `shouldBe` Just ["nonlinear:mod"]
      lookup "f" (erBodyFallbackCauses er) `shouldBe` Just FallbackContractPost

  describe "the body arm" $ do
    it "DV-E-5 a body division is a CallVC with pre d >= 1 and one reflection part" $ do
      forM_ [("/", FQDiv, "call_div"), ("mod", FQMod, "call_mod")] $ \(o, fo, base) ->
        case callVC (op o [v "x", v "d"]) of
          Nothing -> expectationFailure "no CallVC"
          Just vc -> do
            let r = cvResultVar vc
                term = FQBinPred FQEq (FQVar r) (FQBinArith fo (FQVar "x") (FQVar "d"))
            cvCallee vc `shouldBe` o
            cvArgs vc `shouldBe` [FQVar "x", FQVar "d"]
            cvPreObligation vc `shouldBe` Just (partialPre (PDivVar (FQVar "d")))
            cvPostParts vc `shouldBe` [("reflection", term)]
            cvPostAssumption vc `shouldBe` Just term
            cvResultSort vc `shouldBe` FQInt
            (cvCongKey vc, cvPostUnassumed vc, cvPreParts vc) `shouldBe` (Nothing, False, [])
            r `shouldSatisfy` T.isInfixOf base
    it "DV-E-5b a ground divisor <= 0 and a shadowed name have no body arm; a positive one keeps its inline term" $ do
      callVC (op "/" [v "x", i 0]) `shouldBe` Nothing
      snd (bodyToPredFrom 0 intSe Map.empty Set.empty (op "/" [v "x", i 0])) `shouldBe` Nothing
      snd (bodyToPredFrom 0 intSe Map.empty Set.empty (op "/" [v "x", i 2]))
        `shouldBe` Just (SimpleVC [] (FQBinArith FQDiv (FQVar "x") (FQLit 2)))
      er <- emitSrc "(module s (export f) (def-shell f [mod: (fn [int int] -> int) x: int d: int] -> int (pre (>= d 1)) (post (>= result 0)) (mod x d)))"
      lookup "f" (erBodyFallbackCauses er) `shouldBe` Just FallbackBody
      -- a let-bound name
      let letBound = ELet [(PVar "mod", Nothing, ELambda [("a", TInt)] (v "a"))] (app "mod" [v "x", v "d"])
      snd (bodyToPredFrom 0 intSe Map.empty Set.empty letBound) `shouldBe` Nothing
    it "DV-E-6 a division result is not abstractable, and / and mod are not sealed axioms" $ do
      exactDivBuiltins `shouldBe` Set.fromList ["/", "mod"]
      Set.intersection exactDivBuiltins sealedAxiomBuiltins `shouldBe` Set.empty
      fmap (map (\(_, cb) -> (cbCallee cb, cbAbstractable cb)) . collectCallBinders) (callVC (op "/" [v "x", v "d"]))
        `shouldBe` Just [("/", False)]
    it "DV-E-7 two divisions in one constraint carry no abstraction mark" $ do
      er <- emitSrc colOfSrc
      length (tagged "call-pre:/" er ++ tagged "call-pre:mod" er) `shouldBe` 2
      erAbstracted er `shouldBe` Map.empty
      erPostUnassumed er `shouldBe` Map.empty
    it "DV-E-8 the hoist fires per occurrence: in an operand, in a guard, in a tabulate argument; never for a constant divisor" $ do
      let norm e = evalState (aNormalizeBody (Set.fromList ["bytes-tabulate"]) e) 0
          letRhs e = case e of
            ELet [(PVar _, _, r)] b -> r : letRhs b
            _ -> []
          isDiv e = case e of
            EApp o _ -> o `elem` ["/", "mod"]
            EOp o _  -> o `elem` ["/", "mod"]
            _        -> False
      -- both spellings: the parser's EOp `/` and EApp `mod`
      letRhs (norm (op "+" [op "/" [v "x", v "d"], i 1])) `shouldBe` [op "/" [v "x", v "d"]]
      letRhs (norm (op "+" [i 1, app "mod" [v "x", v "d"]])) `shouldBe` [app "mod" [v "x", v "d"]]
      letRhs (norm (EIf (op ">" [op "/" [v "x", v "d"], i 2]) (i 1) (i 0))) `shouldBe` [op "/" [v "x", v "d"]]
      -- nested: the inner one first
      length (filter isDiv (letRhs (norm (op "+" [op "/" [app "mod" [v "x", v "d"], v "c"], i 1])))) `shouldBe` 2
      letRhs (norm (app "bytes-tabulate" [op "/" [v "x", v "d"], v "g"])) `shouldBe` [op "/" [v "x", v "d"]]
      forM_ [ op "+" [op "/" [v "x", i 2], i 1], op "+" [app "mod" [v "x", op "+" [i 1, i 2]], i 1]
            , EIf (op ">" [op "/" [v "x", i 2], i 2]) (i 1) (i 0) ] $ \e -> norm e `shouldBe` e
    it "DV-E-9 a division in a later `and` operand is lowered first, so its obligation is owed on its own path" $ do
      er <- emitSrc $ T.unlines
        [ "(module a (export f)"
        , "  (def f [x: int d: int] -> int (post (>= result 0))"
        , "    (if (and (>= d 1) (> (/ x d) 2)) 1 0)))" ]
      "f" `elem` erBodyFaithfulFns er `shouldBe` True
      map (elem (FQBinPred FQGe (FQVar "d") (FQLit 1)) . flatAnd . reftPred . conLhs) (tagged "call-pre:/" er) `shouldBe` [True]
    it "DV-E-9b (bytes-tabulate (/ n d) g ...) is hoisted and owes d >= 1" $ do
      er <- emitSrc $ T.unlines
        [ "(module t (export f)"
        , "  (def g [k: int i: int] -> int (pre (and (>= i 0) (>= k 0))) (post (= result 7)) 7)"
        , "  (def f [n: int d: int] -> bytes (pre (and (>= n 0) (>= d 1))) (post (= (bytes-length result) (/ n d)))"
        , "    (bytes-tabulate (/ n d) g n)))" ]
      "f" `elem` erBodyFaithfulFns er `shouldBe` True
      length (tagged "call-pre:/" er) `shouldBe` 1
      tagged "call-pre:bytes-tabulate" er `shouldSatisfy` (not . null)

  describe "the product pass" $ do
    it "DV-E-10 golden: a body and clauses with constant divisors print v0.42.0's .fq bytes" $ do
      src <- TIO.readFile "test/fixtures/div_var_1/const.llmll"
      want <- TIO.readFile "test/fixtures/div_var_1/const.fq"
      er <- case parseTopLevel GrammarCoreInversion "const.llmll" src of
        Left e -> error (show e)
        Right stmts -> emitFixpointWith (EmitOptions True Nothing) "const.llmll" stmts
      T.unpack (qualifiersToBraces (erFQText er)) `shouldBe` T.unpack want
    it "DV-E-11 no kept constraint holds a raw division, over the div_var_1 and mul_var_1 witnesses" $ do
      let dv = "../scripts/tests/fixtures/div_var_1/"
          mv = "../scripts/tests/fixtures/mul_var_1/"
          -- one module: the import is replaced by geom's definitions
          inline geom src
            | "(import geom)" `T.isInfixOf` src = T.replace "geom." "" (T.replace "(import geom)" geom src)
            | otherwise = src
          -- the hflip-at mutants hold the same clauses; two stand for them
          pick f = not ("m-hflip-at-" `isPrefixOf` f) || f `elem` ["m-hflip-at-01.llmll", "m-hflip-at-40.llmll"]
      geomSrc <- TIO.readFile (dv <> "geom.llmll")
      let geomDefs = T.dropEnd 2 (T.unlines (drop 4 (T.lines geomSrc)))   -- the defs, without the module's `)`
      dvFiles <- sort . filter (\f -> ".llmll" `isSuffixOf` f && pick f) <$> listDirectory dv
      mvFiles <- sort . filter (".llmll" `isSuffixOf`) <$> listDirectory mv
      length dvFiles `shouldSatisfy` (> 90)
      bad <- forM ([ (dv, f) | f <- dvFiles ] ++ [ (mv, f) | f <- mvFiles ]) $ \(dir, f) -> do
        src <- TIO.readFile (dir <> f)
        er <- emitSrc (inline geomDefs src)
        pure [ (f, conId c) | c <- constraintsOf er, any rawDivision (predsOf er c) ]
      concat bad `shouldBe` []
    it "DV-E-11b each division symbol has a binder at true, a table entry and the product mark; each mul## symbol is printed" $ do
      forM_ [rowOfSrc, colOfSrc, unguardedSrc] $ \src -> do
        er <- emitSrc src
        let bmap = Map.fromList [ (bindId b, b) | b <- fqBinds (erFQFile er) ]
        forM_ (constraintsOf er) $ \c -> do
          let syms = Set.unions (map predSymbols (predsOf er c))
              own s = any (`T.isPrefixOf` s) emitterSymbolPrefixes
              named = Set.fromList [ bindName b | k <- conEnv c, Just b <- [Map.lookup k bmap], own (bindName b) ]
              used = Set.filter own syms
          used `shouldSatisfy` (`Set.isSubsetOf` named)
          -- a monomial only inside a division gets no symbol
          Set.filter ("mul##" `T.isPrefixOf`) named `shouldBe` Set.filter ("mul##" `T.isPrefixOf`) used
          Map.keysSet (Map.findWithDefault Map.empty (conId c) (erMonoTable er)) `shouldBe` named
          (conId c `Set.member` erProductMarked er) `shouldBe` not (Set.null used)
        sum [ 1 :: Int | c <- constraintsOf er, "div##0" `Set.member` Set.unions (map predSymbols (predsOf er c)) ] `shouldSatisfy` (> 0)
    it "DV-E-11c over 32 division pairs the function falls back with nonlinear:/" $ do
      let ps = [ "x" <> T.pack (show n) | n <- [1 .. 33 :: Int] ]
          goal = foldr1 (\a b -> "(+ " <> a <> " " <> b <> ")") [ "(/ " <> p <> " d)" | p <- ps ]
      er <- emitSrc $ T.unlines
        [ "(module o (export f)"
        , "  (def-shell f [d: int " <> T.unwords [ p <> ": int" | p <- ps ] <> "] -> int"
        , "    (pre (>= d 1)) (post (>= " <> goal <> " 0)) 0))" ]
      lookup "f" (erFallbackConstructs er) `shouldBe` Just ["nonlinear:/"]
      [ c | c <- constraintsOf er, "f" `elem` conTag c ] `shouldBe` []
    it "DV-E-11d the ground-fact family is division-facts, beside product-facts; erDivDefs names each divisor" $ do
      er <- emitSrc rowOfSrc
      lookup "row-of" (erGroundFactFamilies er) `shouldSatisfy` maybe False (\fs -> all (`elem` fs) ["product-facts", "division-facts"])
      let wc = FQBinArith FQMul (FQVar "w") (FQVar "c")
      fmap (Set.fromList . Map.elems) (Right (erDivDefs er) :: Either PNF.Refusal (Map.Map FQConstraintId PNF.Poly))
        `shouldBe` Set.fromList . pure <$> PNF.toPoly wc
      [ t | k <- Map.keys (erDivDefs er), Just o <- [Map.lookup k (erConstraintTable er)], let t = coClause o
          , not (isWdClause t || t == "call-pre:/") ] `shouldBe` []
      lin <- emitSrc "(module l (export f) (def f [x: int] -> int (post (= result (/ x 2))) (/ x 2)))"
      concatMap snd (erGroundFactFamilies lin) `shouldNotContain` ["division-facts"]
      erDivDefs lin `shouldBe` Map.empty
    it "DV-E-11e sanitizeFQId keeps div##k and mod##k, and a source div_0 stays apart" $ do
      emitPred (FQVar "div##0") `shouldBe` "div##0"
      emitPred (FQVar "mod##12") `shouldBe` "mod##12"
      predSymbols (FQAnd [FQVar "div##0", FQVar "div_0", FQVar "mod##0", FQVar "mod"])
        `shouldBe` Set.fromList ["div##0", "div_0", "mod##0", "mod"]

  describe "the gates" $ do
    it "DV-E-12 sigmaAutoPred keeps its answer: a variable divisor is outside, a constant one inside" $ do
      sigmaAutoPred (op "=" [v "result", op "/" [v "e", v "d"]]) `shouldBe` Nothing
      sigmaAutoPred (op "=" [v "result", app "mod" [v "e", v "d"]]) `shouldBe` Nothing
      sigmaAutoPred (op "=" [v "result", op "/" [v "e", i 2]]) `shouldSatisfy` (/= Nothing)
      exprHasVarDiv (op "=" [v "result", op "/" [v "e", i 0]]) `shouldBe` False
    it "DV-E-13 measureToPred refuses a variable divisor; a constant one stays" $ do
      measureToPred (op "/" [v "a", v "b"]) `shouldBe` Nothing
      measureToPred (op "+" [app "mod" [v "a", v "b"], i 1]) `shouldBe` Nothing
      measureToPred (op "/" [v "a", i 2]) `shouldSatisfy` (/= Nothing)
      er <- emitSrc $ T.unlines
        [ "(module m (export f)"
        , "  (def-shell f [a: int b: int] -> int (pre (and (>= a 0) (>= b 1))) (post (>= result 0))"
        , "    (decreases (/ a b)) (if (= a 0) 0 (f (- a 1) b))))" ]
      tagged "decreases" er `shouldBe` []
      tagged "descent" er `shouldBe` []
    it "DV-E-14 the refine feasibility gate abstains on a variable divisor and not on a constant one" $ do
      let q post = Feas.buildQuery Map.empty [("x", TInt), ("d", TInt)] (Just TInt)
                     (Contract Nothing Nothing (Just post) Nothing Nothing [] [])
      q (op "=" [v "result", op "/" [v "x", v "d"]]) `shouldBe` Nothing
      q (op "=" [v "result", op "/" [v "x", i 2]]) `shouldSatisfy` (/= Nothing)
      -- the renderer itself is unchanged
      fqPredToSMT (FQBinArith FQDiv (FQVar "x") (FQLit 8)) `shouldBe` Just "(div x 8)"
    it "DV-E-15 a clause with a variable divisor gives no qualifier" $ do
      let sorts = Map.fromList [ (n, FQInt) | n <- ["result", "x", "d"] ]
      extractQualifiers sorts "post" "f" (op ">=" [v "result", op "/" [v "x", v "d"]]) `shouldBe` []
      extractQualifiers sorts "post" "f" (op ">=" [v "result", v "x"]) `shouldSatisfy` (not . null)
    it "DV-E-16 firstVarDivision: the emitter's test, in pre-order, both spellings" $ do
      firstVarDivision (op "+" [op "/" [v "x", v "d"], app "mod" [v "x", v "y"]]) `shouldBe` Just (op "/" [v "x", v "d"])
      firstVarDivision (EIf (op ">" [app "mod" [v "x", v "d"], i 0]) (i 1) (i 0)) `shouldBe` Just (app "mod" [v "x", v "d"])
      firstVarDivision (op "+" [op "/" [v "x", op "+" [i 1, i 2]], op "/" [v "x", i 0]]) `shouldBe` Nothing
      firstVarDivision (op "rem" [v "x", v "d"]) `shouldBe` Nothing

  describe "the recheck" $ do
    it "DV-R-1 the query prints (div e d) and (mod e d), with the symbols expanded and no division binder" $ do
      er <- emitSrc colOfSrc
      let c = head (tagged "body-post" er)
      case buildQuery er (conId c) of
        Left why -> expectationFailure (T.unpack why)
        Right q -> do
          map fst (qVars q) `shouldSatisfy` all (\s -> not (any (`T.isPrefixOf` s) emitterSymbolPrefixes))
          case queryScript q of
            Left why -> expectationFailure (T.unpack why)
            Right s -> do
              T.unpack s `shouldContain` "(div "
              T.unpack s `shouldContain` "(mod |i| (* |c| |w|))"
              T.unpack s `shouldNotContain` "##"
    it "DV-R-2 evalPred is Haskell div and mod at every divisor but 0; 0 is not a value" $ do
      let m = Model (Map.fromList [("x", VInt (-7)), ("d", VInt (-2)), ("z", VInt 0)]) Map.empty
          ev o d = evalPred m (FQBinArith o (FQVar "x") (FQVar d))
      ev FQDiv "d" `shouldBe` Right (VInt 3)      -- SMT-LIB: 4
      ev FQMod "d" `shouldBe` Right (VInt (-1))   -- SMT-LIB: 1
      evalPred m (FQBinArith FQDiv (FQVar "x") (FQLit 2)) `shouldBe` Right (VInt (-4))
      ev FQDiv "z" `shouldBe` Left "division by zero"
      ev FQMod "z" `shouldBe` Left "division by zero"
    it "DV-R-2b a model that divides by zero is unreadable; a model only SMT-LIB's div satisfies is invalid" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just z3 -> do
          let sorts = Map.fromList [ (n, FQInt) | n <- ["x", "d"] ]
              run hyps goal = either (pure . RAbstain) (recheckQuery z3) (mkQuery sorts Map.empty hyps goal)
              eq a k = FQBinPred FQEq a (FQLit k)
              dv = FQBinArith FQDiv (FQVar "x") (FQVar "d")
          a0 <- run [eq (FQVar "d") 0] (FQBinPred FQNeq dv (FQLit 5))
          a0 `shouldBe` RSatUnreadable "division by zero"
          -- SMT-LIB gives (div -7 -2) = 4, Haskell 3
          a1 <- run [eq (FQVar "x") (-7), eq (FQVar "d") (-2)] (FQBinPred FQNeq dv (FQLit 4))
          case a1 of
            RSatInvalid _ -> pure ()
            other -> expectationFailure (show other)
          -- d = -1, where both agree: a validated counterexample
          a2 <- run [eq (FQVar "d") (-1), eq (FQVar "x") 3] (FQBinPred FQGe dv (FQLit 0))
          a2 `shouldSatisfy` isValidated
    it "DV-R-3 d >= 1 is asserted only for a divisor whose definedness id the solver did not refute" $ do
      er <- emitSrc rowOfSrc
      let post = conId (head (tagged "body-post" er))
          defs = Map.keys (erDivDefs er)
          hypsWith r = fmap qHyps (buildQueryWith (provedDivisors er r "row-of") er post)
          dHyps r = length <$> hypsWith r
      Right base <- pure (length . qHyps <$> buildQuery er post)
      defs `shouldSatisfy` (not . null)
      -- proved: the divisor is in the query
      dHyps (FQUnsafe [post]) `shouldBe` Right (base + 1)
      -- every definedness id refuted: not assumed
      dHyps (FQUnsafe (post : defs)) `shouldBe` Right base
      -- another function's divisors do not count
      provedDivisors er (FQUnsafe [post]) "other" `shouldBe` Set.empty
    it "DV-R-4 a division-only constraint carries the product mark, and no raw product" $ do
      er <- emitSrc "(module d (export f) (def f [x: int d: int] -> int (pre (>= d 1)) (post (>= result 0)) (/ x d)))"
      let posts = tagged "body-post" er
      posts `shouldSatisfy` (not . null)
      forM_ posts $ \c -> do
        conId c `Set.member` erProductMarked er `shouldBe` True
        any (PF.hasProduct . reftPred) [conLhs c, conRhs c] `shouldBe` False
    it "DV-R-5 the construct of an uncleared division id is abstraction:nonlinear:/, and a cleared one is refuted" $ do
      er <- emitSrc "(module d (export f) (def f [x: int d: int] -> int (pre (>= d 1)) (post (>= result 0)) (/ x d)))"
      let cs = ids "body-post" er
          av = applyAbstractionVerdict Set.empty er (FQUnsafe cs)
          rf = applyAbstractionVerdict (Set.fromList cs) er (FQUnsafe cs)
      divisionConstruct `shouldBe` "abstraction:nonlinear:/"
      lookup "f" (erFallbackConstructs (aoEmit av)) `shouldBe` Just [divisionConstruct]
      aoResult av `shouldBe` FQSafe
      aoAbstractionConstructs av `shouldBe` [("f", divisionConstruct)]
      aoRefuted rf `shouldBe` Set.fromList ["f"]
      -- a product with no division keeps its construct
      er2 <- emitSrc "(module p (export f) (def f [x: int y: int] -> int (post (>= result 0)) (* x y)))"
      let av2 = applyAbstractionVerdict Set.empty er2 (FQUnsafe (ids "body-post" er2))
      lookup "f" (erFallbackConstructs (aoEmit av2)) `shouldBe` Just ["abstraction:nonlinear:*"]
    it "DV-R-6 recheckVerdict: a negative divisor is refuted through call-pre:/ (d >= 1 is not assumed there)" $ do
      mz3 <- findExecutable "z3"
      case mz3 of
        Nothing -> pendingWith "z3 not installed"
        Just _ -> do
          er <- emitSrc negSrc
          let unsafe = ids "call-pre:/" er ++ ids "body-post" er
          (av, answers) <- recheckVerdict er (FQUnsafe unsafe)
          aoRefuted av `shouldBe` Set.fromList ["f"]
          length answers `shouldSatisfy` (> 0)
          [ diagMessage d | d <- erDiagnostics (aoEmit av), diagCode d == Just "W-BODY-FALLBACK" ] `shouldBe` []

-- ---------------------------------------------------------------------------
-- Step 2: messages, holes, other callers
-- ---------------------------------------------------------------------------

divStep2Spec :: Spec
divStep2Spec = describe "DIV-VAR-1 step 2: messages, holes and other callers" $ do
  let origin cl = ConstraintOrigin "f" cl "/statements/1/body" "t.llmll" Nothing
      table = Map.fromList [ (5, origin "call-pre:/"), (6, origin "call-pre:mod"), (7, origin "call-pre:g") ]
      report ctx is = reportDiagnostics (fqResultToReportWD "t.llmll" table ctx (FQUnsafe is))
  it "DV-M-1 a refuted d >= 1 names the divisor's operator; another call-pre keeps its text" $ do
    divisionObligationText "f" "call-pre:/" `shouldBe` Just "the divisor of '/' in 'f' is not proved to be at least 1 (call-pre:/)"
    divisionObligationText "f" "call-pre:mod" `shouldBe` Just "the divisor of 'mod' in 'f' is not proved to be at least 1 (call-pre:mod)"
    divisionObligationText "f" "call-pre:g" `shouldBe` Nothing
    divisionObligationText "f" "call-pre:bytes-tabulate" `shouldBe` Nothing
    let ds = report emptyWdReportCtx [5, 6, 7]
    map diagMessage ds `shouldBe`
      [ "the divisor of '/' in 'f' is not proved to be at least 1 (call-pre:/) (constraint #5)"
      , "the divisor of 'mod' in 'f' is not proved to be at least 1 (call-pre:mod) (constraint #6)"
      , "call-site precondition of 'g' not satisfied in 'f' \x2014 caller does not prove callee's precondition (constraint #7)" ]
    map diagKind ds `shouldBe` replicate 3 (Just "lh-unsafe")
    map diagSeverity ds `shouldBe` replicate 3 SevError
    map diagPointer ds `shouldBe` replicate 3 (Just "/statements/1/body")
  it "DV-M-2 a marked d >= 1 is lh-may-fail and names the divisor's operator" $ do
    let ctx = emptyWdReportCtx { wrMarkedIds = Set.fromList [5, 6]
                               , wrMarkCause = Map.fromList [(5, divisionConstruct), (6, divisionConstruct)] }
        ds  = report ctx [5, 6]
    map diagMessage ds `shouldBe`
      [ "the divisor of '/' in 'f' is not proved to be at least 1 (call-pre:/): the counterexample uses a value the verifier knows only in part (abstraction:nonlinear:/), so no run may reach it (constraint #5)"
      , "the divisor of 'mod' in 'f' is not proved to be at least 1 (call-pre:mod): the counterexample uses a value the verifier knows only in part (abstraction:nonlinear:/), so no run may reach it (constraint #6)" ]
    map diagKind ds `shouldBe` replicate 2 (Just "lh-may-fail")
    map diagSeverity ds `shouldBe` replicate 2 SevWarning
  it "DV-M-3 the W-BODY-FALLBACK text names a division for a division construct, and a product otherwise" $ do
    let first c w = head (T.lines (diagMessage (mkBodyFallbackProduct "f" c (Just "/statements/1/post") w)))
    first "abstraction:nonlinear:/" ProductNotProved `shouldBe` "W-BODY-FALLBACK f: the post is not proved. A division is in the failing constraint."
    first "nonlinear:/" ProductOverLimit `shouldBe` "W-BODY-FALLBACK f: the post is not proved. A division is in the failing constraint."
    first "nonlinear:mod" ProductOverLimit `shouldBe` "W-BODY-FALLBACK f: the post is not proved. A division is in the failing constraint."
    first "abstraction:nonlinear:*" ProductNotProved `shouldBe` "W-BODY-FALLBACK f: the post is not proved. A product is in the failing constraint."
    first "nonlinear:*" ProductOverLimit `shouldBe` "W-BODY-FALLBACK f: the post is not proved. A product is in the failing constraint."
    let third c w = T.lines (diagMessage (mkBodyFallbackProduct "f" c (Just "/statements/1/post") w)) !! 2
    forM_ ["abstraction:nonlinear:/", "nonlinear:/", "nonlinear:mod"] $ \c -> do
      third c ProductNotProved `shouldBe` "  Division facts did not prove it. Native z3 found no counterexample."
      third c ProductOverLimit `shouldBe` "  This constraint is over the limit for divisions after its equations are applied."
    forM_ ["abstraction:nonlinear:*", "nonlinear:*"] $ \c -> do
      third c ProductNotProved `shouldBe` "  Product facts did not prove it. Native z3 found no counterexample."
      third c ProductOverLimit `shouldBe` "  This constraint is over the limit for products after its equations are applied."
    -- the pair limit counts product pairs, whatever the construct
    third "abstraction:nonlinear:/" (ProductPairLimit 70 64) `shouldBe` third "abstraction:nonlinear:*" (ProductPairLimit 70 64)
    -- through the verdict rule: an uncleared division id
    er <- emitSrc "(module d (export f) (def f [x: int d: int] -> int (pre (>= d 1)) (post (>= result 0)) (/ x d)))"
    let av = applyAbstractionVerdict Set.empty er (FQUnsafe (ids "body-post" er))
        ws = [ diagMessage d | d <- erDiagnostics (aoEmit av), diagCode d == Just "W-BODY-FALLBACK" ]
    map (take 3 . T.lines) ws `shouldBe`
      [[ "W-BODY-FALLBACK f: the post is not proved. A division is in the failing constraint."
       , "  Refused by: abstraction:nonlinear:/   at /statements/1/body"
       , "  Division facts did not prove it. Native z3 found no counterexample." ]]
    any (T.isInfixOf "Refused by: abstraction:nonlinear:/") ws `shouldBe` True
  it "DV-M-4 isNonLinear: a variable divisor is not flagged; a ground divisor <= 0 and rem are" $ do
    isNonLinear (op "/" [v "x", v "y"]) `shouldBe` False
    isNonLinear (op "mod" [v "x", v "y"]) `shouldBe` False
    isNonLinear (app "mod" [v "x", op "*" [v "w", v "c"]]) `shouldBe` False
    isNonLinear (op "*" [v "x", op "/" [v "a", v "b"]]) `shouldBe` False
    isNonLinear (op "/" [v "x", i 0]) `shouldBe` True
    isNonLinear (op "mod" [v "x", op "-" [i 2, i 2]]) `shouldBe` True
    isNonLinear (op "/" [op "/" [v "x", i 0], v "d"]) `shouldBe` True   -- its operands are still scanned
    isNonLinear (op "rem" [v "x", v "y"]) `shouldBe` True
    isNonLinear (op "/" [v "x", i 8]) `shouldBe` False
  it "DV-M-5 leanWorklistSelects takes abstraction:nonlinear:/ and nonlinear:/, and no longer a variable divisor by syntax" $ do
    let lin = op "+" [v "x", v "y"]
    leanWorklistSelects ["abstraction:nonlinear:/"] lin `shouldBe` True
    leanWorklistSelects ["nonlinear:/"] lin `shouldBe` True
    leanWorklistSelects [] (op "/" [v "x", v "y"]) `shouldBe` False
    leanWorklistSelects [] (op "/" [v "x", i 0]) `shouldBe` True
    leanWorklistSelects ["abstraction:app:g"] (op "/" [v "x", v "y"]) `shouldBe` False
  it "DV-M-6 the patch notProved message of a division names no callee" $ do
    notProvedMessage (PatchedFn "f" False (Just "abstraction-unsafe") [divisionConstruct])
      `shouldBe` "'f' was not proved: a division is in the failing constraint, and native z3 found no counterexample (abstraction:nonlinear:/). Its postcondition was assumed."
    notProvedMessage (PatchedFn "f" False (Just "abstraction-unsafe") ["abstraction:nonlinear:*"])
      `shouldBe` "'f' was not proved: a product is in the failing constraint, and native z3 found no counterexample (abstraction:nonlinear:*). Its postcondition was assumed."
