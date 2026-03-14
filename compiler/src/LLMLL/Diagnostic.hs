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
  , formatDiagnostic
  , formatDiagnosticSExp
  , formatDiagnosticJson
  , formatReportJson
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Data.Aeson (ToJSON(..), object, (.=), encode)
import Data.Aeson.Types (Value(..))
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
  { diagSeverity   :: Severity
  , diagSpan       :: Maybe Span
  , diagMessage    :: Text
  , diagSuggestion :: Maybe Text
  , diagCode       :: Maybe Text    -- ^ e.g. "E001", "W002"
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
mkError sp msg = Diagnostic SevError sp msg Nothing Nothing

mkWarning :: Maybe Span -> Text -> Diagnostic
mkWarning sp msg = Diagnostic SevWarning sp msg Nothing Nothing

mkInfo :: Maybe Span -> Text -> Diagnostic
mkInfo sp msg = Diagnostic SevInfo sp msg Nothing Nothing

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
    [ "severity" .= diagSeverity d
    , "message"  .= diagMessage d
    ] ++
    maybe [] (\sp -> ["file" .= spanFile sp, "line" .= spanLine sp, "col" .= spanCol sp]) (diagSpan d) ++
    maybe [] (\s  -> ["suggestion" .= s]) (diagSuggestion d) ++
    maybe [] (\c  -> ["code" .= c])       (diagCode d)

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
