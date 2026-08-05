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
    -- FQ-RESULT-SORT-1: report + tau_ret (effective return type per definition)
  , typeCheckStrictWithCacheAndStatusRet
  , typeCheckWithCacheRet
  , runSketch
    -- * Environment
  , TypeEnv
  , builtinEnv
    -- XMOD-CTOR-1: Module.buildModuleEnv needs the same constructor bindings the
    -- local checker installs, so an importer can CONSTRUCT a value of an
    -- imported sum type and not merely match one.
  , collectConstructors
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
    -- ADMIT-SHARED: seeded variant, so a direct 'structuralUnify' test over an
    -- ALIASED fact-asserting type exercises a LIVE admissibility guard rather
    -- than one disabled by an empty 'tcAliasMap' (SA-19).
  , runTCWithAliases
    -- ADMIT-SHARED: exported so property A2 (@admits am (expandAlias t) ==
    -- admits am t@) tests the REAL expansion the call sites run, not a
    -- re-statement of it that could drift.
  , expandAlias
  , occursIn
  , TC
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe, fromMaybe, isJust)
import Data.List (nub, (\\))
import qualified Data.Set as Set
import Control.Monad (forM_, forM, foldM, when, unless, void)
import LLMLL.InvariantRegistry (InvariantPattern, InvariantSuggestion(..), matchPatterns)
import Control.Monad.State.Strict

