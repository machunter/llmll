{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.Replay
-- Description : Replay an event log against a compiled program (v0.3.1).
--
-- Parses a @.event-log.jsonl@ file line-by-line and compares
-- recorded inputs/outputs against a fresh execution of the program.
module LLMLL.Replay
  ( ReplayResult(..)
  , parseEventLog
  , EventLogEntry(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T

-- | A single event from the JSONL log.
data EventLogEntry = EventLogEntry
  { evSeq       :: Int
  , evInputKind :: Text
  , evInputVal  :: Text
  , evResultKind :: Text
  , evResultVal  :: Text
  } deriving (Show, Eq)

-- | Result of a replay comparison.
data ReplayResult = ReplayResult
  { replayTotal    :: Int
  , replayMatched  :: Int
  , replayDiverged :: [(Int, Text, Text)]  -- (seq, expected, actual)
  } deriving (Show, Eq)

-- | Parse a @.event-log.jsonl@ file into entries.
--   Skips the header line and any malformed lines (crash tolerance).
parseEventLog :: Text -> [EventLogEntry]
parseEventLog contents =
  [ entry
  | line <- T.lines contents
  , T.isInfixOf "\"type\":\"event\"" line
  , Just entry <- [parseEventLine line]
  ]

-- | Parse a single JSONL event line.
--   Strategy: split by known structural markers to extract field values.
parseEventLine :: Text -> Maybe EventLogEntry
parseEventLine line = do
  sq <- extractSeq line
  -- Find "input":{ and "result":{ sections
  let (_, afterInput) = T.breakOn "\"input\":{" line
  let inputSection = T.take 200 (T.drop (T.length "\"input\":{") afterInput)
  ik <- extractFieldVal "\"kind\":\"" inputSection
  iv <- extractFieldVal "\"value\":\"" inputSection
  let (_, afterResult) = T.breakOn "\"result\":{" line
  let resultSection = T.take 200 (T.drop (T.length "\"result\":{") afterResult)
  rk <- extractFieldVal "\"kind\":\"" resultSection
  rv <- extractFieldVal "\"value\":\"" resultSection
  Just EventLogEntry
    { evSeq = sq
    , evInputKind = ik
    , evInputVal = unescape iv
    , evResultKind = rk
    , evResultVal = unescape rv
    }

-- | Extract the seq integer value.
extractSeq :: Text -> Maybe Int
extractSeq txt = do
  let (_, after) = T.breakOn "\"seq\":" txt
  if T.null after then Nothing
  else do
    let rest = T.drop (T.length "\"seq\":") after
    let numTxt = T.takeWhile (\c -> c >= '0' && c <= '9') rest
    case reads (T.unpack numTxt) of
      [(n, "")] -> Just n
      _         -> Nothing

-- | Extract a JSON string value after a key like @"kind":"@
--   Handles escaped quotes by scanning for unescaped closing quote.
extractFieldVal :: Text -> Text -> Maybe Text
extractFieldVal key section = do
  let (_, after) = T.breakOn key section
  if T.null after then Nothing
  else do
    let rest = T.drop (T.length key) after
    Just (takeJsonString rest)

-- | Take characters until unescaped double quote.
--   Handles \" and \\ escape sequences.
takeJsonString :: Text -> Text
takeJsonString = T.pack . go . T.unpack
  where
    go [] = []
    go ('\\' : '"' : cs) = '\\' : '"' : go cs
    go ('\\' : '\\' : cs) = '\\' : '\\' : go cs
    go ('\\' : c : cs) = '\\' : c : go cs
    go ('"' : _) = []
    go (c : cs) = c : go cs

-- | Unescape basic JSON escape sequences.
unescape :: Text -> Text
unescape = T.pack . go . T.unpack
  where
    go [] = []
    go ('\\' : '"' : cs) = '"' : go cs
    go ('\\' : 'n' : cs) = '\n' : go cs
    go ('\\' : '\\' : cs) = '\\' : go cs
    go ('\\' : c : cs) = c : go cs
    go (c : cs) = c : go cs
