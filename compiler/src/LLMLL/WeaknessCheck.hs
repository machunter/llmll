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
--
-- LT-CDP (v0.11): the legacy 5-enumerator catalog used by '--weakness-check'
-- is preserved verbatim through 'generateWeaknessCandidates'; the new
-- 'generateCDPCandidates' returns the closed v0.11 enumeration per
-- 'docs/design/contract-discriminative-power-proposal.md' §4.3.1 (small ints,
-- both bools, "" and "a", list-singletons, Success / Error sums, pair
-- defaults). Both functions share 'WeaknessCandidate' so the downstream
-- 'emitFixpoint' / solver loop is identical.

module LLMLL.WeaknessCheck
  ( -- * Types
    WeaknessCandidate(..)
  , TrivialBody(..)
    -- * Core API
  , generateWeaknessCandidates
    -- * LT-CDP (v0.11) — closed enumeration per proposal §4.3.1
  , generateCDPCandidates
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, catMaybes)

import LLMLL.Syntax
import LLMLL.TypeCheck (typeCheck, builtinEnv)
import LLMLL.Diagnostic (Diagnostic(..), Severity(..), DiagnosticReport(..))

-- ---------------------------------------------------------------------------
-- Trivial Body Catalog
-- ---------------------------------------------------------------------------

-- | Classification of trivial body strategies. LT-CDP (v0.11): the parameter-
-- carrying constructors subsume the legacy zero-argument ones — 'TrivConstInt
-- 0' is the v0.10 'TrivConstZero', 'TrivConstString ""' is 'TrivConstEmptyStr',
-- 'TrivConstBool True' is 'TrivConstTrue'. The legacy 'generateWeaknessCandidates'
-- catalog yields exactly the five v0.10 shapes; the new 'generateCDPCandidates'
-- catalog widens to the proposal §4.3.1 closed enumeration.
data TrivialBody
  = TrivIdentity Name           -- ^ return a parameter unchanged: (lambda [p] p)
  | TrivConstInt Integer        -- ^ return literal int (0, 1, -1, 42)
  | TrivConstString Text        -- ^ return literal string ("", "a")
  | TrivConstBool Bool          -- ^ return literal bool (true, false)
  | TrivConstEmptyList          -- ^ (list-empty) — polymorphic empty list
  | TrivConstListSingle Type    -- ^ single-element list with type default
  | TrivConstSuccess Type       -- ^ Success wrapping the payload-type default
  | TrivConstError              -- ^ Error "default"
  | TrivConstPair Type Type     -- ^ pair of element-type defaults
  deriving (Show, Eq)

-- | Human-readable label for a trivial body.
trivialLabel :: TrivialBody -> Text
trivialLabel (TrivIdentity p)        = "(lambda [" <> p <> "] " <> p <> ")"
trivialLabel (TrivConstInt n)        = "(lambda [...] " <> T.pack (show n) <> ")"
trivialLabel (TrivConstString s)     = "(lambda [...] \"" <> s <> "\")"
trivialLabel (TrivConstBool True)    = "(lambda [...] true)"
trivialLabel (TrivConstBool False)   = "(lambda [...] false)"
trivialLabel TrivConstEmptyList      = "(lambda [...] (list-empty))"
trivialLabel (TrivConstListSingle t) =
  "(lambda [...] (list-cons " <> defaultLabel t <> " (list-empty)))"
trivialLabel (TrivConstSuccess t)    =
  "(lambda [...] (Success " <> defaultLabel t <> "))"
trivialLabel TrivConstError          = "(lambda [...] (Error \"default\"))"
trivialLabel (TrivConstPair a b)     =
  "(lambda [...] (pair " <> defaultLabel a <> " " <> defaultLabel b <> "))"

-- | Construct the AST expression for a trivial body. The list-singleton, sum,
-- and pair forms reduce to combinations of the base-type defaults.
trivialExpr :: TrivialBody -> Expr
trivialExpr (TrivIdentity p)        = EVar p
trivialExpr (TrivConstInt n)        = ELit (LitInt n)
trivialExpr (TrivConstString s)     = ELit (LitString s)
trivialExpr (TrivConstBool b)       = ELit (LitBool b)
trivialExpr TrivConstEmptyList      = EApp "list-empty" []
trivialExpr (TrivConstListSingle t) =
  EApp "list-cons" [defaultExpr t, EApp "list-empty" []]
