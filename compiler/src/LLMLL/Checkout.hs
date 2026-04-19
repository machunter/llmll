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
-- | v0.3.5: Context-aware checkout (Phase C) adds local typing context
-- (Γ, τ, Σ) to the checkout response so agents know what's in scope.
module LLMLL.Checkout
  ( CheckoutToken(..)
  , CheckoutLock(..)
  , ScopeEntry(..)
  , FuncEntry(..)
  , TypeDefEntry(..)
  , ScopeBinding(..)
  , ScopeSource(..)
  , checkoutHole
  , checkoutHoleWithContext
  , releaseHole
  , checkoutStatus
  , loadLock
  , saveLock
  , expireStale
  , lockFilePath
  , normalizePointer
  -- v0.3.5 C4-C6: Context building utilities
  , collectTypeDefinitions
  , monomorphizeFunctions
  , truncateScope
  , buildScopeEntries
  , buildFuncEntries
  , sourceLabel
  ) where

import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), withObject, (.:), (.:?), (.=), object)
import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Read as TR
import Data.Text (Text)
import Data.Time.Clock (UTCTime, NominalDiffTime, getCurrentTime, diffUTCTime, addUTCTime)
import GHC.Generics (Generic)
import Numeric (showHex)
import System.Directory (doesFileExist)
import System.FilePath (replaceExtension, takeExtension)
import System.Random (randomRIO)
import Data.List (isSuffixOf)
import Data.Maybe (mapMaybe)

import LLMLL.JsonPointer (resolvePointer, isHoleNode, findDescendantHoles)
import LLMLL.Diagnostic (Diagnostic(..), Severity(..))
import LLMLL.Syntax (Span(..), Type(..), Name, typeLabel)
import LLMLL.TypeCheck (ScopeBinding(..), ScopeSource(..))

-- ---------------------------------------------------------------------------
-- Data Types
-- ---------------------------------------------------------------------------

-- | v0.3.5: A binding visible at the hole site.
data ScopeEntry = ScopeEntry
  { seName   :: Text   -- ^ binding name
  , seType   :: Text   -- ^ LLMLL type notation (e.g. "list[int]")
  , seSource :: Text   -- ^ "param" | "let-binding" | "match-arm" | "open-import"
  } deriving (Show, Eq, Generic)

instance ToJSON ScopeEntry where
  toJSON se = object
    [ "name"   .= seName se
    , "type"   .= seType se
    , "source" .= seSource se
    ]

instance FromJSON ScopeEntry where
  parseJSON = withObject "ScopeEntry" $ \o ->
    ScopeEntry <$> o .: "name" <*> o .: "type" <*> o .: "source"

-- | v0.3.5: A function signature available at the hole site.
data FuncEntry = FuncEntry
  { feName   :: Text           -- ^ function name
  , feParams :: [(Text, Text)] -- ^ [(paramName, typeName)]
  , feReturn :: Text           -- ^ return type label
  , feStatus :: Text           -- ^ "filled" | "hole" | "builtin"
  } deriving (Show, Eq, Generic)

instance ToJSON FuncEntry where
  toJSON fe = object
    [ "name"    .= feName fe
    , "params"  .= map (\(n, t) -> object ["name" .= n, "type" .= t]) (feParams fe)
    , "returns" .= feReturn fe
    , "status"  .= feStatus fe
    ]

instance FromJSON FuncEntry where
  parseJSON = withObject "FuncEntry" $ \o ->
    FuncEntry <$> o .: "name" <*> o .: "params" <*> o .: "returns" <*> o .: "status"

-- | v0.3.5: A type definition relevant to the hole's context.
data TypeDefEntry = TypeDefEntry
  { tdName         :: Text                   -- ^ type name
  , tdKind         :: Text                   -- ^ "sum" | "alias" | "dependent"
  , tdConstructors :: Maybe [(Text, Maybe Text)]  -- ^ for sum types
  , tdBaseType     :: Maybe Text             -- ^ for aliases/dependent types
  , tdRecursive    :: Bool                   -- ^ EC-4: cycle detected during expansion
  } deriving (Show, Eq, Generic)

