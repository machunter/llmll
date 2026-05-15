{-# LANGUAGE StrictData #-}
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
  , Import(..)
  , Capability(..)
  , CapabilityKind(..)
  , DeterministicFlag
  , EntryMode(..)

    -- * Contracts
  , Contract(..)

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
  ) where

import Data.Map.Strict (Map)
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
  deriving (Show, Eq, Generic)

-- | Human-readable label for a type (for error messages).
typeLabel :: Type -> Text
typeLabel TInt            = "int"
typeLabel TFloat          = "float"
typeLabel TString         = "string"
typeLabel TBool           = "bool"
typeLabel TUnit           = "unit"
typeLabel (TBytes n)      = "bytes[" <> tshow n <> "]"
typeLabel (TList t)       = "list[" <> typeLabel t <> "]"
typeLabel (TMap k v)      = "map[" <> typeLabel k <> "," <> typeLabel v <> "]"
typeLabel (TResult t e)   = "Result[" <> typeLabel t <> "," <> typeLabel e <> "]"
typeLabel (TPair a b)     = "(" <> typeLabel a <> ", " <> typeLabel b <> ")"
typeLabel (TFn args ret)  = "fn[" <> tshow (length args) <> " args] -> " <> typeLabel ret
typeLabel (TPromise t)    = "Promise[" <> typeLabel t <> "]"
typeLabel (TDependent _ b _)= typeLabel b <> " (constrained)"
typeLabel TDelegationError = "DelegationError"
typeLabel (TVar n)        = n
typeLabel (TCustom n)     = n
typeLabel (TSumType ctors) = T.intercalate " | " (map fst ctors)

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
-- @Nothing@   → anonymous step (former DoExpr; state component discarded)
-- @Just name@ → named step     (former DoBind; state component bound)
data DoStep = DoStep (Maybe Name) Expr
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
  | HProofRequired Text           -- ^ ?proof-required, reason tag e.g. "complex-decreases", "non-linear-contract", "manual"
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
  { contractPre        :: Maybe Expr   -- ^ Precondition (must evaluate to bool)
  , contractPreSource  :: Maybe Text   -- ^ v0.6: :source annotation for pre clause
  , contractPost       :: Maybe Expr   -- ^ Postcondition (must evaluate to bool)
  , contractPostSource :: Maybe Text   -- ^ v0.6: :source annotation for post clause
  } deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Evidence Model (v0.8.1b — Diamond Lattice)
-- ---------------------------------------------------------------------------

-- | Evidence tier for a contract clause. Partial order, not total.
-- DLContractChecked and DLTested are incomparable — there is no Ord instance.
--
-- Lattice structure:
--          DLVerified
--         /          \
-- DLContractChecked  DLTested
--         \          /
--          DLAsserted
data DisplayLevel
  = DLAsserted                             -- ^ Runtime assertion only; no evidence
  | DLTested   { dlSamples :: Int }       -- ^ QuickCheck passed N samples
  | DLContractChecked { dlProver :: Text } -- ^ SMT proved contract consistency (not body)
  | DLVerified { dlVerProver :: Text }    -- ^ SMT proved body satisfies contract
  deriving (Show, Eq, Generic)

-- | Structured evidence record for a single contract clause.
-- OBLIG-PBT-3: 'erPbtWitnesses' records property-body hashes that contributed
-- to a 'DLTested n' lift. Used by 'TrustReport.buildTrustReport' on read to
-- downgrade stale entries (property edited / deleted) to 'DLAsserted'. Empty
-- for non-PBT evidence (verifier-written, :trust tested source markers).
data EvidenceRecord = EvidenceRecord
  { erDisplayLevel :: DisplayLevel   -- ^ What kind of evidence backs this clause
  , erBodyFaithful :: Bool           -- ^ True when body VC was generated and passed
  , erSource       :: Maybe Text     -- ^ :source provenance annotation
  , erPbtWitnesses :: [PbtWitness]   -- ^ OBLIG-PBT-3: PBT property-body provenance
  } deriving (Show, Eq, Generic)

