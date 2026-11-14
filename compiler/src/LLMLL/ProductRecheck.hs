{-# LANGUAGE ScopedTypeVariables #-}
-- | MUL-VAR-1: the native recheck of a product-marked UNSAFE id.
--
-- Design record: @docs/design/mul-var-proposal.md@ (Rev 3a), sections
-- "Verdict and recheck", "What @sat@ is validated against", "The recheck's
-- translator" and "The limit and the budget".
--
-- When liquid-fixpoint answers UNSAFE on a constraint that names a monomial
-- symbol @mul##k@, the answer may rest on the product abstraction. This module
-- asks z3 the same question with @*@ interpreted:
--
-- * the query holds the environment refinements, the @lhs@ WITHOUT the
--   product facts (every other ground-fact family is kept: dropping
--   @byte-range@ gives a false @refuted@), and the negated @rhs@, with each
--   @mul##k@ expanded from the emitter's table ('erMonoTable');
-- * z3 reads it on standard input, under the solver guard, with
--   @(set-option :rlimit 2000000)@ and a 5 s process limit;
-- * on @sat@ it asks @get-value@ for each variable and each application of a
--   free function, reads the values (integers, booleans, arrays as finite maps
--   with a default, @Str@ values as tokens) and evaluates every hypothesis
--   and the goal itself, exactly: Haskell @div@ and @mod@, finite maps, and
--   function consistency (two applications of one function to equal
--   arguments have equal results).
--
-- Only a @sat@ whose model passes that evaluation clears the mark: the id is
-- then a complete id, and the verdict layer reports it as it would any other.
-- Every other answer keeps the mark: @unsat@ (a native @unsat@ never gives
-- @verified@), @unknown@, a stop, a value the reader cannot read, a term the
-- translator cannot translate, a model that fails the evaluation, and no z3.
--
-- 'Feasibility.fqPredToSMT' is not used and not changed: the refine gate
-- keeps its own translator.
module LLMLL.ProductRecheck
  ( -- * Limits
    recheckRlimit
  , recheckSeconds
  , recheckBudget
    -- * Answers
  , RecheckAnswer(..)
  , isValidated
    -- * The query
  , SmtSort(..)
  , Query(..)
  , buildQuery
  , mkQuery
  , queryScript
  , expandMonos
    -- * Running it
  , findZ3
  , recheckQuery
  , recheckProducts
  , recheckProductsWith
  , recheckCandidates
  , Partition(..)
    -- * The callers' step
  , recheckVerdict
  , counterexampleLine
    -- * Reading a model
  , Sexp(..)
  , parseSexps
  , Value(..)
  , readValue
  , readModelDefs
    -- * Evaluating a model
  , Model(..)
  , buildFunTable
  , evalPred
  , validateModel
  ) where

import Control.Exception (SomeException, try)
import Control.Monad (foldM, forM, unless)
import Data.Char (isDigit, isSpace)
import Data.IORef
import Data.List (sortOn, nub)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (findExecutable)
import System.Exit (ExitCode(..))

import LLMLL.FixpointIR
import LLMLL.FixpointEmit (EmitResult(..))
import LLMLL.DiagnosticFQ (FQVerifyResult(..), ConstraintOrigin(..), isWdClause)
import qualified LLMLL.ProductNF as PNF
import LLMLL.SolverGuard (runSolverGuardedInput)
import LLMLL.AbstractionVerdict (AbstractionOutcome(..), applyAbstractionVerdict)
import LLMLL.Diagnostic (Diagnostic(..), mkWarning)

-- ---------------------------------------------------------------------------
-- Limits
-- ---------------------------------------------------------------------------

-- | z3's resource limit for one recheck query (design "The limit").
recheckRlimit :: Int
recheckRlimit = 2000000

-- | The process guard for one recheck query, in seconds.
recheckSeconds :: Int
recheckSeconds = 5

-- | At most this many ids per function per partition (design "The budget").
recheckBudget :: Int
recheckBudget = 8

-- ---------------------------------------------------------------------------
-- Answers
-- ---------------------------------------------------------------------------

data RecheckAnswer
  = RValidated [(Text, Value)]
    -- ^ @sat@, and the model passed the exact evaluation: the id is cleared
  | RSatInvalid Text     -- ^ @sat@, and the model failed the evaluation (z3 is named in a warning)
  | RSatUnreadable Text  -- ^ @sat@, with a value the reader cannot read
  | RUnsat               -- ^ never @verified@
  | RUnknown             -- ^ @unknown@, the rlimit reached
  | RStopped             -- ^ the guard stopped z3
  | RFailed Text         -- ^ z3 failed or printed something else
  | RAbstain Text        -- ^ the translator cannot translate a term
  | RNoSolver            -- ^ z3 is not on PATH
  deriving (Show, Eq)

isValidated :: RecheckAnswer -> Bool
isValidated (RValidated _) = True
isValidated _              = False

-- ---------------------------------------------------------------------------
-- The query
-- ---------------------------------------------------------------------------

data SmtSort = SInt | SBool | SStr | SArr SmtSort SmtSort
  deriving (Show, Eq, Ord)

-- | One recheck query, with every @mul##k@ already expanded.
data Query = Query
  { qVars  :: [(Text, SmtSort)]            -- ^ variables, in name order
  , qFuns  :: [(Text, [SmtSort], SmtSort)] -- ^ free functions (arity 0: a constant)
  , qHyps  :: [FQPred]                     -- ^ every hypothesis
  , qGoal  :: FQPred                       -- ^ the goal, asserted negated
  , qApps  :: [FQPred]                     -- ^ each application of a free function, for get-value
  } deriving (Show, Eq)

smtSortOf :: FQSort -> Maybe SmtSort
smtSortOf = \case
  FQInt      -> Just SInt
  FQBool     -> Just SBool
  FQStr      -> Just SStr
  FQMapArr   -> Just (SArr SInt SInt)
  FQArr k v  -> SArr <$> smtSortOf k <*> smtSortOf v
  _          -> Nothing

renderSort :: SmtSort -> Text
renderSort = \case
  SInt -> "Int"
  SBool -> "Bool"
  SStr -> "Str"
  SArr k v -> "(Array " <> renderSort k <> " " <> renderSort v <> ")"

-- | Replace each @mul##k@ by the product of its atoms, with @*@ written out.
expandMonos :: Map Text PNF.Mono -> FQPred -> FQPred
expandMonos tbl = go
  where
    go p = case p of
      FQVar v | Just m <- Map.lookup v tbl -> PNF.polyPred (const Nothing) (Map.singleton m 1)
      FQBinPred op l r  -> FQBinPred op (go l) (go r)
      FQBinArith op l r -> FQBinArith op (go l) (go r)
      FQAnd ps          -> FQAnd (map go ps)
      FQOr ps           -> FQOr (map go ps)
      FQNot q           -> FQNot (go q)
      FQKVar k as       -> FQKVar k (map go as)
      FQApp f as        -> FQApp f (map go as)
      FQIte c a b       -> FQIte (go c) (go a) (go b)
      FQImplies a b     -> FQImplies (go a) (go b)
      _                 -> p

-- | Substitute a variable, as a binder's own name for its refinement variable.
substVar :: Text -> Text -> FQPred -> FQPred
substVar from to = go
  where
    go p = case p of
      FQVar v | v == from -> FQVar to
      FQBinPred op l r  -> FQBinPred op (go l) (go r)
      FQBinArith op l r -> FQBinArith op (go l) (go r)
      FQAnd ps          -> FQAnd (map go ps)
      FQOr ps           -> FQOr (map go ps)
      FQNot q           -> FQNot (go q)
      FQKVar k as       -> FQKVar k (map go as)
      FQApp f as        -> FQApp f (map go as)
      FQIte c a b       -> FQIte (go c) (go a) (go b)
      FQImplies a b     -> FQImplies (go a) (go b)
      _                 -> p

-- | The recheck query of one constraint, or why the translator abstains.
buildQuery :: EmitResult -> FQConstraintId -> Either Text Query
buildQuery er cid = do
  let file = erFQFile er
  c <- maybe (Left "no such constraint") Right
         (lookup cid [ (conId x, x) | x <- fqConstraints file ])
  tbl  <- maybe (Left "no monomial table") Right (Map.lookup cid (erMonoTable er))
  base <- maybe (Left "no lhs without facts") Right (Map.lookup cid (erProductLhs er))
  let bmap  = Map.fromList [ (bindId b, b) | b <- fqBinds file ]
      envBs = [ b | i <- conEnv c, Just b <- [Map.lookup i bmap]
                  , not (mulSymbolPrefix `T.isPrefixOf` bindName b) ]
      hypOf b = let r = bindReft b
                in if reftVar r == bindName b then reftPred r else substVar (reftVar r) (bindName b) (reftPred r)
      envHyps = [ hypOf b | b <- envBs, reftPred (bindReft b) /= FQTrue ]
      hyps  = map (expandMonos tbl) (envHyps ++ [base])
      goal  = expandMonos tbl (reftPred (conRhs c))
      sortsOfBinds = [ (bindName b, reftSort (bindReft b)) | b <- envBs ]
                  ++ [ (reftVar (conLhs c), reftSort (conLhs c)) ]
                  ++ [ (reftVar (conRhs c), reftSort (conRhs c)) ]
      sortMap = Map.fromListWith (\_ old -> old) sortsOfBinds
      consts  = Map.fromList [ (fqcName k, k) | k <- fqConstants file ]
  mkQuery sortMap consts hyps goal

-- | Assemble a query: declare each variable the predicates name, and each
-- free function they apply, or abstain.
mkQuery :: Map Text FQSort -> Map Text FQConstant -> [FQPred] -> FQPred -> Either Text Query
mkQuery sortMap consts hyps goal = do
  let preds = goal : hyps
      vars  = Set.toAscList (Set.unions (map predVarsOf preds))
      apps  = nub (concatMap appsOf preds)
  vs <- forM vars $ \v -> case Map.lookup v sortMap >>= smtSortOf of
          Just s  -> Right (v, s)
          Nothing -> Left ("no sort for " <> v)
  fs <- forM (nub [ f | FQApp f _ <- apps ]) $ \f -> case Map.lookup f consts of
          Just k | Just as <- mapM smtSortOf (fqcArgs k), Just r <- smtSortOf (fqcRet k) -> Right (f, as, r)
          _ -> Left ("no declaration for " <> f)
  let q = Query vs fs hyps goal apps
  _ <- mapM (translate q) preds
  Right q

-- | The variables a predicate names (not application heads).
predVarsOf :: FQPred -> Set Text
predVarsOf = \case
  FQVar v           -> Set.singleton v
  FQBinPred _ l r   -> predVarsOf l `Set.union` predVarsOf r
  FQBinArith _ l r  -> predVarsOf l `Set.union` predVarsOf r
  FQAnd ps          -> Set.unions (map predVarsOf ps)
  FQOr ps           -> Set.unions (map predVarsOf ps)
  FQNot p           -> predVarsOf p
  FQKVar _ as       -> Set.unions (map predVarsOf as)
  FQApp _ as        -> Set.unions (map predVarsOf as)
  FQIte c a b       -> Set.unions (map predVarsOf [c, a, b])
  FQImplies a b     -> predVarsOf a `Set.union` predVarsOf b
  _                 -> Set.empty

-- | Every application of a free function (not the array theory), innermost
-- first.
appsOf :: FQPred -> [FQPred]
appsOf = \case
  FQBinPred _ l r   -> appsOf l ++ appsOf r
  FQBinArith _ l r  -> appsOf l ++ appsOf r
  FQAnd ps          -> concatMap appsOf ps
  FQOr ps           -> concatMap appsOf ps
  FQNot p           -> appsOf p
  FQKVar _ as       -> concatMap appsOf as
  p@(FQApp f as)
    | f `elem` theoryOps -> concatMap appsOf as
    | otherwise          -> concatMap appsOf as ++ [p]
  FQIte c a b       -> concatMap appsOf [c, a, b]
  FQImplies a b     -> appsOf a ++ appsOf b
  _                 -> []

theoryOps :: [Text]
theoryOps = ["Map_select", "Map_store", "Map_default"]

-- | A predicate as SMT-LIB text, with @*@, @div@ and @mod@ interpreted.
translate :: Query -> FQPred -> Either Text Text
translate q = go
  where
    funs = Map.fromList [ (f, length as) | (f, as, _) <- qFuns q ]
    go p = case p of
      FQTrue  -> Right "true"
      FQFalse -> Right "false"
      FQLit n | n < 0     -> Right ("(- " <> tshow (negate n) <> ")")
              | otherwise -> Right (tshow n)
      FQVar v -> Right (sym v)
      FQBinPred FQNeq l r -> (\a b -> "(not (= " <> a <> " " <> b <> "))") <$> go l <*> go r
      FQBinPred op l r -> do
        o <- relName op
        bin o l r
      FQBinArith FQDiv l (FQLit k) | k > 0 -> bin "div" l (FQLit k)
      FQBinArith FQMod l (FQLit k) | k > 0 -> bin "mod" l (FQLit k)
      FQBinArith FQDiv _ _ -> Left "a divisor that is not a positive literal"
      FQBinArith FQMod _ _ -> Left "a divisor that is not a positive literal"
      FQBinArith op l r -> do
        o <- arithName op
        bin o l r
      FQAnd []  -> Right "true"
      FQAnd ps  -> (\xs -> "(and " <> T.unwords xs <> ")") <$> mapM go ps
      FQOr []   -> Right "false"
      FQOr ps   -> (\xs -> "(or " <> T.unwords xs <> ")") <$> mapM go ps
      FQNot a   -> (\x -> "(not " <> x <> ")") <$> go a
      FQImplies a b -> bin "=>" a b
      FQIte c a b -> (\x y z -> "(ite " <> x <> " " <> y <> " " <> z <> ")") <$> go c <*> go a <*> go b
      FQApp "Map_select" [a, i]    -> bin "select" a i
      FQApp "Map_store" [a, i, v]  -> (\x y z -> "(store " <> x <> " " <> y <> " " <> z <> ")") <$> go a <*> go i <*> go v
      FQApp f []
        | Map.lookup f funs == Just 0 -> Right (sym f)
      FQApp f as
        | Map.lookup f funs == Just (length as) ->
            (\xs -> "(" <> sym f <> " " <> T.unwords xs <> ")") <$> mapM go as
      FQApp f _ -> Left ("cannot translate the application of " <> f)
      FQKVar _ _ -> Left "a kvar"
    bin o l r = (\a b -> "(" <> o <> " " <> a <> " " <> b <> ")") <$> go l <*> go r
    relName = \case
      FQGe -> Right ">="
      FQGt -> Right ">"
      FQLe -> Right "<="
      FQLt -> Right "<"
      FQEq -> Right "="
      op   -> Left ("relation " <> tshow op)
    arithName = \case
      FQAdd -> Right "+"
      FQSub -> Right "-"
      FQMul -> Right "*"
      op    -> Left ("operator " <> tshow op)

sym :: Text -> Text
sym v = "|" <> v <> "|"

tshow :: Show a => a -> Text
tshow = T.pack . show

-- | The z3 script of a query: declarations, the hypotheses, the negated goal,
-- @check-sat@, @get-value@ for each variable and application, @get-model@.
queryScript :: Query -> Either Text Text
queryScript q = do
  hs <- mapM (translate q) (qHyps q)
  g  <- translate q (qGoal q)
  ts <- mapM (translate q) (map (FQVar . fst) (qVars q) ++ qApps q)
  let needStr = any (usesStr . snd) (qVars q)
             || any (\(_, as, r) -> any usesStr (r : as)) (qFuns q)
      usesStr = \case
        SStr -> True
        SArr k v -> usesStr k || usesStr v
        _ -> False
  Right $ T.unlines $
       [ "(set-option :produce-models true)"
       , "(set-option :rlimit " <> tshow recheckRlimit <> ")" ]
    ++ [ "(declare-sort Str 0)" | needStr ]
    ++ [ "(declare-const " <> sym v <> " " <> renderSort s <> ")" | (v, s) <- qVars q ]
    ++ [ if null as then "(declare-const " <> sym f <> " " <> renderSort r <> ")"
         else "(declare-fun " <> sym f <> " (" <> T.unwords (map renderSort as) <> ") " <> renderSort r <> ")"
       | (f, as, r) <- qFuns q ]
    ++ [ "(assert " <> h <> ")" | h <- hs ]
    ++ [ "(assert (not " <> g <> "))"
       , "(check-sat)" ]
    ++ [ "(get-value (" <> T.unwords ts <> "))" | not (null ts) ]
    ++ [ "(get-model)" ]

-- ---------------------------------------------------------------------------
-- Running it
-- ---------------------------------------------------------------------------

findZ3 :: IO (Maybe FilePath)
findZ3 = findExecutable "z3"

-- | Run one query and validate the answer.
recheckQuery :: FilePath -> Query -> IO RecheckAnswer
recheckQuery z3 q = case queryScript q of
  Left why -> pure (RAbstain why)
  Right script -> do
    r <- try (runSolverGuardedInput recheckSeconds z3 ["-in", "-smt2"] (T.unpack script))
    pure $ case r of
      Left (e :: SomeException) -> RFailed (T.pack (show e))
      Right (Left _) -> RStopped
      Right (Right (code, out, err)) -> readAnswer q code (T.pack out) (T.pack err)

readAnswer :: Query -> ExitCode -> Text -> Text -> RecheckAnswer
readAnswer q _code out err =
  case parseSexps out of
    Left why -> RFailed ("unreadable z3 output: " <> why <> T.take 200 err)
    Right (SAtom "sat" : rest) -> case rest of
      (SList pairs : more) -> either RSatUnreadable id $ do
        let defs = readModelDefs more
        vals <- forM pairs $ \case
          SList [_, v] -> readValue defs v
          other -> Left ("a get-value entry " <> renderSexp other)
        let nv = length (qVars q)
            env = Map.fromList (zip (map fst (qVars q)) (take nv vals))
            appVals = zip (qApps q) (drop nv vals)
        unless (length vals == nv + length (qApps q)) $
          Left "get-value returned a different number of values"
        Right $ case validateModel q env appVals of
          Left why -> RSatInvalid why
          Right () -> RValidated (Map.toList env)
      _ -> RSatUnreadable "no get-value output"
    Right (SAtom "unsat" : _) -> RUnsat
    Right (SAtom "unknown" : _) -> RUnknown
    Right _ -> RFailed ("unexpected z3 output: " <> T.take 200 out <> T.take 200 err)

-- | The partitions of a function's failing ids (CLAUSE-WELLDEF-1 §4.4).
data Partition = PTruth | PDefinedness | PMeasure
  deriving (Show, Eq, Ord)

partitionOf :: Text -> Partition
partitionOf c
  | isWdClause c                      = PDefinedness
  | c `elem` ["descent", "decreases"] = PMeasure
  | otherwise                         = PTruth

-- | The ids to recheck, per function and partition, in id order, at most
-- 'recheckBudget' each: a failing id that carries the product mark and no
-- other mark, and has an origin.
recheckCandidates :: EmitResult -> FQVerifyResult -> [((Text, Partition), [FQConstraintId])]
recheckCandidates er = \case
  FQUnsafe ids ->
    Map.toList $ Map.map (take recheckBudget . Set.toAscList) $ Map.fromListWith Set.union
      [ ((coFunction o, partitionOf (coClause o)), Set.singleton i)
      | i <- ids
      , i `Set.member` erProductMarked er
      , not (Map.member i (erAbstracted er))
      , not (Map.member i (erPostUnassumed er))
      , Just o <- [Map.lookup i (erConstraintTable er)] ]
  _ -> []

-- | Recheck the product-marked failing ids of an UNSAFE answer with z3. The
-- set holds each id whose model was validated. With no z3 the set is empty,
-- so every mark stays.
recheckProducts :: Maybe FilePath -> EmitResult -> FQVerifyResult
                -> IO (Set FQConstraintId, [(FQConstraintId, RecheckAnswer)])
recheckProducts Nothing er r =
  pure (Set.empty, [ (i, RNoSolver) | (_, is) <- recheckCandidates er r, i <- is ])
recheckProducts (Just z3) er r = recheckProductsWith run er r
  where
    run i = case buildQuery er i of
      Left why -> pure (RAbstain why)
      Right q  -> recheckQuery z3 q

-- | 'recheckProducts' with the runner given: each partition stops at its
-- first validated id.
recheckProductsWith :: (FQConstraintId -> IO RecheckAnswer) -> EmitResult -> FQVerifyResult
                    -> IO (Set FQConstraintId, [(FQConstraintId, RecheckAnswer)])
recheckProductsWith run er r = do
  log' <- newIORef []
  cleared <- fmap Set.unions $ forM (recheckCandidates er r) $ \(_, is) ->
    let loop [] = pure Set.empty
        loop (i : rest) = do
          a <- run i
          modifyIORef' log' ((i, a) :)
          if isValidated a then pure (Set.singleton i) else loop rest
    in loop is
  answers <- reverse <$> readIORef log'
  pure (cleared, answers)

-- | MUL-VAR-1 ("Four callers"): the step each of @verify@, @patch@, @--cdp@
-- and the diverge classifier runs on a solver answer. It rechecks the
-- product-marked failing ids ('recheckProducts', under the budget) and then
-- applies the verdict rule with the ids whose model was validated. z3 is
-- looked up only when a candidate exists, so an answer with no product mark
-- costs nothing and gives exactly 'applyAbstractionVerdict' with no cleared
-- id. With no z3 every mark stays.
--
-- A @sat@ whose model failed the exact evaluation keeps its mark, and the
-- outcome's emit result gets a warning that names z3 (design "Verdict and
-- recheck").
recheckVerdict :: EmitResult -> FQVerifyResult
               -> IO (AbstractionOutcome, [(FQConstraintId, RecheckAnswer)])
recheckVerdict er r
  | null (recheckCandidates er r) = pure (applyAbstractionVerdict Set.empty er r, [])
  | otherwise = do
      z3 <- findZ3
      (cleared, answers) <- recheckProducts z3 er r
      let ao    = applyAbstractionVerdict cleared er r
          warns = [ (mkWarning Nothing ("W-PRODUCT-RECHECK: z3 returned a model for constraint "
                       <> tshow i <> " that failed the exact evaluation (" <> why
                       <> "); the constraint keeps its product mark."))
                      { diagCode = Just "W-PRODUCT-RECHECK" }
                  | (i, RSatInvalid why) <- answers ]
          em    = aoEmit ao
      pure (ao { aoEmit = em { erDiagnostics = erDiagnostics em ++ warns } }, answers)

-- | MUL-VAR-1 ("Messages", Refuted): the validated model of a rechecked id,
-- in the one form the design allows. Integer and boolean variables only, in
-- name order; an array or a @Str@ token is not printed.
counterexampleLine :: [(Text, Value)] -> Text
counterexampleLine vals =
  "VC counterexample: "
  <> T.unwords [ v <> "=" <> shown | (v, x) <- sortOn fst vals, Just shown <- [scalar x] ]
  <> ". Callee results in it are assumed, not computed."
  where
    scalar (VInt n)  = Just (tshow n)
    scalar (VBool b) = Just (if b then "true" else "false")
    scalar _         = Nothing

-- ---------------------------------------------------------------------------
-- Reading z3's output
-- ---------------------------------------------------------------------------

data Sexp = SAtom Text | SList [Sexp]
  deriving (Show, Eq)

renderSexp :: Sexp -> Text
renderSexp (SAtom a) = a
renderSexp (SList xs) = "(" <> T.unwords (map renderSexp xs) <> ")"

-- | The top-level forms of z3's output. A @;@ comment runs to the end of the
-- line; @|...|@ and @"..."@ are one token.
parseSexps :: Text -> Either Text [Sexp]
parseSexps t0 = go (tokens (T.unpack t0)) []
  where
    go [] acc = Right (reverse acc)
    go ts acc = case one ts of
      Left e -> Left e
      Right (x, rest) -> go rest (x : acc)
    one ("(" : ts) = list ts []
    one (")" : _)  = Left "unbalanced )"
    one (a : ts)   = Right (SAtom (T.pack a), ts)
    one []         = Left "end of input"
    list (")" : ts) acc = Right (SList (reverse acc), ts)
    list [] _ = Left "unbalanced ("
    list ts acc = case one ts of
      Left e -> Left e
      Right (x, rest) -> list rest (x : acc)
    tokens [] = []
    tokens (c : cs)
      | isSpace c = tokens cs
      | c == ';'  = tokens (dropWhile (/= '\n') cs)
      | c == '(' || c == ')' = [c] : tokens cs
      | c == '|'  = let (a, b) = break (== '|') cs in ('|' : a ++ "|") : tokens (drop 1 b)
      | c == '"'  = let (a, b) = strLit cs in ('"' : a) : tokens b
      | otherwise = let (a, b) = break (\x -> isSpace x || x `elem` ("()" :: String)) (c : cs) in a : tokens b
    strLit ('"' : '"' : r) = let (a, b) = strLit r in ('"' : '"' : a, b)
    strLit ('"' : r) = ("\"", r)
    strLit (x : r) = let (a, b) = strLit r in (x : a, b)
    strLit [] = ([], [])

-- | A model value. A map is a default with its exceptions; an exception equal
-- to the default is never stored, so structural equality is map equality.
data Value
  = VInt Integer
  | VBool Bool
  | VTok Text
  | VMap Value (Map Value Value)
  deriving (Show, Eq, Ord)

mkMap :: Value -> Map Value Value -> Value
mkMap d ex = VMap d (Map.filter (/= d) ex)

storeV :: Value -> Value -> Value -> Either Text Value
storeV (VMap d ex) k v = Right (mkMap d (Map.insert k v ex))
storeV _ _ _ = Left "store on a value that is not a map"

-- | The @define-fun@ bodies of a @get-model@ output, by name, for
-- @(_ as-array f)@. Each entry is the parameter name and the body.
readModelDefs :: [Sexp] -> Map Text (Text, Sexp)
readModelDefs forms = Map.fromList (concatMap defs forms)
  where
    defs = \case
      SList (SAtom "model" : xs) -> concatMap defs xs
      SList [SAtom "define-fun", SAtom f, SList [SList [SAtom x, _]], _, body] -> [(unbar f, (x, body))]
      SList xs | all isDefine xs -> concatMap defs xs
      _ -> []
    isDefine (SList (SAtom "define-fun" : _)) = True
    isDefine _ = False

unbar :: Text -> Text
unbar t = case T.stripPrefix "|" t >>= T.stripSuffix "|" of
  Just u -> u
  Nothing -> t

-- | Read one value. Anything else is unreadable, and the id keeps its mark.
readValue :: Map Text (Text, Sexp) -> Sexp -> Either Text Value
readValue defs = go Map.empty
  where
    go env s = case s of
      SAtom a
        | Just v <- Map.lookup a env -> Right v
        | a == "true"  -> Right (VBool True)
        | a == "false" -> Right (VBool False)
        | not (T.null a), T.all isDigit a -> Right (VInt (read (T.unpack a)))
        | "!val!" `T.isInfixOf` a -> Right (VTok (unbar a))
        | otherwise -> Left ("an atom " <> a)
      SList [SAtom "-", SAtom n] | not (T.null n), T.all isDigit n -> Right (VInt (negate (read (T.unpack n))))
      SList [SList [SAtom "as", SAtom "const", _], d] -> (\v -> mkMap v Map.empty) <$> go env d
      SList [SAtom "store", a, i, v] -> do
        m <- go env a
        k <- go env i
        x <- go env v
        storeV m k x
      SList [SAtom "let", SList binds, body] -> do
        env' <- foldM (\e b -> case b of
                         SList [SAtom n, x] -> (\v -> Map.insert n v e) <$> go e x
                         _ -> Left "a let binding") env binds
        go env' body
      SList [SAtom "lambda", SList [SList [SAtom x, _]], body] -> lambdaMap env x body
      SList [SAtom "_", SAtom "as-array", SAtom f] -> case Map.lookup (unbar f) defs of
        Just (x, body) -> lambdaMap env x body
        Nothing -> Left ("no definition of " <> f)
      SList [SAtom "as", x, _] -> go env x
      _ -> Left ("a value " <> renderSexp s)
    -- @(ite (= x k) v rest)@ chains with a final default.
    lambdaMap env x body = do
      (ex, d) <- chain body
      Right (mkMap d (Map.fromList ex))
      where
        chain = \case
          SList [SAtom "ite", SList [SAtom "=", a, b], v, rest]
            | a == SAtom x -> point b v rest
            | b == SAtom x -> point a v rest
          other -> (\d -> ([], d)) <$> go env other
        point k v rest = do
          kv <- go env k
          vv <- go env v
          (ex, d) <- chain rest
          Right ((kv, vv) : ex, d)