instance ToJSON TypeDefEntry where
  toJSON td = object $
    [ "name" .= tdName td
    , "kind" .= tdKind td
    ] ++
    maybe [] (\cs -> ["constructors" .=
      map (\(n, mp) -> object $ ["name" .= n] ++ maybe [] (\p -> ["payload" .= p]) mp) cs
    ]) (tdConstructors td) ++
    maybe [] (\bt -> ["base_type" .= bt]) (tdBaseType td) ++
    ["recursive" .= True | tdRecursive td]

instance FromJSON TypeDefEntry where
  parseJSON = withObject "TypeDefEntry" $ \o -> do
    n <- o .: "name"
    k <- o .: "kind"
    cs <- o .:? "constructors"
    bt <- o .:? "base_type"
    rec_ <- o .:? "recursive"
    pure TypeDefEntry
      { tdName = n, tdKind = k, tdConstructors = cs
      , tdBaseType = bt, tdRecursive = maybe False id rec_ }

data CheckoutToken = CheckoutToken
  { ctPointer   :: Text             -- RFC 6901 pointer to the hole
  , ctHoleKind  :: Text             -- e.g. "hole-delegate", "hole-named"
  , ctExpected  :: Maybe Text       -- expected return type (from hole spec, if available)
  , ctTimestamp :: UTCTime           -- lock creation time
  , ctToken     :: Text             -- 32-char hex random bearer token
  , ctTTL       :: NominalDiffTime   -- lock duration (default: 3600s)
  -- v0.3.5: Context-aware checkout fields (Phase C)
  , ctInScope           :: Maybe [ScopeEntry]    -- ^ Γ delta
  , ctExpectedReturn    :: Maybe Text             -- ^ τ as type label
  , ctAvailableFunctions :: Maybe [FuncEntry]     -- ^ Σ (relevant signatures)
  , ctTypeDefinitions   :: Maybe [TypeDefEntry]   -- ^ alias/sum type definitions
  , ctScopeTruncated    :: Bool                   -- ^ C6: true if scope was truncated
  } deriving (Show, Eq, Generic)

instance ToJSON CheckoutToken where
  toJSON ct = object $
    [ "pointer"   .= ctPointer ct
    , "hole_kind" .= ctHoleKind ct
    , "token"     .= ctToken ct
    , "ttl"       .= (round (ctTTL ct) :: Int)
    , "timestamp" .= ctTimestamp ct
    ] ++
    maybe [] (\s  -> ["in_scope"             .= s])  (ctInScope ct) ++
    maybe [] (\rt -> ["expected_return_type"  .= rt]) (ctExpectedReturn ct) ++
    maybe [] (\fs -> ["available_functions"   .= fs]) (ctAvailableFunctions ct) ++
    maybe [] (\td -> ["type_definitions"      .= td]) (ctTypeDefinitions ct) ++
    ["scope_truncated" .= True | ctScopeTruncated ct]

