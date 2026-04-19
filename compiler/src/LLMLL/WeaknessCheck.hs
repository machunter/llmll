-- |
-- Module      : LLMLL.WeaknessCheck
-- Description : v0.3.5 Track W — Weak-spec counter-example generation.
--
-- After @llmll verify@ reports SAFE for a function's contracts, this module
-- attempts to construct trivial bodies that also satisfy those contracts.
-- If a trivial body passes both the type checker and the fixpoint verifier,
-- the specification is considered "weak" — it admits implementations that
-- are almost certainly not the intended ones.
--
-- Design: constructs synthetic 'SDefLogic' statements, type-checks them,
-- then calls 'emitFixpoint' to generate .fq constraints. The caller
-- (Main.hs) invokes the solver and interprets the result.
--
-- Faithfulness: this module NEVER modifies FixpointEmit.hs or builtinEnv.
-- It constructs standard AST nodes and delegates to existing infrastructure.

module LLMLL.WeaknessCheck
  ( -- * Types
    WeaknessCandidate(..)
  , TrivialBody(..)
    -- * Core API
  , generateWeaknessCandidates
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe, catMaybes)

import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, emptyEnv, builtinEnv, TypeCheckResult(..))
import LLMLL.Diagnostic (Diagnostic(..), Severity(..), DiagnosticReport(..))

-- ---------------------------------------------------------------------------
-- Trivial Body Catalog
-- ---------------------------------------------------------------------------

-- | Classification of trivial body strategies.
data TrivialBody
  = TrivIdentity Name   -- ^ return a parameter unchanged: (lambda [p] p)
  | TrivConstZero       -- ^ return literal 0
  | TrivConstEmptyStr   -- ^ return literal ""
  | TrivConstTrue       -- ^ return literal true
  | TrivConstEmptyList  -- ^ return (list-empty)
  deriving (Show, Eq)

-- | Human-readable label for a trivial body.
trivialLabel :: TrivialBody -> Text
trivialLabel (TrivIdentity p) = "(lambda [" <> p <> "] " <> p <> ")"
trivialLabel TrivConstZero    = "(lambda [...] 0)"
trivialLabel TrivConstEmptyStr = "(lambda [...] \"\")"
trivialLabel TrivConstTrue     = "(lambda [...] true)"
trivialLabel TrivConstEmptyList = "(lambda [...] (list-empty))"

-- | Construct the AST expression for a trivial body.
trivialExpr :: TrivialBody -> Expr
trivialExpr (TrivIdentity p) = EVar p
trivialExpr TrivConstZero    = ELit (LitInt 0)
trivialExpr TrivConstEmptyStr = ELit (LitString "")
trivialExpr TrivConstTrue     = ELit (LitBool True)
trivialExpr TrivConstEmptyList = EApp "list-empty" []

-- ---------------------------------------------------------------------------
-- Weakness Candidate
-- ---------------------------------------------------------------------------

