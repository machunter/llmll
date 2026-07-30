-- |
-- Module      : LLMLL.VerifiedCache
-- Description : Sidecar .verified.json file I/O for contract verification levels.
--
-- v0.8.1b: Serializes the new EvidenceRecord/DisplayLevel/AssumptionKind model.
-- Written by `llmll verify` and `llmll test`.
-- Read by `llmll build` (for --contracts=unproven) and module imports.
module LLMLL.VerifiedCache
  ( verifiedPath
  , loadVerified
  , saveVerified
  , saveVerifiedWith   -- TRUST-PRE: variant persisting a top-level caller_obligations array
  , sidecarNeedsRevalidation
  , checkerSoundnessVersion      -- SAFE-ARG: checker-soundness epoch stamped into every sidecar
  , reservedCheckerSoundnessKey
  , dlToJSON           -- DisplayLevel JSON codec (exposed for tests / round-trip)
  , dlFromJSON
  , erToJSON           -- SRC-CONJ-1: EvidenceRecord codec (exposed for tests / round-trip)
  , erFromJSON
  ) where

import Data.Aeson (Value(..), (.=), object)
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesFileExist)

import LLMLL.Syntax (ContractStatus(..), DisplayLevel(..), EvidenceRecord(..), PbtWitness(..), AssumptionKind(..), Name)

-- ---------------------------------------------------------------------------
-- Path convention
-- ---------------------------------------------------------------------------

-- | Compute the sidecar path: foo.llmll -> foo.llmll.verified.json
verifiedPath :: FilePath -> FilePath
verifiedPath fp = fp ++ ".verified.json"

-- ---------------------------------------------------------------------------
-- JSON encoding — DisplayLevel
-- ---------------------------------------------------------------------------

dlToJSON :: DisplayLevel -> Value
dlToJSON DLAsserted          = object ["level" .= ("asserted" :: Text)]
dlToJSON (DLTested n)        = object ["level" .= ("tested" :: Text), "samples" .= n]
dlToJSON (DLContractChecked p) = object ["level" .= ("contract-checked" :: Text), "prover" .= p]
dlToJSON (DLVerified p)      = object ["level" .= ("verified" :: Text), "prover" .= p]
dlToJSON (DLVerifiedLean p)  = object ["level" .= ("verified-lean" :: Text), "prover" .= p]

dlFromJSON :: Value -> Maybe DisplayLevel
dlFromJSON (Object o) =
  case KM.lookup "level" o of
    Just (String "asserted") -> Just DLAsserted
    Just (String "tested")   ->
      let n = case KM.lookup "samples" o of
                Just (Number s) -> round s
                _               -> 0
      in Just (DLTested n)
    Just (String "contract-checked") ->
      let p = case KM.lookup "prover" o of
                Just (String t) -> t
                _               -> ""
      in Just (DLContractChecked p)
    Just (String "verified") ->
      let p = case KM.lookup "prover" o of
                Just (String t) -> t
                _               -> ""
      in Just (DLVerified p)
    Just (String "verified-lean") ->
      let p = case KM.lookup "prover" o of
                Just (String t) -> t
                _               -> ""
      in Just (DLVerifiedLean p)
    _ -> Nothing
dlFromJSON _ = Nothing

-- ---------------------------------------------------------------------------
-- JSON encoding — EvidenceRecord
-- ---------------------------------------------------------------------------

erToJSON :: EvidenceRecord -> Value
erToJSON er = object $
  ["display_level" .= dlToJSON (erDisplayLevel er)] ++
  ["body_faithful" .= True | erBodyFaithful er] ++
  maybe [] (\s -> ["source" .= s]) (erSource er) ++
  -- OBLIG-PBT-3: emit pbt_witnesses only when non-empty (back-compatible read
  -- against v0.10.4 sidecars that lack the field).
  (if null (erPbtWitnesses er) then [] else ["pbt_witnesses" .= map pwToJSON (erPbtWitnesses er)]) ++
  -- INT-1 (v0.10.8): emit overflow_tainted only when True (additive, omitted
  -- when False to keep older sidecar shape byte-identical for untouched records).
  ["overflow_tainted" .= True | erOverflowTainted er] ++
  -- LT-PPR (v0.11): predicate fields emitted only when present/true (additive).
  maybe [] (\f -> ["predicate_form" .= f]) (erPredicateForm er) ++
  maybe [] (\t -> ["predicate_text" .= t]) (erPredicateText er) ++
  ["runtime_check_emitted" .= True | erRuntimeCheckEmitted er] ++
  -- ADMIT-VERIFIED (Option 2): emit verified_hash only when present (additive,
  -- omitted on records the verifier did not stamp). A reader that does not find
  -- the field defaults to Nothing — which the admission leg treats as
  -- fail-closed (not admissible).
  maybe [] (\h -> ["verified_hash" .= h]) (erVerifiedHash er) ++
  -- REC-DESCENT Phase 3: emit termination_verified only when True (additive,
  -- omitted on non-total records so existing sidecars stay byte-identical).
  ["termination_verified" .= True | erTerminationVerified er] ++
  -- SRC-CONJ-1: per-conjunct :source list (author order, null for an unsourced
  -- conjunct), emitted only when non-empty so 0-or-1-clause records stay
  -- byte-identical. Report metadata only; never consulted by admission.
  (if null (erSources er) then [] else ["sources" .= erSources er])

