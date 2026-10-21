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
  , lowerFfiType
  , ffiBoundaryMisuse
  , convIn
  , convOut
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.List (nub)
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
    typeProblem = firstJust (map (allowed CArg False) params ++ [resultProblem result])
    resultProblem r
      | mentionsFn r    = Just "the result contains a function type; write a curried result as more parameters"
      | mentionsBytes r = Just "the result contains bytes[n]; nothing checks the length of bytes a Haskell function returns"
      | otherwise       = allowed CRes False r

-- | Where a type sits in an entry: an argument (LLMLL to Haskell), the result
-- (Haskell to LLMLL), or anywhere inside a function-typed parameter.
data Ctx = CArg | CRes | CFn deriving Eq

-- | The first problem D3 and D10 find in a type at a position, or Nothing.
-- The flag is set inside the key type of a map.
allowed :: Ctx -> Bool -> Type -> Maybe Text
allowed c inKey ty = case ty of
  TInt        -> Nothing
  TFloat      -> Nothing
  TString     -> Nothing
  TBool       -> Nothing
  TUnit       -> Nothing
  TBytes _
    | c /= CRes -> Nothing
  -- FFI-CONV-1 (D10): the boundary types and the direction rule.
  TCustom "hs-text"
    | c == CFn  -> inFn
    | c == CArg && inKey ->
        Just "hs-text in the key type of a map argument: pack is not injective on map keys \
             \(two keys that differ only by a lone surrogate would merge); use string"
    | otherwise -> Nothing
  TCustom "hs-int"
    | c == CFn  -> inFn
    | c == CArg -> Just "hs-int as an argument: narrowing int to Int needs FFI-NARROW-1"
    | otherwise -> Nothing
  TResult t (TCustom "hs-maybe")
    | c == CFn  -> inFn
    | otherwise -> allowed c inKey t
  TCustom "hs-maybe" -> Just "hs-maybe needs an element type: write hs-maybe[T]"
  TList a     -> allowed c inKey a
  TMap k v    -> firstJust [allowed c True k, allowed c inKey v]
  TPair a b   -> firstJust [allowed c inKey a, allowed c inKey b]
  TResult a b -> firstJust [allowed c inKey a, allowed c inKey b]
  TFn as r
    | c /= CRes -> firstJust (map (allowed CFn False) as ++ [allowed CFn False r])
  _           -> Just ("type '" <> typeLabel ty <> "' is not allowed at the Tier 1 boundary; "
                       <> "allowed: int, float, string, bool, unit, list, map, pairs, Result, "
                       <> "hs-text, hs-maybe[T], hs-int (result only), "
                       <> "and as parameters bytes[n] and fn types over these")
  where
    inFn = Just "a boundary type inside a function-typed parameter is not supported"

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

-- | FFI-CONV-1 (D10): the LLMLL type a program sees for a declared type.
lowerFfiType :: Type -> Type
lowerFfiType ty = case ty of
  TCustom "hs-text"              -> TString
  TCustom "hs-int"               -> TInt
  TResult t (TCustom "hs-maybe") -> TResult (lowerFfiType t) TUnit
  TList a                        -> TList (lowerFfiType a)
  TMap k v                       -> TMap (lowerFfiType k) (lowerFfiType v)
  TPair a b                      -> TPair (lowerFfiType a) (lowerFfiType b)
  TResult a b                    -> TResult (lowerFfiType a) (lowerFfiType b)
  TFn as r                       -> TFn (map lowerFfiType as) (lowerFfiType r)
  _                              -> ty

