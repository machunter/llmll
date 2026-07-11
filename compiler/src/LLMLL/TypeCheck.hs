-- |
-- Module      : LLMLL.TypeCheck
-- Description : Bidirectional type checker for LLMLL v0.1.
--
-- Implements a simple bidirectional type checker that:
--   * Builds a type environment from top-level definitions
--   * Infers types for expressions bottom-up
--   * Checks types top-down against annotations
--   * Validates pre/post contract expressions are boolean
--   * Reports structured diagnostics for each error
--
-- Dependent types (TDependent) are partially supported: the constraint
-- expression is well-formedness checked but not evaluated at compile time.
module LLMLL.TypeCheck
  ( -- * Entry Points (GrammarMode is always the first argument)
    typeCheck
  , typeCheckModule
  , typeCheckWithCache
  , typeCheckStrict
  , typeCheckStrictWithCache
  , typeCheckStrictWithCacheAndStatus  -- ADMIT-VERIFIED (Option 2, seam 6)
  , runSketch
    -- * Environment
  , TypeEnv
  , builtinEnv
  , emptyEnv
  , seedCacheEnv   -- XMOD-SCOPE-BRIEF: qualified cache exports into a TypeEnv
  , extendEnv
    -- * Results
  , TypeCheckResult(..)
  , SketchResult(..)
  , SketchHole(..)
  , HoleStatus(..)
    -- * v0.3.5: Scope provenance for context-aware checkout (Phase C)
  , ScopeSource(..)
  , ScopeBinding(..)
    -- * v0.4: Invariant pattern registry (re-export)
  , InvariantSuggestion(..)
    -- * v0.5: U-Full internal exports (for direct unit testing)
  , structuralUnify
  , runTC
  , occursIn
  , TC
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, fromMaybe)
import Data.List (nub, (\\))
import qualified Data.Set as Set
import Control.Monad (forM_, forM, foldM, when, unless, void)
import LLMLL.InvariantRegistry (InvariantPattern, InvariantSuggestion(..), matchPatterns)
import Control.Monad.State.Strict

import LLMLL.Syntax
import LLMLL.Diagnostic
import LLMLL.HoleAnalysis (isNonLinear, buildCallGraph)
import Data.Graph (stronglyConnComp, SCC(..))

-- ---------------------------------------------------------------------------
-- Type Environment
-- ---------------------------------------------------------------------------

-- | Maps names to their types.
type TypeEnv = Map Name Type

-- | Built-in operators and stdlib functions, always in scope (LLMLL.md §13).
-- TVar "a" / TVar "b" stand for polymorphic type parameters;
-- compatibleWith (TVar _) _ = True so they unify with anything.
builtinEnv :: TypeEnv
builtinEnv = Map.fromList $
  -- §13.1 Arithmetic operators
  [ ("+",   TFn [TInt, TInt] TInt)
  , ("-",   TFn [TInt, TInt] TInt)
  , ("*",   TFn [TInt, TInt] TInt)
  , ("/",   TFn [TInt, TInt] TInt)
  , ("mod", TFn [TInt, TInt] TInt)
  -- §13.2 Comparison & equality (polymorphic — TVar matches any type)
  , ("=",   TFn [TVar "a", TVar "a"] TBool)
  , ("!=",  TFn [TVar "a", TVar "a"] TBool)
  , ("<",   TFn [TInt, TInt] TBool)
  , (">",   TFn [TInt, TInt] TBool)
  , ("<=",  TFn [TInt, TInt] TBool)
  , (">=",  TFn [TInt, TInt] TBool)
  -- §13.3 Logic
  , ("and", TFn [TBool, TBool] TBool)
  , ("or",  TFn [TBool, TBool] TBool)
  , ("not", TFn [TBool] TBool)
  , ("=>",  TFn [TBool, TBool] TBool)   -- IMPL-SUGAR: implication (bool → bool → bool)
  , ("<=>", TFn [TBool, TBool] TBool)   -- IMPL-SUGAR: biconditional
  -- §13.4 Pair / record
  -- U2-lite (v0.4): first/second retyped to require TPair argument.
  -- Before U-lite, these used TVar "p" (any type) because the checker couldn't
  -- express the pair constraint. With per-call-site substitution, TPair a b works.
  , ("pair",   TFn [TVar "a", TVar "b"] (TPair (TVar "a") (TVar "b")))
  , ("first",  TFn [TPair (TVar "a") (TVar "b")] (TVar "a"))
  , ("second", TFn [TPair (TVar "a") (TVar "b")] (TVar "b"))
  -- §13.5 List operations
  , ("list-empty",    TFn [] (TList (TVar "a")))
  , ("list-append",   TFn [TList (TVar "a"), TVar "a"] (TList (TVar "a")))
  , ("list-prepend",  TFn [TVar "a", TList (TVar "a")] (TList (TVar "a")))
  , ("list-contains", TFn [TList (TVar "a"), TVar "a"] TBool)
  , ("list-length",   TFn [TList (TVar "a")] TInt)
  , ("list-head",     TFn [TList (TVar "a")] (TResult (TVar "a") TString))
  , ("list-tail",     TFn [TList (TVar "a")] (TResult (TList (TVar "a")) TString))
  , ("list-map",      TFn [TList (TVar "a"), TFn [TVar "a"] (TVar "b")] (TList (TVar "b")))
  , ("list-filter",   TFn [TList (TVar "a"), TFn [TVar "a"] TBool] (TList (TVar "a")))
  , ("list-fold",     TFn [TList (TVar "a"), TVar "b", TFn [TVar "b", TVar "a"] (TVar "b")] (TVar "b"))
  , ("list-nth",      TFn [TList (TVar "a"), TInt] (TResult (TVar "a") TString))
  , ("range",         TFn [TInt, TInt] (TList TInt))
  -- §13.6 String operations
  , ("string-length",   TFn [TString] TInt)
  , ("string-contains", TFn [TString, TString] TBool)
  , ("string-concat",   TFn [TString, TString] TString)
  , ("string-slice",    TFn [TString, TInt, TInt] TString)
  , ("string-char-at",  TFn [TString, TInt] TString)
  , ("string-split",    TFn [TString, TString] (TList TString))
  , ("string-trim",     TFn [TString] TString)
  , ("string-concat-many", TFn [TList TString] TString)
  , ("regex-match",     TFn [TString, TString] TBool)
  , ("string-empty?",   TFn [TString] TBool)
  -- §13.7 Numeric utilities
  , ("int-to-string",  TFn [TInt] TString)
  , ("string-to-int",  TFn [TString] (TResult TInt TString))
  , ("abs",            TFn [TInt] TInt)
  , ("min",            TFn [TInt, TInt] TInt)
  , ("max",            TFn [TInt, TInt] TInt)
  -- §13.8 Result helpers
  , ("ok",         TFn [TVar "a"] (TResult (TVar "a") (TVar "e")))
  , ("err",        TFn [TVar "e"] (TResult (TVar "a") (TVar "e")))
  , ("is-ok",      TFn [TResult (TVar "a") (TVar "e")] TBool)
  , ("unwrap",     TFn [TResult (TVar "a") (TVar "e")] (TVar "a"))
  , ("unwrap-or",  TFn [TResult (TVar "a") (TVar "e"), TVar "a"] (TVar "a"))
  -- §13.9 Standard command constructors (require capability imports, but sigs are known)
  , ("wasi.io.stdout",     TFn [TString] (TCustom "Command"))
  , ("wasi.io.stderr",     TFn [TString] (TCustom "Command"))
  , ("wasi.http.response", TFn [TInt, TString] (TCustom "Command"))
  , ("wasi.http.post",     TFn [TString, TString] (TCustom "Command"))
  , ("wasi.fs.read",       TFn [TString] (TCustom "Command"))
  , ("wasi.fs.write",      TFn [TString, TString] (TCustom "Command"))
  , ("wasi.fs.delete",     TFn [TString] (TCustom "Command"))
  , ("seq-commands",       TFn [TCustom "Command", TCustom "Command"] (TCustom "Command"))
  -- §13.11 Cryptographic operations (v0.6.1)
  -- Opaque primitives backed by real Haskell crypto in preamble.
  -- Correctness is outside the decidable fragment — classified as Asserted.
  , ("hmac-sha1",          TFn [TBytes 20, TBytes 20] (TBytes 20))
  , ("sha1",               TFn [TBytes 20] (TBytes 20))
  ]

emptyEnv :: TypeEnv
emptyEnv = builtinEnv

-- | Seed a TypeEnv with every cache module's exports under their qualified
-- names ('lib.double'). The statement walk's SOpen handler then adds bare
-- aliases (with 'SrcOpenImport' provenance) for '(open ...)'-ed modules —
-- qualified names must be present FIRST for that injection to find them.
-- Shared by the sketch paths ('typecheck --sketch' and the checkout brief,
-- XMOD-SCOPE-BRIEF) so both see the same cross-module scope.
seedCacheEnv :: TypeEnv -> ModuleCache -> TypeEnv
seedCacheEnv = Map.foldlWithKey' seedOne
  where
    seedOne acc path menv =
      let prefix = T.intercalate "." path <> "."
      in Map.union (Map.mapKeys (prefix <>) (meExports menv)) acc

extendEnv :: Name -> Type -> TypeEnv -> TypeEnv
extendEnv = Map.insert

-- ---------------------------------------------------------------------------
-- Sketch Mode Types (Phase 2c)
-- ---------------------------------------------------------------------------

-- | Status of a named hole after sketch inference.
data HoleStatus
  = HoleTyped Type          -- ^ constraint successfully resolved to a concrete type
  | HoleAmbiguous Type Type -- ^ conflicting constraints (first vs second observed)
  | HoleUnknown             -- ^ no constraint reached this hole
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- v0.3.5: Scope provenance for context-aware checkout (Phase C)
-- ---------------------------------------------------------------------------

-- | Classification of where a scope binding originated.
-- The Ord instance gives truncation priority: lower ordinal = higher priority
-- = truncated last. SrcParam < SrcLetBinding < SrcMatchArm < SrcOpenImport.
data ScopeSource
  = SrcParam
  | SrcLetBinding
  | SrcMatchArm
  | SrcOpenImport
  deriving (Show, Eq, Ord)

-- | A binding in the typing environment with its provenance tag.
data ScopeBinding = ScopeBinding
  { sbType   :: Type
  , sbSource :: ScopeSource
  , sbDef    :: Maybe Expr   -- ^ OBLIG-1 v2a: the RHS expr for a let-binding
                             -- ('SrcLetBinding'), for surfacing the definitional
                             -- equality (= y e); 'Nothing' for params/match-arms.
  } deriving (Show, Eq)

-- | A named hole with its inferred status, RFC 6901 JSON Pointer location,
-- and the local typing context (Γ delta) captured at the hole site.
data SketchHole = SketchHole
  { shName    :: Name       -- ^ hole name with \"?\" prefix (e.g. \"?win_message\")
  , shStatus  :: HoleStatus
  , shPointer :: Text       -- ^ RFC 6901 JSON Pointer (e.g. \"/statements/3/body/else\")
  , shEnv     :: Map Name ScopeBinding  -- ^ v0.3.5: Γ delta (tcEnv \\ builtinEnv) with provenance
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Type Checker Monad
-- ---------------------------------------------------------------------------

data TCState = TCState
  { tcEnv          :: TypeEnv
  , tcErrors       :: [Diagnostic]
  , tcAliasMap     :: Map Name Type   -- ^ alias name → structural body (from STypeDef)
  , tcCurrentFn    :: Maybe Name      -- ^ enclosing def-logic/letrec name
  , tcIsLetrec     :: Bool            -- ^ True when inside a letrec (has explicit :decreases)
  -- Sketch mode (Phase 2c --sketch)
  , tcSketchMode   :: Bool            -- ^ True when called from runSketch
  , tcHoles        :: [SketchHole]    -- ^ accumulator (prepend; reversed at runSketch exit)
  , tcPointerStack :: [Text]          -- ^ RFC 6901 pointer segments; [] in check mode (D4)
  -- v0.3: Stratified verification trust-gap tracking
  , tcContractStatus :: Map Name ContractStatus  -- ^ imported function → contract status
  , tcTrusts         :: Map Name DisplayLevel -- ^ acknowledged trust declarations
  -- v0.3.5: Scope provenance tracking (Phase C)
  , tcProvenance     :: Map Name ScopeSource  -- ^ per-binding source classification for checkout context
  -- v0.4: CAP-1 capability enforcement
  , tcModuleStmts    :: [Statement]  -- ^ module's top-level statements, for capability import checks
  -- v0.6.3: strict mode for build/run/verify (BUG-4)
  , tcStrictMode     :: Bool         -- ^ True when unbound vars / unknown fns are hard errors
  -- LT-INV (v0.11): core/shell grammar mode
  , tcGrammarMode    :: GrammarMode  -- ^ active grammar mode, set by the caller
  , tcCoreMode       :: Bool         -- ^ True while type-checking inside a strict-core SDef body
  -- BUG-3 (v0.14.3): monotonic counter for freshening a callee's polymorphic
  -- TVars at each call site (see freshenFnType). Without this, two unrelated
  -- instantiations of the same builtin signature -- or a builtin's TVar and
  -- an unrelated user-inferred TVar that escaped its per-call-site scope
  -- (e.g. an unannotated empty list literal, `TList (TVar "a")`, carried
  -- through the type environment) -- can coincidentally share a bare name
  -- like "a", and structuralUnify's occurs check (occursIn, string-equality
  -- on TVar names) fires a false "infinite type" on the coincidence alone.
  , tcTVarCounter    :: Int
  , tcDefs           :: Map Name Expr  -- ^ OBLIG-1 v2a: let-binding name → RHS,
                                       -- threaded like 'tcProvenance' so a hole's
                                       -- 'shEnv' can carry each let-binding's
                                       -- defining expression (for (= y e)).
  } deriving (Show)

type TC a = State TCState a

-- | Emit a type error.
tcError :: Text -> TC ()
tcError msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkError Nothing msg] }

