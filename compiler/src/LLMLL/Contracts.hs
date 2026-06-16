-- |
-- Module      : LLMLL.Contracts
-- Description : Runtime contract instrumentation for LLMLL def-logic functions.
--
-- Transforms the AST so that `pre` and `post` conditions become
-- runtime assertions. In v0.1, this produces instrumented ASTs where:
--   * Pre-conditions are checked before the function body runs
--   * Post-conditions are checked after the body evaluates with `result` bound
--
-- The instrumented code can be used directly by the interpreter (future)
-- or emitted into the generated Rust (Agent D's scope).
module LLMLL.Contracts
  ( -- * AST Instrumentation
    instrumentContracts
  , instrumentStatement

    -- * Contract Modes (v0.3)
  , ContractsMode(..)
  , applyContractsMode

    -- * Contract Checking Helpers
  , ContractViolation(..)
  , evalContract
  , ContractResult(..)

    -- * Symbolic Evaluator (used by PBT)
  , evalExprStatic
  , evalExprStaticWith
  , FuncEnv
  , buildFuncEnv
  , maxFuel
  , evalOp

    -- * Module-Level Analysis
  , analyzeContracts
  , ContractReport(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Control.Monad (foldM, zipWithM)

import LLMLL.Syntax

-- ---------------------------------------------------------------------------
-- Contract Violation Type
-- ---------------------------------------------------------------------------

-- | A contract violation detected at compile time or runtime.
data ContractViolation = ContractViolation
  { cvFunctionName :: Name
  , cvKind         :: ContractKind
  , cvMessage      :: Text
  } deriving (Show, Eq)

data ContractKind
  = PreViolation   -- ^ precondition not satisfied
  | PostViolation  -- ^ postcondition not satisfied
  deriving (Show, Eq)

data ContractResult
  = Satisfied
  | Violated ContractViolation
  | ContractUnchecked  -- ^ No contract defined
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Contract Report
-- ---------------------------------------------------------------------------

-- | Summary of contracts found in a program.
data ContractReport = ContractReport
  { crFunctionsWithContracts    :: Int
  , crFunctionsWithPre          :: Int
  , crFunctionsWithPost         :: Int
  , crFunctionsWithBoth         :: Int
  , crFunctionsWithoutContracts :: Int
  , crContractDetails           :: [(Name, Contract)]
  } deriving (Show, Eq)

-- | Analyze all contracts in a list of statements.
analyzeContracts :: [Statement] -> ContractReport
analyzeContracts stmts =
  let contractDefs = mapMaybe extractContract stmts
      hasPre  = length [() | (_, c) <- contractDefs, contractPre  c /= Nothing]
      hasPost = length [() | (_, c) <- contractDefs, contractPost c /= Nothing]
      hasBoth = length [() | (_, c) <- contractDefs,
                              contractPre c /= Nothing, contractPost c /= Nothing]
      totalFns = length [() | SDefLogic{}     <- stmts]
                + length [() | SDef{}          <- stmts]
                + length [() | SDefShell{}     <- stmts]
                + length [() | SDefInvariant{} <- stmts]
  in ContractReport
    { crFunctionsWithContracts    = length contractDefs
    , crFunctionsWithPre          = hasPre
    , crFunctionsWithPost         = hasPost
    , crFunctionsWithBoth         = hasBoth
    , crFunctionsWithoutContracts = totalFns - length contractDefs
    , crContractDetails           = contractDefs
    }
  where
    extractContract (SDefLogic name _ _ contract _)
      | contractPre contract /= Nothing || contractPost contract /= Nothing
      = Just (name, contract)
    -- LT-INV (v0.11)
    extractContract (SDef      name _ _ contract _)
      | contractPre contract /= Nothing || contractPost contract /= Nothing
      = Just (name, contract)
    extractContract (SDefShell name _ _ contract _)
      | contractPre contract /= Nothing || contractPost contract /= Nothing
      = Just (name, contract)
    extractContract _ = Nothing

-- ---------------------------------------------------------------------------
-- AST Instrumentation
-- ---------------------------------------------------------------------------

-- | Instrument all def-logic functions with runtime contract checks.
--
-- For a function:
--   (def-logic f [x: int y: int]
--     (pre (>= x 0))
--     (post (>= result 0))
--     body)
--
-- Generates instrumented AST equivalent to:
--   (def-logic f [x: int y: int]
--     (let [_pre_ok (assert-pre f (>= x 0))]
--       (let [result body]
--         (let [_post_ok (assert-post f (>= result 0))]
--           result))))
-- ---------------------------------------------------------------------------
-- Contract Modes (v0.3 Stratified Verification)
-- ---------------------------------------------------------------------------

-- | Controls which runtime assertions survive into generated Haskell.
data ContractsMode
  = ContractsFull      -- ^ All contracts remain as runtime assertions
  | ContractsUnproven  -- ^ Strip assertions for verified contracts only
  | ContractsNone      -- ^ Strip all runtime assertions
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- AST Instrumentation
-- ---------------------------------------------------------------------------

-- | Instrument all def-logic/letrec functions with runtime contract checks.
instrumentContracts :: ContractsMode -> Map Name ContractStatus -> [Statement] -> [Statement]
instrumentContracts mode statusMap = map go
  where
    go stmt = instrumentStatement mode (lookupStatus stmt) stmt
    lookupStatus (SDefLogic n _ _ _ _) = Map.findWithDefault defaultCS n statusMap
    lookupStatus (SLetrec n _ _ _ _ _) = Map.findWithDefault defaultCS n statusMap
    -- LT-INV (v0.11)
    lookupStatus (SDef      n _ _ _ _) = Map.findWithDefault defaultCS n statusMap
    lookupStatus (SDefShell n _ _ _ _) = Map.findWithDefault defaultCS n statusMap
    lookupStatus _                     = defaultCS
    defaultCS = ContractStatus Nothing Nothing []

-- | Instrument a single statement.
instrumentStatement :: ContractsMode -> ContractStatus -> Statement -> Statement
-- None: strip everything
instrumentStatement ContractsNone _ stmt = stmt
-- Full: instrument all contracts (SDefLogic)
instrumentStatement ContractsFull _ (SDefLogic name params mRet contract body) =
  let newBody = wrapWithContracts name contract body
  in SDefLogic name params mRet noContract newBody
-- Full: instrument all contracts (SLetrec)
instrumentStatement ContractsFull _ (SLetrec name params mRet contract dec body) =
  let newBody = wrapWithContracts name contract body
  in SLetrec name params mRet noContract dec newBody
-- LT-INV (v0.11): Full instrumentation for SDef and SDefShell.
instrumentStatement ContractsFull _ (SDef name params mRet contract body) =
  let newBody = wrapWithContracts name contract body
  in SDef name params mRet noContract newBody
instrumentStatement ContractsFull _ (SDefShell name params mRet contract body) =
  let newBody = wrapWithContracts name contract body
  in SDefShell name params mRet noContract newBody
-- Unproven: strip proven contracts, keep unproven (SDefLogic)
instrumentStatement ContractsUnproven cs (SDefLogic name params mRet contract body) =
  let stripped = filterContracts cs contract
      newBody  = wrapWithContracts name stripped body
  in SDefLogic name params mRet noContract newBody
-- Unproven: strip proven contracts, keep unproven (SLetrec)
instrumentStatement ContractsUnproven cs (SLetrec name params mRet contract dec body) =
  let stripped = filterContracts cs contract
      newBody  = wrapWithContracts name stripped body
  in SLetrec name params mRet noContract dec newBody
-- LT-INV (v0.11): Unproven instrumentation for SDef and SDefShell.
instrumentStatement ContractsUnproven cs (SDef name params mRet contract body) =
  let stripped = filterContracts cs contract
      newBody  = wrapWithContracts name stripped body
  in SDef name params mRet noContract newBody
instrumentStatement ContractsUnproven cs (SDefShell name params mRet contract body) =
  let stripped = filterContracts cs contract
      newBody  = wrapWithContracts name stripped body
  in SDefShell name params mRet noContract newBody
-- Everything else: pass through
instrumentStatement _ _ stmt = stmt

-- | Strip proven contract clauses, keep unproven ones.
-- v0.8.1b: Only strip if the evidence record is verified AND body-faithful.
filterContracts :: ContractStatus -> Contract -> Contract
filterContracts cs contract = Contract
  { contractPre = case csPre cs of
      -- v0.8.0: preconditions are never stripped — body VCs prove post, not pre.
      -- A future BODY-VC extension may encode precondition checks into the body,
      -- but for now all proven preconditions remain as runtime assertions.
      _                 -> contractPre contract
  , contractPreSource = contractPreSource contract
  , contractPost = case csPost cs of
      -- v0.8.1b: strip postcondition only when verified AND body-faithful
      Just er | isVerifiedLevel (erDisplayLevel er) && erBodyFaithful er -> Nothing
      _                 -> contractPost contract
  , contractPostSource = contractPostSource contract
  , contractSpecEntropy = contractSpecEntropy contract
  }

-- | v0.8.1b: Body-faithfulness is tracked via EvidenceRecord.erBodyFaithful
-- on ContractStatus.csPost. Stripping requires isVerifiedLevel && erBodyFaithful.

-- | Empty contract — contracts moved into body as assertions.
noContract :: Contract
noContract = Contract Nothing Nothing Nothing Nothing Nothing

-- | Pre-process statements for codegen: strip contract clauses based on mode.
-- Full: keep all contracts (codegen emits them as runtime assertions).
-- None: clear all contracts (no runtime assertions emitted).
-- Unproven: clear proven contracts, keep unproven ones.
applyContractsMode :: ContractsMode -> Map Name ContractStatus -> [Statement] -> [Statement]
applyContractsMode ContractsFull _ stmts = stmts  -- all contracts survive
applyContractsMode ContractsNone _ stmts = map clearContracts stmts
applyContractsMode ContractsUnproven statusMap stmts = map stripProven stmts
  where
    stripProven (SDefLogic n p r c b) =
      let cs = Map.findWithDefault (ContractStatus Nothing Nothing []) n statusMap
      in SDefLogic n p r (filterContracts cs c) b
    stripProven (SLetrec n p r c d b) =
      let cs = Map.findWithDefault (ContractStatus Nothing Nothing []) n statusMap
      in SLetrec n p r (filterContracts cs c) d b
    -- LT-INV (v0.11)
    stripProven (SDef      n p r c b) =
      let cs = Map.findWithDefault (ContractStatus Nothing Nothing []) n statusMap
      in SDef n p r (filterContracts cs c) b
    stripProven (SDefShell n p r c b) =
      let cs = Map.findWithDefault (ContractStatus Nothing Nothing []) n statusMap
      in SDefShell n p r (filterContracts cs c) b
    stripProven s = s

-- | Clear all contract clauses from a statement.
clearContracts :: Statement -> Statement
clearContracts (SDefLogic n p r _ b) = SDefLogic n p r noContract b
clearContracts (SLetrec n p r _ d b) = SLetrec n p r noContract d b
-- LT-INV (v0.11)
clearContracts (SDef      n p r _ b) = SDef n p r noContract b
clearContracts (SDefShell n p r _ b) = SDefShell n p r noContract b
clearContracts s = s

-- | Wrap a function body with pre/post contract assertions.
wrapWithContracts :: Name -> Contract -> Expr -> Expr
wrapWithContracts funcName contract body =
  let withPre  = wrapPre  funcName (contractPre  contract) body
      withPost = wrapPost funcName (contractPost contract) withPre
  in withPost

-- | Wrap body with pre-condition check.
-- (let [_pre_check (if (not pre) (error "pre violated") unit)] body)
wrapPre :: Name -> Maybe Expr -> Expr -> Expr
wrapPre _ Nothing body = body
wrapPre funcName (Just preExpr) body =
  ELet
    [ (PVar "_pre_check"
      , Just TBool
      , EIf
          (EOp "not" [preExpr])
          (EApp "runtime-error"
            [ELit (LitString ("Precondition violated in " <> funcName))])
          (ELit LitUnit)
      )
    ]
    body

-- | Wrap body with post-condition check.
-- (let [result body] (let [_post_check ...] result))
wrapPost :: Name -> Maybe Expr -> Expr -> Expr
wrapPost _ Nothing body = body
wrapPost funcName (Just postExpr) body =
  ELet
    [ (PVar "result", Nothing, body) ]
    (ELet
      [ (PVar "_post_check"
        , Just TBool
        , EIf
            (EOp "not" [postExpr])  -- postExpr can reference 'result'
            (EApp "runtime-error"
              [ELit (LitString ("Postcondition violated in " <> funcName))])
            (ELit LitUnit)
        )
      ]
      (EVar "result"))

-- ---------------------------------------------------------------------------
-- Compile-time Contract Evaluation (Symbolic)
-- ---------------------------------------------------------------------------

-- | Attempt to statically check a contract expression given known constant values.
-- Returns Satisfied if provable, Violated if refuted, or ContractUnchecked if unknown.
evalContract :: Name -> Contract -> Map Name Expr -> ContractResult
evalContract funcName contract env =
  case contractPre contract of
    Just preExpr ->
      case evalExprStatic env preExpr of
        Just (ELit (LitBool True))  -> checkPost
        Just (ELit (LitBool False)) ->
          Violated $ ContractViolation funcName PreViolation
            "Precondition statically evaluates to false"
        _ -> ContractUnchecked  -- Can't determine statically
    Nothing -> checkPost
  where
    checkPost = case contractPost contract of
      Nothing -> Satisfied
      Just postExpr ->
        case evalExprStatic env postExpr of
          Just (ELit (LitBool True))  -> Satisfied
          Just (ELit (LitBool False)) ->
            Violated $ ContractViolation funcName PostViolation
              "Postcondition statically evaluates to false"
          _ -> ContractUnchecked

-- ---------------------------------------------------------------------------
-- Function Environment for PBT
-- ---------------------------------------------------------------------------

-- | Top-level function environment for static evaluation.
-- Maps function name to (parameter names, body).
type FuncEnv = Map Name ([Name], Expr)

-- | Maximum unfolding depth — prevents hangs on recursive def-logic.
--
-- v0.10.5 / OBLIG-PBT-2: raised from 64 → 256. With F-032's complex-type
-- generators producing lists of bounded length 8 and depth-5 nested aliases,
-- a property body that calls @transfer → find-balance → list-fold@ over a
-- realistic Ledger exhausts the prior 64-step budget before reaching a
-- terminal Bool. The 4× bump preserves the non-termination guard on
-- self-recursive def-logic (which would hit any finite cap eventually) while
-- giving real property bodies room to reduce.
maxFuel :: Int
maxFuel = 256

-- | Build a function environment from def-logic statements.
-- Excludes SLetrec (explicitly recursive — would need decreases measure).
buildFuncEnv :: [Statement] -> FuncEnv
buildFuncEnv stmts = Map.fromList
  [ (name, (map fst params, body))
  | stmt <- stmts
  , Just (name, params, _mRet, _contract, body) <- [normalizeDefStmt stmt]
  ]

-- ---------------------------------------------------------------------------
-- Minimal Symbolic Evaluator
-- ---------------------------------------------------------------------------

-- | Symbolically evaluate simple expressions with constant folding.
-- Returns Nothing for expressions that can't be reduced to a literal.
--
-- Backward-compatible wrapper: empty FuncEnv, full fuel.
evalExprStatic :: Map Name Expr -> Expr -> Maybe Expr
evalExprStatic = evalExprStaticWith Map.empty maxFuel

-- | Evaluate with separate function and value environments.
-- Fuel counter prevents non-termination on recursive calls.
evalExprStaticWith :: FuncEnv -> Int -> Map Name Expr -> Expr -> Maybe Expr

evalExprStaticWith _fe fuel _env _expr | fuel <= 0 = Nothing

evalExprStaticWith _fe _fuel env (EVar name) = Map.lookup name env
evalExprStaticWith _fe _fuel _   (ELit lit)  = Just (ELit lit)

evalExprStaticWith fe fuel env (EOp op args) = do
  argVals <- mapM (evalExprStaticWith fe fuel env) args
  evalOp op argVals

evalExprStaticWith fe fuel env (EIf cond thenE elseE) = do
  condVal <- evalExprStaticWith fe fuel env cond
  case condVal of
    ELit (LitBool True)  -> evalExprStaticWith fe fuel env thenE
    ELit (LitBool False) -> evalExprStaticWith fe fuel env elseE
    _                    -> Nothing

evalExprStaticWith fe fuel env (ELet bindings body) = do
  env' <- foldM extendEnv env bindings
  evalExprStaticWith fe fuel env' body
  where
    extendEnv acc (PVar n, _mTy, expr) = do
      val <- evalExprStaticWith fe fuel acc expr
      pure (Map.insert n val acc)
    extendEnv _ _ = Nothing  -- non-variable patterns: bail

evalExprStaticWith fe fuel env (EApp func args) = do
  argVals <- mapM (evalExprStaticWith fe fuel env) args
  case Map.lookup func fe of
    Just (paramNames, funcBody)
      | length paramNames == length argVals ->
          let paramEnv = Map.fromList (zip paramNames argVals)
          in evalExprStaticWith fe (fuel - 1) paramEnv funcBody
      | otherwise -> Nothing  -- arity mismatch
    Nothing -> evalBuiltinApp fe fuel func argVals

-- Delegate holes: evaluate fallback if present
evalExprStaticWith fe fuel env (EHole (HDelegate spec)) =
  case delegateOnFailure spec of
    Just fb -> evalExprStaticWith fe fuel env fb
    Nothing -> Nothing

evalExprStaticWith _ _ _ (EHole _) = Nothing

-- Match expressions
evalExprStaticWith fe fuel env (EMatch scrutinee arms) = do
  scrVal <- evalExprStaticWith fe fuel env scrutinee
  matchArms fe fuel env scrVal arms

-- OBLIG-PBT-2 / F-032: pairs and lambdas are values that need to flow through
-- the evaluator unchanged so higher-order builtins (list-fold, list-map) and
-- pair-destructuring builtins (first, second) can operate on PBT-generated
-- samples. Pairs reduce element-wise; lambdas are first-class values handled
-- by applyLambda when invoked.
evalExprStaticWith fe fuel env (EPair a b) = do
  va <- evalExprStaticWith fe fuel env a
  vb <- evalExprStaticWith fe fuel env b
  pure (EPair va vb)

evalExprStaticWith _ _ _ lam@(ELambda _ _) = Just lam

evalExprStaticWith _ _ _ _ = Nothing

-- ---------------------------------------------------------------------------
-- Built-in Function Applications
-- ---------------------------------------------------------------------------

-- | Evaluate built-in function applications.
--
-- OBLIG-PBT-2 / F-032: signature takes FuncEnv + fuel so higher-order builtins
-- (list-fold, list-map) can apply lambdas via 'applyLambda' under the existing
-- fuel discipline. Pair, list, result, and option builtins ground out the
-- §13 core required for PBT to evaluate realistic property bodies.
--
-- Lists are encoded as cons/nil chains, mirroring how @ok@/@err@ encode
-- @Result@ at the AST level (see 'matchPattern' at line 414 — patterns
-- expect EApp ConstructorName).
evalBuiltinApp :: FuncEnv -> Int -> Name -> [Expr] -> Maybe Expr
-- Result constructors (already canonical to Success/Error tags for match)
evalBuiltinApp _ _ "ok"  [val] = Just (EApp "Success" [val])
evalBuiltinApp _ _ "err" [val] = Just (EApp "Error" [val])
evalBuiltinApp _ _ "is-ok" [EApp "Success" _] = Just (ELit (LitBool True))
evalBuiltinApp _ _ "is-ok" [EApp "Error" _]   = Just (ELit (LitBool False))
evalBuiltinApp _ _ "is-ok" _                  = Nothing

-- Pair constructors and destructors
evalBuiltinApp _ _ "pair"   [a, b]      = Just (EPair a b)
evalBuiltinApp _ _ "first"  [EPair a _] = Just a
evalBuiltinApp _ _ "second" [EPair _ b] = Just b
evalBuiltinApp _ _ "first"  _           = Nothing
evalBuiltinApp _ _ "second" _           = Nothing

-- List constructors (cons/nil are the canonical list shape; downstream
-- builtins pattern-match on EApp "cons" / EApp "nil" exactly as match
-- patterns would under 'matchPattern').
evalBuiltinApp _ _ "cons" [hd, tl] = Just (EApp "cons" [hd, tl])
evalBuiltinApp _ _ "nil"  []       = Just (EApp "nil" [])
-- F-034: 'list-empty' is the nullary alias for 'nil' (TypeCheck.hs:95).
evalBuiltinApp _ _ "list-empty" [] = Just (EApp "nil" [])
-- F-034: 'list-prepend a xs' is the spec-surface name for 'cons a xs'
-- (TypeCheck.hs:97). Distinct from 'list-append', which appends at the tail.
evalBuiltinApp _ _ "list-prepend" [x, list] = Just (EApp "cons" [x, list])

-- List destructors and length.
-- F-034: 'list-head' / 'list-tail' signatures per TypeCheck.hs:100-101 are
-- '[list[a]] -> Result a string' and '[list[a]] -> Result (list[a]) string'.
-- The pre-F-034 clauses returned the raw element / raw tail, which mis-typed
-- the evaluator output relative to the type-checker — any property body
-- pattern-matching '(match (list-head xs) ((Success v) ...) ((Error _) ...))'
-- failed to reduce. Empty-list arms were absent and fell through to Nothing;
-- post-F-034 they return Error-tagged so 'unwrap-or (list-head xs) def' and
-- '(match (list-head xs) ((Success ...) ...) ((Error _) ...))' both reduce.
evalBuiltinApp _ _ "list-head" [EApp "cons" [hd, _]] =
  Just (EApp "Success" [hd])
evalBuiltinApp _ _ "list-head" [EApp "nil"  []]      =
  Just (EApp "Error" [ELit (LitString "list-head: empty list")])
evalBuiltinApp _ _ "list-tail" [EApp "cons" [_, tl]] =
  Just (EApp "Success" [tl])
evalBuiltinApp _ _ "list-tail" [EApp "nil"  []]      =
  Just (EApp "Error" [ELit (LitString "list-tail: empty list")])
evalBuiltinApp _ _ "list-is-empty?" [EApp "nil"  []]      = Just (ELit (LitBool True))
evalBuiltinApp _ _ "list-is-empty?" [EApp "cons" [_, _]]  = Just (ELit (LitBool False))
evalBuiltinApp _ _ "list-length" [list]
  | Just n <- listLengthCons list = Just (ELit (LitInt (toInteger n)))
  | otherwise                     = Nothing

-- List append: append element to end (per builtinEnv: list[a] -> a -> list[a])
evalBuiltinApp _ _ "list-append" [list, elt]
  | Just appended <- consAppendElt list elt = Just appended
  | otherwise                               = Nothing

-- Higher-order list operations: fold, map, filter invoke a lambda.
evalBuiltinApp fe fuel "list-fold"   [list, acc, fn] = foldCons   fe fuel list acc fn
evalBuiltinApp fe fuel "list-map"    [list, fn]      = mapCons    fe fuel list fn
-- F-034: 'list-filter xs (fn [x] body)' keeps cons cells whose predicate
-- reduces to True. Mirrors mapCons' fuel discipline.
evalBuiltinApp fe fuel "list-filter" [list, fn]      = filterCons fe fuel list fn

-- F-034: 'int-to-string' (TypeCheck.hs:119): canonical decimal, includes
-- sign for negative values. Required by c02 transfer log-entry bodies.
evalBuiltinApp _ _ "int-to-string" [ELit (LitInt n)] =
  Just (ELit (LitString (T.pack (show n))))
evalBuiltinApp _ _ "int-to-string" _ = Nothing

-- F-034: 'string-concat-many xs' (TypeCheck.hs:115) concatenates a
-- fully-evaluated cons-chain of string literals. Returns Nothing on
-- non-literal elements or unresolved structure (property body discards,
-- conservative behaviour).
evalBuiltinApp _ _ "string-concat-many" [list]
  | Just s <- stringConcatMany list = Just (ELit (LitString s))
  | otherwise                       = Nothing

-- Option-like helpers: unwrap-or extracts Success payload or returns fallback.
evalBuiltinApp _ _ "unwrap-or" [EApp "Success" [v], _]   = Just v
evalBuiltinApp _ _ "unwrap-or" [EApp "Error"   [_], def] = Just def
evalBuiltinApp _ _ "unwrap-or" _                         = Nothing
-- 'unwrap' extracts Success payload; Error is irreducible in the static
-- evaluator (no panic value), so the property body discards on Error
-- samples. F-033: 'unwrap' is registered in TypeCheck.hs:128 but had no
-- clause here, so c02-shape bodies dereferencing '(unwrap (balance …))'
-- discarded universally.
evalBuiltinApp _ _ "unwrap" [EApp "Success" [v]] = Just v
evalBuiltinApp _ _ "unwrap" [EApp "Error"   [_]] = Nothing
evalBuiltinApp _ _ "unwrap" _                    = Nothing
-- Some / None / is-some: Option-shaped helpers commonly used by agent emissions.
-- Treat 'some'/'none' as Result-shaped tags (Success payload / Error unit) so
-- pattern-matching and is-ok stay consistent.
evalBuiltinApp _ _ "some" [val] = Just (EApp "Success" [val])
evalBuiltinApp _ _ "none" []    = Just (EApp "Error" [ELit LitUnit])
evalBuiltinApp _ _ "is-some" [EApp "Success" _] = Just (ELit (LitBool True))
evalBuiltinApp _ _ "is-some" [EApp "Error"   _] = Just (ELit (LitBool False))
evalBuiltinApp _ _ "is-some" _                  = Nothing

-- F-GATE-8: string-length and string-empty? are registered in TypeCheck.hs:109,118
-- but were absent from the static evaluator. Adding them here allows check blocks
-- that test string-predicate properties to evaluate on literal arguments.
-- Both are constant-folding only: non-literal arguments fall through to Nothing.
evalBuiltinApp _ _ "string-length" [ELit (LitString s)] =
  Just (ELit (LitInt (toInteger (T.length s))))
evalBuiltinApp _ _ "string-length" _ = Nothing

evalBuiltinApp _ _ "string-empty?" [ELit (LitString s)] =
  Just (ELit (LitBool (T.null s)))
evalBuiltinApp _ _ "string-empty?" _ = Nothing

evalBuiltinApp _ _ _ _ = Nothing

-- ---------------------------------------------------------------------------
-- List Helpers (OBLIG-PBT-2 / F-032)
-- ---------------------------------------------------------------------------
-- These walk the cons/nil AST encoding. Fuel is shared with the static
-- evaluator (see 'evalExprStaticWith'); each step into a lambda application
-- decrements it.

-- | Length of a fully-evaluated cons-chain ending in nil. Returns Nothing if
-- the structure is not a list (e.g., a variable that did not resolve).
listLengthCons :: Expr -> Maybe Int
listLengthCons (EApp "nil"  [])           = Just 0
listLengthCons (EApp "cons" [_, tl])      = succ <$> listLengthCons tl
listLengthCons _                          = Nothing

-- | Append a single element to the end of a cons-chain.
consAppendElt :: Expr -> Expr -> Maybe Expr
consAppendElt (EApp "nil"  [])      elt = Just (EApp "cons" [elt, EApp "nil" []])
consAppendElt (EApp "cons" [hd, tl]) elt = do
  tl' <- consAppendElt tl elt
  pure (EApp "cons" [hd, tl'])
consAppendElt _ _ = Nothing

-- | Fold over a cons-chain: list-fold xs acc (fn [acc, x] body) → final acc.
foldCons :: FuncEnv -> Int -> Expr -> Expr -> Expr -> Maybe Expr
foldCons _  _    (EApp "nil"  []) acc _  = Just acc
foldCons fe fuel (EApp "cons" [hd, tl]) acc fn = do
  acc' <- applyLambda fe (fuel - 1) fn [acc, hd]
  foldCons fe (fuel - 1) tl acc' fn
foldCons _ _ _ _ _ = Nothing

-- | Map over a cons-chain: list-map xs (fn [x] body) → cons-chain of body
-- results, preserving order.
mapCons :: FuncEnv -> Int -> Expr -> Expr -> Maybe Expr
mapCons _  _    (EApp "nil"  []) _  = Just (EApp "nil" [])
mapCons fe fuel (EApp "cons" [hd, tl]) fn = do
  hd' <- applyLambda fe (fuel - 1) fn [hd]
  tl' <- mapCons fe (fuel - 1) tl fn
  pure (EApp "cons" [hd', tl'])
mapCons _ _ _ _ = Nothing

-- | Filter a cons-chain by a predicate lambda: list-filter xs (fn [x] body) →
-- cons-chain of elements for which body reduces to True. Returns Nothing on
-- unresolved structure or if the predicate fails to reduce to a Bool literal
-- (conservative: property body discards). Fuel discipline mirrors mapCons.
filterCons :: FuncEnv -> Int -> Expr -> Expr -> Maybe Expr
filterCons _  _    (EApp "nil"  []) _  = Just (EApp "nil" [])
filterCons fe fuel (EApp "cons" [hd, tl]) fn = do
  predVal <- applyLambda fe (fuel - 1) fn [hd]
  tl'     <- filterCons fe (fuel - 1) tl fn
  case predVal of
    ELit (LitBool True)  -> pure (EApp "cons" [hd, tl'])
    ELit (LitBool False) -> pure tl'
    _                    -> Nothing
filterCons _ _ _ _ = Nothing

-- | Concatenate a fully-evaluated cons-chain of LitString literals. Returns
-- Nothing on unresolved structure or non-string elements; the property body
-- then discards on such samples (soundness-preserving).
stringConcatMany :: Expr -> Maybe Text
stringConcatMany (EApp "nil"  [])                       = Just T.empty
stringConcatMany (EApp "cons" [ELit (LitString s), tl]) = (s <>) <$> stringConcatMany tl
stringConcatMany _                                      = Nothing

-- | Apply a lambda to argument values via beta reduction. Fuel-decremented
-- per call so recursive use under higher-order builtins terminates.
applyLambda :: FuncEnv -> Int -> Expr -> [Expr] -> Maybe Expr
applyLambda fe fuel (ELambda params body) args
  | length params == length args =
      let paramEnv = Map.fromList (zip (map fst params) args)
      in evalExprStaticWith fe fuel paramEnv body
  | otherwise = Nothing
applyLambda _ _ _ _ = Nothing

-- ---------------------------------------------------------------------------
-- Pattern Matching
-- ---------------------------------------------------------------------------

-- | Try to match a scrutinee value against a list of arms.
matchArms :: FuncEnv -> Int -> Map Name Expr -> Expr -> [(Pattern, Expr)] -> Maybe Expr
matchArms _  _    _   _ [] = Nothing
matchArms fe fuel env scrVal ((pat, body):rest) =
  case matchPattern scrVal pat of
    Just bindings -> evalExprStaticWith fe fuel (Map.union bindings env) body
    Nothing       -> matchArms fe fuel env scrVal rest

-- | Try to match a value against a pattern, returning bindings on success.
matchPattern :: Expr -> Pattern -> Maybe (Map Name Expr)
matchPattern _ PWildcard       = Just Map.empty
matchPattern v (PVar name)     = Just (Map.singleton name v)
matchPattern (ELit lit) (PLiteral pLit)
  | lit == pLit = Just Map.empty
  | otherwise   = Nothing
matchPattern (EApp ctorName args) (PConstructor patCtor subPats)
  | ctorName == patCtor && length args == length subPats = do
      bindings <- zipWithM matchPattern args subPats
      pure (Map.unions bindings)
  | ctorName == patCtor = Nothing  -- arity mismatch
matchPattern _ (PConstructor _ _) = Nothing
matchPattern _ _ = Nothing

-- | Evaluate a built-in operator on literal values.
evalOp :: Name -> [Expr] -> Maybe Expr
evalOp "not" [ELit (LitBool b)] = Just (ELit (LitBool (not b)))
evalOp "and" [ELit (LitBool a), ELit (LitBool b)] = Just (ELit (LitBool (a && b)))
evalOp "or"  [ELit (LitBool a), ELit (LitBool b)] = Just (ELit (LitBool (a || b)))
evalOp "="   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a == b)))
evalOp "!="  [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a /= b)))
evalOp "="   [ELit (LitBool a), ELit (LitBool b)]  = Just (ELit (LitBool (a == b)))
evalOp "!="  [ELit (LitBool a), ELit (LitBool b)]  = Just (ELit (LitBool (a /= b)))
evalOp "="   [ELit (LitString a), ELit (LitString b)] = Just (ELit (LitBool (a == b)))
evalOp "!="  [ELit (LitString a), ELit (LitString b)] = Just (ELit (LitBool (a /= b)))
evalOp "<"   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a <  b)))
evalOp ">"   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a >  b)))
evalOp "<="  [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a <= b)))
evalOp ">="  [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a >= b)))
evalOp "+"   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitInt  (a +  b)))
evalOp "-"   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitInt  (a -  b)))
evalOp "*"   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitInt  (a *  b)))
evalOp "/" [ELit (LitInt a), ELit (LitInt b)]
  | b /= 0 = Just (ELit (LitInt (a `div` b)))
evalOp _ _ = Nothing
