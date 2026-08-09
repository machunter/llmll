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
  , runReplay
    -- * Event framing (REPLAY-FRAME)
    --
    -- Exported for unit testing: these four are the whole of the
    -- alignment and diagnostic contract, and they are pure, so the
    -- suite can pin them without spawning a process.
  , ReplayObs(..)
  , expectedLineCount
  , obsMatches
  , describeObs
  , escapeForDiag
  , runCapturingExit
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import System.Process (createProcess, proc, std_in, std_out, StdStream(..), waitForProcess)
import System.IO (Handle, hPutStrLn, hFlush, hGetLine, hSetBuffering, BufferMode(..), hClose, hSetEncoding, utf8)
import Control.Exception (try, SomeException)
import System.Exit (ExitCode(..))
import System.Timeout (timeout)

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

-- | What the replayed process actually produced for one event.
--
--   REPLAY-DIAG: 'replayOne' used to return a bare 'Bool' and throw the
--   observation away, so every divergence was reported with the constant
--   @"\<no output\>"@ and a WRONG output was indistinguishable in the
--   diagnostic from NO output. Measured before the fix: a program that
--   printed @ON-DONE-RAN@ on the diverging turn was reported as
--   @actual="\<no output\>"@. Carrying the observation out is the whole
--   of that repair.
data ReplayObs
  = ObsLines Text
    -- ^ The process produced exactly the lines the entry called for.
  | ObsTruncated Text
    -- ^ Some lines arrived, then the stream ended mid-event. The payload is
    --   what did arrive, which is the informative half of the diagnostic.
  | ObsStalled Text
    -- ^ The process is still alive but produced no further line within
    --   'replayLineTimeoutMicros'. Distinct from 'ObsTruncated': the stream did
    --   not end, replay simply stopped waiting. Reachable only from a log that
    --   claims more lines than the program writes, which a harness-written log
    --   never does and a TAMPERED one can. See 'readNLines'.
  | ObsEof
    -- ^ The stream ended before any line of this event.
  | ObsNoCommand
    -- ^ The entry records @"kind":"none"@: no command ran on this turn, so
    --   there is no output to read and nothing to compare. See 'obsMatches'.
  deriving (Show, Eq)

-- | REPLAY-FRAME: how many lines of the child's stdout belong to one event.
--
--   The generated console harness writes each event's output with
--   @putStrLn output@ (@CodegenHs.hs:1461@), so the bytes on the wire for one
--   event are exactly @output ++ "\\n"@, which contains
--   @count '\\n' output + 1@ newlines. Reading that many lines and rejoining
--   them with @'\\n'@ therefore reconstructs @output@ exactly, and consumes
--   exactly the bytes that event wrote — no more, no fewer.
--
--   The previous rule was the constant 1, which is correct only for output
--   that is exactly one line. Measured against the shipped emitter, it failed
--   two ways:
--
--     * A step printing @"line-A\\nline-B"@ replayed 0/2: the first read got
--       @line-A@, compared it against the two-line expectation, and every
--       later event was shifted by the unconsumed remainder.
--     * A step printing @"echo-0\\n"@ replayed 1/2 in the WORSE way: seq 0
--       "matched" because 'T.strip' erased the trailing newline, the blank
--       line stayed on the pipe, and the divergence surfaced at seq 1 — so
--       the report named a turn that was not the cause.
--
--   TOTALITY, and this is why the change needs no deprecation path: the new
--   rule can never turn a match into a mismatch.
--
--     * Zero newlines in @expected@ (every event a single-line program
--       produces): the count is 1, so the behaviour is byte-identical to the
--       old constant.
--     * Interior newlines: one line read can never 'T.strip'-equal an
--       expectation containing an interior newline, because 'T.strip' removes
--       only leading and trailing whitespace. Those events diverge under the
--       old rule unconditionally, so the change can only move them
--       mismatch → match.
--     * Trailing newlines only: matched under the old rule (via 'T.strip')
--       and still match under the new one, with the leftover blank line now
--       consumed instead of desynchronizing every later event.
--
--   No fourth case exists, so the direction of change is one-way.
expectedLineCount :: EventLogEntry -> Int
expectedLineCount e = succ (T.count (T.pack "\n") (evResultVal e))