-- | E20: the boundary type names used outside a haskell.* interface entry.
ffiBoundaryMisuse :: [Statement] -> [Name]
ffiBoundaryMisuse stmts = nub (concatMap (boundaryNames . snd) (concatMap typesOf stmts))
  where
    typesOf st = case st of
      SImport imp
        | "haskell." `T.isPrefixOf` importPath imp -> []
        | otherwise -> map (\(n, t) -> (n, t)) (fromMaybe [] (importInterface imp))
      STypeDef n body -> [(n, body)]
      SDefInterface _ fns _ -> fns
      SCheck p -> propBindings p ++ exprTypes (propBody p)
      SLetrec n ps r _ d b -> sig n ps r ++ exprTypes d ++ exprTypes b
      _ -> case normalizeDefStmt st of
             Just (n, ps, r, _, b) -> sig n ps r ++ exprTypes b
             Nothing               -> []
    sig n ps r = ps ++ [ (n, t) | Just t <- [r] ]
    exprTypes e = case e of
      ELet bs b      -> [ ("let", t) | (_, Just t, _) <- bs ] ++ concat [ exprTypes x | (_, _, x) <- bs ] ++ exprTypes b
      ELambda ps b   -> ps ++ exprTypes b
      EMatch x arms  -> exprTypes x ++ concatMap (exprTypes . snd) arms
      EDo steps      -> concat [ exprTypes x | DoStep _ x _ <- steps ]
      EApp _ as      -> concatMap exprTypes as
      EOp _ as       -> concatMap exprTypes as
      EIf c t f      -> exprTypes c ++ exprTypes t ++ exprTypes f
      EPair a b      -> exprTypes a ++ exprTypes b
      EAwait x       -> exprTypes x
      _              -> []
    boundaryNames ty = case ty of
      TCustom n | n `elem` ["hs-text", "hs-int", "hs-maybe"] -> [n]
      TResult t (TCustom "hs-maybe") -> "hs-maybe" : boundaryNames t
      TList a          -> boundaryNames a
      TMap k v         -> boundaryNames k ++ boundaryNames v
      TPair a b        -> boundaryNames a ++ boundaryNames b
      TResult a b      -> boundaryNames a ++ boundaryNames b
      TFn as r         -> concatMap boundaryNames as ++ boundaryNames r
      TPromise a       -> boundaryNames a
      TDependent _ b _ -> boundaryNames b
      TSumType cs      -> concat [ boundaryNames t | (_, Just t) <- cs ]
      _                -> []

-- | FFI-CONV-1 (D10): the converter from the LLMLL value to the Haskell
-- argument, or Nothing for @id@. Every converter that is not @id@ carries an
-- explicit Haskell type, so GHC checks the declared boundary type against the
-- export (E25). An @hs-int@ or an @hs-text@ map key never reaches here: the
-- checker refuses both in an argument.
convIn :: Type -> Maybe Text
convIn ty = case ty of
  TCustom "hs-text" -> Just "(Data.Text.pack :: String -> Data.Text.Text)"
  TResult t (TCustom "hs-maybe") ->
    Just ("(either (const Nothing) (Just . " <> orId (convIn t) <> "))")
  TList a  -> (\c -> "(map " <> c <> ")") <$> convIn a
  TMap _ v -> (\c -> "(Map.map " <> c <> ")") <$> convIn v
  TPair a b -> pairConv (convIn a) (convIn b)
  TResult a b -> resultConv (convIn a) (convIn b)
  _ -> Nothing

-- | FFI-CONV-1 (D10): the converter from the Haskell result to the LLMLL
-- value, or Nothing for @id@.
convOut :: Type -> Maybe Text
convOut ty = case ty of
  TCustom "hs-text" -> Just "(Data.Text.unpack :: Data.Text.Text -> String)"
  TCustom "hs-int"  -> Just "(toInteger :: Int -> Integer)"
  TResult t (TCustom "hs-maybe") ->
    Just ("(maybe (Left ()) (Right . " <> orId (convOut t) <> "))")
  TList a  -> (\c -> "(map " <> c <> ")") <$> convOut a
  TMap k v -> case (convOut k, convOut v) of
    (Nothing, Nothing) -> Nothing
    (ck, cv) -> Just ("(Map.fromList . map (\\(k, v) -> (" <> orId ck <> " k, " <> orId cv <> " v)) . Map.toList)")
  TPair a b -> pairConv (convOut a) (convOut b)
  TResult a b -> resultConv (convOut a) (convOut b)
  _ -> Nothing

orId :: Maybe Text -> Text
orId = fromMaybe "id"

pairConv :: Maybe Text -> Maybe Text -> Maybe Text
pairConv Nothing Nothing = Nothing
pairConv ca cb = Just ("(\\(x, y) -> (" <> orId ca <> " x, " <> orId cb <> " y))")

resultConv :: Maybe Text -> Maybe Text -> Maybe Text
resultConv Nothing Nothing = Nothing
resultConv ct ce = Just ("(either (Left . " <> orId ce <> ") (Right . " <> orId ct <> "))")

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
