{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.LeanTranslate
-- Description : Translate LLMLL contract AST to Lean 4 theorem obligations (v0.3.1).
--
-- Converts contract pre/post conditions into Lean 4 @theorem@ statements
-- suitable for verification by Leanstral's @lean-lsp-mcp@.
--
-- Supported translations:
--   * Linear arithmetic via EOp: @>@, @>=@, @<@, @<=@, @=@, @+@, @-@
--   * List functions via EApp: @list-length@, @list-head@, @list-tail@
--   * Quantified variables from @for-all@ bindings
--   * @pre@ → hypothesis, @post@ → goal
--
-- Unsupported predicates produce @Unsupported reason@ results.
module LLMLL.LeanTranslate
  ( translateObligation
  , TranslateResult(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import LLMLL.Syntax (Contract(..), Expr(..), Literal(..), Name)

-- | Result of translating a contract to a Lean 4 theorem.
data TranslateResult
  = LeanTheorem Text      -- ^ Valid Lean 4 theorem text
  | Unsupported Text       -- ^ Reason why translation is not possible
  deriving (Show, Eq)

-- | Translate a named contract into a Lean 4 theorem obligation.
translateObligation :: Name -> Contract -> TranslateResult
translateObligation name contract =
  case (contractPre contract, contractPost contract) of
    (Nothing, Nothing) -> Unsupported "empty contract (no pre/post)"
    (mPre, mPost) ->
      case (fmap exprToLean mPre, fmap exprToLean mPost) of
        (_, Just (Left reason)) -> Unsupported reason
        (Just (Left reason), _) -> Unsupported reason
        (mPreLean, mPostLean) ->
          let hypotheses = case mPreLean of
                Just (Right h) -> " (h : " <> h <> ")"
                Nothing -> ""
              goal = case mPostLean of
                Just (Right g) -> g
                Nothing -> "True"
              thName = sanitizeName name
          in LeanTheorem $
               "theorem " <> thName <> hypotheses <> " : " <> goal <> " := by\n  sorry"

-- | Sanitize an LLMLL name for Lean 4 (replace hyphens with underscores).
sanitizeName :: Name -> Text
sanitizeName = T.replace "-" "_"

-- | Convert an LLMLL expression to Lean 4 syntax.
--   Returns @Left reason@ for unsupported constructs.
exprToLean :: Expr -> Either Text Text

-- Literals
exprToLean (ELit (LitInt n))      = Right (T.pack (show n))
exprToLean (ELit (LitBool True))  = Right "True"
exprToLean (ELit (LitBool False)) = Right "False"
exprToLean (EVar name)            = Right (sanitizeName name)

-- Operators (EOp Name [Expr]) — binary operators
exprToLean (EOp ">" [lhs, rhs])  = binop ">" lhs rhs
exprToLean (EOp ">=" [lhs, rhs]) = binop ">=" lhs rhs
exprToLean (EOp "<" [lhs, rhs])  = binop "<" lhs rhs
exprToLean (EOp "<=" [lhs, rhs]) = binop "<=" lhs rhs
exprToLean (EOp "=" [lhs, rhs])  = binop "=" lhs rhs
exprToLean (EOp "+" [lhs, rhs])  = binop "+" lhs rhs
exprToLean (EOp "-" [lhs, rhs])  = binop "-" lhs rhs
exprToLean (EOp "*" [lhs, rhs])  = binop "*" lhs rhs
exprToLean (EOp "and" [lhs, rhs]) = binop "∧" lhs rhs
exprToLean (EOp "or" [lhs, rhs])  = binop "∨" lhs rhs
exprToLean (EOp "not" [arg]) = do
  a <- exprToLean arg
  Right ("¬" <> a)

-- Function applications (EApp Name [Expr])
exprToLean (EApp "list-length" [arg]) = do
  a <- exprToLean arg
  Right (a <> ".length")
exprToLean (EApp "list-head" [arg]) = do
  a <- exprToLean arg
  Right (a <> ".head!")
exprToLean (EApp "list-tail" [arg]) = do
  a <- exprToLean arg
  Right (a <> ".tail")

-- for-all: (EApp "for-all" [EVar v, body])
exprToLean (EApp "for-all" [EVar v, body]) = do
  b <- exprToLean body
  Right ("∀ " <> sanitizeName v <> ", " <> b)

-- Unsupported
exprToLean (EApp "map" _)  = Left "map is not supported for Lean translation"
exprToLean (EApp "fold" _) = Left "fold is not supported for Lean translation"
exprToLean e = Left ("unsupported expression: " <> T.pack (show e))

-- | Helper to translate a binary operation.
binop :: Text -> Expr -> Expr -> Either Text Text
binop op lhs rhs = do
  l <- exprToLean lhs
  r <- exprToLean rhs
  Right ("(" <> l <> " " <> op <> " " <> r <> ")")
