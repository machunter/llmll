{-# LANGUAGE OverloadedStrings #-}

-- | LLMLL.Feasibility — the refine feasibility (no-miracle) gate.
--
-- When @refine@ spawns a new contracted sub-hole
-- @(def G params -> ret (pre …)(post …) ?body)@, this module decides whether the
-- invented sub-contract is FEASIBLE: does every input satisfying @pre@ admit some
-- @result@ satisfying the postcondition (including the return type's refinement
-- @Rret@)? An INFEASIBLE spawn is an unfillable contract — an agent inventing a
-- decomposition that no body can ever discharge — and is rejected.
--
-- Feasibility holds iff
--
-- >   ∀input. pre(input) ⇒ ∃result. (Rret(result) ∧ post(input,result))
--
-- The gate REJECTS iff feasibility FAILS, i.e. iff the following is SAT (inputs are
-- free consts = the ∃input; only @result@ is explicitly quantified):
--
-- >   ∃input. pre(input) ∧ ∀result. ¬(Rret(result) ∧ post(input,result))
--
-- Verdict mapping:
--
--   * @unsat@   → Feasible → ADMIT (fall through to the CDP vacuity gate)
--   * @sat@     → Infeasible → REJECT; the model's input assignment is the witness
--   * @unknown@ / error / timeout → Abstain → ADMIT (fail-open backstop)
--
-- Fail-open discipline: the gate only ever REJECTs on a definitive @sat@. Any
-- rendering failure (out-of-fragment predicate, unsupported sort, non-Int/Bool
-- param or return base type, missing return type), a missing @z3@, or an
-- @unknown@/error result all Abstain — i.e. ADMIT.
--
-- This realizes the Ω-independent semantic-UNSAT check reserved (as future work)
-- by 'LLMLL.CDP.WarnSpecInconsistentOrUnproven': a structurally different
-- existential SAT query, not an extension of CDP's per-candidate Horn-refutation
-- loop.
module LLMLL.Feasibility
  ( FeasVerdict(..)
  , feasibilityOf
  , renderWitness
    -- * Exported for testing
  , fqPredToSMT
  , minimizeWitness
  , parseModel
  , Query(..)
  , buildQuery
  , scriptOf
  ) where

import           Control.Exception (try, IOException)
import           Data.Char (isAlphaNum)
import           Data.Maybe (fromMaybe, maybeToList)
import           Data.Text (Text)
import qualified Data.Text as T
import           System.Exit (ExitCode)
import           System.Process (readProcessWithExitCode)
import           Text.Read (readMaybe)

import           LLMLL.Syntax (Contract(..), Expr(..), Name, Type(..))
import           LLMLL.FixpointIR (FQBinOp(..), FQPred(..))
import           LLMLL.FixpointEmit
                   (AliasMap, exprToPred, renameVar, resolveAliasTy
                   , resolveAllRefinements)

-- ---------------------------------------------------------------------------
-- Verdict
-- ---------------------------------------------------------------------------

-- | The three-way outcome of the feasibility check.
--   The @[(Text,Text)]@ carried by 'Infeasible' is the witnessing input:
--   @(paramName, value)@ pairs (original param names, declaration order).
data FeasVerdict
  = Feasible                    -- ^ unsat → admit
  | Infeasible [(Text, Text)]   -- ^ sat  → reject, with the minimal witnessing input
  | Abstain                     -- ^ unknown / out-of-fragment / no solver → admit
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- FQPred → prefix SMT-LIB
-- ---------------------------------------------------------------------------

-- | Render an 'FQPred' to a prefix (SMT-LIB) term. Mirrors 'LLMLL.FixpointIR.emitPred'
--   but emits prefix syntax for @z3@. Returns 'Nothing' on any constructor outside
--   the decidable Int/Bool QF-LIA fragment ('FQApp' — an uninterpreted-function
--   term such as @strLen@/@Map_select@ — or 'FQKVar'), so the gate abstains rather
--   than mistranslating.
fqPredToSMT :: FQPred -> Maybe Text
fqPredToSMT FQTrue     = Just "true"
fqPredToSMT FQFalse    = Just "false"
fqPredToSMT (FQVar v)  = Just (sanitizeId v)
fqPredToSMT (FQLit n)
  | n < 0              = Just ("(- " <> tshow (abs n) <> ")")
  | otherwise          = Just (tshow n)
-- FQNeq has no primitive in core SMT-LIB Bool; render as ¬(=).
fqPredToSMT (FQBinPred FQNeq l r) = do
  sl <- fqPredToSMT l
  sr <- fqPredToSMT r
  Just ("(not (= " <> sl <> " " <> sr <> "))")
fqPredToSMT (FQBinPred op l r)  = binApp (smtOp op) l r
fqPredToSMT (FQBinArith op l r) = binApp (smtOp op) l r
fqPredToSMT (FQAnd [])   = Just "true"
fqPredToSMT (FQAnd [p])  = fqPredToSMT p
fqPredToSMT (FQAnd ps)   = (\ss -> "(and " <> T.unwords ss <> ")") <$> mapM fqPredToSMT ps
fqPredToSMT (FQOr [])    = Just "false"
fqPredToSMT (FQOr [p])   = fqPredToSMT p
fqPredToSMT (FQOr ps)    = (\ss -> "(or " <> T.unwords ss <> ")") <$> mapM fqPredToSMT ps
fqPredToSMT (FQNot p)    = (\s -> "(not " <> s <> ")") <$> fqPredToSMT p
fqPredToSMT (FQApp _ _)  = Nothing   -- uninterpreted-function term → out of fragment
fqPredToSMT (FQKVar _ _) = Nothing   -- wf constraint variable → out of fragment

binApp :: Text -> FQPred -> FQPred -> Maybe Text
binApp o l r = do
  sl <- fqPredToSMT l
  sr <- fqPredToSMT r
  Just ("(" <> o <> " " <> sl <> " " <> sr <> ")")

-- | Prefix operator symbol. 'FQNeq' is handled specially upstream (¬(=)) and never
--   reaches here.
smtOp :: FQBinOp -> Text
smtOp FQGe  = ">="
smtOp FQGt  = ">"
smtOp FQLe  = "<="
smtOp FQLt  = "<"
smtOp FQEq  = "="
smtOp FQNeq = "distinct"
smtOp FQAdd = "+"
smtOp FQSub = "-"

-- ---------------------------------------------------------------------------
-- Query construction
-- ---------------------------------------------------------------------------

-- | A lowered feasibility query, ready to render to an SMT-LIB script.
data Query = Query
  { qInputs   :: [(Text, Text, Text, Bool)]
    -- ^ per input param: (original name, SMT name, sort text "Int"/"Bool", isInt)
  , qPreSMT   :: Maybe Text    -- ^ the (effective) precondition, or Nothing if absent
  , qRetSort  :: Text          -- ^ the result sort ("Int"/"Bool")
  , qInnerNeg :: Text          -- ^ @(not (and Rret post))@ — the quantifier body
  } deriving (Show, Eq)

-- | Lower a @def@'s (params, return type, contract) into a 'Query', or 'Nothing'
--   (⇒ Abstain) if anything falls outside the decidable Int/Bool fragment.
--
--   The precondition is the /effective/ precondition: @contractPre@ conjoined with
--   any refinement carried by a refinement-typed parameter (α-renamed to the param
--   name, exactly as 'LLMLL.FixpointEmit.paramRefinementPre' assembles it). Omitting
--   a param refinement would weaken @pre@ and risk a spurious REJECT, so it is
--   folded in. The return refinement @Rret@ is extracted the same way and α-renamed
--   to @result@ (cf. 'LLMLL.FixpointEmit.returnRefinementPost').
buildQuery :: AliasMap -> [(Name, Type)] -> Maybe Type -> Contract -> Maybe Query
buildQuery am params mRet contract = do
  ret     <- mRet                       -- no declared return type ⇒ cannot type `result`
  retSort <- baseSortText am ret
  inputs  <- mapM lowerInput params
  -- effective precondition = contractPre ∧ conjoined param refinements
  let paramRefs = [ renameVar x n p | (n, t) <- params, (x, p) <- resolveAllRefinements am t ]
      preExprs  = maybeToList (contractPre contract) ++ paramRefs
  preSMT  <- case preExprs of
               [] -> Just Nothing
               es -> Just <$> lowerE (conjExpr es)
  -- return-type refinement Rret, α-renamed to `result`
  rretSMTs <- mapM lowerE [ renameVar x "result" p | (x, p) <- resolveAllRefinements am ret ]
  -- postcondition
  postSMTs <- case contractPost contract of
                Nothing -> Just []
                Just pe -> (: []) <$> lowerE pe
  let inner    = conjSMT (rretSMTs ++ postSMTs)
      innerNeg = "(not " <> inner <> ")"
  pure Query { qInputs = inputs, qPreSMT = preSMT, qRetSort = retSort, qInnerNeg = innerNeg }
  where
    lowerInput (n, t) = do
      s <- baseSortText am t
      pure (n, sanitizeId n, s, s == "Int")
    conjExpr [e] = e
    conjExpr es  = foldr1 (\a b -> EApp "and" [a, b]) es
    conjSMT []   = "true"
    conjSMT [x]  = x
    conjSMT xs   = "(and " <> T.unwords xs <> ")"

-- | Lower an 'Expr' to an SMT-LIB term via the QF-LIA fragment gate 'exprToPred',
--   then the prefix renderer. 'Nothing' at either step ⇒ out of fragment.
lowerE :: Expr -> Maybe Text
lowerE e = exprToPred e >>= fqPredToSMT

-- | The SMT sort for a base type, or 'Nothing' for anything that is not Int/Bool
--   after alias/refinement resolution (⇒ Abstain).
baseSortText :: AliasMap -> Type -> Maybe Text
baseSortText am t = case resolveAliasTy am t of
  TInt  -> Just "Int"
  TBool -> Just "Bool"
  _     -> Nothing

-- ---------------------------------------------------------------------------
-- Script rendering
-- ---------------------------------------------------------------------------

-- | Render the SMT-LIB script for a query. When @mBound@ is @Just b@, the extra
--   assertion @b@ (the minimization bound) is appended before the check.
scriptOf :: Query -> Maybe Text -> Text
scriptOf q mBound = T.unlines $
     [ "(set-option :timeout 10000)" ]
  ++ [ "(declare-const " <> sn <> " " <> st <> ")" | (_, sn, st, _) <- qInputs q ]
  ++ maybe [] (\p -> [ "(assert " <> p <> ")" ]) (qPreSMT q)
  ++ [ "(assert (forall ((result " <> qRetSort q <> ")) " <> qInnerNeg q <> "))" ]
  ++ maybe [] (\b -> [ "(assert " <> b <> ")" ]) mBound
     -- qsat: z3's complete quantifier-satisfaction tactic for LIA (hand-verified on
     -- the pinned z3 4.15.4 build; plain (check-sat) uses incomplete MBQI).
  ++ [ "(check-sat-using qsat)", "(get-model)" ]