erFromJSON :: Value -> Maybe EvidenceRecord
erFromJSON (Object o) = do
  dlVal <- KM.lookup "display_level" o
  dl    <- dlFromJSON dlVal
  let bf = case KM.lookup "body_faithful" o of
             Just (Bool b) -> b
             _             -> False
      src = case KM.lookup "source" o of
              Just (String s) -> Just s
              _               -> Nothing
      -- OBLIG-PBT-3: optional field; v0.10.4-and-earlier sidecars default to [].
      ws  = case KM.lookup "pbt_witnesses" o of
              Just (Array arr) -> [w | v <- foldr (:) [] arr, Just w <- [pwFromJSON v]]
              _                -> []
      -- INT-1 (v0.10.8): optional field; pre-v0.10.8 sidecars default to False.
      -- Reader-side default-false is the additive-back-compat shape; the strict-core
      -- consumer triggers a re-verify when the field is absent on a DLVerified
      -- body-faithful entry (loadVerified is the invalidation site for v0.10.8).
      ot  = case KM.lookup "overflow_tainted" o of
              Just (Bool b) -> b
              _             -> False
      -- LT-PPR (v0.11): optional fields; pre-v0.11 sidecars default to Nothing/False.
      pf  = case KM.lookup "predicate_form" o of
              Just (String s) -> Just s
              _               -> Nothing
      pt  = case KM.lookup "predicate_text" o of
              Just (String s) -> Just s
              _               -> Nothing
      rc  = case KM.lookup "runtime_check_emitted" o of
              Just (Bool b) -> b
              _             -> False
      -- ADMIT-VERIFIED (Option 2): optional field; pre-ADMIT-VERIFIED sidecars
      -- default to Nothing. Absence is preserved (not defaulted to a value):
      -- 'checkCalleeAdmissibility' fails closed on Nothing.
      vh  = case KM.lookup "verified_hash" o of
              Just (String s) -> Just s
              _               -> Nothing
      -- REC-DESCENT Phase 3: optional total-correctness bit; absent on
      -- pre-REC-DESCENT sidecars defaults to False (fail-closed — an old
      -- sidecar is not termination-verified).
      tv  = case KM.lookup "termination_verified" o of
              Just (Bool b) -> b
              _             -> False
      -- SRC-CONJ-1: optional per-conjunct source list; pre-SRC-CONJ-1 sidecars
      -- default to [] (additive back-compat, symmetric with erToJSON's
      -- omit-when-empty).
      srcs = case KM.lookup "sources" o of
               Just (Array arr) -> [ case v of { String s -> Just s; _ -> Nothing }
                                   | v <- foldr (:) [] arr ]
               _                -> []
  Just $ EvidenceRecord dl bf src ws ot pf pt rc vh tv srcs

-- ---------------------------------------------------------------------------
-- JSON encoding — PbtWitness (OBLIG-PBT-3)
-- ---------------------------------------------------------------------------

pwToJSON :: PbtWitness -> Value
pwToJSON w = object
  [ "hash"        .= pwHash w
  , "description" .= pwDescription w
  ]

pwFromJSON :: Value -> Maybe PbtWitness
pwFromJSON (Object o) =
  let h = case KM.lookup "hash" o of
            Just (String s) -> s
            _               -> ""
      d = case KM.lookup "description" o of
            Just (String s) -> s
            _               -> ""
  in if T.null h then Nothing else Just (PbtWitness h d)
pwFromJSON _ = Nothing

-- ---------------------------------------------------------------------------
-- JSON encoding — AssumptionKind
-- ---------------------------------------------------------------------------