import LLMLL.Syntax
import LLMLL.Diagnostic
-- ADMIT-SHARED: the type-admissibility predicate the emitter's fact-injection
-- gates are built from. Importing it here (rather than mirroring it) is what
-- makes CR-01's defect class — checker guarding a narrower set than the emitter
-- asserts for — unrepresentable. Leaf module; no cycle with FixpointEmit, which
-- this module does not import.
import LLMLL.TypeAdmissibility (AliasMap, builtinAliases, sealedTypeNames, wildAssumeRejects, bytesLenOf, boolValuedMapTy, jsonTypeName, mentionsJson)
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
  -- FS-COPY-1. Byte-faithful copy, delivering RNone. No new Response arm and no
  -- new capability namespace: extractWasiNamespace takes the first two segments,
  -- so this lands under the existing `wasi.fs` capability with exactly the
  -- authority the read/write pair already grants. It exists because the text
  -- channel LOSES bytes that are not valid UTF-8, so read-then-write cannot
  -- express a copy of a binary artifact at all (measured: RErr on byte 0xFF
  -- under UTF-8). Design record: `docs/design/driver-ll-phase4-proposal.md` §8.
  , ("wasi.fs.copy",       TFn [TString, TString] (TCustom "Command"))
  -- CAP-PROC (first operation, pulled forward into EFFECT-RESP's release): a
  -- directory listing. It is here rather than in Phase 2 because it is the sole
  -- producer of the RList arm below, and an arm no command can produce would be
  -- declared surface with no runtime.
  --
  -- CAP-1 does NOT discriminate the capability verb. checkWasiCapability tests
  -- `importPath imp == ns` and never reads importCapability, so this name lands
  -- with exactly the authority wasi.fs.read has today and `(capability list …)`
  -- would parse (Parser.hs pCapKind's CapCustom fallthrough) and be ignored.
  -- Deliberately not faked here; routed as CAP-1-REAL.
  , ("wasi.fs.list",       TFn [TString] (TCustom "Command"))
  -- CAP-PROC Phase 2, four operations. Each has a runtimePreamble body and a
  -- primEffect clause landing ABOVE ObligationAssembly's `wasi.` fallthrough;
  -- without the clause each would silently report ⊤ and every caller's
  -- effect_summary would go vacuous (primEffect is exported for exactly that
  -- regression).
  --
  -- wasi.proc.run is exec/argv, NOT a shell string. The split is what makes the
  -- executable a syntactic constant a reader can enumerate from the module
  -- header; it removes shell metacharacter interpretation as a category. It
  -- BOUNDS NOTHING: the argument vector is unconstrained, and where the granted
  -- program interprets its arguments as instructions the authority delivered
  -- through argv is unbounded. The property is auditability, not authority
  -- bounding, and no capability check is enforced here (CAP-1-REAL).
  -- Parameters: executable, argv, cwd, stdout path, stderr path, timeout secs.
  -- The timeout is in the signature because a budget overrun must be a value
  -- (RErr), not a hang.
  , ("wasi.proc.run",      TFn [TString, TList TString, TString, TString, TString, TInt]
                               (TCustom "Command"))
  -- PROC-BOUNDARY-1 half one: the process argument vector.
  --
  -- Nullary, so it binds as a VALUE (the wasi.clock.monotonic shape below), and
  -- it lands on the EXISTING RList arm rather than a sixth one. CAP-PROC's
  -- admissibility rule states that needing a new arm is the signal EFFECT-RESP's
  -- arm set was wrong; a vector of strings is what RList already carries, so
  -- there is nothing to admit and the Response sum does not move.
  --
  -- Namespace is wasi.proc (extractWasiNamespace takes the first two segments),
  -- so it rides the capability import wasi.proc.run already opens. As with every
  -- other name here, CAP-1 does not discriminate the verb (CAP-1-REAL).
  --
  -- It needs NO grammar and NO def-main change: RC-3 already routes :init's
  -- command into the first response (CodegenHs.hs:1594-1597), so a program that
  -- wants argv issues this as :init's command and matches RList on r0. :init's
  -- arity does not move, so every shipped console program keeps working.
  , ("wasi.proc.args",     TCustom "Command")
  -- Nullary: binds as a VALUE, not a 0-arg function, matching the RNone
  -- convention below and COMP-3b-general's treatment of nullary constructors.
  , ("wasi.clock.monotonic", TCustom "Command")
  , ("wasi.fs.mkdir",      TFn [TString] (TCustom "Command"))
  -- Takes a PATH, not bytes, and hashes inside the sealed builtin. It cannot be
  -- a pure `sha256 : bytes[n] -> ...` on the sha1 precedent: bytes[n] needs a
  -- literal length at the type level and a file's length is not statically
  -- known (effect-response-channel-proposal.md:402-404, the same reason there
  -- is no RBytes arm). Reading via wasi.fs.read first would hash decoded TEXT,
  -- not the file's bytes, and the driver uses this digest as a resume gate.
  , ("wasi.fs.sha256",     TFn [TString] (TCustom "Command"))
  , ("seq-commands",       TFn [TCustom "Command", TCustom "Command"] (TCustom "Command"))
  -- EFFECT-RESP (RC-1): the response channel's four constructors.
  --
  -- Response is COMPILER-SUPPLIED, not program-declared, because the response
  -- alphabet is a function of the COMMAND alphabet and the command alphabet is
  -- sealed in this very list (§13.9 above). A program cannot introduce a
  -- command, so it cannot need an arm; program-declaration would admit dead
  -- arms no command produces and omit arms some command does.
  --
  -- The arms' TYPE (the four-way sum) lives in 'builtinAliases' below, not
  -- here: this map is the VALUE namespace. Both are needed. Without the value
  -- bindings '(RText "x")' is an unknown function; without the alias entry
  -- 'checkExhaustive' cannot see the constructor set and a 'match' missing an
  -- arm passes silently.
  --
  -- Nullary RNone binds as a VALUE rather than a 0-arg function, matching the
  -- COMP-3b-general convention 'collectConstructors' applies to user sum types.
  , ("RNone",              TCustom "Response")
  , ("RText",              TFn [TString] (TCustom "Response"))
  , ("RCode",              TFn [TInt]    (TCustom "Response"))
  , ("RErr",               TFn [TString] (TCustom "Response"))
  -- Fifth arm, settled Rev 5. Sole producer is wasi.fs.list above. A listing is
  -- the one Phase 2 result shape that fails the file-indirection test: it cannot
  -- be persisted and re-read without inventing a delimiter, and a filename may
  -- contain a newline.
  , ("RList",              TFn [TList TString] (TCustom "Response"))
  -- §13.11 Cryptographic operations (v0.6.1)
  -- Opaque primitives backed by real Haskell crypto in preamble.
  -- Correctness is outside the decidable fragment — classified as Asserted.
  , ("hmac-sha1",          TFn [TBytes 20, TBytes 20] (TBytes 20))
  , ("sha1",               TFn [TBytes 20] (TBytes 20))
  -- §13.12 Bytes / map operations (Lever A stage A0).
  -- Typing is special-cased in inferArrayOp (a bytes[n] length is an Int, not
  -- a type variable, and map keys carry the v1 int-only gate — neither is
  -- expressible as a TVar signature). These entries serve name-membership
  -- (callee admissibility, brief/report vocabulary) and map-empty's fully
  -- generic constructor path. Verification-inert at this stage: none of these
  -- names is reflected by FixpointEmit, so bodies/contracts mentioning them
  -- take today's fallback routing unchanged.
  , ("bytes-length", TFn [TVar "bs"] TInt)
  , ("bytes-get",    TFn [TVar "bs", TInt] TInt)
  , ("bytes-set",    TFn [TVar "bs", TInt, TInt] (TVar "bs"))
  , ("bytes-zero",   TFn [] (TVar "bs"))
  , ("map-has",      TFn [TMap (TVar "k") (TVar "v"), TVar "k"] TBool)
  , ("map-get",      TFn [TMap (TVar "k") (TVar "v"), TVar "k"] (TVar "v"))
  , ("map-put",      TFn [TMap (TVar "k") (TVar "v"), TVar "k", TVar "v"] (TMap (TVar "k") (TVar "v")))
  , ("map-empty",    TFn [] (TMap (TVar "k") (TVar "v")))
  -- §13.13 JSON (JSON-1). Thirteen operations over a SEALED OPAQUE carrier.
  --
  -- 'Json' is TCustom jsonTypeName with NO builtinAliases entry, deliberately:
  -- it has no TSumType body, it never resolves, and it lowers to an opaque FQ
  -- sort exactly as list[a] lowers to Lst (FixpointEmit.hs:2419). No name below
  -- is reflected by FixpointEmit, so a body or contract mentioning one takes
  -- today's fallback routing unchanged -- the bytes/map precedent above.
  --
  -- Every one of these is in 'coreExcludedBuiltins': def-shell only. The reason
  -- is NOT opacity. Measured, a `def` matching a list-carrying datatype arm also
  -- lands at body-fallback (FixpointEmit.hs:2500, "the deliberate final
  -- boundary"), so a matchable seven-constructor Json would produce the same
  -- verdict. What the exclusion buys FOR THIS POPULATION is that the fallback
  -- is explicit at the type-check gate instead of silent at the emitter.
  --
  -- READ THAT AS SCOPED TO json-/wasi., NOT AS A GENERAL PRINCIPLE. It holds
  -- here because the fallback is unconditional for these names: a `def`
  -- touching JSON structure falls back under any encoding. It does NOT
  -- generalize to the rest of 'builtinEnv', and reading it as though it did
  -- produces a finding that does not survive measurement (it was filed once).
  -- At v0.14.82, 37 of builtinEnv's 93 names are outside both json-/wasi. and
  -- FixpointEmit's reflected set, so a `def` calling one falls back with no
  -- check-time diagnostic -- and FIVE of them are in 'trustedPrelude' by
  -- deliberate design: 'list-head', 'list-tail', 'string-concat',
  -- 'int-to-string' and 'pair' each land a caller at body-fallback, measured.
  -- 'trustedPrelude' is a CORE-MEMBERSHIP set, not a body-faithfulness set;
  -- ':778' says so ("no body-faithful VC required"). Admission and
  -- body-faithfulness were never coupled.
  --
  -- What actually gates the fallback is composition, not names. The moment a
  -- fallback `def` is CALLED from another `def`, 'checkCalleeAdmissibility'
  -- rejects the caller at `llmll check`, cold, exit 1, via
  -- 'mkCoreMembershipViolation' (':887'). Only a LEAF that nothing calls is
  -- undiagnosed, and it is in no trust closure by construction;
  -- '--strict-verified-core' covers even that, totally, over all 37 rather
  -- than over a hand-listed few. Do not "fix" the gap by adding list-filter /
  -- list-map / list-fold here: that gates 3 of 37 and implies the other 34 are
  -- covered.
  --
  -- NUMBERS ARE LEXEMES. json-parse stores a number's source text and
  -- json-serialize emits it unchanged, so no float ever enters the surface and
  -- no float-formatting rule is owed. json-get-int is strict on "1.0": it
  -- denotes an integral value but is not an integer lexeme, and silent
  -- narrowing is the worse failure.
  , ("json-parse",      TFn [TString] (TResult (TCustom jsonTypeName) TString))
  , ("json-serialize",  TFn [TCustom jsonTypeName] TString)
  , ("json-get",        TFn [TCustom jsonTypeName, TString]
                            (TResult (TCustom jsonTypeName) TString))
  , ("json-get-string", TFn [TCustom jsonTypeName, TString] (TResult TString TString))
  , ("json-get-int",    TFn [TCustom jsonTypeName, TString] (TResult TInt TString))
  , ("json-get-bool",   TFn [TCustom jsonTypeName, TString] (TResult TBool TString))
  -- Returns the number's SOURCE LEXEME as a string, which is the only
  -- observation of a non-integral number the surface offers. Rev 3 dropped this
  -- on the ground that the ported spine reads no float; that is true of stage E
  -- as a stage and false of Phase 3's acceptance clause, which reproduces
  -- self_test()'s six pinned results and four of them are floats
  -- (rfc_to_implementation.py:1405-1409). Without it the LLMLL driver can
  -- produce the artifact but not check it, and the check falls back to Python.
  --
  -- The lexeme, not a float: comparing against a literal is then STRLIT string
  -- equality, which reflects into Sigma_auto, where float equality does not
  -- (LLMLL.md:289). The acceptance check lands inside the fragment.
  , ("json-get-number", TFn [TCustom jsonTypeName, TString] (TResult TString TString))
  , ("json-array",      TFn [TCustom jsonTypeName]
                            (TResult (TList (TCustom jsonTypeName)) TString))
  -- Nullary: binds as a VALUE, not a 0-arg function, matching wasi.clock.monotonic
  -- and RNone above and COMP-3b-general's treatment of nullary constructors.
  , ("json-object",     TCustom jsonTypeName)
  , ("json-set",        TFn [TCustom jsonTypeName, TString, TCustom jsonTypeName]
                            (TResult (TCustom jsonTypeName) TString))
  -- Four MONOMORPHIC injections rather than one polymorphic `json-of : a -> Json`:
  -- a TVar signature would unify with Command -> Json and Json -> Json.
  , ("json-of-string",  TFn [TString] (TCustom jsonTypeName))
  , ("json-of-int",     TFn [TInt] (TCustom jsonTypeName))
  , ("json-of-bool",    TFn [TBool] (TCustom jsonTypeName))
  , ("json-of-list",    TFn [TList (TCustom jsonTypeName)] (TCustom jsonTypeName))
  ]

emptyEnv :: TypeEnv
emptyEnv = builtinEnv

-- EFFECT-RESP: the TYPE half of the sealed 'Response' (its four-arm 'TSumType'
-- body) lives in 'LLMLL.TypeAdmissibility.builtinAliases', imported above,
-- because 'FixpointEmit' needs the same entry and imports TypeAdmissibility but
-- not this module. It is seeded into 'tcAliasMap' at every 'TCState'
-- construction site below.

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
  , shHyps    :: [Expr]     -- ^ OBLIG-1 v2b: match-scrutinee case hypotheses on the
                            -- hole's path, outermost match first (e.g. @(= s (Ctor x))@).
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
  , tcHyps           :: [Expr]         -- ^ OBLIG-1 v2b: match-scrutinee case
                                       -- hypotheses on the current path, innermost
                                       -- first (pushed by 'withHyp' at match-arm
                                       -- entry; snapshot reversed at 'recordHole').
  -- FQ-RESULT-SORT-1: the VERIFICATION-FACING effective return type per definition,
  -- tau_ret(f) = mRet |> bodyType. The type channel already binds 'result' at this
  -- type (the 'fromMaybe bodyType mRet' sites below); the contract channel used to
  -- re-derive it from the annotation alone and default to FQInt, which mis-sorted the
  -- 'result' binder for every unannotated non-int return. Recorded here so the emitter
  -- consumes the checker's answer instead of guessing. Appended at the END of the
  -- record on purpose: the three positional 'TCState' constructions below gain one
  -- trailing argument, which cannot silently swap with an adjacent same-typed field.
  -- NOT read by 'collectTopLevel' or 'Module.toExport' — routing it into the type
  -- environment would make pass 1 of 'checkStatements' depend on pass 2
  -- (docs/design/finding-fq-result-sort-default.md, the withdrawn Rev 1 row 1).
  , tcRetTypes       :: Map Name Type
  } deriving (Show)

type TC a = State TCState a

-- | FQ-RESULT-SORT-1: record a definition's effective return type
-- tau_ret(f) = mRet |> bodyType, for the contract channel to consume instead of
-- re-deriving the sort from the optional annotation. Called once per definition arm,
-- immediately after 'bodyType' is bound, so it fires whether or not a contract is
-- present. Safe under the scope helpers: 'withEnv' / 'withTaggedEnv' /
-- 'withFunctionContext' / 'withSegment' each restore only their own named fields,
-- never the whole state, so this write survives block exit.
recordRetType :: Name -> Type -> TC ()
recordRetType n t = modify $ \s -> s { tcRetTypes = Map.insert n t (tcRetTypes s) }

-- | Emit a type error.
tcError :: Text -> TC ()
tcError msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [mkError Nothing msg] }

-- | Emit a type error carrying a machine-readable 'diagKind'.
--
-- The kind is what a consumer (test, agent, editor) keys off; 'tcError' leaves
-- it Nothing, so an error emitted through it can only be matched on its prose.
tcErrorK :: Text -> Text -> TC ()
tcErrorK kind msg = modify $ \s -> s
  { tcErrors = tcErrors s ++ [(mkError Nothing msg) { diagKind = Just kind }] }

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