-- | OBLIG-PBT-3: SHA-256 hash + description of a property body whose
-- 'PBTPassed' run lifted a contract clause to 'DLTested n'. Hash is taken
-- over the canonical 'Expr' serialization of 'propBody' (see
-- 'LLMLL.PBT.canonicalPropBodyHash'). 'buildTrustReport' validates on read
-- against live property bodies and downgrades stale entries.
data PbtWitness = PbtWitness
  { pwHash        :: Text   -- ^ \"sha256:\" + 64 hex chars
  , pwDescription :: Text   -- ^ propDescription at write time, for display
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
-- Incomparable elements (DLContractChecked ⊓ DLTested) meet at DLAsserted.
evidenceMeet :: DisplayLevel -> DisplayLevel -> DisplayLevel
-- Bottom absorbs
evidenceMeet DLAsserted _            = DLAsserted
evidenceMeet _ DLAsserted            = DLAsserted
-- Same constructor, different metadata: conservative choice
evidenceMeet (DLVerified p1) (DLVerified _)               = DLVerified p1
evidenceMeet (DLContractChecked p1) (DLContractChecked _)  = DLContractChecked p1
evidenceMeet (DLTested n1) (DLTested n2)                   = DLTested (min n1 n2)
-- Verified is top
evidenceMeet (DLVerified _) b        = b
evidenceMeet a (DLVerified _)        = a
-- Incomparable: contract-checked ⊓ tested = asserted
evidenceMeet DLContractChecked{} DLTested{} = DLAsserted
evidenceMeet DLTested{} DLContractChecked{} = DLAsserted

-- | Does evidence level @a@ cover requirement @b@?
-- a covers b iff a is at least as high in the lattice as b.
-- For DLTested, sample counts are metadata — DLTested n covers DLTested m for any n, m.
evidenceCovers :: DisplayLevel -> DisplayLevel -> Bool
evidenceCovers (DLVerified _) _              = True   -- top covers everything
evidenceCovers _ (DLVerified _)              = False  -- only verified covers verified
evidenceCovers _ DLAsserted                  = True   -- everything covers bottom
evidenceCovers DLAsserted _                  = False  -- bottom covers only bottom
evidenceCovers (DLContractChecked _) (DLContractChecked _) = True
evidenceCovers (DLTested _) (DLTested _)     = True
-- Incomparable: contract-checked vs tested
evidenceCovers DLContractChecked{} DLTested{} = False
evidenceCovers DLTested{} DLContractChecked{} = False

-- | Is this verified-level evidence (body-faithful SMT proof)?
isVerifiedLevel :: DisplayLevel -> Bool
isVerifiedLevel DLVerified{} = True
isVerifiedLevel _            = False

-- | True when evidence includes a solver-backed proof (contract or body).
-- Does NOT imply a total ordering — DLTested is incomparable, not "below".
isSolverBacked :: DisplayLevel -> Bool
isSolverBacked DLVerified{}        = True
isSolverBacked DLContractChecked{} = True
isSolverBacked _                   = False

-- | Extract prover name, if any.
dlProverName :: DisplayLevel -> Maybe Text
dlProverName (DLVerified p)        = Just p
dlProverName (DLContractChecked p) = Just p
dlProverName _                     = Nothing

-- | Human display label for a display level.
dlLabel :: DisplayLevel -> Text
dlLabel DLAsserted            = "asserted"
dlLabel (DLTested n)          = "tested (" <> tshow n <> " samples)"
dlLabel (DLContractChecked p) = "contract-checked (" <> p <> ")"
dlLabel (DLVerified p)        = "verified (" <> p <> ")"

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

data Statement
  = SDefLogic
    { defLogicName   :: Name
    , defLogicParams :: [(Name, Type)]
    , defLogicReturn :: Maybe Type
    , defLogicContract :: Contract
    , defLogicBody   :: Expr
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
    , defMainRead   :: Maybe Expr     -- ^ :read  (console/cli only)
    , defMainDone   :: Maybe Expr     -- ^ :done? (console only)
    , defMainOnDone :: Maybe Expr     -- ^ :on-done (optional)
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

-- | Selects the runtime harness template generated by the compiler.
data EntryMode
  = ModeConsole                -- ^ stdin/stdout interactive loop
  | ModeCli                    -- ^ single-shot from OS args
  | ModeHttp { httpPort :: Int } -- ^ hyper/tokio HTTP server
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

data Import = Import
  { importPath        :: Name                  -- ^ e.g. "wasi.filesystem"
  , importInterface   :: Maybe [(Name, Type)]  -- ^ Optional interface spec
  , importCapability  :: Maybe Capability      -- ^ Required capability grant
  } deriving (Show, Eq, Generic)

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
  } deriving (Show)

-- | In-memory module cache: populated by post-order DFS load, read by
-- type-checker and codegen.  Empty for single-file inputs (full backward compat).
type ModuleCache = Map ModulePath ModuleEnv
