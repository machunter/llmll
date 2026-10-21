{-# LANGUAGE OverloadedStrings #-}
-- | FFI-TIER1-1 (docs/design/ffi-tier1-proposal.md): the Tier 1 Hackage
-- boundary. A @haskell.*@ import's interface entries become forced, typed
-- bindings in Lib.hs. This module holds the parts the type checker, the
-- emitter and the trust report must agree on: the closed package set (D5),
-- the name rule (D2), the type rules (D3, D4) and the result forcers (D1).
--
-- Leaf over "LLMLL.Syntax", like "LLMLL.TypeAdmissibility": a dependency on
-- the checker or the emitter would make one of them see the other.
module LLMLL.Ffi
  ( ffiPackageModules
  , FfiEntry(..)
  , ffiEntriesOf
  , ffiEntryNames
  , ffiImportErrors
  , camelName
  , forcerFor
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.Syntax

-- | D5: the nine packages, each mapped to the Haskell module its exports are
-- read from. A @haskell.*@ path naming any other package is
-- @ffi-unknown-package@.
ffiPackageModules :: Map Text Text
ffiPackageModules = Map.fromList
  [ ("aeson",       "Data.Aeson")
  , ("text",        "Data.Text")
  , ("bytestring",  "Data.ByteString")
  , ("containers",  "Data.Map.Strict")
  , ("vector",      "Data.Vector")
  , ("time",        "Data.Time")
  , ("directory",   "System.Directory")
  , ("filepath",    "System.FilePath")
  , ("process",     "System.Process")
  ]

-- | One interface entry of a @haskell.*@ import.
data FfiEntry = FfiEntry
  { feName    :: Name                   -- ^ the LLMLL name, e.g. @take-extension@
  , fePackage :: Text                   -- ^ e.g. @filepath@
  , feModule  :: Text                   -- ^ e.g. @System.FilePath@
  , feType    :: Type                   -- ^ the declared type
  , feSrc     :: Maybe (FilePath, Int)  -- ^ the import's source location
  } deriving (Show, Eq)

-- | The interface entries of every @haskell.*@ import of a known package.
ffiEntriesOf :: [Statement] -> [FfiEntry]
ffiEntriesOf stmts =
  [ FfiEntry n pkg modPath t (importSrc imp)
  | SImport imp <- stmts
  , Just pkg <- [T.stripPrefix "haskell." (importPath imp)]
  , Just modPath <- [Map.lookup pkg ffiPackageModules]
  , (n, t) <- fromMaybe [] (importInterface imp) ]

-- | The names a module's @haskell.*@ interfaces bind.
ffiEntryNames :: [Statement] -> [Name]
ffiEntryNames = map feName . ffiEntriesOf

-- | D2: @take-extension@ is @takeExtension@.
camelName :: Name -> Text
camelName n = case T.splitOn "-" n of
  []       -> n
  (w : ws) -> T.concat (w : map cap ws)
  where
    cap t = case T.uncons t of
      Just (c, rest) -> T.cons (toUpperAscii c) rest
      Nothing        -> t
    toUpperAscii c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise            = c

-- | The errors one import raises, as (diagKind, message). Empty for an import
-- that is not @haskell.*@.
ffiImportErrors :: Import -> [(Text, Text)]
ffiImportErrors imp = case T.stripPrefix "haskell." (importPath imp) of
  Nothing -> []
  Just pkg
    | not (Map.member pkg ffiPackageModules) ->
        [ ( "ffi-unknown-package"
          , "unknown Hackage package 'haskell." <> pkg <> "': Tier 1 imports are limited to "
            <> T.intercalate ", " (map ("haskell." <>) (Map.keys ffiPackageModules)) ) ]
    | otherwise -> concatMap (entryErrors pkg) (fromMaybe [] (importInterface imp))

entryErrors :: Text -> (Name, Type) -> [(Text, Text)]
entryErrors pkg (n, t)
  | T.any (`elem` ("?!'." :: String)) n =
      [ ( "ffi-name-unmappable"
        , "interface entry '" <> n <> "' of haskell." <> pkg
          <> " has no Haskell name: an entry name may not contain ?, !, ' or ." ) ]
  | hasEffect t =
      [ ( "ffi-effect-refused"
        , "interface entry '" <> n <> "' of haskell." <> pkg
          <> " mentions Command or Promise: Tier 1 entries are pure functions; "
          <> "effects go through wasi.* builtins" ) ]
  | otherwise = case typeProblem of
      Just why -> [ ( "ffi-type-unsupported"
                    , "interface entry '" <> n <> "' of haskell." <> pkg <> ": " <> why ) ]
      Nothing  -> []
  where
    (params, result) = case t of
      TFn as r -> (as, r)
      _        -> ([], t)
    typeProblem = firstJust (map paramProblem params ++ [resultProblem result])
    paramProblem p = unsupported True p
    resultProblem r
      | mentionsFn r    = Just "the result contains a function type; write a curried result as more parameters"
      | mentionsBytes r = Just "the result contains bytes[n]; nothing checks the length of bytes a Haskell function returns"
      | otherwise       = unsupported False r

-- | The first type in a parameter or result position that D3 does not allow.
-- A function type is allowed as a parameter, over the same types.
unsupported :: Bool -> Type -> Maybe Text
unsupported inParam ty = case ty of
  TInt        -> Nothing
  TFloat      -> Nothing
  TString     -> Nothing
  TBool       -> Nothing
  TUnit       -> Nothing
  TBytes _
    | inParam   -> Nothing
  TList a     -> unsupported inParam a
  TMap k v    -> firstJust [unsupported inParam k, unsupported inParam v]
  TPair a b   -> firstJust [unsupported inParam a, unsupported inParam b]
  TResult a b -> firstJust [unsupported inParam a, unsupported inParam b]
  TFn as r
    | inParam   -> firstJust (map (unsupported True) as ++ [unsupported True r])
  _           -> Just ("type '" <> typeLabel ty <> "' is not allowed at the Tier 1 boundary; "
                       <> "allowed: int, float, string, bool, unit, list, map, pairs, Result, "
                       <> "and as parameters bytes[n] and fn types over these")

hasEffect :: Type -> Bool
hasEffect = anyType isEffect
  where
    isEffect (TCustom "Command") = True
    isEffect (TPromise _)        = True
    isEffect _                   = False

mentionsFn :: Type -> Bool
mentionsFn = anyType isFn
  where isFn TFn{} = True
        isFn _     = False

mentionsBytes :: Type -> Bool
mentionsBytes = anyType isBytes
  where isBytes TBytes{} = True
        isBytes _        = False

-- | Does any node of the type satisfy the predicate?
anyType :: (Type -> Bool) -> Type -> Bool
anyType p ty = p ty || case ty of
  TList a          -> anyType p a
  TMap k v         -> anyType p k || anyType p v
  TPair a b        -> anyType p a || anyType p b
  TResult a b      -> anyType p a || anyType p b
  TFn as r         -> any (anyType p) as || anyType p r
  TPromise a       -> anyType p a
  TDependent _ b _ -> anyType p b
  _                -> False

firstJust :: [Maybe a] -> Maybe a
firstJust ms = case [ x | Just x <- ms ] of
  (x : _) -> Just x
  []      -> Nothing

-- | D1: the forcer for a binding's result type, built from the type. The
-- existing 'esResultForcers' table is keyed by builtin name and stays as it is.
forcerFor :: Type -> Text
forcerFor ty = case ty of
  TString     -> "llmll_uS"
  TList a     -> "(llmll_uL " <> forcerFor a <> ")"
  TMap k v    -> "(llmll_uM " <> forcerFor k <> " " <> forcerFor v <> ")"
  TPair a b   -> "(llmll_uP2 " <> forcerFor a <> " " <> forcerFor b <> ")"
  TResult t e -> "(llmll_uEi " <> forcerFor e <> " " <> forcerFor t <> ")"
  TBytes _    -> "(llmll_uL llmll_uW)"
  _           -> "llmll_uW"