-- ADMIT-SHARED: the membership predicate this module used to carry
-- (@assumesFact@ \/ @assumesFactMapKey@ \/ @assumesFactBoolValue@) is gone. It was
-- a MIRROR of the emitter's fact-injection gates, and CR-01 was the two copies
-- disagreeing about 'TDependent'. The guard now calls
-- 'LLMLL.TypeAdmissibility.wildAssumeRejects', which is defined over
-- 'LLMLL.TypeAdmissibility.admits' plus
-- 'LLMLL.TypeAdmissibility.bytesLenOf' — the very functions
-- 'LLMLL.FixpointEmit' dispatches on when it decides to assert the fact. Not a
-- mirror: the same functions.
--
-- Three consequences worth stating here, because this is where a future arm gets
-- added:
--
--   * The guard is TOTAL on unnormalized input. It does not require its caller to
--     have run 'expandAlias' first. The call-site expansions below are retained
--     for the OTHER 'compatibleWith' clauses (nominal @TCustom a@ vs
--     @TCustom b@, structural recursion), which still need expanded input; they
--     are no longer what keeps this guard sound.
--
--   * It over-approximates: it ignores the emitter's per-function
--     activation gate ('FixpointEmit.arrGateActive'), which is a function of the
--     callee's BODY. That is deliberate (ADMIT-OVER, see the
--     'LLMLL.TypeAdmissibility' header) — the safe direction is to reject more
--     than the emitter asserts for, and consulting a body-dependent gate would
--     make type acceptance depend on a callee's body.
--
--   * Since FACT-AG-LEN Stage 3 the seams gate on 'wildAssumeRejects' rather than
--     on 'admits' itself. 'admits' is the SOUNDNESS set (types whose fact the
--     emitter injects unearned), now just @map[k,bool]@; 'wildAssumeRejects' adds
--     back the @bytes[n]@ arm for its DIAGNOSTIC value. A new arm that carries an
--     unearned fact belongs in 'admits' and reaches the seams for free; an arm
--     that is only worth a better error message belongs in 'wildAssumeRejects'.

-- | SAFE-ARG: the bare inference wildcard produced by 'collectTopLevel' for an
-- unannotated return, as distinct from two other TVar populations that must NOT
-- be rejected:
--
--   * a NAMED hole — 'inferHole' returns @TVar ("?" <> name)@ — sketch mode;
--   * a POLYMORPHIC builtin variable — @TVar "bs"@ (bytes-set/bytes-zero),
--     @TVar "k"@ \/ @TVar "v"@ (map-empty) — whose absorption is how the calling
--     context determines the component types.
--
-- 'isHoleVar' would fire on named holes, and a catch-all @TVar _@ pattern would
-- reject every @(map-empty)@ at a typed map position (finding Rev 1, edge cases
-- 8 and 9), so neither is usable.
--
-- TRAP: exact equality with @"?"@ is ALSO wrong, and looks right.
-- 'freshenFnType' (BUG-3, v0.14.3, ':1935-1960') alpha-renames every TVar in a
-- callee's signature at each call site as @v <> "$" <> counter@ (':2117'), so an
-- unannotated return arrives at the use site as @TVar "?$0"@, never @TVar "?"@.
-- Measured: with an exact-equality guard the rule was completely dead, and
-- @bad4@ reported @got ?$0@ once the name check was relaxed. Match the bare
-- wildcard and its freshened instances, and nothing else.
isBareWildcard :: Type -> Bool
isBareWildcard (TVar n) = n == "?" || "?$" `T.isPrefixOf` n
isBareWildcard _        = False

-- | SAFE-ARG / WILD-ASSUME (stage 3): the noun phrase naming the fact
-- 'LLMLL.TypeAdmissibility.wildAssumeRejects' refused, used by
-- 'tcWildAssumeError' so the rejection describes what it refused instead of a
-- hardcoded bytes-only wording. The noun is per class, not per call site,
-- because the two arms name different facts.
--
-- FACT-AG-LEN Stage 3 reworded the bytes arm. A @bytes[n]@ value's length is no
-- longer a fact the emitter ASSERTS from the declaration: it is earned, at the
-- call site from the effective pre ('FixpointEmit.bytesLenParamPre') and in the
-- body VC from the effective post ('FixpointEmit.bytesLenRetPost'). What the
-- laundering hop breaks is therefore the PROOF of the length, not a premise, so
-- the noun says "a length to prove". The @map[k,bool]@ arm is unchanged and is
-- still an asserted premise: the @0 \<= select(m$val,k) \<= 1@ range that
-- 'FixpointEmit.injectBoolValRangeFacts' injects from the declared value type, a
-- per-key value RANGE, not a length -- reusing the bytes wording for it would
-- describe the wrong fact. Total: the fallback covers any future arm this
-- function has not been taught yet, rather than making the diagnostic partial.
--
-- ADMIT-SHARED: the arms dispatch on the same two gates 'wildAssumeRejects' is
-- defined over, so a wrapped or aliased type gets its real noun without a
-- 'TDependent' clause of its own — the gates strip and resolve. Previously this
-- function carried a hand-written mirror of that traversal, which is the shape
-- of duplication CR-01 came from.
-- Each arm carries its own verb, because the two facts now reach the solver by
-- different routes: the bytes length is PROVED (an obligation on this position),
-- the map range is ASSERTED (a premise from the declaration). One shared verb
-- would have to be wrong about one of them.
wildAssumeFactNoun :: AliasMap -> Type -> Text
wildAssumeFactNoun am t
  | isJust (bytesLenOf am t) = "a length the verifier must prove at this position"
  | boolValuedMapTy am t     = "a per-key value range that the verifier asserts"
                               <> " from the declaration"
  | otherwise                = "a fact that the verifier asserts from the declaration"

-- | SAFE-ARG: structured rejection for WILD-ASSUME. Carries the same
-- @diagKind@\/@diagExpected@\/@diagGot@ triple as 'tcTypeMismatch' so JSON
-- consumers see a normal type mismatch, plus the remedy in the message: the
-- fix is always to annotate the callee's return type. 'diagHoleSensitive' is
-- deliberately left False — this error does not disappear when a hole resolves
-- (the D3 invariant), because there is no hole involved.
-- Two type arguments, deliberately: @labelTy@ is the type as the user wrote it,
-- so the diagnostic keeps the alias name (Fix 1b), while @resolvedTy@ is the
-- form the guard actually ran 'LLMLL.TypeAdmissibility.wildAssumeRejects' on.
-- The noun must come from the resolved form: naming the fact is the whole point
-- of 'wildAssumeFactNoun', and reading it off an unexpanded 'TCustom' used to
-- degrade every aliased rejection to the generic "a fact" fallback (WR-01,
-- phase 01 review). ADMIT-SHARED makes that degradation impossible rather than
-- merely fixed — the noun's gates resolve aliases themselves — but the two
-- arguments stay, because the LABEL must not be resolved.
tcWildAssumeError :: Text -> Type -> Type -> TC ()
tcWildAssumeError ctx labelTy resolvedTy = do
  am <- gets tcAliasMap
  let msg = "type mismatch in '" <> ctx <> "': expected " <> typeLabel labelTy
              <> ", got ? (an unannotated return type). A " <> typeLabel labelTy
              <> " value carries " <> wildAssumeFactNoun am resolvedTy
              <> ", and inference cannot supply it; annotate the"
              <> " callee's return type."
  modify $ \s -> s
    { tcErrors = tcErrors s ++
        [ (mkError Nothing msg)
            { diagKind     = Just "type-mismatch"
            , diagExpected = Just (typeLabel labelTy)
            , diagGot      = Just "?"
            } ] }

-- | RET-BRANCH-PREF Stage 1: at an 'if' join, prefer the CONCRETE branch's type when
-- the other branch is a SELF-RECURSIVE call that synthesized the '?' wildcard.
--
-- 'inferExpr (EIf ...)' otherwise returns 'thenType' unconditionally, so a wildcard
-- then-branch silently wins over a concrete else-branch. In the self-recursive case the
-- wildcard IS the enclosing function's own return type (collectTopLevel registers an
-- unannotated return as 'TVar "?"'), and the concrete branch is DETERMINING it, so
-- preferring the concrete branch is a least-fixpoint step rather than a guess. That is
-- the standard treatment of a recursive binding (Milner 1978; Damas-Milner POPL 1982).
--
-- The self-recursion side condition is what makes this a derivation, and it is NOT
-- cosmetic. Dropping it (proposal Stage 2) would also fire when the wildcard comes from
-- a call to some OTHER unannotated function, where the concrete branch does not
-- determine the callee's return type and preferring it is an unchecked assumption.
-- A wildcard return is idiomatic, not exceptional: 104 unannotated def heads corpus-wide,
-- 72 alongside another unannotated callee. Stage 2 is gated on measurement; see
-- docs/design/ret-branch-pref-proposal.md.
--
-- Conservative by construction: only a bare 'EApp' whose head is the enclosing function
-- matches, so a self-call reached through 'let' or wrapped in an operator declines and
-- the pre-existing behaviour stands.
preferConcreteOnSelfCall
  :: Maybe Name   -- ^ enclosing definition ('tcCurrentFn')
  -> Expr -> Type -- ^ then-branch expression and its synthesized type
  -> Expr -> Type -- ^ else-branch expression and its synthesized type
  -> Type
preferConcreteOnSelfCall mFn thenE thenTy elseE elseTy
  | isSelfCall thenE, isHoleVar thenTy, not (isHoleVar elseTy) = elseTy
  | isSelfCall elseE, isHoleVar elseTy, not (isHoleVar thenTy) = thenTy
  | otherwise                                                  = thenTy
  where
    isSelfCall (EApp f _) = Just f == mFn
    isSelfCall _          = False

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
  oldHyps <- gets tcHyps
  let newProv = foldr (\(n, _) acc -> Map.insert n source acc) oldProv bindings
      -- OBLIG-1 v2b shadow guard: a stacked case hypothesis that mentions a name
      -- rebound here would, at a deeper hole, refer to the NEW binding — drop it
      -- for the duration (conservative: dropping only loses completeness).
      boundNames = map fst bindings
      liveHyps = [ h | h <- oldHyps, not (any (`exprContainsVar` h) boundNames) ]
  modify $ \s -> s
    { tcEnv = foldr (uncurry Map.insert) oldEnv bindings
    , tcProvenance = newProv
    , tcHyps = liveHyps
    }
  result <- action
  modify $ \s -> s { tcEnv = oldEnv, tcProvenance = oldProv, tcHyps = oldHyps }
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

