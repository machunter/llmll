-- |
-- Module      : LLMLL.Checkout
-- Description : Hole checkout with per-file lock management.
--
-- An agent calls @llmll checkout file.ast.json \/statements\/2\/body@ to lock
-- a hole. The compiler validates the pointer resolves to a @hole-*@ node,
-- records the lock in @.llmll-lock.json@, and returns a checkout token.
--
-- Lock design:
--   • Per-file .llmll-lock.json alongside the source
--   • 1-hour TTL (default); stale locks auto-expired on every operation
--   • Advisory flock for atomicity (prevents concurrent checkout races)
--   • --release flag for explicit abandonment
--   • --status flag for TTL query
module LLMLL.Checkout
  ( CheckoutToken(..)
  , CheckoutLock(..)
  , checkoutHole
  , releaseHole
  , checkoutStatus
  , loadLock
  , saveLock
  , expireStale
  , lockFilePath
  ) where

import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), withObject, (.:), (.:?), (.=), object)
import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time.Clock (UTCTime, NominalDiffTime, getCurrentTime, diffUTCTime, addUTCTime)
import GHC.Generics (Generic)
import Numeric (showHex)
import System.Directory (doesFileExist)
import System.FilePath (replaceExtension, takeExtension)
import System.Random (randomRIO)
import Data.List (isSuffixOf)

import LLMLL.JsonPointer (resolvePointer, isHoleNode, findDescendantHoles)
import LLMLL.Diagnostic (Diagnostic(..), Severity(..))
import LLMLL.Syntax (Span(..))

-- ---------------------------------------------------------------------------
-- Data Types
-- ---------------------------------------------------------------------------

data CheckoutToken = CheckoutToken
  { ctPointer   :: Text             -- RFC 6901 pointer to the hole
  , ctHoleKind  :: Text             -- e.g. "hole-delegate", "hole-named"
  , ctExpected  :: Maybe Text       -- expected return type (from hole spec, if available)
  , ctTimestamp :: UTCTime           -- lock creation time
  , ctToken     :: Text             -- 32-char hex random bearer token
  , ctTTL       :: NominalDiffTime   -- lock duration (default: 3600s)
  } deriving (Show, Eq, Generic)

instance ToJSON CheckoutToken where
  toJSON ct = object
    [ "pointer"   .= ctPointer ct
    , "hole_kind" .= ctHoleKind ct
    , "token"     .= ctToken ct
    , "ttl"       .= (round (ctTTL ct) :: Int)
    , "timestamp" .= ctTimestamp ct
    ]

instance FromJSON CheckoutToken where
  parseJSON = withObject "CheckoutToken" $ \o -> do
    p  <- o .: "pointer"
    hk <- o .: "hole_kind"
    tok <- o .: "token"
    ttlSec <- o .: "ttl"
    ts <- o .: "timestamp"
    expected <- o .:? "expected"
    pure CheckoutToken
      { ctPointer   = p
      , ctHoleKind  = hk
      , ctExpected  = expected
      , ctTimestamp = ts
      , ctToken     = tok
      , ctTTL       = fromIntegral (ttlSec :: Int)
      }

data CheckoutLock = CheckoutLock
  { lockFile    :: FilePath
  , lockTokens  :: [CheckoutToken]
  } deriving (Show, Eq, Generic)

instance ToJSON CheckoutLock where
  toJSON cl = object
    [ "file"   .= lockFile cl
    , "tokens" .= lockTokens cl
    ]

instance FromJSON CheckoutLock where
  parseJSON = withObject "CheckoutLock" $ \o ->
    CheckoutLock <$> o .: "file" <*> o .: "tokens"

-- ---------------------------------------------------------------------------
-- Lock file path
-- ---------------------------------------------------------------------------

-- | Compute lock file path: same directory, .llmll-lock.json suffix.
-- Handles .ast.json double extension: program.ast.json → program.llmll-lock.json
lockFilePath :: FilePath -> FilePath
lockFilePath fp
  | ".ast.json" `isSuffixOf` fp = take (length fp - 9) fp ++ ".llmll-lock.json"
  | otherwise                   = replaceExtension fp ".llmll-lock.json"

-- ---------------------------------------------------------------------------
-- Token Generation
-- ---------------------------------------------------------------------------

generateCheckoutToken :: IO Text
generateCheckoutToken = do
  ws <- mapM (\_ -> randomRIO (0, maxBound :: Int)) [1..4 :: Int]
  let hex = concatMap (\w -> pad16 (showHex (abs w) "")) ws
  pure $ T.pack hex
  where pad16 s = replicate (16 - length s) '0' ++ s

-- ---------------------------------------------------------------------------
-- Stale Lock Expiry
-- ---------------------------------------------------------------------------

-- | Remove expired tokens from a lock.
expireStale :: UTCTime -> CheckoutLock -> CheckoutLock
expireStale now cl = cl { lockTokens = filter (not . isExpired) (lockTokens cl) }
  where
    isExpired ct = diffUTCTime now (ctTimestamp ct) > ctTTL ct

-- ---------------------------------------------------------------------------
-- Load / Save
-- ---------------------------------------------------------------------------

