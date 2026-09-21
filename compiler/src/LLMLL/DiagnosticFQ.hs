-- |
-- Module      : LLMLL.DiagnosticFQ
-- Description : Parse liquid-fixpoint output → [Diagnostic] with JSON Pointers.
--
-- D4: liquid-fixpoint returns SAFE or UNSAFE with constraint IDs.
-- We map each failed constraint ID back to a Diagnostic using the ConstraintTable
-- built by FixpointEmit. The Diagnostic carries a JSON Pointer to the original
-- .ast.json location so AI agents can iterate precisely.

module LLMLL.DiagnosticFQ
  ( -- * Constraint origin table
    ConstraintOrigin(..)
  , ConstraintTable
    -- * Parse liquid-fixpoint output
  , FQVerifyResult(..)
  , parseFQResult
  , parseFQResultJSON
  , parseFQOutcome
    -- * Where the constraint file goes
  , fqPathFor
  , pathTag
  , fqResultToReport
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe, fromMaybe, listToMaybe)
import qualified Data.Aeson as A
import Data.Aeson (Value(..))
import qualified Data.Aeson.KeyMap as KM
import Data.Aeson.Types (parseMaybe, parseJSON)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as BL
import Data.Foldable (toList)
import System.Exit (ExitCode(..))
import System.FilePath (takeBaseName)
import Numeric (showHex)
import qualified Crypto.Hash.SHA256 as SHA
import qualified Data.ByteString as BS

import LLMLL.FixpointIR (FQConstraintId)
import LLMLL.Diagnostic
  ( Diagnostic(..), DiagnosticReport(..), Severity(..)
  , mkError, reportDiagnostics )

-- ---------------------------------------------------------------------------
-- Constraint origin table
-- ---------------------------------------------------------------------------

-- | Where in the LLMLL source a given constraint originated.
data ConstraintOrigin = ConstraintOrigin
  { coFunction   :: Text      -- ^ enclosing def-logic / letrec name
  , coClause     :: Text      -- ^ "pre" | "post" | "decreases" | "body-post" | "call-pre:<callee>"
  , coJsonPtr    :: Text      -- ^ JSON Pointer: "/statements/2/pre"
  , coSourceFile :: FilePath  -- ^ original .llmll or .ast.json path
  } deriving (Show)

-- | Map from constraint ID to its origin in the LLMLL source.
type ConstraintTable = Map FQConstraintId ConstraintOrigin

-- ---------------------------------------------------------------------------
-- Parse liquid-fixpoint output
-- ---------------------------------------------------------------------------

data FQVerifyResult
  = FQSafe
  | FQUnsafe [FQConstraintId]  -- ^ IDs of failed constraints
  | FQError  Text              -- ^ liquid-fixpoint binary error / parse error
  deriving (Show, Eq)

-- | Parse liquid-fixpoint stdout into a structured result.
--
-- liquid-fixpoint output format:
--   SAFE
-- or:
--   UNSAFE
--   <N> constraints violated
--   ...constraint id <N>...
parseFQResult :: Text -> FQVerifyResult
parseFQResult out
  | safeIn && not unsafeIn = FQSafe
  | unsafeIn               = FQUnsafe (extractIds out)
  | otherwise              = FQError out
  where
    outUp    = T.toUpper out
    safeIn   = "SAFE"   `T.isInfixOf` outUp
    unsafeIn = "UNSAFE" `T.isInfixOf` outUp
    -- Extract constraint IDs from lines like: id 47 ...
    extractIds :: Text -> [FQConstraintId]
    extractIds txt = mapMaybe parseId (T.lines txt)
      where
        parseId line =
          let ws = T.words line
          in case dropWhile (/= "id") ws of
               (_:nStr:_) -> case reads (T.unpack nStr) of
                               [(n,"")] -> Just n
                               _        -> Nothing
               _          -> Nothing

-- | VERIFY-RPT-1 (Defect 1b / pointer quality): parse the structured envelope
-- emitted by @fixpoint -q --json@. The text 'parseFQResult' path scrapes
-- constraint ids from the human banner and finds none (the @Unsafe:@ status
-- line carries no @id N@ tokens), yielding @FQUnsafe []@ — no resolvable
-- pointer. The JSON envelope carries the real ids, so they map through the
-- 'ConstraintTable' to source pointers.
--
-- Envelope shape is tag-keyed and heterogeneous in @contents@:
--   @{"tag":"Safe","contents":{stats}}@
--   @{"tag":"Unsafe","contents":[{stats},[ids]]}@
-- With @-q@ the output is a single clean JSON line; without it the line is
-- ANSI-prefixed and preceded by banner noise, so we strip ANSI and scan for a
-- JSON-object line as a robustness fallback. Returns 'Nothing' on any parse
-- failure so callers fall back to 'parseFQResult'.
parseFQResultJSON :: Text -> Maybe FQVerifyResult
parseFQResultJSON txt =
  listToMaybe (mapMaybe tryDecode candidates)
  where
    cleaned    = stripAnsi txt
    candidates = filter looksJson (T.lines cleaned) ++ [T.strip cleaned]
    looksJson l = "{" `T.isPrefixOf` T.strip l
    tryDecode s =
      A.decode (BL.fromStrict (TE.encodeUtf8 (T.strip s))) >>= envelopeToResult

    envelopeToResult :: Value -> Maybe FQVerifyResult
    envelopeToResult (Object o) =
      case KM.lookup "tag" o of
        Just (String "Safe")   -> Just FQSafe
        Just (String "Unsafe") ->
          case KM.lookup "contents" o of
            Just (Array arr) ->
              case toList arr of
                [_stats, idsV] ->
                  Just (FQUnsafe (fromMaybe [] (parseMaybe parseJSON idsV)))
                _ -> Just (FQUnsafe [])
            _ -> Just (FQUnsafe [])
        _ -> Nothing
    envelopeToResult _ = Nothing