trivialExpr (TrivConstSuccess t)    = EApp "Success" [defaultExpr t]
trivialExpr TrivConstError          = EApp "Error" [ELit (LitString "default")]
trivialExpr (TrivConstPair a b)     = EApp "pair" [defaultExpr a, defaultExpr b]

-- | Canonical default expression for a base type. Used to seed list-singleton,
-- Success-payload, and pair constructors per proposal §4.3.1.
defaultExpr :: Type -> Expr
defaultExpr TInt    = ELit (LitInt 0)
defaultExpr TString = ELit (LitString "")
defaultExpr TBool   = ELit (LitBool True)
defaultExpr TUnit   = ELit LitUnit
defaultExpr _       = ELit (LitInt 0)  -- fallback; type-checker filters at tryCandidate

-- | Human-readable form of the canonical default for a type.
defaultLabel :: Type -> Text
defaultLabel TInt    = "0"
defaultLabel TString = "\"\""
defaultLabel TBool   = "true"
defaultLabel TUnit   = "unit"
defaultLabel t       = "/* default-for-" <> typeLabel t <> " */"

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
-- Core API — Legacy --weakness-check (v0.10 catalog, unchanged)
-- ---------------------------------------------------------------------------

-- | For each contracted function in the statement list, generate type-safe
-- trivial body candidates from the legacy v0.10 catalog (identity, 0, \"\", true,
-- empty-list). LT-CDP (v0.11) extends this via 'generateCDPCandidates';
-- '--weakness-check' continues to use this function so its diagnostic surface
-- does not change.
--
-- Algorithm:
--   1. Extract functions with contracts (pre/post)
--   2. For each function, generate the trivial body catalog
--   3. Type-check each synthetic statement (INV-4)
--   4. Keep only type-safe candidates
generateWeaknessCandidates :: GrammarMode -> [Statement] -> [WeaknessCandidate]
generateWeaknessCandidates gm stmts = concatMap (generateForStmt gm stmts legacyCatalog) stmts

-- | LT-CDP (v0.11) — closed candidate enumeration per
-- 'contract-discriminative-power-proposal.md' §4.3.1. Same per-function
-- contract-and-typecheck workflow as 'generateWeaknessCandidates'; the
-- catalog is the widened set that drives the counted DP measurement.
generateCDPCandidates :: GrammarMode -> [Statement] -> [WeaknessCandidate]
generateCDPCandidates gm stmts = concatMap (generateForStmt gm stmts cdpCatalog) stmts