-- | Emit a hole-sensitive type error (holeSensitive = True).
-- Used in unify when at least one type is a hole variable.
tcErrorHS :: Text -> TC ()
tcErrorHS msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [(mkError Nothing msg) { diagHoleSensitive = True }] }

-- | Emit a structured type-mismatch error with expected/got fields.
-- holeSensitive is set if either type is a hole variable (D3).
-- When typeLabel produces identical strings for structurally different types,
-- the constructor name is appended to disambiguate (e.g. "DelegationError (built-in)").
tcTypeMismatch :: Text -> Type -> Type -> TC ()
tcTypeMismatch ctx expected actual = modify $ \s -> s
  { tcErrors = tcErrors s ++
      [ (mkError Nothing msg)
          { diagKind          = Just "type-mismatch"
          , diagExpected      = Just expLabel
          , diagGot           = Just actLabel
          , diagHoleSensitive = isHoleSensitive expected actual
          } ] }
  where
    expBase = typeLabel expected
    actBase = typeLabel actual
    -- When labels are identical but types differ structurally,
    -- disambiguate with the internal constructor name.
    (expLabel, actLabel)
      | expBase == actBase && expected /= actual
      = (expBase <> " (" <> typeConstructorName expected <> ")"
        ,actBase <> " (" <> typeConstructorName actual   <> ")")
      | otherwise = (expBase, actBase)
    msg = "type mismatch in '" <> ctx <> "': expected " <> expLabel
            <> ", got " <> actLabel

-- | True if a type is a hole variable (TVar with "?" prefix).
isHoleVar :: Type -> Bool
isHoleVar (TVar n) = "?" `T.isPrefixOf` n
isHoleVar _        = False

-- | True if either type is a hole variable — signals that a unification
-- failure may disappear once the hole resolves (D3).
isHoleSensitive :: Type -> Type -> Bool
isHoleSensitive t1 t2 = isHoleVar t1 || isHoleVar t2

-- | Emit a type warning.
tcWarn :: Text -> TC ()
tcWarn msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkWarning Nothing msg] }

-- | v0.6.3: Emit a warning in permissive mode, or an error in strict mode (BUG-4).
tcWarnOrError :: Text -> TC ()
tcWarnOrError msg = do
  strict <- gets tcStrictMode
  if strict then tcError msg else tcWarn msg

-- | Look up a name in the environment.
tcLookup :: Name -> TC (Maybe Type)
tcLookup name = gets (Map.lookup name . tcEnv)

-- | Insert a binding into the current environment (persistent within this monad run).
tcInsert :: Name -> Type -> TC ()
tcInsert name ty = modify $ \s -> s { tcEnv = Map.insert name ty (tcEnv s) }

-- | Run a computation in an extended environment.
withEnv :: [(Name, Type)] -> TC a -> TC a
withEnv bindings action = do
  old <- gets tcEnv
  modify $ \s -> s { tcEnv = foldr (uncurry Map.insert) old bindings }
  result <- action
  modify $ \s -> s { tcEnv = old }
  pure result

-- | v0.3.5 (Phase C): Run a computation in an extended environment,
-- also recording provenance tags for context-aware checkout.
-- Provenance is scope-restoring: tags pushed here are popped on exit.
withTaggedEnv :: ScopeSource -> [(Name, Type)] -> TC a -> TC a
withTaggedEnv source bindings action = do
  oldEnv <- gets tcEnv
  oldProv <- gets tcProvenance
  let newProv = foldr (\(n, _) acc -> Map.insert n source acc) oldProv bindings
  modify $ \s -> s
    { tcEnv = foldr (uncurry Map.insert) oldEnv bindings
    , tcProvenance = newProv
    }
  result <- action
  modify $ \s -> s { tcEnv = oldEnv, tcProvenance = oldProv }
  pure result

-- | OBLIG-1 v2a: record let-binding name→RHS for the duration of an action (the
-- let body), so a hole inside it captures each binding's defining expression in
-- its 'shEnv'. Saves/restores 'tcDefs' exactly as 'withTaggedEnv' does
-- 'tcProvenance', so a binding's RHS never leaks to a sibling scope.
withDefs :: [(Name, Expr)] -> TC a -> TC a
withDefs defs action = do
  oldDefs <- gets tcDefs
  modify $ \s -> s { tcDefs = foldr (\(n, e) acc -> Map.insert n e acc) oldDefs defs }
  result <- action
  modify $ \s -> s { tcDefs = oldDefs }
  pure result

-- | Run a computation in a function-scope context.
-- Sets tcCurrentFn and tcIsLetrec for the duration of the action,
-- then restores the previous values on exit.  Mirrors withTaggedEnv.
withFunctionContext :: Name -> Bool -> TC a -> TC a
withFunctionContext name isLetrec action = do
  oldFn  <- gets tcCurrentFn
  oldLet <- gets tcIsLetrec
  modify $ \s -> s { tcCurrentFn = Just name, tcIsLetrec = isLetrec }
  result <- action
  modify $ \s -> s { tcCurrentFn = oldFn, tcIsLetrec = oldLet }
  pure result

-- | LT-INV (v0.11): enter strict-core checking scope, restoring on exit.
-- Patterned on withFunctionContext — safe under State-accumulates-errors discipline.
withCoreMode :: TC a -> TC a
withCoreMode action = do
  old <- gets tcCoreMode
  modify $ \s -> s { tcCoreMode = True }
  result <- action
  modify $ \s -> s { tcCoreMode = old }
  pure result

-- | LT-INV (v0.11): prelude functions unconditionally admitted inside SDef bodies.
-- These are pure, well-typed builtins with no side-effects; no body-faithful VC required.
trustedPrelude :: Set.Set Name
trustedPrelude = Set.fromList
  [ "string-length", "string-concat", "list-head", "list-tail"
  , "list-length", "list-is-empty?", "pair", "first", "second"
  , "random-int", "int-to-string"
  ]

-- | LT-INV (v0.11): under core mode, verify a callee is body-faithful or trusted-prelude.
-- Emits a CoreMembershipViolation error when neither condition holds.
--
-- ADMIT-VERIFIED (Option 2): a 4th admission leg — a callee carrying a
-- persisted, hash-valid, fully-verified 'EvidenceRecord' in 'tcContractStatus'.
-- The record is admissible only on the FULL conjunction (soundness (ii)):
--   isVerifiedLevel(erDisplayLevel) ∧ erBodyFaithful ∧ ¬erOverflowTainted
--   ∧ erVerifiedHash present (≡ hash-valid, see below) ∧ fragment-pure.
-- This is the same conjunction '--strict-verified-core' enforces; a bare
-- 'erBodyFaithful' would let overflow-tainted / escape-discharged / runtime-
-- fallback verdicts through.
--
-- HASH-VALIDITY (soundness (iii)+(iv)): 'tcContractStatus' is seeded from
-- persisted sidecars (seams 5/6) only AFTER 'downgradeStaleVerifiedSidecar'
-- has run, which clears 'erVerifiedHash' to 'Nothing' (and drops
-- 'erBodyFaithful') on any record whose hash is absent or drifted. So a record
-- here that still carries 'erVerifiedHash = Just _' is hash-valid by
-- construction, and a 'Nothing' hash fails the conjunction below — fail-closed
-- on an unguarded / pre-ADMIT-VERIFIED sidecar.
--
-- FRAGMENT-PURITY: a 'DLVerified True' verdict is stamped only on a
-- body-faithful QF-LIA SAFE result (FixpointEmit body VC); the '¬tainted'
-- conjunct excludes the one unbounded-Int escape. No record reaches this leg
-- with a non-QF-LIA body-faithful claim.
checkCalleeAdmissibility :: Name -> TC ()
checkCalleeAdmissibility func = do
  inCore <- gets tcCoreMode
  when inCore $ do
    csMap <- gets tcContractStatus
    -- ADMIT-VERIFIED (soundness (ii)): the persisted-evidence leg REPLACES the
    -- prior bare-'erBodyFaithful' leg. During the strict-core type-check gate,
    -- everything in 'tcContractStatus' is persisted/validated evidence (imported
    -- modules + the entry-file warm seed); there is no in-pass "fresh" evidence
    -- channel here (verification runs after type-check). A bare 'erBodyFaithful'
    -- test would admit overflow-tainted / escape-discharged / runtime-fallback /
    -- hash-absent verdicts. So we admit ONLY on the full conjunction.
    -- REC-DESCENT Phase 3 (b1): a RECURSIVE callee (a cyclic call-graph SCC
    -- member) is admissible into strict-core ONLY when its persisted post
    -- evidence is descent-discharged ('erTerminationVerified'). This closes the
    -- gap where a verified-but-measureless recursive 'def-shell' callee reached
    -- the total-correctness strict core on partial-correctness evidence, and
    -- delivers the lift: a discharged recursive callee (carrying the bit in its
    -- sidecar) is admitted. Non-recursive callees are unaffected.
    stmts <- gets tcModuleStmts
    let recSet = cyclicMembers stmts
        isRec  = func `Set.member` recSet
        recTotal mer = erFullyVerifiedAdmissible mer
                       && maybe False erTerminationVerified mer
        persistedVerified = case Map.lookup func csMap of
          Just cs
            | isRec     -> recTotal (csPost cs)
            | otherwise -> erFullyVerifiedAdmissible (csPre cs)
                           || erFullyVerifiedAdmissible (csPost cs)
          Nothing -> False
        trusted = func `Set.member` trustedPrelude
                  || Map.member func builtinEnv
    am <- gets tcAliasMap   -- COMP-4 (a): admissible-sum constructors are admissible
    unless (persistedVerified || trusted || isAdmissibleConstructor am func) $ do
      enclosing <- gets (maybe "<unknown>" id . tcCurrentFn)
      modify $ \s -> s
        { tcErrors = tcErrors s ++ [mkCoreMembershipViolation enclosing func] }

-- | COMP-4 (a): True iff @func@ is a constructor of an admissible (acyclic-
-- closure) sum type. A recursive datatype (Tree = Node Tree Tree) is excluded so
-- z3's datatype theory stays decidable. Mirrors FixpointEmit.admissibleDatatype
-- — kept local to avoid a TypeCheck→FixpointEmit import; a future refactor shares
-- it via Syntax. Construction of an admissible sum is strict-core-admissible.
isAdmissibleConstructor :: Map.Map Name Type -> Name -> Bool
isAdmissibleConstructor am func =
  or [ go Set.empty (TCustom n)
     | (n, TSumType ctors) <- Map.toList am, func `elem` map fst ctors ]
  where
    go seen t = case sumOf t of
      Nothing -> True
      Just (nm, ctors)
        | nm `Set.member` seen -> False
        | otherwise -> all (go (Set.insert nm seen)) [ pt | (_, Just pt) <- ctors ]
    sumOf t = case t of
      TSumType ctors -> Just ("", ctors)
      TCustom n      -> case Map.lookup n am of
                          Just (TSumType ctors) -> Just (n, ctors)
                          Just other            -> sumOf other
                          Nothing               -> Nothing
      _              -> Nothing

