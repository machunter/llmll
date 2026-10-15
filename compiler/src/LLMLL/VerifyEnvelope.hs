{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.VerifyEnvelope
-- Description : TRUST-REPORT-GATE-1: the one JSON document @llmll verify --json@ prints.
--
-- Under @--json@, @llmll verify@ prints exactly one top-level JSON document on
-- stdout, for every combination of flags (design §3.3,
-- docs/design/trust-report-gate-1-proposal.md). The document is the verdict
-- object. It states its own outcome first, then the versions it composes, then
-- every key of the pre-v0.30.0 verdict object, then each requested report under
-- a fixed key.
--
-- Key order, top level:
--
--   1. @verify_json_version@ ('verifyJsonVersion');
--   2. @exit_code@, the status the process returns. 'Main.finishVerify' passes
--      the same value to 'exitWith', so the two cannot differ;
--   3. @solver_verdict@: @safe@, @refuted@, @error@, or @not-run@ for the two
--      exits that come before the solver (the pre-solver strict-core refusal and
--      solver absent);
--   4. @composed@: the versions of the nested reports, computed from the
--      emitters ('trustReportEmitVersion', 'expectedSchemaVersion', and the
--      obligation report's own @schema_version@ when that report is present);
--   5. the verdict keys, in the order they were emitted before;
--   6. the nested reports, in 'nestedReportKeys' order, each only when present.
--
-- The object is rendered by hand because an aeson 'Object' sorts its keys.
module LLMLL.VerifyEnvelope
  ( VerifyEnvelope(..)
  , verifyJsonVersion
  , nestedReportKeys
  , envelopeFields
  , renderEnvelope
  ) where

import           Data.Aeson          (Value(..), decode, toJSON)
import qualified Data.Aeson.KeyMap   as KM
import           Data.Aeson.Text     (encodeToLazyText)
import qualified Data.ByteString.Lazy as BL
import           Data.Text           (Text)
import qualified Data.Text           as T
import qualified Data.Text.Encoding  as TE
import qualified Data.Text.Lazy      as TL

import           LLMLL.TrustReport   (trustReportEmitVersion)
import           LLMLL.ParserJSON    (expectedSchemaVersion)

-- | The envelope's inputs. 'veVerdict' carries the verdict keys as values;
-- 'veNested' carries each report as the raw JSON text its formatter produced,
-- keyed by its §3.3 key.
data VerifyEnvelope = VerifyEnvelope
  { veExitCode      :: Int
  , veSolverVerdict :: Text
  , veVerdict       :: [(Text, Value)]
  , veNested        :: [(Text, Text)]
  } deriving (Show, Eq)

-- | The version of the envelope's own shape.
verifyJsonVersion :: Text
verifyJsonVersion = "1.0.0"

-- | The fixed key of each nested report, in emit order (design §3.3).
nestedReportKeys :: [Text]
nestedReportKeys =
  [ "trust_report", "spec_coverage", "weakness"
  , "obligation_suggestions", "obligation_report", "strict_errors" ]

-- | The top-level fields in order, each value as raw JSON text. A verdict key
-- that collides with an envelope key is dropped (only @solver_verdict@ does
-- today; it moves to the head). A nested key appears once, last value wins.
envelopeFields :: VerifyEnvelope -> [(Text, Text)]
envelopeFields ve =
     [ ("verify_json_version", enc (String verifyJsonVersion))
     , ("exit_code",           T.pack (show (veExitCode ve)))
     , ("solver_verdict",      enc (String (veSolverVerdict ve)))
     , ("composed",            renderObject composed)
     ]
  ++ [ (k, enc v) | (k, v) <- veVerdict ve, k `notElem` reserved ]
  ++ [ (k, raw) | k <- nestedReportKeys, Just raw <- [lookupLast k (veNested ve)] ]
  where
    reserved = ["verify_json_version", "exit_code", "solver_verdict", "composed"] ++ nestedReportKeys
    composed =
         [ ("trust_report_version", enc (String trustReportEmitVersion))
         , ("schema_version",       enc (String expectedSchemaVersion)) ]
      ++ [ ("obligation_report_schema_version", enc v)
         | Just raw <- [lookupLast "obligation_report" (veNested ve)]
         , Just (Object o) <- [decode (BL.fromStrict (TE.encodeUtf8 raw)) :: Maybe Value]
         , Just v <- [KM.lookup "schema_version" o] ]
    lookupLast k xs = case [ v | (k', v) <- xs, k' == k ] of
      [] -> Nothing
      vs -> Just (last vs)

-- | The envelope as one line of JSON.
renderEnvelope :: VerifyEnvelope -> Text
renderEnvelope = renderObject . envelopeFields

renderObject :: [(Text, Text)] -> Text
renderObject kvs = "{" <> T.intercalate "," [ enc (String k) <> ":" <> v | (k, v) <- kvs ] <> "}"

enc :: Value -> Text
enc = TL.toStrict . encodeToLazyText . toJSON