-- | Does an observation discharge its entry?
--
--   RC-4 / A2, and the limit is deliberate: an @ObsNoCommand@ entry always
--   matches, because the log recorded that no command ran on that turn. Such
--   an entry CAN MATCH WHILE CARRYING NO INFORMATION. A green replay of a
--   program with @:on-done@ is therefore NOT evidence that @:on-done@ ran, or
--   ran correctly — its output is performed outside 'captureStdout' and is
--   not in the log at all (@CodegenHs.hs:1573-1583@). Whether to bring it
--   inside the oracle is REPLAY-INJECT's question, not this function's; the
--   point here is that the limit is written down rather than inferred from a
--   passing count.
obsMatches :: EventLogEntry -> ReplayObs -> Bool
obsMatches _ ObsNoCommand     = True
obsMatches e (ObsLines t)     = T.strip (evResultVal e) == T.strip t
obsMatches _ (ObsTruncated _) = False
obsMatches _ (ObsStalled _)   = False
obsMatches _ ObsEof           = False

-- | Render an observation for the @actual=@ half of a divergence report.
describeObs :: ReplayObs -> Text
describeObs (ObsLines t)     = t
describeObs (ObsTruncated t) = t <> T.pack " <stream ended mid-event>"
describeObs (ObsStalled t)   = t <> T.pack " <no further output; log claims more lines than the program wrote>"
describeObs ObsEof           = T.pack "<no output: stream ended>"
describeObs ObsNoCommand     = T.pack "<no command recorded>"

-- | Escape control characters so a divergence stays on ONE reported line.
--
--   Done here rather than at the print site in @app\/Main.hs@ because
--   @app\/Main.hs@ is the executable component and is not reachable from the
--   test suite; a pure helper in the library is.
escapeForDiag :: Text -> Text
escapeForDiag =
    T.replace (T.pack "\t") (T.pack "\\t")
  . T.replace (T.pack "\r") (T.pack "\\r")
  . T.replace (T.pack "\n") (T.pack "\\n")

-- | Run replay: spawn the compiled executable, feed inputs step-by-step,
--   capture outputs, and compare against logged results.
--   Uses step-by-step I/O synchronization (professor flag D1):
--   write one input → read this event's lines → compare → next.
runReplay :: FilePath -> [EventLogEntry] -> IO ReplayResult
runReplay execPath entries = do
  let cp = (proc execPath []) { std_in = CreatePipe, std_out = CreatePipe }
  (Just hin, Just hout, _, ph) <- createProcess cp
  hSetBuffering hin LineBuffering
  hSetBuffering hout LineBuffering
  -- TOOL-ENCODING-1. createProcess hands back handles carrying the codec
  -- getLocaleEncoding supplied, so replaying a program that prints non-ASCII
  -- failed under a POSIX locale. A per-handle pin is sufficient HERE, unlike in
  -- a generated program: nothing downstream duplicates these handles, so there
  -- is no captureStdout-style pair to rebuild the codec behind them.
  hSetEncoding hin utf8
  hSetEncoding hout utf8
  observations <- mapM (replayOne hin hout) entries
  hClose hin
  _ <- waitForProcess ph
  let outcomes = zip entries observations
      matched  = length [ () | (e, o) <- outcomes, obsMatches e o ]
      diverged = [ ( evSeq e
                   , escapeForDiag (evResultVal e)
                   , escapeForDiag (describeObs o) )
                 | (e, o) <- outcomes, not (obsMatches e o) ]
  pure ReplayResult
    { replayTotal = length entries
    , replayMatched = matched
    , replayDiverged = diverged
    }

