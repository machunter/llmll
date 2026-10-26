{-# LANGUAGE StrictData #-}
{-# LANGUAGE PatternSynonyms #-}
-- |
-- Module      : LLMLL.Syntax
-- Description : Core AST and type definitions for the LLMLL language.
--
-- This is the foundational module. Every other compiler phase depends on it.
-- Defines the abstract syntax tree, the type system representation,
-- hole kinds, statements, capabilities, and the Command/Response IO model.
--
-- v0.2 additions: SOpen, SExport (module namespace control);
-- ModulePath, ModuleEnv, ModuleCache (multi-file compilation).
module LLMLL.Syntax
  ( -- * Names and Source Locations
    Name
  , Span(..)
  , Located(..)

    -- * Types
  , Type(..)
  , TyConstraint(..)
  , entails
  , tyConstraintLabel
  , parseTyConstraint
  , bindTypeParams
  , typeParamsNotSupportedMessage
  , unknownTypeVarMessage
  , bytesLengthInRange
  , bytesLengthRangeMessage
  , typeLabel
  , typeConstructorName

    -- * Expressions
  , Expr(..)
  , Literal(..)
  , Pattern(..)
  , DoStep(..)

    -- * Holes
  , HoleKind(..)
  , DelegateSpec(..)
  , normalizeAsyncDelegateSpec
  , ScaffoldSpec(..)

    -- * Statements (Top-Level Forms)
  , Statement(..)
  , Module(..)
  , Import(ImportAt, Import, importPath, importInterface, importCapability, importSrc)
  , Capability(..)
  , CapabilityKind(..)
  , DeterministicFlag
  , EntryMode(..)

    -- * Contracts
  , Contract(..)
  , ProvClause(..)
  , SpecEntropy(..)
  , specEntropyLabel
  , parseSpecEntropy
  , resolveSpecEntropy
  , raiseLowDP

    -- * Evidence Model (v0.8.1b)
  , DisplayLevel(..)
  , EvidenceRecord(..)
  , PbtWitness(..)
  , AssumptionKind(..)
  , evidenceMeet
  , evidenceCovers
  , isVerifiedLevel
  , isSolverBacked
  , dlProverName
  , dlLabel
  , dlSurfaceLabel
  , trustVerifiedRejected
  , akLabel
  , ContractStatus(..)

    -- * Properties (check blocks)
  , Property(..)

    -- * Built-in Types
  , DelegationError(..)

    -- * Replay Status
  , ReplayStatus(..)

    -- * Commands
  , Command(..)

    -- * Module System (v0.2)
  , ModulePath
  , ModuleEnv(..)
  , ModuleCache
  , SiteKey
  , GenericSites

    -- * Grammar Mode (LT-INV v0.11)
  , GrammarMode(..)
  , normalizeDefStmt
  , defFormTag
  , isCoreBodySyntactic
    -- * SIGMA-CONST-ARITH-1: linear constant arithmetic
  , ConstArith(..)
  , groundInt
  , constArith
  , constArithAdmitted

    -- * Match-arm admissibility (SHELL-FALLBACK-SILENT-1)
  , classifyResultArms
  , classifyNArmAdtArms
  , repairableWildcardArms
  , wildcardPayloadCtors
  , hasHole
  , matchSites
  , matchArmSets
  ) where

import Data.Map.Strict (Map)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- ---------------------------------------------------------------------------
-- Names & Source Location
-- ---------------------------------------------------------------------------

-- | All identifiers in LLMLL are represented as Text.
type Name = Text

-- | Source span for error reporting.
data Span = Span
  { spanFile   :: FilePath
  , spanLine   :: Int
  , spanCol    :: Int
  , spanEndLine :: Int
  , spanEndCol  :: Int
  } deriving (Show, Eq, Ord, Generic)

-- | A value annotated with source location.
data Located a = Located
  { locSpan  :: Span
  , locValue :: a
  } deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Type System
-- ---------------------------------------------------------------------------

-- | The LLMLL type representation.
--
-- In v0.1, dependent types ('TDependent') store the constraint as a raw
-- expression AST — parsed but not evaluated at compile time.
data Type
  = TInt                          -- ^ 64-bit integer
  | TFloat                        -- ^ 64-bit float
  | TString                       -- ^ UTF-8 string
  | TBool                         -- ^ Boolean
  | TUnit                         -- ^ No value (void)
  | TBytes Int                    -- ^ Fixed-length byte array, e.g. bytes[64]
  | TList Type                    -- ^ Homogeneous list
  | TMap Type Type                -- ^ Key-value dictionary
  | TResult Type Type             -- ^ Sum type: Success(t) | Error(e)
  | TPair Type Type               -- ^ Product type: (a, b) — state + command pair
  | TFn [Type] Type               -- ^ Function type: [arg types] -> return type
  | TPromise Type                 -- ^ Async result wrapper
  | TDependent Name Type Expr     -- ^ Dependent type: binding name + base type + constraint expr
  | TDelegationError              -- ^ Built-in DelegationError sum type
  | TVar Name                     -- ^ Type variable (for generics / interfaces)
  | TCustom Name                  -- ^ User-defined type name (alias or opaque ref)
  | TSumType [(Name, Maybe Type)] -- ^ Structured sum type: [(ConstructorName, Maybe PayloadType)]
  -- | GENERICS-1: a rigid type parameter of a generic @def-shell@, with its
  -- declared constraint. Distinct from 'TVar' on purpose: 'TVar' is a
  -- placeholder (a wildcard at about nine sites outside the checker), and a
  -- rigid parameter unifies only with itself. A new constructor fails closed
  -- at every catch-all that does not name it. Produced only by
  -- 'bindTypeParams'; 'LLMLL.TypeCheck.freshenFnType' is where a generic
  -- callee's parameters become placeholders, per call.
  | TParam Name (Maybe TyConstraint)
  deriving (Show, Eq, Generic)

-- | GENERICS-1: the closed constraint set on a type parameter, with the
-- lattice @key => ord => eq@. @eq@ is the equality-capable types (§13.2),
-- @ord@ the ordered types O (§13.5), @key@ the map-key class (§13.12).
data TyConstraint = TCEq | TCOrd | TCKey
  deriving (Show, Eq, Ord, Generic)

-- | @have `entails` want@: a parameter constrained by @have@ satisfies @want@.
entails :: TyConstraint -> TyConstraint -> Bool
entails have want = rank have >= rank want
  where
    rank TCEq  = 1 :: Int
    rank TCOrd = 2
    rank TCKey = 3

-- | The surface spelling of a constraint, shared by both front ends and AstEmit.
tyConstraintLabel :: TyConstraint -> Text
tyConstraintLabel TCEq  = "eq"
tyConstraintLabel TCOrd = "ord"
tyConstraintLabel TCKey = "key"

parseTyConstraint :: Text -> Maybe TyConstraint
parseTyConstraint "eq"  = Just TCEq
parseTyConstraint "ord" = Just TCOrd
parseTyConstraint "key" = Just TCKey
parseTyConstraint _     = Nothing

-- | Human-readable label for a type (for error messages).
-- | BYTES-LEN-RANGE-1: a @bytes[n]@ length must lie in [0, 2^63 - 1], the range
-- of the 'Int' that 'TBytes' carries, checked on the unbounded value before any
-- narrowing. Shared by the S-expression and JSON-AST front ends so both refuse
-- the same lengths with the same text.
bytesLengthInRange :: Integer -> Bool
bytesLengthInRange n = n >= 0 && n <= toInteger (maxBound :: Int)

-- | The refusal message; it begins with the diagnostic kind.
bytesLengthRangeMessage :: Text -> Text
bytesLengthRangeMessage n =
  "bytes-length-range: bytes[" <> n <> "] declares a length outside"
  <> " 0..9223372036854775807; a bytes length must fit the runtime's Int"
  <> " (int-index-wrap-1-proposal D4)"

-- | GENERICS-1: the refusal of a @:type-params@ clause outside @def-shell@.
-- Shared by both front ends; it begins with the diagnostic kind. @form@ is
-- the surface keyword (@def@, @letrec@, @def-interface@, @type@).
typeParamsNotSupportedMessage :: Text -> Name -> Text
typeParamsNotSupportedMessage form name =
  "type-params-not-supported: '" <> form <> " " <> name <> "' declares :type-params,"
  <> " which v1 allows only on def-shell; "
  <> (if form == "type"
        then "generic type declarations are deferred to GENERIC-TYPES-1."
             <> " Declare the type once per element type"
        else "a generic " <> form <> " is deferred to GENERICS-2."
             <> " Write the definition as a def-shell, or at a concrete type")

-- | GENERICS-1: a JSON-AST @type-var@ whose name no enclosing @type_params@
-- declares. It begins with the diagnostic kind.
unknownTypeVarMessage :: Name -> Text
unknownTypeVarMessage n =
  "unknown-type-var: type variable '" <> n <> "' is not declared;"
  <> " a type-var may appear only in a def-shell whose type_params declares it"

typeLabel :: Type -> Text
typeLabel TInt            = "int"
typeLabel TFloat          = "float"
typeLabel TString         = "string"
typeLabel TBool           = "bool"
typeLabel TUnit           = "unit"
typeLabel (TBytes n)      = "bytes[" <> tshow n <> "]"
typeLabel (TList t)       = "list[" <> typeLabel t <> "]"
typeLabel (TMap k v)      = "map[" <> typeLabel k <> "," <> typeLabel v <> "]"
typeLabel (TResult t (TCustom "hs-maybe")) = "hs-maybe[" <> typeLabel t <> "]"  -- FFI-CONV-1: its source spelling
typeLabel (TResult t e)   = "Result[" <> typeLabel t <> "," <> typeLabel e <> "]"
typeLabel (TPair a b)     = "(" <> typeLabel a <> ", " <> typeLabel b <> ")"
typeLabel (TFn args ret)  = "fn[" <> tshow (length args) <> " args] -> " <> typeLabel ret
typeLabel (TPromise t)    = "Promise[" <> typeLabel t <> "]"
typeLabel (TDependent _ b _)= typeLabel b <> " (constrained)"
typeLabel TDelegationError = "DelegationError"
typeLabel (TVar n)        = n
typeLabel (TCustom n)     = n
typeLabel (TSumType ctors) = T.intercalate " | " (map fst ctors)
typeLabel (TParam n _)    = n

-- | Internal constructor name for disambiguation in diagnostics.
-- Used when typeLabel produces identical strings for different Type values.
-- e.g. TDelegationError → "built-in", TCustom "DelegationError" → "named".
typeConstructorName :: Type -> Text
typeConstructorName TInt               = "built-in"
typeConstructorName TFloat             = "built-in"
typeConstructorName TString            = "built-in"
typeConstructorName TBool              = "built-in"
typeConstructorName TUnit              = "built-in"
typeConstructorName TBytes{}           = "built-in"
typeConstructorName TList{}            = "built-in"
typeConstructorName TMap{}             = "built-in"
typeConstructorName TResult{}          = "built-in"
typeConstructorName TPair{}            = "built-in"
typeConstructorName TFn{}              = "built-in"
typeConstructorName TPromise{}         = "built-in"
typeConstructorName TDependent{}       = "constrained"
typeConstructorName TDelegationError   = "built-in"
typeConstructorName (TVar _)           = "type-var"
typeConstructorName (TCustom _)        = "named"
typeConstructorName TSumType{}         = "sum"
typeConstructorName (TParam _ _)       = "type-var"

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Literals
-- ---------------------------------------------------------------------------

data Literal
  = LitInt Integer
  | LitFloat Double
  | LitString Text
  | LitBool Bool
  | LitUnit
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Patterns (for match expressions)
-- ---------------------------------------------------------------------------

data Pattern
  = PConstructor Name [Pattern]   -- ^ e.g. Success(x), Error(e)
  | PVar Name                     -- ^ Variable binding
  | PLiteral Literal              -- ^ Literal pattern
  | PWildcard                     -- ^ Catch-all _
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Expressions
-- ---------------------------------------------------------------------------

data Expr
  = ELit Literal                       -- ^ Literal value
  | EVar Name                          -- ^ Variable reference
  | ELet [(Pattern, Maybe Type, Expr)] Expr -- ^ Let bindings with body (PR 4: pattern head)
  | EIf Expr Expr Expr                 -- ^ Conditional
  | EMatch Expr [(Pattern, Expr)]      -- ^ Pattern matching
  | EApp Name [Expr]                   -- ^ Function application
  | EOp Name [Expr]                    -- ^ Operator application (+, -, >=, =, etc.)
  | EPair Expr Expr                    -- ^ Pair constructor (for state + command)
  | EHole HoleKind                     -- ^ Hole (ambiguity marker)
  | EAwait Expr                        -- ^ Await a Promise
  | ELambda [(Name, Type)] Expr        -- ^ Anonymous function
  | EDo [DoStep]                       -- ^ Monadic do-notation (v0.2 prep)
  deriving (Show, Eq, Generic)

-- | A step in a do-block.
-- PR 2: collapsed from two constructors into one unified form.
--
-- The two discards a step can perform are orthogonal and both are explicit:
--
--   * 'dsName' @Nothing@ discards the STATE component (former DoExpr);
--     @Just n@ binds it (former DoBind).
--   * 'dsDiscard' declares that the COMMAND component is intentionally
--     dropped. Only a non-final step can discard a command, because the final
--     step's command is the one the harness performs.
--
-- DISCARD-1: 'dsDiscard' is a record field rather than a third positional
-- argument so that the ~30 read-only sites use accessors and cannot land a
-- value in the wrong slot. It is ERASABLE: it changes what the type checker
-- ACCEPTS and never what any VC ASSERTS, which is the soundness argument the
-- lifted-freeze policy requires of new syntax. 'emitDo' does not read it and
-- generated Haskell is bit-identical with and without it.
--
-- Two consequences that must hold wherever DoStep is serialised or hashed,
-- both because the marker carries no semantic content:
--
--   * 'LLMLL.AstEmit.doStepToJson' OMITS the field when False, or checkout /
--     patch rewrites every unmarked do-block in the corpus on first touch.
--   * 'LLMLL.PBT.canonicalStep' EXCLUDES it, or dedup keys and cached
--     verdicts move for programs that did not change.
data DoStep = DoStep
  { dsName    :: Maybe Name  -- ^ binds the state component when present
  , dsExpr    :: Expr        -- ^ the step's expression, of type (S, Command)
  , dsDiscard :: Bool        -- ^ DISCARD-1 marker; surface @:discard@
  }
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Holes
-- ---------------------------------------------------------------------------

-- | The different kinds of holes in LLMLL.
data HoleKind
  = HNamed Name                   -- ^ ?implementation_detail
  | HChoose [Name]                -- ^ ?choose(option1, option2)
  | HRequestCap Text              -- ^ ?request-cap(wasi.net.connect)
  | HScaffold ScaffoldSpec        -- ^ ?scaffold(template ...)
  | HDelegate DelegateSpec        -- ^ ?delegate @agent "desc" -> type
  | HDelegateAsync DelegateSpec   -- ^ ?delegate-async @agent "desc" -> type
  | HDelegatePending Type         -- ^ Unresolved delegate (blocks execution)
  | HConflictResolution           -- ^ Merge conflict marker
  -- D3: LiquidHaskell proof obligations
  | HProofRequired Text (Maybe Expr) -- ^ ?proof-required; reason tag + optional contract predicate (LT-PPR v0.11)
  deriving (Show, Eq, Generic)

-- | Specification for a scaffold hole.
data ScaffoldSpec = ScaffoldSpec
  { scaffoldTemplate :: Name
  , scaffoldLanguage :: Maybe Text
  , scaffoldModules  :: [Name]
  , scaffoldStyle    :: Maybe Text
  , scaffoldVersion  :: Maybe Text
  } deriving (Show, Eq, Generic)

-- | Specification for a delegate hole.
data DelegateSpec = DelegateSpec
  { delegateAgent       :: Name          -- ^ Target agent (@crypto-agent)
  , delegateDescription :: Text          -- ^ Task description string
  , delegateReturnType  :: Type          -- ^ Required return type
  , delegateOnFailure   :: Maybe Expr    -- ^ Optional fallback expression
  } deriving (Show, Eq, Generic)

-- | Normalize and validate an async delegate spec's return type.
--
-- Rules:
--   T                  -> Right spec                  (canonical, no change)
--   Promise[T]         -> Right spec{retTy = T}       (legacy wrapper stripped)
--   Promise[Promise[T]] -> Left "..."                 (nested promise, rejected)
--
-- The compiler wraps return_type in Promise automatically
-- (inferHole/HDelegateAsync). If the agent already wrote Promise[T],
-- this strips it so the compiler doesn't double-wrap.
--
-- Language restriction: delegate-async payload types must not be
-- Promise[...].  A single top-level Promise is tolerated as legacy;
-- nested Promise is a hard parse error.
normalizeAsyncDelegateSpec :: DelegateSpec -> Either Text DelegateSpec
normalizeAsyncDelegateSpec spec =
  case delegateReturnType spec of
    TPromise (TPromise _) ->
      Left $ "hole-delegate-async return_type must be the inner type T, not Promise[T]; "
          <> "nested Promise[Promise[...]] is invalid"
    TPromise inner ->
      Right spec { delegateReturnType = inner }
    _ ->
      Right spec

-- ---------------------------------------------------------------------------
-- Contracts
-- ---------------------------------------------------------------------------

-- | Pre/post conditions for a def-logic function.
-- v0.6: :source annotations provide clause-level provenance (per-clause, not per-contract).
data Contract = Contract
  { contractPre         :: Maybe Expr        -- ^ Precondition (must evaluate to bool)
  , contractPreSource   :: Maybe Text        -- ^ v0.6: :source annotation for pre clause
  , contractPost        :: Maybe Expr        -- ^ Postcondition (must evaluate to bool)
  , contractPostSource  :: Maybe Text        -- ^ v0.6: :source annotation for post clause
  , contractSpecEntropy :: Maybe SpecEntropy -- ^ LT-CDP (v0.11): per-contract spec-entropy
                                             -- annotation; 'Nothing' = unannotated (treated as
                                             -- ':strict' at consumption sites), 'Just _' = explicit
                                             -- author intent. Wire-line absence sentinel is
                                             -- distinguished from explicit ':strict' so CDP can
                                             -- report annotation provenance honestly.
  -- SRC-CONJ-1: per-conjunct provenance. When a side was authored as multiple
  -- clauses (S-expr: repeated (pre e :source s) / (post e :source s); JSON-AST:
  -- pre_clauses / post_clauses arrays), the list holds each clause with its own
  -- :source in author order, and the scalar 'contractPre'/'contractPost' above
  -- holds their left and-fold — every verifier-side consumer reads only the
  -- scalar, so the VC surface is unchanged. Invariant: the lists are populated
  -- at PARSE TIME ONLY (never synthesized; 'augmentContractPost' touches only
  -- the scalar), and a non-empty list implies its scalar equals
  -- foldl1 and (map pcExpr list). Empty on every 0-or-1-clause contract, whose
  -- provenance stays on the scalar source fields (legacy shape preserved).
  , contractPreClauses  :: [ProvClause]      -- ^ SRC-CONJ-1: per-conjunct pre provenance
  , contractPostClauses :: [ProvClause]      -- ^ SRC-CONJ-1: per-conjunct post provenance
  } deriving (Show, Eq, Generic)

-- | SRC-CONJ-1: one authored contract clause with its own provenance.
data ProvClause = ProvClause
  { pcExpr   :: Expr        -- ^ the clause expression (one conjunct of the folded scalar)
  , pcSource :: Maybe Text  -- ^ its :source citation, when authored
  } deriving (Show, Eq, Generic)

-- | LT-CDP (v0.11): per-contract spec-entropy annotation.
--
-- Three values per `contract-discriminative-power-proposal.md` §3:
--
--   * 'SpecEntropyStrict'      — default. Low DP raises a `--cdp` / `--weakness-check` diagnostic.
--   * 'SpecEntropyIntentional' — low DP is design (caches, schedulers, unspecified iteration order).
--                                CDP is computed and reported; diagnostic is suppressed.
--   * 'SpecEntropyUnknown'     — CDP is computed and reported but does not raise. For
--                                spec-development workflows where the contract is in flux.
data SpecEntropy
  = SpecEntropyStrict
  | SpecEntropyIntentional
  | SpecEntropyUnknown
  deriving (Show, Eq, Generic)

-- | Wire-line label for a 'SpecEntropy' value. Used by the JSON-AST round-trip
-- and the trust-report `spec_entropy_annotation` field per
-- `contract-discriminative-power-proposal.md` §5.
specEntropyLabel :: SpecEntropy -> Text
specEntropyLabel SpecEntropyStrict      = "strict"
specEntropyLabel SpecEntropyIntentional = "intentional"
specEntropyLabel SpecEntropyUnknown     = "unknown"

-- | Parse a 'SpecEntropy' wire-line label. Strict — unknown values return
-- 'Nothing' so callers can emit a parse error rather than silently default.
parseSpecEntropy :: Text -> Maybe SpecEntropy
parseSpecEntropy "strict"      = Just SpecEntropyStrict
parseSpecEntropy "intentional" = Just SpecEntropyIntentional
parseSpecEntropy "unknown"     = Just SpecEntropyUnknown
parseSpecEntropy _             = Nothing

-- | Resolve a contract's spec-entropy annotation, defaulting absent
-- annotations to ':strict' per proposal §3. Single source of truth for the
-- 'Nothing -> SpecEntropyStrict' default — used by both 'LLMLL.CDP' and
-- 'LLMLL.WeaknessCheck' (the latter cannot import 'LLMLL.CDP', which imports
-- it, so this lives here rather than in 'LLMLL.CDP').
resolveSpecEntropy :: Contract -> SpecEntropy
resolveSpecEntropy c = case contractSpecEntropy c of
  Just se -> se
  Nothing -> SpecEntropyStrict

-- | Does this annotation raise a low-DP diagnostic (identity/const-satisfies
-- warnings under '--cdp', spec-weakness under '--weakness-check')? Per §4.4.6:
-- ':strict' raises; ':intentional' and ':unknown' both suppress (they differ
-- only in author intent, not in whether the diagnostic fires).
raiseLowDP :: SpecEntropy -> Bool
raiseLowDP SpecEntropyStrict = True
raiseLowDP _                 = False

-- ---------------------------------------------------------------------------
-- Evidence Model (v0.8.1b — Diamond Lattice)
-- ---------------------------------------------------------------------------

-- | Evidence tier for a contract clause. A chain, not a diamond, and there is
-- no Ord instance.
--
-- Lattice structure. 'DLVerified' and 'DLVerifiedLean' are PEERS at the top —
-- both mean "the post is proven". 'verified-lean' additionally carries a
-- Lean-kernel-checked certificate; that kernel-checkability is a QUALITY the
-- display string records, NOT a strength above 'DLVerified'. The two are
-- mutually covering ('evidenceCovers') and both 'isVerifiedLevel'.
--
--       DLVerified  ≡  DLVerifiedLean   (peers, top)
--                    |
--             DLTested / DLTestedJoint
--                    |
--             DLAsserted                (bottom)
--
-- TRUST-CC-1: 'DLContractChecked' was retired. It sat between 'DLAsserted' and
-- the top, incomparable to 'DLTested', and NOTHING assigned it: the only
-- evidence-computing producer ('ProofCache.proofToLevel') had no callers, so no
-- meet ever took it as an operand. It also had eliminations and no introduction
-- rule, which is what separated it from a policy-lattice reservation. The state
-- the name denoted is real and is reported as the orthogonal 'body_fallback'
-- marker on the trust report, on the 'termination_unverified' model. See
-- docs/design/trust-cc-1-proposal.md.
data DisplayLevel
  = DLAsserted                             -- ^ Runtime assertion only; no evidence
  | DLTestedJoint { dljSamples :: Int }   -- ^ OBLIG-PBT-5b: PBT-tested only JOINTLY with other
                                          --   subjects (a single multi-subject property body
                                          --   credits N subjects at once). Weaker than solo
                                          --   'DLTested', stronger than 'DLAsserted'.
  | DLTested   { dlSamples :: Int }       -- ^ QuickCheck passed N samples
  | DLVerified { dlVerProver :: Text }    -- ^ SMT proved body satisfies contract
  | DLVerifiedLean { dlLeanProver :: Text } -- ^ Lean-proved + kernel-checked; peer of DLVerified
  deriving (Show, Eq, Generic)

-- | Structured evidence record for a single contract clause.
-- OBLIG-PBT-3: 'erPbtWitnesses' records property-body hashes that contributed
-- to a 'DLTested n' lift. Used by 'TrustReport.buildTrustReport' on read to
-- downgrade stale entries (property edited / deleted) to 'DLAsserted'. Empty
-- for non-PBT evidence (verifier-written, :trust tested source markers).
-- INT-1 (v0.10.8): 'erOverflowTainted' marks 'DLVerified' evidence whose body
-- contains LLMLL-level integer arithmetic over non-literal operands. Such
-- evidence is sound modulo the documented Int64 overflow gap (§5.3.5); the
-- '--strict-verified-core' flag refuses tainted verified clauses. The flag is
-- meaningful only for 'DLVerified' with 'erBodyFaithful = True'; for other
-- evidence levels the value is irrelevant. Defaults to 'False' on read of
-- pre-v0.10.8 sidecars (additive back-compat).
data EvidenceRecord = EvidenceRecord
  { erDisplayLevel         :: DisplayLevel   -- ^ What kind of evidence backs this clause
  , erBodyFaithful         :: Bool           -- ^ True when body VC was generated and passed
  , erSource               :: Maybe Text     -- ^ :source provenance annotation
  , erPbtWitnesses         :: [PbtWitness]   -- ^ OBLIG-PBT-3: PBT property-body provenance
  , erOverflowTainted      :: Bool           -- ^ INT-1: body has unbounded-Int arithmetic
  -- LT-PPR (v0.11): predicate-carrying ?proof-required enrichment
  , erPredicateForm        :: Maybe Text     -- ^ "symbolic" | "runtime" | Nothing when absent
  , erPredicateText        :: Maybe Text     -- ^ pretty-printed predicate expression, when present
  , erRuntimeCheckEmitted  :: Bool           -- ^ True when codegen emitted a runtime assertion
  -- ADMIT-VERIFIED (Option 2): hash over canonical (body, pre, post) + a
  -- semantics/toolchain-version tag, stamped by the verifier on body-faithful
  -- SAFE entries (Main.saveVerified). Read adjacent to 'downgradeStaleSidecar'
  -- to downgrade any 'erBodyFaithful' record whose recomputed hash mismatches,
  -- and consulted by 'TypeCheck.checkCalleeAdmissibility' as the persisted-
  -- evidence admission leg. 'Nothing' on pre-ADMIT-VERIFIED sidecars; that
  -- absence MUST fail closed (not admissible) — never unguarded admission.
  , erVerifiedHash         :: Maybe Text     -- ^ "sha256:" hash of canonical (body,pre,post)+version tag
  -- REC-DESCENT Phase 3: total-correctness bit. True when this function is a
  -- member of a descent-discharged SCC (every member declares a translatable
  -- k=1 (decreases e) measure, all body-faithful, and all well-foundedness +
  -- strict-descent VCs SAFE). Stamped on POST evidence by the verifier; absent
  -- on read defaults to False (fail-closed). Consulted by
  -- 'checkCalleeAdmissibility': a RECURSIVE callee is strict-core-admissible
  -- only when this is True (the b1 lift).
  , erTerminationVerified  :: Bool
  -- SRC-CONJ-1: per-conjunct :source provenance for this clause side, in
  -- author order ('Contract.contractPreClauses' / 'contractPostClauses'
  -- projected to their sources). Empty on 0-or-1-clause contracts (whose
  -- provenance is 'erSource') and on pre-SRC-CONJ-1 sidecars (additive
  -- back-compat, reader defaults to []). Report metadata only: never part of
  -- 'canonicalDefEvidenceHash', never consulted by admission.
  , erSources              :: [Maybe Text]
  } deriving (Show, Eq, Generic)

-- | OBLIG-PBT-3: SHA-256 hash + description of a property body whose
-- 'PBTPassed' run lifted a contract clause to 'DLTested n'. Hash is taken
-- over the canonical 'Expr' serialization of 'propBody' (see
-- 'LLMLL.PBT.canonicalPropBodyHash'). 'buildTrustReport' validates on read
-- against live property bodies and downgrades stale entries.
--
-- TRUST-REPORT-GATE-1 (§3.5): 'pwSubjectKey' is the evidence key
-- ('LLMLL.EvidenceKey', plain variant) of the subject function at write time.
-- The read check accepts a 'tested' record only when a witness carries the
-- live key of the record's function, so a record no longer survives an edit of
-- the tested function's body. 'Nothing' (every record written before v0.30.0)
-- fails closed. The key lives here and not in 'erVerifiedHash' so the
-- strict-core admission leg, which reads 'erVerifiedHash' only, is unchanged.
data PbtWitness = PbtWitness
  { pwHash        :: Text         -- ^ \"sha256:\" + 64 hex chars
  , pwDescription :: Text         -- ^ propDescription at write time, for display
  , pwSubjectKey  :: Maybe Text   -- ^ TRUST-REPORT-GATE-1: subject's evidence key at write time
  } deriving (Show, Eq, Generic)

-- | Classification of unverified dependencies.
data AssumptionKind
  = AKRuntimePrimitive   -- ^ Trusted runtime semantics: +, -, string-length, etc.
  | AKCompilerBuiltin    -- ^ Implemented in LLMLL preamble: string-char-at, regex-match
  | AKExternalOpaque     -- ^ Stub or FFI binding: sha1, hmac-sha1, Aeson
  deriving (Show, Eq, Ord, Generic)

-- | Per-function contract verification status (v0.8.1b).
data ContractStatus = ContractStatus
  { csPre         :: Maybe EvidenceRecord  -- ^ Nothing if no pre clause
  , csPost        :: Maybe EvidenceRecord  -- ^ Nothing if no post clause
  , csAssumptions :: [AssumptionKind]      -- ^ Function-level unverified dependencies
  } deriving (Show, Eq, Generic)

-- | Greatest lower bound (meet) of two display levels.
-- Exhaustive pattern matching — no numeric tier dispatch.
-- TRUST-CC-1: the lattice is a chain, so every pair is comparable. The clause
-- ORDER carries commutativity and associativity; do not reorder the survivors.
evidenceMeet :: DisplayLevel -> DisplayLevel -> DisplayLevel
-- Bottom absorbs
evidenceMeet DLAsserted _            = DLAsserted
evidenceMeet _ DLAsserted            = DLAsserted
-- Same constructor, different metadata: conservative choice
evidenceMeet (DLVerified p1) (DLVerified _)               = DLVerified p1
evidenceMeet (DLVerifiedLean p1) (DLVerifiedLean _)       = DLVerifiedLean p1
evidenceMeet (DLTested n1) (DLTested n2)                   = DLTested (min n1 n2)
-- OBLIG-PBT-5b: joint-tested is the glb of (solo) tested and itself; below tested,
-- above asserted. The TJ⊓V and TJ⊓VL cases fall through to the top-identity
-- equations below (result TJ).
evidenceMeet (DLTestedJoint n1) (DLTestedJoint n2)         = DLTestedJoint (min n1 n2)
evidenceMeet (DLTested _) (DLTestedJoint n)                = DLTestedJoint n
evidenceMeet (DLTestedJoint n) (DLTested _)                = DLTestedJoint n
-- Verified and verified-lean are PEER tops (both 'proven' strength): the glb
-- with any lower level is that lower level, and a mixed proven⊓proven stays at
-- 'proven' strength (the result is still 'isVerifiedLevel'). Ordering the two
-- top equations after the same-constructor cases keeps the meet commutative and
-- associative over {A,T,CC,V,VL}.
evidenceMeet (DLVerified _) b        = b
evidenceMeet a (DLVerified _)        = a
evidenceMeet (DLVerifiedLean _) b    = b
evidenceMeet a (DLVerifiedLean _)    = a

-- | Does evidence level @a@ cover requirement @b@?
-- a covers b iff a is at least as high in the lattice as b.
-- For DLTested, sample counts are metadata — DLTested n covers DLTested m for any n, m.
evidenceCovers :: DisplayLevel -> DisplayLevel -> Bool
-- Verified and verified-lean are peer tops: each covers everything (incl. the
-- other), and only a peer top covers a peer top. So V and VL are MUTUALLY
-- covering — a verified-lean post is assumable exactly where a verified one is.
evidenceCovers (DLVerified _) _              = True   -- top covers everything
evidenceCovers (DLVerifiedLean _) _          = True   -- peer top covers everything
evidenceCovers _ (DLVerified _)              = False  -- only a top covers a top
evidenceCovers _ (DLVerifiedLean _)          = False  -- only a top covers a top
evidenceCovers _ DLAsserted                  = True   -- everything covers bottom
evidenceCovers DLAsserted _                  = False  -- bottom covers only bottom
evidenceCovers (DLTested _) (DLTested _)     = True
-- OBLIG-PBT-5b: joint-tested. Solo-tested covers joint-tested (T ≥ TJ) but not the
-- reverse. (TJ vs Asserted / Verified / VerifiedLean are already decided by the
-- absorbing/top equations above.)
evidenceCovers (DLTestedJoint _) (DLTestedJoint _)     = True
evidenceCovers (DLTested _) (DLTestedJoint _)          = True
evidenceCovers (DLTestedJoint _) (DLTested _)          = False

-- | Is this verified-level (proven-strength) evidence? True for both the SMT
-- body-faithful tier ('DLVerified') and its Lean-kernel-checked peer
-- ('DLVerifiedLean') — they are equal strength, so the summary/tier counts
-- treat a 'verified-lean' post identically to a 'verified' one.
isVerifiedLevel :: DisplayLevel -> Bool
isVerifiedLevel DLVerified{}     = True
isVerifiedLevel DLVerifiedLean{} = True
isVerifiedLevel _                = False

-- | True when evidence includes a solver-/prover-backed proof of the BODY.
-- TRUST-CC-1: this used to return True for 'DLContractChecked' as well, which
-- granted trust (it silences 'TypeCheck.emitTrustGap') on a function whose
-- implementation was never encoded as a VC. The retired tier had no producer,
-- so no in-tree verdict moves.
isSolverBacked :: DisplayLevel -> Bool
isSolverBacked DLVerified{}        = True
isSolverBacked DLVerifiedLean{}    = True
isSolverBacked _                   = False

-- | Extract prover name, if any.
dlProverName :: DisplayLevel -> Maybe Text
dlProverName (DLVerified p)        = Just p
dlProverName (DLVerifiedLean p)    = Just p
dlProverName _                     = Nothing

-- | Human display label for a display level.
dlLabel :: DisplayLevel -> Text
dlLabel DLAsserted            = "asserted"
dlLabel (DLTestedJoint n)     = "tested-joint (" <> tshow n <> " samples)"
dlLabel (DLTested n)          = "tested (" <> tshow n <> " samples)"
dlLabel (DLVerified p)        = "verified (" <> p <> ")"
dlLabel (DLVerifiedLean _)    = "verified-lean"

-- | TRUST-LEVEL-FLOOR-1: the level as a @(trust f :level L)@ declaration and a
-- trust-gap warning spell it, without the sample count or prover that 'dlLabel'
-- appends. 'LLMLL.AstEmit' writes it for a trust declaration, so the JSON-AST
-- @level@ is one that 'LLMLL.ParserJSON.parseTrustDecl' reads back.
dlSurfaceLabel :: DisplayLevel -> Text
dlSurfaceLabel DLAsserted         = "asserted"
dlSurfaceLabel (DLTestedJoint _)  = "tested-joint"
dlSurfaceLabel (DLTested _)       = "tested"
dlSurfaceLabel (DLVerified _)     = "verified"
dlSurfaceLabel (DLVerifiedLean _) = "verified-lean"

-- | TRUST-LEVEL-FLOOR-1: the one rejection text both parsers give for
-- @(trust f :level verified)@. A declaration silences a gap only while the
-- evidence covers the declared level, and a solver-backed clause has no gap,
-- so a @verified@ declaration could never silence anything.
trustVerifiedRejected :: String
trustVerifiedRejected =
  "trust level 'verified' acknowledges nothing: a solver-backed clause has no \
  \trust gap (TRUST-LEVEL-FLOOR-1); declare the level the trust-gap warning reports"

-- | Human display label for an assumption kind.
akLabel :: AssumptionKind -> Text
akLabel AKRuntimePrimitive = "runtime-primitive"
akLabel AKCompilerBuiltin  = "compiler-builtin"
akLabel AKExternalOpaque   = "external-opaque"

-- ---------------------------------------------------------------------------
-- Properties (check blocks)
-- ---------------------------------------------------------------------------

-- | A property-based test specification.
--
-- OBLIG-PBT-4: 'propSubjects' carries explicit ':subject f' / ':subjects [f₁ … fₖ]'
-- keyword metadata on '(check …)' blocks. Empty list = no annotation (the
-- v0.10.5 head-position scan still applies); non-empty = the head-position
-- scan is bypassed and the listed names are the lift targets per
-- 'docs/design/oblig-pbt-3-proposal.md' §11.1 (pinned 2026-05-14).
data Property = Property
  { propDescription :: Text
  , propBindings    :: [(Name, Type)]   -- ^ for-all bindings
  , propBody        :: Expr             -- ^ Property body (must be bool)
  , propSubjects    :: [Name]           -- ^ OBLIG-PBT-4 explicit-subject opt-in
  } deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Statements (Top-Level Forms)
-- ---------------------------------------------------------------------------

-- | LT-INV (v0.11): grammar mode selected by --grammar flag.
-- 'GrammarCoreInversion' is the default from v0.11+; def/def-shell are the
-- canonical forms and def-logic/letrec are rejected at parse time.
-- 'GrammarLegacy' is the explicit opt-out (--grammar=legacy) for v0.10 programs.
data GrammarMode = GrammarLegacy | GrammarCoreInversion
  deriving (Show, Eq)

data Statement
  = SDefLogic
    { defLogicName   :: Name
    , defLogicParams :: [(Name, Type)]
    , defLogicReturn :: Maybe Type
    , defLogicContract :: Contract
    , defLogicBody   :: Expr
    }
  -- | LT-INV (v0.11): strict-core definition form ('def' keyword).
  -- Body is syntactically restricted to QF-LIA constructs; callee admissibility
  -- is enforced by the typechecker under --grammar=core-inversion.
  | SDef
    { defName     :: Name
    , defParams   :: [(Name, Type)]
    , defReturn   :: Maybe Type
    , defContract :: Contract
    , defBody     :: Expr
    }
  -- | LT-INV (v0.11): permissive definition form ('def-shell' keyword).
  -- Identical verification semantics to SDefLogic; explicitly marks the
  -- permissive regime at the source level.
  | SDefShell
    { defShellName      :: Name
    , defShellParams    :: [(Name, Type)]
    , defShellReturn    :: Maybe Type
    , defShellContract  :: Contract
    , defShellBody      :: Expr
    , defShellDecreases :: [Expr]  -- ^ REC-DESCENT (v0.14.24): optional termination
                                   -- measure list (k=1 discharged in v1); [] = absent.
                                   -- Phase 1 is verification-inert: parsed + round-tripped
                                   -- only, no obligation emitted.
    , defShellTypeParams :: [(Name, Maybe TyConstraint)]
                                   -- ^ GENERICS-1: the @:type-params@ clause in
                                   -- declared order; [] = not generic. Every
                                   -- occurrence in the definition is already a
                                   -- 'TParam' ('bindTypeParams').
    }
  -- | v0.12.1: module-level invariant predicate, promoted out of 'SDefLogic'.
  -- Carries identical verification semantics to 'SDefShell'/'SDefLogic' (a
  -- def-invariant has no pre/post and verification is Phase 2b — see
  -- @docs/llmll-ast.schema.json@ DefInvariant). The 5-field shape mirrors the
  -- other def-forms so 'normalizeDefStmt' and every consumer arm stay uniform;
  -- only AstEmit treats it specially, serialising the single param + body as a
  -- @def-invariant@ node rather than the lossy @def-logic@ form (the v0.12.1
  -- round-trip fix). Parseable from both surface forms: JSON-AST
  -- ('LLMLL.ParserJSON.parseDefInvariant') and S-expression
  -- ('LLMLL.Parser.pDefInvariant', @(def-invariant name [x: type] body)@).
  | SDefInvariant
    { defInvariantName     :: Name
    , defInvariantParams   :: [(Name, Type)]
    , defInvariantReturn   :: Maybe Type
    , defInvariantContract :: Contract
    , defInvariantBody     :: Expr
    }
  -- | Explicitly recursive function with a termination measure.
  -- D2: `:decreases expr` must be an integer-valued expression that strictly
  -- decreases in each recursive call (restricted to QF linear arithmetic for LH).
  -- Codegen treats this identically to SDefLogic; the decreases expr is stored
  -- for the LH annotation layer (Deliverable 4).
  | SLetrec
    { letrecName      :: Name
    , letrecParams    :: [(Name, Type)]
    , letrecReturn    :: Maybe Type
    , letrecContract  :: Contract
    , letrecDecreases :: Expr    -- ^ termination measure (must be int-typed)
    , letrecBody      :: Expr
    }
  | SDefInterface
    { defInterfaceName :: Name
    , defInterfaceFns  :: [(Name, Type)]  -- ^ Function signatures
    , defInterfaceLaws :: [Property]      -- ^ v0.6.2: for-all properties (tested via QuickCheck)
    }
  | STypeDef
    { typeDefName :: Name
    , typeDefBody :: Type
    }
  | SCheck Property
  | SImport Import
  | SExpr Expr           -- ^ Top-level expression
  | SDefMain
    { defMainMode   :: EntryMode      -- ^ Runtime harness kind
    , defMainInit   :: Maybe Expr     -- ^ :init (optional for stateless)
    , defMainStep   :: Expr           -- ^ :step (name or lambda)
    , defMainDone   :: Maybe Expr     -- ^ :done? (console only)
    , defMainOnDone :: Maybe Expr     -- ^ :on-done (optional)
    -- | PROC-BOUNDARY-1 §4: @:status@, a total projection from the state type
    -- to @int@, applied ONLY on the @:done?@ path. It is not an effect: nothing
    -- in the program observes the result and the program does not continue past
    -- it, so it is a field on the entry declaration rather than a 'Command'.
    -- Absent means exit 0 on that path, which is every shipped program's
    -- behaviour, so the field is additive.
    --
    -- Deliberately NOT consulted on stdin exhaustion (§4.3): where @:done?@ is
    -- DECLARED the harness exits a fixed 70 there, and where it is not, EOF is
    -- normal termination and the harness exits 0. The information separating
    -- "finished" from "starved" lives in @:done?@, a predicate OUTSIDE the
    -- state, so a projection from state alone cannot see it, and where the
    -- predicate is absent there is no starvation to see.
    , defMainStatus :: Maybe Expr     -- ^ :status (optional; console :done? path)
    }
  -- v0.2 module system
  | SOpen
    { openPath  :: ModulePath        -- ^ Resolved module path e.g. ["app","auth"]
    , openNames :: Maybe [Name]      -- ^ Nothing = all exports; Just ns = selective
    }
  | SExport [Name]                   -- ^ Restrict exported names; absent = export all
  -- v0.3 stratified verification
  | STrust
    { trustTarget :: Name              -- ^ Flat dotted qualified name, e.g. "crypto.hash.pbkdf2"
    , trustLevel  :: DisplayLevel      -- ^ Acknowledged trust level
    }
  -- v0.6 suppression governance
  | SWeaknessOk
    { weaknessTarget :: Name           -- ^ Function name to suppress weakness warnings for
    , weaknessReason :: Text           -- ^ Mandatory reason string (non-empty)
    }
  deriving (Show, Eq, Generic)

-- | LT-INV (v0.11): extract the shared def-like fields from SDefLogic, SDef,
-- or SDefShell.  Returns Nothing for any other statement kind.
-- Use this in the 22-file fan-out wherever all three forms are treated
-- identically (codegen, trust report, fixpoint emission, etc.).
normalizeDefStmt :: Statement -> Maybe (Name, [(Name, Type)], Maybe Type, Contract, Expr)
normalizeDefStmt (SDefLogic     n p r c b) = Just (n, p, r, c, b)
normalizeDefStmt (SDef          n p r c b) = Just (n, p, r, c, b)
normalizeDefStmt (SDefShell     n p r c b _ _) = Just (n, p, r, c, b)
normalizeDefStmt (SDefInvariant n p r c b) = Just (n, p, r, c, b)
normalizeDefStmt _                         = Nothing

-- | GENERICS-1: bind a generic @def-shell@'s declared type parameters.
--
-- Both front ends read a lowercase type name as @TCustom n@ (the JSON-AST
-- @type-var@ kind too), and both call this on every @def-shell@ they build, so
-- the two share one scoping rule. Each @TCustom n@ whose @n@ is declared in
-- 'defShellTypeParams' becomes @TParam n c@ in the value-parameter types, the
-- return type, @pre@, @post@, @decreases@ and every annotation in the body
-- (lambda parameters, typed @let@, a refinement inside a type, a delegate's
-- return type). The identity on every other statement and on a @def-shell@
-- with no @:type-params@, so programs without the clause are untouched.
--
-- Total by design: the one failure the JSON-AST reader can see, a @type-var@
-- whose name is not declared (@unknown-type-var@), is refused in the reader,
-- where the @type-var@ spelling is still visible; here it is a plain name.
bindTypeParams :: Statement -> Statement
bindTypeParams st@(SDefShell n ps r c b ds tps)
  | null tps  = st
  | otherwise =
      SDefShell n [ (p, bt t) | (p, t) <- ps ] (fmap bt r) (bc c) (be b) (map be ds) tps
  where
    bt :: Type -> Type
    bt t = case t of
      TCustom v | Just k <- lookup v tps -> TParam v k
      TParam v _ | Just k <- lookup v tps -> TParam v k
      TList a          -> TList (bt a)
      TMap k v         -> TMap (bt k) (bt v)
      TResult a e      -> TResult (bt a) (bt e)
      TPair a e        -> TPair (bt a) (bt e)
      TFn as ret       -> TFn (map bt as) (bt ret)
      TPromise a       -> TPromise (bt a)
      TDependent v a p -> TDependent v (bt a) (be p)
      TSumType ctors   -> TSumType [ (k, fmap bt mp) | (k, mp) <- ctors ]
      _                -> t
    bc ct = ct { contractPre  = fmap be (contractPre ct)
               , contractPost = fmap be (contractPost ct)
               , contractPreClauses  = map bpc (contractPreClauses ct)
               , contractPostClauses = map bpc (contractPostClauses ct) }
    bpc pc = pc { pcExpr = be (pcExpr pc) }
    be :: Expr -> Expr
    be e = case e of
      ELet binds body  -> ELet [ (p, fmap bt mt, be x) | (p, mt, x) <- binds ] (be body)
      EIf x y z        -> EIf (be x) (be y) (be z)
      EMatch x arms    -> EMatch (be x) [ (p, be a) | (p, a) <- arms ]
      EApp f args      -> EApp f (map be args)
      EOp o args       -> EOp o (map be args)
      EPair x y        -> EPair (be x) (be y)
      EHole h          -> EHole (bh h)
      EAwait x         -> EAwait (be x)
      ELambda lps body -> ELambda [ (p, bt t) | (p, t) <- lps ] (be body)
      EDo steps        -> EDo [ s { dsExpr = be (dsExpr s) } | s <- steps ]
      _                -> e
    bh h = case h of
      HDelegate sp        -> HDelegate (bd sp)
      HDelegateAsync sp   -> HDelegateAsync (bd sp)
      HDelegatePending t  -> HDelegatePending (bt t)
      HProofRequired w mp -> HProofRequired w (fmap be mp)
      _                   -> h
    bd sp = sp { delegateReturnType = bt (delegateReturnType sp)
               , delegateOnFailure  = fmap be (delegateOnFailure sp) }
bindTypeParams st = st

-- | REC-HASH-FORM (b0 of REC-BODY-VC): the def-form tag folded into the
-- ADMIT-VERIFIED evidence hash preimage ('PBT.canonicalDefEvidenceHash'), so a
-- 'def-shell' -> 'def' rename over an intact '.verified.json' drifts the hash
-- and the sidecar is downgraded instead of laundering partial-correctness
-- evidence into the strict-core (total-claim) tier (probe E). 'normalizeDefStmt'
-- deliberately erases the constructor; this recovers just the admission-relevant
-- distinction (strict-core 'def' vs permissive 'def-shell'). 'SLetrec' is tagged
-- for totality though it never reaches the hash sites (letrec emits no body VC).
defFormTag :: Statement -> Text
defFormTag SDefShell{}     = "def-shell"
defFormTag SLetrec{}       = "letrec"
defFormTag SDef{}          = "def"
defFormTag SDefLogic{}     = "def"
defFormTag SDefInvariant{} = "def"
defFormTag _               = "def"

-- | SIGMA-CONST-ARITH-1 (docs/design/sigma-const-arith-1-proposal.md): the
-- value of a GROUND CONSTANT, a closed term of integer literals under `+`,
-- `-`, `*`, `/` and `mod`, folded with the codegen semantics: exact 'Integer'
-- arithmetic and Haskell `div` / `mod` (`emitOp` in "LLMLL.CodegenHs"). A `/`
-- or `mod` folds only when its divisor folds to a value > 0; otherwise the
-- term is not ground. Both spellings ('EOp' and 'EApp') are read.
groundInt :: Expr -> Maybe Integer
groundInt e = case e of
  ELit (LitInt n) -> Just n
  EOp  op [a, b]  -> arith op a b
  EApp op [a, b]  -> arith op a b
  _               -> Nothing
  where
    arith op a b = do
      x <- groundInt a
      y <- groundInt b
      case op of
        "+"   -> Just (x + y)
        "-"   -> Just (x - y)
        "*"   -> Just (x * y)
        "/"   | y > 0 -> Just (x `div` y)
        "mod" | y > 0 -> Just (x `mod` y)
        _     -> Nothing

-- | SIGMA-CONST-ARITH-1: an admitted constant-linear node, with the folded
-- constant and the operand the solver still sees.
data ConstArith
  = MulL Integer Expr   -- ^ @(* c e)@
  | MulR Expr Integer   -- ^ @(* e c)@
  | DivC Expr Integer   -- ^ @(/ e c)@, @c > 0@
  | ModC Expr Integer   -- ^ @(mod e c)@, @c > 0@
  deriving (Show, Eq)

-- | SIGMA-CONST-ARITH-1: classify one `*`, `/` or `mod` node. 'Nothing' for a
-- product of two non-ground terms, a non-ground divisor, or a ground divisor
-- <= 0 (a negative divisor disagrees between Haskell and SMT-LIB; a zero
-- divisor raises at run time). `rem`, `^` and `**` are never admitted. This
-- is a property of THIS node only; the operand's own admission is decided
-- where it is translated or walked.
constArith :: Name -> [Expr] -> Maybe ConstArith
constArith "*" [a, b]
  | Just c <- groundInt a = Just (MulL c b)
  | Just c <- groundInt b = Just (MulR a c)
constArith "/" [e, d]
  | Just c <- groundInt d, c > 0 = Just (DivC e c)
constArith "mod" [e, d]
  | Just c <- groundInt d, c > 0 = Just (ModC e c)
constArith _ _ = Nothing

-- | SIGMA-CONST-ARITH-1: the node is ground, or an admitted constant-linear form.
constArithAdmitted :: Name -> [Expr] -> Bool
constArithAdmitted op args =
  op `elem` constArithOps
  && (isJust (groundInt (EOp op args)) || isJust (constArith op args))

-- | The operators 'constArith' decides.
constArithOps :: [Name]
constArithOps = ["*", "/", "mod"]

-- | LT-INV (v0.11): return 'True' if an expression is admissible inside a
-- strict-core ('SDef') body per the grammar production in the proposal §3.2.
-- Admits: literals, variables, QF-LIA operators (`*`, `/` and `mod` only in an admitted
-- constant-linear form, SIGMA-CONST-ARITH-1; never `rem`), let, if,
-- function application, two-arm Result EMatch, n-arm (>= 2) sum EMatch whose
-- arms are all nullary / single-payload / catch-all (MATCH-WIDEN-2 verifier
-- parity), pair constructor, and non-'HProofRequired' holes.
-- Rejects: lambdas, do-notation, await, non-linear operators (a product of two
-- non-constant terms, a non-constant or non-positive divisor, `rem`), a match arm with
-- a multi-payload constructor pattern, and '?proof-required' holes.
isCoreBodySyntactic :: Expr -> Bool
isCoreBodySyntactic expr = case expr of
  ELit _                   -> True
  EVar _                   -> True
  -- SIGMA-CONST-ARITH-1: `*`, `/` and `mod` are core syntax exactly when the
  -- node is an admitted constant-linear form ('constArithAdmitted').
  EOp op args
    | op `elem` constArithOps -> constArithAdmitted op args && all isCoreBodySyntactic args
    | otherwise               -> isLinearOp op && all isCoreBodySyntactic args
  ELet binds body          -> all (\(_, _, e) -> isCoreBodySyntactic e) binds
                              && isCoreBodySyntactic body
  EIf c t e                -> all isCoreBodySyntactic [c, t, e]
  EApp _ args              -> all isCoreBodySyntactic args
  EPair a b                -> isCoreBodySyntactic a && isCoreBodySyntactic b
  EMatch scr cases         -> isCoreBodySyntactic scr
                              && all (isCoreBodySyntactic . snd) cases
                              && ( (length cases == 2 && all (isResultArm . fst) cases)
                                   -- COMP-3b-general (Phase 1): an N-arm match whose arms
                                   -- are all nullary constructors (or a catch-all) is
                                   -- desugared to nested int-tag `if`s at VC-emission time.
                                   || (not (null cases) && all (isNullaryEnumArm . fst) cases)
                                   -- COMP-4 (d-elim): a two-arm match whose arms are
                                   -- single-payload constructors of a user sum type is
                                   -- core syntax; the verifier opaque-sum-eliminates it
                                   -- (admissible payloads) or conservatively falls back.
                                   || (length cases >= 2 && all (isPayloadCtorArm . fst) cases)
                                   -- MATCH-WIDEN (v0.14.12): a two-arm MIXED sum — one
                                   -- nullary constructor + one single-payload constructor —
                                   -- is core syntax; the verifier opaque-sum-eliminates it
                                   -- with the nullary arm binding no payload skolem.
                                   || (length cases >= 2 && isMixedNullaryPayloadArms (map fst cases)) )
  EHole (HProofRequired _ _) -> False
  EHole _                  -> True
  ELambda _ _              -> False
  EAwait _                 -> False
  EDo _                    -> False
  where
    isLinearOp op = op `notElem` (["*", "/", "mod", "rem"] :: [Name])
    isResultArm (PConstructor n _) = n `elem` (["Success", "Error"] :: [Name])
    isResultArm _                  = False
    isNullaryEnumArm (PConstructor _ []) = True
    isNullaryEnumArm PWildcard           = True
    isNullaryEnumArm (PVar _)            = True
    isNullaryEnumArm _                   = False
    isPayloadCtorArm (PConstructor _ [PVar _]) = True
    isPayloadCtorArm _                         = False
    -- MATCH-WIDEN-2: an n-arm (>= 2) match whose every arm is a nullary
    -- constructor, a single-payload constructor, or a catch-all (wildcard/var)
    -- is core syntax — the verifier discharges it body-faithfully via the n-way
    -- int-tag chain (buildOpaqueSumBranchN); exhaustiveness is enforced by
    -- TypeCheck.checkExhaustive. Generalizes the former exactly-two-arm form.
    isMixedNullaryPayloadArms ps =
      not (null ps)
        && all (\p -> isPayloadCtorArm p || isNullaryEnumArm p) ps

-- ---------------------------------------------------------------------------
-- Match-arm admissibility (SHELL-FALLBACK-SILENT-1)
-- ---------------------------------------------------------------------------
--
-- 'classifyResultArms' and 'classifyNArmAdtArms' lived in FixpointEmit and
-- decided, at VC-emission time, whether a match could be opaque-sum-eliminated.
-- They live here because the CHECKER now needs the same answer: W-MATCH-WILDCARD-PAYLOAD
-- tells an author that binding a payload repairs the function, and that sentence is
-- true only while the checker and the emitter agree on what "admissible" means.
-- Two copies would drift and no gate would catch it. FixpointEmit re-exports both.

-- | v0.9.0 COMP-3: classify a two-arm Result match.
-- Returns (successVar, successBody, errorVar, errorBody) when both arms bind
-- their payload by name. A wildcard payload does NOT classify: the opaque-sum
-- elimination binds a payload skolem and has no name to bind it to.
classifyResultArms :: [(Pattern, Expr)] -> Maybe (Name, Expr, Name, Expr)
classifyResultArms arms = case arms of
  [(PConstructor "Success" [PVar s], bodyS), (PConstructor "Error" [PVar e], bodyE)] ->
    Just (s, bodyS, e, bodyE)
  [(PConstructor "Error" [PVar e], bodyE), (PConstructor "Success" [PVar s], bodyS)] ->
    Just (s, bodyS, e, bodyE)
  _ -> Nothing

-- | MATCH-WIDEN-2: classify an n-arm (>= 2) match on a user sum type. Returns the
-- list of single-payload-or-nullary constructor arms (in source order, distinct
-- constructors) plus an OPTIONAL wildcard/PVar tail body (the terminal else). A
-- wildcard, if present, must be the LAST arm (first-match order). Any arm that is
-- not a nullary/single-payload constructor or a final wildcard → 'Nothing' (the
-- whole match falls back); exhaustiveness is guaranteed upstream by
-- 'TypeCheck.checkExhaustive', so the verifier need not re-check coverage.
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

-- | SHELL-FALLBACK-SILENT-1: does this arm set write a constructor payload as
-- @_@ where binding it by a name would let the verifier eliminate the match?
--
-- The condition is NOT "the arm set is outside 'isCoreBodySyntactic' and the
-- repair brings it inside". 'isCoreBodySyntactic' admits a @Result@ arm whatever
-- its sub-patterns are (its @isResultArm@ ignores them), so
-- @((Success _) …) ((Error _) …)@ is core syntax in a @def@ as well as a
-- @def-shell@, falls back at emission anyway, and the narrower reading misses it
-- entirely. The condition that holds for both shapes is: a @(Ctor _)@ arm is
-- present, and the REPAIRED arm set classifies.
--
-- Decided against the two classifiers above rather than against
-- 'isCoreBodySyntactic', because those two are what actually refuses the body.
repairableWildcardArms :: [(Pattern, Expr)] -> Bool
repairableWildcardArms arms =
  any (isWildcardPayload . fst) arms && armsClassify (map repairArm arms)
  where
    isWildcardPayload (PConstructor _ [PWildcard]) = True
    isWildcardPayload _                            = False
    -- the repair the warning tells the author to make: bind the payload
    repairArm (PConstructor c [PWildcard], b) = (PConstructor c [PVar "x"], b)
    repairArm arm                             = arm
    armsClassify as =
      case classifyResultArms as of
        Just _  -> True
        Nothing -> case classifyNArmAdtArms as of
                     Just (ctorArms, _) -> not (null ctorArms)
                     Nothing            -> False

-- | The constructor names whose payload this arm set writes as @_@. Reported in
-- the warning text so the author knows which arm to repair; the census's closed
-- label vocabulary never carries these, because a constructor name is program
-- text and would give the histogram an unbounded bucket set.
wildcardPayloadCtors :: [(Pattern, Expr)] -> [Name]
wildcardPayloadCtors arms =
  [ c | (PConstructor c [PWildcard], _) <- arms ]

-- | FALLBACK-CENSUS-1: does this body contain a hole of any kind?
--
-- Moved here from FixpointEmit with the classifiers, for the same reason and
-- with its original note: the census and the report share ONE walker, and the
-- checker is now a third consumer. Every hole kind counts: a scaffold, a
-- delegate and a pending delegate are all bodies with nothing written to prove.
hasHole :: Expr -> Bool
hasHole (EHole _)        = True
hasHole (EApp _ args)    = any hasHole args
hasHole (EOp _ args)     = any hasHole args
hasHole (EIf c t e)      = hasHole c || hasHole t || hasHole e
hasHole (ELet bs body)   = any (\(_, _, e) -> hasHole e) bs || hasHole body
hasHole (EMatch s arms)  = hasHole s || any (hasHole . snd) arms
hasHole (EPair a b)      = hasHole a || hasHole b
hasHole (EAwait e)       = hasHole e
hasHole (ELambda _ body) = hasHole body
hasHole (EDo steps)      = any (hasHole . dsExpr) steps
hasHole _                = False

-- | Every 'EMatch' in an expression, outermost first, as (scrutinee, arms).
--
-- The scrutinee is carried because a refusal label must be attributed to the
-- match that earned it. Reporting "the payload sort refused this body" from a
-- whole-function property would mislabel a function that holds one match on an
-- admissible scrutinee and one on an inadmissible one.
matchSites :: Expr -> [(Expr, [(Pattern, Expr)])]
matchSites e = case e of
  EMatch scr arms -> (scr, arms) : concatMap matchSites (scr : map snd arms)
  EApp _ args     -> concatMap matchSites args
  EOp _ args      -> concatMap matchSites args
  EIf c t f       -> concatMap matchSites [c, t, f]
  ELet bs body    -> concatMap (\(_, _, x) -> matchSites x) bs ++ matchSites body
  EPair a b       -> matchSites a ++ matchSites b
  EAwait x        -> matchSites x
  ELambda _ body  -> matchSites body
  EDo steps       -> concatMap (matchSites . dsExpr) steps
  _               -> []

-- | Every 'EMatch' arm set in an expression, outermost first.
matchArmSets :: Expr -> [[(Pattern, Expr)]]
matchArmSets = map snd . matchSites

-- | Selects the runtime harness template generated by the compiler.
--
-- MODE-HTTP-1: the @http@ mode is removed. It was an @error@ stub with no
-- server behind it; the server design is tracked as HTTP-SERVE-1.
data EntryMode
  = ModeConsole                -- ^ stdin/stdout interactive loop
  | ModeCli                    -- ^ console harness without stdin (MODE-CLI-1)
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Modules
-- ---------------------------------------------------------------------------

-- | A complete LLMLL module.
data Module = Module
  { moduleName    :: Name
  , moduleImports :: [Import]
  , moduleBody    :: [Statement]
  } deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Imports & Capabilities
-- ---------------------------------------------------------------------------

data Import = ImportAt
  { importPath        :: Name                  -- ^ e.g. "wasi.filesystem"
  , importInterface   :: Maybe [(Name, Type)]  -- ^ Optional interface spec
  , importCapability  :: Maybe Capability      -- ^ Required capability grant
  -- | FFI-TIER1-1: the source file and line of the @(import ...)@ form, so a
  -- @haskell.*@ interface binding can carry a GHC LINE pragma pointing back at
  -- it. The S-expression parser fills it; JSON-AST has no positions and leaves
  -- it Nothing. It is a location, not part of the program: 'Eq' ignores it, so
  -- the same program read from either front end still compares equal.
  , importSrc         :: Maybe (FilePath, Int)
  } deriving (Show, Generic)

instance Eq Import where
  a == b = (importPath a, importInterface a, importCapability a)
        == (importPath b, importInterface b, importCapability b)

-- | An import with no source location: the three-field form every builder
-- outside the S-expression parser uses.
pattern Import :: Name -> Maybe [(Name, Type)] -> Maybe Capability -> Import
pattern Import p i c <- ImportAt p i c _
  where Import p i c = ImportAt p i c Nothing
{-# COMPLETE Import #-}

-- | Whether a capability uses deterministic logging.
type DeterministicFlag = Bool

data Capability = Capability
  { capKind          :: CapabilityKind
  , capTarget        :: Text                   -- ^ e.g. "/data", "https://...", "8080"
  , capDeterministic :: DeterministicFlag       -- ^ :deterministic true
  } deriving (Show, Eq, Generic)

data CapabilityKind
  = CapRead
  | CapWrite
  | CapReadWrite
  | CapNetConnect
  | CapNetServe
  | CapHttpPost
  | CapHttpGet
  | CapClockMonotonic
  | CapRandomGet
  | CapCpu Text          -- ^ CPU capability with core count
  | CapCustom Text       -- ^ Custom / extensible
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Built-in Error Types
-- ---------------------------------------------------------------------------

-- | The DelegationError sum type — built into the language.
data DelegationError
  = AgentTimeout
  | AgentCrash
  | TypeMismatch
  | AgentNotFound
  deriving (Show, Eq, Ord, Enum, Bounded, Generic)

-- ---------------------------------------------------------------------------
-- Replay Status
-- ---------------------------------------------------------------------------

-- | Whether a module is replayable (all non-deterministic capabilities
-- use :deterministic true) or best-effort.
data ReplayStatus
  = Replayable       -- ^ ✅ All deterministic
  | BestEffortReplay -- ^ ⚠️ Some non-deterministic capabilities
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Commands (IO Model)
-- ---------------------------------------------------------------------------

-- | A Command represents an IO intent returned by pure logic.
-- The runtime inspects and executes these.
data Command
  = CmdHttpResponse Int Text       -- ^ Status code + body
  | CmdHttpRequest Text Text Text  -- ^ Method, URL, body
  | CmdFsRead FilePath
  | CmdFsWrite FilePath Text
  | CmdFsDelete FilePath
  | CmdDbQuery Text                -- ^ Query string
  | CmdDbInsert Text Text          -- ^ Table, data
  | CmdCustom Name [Expr]          -- ^ Extensible command
  deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Module System (v0.2)
-- ---------------------------------------------------------------------------

-- | Canonical multi-segment module path, e.g. ["app", "auth", "bcrypt"].
-- Derived from the file's location relative to the source root
-- (convention-over-declaration: the (module Name ...) label is for human
-- readability only and does not affect the canonical path).
type ModulePath = [Name]

-- | Everything the type-checker and codegen need from one compiled module.
data ModuleEnv = ModuleEnv
  { meExports        :: Map Name Type             -- ^ exported name → type
  , meStatements     :: [Statement]               -- ^ parsed statements (for codegen left-to-right)
  , meInterfaces     :: Map Name [(Name, Type)]   -- ^ exported interface shapes
  , meAliasMap       :: Map Name Type             -- ^ exported type aliases (for cross-module unify)
  , mePath           :: ModulePath                -- ^ this module's canonical path
  , meContractStatus :: Map Name ContractStatus   -- ^ v0.3: per-function verification levels
  , meContracts      :: Map Name ([(Name, Type)], Contract, Maybe Type)
    -- ^ v0.10 MOD-1: per-function contract expressions for cross-module
    -- compositional verification. Carries (params, contract, returnType)
    -- matching ContractEnv's shape so imported contracts can be merged
    -- directly into the local ContractEnv.
  , meRetTypes       :: Map Name Type
    -- ^ FQ-RESULT-SORT-1 stage (b): this module's effective return types,
    -- tau_ret(f) = mRet |> tau_body, as recorded by the type checker when the
    -- module was loaded. Needed because 'seedImportedContracts' rebuilds an
    -- imported module's ContractEnv from 'meStatements' rather than reading
    -- 'meContracts', so the raw optional annotation was the only return-type
    -- signal available cross-module and an unannotated non-int callee sorted
    -- its call-result binder at FQInt. Kept as a separate field rather than
    -- folded into 'meContracts' precisely because that rebuild path bypasses
    -- 'meContracts' entirely.
  , meBuiltinAxioms  :: Maybe (Map Name [Name])
    -- ^ TRUST-AXIOM: the sealed-builtin axiom set this module's sidecar
    -- recorded, per def. An importing module cannot recompute it: a caller's
    -- run never emits the callee's body VC, so the callee's sidecar is the only
    -- source. 'Nothing' means the sidecar predates the disclosure and the sets
    -- are UNKNOWN, which a reader must render as unrecorded rather than as
    -- "assumes nothing"; see 'LLMLL.VerifiedCache.axiomDisclosureVersion'.
  , meGenericSites   :: GenericSites
    -- ^ GENERICS-1: this module's generic instantiation sites, as recorded by
    -- the type checker when the module was loaded. An importer needs them to
    -- specialize an imported generic whose body calls other generics: the
    -- importer's own check never sees that body's calls. Empty for a module
    -- with no generic call.
  } deriving (Show)

-- | GENERICS-1: one generic call site, as @(enclosing, callee, args)@. The
-- enclosing component is the top-level definition that contains the call, or
-- the RFC 6901 pointer @"/statements/N"@ of any other top-level statement (a
-- check, a def-main). @args@ is 'LLMLL.PBT.canonicalExpr' of each argument.
-- Keyed by argument text because the checker elaborates no tree (plan F2).
type SiteKey = (Name, Name, [Text])

-- | GENERICS-1: the site table. The value is the callee's type arguments in
-- its declared @:type-params@ order. A type argument may mention the
-- enclosing definition's own 'TParam's; @TVar "?unfixed"@ marks a type the
-- call never fixes (AMBIG-TVAR-1), which specialization takes at @int@.
type GenericSites = Map SiteKey [Type]

-- | In-memory module cache: populated by post-order DFS load, read by
-- type-checker and codegen.  Empty for single-file inputs (full backward compat).
type ModuleCache = Map ModulePath ModuleEnv
