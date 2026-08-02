{-# LANGUAGE FlexibleContexts #-}
-- |
-- Module      : LLMLL.FixpointEmit
-- Description : Walk LLMLL typed AST → .fq constraint file + ConstraintTable.
--
-- D4: Decoupled verification backend.
--
-- Coverage: QF linear integer arithmetic only.
--   - Integer params / return types
--   - Linear pre/post predicates (+, -, =, <, <=, >=, >)
--   - Simple letrec termination measures (single-variable or constant)
--   - TSumType sort declarations
--
-- Non-linear sites (HProofRequired holes from D3) are skipped — the compiler
-- already flagged them; the verifier simply omits them from the .fq output.
--
-- FAITHFULNESS INVARIANT (v0.3, updated v0.8.0):
-- This module's output is trusted by --contracts=unproven. If emitFixpoint
-- reports SAFE for a contract, the runtime assertion for that contract must
-- be semantically redundant for all well-typed inputs. Any extension to
-- exprToPred must preserve this invariant: never translate a contract to a
-- weaker .fq constraint that the solver accepts trivially.
--
-- BODY-VC (v0.8.0):
-- When EmitOptions.emitBodyVCs is True, function bodies in the supported
-- QF-LIA fragment are translated to verification conditions via bodyToPredM.
-- Body VCs prove: P ∧ (result = ⟦body⟧) ⟹ Q (postcondition faithfulness).
-- Functions outside the fragment fall back to contract-only verification.
--
-- COMPOSITIONAL VERIFICATION (v0.9.0, COMP-0 Rev 2):
-- When a function f calls a contracted function g, the emitter uses
-- assume-guarantee reasoning: f must PROVE g's precondition (obligation)
-- and may ASSUME g's postcondition (hypothesis). Recursive functions'
-- own body VCs are excluded; callers may use assume-guarantee against
-- recursive functions' contracts with trust degradation via evidenceMeet.

module LLMLL.FixpointEmit
  ( -- * Top-level emitter
    emitFixpoint
  , emitFixpointWith
  , emitFixpointWithCache         -- xmod-ag: cross-module assume-guarantee body-VC
    -- * Configuration
  , EmitOptions(..)
  , defaultEmitOptions
    -- * Result
  , EmitResult(..)
    -- * Alias map (v0.8.0)
  , AliasMap
  , buildAliasMap
  , isIntLike
    -- * Body-VC types (exported for testing)
  , BodyVC(..)
  , LetBinding(..)
  , FlatPath
  , SortEnv
    -- * Compositional verification (v0.9.0)
  , ContractEnv
  , buildContractEnv
  , buildContractEnvWith         -- xmod-ag: explicit-alias-map variant
  , seedImportedContracts        -- xmod-ag: dual-keyed imported ContractEnv
  , cacheAwareAliasMap           -- xmod-cg-brief: merged local-wins alias map
  , cacheAwareContractEnv        -- xmod-cg-brief: entry ∪ imported ContractEnv
  , augmentContractPost          -- DEF-RET Unit 2: return-refinement → effective post
  , buildSortEnv                 -- v0.10 (Language Team Correction 1)
  , applySubst
  , isConstructorDependent
  , collectCallPreObligations
    -- * Body-VC engine (exported for testing)
  , bodyToPredFrom
  , bodyToPredFromR
  , flattenBodyVC
  , pathBranchSides              -- COMP-3b-general: structural branch provenance (localization)
  , collectBranchBinders         -- COMP-3b-general: match-binder tree-walk
  , collectCallSites             -- COMP-4 (b): call sites for payload-subtyping
  , payloadRefinement            -- COMP-4 (b): payload type → (bindingVar, pred)
  , payloadArms                  -- COMP-4 (b): two-arm payload types per arm key
  , admissibleDatatype           -- COMP-4 (a): acyclic-closure admissibility
  , sortableComponent            -- PAIR-RET-2: pair-component faithful-sortability
  , resultReturnUnsafe           -- COMP-4-RESULT: non-admissible Result-return firewall
  , typeToSortA                  -- COMP-4 (a): alias-aware sort (FQData for payload sums)
  , countPathsBounded
    -- * Contract translation (exported for testing)
  , exprToPred
    -- * Refinement resolution (exported for the refine feasibility gate, LLMLL.Feasibility)
  , resolveAllRefinements
  , resolveAliasTy
  , renameVar
    -- * STRLIT (exported for testing): literal interning + Stage-2 code-point length
  , strlitConst
  , strlitLen
    -- * LEVER-A3: classifier–emitter coherence (the §6.1 arbiter, shared with
    -- ObligationMining/ObligationAssembly so classification cannot drift from
    -- what this emitter actually reflects)
  , contractArrGuardsBlock
  , contractSigGuardsBlock
  , contractMentionsArrOp
  , exprMentionsArrOp
    -- * COMP-3b-general Phase 1 (exported for testing)
  , desugarCtorValues
  , buildCtorTagMap
    -- * INT-1 (v0.10.8): overflow taint scan
  , bodyHasOverflowArith
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.IORef
import Data.Maybe (fromMaybe, mapMaybe, isJust, catMaybes)
import Data.List (nub, partition)
import Control.Monad (forM_, forM, when, unless)
import Control.Monad.State.Strict (State, evalState, get, put, MonadState)
import Control.Monad.Reader (ReaderT, runReaderT, ask, lift)
import Data.Char (isUpper, ord)
import Numeric (showHex)
import Data.Graph (stronglyConnComp, SCC(..))

import LLMLL.Syntax
-- ADMIT-SHARED: the shared alias normalization + type-admissibility predicates.
-- Re-exported below (AliasMap, buildAliasMap, isIntLike, resolveAliasTy) so this
-- module's existing consumers are source-compatible.
import LLMLL.TypeAdmissibility
import LLMLL.FixpointIR
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable)
import LLMLL.Diagnostic (Diagnostic, mkWarning)
import LLMLL.HoleAnalysis (buildCallGraph)
import LLMLL.GuardClassifier (classifyGuardM, lookupPredOp, lookupArithOp)

-- ---------------------------------------------------------------------------
-- Configuration (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Options controlling what the emitter generates.
data EmitOptions = EmitOptions
  { emitBodyVCs :: Bool   -- ^ Emit body-faithful verification conditions
  , emitBodyVCTargets :: Maybe [Name]
      -- ^ R8 (incremental patch re-verify): when @Just names@, emit body-VC
      -- constraints ONLY for these functions. All functions' contracts are still
      -- registered (assume-guarantee context), so a targeted function's body-VC is
      -- byte-identical to the whole-module emission — only the untargeted functions'
      -- body-VCs are omitted. @Nothing@ (the default) = every function. Sound for a
      -- patch because a patch fills one function's body hole: contracts never change
      -- (contract-position holes are excluded from checkout, 'HoleAnalysis') and VCs
      -- are assume-guarantee modular ('FixpointEmit' has no cross-function body
      -- coupling), so only the patched function's body-VC differs.
  } deriving (Show, Eq)

defaultEmitOptions :: EmitOptions
defaultEmitOptions = EmitOptions { emitBodyVCs = False, emitBodyVCTargets = Nothing }

-- | R8: is this function targeted for body-VC emission? @Nothing@ targets = all.
bodyVCTargeted :: EmitOptions -> Name -> Bool
bodyVCTargeted opts nm = case emitBodyVCTargets opts of
  Nothing    -> True
  Just names -> nm `elem` names

-- ---------------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------------

data EmitResult = EmitResult
  { erFQFile            :: FQFile           -- ^ the assembled .fq data structure
  , erFQText            :: Text             -- ^ .fq text ready to write to disk
  , erConstraintTable   :: ConstraintTable  -- ^ ID → origin (for DiagnosticFQ)
  , erSkipped           :: [Text]           -- ^ names of skipped non-linear functions
  , erBodyFaithfulFns   :: [Text]           -- ^ v0.8.0: functions with successful body VCs
  , erBodyFallback      :: [Text]           -- ^ v0.8.0: functions that fell back
  , erDiagnostics       :: [Diagnostic]     -- ^ v0.8.0: path-limit warnings, etc.
  , erEmittedPre        :: [Text]           -- ^ v0.8.0: functions whose pre emitted a constraint
  , erEmittedPost       :: [Text]           -- ^ v0.8.0: functions whose post emitted a constraint
  , erCallPreFns        :: [Text]           -- ^ v0.9.0: functions that emitted call-pre obligations
  , erOverflowTaintedFns :: [Text]          -- ^ INT-1 (v0.10.8): body-faithful fns whose body uses unbounded-Int arithmetic
  , erMeasuredFns        :: [Text]          -- ^ REC-DESCENT: def-shells with a translatable k=1 decreases measure (the descent-discharge candidate set; on SAFE + whole-SCC-measured ⇒ termination-verified)
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Body-VC types (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Sort environment: maps variable names to their FQ sorts.
-- Used by bodyToPredM to reject non-int vars in the QF-LIA fragment.
type SortEnv = Map Name FQSort

-- | A body verification condition tree.
data BodyVC
  = SimpleVC [LetBinding] FQPred
    -- ^ A straight-line sequence of let-bindings followed by a result predicate
  | BranchVC FQPred [(Name, FQSort, FQPred)] BodyVC BodyVC
    -- ^ A two-way branch: guard; binders INTRODUCED at this node (the synthetic
    --   match guard + arm payloads for a Result elimination, each later declared
    --   at trivial refinement FQTrue by 'collectBranchBinders'; empty @[]@ for an
    --   if-then-else or a hoisted branch); then-VC; else-VC.
  | CallVC                               -- ^ v0.9.0: Compositional call site
    { cvCallee         :: Name           -- ^ callee function name
    , cvArgs           :: [FQPred]       -- ^ translated argument predicates
    , cvPreObligation  :: Maybe FQPred   -- ^ callee pre after substitution (PROVE polarity)
    , cvPostAssumption :: Maybe FQPred   -- ^ callee post after substitution (ASSUME polarity)
    , cvResultVar      :: Name           -- ^ fresh result variable (_call_g_N)
    , cvResultSort     :: FQSort         -- ^ sort of the result
    , cvContinuation   :: BodyVC         -- ^ rest of the body after the call
    }
  deriving (Show, Eq)

-- | A single let-binding in the body VC.
data LetBinding = LetBinding
  { lbName :: Text     -- ^ Alpha-renamed variable name
  , lbSort :: FQSort   -- ^ Sort of the binding
  , lbRhs  :: FQPred   -- ^ RHS predicate (what the variable equals)
  } deriving (Show, Eq)

-- | A flattened path through the body-VC tree:
-- (path guard conjunction, accumulated let-bindings, result predicate)
type FlatPath = (FQPred, [LetBinding], FQPred)

-- ---------------------------------------------------------------------------
-- Compositional verification types (v0.9.0 COMP-1)
-- ---------------------------------------------------------------------------

-- | Contract environment: maps function names to their parameter lists,
-- contracts, and optional return type annotations.
-- Return type is needed for EMatch sort derivation (COMP-0 §5.3, Issue 5).
type ContractEnv = Map Name ([(Name, Type)], Contract, Maybe Type)

-- | Build a ContractEnv from top-level statements (alias map derived from the
-- same statements). Preserved as the single-file entry point.
buildContractEnv :: [Statement] -> ContractEnv
buildContractEnv stmts = buildContractEnvWith (buildAliasMap stmts) stmts

-- | xmod-ag: build a ContractEnv against an EXPLICIT alias map. A caller passes
-- the cache-aware merged map (entry ∪ imported STypeDefs, local-wins) so an
-- imported contract's nullary-ctor VALUES get the SAME int tags the entry body
-- uses (professor review: a split entry/import tag map is the cross-module
-- unsoundness — one merged map makes tags coherent by construction, and
-- buildCtorTagMap's "unambiguous only" guard fail-closes any residual clash).
-- Body is the original buildContractEnv; only 'am' is now a parameter.
buildContractEnvWith :: AliasMap -> [Statement] -> ContractEnv
buildContractEnvWith am stmts = Map.fromList $ mapMaybe go stmts
  where
    -- NIW (v0.12, F-NIW-1): fold refinement-aliased param predicates into each
    -- contract's effective precondition, so call-pre obligations prove them at
    -- call sites (intro-side).
    -- DEF-RET Unit 2: fold the return refinement into the EXPORTED post (the
    -- caller-assumable guarantee, consumed via assume-guarantee), the dual of
    -- the param-refinement pre fold. Unconditional/syntactic; verdict-gating is
    -- the downstream trust closure (refutedClosure / asserted-floor meet).
    ctorTags = buildCtorTagMap am
    -- COMP-3c / COMP-3b-general (cenv-desugar fix): desugar nullary-enum
    -- constructors in the STORED contract, not just at the definition site
    -- (emitFnConstraints, ~:415-419). The ContractEnv is consumed by CALLERS via
    -- assume-guarantee (CallVC); without this, a caller of a function whose contract
    -- uses nullary-enum constructors pulls them RAW into its .fq → liquid-fixpoint
    -- "Constraint with free vars" crash. The per-function bound-set (params)
    -- preserves shadowing, exactly as the definition-site desugar does.
    dsContract params c =
      let ds = desugarCtorValues ctorTags (Set.fromList (map fst params))
      in c { contractPre = ds <$> contractPre c, contractPost = ds <$> contractPost c }
    aug params mRet c = dsContract params (augmentContractPost am mRet (augmentContractPre am params c))
    -- R1 (bool-ret-synth): the ContractEnv third slot is the return type that CallVC's
    -- 'calleeRetSort' (~:2984) uses to sort a callee's opaque call-result binder. An
    -- annotation-less, post-less function with a syntactically boolean body (e.g. a
    -- predicate '(and (>= x 0) ...)') otherwise defaults that binder to FQInt, while an
    -- 'if'-guard consuming it elaborates '&&' at Bool — the sort mismatch that crashed
    -- liquid-fixpoint (regression of the BOOL-FRAG migration, v0.14.14). Synthesise
    -- 'Just TBool' for exactly that case so the binder sorts FQBool. Scoped to no-post so
    -- 'aug' (augmentContractPost) is a no-op and still sees the declared 'mRet' — the
    -- only value that changes is the third slot 'calleeRetSort' reads.
    synthRet mRet contract body
      | Nothing <- mRet, Nothing <- contractPost contract, bodyIsBoolean body = Just TBool
      | otherwise                                                             = mRet
    go (SDefLogic name params mRet contract body) = Just (name, (params, aug params mRet contract, synthRet mRet contract body))
    go (SLetrec name params mRet contract _dec body) = Just (name, (params, aug params mRet contract, synthRet mRet contract body))
    -- LT-INV (v0.11)
    go (SDef      name params mRet contract body) = Just (name, (params, aug params mRet contract, synthRet mRet contract body))
    go (SDefShell name params mRet contract body _dec) = Just (name, (params, aug params mRet contract, synthRet mRet contract body))
    -- v0.12.1: def-invariant registers in the VC env identically to SDefLogic.
    go (SDefInvariant name params mRet contract body) = Just (name, (params, aug params mRet contract, synthRet mRet contract body))
    go _ = Nothing

-- | R1 (bool-ret-synth): True when an expression is syntactically boolean-valued.
-- Reuses 'exprToPred' (the QF-LIA reflector, which normalises EOp→EApp) for leaf
-- op-classification and reads its FQPred result head; recurses through the control
-- forms 'exprToPred' rejects (EIf/ELet/EMatch). Conservative under-approximation:
-- any non-boolean-headed or unclassifiable leaf (a bare call, a variable, an int
-- literal, arithmetic) yields False, so it never mis-sorts an int result as Bool.
bodyIsBoolean :: Expr -> Bool
bodyIsBoolean (EIf _ t e)     = bodyIsBoolean t && bodyIsBoolean e
bodyIsBoolean (ELet _ b)      = bodyIsBoolean b
bodyIsBoolean (EMatch _ arms) = not (null arms) && all (bodyIsBoolean . snd) arms
bodyIsBoolean e               = maybe False isBoolHead (exprToPred e)

-- | The FQPred result heads that denote a boolean-valued expression. Comparisons
-- (FQBinPred) and the logical connectives are boolean; FQVar/FQLit/FQBinArith/FQApp
-- (arithmetic terms and opaque/uninterpreted applications) are not.
isBoolHead :: FQPred -> Bool
isBoolHead FQTrue          = True
isBoolHead FQFalse         = True
isBoolHead (FQBinPred _ _ _) = True
isBoolHead (FQAnd _)       = True
isBoolHead (FQOr _)        = True
isBoolHead (FQNot _)       = True
isBoolHead _               = False

-- | REC-DESCENT: name → (param names, termination measure TUPLE) for every
-- 'def-shell' that declares a non-empty 'decreases' clause. A k=1 tuple discharges
-- via the scalar '<'; a k>1 tuple discharges lexicographically (v0.14.27). k=0
-- (absent) is excluded — a plain unmeasured recursive fn stays
-- 'termination_unverified'. The param names let the descent emitter substitute the
-- call arguments into the callee's measure ('eᵍ[a/params_g]'), exactly as the
-- call-pre obligation substitutes the callee's precondition.
buildMeasureMap :: [Statement] -> Map Name ([Name], [Expr])
buildMeasureMap stmts = Map.fromList
  [ (n, (map fst params, dec))
  | SDefShell n params _ _ _ dec <- stmts, not (null dec) ]

-- | xmod-ag: build the imported half of a cross-module ContractEnv. For each
-- cached module, re-derive its contracts from its own statements THROUGH the
-- merged alias map 'am' (so nullary-ctor tags match the entry body), then key
-- each contract BOTH bare ('double') and fully-qualified ('lib.double') to
-- match either call-site form (opened import vs qualified access). 'Map.unions'
-- is left-biased across modules; a genuine bare-name clash across two imports
-- resolves arbitrarily but stays sound — the qualified key is always exact, and
-- the caller only ever looks up the name the type checker resolved.
--
-- Supersedes the dead v0.10 'buildContractEnvWithImports', which unioned RAW,
-- bare-only 'meContracts' (never desugared, never qualified) and was never
-- called.
-- FQ-RESULT-SORT-1 stage (b): this path REBUILDS the imported ContractEnv from
-- 'meStatements' rather than reading 'meContracts', so the raw optional annotation
-- used to be the only return-type signal available cross-module: a call to an
-- imported unannotated non-int-returning callee sorted its call-result binder at
-- FQInt. Override the third slot from the imported module's own recorded tau_ret
-- ('meRetTypes', populated by the loader's typecheck) before dual-keying, so both
-- the bare and qualified entries carry it.
seedImportedContracts :: AliasMap -> ModuleCache -> ContractEnv
seedImportedContracts am cache =
  Map.unions
    [ let bare0     = buildContractEnvWith am (meStatements menv)
          bare      = Map.mapWithKey
                        (\n (ps, c, mr) -> (ps, c, effRet (meRetTypes menv) n mr))
                        bare0
          prefix    = T.intercalate "." (mePath menv) <> "."
          qualified = Map.mapKeys (prefix <>) bare
      in Map.union bare qualified
    | menv <- Map.elems cache ]

-- | xmod-ag: cache-aware alias map. Local (entry) STypeDefs win over imported
-- ones (Map.union left-bias), matching TypeCheck.seedAliases, so buildCtorTagMap
-- assigns nullary-ctor tags that agree with the type checker's nominal-by-name
-- resolution. Empty cache ⇒ buildAliasMap stmts, unchanged.
cacheAwareAliasMap :: [Statement] -> ModuleCache -> AliasMap
cacheAwareAliasMap stmts cache =
  Map.union (buildAliasMap stmts)
            (Map.unions [ meAliasMap menv | menv <- Map.elems cache ])

-- | Cache-aware ContractEnv: entry contracts (shadowing) ∪ imported contracts
-- (dual-keyed, desugared against the merged alias map). The single recipe
-- shared by the verify path ('emitFixpointWithCache') and the checkout brief's
-- consumed_guarantees channel (XMOD-CG-BRIEF), so both consume the same
-- contract set. Empty cache ⇒ buildContractEnvWith aliases stmts.
cacheAwareContractEnv :: AliasMap -> [Statement] -> ModuleCache -> ContractEnv
cacheAwareContractEnv aliases stmts cache =
  Map.union (buildContractEnvWith aliases stmts)
            (seedImportedContracts aliases cache)

-- ---------------------------------------------------------------------------
-- Built-in qualifier safety net
-- ---------------------------------------------------------------------------

builtinQualifiers :: [FQQualifier]
builtinQualifiers =
  [ FQQualifier "True"  [("v", FQInt)]                       FQTrue
  , FQQualifier "GEZ"   [("v", FQInt)]                       (FQBinPred FQGe (FQVar "v") (FQLit 0))
  , FQQualifier "GTZ"   [("v", FQInt)]                       (FQBinPred FQGt (FQVar "v") (FQLit 0))
  , FQQualifier "EqZ"   [("v", FQInt)]                       (FQBinPred FQEq (FQVar "v") (FQLit 0))
  , FQQualifier "Eq"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQEq (FQVar "v") (FQVar "w"))
  , FQQualifier "GE"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQGe (FQVar "v") (FQVar "w"))
  , FQQualifier "GT"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQGt (FQVar "v") (FQVar "w"))
  ]

-- ---------------------------------------------------------------------------
-- Top-level emitter
-- ---------------------------------------------------------------------------

-- | Walk a list of top-level statements and emit a .fq constraint file.
-- The function is pure in terms of result, but uses IORef internally for
-- the sequential constraint-ID counter and ConstraintTable accumulator.
-- | Emit constraints using default options (no body VCs).
emitFixpoint :: FilePath -> [Statement] -> IO EmitResult
emitFixpoint = emitFixpointWith defaultEmitOptions

-- | Emit constraints with explicit options (single-file: empty module cache).
-- FQ-RESULT-SORT-1: the no-cache wrapper passes an EMPTY tau_ret map, so every
-- unannotated definition reaching it keeps the pre-change FQInt default. That is
-- today's behavior, not a regression, but it is also not the fix: the three synthetic
-- callers (weakness-check, CDP candidate, diverge-fill) run their own typecheck and
-- must supply their own map. Wiring those is stage (b); see
-- docs/design/finding-fq-result-sort-default.md "Affected surface".
emitFixpointWith :: EmitOptions -> FilePath -> [Statement] -> IO EmitResult
emitFixpointWith opts srcFile = emitFixpointWithCache opts srcFile Map.empty Map.empty

-- | xmod-ag: emit constraints with an explicit module cache, so a caller of an
-- IMPORTED contracted function verifies body-faithful (assume-guarantee against
-- the imported contract) instead of falling back to contract-only. Empty cache
-- ⇒ identical to the single-file path ⇒ byte-identical .fq (every union below
-- degenerates to the identity).
-- | FQ-RESULT-SORT-1: the effective return type tau_ret(f) = mRet |> tau_body.
-- A declared annotation always wins; absent one, the checker's synthesized body type
-- is used. Substituting at the 'emitFnConstraints' boundary (rather than editing each
-- of the five 'maybe FQInt sortA1 mRet' sites and the two admissibility guards
-- separately) is deliberate: every consumer inside reads the same 'mRet', so one
-- substitution fixes the sort derivation AND makes 'sigPairUnsafe' /
-- 'resultReturnUnsafe' evaluate against the real return type instead of failing open
-- on 'Nothing' (GUARD-EFFECTIVE). Sound for the two non-sort consumers as well:
-- 'augmentContractPost' folds only refinement ALIASES, which are annotation-only and
-- never synthesized, and 'bytesLenOf' can only match a declared 'bytes[n]' since
-- 'bytes-zero' already requires a declared return (LEVER-A0).
-- A synthesized 'TVar "?"' still lowers to FQInt here, i.e. today's behavior; the
-- HOLE-RET guard that routes it to a fallback is stage (c), not this change.
effRet :: Map Name Type -> Name -> Maybe Type -> Maybe Type
effRet _        _    r@(Just _) = r
effRet retTypes name Nothing    = Map.lookup name retTypes

emitFixpointWithCache :: EmitOptions -> FilePath -> ModuleCache -> Map Name Type -> [Statement] -> IO EmitResult
emitFixpointWithCache opts srcFile cache retTypes stmts = do
  let aliases = cacheAwareAliasMap stmts cache
  -- xmod-ag: the DATATYPE-DECL scan (only) widens to imported statements, so an
  -- assumed imported post mentioning a Pair2/Result constructor has its decl in
  -- the .fq. Per-function VC emission below stays entry-only — imported bodies
  -- are never re-verified (assume-guarantee is against the contract).
  let dataScanStmts = stmts ++ concatMap meStatements (Map.elems cache)
  -- xmod-ag: seed the body-VC ContractEnv with imported contracts (dual-keyed,
  -- desugared against the merged alias map). Entry contracts shadow imports.
  -- FQ-RESULT-SORT-1: the ContractEnv's third slot is the callee return type that
  -- 'calleeRetSort' uses to sort a call-result binder (_bv_call_<f>_N). Fixing only
  -- the definition-site 'result' binder is not enough: a call to an unannotated
  -- non-int-returning callee (including a SELF-recursive call) still emitted that
  -- binder at FQInt, so the body VC equated a bool 'result' with an int call result
  -- and liquid-fixpoint refused it. Override the slot with tau_ret here rather than
  -- threading a parameter through 'buildContractEnvWith', which is also consumed by
  -- the checkout-brief path (xmod-cg-brief) and must keep its signature.
  -- 'retTypes' is ENTRY-module only, so an imported callee keeps its declared mRet
  -- and today's behavior; carrying tau_ret across 'meContracts' is stage (b).
  -- 'synthRet' is deliberately left in place: it is the fallback for ContractEnv
  -- builders that receive no tau_ret, and retiring it here would regress the R1
  -- bool-ret-synth fix (v0.14.14) on those paths.
  let cenv = Map.mapWithKey
               (\n (ps, c, mr) -> (ps, c, effRet retTypes n mr))
               (cacheAwareContractEnv aliases stmts cache)
      measureMap = buildMeasureMap stmts   -- REC-DESCENT: name → (params, k=1 measure)
      callGraph = buildCallGraph stmts
      sccs = stronglyConnComp
        [(name, name, deps) | (name, deps) <- Map.toList callGraph]
      recursiveNames = Set.fromList $ concatMap getRecursive sccs
        where
          getRecursive (AcyclicSCC _) = []
          getRecursive (CyclicSCC ns) = ns
  ctrRef    <- newIORef (0 :: Int)  -- constraint ID counter
  bindRef   <- newIORef (0 :: Int)  -- binder ID counter
  tableRef  <- newIORef (Map.empty :: ConstraintTable)
  skippedRef<- newIORef ([] :: [Text])
  bindsRef  <- newIORef ([] :: [FQBind])
  constsRef <- newIORef ([] :: [FQConstraint])
  qualsRef  <- newIORef builtinQualifiers
  dataRef   <- newIORef ([] :: [FQDataDecl])
  -- v0.8.0: body-VC global alpha-renaming counter (E08: shared across functions)
  bodyCounterRef <- newIORef (0 :: Int)
  bodyFaithfulRef <- newIORef ([] :: [Text])
  bodyFallbackRef <- newIORef ([] :: [Text])
  diagsRef <- newIORef ([] :: [Diagnostic])
  emittedPreRef <- newIORef ([] :: [Text])
  emittedPostRef <- newIORef ([] :: [Text])
  callPreRef <- newIORef ([] :: [Text])  -- v0.9.0: functions with call-pre obligations
  overflowTaintedRef <- newIORef ([] :: [Text])  -- INT-1: body-faithful fns with unbounded-Int arithmetic

  let freshCid = do
        n <- readIORef ctrRef
        modifyIORef' ctrRef (+1)
        return n

  let freshBid = do
        n <- readIORef bindRef
        modifyIORef' bindRef (+1)
        return n

  let addBind b   = modifyIORef' bindsRef (++ [b])
  -- NIW (v0.12): inject ground measure range facts (m t >= 0) per occurring
  -- measure-term at the single point all constraints flow through. No-op when a
  -- constraint contains no FQApp, so measure-free .fq output is byte-identical.
  -- STRLIT: injectStrLitDistinct conjoins pairwise string-literal distinctness and
  -- injectStrLitLen (Stage 2) pins each literal's code-point length, both composed
  -- with the measure/byte range facts at the single choke point. Pure,
  -- constraint-derived (no per-function state); byte-inert without string literals.
  let addConst c  = modifyIORef' constsRef (++ [injectStrLitLen (injectStrLitDistinct (injectRangeFacts c))])
  let addQuals qs = modifyIORef' qualsRef (++ qs)
  let addData  d  = modifyIORef' dataRef  (++ [d])
  let addSkip  n  = modifyIORef' skippedRef (++ [n])
  let addOrigin cid orig = modifyIORef' tableRef (Map.insert cid orig)
  let addBodyFaithful n = modifyIORef' bodyFaithfulRef (++ [n])
  let addBodyFallback n = modifyIORef' bodyFallbackRef (++ [n])
  let addDiag d = modifyIORef' diagsRef (++ [d])
  let addEmittedPre n = modifyIORef' emittedPreRef (++ [n])
  let addEmittedPost n = modifyIORef' emittedPostRef (++ [n])
  let addCallPre n = modifyIORef' callPreRef (++ [n])  -- v0.9.0
  let addOverflowTainted n = modifyIORef' overflowTaintedRef (++ [n])  -- INT-1

  -- PAIR-RET: emit the polymorphic product datatype `data Pair2 2 = [ | pair2 {...} ]`
  -- exactly once, only when the module actually uses pairs — so a pair-free module's
  -- .fq stays byte-identical (the NIW byte-inert convention). The single parametric
  -- decl serves every (Pair2 s0 s1) applied sort; no per-sort-pair dedup is needed.
  when (moduleUsesPairs aliases dataScanStmts) $
    addData (FQDataDecl "Pair2" 2 [("pair2", [FQTyVar 0, FQTyVar 1])])

  -- COMP-4-RESULT: emit the polymorphic Result datatype once, only when the module
  -- CONSTRUCTS a Result (a `-> Result` admissible return or `(ok e)`/`(err e)` in a
  -- body/contract) — an eliminate-only module (Result param, scalar return, e.g.
  -- `settle`) never sorts a Result value (skolem path) and stays byte-identical.
  when (moduleConstructsResult aliases dataScanStmts) $
    addData (FQDataDecl "Result" 2 [("ok", [FQTyVar 0]), ("err", [FQTyVar 1])])

  -- Process each statement
  forM_ (zip [0..] stmts) $ \(idx, stmt) ->
    case stmt of
      STypeDef name body ->
        -- Emit ADT sorts for TSumType members
        forM_ (typeSorts aliases name body) addData

      SDefLogic name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames measureMap
          name params (effRet retTypes name mRet) contract (Just body) Nothing idx

      SLetrec name params mRet contract dec body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames measureMap
          name params (effRet retTypes name mRet) contract Nothing (Just dec) idx

      -- LT-INV (v0.11): SDef and SDefShell emit constraints identically to SDefLogic.
      SDef name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames measureMap
          name params (effRet retTypes name mRet) contract (Just body) Nothing idx

      -- REC-DESCENT (v0.14.25): a def-shell's k=1 measure is threaded as 'mDec'
      -- for well-foundedness (e ≥ 0), reusing the letrec constraint path; the
      -- per-call-site strict descent is emitted from 'measureMap' in the body
      -- block. k>1 (lexicographic) is accepted but not discharged (W-DECREASES-LEX);
      -- a measure on a non-recursive def-shell is unused (W-DECREASES-UNUSED).
      SDefShell name params mRet contract body dec -> do
        -- REC-DESCENT lexicographic (k≥1): the FULL measure tuple is threaded via
        -- 'measureMap' and drives BOTH well-foundedness (≥0 per component) and the
        -- per-call-site lexicographic descent. 'mDec' is now letrec-only (Nothing here).
        when (not (null dec) && Set.notMember name recursiveNames) $
          addDiag $ mkWarning Nothing $ "W-DECREASES-UNUSED: '" <> name
            <> "' declares a decreases measure but is not self-recursive; no descent obligation is emitted."
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames measureMap
          name params (effRet retTypes name mRet) contract (Just body) Nothing idx

      -- v0.12.1: def-invariant emits constraints identically to SDefLogic.
      SDefInvariant name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames measureMap
          name params (effRet retTypes name mRet) contract (Just body) Nothing idx

      _ -> pure ()

  -- Assemble result
  dataDecs  <- readIORef dataRef
  quals     <- readIORef qualsRef
  binds     <- readIORef bindsRef
  consts    <- readIORef constsRef
  table     <- readIORef tableRef
  skipped   <- readIORef skippedRef
  bfaithful <- readIORef bodyFaithfulRef
  bfallback <- readIORef bodyFallbackRef
  diags     <- readIORef diagsRef
  emPre     <- readIORef emittedPreRef
  emPost    <- readIORef emittedPostRef
  callPre   <- readIORef callPreRef
  ovTainted <- readIORef overflowTaintedRef
  -- NIW (v0.12): declare a UF constant for each measure symbol actually used in
  -- any constraint or binder. None used → empty section → byte-identical .fq.
  let ctorNames = Set.fromList $ concat
        [ fqCtorSym c : [ fqCtorSym c <> "_" <> T.pack (show i) | i <- [0 .. length flds - 1] ]
        | d <- dataDecs, (c, flds) <- ddCtors d ]
      -- COMP-4 (a): datatype constructors are declared via `data`, not as UF
      -- constants — exclude them from the measure-symbol sweep (else a spurious
      -- `constant full : ...` collides with the FQData constructor). PAIR-RET: also
      -- exclude the per-constructor *selectors* (`<ctor>_<i>`, the field names) — a
      -- pair projection `(pair2_0 r)` applies a datatype selector in goal position, so
      -- the selector symbol now appears in the sweep where COMP-4 (match-skolem
      -- elimination) never surfaced it.
      -- CDP deep-dive Rev 5 (routed finding): the sweep used to miss measures
      -- referenced ONLY by an auto-synthesized qualifier (extractQualifiers)
      -- and nowhere in a constraint or binder — e.g. a post-condition
      -- referencing 'list-length' on a function whose body-VC fell back, so
      -- no constraint ever mentions 'listLen'. The qualifier still does, and
      -- liquid-fixpoint crashes ("Qualifier with free vars") on the
      -- undeclared symbol. Scanning 'quals' too closes the gap; 'quals'
      -- includes 'builtinQualifiers' (pure int comparisons, no measure
      -- symbols), so this is a no-op for programs that don't hit the gap.
      -- LEVER-A1: the array-theory operation symbols are INTERPRETED by the
      -- solver (native map theory) — declaring them as UF constants would
      -- shadow the theory. Excluded from the sweep like datatype ctors.
      arrayTheorySyms = Set.fromList ["Map_select", "Map_store", "Map_default"]
      allAppNames = Set.unions $
           [ Set.union (appNames (reftPred (conLhs c))) (appNames (reftPred (conRhs c)))
           | c <- consts ]
        ++ [ appNames (reftPred (bindReft b)) | b <- binds ]
        ++ [ appNames (qualBody q) | q <- quals ]
      -- STRLIT: interned string-literal constants are NULLARY Str constants, not
      -- [Str]->int measure UFs — declare them separately and exclude them from the
      -- measure sweep (else measureConstant's default mis-declares them as unary
      -- functions and the solver sort-mismatches).
      strLitNames  = Set.filter ("strlit_" `T.isPrefixOf`) allAppNames
      strLitConsts = [ FQConstant n [] FQStr | n <- Set.toList strLitNames ]
      usedMeasures = allAppNames Set.\\ ctorNames Set.\\ arrayTheorySyms Set.\\ strLitNames
      measureConsts = map measureConstant (Set.toList usedMeasures)
  let fqFile = FQFile (measureConsts ++ strLitConsts) dataDecs quals binds consts
  return EmitResult
    { erFQFile            = fqFile
    , erFQText            = emitFQFile fqFile
    , erConstraintTable   = table
    , erSkipped           = skipped
    , erBodyFaithfulFns   = bfaithful
    , erBodyFallback      = bfallback
    , erDiagnostics       = diags
    , erEmittedPre        = emPre
    , erEmittedPost       = emPost
    , erCallPreFns        = callPre
    , erOverflowTaintedFns = ovTainted
    , erMeasuredFns        = [ n | (n, (_, es)) <- Map.toList measureMap, all (isJust . exprToPred) es ]
    }

-- ---------------------------------------------------------------------------
-- Per-function constraint emission
-- ---------------------------------------------------------------------------

emitFnConstraints
  :: EmitOptions
  -> FilePath
  -> IO FQConstraintId    -- fresh constraint ID
  -> IO FQBindId          -- fresh binder ID
  -> (FQBind       -> IO ())
  -> (FQConstraint -> IO ())
  -> ([FQQualifier] -> IO ())
  -> (Text -> IO ())       -- record skipped function
  -> (FQConstraintId -> ConstraintOrigin -> IO ())
  -> (Text -> IO ())       -- record body-faithful function
  -> (Text -> IO ())       -- record body-fallback function
  -> (Diagnostic -> IO ()) -- emit diagnostics
  -> (Text -> IO ())       -- v0.8.0: record emitted pre clause
  -> (Text -> IO ())       -- v0.8.0: record emitted post clause
  -> (Text -> IO ())       -- v0.9.0: record call-pre obligation
  -> (Text -> IO ())       -- INT-1: record overflow-tainted function
  -> IORef Int             -- body-VC alpha-renaming counter
  -> AliasMap              -- v0.8.0: type alias map for isIntLike
  -> ContractEnv           -- v0.9.0: contract environment for compositional VC
  -> Set.Set Name          -- v0.9.0: recursive SCC set
  -> Map Name ([Name], [Expr]) -- REC-DESCENT: name → (params, measure tuple)
  -> Name
  -> [(Name, Type)]
  -> Maybe Type
  -> Contract
  -> Maybe Expr            -- Just body = function body (Nothing for letrec)
  -> Maybe Expr            -- Just dec = letrec :decreases OR def-shell k=1 measure (well-foundedness)
  -> Int                   -- statement index (for JSON Pointer)
  -> IO ()
emitFnConstraints opts srcFile freshCid freshBid addBind addConst0 addQuals
    addSkip addOrigin addBodyFaithful addBodyFallback addDiag
    addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv sccSet measureMap
    name params mRet contract0 mBody mDec stmtIdx = do

  -- NIW (v0.12, F-NIW-1): fold refinement-aliased param predicates into this
  -- function's own effective precondition, so the body VC assumes them
  -- (elim-side). The intro-side (callers prove them) is handled via the
  -- augmented cenv in buildContractEnv.
  -- DEF-RET Unit 2: dually, fold a refinement-aliased RETURN into the effective
  -- postcondition, so the body VC PROVES it (introduction, §3.4.1). A non-Σ_auto
  -- return refinement makes the augmented post untranslatable → existing
  -- mPostPred=Nothing fallback (the §3.4.5 firewall) — no special guard needed.
  -- COMP-3b-general (Phase 1): desugar nullary-constructor values to int tags in
  -- the contract (and, below, the body) before translation, so an idiomatic enum
  -- function reduces to the int-tag QF-LIA form the verifier already discharges.
  let contractAug = augmentContractPost aliases mRet (augmentContractPre aliases params contract0)
      ctorTags    = buildCtorTagMap aliases
      dsExpr      = desugarCtorValues ctorTags (Set.fromList (map fst params))
      -- MATCH-WIDEN STRETCH (v0.14.12): a scrutinee-constructor clause `(= sig Continue)`
      -- over a two-arm PAYLOAD-bearing sum param rewrites to `(= sig$tag k)` (k = the
      -- constructor's declaration-order tag), discharging against the seeded free int
      -- tag the match's BranchVC declares — instead of leaving the opaque sum unsorted
      -- (FLOOR fallback). Scoped to NON-all-nullary two-arm sums: all-nullary enums are
      -- already lowered by desugarCtorValues/buildCtorTagMap, and the existing corpus
      -- has no mixed-sum `=Ctor` post, so this is a no-op there (equivalence preserved).
      -- Only params ACTUALLY MATCHED in the body qualify: a matched scrutinee's
      -- <v>$tag is declared by the match's BranchVC, so the desugared `<v>$tag=k` is
      -- well-sorted. A param referenced via `=Ctor` but never matched keeps its bare
      -- form → the FLOOR guard falls back to contract-only (no free-var crash).
      matchedVs   = maybe Set.empty matchedScrutVars mBody
      scrutTagMap = Map.fromList
        [ (v, Map.fromList (zip (map fst ctors) [0 ..]))
        | (v, t) <- params
        , v `Set.member` matchedVs
        , TSumType ctors <- [resolveAliasTy aliases t]
        , length ctors >= 2    -- MATCH-WIDEN-2: n-ary (was ==2); mixed sums only (any payload)
        , any (isJust . snd) ctors ]
      dsAll e     = desugarScrutCtor scrutTagMap (dsExpr e)
      contract    = contractAug { contractPre  = dsAll <$> contractPre contractAug
                                , contractPost = dsAll <$> contractPost contractAug }

  -- Only handle integer-typed parameters (linear arithmetic fragment)
  let intParams = [ (n, t) | (n, t) <- params, isScalarLike aliases t ]
  -- LEVER-A1: the per-function activation gate (§5). When on, bytes[n] params
  -- join the binder set at the array sort (family-1 fact in the binder reft),
  -- and the result sort of a bytes return is the array sort. When off — every
  -- function that neither mentions an array-class op nor calls an
  -- array-op-contracted callee, i.e. the whole pre-existing corpus — arrParams
  -- and mapParams are empty and sortA1 coincides with typeToSortA:
  -- byte-identical .fq.
  -- LEVER-A2: the gate's mention set widens to the map ops, and admissible
  -- map[int,int] params split into the two-array encoding (m$has / m$val,
  -- proposal §5 Rev 1.1: presence is an int-0/1 array). A map param at any
  -- other key/value sort is NOT split — the reflection cases require split
  -- binders (mapPairTermsB roots on them), so obligations over it fall back.
  let arrGate = arrGateActive cenv contract mBody
      arrParams = if arrGate
                    then [ (n, t) | (n, t) <- params, isJust (bytesLenOf aliases t) ]
                    else []
      mapParams = if arrGate
                    then [ (n, t) | (n, t) <- params, mapArrEncodableTy aliases t ]
                    else []
      -- LEVER-A2.2: the $val arrays of this function's bool-valued maps (params
      -- + result). Each occurring Map_select on one carries the ground value-
      -- range fact 0 ≤ v ≤ 1 (injectBoolValRangeFacts, wrapped into addConst
      -- below) — the byte-range discipline at the value sort, making the {0,1}
      -- encoding exact. Empty off-gate and for int-valued maps → byte-identical.
      boolValArrs = if arrGate
                      then Set.fromList
                             [ n <> "$val"
                             | (n, t) <- params ++ [ ("result", rt) | Just rt <- [mRet] ]
                             , boolValuedMapTy aliases t ]
                      else Set.empty
      addConst c = addConst0 (injectBoolValRangeFacts boolValArrs c)
      sortA1 t = case bytesLenOf aliases t of
                   Just _ | arrGate -> byteArraySort
                   _                -> typeToSortA aliases t
  -- NIW (v0.12): non-int params used as measure arguments get an opaque carrier
  -- binder so (strLen s) / (listLen xs) resolve to an in-scope symbol. Scoped to
  -- genuinely-used measure args (scan of contract + body) so measure-free
  -- functions emit byte-identical .fq.
  let measureVars = Set.unions
        [ maybe Set.empty measureArgVars (contractPre contract)
        , maybe Set.empty measureArgVars (contractPost contract)
        , maybe Set.empty measureArgVars mBody
        -- F-NIW-2: carrier vars passed as arguments to a measure-refined callee
        -- param need binding too, so the emitted call-pre obligation references
        -- an in-scope symbol (intro-side).
        , maybe Set.empty (collectCallArgCarrierVars aliases cenv) mBody
        -- STRLIT: string params compared against a string literal now reflect and
        -- need an in-scope FQStr carrier binder (contract clauses only — the body
        -- side already binds via its own VC machinery, per the `pos` witness).
        , maybe Set.empty strEqOperandVars (contractPre contract)
        , maybe Set.empty strEqOperandVars (contractPost contract)
        -- A2.2-string (residue lift): string params used as map-put VALUES need
        -- the FQStr carrier binder too — in contracts AND in the body (the body
        -- VC references the param name through the shared param binders).
        , maybe Set.empty mapPutValVars (contractPre contract)
        , maybe Set.empty mapPutValVars (contractPost contract)
        , maybe Set.empty mapPutValVars mBody
        -- A2.2-string (keys): string params used as map KEYS need the carrier too.
        , maybe Set.empty mapKeyVars (contractPre contract)
        , maybe Set.empty mapKeyVars (contractPost contract)
        , maybe Set.empty mapKeyVars mBody ]
      measureParams = [ (n, t) | (n, t) <- params
                      , n `Set.member` measureVars
                      , isMeasureSort aliases t
                      , not (isIntLike aliases t) ]
  -- v0.8.0: Fix dead early-exit — check condition and exit early if nothing to verify.
  let hasContract = isJust (contractPre contract) || isJust (contractPost contract)
      hasIntParams = not (null intParams)
  -- Only proceed if there are int params or contracts to verify
  if not hasIntParams && not hasContract
    then pure ()
    else do

    -- Emit binders for int params plus any measure-argument carrier params (NIW)
    -- plus, under the LEVER-A1 gate, bytes[n] params at the array sort.
    paramBinds <- mapM (emitParamBind aliases freshBid addBind) (intParams ++ measureParams ++ arrParams)
    -- LEVER-A2: each gated map[int,int] param splits into its two component
    -- binders (m$has at int-0/1, m$val at the value array), both unconstrained
    -- (FQTrue) — a symbolic map is an arbitrary pair of arrays; the encoding's
    -- semantics live in how the ops read/write the pair, not in binder facts.
    -- A2.2-string: the $val binder threads the value-array sort (Str for a
    -- string-valued map, else the int-element mapArraySort); $has is always
    -- int-0/1. This is the param-side of the single sort-threading seam.
    mapCompBinds <- fmap concat $ forM mapParams $ \(n, t) ->
      forM [("$has", mapHasArraySort aliases t), ("$val", mapValArraySort aliases t)] $ \(sfx, srt) -> do
        bid <- freshBid
        let b = FQBind bid (n <> sfx) (FQReft "v" srt FQTrue)
        addBind b
        return b
    let envIds = map bindId paramBinds ++ map bindId mapCompBinds

    -- Emit qualifiers extracted from pre/post
    -- BOOL-FRAG (v0.14.15): qualifier params must carry their REAL sort. A bool
    -- var emitted as `int` makes `(not b)` an ill-sorted `not` over int, which
    -- crashes liquid-fixpoint ("free vars [not]"); and/or survive by coercion but
    -- not does not. Sort result + params from the signature; others default int.
    let qualSortMap = Map.fromList $
          ("result", maybe FQInt sortA1 mRet)
          : [ (pn, sortA1 pt) | (pn, pt) <- params ]
        preQuals  = maybe [] (extractQualifiers qualSortMap "pre"  name) (contractPre contract)
        postQuals = maybe [] (extractQualifiers qualSortMap "post" name) (contractPost contract)
    addQuals (preQuals ++ postQuals)

    -- Emit standalone pre-condition constraint (legacy, non-body-VC mode only)
    -- v0.8.0: When body VCs are active, standalone pre/post constraints are
    -- suppressed. Body VCs encode the correct proof obligation:
    --   P ∧ (result = ⟦body⟧) ⟹ Q
    -- Standalone constraints (lhs true, rhs P) are not sound proof obligations.
    unless (emitBodyVCs opts) $ case contractPre contract of
      Nothing  -> pure ()
      Just pre ->
        case exprToPred pre of
          Nothing   -> addSkip name  -- non-linear: skip with note
          Just pred -> do
            cid  <- freshCid
            let lhs = FQReft "v" FQInt FQTrue   -- no lhs restriction
                rhs = FQReft "v" FQInt pred
                c   = FQConstraint cid envIds lhs rhs [name, "pre"]
            addConst c
            addEmittedPre name  -- v0.8.0: track that this pre actually emitted
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/pre"
            addOrigin cid (ConstraintOrigin name "pre" ptr srcFile)

    -- Emit standalone post-condition constraint (legacy, non-body-VC mode only)
    -- PAIR-RET-2: a non-sortable pair component would mis-sort the result binder
    -- here too; skip rather than emit a crash-inducing constraint.
    unless (emitBodyVCs opts || sigPairUnsafe aliases params mRet || resultReturnUnsafe aliases mRet) $ case contractPost contract of
      Nothing   -> pure ()
      Just post ->
        case exprToPred post of
          Nothing   -> addSkip name
          Just pred -> do
            cid    <- freshCid
            -- 'result' binder: type inferred from return annotation
            let retSort = maybe FQInt sortA1 mRet
            rbid   <- freshBid
            let resultBind = FQBind rbid "result" (FQReft "v" retSort FQTrue)
            addBind resultBind
            let lhs = FQReft "result" retSort FQTrue
                rhs = FQReft "result" retSort pred
                c   = FQConstraint cid (envIds ++ [rbid]) lhs rhs [name, "post"]
            addConst c
            addEmittedPost name  -- v0.8.0: track that this post actually emitted
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/post"
            addOrigin cid (ConstraintOrigin name "post" ptr srcFile)

    -- Emit well-foundedness constraints: pre ⟹ eᵢ ≥ 0, ONE PER measure component.
    -- REC-DESCENT lexicographic: a def-shell's FULL tuple comes from 'measureMap'
    -- (a ≥0 floor per component, so the lexicographic order on ℕᵏ is well-founded —
    -- professor ruling (a)); a letrec's single :decreases still comes from 'mDec'.
    -- The measure is a TERM (decPred), not a predicate — the constraint proves the
    -- value is a natural number, well-founding the < order the descent uses. k=1 is
    -- unchanged (a single ≥0, same constraint-id order → byte-identical .fq).
    let wfMeasures = case Map.lookup name measureMap of
                       Just (_, decs) -> decs             -- def-shell: full tuple
                       Nothing        -> maybe [] pure mDec  -- letrec: single measure
        mWfPre = contractPre contract >>= exprToPred
    forM_ wfMeasures $ \decE ->
      case exprToPred decE of
        Nothing      -> addSkip name  -- untranslatable component: skip (SCC stays partial)
        Just decPred -> do
          cid  <- freshCid
          let lhs = FQReft "v" FQInt (fromMaybe FQTrue mWfPre)
              rhs = FQReft "v" FQInt (FQBinPred FQGe decPred (FQLit 0))
              c   = FQConstraint cid envIds lhs rhs [name, "decreases"]
          addConst c
          let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/decreases"
          addOrigin cid (ConstraintOrigin name "decreases" ptr srcFile)

    -- v0.8.0: Emit body-faithful verification conditions
    -- Body VCs prove: P ∧ (result = ⟦body⟧) ⟹ Q
    when (emitBodyVCs opts && bodyVCTargeted opts name) $ case mBody of
      Nothing -> pure ()  -- letrec: no body VC (recursive, excluded from BODY-VC-0)
      Just body -> do
        -- Fallback policy (§0.7): require translatable post. If pre exists, it must
        -- also be translatable, otherwise fallback conservatively.
        -- DEF-RET Unit 2: `contract` here already has the return refinement folded
        -- into its post (augmentContractPost above), so a refinement-aliased return
        -- is proven as part of the post goal. A non-Σ_auto return refinement makes
        -- this post untranslatable → mPostPred=Nothing → fallback (§3.4.5 firewall),
        -- exactly the Unit-1 conservative behavior, now via the existing path.
        -- CLASSIFY-MEASURE: the three ungated type-level guards (PAIR-RET-2
        -- non-sortable pair component, COMP-4-RESULT non-admissible Result
        -- payload, MATCH-WIDEN bare opaque-sum param mention — each would
        -- crash or mis-sort liquid-fixpoint) are composed in
        -- 'contractSigGuardsBlock', which the classifier shares — one arbiter,
        -- no drift (§6.1).
        let mPostPred | contractSigGuardsBlock aliases params mRet contract = Nothing
                      -- LEVER-A1 (review F1): whole-structure = / /= over a bytes
                      -- operand is unconditionally out-of-fragment → contract-only
                      -- fallback (never reflected to array equality; §7 row 4).
                      -- LEVER-A2: same rule for map operands (wholeArrEqClause
                      -- covers both bytes-ish and map-ish operands).
                      | arrGate && (wholeArrEqClause aliases params mRet (contractPost contract)
                                 || wholeArrEqClause aliases params mRet (contractPre contract)) = Nothing
                      -- LEVER-A2: a map-op-bearing clause whose map-typed
                      -- params/result are not all admissible map[int,int], or
                      -- whose map-put value args are not int-in-context, would
                      -- reflect against binders that don't exist (or at the
                      -- wrong element sort) — free-var/ill-sort crash, not a
                      -- fallback. Route the whole contract to fallback instead
                      -- (§6.1: never a partial reflection).
                      | (exprMentionsMapOpM (contractPost contract)
                          || exprMentionsMapOpM (contractPre contract))
                        && mapClauseBlocked aliases params mRet
                             (contractPost contract) (contractPre contract) = Nothing
                      | otherwise                         = contractPost contract >>= exprToPred
            mPrePred  = case contractPre contract of
                          Nothing  -> Just Nothing       -- no pre is fine
                          Just pre -> case exprToPred pre of
                                        Nothing -> Nothing    -- pre exists but untranslatable → fallback
                                        Just p  -> Just (Just p)
        case (mPostPred, mPrePred) of
          (Nothing, _) -> addBodyFallback name  -- no translatable post → fallback
          (_, Nothing) -> addBodyFallback name  -- untranslatable pre → fallback
          (Just postPred, Just mPre) -> do
            -- Build SortEnv from int-typed parameters
            let body' = dsExpr body  -- COMP-3b-general: desugar enum match + ctor values
            -- COMP-3b-general (opaque-sum elimination): a Result-typed *variable*
            -- scrutinee (param or let-bound) is opaque to the int-only SortEnv, so
            -- the generic EMatch path cannot resolve its arm payload sorts. Seed the
            -- SortEnv with derived payload-sort keys ("<v>$ok"/"<v>$err"; '$' is not
            -- a legal source identifier char, so these cannot collide) for every
            -- Result-typed param; the EMatch case reads them to build the branch at
            -- ANY nesting depth (not just top level). The match guard and arm
            -- payloads are declared by 'collectBranchBinders' over the whole VC tree
            -- (generalizing the former single-shot extraResultBinds). This subsumes
            -- the former top-level-only flat-Result special-case.
            let sortEnv0 = buildSortEnv aliases params
                resultKeys =
                  [ kv
                  | (v, t) <- params
                  , TResult okT errT <- [resolveAliasTy aliases t]
                  , kv <- [ (v <> "$ok",  typeToSort okT)
                          , (v <> "$err", typeToSort errT) ] ]
                -- COMP-4 (d-elim): per-constructor payload-sort keys for an
                -- admissible two-arm USER sum-type param, so the generic EMatch
                -- path can opaque-sum-eliminate a match on it (same skolem-branch
                -- as Result). Seeded ONLY when both payloads are QF-LIA scalars
                -- (admissiblePayload); a sum/recursive payload is not seeded → the
                -- match falls back (firewall, design §5). Param-scoped, matching
                -- the Result seeding above.
                -- MATCH-WIDEN (v0.14.12): seed the payload-sort key for EACH
                -- payload-bearing constructor of a two-arm sum. A nullary constructor
                -- (Nothing payload) contributes no key (the mixed-arm case); a
                -- non-admissible (recursive) payload contributes no key → the match
                -- falls back (firewall). Both-payload sums seed both keys as before.
                adtKeys =
                  [ (v <> "$" <> c, typeToSort pt)
                  | (v, t) <- params
                  , TSumType ctors <- [resolveAliasTy aliases t]
                  , length ctors >= 2    -- MATCH-WIDEN-2: n-ary
                  , (c, Just pt) <- ctors
                  , admissiblePayload aliases pt ]
                -- MATCH-WIDEN STRETCH (S0): seed a free int TAG per two-arm sum param
                -- (Result or user ADT). The discrimination guard switches from the free
                -- boolean to (= v$tag k) in S1/S2; a post referencing the scrutinee's
                -- constructor desugars to (= v$tag k) in S3. Free int, QF-LIA — no testers.
                tagKeys =
                  [ (v <> "$tag", FQInt)
                  | (v, t) <- params
                  , case resolveAliasTy aliases t of
                      TResult _ _    -> True
                      TSumType ctors -> length ctors >= 2    -- MATCH-WIDEN-2: n-ary
                      _              -> False ]
                -- LEVER-A2: component-sort keys for each gated admissible
                -- map[int,int] param — the '$'-suffix discipline of the Result
                -- keys above. Their presence in the SortEnv is ALSO the body
                -- channel's admissibility witness: mapPairTermsB roots only on
                -- variables whose "$has" key is here.
                -- A2.2-string: string-valued map params join the body-channel
                -- SortEnv too, with the $val key at the Str array sort — the
                -- body-side of the sort-threading seam, so mapPairTermsB can root
                -- on them and the map-get result sort recovers Str from here.
                mapKeys =
                  [ kv
                  | arrGate
                  , (v, t) <- params
                  , mapArrEncodableTy aliases t
                  , kv <- [ (v <> "$has", mapHasArraySort aliases t)
                          , (v <> "$val", mapValArraySort aliases t) ] ]
                -- A2.2-string (residue lift): string params used as map-put
                -- VALUES join the body-channel SortEnv at FQStr, so strValTerm's
                -- var leg resolves them. Scoped to actual put-value occurrences
                -- (byte-inert otherwise, the NIW convention).
                strParamKeys =
                  [ (v, FQStr)
                  | (v, t) <- params
                  , isStrLike aliases t
                  , v `Set.member` maybe Set.empty
                      (\b -> mapPutValVars b `Set.union` mapKeyVars b) mBody ]
                sortEnv = foldr (uncurry Map.insert) sortEnv0 (resultKeys ++ adtKeys ++ tagKeys ++ mapKeys ++ strParamKeys)
                -- COMP-4 (b): parallel refinement env — each refined-payload
                -- Result/two-arm-ADT param payload's declared refinement, keyed
                -- identically to the sort keys. Unrefined payloads contribute
                -- nothing (FQTrue skolem, the d-elim behavior).
                resultRefs =
                  [ (key, ref)
                  | (v, t) <- params
                  , TResult okT errT <- [resolveAliasTy aliases t]
                  , (key, pt) <- [ (v <> "$ok", okT), (v <> "$err", errT) ]
                  , Just ref <- [payloadRefinement aliases pt] ]
                adtRefs =
                  [ (v <> "$" <> c, ref)
                  | (v, t) <- params
                  , TSumType ctors <- [resolveAliasTy aliases t]
                  , length ctors >= 2    -- MATCH-WIDEN-2: n-ary
                  , (c, Just pt) <- ctors
                  , admissiblePayload aliases pt
                  , Just ref <- [payloadRefinement aliases pt] ]
                refEnv = Map.fromList (resultRefs ++ adtRefs)
            -- LEVER-A2: a gated function RETURNING an admissible map[int,int]
            -- takes a dedicated emission: the body's component pair is PINNED
            -- to fresh result$has/result$val env binders on the constraint LHS
            -- (the A1 resultLenFact lesson: the constraint reft var `result`
            -- shadows a same-named env binder, but the $-suffixed component
            -- names are unshadowed), and the reflected post reads them via
            -- mapPairTermsC's `result` root.
            -- LEVER-A2.1: the accepted shape widens from "pure map term" to a
            -- STRAIGHT-LINE let-chain over map-gets and scalar defs ending in a
            -- pure map term — the read-modify-write class. The body is
            -- ANF-normalized first (hoisting embedded map-gets into lets, the
            -- same hoist set as the generic path), then 'mapRetChain' peels the
            -- spine: each map-get contributes a PROVE presence obligation
            -- (tag "call-pre:map-get") and an exact pin (v = value-select) on
            -- its binder; each scalar let pins its definition. Branches,
            -- embedded contracted calls, and shadowing → Nothing → contract-only
            -- fallback, whole (§6.1). Generic translation is SKIPPED for the
            -- dedicated path (mBodyVC forced Nothing) so the case below stays
            -- three-way at the original structure.
            seedD <- readIORef bodyCounterRef
            let anfNames = Map.keysSet cenv
                             `Set.union` Set.fromList ["bytes-get", "bytes-set", "map-get"]
                (bodyD, seedD') = evalState
                  (do r <- aNormalizeBody anfNames (expandMapLets (Map.keysSet cenv) body')
                      c <- get
                      return (r, c))
                  seedD
                -- A2.2-string residue lift: the dedicated map-returning path
                -- widens from map[int,int] to string-valued maps too — the
                -- chain translation (mapPairTermsB) is already value-sort-aware
                -- via the SortEnv, so a string RMW chain peels identically.
                mMapRetPair
                  | arrGate
                  , Just rt <- mRet
                  , mapArrEncodableTy aliases rt
                  = mapRetChain (if mapStrValuedTy aliases rt then FQStr else FQInt)
                                sortEnv bodyD
                  | otherwise = Nothing
            -- Commit the ANF counter only when the dedicated path is taken —
            -- otherwise the generic path re-reads the untouched ref
            -- (byte-inertness for everything else).
            when (isJust mMapRetPair) (writeIORef bodyCounterRef seedD')
            -- Translate body (generic path; Result-var matches handled within).
            seed <- readIORef bodyCounterRef
            let (newSeed, mBodyVC) =
                  if isJust mMapRetPair
                    then (seed, Nothing)
                    else bodyToPredFromR seed sortEnv refEnv scrutTagMap cenv sccSet body'
            writeIORef bodyCounterRef newSeed
            case (mMapRetPair, mBodyVC) of
              (Just tree, _) -> do
                -- F-011.3: flatten the guarded map-return tree; each leaf is one
                -- component-pin constraint with its path guard conjoined onto the
                -- LHS and its arm tag from provenance. A branch-free body is a
                -- single Nothing-provenance leaf with empty guards — byte-identical
                -- to the pre-F-011.3 straight-line emission (binder/constraint
                -- counters advance in the same order). Preserve the 4096-path cap
                -- (§6.1): a pathological branch fan-out falls back whole rather
                -- than emitting past the cap.
                let leaves = flattenMapRetTree tree
                    isMRGet MRGet{} = True
                    isMRGet _       = False
                if length (take 4097 leaves) > 4096
                  then do
                    addBodyFallback name
                    addDiag $ mkWarning Nothing $
                      "body VC for '" <> name <> "' exceeded 4096 path limit — "
                      <> "falling back to contract-only verification"
                  else do
                  -- Record the call-pre marker once per function (any leaf with a
                  -- chain get emits a presence obligation); 'addCallPre' appends,
                  -- so keep it out of the per-leaf loop to avoid duplicate entries.
                  when (any (\(steps, _, _, _) -> any isMRGet steps) leaves)
                       (addCallPre name)
                  forM_ leaves $ \(steps, guards, (hT, vT), prov) -> do
                    -- LEVER-A2.1: chain-step binders — pins ride the binder
                    -- refinement (the F-NIW-4b discipline), so both the presence
                    -- obligations and the final constraint see them via the env.
                    stepBindIds <- forM steps $ \st -> do
                      bid <- freshBid
                      case st of
                        -- A2.2-string: the get-step binder carries the chain's value
                        -- sort (Str for a string-map read) so the pin is well-sorted.
                        MRGet v _ sel vSort ->
                          addBind (FQBind bid v (FQReft "v" vSort
                                    (FQBinPred FQEq (FQVar "v") sel)))
                        MRDef v t ->
                          addBind (FQBind bid v (FQReft "v" FQInt
                                    (FQBinPred FQEq (FQVar "v") t)))
                      return bid
                    -- A2.2-string: result$val threads the return type's value-array
                    -- sort ((Map_t int Str) for a string-valued map return).
                    rhbid <- freshBid
                    addBind (FQBind rhbid "result$has"
                              (FQReft "v" (maybe mapArraySort (mapHasArraySort aliases) mRet) FQTrue))
                    rvbid <- freshBid
                    addBind (FQBind rvbid "result$val"
                              (FQReft "v" (maybe mapArraySort (mapValArraySort aliases) mRet) FQTrue))
                    -- LEVER-A2.1: PROVE-polarity presence obligation per chain get.
                    -- F-011.3: the path guard gates each obligation — a shared get
                    -- ahead of a branch is proven under g and under ¬g (jointly
                    -- unconditional); an arm-local get only under its arm's guard.
                    let getObls = [ pres | MRGet _ pres _ _ <- steps ]
                    forM_ getObls $ \pres -> do
                      ocid <- freshCid
                      let olhs = FQReft "v" FQInt (conjoinAll (maybe [] (:[]) mPre ++ guards))
                          orhs = FQReft "v" FQInt pres
                          oc = FQConstraint ocid (envIds ++ stepBindIds) olhs orhs
                                 [name, "call-pre:map-get"]
                      addConst oc
                      let optr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                      addOrigin ocid (ConstraintOrigin name "call-pre:map-get" optr srcFile)
                    cid <- freshCid
                    -- F-011.3: the else-arm's `result$has = m$has ∧ result$val = m$val`
                    -- for a returned param map is the body-VC aliasing of `result`
                    -- to ⟦body⟧ (component-pin discipline), NOT a surface `(= result m)`
                    -- of two independently-built maps — so it does not trip the
                    -- whole-structure-`=` firewall (contract channel only). Same
                    -- discipline MAP-RET-CALL already ships for call tails.
                    let pins = [ FQBinPred FQEq (FQVar "result$has") hT
                               , FQBinPred FQEq (FQVar "result$val") vT ]
                        lhsPred = conjoinAll (maybe [] (:[]) mPre ++ guards ++ pins)
                        lhs = FQReft "result" FQInt lhsPred
                        rhs = FQReft "result" FQInt postPred
                        tag = case prov of
                                Nothing    -> "body-post"
                                Just True  -> "body-post-then"
                                Just False -> "body-post-else"
                        c = FQConstraint cid (envIds ++ stepBindIds ++ [rhbid, rvbid]) lhs rhs [name, tag]
                    addConst c
                    let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                    addOrigin cid (ConstraintOrigin name tag ptr srcFile)
                  addBodyFaithful name
              (Nothing, Nothing) -> addBodyFallback name  -- body outside QF-LIA fragment
              (Nothing, Just bvc) -> do
                -- Path count check (bounded)
                let pathCount = countPathsBounded 4097 bvc  -- stop at 4097
                if pathCount > 4096
                  then do
                    -- >4096: fallback, not error
                    addBodyFallback name
                    addDiag $ mkWarning Nothing $
                      "body VC for '" <> name <> "' exceeded 4096 path limit — "
                      <> "falling back to contract-only verification"
                  -- LEVER-A2.1 sort guard: an INT-returning function whose body
                  -- tail is an array-sorted call result (a map-returning body
                  -- the dedicated mapRetChain path could not pin — a branch or
                  -- embedded call — that fell through with retSort defaulting to
                  -- FQInt) would emit an ill-sorted `result = rVar`. Route it to
                  -- fallback (§6.1). Gated on FQInt so a bytes/map return (whose
                  -- retSort IS the array sort, equating cleanly) is unaffected —
                  -- byteArraySort and mapArraySort are the same FQArr FQInt FQInt,
                  -- so the sort alone cannot distinguish them; the retSort gate
                  -- does.
                  -- MAP-RET-CALL (A4 finding F-2): a map-returning function whose
                  -- every path tail IS a map-returning call result no longer falls
                  -- back — the whole-map `result = rVar` the split encoding cannot
                  -- express becomes the COMPONENT pins result$has = rVar$has ∧
                  -- result$val = rVar$val (the mapRetChain terminal discipline,
                  -- extended to call tails). The callee's post is already on the
                  -- path, component-substituted (resultCompSubst), and rVar's
                  -- components are declared (compLBs) — only the final equation
                  -- was missing. Mixed tails (a param/pure-map arm alongside a
                  -- call arm) still fall back whole (refuse-not-pad, §6.1).
                  else if maybe FQInt sortA1 mRet == FQInt && arrayResultPath bvc
                          && not (arrGate && maybe False (mapArrEncodableTy aliases) mRet
                                  && all pinnableTail (flattenBodyVC bvc))
                    then addBodyFallback name
                    else do
                    -- Warn at 257-4096
                    when (pathCount > 256) $
                      addDiag $ mkWarning Nothing $
                        "body VC for '" <> name <> "' has "
                        <> T.pack (show pathCount) <> " paths (high path count may slow solver)"
                    -- Flatten and emit constraints
                    let paths = flattenBodyVC bvc
                        provs = pathBranchSides bvc  -- structural then/else provenance, positionally aligned with paths
                        retSort = maybe FQInt sortA1 mRet
                        -- LEVER-A1: the family-1 fact for a gated bytes[n] RETURN
                        -- (type-level truth: every bytes[n] value has length n). It
                        -- must ride the constraint LHS, not the result binder's
                        -- refinement — the constraint reft var `result` SHADOWS the
                        -- env binder of the same name, so a binder-level fact is
                        -- invisible exactly where it is needed (param binders are
                        -- not shadowed; theirs stay on the binder).
                        resultLenFact = case (if arrGate then mRet >>= bytesLenOf aliases else Nothing) of
                          Just blen -> [FQBinPred FQEq (FQApp "bytesLen" [FQVar "result"])
                                                       (FQLit (fromIntegral blen))]
                          Nothing   -> []
                    -- COMP-3b-general: declare every match-introduced binder across
                    -- the WHOLE VC tree (synthetic guard + arm payloads, at their
                    -- ok/err sort) so the per-arm body-VC constraints have no free
                    -- vars. Trivial refinement FQTrue = an arbitrary value of the
                    -- sort = the universal per-arm hypothesis. 'collectBranchBinders'
                    -- is the SOLE emitter of these binders (no double-declaration);
                    -- empty for a branch-free body.
                    extraBindIds <- mapM (\(vn, vs, vp) -> do
                      ebid <- freshBid
                      addBind (FQBind ebid vn (FQReft "v" vs vp))
                      return ebid) (collectBranchBinders bvc)
                    -- MAP-RET-CALL (F-2): in map-ret mode (map-returning fn whose
                    -- tails are call results — the 1034 guard admitted it), the
                    -- result is pinned COMPONENT-wise; a bare `result` binder is
                    -- neither needed nor meaningful (mapRetChain's convention:
                    -- the constraint reft var "result" at FQInt is unused).
                    let mapRetMode = maybe FQInt sortA1 mRet == FQInt && arrayResultPath bvc
                    forM_ (zip provs paths) $ \(prov, (guard, lbs, resultPred)) -> do
                      -- Emit binders for each let-binding in this path
                      lbBindIds <- mapM (\lb -> do
                        bid <- freshBid
                        let b = FQBind bid (lbName lb) (FQReft "v" (lbSort lb)
                                  (FQBinPred FQEq (FQVar "v") (lbRhs lb)))
                        addBind b
                        return bid) lbs
                      -- Emit result binder(s): the scalar result, or (map-ret
                      -- mode) the split result$has/result$val components at the
                      -- return type's array sorts.
                      resultBindIds <- if mapRetMode
                        then do
                          rh <- freshBid
                          addBind (FQBind rh "result$has"
                                    (FQReft "v" (maybe mapArraySort (mapHasArraySort aliases) mRet) FQTrue))
                          rv <- freshBid
                          addBind (FQBind rv "result$val"
                                    (FQReft "v" (maybe mapArraySort (mapValArraySort aliases) mRet) FQTrue))
                          return [rh, rv]
                        else do
                          rbid <- freshBid
                          addBind (FQBind rbid "result" (FQReft "v" retSort FQTrue))
                          return [rbid]
                      -- Build LHS: guard ∧ pre ∧ (result = body-result), where the
                      -- map-ret equation is the component pin pair.
                      let resultEqs = case resultPred of
                            FQVar v | mapRetMode ->
                              [ FQBinPred FQEq (FQVar "result$has") (FQVar (v <> "$has"))
                              , FQBinPred FQEq (FQVar "result$val") (FQVar (v <> "$val")) ]
                            _ -> [FQBinPred FQEq (FQVar "result") resultPred]
                          lhsPred  = conjoinAll $ [guard | guard /= FQTrue]
                                                ++ maybe [] (:[]) mPre
                                                ++ resultLenFact
                                                ++ resultEqs
                          lhs = FQReft "result" retSort lhsPred
                          rhs = FQReft "result" retSort postPred
                      -- Determine tag from structural branch provenance (the
                      -- outermost branch side this path descends from), not a
                      -- path-index midpoint — the midpoint mislabeled the refuted
                      -- arm under unbalanced nesting (unequal then/else path counts).
                      let tag = case prov of
                                  Nothing    -> "body-post"
                                  Just True  -> "body-post-then"
                                  Just False -> "body-post-else"
                      cid <- freshCid
                      let allEnvIds = envIds ++ extraBindIds ++ lbBindIds ++ resultBindIds
                          c = FQConstraint cid allEnvIds lhs rhs [name, tag]
                      addConst c
                      let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                      addOrigin cid (ConstraintOrigin name tag ptr srcFile)
                    -- Mark as body-faithful
                    addBodyFaithful name

                    -- INT-1 (v0.10.8): tagged body-faithful fns whose body used
                    -- LLMLL-level integer arithmetic over non-literal operands.
                    -- LT-INT (v0.11): trigger set is empty — `int` is now Integer
                    -- at codegen, so no `int` arithmetic can overflow at runtime.
                    -- The walker `bodyHasOverflowArith` and the `erOverflowTainted`
                    -- field are preserved across the module surface; INT-3 re-arms
                    -- the trigger when the `machine-int` primitive lands (gated by
                    -- callee/operand type-awareness, not by the syntactic walker).
                    -- See docs/design/int-2-boundary-shims.md §4.
                    -- when (bodyHasOverflowArith body) (addOverflowTainted name)

                    -- v0.9.0: Emit call-pre obligations for any CallVC nodes
                    -- Each obligation is a separate constraint proving the callee's
                    -- precondition is satisfied at the call site.
                    let callObligations = collectCallPreObligations bvc
                    unless (null callObligations) $ do
                      addCallPre name
                      forM_ (zip [0::Int ..] callObligations) $ \(cpIdx, (callee, prePred, pathGuard, ctxCalls, pathLbs)) -> do
                        -- F-NIW-4: declare the prior-call result vars on this path so
                        -- a precondition referencing one is not a free variable; their
                        -- assumed posts join the LHS hypothesis (assume-guarantee).
                        -- LEVER-A2.1: a map-returning prior call also declares its
                        -- split components (rv$has/rv$val) — the assumed post and a
                        -- later map-op obligation root on them.
                        -- A2.2-string: string-map returns (strMapArraySort marker)
                        -- split too; $val carries the marker's value sort.
                        let ctxDecls = concat
                              [ (rv, rs) : [ (rv <> "$has", markerHasSort rs)
                                           | isMapArrRetSort rs ]
                                        ++ [ (rv <> "$val", markerValSort rs)
                                           | isMapArrRetSort rs ]
                              | (rv, rs, _) <- ctxCalls ]
                        ctxBindIds <- mapM (\(dv, ds) -> do
                          bid <- freshBid
                          addBind (FQBind bid dv (FQReft "v" ds FQTrue))
                          return bid) ctxDecls
                        -- F-NIW-4b: declare the in-scope let-bound non-call values on
                        -- this path with their defining equality, so a precondition
                        -- referencing one is provable. Filtered to the subset whose RHS
                        -- is in scope (params ∪ prior results ∪ earlier lbs).
                        let priorRVars = [ rv | (rv, _, _) <- ctxCalls ]
                            scope0     = Set.fromList (map bindName paramBinds ++ priorRVars)
                            usableLbs  = inScopeLbs scope0 (nub pathLbs)
                        lbCtxBindIds <- mapM (\lb -> do
                          bid <- freshBid
                          addBind (FQBind bid (lbName lb) (FQReft "v" (lbSort lb)
                                    (FQBinPred FQEq (FQVar "v") (lbRhs lb))))
                          return bid) usableLbs
                        cid <- freshCid
                        let cpTag = "call-pre:" <> callee
                            ctxPosts = [ post | (_, _, post) <- ctxCalls, post /= FQTrue ]
                            -- LHS: path guard ∧ caller pre ∧ prior-call assumed posts
                            lhsPred = conjoinAll $ [pathGuard | pathGuard /= FQTrue]
                                                 ++ maybe [] (:[]) mPre
                                                 ++ ctxPosts
                            lhs = FQReft "v" FQInt lhsPred
                            -- RHS: callee's precondition (PROVE polarity — caller must prove this)
                            rhs = FQReft "v" FQInt prePred
                            c = FQConstraint cid (envIds ++ ctxBindIds ++ lbCtxBindIds) lhs rhs [name, cpTag]
                        addConst c
                        let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                        addOrigin cid (ConstraintOrigin name cpTag ptr srcFile)

                    -- REC-DESCENT (v0.14.25): strict-descent obligations. For each
                    -- intra-SCC call f→g where BOTH f and g declare a k=1 measure,
                    -- emit  pathGuard ∧ preᶠ ∧ ctxPosts ⟹ eᵍ[a/params_g] < eᶠ
                    -- (tag "descent"). Common ℕ order (< floored by the ≥0
                    -- well-foundedness constraint) — sound for different-measure
                    -- mutual recursion (Floyd ranking; professor Q2). A callee with
                    -- no measure, or an untranslatable measure, emits no descent
                    -- constraint (the SCC stays termination_unverified; §3.4.5).
                    -- REC-DESCENT lexicographic (k≥1): the caller's FULL tuple. Every
                    -- component must translate (any untranslatable → no descent, the
                    -- SCC stays termination_unverified; §3.4.5 firewall).
                    case Map.lookup name measureMap of
                      Nothing -> pure ()   -- f declares no measure
                      Just (_fParams, fMeasEs) -> case traverse exprToPred fMeasEs of
                        Nothing ->           -- some caller measure component untranslatable
                          addDiag $ mkWarning Nothing $ "decreases measure of '" <> name
                            <> "' has a non-linear-arithmetic component; no descent obligation emitted "
                            <> "(the function stays termination_unverified)."
                        Just fMeasPreds ->
                          forM_ (collectDescentSites bvc) $ \(callee, cArgs, pathGuard, ctxCalls, pathLbs) ->
                            when (Set.member callee sccSet) $
                              case Map.lookup callee measureMap of
                                Nothing -> pure ()   -- callee unmeasured → SCC not fully-declared; stays partial
                                Just (gParams, gMeasEs) -> case traverse exprToPred gMeasEs of
                                  Nothing -> pure ()  -- callee component untranslatable → skip (stays partial)
                                  Just gMeasPreds
                                    -- EQUAL-LENGTH GATE (professor ruling (b)): a
                                    -- lexicographic '<' between tuples of DIFFERENT arity is
                                    -- undefined; refuse cleanly (SCC stays partial). NEVER
                                    -- prefix-compare/truncate — that is the one unsound move.
                                    | length gMeasPreds /= length fMeasPreds -> pure ()
                                    | otherwise -> do
                                    let subst       = Map.fromList (zip gParams cArgs)
                                        gMeasSubsts = map (applySubst subst) gMeasPreds
                                        priorRVars  = [ rv | (rv, _, _) <- ctxCalls ]
                                        scope0      = Set.fromList (map bindName paramBinds ++ priorRVars)
                                        usableLbs   = inScopeLbs scope0 (nub pathLbs)
                                    -- LEVER-A2.1: expand map-returning prior-call
                                    -- results into their split components (mirrors
                                    -- the call-pre emission above).
                                    -- A2.2-string: mirrors the call-pre ctxDecls widening.
                                    let dCtxDecls = concat
                                          [ (rv, rs) : [ (rv <> "$has", markerHasSort rs)
                                                       | isMapArrRetSort rs ]
                                                    ++ [ (rv <> "$val", markerValSort rs)
                                                       | isMapArrRetSort rs ]
                                          | (rv, rs, _) <- ctxCalls ]
                                    ctxBindIds <- mapM (\(dv, ds) -> do
                                      bid <- freshBid
                                      addBind (FQBind bid dv (FQReft "v" ds FQTrue))
                                      return bid) dCtxDecls
                                    lbCtxBindIds <- mapM (\lb -> do
                                      bid <- freshBid
                                      addBind (FQBind bid (lbName lb) (FQReft "v" (lbSort lb)
                                                (FQBinPred FQEq (FQVar "v") (lbRhs lb))))
                                      return bid) usableLbs
                                    dcid <- freshCid
                                    let ctxPosts = [ post | (_, _, post) <- ctxCalls, post /= FQTrue ]
                                        lhsPred = conjoinAll $ [pathGuard | pathGuard /= FQTrue]
                                                             ++ maybe [] (:[]) mPre
                                                             ++ ctxPosts
                                        lhs = FQReft "v" FQInt lhsPred
                                        -- callee tuple <_lex caller tuple (k=1 → bare '<')
                                        rhs = FQReft "v" FQInt (lexLess gMeasSubsts fMeasPreds)
                                        dc  = FQConstraint dcid (envIds ++ ctxBindIds ++ lbCtxBindIds) lhs rhs [name, "descent"]
                                    addConst dc
                                    let dptr = "/statements/" <> T.pack (show stmtIdx) <> "/decreases"
                                    addOrigin dcid (ConstraintOrigin name "descent" dptr srcFile)

                    -- COMP-4 (b) intro-side: payload-subtyping obligations. For
                    -- each call passing an arg to a refined-payload Result/ADT
                    -- param, emit ∀v. p_arg(v) ⟹ p_param(v) as a standalone
                    -- refinement-subtyping constraint (Vazou ICFP14; liquid-
                    -- fixpoint's native operation). Syntactic-reflexivity fast-
                    -- path: NO constraint when the arg's payload refinement equals
                    -- the param's (the param-forwarding case). A forwarded-param
                    -- arg sources p_arg from refEnv; any other arg is unrefined
                    -- (FQTrue) → a refined param payload is then unprovable →
                    -- refused (sound). The declaration-driven obligation makes the
                    -- elim-side assumption (Stage 1b) sound.
                    forM_ (collectCallSites bvc) $ \(callee, callArgs) ->
                      case Map.lookup callee cenv of
                        Nothing -> return ()
                        Just (calleeParams, _, _) ->
                          forM_ (zip calleeParams callArgs) $ \((_, pt), argPred) ->
                            forM_ (payloadArms aliases pt) $ \(armKey, payT) ->
                              case payloadRefinement aliases payT of
                                Nothing -> return ()
                                Just (xbP, pParamE) -> do
                                  let mArgRef = case argPred of
                                        FQVar a -> Map.lookup (a <> armKey) refEnv
                                        _       -> Nothing
                                      reflexive = case mArgRef of
                                        Just (xbA, pA) -> renameVar xbA "v" pA == renameVar xbP "v" pParamE
                                        Nothing        -> False
                                  unless reflexive $ do
                                    let psort    = typeToSort (resolveAliasTy aliases payT)
                                        pParamFQ = fromMaybe FQTrue (exprToPred (renameVar xbP "v" pParamE))
                                        pArgFQ   = case mArgRef of
                                          Just (xbA, pA) -> fromMaybe FQTrue (exprToPred (renameVar xbA "v" pA))
                                          Nothing        -> FQTrue
                                        subTag   = "payload-sub:" <> callee
                                    scid <- freshCid
                                    let sc = FQConstraint scid envIds (FQReft "v" psort pArgFQ) (FQReft "v" psort pParamFQ) [name, subTag]
                                    addConst sc
                                    let sptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                                    addOrigin scid (ConstraintOrigin name subTag sptr srcFile)

-- NIW (v0.12): alias-aware so a refinement-aliased param (e.g. `w : Word`)
-- gets its carrier sort (Str/Lst) rather than the typeToSort default (int).
emitParamBind :: AliasMap -> IO FQBindId -> (FQBind -> IO ()) -> (Name, Type) -> IO FQBind
emitParamBind aliases freshBid addBind (n, t) = do
  bid <- freshBid
  -- LEVER-A1: a bytes[n] param (reachable ONLY via the gated arrParams list —
  -- bytes is neither scalar-like nor a measure sort, so an ungated function
  -- never sends one here) binds at the array sort.
  --
  -- FACT-AG-LEN (Stage 1): the binder carries NO length fact. `bytesLen(v) = n`
  -- used to ride here ('bytesLenReft'), which put it in every VC antecedent with
  -- nothing discharging it (SAFE-ARG). It is now contributed to the effective
  -- PRECONDITION by 'bytesLenParamPre', so callers prove it and the body assumes
  -- it, exactly as for a hand-written `pre`. The SORT stays 'byteArraySort':
  -- dropping the whole clause would fall through to typeToSort's conservative
  -- FQInt default and emit ill-sorted `bytesLen` applications.
  let reft = case bytesLenOf aliases t of
        Just _   -> FQReft "v" byteArraySort FQTrue
        Nothing  -> FQReft "v" (typeToSort (resolveAliasTy aliases t)) FQTrue
      b = FQBind bid n reft
  addBind b
  return b

-- MATCH-WIDEN (v0.14.12): does a contract clause reference a sum-typed PARAMETER by
-- its bare name? An opaque sum has no value sort in the current encoding (only its arm
-- payloads are seeded via the "<v>$<Ctor>" keys), so a clause like a post
-- `(= sig Continue)` over a scrutinee `sig : Step` would leave `sig` free/unsorted and
-- CRASH liquid-fixpoint ("Constraint with free vars [sig]"). Detect it and fall back to
-- contract-only, matching the 'sigPairUnsafe' / 'resultReturnUnsafe' precedent. Fires
-- only when a sum param is named directly (a post over `result`, or a discharge post
-- that only reads the arm bodies, does not fire).
clauseOverOpaqueSumParam :: AliasMap -> [(Name, Type)] -> Maybe Expr -> Bool
clauseOverOpaqueSumParam _  _      Nothing       = False
clauseOverOpaqueSumParam am params (Just clause) =
  any (\(v, t) -> isSumTy (resolveAliasTy am t) && exprMentionsVar v clause) params
  where
    -- ENUM-EQ-FALLBACK: an all-nullary enum param is NOT opaque — it is
    -- int-tag-desugared (isIntLike/desugarCtorValues, COMP-3b-general) and lives
    -- in the sort env as FQInt, so a clause naming it is well-sorted. Firing on
    -- it forced contract-only fallback and silently lost refutation
    -- (v0.14.12–v0.14.31). Only a payload-bearing sum is value-opaque.
    isSumTy (TSumType ctors) = any (isJust . snd) ctors
    isSumTy _                = False

-- | Local free-mention check (TypeCheck.exprContainsVar is not imported here).
exprMentionsVar :: Name -> Expr -> Bool
exprMentionsVar target = go
  where
    go (EVar n)      = n == target
    go (EApp _ as)   = any go as
    go (EOp _ as)    = any go as
    go (EIf c t e)   = go c || go t || go e
    go (ELet bs b)   = any (\(_, _, e) -> go e) bs || go b
    go (EMatch e cs) = go e || any (go . snd) cs
    go (EPair a b)   = go a || go b
    go (ELambda _ b) = go b
    go _             = False

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- ADMIT-SHARED: 'AliasMap', 'buildAliasMap', 'resolveAliasTy', 'isIntLike',
-- 'isBoolLike', 'isStrLike', 'isScalarLike', 'bytesLenOf' and 'boolValuedMapTy'
-- now live in 'LLMLL.TypeAdmissibility', a leaf module the type checker imports
-- too, so the checker's admission guard and this module's fact-injection gates
-- are the SAME functions rather than mirrored ones (CR-01 was their
-- disagreement). They are re-exported from here, so existing consumers
-- (RefineReuse, ObligationAssembly, ObligationMining) are unchanged.
--
-- The moved definitions gained a per-traversal cycle guard. This module's
-- previous 'resolveAliasTy' would diverge on a non-contractive alias and was
-- shielded only by 'check' failing before 'verify' ran; the checker now calls
-- the same function, so the guard is required rather than defensive.

-- ---------------------------------------------------------------------------
-- LEVER-A1/A2: bytes[n] + map[int,int] static discharge
-- (data-scope-lever-a-arrays-proposal.md, Rev 1.1). The array class activates
-- PER FUNCTION (the §5 activation gate) so every function outside the gate
-- emits byte-identical .fq. A2 reflects map[int,int] via the two-array
-- encoding (m$has int-0/1 presence + m$val values); string/bool-VALUED maps
-- and cross-call map assume-guarantee are deferred (fall back whole, §6.1 —
-- never a partial reflection).
-- ---------------------------------------------------------------------------

-- | The reflected bytes-op family (stage A1). NOT the map ops.
bytesOpNames :: [Name]
bytesOpNames = ["bytes-length", "bytes-get", "bytes-set", "bytes-zero"]

-- | The reflected map-op family (stage A2).
mapOpNames :: [Name]
mapOpNames = ["map-has", "map-get", "map-put", "map-empty"]

-- | The bytes[n] lowering: int-indexed, int-element SMT array (elements are
-- byte values 0–255; the range is a ground fact per read, injectRangeFacts).
byteArraySort :: FQSort
byteArraySort = FQArr FQInt FQInt

-- | Family-1 ground fact as a binder refinement: @bytesLen(v) = n@ — the
-- type-level length becomes a solver fact on the binder itself, in scope of
-- every constraint that uses it (path-(a) discipline: ground per binder, never
-- a quantified axiom).
bytesLenReft :: Int -> FQReft
bytesLenReft n = FQReft "v" byteArraySort
  (FQBinPred FQEq (FQApp "bytesLen" [FQVar "v"]) (FQLit (fromIntegral n)))

-- | Does an expression mention any op in the given family (any nesting)?
exprMentionsOpIn :: [Name] -> Expr -> Bool
exprMentionsOpIn ops = go
  where
    go (EApp f args)  = f `elem` ops || any go args
    go (EOp  f args)  = f `elem` ops || any go args
    go (EIf c t e)    = go c || go t || go e
    go (ELet bs b)    = any (\(_, _, r) -> go r) bs || go b
    go (EMatch s as)  = go s || any (go . snd) as
    go (ELambda _ b)  = go b
    go (EDo steps)    = any (\(DoStep _ e) -> go e) steps
    go (EPair a b)    = go a || go b
    go (EAwait e)     = go e
    go _              = False

exprMentionsBytesOp :: Expr -> Bool
exprMentionsBytesOp = exprMentionsOpIn bytesOpNames

exprMentionsMapOp :: Expr -> Bool
exprMentionsMapOp = exprMentionsOpIn mapOpNames

exprMentionsMapOpM :: Maybe Expr -> Bool
exprMentionsMapOpM = maybe False exprMentionsMapOp

-- | Any array-class op (bytes or map) — the LEVER-A2 gate's mention set.
exprMentionsArrOp :: Expr -> Bool
exprMentionsArrOp = exprMentionsOpIn (bytesOpNames ++ mapOpNames)

contractMentionsBytesOp :: Contract -> Bool
contractMentionsBytesOp c =
     maybe False exprMentionsBytesOp (contractPre c)
  || maybe False exprMentionsBytesOp (contractPost c)

contractMentionsMapOp :: Contract -> Bool
contractMentionsMapOp c =
     exprMentionsMapOpM (contractPre c)
  || exprMentionsMapOpM (contractPost c)

contractMentionsArrOp :: Contract -> Bool
contractMentionsArrOp c = contractMentionsBytesOp c || contractMentionsMapOp c

-- | LEVER-A3: the classifier-side composition of the SAME two array guards the
-- contract channel runs before reflecting (the mPostPred chain above): True
-- when the emitter would force contract-only fallback for array reasons —
-- whole-structure = / /= over an array operand (review F1), or a map-op clause
-- over inadmissible map types / non-int put values (the A2 crash-class guard).
-- Exported so ObligationMining/ObligationAssembly classify with the emitter's
-- own predicates instead of a drift-prone reimplementation (§6.1: the
-- classifier's job is deciding exact-reflectability per obligation).
contractArrGuardsBlock :: AliasMap -> [(Name, Type)] -> Maybe Type -> Contract -> Bool
contractArrGuardsBlock am params mRet c =
     wholeArrEqClause am params mRet (contractPost c)
  || wholeArrEqClause am params mRet (contractPre c)
  || (contractMentionsMapOp c
      && mapClauseBlocked am params mRet (contractPost c) (contractPre c))

-- | CLASSIFY-MEASURE: the UNGATED type-level legs of the contract channel's
-- fallback decision — the exact guards 'mPostPred' runs before reflecting,
-- independent of the array activation gate: a non-sortable pair component
-- ('sigPairUnsafe'), a non-admissible Result payload ('resultReturnUnsafe'),
-- or a clause naming a payload-bearing sum param bare
-- ('clauseOverOpaqueSumParam'). 'mPostPred' composes THIS function, so the
-- classifier and the emitter cannot drift: classification calls the same
-- arbiter the emitter falls back on. (The gated array legs stay separate in
-- 'contractArrGuardsBlock' because the emitter applies them only under
-- 'arrGateActive'.)
contractSigGuardsBlock :: AliasMap -> [(Name, Type)] -> Maybe Type -> Contract -> Bool
contractSigGuardsBlock am params mRet c =
     sigPairUnsafe am params mRet
  || resultReturnUnsafe am mRet
  || clauseOverOpaqueSumParam am params (contractPost c)
  || clauseOverOpaqueSumParam am params (contractPre c)

-- | The §5 activation gate. On when the function's own contract or body
-- mentions an array-class op (bytes or, since A2, map), or its body calls a
-- contracted callee whose contract does (the callee's pre/post is translated
-- at the call site, so the CALLER's VC carries the reflected terms and needs
-- the array binders). Off — the entire pre-existing corpus — nothing changes.
arrGateActive :: ContractEnv -> Contract -> Maybe Expr -> Bool
arrGateActive cenv contract mBody =
     contractMentionsArrOp contract
  || maybe False exprMentionsArrOp mBody
  || maybe False calleeCarries mBody
  where
    calleeCarries e = any calleeHit (Set.toList (calledNames e))
    calleeHit f = case Map.lookup f cenv of
      Just (_, c, _) -> contractMentionsArrOp c
      Nothing        -> False
    calledNames :: Expr -> Set.Set Name
    calledNames (EApp f args)  = Set.insert f (Set.unions (map calledNames args))
    calledNames (EOp  f args)  = Set.insert f (Set.unions (map calledNames args))
    calledNames (EIf c t e)    = Set.unions [calledNames c, calledNames t, calledNames e]
    calledNames (ELet bs b)    = Set.unions (calledNames b : [ calledNames r | (_, _, r) <- bs ])
    calledNames (EMatch s as)  = Set.unions (calledNames s : map (calledNames . snd) as)
    calledNames (ELambda _ b)  = calledNames b
    calledNames (EDo steps)    = Set.unions [ calledNames e | DoStep _ e <- steps ]
    calledNames (EPair a b)    = Set.union (calledNames a) (calledNames b)
    calledNames (EAwait e)     = calledNames e
    calledNames _              = Set.empty

-- | LEVER-A1 (review F1), extended by A2: a contract clause applying = / /= to
-- an array-valued operand (bytes OR map). Whole-structure equality is
-- UNCONDITIONALLY out-of-fragment in v1: the encoding carries junk outside
-- [0,n) / at absent keys, so representational array equality diverges from the
-- observational `=` of LLMLL.md §11.1 — reflecting it risks a spurious
-- refutation of an observationally true post (a §5.3.4 claim-accuracy break).
-- Routes the function to contract-only fallback.
wholeArrEqClause :: AliasMap -> [(Name, Type)] -> Maybe Type -> Maybe Expr -> Bool
wholeArrEqClause _ _ _ Nothing = False
wholeArrEqClause am params mRet (Just e0) = go e0
  where
    bytesVars = Set.fromList $ [ n | (n, t) <- params, isJust (bytesLenOf am t) ]
                            ++ [ "result" | Just t <- [mRet], isJust (bytesLenOf am t) ]
    mapVars = Set.fromList $ [ n | (n, t) <- params, isMapTy am t ]
                          ++ [ "result" | Just t <- [mRet], isMapTy am t ]
    go (EApp op [l, r])
      | op `elem` ["=", "==", "/=", "!=", "≠"] = arrish l || arrish r || go l || go r
    go (EApp _ args)  = any go args
    go (EOp op args)  = go (EApp op args)
    go (EIf c t e)    = go c || go t || go e
    go (ELet bs b)    = any (\(_, _, r) -> go r) bs || go b
    go (EMatch s as)  = go s || any (go . snd) as
    go _              = False
    arrish (EVar v)              = v `Set.member` bytesVars || v `Set.member` mapVars
    arrish (EApp "bytes-set" _)  = True
    arrish (EApp "bytes-zero" _) = True
    arrish (EApp "map-put" _)    = True
    arrish (EApp "map-empty" _)  = True
    arrish (EOp op as)           = arrish (EApp op as)
    arrish _                     = False

-- | Any map[k,v] type (alias-resolved), admissible or not.
isMapTy :: AliasMap -> Type -> Bool
isMapTy am t = case resolveAliasTy am t of
  TMap _ _ -> True
  _        -> False

-- | LEVER-A2 admissibility: the strictly-int map class map[int,int]. Retained
-- for the int-only call sites (measure carriers etc.); the array-encoding
-- admission sites use 'mapArrEncodableTy' (which also admits bool values).
mapIntIntTy :: AliasMap -> Type -> Bool
mapIntIntTy am t = case resolveAliasTy am t of
  TMap kt vt -> isIntLike am kt && isIntLike am vt
  _          -> False

-- | LEVER-A2.2 admissibility: the maps the two-array encoding accepts — int
-- keys, and a SCALAR value (int OR bool). A bool value rides the same int-0/1
-- array as presence: 'true'/'false' lower to 1/0 (literal-bridge), and each
-- occurring bool VALUE read carries the ground range fact 0 ≤ v ≤ 1
-- ('injectRangeFacts', the byte-range discipline at the value sort) so the
-- ℤ-encoding is exact on {0,1} — closing the disequality-in-hypothesis spurious
-- refute (professor review, 2026-07-13). String-valued maps stay out.
mapArrEncodableTy :: AliasMap -> Type -> Bool
mapArrEncodableTy am t = case resolveAliasTy am t of
  -- A2.2-string (keys): string KEYS join int keys — the array theory is
  -- polymorphic in the key sort, literal keys reflect via STRLIT (interned
  -- constants + ground distinctness makes literal-keyed reasoning exact;
  -- literal/var key pairs get no fact — a genuine model, arrays §87(iii)).
  TMap kt vt -> (isIntLike am kt || isStrLike am kt)
                  && (isScalarLike am vt || isStrLike am vt)
  _          -> False

-- | A2.2-string (keys): a map whose keys are string (any admissible value).
-- Drives the $has/$val array KEY dimension.
mapStrKeyedTy :: AliasMap -> Type -> Bool
mapStrKeyedTy am t = case resolveAliasTy am t of
  TMap kt _ -> isStrLike am kt
  _         -> False

-- | A2.2-string (keys): the $has (presence) component-array sort — int-0/1
-- values over the map's key sort.
mapHasArraySort :: AliasMap -> Type -> FQSort
mapHasArraySort am t
  | mapStrKeyedTy am t = FQArr FQStr FQInt
  | otherwise          = mapArraySort

-- | A2.2-string: a map whose keys are int and values are string. Unlike the
-- bool 0/1 bridge, a string value needs a GENUINE Str element sort — the $val
-- array is (Map_t int Str), so a map-get is a Str-EUF term comparable to the
-- interned strlit_ constants (STRLIT). Drives the $val sort ('mapValArraySort')
-- and the Stage-1 firewall on string-VALUED map RETURNS (deferred).
mapStrValuedTy :: AliasMap -> Type -> Bool
mapStrValuedTy am t = case resolveAliasTy am t of
  -- A2.2-string (keys): value-only — the key dimension is tracked separately
  -- (mapStrKeyedTy), so string-keyed-string-valued maps classify in both.
  TMap _ vt -> isStrLike am vt
  _         -> False

-- | A2.2-string: the $val component-array sort for a map type — (Map_t int Str)
-- for a string-valued map, else the uniform int-element 'mapArraySort' (int
-- values and the bool-0/1 bridge). The $has array is always 'mapArraySort'
-- (presence is int-0/1). This is the single sort-threading seam: every $val
-- binder site consults it, so a Str value array declares consistently and a
-- Map_select over it is Str-sorted.
mapValArraySort :: AliasMap -> Type -> FQSort
mapValArraySort am t = case (mapStrKeyedTy am t, mapStrValuedTy am t) of
  (False, False) -> mapArraySort            -- int keys, int/bool values (legacy FQMapArr)
  (False, True)  -> strMapArraySort         -- int keys, string values
  (True,  False) -> FQArr FQStr FQInt       -- string keys, int/bool values
  (True,  True)  -> FQArr FQStr FQStr       -- string keys, string values

-- | A2.2-string (residue lift): the string-map marker/component sort. Mirrors
-- the int-map convention where the whole-map RETURN marker equals the component
-- sort ('mapArraySort' = FQMapArr): a string-valued map return is marked
-- @FQArr FQInt FQStr@ — distinct from FQMapArr (int/bool maps) and from
-- byteArraySort (FQArr FQInt FQInt) — and its $val component carries the same
-- sort. Every marker-dispatch site widens via 'isMapArrRetSort'.
strMapArraySort :: FQSort
strMapArraySort = FQArr FQInt FQStr

-- | A2.2-string (residue lift): is this sort a map-return marker (int/bool map
-- OR string-valued map)? The widened guard for every `== mapArraySort` return-
-- dispatch site; bytes returns (byteArraySort) remain excluded.
isMapArrRetSort :: FQSort -> Bool
isMapArrRetSort s =
     s == mapArraySort            -- int keys, int/bool values (FQMapArr)
  || s == strMapArraySort         -- int keys, string values
  || s == FQArr FQStr FQInt       -- string keys, int/bool values
  || s == FQArr FQStr FQStr       -- string keys, string values

-- | A2.2-string (residue lift): the $val component sort a map-return marker
-- implies (marker = $val sort, the established convention).
markerValSort :: FQSort -> FQSort
markerValSort s = if isMapArrRetSort s then s else mapArraySort

-- | A2.2-string (keys): the $has component sort a map-return marker implies —
-- int-0/1 presence over the marker's KEY sort.
markerHasSort :: FQSort -> FQSort
markerHasSort (FQArr FQStr _) = FQArr FQStr FQInt
markerHasSort _               = mapArraySort

-- | LEVER-A2.2: the SYNTACTIC array-encodable map check used in 'bodyToPredM',
-- which has no AliasMap (the PAIR-RET-2 precedent): a literal @map[int,int]@ or
-- @map[int,bool]@ callee return / param. An alias-hidden map return keeps FQInt
-- and its post components stay unsubstituted → conservatively not assumed.
syntEncodableMapTy :: Type -> Bool
syntEncodableMapTy (TMap TInt TInt)       = True
syntEncodableMapTy (TMap TInt TBool)      = True
syntEncodableMapTy (TMap TInt TString)    = True  -- A2.2-string residue lift
syntEncodableMapTy (TMap TString TInt)    = True  -- A2.2-string keys
syntEncodableMapTy (TMap TString TBool)   = True  -- A2.2-string keys
syntEncodableMapTy (TMap TString TString) = True  -- A2.2-string keys
syntEncodableMapTy _                      = False

-- | A2.2-string (residue lift): the return-marker sort of a syntactic map type
-- (the 'syntEncodableMapTy' class) — the Str marker for a string-valued map,
-- 'mapArraySort' otherwise. Used where a callee's literal return type drives
-- the marker (no AliasMap, the PAIR-RET-2 precedent).
syntMapRetSort :: Type -> FQSort
syntMapRetSort (TMap TInt TString)    = strMapArraySort
syntMapRetSort (TMap TString TInt)    = FQArr FQStr FQInt   -- A2.2-string keys
syntMapRetSort (TMap TString TBool)   = FQArr FQStr FQInt   -- A2.2-string keys
syntMapRetSort (TMap TString TString) = FQArr FQStr FQStr   -- A2.2-string keys
syntMapRetSort _                      = mapArraySort

-- | The component-array sort of the two-array map encoding (int keys, int-0/1
-- presence / int values). One sort for both components in the v1 class.
mapArraySort :: FQSort
mapArraySort = FQMapArr

-- | LEVER-A2 crash-class guard for map-op-bearing contract clauses. Blocks (→
-- whole-contract fallback) when a reflection would reference binders that were
-- never split or produce ill-sorted FQ:
--   (a) some map-typed param or the map return is not array-encodable
--       (map[int,{int,bool}]) — a string-valued or non-int-keyed map;
--   (b) some map-put VALUE argument is neither an int/bool literal nor an
--       int-like param (a bool VAR value falls back — deferred);
--   (c) LEVER-A2.2: a bool-valued map-get used in a boolean position other than
--       a direct =/ /= comparison — an int Map_select in a not/and/or/if/bare
--       slot is ill-sorted (contract clauses only see params/result, so these
--       syntactic checks are complete for the contract channel).
mapClauseBlocked :: AliasMap -> [(Name, Type)] -> Maybe Type -> Maybe Expr -> Maybe Expr -> Bool
mapClauseBlocked am params mRet mPost mPre =
     any (\(_, t) -> isMapTy am t && not (mapArrEncodableTy am t)) paramsAndRet
  -- A2.2-string residue lift: string-valued map RETURNS are now admitted — the
  -- result$val binder, mapRetChain, and the callee-return marker sites all
  -- thread the Str value sort (strMapArraySort marker).
  || badPutValue mPost || badPutValue mPre
  || boolMapUnsafe mPost || boolMapUnsafe mPre
  where
    paramsAndRet = params ++ [ ("result", t) | Just t <- [mRet] ]
    intParamSet  = Set.fromList [ n | (n, t) <- params, isIntLike am t ]
    strParamSet  = Set.fromList [ n | (n, t) <- params, isStrLike am t ]
    boolMapVars  = Set.fromList [ n | (n, t) <- paramsAndRet, boolValuedMapTy am t ]
    badPutValue Nothing   = False
    badPutValue (Just e0) = go e0
      where
        -- A2.2-string (map-empty lift): a string-PARAM value on an EMPTY-rooted
        -- chain in a contract clause is blocked — the type-blind contract
        -- channel cannot infer the element sort from a var, so the store would
        -- be ill-sorted against the int default. Literal values reveal the sort
        -- (mapPairTermsC infers) and var values on var-rooted maps are fine
        -- (the $val binder carries the sort).
        go (EApp "map-put" [mE, kE, vE])
          | emptyRooted mE, EVar v <- vE, v `Set.member` strParamSet = True
          where emptyRooted e = case e of
                  EApp "map-empty" []          -> True
                  EOp  "map-empty" []          -> True
                  EApp "map-put" (mE' : _)     -> emptyRooted mE'
                  EOp  "map-put" (mE' : _)     -> emptyRooted mE'
                  _                            -> False
        go (EApp "map-put" [mE, kE, vE]) = not (okVal vE) || go mE || go kE || go vE
        go (EApp _ args)  = any go args
        go (EOp op args)  = go (EApp op args)
        go (EIf c t e)    = go c || go t || go e
        go (ELet bs b)    = any (\(_, _, r) -> go r) bs || go b
        go (EMatch s as)  = go s || any (go . snd) as
        go _              = False
        okVal (ELit (LitInt _))    = True
        okVal (ELit (LitBool _))   = True   -- LEVER-A2.2: bridged 0/1 (boolValLit)
        okVal (ELit (LitString _)) = True   -- A2.2-string: reflects via strlitConst
        okVal (EVar v)             = v `Set.member` intParamSet || v `Set.member` strParamSet
        okVal (EApp op [l, r])
          | op `elem` ["+", "-"] = okVal l && okVal r
        okVal (EOp op as)        = okVal (EApp op as)
        okVal _                  = False
    -- LEVER-A2.2: a bool-valued map-get reflects to an int Map_select. That int
    -- term is well-sorted ONLY when it meets another INT-reflecting term across
    -- =/ /= — a bridged bool literal (→ FQLit 0/1) or another bool-map-get (→
    -- another select). Any other position — bare, under a boolean connective, an
    -- if-condition, or =/ /= against a bool VARIABLE (int-select vs bool-var is
    -- ill-sorted) — is blocked → whole-contract fallback. The admitted shapes
    -- (get-vs-literal, get-vs-get) stay live; get-vs-var falls back (deferred).
    boolMapUnsafe Nothing  = False
    boolMapUnsafe (Just e) = walk e
    walk e
      | isBoolMapGet e = True   -- a bool-map-get in a non-eq (boolean) position
      | otherwise = case e of
          EApp op [l, r]
            | op `elem` eqNeqOps, isBoolMapGet l || isBoolMapGet r
                -> not (intReflecting l && intReflecting r)
            | op `elem` eqNeqOps
                -> walk l || walk r
          EApp _ args  -> any walk args
          EOp op args  -> walk (EApp op args)
          EIf c t el   -> walk c || walk t || walk el
          ELet bs b    -> any (\(_, _, r) -> walk r) bs || walk b
          EMatch s as  -> walk s || any (walk . snd) as
          _            -> False
    -- reflects to an int term across =/ /= : a bool-map-get or a bool literal.
    intReflecting x = isBoolMapGet x || isBoolLitE x
    isBoolLitE (ELit (LitBool _)) = True
    isBoolLitE _                  = False
    eqNeqOps = ["=", "==", "/=", "!=", "≠"] :: [Text]
    isBoolMapGet (EApp "map-get" (mE : _)) = rootBoolMap mE
    isBoolMapGet (EOp  "map-get" (mE : _)) = rootBoolMap mE
    isBoolMapGet _                         = False
    rootBoolMap (EVar v)                = v `Set.member` boolMapVars
    rootBoolMap (EApp "map-put" (m:_))  = rootBoolMap m
    rootBoolMap (EOp  "map-put" (m:_))  = rootBoolMap m
    rootBoolMap _                       = False

-- | LEVER-A2, contract channel: translate a map-typed CONTRACT subterm to its
-- component pair ⟨has-term, val-term⟩. Roots are variables (params/result —
-- their split binders are guaranteed by the gate + mapClauseBlocked), map-put
-- chains, and map-empty. Anything else → Nothing → the enclosing clause falls
-- back (§6.1). Presence stores write the int tag 1; map-empty is the all-absent
-- pair of const arrays (probe p4/p5b).
-- | LEVER-A2.2 literal-bridge: a bool literal at a map VALUE position lowers to
-- its int-0/1 tag (@true@→1, @false@→0) so it stores well-sorted into the
-- int-element @$val@ array. Only literals bridge; a bool VAR value returns
-- Nothing → the enclosing op falls back (an @ite@-bridge for bool vars is
-- deferred). The typechecker's homogeneous value typing guarantees a bool
-- literal here implies a bool-valued map (TypeCheck.hs:162-164), so this is
-- context-free and sound.
boolValLit :: Expr -> Maybe FQPred
boolValLit (ELit (LitBool True))  = Just (FQLit 1)
boolValLit (ELit (LitBool False)) = Just (FQLit 0)
boolValLit _                      = Nothing

-- STRLIT: 'strlitConst' / 'strlitLen' moved to FixpointIR (re-exported here) so
-- the guard channel (GuardClassifier) can intern literals without an import cycle.

-- | LEVER-A2.2: the int-0/1 tag of a bool literal (true→1, false→0).
boolTag :: Bool -> Integer
boolTag b = if b then 1 else 0

-- | LEVER-A2.2: is the expression a @map-get@ application (either surface form)?
-- Used to spot the bool-value get-comparison bridge in 'exprToPred'.
isMapGetHead :: Expr -> Bool
isMapGetHead (EApp "map-get" _) = True
isMapGetHead (EOp  "map-get" _) = True
isMapGetHead _                  = False

-- A2.2-string (map-empty lift): the value-array default ELEMENT for an element
-- sort — the empty-string constant for Str (semantically inert: the presence
-- obligation guards absent reads), 0 otherwise. Map_default is polymorphic in
-- liquid-fixpoint (func(2, [@(1); (Map_t @(0) @(1))])) — the element argument
-- alone determines the array type, so this is the entire Str-array story.
defaultElemFor :: FQSort -> FQPred
defaultElemFor FQStr = FQApp (strlitConst "") []
defaultElemFor _     = FQLit 0

-- A2.2-string (map-empty lift): is this expression literally (map-empty)?
-- A DIRECT get/has on it is degenerate (always-absent read) and its int-default
-- encoding meets Str terms ill-sorted → those shapes route to fallback whole.
isMapEmptyE :: Expr -> Bool
isMapEmptyE (EApp "map-empty" []) = True
isMapEmptyE (EOp  "map-empty" []) = True
isMapEmptyE _                     = False

-- A2.2-string (map-empty lift): the element sort is now INFERRED from the put
-- VALUE (a strlit value ⟹ a Str value array) and threaded down to the
-- map-empty leaf, so `(map-put (map-empty) k "x")` emits a Str-defaulted value
-- array instead of the int default that crashed the elaborator ("Cannot unify
-- Str with int"). Var-valued puts reveal nothing here (the contract channel is
-- type-blind) — a string-PARAM value on an empty-rooted chain is blocked at the
-- clause level (badPutValue) instead.
mapPairTermsC :: Expr -> Maybe (FQPred, FQPred)
mapPairTermsC = goC FQInt
  where
    goC _  (EVar m) = Just (FQVar (m <> "$has"), FQVar (m <> "$val"))
    goC es (EApp "map-put" [mE, kE, vE]) = do
      k <- exprToPred kE
      v <- case boolValLit vE of { Just x -> Just x; Nothing -> exprToPred vE }
      let es' = case v of
                  FQApp n [] | "strlit_" `T.isPrefixOf` n -> FQStr
                  _                                       -> es
      (h, vl) <- goC es' mE
      pure ( FQApp "Map_store" [h, k, FQLit 1]
           , FQApp "Map_store" [vl, k, v] )
    goC es (EApp "map-empty" []) =
      Just (FQApp "Map_default" [FQLit 0], FQApp "Map_default" [defaultElemFor es])
    goC es (EOp f as) = goC es (EApp f as)
    goC _ _ = Nothing

-- | LEVER-A2, body channel: the same pair translation with the body's renaming
-- env + SortEnv discipline. A variable root must have SPLIT binders in scope
-- (its "$has" key is in the SortEnv — seeded only for gated admissible
-- map[int,int] params), and map-put value/key args must be int-in-context
-- (literal, int-sorted var, or +/- arith over those) — a string-typed value
-- var would otherwise store an ill-sorted (or free) symbol into an int-element
-- array. Failure → Nothing → the enclosing op falls back (§6.1).
mapPairTermsB :: Map Name Name -> SortEnv -> Expr -> Maybe (FQPred, FQPred)
mapPairTermsB = mapPairTermsBWith FQInt

-- | A2.2-string (map-empty lift): the es-taking variant — the CONTEXT's element
-- sort seeds the inference (mapRetChain passes the return type's, so a bare
-- `(map-empty)` tail on a string-map return emits the Str default instead of
-- the elaborator-crashing int one).
mapPairTermsBWith :: FQSort -> Map Name Name -> SortEnv -> Expr -> Maybe (FQPred, FQPred)
mapPairTermsBWith es0 env se = go es0
  where
    go _ (EVar m) =
      let m' = fromMaybe m (Map.lookup m env)
      in if Map.member (m' <> "$has") se
           then Just (FQVar (m' <> "$has"), FQVar (m' <> "$val"))
           else Nothing
    -- A2.2-string (map-empty lift): the put VALUE translates FIRST — a Str value
    -- (strlit literal, or a Str-carrier var in the SortEnv) fixes the element
    -- sort, threaded down so a map-empty leaf gets a Str-defaulted value array:
    -- `(map-put (map-empty) k "x")` and `(map-put (map-empty) k s)` now verify
    -- (previously: fallback; and the int default crashed the elaborator when it
    -- met a Str term). Var roots ignore the element sort (their $val binder
    -- carries its own); the typechecker's homogeneous value typing makes the
    -- value-first inference sound (a Str value on an int-valued map is a prior
    -- type error).
    go es (EApp "map-put" [mE, kE, vE]) = do
      k <- mapKeyTerm env se kE
      (v, es') <- case boolValLit vE of
        Just x  -> Just (x, es)
        Nothing -> case strValTerm env se vE of
          Just s  -> Just (s, FQStr)
          Nothing -> (\x -> (x, es)) <$> scalarIntTerm env se vE
      (h, vl) <- go es' mE
      pure ( FQApp "Map_store" [h, k, FQLit 1]
           , FQApp "Map_store" [vl, k, v] )
    go es (EApp "map-empty" []) =
      Just (FQApp "Map_default" [FQLit 0], FQApp "Map_default" [defaultElemFor es])
    go es (EOp f as) = go es (EApp f as)
    go _ _ = Nothing

-- | An int-in-context scalar term for map-op key/value positions (body
-- channel): int literal, int-sorted in-scope variable, or +/- arithmetic over
-- those. Deliberately narrow — contracted calls are ANF-hoisted into lets
-- before this runs, so a variable is the general case.
scalarIntTerm :: Map Name Name -> SortEnv -> Expr -> Maybe FQPred
scalarIntTerm env se = go
  where
    go (ELit (LitInt n)) = Just (FQLit n)
    go (EVar v) =
      let v' = fromMaybe v (Map.lookup v env)
      in case Map.lookup v' se of
           Just FQInt -> Just (FQVar v')
           _          -> Nothing
    go (EApp op [l, r])
      | Just bop <- lookupArithOp op, op `elem` ["+", "-"]
      = FQBinArith bop <$> go l <*> go r
    go (EOp op as) = go (EApp op as)
    go _ = Nothing

-- | A2.2-string: does this value-array term have a Str element sort — a $val
-- binder declared (Map_t int Str), through any Map_store chain? Recovered from
-- the SortEnv, so the body channel needs no AliasMap. A Map_default-rooted array
-- (map-empty) is int-sorted, so a string put onto an empty map is NOT Str-rooted
-- and correctly falls back (Stage-1 defers string map-empty construction).
strValArrTerm :: SortEnv -> FQPred -> Bool
strValArrTerm se (FQVar n) = case Map.lookup n se of
  Just (FQArr _ FQStr) -> True
  _                    -> False
strValArrTerm se (FQApp "Map_store" (a:_)) = strValArrTerm se a
-- A2.2-string (map-empty lift): a Str-DEFAULTED empty root (the type-directed
-- default is self-identifying) — so a get over an empty-rooted string chain
-- sorts its result var Str.
strValArrTerm _  (FQApp "Map_default" [FQApp n []])
  | "strlit_" `T.isPrefixOf` n = True
strValArrTerm _  _ = False

-- | A2.2-string: the element (range) sort a map-get yields from a value array —
-- Str for a (Map_t int Str) $val, else int. Sorts the fresh map-get result
-- binder to match the Map_select (replacing the FQInt hardwire at the map-get
-- CallVC), so a string-valued get is well-sorted end to end.
mapSelValSort :: SortEnv -> FQPred -> FQSort
mapSelValSort se vl = if strValArrTerm se vl then FQStr else FQInt

-- | A2.2-string: extract a map-put value as a Str-sorted term — a string literal
-- (interned via 'strlitConst', reflecting exactly as STRLIT does elsewhere) or a
-- Str-carrier param in scope. Used ONLY when the target value array is Str
-- ('strValArrTerm'), so an int-element array put is unaffected and a string put
-- onto a map-empty (int default) is rejected → fallback.
strValTerm :: Map Name Name -> SortEnv -> Expr -> Maybe FQPred
strValTerm env se e = case e of
  ELit (LitString s) -> Just (FQApp (strlitConst s) [])
  EVar v -> let v' = fromMaybe v (Map.lookup v env)
            in case Map.lookup v' se of
                 Just FQStr -> Just (FQVar v')
                 _          -> Nothing
  _ -> Nothing

-- | A2.2-string (keys): a SELF-SORTING map key term — int-in-context
-- ('scalarIntTerm': literal / int var / +,- arith) or a Str term (strlit
-- literal / Str-carrier var). The key term itself is unambiguous (an int var
-- key on a string-keyed map is a prior type error), and the array theory is
-- polymorphic in the key sort, so no key-sort threading is needed — the
-- Map_select/Map_store application unifies against the \$has/\$val binder sorts.
mapKeyTerm :: Map Name Name -> SortEnv -> Expr -> Maybe FQPred
mapKeyTerm env se kE = case scalarIntTerm env se kE of
  Just k  -> Just k
  Nothing -> strValTerm env se kE

-- | LEVER-A2.1: one peeled step of a straight-line map-returning body chain.
data MapRetStep
  = MRGet Name FQPred FQPred FQSort  -- ^ bound var, presence pred (PROVE), value select (pin), value sort (A2.2-string: Str for a string-map read, else int)
  | MRDef Name FQPred                 -- ^ bound var, defining scalar term (pin)

-- | F-011.3: a guarded tree of map-return leaves. A 'Leaf' carries the
-- straight-line steps peeled on its path (each 'MRGet' its presence obligation
-- and pin, each 'MRDef' its scalar pin) plus the terminal component pair; a
-- 'Branch' carries the reflected guard and its two arms. Reflecting an @if@
-- through the array-valued result is sound and stays in QF_AUFLIA (same
-- fragment as the straight-line map path): each leaf becomes one component-pin
-- constraint with the path guard conjoined onto its LHS and the arm tag taken
-- from provenance (§6.1 exact-reflection; a branch-free body is a single Leaf,
-- byte-identical to the pre-F-011.3 straight-line emission).
data MapRetTree
  = Leaf [MapRetStep] (FQPred, FQPred)
  | Branch FQPred MapRetTree MapRetTree

-- | LEVER-A2.1 (read-modify-write class): peel a straight-line, ANF'd,
-- let-expanded map-returning body — a spine of lets whose RHSs are map-gets
-- or scalar int terms, terminating in a pure map term. Each map-get step
-- carries its presence obligation and exact pin; each scalar step its
-- defining pin. Anything else — branches, contracted calls, shadowing a name
-- already in the SortEnv, non-scalar lets — is Nothing → the whole body falls
-- back (§6.1: never a partial reflection).
-- A2.2-string (map-empty lift): the chain takes the RETURN type's element sort,
-- passed to the terminal translation — a bare `(map-empty)` (or an empty-rooted
-- put chain whose value doesn't reveal the sort) on a string-map return then
-- emits the Str-defaulted value array (the hz1 elaborator-crash fix).
mapRetChain :: FQSort -> SortEnv -> Expr -> Maybe MapRetTree
mapRetChain esRet se0 = go se0
  where
    go se (ELet [(PVar v, _, rhs0)] body)
      | Map.member v se = Nothing            -- shadowing → fall back whole
      | otherwise =
          case normOp rhs0 of
            EApp "map-get" [mE, kE] -> do
              (h, vl) <- mapPairTermsB Map.empty se mE
              k <- mapKeyTerm Map.empty se kE
              -- A2.2-string: the bound var carries the value array's element
              -- sort (Str for a string-map read), so a later step can use it as
              -- a put VALUE (strValTerm's se lookup) and the binder is well-
              -- sorted against the Str Map_select pin.
              let pres  = FQBinPred FQEq (FQApp "Map_select" [h, k]) (FQLit 1)
                  sel   = FQApp "Map_select" [vl, k]
                  vSort = mapSelValSort se vl
              sub <- go (Map.insert v vSort se) body
              pure (prependStep (MRGet v pres sel vSort) sub)
            rhs -> do
              t <- scalarIntTerm Map.empty se rhs
              sub <- go (Map.insert v FQInt se) body
              pure (prependStep (MRDef v t) sub)
    -- F-011.3: reflect an `if` through the array-valued result. The body is
    -- ANF'd before this runs, so a guard's `map-get` operands are hoisted to
    -- seeded lets ahead of the branch — the guard is var-operand, so the
    -- existing var-operand classifier ('guardToPredM'/'classifyGuardM', whose
    -- State counter is inert for guards) suffices. An un-reflectable guard, or
    -- an un-reflectable arm, → Nothing → whole-body fallback (§6.1: never a
    -- partial reflection). Terminal arms accept a param-map root and a pure
    -- map-put/map-empty chain (both exact reflections via 'mapPairTermsBWith').
    go se (EIf c t e) = do
      g  <- evalState (guardToPredM Map.empty se c) 0
      tt <- go se t
      et <- go se e
      pure (Branch g tt et)
    go se (ELet (b:bs) body) = go se (ELet [b] (ELet bs body))
    go se (ELet [] body)     = go se body
    go se e                  = Leaf [] <$> mapPairTermsBWith esRet Map.empty se e
    normOp (EOp f as) = EApp f as
    normOp e          = e
    -- Push a peeled step down to every leaf it dominates (shared lets ahead of a
    -- branch land in both arms; each leaf then emits its own binder — safe, the
    -- generic per-path emission duplicates path binders the same way).
    prependStep :: MapRetStep -> MapRetTree -> MapRetTree
    prependStep st (Leaf steps term) = Leaf (st : steps) term
    prependStep st (Branch g l r)    = Branch g (prependStep st l) (prependStep st r)

-- | F-011.3: flatten a 'MapRetTree' to one entry per leaf —
-- @(path steps, accumulated guard predicates, terminal component pair,
-- outermost-branch provenance)@. Guards accumulate top-down (@¬g@ on the else
-- arm); provenance is the OUTERMOST branch side (@Nothing@ for a branch-free
-- tree), mirroring 'pathBranchSides' so a refuted arm localizes structurally
-- (@body-post-then@/@body-post-else@) rather than by a path-index midpoint.
flattenMapRetTree :: MapRetTree -> [([MapRetStep], [FQPred], (FQPred, FQPred), Maybe Bool)]
flattenMapRetTree = go [] Nothing
  where
    go accG prov (Leaf steps term) = [(steps, accG, term, prov)]
    go accG prov (Branch g l r)    =
         go (accG ++ [g])       (setProv True  prov) l
      ++ go (accG ++ [FQNot g]) (setProv False prov) r
    setProv side Nothing = Just side
    setProv _    p       = p

-- | LEVER-A2 (§5.1, the pipeline shape): substitute PURE map-typed
-- let-bindings into their bodies BEFORE ANF/translation, reducing the
-- let-bound pipeline `(let [(m2 (map-put m k v))] (map-get m2 k))` to the
-- composite form the reflection cases handle. Substitution is §6.1-exact: the
-- ops are pure functional updates, so duplication preserves meaning. Guarded:
-- only RHSs whose head chain is map-put/map-empty and which mention NO
-- contracted-callee name are expanded (a call inside a duplicated RHS would
-- duplicate its call obligations); anything else stays a normal let (and the
-- enclosing map op then falls back — sound). Shadowing respected: substitution
-- stops where the name is rebound.
expandMapLets :: Set.Set Name -> Expr -> Expr
expandMapLets callNames e0
  -- Byte-inertness: a map-op-free body returns the ORIGINAL expression object
  -- untouched. `go` rebuilds the tree (and desugars multi-binding lets), which
  -- is translation-equivalent but shifts ANF fresh-variable numbering — a
  -- .fq-text diff the F7 sweep rightly rejects for the pre-existing corpus.
  | not (exprMentionsMapOp e0) = e0
  | otherwise                  = go e0
  where
    go :: Expr -> Expr
    go (ELet [(PVar v, mt, rhs)] body)
      | isPureMapTerm rhs' = go (substVar v rhs' body)
      | otherwise          = ELet [(PVar v, mt, rhs')] (go body)
      where rhs' = go rhs
    go (ELet (b:bs) body) = go (ELet [b] (ELet bs body))
    go (ELet [] body)     = go body
    -- F-011.3 (if-floating): push a single `if` out of a strict, pure, callFree
    -- argument of map-put/bytes-set/+/-, reducing the conditional-stored-value
    -- case to the map-valued-if case before mapRetChain runs. §6.1-exact: these
    -- ops are strict and pure in every argument, so
    -- `(f … (if c a b) …)` ≡ `(if c (f … a …) (f … b …))`; the existing callFree
    -- guard (over ALL args, so the duplicated operands carry no contracted call)
    -- prevents duplicating a call's obligations. One `if` per rewrite; the outer
    -- `go`/recursion floats any remaining ones. Byte-inert for map-op-free bodies
    -- (the enclosing gate returns them untouched before `go` ever runs).
    go (EApp f args)
      | f `elem` ["map-put", "bytes-set", "+", "-"]
      , all callFree args
      , (pre, EIf c a b : post) <- break isIfE args
      = go (EIf c (EApp f (pre ++ a : post)) (EApp f (pre ++ b : post)))
    go (EApp f args)      = EApp f (map go args)
    go (EOp f args)       = EOp f (map go args)
    go (EIf c t e)        = EIf (go c) (go t) (go e)
    go (EMatch s as)      = EMatch (go s) [ (p, go b) | (p, b) <- as ]
    go (ELambda ps b)     = ELambda ps (go b)
    go (EPair a b)        = EPair (go a) (go b)
    go (EAwait e)         = EAwait (go e)
    go e                  = e
    isPureMapTerm (EApp "map-put" [mE, kE, vE]) =
      (isPureMapTerm mE || isVarE mE) && callFree kE && callFree vE && callFree mE
    isPureMapTerm (EApp "map-empty" []) = True
    isPureMapTerm (EOp f as) = isPureMapTerm (EApp f as)
    isPureMapTerm _ = False
    isVarE (EVar _) = True
    isVarE _        = False
    isIfE (EIf{}) = True
    isIfE _       = False
    callFree = not . mentionsCallName
    mentionsCallName (EApp f args) = f `Set.member` callNames || any mentionsCallName args
    mentionsCallName (EOp f args)  = mentionsCallName (EApp f args)
    mentionsCallName (EIf c t e)   = any mentionsCallName [c, t, e]
    mentionsCallName (ELet bs b)   = any (\(_, _, r) -> mentionsCallName r) bs || mentionsCallName b
    mentionsCallName (EMatch s as) = mentionsCallName s || any (mentionsCallName . snd) as
    mentionsCallName (EPair a b)   = mentionsCallName a || mentionsCallName b
    mentionsCallName (EAwait e)    = mentionsCallName e
    mentionsCallName _             = False
    -- Capture-safe-enough substitution: stop at any construct that rebinds v.
    substVar v r = sub
      where
        sub e@(EVar x) | x == v = r
                       | otherwise = e
        sub (EApp f args) = EApp f (map sub args)
        sub (EOp f args)  = EOp f (map sub args)
        sub (EIf c t e)   = EIf (sub c) (sub t) (sub e)
        sub el@(ELet [(PVar x, mt, rhs)] body)
          | x == v    = ELet [(PVar x, mt, sub rhs)] body   -- v rebound: RHS still sees outer v
          | otherwise = ELet [(PVar x, mt, sub rhs)] (sub body)
        sub (ELet (b:bs) body) = case sub (ELet [b] (ELet bs body)) of e -> e
        sub (ELet [] body) = sub body
        sub (EMatch s as) = EMatch (sub s)
          [ (p, if v `Set.member` patVars p then b else sub b) | (p, b) <- as ]
        sub (ELambda ps b)
          | v `elem` map fst ps = ELambda ps b
          | otherwise           = ELambda ps (sub b)
        sub (EPair a b) = EPair (sub a) (sub b)
        sub (EAwait e)  = EAwait (sub e)
        sub e = e
        patVars (PVar x)            = Set.singleton x
        patVars (PConstructor _ ps) = Set.unions (map patVars ps)
        patVars _                   = Set.empty

-- | LEVER-A1: does a contract clause apply a bytes op to @result@? Used by the
-- call-site post-assumption guard (an ill-sorted reflected term over an
-- int-sorted result var would crash the solver rather than fall back).
bytesOpOnResult :: Maybe Expr -> Bool
bytesOpOnResult Nothing   = False
bytesOpOnResult (Just e0) = go e0
  where
    go (EApp f args)
      | f `elem` bytesOpNames = any (exprMentionsVar "result") args || any go args
      | otherwise             = any go args
    go (EOp f args)  = go (EApp f args)
    go (EIf c t e)   = go c || go t || go e
    go (ELet bs b)   = any (\(_, _, r) -> go r) bs || go b
    go (EMatch s as) = go s || any (go . snd) as
    go _             = False

-- | PAIR-RET: does the module use pairs anywhere a Pair2 sort/term would be emitted?
-- Checks each def-form's signature for a (transitive) pair type AND walks its contract
-- and body for `EPair` / `(first _)` / `(second _)`. The body walk catches a pair that
-- is constructed-and-consumed entirely inside a body (int signature, no surface pair) —
-- which would otherwise emit `pair2`/`pair2_*` terms against an undeclared sort.
moduleUsesPairs :: AliasMap -> [Statement] -> Bool
moduleUsesPairs am = any stmtUsesPairs
  where
    stmtUsesPairs s = case sigOf s of
      Nothing -> False
      Just (params, mRet, contract, mBody) ->
           any (typeHasPair . snd) params
        || maybe False typeHasPair mRet
        || any exprUsesPair ([ p | Just p <- [contractPre contract] ]
                          ++ [ p | Just p <- [contractPost contract] ])
        || maybe False exprUsesPair mBody
    sigOf s = case s of
      SDefLogic _ p r c b     -> Just (p, r, c, Just b)
      SDef _ p r c b          -> Just (p, r, c, Just b)
      SDefShell _ p r c b _     -> Just (p, r, c, Just b)
      SDefInvariant _ p r c b -> Just (p, r, c, Just b)
      SLetrec _ p r c _ b     -> Just (p, r, c, Just b)
      _                       -> Nothing
    typeHasPair t = case resolveAliasTy am t of
      TPair{}     -> True
      TList t'    -> typeHasPair t'
      TResult a b -> typeHasPair a || typeHasPair b
      TPromise t' -> typeHasPair t'
      _           -> False
    exprUsesPair = go
      where
        go (EPair _ _)            = True
        go (EApp op args)         = op `elem` ["first", "second"] || any go args
        go (EOp  op args)         = op `elem` ["first", "second"] || any go args
        go (EIf c t e)            = go c || go t || go e
        go (ELet bs body)         = any (\(_, _, rhs) -> go rhs) bs || go body
        go (EMatch scr arms)      = go scr || any (go . snd) arms
        go (ELambda _ body)       = go body
        go (EDo steps)            = any (\(DoStep _ e) -> go e) steps
        go (EAwait e)             = go e
        go _                      = False

-- | COMP-4-RESULT: does the module CONSTRUCT a Result (so a Result FQData term/sort is
-- emitted)? True for a `-> Result` return (its binder gets the FQData sort) or a body/
-- contract that applies `ok`/`err`. False for an eliminate-only module (Result param,
-- scalar return — opaque skolem path), keeping its .fq byte-identical. Match PATTERNS
-- `(ok x)` are not walked (only arm bodies), so `settle`-shaped elimination is excluded.
moduleConstructsResult :: AliasMap -> [Statement] -> Bool
moduleConstructsResult am = any stmtConstructs
  where
    stmtConstructs s = case sigOf s of
      Nothing -> False
      Just (_params, mRet, contract, mBody) ->
           maybe False isResult mRet
        || any exprConstructs ([ p | Just p <- [contractPre contract] ]
                            ++ [ p | Just p <- [contractPost contract] ])
        || maybe False exprConstructs mBody
    sigOf s = case s of
      SDefLogic _ p r c b     -> Just (p, r, c, Just b)
      SDef _ p r c b          -> Just (p, r, c, Just b)
      SDefShell _ p r c b _     -> Just (p, r, c, Just b)
      SDefInvariant _ p r c b -> Just (p, r, c, Just b)
      SLetrec _ p r c _ b     -> Just (p, r, c, Just b)
      _                       -> Nothing
    isResult t = case resolveAliasTy am t of TResult{} -> True; _ -> False
    exprConstructs = go
      where
        go (EApp op args)    = op `elem` ["ok", "err"] || any go args
        go (EOp  op args)    = op `elem` ["ok", "err"] || any go args
        go (EIf c t e)       = go c || go t || go e
        go (ELet bs body)    = any (\(_, _, rhs) -> go rhs) bs || go body
        go (EMatch scr arms) = go scr || any (go . snd) arms
        go (ELambda _ body)  = go body
        go (EDo steps)       = any (\(DoStep _ e) -> go e) steps
        go (EPair a b)       = go a || go b
        go (EAwait e)        = go e
        go _                 = False

typeToSort :: Type -> FQSort
typeToSort TInt    = FQInt
typeToSort TBool   = FQBool
typeToSort TString = FQStr            -- NIW: opaque carrier for string measures
typeToSort (TList _) = FQList         -- NIW: opaque carrier for list measures
typeToSort (TDependent _ base _) = typeToSort base
-- PAIR-RET: a pair lowers to the parametric product sort `(Pair2 s0 s1)`, recursively
-- (nested pairs nest the applied sort — spike-confirmed). This is unconditional so the
-- binder sort always agrees with exprToPred's (sort-blind) selector emission; the
-- discharging *scope* is QF-LIA-scalar components (int/bool/string-measure), enforced
-- per-operator by exprToPred — a non-scalar projection used outside Σ_auto falls back.
typeToSort (TPair a b) = FQDataApp "Pair2" [typeToSort a, typeToSort b]
typeToSort _     = FQInt  -- conservative default

-- | COMP-4 (a): alias-aware sort. An admissible sum lowers to its native FQData
-- sort so constructor/selector terms type-check; everything else (int-tag enum,
-- refinement alias, base type) falls through to 'typeToSort' unchanged.
typeToSortA :: AliasMap -> Type -> FQSort
typeToSortA am t = case t of
  -- PAIR-RET-2: alias-AWARE pair lowering — a component is mapped through
  -- typeToSortA (not the alias-unaware typeToSort), so an admissible sum component
  -- `(int, Box)` lowers to `(Pair2 int Box)` instead of collapsing Box to int.
  -- (The non-admissible case is firewalled by sigPairUnsafe before emission.)
  TPair a b -> FQDataApp "Pair2" [typeToSortA am a, typeToSortA am b]
  -- COMP-4-RESULT: a constructed Result lowers to the native polymorphic datatype
  -- `(Result a b)` so `(ok e)`/`(err e)` reflect (closing the COMP-4 (a) drift —
  -- ok/err are lowercase builtins the uppercase-ctor guard misses). The non-admissible
  -- payload case is firewalled by resultReturnUnsafe before emission; opaque/received
  -- Results (param scrutinees) stay on the skolem path (disjoint binders).
  TResult a b -> FQDataApp "Result" [typeToSortA am a, typeToSortA am b]
  TCustom n | Just (TSumType ctors) <- Map.lookup n am
            , admissibleDatatype am (TSumType ctors)
            , hasRealPayload ctors -> FQData n
  -- a resolved (anonymous) TSumType return: reverse-lookup its decl name
  TSumType ctors
    | admissibleDatatype am t
    , hasRealPayload ctors
    , (n:_) <- [ nm | (nm, TSumType c) <- Map.toList am, c == ctors ] -> FQData n
  _ -> typeToSort t
  where
    -- A pure nullary enum (all unit/empty payloads) is int-tag-desugared
    -- (COMP-3c) → keep FQInt; only a sum with a real payload field uses the
    -- native FQData sort. Mirrors typeSorts' fieldsOf (unit is not a field).
    hasRealPayload cs = any realField cs
    realField (_, Just pt) = resolveAliasTy am pt /= TUnit
    realField (_, Nothing) = False

-- | PAIR-RET-2: is a pair component faithfully representable as an FQSort that
-- AGREES with its reflected term? Scalars (int/bool/string carrier), lists (Lst
-- carrier), nested pairs, nullary enums (int-tag, COMP-3c), and admissible payload
-- sums (FQData) are. A `Result` or a recursive/non-admissible payload sum is NOT:
-- typeToSortA collapses it to FQInt while construction reflects an FQData term, a
-- sort mismatch that crashes liquid-fixpoint. A non-sortable component routes the
-- whole function to erBodyFallback (the §5.3.3 firewall) instead of emitting the
-- crash-inducing constraint.
sortableComponent :: AliasMap -> Type -> Bool
sortableComponent am t0 = case resolveAliasTy am t0 of
  TInt        -> True
  TBool       -> True
  TString     -> True
  TList _     -> True
  TPair a b   -> sortableComponent am a && sortableComponent am b
  TResult a b -> sortableComponent am a && sortableComponent am b  -- v0.13.14: Result is a native datatype (COMP-4-RESULT) → a pair-of-Result component is sortable iff its payloads are
  s@(TSumType ctors)
    | any realField ctors -> admissibleDatatype am s     -- payload sum → FQData iff acyclic
    | otherwise           -> True                         -- nullary enum → int-tag (COMP-3c)
  _           -> False
  where realField (_, Just pt) = resolveAliasTy am pt /= TUnit
        realField (_, Nothing) = False

-- | PAIR-RET-2: does any pair in the signature carry a non-sortable component?
-- If so the body-faithful path would mis-sort the binder; force a clean fallback.
sigPairUnsafe :: AliasMap -> [(Name, Type)] -> Maybe Type -> Bool
sigPairUnsafe am params mRet =
  any (pairUnsafe . snd) params || maybe False pairUnsafe mRet
  where pairUnsafe t = case resolveAliasTy am t of
          TPair a b -> not (sortableComponent am a && sortableComponent am b)
          _         -> False

-- | COMP-4-RESULT: a `-> Result` RETURN whose ok/err payload is non-admissible
-- would mis-sort the constructor term and crash the solver; force a clean fallback.
-- Return-ONLY: a Result PARAM is opaque (the skolem path), never sorted as a Result, so
-- it is unaffected (no regression to the existing d-elim / COMP-3b elimination of Result
-- params). Admissible payloads (v0.13.14) = any acyclic composition of scalar
-- (int/bool/string), an acyclic sum (FQData / int-tag enum), a pair, or a nested Result.
-- A `list` carrier or a recursive sum stays firewalled (the deliberate final boundary).
resultReturnUnsafe :: AliasMap -> Maybe Type -> Bool
resultReturnUnsafe am mRet = case resolveAliasTy am <$> mRet of
  Just (TResult a b) -> not (payloadOK a && payloadOK b)
  _                  -> False
  where
    payloadOK t = case resolveAliasTy am t of
      TInt           -> True
      TBool          -> True
      TString        -> True
      TPair a b      -> payloadOK a && payloadOK b           -- v0.13.14: composed (int,int) payload
      TResult a b    -> payloadOK a && payloadOK b           -- v0.13.14: nested Result payload
      s@(TSumType _) -> admissibleDatatype am s
      _              -> False                                -- list carrier / recursive → firewall (final boundary)

-- | PAIR-RET-2: a SYNTACTIC (alias-free) conservative variant for the call-VC path
-- (`bodyToPredM` has no AliasMap). True if the return is a pair with any component
-- that is not obviously sortable (scalar / list / nested-scalar-pair). A
-- TCustom/TSumType/TResult component is treated as possibly-unsafe — conservative
-- (a nullary-enum component is gated too, a harmless completeness loss); the
-- precise alias-aware check is 'sigPairUnsafe'.
syntacticUnsafePairRet :: Maybe Type -> Bool
syntacticUnsafePairRet = maybe False go
  where
    go (TPair a b) = not (scalarish a && scalarish b)
    go _           = False
    scalarish TInt               = True
    scalarish TBool              = True
    scalarish TString            = True
    scalarish (TList _)          = True
    scalarish (TPair a b)        = scalarish a && scalarish b
    scalarish (TDependent _ b _) = scalarish b
    scalarish _                  = False

-- | COMP-4 (d-elim): a two-arm-ADT payload is admissible to opaque-sum
-- elimination iff its sort is a QF-LIA-representable scalar (int / bool /
-- string-measure carrier). A payload that is itself a sum/Result/list/etc. type
-- is NOT admissible — it would need the datatype theory of COMP-4 (a) /
-- construction reasoning — so the match falls back via the §5.3.3 firewall.
-- (Enum-tag and list payloads are deliberate follow-ups, not this slice.)
admissiblePayload :: AliasMap -> Type -> Bool
admissiblePayload am t = case resolveAliasTy am t of
  TInt    -> True
  TBool   -> True
  TString -> True
  _       -> False

-- | COMP-4 (a) §5: a sum type is admissible for the native FQData path iff its
-- reachable type-closure is ACYCLIC (transitive-closure acyclicity, Rev 3) — a
-- recursive datatype (Tree = Node Tree Tree) is EXCLUDED so z3's datatype theory
-- stays decidable. Conservative: a payload that is neither a base type nor an
-- acyclically-reachable sum is treated as a non-sum leaf.
admissibleDatatype :: AliasMap -> Type -> Bool
admissibleDatatype am = go Set.empty
  where
    go seen t = case sumOf t of
      Nothing -> True   -- base / non-sum payload: a leaf, fine
      Just (nm, ctors)
        | nm `Set.member` seen -> False                       -- cycle → inadmissible
        | otherwise -> all (go (Set.insert nm seen)) [ pt | (_, Just pt) <- ctors ]
    sumOf t = case t of
      TSumType ctors -> Just ("", ctors)
      TCustom n      -> case Map.lookup n am of
                          Just (TSumType ctors) -> Just (n, ctors)
                          Just other            -> sumOf other
                          Nothing               -> Nothing
      _              -> Nothing

typeSorts :: AliasMap -> Name -> Type -> [FQDataDecl]
typeSorts am name (TSumType ctors)
  | admissibleDatatype am (TSumType ctors) =
      [FQDataDecl name 0 [ (c, fieldsOf mp) | (c, mp) <- ctors ]]
  | otherwise =
      [FQDataDecl name 0 [ (c, []) | (c, _) <- ctors ]]
  where
    -- A `unit` payload is the nullary-enum marker (COMP-3c `(| Red unit)`), not a
    -- real field — it must contribute no field, so an int-tag enum stays `{ }`.
    fieldsOf (Just pt) | resolveAliasTy am pt /= TUnit = [typeToSort pt]
    fieldsOf _                                         = []
typeSorts _ _ _ = []

maybeToList :: Maybe a -> [a]
maybeToList Nothing  = []
maybeToList (Just x) = [x]

-- ---------------------------------------------------------------------------
-- COMP-3b-general (Phase 1): nullary-enum constructor-value desugaring
-- ---------------------------------------------------------------------------

-- | Tag table for nullary-enum constructors: each constructor of an in-scope
-- nullary 'TSumType' maps to its declaration index (its int tag). Only names
-- that are UNAMBIGUOUS across all in-scope enums are kept — a name that is a
-- constructor of more than one enum is excluded, so the desugar leaves it as a
-- variable (→ unbound symbol → 'asserted' fallback, sound, never mis-tagged).
buildCtorTagMap :: AliasMap -> Map Name Int
buildCtorTagMap am =
  let perEnum = [ (c, i)
                | t <- Map.elems am
                , TSumType ctors <- [t]
                , all (\(_, mp) -> case mp of Nothing -> True; Just _ -> False) ctors
                , (i, (c, _)) <- zip [0 ..] ctors ]
      grouped = Map.fromListWith (++) [ (c, [i]) | (c, i) <- perEnum ]
  in Map.fromList [ (c, i) | (c, [i]) <- Map.toList grouped ]  -- unambiguous only

-- | Scope-aware desugar that lowers nullary-constructor VALUES and nullary-enum
-- matches to the int-tag QF-LIA form the existing VC machinery already verifies:
--   (a) a value-position @EVar n@ that resolves to a nullary constructor (n in
--       the tag table, not shadowed by a local binding) → @ELit (LitInt tag)@;
--   (b) an @EMatch@ on a variable whose arms are all nullary constructors (or a
--       catch-all) → a right-nested @EIf@ on @(= scrut tag_i)@.
-- Result matches (Success/Error, payload-bearing) are untouched — their
-- constructors are not in the tag table — and flow to the existing COMP-3 path.
-- The bound-set makes a @let@/param sharing a constructor's name win (it stays a
-- variable). Payload-bearing constructors and payload-projecting posts are left
-- alone (→ 'asserted'), keeping the QF-LIA boundary intact (no datatype theory).
desugarCtorValues :: Map Name Int -> Set.Set Name -> Expr -> Expr
desugarCtorValues tags = go
  where
    tagLit c = ELit (LitInt (toInteger (tags Map.! c)))

    go bound e = case e of
      EVar n
        | n `Map.member` tags && not (n `Set.member` bound) -> tagLit n
        | otherwise                                         -> e
      ELit _      -> e
      EHole _     -> e
      EOp op as   -> EOp op (map (go bound) as)
      EApp f as   -> EApp f (map (go bound) as)
      EPair a b   -> EPair (go bound a) (go bound b)
      EAwait a    -> EAwait (go bound a)
      EIf c t el  -> EIf (go bound c) (go bound t) (go bound el)
      ELambda ps body ->
        ELambda ps (go (foldr (Set.insert . fst) bound ps) body)
      ELet binds body ->
        let bound' = foldr Set.insert bound (concatMap (\(p,_,_) -> patVars p) binds)
        in ELet [ (p, mt, go bound' rhs) | (p, mt, rhs) <- binds ] (go bound' body)
      EDo steps   -> EDo [ DoStep mn (go bound se) | DoStep mn se <- steps ]
      EMatch scr arms
        | EVar _ <- scr, not (null arms), all (rewritableArm . fst) arms
          -> buildChain (go bound scr) bound arms
        | otherwise
          -> EMatch (go bound scr)
               [ (p, go (foldr Set.insert bound (patVars p)) b) | (p, b) <- arms ]

    rewritableArm (PConstructor c []) = c `Map.member` tags
    rewritableArm (PVar _)            = True
    rewritableArm PWildcard           = True
    rewritableArm _                   = False

    -- Right-nested EIf. The LAST arm is the bare else (exhaustiveness — enforced
    -- by the type checker — guarantees it covers the remaining constructor); a
    -- PVar/PWildcard arm is a catch-all and becomes the else, ignoring later arms.
    buildChain _    bound [(_, b)]        = go bound b
    buildChain scr' bound ((p, b) : rest) = case p of
      PConstructor c [] -> EIf (EOp "=" [scr', tagLit c]) (go bound b) (buildChain scr' bound rest)
      _                 -> go bound b
    buildChain _    _     []              = ELit LitUnit  -- unreachable (arms non-empty)

    patVars (PVar n)            = [n]
    patVars (PConstructor _ ps) = concatMap patVars ps
    patVars _                   = []

-- | MATCH-WIDEN STRETCH (v0.14.12): rewrite a scrutinee-constructor equality
-- `(= v Ctor)` / `(= Ctor v)` — where @v@ is a two-arm payload-bearing sum param and
-- @Ctor@ one of its constructors — to the int-tag form `(= v$tag k)`. This lets a post
-- that references the matched value's constructor discharge against the seeded free int
-- tag the match's BranchVC declares. Any other occurrence of @v@ is untouched (it keeps
-- the FLOOR fallback). Keyed on the scrutinee-tag map (non-all-nullary two-arm sums).
desugarScrutCtor :: Map Name (Map Name Int) -> Expr -> Expr
desugarScrutCtor stm = go
  where
    tagEq v k = EOp "=" [EVar (v <> "$tag"), ELit (LitInt (toInteger k))]
    go e = case e of
      EOp "=" [EVar a, EVar b]
        | Just ct <- Map.lookup a stm, Just k <- Map.lookup b ct -> tagEq a k
        | Just ct <- Map.lookup b stm, Just k <- Map.lookup a ct -> tagEq b k
      EOp op as   -> EOp op (map go as)
      EApp f as   -> EApp f (map go as)
      EIf c t el  -> EIf (go c) (go t) (go el)
      ELet bs b   -> ELet [ (p, mt, go r) | (p, mt, r) <- bs ] (go b)
      EPair a b   -> EPair (go a) (go b)
      EAwait a    -> EAwait (go a)
      _           -> e

-- | MATCH-WIDEN STRETCH: the set of variables that appear as a `match` scrutinee
-- anywhere in a body (`(match (EVar v) …)`). Used to gate the scrutinee-constructor
-- desugar to params whose `$tag` the body actually declares (via the match BranchVC).
matchedScrutVars :: Expr -> Set.Set Name
matchedScrutVars e = case e of
  EMatch (EVar v) arms -> Set.insert v (Set.unions (map (matchedScrutVars . snd) arms))
  EMatch scr arms      -> Set.unions (matchedScrutVars scr : map (matchedScrutVars . snd) arms)
  EOp _ as             -> Set.unions (map matchedScrutVars as)
  EApp _ as            -> Set.unions (map matchedScrutVars as)
  EIf c t el           -> Set.unions [matchedScrutVars c, matchedScrutVars t, matchedScrutVars el]
  ELet bs b            -> Set.unions (matchedScrutVars b : map (\(_, _, r) -> matchedScrutVars r) bs)
  EPair a b            -> Set.union (matchedScrutVars a) (matchedScrutVars b)
  EAwait a             -> matchedScrutVars a
  _                    -> Set.empty

-- | INT-1 (v0.10.8): True when an expression tree contains LLMLL-level
-- integer arithmetic over operands that are not all integer literals whose
-- folded value fits 'Int64'. The check is purely syntactic — it does not
-- consult refinement predicates that might witness bounds. This is the
-- conservative-honest discharge of the Int64 overflow gap documented at
-- 'LLMLL.md §5.3.5'; the principled clearance paths are (i) ?proof-required
-- + Leanstral, (ii) post-v0.11 INT-2 unbounded 'int', or (iii) post-freeze
-- INT-3 'machine-int' under QF-BV.
--
-- The arithmetic operators recognised are the LLMLL surface forms emitted by
-- both 'EOp' and 'EApp' nodes: '+', '-', '*', '/', 'mod', 'rem', '^', '**'.
-- Predicate, boolean, list, and string operators are not arithmetic and do
-- not taint. Literal folding clears only the simplest case (a constant value
-- inside Int64 range); any non-literal operand taints the surrounding op.
bodyHasOverflowArith :: Expr -> Bool
bodyHasOverflowArith = go
  where
    arithOps :: [Name]
    arithOps = ["+", "-", "*", "/", "mod", "rem", "^", "**"]

    -- All operands are integer literals whose computed value fits Int64.
    -- Used to clear the taint for compile-time constant expressions like
    -- (+ 40 2). The arithmetic itself is performed on Haskell Integer and
    -- the result is range-checked; out-of-range constants taint, matching
    -- the semantic claim "arithmetic that may overflow at Haskell level."
    allLitsInBounds :: [Expr] -> Bool
    allLitsInBounds es =
      let lits = traverse litValue es
      in case lits of
           Just vs -> all (\v -> v >= toInteger (minBound :: Int)
                              && v <= toInteger (maxBound :: Int)) vs
           Nothing -> False

    litValue :: Expr -> Maybe Integer
    litValue (ELit (LitInt n)) = Just n
    litValue _                 = Nothing

    isArith :: Name -> Bool
    isArith op = op `elem` arithOps

    go :: Expr -> Bool
    go (EOp op args)  | isArith op = not (allLitsInBounds args) || any go args
                      | otherwise  = any go args
    go (EApp op args) | isArith op = not (allLitsInBounds args) || any go args
                      | otherwise  = any go args
    go (ELit _)         = False
    go (EVar _)         = False
    go (EHole _)        = False
    go (EIf c t e)      = go c || go t || go e
    go (ELet bindings body) = any (\(_, _, rhs) -> go rhs) bindings || go body
    go (EMatch scr arms) = go scr || any (go . snd) arms
    go (ELambda _ body) = go body
    go (EDo steps)      = any (\(DoStep _ e) -> go e) steps
    go (EPair l r)      = go l || go r
    go (EAwait e)       = go e

-- | Convert a linear arithmetic LLMLL Expr to a FQPred.
-- Returns Nothing for non-linear or unsupported expressions (→ skip/proof-required).
exprToPred :: Expr -> Maybe FQPred
-- MATCH-WIDEN Slice 1: a bare nullary constructor of a mixed/payload sum reflects
-- as the FQData nullary term (mirrors the payload EApp path). Safe because
-- all-nullary-enum ctors are int-tag-desugared (desugarCtorValues) before here, so an
-- uppercase EVar reaching exprToPred is a mixed-sum nullary constructor, not a variable.
exprToPred (EVar v)
  | not (T.null v), isUpper (T.head v) = Just (FQApp (fqCtorSym v) [])
  | otherwise                          = Just (FQVar v)
exprToPred (ELit (LitInt n)) = Just (FQLit n)
exprToPred (ELit (LitBool True))  = Just FQTrue
exprToPred (ELit (LitBool False)) = Just FQFalse
-- STRLIT (Stage 1): a string literal reflects to a content-interned nullary Str
-- constant. SOUND ONLY paired with injectStrLitDistinct, which conjoins pairwise
-- `/=` over occurring literal constants — the flip alone is UNSAFE-unsound (a model
-- identifying "a"="b" spuriously refutes; §6.1 F2). Term-vs-term string equality
-- already reflected; this closes the literal gap.
exprToPred (ELit (LitString s)) = Just (FQApp (strlitConst s) [])
-- | LEVER-A2.2 get-comparison bridge (well-sortedness): a bool-valued
-- @(map-get m k)@ compared against a bool literal reflects the value select
-- against the int-0/1 tag — @FQEq (Map_select …) (FQLit 0/1)@ — never the
-- ill-sorted @FQEq (Map_select …) FQTrue@. Either operand order. Sound and
-- context-free: the homogeneous @=@ typing (TypeCheck.hs:81) means a bool
-- literal opposite a map-get forces the map bool-valued. The value-range fact
-- (injectBoolValRangeFacts) supplies @0 ≤ v ≤ 1@ so a @/=@ here is exact, not a
-- ℤ over-approximation (professor review 2026-07-13). Must precede the generic
-- @=@/@/=@ clauses below.
exprToPred (EApp op [l, r])
  | op `elem` eqNeqOps, isMapGetHead l, ELit (LitBool b) <- r
      = (\s -> FQBinPred (relOf op) s (FQLit (boolTag b))) <$> exprToPred l
  | op `elem` eqNeqOps, ELit (LitBool b) <- l, isMapGetHead r
      = (\s -> FQBinPred (relOf op) (FQLit (boolTag b)) s) <$> exprToPred r
  where
    eqNeqOps = ["=", "==", "/=", "!=", "≠"] :: [Text]
    relOf o  = if o `elem` (["/=", "!=", "≠"] :: [Text]) then FQNeq else FQEq
exprToPred (EApp op [l, r])
  | op `elem` [">=", "≥"] = (\a b -> FQBinPred FQGe  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` [">"]        = (\a b -> FQBinPred FQGt  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["<=", "≤"] = (\a b -> FQBinPred FQLe  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["<"]        = (\a b -> FQBinPred FQLt  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["=", "=="]  = (\a b -> FQBinPred FQEq  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["/=", "!=", "≠"] = (\a b -> FQBinPred FQNeq a b) <$> exprToPred l <*> exprToPred r
  | op == "+"              = (\a b -> FQBinArith FQAdd a b) <$> exprToPred l <*> exprToPred r
  | op == "-"              = (\a b -> FQBinArith FQSub a b) <$> exprToPred l <*> exprToPred r
  -- non-linear ops: reject
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = Nothing
exprToPred (EApp "and" args) = FQAnd <$> mapM exprToPred args
exprToPred (EApp "or"  args) = FQOr  <$> mapM exprToPred args
exprToPred (EApp "not" [a])  = FQNot <$> exprToPred a
-- IMPL-SUGAR: (=> p q) and (<=> p q) are pure sugar. Desugar here (VC-emission
-- only) to the or/not/and forms; the resulting FQ is byte-identical to writing
-- the expansion by hand. The AST retains =>/<=> (round-trip + schema).
exprToPred (EApp "=>"  [p, q]) = exprToPred (EApp "or" [EApp "not" [p], q])
exprToPred (EApp "<=>" [p, q]) =
  exprToPred (EApp "and" [EApp "or" [EApp "not" [p], q], EApp "or" [EApp "not" [q], p]])
-- NIW (v0.12): measure-class applications → uninterpreted-function terms.
-- The argument is a WF base term (REF-META-3 M3); exprToPred (EVar v) = FQVar v
-- carries it through unconditionally. Range facts (m t >= 0) are injected
-- centrally at addConst, not here. Only string-length / list-length are admitted.
exprToPred (EApp "string-length" [a]) = (\x -> FQApp "strLen"  [x]) <$> exprToPred a
exprToPred (EApp "list-length"   [a]) = (\x -> FQApp "listLen" [x]) <$> exprToPred a
-- PAIR-RET: pair projections reflect to the native Pair2 selector terms, a pair
-- construction to the constructor. The product is the single-constructor restriction
-- of the COMP-4 datatype class (§5.3.3): the valid tester makes selectors total and
-- fully determined, so selector-in-goal is sound with no under-specified region
-- (professor adjudication). Symbols are namespaced (`pair2`) to avoid collision with a
-- user sum whose `Pair` constructor COMP-4 lowercases to `pair`.
exprToPred (EApp "first"  [a]) = (\x   -> FQApp "pair2_0" [x])   <$> exprToPred a
exprToPred (EApp "second" [a]) = (\x   -> FQApp "pair2_1" [x])   <$> exprToPred a
exprToPred (EPair a b)         = (\x y -> FQApp "pair2"   [x, y]) <$> exprToPred a <*> exprToPred b
-- LEVER-A1 (proposal §4): the bytes-op family reflects into the array theory —
-- bytes-length to the bytesLen UF (grounded per binder by the family-1 binder
-- fact), bytes-get/bytes-set to the interpreted select/store. Exact reflections
-- (§6.1). The MAP ops are deliberately ABSENT (stage A2): a contract mentioning
-- one falls to the catch-all below → contract-only fallback, per the
-- exact-reflection rule. These cases fire only when the ops occur, so every
-- op-free contract translates byte-identically.
exprToPred (EApp "bytes-length" [b]) = (\x -> FQApp "bytesLen" [x]) <$> exprToPred b
exprToPred (EApp "bytes-get" [b, i]) =
  (\x y -> FQApp "Map_select" [x, y]) <$> exprToPred b <*> exprToPred i
exprToPred (EApp "bytes-set" [b, i, v]) =
  (\x y z -> FQApp "Map_store" [x, y, z]) <$> exprToPred b <*> exprToPred i <*> exprToPred v
-- LEVER-A2 (proposal §4): the map ops reflect via the two-array encoding —
-- presence is the int-0/1 array (Rev 1.1), so `(map-has m k)` is the equation
-- `Map_select(m$has, k) = 1` and `(map-get m k)` reads the value array. The
-- map argument threads as a component PAIR (mapPairTermsC): variable roots
-- resolve to the split binders (guaranteed in scope by the activation gate +
-- mapClauseBlocked), map-put chains to paired stores, map-empty to const
-- arrays. A bare map-put/map-empty NOT under map-has/map-get (e.g. a
-- whole-structure equality) has no standalone case → falls back (review F1).
-- A2.2-string (map-empty lift): a DIRECT get/has on (map-empty) is degenerate
-- (an always-absent read) and its int-default encoding meets Str contexts
-- ill-sorted (elaborator crash) — route to fallback. Put-chains over map-empty
-- stay admitted (element sort inferred from the put value).
exprToPred (EApp "map-has" [mE, _]) | isMapEmptyE mE = Nothing
exprToPred (EApp "map-get" [mE, _]) | isMapEmptyE mE = Nothing
exprToPred (EApp "map-has" [mE, kE]) = do
  (h, _) <- mapPairTermsC mE
  k <- exprToPred kE
  pure (FQBinPred FQEq (FQApp "Map_select" [h, k]) (FQLit 1))
exprToPred (EApp "map-get" [mE, kE]) = do
  (_, vl) <- mapPairTermsC mE
  k <- exprToPred kE
  pure (FQApp "Map_select" [vl, k])
-- v0.8.0: Parser emits operators as EOp; delegate to EApp for uniform handling.
exprToPred (EOp op args)     = exprToPred (EApp op args)
-- COMP-4-RESULT: the Result builtins `ok`/`err` are lowercase, so the uppercase-ctor
-- clause below misses them; reflect them explicitly into the native `Result` datatype
-- constructor terms (closes the COMP-4 (a) drift for the Result builtin).
exprToPred (EApp "ok"  [e]) = (\x -> FQApp "ok"  [x]) <$> exprToPred e
exprToPred (EApp "err" [e]) = (\x -> FQApp "err" [x]) <$> exprToPred e
-- COMP-4 (a): a constructor application (uppercase head) in a contract reflects
-- into the native FQData constructor term — so a post `result = Rejected reason`
-- discharges by constructor equality.
exprToPred (EApp ctor args)
  | not (T.null ctor), isUpper (T.head ctor) = FQApp (fqCtorSym ctor) <$> mapM exprToPred args
exprToPred _ = Nothing  -- lambda, let, match, etc. → not in QF linear arith

-- | Extract qualifiers from an expression (auto-synthesis from pre/post).
-- Each atomic comparison at the top level becomes a qualifier template.
extractQualifiers :: Map Text FQSort -> Text -> Name -> Expr -> [FQQualifier]
extractQualifiers sortMap clause fnName expr =
  case exprToPred expr of
    Nothing   -> []  -- non-linear, no qualifiers
    Just pred
      -- COMP-4 (a): a post referencing a datatype constructor (a non-measure
      -- FQApp) cannot become a qualifier — the ctor would be a free symbol
      -- ("Qualifier with free vars"). Qualifiers are optional inference hints;
      -- skipping is sound (the constraint still checks the post).
      -- LEVER-A2.1 disposition (the CLASSIFY-MEASURE watch-item): array-class
      -- preds (Map_select/Map_store/Map_default/bytesLen) are DELIBERATELY
      -- caught by this same guard — LLMLL's body VCs are fully path-enumerated
      -- (no kvars), so qualifiers only feed wf-constraint inference, and an
      -- array qualifier would carry theory symbols into exactly the
      -- free-symbol crash this guard exists to prevent. All A1/A2 cruxes
      -- discharge without array qualifiers; correct as-is, no change.
      | not (Set.null (appNames pred `Set.difference` Set.fromList ["strLen", "listLen"])) -> []
      | otherwise -> atomicQualifiers sortMap fnName clause pred

-- BOOL-FRAG (v0.14.15): sortMap carries each var's real FQSort (result + params);
-- a var absent from it defaults to FQInt (unchanged behavior for int-only preds).
atomicQualifiers :: Map Text FQSort -> Name -> Text -> FQPred -> [FQQualifier]
atomicQualifiers sortMap fn clause pred =
  case pred of
    FQBinPred op l r ->
      let vars = nubT (predVars l ++ predVars r)
          params = map (\v -> (v, Map.findWithDefault FQInt v sortMap)) ("v" : vars)
          qname  = "Q_" <> fn <> "_" <> clause <> "_" <> T.pack (show (hashPred pred))
      in [FQQualifier qname params pred]
    FQAnd ps -> concatMap (atomicQualifiers sortMap fn clause) ps
    FQOr  ps -> concatMap (atomicQualifiers sortMap fn clause) ps
    _ -> []

predVars :: FQPred -> [Text]
predVars (FQVar v)            = [v]
predVars (FQLit _)            = []
predVars FQTrue               = []
predVars FQFalse              = []
predVars (FQBinPred _ l r)   = predVars l ++ predVars r
predVars (FQBinArith _ l r)  = predVars l ++ predVars r
predVars (FQAnd ps)           = concatMap predVars ps
predVars (FQOr  ps)           = concatMap predVars ps
predVars (FQNot p)            = predVars p
predVars (FQKVar _ args)      = concatMap predVars args
predVars (FQApp _ args)       = concatMap predVars args  -- NIW: measure args carry the free vars

nubT :: [Text] -> [Text]
nubT [] = []
nubT (x:xs) = x : nubT (filter (/= x) xs)

-- Simple hash for unique qualifier names (not cryptographic)
hashPred :: FQPred -> Int
hashPred = T.length . T.pack . show

-- ---------------------------------------------------------------------------
-- Body-VC translation engine (v0.8.0 BODY-VC-1, extended v0.9.0 COMP-1)
-- ---------------------------------------------------------------------------

-- | Pure entry point: translates a function body to a BodyVC tree.
-- Takes a seed counter value and a sort environment (built from int params).
-- Returns (updatedCounter, Maybe BodyVC). Nothing = unsupported expression.
--
-- v0.9.0: accepts ContractEnv and SCC set for compositional verification.
-- Pass Map.empty / Set.empty for leaf functions (backward compat).
-- | COMP-4 (b): the elimination-side refinement env. Keyed by the same
-- "<scrutinee>$<arm>" derived keys as the sort env; the value is the matched
-- arm payload's declared refinement as (bindingVar, pred). Read-only, seeded
-- once by the driver (bodyToPredFromR); threaded as a Reader context so the
-- bodyToPredM equations and their recursive calls are untouched.
type RefEnv = Map Name (Name, Expr)

-- | MATCH-WIDEN STRETCH (v0.14.12): scrutinee → (constructor → declaration-order tag).
-- Threaded so the int-tag discrimination guard uses a constructor's DECLARATION tag
-- (agreeing with the post's `=Ctor` desugar) rather than its arm position — otherwise a
-- match that reorders its arms false-refutes a scrutinee-constructor post.
type ScrutTags = Map Name (Map Name Int)

bodyToPredFrom :: Int -> SortEnv -> ContractEnv -> Set.Set Name -> Expr -> (Int, Maybe BodyVC)
bodyToPredFrom seed sortEnv cenv sccSet expr =
  bodyToPredFromR seed sortEnv Map.empty Map.empty cenv sccSet expr

-- | COMP-4 (b): bodyToPredFrom with an explicit elimination-side RefEnv (and, MATCH-WIDEN
-- STRETCH, a ScrutTags map). The driver seeds RefEnv from refined-payload params and
-- ScrutTags from two-arm payload sums; existing callers use 'bodyToPredFrom' (both empty).
bodyToPredFromR :: Int -> SortEnv -> RefEnv -> ScrutTags -> ContractEnv -> Set.Set Name -> Expr -> (Int, Maybe BodyVC)
bodyToPredFromR seed sortEnv refEnv scrutTags cenv sccSet expr =
  -- LEVER-A1: bytes-get/bytes-set join the ANF hoist set so a nested occurrence
  -- (argument/operator position) lifts into a let and threads its CallVC
  -- (pre obligation + exact-pinning post). Hoisting only fires on occurrence —
  -- byte-inert for every op-free body.
  -- LEVER-A2: map-get joins the hoist set (its presence pre needs the CallVC
  -- channel); map-put/map-empty deliberately do NOT (they stay inline so
  -- expandMapLets/mapPairTermsB thread them as component pairs). expandMapLets
  -- runs FIRST: pure map-typed lets substitute into their bodies, reducing the
  -- §5.1 pipeline shape to the composite form. Inert for map-let-free bodies.
  let callNames = Map.keysSet cenv `Set.union` Set.fromList ["bytes-get", "bytes-set", "map-get"]
      (result, finalCounter) = runStateFrom seed $ do
        expr' <- aNormalizeBody callNames (expandMapLets (Map.keysSet cenv) expr)
        runReaderT (bodyToPredM Map.empty sortEnv cenv sccSet expr') (refEnv, scrutTags)
  in (finalCounter, result)
  where
    -- Run a State Int computation with a given starting value.
    -- Returns (result, finalState).
    runStateFrom :: Int -> State Int a -> (a, Int)
    runStateFrom s action =
      let go = do { r <- action; c <- get; return (r, c) }
      in evalState go s

-- | Fresh name generator for alpha-renaming.
freshName :: MonadState Int m => Name -> m Text
freshName base = do
  n <- get
  put (n + 1)
  return ("_bv_" <> base <> "_" <> T.pack (show n))

-- | A-normalization for the body-VC path. Lift user-function CALLS out of
-- argument / operator / pair-component / if-condition / match-scrutinee
-- positions into fresh @let@ bindings, so every call has an enclosing 'ELet'
-- for the emitter to thread its 'CallVC' continuation. Without this, a nested
-- call @(f (g x))@ hits 'bodyToPredM'\'s @translateCallArg@, which accepts only
-- a 'SimpleVC' argument and rejects the @(g x)@ 'CallVC' — falling the whole
-- call back to @asserted@. Calls in TAIL position (if-branches, let-body, the
-- final expr) and in let-rhs are left in place; the emitter already handles
-- those.
--
-- Identity on any expression with no call in argument position, so it never
-- perturbs a function that already verified body-faithfully. Uses the shared
-- alpha-renaming counter (runs before 'bodyToPredM', which continues it).
aNormalizeBody :: Set.Set Name -> Expr -> State Int Expr
aNormalizeBody calls = normTail
  where
    isCall f = f `Set.member` calls

    -- Tail context: a call at the head is fine; hoist calls from sub-positions.
    normTail :: Expr -> State Int Expr
    normTail e = case e of
      EApp f args     -> do { (bs, as) <- atomizeArgs args; pure (wrapLets bs (EApp f as)) }
      EOp  op args    -> do { (bs, as) <- atomizeArgs args; pure (wrapLets bs (EOp op as)) }
      EPair a b       -> do { (bs, as) <- atomizeArgs [a, b]; pure (wrapLets bs (mkPair as)) }
      EIf c t f       -> do
        (bs, c') <- atomize c
        t' <- normTail t
        f' <- normTail f
        pure (wrapLets bs (EIf c' t' f'))
      EMatch s arms   -> do
        (bs, s') <- atomize s
        arms' <- mapM (\(p, rhs) -> (,) p <$> normTail rhs) arms
        pure (wrapLets bs (EMatch s' arms'))
      ELet binds body -> do
        binds' <- mapM (\(p, mt, rhs) -> (\r -> (p, mt, r)) <$> normTail rhs) binds
        body'  <- normTail body
        pure (ELet binds' body')
      _               -> pure e

    -- Atom context: must become atomic; a call here is hoisted to a fresh let.
    atomize :: Expr -> State Int ([(Pattern, Maybe Type, Expr)], Expr)
    atomize e = case e of
      EApp f args | isCall f -> do
        (bs, as) <- atomizeArgs args
        t <- freshName "anf"
        pure (bs ++ [(PVar t, Nothing, EApp f as)], EVar t)
      EApp op args -> do { (bs, as) <- atomizeArgs args; pure (bs, EApp op as) }
      EOp  op args -> do { (bs, as) <- atomizeArgs args; pure (bs, EOp op as) }
      EPair a b    -> do { (bs, as) <- atomizeArgs [a, b]; pure (bs, mkPair as) }
      _            -> pure ([], e)

    atomizeArgs :: [Expr] -> State Int ([(Pattern, Maybe Type, Expr)], [Expr])
    atomizeArgs xs = do
      rs <- mapM atomize xs
      pure (concatMap fst rs, map snd rs)

    mkPair [a, b] = EPair a b
    mkPair _      = error "aNormalizeBody: pair arity"

    -- Nested single-binding lets → unambiguous sequential (let*) scoping.
    wrapLets :: [(Pattern, Maybe Type, Expr)] -> Expr -> Expr
    wrapLets []     e = e
    wrapLets (b:bs) e = ELet [b] (wrapLets bs e)

-- | Core body-to-predicate translation. Handles all operators directly
-- (NOT delegating to exprToPred) to preserve the alpha-renaming environment.
--
-- exprToPred does not consult the renaming env — it translates EVar v as
-- FQVar v using the original name. If a let-bound variable (renamed to
-- _bv_x_0) appears inside an operator expression and we delegate to
-- exprToPred, the .fq output will reference the un-renamed name, which
-- the solver cannot resolve.
--
-- v0.9.0: Extended with ContractEnv and SCC set for compositional verification.
-- When encountering EApp to a contracted user function, uses assume-guarantee
-- reasoning (COMP-0 §2). SCC set excludes recursive functions' own body VCs
-- but allows callers to use assume-guarantee (Issue 4 relaxation).
bodyToPredM :: Map Name Name  -- ^ renaming env
            -> SortEnv        -- ^ sort env
            -> ContractEnv    -- ^ v0.9.0: contract lookup
            -> Set.Set Name   -- ^ v0.9.0: recursive SCC set (for own-body exclusion)
            -> Expr
            -> ReaderT (RefEnv, ScrutTags) (State Int) (Maybe BodyVC)

-- Literals
bodyToPredM _ _ _ _ (ELit (LitInt n)) = return (Just (SimpleVC [] (FQLit n)))
bodyToPredM _ _ _ _ (ELit (LitBool True))  = return (Just (SimpleVC [] FQTrue))
bodyToPredM _ _ _ _ (ELit (LitBool False)) = return (Just (SimpleVC [] FQFalse))
-- STRLIT (body-channel flip): a string literal as a body/branch LEAF reflects to
-- its interned nullary Str constant — `(if (map-has m k) (map-get m k) "none")`
-- now discharges body-faithfully (the string-returning defensive-read shape).
bodyToPredM _ _ _ _ (ELit (LitString s)) =
  return (Just (SimpleVC [] (FQApp (strlitConst s) [])))

-- MATCH-WIDEN Slice 1: a bare nullary constructor of a mixed/payload sum (NOT
-- int-tag-desugared, since buildCtorTagMap excludes non-all-nullary sums) reflects
-- as the FQData nullary constructor term, mirroring the payload EApp path below.
bodyToPredM _ _ _ _ (EVar v)
  | not (T.null v), isUpper (T.head v) =
      return (Just (SimpleVC [] (FQApp (fqCtorSym v) [])))

-- Variables: look up renamed name, check sort env
bodyToPredM env sortEnv _ _ (EVar v) =
  let renamed = fromMaybe v (Map.lookup v env)
  in case Map.lookup renamed sortEnv of
       Just FQInt  -> return (Just (SimpleVC [] (FQVar renamed)))
       Just FQBool -> return (Just (SimpleVC [] (FQVar renamed)))  -- BOOL-FRAG: bare bool var body
       -- STRLIT (body-channel flip): a Str-sorted var — an ANF-hoisted string
       -- map-get result (CallVC-seeded at mapSelValSort) or a seeded put-value
       -- param — reflects, so `(= t "active")` as a bool RESULT leaf and a
       -- Str-var body/leaf are body-faithful. Sort-safe: the typechecker
       -- confines a string term to string positions, and every equation it can
       -- appear in meets another Str-sorted term (strlit constant, Str var, or
       -- Str Map_select).
       Just FQStr  -> return (Just (SimpleVC [] (FQVar renamed)))
       _           -> return Nothing  -- non-scalar or unknown sort → fallback

-- v0.9.0: User-defined function call with contract (COMP-0 §2, §3)
-- Issue 4 resolution: SCC guard REMOVED. Callers of recursive functions
-- may use assume-guarantee against the recursive function's contract.
-- A recursive function's OWN body VC is emitted and discharged too: the cycle
-- is verified by the mutual-recursion assume-guarantee rule (each member assumes
-- its callees' posts, proves its own body) — sound at PARTIAL correctness
-- (termination unverified; R7). See LLMLL.md §0.1 / §4.3.
bodyToPredM env se cenv _sccSet (EApp fname args)
  | fname `Map.member` cenv
  , lookupArithOp fname == Nothing   -- not a builtin operator
  , lookupPredOp fname == Nothing    -- not a builtin operator
  , fname `notElem` ["not", "and", "or", "*", "/", "mod", "rem", "^", "**"]
  = do
    -- Translate arguments. F-NIW-2: a bare-variable argument translates to its
    -- FQVar regardless of sort — the type checker guarantees its uses in the
    -- callee contract are sort-consistent, and this lets a carrier (string/list)
    -- argument reach the call-pre substitution so a measure-refined param's
    -- obligation is emitted instead of forcing whole-call fallback. Non-variable
    -- arguments still route through bodyToPredM (int/QF-LIA only).
    let translateCallArg (EVar v) =
          return (Just (FQVar (fromMaybe v (Map.lookup v env))))
        translateCallArg a = do
          mvc <- bodyToPredM env se cenv _sccSet a
          return $ case mvc of Just (SimpleVC [] p) -> Just p; _ -> Nothing
    mArgPredsList <- mapM translateCallArg args
    let mArgPreds = sequence mArgPredsList
    case mArgPreds of
      Nothing -> return Nothing  -- argument translation failed
      Just argPreds -> do
        let (params, contract, mRetType) = cenv Map.! fname
            paramNames = map fst params
            -- LEVER-A1: a callee returning bytes[n] whose contract mentions a
            -- bytes op sorts its result var at the array sort (its post's
            -- reflected terms mention the result). A bytes return WITHOUT
            -- bytes ops in the contract keeps today's FQInt — byte-inertness
            -- for the opaque-carrier corpus (the crypto call chains).
            -- LEVER-A2.1: a callee returning a LITERAL map[int,int] whose
            -- contract mentions a map op sorts its result var at the array
            -- sort too — the marker the ELet CallVC case reads to seed the
            -- result's split component binders (r$has/r$val). Syntactic
            -- literal check only (bodyToPredM has no AliasMap — the
            -- PAIR-RET-2 precedent); an alias-hidden map return keeps FQInt
            -- and its post components stay unsubstituted → not assumed.
            calleeRetSort = case mRetType of
              Just (TBytes _) | contractMentionsBytesOp contract -> byteArraySort
              Just t | syntEncodableMapTy t, contractMentionsMapOp contract -> syntMapRetSort t
              _ -> maybe FQInt typeToSort mRetType
        -- Build substitution: callee params → translated args.
        -- LEVER-A2.1 (cross-call map assume-guarantee): a map-op-bearing callee
        -- contract reflects COMPONENT-rooted names (p$has/p$val via
        -- mapPairTermsC), which the plain param→arg substitution cannot
        -- rewrite. For each literal map[int,int] param whose raw ARG pair-
        -- translates in the caller (mapPairTermsB — requires the caller's own
        -- split binders, i.e. the caller is gated), extend the substitution
        -- with the component keys. A map param whose arg does NOT translate
        -- leaves its components unsubstituted; the leftover check below then
        -- forces pre-fallback / post-non-assumption exactly as before.
        let mapCompSubst = Map.fromList $ concat
              [ [ (p <> "$has", h), (p <> "$val", vl) ]
              | ((p, pt), aE) <- zip params args, syntEncodableMapTy pt
              , Just (h, vl) <- [mapPairTermsB env se aE] ]
            -- Component names a reflected callee clause could root that MUST
            -- have a substitution entry for the clause to be caller-meaningful.
            -- Checked on the PRE-substitution predicate (whose every var is
            -- callee-scope) against the substitution's key set — checking the
            -- substituted OUTPUT would false-positive when a caller arg shares
            -- its name with the callee param (`(read1 m k)` with param `m`:
            -- the correctly-substituted caller `m$has` is textually identical
            -- to the callee leftover).
            calleeCompNames = Set.fromList $ concat
              [ [ p <> "$has", p <> "$val" ]
              | p <- "result" : paramNames ]
            uncoveredComps extraKeys p =
              any (\v -> v `Set.member` calleeCompNames
                      && not (v `Map.member` mapCompSubst)
                      && not (v `Set.member` extraKeys))
                  (predVars p)
        let subst = Map.union mapCompSubst (Map.fromList (zip paramNames argPreds))
        -- Issue 1 resolution: three-way pre distinction (soundness-critical)
        --   callee has no pre        → no obligation, assumption valid
        --   callee has pre, translates → obligation emitted
        --   callee has pre, fails     → ENTIRE CALL FALLS BACK
        -- LEVER-A2.1: cross-call assume-guarantee over MAP-op-bearing callee
        -- contracts is LIVE — component substitution above rewrites p$has/p$val
        -- to the caller's translated components. The leftover check preserves
        -- the three-way soundness discipline: a reflected pre still rooting an
        -- unsubstituted component (ungated caller, alias-hidden map param,
        -- untranslatable map arg) forces WHOLE-call fallback — never an
        -- unproven obligation, never a free variable in the .fq.
        let mPreResult = case contractPre contract of
              Nothing  -> Just Nothing
              Just pre -> case exprToPred pre of
                            Nothing -> Nothing       -- untranslatable pre → fallback
                            Just p  ->
                              if uncoveredComps Set.empty p
                                then Nothing         -- uncovered map component → fallback
                                else Just (Just (applySubst subst p))
        case mPreResult of
          Nothing -> return Nothing  -- soundness: cannot assume post without verifying pre
          Just mPrePred -> do
            -- Translate post (Nothing = no post → no assumption).
            -- PAIR-RET-2: bodyToPredM has no AliasMap, so use a syntactic, conservative
            -- guard — if the callee returns a pair with any non-scalar/non-list/
            -- non-nested-scalar-pair component, do NOT assume its post (it could
            -- mis-sort `pair2_i` against the alias-unaware retSort and crash the
            -- solver). The callee itself already fell back when emitted.
            let mPostPred | syntacticUnsafePairRet mRetType = Nothing
                          -- LEVER-A1: a callee post applying a bytes op to `result`
                          -- when the result var is NOT array-sorted (a non-TBytes or
                          -- alias-hidden return) would emit an ill-sorted Map_*/bytesLen
                          -- term over an int var and crash the solver — do not assume
                          -- the post (sound weakening; the call still proves its pre).
                          | bytesOpOnResult (contractPost contract)
                            && calleeRetSort /= byteArraySort = Nothing
                          | otherwise                       = contractPost contract >>= exprToPred
            -- Fresh result variable
            resultVar <- freshName ("call_" <> fname)
            -- LEVER-A2.1: a map-returning callee's post roots result$has/
            -- result$val — substitute them to the fresh result var's split
            -- components (declared by the ELet CallVC seed via the
            -- mapArraySort marker). Guarded on the marker: without it the
            -- components would be free vars, so the leftover check below
            -- drops the assumption (sound weakening) instead.
            -- A2.2-string: string-map returns (strMapArraySort marker) substitute
            -- their components identically — the substitution is name-driven.
            let resultCompSubst
                  | isMapArrRetSort calleeRetSort = Map.fromList
                      [ ("result$has", FQVar (resultVar <> "$has"))
                      , ("result$val", FQVar (resultVar <> "$val")) ]
                  | otherwise = Map.empty
                postSubst = Map.union resultCompSubst
                              (Map.insert "result" (FQVar resultVar) subst)
                mPostSubst = do
                  p <- mPostPred
                  if uncoveredComps (Map.keysSet resultCompSubst) p
                    then Nothing                    -- uncovered component → not assumed
                    else Just (applySubst postSubst p)
                retSort = calleeRetSort
            -- Issue 3 resolution: return CallVC directly (Option A)
            -- The enclosing ELet case fills the real continuation.
            return $ Just $ CallVC
              { cvCallee         = fname
              , cvArgs           = argPreds
              , cvPreObligation  = mPrePred
              , cvPostAssumption = mPostSubst
              , cvResultVar      = resultVar
              , cvResultSort     = retSort
              , cvContinuation   = SimpleVC [] (FQVar resultVar)
              }

-- Binary arithmetic operators (+, -)
bodyToPredM env se cenv sccSet (EApp op [l, r])
  | Just binOp <- lookupArithOp op = do
      lvc <- bodyToPredM env se cenv sccSet l
      rvc <- bodyToPredM env se cenv sccSet r
      case (lvc, rvc) of
        (Just (SimpleVC [] lp), Just (SimpleVC [] rp)) ->
          return . Just $ SimpleVC [] (FQBinArith binOp lp rp)
        _ -> return Nothing

-- Binary comparison operators (>=, >, <=, <, =, /=, plus Unicode)
bodyToPredM env se cenv sccSet (EApp op [l, r])
  | Just binOp <- lookupPredOp op = do
      lvc <- bodyToPredM env se cenv sccSet l
      rvc <- bodyToPredM env se cenv sccSet r
      case (lvc, rvc) of
        (Just (SimpleVC [] lp), Just (SimpleVC [] rp)) ->
          return . Just $ SimpleVC [] (FQBinPred binOp lp rp)
        _ -> return Nothing

-- Non-linear operators: reject
bodyToPredM _ _ _ _ (EApp op [_, _])
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = return Nothing

-- Logical operators: not, and, or
bodyToPredM env se cenv sccSet (EApp "not" [a]) = do
  avc <- bodyToPredM env se cenv sccSet a
  case avc of
    Just (SimpleVC [] p) -> return . Just $ SimpleVC [] (FQNot p)
    _ -> return Nothing

bodyToPredM env se cenv sccSet (EApp "and" args) = do
  avcs <- mapM (bodyToPredM env se cenv sccSet) args
  let preds = [p | Just (SimpleVC [] p) <- avcs]
  if length preds == length args
    then return . Just $ SimpleVC [] (FQAnd preds)
    else return Nothing

bodyToPredM env se cenv sccSet (EApp "or" args) = do
  avcs <- mapM (bodyToPredM env se cenv sccSet) args
  let preds = [p | Just (SimpleVC [] p) <- avcs]
  if length preds == length args
    then return . Just $ SimpleVC [] (FQOr preds)
    else return Nothing

-- IMPL-SUGAR: (=> p q) / (<=> p q) desugar to or/not/and (byte-identical .fq).
bodyToPredM env se cenv sccSet (EApp "=>" [p, q]) =
  bodyToPredM env se cenv sccSet (EApp "or" [EApp "not" [p], q])
bodyToPredM env se cenv sccSet (EApp "<=>" [p, q]) =
  bodyToPredM env se cenv sccSet
    (EApp "and" [EApp "or" [EApp "not" [p], q], EApp "or" [EApp "not" [q], p]])

-- NIW (v0.12): measure-class application in a body → uninterpreted-function term.
-- The argument is a bare base-typed binding (Phase 1, REF-META-3 M3); we translate
-- it directly to an FQVar under the renaming env rather than recursing through
-- bodyToPredM (whose EVar case admits only int-sorted vars). Nested/non-var args
-- fall through to the catch-all (→ body fallback), which is sound.
bodyToPredM env _ _ _ (EApp "string-length" [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "strLen"  [FQVar (fromMaybe v (Map.lookup v env))])
bodyToPredM env _ _ _ (EApp "list-length"   [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "listLen" [FQVar (fromMaybe v (Map.lookup v env))])

-- LEVER-A1: the reflected bytes-op family in body position (proposal §4).
-- `bytes-length` mirrors the measure clauses above (EVar argument only —
-- aNormalizeBody hoists bytes-set out of argument position, so the argument is
-- always a variable post-ANF; anything else → catch-all → fallback, sound).
bodyToPredM env _ _ _ (EApp "bytes-length" [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "bytesLen" [FQVar (fromMaybe v (Map.lookup v env))])

-- `bytes-get b i` → an EXACT-PINNING CallVC (§6.1): the fresh result var is
-- EQUATED to the interpreted `Map_select` term in the assumed post, so all
-- downstream reasoning sees the theory term itself — never an opaque skolem
-- (a skolem is sound for SAFE but licenses spurious refutation). The
-- index-in-bounds pre rides the existing call-pre machinery (PROVE polarity,
-- path-guarded, tag "call-pre:bytes-get"); the byte-range fact is injected per
-- occurring select term (injectRangeFacts, family 2).
bodyToPredM env se cenv sccSet (EApp "bytes-get" [EVar b, iE]) = do
  let bP = FQVar (fromMaybe b (Map.lookup b env))
  mIvc <- bodyToPredM env se cenv sccSet iE
  case mIvc of
    Just (SimpleVC [] iP) -> do
      r <- freshName "call_bytes_get"
      let pre  = FQAnd [ FQBinPred FQLe (FQLit 0) iP
                       , FQBinPred FQLt iP (FQApp "bytesLen" [bP]) ]
          post = FQBinPred FQEq (FQVar r) (FQApp "Map_select" [bP, iP])
      return . Just $ CallVC "bytes-get" [bP, iP] (Just pre) (Just post)
                             r FQInt (SimpleVC [] (FQVar r))
    _ -> return Nothing

-- `bytes-set b i v` → the same exact-pinning shape at the array sort. The
-- assumed post carries the store equality AND the length-preservation fact
-- `bytesLen(r) = bytesLen(b)` (semantically valid — store preserves length —
-- and needed so a subsequent read of the result can discharge its bound).
bodyToPredM env se cenv sccSet (EApp "bytes-set" [EVar b, iE, vE]) = do
  let bP = FQVar (fromMaybe b (Map.lookup b env))
  mIvc <- bodyToPredM env se cenv sccSet iE
  mVvc <- bodyToPredM env se cenv sccSet vE
  case (mIvc, mVvc) of
    (Just (SimpleVC [] iP), Just (SimpleVC [] vP)) -> do
      r <- freshName "call_bytes_set"
      let pre  = FQAnd [ FQBinPred FQLe (FQLit 0) iP
                       , FQBinPred FQLt iP (FQApp "bytesLen" [bP])
                       , FQBinPred FQLe (FQLit 0) vP
                       , FQBinPred FQLe vP (FQLit 255) ]
          post = FQAnd [ FQBinPred FQEq (FQVar r) (FQApp "Map_store" [bP, iP, vP])
                       , FQBinPred FQEq (FQApp "bytesLen" [FQVar r]) (FQApp "bytesLen" [bP]) ]
      return . Just $ CallVC "bytes-set" [bP, iP, vP] (Just pre) (Just post)
                             r byteArraySort (SimpleVC [] (FQVar r))
    _ -> return Nothing

-- `(bytes-zero)` → the const array (probe p4). The typechecker restricts it to
-- the whole body of a def with a literal `-> bytes[n]` return, so it only ever
-- reaches here in result position; the result binder's family-1 fact supplies
-- its length.
bodyToPredM _ _ _ _ (EApp "bytes-zero" []) =
  return . Just $ SimpleVC [] (FQApp "Map_default" [FQLit 0])

-- LEVER-A2: `map-has m k` in body position (bool atom — a bool body result or,
-- via GuardClassifier's twin case, an if-condition). Pure translation, no
-- obligation: presence testing is total.
-- A2.2-string (map-empty lift): direct get/has on (map-empty) → fallback (the
-- degenerate always-absent read; its int default meets Str contexts ill-sorted).
bodyToPredM _ _ _ _ (EApp "map-has" [mE, _]) | isMapEmptyE mE = return Nothing
bodyToPredM _ _ _ _ (EApp "map-get" [mE, _]) | isMapEmptyE mE = return Nothing
bodyToPredM env se _ _ (EApp "map-has" [mE, kE]) =
  return $ do
    (h, _) <- mapPairTermsB env se mE
    k <- mapKeyTerm env se kE
    pure (SimpleVC [] (FQBinPred FQEq (FQApp "Map_select" [h, k]) (FQLit 1)))

-- LEVER-A2: `map-get m k` → an EXACT-PINNING CallVC (§6.1), the map twin of
-- bytes-get: the key-presence pre `Map_select(m$has,k) = 1` is a PROVE-polarity
-- call-site obligation (tag "call-pre:map-get"), and the fresh result is
-- EQUATED to the value-array select — never an opaque skolem. The map argument
-- may be a composite (map-put chain / map-empty — the let-expanded pipeline
-- shape); read-over-write then discharges the presence pre for the stored key.
bodyToPredM env se _ _ (EApp "map-get" [mE, kE]) =
  case (mapPairTermsB env se mE, mapKeyTerm env se kE) of
    (Just (h, vl), Just k) -> do
      r <- freshName "call_map_get"
      -- A2.2-string: the result sort is the value array's element sort — Str for
      -- a (Map_t int Str) $val, else int (mapSelValSort, recovered from the
      -- SortEnv) — so a string-valued map-get is well-sorted, not an FQInt-vs-Str
      -- mismatch against the Str Map_select.
      let pre  = FQBinPred FQEq (FQApp "Map_select" [h, k]) (FQLit 1)
          post = FQBinPred FQEq (FQVar r) (FQApp "Map_select" [vl, k])
      return . Just $ CallVC "map-get" [h, vl, k] (Just pre) (Just post)
                             r (mapSelValSort se vl) (SimpleVC [] (FQVar r))
    _ -> return Nothing

-- Normalize EOp to EApp
bodyToPredM env se cenv sccSet (EOp name args) = bodyToPredM env se cenv sccSet (EApp name args)

-- EIf: branch into guard + then-VC + else-VC
bodyToPredM env se cenv sccSet (EIf guard thenE elseE) = do
  mGuard <- lift (guardToPredM env se guard)
  case mGuard of
    Nothing -> return Nothing
    Just gp -> do
      mthen <- bodyToPredM env se cenv sccSet thenE
      melse <- bodyToPredM env se cenv sccSet elseE
      case (mthen, melse) of
        (Just tvc, Just evc) -> return (Just (BranchVC gp [] tvc evc))
        _                    -> return Nothing

-- ELet with single PVar binding: alpha-rename, emit LetBinding, recurse
bodyToPredM env se cenv sccSet (ELet [(PVar v, _mType, rhs)] body) = do
  -- Translate the RHS
  mRhsVC <- bodyToPredM env se cenv sccSet rhs
  case mRhsVC of
    Nothing -> return Nothing
    Just (SimpleVC [] rhsPred) -> do
      -- Alpha-rename the bound variable
      renamed <- freshName v
      let env'  = Map.insert v renamed env
          sort  = predSortOf rhsPred
          se'   = Map.insert renamed sort se
          lb    = LetBinding renamed sort rhsPred
      -- Recurse on body with updated env
      mBodyVC <- bodyToPredM env' se' cenv sccSet body
      case mBodyVC of
        Nothing -> return Nothing
        Just (SimpleVC lbs resultP) ->
          return (Just (SimpleVC (lb : lbs) resultP))
        Just (BranchVC gp bs tvc evc) ->
          -- Prepend this binding to both branches
          return (Just (BranchVC gp bs (prependLB lb tvc) (prependLB lb evc)))
        -- v0.9.0: SimpleVC RHS but body produces CallVC — prepend binding
        Just cvc@(CallVC {}) ->
          return (Just (prependLB lb cvc))
    -- v0.9.0: RHS is a CallVC — thread the body as the continuation (Issue 3).
    -- F-NIW-4: alias the let variable directly to the call's result var (rVar),
    -- which the CallVC continuation binds with the callee's post. Minting a fresh
    -- name here left the let var unbound (never equated to rVar) — a free variable
    -- in every constraint that referenced it (the withdraw-twice / banking_ledger
    -- crash, masked pre-F-NIW-3 by liquid-fixpoint's hyphen mis-lex).
    Just (CallVC cal callArgs mPre mPost rVar rSort _cont) -> do
      -- LEVER-A2.1: a map-returning callee (rSort == mapArraySort, the
      -- cross-call marker) binds its result as a SPLIT component pair — seed
      -- rVar$has/rVar$val so subsequent map ops over the let-bound name root
      -- through mapPairTermsB (env renames v → rVar; its "$has" lookup then
      -- hits these keys). The component binders themselves are declared at
      -- flatten/compile time via collectCallResultComps.
      -- A2.2-string: string-map returns (strMapArraySort marker) seed their
      -- components too, $val at the marker's value sort — so a downstream
      -- map-get over the let-bound string map is Str-sorted end to end.
      let env' = Map.insert v rVar env
          se0  = Map.insert rVar rSort se
          se'  = if isMapArrRetSort rSort
                   then Map.insert (rVar <> "$has") (markerHasSort rSort)
                          (Map.insert (rVar <> "$val") (markerValSort rSort) se0)
                   else se0
      mBodyVC <- bodyToPredM env' se' cenv sccSet body
      case mBodyVC of
        Nothing -> return Nothing
        Just bvc -> return $ Just $ CallVC cal callArgs mPre mPost rVar rSort bvc
    -- RHS is a branch (EIf in let RHS) — hoist via flattening.
    -- Single-path degenerate branches are handled; multi-path falls back.
    Just bvc@(BranchVC _ _ _ _) -> do
      renamed <- freshName v
      let env'  = Map.insert v renamed env
          se'   = Map.insert renamed FQInt se
          paths = flattenBodyVC bvc
      case paths of
        -- Degenerate single-path: the branch always takes one path
        [(_, pathLBs, pathResult)] -> do
          let lb = LetBinding renamed FQInt pathResult
          mBodyVC <- bodyToPredM env' se' cenv sccSet body
          case mBodyVC of
            Nothing -> return Nothing
            Just (SimpleVC lbs resultP) ->
              return (Just (SimpleVC (pathLBs ++ [lb] ++ lbs) resultP))
            Just (BranchVC gp bs tvc evc) ->
              return (Just (BranchVC gp bs
                (prependLBs (pathLBs ++ [lb]) tvc)
                (prependLBs (pathLBs ++ [lb]) evc)))
        -- Multi-path (MATCH-WIDEN-2, §S4 sequential matches): thread the branch
        -- into the body instead of falling back. At each RHS-branch leaf, bind
        -- `v` to that path's result and translate `body` FRESH — fresh skolems
        -- per path, because 'collectBranchBinders' does not dedup, so grafting a
        -- shared body-'BranchVC' would double-declare its binders. The RHS branch
        -- guards + payload binders are preserved; only the leaf continuation
        -- changes. Any leaf whose body fails to translate → whole fallback
        -- (Applicative Maybe short-circuit). When `body` is itself a match this
        -- nests naturally (two sequential matches).
        _ ->
          let graftLeaves (SimpleVC lbs result) = do
                rn <- freshName v
                let env'' = Map.insert v rn env
                    se''  = Map.insert rn FQInt se
                    lb    = LetBinding rn FQInt result
                mb <- bodyToPredM env'' se'' cenv sccSet body
                return (prependLBs (lbs ++ [lb]) <$> mb)
              graftLeaves (BranchVC g bs t e) = do
                mt <- graftLeaves t
                me <- graftLeaves e
                return (BranchVC g bs <$> mt <*> me)
              graftLeaves (CallVC cal cargs mPre mPost rVar rSort cont) = do
                mc <- graftLeaves cont
                return ((\k -> CallVC cal cargs mPre mPost rVar rSort k) <$> mc)
          in graftLeaves bvc
    _ -> return Nothing

-- ELet with multiple bindings: desugar to nested single-binding ELets
bodyToPredM env se cenv sccSet (ELet (b:bs) body) =
  bodyToPredM env se cenv sccSet (ELet [b] (ELet bs body))

-- ELet with no bindings (degenerate): just translate the body
bodyToPredM env se cenv sccSet (ELet [] body) = bodyToPredM env se cenv sccSet body

-- v0.9.0 COMP-3: EMatch on Result (two-path encoding)
-- Handles: (match scrutinee ((Success s) bodyS) ((Error e) bodyE))
-- Produces: BranchVC (FQVar "_match_success_N") bodyS_VC bodyE_VC
-- Falls back on:
--   - Non-two-arm matches (general ADT → future)
--   - Constructors other than Success/Error
--   - Scrutinee translation failure
--   - Constructor-dependent postconditions (Issue 2)
--   - Unannotated return types on scrutinee calls
-- COMP-3b-general (opaque-sum elimination): a Result-typed VARIABLE scrutinee
-- (param or let-bound), detected by the derived "<v>$ok"/"<v>$err" payload-sort
-- keys the driver/ELet seeded into the SortEnv. The variable's value is opaque
-- (it is not in the value SortEnv), so we do NOT translate the scrutinee; we
-- case-split on a fresh free guard and bind each arm's payload at its declared
-- sort. Guard + payloads ride the BranchVC binder field for 'collectBranchBinders'
-- to declare (FQTrue skolems). Subsumes the former top-level flat-Result
-- special-case; fires at any nesting depth.
bodyToPredM env se cenv sccSet (EMatch (EVar r) arms)
  | Just (sV, sB, eV, eB) <- classifyResultArms arms
  , Just okSort  <- Map.lookup (r <> "$ok")  se
  , Just errSort <- Map.lookup (r <> "$err") se
  = do (refEnv, _) <- ask
       -- Result: arm1 = Success = tag 0 (Result posts are not tag-desugared, so arm order suffices).
       buildOpaqueSumBranch env se cenv sccSet r 0
         (Just (sV, okSort,  Map.lookup (r <> "$ok")  refEnv), sB)
         (Just (eV, errSort, Map.lookup (r <> "$err") refEnv), eB)

-- COMP-4 (d-elim): the same opaque-sum elimination for an arbitrary admissible
-- two-arm USER sum type, detected by per-constructor "<v>$<Ctor>" payload-sort
-- keys the driver seeded for the scrutinee variable. Ctor-agnostic generalization
-- of the Result clause above (which keeps its "$ok"/"$err" key scheme). A match
-- whose scrutinee var was not seeded (non-admissible/recursive payload) does not
-- match here and falls through to the generic path → fallback.
-- COMP-4 (d-elim) + MATCH-WIDEN (v0.14.12, mixed arms): a two-arm user-sum match
-- where each arm is a single-payload OR nullary constructor. A payload arm requires
-- its "<v>$<Ctor>" sort key to be seeded (admissible payload); a nullary arm needs
-- no key and binds no payload. A payload arm whose key is absent (non-admissible /
-- recursive payload) fails 'armOk' → falls through to the generic path → fallback.
-- MATCH-WIDEN-2: n-arm (≥2) user-sum match. Each constructor arm discriminates on
-- its declaration-order tag `<r>$tag = k`; the arms compose as a right-nested
-- BranchVC chain (first-match ¬prior), n=2 being byte-identical to the prior
-- binary encoding. A payload arm requires its `<r>$<Ctor>` sort key (admissible
-- payload); an arm whose key is absent (non-admissible/recursive) → whole match
-- falls back. Exhaustiveness is upstream (TypeCheck.checkExhaustive).
bodyToPredM env se cenv sccSet (EMatch (EVar r) arms)
  | Just (ctorArms, mWild) <- classifyNArmAdtArms arms
  , not (null ctorArms)
  , all (\(c, mv, _) -> armOk c mv) ctorArms
  = do (refEnv, stm) <- ask
       -- The scrutinee's declaration-order tag map (from ScrutTags) gives each arm's
       -- tag and the constructor count n (for the tag range fact `tag ∈ {0..n-1}`).
       let tagOf c   = fromMaybe 0 (Map.lookup r stm >>= Map.lookup c)
           nCtors    = maybe (length ctorArms) Map.size (Map.lookup r stm)
           armTuples = [ (tagOf c, armPayload refEnv c mv, b) | (c, mv, b) <- ctorArms ]
       buildOpaqueSumBranchN env se cenv sccSet r nCtors armTuples mWild
  where
    armOk _ Nothing  = True                          -- nullary arm: always fine
    armOk c (Just _) = Map.member (r <> "$" <> c) se  -- payload arm: must be seeded
    armPayload _      _ Nothing  = Nothing
    armPayload refEnv c (Just v) =
      (\s -> (v, s, Map.lookup (r <> "$" <> c) refEnv)) <$> Map.lookup (r <> "$" <> c) se

bodyToPredM env se cenv sccSet (EMatch scrutinee arms)
  -- Must be exactly 2 arms with Success and Error constructors
  | Just (successVar, successBody, errorVar, errorBody) <- classifyResultArms arms
  = do
    -- Translate scrutinee
    mScrutVC <- bodyToPredM env se cenv sccSet scrutinee
    case mScrutVC of
      Nothing -> return Nothing
      Just scrutVC -> do
        -- Determine the ok/err sorts from the scrutinee's type
        -- For EVar: look up in sort env (conservative: assume FQInt)
        -- For CallVC: use the callee's return type from ContractEnv
        let (okSort, errSort) = case scrutinee of
              EApp fname _ | fname `Map.member` cenv ->
                let (_, _, mRetType) = cenv Map.! fname
                in case mRetType of
                     Just (TResult okT errT) -> (typeToSort okT, typeToSort errT)
                     _                       -> (FQInt, FQInt)
              _ -> (FQInt, FQInt)  -- fallback: assume int payloads

        -- Generate fresh names for payload variables and match guard
        successRenamed <- freshName successVar
        errorRenamed   <- freshName errorVar
        guardVar       <- freshName "_match_success"

        -- Success branch: bind payload variable, translate body
        let envS = Map.insert successVar successRenamed env
            seS  = Map.insert successRenamed okSort se
        mSuccessVC <- bodyToPredM envS seS cenv sccSet successBody

        -- Error branch: bind payload variable, translate body
        let envE = Map.insert errorVar errorRenamed env
            seE  = Map.insert errorRenamed errSort se
        mErrorVC <- bodyToPredM envE seE cenv sccSet errorBody

        case (mSuccessVC, mErrorVC) of
          (Just svc, Just evc) -> do
            -- For CallVC scrutinee: thread as let-binding + branch
            -- For SimpleVC scrutinee: just branch with synthetic guard
            let matchBinders = [(guardVar, FQBool, FQTrue), (successRenamed, okSort, FQTrue), (errorRenamed, errSort, FQTrue)]
            case scrutVC of
              SimpleVC [] _scrutPred ->
                return (Just (BranchVC (FQVar guardVar) matchBinders svc evc))
              CallVC {} ->
                -- The scrutinee is a function call — wrap the branch as CallVC continuation
                -- The CallVC result is the match scrutinee; branch discriminates its constructor
                return (Just (setCallVCContinuation scrutVC (BranchVC (FQVar guardVar) matchBinders svc evc)))
              _ ->
                -- Scrutinee produced a complex VC (branch, etc.) — fallback
                return Nothing
          _ -> return Nothing

-- Everything else: match, app (user-defined without contract), lambda, etc. → fallback
-- COMP-4 (a): a constructor application (uppercase head; not a cenv callee or a
-- builtin op, which are lowercase) — e.g. (Rejected reason) — reflects into the
-- native FQData constructor term `(ctor args)`. The strict-core gate admits only
-- admissible-sum constructors, so a ctor reaching a body-faithful VC is declared
-- (typeSorts real arities); the field name is the selector. The ctor symbol is
-- routed through `fqCtorSym` to agree with emitCtor's declaration symbol.
bodyToPredM env se cenv sccSet (EApp ctor args)
  | not (T.null ctor), isUpper (T.head ctor) = do
      let tr (EVar v) = return (Just (FQVar (fromMaybe v (Map.lookup v env))))
          tr a        = do mv <- bodyToPredM env se cenv sccSet a
                           return $ case mv of Just (SimpleVC [] p) -> Just p; _ -> Nothing
      margs <- mapM tr args
      return $ (\fas -> SimpleVC [] (FQApp (fqCtorSym ctor) fas)) <$> sequence margs

-- COMP-4-RESULT: the lowercase Result builtins `ok`/`err` constructed in a body reflect
-- to the native Result constructor term (the uppercase clause above misses them).
bodyToPredM env se cenv sccSet (EApp rc [a])
  | rc == "ok" || rc == "err" = do
      let tr (EVar v) = return (Just (FQVar (fromMaybe v (Map.lookup v env))))
          tr e        = do mv <- bodyToPredM env se cenv sccSet e
                           return $ case mv of Just (SimpleVC [] p) -> Just p; _ -> Nothing
      ma <- tr a
      return $ (\p -> SimpleVC [] (FQApp rc [p])) <$> ma

-- PAIR-RET: a pair construction in a body reflects to the Pair2 constructor term so a
-- function returning `(pair a b)` is body-faithful for a projection post. Mirrors the
-- COMP-4 (a) constructor clause above (the `tr` helper handles EVar specially and
-- recurses for compound operands).
bodyToPredM env se cenv sccSet (EPair a b) = do
  let tr (EVar v) = return (Just (FQVar (fromMaybe v (Map.lookup v env))))
      tr e        = do mv <- bodyToPredM env se cenv sccSet e
                       return $ case mv of Just (SimpleVC [] p) -> Just p; _ -> Nothing
  pa <- tr a
  pb <- tr b
  return $ (\x y -> SimpleVC [] (FQApp "pair2" [x, y])) <$> pa <*> pb
-- PAIR-RET: a body that *is* a projection (`(first p)` / `(second p)` over a pair var).
bodyToPredM env _ _ _ (EApp "first"  [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "pair2_0" [FQVar (fromMaybe v (Map.lookup v env))])
bodyToPredM env _ _ _ (EApp "second" [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "pair2_1" [FQVar (fromMaybe v (Map.lookup v env))])

bodyToPredM _ _ _ _ _ = return Nothing

-- | COMP-3b-general / COMP-4 (d-elim): build the opaque-sum elimination
-- skolem-branch for a two-arm match on an opaque (param/let-bound) variable
-- scrutinee. Each arm's payload binds as an FQTrue skolem at its declared sort;
-- the synthetic free guard + the two payloads ride the BranchVC binder field for
-- 'collectBranchBinders' to declare. The scrutinee value is opaque (absent from
-- the value SortEnv), so it is never translated — the case-split is on the fresh
-- guard, and exhaustiveness/distinctness are discharged structurally (the
-- type-checker's two-arm coverage + the boolean guard), staying in QF-LIA.
buildOpaqueSumBranch
  :: Map Name Name -> SortEnv -> ContractEnv -> Set.Set Name
  -> Name                                               -- ^ MATCH-WIDEN STRETCH: scrutinee var (tag discrimination)
  -> Int                                                -- ^ arm-1 constructor's declaration-order tag
  -> (Maybe (Name, FQSort, Maybe (Name, Expr)), Expr)   -- ^ arm 1: optional (payload var, sort, refinement), body
  -> (Maybe (Name, FQSort, Maybe (Name, Expr)), Expr)   -- ^ arm 2
  -> ReaderT (RefEnv, ScrutTags) (State Int) (Maybe BodyVC)
-- MATCH-WIDEN (v0.14.12): each arm's payload is OPTIONAL. A nullary arm of a mixed
-- sum (Nothing) binds no payload and contributes no skolem binder; a single-payload
-- arm (Just …) is the d-elim behavior unchanged. First-match is the boolean guard
-- (arm 1 = guard-true, arm 2 = guard-false = ¬arm1), unchanged.
buildOpaqueSumBranch env se cenv sccSet scrutVar tag1 (mp1, b1) (mp2, b2) = do
  -- MATCH-WIDEN STRETCH (v0.14.12): discriminate arms on a free int TAG equality
  -- `(= <scrut>$tag 0)` (arm1) / `¬` (arm2, via flattenBodyVC's FQNot), instead of a
  -- fresh unconstrained boolean. CONSERVATIVE EXTENSION: on existing matches the arm
  -- bodies never mention the tag, so `svc under (tag=0)` ≡ `svc unconditional` — same
  -- discharge and refutation. It becomes load-bearing only for a post that references
  -- the scrutinee's constructor (desugared to `<scrut>$tag=k` in S3). The range fact
  -- `tag ∈ {0,1}` keeps the else-arm `¬(tag=0)` ≡ `tag=1`. Stays QF-LIA (no testers).
  let tagVar = scrutVar <> "$tag"
      guardP = FQBinPred FQEq (FQVar tagVar) (FQLit (toInteger tag1))
      rangeF = FQOr [ FQBinPred FQEq (FQVar tagVar) (FQLit 0)
                    , FQBinPred FQEq (FQVar tagVar) (FQLit 1) ]
  (env1, se1, binders1) <- bindArm mp1
  mvc1 <- bodyToPredM env1 se1 cenv sccSet b1
  (env2, se2, binders2) <- bindArm mp2
  mvc2 <- bodyToPredM env2 se2 cenv sccSet b2
  return $ case (mvc1, mvc2) of
    (Just vc1, Just vc2) ->
      Just (BranchVC guardP
                     ((tagVar, FQInt, rangeF) : binders1 ++ binders2)
                     vc1 vc2)
    _ -> Nothing
  where
    -- COMP-4 (b): declare a payload at its DECLARED refinement (sound because the
    -- intro-side obligation makes every caller prove it); Nothing → FQTrue skolem
    -- (d-elim). A nullary arm binds nothing and declares no skolem.
    bindArm Nothing = return (env, se, [])
    bindArm (Just (v, s, mref)) = do
      r <- freshName v
      let armPred = case mref of
            Nothing      -> FQTrue
            Just (xb, p) -> fromMaybe FQTrue (exprToPred (renameVar xb r p))
      return (Map.insert v r env, Map.insert r s se, [(r, s, armPred)])

-- | MATCH-WIDEN-2: n-way generalization of 'buildOpaqueSumBranch'. Builds a
-- right-nested 'BranchVC' chain discriminating each constructor arm on its
-- declaration-order tag `<v>$tag = kᵢ`, with the final arm (or an explicit
-- wildcard) as the terminal `¬prior` else. The tag range fact `tag ∈ {0..n-1}`
-- and every arm's payload skolem binder ride the OUTERMOST branch's binder field
-- (declared by 'collectBranchBinders'); inner branches carry none. At n=2 with no
-- wildcard this is byte-identical to 'buildOpaqueSumBranch' (one BranchVC, the
-- tag binder + both payload binders, then=arm1, else=arm2). Exhaustiveness is
-- guaranteed upstream (TypeCheck.checkExhaustive), so the terminal else soundly
-- covers the remaining constructor(s). Any arm body outside the fragment (Nothing)
-- → whole match falls back. Stays QF-LIA (no datatype testers).
buildOpaqueSumBranchN
  :: Map Name Name -> SortEnv -> ContractEnv -> Set.Set Name
  -> Name                                                    -- ^ scrutinee var (tag discrimination)
  -> Int                                                     -- ^ constructor count n (tag range fact)
  -> [(Int, Maybe (Name, FQSort, Maybe (Name, Expr)), Expr)] -- ^ constructor arms: (tag, optional payload, body)
  -> Maybe Expr                                              -- ^ optional wildcard-tail body (terminal else)
  -> ReaderT (RefEnv, ScrutTags) (State Int) (Maybe BodyVC)
buildOpaqueSumBranchN env se cenv sccSet scrutVar nCtors arms mWild = do
  let tagVar  = scrutVar <> "$tag"
      rangeF  = FQOr [ FQBinPred FQEq (FQVar tagVar) (FQLit (toInteger i)) | i <- [0 .. nCtors - 1] ]
      tagEq t = FQBinPred FQEq (FQVar tagVar) (FQLit (toInteger t))
  -- Bind then translate each arm in source order (preserves the freshName counter
  -- order, so n=2 output is byte-identical to the binary builder).
  armVCs <- forM arms $ \(tag, mp, b) -> do
    (env', se', binders) <- bindArm mp
    mvc <- bodyToPredM env' se' cenv sccSet b
    return (tag, binders, mvc)
  mWildVC <- traverse (bodyToPredM env se cenv sccSet) mWild
  let allArmVCs = sequence [ mvc | (_, _, mvc) <- armVCs ]
      wildOk    = case mWild of
                    Nothing -> Just Nothing
                    Just _  -> case mWildVC of Just (Just vc) -> Just (Just vc); _ -> Nothing
  case (allArmVCs, wildOk) of
    (Just vcs, Just mwvc) ->
      let tagged     = zip3 [ t | (t, _, _) <- armVCs ] [ bs | (_, bs, _) <- armVCs ] vcs
          allBinders = concat [ bs | (_, bs, _) <- armVCs ]
          (branchArms, terminalVC) = case mwvc of
            Just wvc -> (tagged, wvc)                              -- wildcard = terminal else
            Nothing  -> (init tagged, (\(_, _, vc) -> vc) (last tagged))  -- last arm = terminal else
          branchTags = [ t | (t, _, _) <- branchArms ]
      in case branchArms of
           [] -> return (Just terminalVC)  -- degenerate: wildcard-only match
           -- Soundness: the chain's tag guards must be DISTINCT, else a later arm's
           -- `¬prior ∧ tag=kᵢ` collapses to false (vacuous, never checked). Non-distinct
           -- tags mean the scrutinee's ScrutTags were not seeded (e.g. an int-valued
           -- enum reaching here unseeded, or a bodyToPredFrom unit call) → fall back.
           -- n=2 has a single branch guard, so this never trips it (byte-identity).
           _ | length (nub branchTags) /= length branchTags -> return Nothing
           ((tag1, _, vc1) : rest) ->
             let inner = foldr (\(tag, _, vc) acc -> BranchVC (tagEq tag) [] vc acc) terminalVC rest
             in return (Just (BranchVC (tagEq tag1)
                                       ((tagVar, FQInt, rangeF) : allBinders)
                                       vc1 inner))
    _ -> return Nothing
  where
    bindArm Nothing = return (env, se, [])
    bindArm (Just (v, s, mref)) = do
      r <- freshName v
      let armPred = case mref of
            Nothing      -> FQTrue
            Just (xb, p) -> fromMaybe FQTrue (exprToPred (renameVar xb r p))
      return (Map.insert v r env, Map.insert r s se, [(r, s, armPred)])

-- ---------------------------------------------------------------------------
-- Guard translation (v0.8.0, v0.10: extracted to GuardClassifier.hs)
-- ---------------------------------------------------------------------------

-- | Translates guard expressions to FQPred. Delegates to the shared
-- classifyGuardM core in GuardClassifier.hs (v0.10 drift mitigation,
-- spec §4.2.4). Behavioral equivalent of the pre-extraction guardToPredM.
guardToPredM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
guardToPredM = classifyGuardM

-- ---------------------------------------------------------------------------
-- Flattening and path counting (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Flatten a BodyVC tree into a list of paths.
-- Each path is (guard, let-bindings, result predicate).
-- For SimpleVC, the guard is FQTrue (unconditional).
-- For BranchVC, each branch produces paths with guard conjunction.
flattenBodyVC :: BodyVC -> [FlatPath]
flattenBodyVC (SimpleVC lbs result) = [(FQTrue, lbs, result)]
flattenBodyVC (BranchVC guard _ thenVC elseVC) =
  let thenPaths = [(conjoin guard g, lbs, r) | (g, lbs, r) <- flattenBodyVC thenVC]
      elsePaths = [(conjoin (FQNot guard) g, lbs, r) | (g, lbs, r) <- flattenBodyVC elseVC]
  in thenPaths ++ elsePaths
-- v0.9.0: Flatten a CallVC by threading postcondition as guard and
-- result variable as let-binding into the continuation paths.
-- The precondition obligation is emitted separately during constraint
-- emission — it is NOT folded into the body-post constraint.
flattenBodyVC (CallVC _callee _args _mPre mPost resultVar resultSort cont) =
  let contPaths = flattenBodyVC cont
      -- Add result variable as a let-binding and postcondition as guard
      resultLB = LetBinding resultVar resultSort (FQVar resultVar)
      -- LEVER-A2.1: a map-returning callee's result is a SPLIT component pair;
      -- declare the components (self-eq declaration, the resultLB pattern) so
      -- the assumed post and downstream map ops that root on them are bound.
      -- A2.2-string: string-map returns split too; $val at the marker's value sort.
      compLBs = [ LetBinding (resultVar <> sfx) srt (FQVar (resultVar <> sfx))
                | isMapArrRetSort resultSort
                , (sfx, srt) <- [ ("$has", markerHasSort resultSort)
                                , ("$val", markerValSort resultSort) ] ]
  in [ ( conjoinAll [guard, fromMaybe FQTrue mPost]
       , resultLB : compLBs ++ lbs
       , resultPred )
     | (guard, lbs, resultPred) <- contPaths
     ]

-- | LEVER-A2.1: does any flattened path RETURN an array-sorted let-bound var
-- (a map-returning call's result)? The generic body-post constraint equates
-- `result` (int reft) against the path result — ill-sorted for an array var,
-- so the caller routes to fallback instead (§6.1).
arrayResultPath :: BodyVC -> Bool
arrayResultPath bvc =
  any (\(_, lbs, rp) -> case rp of
         FQVar v -> any (\lb -> lbName lb == v && isMapArrRetSort (lbSort lb)) lbs
         _       -> False)
      (flattenBodyVC bvc)

-- | MAP-RET-CALL (A4 F-2): is this flattened path's tail a map-returning
-- CALL-RESULT var (a marker-sorted LetBinding on the path)? Every path must be
-- for the component-pinned tail-call emission; anything else — a param tail, a
-- pure-map-term tail (mapRetChain's class), a scalar — routes the function to
-- fallback whole as before.
pinnableTail :: (FQPred, [LetBinding], FQPred) -> Bool
pinnableTail (_, lbs, rp) = case rp of
  FQVar v -> any (\lb -> lbName lb == v && isMapArrRetSort (lbSort lb)) lbs
  _       -> False

-- | Per-path outermost-branch provenance, in the SAME order as 'flattenBodyVC'.
-- For each flattened path: @Just True@ if it descends from the then-subtree of
-- the outermost 'BranchVC', @Just False@ from the else-subtree, @Nothing@ if the
-- tree has no branch (unconditional). Used to localize a refuted arm structurally
-- rather than by a path-index midpoint, which mislabels under unbalanced nesting
-- (unequal then/else path counts). Mirrors 'flattenBodyVC's recursion so the two
-- lists align positionally.
pathBranchSides :: BodyVC -> [Maybe Bool]
pathBranchSides (SimpleVC _ _)             = [Nothing]
pathBranchSides (BranchVC _ _ thenVC elseVC) =
  [Just True  | _ <- flattenBodyVC thenVC] ++
  [Just False | _ <- flattenBodyVC elseVC]
pathBranchSides (CallVC _ _ _ _ _ _ cont)  = pathBranchSides cont

-- | Count paths in a BodyVC tree with an upper bound.
-- Stops counting once the limit is exceeded (avoids state explosion).
countPathsBounded :: Int -> BodyVC -> Int
countPathsBounded limit = go
  where
    go (SimpleVC _ _) = 1
    go (BranchVC _ _ tvc evc) =
      let tc = go tvc
      in if tc >= limit then tc
         else let ec = go evc
              in min limit (tc + ec)
    go (CallVC _ _ _ _ _ _ cont) = go cont  -- v0.9.0: paths determined by continuation

-- | v0.9.0: Collect all call-pre obligations from a BodyVC tree.
-- Returns (calleeName, preconditionPred, pathGuard) for each CallVC
-- that has a non-Nothing precondition obligation.
-- Path guards are accumulated through BranchVC nodes.
-- F-NIW-4: each obligation carries its path's prior-call context — the result var,
-- sort, and assumed post of every CallVC on the path before it. A later call whose
-- precondition references an earlier call's result (e.g. withdraw-twice's
-- `(withdraw after-first second)`) is then provable under the earlier call's
-- assumed post (assume-guarantee; the trust meet over those callees is taken
-- downstream by TrustReport over the syntactic call graph). Without this context
-- the result var is a free variable in the param-scoped call-pre constraint.
-- | COMP-4 (b) intro-side: every (callee, translated-args) call site in the VC
-- tree, for emitting per-call payload-subtyping obligations. Path-independent
-- (the subtyping is a static fact about the arg/param types, not a runtime
-- obligation), so guards/context are not collected.
collectCallSites :: BodyVC -> [(Name, [FQPred])]
collectCallSites (SimpleVC _ _)               = []
collectCallSites (BranchVC _ _ t e)           = collectCallSites t ++ collectCallSites e
collectCallSites (CallVC c args _ _ _ _ cont) = (c, args) : collectCallSites cont

collectCallPreObligations :: BodyVC -> [(Name, FQPred, FQPred, [(Text, FQSort, FQPred)], [LetBinding])]
collectCallPreObligations = go FQTrue []
  where
    go _guard _calls (SimpleVC _ _) = []
    go guard calls (BranchVC g _ thenVC elseVC) =
      go (conjoin guard g) calls thenVC ++ go (conjoin guard (FQNot g)) calls elseVC
    go guard calls (CallVC callee _args mPre mPost rVar rSort cont) =
      let preObligs = case mPre of
            -- F-NIW-4b: attach the path's let-bindings (which prependLB has pushed
            -- into the leaf of `cont`) so a precondition referencing a let-bound
            -- non-call value (e.g. `(g y)` where `y = x+1`) can be proved under
            -- that value's defining equality. The emission filters them to the
            -- subset in scope at the call.
            Just prePred -> [(callee, prePred, guard, calls, subtreeLbs cont)]
            Nothing      -> []
          -- subsequent obligations may assume this call's post over its result var
          calls' = calls ++ [(rVar, rSort, fromMaybe FQTrue mPost)]
          contObligs = go guard calls' cont
      in preObligs ++ contObligs

-- | REC-DESCENT (v0.14.25): like 'collectCallPreObligations', but yields the
-- callee's translated ARGUMENTS (not its precondition) for EVERY 'CallVC' node,
-- so the descent emitter can substitute them into the callee's measure. Same
-- path-guard / prior-call-context threading as the call-pre walk.
collectDescentSites :: BodyVC -> [(Name, [FQPred], FQPred, [(Text, FQSort, FQPred)], [LetBinding])]
collectDescentSites = go FQTrue []
  where
    go _guard _calls (SimpleVC _ _) = []
    go guard calls (BranchVC g _ thenVC elseVC) =
      go (conjoin guard g) calls thenVC ++ go (conjoin guard (FQNot g)) calls elseVC
    go guard calls (CallVC callee args _mPre mPost rVar rSort cont) =
      let here    = [(callee, args, guard, calls, subtreeLbs cont)]
          calls'  = calls ++ [(rVar, rSort, fromMaybe FQTrue mPost)]
      in here ++ go guard calls' cont

-- | F-NIW-4b: all let-bindings reachable in a BodyVC. `prependLB` parks
-- let-bindings at the leaf SimpleVC of a CallVC continuation, so a call-pre
-- obligation's path lbs are gathered from its continuation subtree.
subtreeLbs :: BodyVC -> [LetBinding]
subtreeLbs (SimpleVC lbs _)          = lbs
subtreeLbs (BranchVC _ _ t e)        = subtreeLbs t ++ subtreeLbs e
subtreeLbs (CallVC _ _ _ _ _ _ cont) = subtreeLbs cont

-- | COMP-3b-general: every match-introduced binder (synthetic guard + arm
-- payloads) carried in a 'BranchVC' binder field across the whole VC tree, so the
-- driver can declare them all at trivial refinement FQTrue. This is the SOLE
-- emitter of these binders — it generalizes the former single-shot
-- @extraResultBinds@ from one top-level match to arbitrarily-nested matches.
-- Soundness (professor confirm gate, Q1): each binder is 'freshName'-unique
-- (globally distinct, well-formed flat context) and a payload symbol only occurs
-- in its own arm's path predicates, so a flat FQTrue declaration is vacuous on any
-- constraint where it does not occur — the validity-preserving weakening lemma.
collectBranchBinders :: BodyVC -> [(Name, FQSort, FQPred)]
collectBranchBinders (SimpleVC _ _)            = []
collectBranchBinders (BranchVC _ bs t e)       = bs ++ collectBranchBinders t ++ collectBranchBinders e
collectBranchBinders (CallVC _ _ _ _ _ _ cont) = collectBranchBinders cont

-- | F-NIW-4b: the subset of candidate let-bindings whose RHS free variables are
-- all already in scope (params ∪ prior-call results ∪ already-included lbs),
-- to a fixpoint and in dependency order. Out-of-scope lbs (e.g. branch-local, or
-- bound after the call) are excluded — admitting them would re-introduce free
-- variables. Sound: an lb is a let-definition equality, a tautology in context.
inScopeLbs :: Set.Set Text -> [LetBinding] -> [LetBinding]
inScopeLbs scope lbs0 =
  let (ok, rest) = partition (\lb -> all (`Set.member` scope) (predVars (lbRhs lb))) lbs0
  in if null ok
       then []
       else ok ++ inScopeLbs (foldr (Set.insert . lbName) scope ok) rest

-- ---------------------------------------------------------------------------
-- Predicate helpers (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Conjoin two predicates, simplifying FQTrue identity.
conjoin :: FQPred -> FQPred -> FQPred
conjoin FQTrue q     = q
conjoin p      FQTrue = p
conjoin p      q      = FQAnd [p, q]

-- | Conjoin a list of predicates.
conjoinAll :: [FQPred] -> FQPred
conjoinAll = foldr conjoin FQTrue

-- | Lexicographic strict-less predicate: gs <_lex fs (callee tuple strictly below
-- caller tuple). REC-DESCENT lexicographic (k>1). k=1 collapses to a bare '<' so a
-- k=1 descent '.fq' is byte-identical to the pre-lexicographic encoding; k>1 is the
-- QF-LIA disjunction ⋁ᵢ (g₀=f₀ ∧ … ∧ g_{i-1}=f_{i-1} ∧ gᵢ<fᵢ), each atom linear.
-- Precondition: length gs == length fs (the caller enforces the equal-length gate;
-- a lexicographic order over differing arities is undefined — professor ruling (b)).
lexLess :: [FQPred] -> [FQPred] -> FQPred
lexLess [g] [f] = FQBinPred FQLt g f
lexLess gs  fs  = FQOr [ mkTerm i | i <- [0 .. length gs - 1] ]
  where
    mkTerm i = let eqs = [ FQBinPred FQEq (gs !! j) (fs !! j) | j <- [0 .. i - 1] ]
                   lt  = FQBinPred FQLt (gs !! i) (fs !! i)
               in if null eqs then lt else FQAnd (eqs ++ [lt])

-- ---------------------------------------------------------------------------
-- NIW (v0.12): measure-class emission helpers (REF-META-2 §4 / REF-META-3 §4.2)
-- ---------------------------------------------------------------------------

-- | Variables appearing as the argument of a measure application
-- (string-length / list-length) anywhere in an expression. Drives which non-int
-- params need an opaque carrier binder, preserving byte-identical .fq output for
-- measure-free functions.
-- | STRLIT (Stage 1): variables appearing as a direct operand of an @=@/@!=@
-- comparison. After the 'exprToPred' @LitString@ flip, a string param compared
-- against a string literal reflects (@s = strlit_…@), so it must be an in-scope
-- @FQStr@ carrier binder or the solver rejects a free var. Collected into
-- 'measureVars'; the 'measureParams' 'isMeasureSort' gate then binds only the
-- string/list ones (int operands are already bound via 'intParams'; list operands
-- get a harmless unused carrier).
-- | A2.2-string (residue lift): vars in map-put VALUE position. A string param
-- used as a put value ((map-put m k s)) needs an FQStr carrier binder (via
-- 'measureVars', filtered by 'isMeasureSort' — an int var collected here is
-- filtered out and harmless) AND a body-channel SortEnv entry so 'strValTerm'
-- resolves it. Type-blind, like 'strEqOperandVars'.
-- | A2.2-string (keys): vars in map-op KEY position (get/has/put). A string
-- param used as a key needs the FQStr carrier binder + body-SortEnv entry,
-- exactly like a put value ('mapPutValVars'); int vars collected here are
-- filtered out downstream (isMeasureSort / isStrLike gates).
mapKeyVars :: Expr -> Set.Set Name
mapKeyVars e = case e of
  EApp "map-put" [mE, kE, vE] -> Set.unions [kVar kE, mapKeyVars mE, mapKeyVars kE, mapKeyVars vE]
  EApp "map-get" [mE, kE]     -> Set.unions [kVar kE, mapKeyVars mE, mapKeyVars kE]
  EApp "map-has" [mE, kE]     -> Set.unions [kVar kE, mapKeyVars mE, mapKeyVars kE]
  EApp _ args   -> Set.unions (map mapKeyVars args)
  EOp op args   -> mapKeyVars (EApp op args)
  EIf a b c     -> Set.unions (map mapKeyVars [a, b, c])
  ELet bs body  -> Set.unions (mapKeyVars body : [mapKeyVars r | (_, _, r) <- bs])
  EMatch s arms -> Set.unions (mapKeyVars s : map (mapKeyVars . snd) arms)
  EPair a b     -> Set.union (mapKeyVars a) (mapKeyVars b)
  _             -> Set.empty
  where
    kVar (EVar v) = Set.singleton v
    kVar _        = Set.empty

mapPutValVars :: Expr -> Set.Set Name
mapPutValVars e = case e of
  EApp "map-put" [mE, kE, vE] ->
    Set.unions [valVar vE, mapPutValVars mE, mapPutValVars kE, mapPutValVars vE]
  EApp _ args   -> Set.unions (map mapPutValVars args)
  EOp op args   -> mapPutValVars (EApp op args)
  EIf a b c     -> Set.unions (map mapPutValVars [a, b, c])
  ELet bs body  -> Set.unions (mapPutValVars body : [mapPutValVars r | (_, _, r) <- bs])
  EMatch s arms -> Set.unions (mapPutValVars s : map (mapPutValVars . snd) arms)
  EPair a b     -> Set.union (mapPutValVars a) (mapPutValVars b)
  _             -> Set.empty
  where
    valVar (EVar v) = Set.singleton v
    valVar _        = Set.empty

strEqOperandVars :: Expr -> Set.Set Name
strEqOperandVars e = case e of
  EApp op [l, r] | op `elem` (["=", "==", "/=", "!=", "≠"] :: [Text]) ->
    Set.unions [operandVar l, operandVar r, strEqOperandVars l, strEqOperandVars r]
  EApp _ args   -> Set.unions (map strEqOperandVars args)
  EOp op args   -> strEqOperandVars (EApp op args)
  EIf a b c     -> Set.unions (map strEqOperandVars [a, b, c])
  ELet bs body  -> Set.unions (strEqOperandVars body : [strEqOperandVars r | (_, _, r) <- bs])
  EMatch s arms -> Set.unions (strEqOperandVars s : map (strEqOperandVars . snd) arms)
  EPair a b     -> Set.union (strEqOperandVars a) (strEqOperandVars b)
  ELambda _ b   -> strEqOperandVars b
  EAwait a      -> strEqOperandVars a
  EDo steps     -> Set.unions [strEqOperandVars x | DoStep _ x <- steps]
  _             -> Set.empty
  where
    operandVar (EVar v) = Set.singleton v
    operandVar _        = Set.empty

measureArgVars :: Expr -> Set.Set Name
measureArgVars e = case e of
  EApp "string-length" [EVar v] -> Set.singleton v
  EApp "list-length"   [EVar v] -> Set.singleton v
  EApp _ args   -> Set.unions (map measureArgVars args)
  EOp _ args    -> Set.unions (map measureArgVars args)
  EIf a b c     -> Set.unions (map measureArgVars [a, b, c])
  ELet bs body  -> Set.unions (measureArgVars body : [measureArgVars r | (_, _, r) <- bs])
  EMatch s arms -> Set.unions (measureArgVars s : map (measureArgVars . snd) arms)
  EPair a b     -> Set.union (measureArgVars a) (measureArgVars b)
  ELambda _ b   -> measureArgVars b
  EAwait a      -> measureArgVars a
  EDo steps     -> Set.unions [measureArgVars x | DoStep _ x <- steps]
  _             -> Set.empty

-- | True when a type resolves (through aliases / refinements) to a measure
-- carrier sort (string or list).
isMeasureSort :: AliasMap -> Type -> Bool
isMeasureSort _  TString            = True
isMeasureSort _  (TList _)          = True
isMeasureSort am (TDependent _ b _) = isMeasureSort am b
isMeasureSort am (TCustom n)        = maybe False (isMeasureSort am) (Map.lookup n am)
isMeasureSort _  _                  = False

-- | REF-META-2 §4 emission side-condition: for every measure-term m(t) in a
-- constraint, conjoin the ground range fact (m t) >= 0 into the LHS as a
-- hypothesis — the local-theory-extension instantiation, ground facts per
-- occurring term (never a quantified axiom). Byte-inert when no FQApp is present.
injectRangeFacts :: FQConstraint -> FQConstraint
injectRangeFacts c =
  let apps  = nub (collectApps (reftPred (conLhs c)) ++ collectApps (reftPred (conRhs c)))
      facts = concatMap factsFor apps
      -- LEVER-A1/A2 fact synthesis per head symbol. Array-VALUED terms
      -- (Map_store / Map_default) get NO facts — `(Map_store …) >= 0` is
      -- ill-sorted over the array sort. A2 resolves the A1 landmine: a
      -- Map_select term carries the byte-range family-2 facts `0 ≤ t ≤ 255`
      -- ONLY when its array argument is BYTES-ROOTED — a map component read
      -- (roots named *$has / *$val, or a Map_default chain, which only map
      -- composites produce in select position) is an unconstrained int and
      -- must get NO range fact (a phantom 0..255 on a map value would be an
      -- unsound assumption). Missing a fact only loses completeness; adding a
      -- wrong one breaks refutation exactness (§6.1) — the discriminator errs
      -- toward no-facts. Every other FQApp keeps the pre-existing `t >= 0`
      -- measure fact exactly as before (byte-identical for the existing
      -- corpus).
      factsFor a@(FQApp f args)
        -- STRLIT: an interned string-literal constant is a NULLARY Str constant,
        -- not an int measure — `strlit_… >= 0` is ill-sorted (Str vs int) and
        -- crashes liquid-fixpoint. Exclude it (the range-fact catch-all below
        -- assumes an int-sorted measure application). Surfaces once a string
        -- literal meets `string-length` or a string-valued map value.
        | "strlit_" `T.isPrefixOf` f = []
        | f `elem` ["Map_store", "Map_default"] = []
        | f == "Map_select" = case args of
            (arr : _) | bytesRootedArr arr ->
              [ FQBinPred FQGe a (FQLit 0), FQBinPred FQLe a (FQLit 255) ]
            _ -> []
      factsFor a = [ FQBinPred FQGe a (FQLit 0) ]
      bytesRootedArr (FQVar n) = not ("$has" `T.isSuffixOf` n || "$val" `T.isSuffixOf` n)
      bytesRootedArr (FQApp "Map_store" (arr : _)) = bytesRootedArr arr
      bytesRootedArr _ = False
  in if null facts
       then c
       else c { conLhs = (conLhs c) { reftPred = foldr conjoin (reftPred (conLhs c)) facts } }

-- | LEVER-A2.2: conjoin the ground value-range fact @0 ≤ v ≤ 1@ for each
-- occurring bool-map VALUE read — a @Map_select@ whose array roots (through any
-- @Map_store@ chain) in a bool-valued map's @$val@ array (the @boolValArrs@ set,
-- scoped per function). This is the byte-range family-2 discipline
-- ('injectRangeFacts') at the value sort: it supplies the @value ∈ {0,1}@
-- invariant the ℤ-encoding lacks, making the encoding exact on occurring keys
-- and closing the disequality-in-hypothesis spurious refute (professor review,
-- 2026-07-13). The fact pins the read RESULT, not a key, so it is sound under
-- key aliasing. Byte-inert when @boolValArrs@ is empty (off-gate / int-valued
-- maps) or no such select occurs — collected from both lhs and rhs so a value
-- read occurring only in the goal (post) still lands its fact in the lhs.
injectBoolValRangeFacts :: Set.Set Text -> FQConstraint -> FQConstraint
injectBoolValRangeFacts bva c
  | Set.null bva = c
  | otherwise =
      let apps  = nub (collectApps (reftPred (conLhs c)) ++ collectApps (reftPred (conRhs c)))
          facts = concatMap factsFor apps
          factsFor a@(FQApp "Map_select" (arr : _))
            | boolValRooted arr = [ FQBinPred FQGe a (FQLit 0), FQBinPred FQLe a (FQLit 1) ]
          factsFor _ = []
          boolValRooted (FQVar n)                     = n `Set.member` bva
          boolValRooted (FQApp "Map_store" (arr : _)) = boolValRooted arr
          boolValRooted _                             = False
      in if null facts
           then c
           else c { conLhs = (conLhs c) { reftPred = foldr conjoin (reftPred (conLhs c)) facts } }

-- | STRLIT (Stage 1): conjoin ground pairwise-distinctness @c_i /= c_j@ for every
-- unordered pair of DISTINCT occurring string-literal constants (nullary
-- @FQApp "strlit_…" []@), collected from LHS ∪ RHS. Mirrors 'injectRangeFacts''s
-- per-occurrence ground discipline and is the MANDATORY companion to the
-- 'exprToPred' @LitString@ flip: without it, a model identifying two literals
-- spuriously refutes a valid post (§6.1 F2). Literal/variable and literal/term
-- pairs get no fact by construction — only @strlit_@ constants are paired.
-- Byte-inert when fewer than two distinct literals occur (deterministic order via
-- 'Set.toAscList'), so string-literal-free @.fq@ is byte-identical.
injectStrLitDistinct :: FQConstraint -> FQConstraint
injectStrLitDistinct c =
  let apps  = collectApps (reftPred (conLhs c)) ++ collectApps (reftPred (conRhs c))
      names = Set.toAscList (Set.fromList
                [ n | FQApp n [] <- apps, "strlit_" `T.isPrefixOf` n ])
      facts = [ FQBinPred FQNeq (FQApp a []) (FQApp b [])
              | (a, rest) <- pairsTail names, b <- rest ]
  in if null facts
       then c
       else c { conLhs = (conLhs c) { reftPred = foldr conjoin (reftPred (conLhs c)) facts } }
  where
    pairsTail []     = []
    pairsTail (x:xs) = (x, xs) : pairsTail xs

-- | STRLIT (Stage 2): pin the CODE-POINT length of every occurring string-literal
-- constant — conjoin the ground fact @strLen(strlit_s) = |s|@, one per DISTINCT
-- literal, collected from LHS ∪ RHS. Composes with the @string-length@ → @strLen@
-- reflection ('exprToPred') so length-consistency reasoning discharges: under
-- @pre (= s "GET")@, the goal @(= (string-length s) 5)@ REFUTES because congruence
-- gives @strLen s = strLen strlit_GET = 3 /= 5@, and the twin @… 3@ VERIFIES. |s|
-- is recovered exactly from the interned name ('strlitLen'), so it is the runtime
-- code-point count. SOUND: each fact is a true, mutually-consistent ground
-- equation (@strLen@ is uninterpreted; 'strlitConst' injectivity gives each
-- constant exactly one length), so it only strengthens the hypothesis — it can
-- close a spurious refute, never open one, and never contradicts (no vacuous SAFE).
-- The extra @strLen@ application makes the sweep declare @strLen : (Str) -> int@
-- (measureConstant default) even when the program has no @string-length@ call.
-- Byte-inert without string literals; mirrors 'injectStrLitDistinct''s occurring-set
-- discipline. Idempotent w.r.t. 'injectStrLitDistinct' order: neither introduces a
-- new @strlit_@ name the other must pair.
injectStrLitLen :: FQConstraint -> FQConstraint
injectStrLitLen c =
  let apps  = collectApps (reftPred (conLhs c)) ++ collectApps (reftPred (conRhs c))
      names = Set.toAscList (Set.fromList
                [ n | FQApp n [] <- apps, "strlit_" `T.isPrefixOf` n ])
      facts = [ FQBinPred FQEq (FQApp "strLen" [FQApp n []]) (FQLit (strlitLen n))
              | n <- names ]
  in if null facts
       then c
       else c { conLhs = (conLhs c) { reftPred = foldr conjoin (reftPred (conLhs c)) facts } }

-- | Measure-application subterms of a predicate.
collectApps :: FQPred -> [FQPred]
collectApps p = case p of
  FQApp _ args     -> p : concatMap collectApps args
  FQBinPred _ l r  -> collectApps l ++ collectApps r
  FQBinArith _ l r -> collectApps l ++ collectApps r
  FQAnd ps         -> concatMap collectApps ps
  FQOr  ps         -> concatMap collectApps ps
  FQNot q          -> collectApps q
  FQKVar _ args    -> concatMap collectApps args
  _                -> []

-- | Head symbol names of the measure applications in a predicate.
appNames :: FQPred -> Set.Set Text
appNames p = case p of
  FQApp f args     -> Set.insert f (Set.unions (map appNames args))
  FQBinPred _ l r  -> Set.union (appNames l) (appNames r)
  FQBinArith _ l r -> Set.union (appNames l) (appNames r)
  FQAnd ps         -> Set.unions (map appNames ps)
  FQOr  ps         -> Set.unions (map appNames ps)
  FQNot q          -> appNames q
  FQKVar _ args    -> Set.unions (map appNames args)
  _                -> Set.empty

-- | UF constant declaration for a measure symbol.
measureConstant :: Text -> FQConstant
measureConstant "listLen"  = FQConstant "listLen"  [FQList] FQInt
-- LEVER-A1: the family-1 length UF over the byte-array sort (grounded per
-- binder by the `bytesLen(v) = n` binder fact; declared only when used).
measureConstant "bytesLen" = FQConstant "bytesLen" [FQArr FQInt FQInt] FQInt
measureConstant n          = FQConstant n          [FQStr]  FQInt  -- strLen + default

-- | F-NIW-1: collect every refinement predicate along a (possibly aliased) type's
-- chain, with its binding variable. Stacked aliases (e.g. NonEmptyWord over Word,
-- §3.4.4 conjunction-at-introduction) contribute all their predicates; each is
-- α-identified to the single param witness by the caller (REF-META-3 review F3).
resolveAllRefinements :: AliasMap -> Type -> [(Name, Expr)]
resolveAllRefinements am t = case t of
  TDependent x base p -> (x, p) : resolveAllRefinements am base
  TCustom n           -> maybe [] (resolveAllRefinements am) (Map.lookup n am)
  _                   -> []

-- | COMP-4 (b): a payload type's declared refinement as (bindingVar, pred),
-- or Nothing for a base/unrefined payload. Conjoins multiply-refined aliases,
-- renamed to a common binding var. Reuses resolveAllRefinements, which already
-- descends a refinement-aliased payload type (PositiveInt → n>0); the Result/
-- TSumType wrapper is peeled by the caller (the driver works per payload arm).
payloadRefinement :: AliasMap -> Type -> Maybe (Name, Expr)
payloadRefinement am t = case resolveAllRefinements am t of
  []             -> Nothing
  ps@((x0, _):_) -> Just (x0, foldr1 (\a b -> EApp "and" [a, b]) [ renameVar x x0 p | (x, p) <- ps ])

-- | COMP-4 (b): the per-arm payload TYPES of a two-arm sum type, each tagged
-- with the "$<arm>" key suffix the driver/refEnv key by. Result → $ok/$err; a
-- two-arm user ADT → $<Ctor>. Empty for a non-sum type. Mirrors the driver's
-- resultKeys/adtKeys arm scheme so the intro-side keys align with the elim-side.
payloadArms :: AliasMap -> Type -> [(Text, Type)]
payloadArms am t = case resolveAliasTy am t of
  TResult okT errT                        -> [("$ok", okT), ("$err", errT)]
  TSumType [(c1, Just t1), (c2, Just t2)] -> [("$" <> c1, t1), ("$" <> c2, t2)]
  _                                       -> []

-- | Rename a free variable in an expression (the refinement binding var → the
-- param name). Refinement predicates are first-order and closed over the single
-- binding var (REF-META-3 W-FirstOrder / W-Closed), so naive capture-free
-- substitution is sound — no inner binder shadows the binding var.
renameVar :: Name -> Name -> Expr -> Expr
renameVar from to = go
  where
    go (EVar v)        = EVar (if v == from then to else v)
    go (EApp f as)     = EApp f (map go as)
    go (EOp o as)      = EOp o (map go as)
    go (EIf a b c)     = EIf (go a) (go b) (go c)
    go (ELet bs bd)    = ELet [(bn, bt, go r) | (bn, bt, r) <- bs] (go bd)
    go (EMatch s arms) = EMatch (go s) [(pat, go bdy) | (pat, bdy) <- arms]
    go (EPair a b)     = EPair (go a) (go b)
    go (ELambda ps bd) = ELambda ps (go bd)
    go (EAwait a)      = EAwait (go a)
    go e               = e

-- | FACT-AG-LEN (Stage 1): the length equality a @bytes[n]@ param contributes to
-- its function's effective PRECONDITION, instantiated at the param name.
--
-- Before this, the fact @bytesLen(v) = n@ was asserted unconditionally as the
-- param BINDER's refinement ('bytesLenReft', 'emitParamBind'), so it entered
-- every VC antecedent with no obligation discharging it — the SAFE-ARG class
-- (docs/design/fact-ag-proposal.md; docs/design/finding-arg-position-false-safe.md).
-- Routing it through the pre makes it EARNED: §5.3.4's call rule proves it at
-- each call site (PROVE polarity, via the augmented 'ContractEnv' that
-- 'buildContractEnvWith' already builds) and assumes it inside the callee.
--
-- Deliberately NOT folded into 'resolveAllRefinements', which has four other
-- consumers that must not see it: 'returnRefinementPost' (that is Stage 3, and
-- the stage ordering is a correctness constraint — Stage 3 without Stage 2
-- refutes every @bytes-zero@ body), 'payloadRefinement' (COMPONENT positions,
-- a deliberate exclusion), "LLMLL.Feasibility" (a separate SMT lowering for the
-- no-miracle gate), and 'collectCallArgCarrierVars' (measure-carrier binding).
--
-- Alias-chasing for free: 'bytesLenOf' resolves through 'resolveAliasTy', so
-- @(type Key bytes[32])@ elaborates identically to @bytes[32]@ (the A1 property
-- at the head position).
bytesLenParamPre :: AliasMap -> (Name, Type) -> [Expr]
bytesLenParamPre am (n, t) = case bytesLenOf am t of
  Just len -> [ EApp "=" [ EApp "bytes-length" [EVar n]
                         , ELit (LitInt (toInteger len)) ] ]
  Nothing  -> []

-- | F-NIW-1: the conjoined refinement predicate contributed by refinement-aliased
-- params, each instantiated at the param name (p[param/x]). Nothing if no param
-- is refinement-typed. This becomes part of the function's effective precondition,
-- so the existing pre machinery discharges it both ways: assumed in the body VC
-- (elim) and proven at call sites via call-pre obligations (intro).
--
-- FACT-AG-LEN (Stage 1): @bytes[n]@ params contribute their length equality here
-- too ('bytesLenParamPre'). Emitting @bytes-length@ into the pre also
-- SELF-ACTIVATES the LEVER-A1 gate, because 'arrGateActive' reads the AUGMENTED
-- contract and @"bytes-length"@ is in 'bytesOpNames' — so the param binds at
-- 'byteArraySort' and the predicate is well-sorted, with no change to
-- 'typeToSort' or to the gate.
paramRefinementPre :: AliasMap -> [(Name, Type)] -> Maybe Expr
paramRefinementPre am params =
  case [ renameVar x n p | (n, t) <- params, (x, p) <- resolveAllRefinements am t ]
       ++ concatMap (bytesLenParamPre am) params of
    []    -> Nothing
    preds -> Just (foldr1 (\a b -> EApp "and" [a, b]) preds)

-- | Fold param refinements into a contract's precondition.
augmentContractPre :: AliasMap -> [(Name, Type)] -> Contract -> Contract
augmentContractPre am params c =
  case paramRefinementPre am params of
    Nothing   -> c
    Just rpre -> c { contractPre = Just (andPre (contractPre c) rpre) }
  where
    andPre Nothing  r = r
    andPre (Just p) r = EApp "and" [p, r]

-- | DEF-RET Unit 2: the conjoined refinement predicate contributed by a
-- refinement-aliased RETURN type, instantiated at @result@ (p[result/x]).
-- Nothing if the return is unannotated or base-typed. The guarantee-side dual
-- of 'paramRefinementPre': folded into the function's effective POSTcondition,
-- so the existing post machinery discharges it both ways — proven in the body
-- VC (introduction, §3.4.1) and assumed at call sites via assume-guarantee
-- (elimination). Folds UNCONDITIONALLY (syntactic, pre-verdict, like a hand-
-- written @post@ clause); verdict-gating (asserted floor / refuted exclusion)
-- is the existing trust-closure machinery, not this fold.
returnRefinementPost :: AliasMap -> Maybe Type -> Maybe Expr
returnRefinementPost am mRet = case mRet of
  Nothing -> Nothing
  Just t  -> case [ renameVar x "result" p | (x, p) <- resolveAllRefinements am t ] of
               []    -> Nothing
               preds -> Just (foldr1 (\a b -> EApp "and" [a, b]) preds)

-- | Fold the return refinement into a contract's postcondition (DEF-RET Unit 2).
augmentContractPost :: AliasMap -> Maybe Type -> Contract -> Contract
augmentContractPost am mRet c =
  case returnRefinementPost am mRet of
    Nothing    -> c
    Just rpost -> c { contractPost = Just (andPost (contractPost c) rpost) }
  where
    andPost Nothing  r = r
    andPost (Just p) r = EApp "and" [p, r]

-- | F-NIW-2: bare-variable arguments passed to a measure-refined callee param,
-- anywhere in an expression. These caller vars need carrier binders so the
-- intro-side call-pre obligation (the callee's refinement, substituted) refers
-- to an in-scope symbol. Gated on the callee param being refinement-typed AND
-- carrier-sorted, so measure-free callees contribute nothing (byte-identity).
collectCallArgCarrierVars :: AliasMap -> ContractEnv -> Expr -> Set.Set Name
collectCallArgCarrierVars am cenv = go
  where
    go e = case e of
      EApp f args ->
        let here = case Map.lookup f cenv of
              Just (ps, _, _) ->
                Set.fromList
                  [ v
                  | (EVar v, (_, t)) <- zip args ps
                  , not (null (resolveAllRefinements am t))
                  , isMeasureSort am t ]
              Nothing -> Set.empty
        in Set.union here (Set.unions (map go args))
      EOp _ args    -> Set.unions (map go args)
      EIf a b c     -> Set.unions (map go [a, b, c])
      ELet bs body  -> Set.unions (go body : [go r | (_, _, r) <- bs])
      EMatch s arms -> Set.unions (go s : map (go . snd) arms)
      EPair a b     -> Set.union (go a) (go b)
      ELambda _ b   -> go b
      EAwait a      -> go a
      EDo steps     -> Set.unions [go x | DoStep _ x <- steps]
      _             -> Set.empty

-- | Prepend a let-binding to a BodyVC.
prependLB :: LetBinding -> BodyVC -> BodyVC
prependLB lb (SimpleVC lbs r) = SimpleVC (lb : lbs) r
prependLB lb (BranchVC g bs t e) = BranchVC g bs (prependLB lb t) (prependLB lb e)
prependLB lb (CallVC cal args mPre mPost rVar rSort cont) =
  CallVC cal args mPre mPost rVar rSort (prependLB lb cont)  -- v0.9.0

prependLBs :: [LetBinding] -> BodyVC -> BodyVC
prependLBs lbs bvc = foldr prependLB bvc lbs

-- | v0.9.0 COMP-3: Classify match arms as Result (Success/Error) pattern.
-- Returns Just (successVar, successBody, errorVar, errorBody) if the arms
-- are exactly two with Success and Error constructors (in either order).
-- Returns Nothing for non-Result patterns.
classifyResultArms :: [(Pattern, Expr)] -> Maybe (Name, Expr, Name, Expr)
classifyResultArms arms = case arms of
  [(PConstructor "Success" [PVar s], bodyS), (PConstructor "Error" [PVar e], bodyE)] ->
    Just (s, bodyS, e, bodyE)
  [(PConstructor "Error" [PVar e], bodyE), (PConstructor "Success" [PVar s], bodyS)] ->
    Just (s, bodyS, e, bodyE)
  _ -> Nothing

-- | MATCH-WIDEN-2: classify an n-arm (≥2) match on a user sum type. Returns the
-- list of single-payload-or-nullary constructor arms (in source order, distinct
-- constructors) plus an OPTIONAL wildcard/PVar tail body (the terminal else). A
-- wildcard, if present, must be the LAST arm (first-match order). Any arm that is
-- not a nullary/single-payload constructor or a final wildcard → 'Nothing' (the
-- whole match falls back). n-ary generalization of 'classifyTwoArmAdtArms';
-- exhaustiveness is guaranteed upstream by 'TypeCheck.checkExhaustive', so the
-- verifier need not re-check coverage.
classifyNArmAdtArms :: [(Pattern, Expr)] -> Maybe ([(Name, Maybe Name, Expr)], Maybe Expr)
classifyNArmAdtArms arms0 = go arms0 []
  where
    go [] acc
      | null acc  = Nothing
      | otherwise = Just (reverse acc, Nothing)
    -- a final wildcard / PVar arm becomes the terminal else; must be last
    go [(PWildcard, b)] acc
      | not (null acc) = Just (reverse acc, Just b)
    go [(PVar _, b)] acc
      | not (null acc) = Just (reverse acc, Just b)
    go ((PConstructor c [PVar v], b) : rest) acc
      | c `notElem` map (\(cc, _, _) -> cc) acc = go rest ((c, Just v, b) : acc)
    go ((PConstructor c [], b) : rest) acc
      | c `notElem` map (\(cc, _, _) -> cc) acc = go rest ((c, Nothing, b) : acc)
    go _ _ = Nothing

-- | v0.9.0 COMP-3: Replace the continuation of a CallVC.
-- Used for EMatch-over-call: the match's BranchVC becomes the call's continuation.
setCallVCContinuation :: BodyVC -> BodyVC -> BodyVC
setCallVCContinuation (CallVC cal args mPre mPost rVar rSort _cont) newCont =
  CallVC cal args mPre mPost rVar rSort newCont
setCallVCContinuation bvc _newCont = bvc  -- no-op for non-CallVC (shouldn't happen)

-- | Infer the FQSort of a predicate result.
-- In BODY-VC-0, we only support int-typed results.
predSortOf :: FQPred -> FQSort
predSortOf (FQLit _)         = FQInt
predSortOf (FQVar _)         = FQInt  -- in BODY-VC-0, all vars in SortEnv are FQInt
predSortOf (FQBinArith _ _ _) = FQInt
predSortOf (FQBinPred _ _ _) = FQBool  -- comparisons return bool
predSortOf FQTrue            = FQBool
predSortOf FQFalse           = FQBool
predSortOf (FQNot _)         = FQBool
predSortOf (FQAnd _)         = FQBool
predSortOf (FQOr _)          = FQBool
predSortOf (FQKVar _ _)      = FQInt  -- fallback
predSortOf (FQApp _ _)       = FQInt  -- NIW: measures are integer-valued

-- | Build a SortEnv from function parameters (int-typed only for BODY-VC-0).
-- v0.8.0: uses isIntLike with alias map to resolve type aliases.
buildSortEnv :: AliasMap -> [(Name, Type)] -> SortEnv
buildSortEnv aliases params = Map.fromList
  [ (n, typeToSort t) | (n, t) <- params, isScalarLike aliases t ]

-- ---------------------------------------------------------------------------
-- Operator lookup tables (v0.8.0, v0.10: moved to GuardClassifier.hs)
-- ---------------------------------------------------------------------------
-- lookupArithOp and lookupPredOp are now imported from LLMLL.GuardClassifier.
-- Internal uses in this module (exprToPred, bodyToPredM) go through the import.

-- ---------------------------------------------------------------------------
-- Compositional verification helpers (v0.9.0 COMP-1)
-- ---------------------------------------------------------------------------

-- | Capture-free predicate substitution.
-- Replaces free variables in a FQPred according to the substitution map.
-- Variables not in the map are left unchanged.
applySubst :: Map Name FQPred -> FQPred -> FQPred
applySubst subst (FQVar v) = Map.findWithDefault (FQVar v) v subst
applySubst subst (FQBinPred op l r) = FQBinPred op (applySubst subst l) (applySubst subst r)
applySubst subst (FQBinArith op l r) = FQBinArith op (applySubst subst l) (applySubst subst r)
applySubst subst (FQAnd ps) = FQAnd (map (applySubst subst) ps)
applySubst subst (FQOr ps) = FQOr (map (applySubst subst) ps)
applySubst subst (FQNot p) = FQNot (applySubst subst p)
applySubst subst (FQApp f args) = FQApp f (map (applySubst subst) args)  -- NIW: substitute measure args
applySubst _ p = p  -- FQLit, FQTrue, FQFalse unchanged

-- | Does the postcondition use constructor-dependent reasoning?
-- If the postcondition contains EMatch on "result", the EMatch encoding
-- cannot safely assume the same postcondition on both branches.
-- Full constructor-decomposed postconditions are deferred (COMP-0 §13).
-- Added to TCB (COMP-0 Rev 2, Issue 2).
isConstructorDependent :: Expr -> Bool
isConstructorDependent (EMatch (EVar "result") _) = True
isConstructorDependent (EMatch _ _)                = False
isConstructorDependent (EApp _ args) = any isConstructorDependent args
isConstructorDependent (ELet _ body) = isConstructorDependent body
isConstructorDependent (EIf _ t e)   = isConstructorDependent t || isConstructorDependent e
isConstructorDependent _             = False