-- | Walk one statement and produce candidates per the supplied catalog
-- builder. Statements without contracts produce no candidates.
-- The full statement list is threaded through so that 'tryCandidate' can
-- include module-level type-alias definitions in the synthetic type-check
-- (F-006: functions with custom-type-alias params produced zero candidates
-- because the alias was absent from the synthetic check's tcAliasMap).
generateForStmt
  :: GrammarMode
  -> [Statement]
  -> ([(Name, Type)] -> Maybe Type -> [TrivialBody])
  -> Statement
  -> [WeaknessCandidate]
generateForStmt gm allStmts catalog (SDefLogic name params mRet contract _body)
  | hasContracts contract =
      mapMaybe (tryCandidate gm allStmts name params mRet contract) (catalog params mRet)
generateForStmt gm allStmts catalog (SLetrec name params mRet contract _dec _body)
  | hasContracts contract =
      mapMaybe (tryCandidate gm allStmts name params mRet contract) (catalog params mRet)
-- LT-INV (v0.11): SDef and SDefShell contribute to weakness check identically.
generateForStmt gm allStmts catalog (SDef name params mRet contract _body)
  | hasContracts contract =
      mapMaybe (tryCandidate gm allStmts name params mRet contract) (catalog params mRet)
generateForStmt gm allStmts catalog (SDefShell name params mRet contract _body)
  | hasContracts contract =
      mapMaybe (tryCandidate gm allStmts name params mRet contract) (catalog params mRet)
generateForStmt _ _ _ _ = []

-- | Does this contract have at least one clause?
hasContracts :: Contract -> Bool
hasContracts (Contract pre _ post _ _) = pre /= Nothing || post /= Nothing

-- ---------------------------------------------------------------------------
-- Catalog builders
-- ---------------------------------------------------------------------------

-- | v0.10 legacy catalog: identity over each param + (0 :: Int) + ("" :: String) +
-- (true :: Bool) + (list-empty :: list[_]).
legacyCatalog :: [(Name, Type)] -> Maybe Type -> [TrivialBody]
legacyCatalog params mRet =
  let identities = [TrivIdentity p | (p, pTy) <- params, matchesReturn pTy mRet]
      constants  = catMaybes
        [ if matchesReturnType TInt mRet    then Just (TrivConstInt 0)        else Nothing
        , if matchesReturnType TString mRet then Just (TrivConstString "")    else Nothing
        , if matchesReturnType TBool mRet   then Just (TrivConstBool True)    else Nothing
        , if matchesReturnList mRet         then Just TrivConstEmptyList      else Nothing
        ]
  in identities ++ constants

-- | LT-CDP (v0.11) extended catalog per proposal §4.3.1. The set is closed —
-- v0.12+ may widen to LLM-generated candidates per
-- 'docs/design/invariant-discovery-review.md' §5; v0.11 ships this exact list
-- and the trust-report 'basis' field is "observational-candidate-set".
--
-- F-005 ancillary: when 'mRet' is 'Nothing' (sexp-parsed functions never carry
-- a return-type annotation — see Parser.hs:169), constants are generated
-- optimistically and 'tryCandidate''s type-check filters the incompatible ones.
-- 'legacyCatalog' is unaffected; only this function uses
-- 'matchesReturnTypeOrUnknown'.
cdpCatalog :: [(Name, Type)] -> Maybe Type -> [TrivialBody]
cdpCatalog params mRet =
  let identities = [TrivIdentity p | (p, pTy) <- params, matchesReturn pTy mRet]
      ints = if matchesReturnTypeOrUnknown TInt mRet
                then map TrivConstInt [0, 1, -1, 42]
                else []
      bools = if matchesReturnTypeOrUnknown TBool mRet
                then [TrivConstBool True, TrivConstBool False]
                else []
      strings = if matchesReturnTypeOrUnknown TString mRet
                  then map TrivConstString ["", "a"]
                  else []
      lists = case mRet of
        Just (TList elt) -> [TrivConstEmptyList, TrivConstListSingle elt]
        Nothing          -> [TrivConstEmptyList]  -- polymorphic; TC filters
        _                -> []
      sums = case mRet of
        Just (TResult okT _) -> [TrivConstSuccess okT, TrivConstError]
        Nothing              -> [TrivConstError]  -- payload-free form; TC filters
        _                    -> []
      pairs = case mRet of
        Just (TPair a b) -> [TrivConstPair a b]
        _                -> []
  in identities ++ ints ++ bools ++ strings ++ lists ++ sums ++ pairs

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

-- | For the CDP catalog only: True when the return type is unannotated
-- ('mRet = Nothing') OR structurally compatible with the given type.
-- Generates candidates optimistically when the return type is unknown;
-- 'tryCandidate''s type-check filters incompatible ones before the solver.
-- Does NOT affect 'legacyCatalog' (which uses the stricter 'matchesReturnType').
matchesReturnTypeOrUnknown :: Type -> Maybe Type -> Bool
matchesReturnTypeOrUnknown _ Nothing     = True
matchesReturnTypeOrUnknown t (Just retTy) = compatibleTypes t retTy

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
  :: GrammarMode
  -> [Statement]
  -> Name
  -> [(Name, Type)]
  -> Maybe Type
  -> Contract
  -> TrivialBody
  -> Maybe WeaknessCandidate
tryCandidate gm allStmts name params mRet contract trivBody =
  let syntheticBody = trivialExpr trivBody
      syntheticStmt = SDefLogic
        ("__weakness_check_" <> name)
        params
        mRet
        contract
        syntheticBody
      -- INV-4: Type-check the synthetic statement.
      -- Prepend STypeDef statements from the calling module so that
      -- checkStatements populates tcAliasMap with any custom type aliases
      -- (e.g. PositiveInt) referenced in the contract or parameter list.
      -- Without this, expandAlias returns TCustom X unexpanded and
      -- structuralUnify emits a false type-mismatch error on the
      -- pre-condition, filtering every candidate (F-006).
      typeDefs = [s | s@STypeDef{} <- allStmts]
      report = typeCheck gm builtinEnv (typeDefs ++ [syntheticStmt])
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
