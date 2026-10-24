-- |
-- Module      : LLMLL.Diagnostic
-- Description : Structured error and warning types for the LLMLL compiler.
--
-- All compiler phases produce 'Diagnostic' values instead of raw strings.
-- Diagnostics can be serialized as S-expressions or JSON.
module LLMLL.Diagnostic
  ( Diagnostic(..)
  , Severity(..)
  , DiagnosticReport(..)
  , mkError
  , mkWarning
  , mkInfo
  , mkErrorAt
  , formatDiagnostic
  , formatDiagnosticSExp
  , formatParseDiagSExp
  , formatDiagnosticJson
  , formatReportJson
  , megaparsecToDiagnostic
, modeHttpRetiredMessage
  -- * Phase 2a: Module System Diagnostics
  , mkCircularImport
  , mkModuleNotFound
  , mkInterfaceMismatch
  , mkExportConflict
  , mkOpenShadowWarning
  -- * Phase 2b: Static Analysis Diagnostics
  , mkNonExhaustiveMatch
  , reportDiagnostics
  , reportSuccess
  -- * v0.3: Patch diagnostic rebasing
  , PatchOpInfo(..)
  , rebaseToPatch
  -- * v0.3: Stratified verification
  , mkTrustGapWarning
  , mkTrustGapDeclaredWarning
  -- * v0.3.5: Weakness check
  , mkSpecWeakness
  , mkCandidateUnvalidated
  -- * v0.4: Capability enforcement (CAP-1)
  , mkMissingCapability
  -- * ENV-READ-1: the environment channel's three fail-closed side conditions
  , mkEnvDeterministicRefused
  , mkFsDeterministicRefused
  , mkEnvNameMalformed
  , mkProcEnvNameMalformed
  , mkProcTimeoutInvalid
  -- * HTTP-GET-1: the literal-URL rule
  , mkHttpUrlMalformed
  -- * REGEX-CAPTURE-1 / REGEX-CASE-1: the literal-pattern rule
  , mkInvalidRegex
  , mkRegexReplacementLiteral
  -- * XMOD-RUN-LOAD-1: a surface with no file cannot load imports
  , importNeedsFile
  -- * CTOR-AS-VALUE: a constructor of bool or Result is not a value
  , mkCtorAsValue
  -- * LT-INV (v0.11): core/shell grammar violations
  , mkCoreGrammarViolation
  , mkCoreMembershipViolation
  , mkCoreFfiCallee
  , mkCoreMembershipViolationLocal
  , mkCoreTerminationAssumed
  , mkCoreExcludedBuiltin
  -- * REFINE-REUSE: non-blocking reuse-duplicate warning
  , mkReuseWarning
  , mkContractReadOOBWarning
    -- SHELL-FALLBACK-SILENT-1
  , mkBodyFallbackWarning
  , mkMatchWildcardPayloadWarning
    -- DECREASES-LEN-1
  , mkDecreasesUndischarged
  -- * TOOL-ENCODING-1: source decoding pinned to UTF-8
  , decodeSourceUtf8
  , writeFileUtf8
  , firstInvalidUtf8Offset
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import Data.Maybe (fromMaybe)
import Data.Word (Word8)
import Numeric (showHex)
import Data.Aeson (ToJSON(..), object, (.=), encode)
import Data.Aeson.Types (Value(..))
import Data.Void (Void)
import qualified Data.List.NonEmpty as NE
import Text.Megaparsec (ParseErrorBundle, errorBundlePretty, bundleErrors, attachSourcePos, bundlePosState)
import Text.Megaparsec.Error (errorOffset, ParseError(..), ErrorFancy(..))
import qualified Data.Set as Set
import Text.Megaparsec.Pos (unPos, sourceLine, sourceColumn)
import LLMLL.Syntax (Span(..), Statement(SImport), Import(importPath))
import LLMLL.RegexPattern (RegexProblem(..))
import GHC.Generics (Generic)

-- | Severity level.
data Severity
  = SevError
  | SevWarning
  | SevInfo
  deriving (Show, Eq, Ord, Generic)

-- | A single compiler diagnostic.
data Diagnostic = Diagnostic
  { diagSeverity      :: Severity
  , diagSpan          :: Maybe Span
  , diagMessage       :: Text
  , diagSuggestion    :: Maybe Text
  , diagCode          :: Maybe Text     -- ^ e.g. \"E001\", \"W002\"
  -- v0.1.2 additions (roadmap JSON diagnostic shape):
  , diagKind          :: Maybe Text     -- ^ Error class: \"type-mismatch\", \"undefined-name\", etc.
  , diagPointer       :: Maybe Text     -- ^ RFC 6901 JSON Pointer to the offending AST node
  , diagInferredType  :: Maybe Text     -- ^ Inferred type at the error site, if available
  -- Phase 2c D3:
  , diagHoleSensitive :: Bool           -- ^ True → error may disappear when holes are filled
  -- Phase 2c D5 (structured error schema):
  , diagExpected      :: Maybe Text     -- ^ Expected type label (type-mismatch errors)
  , diagGot           :: Maybe Text     -- ^ Actual type label   (type-mismatch errors)
  , diagHole          :: Maybe Text     -- ^ Hole name (ambiguous-hole errors, e.g. \"?my_hole\")
  } deriving (Show, Eq, Generic)

-- | A collection of diagnostics from a compiler phase.
data DiagnosticReport = DiagnosticReport
  { reportPhase       :: Text          -- ^ "lexer", "parser", "typecheck"
  , reportDiagnostics :: [Diagnostic]
  , reportSuccess     :: Bool
  } deriving (Show, Eq, Generic)

-- ---------------------------------------------------------------------------
-- Smart Constructors
-- ---------------------------------------------------------------------------

mkError :: Maybe Span -> Text -> Diagnostic
mkError sp msg = Diagnostic SevError sp msg Nothing Nothing Nothing Nothing Nothing False Nothing Nothing Nothing

mkWarning :: Maybe Span -> Text -> Diagnostic
mkWarning sp msg = Diagnostic SevWarning sp msg Nothing Nothing Nothing Nothing Nothing False Nothing Nothing Nothing

mkInfo :: Maybe Span -> Text -> Diagnostic
mkInfo sp msg = Diagnostic SevInfo sp msg Nothing Nothing Nothing Nothing Nothing False Nothing Nothing Nothing

-- ---------------------------------------------------------------------------
-- v0.3: Patch diagnostic rebasing
-- ---------------------------------------------------------------------------

-- | Metadata for a single mutation patch op. Test ops are excluded because
-- they cannot introduce type errors.
data PatchOpInfo = PatchOpInfo
  { poiIndex :: Int    -- ^ 0-based index in the patch array
  , poiPath  :: Text   -- ^ RFC 6901 pointer targeted by this op
  , poiKind  :: Text   -- ^ "replace" | "add" | "remove"
  } deriving (Show, Eq, Generic)

instance ToJSON PatchOpInfo where
  toJSON poi = object
    [ "index" .= poiIndex poi
    , "path"  .= poiPath poi
    , "kind"  .= poiKind poi
    ]

-- | Rebase diagnostic pointers relative to patch operations.
-- Only mutation ops (replace/add/remove) can introduce type errors; test cannot.
--
-- Algorithm (reverse precedence — last matching op wins):
--   for each op in ops (reversed):
--     if diag.pointer starts with op.path:
--       suffix = diag.pointer - op.path
--       diag.pointer = "patch-op/" <> show op.index <> suffix
--       return diag
--   return diag unchanged (error in pre-existing code)
rebaseToPatch :: [PatchOpInfo] -> Diagnostic -> Diagnostic
rebaseToPatch ops diag = case diagPointer diag of
  Nothing  -> diag
  Just ptr -> case findMatchingOp (reverse ops) ptr of
    Nothing  -> diag  -- error not in any patched subtree
    Just (poi, suffix) ->
      diag { diagPointer = Just ("patch-op/" <> T.pack (show (poiIndex poi)) <> suffix) }
  where
    findMatchingOp [] _ = Nothing
    findMatchingOp (poi:rest) ptr
      | poiPath poi == ptr = Just (poi, "")  -- exact match
      | (poiPath poi <> "/") `T.isPrefixOf` ptr =
          Just (poi, T.drop (T.length (poiPath poi)) ptr)
      | otherwise = findMatchingOp rest ptr

-- | Smart constructor for diagnostics with a JSON Pointer and kind class.
-- Used by ParserJSON and the hole density validator.
mkErrorAt :: Text   -- ^ kind (e.g. \"type-mismatch\")
          -> Text   -- ^ RFC 6901 JSON Pointer
          -> Text   -- ^ message
          -> Diagnostic
mkErrorAt kind ptr msg = (mkError Nothing msg)
  { diagKind    = Just kind
  , diagPointer = Just ptr
  }

-- ---------------------------------------------------------------------------
-- Phase 2a: Module System Diagnostics
-- ---------------------------------------------------------------------------

-- | Circular import detected by DFS. The cycle list starts and ends with the
-- same module path so the cycle is visually clear.
-- e.g. ["foo.bar", "foo.baz", "foo.bar"]
mkCircularImport :: [Text] -> Diagnostic
mkCircularImport cycle_ =
  let msg = "Circular import detected: " <> T.intercalate " \x2192 " cycle_
  in (mkError Nothing msg) { diagKind = Just "circular-import" }

-- | A required module file was not found in any search root.
mkModuleNotFound :: Text -> [FilePath] -> Diagnostic
mkModuleNotFound path roots =
  let msg = "Module not found: " <> path
           <> " (searched: " <> T.intercalate ", " (map T.pack roots) <> ")"
  in (mkError Nothing msg) { diagKind = Just "module-not-found" }

-- | Structural incompatibility between a def-interface and its implementation.
mkInterfaceMismatch :: Text -> Text -> Text -> Text -> Text -> Text -> Diagnostic
mkInterfaceMismatch modPath iface method expected got pointer =
  let msg = "interface-mismatch in " <> modPath <> " / " <> iface
            <> ": method '" <> method <> "' expected " <> expected
            <> ", got " <> got
  in (mkError Nothing msg)
       { diagKind    = Just "interface-mismatch"
       , diagPointer = Just pointer
       }

-- | An (export f) declaration names f but f is not defined in this module.
mkExportConflict :: Text -> Text -> Diagnostic
mkExportConflict name modPath =
  let msg = "export-conflict: '" <> name <> "' is not defined in " <> modPath
  in (mkError Nothing msg) { diagKind = Just "export-conflict" }

-- | Two (open ...) declarations both export the same bare name; second wins.
mkOpenShadowWarning :: Text -> Text -> Text -> Diagnostic
mkOpenShadowWarning name shadowedBy prevFrom =
  let msg = "open-shadow-warning: '" <> name <> "' from " <> prevFrom
            <> " is shadowed by " <> shadowedBy
  in (mkWarning Nothing msg) { diagKind = Just "open-shadow-warning" }

-- | CONTRACT-READ-LINT: a literal-index @bytes-get@ in a contract clause
-- (@pre@/@post@) that is statically out of bounds against a literal @bytes[n]@
-- parameter bound — e.g. @(bytes-get b 9)@ where @b : bytes[8]@. Contract reads
-- are total selects, so such a contract type-checks and can even verify, but the
-- generated runtime assertion aborts on /every/ execution
-- (verified-yet-always-crashing). Non-blocking, JSON-visible (the F-001 lesson).
-- Args are pre-rendered Text (@fnName@, @bytesVar@, @idx@, @n@). See
-- @docs/design/contract-position-reads-disposition.md@.
mkContractReadOOBWarning :: Text -> Text -> Text -> Text -> Diagnostic
mkContractReadOOBWarning fnName bytesVar idx n =
  let msg = "contract-read-oob: '(bytes-get " <> bytesVar <> " " <> idx
            <> ")' in '" <> fnName <> "' is always out of bounds — " <> bytesVar
            <> " : bytes[" <> n <> "], index " <> idx <> " is outside [0," <> n
            <> "). The contract can verify but its runtime assertion aborts on "
            <> "every execution (verified-yet-always-crashing). Use an in-bounds index."
  in (mkWarning Nothing msg) { diagKind = Just "contract-read-oob" }

-- | v0.3: Cross-module call to a function with an unproven contract.
mkTrustGapWarning :: Text -> Text -> Text -> Diagnostic
mkTrustGapWarning funcName level = mkTrustGapDeclaredWarning funcName level level Nothing

-- | TRUST-LEVEL-FLOOR-1: the general form. @level@ is the checked level the
-- warning reports, @hint@ the level the fix-it declares (they differ only for
-- @tested-joint@, which has no surface form, so the hint is @asserted@), and
-- @mDeclared@ the level of a @(trust ...)@ declaration the evidence no longer
-- covers. The @(level: ...)@ prefix is the same in both forms.
mkTrustGapDeclaredWarning :: Text -> Text -> Text -> Maybe Text -> Text -> Diagnostic
mkTrustGapDeclaredWarning funcName level hint mDeclared pointer =
  let declared = case mDeclared of
        Nothing -> "Your module inherits this trust gap. "
        Just d  -> "Your (trust " <> funcName <> " :level " <> d <> ") declares "
                   <> d <> ", which this evidence no longer meets. "
      msg = "Function " <> funcName <> " has an unproven contract (level: "
            <> level <> "). " <> declared
            <> "Silence with: (trust " <> funcName <> " :level " <> hint <> ")"
  in (mkWarning Nothing msg)
       { diagKind = Just "trust-gap"
       , diagPointer = Just pointer
       }

-- | SHELL-FALLBACK-SILENT-1 (W-BODY-FALLBACK): the body left the decidable
-- fragment, so the post is assumed rather than proved.
--
-- Raised by the emitter, which reaches this point only for a function that HAS a
-- post ('FallbackNoPost' is decided first). Contract-only verification of such a
-- function stays sound (LLMLL.md §4.1, §4.4); what was missing was any statement
-- that the body-faithful claim had been lost, and which construct lost it.
--
-- The closed labels ride 'body_fallback_constructs' for the census. The
-- constructor names ride this message only: a constructor name is program text
-- and would give the census histogram an unbounded bucket set.
mkBodyFallbackWarning :: Text    -- ^ function name
                      -> Text    -- ^ rendered fallback cause
                      -> [Text]  -- ^ closed refusal labels
                      -> [Text]  -- ^ constructors whose payload is written '_'
                      -> Diagnostic
mkBodyFallbackWarning fnName cause labels wildCtors =
  let labelText = if null labels then "unclassified" else T.intercalate ", " labels
      repair = if null wildCtors then ""
               else " Bind the payload of " <> T.intercalate ", " (map quoted wildCtors)
                    <> " by name to verify the body."
      msg = "W-BODY-FALLBACK: '" <> fnName <> "' fell back from body-faithful "
            <> "verification (" <> cause <> "), so its post is assumed and not "
            <> "proved. Refused by: " <> labelText <> "." <> repair
  in (mkWarning Nothing msg)
       { diagCode = Just "W-BODY-FALLBACK"
       , diagKind = Just "body-fallback-cause"
       }

-- | DECREASES-LEN-1 (W-DECREASES-UNDISCHARGED): a self-recursive def-shell
-- declares a (decreases …) measure, but its body fell back, so no descent
-- obligation reached the solver. Descent is emitted inside the body VC only, so
-- a fallback drops the declared measure; before this warning it did so with no
-- statement naming the clause. The function stays termination_unverified.
mkDecreasesUndischarged :: Text    -- ^ function name
                        -> Text    -- ^ rendered fallback cause
                        -> Int     -- ^ statement index (JSON Pointer)
                        -> Diagnostic
mkDecreasesUndischarged fnName cause stmtIdx =
  let msg = "W-DECREASES-UNDISCHARGED: '" <> fnName <> "' declares a decreases "
            <> "measure, but its body fell back from body-faithful verification ("
            <> cause <> "), so no descent obligation was emitted and termination "
            <> "is not proved. The function stays termination_unverified."
  in (mkWarning Nothing msg)
       { diagCode    = Just "W-DECREASES-UNDISCHARGED"
       , diagPointer = Just ("/statements/" <> T.pack (show stmtIdx) <> "/decreases")
       }

-- | SHELL-FALLBACK-SILENT-1 (W-MATCH-WILDCARD-PAYLOAD): a match arm writes a
-- constructor payload as '_' where binding it by name would verify the body.
--
-- Raised at check time, and only for a function that carries a post and holds no
-- hole. In a @def@ the same body is the hard error 'mkCoreGrammarViolation'; in a
-- @def-shell@ nothing was said at all, which is the asymmetry this closes.
mkMatchWildcardPayloadWarning :: Text -> [Text] -> Diagnostic
mkMatchWildcardPayloadWarning fnName ctors =
  let ctorText = T.intercalate ", " (map quoted ctors)
      msg = "W-MATCH-WILDCARD-PAYLOAD: '" <> fnName <> "' writes the payload of "
            <> ctorText <> " as '_', so the verifier cannot eliminate the match "
            <> "and the post is assumed rather than proved. Bind the payload by "
            <> "name to verify the body."
  in (mkWarning Nothing msg)
       { diagCode = Just "W-MATCH-WILDCARD-PAYLOAD"
       , diagKind = Just "match-wildcard-payload"
       }

quoted :: Text -> Text
quoted t = "'" <> t <> "'"

-- | REFINE-REUSE (W-REUSE): a `refine`-spawned sub-contract is contract-identical
-- (up to α-rename) to an existing in-scope def. NON-BLOCKING advisory — the
-- refine still succeeds; this only suggests calling the existing def instead of
-- filling a duplicate. Sound-but-incomplete (normal-form-key equality).
mkReuseWarning :: Text  -- ^ spawned sub-contract's def name
               -> Text  -- ^ the contract-identical in-scope def
               -> Diagnostic
mkReuseWarning spawned candidate =
  let msg = "spawned '" <> spawned <> "' is contract-identical to in-scope '"
            <> candidate <> "'; consider calling it instead of filling a duplicate"
  in (mkWarning Nothing msg)
       { diagCode = Just "W-REUSE"
       , diagKind = Just "reuse-duplicate"
       }

-- ---------------------------------------------------------------------------
-- v0.3.5: Spec Weakness Diagnostics
-- ---------------------------------------------------------------------------

-- | Emit a spec-weakness warning diagnostic.
-- EC-7: includes precondition text when present.
mkSpecWeakness
  :: Text         -- ^ function name
  -> Text         -- ^ trivial body label (e.g. "(lambda [x] x)")
  -> Maybe Text   -- ^ precondition text (EC-7), if any
  -> Maybe Text   -- ^ postcondition text, if any
  -> Diagnostic
mkSpecWeakness funcName trivialLabel mPre mPost =
  let preNote = case mPre of
        Nothing -> ""
        Just p  -> "\n  Under precondition: " <> p
      postNote = case mPost of
        Nothing -> ""
        Just p  -> "\n  Your contract: " <> p
      suggestion = "Consider adding a postcondition that distinguishes your implementation from " <> trivialLabel
      msg = "Spec weakness detected for `" <> funcName <> "`:"
            <> preNote <> postNote
            <> "\n  Trivial valid implementation: " <> trivialLabel
            <> "\n  " <> suggestion
  in (mkWarning Nothing msg)
       { diagKind       = Just "spec-weakness"
       , diagSuggestion = Just suggestion
       }

-- | CDP deep-dive Rev 5 (item 5): a weakness-check candidate whose own
-- synthetic body fell outside the QF-LIA-translatable fragment
-- ('erBodyFallback'). Distinct from 'mkSpecWeakness': this candidate's
-- satisfaction is unknown, not confirmed weak — a solver verdict on a
-- body-fallback emission is not evidence either way, so it must not be
-- silently dropped (that would regress '--weakness-check''s diagnostic
-- surface for functions whose only weak candidate happens to be excluded).
mkCandidateUnvalidated
  :: Text  -- ^ function name
  -> Text  -- ^ trivial body label
  -> Diagnostic
mkCandidateUnvalidated funcName trivialLabel =
  let msg = "Weakness-check candidate for `" <> funcName <> "` could not be validated: "
            <> trivialLabel <> " — body translation fell outside the checkable "
            <> "(QF-LIA) fragment. This candidate's satisfaction is unknown, not confirmed weak."
  in (mkWarning Nothing msg)
       { diagKind = Just "weakness-check-candidate-unvalidated" }

-- ---------------------------------------------------------------------------
-- v0.4: Capability Enforcement Diagnostics (CAP-1)
-- ---------------------------------------------------------------------------

-- | Emit a missing-capability error when a wasi.* function is called
-- without a matching (import wasi.<namespace> (capability ...)) in the module.
-- CAP-1: capabilities are module-local (non-transitive).
mkMissingCapability
  :: Text         -- ^ function name (e.g. "wasi.io.stdout")
  -> Text         -- ^ required namespace (e.g. "wasi.io")
  -> Diagnostic
mkMissingCapability func namespace =
  let suggestion = "Add: (import " <> namespace <> " (capability ...))"
      msg = func <> " requires (import " <> namespace <> " (capability ...)) "
            <> "\x2014 wasi.* functions need an explicit capability import in each module"
  in (mkError Nothing msg)
       { diagKind       = Just "missing-capability"
       , diagSuggestion = Just suggestion
       }

-- | ENV-READ-1: @:deterministic true@ on a @wasi.env@ import is refused.
--
-- REFUSED RATHER THAN DEFAULTED. A default that fails open writes a secret
-- whenever somebody copies a clock import.
--
-- THE MESSAGE STATES A FORWARD CONDITION AND NOT A LIVE LEAK, and that wording
-- is measured rather than cautious. At v0.14.99 no capture runs at all:
-- 'capDeterministic' reaches exactly one consumer in the tree (@AstEmit.hs:443@,
-- which serialises it to JSON), @CodegenHs.hs@'s emitted @eventJsonL@ writes the
-- @captures@ array as a literal @[]@, and @Replay.hs@ never reads a capture. A
-- witness program carrying @:deterministic true@ on a clock import was built and
-- run: its log records @"captures":[]@ on every event. @LLMLL.md:1816@ describes
-- the mechanism as though it exists, so the drift is in the spec.
--
-- The guard therefore lands BEFORE the leak rather than after it. A message
-- claiming the flag writes a secret today would be false today.
--
-- EVENT-LOG-2 (v0.28.2) narrowed §10a to the shipped oracle. Both refusal
-- messages now say so and name REPLAY-INJECT as the row the guard is for.
-- | FS-STAT-1. The @wasi.fs@ counterpart, and the REASON IS DIFFERENT, which is
-- why this is a second diagnostic rather than one more path on the environment
-- one above. The environment refusal is about SECRECY: a captured environment
-- read writes a credential to the event log. This refusal is about a CLAIM THAT
-- WOULD BE FALSE: @wasi.fs.stat@ differences the wall clock against a file's
-- modification time, so two runs of the same program over the same tree return
-- different values. A capability marked deterministic would promise replay
-- determinism over an operation that has none.
--
-- The refusal is on the IMPORT and not the call, matching the environment rule
-- directly above. The import IS the grant, so a module carrying the flag is
-- refused whether or not it calls @wasi.fs.stat@. That is the stricter reading
-- and the simpler one.
--
-- MEASURED before shipping: the in-tree population carrying @:deterministic
-- true@ on a @wasi.fs@ import is ZERO. Two files match a text search for the
-- flag beside a @wasi.fs@ import, and in both the flag appears inside a COMMENT
-- explaining that it would be refused on @wasi.env@. Every real import in both
-- carries @:deterministic false@.
mkFsDeterministicRefused
  :: Text         -- ^ import path (e.g. "wasi.fs")
  -> Diagnostic
mkFsDeterministicRefused path =
  let msg = ":deterministic true is refused on a " <> path <> " import. "
            <> "No capture runs today (LLMLL.md 10a). The refusal guards "
            <> "REPLAY-INJECT: if capture is built, the flag would mark this "
            <> "capability's return values as replayable from the log, and "
            <> "wasi.fs.stat differences the wall clock against a file's "
            <> "modification time, so it returns a different value on a later "
            <> "run over an unchanged tree. The flag would claim replay "
            <> "determinism over an operation that does not have it."
      suggestion = "Use (capability read \"...\" :deterministic false), or omit "
                   <> "the flag entirely."
  in (mkError Nothing msg)
       { diagKind       = Just "fs-deterministic-refused"
       , diagSuggestion = Just suggestion
       }

mkEnvDeterministicRefused
  :: Text         -- ^ import path (e.g. "wasi.env")
  -> Diagnostic
mkEnvDeterministicRefused path =
  let msg = ":deterministic true is refused on a " <> path <> " import. "
            <> "No capture runs today (LLMLL.md 10a). The refusal guards "
            <> "REPLAY-INJECT: if capture is built, a captured environment read "
            <> "would write a secret to <module>.event-log.jsonl in plaintext, "
            <> "because the environment carries credentials by convention. This is refused rather than defaulted, because a "
            <> "default that fails open writes a secret whenever a clock import "
            <> "is copied. Redaction of a captured value is a separate proposal."
      suggestion = "Use (capability read \"...\" :deterministic false), or omit "
                   <> "the flag entirely."
  in (mkError Nothing msg)
       { diagKind       = Just "env-deterministic-refused"
       , diagSuggestion = Just suggestion
       }

-- | ENV-READ-1: a LITERAL environment variable name that cannot name a variable.
--
-- Two forms are refused: the empty name, and a name containing @=@. Measured
-- 2026-08-14: an unset name, a name containing @=@, and the empty name all
-- answer the same thing at the OS level, so @RErr@ conflates "unset" with "this
-- name cannot name a variable". A variable that is set and empty stays
-- distinguishable, so the conflation is on the NAME side and not the value side.
--
-- The rule reaches a LITERAL only. A computed name keeps the conflation, and
-- that limit is pinned by a test rather than hidden.
mkEnvNameMalformed
  :: Text         -- ^ the offending literal
  -> Text         -- ^ which rule fired ("empty" or "contains-equals")
  -> Diagnostic
mkEnvNameMalformed lit rule =
  let what = case rule of
        "empty" -> "a literal environment variable name cannot be empty"
        _       -> "a literal environment variable name cannot contain \"=\""
      msg = what <> " (got " <> tshow lit <> "). Such a name can never resolve, "
            <> "so the call always answers RErr and its failure is "
            <> "indistinguishable from an unset variable."
      suggestion = "Pass a name that can name a variable, e.g. \"HOME\"."
  in (mkError Nothing msg)
       { diagKind       = Just "env-name-malformed"
       , diagSuggestion = Just suggestion
       }

-- | PROC-ENV-1 (docs/design/g7-tooling-builtins-proposal.md section 3). A
-- literal proc-env name that is empty or contains "=" can never name a
-- variable: wasi.proc.exec would answer RErr on every run. A computed name
-- reaches that runtime check instead.
mkProcEnvNameMalformed
  :: Text         -- ^ the offending literal
  -> Text         -- ^ which rule fired ("empty" or "contains-equals")
  -> Diagnostic
mkProcEnvNameMalformed lit rule =
  let what = case rule of
        "empty" -> "a literal proc-env variable name cannot be empty"
        _       -> "a literal proc-env variable name cannot contain \"=\""
      msg = what <> " (got " <> tshow lit <> "). wasi.proc.exec would answer "
            <> "RErr for this specification on every run."
      suggestion = "Pass the name and the value separately: (proc-env spec \"LC_ALL\" \"C\")."
  in (mkError Nothing msg)
       { diagKind       = Just "proc-env-name-malformed"
       , diagSuggestion = Just suggestion
       }

-- | PROC-ENV-1: a literal proc-spec timeout below one second. A computed one
-- reaches wasi.proc.exec, which answers RErr before the child starts.
mkProcTimeoutInvalid :: Integer -> Diagnostic
mkProcTimeoutInvalid n =
  (mkError Nothing ("a proc-spec timeout must be at least 1 second (got "
                    <> tshow n <> ")."))
    { diagKind       = Just "proc-timeout-invalid"
    , diagSuggestion = Just "Pass a positive number of seconds, e.g. (proc-spec 60)."
    }

-- | CTOR-AS-VALUE (docs/design/ctor-as-value-proposal.md). An unbound True,
-- False, Success or Error in expression position: a constructor usable only
-- as a match pattern. The message names the value spelling.
mkCtorAsValue :: Text -> Diagnostic
mkCtorAsValue x =
  let (owner, pat, value) = case x of
        "True"    -> ("bool", "(True)", "the value is `true`")
        "False"   -> ("bool", "(False)", "the value is `false`")
        "Success" -> ("Result", "(Success x)", "build the value with `(ok x)`")
        _         -> ("Result", "(Error e)", "build the value with `(err e)`")
      msg = "'" <> x <> "' is a constructor of " <> owner
            <> ", usable only as a match pattern " <> pat <> "; " <> value <> "."
      suggestion = case x of
        "True"    -> "Write true."
        "False"   -> "Write false."
        "Success" -> "Write (ok x) to build a Success value."
        _         -> "Write (err e) to build an Error value."
  in (mkError Nothing msg)
       { diagKind       = Just "constructor-as-value"
       , diagSuggestion = Just suggestion
       }

-- | XMOD-RUN-LOAD-1. A surface that receives source text with no file (serve's
-- POST /typecheck and /sketch, a repl line) has no directory to resolve an
-- @(import M)@ of a user module against. It used to check the text with an
-- empty module cache, where @M.f@ is an unknown name and only a warning, so an
-- ill-typed call reported success. It now refuses the import by name. A
-- @wasi.*@ import is a host capability, not a module, and passes.
importNeedsFile :: Text -> [Statement] -> Maybe Diagnostic
importNeedsFile surface stmts =
  case [ importPath i | SImport i <- stmts
                      , not ("wasi." `T.isPrefixOf` importPath i || importPath i == "wasi") ] of
    []      -> Nothing
    (m : _) -> Just (mkError Nothing
      ("(import " <> m <> ") needs a file: " <> surface <> " receives source text with no "
       <> "location, so a module import cannot be resolved and its names cannot be checked."))
      { diagKind       = Just "import-needs-file"
      , diagSuggestion = Just ("Write the program to a file and run `llmll check FILE`; to "
                               <> "edit a hole in it, use checkout and patch on that file.")
      }

-- | REGEX-CAPTURE-1 / REGEX-CASE-1. A regex pattern `check` can see (a string
-- literal, or a nullary local definition whose whole body is one) that the
-- run-time compile would reject, or that uses a letter escape regex-tdfa
-- reads as the letter itself (amendment A1: @\\d@ matches the letter d). At
-- run time either one answers False or [] for every subject, with no message.
-- Same placement and reach as the ENV-READ-1 and HTTP-GET-1 rules; a pattern
-- passed as a parameter is not seen, and Spec.hs RX-9 pins that limit.
mkInvalidRegex
  :: Text          -- ^ the builtin called (e.g. "regex-find")
  -> Text          -- ^ the pattern, as the builtin receives it
  -> Maybe Text    -- ^ the nullary definition that returned it, if any
  -> RegexProblem
  -> Diagnostic
mkInvalidRegex func pat via problem =
  let source = maybe "" (\d -> " (returned by " <> d <> ")") via
      -- REGEX-REPLACE-1 (F5): regex-replace-all answers its subject unchanged.
      answer = case func of
        "regex-match"       -> "False"
        "regex-replace-all" -> "the subject unchanged"
        _                   -> "[]"
      (what, suggestion) = case problem of
        RxParse err ->
          ( "cannot compile: " <> T.pack err
          , "Patterns are POSIX ERE (LLMLL.md \167" <> "13.6). A leading (?i) is the only "
            <> "inline flag; non-greedy *?, (?:...) and lookaround are not supported." )
        RxEscape c ->
          ( "uses \\" <> T.singleton c <> ", which POSIX ERE reads as the letter "
            <> T.singleton c <> ", not a class or a control character"
          , escapeHint c )
      msg = "regex pattern " <> tshow pat <> source <> " " <> what
            <> ". At run time " <> func <> " would answer " <> answer
            <> " with no message."
  in (mkError Nothing msg)
       { diagKind       = Just "invalid-regex"
       , diagSuggestion = Just suggestion
       }
  where
    escapeHint c = case c of
      'd' -> "Use [0-9] or [[:digit:]]."
      'D' -> "Use [^0-9] or [^[:digit:]]."
      'w' -> "Use [[:alnum:]_]."
      'W' -> "Use [^[:alnum:]_]."
      's' -> "Use [[:space:]]."
      'S' -> "Use [^[:space:]]."
      _ | c `elem` ("ntrfv" :: String) ->
            "Write the character itself: in an LLMLL string literal \"\\n\" is a newline."
        | otherwise ->
            "Remove the backslash, or use a bracket expression. Patterns are POSIX ERE (LLMLL.md \167" <> "13.6)."


-- | REGEX-REPLACE-1. A literal replacement that holds a backslash and a digit.
-- regex-replace-all inserts the replacement as written, so @\1@ is two
-- characters and not group 1. A warning, not an error: the text may be meant.
mkRegexReplacementLiteral :: Text -> Diagnostic
mkRegexReplacementLiteral r =
  (mkWarning Nothing
     ("regex-replace-all replacement " <> T.pack (show r) <> " holds a backslash and a digit. "
      <> "The replacement is literal text: it is inserted as written, and there are no "
      <> "group references such as \\1 or $1."))
    { diagKind       = Just "regex-replacement-literal"
    , diagSuggestion = Just ("To use a group, take the match with regex-find-all or "
                             <> "regex-spans and build the text with string-slice and "
                             <> "string-concat (LLMLL.md \167" <> "13.6).")
    }

-- | HTTP-GET-1. A LITERAL url passed to wasi.http.get that does not begin with
-- http:// or https://. Sits beside the ENV-READ-1 rule in inferExpr and has the
-- same reach: a literal only. Two inputs this catches at check time would each
-- misbehave at run time: a reversed call (dest in the url slot, both being
-- strings) and a literal with a leading method word ("POST https://..."),
-- which http-client's parseRequest honours as the request method.
mkHttpUrlMalformed
  :: Text         -- ^ the offending literal
  -> Diagnostic
mkHttpUrlMalformed lit =
  let msg = "a literal URL for wasi.http.get must begin with http:// or https:// (got "
            <> tshow lit <> "). The runtime refuses every other scheme before any "
            <> "request, so this call would always answer RErr; and a leading method "
            <> "word would change the request method."
      suggestion = "Pass a URL beginning with http:// or https://, and check the "
                   <> "argument order: (wasi.http.get url dest), the URL first."
  in (mkError Nothing msg)
       { diagKind       = Just "http-url-malformed"
       , diagSuggestion = Just suggestion
       }

-- ---------------------------------------------------------------------------
-- Phase 2b: Static Analysis Diagnostics
-- ---------------------------------------------------------------------------

-- | Non-exhaustive match over a known ADT sum type.
-- Emitted when the match arms cover a strict subset of the ADT's constructors
-- and no wildcard/variable arm is present.
--
-- Parameters:
--   fnName    — enclosing function name (for context in the error)
--   typeName  — name of the ADT being matched
--   missing   — constructor names not covered by any arm
--   covered   — constructor names that were covered
mkNonExhaustiveMatch :: Text -> Text -> [Text] -> [Text] -> Diagnostic
mkNonExhaustiveMatch fnName typeName missing covered =
  let missingStr = T.intercalate ", " missing
      coveredStr = T.intercalate ", " covered
      msg = "non-exhaustive match in '" <> fnName <> "': "
            <> "type '" <> typeName <> "' has unmatched constructors: "
            <> missingStr
            <> " (covered: " <> coveredStr <> ")"
  in (mkError Nothing msg)
       { diagKind    = Just "non-exhaustive-match"
       , diagPointer = Just ("/def-logic/" <> fnName <> "/body")
       }

-- ---------------------------------------------------------------------------
-- LT-INV (v0.11): Core/Shell Grammar Violations
-- ---------------------------------------------------------------------------

-- | Emitted when a strict-core (def) body contains non-core syntax: lambda,
-- do-notation, await, non-linear arithmetic (*\//mod/rem), an unrestricted
-- match expression, or a ?proof-required hole.
mkCoreGrammarViolation :: Text -> Text -> Diagnostic
mkCoreGrammarViolation defName detail =
  let msg = "def '" <> defName <> "': body contains non-core syntax \x2014 " <> detail
            <> "; use def-shell for permissive bodies"
  in (mkError Nothing msg)
       { diagKind       = Just "core-grammar-violation"
       , diagSuggestion = Just ("Replace (def " <> defName <> " ...) with (def-shell " <> defName <> " ...)")
       }

-- | Emitted when a callee inside a strict-core (def) body is neither
-- body-faithful (verified) nor in the trusted-prelude set.
mkCoreMembershipViolation :: Text -> Text -> Diagnostic
mkCoreMembershipViolation defName callee =
  let msg = "def '" <> defName <> "': callee '" <> callee
            <> "' is not body-faithful and not in the trusted prelude; "
            <> "only verified (body-faithful) functions and trusted builtins are admissible in strict-core bodies"
  in (mkError Nothing msg)
       { diagKind       = Just "core-membership-violation"
       , diagSuggestion = Just ("Verify '" <> callee <> "' with (llmll verify) before calling it from a strict-core def")
       }

-- | FFI-TIER1-1 (E9): the same violation when the callee is a haskell.*
-- interface entry. "Verify it first" cannot help: a Hackage function has no
-- LLMLL body to verify. Same 'diagKind' as 'mkCoreMembershipViolation'.
mkCoreFfiCallee :: Text -> Text -> Diagnostic
mkCoreFfiCallee defName callee =
  let msg = "def '" <> defName <> "': callee '" <> callee
            <> "' is a haskell.* interface entry; a Hackage function has no body to verify, "
            <> "so it is not admissible in a strict-core body"
  in (mkError Nothing msg)
       { diagKind       = Just "core-membership-violation"
       , diagSuggestion = Just ("Call '" <> callee <> "' from a def-shell instead (admitting Hackage functions to the strict core is FFI-UNINTERP-1)")
       }

-- | HEADLINE-TERM-1 item (4): the same violation when the callee is defined in
-- the SAME file. Admission reads persisted evidence only, and verification
-- runs after this check, so "verify it first" cannot help here: the file does
-- not type-check while the call is present. The remedy is module placement.
-- A recursive callee additionally needs a discharging measure (REC-DESCENT
-- Phase 3 (b1)). Same 'diagKind' as 'mkCoreMembershipViolation', so every
-- consumer keyed on the kind is unaffected.
mkCoreMembershipViolationLocal :: Text -> Text -> Bool -> Diagnostic
mkCoreMembershipViolationLocal defName callee isRec =
  let msg = "def '" <> defName <> "': callee '" <> callee
            <> "' is defined in this file and has no recorded verification; "
            <> "a def may call only trusted builtins and functions verified in an earlier run"
            <> (if isRec
                  then " (a recursive callee must also be descent-discharged by a (decreases \x2026) measure)"
                  else "")
  in (mkError Nothing msg)
       { diagKind       = Just "core-membership-violation"
       , diagSuggestion = Just ("Move '" <> callee <> "' to its own module"
                                <> (if isRec then " with a (decreases \x2026) measure" else "")
                                <> ", verify it, then import it")
       }

-- | DEF-ADMIT-XMOD-1: the violation when an imported callee is proved only if
-- a recursion terminates: it is recursive with no discharging measure, or it
-- reaches such a recursion ('via', module-qualified). A 'def' is a
-- total-correctness claim (LLMLL.md §4.2), so it may not rest on that. Same
-- 'diagKind' as 'mkCoreMembershipViolation', so every consumer keyed on the
-- kind still sees the refusal.
mkCoreTerminationAssumed :: Text -> Text -> Text -> Diagnostic
mkCoreTerminationAssumed defName callee via =
  let msg = "def '" <> defName <> "': callee '" <> callee
            <> "' is proved only if '" <> via <> "' terminates"
            <> " (a recursion with no discharging (decreases \x2026) measure); "
            <> "a def may call only functions whose termination is proved"
  in (mkError Nothing msg)
       { diagKind       = Just "core-membership-violation"
       , diagSuggestion = Just ("Add a (decreases \x2026) measure to '" <> via
                                <> "' and verify it, or declare '" <> defName <> "' as a def-shell")
       }

-- | CORE-EXCL (JSON-1): emitted when a strict-core body calls a builtin that is
-- 'def-shell'-only by construction.
--
-- Distinct from 'mkCoreMembershipViolation' because that diagnostic's remedy is
-- wrong here: it says the callee "is not body-faithful" and suggests running
-- @llmll verify@ on it, and neither applies to a sealed builtin. A @json-*@ or
-- @wasi.*@ name has no LLMLL body to verify and never will, so the only remedy
-- is to move the caller to @def-shell@. Pointing an agent at a verification run
-- that cannot exist is the one-shot-correctness cost this arm exists to avoid
-- (docs\/compiler-team-roadmap.md:6).
mkCoreExcludedBuiltin :: Text -> Text -> Diagnostic
mkCoreExcludedBuiltin defName callee =
  let why | "json-" `T.isPrefixOf` callee =
              "JSON values are an opaque carrier, so a body touching one cannot \
              \produce a body-faithful VC"
          | "proc-" `T.isPrefixOf` callee =
              "ProcSpec values are an opaque carrier, so a body touching one cannot \
              \produce a body-faithful VC"
          | otherwise =
              "it performs IO, and effects are not admissible in a strict-core body"
      msg = "def '" <> defName <> "': callee '" <> callee
            <> "' is a def-shell-only builtin; " <> why
  in (mkError Nothing msg)
       { diagKind       = Just "core-excluded-builtin"
       , diagSuggestion = Just ("Replace (def " <> defName <> " ...) with (def-shell "
                                <> defName <> " ...); '" <> callee
                                <> "' is sealed and has no verifiable body")
       }

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

-- | Format a Diagnostic as a human-readable string.
formatDiagnostic :: Diagnostic -> Text
formatDiagnostic d =
  sevLabel (diagSeverity d) <> locationStr (diagSpan d) <> ": " <> diagMessage d
  <> maybe "" (\s -> "\n  suggestion: " <> s) (diagSuggestion d)
  where
    sevLabel SevError   = "error"
    sevLabel SevWarning = "warning"
    sevLabel SevInfo    = "info"

    locationStr Nothing = ""
    locationStr (Just sp) =
      " [" <> T.pack (spanFile sp)
      <> ":" <> tshow (spanLine sp)
      <> ":" <> tshow (spanCol sp) <> "]"

-- | Format a Diagnostic as an S-expression (for machine consumption).
formatDiagnosticSExp :: Diagnostic -> Text
formatDiagnosticSExp d =
  "(diagnostic"
  <> " :severity " <> sevStr (diagSeverity d)
  <> maybe "" (\sp ->
       " :location (" <> T.pack (spanFile sp)
       <> " " <> tshow (spanLine sp)
       <> " " <> tshow (spanCol sp) <> ")") (diagSpan d)
  <> " :message " <> quote (diagMessage d)
  <> maybe "" (\s -> " :suggestion " <> quote s) (diagSuggestion d)
  <> maybe "" (\c -> " :code " <> quote c) (diagCode d)
  <> ")"
  where
    sevStr SevError   = "error"
    sevStr SevWarning = "warning"
    sevStr SevInfo    = "info"

    quote t = "\"" <> T.replace "\"" "\\\"" t <> "\""

-- | The default (non-JSON) rendering of a parse-phase diagnostic, as
-- `llmll check` prints it. DIAG-KIND-SEXPR-1: @:kind@ follows @:phase@
-- whenever the diagnostic carries one, so this channel tells a decode
-- failure (source-decode-error, json-decode-error) from a parse failure
-- (json-parse-error) without reading the message. Additive: a consumer
-- matching "(error :phase parse" or a :message substring is unaffected.
formatParseDiagSExp :: FilePath -> Diagnostic -> Text
formatParseDiagSExp fp d =
  "(error :phase parse"
  <> maybe "" (\k -> " :kind " <> quote k) (diagKind d)
  <> " :file " <> quote (T.pack fp)
  <> maybe "" (\sp -> " :line " <> tshow (spanLine sp) <> " :col " <> tshow (spanCol sp)) (diagSpan d)
  <> " :message " <> quote (diagMessage d)
  <> maybe "" (\h -> " :hint " <> quote h) (diagSuggestion d)
  <> ")"
  where
    quote t = "\"" <> T.replace "\"" "\\\"" t <> "\""

-- ---------------------------------------------------------------------------
-- JSON Serialisation
-- ---------------------------------------------------------------------------

instance ToJSON Severity where
  toJSON SevError   = String "error"
  toJSON SevWarning = String "warning"
  toJSON SevInfo    = String "info"

instance ToJSON Diagnostic where
  toJSON d = object $
    [ "severity"      .= diagSeverity d
    , "message"       .= diagMessage d
    , "holeSensitive" .= diagHoleSensitive d
    ] ++
    maybe [] (\sp -> ["file" .= spanFile sp, "line" .= spanLine sp, "col" .= spanCol sp]) (diagSpan d) ++
    maybe [] (\s  -> ["suggestion"    .= s]) (diagSuggestion d)  ++
    maybe [] (\c  -> ["code"          .= c]) (diagCode d)        ++
    maybe [] (\k  -> ["kind"          .= k]) (diagKind d)        ++
    maybe [] (\p  -> ["pointer"       .= p]) (diagPointer d)     ++
    maybe [] (\t  -> ["inferred-type" .= t]) (diagInferredType d) ++
    maybe [] (\e  -> ["expected"      .= e]) (diagExpected d)    ++
    maybe [] (\g  -> ["got"           .= g]) (diagGot d)         ++
    maybe [] (\h  -> ["hole"          .= h]) (diagHole d)

instance ToJSON DiagnosticReport where
  toJSON r = object
    [ "phase"       .= reportPhase r
    , "success"     .= reportSuccess r
    , "diagnostics" .= reportDiagnostics r
    ]

-- | Format a single Diagnostic as a JSON object string.
formatDiagnosticJson :: Diagnostic -> Text
formatDiagnosticJson = T.pack . TL.unpack . TLE.decodeUtf8 . encode

-- | Format a full DiagnosticReport as a JSON object string.
formatReportJson :: DiagnosticReport -> Text
formatReportJson = T.pack . TL.unpack . TLE.decodeUtf8 . encode

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- Megaparsec bridge
-- ---------------------------------------------------------------------------

-- | Convert a Megaparsec 'ParseErrorBundle' into a 'Diagnostic' with a
-- proper source span.  Uses 'errorBundlePretty' for the message text and
-- 'attachSourcePos' to recover line \/col from the byte offset.
megaparsecToDiagnostic :: FilePath -> ParseErrorBundle T.Text Void -> Diagnostic
megaparsecToDiagnostic fp bundle =
  let prettyMsg   = T.pack (errorBundlePretty bundle)
      -- Walk the error list with source positions attached.
      errList     = NE.toList (fst (attachSourcePos errorOffset (bundleErrors bundle) (bundlePosState bundle)))
      -- Take the first error's position.
      mPos        = case errList of
                      []           -> Nothing
                      ((_, pos):_) -> Just pos
      mSpan       = fmap (\pos ->
                      Span fp
                           (fromIntegral (unPos (sourceLine   pos)))
                           (fromIntegral (unPos (sourceColumn pos)))
                           (fromIntegral (unPos (sourceLine   pos)))
                           (fromIntegral (unPos (sourceColumn pos))))
                    mPos
      -- Strip the "<file>:line:col:\n" prefix that errorBundlePretty adds,
      -- so downstream formatters can append their own location info.
      cleanMsg    = stripLocationPrefix prettyMsg
      -- The generic hint is wrong for an error that already says what to do
      -- instead. Today that is only the retired `:mode http` (MODE-HTTP-1):
      -- the error sits inside a def-main, so "use def ... at the top level"
      -- pointed the reader away from the actual fix.
      isHttpRetired = any isHttpFail (NE.toList (bundleErrors bundle))
      isHttpFail (FancyError _ fs) =
        ErrorFail (T.unpack modeHttpRetiredMessage) `Set.member` fs
      isHttpFail _ = False
      -- FLOAT-LIT-1: a float literal outside the range rule fails with a
      -- message that begins "float-literal-range:" (LLMLL.FloatLit). It is a
      -- parse-phase diagnostic because only the parser has the literal's
      -- text, and it carries the kind so a consumer need not read the message.
      isFloatRange = any isFloatRangeFail (NE.toList (bundleErrors bundle))
      isFloatRangeFail (FancyError _ fs) =
        any (\f -> case f of
                     ErrorFail m -> "float-literal-range:" `T.isPrefixOf` T.pack m
                     _           -> False) (Set.toList fs)
      isFloatRangeFail _ = False
      suggestion
        | isHttpRetired = Nothing
        | isFloatRange  = Just "write a float literal whose value is finite and, unless it is zero, at least about 4.9e-324 in magnitude"
        | otherwise     = Just "use def, def-shell, type, import, or check at the top level"
      kind
        | isFloatRange = Just "float-literal-range"
        | otherwise    = Nothing
  in (Diagnostic SevError mSpan cleanMsg suggestion (Just "E001") Nothing Nothing Nothing False Nothing Nothing Nothing) { diagKind = kind }
  where
    stripLocationPrefix t =
      -- errorBundlePretty lines: "<file>:line:col:\nerror: ..."
      let ls = T.lines t
      in case ls of
           (_hdr:rest) -> T.strip (T.unlines rest)
           []          -> t

-- | MODE-HTTP-1: the parse error for @:mode http@. It lives here rather than
-- in LLMLL.Parser so 'megaparsecToDiagnostic' can recognise it and omit the
-- generic top-level hint. The text is quoted verbatim by CHANGELOG v0.29.0.
modeHttpRetiredMessage :: Text
modeHttpRetiredMessage =
  ":mode http is not supported: no HTTP server harness exists. Outbound \
  \HTTP calls are wasi.http.* commands from a console or cli program. The \
  \server design is tracked as HTTP-SERVE-1."

-- ---------------------------------------------------------------------------
-- TOOL-ENCODING-1: source decoding, pinned to UTF-8
-- ---------------------------------------------------------------------------
--
-- LLMLL.md 2 says source files are UTF-8. Until this landed the compiler read
-- them through `TIO.readFile`, which decodes via the AMBIENT LOCALE, so a
-- source file's meaning depended on the environment that compiled it. On a
-- POSIX-locale Linux host every one of the 15 fixtures in scripts/doc-claims/
-- failed to read at all. macOS cannot reproduce that: GHC there resolves UTF-8
-- under every LC_ALL, which is why the defect survived to v0.14.92.
--
-- The decode failure is routed to an ordinary parse Diagnostic rather than to a
-- new error channel, so it flows through the existing `emitParseDiag` path and
-- classifies as `parse-error`. The decode/parse distinction lives in `diagKind`
-- (`source-decode-error`), mirroring ParserJSON's existing json-decode-error /
-- json-parse-error split rather than inventing a second mechanism for the same
-- distinction.
--
-- THE MESSAGE IS LOAD-BEARING AND THAT IS NOT A STYLE PREFERENCE.
-- `emitParseDiag` renders :phase/:file/:line/:col/:message/:hint and does NOT
-- render diagKind, so on the default S-expression channel the message text is
-- the ONLY thing distinguishing "your bytes are wrong" from "your syntax is
-- wrong". It therefore names the encoding in words, the offending byte in hex,
-- and the position; each of those three is separately tested.

-- | The UTF-8 byte-order mark, which LLMLL source may not carry.
utf8Bom :: BS.ByteString
utf8Bom = BS.pack [0xEF, 0xBB, 0xBF]

-- | Byte offset of the first byte that does not begin or continue a valid UTF-8
-- sequence, or 'Nothing' when the whole input is valid UTF-8.
--
-- Written out rather than read off 'Data.Text.Encoding.decodeUtf8'' because
-- that function's 'UnicodeException' carries the offending BYTE and not its
-- POSITION, and this row owes a diagnostic naming line and column.
--
-- The table is Unicode table 3-7, so overlong encodings (0xC0 and 0xC1; 0xE0
-- below 0xA0; 0xF0 below 0x90), surrogates (0xED at or above 0xA0) and scalar
-- values above U+10FFFF (0xF4 above 0x8F, and 0xF5 upward) are all rejected
-- rather than silently admitted.
firstInvalidUtf8Offset :: BS.ByteString -> Maybe Int
firstInvalidUtf8Offset bs = go 0
  where
    len  = BS.length bs
    at i = BS.index bs i
    cont i lo hi = i < len && at i >= lo && at i <= hi
    go i
      | i >= len               = Nothing
      | b <  0x80              = go (i + 1)
      | b >= 0xC2 && b <= 0xDF = sq2 0x80 0xBF
      | b == 0xE0              = sq3 0xA0 0xBF
      | b >= 0xE1 && b <= 0xEC = sq3 0x80 0xBF
      | b == 0xED              = sq3 0x80 0x9F
      | b >= 0xEE && b <= 0xEF = sq3 0x80 0xBF
      | b == 0xF0              = sq4 0x90 0xBF
      | b >= 0xF1 && b <= 0xF3 = sq4 0x80 0xBF
      | b == 0xF4              = sq4 0x80 0x8F
      | otherwise              = Just i
      where
        b = at i
        sq2 lo hi
          | cont (i+1) lo hi = go (i + 2)
          | otherwise        = Just i
        sq3 lo hi
          | cont (i+1) lo hi && cont (i+2) 0x80 0xBF = go (i + 3)
          | otherwise                                = Just i
        sq4 lo hi
          | cont (i+1) lo hi && cont (i+2) 0x80 0xBF && cont (i+3) 0x80 0xBF = go (i + 4)
          | otherwise                                                        = Just i

-- | 1-based line and column of a byte offset.
--
-- Counting 0x0A on RAW BYTES is exact here rather than approximate: every UTF-8
-- continuation byte is at or above 0x80, so 0x0A can never occur inside a
-- multi-byte sequence. The prefix before the offending offset is by
-- construction valid UTF-8, which is what makes the count unambiguous.
offsetLineCol :: BS.ByteString -> Int -> (Int, Int)
offsetLineCol bs off =
  let prefix = BS.take off bs
      nls    = BS.count 0x0A prefix
  in ( nls + 1
     , case BS.elemIndexEnd 0x0A prefix of
         Nothing -> off + 1
         Just k  -> off - k
     )

hexByte :: Word8 -> Text
hexByte w = let s = showHex w "" in T.pack (if length s < 2 then '0' : s else s)

-- | Decode LLMLL source as UTF-8, independent of the ambient locale.
--
-- The codec is authoritative for accept/reject; 'firstInvalidUtf8Offset' runs
-- ONLY on the failure path, to locate what the codec already refused. So the
-- success path pays nothing for the position arithmetic.
-- | BUILD-ENCODING-1: the write side of the same rule. `TIO.writeFile`
-- ENCODES through the ambient locale, so under a POSIX or C locale on Linux
-- any non-ASCII character in the text fails the write with `withFile: invalid
-- argument (cannot encode character ...)`. The generated `Lib.hs` preamble
-- carries em dashes in its comments, so under that locale `llmll build`
-- failed for EVERY program. Found by the doc-claims cover, which sets no
-- locale on purpose, on the first CI run of its `@run` path (v0.25.3); macOS
-- cannot reproduce it, for the reason given above.
writeFileUtf8 :: FilePath -> Text -> IO ()
writeFileUtf8 fp = BS.writeFile fp . TE.encodeUtf8

decodeSourceUtf8 :: FilePath -> BS.ByteString -> Either Diagnostic Text
decodeSourceUtf8 fp bs
  | utf8Bom `BS.isPrefixOf` bs = Left bomDiag
  | otherwise =
      case TE.decodeUtf8' bs of
        Right t -> Right t
        Left _  -> Left (invalidDiag (fromMaybe 0 (firstInvalidUtf8Offset bs)))
  where
    bomDiag =
      (mkError (Just (Span fp 1 1 1 1))
        "source file begins with a UTF-8 byte-order mark (U+FEFF); LLMLL source files must not carry one")
        { diagKind       = Just "source-bom"
        , diagSuggestion = Just "re-save the file as UTF-8 with no byte-order mark"
        }
    invalidDiag off =
      let (ln, col) = offsetLineCol bs off
          byte      = if off < BS.length bs then BS.index bs off else 0
      in (mkError (Just (Span fp ln col ln col))
            ( "source file is not valid UTF-8: invalid byte 0x" <> hexByte byte
           <> " at line " <> tshow ln <> ", column " <> tshow col
           <> ". LLMLL source files are UTF-8 and the host locale is not consulted." ))
           { diagKind       = Just "source-decode-error"
           , diagSuggestion = Just "re-save the file as UTF-8"
           }
