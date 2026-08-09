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
  , formatDiagnosticJson
  , formatReportJson
  , megaparsecToDiagnostic
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
  -- * v0.3.5: Weakness check
  , mkSpecWeakness
  , mkCandidateUnvalidated
  -- * v0.4: Capability enforcement (CAP-1)
  , mkMissingCapability
  -- * LT-INV (v0.11): core/shell grammar violations
  , mkCoreGrammarViolation
  , mkCoreMembershipViolation
  , mkCoreExcludedBuiltin
  -- * REFINE-REUSE: non-blocking reuse-duplicate warning
  , mkReuseWarning
  , mkContractReadOOBWarning
  -- * TOOL-ENCODING-1: source decoding pinned to UTF-8
  , decodeSourceUtf8
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
import Text.Megaparsec.Error (errorOffset)
import Text.Megaparsec.Pos (unPos, sourceLine, sourceColumn)
import LLMLL.Syntax (Span(..))
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
mkTrustGapWarning funcName level pointer =
  let msg = "Function " <> funcName <> " has an unproven contract (level: "
            <> level <> "). Your module inherits this trust gap. "
            <> "Silence with: (trust " <> funcName <> " :level " <> level <> ")"
  in (mkWarning Nothing msg)
       { diagKind = Just "trust-gap"
       , diagPointer = Just pointer
       }

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
      suggestion  = Just "use def, def-shell, type, import, or check at the top level"
  in (Diagnostic SevError mSpan cleanMsg suggestion (Just "E001") Nothing Nothing Nothing False Nothing Nothing Nothing)
  where
    stripLocationPrefix t =
      -- errorBundlePretty lines: "<file>:line:col:\nerror: ..."
      let ls = T.lines t
      in case ls of
           (_hdr:rest) -> T.strip (T.unlines rest)
           []          -> t

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