-- | VERDICT-UNSTABLE-1: where 'llmll verify' writes the constraint file.
--
-- The default path must be unique per SOURCE FILE. It used to be
-- @"/tmp/" <> takeBaseName src <> ".fq"@, which is unique per BASENAME, so two
-- different files with the same basename shared one slot. A concurrent pair
-- then raced between the write and the solver read, and the loser handed
-- liquid-fixpoint the other file's constraints.
--
-- Measured 2026-09-20 before the fix: the census population carries 13
-- colliding basenames over 260 files, and 40 concurrent trials of a
-- same-basename pair disagreed with their own isolated verdicts 40 times. 30
-- of those reported a REFUTED file SAFE and wrote it a @verified@ sidecar, so
-- the defect failed OPEN far more often than closed.
--
-- @src@ must be ABSOLUTE. A relative path collides exactly as the basename did,
-- because two workers verifying the same repo-relative file in separate tree
-- copies would hash the same string.
--
-- The tag is stable across runs, so /tmp holds one file per source file rather
-- than one per run. That is the reason this is a hash rather than
-- 'System.IO.openTempFile': the accumulation a fresh temp file per run would
-- cause is worse than the residual it would close. The residual is two
-- concurrent runs of the SAME absolute path, which write identical bytes.
fqPathFor :: Maybe FilePath   -- ^ an explicit @--fq-out@, which is honoured as given
          -> FilePath         -- ^ the ABSOLUTE path of the source file
          -> FilePath
fqPathFor (Just out) _   = out
fqPathFor Nothing    src =
  "/tmp/llmll-" <> takeBaseName src <> "-" <> T.unpack (pathTag src) <> ".fq"

-- | Twelve hex characters of the SHA256 of a path. Used only by 'fqPathFor'.
pathTag :: FilePath -> Text
pathTag p =
  T.take 12 . T.pack . concatMap byteHex . BS.unpack
            . SHA.hash . TE.encodeUtf8 . T.pack $ p
  where
    byteHex b = let h = showHex b "" in if length h == 1 then '0':h else h

-- | VERDICT-UNSTABLE-1: decide the outcome from the exit code AND the output.
--
-- A refutation is negative evidence (@LLMLL.md@ §4.4) and
-- @--strict-verified-core@ refuses a refuted function, so a solver that DIED
-- must never be reported as one. 'parseFQResult' alone cannot tell the two
-- apart: it scans for the substring @UNSAFE@ over stdout and stderr merged, and
-- it is reached exactly when the JSON envelope does not decode, which is the
-- crash case. A killed process that emitted a partial @Unsafe@ envelope then
-- reads as @FQUnsafe []@, and a partial @Safe@ envelope reads as 'FQSafe'.
--
-- Measured against the real binary 2026-09-20: @fixpoint -q --json@ exits 0 on
-- Safe and 1 on Unsafe. Any other code means it produced no verdict. So a
-- decoded envelope is positive evidence and outranks the code, and a bare
-- text scrape must be corroborated by the matching code or it becomes
-- 'FQError'. The rule demands positive evidence; it never trusts an exit
-- status on its own.
--
-- 'parseFQResult' keeps its text-only signature for callers with no exit code.
parseFQOutcome :: ExitCode -> Text -> FQVerifyResult
parseFQOutcome code merged =
  case parseFQResultJSON merged of
    Just r  -> r          -- a decoded envelope is the solver's own answer
    Nothing -> case parseFQResult merged of
      FQUnsafe ids | code == ExitFailure 1 -> FQUnsafe ids
      FQSafe       | code == ExitSuccess   -> FQSafe
      FQError e                            -> FQError e
      _                                    -> FQError noVerdict
  where
    noVerdict =
      "produced no verdict (exit " <> renderExit code <> "): " <> merged
    renderExit ExitSuccess     = "0"
    renderExit (ExitFailure n) = T.pack (show n)

