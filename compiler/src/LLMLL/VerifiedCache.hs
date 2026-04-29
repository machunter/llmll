-- |
-- Module      : LLMLL.VerifiedCache
-- Description : Sidecar .verified.json file I/O for contract verification levels.
--
-- v0.3: Persists per-function ContractStatus alongside module source.
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
import Data.Text (Text)
import System.Directory (doesFileExist)

import LLMLL.Syntax (ContractStatus(..), VerificationLevel(..), Name)

-- ---------------------------------------------------------------------------
-- Path convention
-- ---------------------------------------------------------------------------

-- | Compute the sidecar path: foo.llmll -> foo.llmll.verified.json
verifiedPath :: FilePath -> FilePath
verifiedPath fp = fp ++ ".verified.json"

-- ---------------------------------------------------------------------------
-- JSON encoding
-- ---------------------------------------------------------------------------

vlToJSON :: VerificationLevel -> Value
vlToJSON VLAsserted      = object ["level" .= ("asserted" :: Text)]
vlToJSON (VLTested n)    = object ["level" .= ("tested" :: Text), "samples" .= n]
vlToJSON (VLProven prov) = object ["level" .= ("proven" :: Text), "prover" .= prov]
vlToJSON (VLProvenSMT solver) = object ["level" .= ("proven-smt" :: Text), "prover" .= solver]

vlFromJSON :: Value -> Maybe VerificationLevel
vlFromJSON (Object o) =
  case KM.lookup "level" o of
    Just (String "asserted") -> Just VLAsserted
    Just (String "tested")   ->
      let n = case KM.lookup "samples" o of
                Just (Number s) -> round s
                _               -> 0
      in Just (VLTested n)
    Just (String "proven")   ->
      let p = case KM.lookup "prover" o of
                Just (String t) -> t
                _               -> ""
      in Just (VLProven p)
    Just (String "proven-smt") ->
      let p = case KM.lookup "prover" o of
                Just (String t) -> t
                _               -> ""
      in Just (VLProvenSMT p)
    _ -> Nothing
vlFromJSON _ = Nothing

csToJSON :: ContractStatus -> Value
csToJSON cs = object $
  maybe [] (\v -> ["pre" .= vlToJSON v]) (csPreLevel cs) ++
  maybe [] (\v -> ["post" .= vlToJSON v]) (csPostLevel cs) ++
  maybe [] (\s -> ["pre_source" .= s]) (csPreSource cs) ++
  maybe [] (\s -> ["post_source" .= s]) (csPostSource cs)

csFromJSON :: Value -> Maybe ContractStatus
csFromJSON (Object o) =
  let pre  = KM.lookup "pre" o >>= vlFromJSON
      post = KM.lookup "post" o >>= vlFromJSON
      preS = case KM.lookup "pre_source" o of
               Just (String s) -> Just s
               _               -> Nothing
      postS = case KM.lookup "post_source" o of
               Just (String s) -> Just s
               _               -> Nothing
  in Just $ ContractStatus pre post preS postS
csFromJSON _ = Nothing

-- ---------------------------------------------------------------------------
-- File I/O
-- ---------------------------------------------------------------------------

-- | Load verified status from sidecar file. Returns empty map if file missing.
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
        Just (Object top) ->
          pure $ Map.fromList
            [ (AK.toText key, cs)
            | (key, val) <- KM.toList top
            , Just cs <- [csFromJSON val]
            ]
        _ -> pure Map.empty

-- | Save verified status to sidecar file.
saveVerified :: FilePath -> Map Name ContractStatus -> IO ()
saveVerified fp statuses = do
  let path = verifiedPath fp
      pairs = [ AK.fromText k .= csToJSON cs | (k, cs) <- Map.toList statuses ]
  BL.writeFile path (A.encode (object pairs))
