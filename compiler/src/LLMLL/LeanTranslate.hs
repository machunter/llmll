{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.LeanTranslate
-- Description : Translate an LLMLL OBLIGATION (not just its contract) to a Lean 4 theorem.
--
-- Layer-1-lite of the Leanstral demo (`docs/design/leanstral-demo-spec.md §3`).
--
-- The production Layer-1 finding (`leanstral-integration-scope.md §2`) was that
-- the old translator read only the /contract/ — @result@ and the params were
-- unbound free variables, so the emitted theorem was misstated (either
-- non-elaborating or an auto-bound-implicit universally-quantified /false/
-- claim). A proved Lean theorem certifies the LLMLL contract only if the
-- encoding is faithful, so faithfulness is the trust root.
--
-- 'translateObligation' now receives @(name, params, ret, contract, body)@ and
-- emits, with @result@ BOUND to the translated body:
--
-- > import Mathlib.Tactic
-- >
-- > theorem <name> (p₁ : T₁) … (result : Tret) (h_body : result = ⟦body⟧) : ⟦post⟧ := by
-- >   sorry
--
-- Faithfulness is scoped to the demo obligation class (multiplication-only,
-- @result@-bound, no partial function) so the translation is faithful /by
-- inspection/ (spec §6). 'bodyToLean' admits the QF-LIA fragment plus integer
-- @*@ (which agrees between Haskell codegen and Lean 4 — no floor-vs-truncated
-- landmine, unlike @/@\/@mod@) and returns @Left@ for EVERYTHING else
-- (@/@, @mod@, @rem@, @^@, @**@, lists, matches, lambdas, holes) and for any
-- residual free variable (fail-closed). The old unfaithful paths — @list-head@
-- → @.head!@ (a partial function that proves the post for @[]@) and the untyped
-- @for-all@ → @∀@ — are killed: they are 'Unsupported' now.
module LLMLL.LeanTranslate
  ( translateObligation
  , TranslateResult(..)
  , bodyToLean
  , exprToLeanScoped
  ) where

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import LLMLL.Syntax (Contract(..), Expr(..), Literal(..), Name, Type(..))

-- | Result of translating an obligation to a Lean 4 theorem.
data TranslateResult
  = LeanTheorem Text      -- ^ Valid Lean 4 theorem text (ends in @sorry@ — Leanstral fills the proof)
  | Unsupported Text      -- ^ Reason why a faithful translation is not possible (fail-closed)
  deriving (Show, Eq)

-- | Translate a function's OBLIGATION into a Lean 4 theorem.
--
-- @translateObligation name params ret contract body@ states
-- @pre ∧ (result = ⟦body⟧) ⟹ post@ with @result@ bound to the body, mirroring
-- the body-VC LHS shape (@FixpointEmit.hs:701-706@: @result = resultPred@).
--
-- Fail-closed on: a missing return type (nothing to bind @result@ to), an
-- unsupported param\/return type, an empty postcondition (nothing to prove), a
-- body or predicate outside the faithful fragment, or a residual free variable.
translateObligation
  :: Name                 -- ^ function name
  -> [(Name, Type)]       -- ^ parameters
  -> Maybe Type           -- ^ return type (binds @result@)
  -> Contract             -- ^ pre\/post
  -> Expr                 -- ^ the real body
  -> TranslateResult
translateObligation name params mRet contract body =
  case mRet of
    Nothing  -> Unsupported "return type required to bind `result`"
    Just ret -> case typeToLean ret of
      Left r        -> Unsupported ("return type: " <> r)
      Right retLean -> case mapM (\(pn, pt) -> (,) pn <$> typeToLean pt) params of
        Left r         -> Unsupported ("parameter type: " <> r)
        Right paramTys -> case contractPost contract of
          Nothing   -> Unsupported "empty postcondition (nothing to prove)"
          Just post ->
            let paramScope = Set.fromList (map fst params)
                postScope  = Set.insert "result" paramScope
            in case bodyToLean paramScope body of
              Left r         -> Unsupported ("body: " <> r)
              Right bodyLean -> case exprToLeanScoped postScope post of
                Left r        -> Unsupported ("post: " <> r)
                Right postLean ->
                  -- Optional precondition → an extra hypothesis (params in scope).
                  case fmap (exprToLeanScoped paramScope) (contractPre contract) of
                    Just (Left r) -> Unsupported ("pre: " <> r)
                    mPreEither    ->
                      let preHyp = case mPreEither of
                            Just (Right p) -> " (h_pre : " <> p <> ")"
                            _              -> ""
                          paramBinders = T.concat
                            [ " (" <> sanitizeName pn <> " : " <> pty <> ")"
                            | (pn, pty) <- paramTys ]
                          header = "theorem " <> sanitizeName name
                                 <> paramBinders
                                 <> preHyp
                                 <> " (result : " <> retLean <> ")"
                                 <> " (h_body : result = " <> bodyLean <> ")"
                                 <> " : " <> postLean <> " := by"
                      in LeanTheorem $ "import Mathlib.Tactic\n\n" <> header <> "\n  sorry"

-- | Translate a function body over the faithful QF-LIA + integer-@*@ fragment.
--
-- @scope@ is the set of in-scope binders (the params). An 'EVar' outside it is
-- a residual free variable → @Left@ (fail-closed). Everything outside the
-- fragment is @Left@.
bodyToLean :: Set Name -> Expr -> Either Text Text
bodyToLean = exprToLeanScoped

-- | Translate an LLMLL expression to Lean 4 over the faithful fragment.
--
-- Admits: integer\/bool literals, in-scope variables, the linear arithmetic
-- operators (@+@, @-@), integer @*@ (faithful — no floor\/trunc divergence),
-- the comparisons (@>@, @>=@, @<@, @<=@, @=@, @!=@ and their Unicode aliases),
-- and the boolean connectives (@and@, @or@, @not@). Returns @Left reason@ for
-- @/@\/@mod@\/@rem@\/@^@\/@**@ (nonlinear\/partial — the floor-vs-truncated
-- landmine, `leanstral-integration-scope.md §7`), for lists\/matches\/lambdas\/
-- holes, and for a variable not in @scope@.
exprToLeanScoped :: Set Name -> Expr -> Either Text Text
exprToLeanScoped _ (ELit (LitInt n))      = Right (litIntLean n)
exprToLeanScoped _ (ELit (LitBool True))  = Right "True"
exprToLeanScoped _ (ELit (LitBool False)) = Right "False"
exprToLeanScoped scope (EVar v)
  | v `Set.member` scope = Right (sanitizeName v)
  | otherwise            = Left ("residual free variable `" <> v <> "` (fail-closed)")
-- Operators reach us as EOp (S-expr parser) or, in some AST forms, as EApp;
-- normalize both through one handler (mirrors 'isNonLinear''s EOp→EApp
-- normalization, HoleAnalysis.hs:348).
exprToLeanScoped scope (EOp op args)  = opAppToLean scope op args
exprToLeanScoped scope (EApp op args) = opAppToLean scope op args
exprToLeanScoped _ e =
  Left ("unsupported expression outside the demo fragment: " <> T.pack (show e))

-- | Translate an operator\/function application over the faithful fragment.
opAppToLean :: Set Name -> Name -> [Expr] -> Either Text Text
opAppToLean scope op [l, r]
  | Just leanOp <- lookup op binOps         = binopToLean scope leanOp l r
  | op `elem` nonlinearOps                  =
      Left (op <> " is nonlinear/partial arithmetic — outside the demo fragment "
            <> "(faithful Int.fdiv/fmod mapping is production work)")
opAppToLean scope "not" [a] = do
  a' <- exprToLeanScoped scope a
  Right ("¬" <> a')
-- IMPL-SUGAR: desugar =>/<=> to or/not/and (Lean already handles ∨/¬/∧ via binOps)
opAppToLean scope "=>" [p, q] =
  exprToLeanScoped scope (EApp "or" [EApp "not" [p], q])
opAppToLean scope "<=>" [p, q] =
  exprToLeanScoped scope (EApp "and" [EApp "or" [EApp "not" [p], q], EApp "or" [EApp "not" [q], p]])
opAppToLean _ op args =
  Left ("unsupported application `" <> op <> "`/" <> T.pack (show (length args)))

-- | Binary operators that translate faithfully. @*@ is in — it agrees between
-- Haskell codegen and Lean 4; @/@\/@mod@ are deliberately absent (landmine).
binOps :: [(Name, Text)]
binOps =
  [ ("+", "+"), ("-", "-"), ("*", "*")
  , (">", ">"), (">=", ">="), ("<", "<"), ("<=", "<=")
  , ("=", "="), ("==", "="), ("!=", "≠"), ("/=", "≠")
  , ("and", "∧"), ("or", "∨")
  -- Unicode comparison aliases the parser may carry through:
  , ("\x2265", ">="), ("\x2264", "<="), ("\x2260", "≠")
  , ("\x2227", "∧"), ("\x2228", "∨")
  ]

-- | Operators deliberately rejected as unfaithful\/nonlinear for the demo.
nonlinearOps :: [Name]
nonlinearOps = ["/", "mod", "rem", "^", "**"]

-- | Translate a binary application, parenthesizing the result.
binopToLean :: Set Name -> Text -> Expr -> Expr -> Either Text Text
binopToLean scope op l r = do
  l' <- exprToLeanScoped scope l
  r' <- exprToLeanScoped scope r
  Right ("(" <> l' <> " " <> op <> " " <> r' <> ")")

-- | Translate an LLMLL type to a Lean 4 type. Fail-closed outside the demo
-- fragment: only @int@ (→ @Int@) and @bool@ (→ @Bool@) are faithful here.
typeToLean :: Type -> Either Text Text
typeToLean TInt  = Right "Int"
typeToLean TBool = Right "Bool"
typeToLean t     = Left ("unsupported type outside the demo fragment: " <> T.pack (show t))

-- | Render an integer literal, parenthesizing negatives so Lean parses them as
-- terms rather than as a subtraction fragment.
litIntLean :: Integer -> Text
litIntLean n
  | n < 0     = "(" <> T.pack (show n) <> ")"
  | otherwise = T.pack (show n)

-- | Sanitize an LLMLL name for Lean 4 (hyphens → underscores).
sanitizeName :: Name -> Text
sanitizeName = T.replace "-" "_"
