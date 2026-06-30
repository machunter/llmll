{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : LLMLL.ProofArtifact
-- Description : PROOF-ARTIFACT (staged MVP) — a unified, reproducible verification record.
--
-- Settled design: @docs/design/proof-artifact-proposal.md@ (Rev 2, professor-cleared).
--
-- One serializable object per @verify@ run that RE-PROJECTS the existing scattered
-- justification surfaces (trust report, obligation report, @.fq@ VC, @.verified.json@
-- sidecar) plus the determinism-pin delta fields, so a verdict can be re-derived
-- hermetically (the F*-@.hints@ / Dafny-caching R-property) and audited in one place.
--
-- The soundness spine is the §4.1 LCF invariant: a per-function record carrying a
-- POSITIVE tier (verified / contract-checked / tested) is UNCONSTRUCTIBLE unless its
-- qualifiers cohere — it is not also refuted, did not fall back, and (when a CDP
-- discriminative axis is recorded) carries its basis. 'FnRecord' is therefore abstract:
-- its data constructor is unexported and the ONLY mint is 'mkFnRecord', the kernel that
-- refuses the laundered states. 'FromJSON' routes through the same kernel, so a tampered
-- artifact with a laundered positive record fails to parse rather than deserializing.
--
-- Staged MVP: ships the R-property on the full stored VC; @unsat_core@ is a reserved
-- field (Z3's core is not cheaply surfaced through liquid-fixpoint — §8/Risk-3). The
-- @certificate@ field is reserved for the future Lean tier only; never a Z3 proof object.
module LLMLL.ProofArtifact
  ( -- * The artifact
    ProofArtifact(..)
  , ComposedVersions(..)
  , SolverMeta(..)
  , SolverResult(..)
    -- * Per-function record (abstract — minted only via the kernel)
  , FnRecord            -- NB: constructor intentionally NOT exported (LCF discipline)
  , fnName, fnTier, fnCallerObligations, fnFallbackReason, fnRefuted, fnDiscrimBasis
  , Tier(..)
  , isPositiveTier
    -- * The §4.1 LCF kernel
  , FnInputs(..)
  , LaunderError(..)
  , mkFnRecord
  , renderLaunderError
    -- * Replay (fail-closed classification — the pure spine)
  , ReplayOutcome(..)
  , classifyReplay
    -- * Constants
  , proofArtifactVersion
  , codegenSemanticsVersion
  ) where

import           Data.Aeson
import           Data.Aeson.Types   (Parser)
import           Data.Text          (Text)
import qualified Data.Text          as T

-- ---------------------------------------------------------------------------
-- Tiers
-- ---------------------------------------------------------------------------

-- | The diamond-lattice evidence tier, flattened for the artifact projection.
data Tier
  = TVerified         -- ^ body-faithful, solver-proven (positive)
  | TContractChecked  -- ^ contract consistency proven, not body (positive)
  | TTested           -- ^ PBT evidence only (positive)
  | TAsserted         -- ^ runtime assertion only (non-positive)
  | TNoContract       -- ^ no contract (non-positive)
  deriving (Show, Eq)

-- | A POSITIVE tier is one whose record the §4.1 invariant constrains.
isPositiveTier :: Tier -> Bool
isPositiveTier t = t `elem` [TVerified, TContractChecked, TTested]

tierText :: Tier -> Text
tierText TVerified        = "verified"
tierText TContractChecked = "contract-checked"
tierText TTested          = "tested"
tierText TAsserted        = "asserted"
tierText TNoContract      = "none"

tierFromText :: Text -> Maybe Tier
tierFromText "verified"         = Just TVerified
tierFromText "contract-checked" = Just TContractChecked
tierFromText "tested"           = Just TTested
tierFromText "asserted"         = Just TAsserted
tierFromText "none"             = Just TNoContract
tierFromText _                  = Nothing

-- ---------------------------------------------------------------------------
-- The §4.1 LCF kernel
-- ---------------------------------------------------------------------------

-- | Raw inputs a per-function record is minted from. The kernel ('mkFnRecord')
-- is the sole gate between these and a 'FnRecord'.
data FnInputs = FnInputs
  { fiName           :: Text
  , fiTier           :: Tier
  , fiCallerObligs   :: [Text]        -- ^ rendered 'requires' the caller must discharge
  , fiFallbackReason :: Maybe Text    -- ^ Just iff the body left the body-faithful fragment
  , fiRefuted        :: Bool          -- ^ the orthogonal negative-evidence flag
  , fiDiscrim        :: Maybe (Maybe Text)
      -- ^ Nothing = no CDP axis recorded; Just b = a discriminative axis with basis @b@.
      --   @Just Nothing@ is the laundered "axis present, basis absent" state the kernel rejects.
  } deriving (Show, Eq)

-- | Ways the §4.1 invariant can be violated — each makes a positive-tier record ill-formed.
data LaunderError
  = PositiveWithFallback Text   -- ^ a positive tier whose body fell back
  | PositiveWithRefuted  Text   -- ^ a positive tier also flagged refuted
  | DiscrimMissingBasis  Text   -- ^ a discriminative axis recorded without its basis
  deriving (Show, Eq)

renderLaunderError :: LaunderError -> Text
renderLaunderError (PositiveWithFallback n) =
  "ill-formed artifact: function '" <> n <> "' carries a positive tier but a non-empty fallback_reason"
renderLaunderError (PositiveWithRefuted n) =
  "ill-formed artifact: function '" <> n <> "' carries a positive tier but is flagged refuted"
renderLaunderError (DiscrimMissingBasis n) =
  "ill-formed artifact: function '" <> n <> "' records a discriminative_axis without its basis"

-- | A per-function record — ABSTRACT. The data constructor is not exported; the
-- only way to obtain a 'FnRecord' is through 'mkFnRecord' (the kernel) or 'FromJSON'
-- (which itself routes through the kernel). This is the LCF discipline: a positive
-- tier is mintable only when its qualifiers cohere, exactly as a @Thm@ is mintable
-- only through the kernel. Evidence-laundering by field omission/contradiction is
-- therefore not a discouraged practice but an unrepresentable state.
data FnRecord = FnRecord
  { fnName              :: Text
  , fnTier              :: Tier
  , fnCallerObligations :: [Text]
  , fnFallbackReason    :: Maybe Text
  , fnRefuted           :: Bool
  , fnDiscrimBasis      :: Maybe (Maybe Text)
  } deriving (Show, Eq)

-- | THE KERNEL. Mint a per-function record only if the §4.1 invariant holds. A
-- positive tier (verified / contract-checked / tested) is rejected when it is also
-- refuted, when it carries a fallback reason (it did not, in fact, stay body-faithful),
-- or when a discriminative axis is recorded without its basis. Non-positive tiers are
-- unconstrained (a fallback or refuted record is legitimate and carries its evidence).
mkFnRecord :: FnInputs -> Either LaunderError FnRecord
mkFnRecord i
  | isPositiveTier (fiTier i), Just _ <- fiFallbackReason i =
      Left (PositiveWithFallback (fiName i))
  | isPositiveTier (fiTier i), fiRefuted i =
      Left (PositiveWithRefuted (fiName i))
  | Just Nothing <- fiDiscrim i =
      Left (DiscrimMissingBasis (fiName i))
  | otherwise =
      Right FnRecord
        { fnName              = fiName i
        , fnTier              = fiTier i
        , fnCallerObligations = fiCallerObligs i
        , fnFallbackReason    = fiFallbackReason i
        , fnRefuted           = fiRefuted i
        , fnDiscrimBasis      = fiDiscrim i
        }

-- ---------------------------------------------------------------------------
-- Solver metadata + result
-- ---------------------------------------------------------------------------

-- | The determinism inputs pinned for replay (§4.3) — version ALONE is insufficient.
data SolverMeta = SolverMeta
  { smFixpointVersion :: Text
  , smZ3Version       :: Text
  , smOptions         :: [Text]
  , smResourceLimits  :: Maybe Text
  } deriving (Show, Eq)

-- | The verdict; @RUnknown@ is a DISTINCT fail-closed outcome, never read as a verdict.
data SolverResult = RSafe | RUnsafeRefuted | RNoVC | RUnknown
  deriving (Show, Eq)

solverResultText :: SolverResult -> Text
solverResultText RSafe          = "safe"
solverResultText RUnsafeRefuted = "unsafe-refuted"
solverResultText RNoVC          = "no-vc"
solverResultText RUnknown       = "unknown"

solverResultFromText :: Text -> Maybe SolverResult
solverResultFromText "safe"           = Just RSafe
solverResultFromText "unsafe-refuted" = Just RUnsafeRefuted
solverResultFromText "no-vc"          = Just RNoVC
solverResultFromText "unknown"        = Just RUnknown
solverResultFromText _                = Nothing

-- ---------------------------------------------------------------------------
-- The run-level artifact
-- ---------------------------------------------------------------------------

-- | Versions this artifact COMPOSES — embedded, not re-minted (Risk 6).
data ComposedVersions = ComposedVersions
  { cvTrustReport :: Text   -- ^ trust_report_version (1.4.0 at time of writing)
  , cvSchema      :: Text   -- ^ JSON-AST schemaVersion
  } deriving (Show, Eq)

data ProofArtifact = ProofArtifact
  { paVersion       :: Text             -- ^ proof_artifact_version
  , paComposed      :: ComposedVersions
  , paSourcePath    :: Text             -- ^ the source file the artifact was built from (replay recomputes its hash)
  , paSourceHash    :: Maybe Text       -- ^ "sha256:" identity / staleness driver
  , paSolver        :: SolverMeta
  , paCodegenSemVer :: Text             -- ^ codegen_semantics_version (dormant; distinguishes int / machine-int)
  , paSolverResult  :: SolverResult
  , paVc            :: Text             -- ^ the full .fq VC text — the R-property proof trace
  , paUnsatCore     :: Maybe Text       -- ^ RESERVED (deferred); always Nothing in the staged MVP
  , paFunctions     :: [FnRecord]       -- ^ per-function projections, each minted via the kernel
  , paCertificate   :: Maybe Text       -- ^ RESERVED for the Lean tier ONLY; never a Z3 proof object
  } deriving (Show, Eq)

-- | Bumped independently of the surfaces it composes.
proofArtifactVersion :: Text
proofArtifactVersion = "0.1.0"

-- | The dormant codegen-semantics stamp (LLMLL.md §5.3.5:1051) — unbounded @int@ today.
codegenSemanticsVersion :: Text
codegenSemanticsVersion = "int-unbounded-1"

-- ---------------------------------------------------------------------------
-- Replay (fail-closed classification — pure; the IO re-run lives in Main)
-- ---------------------------------------------------------------------------

data ReplayOutcome
  = ReplayReproduced SolverResult  -- ^ hashes + determinism inputs match and the verdict reproduced
  | ReplayFailClosed Text          -- ^ ANY mismatch, or unknown/timeout — never honor the recorded verdict
  deriving (Show, Eq)

-- | The §4.3 fail-closed decision. Fails closed on (in order): a source/AST hash
-- mismatch; a determinism-input (solver build / options / limits) mismatch; an
-- @unknown@/timeout re-run (a distinct non-verdict); or a verdict that does not
-- reproduce. Only an exact match on every axis honors the recorded verdict.
classifyReplay
  :: Maybe Text     -- ^ source hash recomputed from the named source at replay time
  -> SolverMeta     -- ^ the solver metadata of the replay environment
  -> SolverResult   -- ^ the re-run verdict on the stored VC
  -> ProofArtifact  -- ^ the recorded artifact
  -> ReplayOutcome
classifyReplay recomputedHash curMeta rerun art
  | paSourceHash art /= recomputedHash =
      ReplayFailClosed "source/AST hash mismatch — artifact stale relative to the named source"
  | paSolver art /= curMeta =
      ReplayFailClosed "determinism-input mismatch (solver build / options / resource limits)"
  | rerun == RUnknown =
      ReplayFailClosed "replay returned unknown/timeout — demote to needs-re-verify (not a verdict)"
  | rerun /= paSolverResult art =
      ReplayFailClosed "verdict did not reproduce"
  | otherwise =
      ReplayReproduced rerun

-- ---------------------------------------------------------------------------
-- JSON — FnRecord deserialization routes through the kernel (laundered → parse failure)
-- ---------------------------------------------------------------------------

instance ToJSON Tier where toJSON = String . tierText
instance ToJSON SolverResult where toJSON = String . solverResultText

instance ToJSON SolverMeta where
  toJSON m = object
    [ "fixpoint_version" .= smFixpointVersion m
    , "z3_version"       .= smZ3Version m
    , "options"          .= smOptions m
    , "resource_limits"  .= smResourceLimits m ]

instance FromJSON SolverMeta where
  parseJSON = withObject "SolverMeta" $ \o -> SolverMeta
    <$> o .:  "fixpoint_version"
    <*> o .:  "z3_version"
    <*> o .:  "options"
    <*> o .:? "resource_limits"

instance ToJSON ComposedVersions where
  toJSON v = object [ "trust_report_version" .= cvTrustReport v, "schema_version" .= cvSchema v ]

instance FromJSON ComposedVersions where
  parseJSON = withObject "ComposedVersions" $ \o -> ComposedVersions
    <$> o .: "trust_report_version" <*> o .: "schema_version"

instance ToJSON FnRecord where
  toJSON r = object $
    [ "name"               .= fnName r
    , "evidence_level"     .= fnTier r
    , "caller_obligations" .= fnCallerObligations r
    , "fallback_reason"    .= fnFallbackReason r
    , "refuted"            .= fnRefuted r
    ] ++ discrim
    where
      discrim = case fnDiscrimBasis r of
        Nothing       -> []
        Just mbasis   -> [ "discriminative_axis" .= object [ "basis" .= mbasis ] ]

instance FromJSON FnRecord where
  parseJSON = withObject "FnRecord" $ \o -> do
    nm   <- o .: "name"
    tTxt <- o .: "evidence_level"
    tier <- maybe (fail ("unknown evidence_level: " <> T.unpack tTxt)) pure (tierFromText tTxt)
    cobs <- o .:  "caller_obligations"
    fbk  <- o .:? "fallback_reason"
    ref  <- o .:  "refuted"
    disc <- parseDiscrim o
    -- LCF discipline on the read side: a laundered positive record fails the PARSE.
    case mkFnRecord (FnInputs nm tier cobs fbk ref disc) of
      Left  e -> fail (T.unpack (renderLaunderError e))
      Right r -> pure r
    where
      parseDiscrim :: Object -> Parser (Maybe (Maybe Text))
      parseDiscrim o = do
        mAxis <- o .:? "discriminative_axis"
        case mAxis of
          Nothing  -> pure Nothing
          Just ax  -> Just <$> withObject "discriminative_axis" (\a -> a .:? "basis") ax

instance ToJSON ProofArtifact where
  toJSON a = object
    [ "proof_artifact_version"   .= paVersion a
    , "composed_versions"        .= paComposed a
    , "source_path"              .= paSourcePath a
    , "source_hash"              .= paSourceHash a
    , "solver"                   .= paSolver a
    , "codegen_semantics_version".= paCodegenSemVer a
    , "solver_result"            .= paSolverResult a
    , "vc"                       .= paVc a
    , "unsat_core"               .= paUnsatCore a      -- reserved (deferred)
    , "functions"                .= paFunctions a
    , "certificate"              .= paCertificate a    -- reserved (Lean tier only)
    ]

instance FromJSON ProofArtifact where
  parseJSON = withObject "ProofArtifact" $ \o -> do
    ver  <- o .:  "proof_artifact_version"
    comp <- o .:  "composed_versions"
    sp   <- o .:  "source_path"
    sh   <- o .:? "source_hash"
    slv  <- o .:  "solver"
    csv  <- o .:  "codegen_semantics_version"
    srTx <- o .:  "solver_result"
    sr   <- maybe (fail ("unknown solver_result: " <> T.unpack srTx)) pure (solverResultFromText srTx)
    vc   <- o .:  "vc"
    uc   <- o .:? "unsat_core"
    fns  <- o .:  "functions"           -- each FnRecord re-checked by its kernel-routed FromJSON
    cert <- o .:? "certificate"
    pure (ProofArtifact ver comp sp sh slv csv sr vc uc fns cert)