-- | Drop ANSI CSI escape sequences (@ESC [ … m@) so a banner-wrapped JSON line
-- is recoverable. Used only by 'parseFQResultJSON'.
stripAnsi :: Text -> Text
stripAnsi = go
  where
    go t = case T.break (== '\x1b') t of
      (before, rest)
        | T.null rest -> before
        | otherwise   -> before <> go (T.drop 1 (T.dropWhile (/= 'm') rest))

-- ---------------------------------------------------------------------------
-- Convert to DiagnosticReport
-- ---------------------------------------------------------------------------

-- | Convert a FQVerifyResult + ConstraintTable → DiagnosticReport.
-- Each failed constraint becomes one Diagnostic with machine-readable fields:
--   diagKind     = Just "lh-unsafe"
--   diagMessage  = human description of which clause failed
--   diagPointer  = Just "/statements/N/pre"  (JSON Pointer for AI iteration)
fqResultToReport :: FilePath -> ConstraintTable -> FQVerifyResult -> DiagnosticReport
fqResultToReport _fp _table FQSafe =
  DiagnosticReport
    { reportPhase       = "lh-fixpoint"
    , reportDiagnostics = []
    , reportSuccess     = True
    }
fqResultToReport fp table (FQUnsafe ids) =
  let diags0 = mapMaybe (toDiag fp table) ids
      -- VERIFY-RPT-1 (Defect 1b): when the solver reports UNSAFE but no
      -- constraint id resolves to a diagnostic — empty 'ids' (text-scrape
      -- failure) or ids absent from the table — synthesize a function-level
      -- fallback so the payload is never empty.
      diags  = if null diags0 then [fallbackUnsafeDiag table] else diags0
  in DiagnosticReport
    { reportPhase       = "lh-fixpoint"
    -- VERIFY-RPT-1 (Defect 1a, load-bearing): UNSAFE always fails closed,
    -- regardless of whether any id resolved. An unmappable unsafe id is still
    -- unsafe. The exit/verdict decision in doVerify routes through the
    -- 'FQVerifyResult' constructor, not this projection.
    , reportDiagnostics = diags
    , reportSuccess     = False
    }
fqResultToReport _fp _table (FQError txt) =
  let d = mkError Nothing ("liquid-fixpoint error: " <> txt)
  in DiagnosticReport
    { reportPhase       = "lh-fixpoint"
    , reportDiagnostics = [d]
    , reportSuccess     = False
    }

toDiag :: FilePath -> ConstraintTable -> FQConstraintId -> Maybe Diagnostic
toDiag fp table cid =
  case Map.lookup cid table of
    Nothing -> Just $ mkError Nothing $
               "constraint #" <> T.pack (show cid) <> " failed (unknown origin)"
    Just orig ->
      let msg = case coClause orig of
                  "body-post"      -> "body verification of '" <> coFunction orig
                                      <> "' failed — implementation does not satisfy postcondition"
                  "body-post-then" -> "body verification of '" <> coFunction orig
                                      <> "' failed (then-branch does not satisfy postcondition)"
                  "body-post-else" -> "body verification of '" <> coFunction orig
                                      <> "' failed (else-branch does not satisfy postcondition)"
                  clause | "call-pre:" `T.isPrefixOf` clause ->
                    let callee = T.drop 9 clause  -- drop "call-pre:"
                    in "call-site precondition of '" <> callee
                       <> "' not satisfied in '" <> coFunction orig
                       <> "' — caller does not prove callee's precondition"
                  clause | "payload-sub:" `T.isPrefixOf` clause ->
                    let callee = T.drop 12 clause  -- drop "payload-sub:"
                    in "payload subtyping for call to '" <> callee
                       <> "' not satisfied in '" <> coFunction orig
                       <> "' — argument's payload does not satisfy the callee param's declared refinement (COMP-4 b)"
                  _                -> coClause orig <> "-condition of '" <> coFunction orig
                                      <> "' not verified"
                <> " (constraint #" <> T.pack (show cid) <> ")"
          d   = mkError Nothing msg
      in Just d { diagPointer = Just (coJsonPtr orig) }

-- | VERIFY-RPT-1 (Defect 1b): fallback diagnostic for an UNSAFE verdict that
-- carries no resolvable constraint id. Points at the first known origin's
-- pointer (the '/statements/N/body' clause carrying the offending fill — the
-- target a repair agent must edit), else the document root. Guarantees the
-- 'FQUnsafe' diagnostic payload is never empty, so 'verify' and 'patch' never
-- report an unsafe result with zero diagnostics.
fallbackUnsafeDiag :: ConstraintTable -> Diagnostic
fallbackUnsafeDiag table =
  let mOrig = case Map.elems table of
                (o:_) -> Just o
                []    -> Nothing
      ptr   = maybe "/" coJsonPtr mOrig
      fn    = maybe "" (\o -> " of '" <> coFunction o <> "'") mOrig
      msg   = "body verification" <> fn
              <> " failed \8212 implementation does not satisfy contract "
              <> "(liquid-fixpoint UNSAFE; no constraint id resolved to a source location)"
      d     = mkError Nothing msg
  in d { diagPointer = Just ptr, diagKind = Just "lh-unsafe" }
