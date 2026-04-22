-- |
-- Module      : LLMLL.SpecCoverage
-- Description : v0.6.0: Specification coverage metric.
--
-- Classifies every function in a module as contracted, suppressed (via
-- @weakness-ok@), or unspecified, then computes the effective coverage
-- ratio.  Used by @llmll verify --spec-coverage@.
--
-- Design: pure function — all IO (loading sidecars, printing) happens
-- in Main.hs.  The classifier is exported for reuse by TrustReport.

module LLMLL.SpecCoverage
  ( -- * Types
    CoverageReport(..)
  , FunctionClass(..)
  , FunctionEntry(..)
  , CoverageSummary(..)
    -- * Core API
  , runCoverage
  , classifyFunction
    -- * Formatting
  , formatCoverageText
  , formatCoverageJson
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.List (nub, sortOn)
import Data.Aeson (encode, object, (.=), Value(..))
import qualified Data.ByteString.Lazy.Char8 as BLC

import LLMLL.Syntax
import LLMLL.Diagnostic (Diagnostic(..), Severity(..), mkWarning)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | How a function is classified for spec coverage.
data FunctionClass
  = FCContracted     -- ^ Has at least one pre or post clause
  | FCSuppressed     -- ^ Has weakness-ok and no contracts
  | FCUnspecified    -- ^ No contract, no suppression
  deriving (Show, Eq, Ord)

-- | A single function's coverage entry.
data FunctionEntry = FunctionEntry
  { feName      :: Name              -- ^ Function name
  , feClass     :: FunctionClass     -- ^ Classification
  , fePreLevel  :: Maybe VerificationLevel  -- ^ From sidecar
  , fePostLevel :: Maybe VerificationLevel  -- ^ From sidecar
  , feReason    :: Maybe Text        -- ^ weakness-ok reason (if suppressed)
  } deriving (Show, Eq)

-- | Aggregate summary.
data CoverageSummary = CoverageSummary
  { csContracted   :: Int
  , csSuppressed   :: Int
  , csUnspecified   :: Int
  , csTotal        :: Int
  , csProven       :: Int  -- ^ Functions with all clauses proven
  , csTested       :: Int  -- ^ Functions with tested (but not proven) clauses
  , csAsserted     :: Int  -- ^ Functions with asserted clauses
  , csEffective    :: Double  -- ^ effective_coverage in [0, 1]
  } deriving (Show, Eq)

-- | The full coverage report.
data CoverageReport = CoverageReport
  { crEntries    :: [FunctionEntry]
  , crSummary    :: CoverageSummary
  , crWarnings   :: [Diagnostic]     -- ^ WO-1, WO-2, D10 warnings
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Core API
-- ---------------------------------------------------------------------------

-- | Classify a single function given its contract and suppression status.
-- Exported for reuse by TrustReport (shared classifier per Language Team).
classifyFunction
  :: Contract          -- ^ The function's contract
  -> Bool              -- ^ Has a matching SWeaknessOk?
  -> Maybe Text        -- ^ weakness-ok reason (if any)
  -> FunctionClass
classifyFunction contract hasSuppression _reason
  | contractPre contract /= Nothing || contractPost contract /= Nothing
      = FCContracted   -- WO-2: contracted takes priority
  | hasSuppression
      = FCSuppressed
  | otherwise
      = FCUnspecified

-- | Build a spec coverage report from statements and sidecar data.
-- Pure function — Main.hs handles IO.
runCoverage :: [Statement] -> Map Name ContractStatus -> CoverageReport
runCoverage stmts csMap =
  let -- Extract suppressions (SWeaknessOk) — deduplicated by name (WO-3)
      suppressions = nub [(n, r) | SWeaknessOk n r <- stmts]
      suppMap = Map.fromList suppressions

      -- Extract all SDefLogic / SLetrec functions
      functions = extractFunctions stmts

      -- Classify each function
      entries = map (classifyEntry suppMap csMap) functions

      -- WO-1: Check for weakness-ok targets that don't match any function
      functionNames = map fst functions
      wo1Warnings = [ mkWO1Warning name reason
                    | (name, reason) <- suppressions
                    , name `notElem` functionNames
                    ]

      -- WO-2: Check for functions with both contracts and weakness-ok
      wo2Warnings = [ mkWO2Warning (feName e)
                    | e <- entries
                    , feClass e == FCContracted
                    , Map.member (feName e) suppMap
                    ]

      -- Compute summary
      summary = computeSummary entries

      -- D10: Bulk suppression guardrail
      d10Warnings = if csTotal summary > 0
                    && fromIntegral (csSuppressed summary) / fromIntegral (csTotal summary) > (0.5 :: Double)
                    then [mkD10Warning (csSuppressed summary) (csTotal summary)]
                    else []

  in CoverageReport entries summary (wo1Warnings ++ wo2Warnings ++ d10Warnings)

-- ---------------------------------------------------------------------------
-- Internal: function extraction and classification
-- ---------------------------------------------------------------------------

-- | Extract (name, contract) pairs from SDefLogic / SLetrec statements.
-- Excludes SDefInterface, SCheck, SDefMain, imports, etc.
extractFunctions :: [Statement] -> [(Name, Contract)]
extractFunctions stmts =
  [ (name, contract)
  | stmt <- stmts
  , (name, contract) <- case stmt of
      SDefLogic n _ _ c _ -> [(n, c)]
      SLetrec   n _ _ c _ _ -> [(n, c)]
      _                   -> []
  ]

-- | Classify a single function and build its coverage entry.
classifyEntry
  :: Map Name Text           -- ^ suppression map (name -> reason)
  -> Map Name ContractStatus -- ^ sidecar data
  -> (Name, Contract)        -- ^ (function name, contract)
  -> FunctionEntry
classifyEntry suppMap csMap (name, contract) =
  let hasSuppression = Map.member name suppMap
      reason = Map.lookup name suppMap
      cls = classifyFunction contract hasSuppression reason
      cs = Map.lookup name csMap
      preLevel  = cs >>= csPreLevel
      postLevel = cs >>= csPostLevel
  in FunctionEntry
       { feName      = name
       , feClass     = cls
       , fePreLevel  = preLevel
       , fePostLevel = postLevel
       , feReason    = reason
       }

-- | Compute the aggregate summary from entries.
computeSummary :: [FunctionEntry] -> CoverageSummary
computeSummary entries =
  let contracted  = [e | e <- entries, feClass e == FCContracted]
      suppressed  = [e | e <- entries, feClass e == FCSuppressed]
      unspecified = [e | e <- entries, feClass e == FCUnspecified]
      total       = length entries
      -- SC-PO-1: division guard — 0 functions → 100%
      effective   = if total == 0
                    then 1.0
                    else fromIntegral (length contracted + length suppressed)
                         / fromIntegral total
      -- Count by verification level within contracted
      proven   = length [e | e <- contracted, isProven (fePreLevel e) && isProven (fePostLevel e)]
      tested   = length [e | e <- contracted, isTested (fePreLevel e) || isTested (fePostLevel e)
                                             , not (isProven (fePreLevel e) && isProven (fePostLevel e))]
      asserted = length contracted - proven - tested
  in CoverageSummary
       { csContracted = length contracted
       , csSuppressed = length suppressed
       , csUnspecified = length unspecified
       , csTotal      = total
       , csProven     = proven
       , csTested     = tested
       , csAsserted   = asserted
       , csEffective  = effective
       }
  where
    isProven (Just (VLProven _)) = True
    isProven _                   = False
    isTested (Just (VLTested _)) = True
    isTested _                   = False

-- ---------------------------------------------------------------------------
-- Warning constructors
-- ---------------------------------------------------------------------------

-- | WO-1: weakness-ok target does not match any function in this module.
mkWO1Warning :: Name -> Text -> Diagnostic
mkWO1Warning name reason =
  (mkWarning Nothing
    ("weakness-ok target '" <> name <> "' does not match any function in this module (reason: \"" <> reason <> "\")"))
  { diagCode = Just "W601"
  , diagKind = Just "weakness-ok-unresolved"
  }

-- | WO-2: function has contracts AND weakness-ok (contracts take priority).
mkWO2Warning :: Name -> Diagnostic
mkWO2Warning name =
  (mkWarning Nothing
    ("function '" <> name <> "' has contracts and a weakness-ok declaration — contracts take priority; weakness-ok is redundant"))
  { diagCode = Just "W602"
  , diagKind = Just "weakness-ok-redundant"
  }

-- | D10: More than half of functions are suppressed.
mkD10Warning :: Int -> Int -> Diagnostic
mkD10Warning suppressed total =
  (mkWarning Nothing
    ("More than half of functions are suppressed (" <> tshow suppressed <> "/" <> tshow total
     <> ") — review whether the suppression policy is being used appropriately."))
  { diagCode = Just "W603"
  , diagKind = Just "bulk-suppression"
  }

-- ---------------------------------------------------------------------------
-- Formatting (human-readable)
-- ---------------------------------------------------------------------------

formatCoverageText :: CoverageReport -> Text
formatCoverageText report =
  let s = crSummary report
      separator = T.replicate 44 "─"
      pct n d = if d == 0 then "N/A" else tshow (round (100 * fromIntegral n / fromIntegral d :: Double) :: Int) <> "%"
      header = "Spec Coverage Report"
      contracted = [ "  Functions with contracts:     "
                     <> tshow (csContracted s) <> " / " <> tshow (csTotal s)
                     <> "   (" <> pct (csContracted s) (csTotal s) <> ")"
                   , "    Proven:                     " <> tshow (csProven s)
                   , "    Tested:                     " <> tshow (csTested s)
                   , "    Asserted:                   " <> tshow (csAsserted s)
                   ]
      suppressionLines =
        let suppEntries = [e | e <- crEntries report, feClass e == FCSuppressed]
        in if null suppEntries then []
           else ["  Intentional Underspecification:"]
                ++ map (\e -> "    ⊘ " <> feName e <> " — \"" <> maybe "" id (feReason e) <> "\"") suppEntries
      unspecLines =
        let unspecs = [feName e | e <- crEntries report, feClass e == FCUnspecified]
        in if null unspecs then []
           else [ "  Unspecified:                  " <> tshow (length unspecs)
                , "    " <> T.intercalate ", " unspecs
                ]
      effectiveLine = [ separator
                      , "  Effective coverage: "
                        <> tshow (round (100 * csEffective s) :: Int) <> "%"
                        <> " (" <> tshow (csContracted s + csSuppressed s)
                        <> "/" <> tshow (csTotal s) <> ")"
                      ]
      warningLines = if null (crWarnings report) then []
                     else [""] ++ map (\d -> "  ⚠ " <> diagMessage d) (crWarnings report)
  in T.unlines ([header, separator] ++ contracted ++ suppressionLines ++ unspecLines ++ effectiveLine ++ warningLines)

-- ---------------------------------------------------------------------------
-- Formatting (JSON)
-- ---------------------------------------------------------------------------

formatCoverageJson :: CoverageReport -> Text
formatCoverageJson report =
  T.pack . BLC.unpack . encode $ object
    [ "entries"   .= map entryJson (sortOn feName (crEntries report))
    , "summary"   .= summaryJson (crSummary report)
    , "warnings"  .= map warnJson (crWarnings report)
    ]
  where
    entryJson e = object
      [ "name"       .= feName e
      , "class"      .= classLabel (feClass e)
      , "pre_level"  .= fmap vlLabel (fePreLevel e)
      , "post_level" .= fmap vlLabel (fePostLevel e)
      , "reason"     .= feReason e
      ]
    summaryJson s = object
      [ "contracted"         .= csContracted s
      , "suppressed"         .= csSuppressed s
      , "unspecified"        .= csUnspecified s
      , "total"              .= csTotal s
      , "proven"             .= csProven s
      , "tested"             .= csTested s
      , "asserted"           .= csAsserted s
      , "effective_coverage" .= csEffective s
      ]
    warnJson d = object
      [ "code"    .= diagCode d
      , "message" .= diagMessage d
      ]

classLabel :: FunctionClass -> Text
classLabel FCContracted  = "contracted"
classLabel FCSuppressed  = "suppressed"
classLabel FCUnspecified = "unspecified"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

vlLabel :: VerificationLevel -> Text
vlLabel VLAsserted    = "asserted"
vlLabel (VLTested n)  = "tested (" <> tshow n <> " samples)"
vlLabel (VLProven p)  = "proven (" <> p <> ")"

tshow :: Show a => a -> Text
tshow = T.pack . show