-- ---------------------------------------------------------------------------
-- Evaluating a model
-- ---------------------------------------------------------------------------

-- | Variables, and each free function as a finite table.
data Model = Model
  { mVars :: Map Text Value
  , mFuns :: Map (Text, [Value]) Value
  } deriving (Show)

-- | The function table from z3's values for each application. Arguments are
-- evaluated here, innermost application first; two applications with equal
-- arguments and different results fail (function consistency).
buildFunTable :: Map Text Value -> [(FQPred, Value)] -> Either Text (Map (Text, [Value]) Value)
buildFunTable vars apps = foldM add Map.empty (sortOn (depth . fst) apps)
  where
    add tbl (FQApp f as, v) = do
      args <- mapM (evalPred (Model vars tbl)) as
      case Map.lookup (f, args) tbl of
        Just v' | v' /= v -> Left ("function consistency: " <> f)
        _ -> Right (Map.insert (f, args) v tbl)
    add _ (p, _) = Left ("not an application: " <> emitPred p)
    depth = \case
      FQApp _ as -> 1 + maximum (0 : map depth as)
      FQBinArith _ l r -> max (depth l) (depth r)
      FQBinPred _ l r -> max (depth l) (depth r)
      FQIte c a b -> maximum (map depth [c, a, b])
      FQNot p -> depth p
      FQAnd ps -> maximum (0 : map depth ps)
      FQOr ps -> maximum (0 : map depth ps)
      _ -> 0 :: Int