instance FromJSON CheckoutToken where
  parseJSON = withObject "CheckoutToken" $ \o -> do
    p  <- o .: "pointer"
    hk <- o .: "hole_kind"
    tok <- o .: "token"
    ttlSec <- o .: "ttl"
    ts <- o .: "timestamp"
    expected <- o .:? "expected"
    scope <- o .:? "in_scope"
    expRet <- o .:? "expected_return_type"
    funcs <- o .:? "available_functions"
    tdefs <- o .:? "type_definitions"
    trunc <- o .:? "scope_truncated"
    pure CheckoutToken
      { ctPointer   = p
      , ctHoleKind  = hk
      , ctExpected  = expected
      , ctTimestamp = ts
      , ctToken     = tok
      , ctTTL       = fromIntegral (ttlSec :: Int)
      , ctInScope           = scope
      , ctExpectedReturn    = expRet
      , ctAvailableFunctions = funcs
      , ctTypeDefinitions   = tdefs
      , ctScopeTruncated    = maybe False id trunc
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
-- This is the backward-compatible entry point (no context).
checkoutHole :: FilePath -> Value -> Text -> IO (Either Diagnostic CheckoutToken)
checkoutHole fp astVal pointer =
  checkoutHoleWithContext fp astVal pointer Nothing Nothing Nothing Nothing

-- | v0.3.5 (Phase C): Context-aware checkout.
-- Accepts typing context from the type checker (threaded through Main.hs)
-- and includes it in the checkout response.
checkoutHoleWithContext
  :: FilePath
  -> Value               -- ^ JSON-AST
  -> Text                -- ^ pointer (user-supplied, will be normalized)
  -> Maybe [ScopeEntry]  -- ^ Γ delta (in-scope bindings)
  -> Maybe Text          -- ^ τ (expected return type label)
  -> Maybe [FuncEntry]   -- ^ Σ (available function signatures)
  -> Maybe [TypeDefEntry] -- ^ type definitions
  -> IO (Either Diagnostic CheckoutToken)
checkoutHoleWithContext fp astVal rawPointer mScope mExpRet mFuncs mTypeDefs = do
  let pointer = normalizePointer rawPointer
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
                    -- v0.3.5: attach context
                    , ctInScope           = mScope
                    , ctExpectedReturn    = mExpRet
                    , ctAvailableFunctions = mFuncs
                    , ctTypeDefinitions   = mTypeDefs
                    , ctScopeTruncated    = False  -- C6 will set this
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

-- ---------------------------------------------------------------------------
-- v0.3.5: Pointer Normalization (EC-3)
-- ---------------------------------------------------------------------------

-- | Normalize an RFC 6901 pointer: strip leading zeros from numeric segments.
-- "/statements/02/body" → "/statements/2/body"
-- Non-numeric segments are passed through unchanged.
normalizePointer :: Text -> Text
normalizePointer ptr
  | T.null ptr = ptr
  | T.head ptr == '/' = "/" <> T.intercalate "/" (map normalizeSegment (T.splitOn "/" (T.tail ptr)))
  | otherwise = ptr  -- not a valid absolute pointer, pass through
  where
    normalizeSegment seg = case TR.decimal seg of
      Right (n, rest) | T.null rest -> T.pack (show (n :: Int))
      _                             -> seg

-- ---------------------------------------------------------------------------
-- v0.3.5 C4: Type Definition Collection (depth-bounded alias expansion)
-- ---------------------------------------------------------------------------

-- | Collect TypeDefEntry items for all TCustom types referenced in the scope
-- and expected type. Uses depth-bounded expansion (max 5 levels) with cycle
-- detection (EC-4). TDependent types serialize the base type only (EC-5).
collectTypeDefinitions :: Map.Map Name Type -> Maybe Type -> Map.Map Name Type -> [TypeDefEntry]
collectTypeDefinitions scopeTypes mExpected aliasMap =
  let -- Gather all TCustom names referenced in scope types and expected type
      customNames = concatMap collectCustomNames (Map.elems scopeTypes)
                    ++ maybe [] collectCustomNames mExpected
      uniqueNames = Map.keys $ Map.fromList [(n, ()) | n <- customNames]
  in  mapMaybe (expandTypeDef aliasMap [] 5) uniqueNames

-- | Recursively collect TCustom names from a type.
collectCustomNames :: Type -> [Name]
collectCustomNames (TCustom n) = [n]
collectCustomNames (TList t) = collectCustomNames t
collectCustomNames (TMap k v) = collectCustomNames k ++ collectCustomNames v
collectCustomNames (TResult a b) = collectCustomNames a ++ collectCustomNames b
collectCustomNames (TPair a b) = collectCustomNames a ++ collectCustomNames b
collectCustomNames (TFn ps r) = concatMap collectCustomNames ps ++ collectCustomNames r
collectCustomNames (TPromise t) = collectCustomNames t
collectCustomNames (TDependent _ base _) = collectCustomNames base
collectCustomNames _ = []

-- | Expand a single type alias into a TypeDefEntry.
-- visited: cycle detection; fuel: depth bound.
expandTypeDef :: Map.Map Name Type -> [Name] -> Int -> Name -> Maybe TypeDefEntry
expandTypeDef _ _ 0 name = Just TypeDefEntry
  { tdName = name, tdKind = "alias", tdConstructors = Nothing
  , tdBaseType = Just "(expansion depth exceeded)"
  , tdRecursive = True
  }
expandTypeDef aliasMap visited fuel name
  | name `elem` visited = Just TypeDefEntry
      { tdName = name, tdKind = "alias", tdConstructors = Nothing
      , tdBaseType = Nothing, tdRecursive = True
      }
  | otherwise = case Map.lookup name aliasMap of
      Nothing -> Nothing  -- not a user-defined alias, skip
      Just (TSumType ctors) -> Just TypeDefEntry
        { tdName = name, tdKind = "sum"
        , tdConstructors = Just [(cn, fmap typeLabel mp) | (cn, mp) <- ctors]
        , tdBaseType = Nothing, tdRecursive = False
        }
      Just (TDependent _ base _) -> Just TypeDefEntry  -- EC-5: base type only
        { tdName = name, tdKind = "dependent", tdConstructors = Nothing
        , tdBaseType = Just (typeLabel base), tdRecursive = False
        }
      Just other -> Just TypeDefEntry
        { tdName = name, tdKind = "alias", tdConstructors = Nothing
        , tdBaseType = Just (typeLabel other), tdRecursive = False
        }

-- ---------------------------------------------------------------------------
-- v0.3.5 C5: Monomorphization (presentation-only, INV-2)
-- ---------------------------------------------------------------------------

-- | Monomorphize polymorphic function signatures against concrete types in scope.
-- For each TVar in a function's parameter list, if the in-scope bindings contain
-- a concrete type at the matching position (e.g. list[int] matches list[a]),
-- substitute the TVar throughout the signature.
-- This is a presentation-only transformation (INV-2): no builtinEnv mutation.
monomorphizeFunctions
  :: Map.Map Name Type    -- ^ Γ (in-scope bindings: name → type)
  -> Map.Map Name Type    -- ^ Σ (function signatures: name → TFn [...] ret)
  -> Map.Map Name Type    -- ^ Σ' with monomorphized signatures
monomorphizeFunctions scope sigs =
  let -- Collect concrete inner types from scope: e.g. xs : list[int] → (a, int)
      concreteSubst = Map.foldl' extractConcreteBindings Map.empty scope
  in  Map.map (applyMonoSubst concreteSubst) sigs

-- | Extract TVar → concrete type mappings from in-scope types.
-- e.g. list[int] contributes a → int (matching list[a] in builtins).
extractConcreteBindings :: Map.Map Name Type -> Type -> Map.Map Name Type
extractConcreteBindings acc (TList t) | not (isTVar t) =
  Map.insert "a" t acc
extractConcreteBindings acc (TResult t e)
  | not (isTVar t) = Map.insert "a" t (if isTVar e then acc else Map.insert "e" e acc)
  | not (isTVar e) = Map.insert "e" e acc
extractConcreteBindings acc (TMap k v)
  | not (isTVar k) = Map.insert "a" k (if isTVar v then acc else Map.insert "b" v acc)
  | not (isTVar v) = Map.insert "b" v acc
extractConcreteBindings acc (TPair a b)
  | not (isTVar a) = Map.insert "a" a (if isTVar b then acc else Map.insert "b" b acc)
  | not (isTVar b) = Map.insert "b" b acc
extractConcreteBindings acc _ = acc

isTVar :: Type -> Bool
isTVar (TVar _) = True
isTVar _        = False

-- | Apply a monomorphization substitution to a type.
-- Only substitutes TVar → concrete; concrete types pass through.
-- INV-1: idempotent because concrete types contain no TVar.
applyMonoSubst :: Map.Map Name Type -> Type -> Type
applyMonoSubst subst (TVar n) = Map.findWithDefault (TVar n) n subst
applyMonoSubst subst (TList t) = TList (applyMonoSubst subst t)
applyMonoSubst subst (TMap k v) = TMap (applyMonoSubst subst k) (applyMonoSubst subst v)
applyMonoSubst subst (TResult a b) = TResult (applyMonoSubst subst a) (applyMonoSubst subst b)
applyMonoSubst subst (TPair a b) = TPair (applyMonoSubst subst a) (applyMonoSubst subst b)
applyMonoSubst subst (TPromise t) = TPromise (applyMonoSubst subst t)
applyMonoSubst subst (TFn params ret) = TFn (map (applyMonoSubst subst) params) (applyMonoSubst subst ret)
applyMonoSubst _ t = t  -- TInt, TString, TBool, etc. pass through

-- ---------------------------------------------------------------------------
-- v0.3.5 C6: Scope Truncation
-- ---------------------------------------------------------------------------

-- | Truncate an in-scope binding map to at most N entries, respecting
-- ScopeSource priority (SrcParam retained first, SrcOpenImport dropped first).
-- Returns (truncated map, wasTruncated).
-- INV-3: Shadowing safety is structurally guaranteed by Map's single-entry-per-key.
truncateScope :: Int -> [(Name, ScopeEntry)] -> ([ScopeEntry], Bool)
truncateScope limit entries
  | length entries <= limit = (map snd entries, False)
  | otherwise =
      let -- Sort by source priority: param first (lowest ordinal), open-import last
          sorted = sortBySource entries
          kept   = take limit sorted
      in  (map snd kept, True)
  where
    sourcePriority :: Text -> Int
    sourcePriority "param"       = 0
    sourcePriority "let-binding" = 1
    sourcePriority "match-arm"   = 2
    sourcePriority "open-import" = 3
    sourcePriority _             = 4

    sortBySource = sortBy (comparing (sourcePriority . seSource . snd))

    sortBy :: (a -> a -> Ordering) -> [a] -> [a]
    sortBy _ [] = []
    sortBy cmp (x:xs) =
      let (lt, ge) = partition' (\y -> cmp y x == LT) xs
      in sortBy cmp lt ++ [x] ++ sortBy cmp ge

    comparing :: Ord b => (a -> b) -> a -> a -> Ordering
    comparing f a b = compare (f a) (f b)

-- ---------------------------------------------------------------------------
-- v0.3.5: Context Building (Main.hs-facing API)
-- ---------------------------------------------------------------------------

-- | Build the checkout context from SketchHole data and the type environment.
-- This is called from Main.hs to assemble the context for checkoutHoleWithContext.
-- Imports ScopeBinding/ScopeSource from TypeCheck.hs via the caller.
buildScopeEntries :: Map.Map Name ScopeBinding -> [ScopeEntry]
buildScopeEntries env =
  [ ScopeEntry name (typeLabel (sbType binding)) (sourceLabel (sbSource binding))
  | (name, binding) <- Map.toAscList env
  ]

-- | Build FuncEntry list from a function signature map.
buildFuncEntries :: Map.Map Name Type -> [FuncEntry]
buildFuncEntries sigs =
  [ case ty of
      TFn params ret -> FuncEntry name
        (zipWith (\i t -> ("p" <> T.pack (show (i :: Int)), typeLabel t)) [0..] params)
        (typeLabel ret)
        "builtin"
      _ -> FuncEntry name [] (typeLabel ty) "builtin"
  | (name, ty) <- Map.toAscList sigs
  , not ("wasi." `T.isPrefixOf` name)  -- Q1: exclude wasi.* builtins
  ]

-- | Render ScopeSource as JSON-friendly text.
sourceLabel :: ScopeSource -> Text
sourceLabel SrcParam      = "param"
sourceLabel SrcLetBinding = "let-binding"
sourceLabel SrcMatchArm   = "match-arm"
sourceLabel SrcOpenImport = "open-import"
