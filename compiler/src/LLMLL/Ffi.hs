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
  , lowerBoundaryMisuse
  , convIn
  , convOut
  ) where

import Data.Functor.Const (Const(..))
import Data.Functor.Identity (Identity(..))
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
-- FFI-E20-CASCADE-1: the 'TPromise', 'TDependent' and 'TSumType' arms make it
-- cover the same constructors as the E20 collector, so a misused boundary type
-- is lowered wherever E20 finds it. No interface entry reaches these arms: D10
-- refuses all three in an entry before lowering.
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
  TPromise a                     -> TPromise (lowerFfiType a)
  TDependent n b p               -> TDependent n (lowerFfiType b) p
  TSumType cs                    -> TSumType [ (c, fmap lowerFfiType t) | (c, t) <- cs ]
  _                              -> ty

-- | FFI-E20-CASCADE-1: the one traversal over every type position that is not
-- inside a @haskell.*@ interface entry. E20 collects through it
-- ('ffiBoundaryMisuse') and the checker's recovery lowers through it
-- ('lowerBoundaryMisuse'), so the positions E20 reports and the positions the
-- lowering repairs cannot differ. Visited: non-@haskell.*@ import interfaces,
-- type-def bodies, def-interface signatures, check bindings and bodies, and
-- the parameters, return type and body of every def form (the decreases of a
-- letrec too; not contracts). Inside an expression: let annotations and
-- lambda parameters. Every other position is returned unchanged.
traverseNonFfiTypes :: Applicative f => (Type -> f Type) -> Statement -> f Statement
traverseNonFfiTypes f st = case st of
  SImport imp
    | "haskell." `T.isPrefixOf` importPath imp -> pure st
    | otherwise -> case importInterface imp of
        Nothing  -> pure st
        Just ifc -> (\ifc' -> SImport imp { importInterface = Just ifc' }) <$> traverse binding ifc
  STypeDef n body -> STypeDef n <$> f body
  SDefInterface n fns laws -> (\fns' -> SDefInterface n fns' laws) <$> traverse binding fns
  SCheck p -> (\bs b -> SCheck p { propBindings = bs, propBody = b })
                <$> traverse binding (propBindings p) <*> expr (propBody p)
  SLetrec n ps r c d b -> (\ps' r' d' b' -> SLetrec n ps' r' c d' b')
                <$> traverse binding ps <*> traverse f r <*> expr d <*> expr b
  SDefLogic n ps r c b -> (\ps' r' b' -> SDefLogic n ps' r' c b')
                <$> traverse binding ps <*> traverse f r <*> expr b
  SDef n ps r c b -> (\ps' r' b' -> SDef n ps' r' c b')
                <$> traverse binding ps <*> traverse f r <*> expr b
  SDefShell n ps r c b ds -> (\ps' r' b' -> SDefShell n ps' r' c b' ds)
                <$> traverse binding ps <*> traverse f r <*> expr b
  SDefInvariant n ps r c b -> (\ps' r' b' -> SDefInvariant n ps' r' c b')
                <$> traverse binding ps <*> traverse f r <*> expr b
  _ -> pure st
  where
    binding (n, t) = (,) n <$> f t
    -- A let visits every annotation before every bound expression, the order
    -- the E20 collector reported in before this traversal existed.
    expr e = case e of
      ELet bs b ->
        (\ts xs b' -> ELet (zipWith3 (\(p, _, _) t x -> (p, t, x)) bs ts xs) b')
          <$> traverse (\(_, t, _) -> traverse f t) bs
          <*> traverse (\(_, _, x) -> expr x) bs
          <*> expr b
      ELambda ps b  -> ELambda <$> traverse binding ps <*> expr b
      EMatch x arms -> EMatch <$> expr x <*> traverse (\(p, a) -> (,) p <$> expr a) arms
      EDo steps     -> EDo <$> traverse (\s -> (\x -> s { dsExpr = x }) <$> expr (dsExpr s)) steps
      EApp g as     -> EApp g <$> traverse expr as
      EOp o as      -> EOp o <$> traverse expr as
      EIf c t e'    -> EIf <$> expr c <*> expr t <*> expr e'
      EPair a b     -> EPair <$> expr a <*> expr b
      EAwait x      -> EAwait <$> expr x
      _             -> pure e

-- | E20: the boundary type names used outside a haskell.* interface entry.
ffiBoundaryMisuse :: [Statement] -> [Name]
ffiBoundaryMisuse stmts =
  nub (concatMap (getConst . traverseNonFfiTypes (Const . boundaryNames)) stmts)
  where
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

-- | FFI-E20-CASCADE-1: the statements with every boundary type that E20
-- reports replaced by its lowered LLMLL type. The checker reports E20 on the
-- source statements and type-checks this copy, so a misused @hs-text@ gives
-- E20 alone and no follow-on @type-mismatch@. It is the identity on a program
-- with no E20: @ffiBoundaryMisuse ss == []@ implies
-- @lowerBoundaryMisuse ss == ss@.
lowerBoundaryMisuse :: [Statement] -> [Statement]
lowerBoundaryMisuse = map (runIdentity . traverseNonFfiTypes (Identity . lowerFfiType))

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