-- | Exact evaluation: integers are unbounded, @/@ and @mod@ are Haskell
-- 'div' and 'mod' by a positive literal, arrays are finite maps.
evalPred :: Model -> FQPred -> Either Text Value
evalPred m = go
  where
    go p = case p of
      FQTrue -> Right (VBool True)
      FQFalse -> Right (VBool False)
      FQLit n -> Right (VInt n)
      FQVar v -> maybe (Left ("no value for " <> v)) Right (Map.lookup v (mVars m))
      FQBinPred op l r -> do
        a <- go l
        b <- go r
        case op of
          FQEq  -> Right (VBool (a == b))
          FQNeq -> Right (VBool (a /= b))
          _ -> do
            x <- int a
            y <- int b
            case op of
              FQLt -> Right (VBool (x < y))
              FQLe -> Right (VBool (x <= y))
              FQGt -> Right (VBool (x > y))
              FQGe -> Right (VBool (x >= y))
              _    -> Left ("relation " <> tshow op)
      FQBinArith op l r -> do
        x <- go l >>= int
        y <- go r >>= int
        case op of
          FQAdd -> Right (VInt (x + y))
          FQSub -> Right (VInt (x - y))
          FQMul -> Right (VInt (x * y))
          FQDiv | y > 0 -> Right (VInt (x `div` y))
          FQMod | y > 0 -> Right (VInt (x `mod` y))
          _ -> Left ("operator " <> tshow op <> " at divisor " <> tshow y)
      FQAnd ps -> VBool . and <$> mapM (\q -> go q >>= bool) ps
      FQOr ps -> VBool . or <$> mapM (\q -> go q >>= bool) ps
      FQNot q -> VBool . not <$> (go q >>= bool)
      FQImplies a b -> do
        x <- go a >>= bool
        if x then go b else Right (VBool True)
      FQIte c a b -> do
        x <- go c >>= bool
        if x then go a else go b
      FQApp "Map_select" [a, i] -> do
        mv <- go a
        k <- go i
        case mv of
          VMap d ex -> Right (Map.findWithDefault d k ex)
          _ -> Left "select on a value that is not a map"
      FQApp "Map_store" [a, i, v] -> do
        mv <- go a
        k <- go i
        x <- go v
        storeV mv k x
      FQApp f as -> do
        args <- mapM go as
        maybe (Left ("no value for an application of " <> f)) Right (Map.lookup (f, args) (mFuns m))
      FQKVar _ _ -> Left "a kvar"
    int (VInt n) = Right n
    int v = Left ("not an integer: " <> tshow v)
    bool (VBool b) = Right b
    bool v = Left ("not a boolean: " <> tshow v)

-- | Every hypothesis must evaluate to true and the goal to false.
validateModel :: Query -> Map Text Value -> [(FQPred, Value)] -> Either Text ()
validateModel q vars apps = do
  tbl <- buildFunTable vars apps
  let m = Model vars tbl
  forM_' (zip [1 :: Int ..] (qHyps q)) $ \(k, h) -> do
    v <- evalPred m h
    unless (v == VBool True) $ Left ("hypothesis " <> tshow k <> " is false in the model")
  g <- evalPred m (qGoal q)
  unless (g == VBool False) $ Left "the goal is true in the model"
  where
    forM_' xs f = mapM_ f xs