-- | ADMIT-VERIFIED (Option 2): the full-conjunction admissibility predicate for
-- a single clause's evidence. Admit ONLY when the record is verified-level,
-- body-faithful, NOT overflow-tainted, and carries a (hash-valid) persisted
-- 'erVerifiedHash'. 'Nothing' (no clause, or no/absent hash) ⇒ not admissible
-- (fail closed). Never keys off a bare 'erBodyFaithful'.
erFullyVerifiedAdmissible :: Maybe EvidenceRecord -> Bool
erFullyVerifiedAdmissible Nothing   = False
erFullyVerifiedAdmissible (Just er) =
     isVerifiedLevel (erDisplayLevel er)
  && erBodyFaithful er
  && not (erOverflowTainted er)
  && maybe False (const True) (erVerifiedHash er)  -- fail closed on absent hash

-- | REC-DESCENT Phase 3: cyclic call-graph SCC members (the recursive
-- functions). Local mirror of 'ObligationAssembly.recursiveNames', kept here to
-- avoid the TypeCheck→ObligationAssembly import cycle (the same pattern
-- 'TrustReport.cyclicSccMembers' uses).
cyclicMembers :: [Statement] -> Set.Set Name
cyclicMembers stmts =
  let cg   = buildCallGraph stmts
      sccs = stronglyConnComp [(n, n, deps) | (n, deps) <- Map.toList cg]
  in Set.fromList [n | CyclicSCC ns <- sccs, n <- ns]

-- | Emit a structured non-exhaustive-match error using the registered diagnostic.
tcEmitNonExhaustive :: Name -> [Name] -> [Name] -> TC ()
tcEmitNonExhaustive typeName missing covered = do
  fn <- gets (maybe "<top>" id . tcCurrentFn)
  modify $ \s -> s
    { tcErrors = tcErrors s ++ [mkNonExhaustiveMatch fn typeName missing covered] }

-- | Run the type checker monad.
runTC :: GrammarMode -> TypeEnv -> TC a -> (a, [Diagnostic])
runTC gm env action =
  let (result, st) = runState action (TCState env [] Map.empty Nothing False False [] [] Map.empty Map.empty Map.empty [] False gm False 0 Map.empty)
  in (result, tcErrors st)

-- | Run the type checker in sketch mode.
runTCSketch :: GrammarMode -> TypeEnv -> TC a -> (a, TCState)
runTCSketch gm env action =
  runState action (TCState env [] Map.empty Nothing False True [] [] Map.empty Map.empty Map.empty [] False gm False 0 Map.empty)

-- | v0.3: Emit a trust-gap warning if a contract clause is unproven and
-- not covered by a (trust ...) declaration.
emitTrustGap :: Name -> Map Name DisplayLevel -> Maybe DisplayLevel -> TC ()
emitTrustGap _ _ Nothing = pure ()
emitTrustGap _ _ (Just vl) | isSolverBacked vl = pure ()  -- solver-backed: no gap
emitTrustGap func trusts (Just vl) =
  case Map.lookup func trusts of
    Just tl | evidenceCovers tl vl -> pure ()  -- trust level sufficient
    _ -> do
      ptr <- gets tcPointerStack
      let ptrText = "/" <> T.intercalate "/" (reverse ptr)
          levelText = case vl of
            DLAsserted  -> "asserted"
            DLTested _  -> "tested"
            _           -> "unknown"
      modify $ \s -> s { tcErrors = tcErrors s ++ [mkTrustGapWarning func levelText ptrText] }

-- | Push a path segment onto the pointer stack, run action, then pop (D4).
-- Structurally identical to withEnv: push/run/pop.
-- Safe pop guards against underflow on programming errors.
withSegment :: Text -> TC a -> TC a
withSegment seg action = do
  modify $ \s -> s { tcPointerStack = tcPointerStack s ++ [seg] }
  result <- action
  modify $ \s -> s { tcPointerStack =
    case tcPointerStack s of { [] -> []; xs -> init xs } }
  pure result

-- | Reconstruct the RFC 6901 JSON Pointer from the current segment stack.
currentPointer :: TC Text
currentPointer = do
  stack <- gets tcPointerStack
  pure $ "/" <> T.intercalate "/" stack

-- | Record a named hole with its status and local typing context (sketch mode only).
-- v0.3.5 (Phase C): snapshots the env delta (tcEnv \\ builtinEnv) with provenance
-- at the hole site. This is the complete Γ visible to the agent filling this hole.
recordHole :: Name -> HoleStatus -> TC ()
recordHole name status = do
  sketch <- gets tcSketchMode
  when sketch $ do
    ptr <- currentPointer   -- reads tcPointerStack via currentPointer
    -- v0.3.5 C2: snapshot tcEnv delta with provenance
    env <- gets tcEnv
    prov <- gets tcProvenance
    defs <- gets tcDefs
    let delta = Map.difference env builtinEnv
        -- Build ScopeBinding map: join type from env with source from provenance,
        -- and (OBLIG-1 v2a) the let-binding RHS from tcDefs.
        -- Default to SrcLetBinding for bindings without explicit provenance
        -- (e.g. top-level definitions registered in checkStatements).
        scopedDelta = Map.mapWithKey (\k t ->
          ScopeBinding t (Map.findWithDefault SrcLetBinding k prov) (Map.lookup k defs)) delta
    modify $ \s -> s { tcHoles = SketchHole ("?" <> name) status ptr scopedDelta : tcHoles s }

-- | Emit an ambiguous-hole diagnostic to the error accumulator.
emitAmbiguous :: Name -> Type -> Type -> TC ()
emitAmbiguous name t1 t2 = do
  let msg = "conflicting constraints: " <> typeLabel t1 <> " vs " <> typeLabel t2
  modify $ \s -> s { tcErrors = tcErrors s ++
    [(mkError Nothing ("ambiguous-hole \"?" <> name <> "\" — " <> msg))
       { diagKind = Just "ambiguous-hole"
       , diagHole = Just ("?" <> name)
       }] }

-- ---------------------------------------------------------------------------
-- Entry Points
-- ---------------------------------------------------------------------------

-- | Type-check a list of top-level statements.
typeCheck :: GrammarMode -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheck gm env stmts =
  let (_, diags) = runTC gm env (checkStatements stmts)
      hasErrors  = any ((== SevError) . diagSeverity) diags
  in DiagnosticReport
    { reportPhase       = "typecheck"
    , reportDiagnostics = diags
    , reportSuccess     = not hasErrors
    }

-- | Type-check a full Module.
typeCheckModule :: GrammarMode -> TypeEnv -> Module -> DiagnosticReport
typeCheckModule gm env m = typeCheck gm env (moduleBody m)

-- | Type-check with an existing ModuleCache.
-- Seeds the TypeEnv with all qualified names from imported modules before
-- running the standard single-file check. Empty cache = single-file path.
-- v0.3: also seeds tcContractStatus for trust-gap warnings.
typeCheckWithCache :: GrammarMode -> ModuleCache -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckWithCache gm = typeCheckWithCacheMode gm False

-- | v0.6.3: Strict typecheck — unbound vars and unknown fns are hard errors.
typeCheckStrict :: GrammarMode -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckStrict gm env stmts =
  let (_, diags) = runTCStrict gm env (checkStatements stmts)
      hasErrors  = any ((== SevError) . diagSeverity) diags
  in DiagnosticReport
    { reportPhase       = "typecheck"
    , reportDiagnostics = diags
    , reportSuccess     = not hasErrors
    }

runTCStrict :: GrammarMode -> TypeEnv -> TC a -> (a, [Diagnostic])
runTCStrict gm env action =
  let (result, st) = runState action (TCState env [] Map.empty Nothing False False [] [] Map.empty Map.empty Map.empty [] True gm False 0 Map.empty)
  in (result, tcErrors st)

-- | v0.6.3: Strict typecheck with module cache.
typeCheckStrictWithCache :: GrammarMode -> ModuleCache -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckStrictWithCache gm cache = typeCheckWithCacheMode' gm True cache Map.empty

-- | ADMIT-VERIFIED (Option 2, seam 6): strict typecheck variant that also seeds
-- 'tcContractStatus' with the entry file's OWN persisted (bare-keyed)
-- ContractStatus, so the same-file warm path can admit a strict-core
-- 'def'→'def' call whose callee was verified in a prior pass. The caller MUST
-- pass evidence already validated by 'downgradeStaleVerifiedSidecar' (so an
-- absent/stale hash has been demoted before it reaches the admission leg).
-- The entry seed unions OVER the cache-qualified seed (it is the local file's
-- own bare names; there is no key collision with qualified import keys).
typeCheckStrictWithCacheAndStatus
  :: GrammarMode -> ModuleCache -> Map Name ContractStatus -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckStrictWithCacheAndStatus gm = typeCheckWithCacheMode' gm True

-- | Internal: shared implementation for typeCheckWith(Strict)Cache(WithMode).
typeCheckWithCacheMode :: GrammarMode -> Bool -> ModuleCache -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckWithCacheMode gm strict cache = typeCheckWithCacheMode' gm strict cache Map.empty