-- | OBLIG-1 v2b: push a match-scrutinee case hypothesis for the duration of an
-- action (the arm body), so a hole inside it captures the hypothesis in its
-- 'shHyps'. Save/restore like 'withDefs'; identity when there is no renderable
-- hypothesis. Must run INSIDE the arm's 'withTaggedEnv' so the shadow guard
-- (which drops hypotheses mentioning rebound names) never sees the arm's own
-- hypothesis — its binder references are to the arm's fresh bindings.
withHyp :: Maybe Expr -> TC a -> TC a
withHyp Nothing action = action
withHyp (Just h) action = do
  oldHyps <- gets tcHyps
  modify $ \s -> s { tcHyps = h : oldHyps }
  result <- action
  modify $ \s -> s { tcHyps = oldHyps }
  pure result

-- | OBLIG-1 v2b: the renderable case hypothesis for one match arm, or Nothing.
-- Rendering follows the contract-vocabulary conventions the examples already
-- use in posts: a payload arm is a constructor application, @(= s (Ctor x))@;
-- a nullary arm is the bare constructor value, @(= s Ctor)@ (as in
-- @(= sig Continue)@ — nullary ctors appear bare in contract position).
--
-- Sound-but-incomplete by design (the accepted OBLIG-1 bar): only an 'EVar'
-- scrutinee with an all-'PVar' constructor pattern is rendered. A complex
-- scrutinee (call/op — its value has no name at the hole), a wildcard or
-- variable or literal arm, and a nested sub-pattern are all skipped silently.
matchHypothesis :: Expr -> Pattern -> Maybe Expr
matchHypothesis (EVar s) (PConstructor c args) =
  case mapM patVar args of
    Just [] -> Just (EApp "=" [EVar s, EVar c])
    Just ns -> Just (EApp "=" [EVar s, EApp c (map EVar ns)])
    Nothing -> Nothing
  where
    patVar (PVar n) = Just n
    patVar _        = Nothing
matchHypothesis _ _ = Nothing

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
  , "int-to-string"
  ]
-- R-13: every name above carries a 'builtinEnv' type. 'random-int' sat on this
-- list without one, so a call to it passed core-membership on the strength of
-- the entry alone and was then rejected downstream as an unknown function.
-- Keep that invariant: do not add a name here that builtinEnv does not declare.

-- | CORE-EXCL (JSON-1): builtins that are 'def-shell'-only.
--
-- 'checkCalleeAdmissibility' admitted every 'builtinEnv' member unconditionally,
-- which is why 'LLMLL.md':454's claim that the typechecker enforces @def-shell@
-- for functions that "perform IO via @wasi.*@" was false: measured at v0.14.81,
-- @(def make-read [p: string] (wasi.fs.read p))@ passed @llmll check@.
--
-- Two populations, one mechanism:
--
--   * @json-*@ -- a `def` touching JSON structure lands at body-fallback under
--     ANY encoding (FixpointEmit.hs:2500 firewalls the list carrier), so the
--     exclusion does not lose verification power. It converts a silent emitter-
--     side degradation into an explicit check-time diagnostic.
--
--   * @wasi.*@ -- makes the existing spec sentence true. Blast radius measured
--     across examples\/, scripts\/, tools\/, compiler\/test\/, docs\/: __0 of 303__
--     `def`-form functions mention a @wasi.@ name.
--
-- Membership is by NAME, not by type. A `Json`-typed binder with no operation
-- applied to it stays admissible and stays body-faithful: its sort is opaque,
-- no axiom mentions it, and it cannot affect a VC's satisfiability -- the same
-- reason a @list[a]@ parameter is admissible today. The rule bounds operations,
-- not values. Equality is the one operation that reaches a value without naming
-- it, and JSON-NOEQ ('inferExpr' EOp\/EApp) covers that separately.
coreExcludedBuiltins :: Set.Set Name
coreExcludedBuiltins =
  Set.filter (\n -> "json-" `T.isPrefixOf` n || "wasi." `T.isPrefixOf` n)
             (Map.keysSet builtinEnv)

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
        -- CORE-EXCL (JSON-1): the exclusion set is consulted BEFORE the
        -- builtinEnv leg, so a def-shell-only builtin is not admitted on the
        -- strength of having a type. Ordering matters: every excluded name is
        -- also a builtinEnv member, so testing membership first would admit
        -- all of them.
        excluded = func `Set.member` coreExcludedBuiltins
        trusted = not excluded
                  && (func `Set.member` trustedPrelude || Map.member func builtinEnv)
    am <- gets tcAliasMap   -- COMP-4 (a): admissible-sum constructors are admissible
    unless (not excluded && (persistedVerified || trusted || isAdmissibleConstructor am func)) $ do
      enclosing <- gets (maybe "<unknown>" id . tcCurrentFn)
      -- CORE-EXCL gets its OWN diagnostic: the membership message's remedy
      -- ("verify it first") is unreachable for a sealed builtin.
      let d = if excluded then mkCoreExcludedBuiltin enclosing func
                          else mkCoreMembershipViolation enclosing func
      modify $ \s -> s { tcErrors = tcErrors s ++ [d] }

-- | JSON-NOEQ (JSON-1): equality is denied at the sealed @Json@ carrier.
--
-- Three consumers, because @=@ and @!=@ are 'EOp' (Parser.hs:933-935) while
-- @list-contains@ is an ordinary 'EApp':
--
-- >  =  : TFn [TVar "a", TVar "a"] TBool
-- >  != : TFn [TVar "a", TVar "a"] TBool
-- >  list-contains : TFn [TList (TVar "a"), TVar "a"] TBool
--
-- @list-contains@ is the path a review of this design missed, and it is
-- reachable rather than hypothetical: @json-array@ produces exactly the
-- @list[Json]@ it consumes.
--
-- Denied rather than defined, for two reasons. Structural equality on any
-- representation makes representation detail (key order) observable program
-- behaviour, and equality at an opaque carrier silently drops a `def` from
-- body-faithful to fallback with no diagnostic -- measured on @Command@, the
-- nearest existing analogue, controlled against @int@ (faithful) and @string@
-- (fallback). The idiom for a program that needs it is
-- @(= (json-serialize a) (json-serialize b))@, where what is compared is stated.
--
-- Checked against the per-call-site substitution rather than the raw argument
-- types, so @Result[Json, string]@ and @list[Json]@ are caught by the same test
-- that catches a bare @Json@.
jsonEqConsumers :: Set.Set Name
jsonEqConsumers = Set.fromList ["=", "!=", "list-contains"]

checkJsonNoEq :: Name -> Map.Map Name Type -> TC ()
checkJsonNoEq name subst =
  when (name `Set.member` jsonEqConsumers) $ do
    am <- gets tcAliasMap
    when (any (mentionsJson am) (Map.elems subst)) $
      tcErrorK "json-equality-denied" $
        "'" <> name <> "' is not defined at type '" <> jsonTypeName
        <> "': equality on a sealed JSON value would expose member order as "
        <> "observable behaviour. Compare serializations instead: "
        <> "(= (json-serialize a) (json-serialize b))"

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

-- | The initial 'TCState', shared by the three entry points below.
--
-- Factored out with ADMIT-SHARED for one reason: the alias map is no longer
-- inert at the 'structuralUnify' seam. That seam reads 'tcAliasMap' to decide
-- admissibility, so an entry point that hardcodes 'Map.empty' silently DISABLES
-- the guard for anything it runs. Three positional 19-field constructions each
-- pinning that field to empty is how such a hole stays invisible.
-- EFFECT-RESP: 'builtinAliases' is unioned UNDER the caller's map here rather
-- than at each call site, for the same reason the constructor was factored out
-- in the first place: an entry point that misses the seed silently disables
-- Response exhaustiveness for everything it runs, and that is invisible from
-- the call site.
initialTCState :: GrammarMode -> TypeEnv -> AliasMap -> Bool -> Bool -> TCState
initialTCState gm env am sketch strict =
  TCState env [] (Map.union am builtinAliases) Nothing False sketch [] [] Map.empty Map.empty Map.empty []
          strict gm False 0 Map.empty [] Map.empty

-- | Run the type checker monad.
runTC :: GrammarMode -> TypeEnv -> TC a -> (a, [Diagnostic])
runTC gm env = runTCWithAliases gm env Map.empty

-- | Run the type checker monad with a pre-seeded alias environment.
--
-- ADMIT-SHARED: 'runTC' seeds an EMPTY 'tcAliasMap', which is correct for its
-- callers (whole-file entry points populate the map themselves in
-- 'checkStatements') but wrong for a direct 'structuralUnify' unit test over an
-- ALIASED fact-asserting type — @admits Map.empty (TCustom "BoolMap")@ is False,
-- so such a test would exercise a disabled guard and pass vacuously. This
-- project has shipped a dead WILD-ASSUME guard twice (the exact-@TVar "?"@
-- equality that made the first implementation completely dead, and CR-01's
-- narrower-than-the-emitter match); a third variant hiding in the test harness
-- is cheap to foreclose. SA-19 uses this entry point.
runTCWithAliases :: GrammarMode -> TypeEnv -> AliasMap -> TC a -> (a, [Diagnostic])
runTCWithAliases gm env am action =
  let (result, st) = runState action (initialTCState gm env am False False)
  in (result, tcErrors st)