-- | A candidate trivial implementation that passed the type checker.
-- The caller (Main.hs) uses this to run the fixpoint verifier.
data WeaknessCandidate = WeaknessCandidate
  { wcFunctionName  :: Name          -- ^ original function name
  , wcTrivialBody   :: TrivialBody   -- ^ which trivial strategy
  , wcTrivialLabel  :: Text          -- ^ human-readable body text
  , wcSyntheticStmt :: Statement     -- ^ synthetic SDefLogic for emitFixpoint
  , wcPrecondition  :: Maybe Expr    -- ^ original pre (for EC-7 diagnostic text)
  , wcPostcondition :: Maybe Expr    -- ^ original post
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Core API
-- ---------------------------------------------------------------------------

-- | For each contracted function in the statement list, generate type-safe
-- trivial body candidates. These are ready to be fed to 'emitFixpoint'.
--
-- Algorithm:
--   1. Extract functions with contracts (pre/post)
--   2. For each function, generate the trivial body catalog
--   3. Type-check each synthetic statement (INV-4)
--   4. Keep only type-safe candidates
--
-- Functions without contracts are skipped (nothing to check weakness against).
generateWeaknessCandidates :: [Statement] -> [WeaknessCandidate]
generateWeaknessCandidates stmts =
  concatMap generateForStmt stmts

-- | Generate weakness candidates for a single statement.
generateForStmt :: Statement -> [WeaknessCandidate]
generateForStmt (SDefLogic name params mRet contract body)
  | hasContracts contract =
      let catalog = trivialCatalog params mRet
      in mapMaybe (tryCandidate name params mRet contract) catalog
generateForStmt (SLetrec name params mRet contract dec body)
  | hasContracts contract =
      -- For letrec, generate SDefLogic (no recursion needed for trivial bodies)
      let catalog = trivialCatalog params mRet
      in mapMaybe (tryCandidate name params mRet contract) catalog
generateForStmt _ = []

-- | Does this contract have at least one clause?
hasContracts :: Contract -> Bool
hasContracts (Contract pre post) = pre /= Nothing || post /= Nothing

-- | Generate the catalog of trivial bodies applicable to this function signature.
trivialCatalog :: [(Name, Type)] -> Maybe Type -> [TrivialBody]
trivialCatalog params mRet =
  let identities = [TrivIdentity p | (p, pTy) <- params, matchesReturn pTy mRet]
      constants  = catMaybes
        [ if matchesReturnType TInt mRet      then Just TrivConstZero else Nothing
        , if matchesReturnType TString mRet   then Just TrivConstEmptyStr else Nothing
        , if matchesReturnType TBool mRet     then Just TrivConstTrue else Nothing
        , if matchesReturnList mRet           then Just TrivConstEmptyList else Nothing
        ]
  in identities ++ constants

-- | Check if a param type matches the return type (for identity body).
matchesReturn :: Type -> Maybe Type -> Bool
matchesReturn _ Nothing = True  -- no return annotation → any param could work
matchesReturn pTy (Just retTy) = compatibleTypes pTy retTy

-- | Check if a given type matches the return type.
matchesReturnType :: Type -> Maybe Type -> Bool
matchesReturnType _ Nothing = False  -- only generate constant if return type is known
matchesReturnType t (Just retTy) = compatibleTypes t retTy

-- | Check if return type is a list type.
matchesReturnList :: Maybe Type -> Bool
matchesReturnList (Just (TList _)) = True
matchesReturnList _ = False

-- | Structural type compatibility (simplified, for trivial body filtering).
-- This is a conservative check — the type checker will catch false positives.
compatibleTypes :: Type -> Type -> Bool
compatibleTypes TInt TInt = True
compatibleTypes TString TString = True
compatibleTypes TBool TBool = True
compatibleTypes TFloat TFloat = True
compatibleTypes TUnit TUnit = True
compatibleTypes (TList _) (TList _) = True
compatibleTypes (TVar _) _ = True
compatibleTypes _ (TVar _) = True
compatibleTypes a b = a == b

-- | Try to construct a type-safe weakness candidate.
-- Returns Nothing if the type checker rejects the synthetic body (INV-4).
tryCandidate
  :: Name
  -> [(Name, Type)]
  -> Maybe Type
  -> Contract
  -> TrivialBody
  -> Maybe WeaknessCandidate
tryCandidate name params mRet contract trivBody =
  let syntheticBody = trivialExpr trivBody
      syntheticStmt = SDefLogic
        ("__weakness_check_" <> name)
        params
        mRet
        contract
        syntheticBody
      -- INV-4: Type-check the synthetic statement.
      -- We use emptyEnv + builtinEnv since the function must be self-contained.
      report = typeCheck builtinEnv [syntheticStmt]
      hasErrors = any (\d -> diagSeverity d == SevError) (reportDiagnostics report)
  in if hasErrors
     then Nothing  -- type-incompatible trivial body, skip silently
     else Just WeaknessCandidate
       { wcFunctionName  = name
       , wcTrivialBody   = trivBody
       , wcTrivialLabel  = trivialLabel trivBody
       , wcSyntheticStmt = syntheticStmt
       , wcPrecondition  = contractPre contract
       , wcPostcondition = contractPost contract
       }