-- | Internal: as 'typeCheckWithCacheMode', plus an entry-file ContractStatus
-- seed (bare-keyed) unioned into 'tcContractStatus' (ADMIT-VERIFIED seam 6).
typeCheckWithCacheMode'
  :: GrammarMode -> Bool -> ModuleCache -> Map Name ContractStatus -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckWithCacheMode' gm strict cache entryCS baseEnv stmts =
  let -- Inject qualified names from all cached modules
      seededEnv = Map.foldlWithKey' seedModule baseEnv cache
      -- v0.3: merge contract status from all cached modules (qualified names)
      seededCSImports = Map.foldlWithKey' seedStatus Map.empty cache
      -- ADMIT-VERIFIED: the entry file's own bare-keyed evidence wins on a key
      -- clash (it is the live file's verdict).
      seededCS  = Map.union entryCS seededCSImports
      -- XMOD-ALIAS: seed the alias map with imported type aliases (bare-keyed),
      -- so that an imported refinement/dependent alias (e.g. PositiveInt) can be
      -- unfolded to its base type by 'expandAlias' when the importing module does
      -- arithmetic/comparison on a value of that type. Without this, the imported
      -- alias stays an opaque TCustom and '>='/'-' reject it, whereas the same
      -- code in-module type-checks. Type annotations on params are written bare
      -- (regardless of 'open'), so bare keys are the correct form. Local STypeDefs
      -- shadow these in 'checkStatements' (local wins; same direction as 'open').
      seededAliases = Map.foldl seedAliases Map.empty cache
      (_, st) = runState (checkStatements stmts)
        (TCState seededEnv [] seededAliases Nothing False False [] [] seededCS Map.empty Map.empty [] strict gm False 0 Map.empty)
      diags = tcErrors st
      hasErrors = any ((== SevError) . diagSeverity) diags
  in DiagnosticReport
    { reportPhase       = "typecheck"
    , reportDiagnostics = diags
    , reportSuccess     = not hasErrors
    }
  where
    seedModule acc path menv =
      let prefix = T.intercalate "." path <> "."
          qualified = Map.mapKeys (prefix <>) (meExports menv)
      in Map.union qualified acc
    seedStatus acc path menv =
      let prefix = T.intercalate "." path <> "."
          qualified = Map.mapKeys (prefix <>) (meContractStatus menv)
      in Map.union qualified acc
    -- XMOD-ALIAS: imported aliases keyed by their bare name. Left-biased union
    -- over the cache fold makes the first module a colliding name appears in win
    -- (deterministic; same bias as the qualified-name/status seeds above).
    seedAliases acc menv = Map.union (meAliasMap menv) acc

-- ---------------------------------------------------------------------------
-- Statement Checking
-- ---------------------------------------------------------------------------

-- | Build top-level environment from definitions, then check each statement.
checkStatements :: [Statement] -> TC ()
checkStatements stmts = do
  -- First pass: collect all top-level function and type names
  let topLevel  = mapMaybe collectTopLevel stmts
      aliasMap  = Map.fromList [(n, body) | STypeDef n body <- stmts]
      -- v0.3: collect trust declarations into tcTrusts
      trustMap  = Map.fromList [(trustTarget s, trustLevel s) | s@STrust{} <- stmts]
  -- Populate alias map so expandAlias can resolve TCustom aliases in unify.
  -- XMOD-ALIAS: union the current-module aliases OVER any imported aliases that
  -- 'typeCheckWithCacheMode'' pre-seeded into 'tcAliasMap' (local STypeDefs
  -- shadow imports; same direction as 'open'). The single-file path seeds an
  -- empty 'tcAliasMap', so this is a no-op union there.
  -- v0.4 CAP-1: store top-level statements for capability checks in inferExpr
  modify $ \s -> s { tcAliasMap = Map.union aliasMap (tcAliasMap s), tcTrusts = Map.union trustMap (tcTrusts s), tcModuleStmts = stmts }
  -- Fix 3: detect type alias cycles and emit diagnostics.
  -- Self-reference inside TSumType payloads is legitimate recursive-ADT structure,
  -- not an alias cycle (e.g. (type Tree (| Leaf unit | Node Tree)) is valid).
  let collectCustomNames :: Type -> Set.Set Name
      collectCustomNames ty = case ty of
        TCustom n        -> Set.singleton n
        TList a          -> collectCustomNames a
        TMap k v         -> collectCustomNames k <> collectCustomNames v
        TResult a b      -> collectCustomNames a <> collectCustomNames b
        TPair a b        -> collectCustomNames a <> collectCustomNames b
        TPromise a       -> collectCustomNames a
        TFn args ret     -> foldMap collectCustomNames args <> collectCustomNames ret
        TSumType _       -> Set.empty   -- self-reference in constructor payloads is recursion, not a cycle
        TDependent _ b _ -> collectCustomNames b
        _                -> Set.empty
      aliasGraph = Map.map collectCustomNames aliasMap
      -- DFS: returns all names participating in any cycle
      detectCycles :: Set.Set Name
      detectCycles =
        let reachable start = go' Set.empty start
              where
                go' :: Set.Set Name -> Name -> Set.Set Name
                go' visited n
                  | n `Set.member` visited = Set.singleton n
                  | otherwise = case Map.lookup n aliasGraph of
                      Nothing   -> Set.empty
                      Just deps -> foldMap (go' (Set.insert n visited))
                                           (Set.toList (deps `Set.intersection` Map.keysSet aliasMap))
        in foldMap reachable (Map.keys aliasMap)
      cyclicNames = Set.toAscList detectCycles
  forM_ cyclicNames $ \n ->
    tcError $ "type alias cycle involving '" <> n <> "'"
  withEnv topLevel $ do
    -- Register ADT constructors as callable functions (LLMLL.md §3.3).
    let ctorBindings = collectConstructors stmts
    -- Phase 1: intra-module constructor name duplicates.
    let ctorNames = map fst ctorBindings
        dupes = ctorNames \\ nub ctorNames
    forM_ (nub dupes) $ \dupName ->
      tcWarnOrError $ "duplicate constructor name '" <> dupName
                      <> "' within or across type definitions; first definition wins"
    -- Phase 2: constructor/function collisions (value namespace only).
    -- Skip TCustom entries (type names, interface names) — separate namespace.
    forM_ (nub (map fst ctorBindings)) $ \ctorName -> do
      mExisting <- tcLookup ctorName
      case mExisting of
        Just (TCustom _) -> pure ()  -- type/interface name, not value — skip
        Just existingType ->
          tcWarnOrError $ "constructor '" <> ctorName <> "' shadows existing binding of type "
                          <> typeLabel existingType
        Nothing -> pure ()
    withEnv ctorBindings $ do
      -- Second pass: check each statement with its RFC 6901 pointer context.
      -- Each segment is one RFC 6901 token: "statements" and "N" are separate.
      forM_ (zip [0 :: Int ..] stmts) $ \(i, stmt) ->
        withSegment "statements" $ withSegment (tshow i) (checkStatement stmt)

-- | Extract (name, type) for top-level definitions (for forward references).
collectTopLevel :: Statement -> Maybe (Name, Type)
collectTopLevel (SDefLogic name params mRet _contract _body) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet
  in Just (name, TFn argTypes retType)
collectTopLevel (SLetrec name params mRet _contract _dec _body) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet
  in Just (name, TFn argTypes retType)
-- LT-INV (v0.11): strict-core and permissive-shell definitions register identically.
collectTopLevel (SDef name params mRet _contract _body) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet
  in Just (name, TFn argTypes retType)
collectTopLevel (SDefShell name params mRet _contract _body _) =
  let argTypes = map snd params
      retType  = fromMaybe (TVar "?") mRet
  in Just (name, TFn argTypes retType)
-- v0.12.1: def-invariant registers identically to its prior SDefLogic form.
collectTopLevel (SDefInvariant name params mRet contract body) =
  collectTopLevel (SDefLogic name params mRet contract body)
collectTopLevel (SDefInterface name fns _laws) =
  Just (name, TCustom name)  -- interfaces register as custom types
collectTopLevel (STypeDef name body) =
  Just (name, TCustom name)  -- type aliases register as custom types
collectTopLevel _ = Nothing

-- | Extract constructor bindings from sum-type definitions.
-- Each constructor is registered as a callable function in the value namespace
-- (LLMLL.md §3.3: "Use the constructor name as a function call").
-- Returns TCustom typeName — preserves declared type name until alias
-- expansion.  NOTE: nominal identity is future work; compatibleWith
-- (TSumType) compares constructor names only, not payload types.
--
-- SCOPE LIMITATION: single-file only. Cross-module constructor injection
-- must be added when ModuleEnv carries constructor bindings.
collectConstructors :: [Statement] -> [(Name, Type)]
collectConstructors stmts = concatMap go stmts
  where
    go (STypeDef typeName (TSumType ctors)) =
      let retType = TCustom typeName
      in [ case mPayload of
             -- COMP-3b-general: a nullary constructor used bare is a VALUE of the
             -- sum type (not a 0-arg function), so `(= result Established)` and
             -- `(step Closed PassiveOpen)` type-check. Pattern position reads the
             -- constructor off the scrutinee's TSumType, not this binding, so this
             -- does not affect match type-checking. Payload constructors stay
             -- functions (applied as `(Circle r)`).
             Nothing -> (ctor, retType)
             Just pt -> (ctor, TFn [pt] retType)
         | (ctor, mPayload) <- ctors ]
    go _ = []

checkStatement :: Statement -> TC ()
checkStatement (SDefLogic name params mRet contract body) = do
  withFunctionContext name False $ do
    let paramBindings = params
    withTaggedEnv SrcParam paramBindings $ do
      -- Infer body type: push "body" segment for pointer precision
      bodyType <- withSegment "body" (inferExpr body)
      -- Check return type annotation if present
      case mRet of
        Nothing -> pure ()
        Just retTy -> unify name retTy bodyType
      -- Check pre-condition is boolean (result NOT in scope — §4.3)
      case contractPre contract of
        Nothing -> pure ()
        Just pre -> do
          when (exprContainsVar "result" pre) $
            tcError $ "pre condition of '" <> name <> "' references 'result', which is only available in post clauses (§4.3)"
          preType <- inferExpr pre
          preOk <- compatibleExpanded preType TBool
          unless preOk $
            tcError $ "pre condition of '" <> name <> "' must be bool, got " <> typeLabel preType
      -- Check post-condition is boolean (has access to 'result')
      case contractPost contract of
        Nothing -> pure ()
        Just post -> do
          let resultType = fromMaybe bodyType mRet
          postType <- withEnv [("result", resultType)] (inferExpr post)
          postOk <- compatibleExpanded postType TBool
          unless postOk $
            tcError $ "post condition of '" <> name <> "' must be bool, got " <> typeLabel postType

checkStatement (SLetrec name params mRet contract dec body) = do
  withFunctionContext name True $ do
    let paramBindings = params
    withTaggedEnv SrcParam paramBindings $ do
      -- Validate :decreases is integer-typed (QF linear arithmetic restriction)
      decType <- inferExpr dec
      decOk <- compatibleExpanded decType TInt
      unless decOk $
        tcWarn $ "letrec '" <> name <> "': :decreases must be int-typed, got " <> typeLabel decType
      -- Infer body type: push "body" segment for pointer precision
      bodyType <- withSegment "body" (inferExpr body)
      case mRet of
        Nothing -> pure ()
        Just retTy -> unify name retTy bodyType
      -- Check pre-condition (result NOT in scope — §4.3)
      case contractPre contract of
        Nothing -> pure ()
        Just pre -> do
          when (exprContainsVar "result" pre) $
            tcError $ "pre condition of '" <> name <> "' references 'result', which is only available in post clauses (§4.3)"
          preType <- inferExpr pre
          preOk <- compatibleExpanded preType TBool
          unless preOk $
            tcError $ "pre condition of '" <> name <> "' must be bool, got " <> typeLabel preType
      -- Check post-condition
      case contractPost contract of
        Nothing -> pure ()
        Just post -> do
          let resultType = fromMaybe bodyType mRet
          postType <- withEnv [("result", resultType)] (inferExpr post)
          postOk <- compatibleExpanded postType TBool
          unless postOk $
            tcError $ "post condition of '" <> name <> "' must be bool, got " <> typeLabel postType

-- | LT-INV (v0.11): strict-core definition.
-- Activates core mode so that inferExpr/EApp enforces callee admissibility.
-- Also gates on isCoreBodySyntactic before type-inference — structural violations
-- are reported once here rather than as cascading downstream errors.
checkStatement (SDef name params mRet contract body) = do
  unless (isCoreBodySyntactic body) $
    modify $ \s -> s
      { tcErrors = tcErrors s ++
          [mkCoreGrammarViolation name "lambda, do, await, non-linear arithmetic, or unrestricted match"] }
  withFunctionContext name False $ withCoreMode $ do
    withTaggedEnv SrcParam params $ do
      -- REF-META-5 Check-Hole at the return position (§3.4.6): a bare named-hole
      -- body records HoleTyped retTy instead of HoleUnknown. Every other body
      -- keeps infer-then-unify, preserving the name-attributed return mismatch.
      bodyType <- case (mRet, body) of
        (Just retTy, EHole (HNamed _)) -> retTy <$ withSegment "body" (checkExpr body retTy)
        (Just retTy, _)                -> do
          t <- withSegment "body" (inferExpr body)
          unify name retTy t
          pure t
        (Nothing, _)                   -> withSegment "body" (inferExpr body)
      case contractPre contract of
        Nothing -> pure ()
        Just pre -> do
          when (exprContainsVar "result" pre) $
            tcError $ "pre condition of '" <> name <> "' references 'result', which is only available in post clauses (§4.3)"
          preType <- inferExpr pre
          preOk <- compatibleExpanded preType TBool
          unless preOk $
            tcError $ "pre condition of '" <> name <> "' must be bool, got " <> typeLabel preType
      case contractPost contract of
        Nothing -> pure ()
        Just post -> do
          let resultType = fromMaybe bodyType mRet
          postType <- withEnv [("result", resultType)] (inferExpr post)
          postOk <- compatibleExpanded postType TBool
          unless postOk $
            tcError $ "post condition of '" <> name <> "' must be bool, got " <> typeLabel postType

-- | LT-INV (v0.11): permissive-shell definition.
-- Same type-checking rules as SDefLogic; no structural or callee-admissibility restrictions.
checkStatement (SDefShell name params mRet contract body decreases) = do
  withFunctionContext name False $ do
    withTaggedEnv SrcParam params $ do
      bodyType <- case (mRet, body) of
        (Just retTy, EHole (HNamed _)) -> retTy <$ withSegment "body" (checkExpr body retTy)
        (Just retTy, _)                -> do
          t <- withSegment "body" (inferExpr body)
          unify name retTy t
          pure t
        (Nothing, _)                   -> withSegment "body" (inferExpr body)
      case contractPre contract of
        Nothing -> pure ()
        Just pre -> do
          when (exprContainsVar "result" pre) $
            tcError $ "pre condition of '" <> name <> "' references 'result', which is only available in post clauses (§4.3)"
          preType <- inferExpr pre
          preOk <- compatibleExpanded preType TBool
          unless preOk $
            tcError $ "pre condition of '" <> name <> "' must be bool, got " <> typeLabel preType
      case contractPost contract of
        Nothing -> pure ()
        Just post -> do
          let resultType = fromMaybe bodyType mRet
          postType <- withEnv [("result", resultType)] (inferExpr post)
          postOk <- compatibleExpanded postType TBool
          unless postOk $
            tcError $ "post condition of '" <> name <> "' must be bool, got " <> typeLabel postType
      -- REC-DESCENT (v0.14.24): type-check each decreases measure — int-typed over
      -- the params (same binding scope as pre), 'result' rejected. Phase 1 is
      -- verification-inert: this is the surface scope/type check only, no obligation.
      forM_ decreases $ \m -> do
        when (exprContainsVar "result" m) $
          tcError $ "decreases measure of '" <> name <> "' references 'result', which is only available in post clauses (§4.3)"
        mType <- inferExpr m
        mOk <- compatibleExpanded mType TInt
        unless mOk $
          tcError $ "decreases measure of '" <> name <> "' must be int, got " <> typeLabel mType

-- v0.12.1: def-invariant type-checks identically to its prior SDefLogic form.
checkStatement (SDefInvariant name params mRet contract body) =
  checkStatement (SDefLogic name params mRet contract body)
checkStatement (SDefInterface name fns laws) = do
  -- Register interface function signatures
  forM_ fns $ \(fname, ftype) ->
    case ftype of
      TFn _ _ -> pure ()
      other -> tcError $
        "interface '" <> name <> "' function '" <> fname
        <> "' must have fn type, got " <> typeLabel other
  -- v0.6.2: type-check :laws as Properties (for-all bindings + bool body)
  forM_ laws $ \(Property _desc bindings body _subjects) -> do
    let ifaceBindings = fns  -- interface method signatures as env
    withEnv ifaceBindings $ withEnv bindings $ do
      bodyType <- inferExpr body
      lawOk <- compatibleExpanded bodyType TBool
      unless lawOk $
        tcError $ "interface '" <> name <> "' :laws clause must be bool, got " <> typeLabel bodyType

checkStatement (STypeDef name body) = do
  -- Check that dependent type constraints are well-formed
  case body of
    TDependent bindName base constraint -> do
      -- Bring binding variable into scope before checking the constraint
      ctype <- withEnv [(bindName, base)] (inferExpr constraint)
      ctypeOk <- compatibleExpanded ctype TBool
      unless ctypeOk $
        tcWarn $ "type '" <> name <> "' constraint should be bool, got " <> typeLabel ctype
    _ -> pure ()

checkStatement (SCheck prop) = do
  -- Property bindings become forall quantifiers
  withEnv (propBindings prop) $ do
    bodyType <- inferExpr (propBody prop)
    chkOk <- compatibleExpanded bodyType TBool
    unless chkOk $
      tcError $ "check property '" <> propDescription prop
        <> "': body must be bool, got " <> typeLabel bodyType

checkStatement (SImport imp) = do
  -- Register imported interface functions if specified
  case importInterface imp of
    Nothing -> pure ()
    Just fns -> forM_ fns $ \(fname, ftype) ->
      modify $ \s -> s { tcEnv = Map.insert fname ftype (tcEnv s) }

-- | SOpen: inject exported names from the referenced module as bare names.
-- Qualified names (module.path.f) must already be in the env via typeCheckWithCache.
-- We look for any key of the form "<dotted-path>.<name>" and add bare aliases.
-- Emits open-shadow-warning when a name collision occurs.
checkStatement (SOpen openPath_ mNames) = do
  let prefix = T.intercalate "." openPath_ <> "."
  env <- gets tcEnv
  let qualifying = Map.filterWithKey (\k _ -> prefix `T.isPrefixOf` k) env
      -- Strip prefix to get bare name
      bareExports = Map.mapKeys (T.drop (T.length prefix)) qualifying
      -- Apply selective open filter if present
      filtered = case mNames of
        Nothing -> bareExports
        Just ns -> Map.filterWithKey (\k _ -> k `elem` ns) bareExports
  -- Detect collisions and emit warnings
  forM_ (Map.toList filtered) $ \(bareName, ty) -> do
    mExisting <- tcLookup bareName
    case mExisting of
      Just _ -> tcWarn $
        "open-shadow-warning: '" <> bareName <> "' from " <> T.intercalate "." openPath_
        <> " shadows an existing binding"
      Nothing -> pure ()
    tcInsert bareName ty
    -- v0.3.5 (Phase C): tag open-imported bindings for checkout context
    modify $ \s -> s { tcProvenance = Map.insert bareName SrcOpenImport (tcProvenance s) }
  -- ADMIT-VERIFIED (Option 2, seam 5): the qualified-seeded ContractStatus
  -- (typeCheckWithCacheMode seeds 'tcContractStatus' under '<path>.<name>'
  -- keys) is invisible to the bare-name admissibility lookup in
  -- 'checkCalleeAdmissibility'. Mirror the 'tcEnv' bare-alias injection above:
  -- inject the bare-keyed ContractStatus for exactly the same selectively-
  -- filtered names, so a strict-core caller of the bare callee can find the
  -- imported verified evidence. We do NOT overwrite an existing bare entry
  -- (the local file's own evidence wins; same shadow direction as 'tcEnv').
  csMap <- gets tcContractStatus
  let qualifyingCS = Map.filterWithKey (\k _ -> prefix `T.isPrefixOf` k) csMap
      bareCS       = Map.mapKeys (T.drop (T.length prefix)) qualifyingCS
      filteredCS   = case mNames of
        Nothing -> bareCS
        Just ns -> Map.filterWithKey (\k _ -> k `elem` ns) bareCS
  forM_ (Map.toList filteredCS) $ \(bareName, cs) ->
    modify $ \s -> s
      { tcContractStatus =
          Map.insertWith (\_new old -> old) bareName cs (tcContractStatus s) }

-- | SExport is a compile-time annotation only; no type-checking action needed.
checkStatement (SExport _) = pure ()

-- | v0.3: STrust is already collected in checkStatements; no per-statement action.
checkStatement (STrust _ _) = pure ()

-- | v0.6: SWeaknessOk is collected by SpecCoverage; no per-statement type-check action.
checkStatement (SWeaknessOk _ _) = pure ()

checkStatement (SExpr expr) = do
  _ <- inferExpr expr
  pure ()

checkStatement (SDefMain { defMainStep = stepE, defMainDone = doneE }) = do
  -- Type-check the step and done? expressions
  _ <- inferExpr stepE
  case doneE of
    Nothing -> pure ()
    Just de -> do
      doneType <- inferExpr de
      doneOk <- compatibleExpanded doneType TBool
      unless doneOk $
        tcWarn ":done? should return bool; found non-bool type (ignored in v0.2)"

-- ---------------------------------------------------------------------------
-- v0.4 CAP-1: Capability Enforcement Helpers
-- ---------------------------------------------------------------------------

-- | Extract the WASI namespace from a fully-qualified function name.
-- e.g., "wasi.io.stdout" → "wasi.io", "wasi.fs.write" → "wasi.fs"
-- Takes the first two segments of the dotted path.
extractWasiNamespace :: Name -> Name
extractWasiNamespace func =
  T.intercalate "." (take 2 (T.splitOn "." func))

-- | CAP-1: Verify that a wasi.* function call has a matching capability import
-- in the current module's statement list. Capabilities are non-transitive:
-- module B importing module A does NOT inherit A's wasi capabilities.
-- Emits a structured missing-capability error if no matching import is found.
checkWasiCapability :: Name -> TC ()
checkWasiCapability func = do
  stmts <- gets tcModuleStmts
  let namespace = extractWasiNamespace func
      hasImport = any (matchesWasiImport namespace) stmts
  unless hasImport $
    modify $ \s -> s { tcErrors = tcErrors s ++ [mkMissingCapability func namespace] }
  where
    matchesWasiImport ns (SImport imp) = importPath imp == ns
    matchesWasiImport _ _ = False

-- ---------------------------------------------------------------------------
-- Expression Type Inference
-- ---------------------------------------------------------------------------

-- | True when an expression is a hole of any kind.
isHole :: Expr -> Bool
isHole (EHole _) = True
isHole _         = False

-- | Checking mode entry point.
-- At EHole (HNamed): records HoleTyped in sketch mode; reads JSON Pointer from TCState.
-- At other exprs: infer, then unify against expected (identical to existing behaviour).
checkExpr :: Expr -> Type -> TC ()
checkExpr (EHole (HNamed name)) expected =
  recordHole name (HoleTyped expected)
checkExpr (EHole hk) expected = do
  actual <- inferHole hk
  unify "<check>" expected actual
checkExpr e expected   = inferExpr e >>= \actual -> unify "<check>" expected actual

-- | Infer the type of an expression.
inferExpr :: Expr -> TC Type
inferExpr (ELit lit) = pure (inferLiteral lit)

inferExpr (EVar name) = do
  mTy <- tcLookup name
  case mTy of
    Just ty -> pure ty
    Nothing -> do
      tcWarnOrError $ "unbound variable '" <> name <> "' (may be in scope at runtime)"
      pure (TVar name)  -- Return type variable for unbound

inferExpr (ELet bindings body) = do
  -- EC-1: Save env before processing. The foldM below uses tcInsert to make
  -- each binding visible to subsequent bindings, which mutates tcEnv.
  -- We must restore to pre-let env after the let completes, so bindings
  -- don't leak to sibling expressions (e.g. else-branches in if).
  savedEnv <- gets tcEnv
  savedProv <- gets tcProvenance
  -- Process bindings sequentially: each binding extends the scope for the next
  -- PR 4: binding head is now Pattern, not Name.
  resolvedBindings <- foldM (\acc (pat, mAnnot, expr) -> do
    inferredTy <- inferExpr expr
    newBindings <- case pat of
      -- Simple variable binding (hot path — identical to old semantics)
      PVar n -> do
        let ty = case mAnnot of
                   Nothing     -> inferredTy
                   Just annotTy -> annotTy  -- trust annotation; unify below
        case mAnnot of
          Nothing     -> pure ()
          Just annotTy -> unify n annotTy inferredTy
        pure [(n, ty)]
      -- All other patterns (pair destructuring, nested, future extensions)
      _ -> checkPattern pat inferredTy
    -- Extend scope for subsequent bindings
    mapM_ (uncurry tcInsert) newBindings
    pure (acc ++ newBindings)
    ) [] bindings
  -- Restore to pre-let env, then use withTaggedEnv for the body only.
  -- This ensures foldM's tcInsert mutations don't leak to sibling expressions.
  modify $ \s -> s { tcEnv = savedEnv, tcProvenance = savedProv }
  -- OBLIG-1 v2a: record simple-var let-binding RHSs so a hole in the body
  -- carries the definitional equality (= y e). Only PVar heads (a destructuring
  -- pattern has no single binder to attach an RHS to).
  --
  -- LET-PTR: the body traversal pushes the "body" segment (like function bodies,
  -- if-branches, match-arms) so a let-nested hole's sketch pointer matches its
  -- AST node (.../body). Without it the hole recorded /statements/N/body while
  -- its AST node is /statements/N/body/body, so `checkout` could not resolve the
  -- hole and returned null in_scope / assumptions for every let-nested hole.
  let letDefs = [ (n, e) | (PVar n, _, e) <- bindings ]
  withDefs letDefs (withTaggedEnv SrcLetBinding resolvedBindings
    (withSegment "body" (inferExpr body)))

inferExpr (EIf cond thenE elseE) = do
  condType <- inferExpr cond
  condOk <- compatibleExpanded condType TBool
  unless condOk $
    tcError $ "if condition must be bool, got " <> typeLabel condType
  -- Sketch propagation: if one branch is a hole, constrain it from the other.
  -- withSegment threads one RFC 6901 token per call so the stack stays clean.
  case (isHole thenE, isHole elseE) of
    (False, False) -> do
      -- Standard path (both concrete)
      thenType <- withSegment "then" (inferExpr thenE)
      elseType <- withSegment "else" (inferExpr elseE)
      branchOk <- compatibleExpanded thenType elseType
      if branchOk
        then pure thenType
        else do
          tcWarnOrError $ "if branches have different types: " <> typeLabel thenType
                    <> " vs " <> typeLabel elseType
          pure thenType
    (False, True) -> do
      -- else is a hole: infer then, propagate into else
      thenType <- withSegment "then" (inferExpr thenE)
      withSegment "else" (checkExpr elseE thenType)
      pure thenType
    (True, False) -> do
      -- then is a hole: infer else, propagate into then
      elseType <- withSegment "else" (inferExpr elseE)
      withSegment "then" (checkExpr thenE elseType)
      pure elseType
    (True, True) -> do
      -- both holes: infer each (will emit HoleUnknown)
      withSegment "then" (void $ inferExpr thenE)
      withSegment "else" (void $ inferExpr elseE)
      pure (TVar "?")

inferExpr (EMatch expr cases) = do
  scrutType <- inferExpr expr
  -- Resolve through type aliases so we can see the structural TSumType body
  -- (redundant; checkPattern also expands at entry — kept for checkExhaustive)
  resolvedScrutType <- expandAlias scrutType
  -- Exhaustiveness check: only for TSumType where the full constructor set is known
  checkExhaustive resolvedScrutType cases
  -- Index all cases for reliable pointer paths
  let indexedCases = zip [0 :: Int ..] cases
      nonHoleArms  = [(i, pat, body) | (i, (pat, body)) <- indexedCases, not (isHole body)]
      holeArms     = [(i, pat, body) | (i, (pat, body)) <- indexedCases,     isHole body]
  -- Pass 1: synthesise non-hole arm bodies; track conflict.
  -- Each arm pointer uses three clean tokens: "arms" / i / "body"
  nonHoleResults <- forM nonHoleArms $ \(i, pat, body) -> do
    patBindings <- checkPattern pat resolvedScrutType
    t <- withTaggedEnv SrcMatchArm patBindings $
           withSegment "arms" $ withSegment (tshow i) $ withSegment "body" $
             inferExpr body
    pure t
  -- Unify non-hole arm types; on first mismatch record the conflicting pair
  (armT, mConflict) <- case nonHoleResults of
    [] -> pure (TVar "?", Nothing)
    (t:ts) -> foldM (\(acc, mc) t' ->
        if mc /= Nothing then pure (acc, mc)
        else do
          armOk <- compatibleExpanded acc t'
          if armOk then pure (acc, Nothing)
             else do
               tcWarn $ "match arms have different types: " <> typeLabel acc <> " vs " <> typeLabel t'
               pure (acc, Just (acc, t'))
      ) (t, Nothing) ts
  -- Pass 2: check hole arm bodies against unified arm type (or record conflict/unknown)
  forM_ holeArms $ \(i, pat, body) -> do
    patBindings <- checkPattern pat resolvedScrutType
    withTaggedEnv SrcMatchArm patBindings $
      withSegment "arms" $ withSegment (tshow i) $ withSegment "body" $ do
        case body of
          EHole (HNamed name) -> do
            let status = case mConflict of
                  Just (t1, t2) -> HoleAmbiguous t1 t2
                  Nothing       -> if armT == TVar "?" then HoleUnknown else HoleTyped armT
            recordHole name status
            -- Emit ambiguous-hole diagnostic if conflict
            case mConflict of
              Just (t1, t2) -> emitAmbiguous name t1 t2
              Nothing       -> pure ()
          _ -> checkExpr body armT  -- non-named hole kinds
  pure $ if mConflict /= Nothing then TVar "?" else armT

inferExpr (EApp func args) = do
  -- v0.4 CAP-1: capability enforcement for wasi.* calls.
  -- Check is here (in inferExpr, not checkStatement) because EApp can appear
  -- in any nesting context: let RHS, if branches, match arms, do steps, contracts.
  when ("wasi." `T.isPrefixOf` func) $ checkWasiCapability func
  -- LT-INV (v0.11): under strict-core mode, callee must be body-faithful or trusted-prelude.
  checkCalleeAdmissibility func
  -- S4: warn on dotted function names in app position (non-wasi)
  when ("." `T.isInfixOf` func && not ("wasi." `T.isPrefixOf` func)) $
    tcWarn $ "dotted function name '" <> func <> "' in app position is not supported; "
           <> "use (open <module-path>) and call the bare exported name. "
           <> "For Result constructors, use 'ok' and 'err' instead of qualified forms."
  -- BUG-3 (v0.14.3): freshen the callee's TVars for this call site so a
  -- polymorphic builtin's own placeholder names (e.g. "a"/"b" in `second`)
  -- can never collide with an unrelated leaked TVar or another call's
  -- instantiation of the same signature. See freshenFnType.
  mFuncTyRaw <- tcLookup func
  mFuncTy    <- traverse freshenFnType mFuncTyRaw
  let nArgs = length args
  -- D2: warn when a def-logic calls itself recursively without :decreases (GrammarLegacy only).
  -- Under GrammarCoreInversion: def-shell self-calls are correct (no warning); def self-calls
  -- are already caught by checkCalleeAdmissibility (core-membership-violation).
  isLetrec <- gets tcIsLetrec
  mCurrent <- gets tcCurrentFn
  gm       <- gets tcGrammarMode
  when (mCurrent == Just func && not isLetrec && gm == GrammarLegacy) $
    tcWarn $ "self-recursive call to '" <> func <> "' inside def-logic; "
              <> "use (letrec " <> func <> " [...] :decreases ...) to provide a termination measure"
  -- v0.3: trust-gap warning for cross-module calls with unproven contracts
  do csMap  <- gets tcContractStatus
     trusts <- gets tcTrusts
     case Map.lookup func csMap of
       Nothing -> pure ()  -- no contract status known (local or unknown)
       Just cs -> do
         -- Check pre-condition
         emitTrustGap func trusts (fmap erDisplayLevel (csPre cs))
         -- Check post-condition
         emitTrustGap func trusts (fmap erDisplayLevel (csPost cs))
  case mFuncTy of
    Nothing -> do
      tcWarnOrError $ "call to unknown function '" <> func <> "'"
      pure (TVar "?")  -- wildcard: don't inject false type mismatch downstream
    Just (TFn paramTypes retType) -> do
      when (nArgs /= length paramTypes) $ do
        let hint = if func == "string-concat" && nArgs > length paramTypes
                     then " \x2014 use string-concat-many for joining more than 2 strings"
                     else ""
        tcError $ "function '" <> func <> "' expects " <> tshow (length paramTypes)
                  <> " args, got " <> tshow nArgs <> hint
      -- v0.4 U-Lite: per-call-site substitution.
      -- Each call gets its own substitution map. When a polymorphic parameter
      -- (TVar "a") first encounters a concrete type, it binds a → T.
      -- Subsequent uses of the same TVar check consistency.
      finalSubst <- foldM (\subst (j, expected, arg) ->
        withSegment "args" $ withSegment (tshow (j :: Int)) $ do
          case arg of
            EHole hk -> do
              -- Holes: record with substituted type, don't contribute to subst
              checkExpr (EHole hk) (applySubst subst expected)
              pure subst
            _ -> do
              actual <- inferExpr arg
              expected' <- expandAlias expected
              actual'   <- expandAlias actual
              structuralUnify func subst (stripDep expected') (stripDep actual')
        ) Map.empty (zip3' [0 :: Int ..] paramTypes args)
      pure (applySubst finalSubst retType)
    Just (TCustom n)
      -- COMP-4: a nullary constructor applied with no args — `(Empty)` — is a
      -- VALUE of its sum type (η: `(f)` ≡ `f`). collectConstructors registers a
      -- nullary ctor as `ctor : TCustom Sum`; the bare-EVar form already types as
      -- the sum, and this makes the application form agree (so a payload sum with
      -- a nullary variant, `(| Accepted int) (| Rejected)`, is constructible).
      | null args -> pure (TCustom n)
      | otherwise -> do
          tcError $ "'" <> func <> "' is not a function (nullary constructor / value of type "
                    <> n <> ") but is applied to " <> tshow nArgs <> " arg(s)"
          pure (TCustom n)
    Just other -> do
      tcError $ "'" <> func <> "' is not a function, it has type " <> typeLabel other
      pure TUnit

inferExpr (EOp op args) = do
  -- TC-EOP-1 (v0.10.7): mirror the EApp arity/type-check loop above. Prior to
  -- this fix the args were ignored entirely, so (+ 1 "x"), (= 1 "1"), (not 1),
  -- and arity-bad calls like (+ 1) silently passed. The polymorphic ops
  -- (=, !=, etc.) declare TVar "a" in builtinEnv; structuralUnify's
  -- per-call-site substitution map enforces same-tyvar-same-type within one
  -- call, so (= 1 "1") fails at arg 1 against the int bound from arg 0.
  -- BUG-3 (v0.14.3): freshen for the same reason as the EApp path above.
  mOpTy <- traverse freshenFnType (Map.lookup op builtinEnv)
  case mOpTy of
    Just (TFn paramTypes retType) -> do
      let nArgs = length args
      when (nArgs /= length paramTypes) $
        tcError $ "operator '" <> op <> "' expects " <> tshow (length paramTypes)
                  <> " args, got " <> tshow nArgs
      finalSubst <- foldM (\subst (j, expected, arg) ->
        withSegment "args" $ withSegment (tshow (j :: Int)) $ do
          case arg of
            EHole hk -> do
              checkExpr (EHole hk) (applySubst subst expected)
              pure subst
            _ -> do
              actual <- inferExpr arg
              expected' <- expandAlias expected
              actual'   <- expandAlias actual
              structuralUnify op subst (stripDep expected') (stripDep actual')
        ) Map.empty (zip3' [0 :: Int ..] paramTypes args)
      pure (applySubst finalSubst retType)
    Just other -> do
      tcError $ "operator '" <> op <> "' has non-function type "
                <> typeLabel other
      pure TBool
    Nothing -> do
      tcWarnOrError $ "unknown operator '" <> op <> "'"
      pure TBool

inferExpr (EPair a b) = do
  ta <- inferExpr a
  tb <- inferExpr b
  pure (TPair ta tb)  -- PR 1: correct product type; was TResult (unsound)

inferExpr (EHole holeKind) = inferHole holeKind

inferExpr (EAwait expr) = do
  innerType <- inferExpr expr
  case innerType of
    TPromise t -> pure (TResult t TDelegationError)  -- v0.3 §3.2: await returns Result[t, DelegationError]
    other -> do
      tcWarn $ "await applied to non-Promise type " <> typeLabel other
      pure other  -- Best-effort: unwrap whatever

inferExpr (ELambda params body) = do
  bodyType <- withTaggedEnv SrcParam params (inferExpr body)
  pure (TFn (map snd params) bodyType)

inferExpr (EDo steps) = do
  case steps of
    [] -> pure TUnit
    _  -> inferDoSteps steps

-- | Infer the type of a hole expression.
inferHole :: HoleKind -> TC Type
inferHole (HNamed name) = do
  -- Synthesis context: no expected type reached this hole.
  -- Return TVar (\"?\" <> name) so isHoleVar fires on downstream unification
  -- failures, classifying them as holeSensitive (D3 invariant).
  recordHole name HoleUnknown
  tcWarn $ "unresolved named hole"
  pure (TVar ("?" <> name))  -- D3 canonical form: must use ?-prefixed TVar

inferHole (HChoose _options) = do
  tcWarn "unresolved ?choose hole"
  pure (TVar "?")

inferHole (HRequestCap cap) = do
  tcWarn $ "capability request hole for: " <> cap
  pure TUnit

inferHole (HScaffold spec) = do
  tcWarn $ "scaffold hole for template: " <> scaffoldTemplate spec
  pure TUnit

inferHole (HDelegate spec) = do
  let retTy = delegateReturnType spec
  case delegateOnFailure spec of
    Nothing -> pure ()
    Just fb -> checkExpr fb retTy
  pure retTy

inferHole (HDelegateAsync spec) =
  case delegateReturnType spec of
    TPromise _ -> do
      -- Defensive backstop for ASTs constructed outside the parsers.
      -- Parsers reject this at parse time; this only fires for
      -- programmatic AST construction.
      tcError $ "hole-delegate-async return_type is Promise[...] after normalization; "
                <> "return_type must be the inner type T, not Promise[T] "
                <> "(got " <> typeLabel (delegateReturnType spec) <> ")"
      pure (TVar "?")                 -- wildcard: matches convention at line 844
    inner -> pure (TPromise inner)    -- canonical wrapping

inferHole (HDelegatePending retType) = do
  tcError "blocking delegate hole — execution will stall"
  pure retType

inferHole HConflictResolution = do
  tcError "unresolved merge conflict hole"
  pure (TVar "?")

inferHole (HProofRequired reason mPred) = do
  tcWarn $ "proof-required hole [" <> reason <> "]: needs formal verification"
  case mPred of
    Nothing -> pure ()
    Just pred -> do
      predType <- inferExpr pred
      predOk <- compatibleExpanded predType TBool
      unless predOk $
        tcError $ "?proof-required predicate must be bool, got " <> typeLabel predType
      when (isNonLinear pred) $
        tcWarn "?proof-required predicate contains non-linear arithmetic: cannot be discharged by QF-LIA; Leanstral obligation required"
  pure (TVar "?")

-- | Infer type from do-steps with pair-thread enforcement (PR 2).
-- Every step must return (S, Command) i.e. TPair S (TCustom "Command").
-- The state type S is unified across all steps.
-- DO-1: non-final steps that produce a Command emit a warning.
inferDoSteps :: [DoStep] -> TC Type
inferDoSteps [] = pure TUnit
inferDoSteps steps = do
  let (DoStep mName0 e0) = head steps
  t0 <- withSegment "steps" $ withSegment "0" $ inferExpr e0
  (s0, cmd0) <- expectPairType "do-block step 0" t0
  -- DO-1: check step 0 if it is not the final step
  when (length steps > 1) $
    checkDiscardedCommand 0 cmd0
  let binding0 = case mName0 of
        Just n  -> [(n, s0)]
        Nothing -> [("_s_0", s0)]
  withEnv binding0 $ go s0 (1 :: Int) (tail steps)
  where
    go sType _ [] = pure (TPair sType (TCustom "Command"))
    go sType i (DoStep mName e : rest) = do
      t <- withSegment "steps" $ withSegment (tshow i) $ inferExpr e
      (si, cmdTy) <- expectPairType ("do-block step " <> tshow i) t
      -- Unify S: all steps must thread the same state type
      unify ("do-block step " <> tshow i) sType si
      -- DO-1: check non-final steps
      when (not (null rest)) $
        checkDiscardedCommand i cmdTy
      let bindName = case mName of
            Just n  -> n
            Nothing -> "_s_" <> tshow i
      withEnv [(bindName, si)] $ go sType (i + 1) rest

-- | DO-1: Emit warning when an intermediate step produces a Command
-- that the current codegen will silently discard.
-- v0.7: Warning-only in all modes. Hard error deferred to v0.8
-- when (discard expr) provides an explicit opt-out.
checkDiscardedCommand :: Int -> Type -> TC ()
checkDiscardedCommand i cmdTy =
  when (cmdTy == TCustom "Command") $
    tcWarn $ "do-block step " <> tshow i
             <> ": current codegen discards this intermediate command. "
             <> "Use `seq-commands` to sequence IO actions explicitly."

-- | Expect a TPair; emit "do-step-type-error" and return wildcard components
-- on failure so one bad step doesn't cascade and suppress subsequent errors.
expectPairType :: Text -> Type -> TC (Type, Type)
expectPairType _ (TPair a b) = pure (a, b)
expectPairType ctx t = do
  modify $ \s -> s { tcErrors = tcErrors s ++
    [(mkError Nothing ("do-step-type-error in " <> ctx <>
      ": step must return (S, Command), got " <> typeLabel t))
      { diagKind = Just "do-step-type-error" }] }
  pure (TVar "?", TCustom "Command")  -- wildcards; don't cascade

-- ---------------------------------------------------------------------------
-- Pattern Checking
-- ---------------------------------------------------------------------------
-- Exhaustiveness Checking (D1)
-- ---------------------------------------------------------------------------

-- | Check that a match expression is exhaustive for known sum types.
-- Only fires for TSumType, TResult, and TBool — all other types pass silently.
-- A wildcard (PWildcard) or variable (PVar) arm satisfies coverage for any type.
checkExhaustive :: Type -> [(Pattern, Expr)] -> TC ()
checkExhaustive scrutTy arms = do
  -- If any arm is a wildcard or variable, it catches everything
  let hasWildcard = any (isWild . fst) arms
  unless hasWildcard $ do
    let covered = [c | (PConstructor c _, _) <- arms]
    case scrutTy of
      TSumType ctors -> do
        let allCtors  = map fst ctors
            missing   = filter (`notElem` covered) allCtors
        unless (null missing) $
          tcEmitNonExhaustive (typeLabel scrutTy) missing covered
      TResult _ _ -> do
        -- Built-in: Success / Error must both be present
        -- NOTE: TPair is handled by the fallthrough `_ -> pure ()` case below;
        -- pair-typed scrutinees have no known constructor set to check exhaustively.
        let missing = filter (`notElem` covered) ["Success", "Error"]
        unless (null missing) $
          tcEmitNonExhaustive "Result" missing covered
      TBool -> do
        -- Built-in: True / False must both be present (if using ctor patterns)
        let boolCtors = filter (`elem` ["True", "False"]) covered
        unless (null boolCtors) $ do  -- only fire if they're using ctor patterns
          let missing = filter (`notElem` covered) ["True", "False"]
          unless (null missing) $
            tcEmitNonExhaustive "Bool" missing covered
      _ -> pure ()   -- unknown type — no false positives
  where
    isWild PWildcard = True
    isWild (PVar _)  = True
    isWild _         = False

-- ---------------------------------------------------------------------------
-- Pattern Checking
-- ---------------------------------------------------------------------------

-- | Type-check a pattern against a scrutinee type, returning new bindings.
-- Expands the scrutinee type at entry so all pattern-dispatch cases see
-- the structural body (TSumType, TResult, TPair) rather than a TCustom alias.
checkPattern :: Pattern -> Type -> TC [(Name, Type)]
checkPattern pat scrutTy = do
  scrutTy' <- expandAlias scrutTy
  checkPatternExpanded pat scrutTy'

-- | Internal: pattern checking against an already-expanded scrutinee type.
checkPatternExpanded :: Pattern -> Type -> TC [(Name, Type)]
checkPatternExpanded PWildcard _ = pure []
checkPatternExpanded (PVar name) ty = pure [(name, ty)]
checkPatternExpanded (PLiteral lit) scrutTy = do
  let litTy = inferLiteral lit
  unless (compatibleWith litTy scrutTy) $
    tcWarn $ "literal pattern type " <> typeLabel litTy
              <> " may not match scrutinee type " <> typeLabel scrutTy
  pure []
checkPatternExpanded (PConstructor ctor subPats) scrutTy = do
  -- Built-in constructors: Success(v), Error(e)
  case (ctor, scrutTy) of
    ("Success", TResult t _) ->
      case subPats of
        [p] -> checkPattern p t
        _   -> do { tcError "Success takes one argument"; pure [] }
    ("Error", TResult _ e) ->
      case subPats of
        [p] -> checkPattern p e
        _   -> do { tcError "Error takes one argument"; pure [] }
    -- TSumType: look up the constructor in the known-good constructor list
    (_, TSumType ctorList) ->
      case lookup ctor ctorList of
        Nothing ->
          do { tcWarn $ "unknown constructor '" <> ctor <> "' for sum type"; pure [] }
        Just Nothing ->
          -- Nullary constructor
          if null subPats then pure []
          else do { tcWarn $ "constructor '" <> ctor <> "' takes no arguments"; pure [] }
        Just (Just payload) ->
          case subPats of
            [p] -> checkPattern p payload
            _   -> do { tcWarn $ "constructor '" <> ctor <> "' takes one argument"; pure [] }
    -- PR 4: Built-in pair constructor: (pair fst snd)
    ("pair", TPair a b) ->
      case subPats of
        [p1, p2] -> do
          bs1 <- checkPattern p1 a
          bs2 <- checkPattern p2 b
          pure (bs1 ++ bs2)
        _ -> do { tcError "pair destructor takes exactly two sub-patterns"; pure [] }
    _ -> do
      -- Unknown constructor — bind sub patterns as type vars
      bindings <- forM (zip [0..] subPats) $ \(i, p) ->
        checkPattern p (TVar (ctor <> tshow (i :: Int)))
      pure (concat bindings)

-- ---------------------------------------------------------------------------
-- v0.4 U-Lite / v0.5 U-Full: Per-Call-Site Substitution Helpers
-- ---------------------------------------------------------------------------

-- | Apply a type variable substitution map to a type, recursively.
applySubst :: Map Name Type -> Type -> Type
applySubst subst t@(TVar a)       = Map.findWithDefault t a subst
applySubst subst (TList t)        = TList (applySubst subst t)
applySubst subst (TResult a b)    = TResult (applySubst subst a) (applySubst subst b)
applySubst subst (TPair a b)      = TPair (applySubst subst a) (applySubst subst b)
applySubst subst (TFn ps r)       = TFn (map (applySubst subst) ps) (applySubst subst r)
applySubst subst (TPromise t)     = TPromise (applySubst subst t)
applySubst subst (TMap k v)       = TMap (applySubst subst k) (applySubst subst v)
applySubst subst (TDependent n b e) = TDependent n (applySubst subst b) e
applySubst _     t                = t  -- TInt, TString, TBool, TUnit, TBytes, TCustom, TSumType, TFloat

-- | Strip TDependent to its base type (ignores the constraint).
stripDep :: Type -> Type
stripDep (TDependent _ base _) = base
stripDep t = t

-- | v0.5 U1-full: Check if a type variable occurs in a type (infinite type guard).
-- Must be structurally total over the Type ADT (Language Team review, 2026-04-21).
occursIn :: Name -> Type -> Bool
occursIn a (TVar b)           = a == b
occursIn a (TList t)          = occursIn a t
occursIn a (TResult x y)      = occursIn a x || occursIn a y
occursIn a (TPair x y)        = occursIn a x || occursIn a y
occursIn a (TFn ps r)         = any (occursIn a) ps || occursIn a r
occursIn a (TPromise t)       = occursIn a t
occursIn a (TMap k v)         = occursIn a k || occursIn a v
occursIn a (TDependent _ b _) = occursIn a b
occursIn a (TSumType ctors)   = any (\(_, mT) -> maybe False (occursIn a) mT) ctors
occursIn _ _                  = False  -- TInt, TString, TBool, TUnit, TBytes, TCustom, TFloat, TDelegationError

-- | Collect every distinct TVar name occurring (structurally) in a type.
-- Mirrors 'occursIn's constructor coverage exactly, as a set-builder instead
-- of a membership test. Used by 'freshenFnType' (BUG-3, v0.14.3).
freeTVarNames :: Type -> Set.Set Name
freeTVarNames (TVar a)           = Set.singleton a
freeTVarNames (TList t)          = freeTVarNames t
freeTVarNames (TResult x y)      = Set.union (freeTVarNames x) (freeTVarNames y)
freeTVarNames (TPair x y)        = Set.union (freeTVarNames x) (freeTVarNames y)
freeTVarNames (TFn ps r)         = Set.unions (map freeTVarNames ps) `Set.union` freeTVarNames r
freeTVarNames (TPromise t)       = freeTVarNames t
freeTVarNames (TMap k v)         = Set.union (freeTVarNames k) (freeTVarNames v)
freeTVarNames (TDependent _ b _) = freeTVarNames b
freeTVarNames (TSumType ctors)   = Set.unions [ maybe Set.empty freeTVarNames mT | (_, mT) <- ctors ]
freeTVarNames _                  = Set.empty  -- TInt, TString, TBool, TUnit, TBytes, TCustom, TFloat, TDelegationError

-- | BUG-3 (v0.14.3): instantiate a (possibly polymorphic) function type with
-- fresh, globally-unique TVar names before it is used at a call site.
--
-- Root cause this fixes: 'builtinEnv' declares polymorphic builtins with
-- fixed, literal TVar names ("a", "b", ...), e.g. @second :: TFn [TPair
-- (TVar "a") (TVar "b")] (TVar "b")@ -- and every call to the same builtin
-- resolves to the exact same 'Type' value (a constant Map lookup, never
-- instantiated). Separately, an unannotated empty-list literal is inferred
-- with an unbound 'TVar "a"' that is never resolved to a concrete element
-- type; because LLMLL has no let-generalization, this bare TVar propagates
-- structurally through the type environment wherever the binding is used.
-- When such a leaked user TVar and a builtin's own placeholder happen to
-- share a bare name, 'structuralUnify's occurs check ('occursIn', plain
-- string equality on TVar names) cannot tell "the same variable, seen
-- twice" apart from "two unrelated variables that happen to be spelled the
-- same" -- and fires a false "infinite type" on the latter.
--
-- Fix scope (deliberately narrow, not full HM let-polymorphism): freshen
-- only the *callee's own* TVars at each 'EApp'/'EOp' call site, via a
-- monotonic per-typecheck-run counter ('tcTVarCounter'). This is standard
-- Hindley-Milner instantiation (rename bound TVars to fresh names before
-- unification) applied at exactly the two call sites that look up a
-- function/operator type from the environment. It does not touch
-- let-bound value types (e.g. the leaked empty-list TVar itself is left
-- alone) -- full let-generalization/instantiation is a materially larger
-- change and out of scope for this fix; narrowing to callee-signature
-- freshening is sufficient because collisions require a *builtin's*
-- fixed-name TVar on one side, and after freshening no two call sites (nor
-- a call site and an unrelated leaked TVar) can ever share a name again.
-- No-op (and free) for any concrete, TVar-free type, which covers ordinary
-- user-defined 'def'/'def-shell' signatures (LLMLL's surface syntax has no
-- generic/type-variable annotation, so user function types never contain a
-- TVar in the first place).
freshenFnType :: Type -> TC Type
freshenFnType t =
  case Set.toList (freeTVarNames t) of
    []  -> pure t  -- no TVars: nothing to freshen (the common case for user defs)
    vs -> do
      n <- gets tcTVarCounter
      modify $ \s -> s { tcTVarCounter = n + 1 }
      let rename = Map.fromList [ (v, TVar (v <> "$" <> tshow n)) | v <- vs ]
      pure (applySubst rename t)

-- | Structural unification with substitution tracking.
-- When a TVar in the expected type first encounters a concrete actual type,
-- it's bound in the substitution map. If the same TVar is encountered again
-- with a different concrete type, a type-mismatch error is emitted.
--
-- v0.5 U-Full: TVar-TVar now binds (wildcard closure). Occurs check prevents
-- infinite types. Bound-TVar consistency uses recursive structuralUnify
-- instead of compatibleWith (Language Team Issue 2, 2026-04-21).
--
-- PRECONDITION: inputs must be pre-expanded via expandAlias. The production
-- call site (EApp, inferExpr) expands before calling. Direct test usage via
-- runTCPure should expand inputs before calling structuralUnify.
structuralUnify :: Name -> Map Name Type -> Type -> Type -> TC (Map Name Type)
structuralUnify func subst expected actual =
  case (expected, actual) of
    -- TVar expected: check or bind in substitution
    (TVar a, _) ->
      case Map.lookup a subst of
        -- v0.5 U2-full (Issue 2): Already bound — recursively unify the bound
        -- type against the actual. This ensures that TVar-TVar bindings are
        -- enforced: if a → TVar "b" and actual = TString, the recursive call
        -- will extend the substitution with b → TString. Using compatibleWith
        -- here would silently wildcard (TVar _ matches anything) and defeat
        -- the substitution mechanism.
        --
        -- SUBSTITUTION CYCLE RISK (Language Team, 2026-04-21): If subst
        -- contains a → TVar "b" AND b → TVar "a", this recursive call will
        -- loop forever (a → b → a → ...). The occurs check (occursIn) does
        -- NOT cover this — it inspects structural occurrence in the Type AST,
        -- not cycles in the substitution map. Currently safe because:
        --   (1) The reflexive guard at L1076 blocks a → TVar "a".
        --   (2) Per-call-site scoping means subst is fresh per EApp, limiting
        --       the window for transitive TVar chains.
        -- If global substitution or cross-EApp constraint sharing is ever
        -- introduced, add a visited-set parameter or path-compression pass.
        Just bound -> structuralUnify func subst bound actual
        Nothing ->
          case actual of
            -- v0.5 U2-full: TVar-TVar wildcard closure.
            -- Bind TVar to TVar so constraints propagate through chains.
            -- Reflexive case (a == b) produces no new information.
            TVar b
              | a == b    -> pure subst  -- reflexive: no new info
              | otherwise -> pure (Map.insert a actual subst)  -- bind TVar to TVar
            -- v0.5 U1-full: Occurs check before binding.
            -- Prevents infinite types like a ~ list[a].
            _      -> if occursIn a actual
                        then do
                          tcError $ "infinite type: " <> a <> " occurs in " <> typeLabel actual
                          pure subst
                        else pure (Map.insert a actual subst)  -- bind

    -- TVar actual: wildcard (can't constrain from the expected-type side).
    -- SAFETY (Language Team review, 2026-04-21): This is correct only because
    -- substitution scope is per-call-site. The substitution map created in
    -- inferExpr (EApp ...) does NOT escape the EApp boundary. If we ever move
    -- to global substitution, this line becomes a soundness hole — actual TVars
    -- from return types would need to participate in the global constraint set.
    (_, TVar _) -> pure subst

    -- Structural recursion for compound types
    (TList a, TList b) -> structuralUnify func subst a b

    (TResult a b, TResult c d) -> do
      s1 <- structuralUnify func subst a c
      structuralUnify func s1 b d

    (TPair a b, TPair c d) -> do
      s1 <- structuralUnify func subst a c
      structuralUnify func s1 b d

    (TPromise a, TPromise b) -> structuralUnify func subst a b

    (TMap k1 v1, TMap k2 v2) -> do
      s1 <- structuralUnify func subst k1 k2
      structuralUnify func s1 v1 v2

    (TFn as r, TFn bs s) ->
      if length as == length bs then do
        s1 <- foldM (\st (a, b) -> structuralUnify func st a b) subst (zip as bs)
        structuralUnify func s1 r s
      else do
        tcTypeMismatch func expected actual
        pure subst

    -- TDependent: strip and compare base type
    (TDependent _ a _, b) -> structuralUnify func subst a b
    (a, TDependent _ b _) -> structuralUnify func subst a b

    -- TCustom wildcard
    (TCustom "_", _) -> pure subst
    (_, TCustom "_") -> pure subst

    -- Fallback: structural equality via compatibleWith
    _ ->
      if compatibleWith expected actual
        then pure subst
        else do
          tcTypeMismatch func expected actual
          pure subst

-- | Zip three lists (truncating to shortest).
zip3' :: [a] -> [b] -> [c] -> [(a, b, c)]
zip3' (a:as) (b:bs) (c:cs) = (a, b, c) : zip3' as bs cs
zip3' _ _ _ = []

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------

-- | Infer type of a literal.
inferLiteral :: Literal -> Type
inferLiteral (LitInt _)    = TInt
inferLiteral (LitFloat _)  = TFloat
inferLiteral (LitString _) = TString
inferLiteral (LitBool _)   = TBool
inferLiteral LitUnit       = TUnit

-- | Check if two types are compatible (structural equality, with TVar wildcard).
-- TDependent is checked by its base type only (constraint not evaluated).
compatibleWith :: Type -> Type -> Bool
compatibleWith (TVar _) _            = True  -- type variable matches anything
compatibleWith _ (TVar _)            = True
compatibleWith (TCustom "_") _       = True  -- untyped param wildcard
compatibleWith _ (TCustom "_")       = True
compatibleWith (TCustom a) (TCustom b) = a == b
compatibleWith (TDependent _ a _) b   = compatibleWith a b
compatibleWith a (TDependent _ b _)   = compatibleWith a b
compatibleWith (TList a) (TList b)  = compatibleWith a b
compatibleWith (TMap k1 v1) (TMap k2 v2) = compatibleWith k1 k2 && compatibleWith v1 v2
compatibleWith (TResult a b) (TResult c d) = compatibleWith a c && compatibleWith b d
-- PR 1: TPair structural equality (both components must match)
compatibleWith (TPair a b) (TPair c d) = compatibleWith a c && compatibleWith b d
compatibleWith (TPromise a) (TPromise b) = compatibleWith a b
compatibleWith (TFn as r) (TFn bs s) =
  length as == length bs && all (uncurry compatibleWith) (zip as bs) && compatibleWith r s
compatibleWith (TBytes m) (TBytes n) = m == n
-- TSumType: compatible with itself and with TCustom of the same registered name
-- TSumType: structural constructor equality (v0.4 U7-lite)
-- Before U-lite: any sum ≡ any sum (unsound). Now requires matching constructors.
compatibleWith (TSumType a) (TSumType b) = map fst a == map fst b
compatibleWith a b = a == b

-- | TC-level compatibility check that expands aliases before comparison.
-- Use at call sites that receive types from inference (which may
-- contain unresolved TCustom aliases from the environment).
compatibleExpanded :: Type -> Type -> TC Bool
compatibleExpanded a b = do
  a' <- expandAlias a
  b' <- expandAlias b
  pure (compatibleWith a' b')

-- | Unify two types, emitting an error if they are incompatible.
-- | Fully expand type aliases: traverses composite type structure and
-- chases alias chains transitively.  Cycle guard (per-traversal Set)
-- prevents divergence on (type A B) (type B A).
--
-- NOTE: TDependent recurses into the base type only. The predicate is
-- an Expr, not a Type; alias expansion inside contract predicates is
-- owned by Contracts.hs / FixpointEmit.hs. Do not "fix" this asymmetry
-- without coordinating with those modules.
expandAlias :: Type -> TC Type
expandAlias t0 = go Set.empty t0
  where
    go :: Set.Set Name -> Type -> TC Type
    go seen t = case t of
      TCustom n
        | n `Set.member` seen -> pure (TCustom n)   -- alias cycle: stop
        | otherwise -> do
            am <- gets tcAliasMap
            case Map.lookup n am of
              Nothing   -> pure (TCustom n)
              Just body -> go (Set.insert n seen) body
      TList a            -> TList    <$> go seen a
      TMap k v           -> TMap     <$> go seen k <*> go seen v
      TResult a b        -> TResult  <$> go seen a <*> go seen b
      TPair a b          -> TPair    <$> go seen a <*> go seen b
      TPromise a         -> TPromise <$> go seen a
      TFn args ret       -> TFn      <$> traverse (go seen) args <*> go seen ret
      TSumType ctors     -> TSumType <$> traverse
                              (\(c, mp) -> (\mp' -> (c, mp')) <$> traverse (go seen) mp)
                              ctors
      TDependent n b c   -> (\b' -> TDependent n b' c) <$> go seen b
      _                  -> pure t   -- TInt/TFloat/TString/TBool/TUnit/TBytes/TVar/TDelegationError

unify :: Name -> Type -> Type -> TC ()
unify ctx expected actual = do
  expected' <- expandAlias expected
  actual'   <- expandAlias actual
  unless (compatibleWith expected' actual') $
    -- Report originals to preserve alias names in diagnostics (Fix 1b).
    tcTypeMismatch ctx expected actual

-- | zipWithM_ with indices.
zipWithM_ :: Monad m => (a -> b -> m c) -> [a] -> [b] -> m ()
zipWithM_ f xs ys = sequence_ (zipWith f xs ys)

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Result Type
-- ---------------------------------------------------------------------------

-- | Extended result that includes the inferred type environment.
data TypeCheckResult = TypeCheckResult
  { tcrReport :: DiagnosticReport
  , tcrEnv    :: TypeEnv   -- ^ Environment after processing (with top-level defs)
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Sketch Mode (Phase 2c: --sketch)
-- ---------------------------------------------------------------------------

-- | Result of running the type checker in sketch mode.
data SketchResult = SketchResult
  { sketchHoles      :: [SketchHole]           -- ^ holes in source order
  , sketchErrors     :: [Diagnostic]           -- ^ type errors present in partial program
  , sketchInvariants :: [InvariantSuggestion]  -- ^ v0.4: matched invariant suggestions
  } deriving (Show)

-- | Run the type checker in sketch mode.
-- Accepts partial programs with holes everywhere. Returns each named hole's
-- status (Typed / Ambiguous / Unknown) and JSON Pointer, plus any type errors.
-- v0.4: Also matches function signatures against the invariant pattern registry.
runSketch :: GrammarMode -> TypeEnv -> [Statement] -> [InvariantPattern] -> SketchResult
runSketch gm env stmts patterns =
  let action          = checkStatements stmts
      (_, finalState) = runTCSketch gm env action
      invariants = concatMap (matchStmt (tcEnv finalState)) stmts
  in SketchResult
       { sketchHoles      = reverse (tcHoles finalState)
       , sketchErrors     = tcErrors finalState
       , sketchInvariants = invariants
       }
  where
    matchStmt _ (SDefLogic name params mRetType _ _) =
      let paramTypes = map snd params
          retType    = fromMaybe (TCustom "_") mRetType
          fnType     = TFn paramTypes retType
      in matchPatterns name fnType patterns
    matchStmt _ (SLetrec name params mRetType _ _ _) =
      let paramTypes = map snd params
          retType    = fromMaybe (TCustom "_") mRetType
          fnType     = TFn paramTypes retType
      in matchPatterns name fnType patterns
    -- v0.12.1: def-invariant matches identically to its prior SDefLogic form.
    matchStmt e (SDefInvariant name params mRetType c b) =
      matchStmt e (SDefLogic name params mRetType c b)
    matchStmt _ _ = []

-- ---------------------------------------------------------------------------
-- AST Helpers
-- ---------------------------------------------------------------------------

-- | Check if an expression contains a free occurrence of the given variable name.
exprContainsVar :: Name -> Expr -> Bool
exprContainsVar v (EVar n)          = n == v
exprContainsVar v (EApp _ args)     = any (exprContainsVar v) args
exprContainsVar v (EOp _ args)      = any (exprContainsVar v) args
exprContainsVar v (EIf c t e)       = exprContainsVar v c || exprContainsVar v t || exprContainsVar v e
exprContainsVar v (ELet binds body) = any (\(_, _, e) -> exprContainsVar v e) binds || exprContainsVar v body
exprContainsVar v (EMatch e cases)  = exprContainsVar v e || any (\(_, b) -> exprContainsVar v b) cases
exprContainsVar v (EPair a b)       = exprContainsVar v a || exprContainsVar v b
exprContainsVar v (ELambda _ body)  = exprContainsVar v body
exprContainsVar v (EAwait e)        = exprContainsVar v e
exprContainsVar v (EDo steps)       = any (\(DoStep _ e) -> exprContainsVar v e) steps
exprContainsVar _ (ELit _)          = False
exprContainsVar _ (EHole _)         = False
