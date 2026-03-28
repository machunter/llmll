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
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
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
      suggestion  = Just "use def-logic, type, import, or check at the top level (v0.1.1 single-file model)"
  in (Diagnostic SevError mSpan cleanMsg suggestion (Just "E001") Nothing Nothing Nothing False Nothing Nothing Nothing)
  where
    stripLocationPrefix t =
      -- errorBundlePretty lines: "<file>:line:col:\nerror: ..."
      let ls = T.lines t
      in case ls of
           (_hdr:rest) -> T.strip (T.unlines rest)
           []          -> t