-- ---------------------------------------------------------------------------
-- z3 runner
-- ---------------------------------------------------------------------------

data Z3Out = Z3Sat Text | Z3Unsat | Z3Other

-- | Run a script through @z3 -in@. Fails to 'Z3Other' (⇒ Abstain) on any process
--   error; classifies purely by the first non-blank output line.
runZ3 :: FilePath -> Text -> IO Z3Out
runZ3 z3 script = do
  r <- try (readProcessWithExitCode z3 ["-in"] (T.unpack script))
  pure $ case (r :: Either IOException (ExitCode, String, String)) of
    Left _          -> Z3Other
    Right (_, o, _) -> case dropWhile T.null (map T.strip (T.lines (T.pack o))) of
      ("unsat" : _) -> Z3Unsat
      ("sat"   : _) -> Z3Sat (T.pack o)
      _             -> Z3Other   -- unknown / (error …) / empty

-- ---------------------------------------------------------------------------
-- Model parsing
-- ---------------------------------------------------------------------------

-- | Parse the @(define-fun x () Int 0)@ lines of a z3 model into (name, value)
--   pairs. Handles the value on the same or a following line and the @(- k)@ form
--   for negatives. Sorts are Int/Bool only, so values are @k@, @(- k)@, @true@,
--   @false@.
parseModel :: Text -> [(Text, Text)]
parseModel = go . T.words . T.replace ")" " ) " . T.replace "(" " ( "
  where
    go ("define-fun" : name : "(" : ")" : _sort : rest) =
      let (val, rest') = readVal rest in (name, val) : go rest'
    go (_ : rest) = go rest
    go []         = []
    readVal ("(" : "-" : n : ")" : rest) = ("-" <> n, rest)
    readVal (a : rest)                   = (a, rest)
    readVal []                           = ("", [])

-- ---------------------------------------------------------------------------
-- Minimal-witness search (solve-and-tighten)
-- ---------------------------------------------------------------------------

-- | Given the first satisfying model, tighten toward the smallest witness by
--   cost @c = Σ|inputᵢ|@ over the Int inputs. Loops up to K=8, each round adding
--   @(assert (< Σ|inputᵢ| c))@ and re-solving; stops on the first non-@sat@.
--   Returns the smallest model found. Purpose: name the boundary (@x=0,y=1@),
--   not an arbitrary corner. No Int inputs ⇒ nothing to minimize, return as-is.
minimizeWitness :: FilePath -> Query -> [(Text, Text)] -> IO [(Text, Text)]
minimizeWitness z3 q = loop (0 :: Int)
  where
    intNames = [ sn | (_, sn, _, True) <- qInputs q ]
    sanNames = [ sn | (_, sn, _, _)    <- qInputs q ]
    loop k best
      | k >= 8 || null intNames = pure best
      | otherwise = case boundExpr (costOf best) of
          Nothing -> pure best
          Just b  -> do
            out <- runZ3 z3 (scriptOf q (Just b))
            case out of
              Z3Sat m -> loop (k + 1) (filterInputs sanNames (parseModel m))
              _       -> pure best
    costOf model =
      sum [ abs v | sn <- intNames, Just v <- [lookup sn model >>= (readMaybe . T.unpack)] ]
    boundExpr c
      | null intNames = Nothing
      | otherwise     = Just ("(< " <> sumTerm (map absTerm intNames) <> " " <> tshow c <> ")")
    absTerm n  = "(ite (>= " <> n <> " 0) " <> n <> " (- " <> n <> "))"
    sumTerm [t] = t
    sumTerm ts  = "(+ " <> T.unwords ts <> ")"

filterInputs :: [Text] -> [(Text, Text)] -> [(Text, Text)]
filterInputs names = filter ((`elem` names) . fst)

-- | The witness in original param names, declaration order.
witnessOf :: Query -> [(Text, Text)] -> [(Text, Text)]
witnessOf q model = [ (orig, fromMaybe "?" (lookup sn model)) | (orig, sn, _, _) <- qInputs q ]

-- ---------------------------------------------------------------------------
-- Top-level gate
-- ---------------------------------------------------------------------------

-- | Decide the feasibility of a spawned sub-contract. Fail-open: only a definitive
--   @sat@ yields 'Infeasible'; everything else Admits (Feasible/Abstain).
feasibilityOf :: FilePath -> AliasMap -> [(Name, Type)] -> Maybe Type -> Contract -> IO FeasVerdict
feasibilityOf z3 am params mRet contract =
  case buildQuery am params mRet contract of
    Nothing -> pure Abstain
    Just q  -> do
      out <- runZ3 z3 (scriptOf q Nothing)
      case out of
        Z3Unsat  -> pure Feasible
        Z3Other  -> pure Abstain
        Z3Sat m0 -> do
          let model0 = filterInputs [ sn | (_, sn, _, _) <- qInputs q ] (parseModel m0)
          best <- minimizeWitness z3 q model0
          pure (Infeasible (witnessOf q best))

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Render a witness as @x=0,y=1@ for the rejection message.
renderWitness :: [(Text, Text)] -> Text
renderWitness = T.intercalate "," . map (\(n, v) -> n <> "=" <> v)

-- | Map an LLMLL identifier to an SMT-LIB-legal one (same policy as
--   'LLMLL.FixpointIR.sanitizeFQId'): non-@[A-Za-z0-9_]@ → @_@. Applied to both
--   the @declare-const@ names and 'FQVar' references so they resolve identically.
sanitizeId :: Text -> Text
sanitizeId = T.map (\c -> if isAlphaNum c || c == '_' then c else '_')

tshow :: Show a => a -> Text
tshow = T.pack . show
