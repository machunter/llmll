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
  , fqResultToReport
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)

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
  , coClause     :: Text      -- ^ "pre" | "post" | "decreases"
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
  | "SAFE" `T.isInfixOf` out && not ("UNSAFE" `T.isInfixOf` out) = FQSafe
  | "UNSAFE" `T.isInfixOf` out = FQUnsafe (extractIds out)
  | otherwise = FQError out
  where
    -- Extract constraint IDs from lines like:
    --   id 47 ... or ... constraint id = 47 ...
    extractIds :: Text -> [FQConstraintId]
    extractIds txt =
      mapMaybe parseId (T.lines txt)
      where
        parseId line =
          let ws = T.words line
          in case dropWhile (/= "id") ws of
               (_:nStr:_) -> case reads (T.unpack nStr) of
                               [(n,"")] -> Just n
                               _        -> Nothing
               _           -> Nothing

-- ---------------------------------------------------------------------------
-- Convert to DiagnosticReport
-- ---------------------------------------------------------------------------

-- | Convert a FQVerifyResult + ConstraintTable → DiagnosticReport.
-- Each failed constraint becomes one Diagnostic with machine-readable fields:
--   diagKind     = Just "lh-unsafe"
--   diagMessage  = human description of which clause failed
--   diagPointer  = Just "/statements/N/pre"  (JSON Pointer for AI iteration)
fqResultToReport :: FilePath -> ConstraintTable -> FQVerifyResult -> DiagnosticReport
fqResultToReport fp _table FQSafe =
  DiagnosticReport
    { reportDiagnostics = []
    , reportSuccess     = True
    }
fqResultToReport fp table (FQUnsafe ids) =
  let diags = mapMaybe (toDiag fp table) ids
  in DiagnosticReport
    { reportDiagnostics = diags
    , reportSuccess     = null diags  -- might be unknown constraint IDs
    }
fqResultToReport fp _table (FQError txt) =
  let d = mkError Nothing ("liquid-fixpoint error: " <> txt)
  in DiagnosticReport
    { reportDiagnostics = [d]
    , reportSuccess     = False
    }

toDiag :: FilePath -> ConstraintTable -> FQConstraintId -> Maybe Diagnostic
toDiag fp table cid =
  case Map.lookup cid table of
    Nothing -> Just $ mkError Nothing $
               "constraint #" <> T.pack (show cid) <> " failed (unknown origin)"
    Just orig ->
      let msg = coClause orig <> "-condition of '" <> coFunction orig <> "' not verified"
                <> " (constraint #" <> T.pack (show cid) <> ")"
          d   = mkError Nothing msg
      in Just d { diagPointer = Just (coJsonPtr orig) }