-- | Run the type checker in sketch mode.
runTCSketch :: GrammarMode -> TypeEnv -> TC a -> (a, TCState)
runTCSketch gm env action = runState action (initialTCState gm env Map.empty True False)

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
    hyps <- gets tcHyps
    let delta = Map.difference env builtinEnv
        -- Build ScopeBinding map: join type from env with source from provenance,
        -- and (OBLIG-1 v2a) the let-binding RHS from tcDefs.
        -- Default to SrcLetBinding for bindings without explicit provenance
        -- (e.g. top-level definitions registered in checkStatements).
        scopedDelta = Map.mapWithKey (\k t ->
          ScopeBinding t (Map.findWithDefault SrcLetBinding k prov) (Map.lookup k defs)) delta
    -- OBLIG-1 v2b: tcHyps is innermost-first (a push stack); the brief reads
    -- outermost-first (path order), hence the reverse.
    modify $ \s -> s { tcHoles = SketchHole ("?" <> name) status ptr scopedDelta (reverse hyps) : tcHoles s }

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
  let (result, st) = runState action (initialTCState gm env Map.empty False True)
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

-- | FQ-RESULT-SORT-1: 'typeCheckStrictWithCacheAndStatus' plus tau_ret. Used by the
-- entry verify path, where the report and the emitter call sit in the same scope.
typeCheckStrictWithCacheAndStatusRet
  :: GrammarMode -> ModuleCache -> Map Name ContractStatus -> TypeEnv -> [Statement]
  -> (DiagnosticReport, Map Name Type)
typeCheckStrictWithCacheAndStatusRet gm = typeCheckWithCacheModeRet' gm True

-- | FQ-RESULT-SORT-1: 'typeCheckWithCache' plus tau_ret, for the module import path.
typeCheckWithCacheRet
  :: GrammarMode -> ModuleCache -> TypeEnv -> [Statement] -> (DiagnosticReport, Map Name Type)
typeCheckWithCacheRet gm cache = typeCheckWithCacheModeRet' gm False cache Map.empty

-- | Internal: shared implementation for typeCheckWith(Strict)Cache(WithMode).
typeCheckWithCacheMode :: GrammarMode -> Bool -> ModuleCache -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckWithCacheMode gm strict cache = typeCheckWithCacheMode' gm strict cache Map.empty

-- | Internal: as 'typeCheckWithCacheMode', plus an entry-file ContractStatus
-- seed (bare-keyed) unioned into 'tcContractStatus' (ADMIT-VERIFIED seam 6).
typeCheckWithCacheMode'
  :: GrammarMode -> Bool -> ModuleCache -> Map Name ContractStatus -> TypeEnv -> [Statement] -> DiagnosticReport
