{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.ProofCache
-- Description : Per-file .proof-cache.json sidecar for Lean proof certificates (v0.3.1).
--
-- Follows the @VerifiedCache@ pattern: one sidecar file per LLMLL source file.
-- Stores proof certificates indexed by contract path (JSON pointer into the AST).
-- Cache invalidation uses SHA-256 hash of the contract expression text.
module LLMLL.ProofCache
  ( -- * Path convention
    proofCachePath
    -- * Cache entries
  , ProofEntry(..)
    -- * I/O
  , loadProofCache
  , saveProofCache
  , lookupProof
  , insertProof
    -- * Trust Guards (v0.6.3)
  , isTaintedProof
  , proofToLevel
    -- * Hashing
  , computeObligationHash
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Aeson ((.=), (.:), (.:?))
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import System.Directory (doesFileExist)
import Crypto.Hash.SHA256 (hash)
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE
import Data.Word (Word8)
import Numeric (showHex)

import LLMLL.Syntax (VerificationLevel(..))

-- | A cached proof entry.
data ProofEntry = ProofEntry
  { peObligationHash :: Text    -- ^ SHA-256 hash of contract text (for invalidation)
  , peProof          :: Text    -- ^ Lean 4 proof term
  , peProver         :: Text    -- ^ Prover name (e.g. "leanstral")
  , peVerifiedAt     :: Text    -- ^ ISO 8601 timestamp
  } deriving (Show, Eq)

instance A.ToJSON ProofEntry where
  toJSON pe = A.object
    [ "obligation_hash" .= peObligationHash pe
    , "proof"           .= peProof pe
    , "prover"          .= peProver pe
    , "verified_at"     .= peVerifiedAt pe
    ]

instance A.FromJSON ProofEntry where
  parseJSON = A.withObject "ProofEntry" $ \o -> do
    h <- o .: "obligation_hash"
    p <- o .: "proof"
    prov <- o .:? "prover" A..!= "leanstral"
    t <- o .:? "verified_at" A..!= ""
    pure ProofEntry
      { peObligationHash = h
      , peProof = p
      , peProver = prov
      , peVerifiedAt = t
      }

-- | Compute the sidecar path: foo.llmll -> foo.llmll.proof-cache.json
proofCachePath :: FilePath -> FilePath
proofCachePath fp = fp ++ ".proof-cache.json"

-- | Load proof cache from disk. Returns empty map if file doesn't exist.
loadProofCache :: FilePath -> IO (Map Text ProofEntry)
loadProofCache fp = do
  let path = proofCachePath fp
  exists <- doesFileExist path
  if not exists then pure Map.empty
  else do
    raw <- BL.readFile path
    case A.decode raw of
      Just (A.Object top) ->
        case KM.lookup "proofs" top of
          Just proofsVal ->
            case A.fromJSON proofsVal of
              A.Success m -> pure m
              A.Error _   -> pure Map.empty
          Nothing -> pure Map.empty
      _ -> pure Map.empty

-- | Save proof cache to disk.
saveProofCache :: FilePath -> Map Text ProofEntry -> IO ()
saveProofCache fp entries = do
  let path = proofCachePath fp
      val = A.object
        [ "version" .= ("0.3.1" :: Text)
        , "proofs"  .= entries
        ]
  BL.writeFile path (A.encode val)

-- | Look up a proof by contract path, checking hash for invalidation.
lookupProof :: Text -> Text -> Map Text ProofEntry -> Maybe ProofEntry
lookupProof contractPath currentHash cache =
  case Map.lookup contractPath cache of
    Just entry | peObligationHash entry == currentHash -> Just entry
    _ -> Nothing

-- | Insert a proof entry into the cache.
insertProof :: Text -> ProofEntry -> Map Text ProofEntry -> Map Text ProofEntry
insertProof = Map.insert

-- | Compute SHA-256 hash of obligation text for cache invalidation.
--   Returns a 64-character lowercase hex string.
computeObligationHash :: Text -> Text
computeObligationHash = T.pack . concatMap toHex . BS.unpack . hash . TE.encodeUtf8
  where
    toHex :: Word8 -> String
    toHex w = let s = showHex w "" in if length s == 1 then '0' : s else s

-- ---------------------------------------------------------------------------
-- Trust Guards (v0.6.3)
-- ---------------------------------------------------------------------------

-- | A proof is tainted if it was produced by a mock prover or contains
-- sorry/axiom/admit markers. Tainted proofs must not raise trust level.
isTaintedProof :: ProofEntry -> Bool
isTaintedProof pe =
  peProver pe == "mock"
  || any (`T.isInfixOf` peProof pe) ["sorry", "axiom", "mock", "admit"]

-- | Convert a proof cache entry to a VerificationLevel.
-- Tainted proofs are capped at VLAsserted (cannot be "proven").
proofToLevel :: ProofEntry -> VerificationLevel
proofToLevel pe
  | isTaintedProof pe = VLAsserted
  | peProver pe == "liquid-fixpoint" = VLProvenSMT (peProver pe)
  | otherwise                        = VLProven (peProver pe)

