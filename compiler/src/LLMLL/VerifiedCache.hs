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
  ) where

import Data.Aeson (Value(..), (.=), object)
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
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
  ["overflow_tainted" .= True | erOverflowTainted er]

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
  Just $ EvidenceRecord dl bf src ws ot

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
-- INT-1 (v0.10.8): sidecars written by pre-v0.10.8 verify runs lack the
-- 'overflow_tainted' field on DLVerified body-faithful records. The reader
-- defaults the missing field to False (additive back-compat), but a strict-core
-- consumer that trusts a default-False on what was actually an unbounded-Int
-- arithmetic body would see a silent false negative. To eliminate that
-- exposure, 'loadVerified' invalidates the entire sidecar (returns empty,
-- forcing re-verify) whenever any verified body-faithful entry lacks the
-- field. Pre-v0.10.8 sidecars therefore regenerate on first verify against
-- v0.10.8+.
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
                , Just cs <- [csFromJSON val]
                ]
        _ -> pure Map.empty

-- | INT-1 (v0.10.8): True when the sidecar contains at least one
-- 'DLVerified' body-faithful entry that lacks the 'overflow_tainted' field.
-- Such entries pre-date v0.10.8's overflow-taint marking, so the file as a
-- whole is treated as stale and re-verified rather than silently reading the
-- taint as False.
sidecarNeedsRevalidation :: KM.KeyMap Value -> Bool
sidecarNeedsRevalidation top = any csNeedsRevalidation (KM.elems top)
  where
    csNeedsRevalidation (Object cs) =
      any erNeedsRevalidation [v | k <- ["pre", "post"], Just v <- [KM.lookup k cs]]
    csNeedsRevalidation _ = False

    erNeedsRevalidation (Object er) =
      let isVerifiedBodyFaithful = case (KM.lookup "display_level" er, KM.lookup "body_faithful" er) of
            (Just (Object dl), Just (Bool True))
              | KM.lookup "level" dl == Just (String "verified") -> True
            _ -> False
          taintFieldAbsent = isNothing (KM.lookup "overflow_tainted" er)
      in isVerifiedBodyFaithful && taintFieldAbsent
    erNeedsRevalidation _ = False

-- | Save verified status to sidecar file.
saveVerified :: FilePath -> Map Name ContractStatus -> IO ()
saveVerified fp statuses = do
  let path = verifiedPath fp
      pairs = [ AK.fromText k .= csToJSON cs | (k, cs) <- Map.toList statuses ]
  BL.writeFile path (A.encode (object pairs))
