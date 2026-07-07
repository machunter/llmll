-- |
-- Module      : LLMLL.GuardClassifier
-- Description : Shared guard classification logic (v0.10, OBLIG-0 §4.2.4).
--
-- Sort-aware predicate classification extracted from FixpointEmit.guardToPredM.
-- Both the verification consumer (FixpointEmit) and the presentation consumer
-- (ObligationAssembly) call classifyGuardM, preventing drift between the two
-- codepaths. The shared core handles variable lookup, operator dispatch, and
-- recursive structure; consumers differ only in what they do with the result.
--
-- Depends on FixpointIR.FQPred (stable since v0.8.0, no IO, no dependencies
-- beyond Text). This coupling is accepted — see Language Team Finding 3.
module LLMLL.GuardClassifier
  ( -- * Shared guard classification core
    classifyGuardM
    -- * Operator lookup tables (moved from FixpointEmit)
  , lookupPredOp
  , lookupArithOp
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, catMaybes)
import Control.Monad.State.Strict (State)

import LLMLL.Syntax (Name, Expr(..), Literal(..))
import LLMLL.FixpointIR (FQPred(..), FQBinOp(..), FQSort(..))
-- F1: SortEnv is a type alias defined in FixpointEmit. We import it
-- as Map Name FQSort directly since it's just a type alias.
-- The canonical import path is LLMLL.FixpointEmit.SortEnv.

-- | SortEnv maps variable names to their FQ sorts.
-- Duplicated from FixpointEmit to avoid circular imports.
-- Both definitions are identical: @type SortEnv = Map Name FQSort@.
type SortEnv = Map Name FQSort

-- ---------------------------------------------------------------------------
-- Shared guard classification core (v0.8.0 origin, v0.10 extraction)
-- ---------------------------------------------------------------------------

-- | Translates guard expressions to FQPred, consulting BOTH the renaming
-- environment AND SortEnv. Variables are checked against sortEnv; non-int
-- or unknown vars cause fallback. This prevents the soundness bug where
-- exprToPred would silently assign FQInt to bool/string variables.
--
-- This is the shared core called by:
--   * FixpointEmit.guardToPredM (verification — uses FQPred for solver)
--   * ObligationAssembly.guardToPredPresentation (presentation — checks isJust)
classifyGuardM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
classifyGuardM env sortEnv (EVar v) =
  let renamed = fromMaybe v (Map.lookup v env)
  in case Map.lookup renamed sortEnv of
       Just FQInt  -> return (Just (FQVar renamed))
       Just FQBool -> return (Just (FQVar renamed))  -- BOOL-FRAG: bool var as a guard atom (path-split on b / ¬b)
       _           -> return Nothing  -- non-scalar or unknown → fallback

classifyGuardM _ _ (ELit (LitBool True))  = return (Just FQTrue)
classifyGuardM _ _ (ELit (LitBool False)) = return (Just FQFalse)
classifyGuardM _ _ (ELit (LitInt n))      = return (Just (FQLit n))

-- Comparison operators (including Unicode aliases)
classifyGuardM env se (EApp op [l, r])
  | Just binOp <- lookupPredOp op = do
      lp <- classifyGuardM env se l
      rp <- classifyGuardM env se r
      return $ FQBinPred binOp <$> lp <*> rp

-- Arithmetic in guards
classifyGuardM env se (EApp op [l, r])
  | Just binOp <- lookupArithOp op = do
      lp <- classifyGuardM env se l
      rp <- classifyGuardM env se r
      return $ FQBinArith binOp <$> lp <*> rp

-- Non-linear in guards
classifyGuardM _ _ (EApp op [_, _])
  | op `elem` ["*", "/", "mod", "rem"] = return Nothing

classifyGuardM env se (EApp "not" [a]) = do
  ap <- classifyGuardM env se a
  return $ FQNot <$> ap

classifyGuardM env se (EApp "and" args) = do
  ps <- mapM (classifyGuardM env se) args
  return $ if all isJust ps then Just (FQAnd (catMaybes ps)) else Nothing

classifyGuardM env se (EApp "or" args) = do
  ps <- mapM (classifyGuardM env se) args
  return $ if all isJust ps then Just (FQOr (catMaybes ps)) else Nothing

-- Normalize EOp
classifyGuardM env se (EOp name args) = classifyGuardM env se (EApp name args)

-- Everything else in guard position: ELet, EIf, etc. → fallback
classifyGuardM _ _ _ = return Nothing

-- ---------------------------------------------------------------------------
-- Operator lookup tables (moved from FixpointEmit, v0.8.0)
-- ---------------------------------------------------------------------------

-- | Look up an arithmetic binary operator (including Unicode aliases).
lookupArithOp :: Name -> Maybe FQBinOp
lookupArithOp "+" = Just FQAdd
lookupArithOp "-" = Just FQSub
lookupArithOp _   = Nothing

-- | Look up a predicate binary operator (including Unicode aliases).
lookupPredOp :: Name -> Maybe FQBinOp
lookupPredOp ">="  = Just FQGe
lookupPredOp "≥"   = Just FQGe
lookupPredOp ">"   = Just FQGt
lookupPredOp "<="  = Just FQLe
lookupPredOp "≤"   = Just FQLe
lookupPredOp "<"   = Just FQLt
lookupPredOp "="   = Just FQEq
lookupPredOp "=="  = Just FQEq
lookupPredOp "/="  = Just FQNeq
lookupPredOp "!="  = Just FQNeq
lookupPredOp "≠"   = Just FQNeq
lookupPredOp _     = Nothing