akToJSON :: AssumptionKind -> Value
akToJSON AKRuntimePrimitive = String "runtime-primitive"
akToJSON AKCompilerBuiltin  = String "compiler-builtin"
akToJSON AKExternalOpaque   = String "external-opaque"

akFromJSON :: Value -> Maybe AssumptionKind
akFromJSON (String "runtime-primitive") = Just AKRuntimePrimitive
akFromJSON (String "compiler-builtin")  = Just AKCompilerBuiltin
akFromJSON (String "external-opaque")   = Just AKExternalOpaque
akFromJSON _ = Nothing

-- ---------------------------------------------------------------------------
-- JSON encoding — ContractStatus
-- ---------------------------------------------------------------------------

csToJSON :: ContractStatus -> Value
csToJSON cs = object $
  maybe [] (\er -> ["pre" .= erToJSON er]) (csPre cs) ++
  maybe [] (\er -> ["post" .= erToJSON er]) (csPost cs) ++
  if null (csAssumptions cs) then [] else ["assumptions" .= map akToJSON (csAssumptions cs)]

csFromJSON :: Value -> Maybe ContractStatus
csFromJSON (Object o) =
  let pre  = KM.lookup "pre" o >>= erFromJSON
      post = KM.lookup "post" o >>= erFromJSON
      assumptions = case KM.lookup "assumptions" o of
        Just (Array arr) -> concatMap (\v -> maybe [] (:[]) (akFromJSON v)) (foldr (:) [] arr)
        _                -> []
  in Just $ ContractStatus pre post assumptions
csFromJSON _ = Nothing

-- ---------------------------------------------------------------------------
-- File I/O
-- ---------------------------------------------------------------------------

-- | Load verified status from sidecar file. Returns empty map if file missing
-- or if the file uses an old/incompatible format.
--
-- VERIFY-RPT-1 (Defect 2): the INT-1 (v0.10.8) field-absence revalidation
-- trigger is disarmed (see 'sidecarNeedsRevalidation'). It over-invalidated
-- every v0.11 verified sidecar — LT-INT (v0.11) emptied the overflow-taint
-- emitter ('FixpointEmit.hs') so the writer legitimately omits
-- 'overflow_tainted' on all verified entries, which the old trigger read as
-- "stale, re-verify" and returned 'Map.empty', so '--trust-report' could never
-- surface 'verified'.
loadVerified :: FilePath -> IO (Map Name ContractStatus)
loadVerified fp = do
  let path = verifiedPath fp
  exists <- doesFileExist path
  if not exists
    then pure Map.empty
    else do
      bs <- BL.readFile path
      case A.decode bs of
        Nothing -> pure Map.empty
        Just (Object top)
          | sidecarNeedsRevalidation top -> pure Map.empty
          | otherwise ->
              pure $ Map.fromList
                [ (AK.toText key, cs)
                | (key, val) <- KM.toList top
                -- TRUST-PRE: skip the reserved top-level obligation key; it is a
                -- persisted contract property for the '.verified.json' reader,
                -- not a per-function ContractStatus. LLMLL itself re-derives the
                -- axis from the live source on every trust-report build.
                , AK.toText key /= reservedCallerObligationsKey
                -- SAFE-ARG: the checker-soundness stamp is a sidecar property,
                -- not a per-function ContractStatus.
                , AK.toText key /= reservedCheckerSoundnessKey
                , Just cs <- [csFromJSON val]
                ]
        _ -> pure Map.empty