typeCheckWithCacheMode' gm strict cache entryCS baseEnv stmts =
  fst (typeCheckWithCacheModeRet' gm strict cache entryCS baseEnv stmts)

-- | FQ-RESULT-SORT-1: 'typeCheckWithCacheMode'' plus the recorded effective return
-- types (tau_ret per definition). This is the single shared implementation; the
-- report-only wrapper above discards the map, so all pre-existing callers keep their
-- signatures. Both consumers that need tau_ret route through here: the entry verify
-- path (via 'typeCheckStrictWithCacheAndStatusRet') and the module import path
-- (via 'typeCheckWithCacheRet', called at Module.hs:189 one line before the
-- ModuleEnv is built).
typeCheckWithCacheModeRet'
  :: GrammarMode -> Bool -> ModuleCache -> Map Name ContractStatus -> TypeEnv -> [Statement]
  -> (DiagnosticReport, Map Name Type)
typeCheckWithCacheModeRet' gm strict cache entryCS baseEnv stmts =
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
      -- EFFECT-RESP: 'builtinAliases' goes UNDER the imported ones, so a
      -- cached module can never displace a sealed type. This site does not
      -- route through 'initialTCState', so it needs its own union.
      seededAliases = Map.union (Map.foldl seedAliases Map.empty cache) builtinAliases
      (_, st) = runState (checkStatements stmts)
        (TCState seededEnv [] seededAliases Nothing False False [] [] seededCS Map.empty Map.empty [] strict gm False 0 Map.empty [] Map.empty)
      diags = tcErrors st
      hasErrors = any ((== SevError) . diagSeverity) diags
  in ( DiagnosticReport
         { reportPhase       = "typecheck"
         , reportDiagnostics = diags
         , reportSuccess     = not hasErrors
         }
     , tcRetTypes st
     )
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
  --
  -- ADMIT-SHARED: this stays a separate traversal from
  -- 'LLMLL.TypeAdmissibility.normalizeTy', deliberately. It computes the SET OF
  -- NAMES participating in a cycle (a normalizer computes no such set), and its
  -- TSumType policy is the OPPOSITE of the normalizer's: payloads are excluded
  -- here because a recursive ADT is legitimate, and included there because
  -- property A1 must hold at component positions. Both policies are right for
  -- their purpose; merging them would either red-line the recursive-ADT case
  -- below or open an A1 hole at sum-payload positions.
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
    -- XMOD-CTOR-2 / RESULT-CTOR-COLLIDE: a user sum type may not declare a
    -- constructor named Success or Error.
    --
    -- CodegenHs.rewriteCtor rewrites those two names to Right and Left
    -- UNCONDITIONALLY, with no knowledge of the declaring type, because
    -- Result[t,e] is emitted as Either e t. So `(type Outcome (| Error) ...)`
    -- silently emits a nullary user constructor as `Left`, and GHC then reports
    -- "The constructor 'Left' should have 1 argument, but has been given none".
    -- Found by building tools/llmll-driver/stage.llmll, which had type-checked
    -- and VERIFIED in that state since July: the corpus is check-only, so
    -- nothing had ever compiled it.
    --
    -- Rejecting here converts a silent miscompile into a check error. The
    -- principled fix is to thread the declaring type into rewriteCtor so user
    -- constructors are never confused with Result's; that is a codegen refactor
    -- and is filed rather than done here.
    forM_ (nub (map fst ctorBindings)) $ \ctorName ->
      when (ctorName `elem` (["Success", "Error"] :: [Name])) $
        tcErrorK "reserved-constructor-name" $
          "constructor '" <> ctorName <> "' is reserved: it is a Result[t,e] "
          <> "constructor and the code generator rewrites it to Haskell's "
          <> (if ctorName == "Success" then "Right" else "Left")
          <> " regardless of the declaring type. Rename it; a program using it "
          <> "type-checks and then fails to build."
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
  lintContractReads name params contract          -- CONTRACT-READ-LINT
  withFunctionContext name False $ do
    let paramBindings = params
    withTaggedEnv SrcParam paramBindings $ do
      -- Infer body type: push "body" segment for pointer precision
      bodyType <- withSegment "body" (inferExpr body)
      recordRetType name (fromMaybe bodyType mRet)   -- FQ-RESULT-SORT-1
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
      recordRetType name (fromMaybe bodyType mRet)   -- FQ-RESULT-SORT-1
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
  lintContractReads name params contract          -- CONTRACT-READ-LINT
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
        -- LEVER-A0: bytes-zero's v1 determining context — the full body under a
        -- declared literal '-> bytes[n]' return type. The length must be
        -- syntactically present (no alias expansion): codegen reads the same
        -- annotation to emit the n-length zero value, and the two ends must
        -- agree on when the construct is legal.
        (Just retTy@(TBytes _), EApp "bytes-zero" []) -> pure retTy
        (Just retTy, _)                -> do
          t <- withSegment "body" (inferExpr body)
          unify name retTy t
          pure t
        (Nothing, _)                   -> withSegment "body" (inferExpr body)
      recordRetType name (fromMaybe bodyType mRet)   -- FQ-RESULT-SORT-1
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
  lintContractReads name params contract          -- CONTRACT-READ-LINT
  withFunctionContext name False $ do
    withTaggedEnv SrcParam params $ do
      bodyType <- case (mRet, body) of
        (Just retTy, EHole (HNamed _)) -> retTy <$ withSegment "body" (checkExpr body retTy)
        -- LEVER-A0: same bytes-zero determining-context rule as the SDef site.
        (Just retTy@(TBytes _), EApp "bytes-zero" []) -> pure retTy
        (Just retTy, _)                -> do
          t <- withSegment "body" (inferExpr body)
          unify name retTy t
          pure t
        (Nothing, _)                   -> withSegment "body" (inferExpr body)
      recordRetType name (fromMaybe bodyType mRet)   -- FQ-RESULT-SORT-1
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
  -- EFFECT-RESP: a program may not redefine a sealed builtin type. Local
  -- STypeDefs win the alias-map union (checkStatements), so without this the
  -- redefinition succeeds silently and the def-main loop hands a builtin
  -- Response to a step whose parameter is the user's type.
  -- JSON-1: the reason clause is now per-type. It used to state the Response
  -- rationale unconditionally, which became wrong the moment an opaque sealed
  -- type joined the list (Json has no constructors at all, so "its constructors
  -- are sealed because the response alphabet ..." is not a reason for it).
  when (name `elem` sealedTypeNames) $
    tcErrorK "sealed-type-redefinition" $
      "type '" <> name <> "' is supplied by the compiler and cannot be redefined; "
      <> if name == jsonTypeName
           then "it is an opaque carrier with no program-visible structure, and its \
                \operations are sealed in §13.13"
           else "its constructors are sealed because the response alphabet is a \
                \function of the command alphabet"
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

checkStatement (SDefMain { defMainMode = mode, defMainStep = stepE, defMainDone = doneE
                         , defMainStatus = statusE }) = do
  -- Type-check the step and done? expressions
  stepTy <- inferExpr stepE
  checkStepArity mode stepTy
  case doneE of
    Nothing -> pure ()
    Just de -> do
      doneType <- inferExpr de
      doneOk <- compatibleExpanded doneType TBool
      unless doneOk $
        tcWarn ":done? should return bool; found non-bool type (ignored in v0.2)"
  checkStatusField mode doneE statusE

-- | PROC-BOUNDARY-1 §4: the @:status@ field's check-time surface.
--
-- Three diagnostics, all warnings and none an error, because @:status@ is
-- additive and no shipped program declares it: a hard error here could only
-- fire on a program written after this ships, and the design's own gap case
-- (§6.6) names @tcWarn@ as the in-scope move.
--
-- IT DOES NOT COPY THE @:done?@ CHECK ABOVE, deliberately. That check compares
-- the inferred type of the whole EXPRESSION against 'TBool', but @:done?@ names
-- a FUNCTION, so its type is @TFn [S] bool@ and 'compatibleWith' falls through
-- to structural equality and returns False. Measured at v0.14.84: `llmll check`
-- on scripts/build-smoke/smoke.llmll, a correct program, reports
-- "1 warning ... :done? should return bool". The warning fires on every console
-- program in the corpus that declares @:done?@ by name, so it carries no
-- information. This function reads the RETURN POSITION instead, which is what
-- the sibling meant to do. The sibling is left alone rather than fixed here:
-- changing it is a behaviour change to an unrelated diagnostic and belongs to
-- its own row.
--
-- 'TVar' in return position (an unannotated @def-shell@) is compatible with
-- anything by 'compatibleWith':2777, so an inferred-return program is not
-- warned at. That is the same latitude 'checkStepArity' extends and for the
-- same reason: every console entry point in the corpus is unannotated.
checkStatusField :: EntryMode -> Maybe Expr -> Maybe Expr -> TC ()
checkStatusField _    _     Nothing   = pure ()
checkStatusField mode mDone (Just se) = do
  -- §4: the field is meaningful only where a :done? path exists to apply it on.
  -- cli and http harnesses perform no Command and have no terminal state to
  -- project, so :status there is dead surface.
  unless (mode == ModeConsole) $
    tcWarn ":status applies only to :mode console; it is ignored in cli and http mode"
  -- §6.6, the gap the proposal flags: with no :done? the settle path is
  -- unreachable, the only exit is stdin exhaustion, and exhaustion does NOT
  -- consult :status (§4.3). The projection is therefore dead code, and a
  -- program that declared it believing it would run on EOF has the design
  -- exactly backwards. A warning rather than an error, on the MATCH-CATCHALL-1
  -- precedent: the population is bounded by programs shipping past a warning.
  --
  -- Rev 3 sharpened what the dead path exits: 0, not 70. A program with no
  -- :done? has no notion of completion, so EOF is normal termination rather
  -- than starvation. That makes this warning MORE worth emitting, not less --
  -- the author asked for an exit status and will silently get 0 every run.
  when (mode == ModeConsole && not (isJust mDone)) $
    tcWarn ":status without :done? is dead: the only exit is stdin exhaustion, \
           \which is normal termination here and exits 0 without consulting \
           \:status"
  sTy      <- inferExpr se
  resolved <- expandAlias sTy
  retTy    <- case resolved of
                TFn _ r -> expandAlias r
                other   -> pure other
  retOk    <- compatibleExpanded retTy TInt
  unless retOk $
    tcWarn ":status should return int (an exit status in 0..255); \
           \found a non-int return type"

-- | EFFECT-RESP (RC-1): the console @:step@ takes @(S, string, Response)@.
--
-- This is the migration's ONLY diagnostic and that is why it exists. Before it,
-- 'checkStatement' for SDefMain inferred the step expression and DISCARDED the
-- result, so the step was never applied and its arity was never constrained: a
-- one-parameter step and a three-parameter step type-checked identically.
-- Adding the response parameter is therefore a breaking change that @llmll
-- check@ reported on no program at all, leaving GHC as the first observer. Same
-- check-passes/build-fails seam as WASI-RT, reached by a different route.
--
-- Deliberately constrains the PARAMETER LIST ONLY, not the return position.
-- 'collectTopLevel' gives an unannotated @def-shell@ a return type of
-- @TVar "?"@, and every console step in the corpus is unannotated, so a rule
-- requiring @(S, Command)@ back would reject the very programs it is meant to
-- migrate. The return shape is already enforced where it can be: codegen
-- destructures the pair, and 'expectPairType' covers the do-notation path.
--
-- cli and http modes are untouched. Their harnesses perform no command
-- (CodegenHs 'emitMainBody' ModeCli prints the step's result and ModeHttp is an
-- error stub), so there is no response to deliver and no arity to change.
checkStepArity :: EntryMode -> Type -> TC ()
checkStepArity ModeConsole stepTy = do
  resolved <- expandAlias stepTy
  case resolved of
    TFn ps _
      | length ps == 3 -> do
          thirdOk <- compatibleExpanded (ps !! 2) (TCustom "Response")
          unless thirdOk $ arityError (Just (ps !! 2)) (length ps)
      | otherwise -> arityError Nothing (length ps)
    -- Not a function type at all: either a hole or an ill-typed :step. Both are
    -- already diagnosed by 'inferExpr' at the call site above; a second error
    -- here would just double-report.
    _ -> pure ()
  where
    arityError mThird n = tcErrorK "def-main-step-arity" $
      ":step of a console def-main must take three parameters "
      <> "(state, input: string, response: Response) and return (state, Command); found "
      <> tshow n <> " parameter" <> (if n == 1 then "" else "s")
      <> case mThird of
           Just t  -> ", whose third is " <> typeLabel t <> " rather than Response"
           Nothing -> ""
      <> ". Each performed command yields one Response, delivered as the next "
      <> "step's third argument (EFFECT-RESP RC-1)."
checkStepArity _ _ = pure ()

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
        then do
          -- RET-BRANCH-PREF Stage 1. Applied ONLY on the compatible path: on the
          -- mismatch path below the program is already in error and 'thenType' is a
          -- recovery value, so changing which broken type propagates buys nothing.
          mFn <- gets tcCurrentFn
          pure (preferConcreteOnSelfCall mFn thenE thenType elseE elseType)
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
  -- SCRUT-PTR: push the "scrutinee" segment (matches AstEmit's match-node key)
  -- so a hole in scrutinee position records its own pointer instead of the
  -- parent match node's — the LET-PTR defect class (v0.14.31 precedent).
  scrutType <- withSegment "scrutinee" (inferExpr expr)
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
    -- OBLIG-1 v2b: a hole nested anywhere in this arm's body captures the arm's
    -- case hypothesis. withHyp sits INSIDE withTaggedEnv (see its haddock).
    t <- withTaggedEnv SrcMatchArm patBindings $
           withHyp (matchHypothesis expr pat) $
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
      withHyp (matchHypothesis expr pat) $
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
  -- LEVER-A0: bytes/map builtins are typed by inferArrayOp, ahead of the
  -- generic builtinEnv path — a bytes[n] length is an Int (not a TVar) and
  -- map ops carry the v1 int-only key gate, neither expressible as a
  -- polymorphic signature. map-empty is NOT intercepted: its
  -- TFn [] (TMap k v) entry types fully generically (list-empty precedent).
  if func `elem` arrayOpNames
    then inferArrayOp func args
    else case mFuncTy of
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
      checkJsonNoEq func finalSubst   -- JSON-NOEQ: list-contains
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
      checkJsonNoEq op finalSubst     -- JSON-NOEQ: = and !=
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
  let (DoStep mName0 e0 dsc0) = head steps
  t0 <- withSegment "steps" $ withSegment "0" $ inferExpr e0
  (s0, cmd0) <- expectPairType "do-block step 0" t0
  -- DISCARD-1: check step 0 if it is not the final step; if it IS the final
  -- step, its command is performed and the marker would assert a falsehood.
  if length steps > 1
    then checkDiscardedCommand 0 cmd0 dsc0
    else checkMarkerOnFinalStep 0 dsc0
  let binding0 = case mName0 of
        Just n  -> [(n, s0)]
        Nothing -> [("_s_0", s0)]
  withEnv binding0 $ go s0 (1 :: Int) (tail steps)
  where
    go sType _ [] = pure (TPair sType (TCustom "Command"))
    go sType i (DoStep mName e dsc : rest) = do
      t <- withSegment "steps" $ withSegment (tshow i) $ inferExpr e
      (si, cmdTy) <- expectPairType ("do-block step " <> tshow i) t
      -- Unify S: all steps must thread the same state type
      unify ("do-block step " <> tshow i) sType si
      -- DISCARD-1: non-final steps must opt out; the final step must not.
      if not (null rest)
        then checkDiscardedCommand i cmdTy dsc
        else checkMarkerOnFinalStep i dsc
      let bindName = case mName of
            Just n  -> n
            Nothing -> "_s_" <> tshow i
      withEnv [(bindName, si)] $ go sType (i + 1) rest

-- | DISCARD-1: a non-final step whose command is dropped must say so.
--
-- This was a warning from v0.7, carrying a note deferring the hard error to
-- v0.8 "when (discard expr) provides an explicit opt-out". The opt-out is the
-- @:discard@ marker and this is that error, cashed at v0.14.80. 'emitDo'
-- is unchanged: it drops the command exactly as before, and the marker only
-- decides whether dropping it is legal. Generated Haskell is bit-identical.
--
-- Deliberately NOT the alternative reading (auto-composing intermediate
-- commands via 'seq-commands'): under EFFECT-RESP's response channel an
-- auto-composing do-block discards every non-final step's RESPONSE and so
-- could never consume an intermediate effect result, which is the shape the
-- driver's stages need.
checkDiscardedCommand :: Int -> Type -> Bool -> TC ()
checkDiscardedCommand i cmdTy discarded =
  when (cmdTy == TCustom "Command" && not discarded) $
    modify $ \s -> s { tcErrors = tcErrors s ++
      [(mkError Nothing $ "do-block step " <> tshow i
          <> ": codegen discards this intermediate command. "
          <> "Sequence it with `seq-commands`, or mark the step "
          <> "`[x <- e :discard]` to state that dropping it is intended.")
        { diagKind = Just "do-discard-error" }] }

-- | DISCARD-1: the final step's command is the one the harness performs, so
-- marking it discarded asserts something false. Rejected rather than ignored:
-- a marker that silently means nothing on one position and something on every
-- other is exactly the surface an agent mislearns.
checkMarkerOnFinalStep :: Int -> Bool -> TC ()
checkMarkerOnFinalStep i discarded =
  when discarded $
    modify $ \s -> s { tcErrors = tcErrors s ++
      [(mkError Nothing $ "do-block step " <> tshow i
          <> ": `:discard` is not allowed on the final step, whose command "
          <> "is the block's result and is performed. Remove the marker.")
        { diagKind = Just "do-discard-final" }] }

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
-- MATCH-NULLARY-1 (docs/design/finding-match-nullary-ctor-unsound.md).
-- A nullary constructor written bare in a match arm — `(Idle 1)` rather than the
-- spec's `((Idle) 1)` (§3.4) — parses as a BINDER named `Idle` (Parser.hs's
-- `PVar <$> pIdent` fallthrough), not as a constructor pattern. The arm then
-- silently becomes a catch-all and every later arm is dead. Codegen emits the
-- name verbatim, which Haskell reads back as a constructor, so the generated
-- program branches correctly while the verifier reasons about the catch-all —
-- and proves postconditions the running code violates (a false SAFE under
-- --strict-verified-core). Reject it here, where the scrutinee's constructor set
-- is known, and name the correct form. Hard error, not a rewrite: `((Idle) ...)`
-- already exists and silently reinterpreting would change a program's meaning.
checkPatternExpanded (PVar name) ty = do
  let ctorNames = case ty of
        TSumType ctorList -> map fst ctorList
        TResult _ _       -> ["Success", "Error"]
        _                 -> []
  when (name `elem` ctorNames) $
    tcError $ "pattern '" <> name <> "' names a constructor of the scrutinee type ("
           <> typeLabel ty <> "), so it binds as a catch-all instead of matching that "
           <> "constructor; write ((" <> name <> ") ...) for the constructor pattern"
  pure [(name, ty)]
checkPatternExpanded (PLiteral lit) scrutTy = do
  let litTy = inferLiteral lit
  am <- gets tcAliasMap
  unless (compatibleWith am litTy scrutTy) $
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
-- | LEVER-A0: the bytes/map builtins whose typing cannot ride the generic
-- TVar-signature path (see the §13.12 builtinEnv block). map-empty is absent
-- on purpose — TFn [] (TMap k v) types generically.
arrayOpNames :: [Name]
arrayOpNames =
  [ "bytes-length", "bytes-get", "bytes-set", "bytes-zero"
  , "map-has", "map-get", "map-put" ]

-- | LEVER-A0: dedicated typing for the array/map operation family (proposal
-- data-scope-lever-a-arrays-proposal.md §3). Enforces:
--   * first-argument structure (bytes[n] / map[k,v], alias-expanded);
--   * the v1 int-only map-key gate (F2 disposition) — a diagnostic on the
--     OPERATION, the type former stays unrestricted;
--   * bytes-set's length-preserving result type (bytes[n] in, bytes[n] out);
--   * bytes-zero's determining-context rule — v1 admits it only as the full
--     body of a function declared '-> bytes[n]' (handled at the def sites);
--     reaching it here means the context did not determine n.
-- Lenient where the argument type is an unresolved TVar (hole/unknown):
-- accept and return the best-known type, mirroring the generic path's
-- wildcard discipline so sketch mode and hole briefs keep working.
inferArrayOp :: Name -> [Expr] -> TC Type
inferArrayOp func args = case func of
  "bytes-zero" -> do
    checkArity 0
    tcError $ "(bytes-zero) requires a context that determines bytes[n]; "
              <> "v1 supports it only as the full body of a function declared '-> bytes[n]'"
    pure (TVar "?")
  "bytes-length" -> do
    checkArity 1
    _ <- bytesArg 0
    pure TInt
  "bytes-get" -> do
    checkArity 2
    _ <- bytesArg 0
    intArg 1
    pure TInt
  "bytes-set" -> do
    checkArity 3
    bTy <- bytesArg 0
    intArg 1
    intArg 2
    pure bTy
  "map-has" -> do
    checkArity 2
    _ <- mapArgAndKey
    pure TBool
  "map-get" -> do
    checkArity 2
    (_, vt) <- mapArgAndKey
    pure vt
  "map-put" -> do
    checkArity 3
    (kt, vt) <- mapArgAndKey
    vt' <- valueArg 2 vt
    pure (TMap kt vt')
  _ -> do  -- unreachable by construction (arrayOpNames gate)
    tcWarnOrError $ "call to unknown function '" <> func <> "'"
    pure (TVar "?")
  where
    checkArity n =
      when (length args /= n) $
        tcError $ "function '" <> func <> "' expects " <> tshow (n :: Int)
                  <> " args, got " <> tshow (length args)
    argAt j = withSegment "args" $ withSegment (tshow (j :: Int)) $
      case drop j args of
        (EHole hk : _) -> do
          -- Record the hole with a wildcard expectation; array-op arg types
          -- are enforced only on concrete terms (generic-path discipline).
          checkExpr (EHole hk) (TVar "?")
          pure (TVar "?")
        (e : _)        -> inferExpr e >>= expandAlias
        []             -> pure (TVar "?")  -- arity error already reported
    bytesArg j = do
      t <- argAt j
      case t of
        TBytes _ -> pure t
        TVar _   -> pure t  -- unresolved (hole/unknown): lenient
        other    -> do
          tcError $ "function '" <> func <> "' expects bytes[n] as argument "
                    <> tshow (j + 1) <> ", got " <> typeLabel other
          pure (TVar "?")
    intArg j = do
      t <- argAt j
      ok <- compatibleExpanded t TInt
      unless ok $
        tcError $ "function '" <> func <> "' expects int as argument "
                  <> tshow (j + 1) <> ", got " <> typeLabel t
    -- First argument must be map[k,v]; key argument (index 1) must match the
    -- map's key sort. A2.2-string (keys): the admissible key class widens from
    -- {int} to {int, string} — string keys reflect via the STRLIT interned
    -- constants + ground distinctness (Lever A §3 v1.5, delivered); other key
    -- sorts stay deferred.
    mapArgAndKey = do
      t <- argAt 0
      (kt, vt) <- case t of
        TMap kt vt -> do
          ktE <- expandAlias kt
          case ktE of
            TInt    -> pure ()
            TString -> pure ()  -- A2.2-string keys
            TVar _  -> pure ()  -- unresolved key sort: gate lands on the key arg
            other  -> tcError $ "map operation '" <> func <> "' requires int or string keys "
                                <> "(got map[" <> typeLabel other <> ",...]); "
                                <> "other key sorts are deferred (Lever A §3)"
          pure (ktE, vt)
        TVar _ -> pure (TVar "?", TVar "?")  -- unresolved map (hole/unknown): lenient
        other  -> do
          tcError $ "function '" <> func <> "' expects map[k,v] as argument 1, got "
                    <> typeLabel other
          pure (TVar "?", TVar "?")
      kArgTy <- argAt 1
      case kt of
        TInt -> do
          kOk <- compatibleExpanded kArgTy TInt
          unless kOk $
            tcError $ "map operation '" <> func <> "' requires an int key for this map, got "
                      <> typeLabel kArgTy
        TString -> do
          kOk <- compatibleExpanded kArgTy TString
          unless kOk $
            tcError $ "map operation '" <> func <> "' requires a string key for this map, got "
                      <> typeLabel kArgTy
        -- unresolved map/key sort: the key argument itself must land in the class
        _ -> do
          kInt <- compatibleExpanded kArgTy TInt
          kStr <- compatibleExpanded kArgTy TString
          unless (kInt || kStr) $
            tcError $ "map operation '" <> func <> "' requires an int or string key, got "
                      <> typeLabel kArgTy
      pure (kt, vt)
    valueArg j vt = do
      t <- argAt j
      case vt of
        TVar _ -> pure t  -- map's value sort unresolved: take the argument's
        _      -> do
          vOk <- compatibleExpanded t vt
          unless vOk $
            tcError $ "function '" <> func <> "' expects a value of type "
                      <> typeLabel vt <> " as argument " <> tshow (j + 1)
                      <> ", got " <> typeLabel t
          pure vt

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
-- The production call site (EApp, inferExpr) expands aliases before calling,
-- and the structural clauses below rely on that (nominal TCustom comparison,
-- component recursion). ADMIT-SHARED removed one thing from that list: the
-- WILD-ASSUME guard no longer needs it, because 'admits' normalizes its own
-- argument. A direct test that skips expansion gets a live guard and possibly
-- imprecise structural comparison, not a silently dead guard.
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
    -- SAFE-ARG (WILD-ASSUME): the LIVE argument seam. An unannotated callee's
    -- bare wildcard must not satisfy a fact-asserting parameter type; admitting
    -- it lets a bytes[32] reach a bytes[64] param, after which the callee's VC
    -- asserts bytesLen(b) = 64 and discharges index-in-bounds against a false
    -- premise. Measured false SAFE, v0.14.34..v0.14.72
    -- (docs/design/finding-arg-position-false-safe.md).
    --
    -- FACT-AG-LEN Stage 3: for the bytes arm this seam is now a DIAGNOSTIC, not a
    -- soundness gate. The length is earned (bytesLenParamPre / bytesLenRetPost),
    -- so the same hop is refuted downstream whether or not the checker stops it.
    -- The seam is KEPT because a type error here names the remedy (annotate the
    -- callee's return) and a refuted obligation does not; hence 'wildAssumeRejects'
    -- rather than 'admits'. The map arm is still a soundness gate.
    (_, TVar _) | isBareWildcard actual -> do
      -- ADMIT-SHARED: 'wildAssumeRejects' is total on unnormalized input, so this
      -- seam no longer depends on the EApp/EOp call sites having stripped and
      -- expanded 'expected' first. They still do, and label and noun therefore
      -- still read off the same type here, but the guard would fire either way.
      am <- gets tcAliasMap
      when (wildAssumeRejects am expected) $ tcWildAssumeError func expected expected
      pure subst

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
    _ -> do
      am <- gets tcAliasMap
      if compatibleWith am expected actual
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
--
-- ADMIT-SHARED: the 'AliasMap' parameter exists so the WILD-ASSUME clause below
-- lives INSIDE this predicate rather than at its callers. Hoisting the guard
-- into 'unify' would have avoided threading, and would have put the guard back
-- on a call-site-dependent footing — which is the failure mode ADMIT-SHARED
-- exists to remove. Every caller of 'compatibleWith' inherits the guard whether
-- or not it remembered to.
compatibleWith :: AliasMap -> Type -> Type -> Bool
compatibleWith _  (TVar _) _         = True  -- type variable matches anything
-- SAFE-ARG (WILD-ASSUME): the return / checkExpr seam, reached via 'unify'.
-- ACTUAL side only: a bare wildcard in EXPECTED position is the absence of a
-- declaration, so there is no asserted fact to falsify and rejecting it would
-- buy no soundness (finding Rev 1, "Direction: guard the actual side only").
-- FACT-AG-LEN Stage 3: 'wildAssumeRejects', not 'admits' — see the sibling seam
-- in 'structuralUnify' for why the bytes arm outlived its soundness role.
compatibleWith am t a@(TVar _)
  | isBareWildcard a, wildAssumeRejects am t = False
compatibleWith _  _ (TVar _)         = True
compatibleWith _  (TCustom "_") _    = True  -- untyped param wildcard
compatibleWith _  _ (TCustom "_")    = True
compatibleWith _  (TCustom a) (TCustom b) = a == b
compatibleWith am (TDependent _ a _) b   = compatibleWith am a b
compatibleWith am a (TDependent _ b _)   = compatibleWith am a b
compatibleWith am (TList a) (TList b)  = compatibleWith am a b
compatibleWith am (TMap k1 v1) (TMap k2 v2) = compatibleWith am k1 k2 && compatibleWith am v1 v2
compatibleWith am (TResult a b) (TResult c d) = compatibleWith am a c && compatibleWith am b d
-- PR 1: TPair structural equality (both components must match)
compatibleWith am (TPair a b) (TPair c d) = compatibleWith am a c && compatibleWith am b d
compatibleWith am (TPromise a) (TPromise b) = compatibleWith am a b
compatibleWith am (TFn as r) (TFn bs s) =
  length as == length bs && all (uncurry (compatibleWith am)) (zip as bs) && compatibleWith am r s
compatibleWith _  (TBytes m) (TBytes n) = m == n
-- TSumType: compatible with itself and with TCustom of the same registered name
-- TSumType: structural constructor equality (v0.4 U7-lite)
-- Before U-lite: any sum ≡ any sum (unsound). Now requires matching constructors.
compatibleWith _  (TSumType a) (TSumType b) = map fst a == map fst b
compatibleWith _  a b = a == b

-- | TC-level compatibility check that expands aliases before comparison.
-- Use at call sites that receive types from inference (which may
-- contain unresolved TCustom aliases from the environment).
compatibleExpanded :: Type -> Type -> TC Bool
compatibleExpanded a b = do
  a' <- expandAlias a
  b' <- expandAlias b
  am <- gets tcAliasMap
  pure (compatibleWith am a' b')

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
  am        <- gets tcAliasMap
  unless (compatibleWith am expected' actual') $
    -- SAFE-ARG: route the WILD-ASSUME rejection to its own diagnostic. Without
    -- this the message reads "got ?$0", leaking 'freshenFnType''s internal
    -- alpha-renaming counter into agent-facing output and naming no remedy.
    -- This is a diagnostic ROUTER, not a third guard: it must test exactly what
    -- the 'compatibleWith' clause above rejected on, or a rejected program gets
    -- the generic mismatch message. Hence 'wildAssumeRejects', in step with that
    -- clause (FACT-AG-LEN Stage 3).
    if isBareWildcard actual' && wildAssumeRejects am expected'
      -- Label from the original (alias name preserved, Fix 1b); noun from the
      -- expanded form the guard above actually tested (WR-01).
      then tcWildAssumeError ctx expected expected'
      -- Report originals to preserve alias names in diagnostics (Fix 1b).
      else tcTypeMismatch ctx expected actual

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
exprContainsVar v (EDo steps)       = any (\(DoStep _ e _) -> exprContainsVar v e) steps
exprContainsVar _ (ELit _)          = False
exprContainsVar _ (EHole _)         = False

-- CONTRACT-READ-LINT: warn on a statically out-of-bounds bytes read in a
-- contract clause (pre/post) — the decidable slice: a literal index against a
-- literal 'bytes[n]' parameter bound, e.g. '(bytes-get b 9)' where 'b : bytes[8]'.
-- Contract reads are total selects (FixpointEmit.exprToPred), so the contract
-- type-checks and can verify, but its generated runtime assertion aborts on every
-- execution. Syntactic (no solver), non-blocking, JSON-visible via diagKind.
-- See docs/design/contract-position-reads-disposition.md (disposition (c)).
lintContractReads :: Name -> [(Name, Type)] -> Contract -> TC ()
lintContractReads fnName params contract =
    mapM_ lintClause [contractPre contract, contractPost contract]
  where
    bytesLens = [ (pn, n) | (pn, TBytes n) <- params ]
    lintClause Nothing  = pure ()
    lintClause (Just e) = mapM_ emitOOB (collectBytesGets e)
    emitOOB :: (Name, Integer) -> TC ()
    emitOOB (bvar, idx) =
      case lookup bvar bytesLens of
        Just n | idx < 0 || idx >= fromIntegral n ->
          modify $ \s -> s { tcErrors = tcErrors s ++
            [mkContractReadOOBWarning fnName bvar (tshow idx) (tshow n)] }
        _ -> pure ()

-- Collect '(bytes-get <var> <literal-int>)' reads anywhere in an expression —
-- the decidable literal-index slice. A non-literal index is skipped (the
-- recursive descent into args finds no match).
collectBytesGets :: Expr -> [(Name, Integer)]
collectBytesGets (EApp "bytes-get" [EVar b, ELit (LitInt i)]) = [(b, i)]
collectBytesGets (EApp _ args)     = concatMap collectBytesGets args
collectBytesGets (EOp _ args)      = concatMap collectBytesGets args
collectBytesGets (EIf c t e)       = collectBytesGets c ++ collectBytesGets t ++ collectBytesGets e
collectBytesGets (ELet binds body) = concatMap (\(_, _, e) -> collectBytesGets e) binds ++ collectBytesGets body
collectBytesGets (EMatch e cases)  = collectBytesGets e ++ concatMap (collectBytesGets . snd) cases
collectBytesGets (EPair a b)       = collectBytesGets a ++ collectBytesGets b
collectBytesGets (ELambda _ body)  = collectBytesGets body
collectBytesGets (EAwait e)        = collectBytesGets e
collectBytesGets (EDo steps)       = concatMap (\(DoStep _ e _) -> collectBytesGets e) steps
collectBytesGets (ELit _)          = []
collectBytesGets (EVar _)          = []
collectBytesGets (EHole _)         = []