-- | Replay a single event: write input, read this event's output, report it.
--   Step-by-step sync (professor flag D1). The console loop is line-based, so
--   hGetLine blocks correctly until output is ready.
--
--   The input is written on EVERY entry, including an @ObsNoCommand@ one: the
--   terminating turn still CONSUMES a stdin line even though it performs no
--   command (@CodegenHs.hs:1518-1521@), so skipping the write would leave
--   replay driving one fewer input than the recorded run did.
replayOne :: Handle -> Handle -> EventLogEntry -> IO ReplayObs
replayOne hin hout entry = do
  hPutStrLn hin (T.unpack (evInputVal entry))
  hFlush hin
  if evResultKind entry == T.pack "none"
    then pure ObsNoCommand
    else readNLines hout (expectedLineCount entry)

-- | How long to wait for one line before declaring the stream stalled.
--
--   Needed because 'expectedLineCount' trusts the log. A harness-written log
--   never over-claims (the emitter writes @output ++ "\\n"@, so the count is
--   exact by construction), but `llmll replay` is a determinism oracle and a
--   TAMPERED log is exactly the input it exists to judge. Without a deadline,
--   a log whose recorded output gained a newline makes replay read a line the
--   program never writes, and since the program is blocked waiting for the
--   next stdin line that replay will not send until the read returns, the two
--   deadlock. The old one-line-per-event rule could not over-read and so had
--   no such state; this is the cost of reading the count from the log, and a
--   bounded wait is the price.
--
--   Ten seconds is per LINE, not per replay, and only a failing replay ever
--   waits: a correct one always has its line already buffered.
replayLineTimeoutMicros :: Int
replayLineTimeoutMicros = 10 * 1000 * 1000

-- | Read @n@ lines and rejoin them with newlines, reporting a short read.
readNLines :: Handle -> Int -> IO ReplayObs
readNLines hout = go []
  where
    go acc 0 = pure (ObsLines (joined acc))
    go acc k = do
      mResult <- timeout replayLineTimeoutMicros
                   (try (hGetLine hout) :: IO (Either SomeException String))
      case mResult of
        Nothing -> pure (ObsStalled (joined acc))
        Just (Left _)
          | null acc  -> pure ObsEof
          | otherwise -> pure (ObsTruncated (joined acc))
        Just (Right l) -> go (T.pack l : acc) (k - 1)
    joined = T.intercalate (T.pack "\n") . reverse

-- | Run an IO action that always terminates the whole process via
--   'System.Exit.exitWith' \/ 'exitSuccess' \/ 'exitFailure' on every code
--   path (this is how @doBuild@\/@doBuildFromJson@ in app\/Main.hs behave),
--   intercepting the resulting 'ExitCode' instead of letting it propagate
--   up through the RTS and kill the caller outright.
--
--   BUG-1 (v0.14.3): @doReplay@ used to call such a build step directly.
--   Every path through @doBuild@ ends in 'exitSuccess' or 'exitFailure', so
--   the call unconditionally terminated the whole @llmll replay@ invocation
--   before it ever reached 'runReplay' below it — the replay summary
--   ("N\/N events matched") was dead, unreachable code. Wrapping the build
--   sub-step in 'runCapturingExit' lets the caller inspect the outcome: on
--   'ExitSuccess' it continues to 'runReplay'; on 'ExitFailure' it should
--   re-raise via 'System.Exit.exitWith' so a build failure still fails the
--   whole command (no silent swallow).
--
--   'System.Exit.exitWith' is documented to work by throwing an 'ExitCode'
--   exception that the RTS normally catches at the top level; catching it
--   ourselves first is the standard technique for running an
--   exit-terminated sub-step without dying with it.
runCapturingExit :: IO () -> IO ExitCode
runCapturingExit act = either id (const ExitSuccess) <$> try act