-- | Whether a loaded sidecar must be discarded and re-verified.
--
-- DISARMED (VERIFY-RPT-1, v0.11). Always 'False'. The INT-1 (v0.10.8) trigger
-- invalidated any 'DLVerified' body-faithful entry that lacked the
-- 'overflow_tainted' field (absence read pessimistically as "could be tainted").
-- LT-INT (v0.11) made 'int' codegen unbounded ('Integer') and emptied the taint
-- emitter, so the field is now legitimately absent on every verified entry —
-- the trigger fired on all of them, the load-bearing cause of Defect 2.
--
-- SOUNDNESS SIDE-CONDITION (professor adjudication, VERIFY-RPT-1):
--   'overflow_tainted'-absent ⇒ False is sound IFF the loading binary's codegen
--   semantics are unbounded for every type the record's body ranges over.
-- Discharged by construction in the v0.11 window: all 'int' codegen is 'Integer';
-- already-shipped v0.10.x binaries retain the old invalidate-on-absence in the
-- one cross-binary direction that could otherwise reopen the gap.
--
-- !! TRIP-WIRE for INT-3 / machine-int (docs/design/int-3-machine-int-sketch.md
-- §3.2): 'machine-int' reintroduces bounded (2^64 two's-complement) codegen
-- inside a v0.11+ binary, so loader-version no longer implies runtime semantics
-- and the antecedent above is FALSIFIED. When INT-3 lands, this disarm MUST be
-- replaced by a 'codegen_semantics_version'-keyed check (proposal §3.5) — NOT by
-- restoring the field-absence trigger, and re-arming the FixpointEmit walker
-- alone is insufficient. The pre-disarm logic to port: invalidate when a
-- 'verified' + 'body_faithful=true' entry lacks 'overflow_tainted' AND was
-- produced under bounded-codegen semantics.
-- SAFE-ARG (v0.14.73): the INT-1 disarm above is retained for the
-- 'overflow_tainted' axis; the function is no longer unconditionally False.
-- A sidecar whose 'checker_soundness_version' is ABSENT or differs from this
-- binary's 'checkerSoundnessVersion' is discarded. Absence is the affected-range
-- signal: no sidecar written by v0.14.34..v0.14.72 carries the key, and every
-- verdict in that range may rest on the WILD-ASSUME false SAFE
-- (docs/design/finding-arg-position-false-safe.md).
--
-- This is sound in exactly the way the INT-1 field-absence trigger was NOT.
-- That trigger over-invalidated because the writer LEGITIMATELY omitted
-- 'overflow_tainted' on every verified entry, so absence meant "normal". Here
-- 'saveVerifiedWith' emits the stamp unconditionally, so absence means "written
-- by an older binary" and can never be a normal state going forward.
sidecarNeedsRevalidation :: KM.KeyMap Value -> Bool
sidecarNeedsRevalidation top =
  case KM.lookup (AK.fromText reservedCheckerSoundnessKey) top of
    Just (String v) -> v /= checkerSoundnessVersion
    _               -> True

-- | Save verified status to sidecar file.
saveVerified :: FilePath -> Map Name ContractStatus -> IO ()
saveVerified fp statuses = saveVerifiedWith fp statuses []

-- | TRUST-PRE: reserved top-level key carrying the persisted caller-obligation
-- axis. Skipped by 'loadVerified' (it is a contract property, not a
-- ContractStatus); written by 'saveVerifiedWith'.
reservedCallerObligationsKey :: Text
reservedCallerObligationsKey = "caller_obligations"

-- | SAFE-ARG: the CHECKER-soundness epoch, stamped into every sidecar written
-- by this binary. Deliberately DISTINCT from 'codegen_semantics_version'
-- ('ProofArtifact.codegenSemanticsVersion', which tracks int-vs-machine-int
-- CODEGEN semantics and is INT-3's re-arm discriminator): one string cannot say
-- which of the two axes moved, and spending the codegen stamp here would leave
-- INT-3 without one (finding-arg-position-false-safe.md Rev 1).
--
-- Bumped when a checker defect invalidates verdicts produced by older binaries.
checkerSoundnessVersion :: Text
checkerSoundnessVersion = "1"

-- | SAFE-ARG: reserved top-level sidecar key carrying 'checkerSoundnessVersion'.
reservedCheckerSoundnessKey :: Text
reservedCheckerSoundnessKey = "checker_soundness_version"

-- | TRUST-PRE: save verified status PLUS a persisted top-level
-- 'caller_obligations' array. The obligation objects are pre-rendered 'Value's
-- (built with 'TrustReport.callerObligationJson') so this module keeps its lean
-- 'Syntax'-only dependency and the two surfaces share one shape. The array is
-- emitted unconditionally (even when empty) — a 'requires' is a static contract
-- property, so its ABSENCE for a given function is itself information, the
-- deliberate inverse of the non-persisted 'refuted' verdict.
saveVerifiedWith :: FilePath -> Map Name ContractStatus -> [Value] -> IO ()
saveVerifiedWith fp statuses obligations = do
  let path = verifiedPath fp
      pairs = [ AK.fromText k .= csToJSON cs | (k, cs) <- Map.toList statuses ]
      obKey = [ AK.fromText reservedCallerObligationsKey .= obligations ]
      -- SAFE-ARG: stamped UNCONDITIONALLY, which is what makes absence a sound
      -- "written by an older binary" signal in 'sidecarNeedsRevalidation'.
      csKey = [ AK.fromText reservedCheckerSoundnessKey .= checkerSoundnessVersion ]
  BL.writeFile path (A.encode (object (pairs ++ obKey ++ csKey)))
