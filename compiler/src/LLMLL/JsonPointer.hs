-- |
-- Module      : LLMLL.JsonPointer
-- Description : RFC 6901 JSON Pointer operations on Data.Aeson.Value.
--
-- Pure structural operations — no domain logic. Used by both
-- LLMLL.Checkout (pointer validation) and LLMLL.PatchApply (patch ops).
module LLMLL.JsonPointer
  ( resolvePointer
  , setAtPointer
  , removeAtPointer
  , parsePointer
  , isHoleNode
  , findDescendantHoles
  ) where

import Data.Aeson (Value(..))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key as K
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Pointer Parsing (RFC 6901)
-- ---------------------------------------------------------------------------

-- | Parse an RFC 6901 pointer into path segments.
-- "/statements/2/body" → ["statements", "2", "body"]
-- "" → []
parsePointer :: Text -> [Text]
parsePointer "" = []
parsePointer p
  | T.head p == '/' = filter (not . T.null) $ T.splitOn "/" (T.drop 1 p)
  | otherwise       = filter (not . T.null) $ T.splitOn "/" p

-- ---------------------------------------------------------------------------
-- Resolve
-- ---------------------------------------------------------------------------

-- | Resolve a pointer against a JSON Value.
-- Returns Nothing if any segment fails to resolve.
resolvePointer :: Text -> Value -> Maybe Value
resolvePointer ptr val = go (parsePointer ptr) val
  where
    go []     v          = Just v
    go (s:ss) (Object o) = KM.lookup (K.fromText s) o >>= go ss
    go (s:ss) (Array a)  = readMaybe (T.unpack s) >>= (a V.!?) >>= go ss
    go _      _          = Nothing

-- ---------------------------------------------------------------------------
-- Set at pointer
-- ---------------------------------------------------------------------------

-- | Set a value at a pointer location. Returns Left on invalid path.
setAtPointer :: Text -> Value -> Value -> Either Text Value
setAtPointer ptr newVal root = go (parsePointer ptr) root
  where
    go []     _          = Right newVal
    go (s:ss) (Object o) =
      case KM.lookup (K.fromText s) o of
        Nothing -> Left $ "key not found: " <> s
        Just child -> do
          child' <- go ss child
          Right (Object (KM.insert (K.fromText s) child' o))
    go (s:ss) (Array a) =
      case readMaybe (T.unpack s) of
        Nothing -> Left $ "invalid array index: " <> s
        Just i
          | i < 0 || i >= V.length a -> Left $ "array index out of bounds: " <> s
          | otherwise -> do
              child' <- go ss (a V.! i)
              Right (Array (a V.// [(i, child')]))
    go (s:_) _ = Left $ "cannot descend into non-container at: " <> s

-- ---------------------------------------------------------------------------
-- Remove at pointer
-- ---------------------------------------------------------------------------

-- | Remove the node at a pointer location.
removeAtPointer :: Text -> Value -> Either Text Value
removeAtPointer ptr root =
  let segs = parsePointer ptr
  in case segs of
    [] -> Left "cannot remove root"
    _  -> goRemove segs root
  where
    goRemove [s]    (Object o)
      | KM.member (K.fromText s) o = Right (Object (KM.delete (K.fromText s) o))
      | otherwise                  = Left $ "key not found for remove: " <> s
    goRemove [s]    (Array a) = case readMaybe (T.unpack s) of
      Nothing -> Left $ "invalid array index for remove: " <> s
      Just i
        | i < 0 || i >= V.length a -> Left $ "array index out of bounds for remove: " <> s
        | otherwise -> Right (Array (V.ifilter (\idx _ -> idx /= i) a))
    goRemove (s:ss) (Object o) = case KM.lookup (K.fromText s) o of
      Nothing    -> Left $ "key not found: " <> s
      Just child -> do
        child' <- goRemove ss child
        Right (Object (KM.insert (K.fromText s) child' o))
    goRemove (s:ss) (Array a) = case readMaybe (T.unpack s) of
      Nothing -> Left $ "invalid array index: " <> s
      Just i
        | i < 0 || i >= V.length a -> Left $ "array index out of bounds: " <> s
        | otherwise -> do
            child' <- goRemove ss (a V.! i)
            Right (Array (a V.// [(i, child')]))
    goRemove (s:_) _ = Left $ "cannot descend into non-container at: " <> s
    goRemove []    _ = Left "cannot remove root"

-- ---------------------------------------------------------------------------
-- Hole detection
-- ---------------------------------------------------------------------------

-- | Check if a JSON node represents a hole (kind starts with "hole-").
isHoleNode :: Value -> Bool
isHoleNode (Object o) =
  case KM.lookup "kind" o of
    Just (String k) -> T.isPrefixOf "hole-" k
    _               -> False
isHoleNode _ = False

-- | Find all hole-node pointers that are descendants of the given pointer.
-- Used by checkout to provide hints when pointer doesn't target a hole directly.
findDescendantHoles :: Text -> Value -> [Text]
findDescendantHoles ptr root =
  case resolvePointer ptr root of
    Nothing  -> []
    Just val -> map (\suffix -> if T.null suffix then ptr else ptr <> "/" <> suffix) (findHoles "" val)
  where
    findHoles :: Text -> Value -> [Text]
    findHoles prefix v
      | isHoleNode v = [prefix]
      | otherwise = case v of
          Object o -> concatMap (\(k, child) ->
            let seg = K.toText k
                p   = if T.null prefix then seg else prefix <> "/" <> seg
            in findHoles p child) (KM.toList o)
          Array a -> concatMap (\(i, child) ->
            let seg = T.pack (show i)
                p   = if T.null prefix then seg else prefix <> "/" <> seg
            in findHoles p child) (zip [0..] (V.toList a))
          _ -> []
