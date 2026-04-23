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
      totalFns = length [() | SDefLogic{} <- stmts]
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
  | ContractsUnproven  -- ^ Strip assertions for VLProven contracts only
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
    lookupStatus _                     = defaultCS
    defaultCS = ContractStatus Nothing Nothing Nothing Nothing

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
-- Everything else: pass through
instrumentStatement _ _ stmt = stmt

-- | Strip proven contract clauses, keep unproven ones.
filterContracts :: ContractStatus -> Contract -> Contract
filterContracts cs contract = Contract
  { contractPre = case csPreLevel cs of
      Just (VLProven _) -> Nothing
      _                 -> contractPre contract
  , contractPreSource = contractPreSource contract
  , contractPost = case csPostLevel cs of
      Just (VLProven _) -> Nothing
      _                 -> contractPost contract
  , contractPostSource = contractPostSource contract
  }

-- | Empty contract — contracts moved into body as assertions.
noContract :: Contract
noContract = Contract Nothing Nothing Nothing Nothing

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
      let cs = Map.findWithDefault (ContractStatus Nothing Nothing Nothing Nothing) n statusMap
      in SDefLogic n p r (filterContracts cs c) b
    stripProven (SLetrec n p r c d b) =
      let cs = Map.findWithDefault (ContractStatus Nothing Nothing Nothing Nothing) n statusMap
      in SLetrec n p r (filterContracts cs c) d b
    stripProven s = s

-- | Clear all contract clauses from a statement.
clearContracts :: Statement -> Statement
clearContracts (SDefLogic n p r _ b) = SDefLogic n p r noContract b
clearContracts (SLetrec n p r _ d b) = SLetrec n p r noContract d b
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
-- Minimal Symbolic Evaluator
-- ---------------------------------------------------------------------------

-- | Symbolically evaluate simple expressions with constant folding.
-- Returns Nothing for expressions that can't be reduced to a literal.
evalExprStatic :: Map Name Expr -> Expr -> Maybe Expr
evalExprStatic env (EVar name) = Map.lookup name env
evalExprStatic _   (ELit lit)  = Just (ELit lit)

evalExprStatic env (EOp op args) = do
  argVals <- mapM (evalExprStatic env) args
  evalOp op argVals

evalExprStatic env (EIf cond thenE elseE) = do
  condVal <- evalExprStatic env cond
  case condVal of
    ELit (LitBool True)  -> evalExprStatic env thenE
    ELit (LitBool False) -> evalExprStatic env elseE
    _                    -> Nothing

evalExprStatic env (EApp func args) = do
  argVals <- mapM (evalExprStatic env) args
  case Map.lookup func env of
    Just body -> evalExprStatic (Map.fromList (zipWith mkBinding [0..] argVals)) body
    Nothing   -> Nothing
  where
    mkBinding :: Int -> Expr -> (Name, Expr)
    mkBinding i v = (T.pack ("arg" ++ show i), v)

evalExprStatic _ _ = Nothing

-- | Evaluate a built-in operator on literal values.
evalOp :: Name -> [Expr] -> Maybe Expr
evalOp "not" [ELit (LitBool b)] = Just (ELit (LitBool (not b)))
evalOp "and" [ELit (LitBool a), ELit (LitBool b)] = Just (ELit (LitBool (a && b)))
evalOp "or"  [ELit (LitBool a), ELit (LitBool b)] = Just (ELit (LitBool (a || b)))
evalOp "="   [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a == b)))
evalOp "!="  [ELit (LitInt  a), ELit (LitInt b)]  = Just (ELit (LitBool (a /= b)))
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