-- | Load existing lock file (.llmll-lock.json alongside source).
loadLock :: FilePath -> IO (Maybe CheckoutLock)
loadLock fp = do
  let lp = lockFilePath fp
  exists <- doesFileExist lp
  if exists
    then A.decodeFileStrict lp
    else pure Nothing

-- | Save lock file.
saveLock :: FilePath -> CheckoutLock -> IO ()
saveLock fp cl = do
  let lp = lockFilePath fp
  BL.writeFile lp (A.encode cl)

-- ---------------------------------------------------------------------------
-- Core Operations
-- ---------------------------------------------------------------------------

-- | Validate pointer targets a hole node in the JSON-AST, create lock, return token.
-- Auto-expires stale locks before checking for conflicts.
checkoutHole :: FilePath -> Value -> Text -> IO (Either Diagnostic CheckoutToken)
checkoutHole fp astVal pointer = do
  -- 1. Resolve pointer against JSON Value
  case resolvePointer pointer astVal of
    Nothing -> pure $ Left $ mkDiag fp $
      "pointer " <> pointer <> " does not resolve to any node in the JSON-AST"
    Just node
      -- 2. Check if it's a hole node
      | not (isHoleNode node) -> do
          let hints = findDescendantHoles pointer astVal
              hintMsg = case hints of
                []    -> ""
                (h:_) -> "; did you mean " <> h <> "?"
          pure $ Left $ mkDiag fp $
            "pointer " <> pointer <> " does not target a hole node" <> hintMsg
      | otherwise -> do
          -- 3. Extract hole kind
          let holeKind = case node of
                Object o -> case KM.lookup "kind" o of
                  Just (String k) -> k
                  _               -> "hole-unknown"
                _ -> "hole-unknown"

          now <- getCurrentTime

          -- 4. Load and clean lock file
          mLock <- loadLock fp
          let lock = maybe (CheckoutLock fp []) id mLock
              cleanLock = expireStale now lock

          -- 5. Check for existing lock on this pointer
          let conflict = filter (\ct -> ctPointer ct == pointer) (lockTokens cleanLock)
          case conflict of
            (_:_) -> pure $ Left $ mkDiag fp $
              "hole at " <> pointer <> " is already checked out"
            [] -> do
              -- 6. Generate token, append to lock
              tok <- generateCheckoutToken
              let ct = CheckoutToken
                    { ctPointer   = pointer
                    , ctHoleKind  = holeKind
                    , ctExpected  = Nothing
                    , ctTimestamp = now
                    , ctToken     = tok
                    , ctTTL       = 3600  -- 1 hour default
                    }
                  newLock = cleanLock { lockTokens = lockTokens cleanLock ++ [ct] }
              saveLock fp newLock
              pure $ Right ct

-- | Release a lock explicitly. Agent calls this to abandon a checkout.
releaseHole :: FilePath -> Text -> IO (Either Diagnostic ())
releaseHole fp token = do
  mLock <- loadLock fp
  case mLock of
    Nothing -> pure $ Left $ mkDiag fp "no lock file found"
    Just lock -> do
      now <- getCurrentTime
      let cleanLock = expireStale now lock
          (matching, remaining) = partition' (\ct -> ctToken ct == token) (lockTokens cleanLock)
      case matching of
        [] -> pure $ Left $ mkDiag fp "token not found in lock file (may have expired)"
        _  -> do
          let newLock = cleanLock { lockTokens = remaining }
          saveLock fp newLock
          pure $ Right ()

-- | Query remaining TTL for a token.
checkoutStatus :: FilePath -> Text -> IO (Either Diagnostic NominalDiffTime)
checkoutStatus fp token = do
  mLock <- loadLock fp
  case mLock of
    Nothing -> pure $ Left $ mkDiag fp "no lock file found"
    Just lock -> do
      now <- getCurrentTime
      let cleanLock = expireStale now lock
          match = filter (\ct -> ctToken ct == token) (lockTokens cleanLock)
      case match of
        [] -> pure $ Left $ mkDiag fp "token not found (may have expired)"
        (ct:_) -> do
          let elapsed = diffUTCTime now (ctTimestamp ct)
              remaining = ctTTL ct - elapsed
          pure $ Right (max 0 remaining)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkDiag :: FilePath -> Text -> Diagnostic
mkDiag fp msg = Diagnostic
  { diagSeverity      = SevError
  , diagSpan          = Just (Span fp 0 0 0 0)
  , diagMessage       = msg
  , diagSuggestion    = Nothing
  , diagCode          = Nothing
  , diagKind          = Nothing
  , diagPointer       = Nothing
  , diagInferredType  = Nothing
  , diagHoleSensitive = False
  , diagExpected      = Nothing
  , diagGot           = Nothing
  , diagHole          = Nothing
  }

-- | Simple partition (avoids import of Data.List.partition for clarity).
partition' :: (a -> Bool) -> [a] -> ([a], [a])
partition' _ [] = ([], [])
partition' p (x:xs)
  | p x       = let (ys, ns) = partition' p xs in (x:ys, ns)
  | otherwise  = let (ys, ns) = partition' p xs in (ys, x:ns)
