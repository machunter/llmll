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
  , CheckoutContext(..)   -- v0.10 OBLIG-1
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
  -- R5: divergence sessions (checkout --multi N) — isolated scratch copies
  , DivergenceSession(..)
  , DivergenceMember(..)
  , MultiCheckoutResult(..)
  , checkoutHoleMulti
  , divergeSessionPath
  , loadSessions
  , saveSessions
  , expireStaleSessions
  , sessionMembers
  , scratchPathFor
  , promoteDivergenceWinner
  , emptyCheckoutContext
  -- v0.3.5 C4-C6: Context building utilities
  , collectTypeDefinitions
  , monomorphizeFunctions
  , truncateScope
  , buildScopeEntries
  , assembleAssumptions  -- OBLIG-1: the brief's 'assumptions' field (v1 params / v2a let-defs / v2b match hyps)
  , buildFuncEntries
  , buildCheckoutFuncs   -- HOLE-STATUS: the brief's available_functions list
  , sourceLabel
  ) where

import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), withObject, (.:), (.:?), (.!=), (.=), object)
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
import System.Directory (doesFileExist, copyFile, removeFile)
import System.FilePath (replaceExtension, takeExtension)
import System.Random (randomRIO)
import Data.List (isSuffixOf)
import Data.Maybe (mapMaybe)

import LLMLL.JsonPointer (resolvePointer, isHoleNode, findDescendantHoles)
import LLMLL.Diagnostic (Diagnostic(..), Severity(..))
import LLMLL.Syntax (Span(..), Type(..), Expr(..), Name, typeLabel, Statement, ModuleCache, Contract(..), normalizeDefStmt)
import LLMLL.TypeCheck (ScopeBinding(..), ScopeSource(..))
import LLMLL.TrustReport (TrustEntry)
import LLMLL.ObligationAssembly (trustLabel, importedContractedFns, exprToSExpr, substExpr)
import LLMLL.ObligationMining (isQfLia)
import LLMLL.HubQuery (QueryResult(..))

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
-- DEMO-COMP (§3.2): additive pre/post/tier so the contracted-user vocabulary
-- carries the contract an agent must discharge and may assume. All three are
-- 'Maybe Text': 'fePre'/'fePost' are 'Nothing' for an absent clause (a pre-free
-- callee → 'pre: null'); 'feTier' is 'Nothing' for builtins (no trust tier).
data FuncEntry = FuncEntry
  { feName   :: Text           -- ^ function name
  , feParams :: [(Text, Text)] -- ^ [(paramName, typeName)]
  , feReturn :: Text           -- ^ return type label
  , feStatus :: Text           -- ^ "filled" | "hole" | "builtin" | "imported" (XMOD-SCOPE-BRIEF)
  , fePre    :: Maybe Text     -- ^ DEMO-COMP: precondition (rendered), null if pre-free
  , fePost   :: Maybe Text     -- ^ DEMO-COMP: postcondition (rendered), null if absent
  , feTier   :: Maybe Text     -- ^ DEMO-COMP: effective trust tier, null for builtins
  } deriving (Show, Eq, Generic)

instance ToJSON FuncEntry where
  toJSON fe = object $
    [ "name"        .= feName fe
    , "params"      .= map (\(n, t) -> object ["name" .= n, "type" .= t]) (feParams fe)
    , "returns"     .= feReturn fe
    , "return_type" .= feReturn fe   -- DEMO-COMP §3.2: alias of returns
    , "status"      .= feStatus fe
    -- DEMO-COMP: emitted unconditionally as null when absent (additive; agents
    -- read pre/post/tier directly off the contracted-vocabulary entry).
    , "pre"         .= fePre fe
    , "post"        .= fePost fe
    , "tier"        .= feTier fe
    ]

instance FromJSON FuncEntry where
  parseJSON = withObject "FuncEntry" $ \o ->
    FuncEntry <$> o .: "name"
              <*> (o .: "params" >>= mapM parseParam)
              <*> o .: "returns" <*> o .: "status"
              <*> o .:? "pre" <*> o .:? "post" <*> o .:? "tier"
    where
      -- ToJSON renders each param as {"name":..,"type":..}; decode that shape
      -- (the default [(Text,Text)] decoder expects a 2-element array and would
      -- fail the additive round-trip, e.g. DEMO-COMP DC-4).
      parseParam = withObject "FuncEntry.param" $ \p ->
        (,) <$> p .: "name" <*> p .: "type"

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
    -- Constructors are serialized by the ToJSON above as objects {name, payload?}.
    -- Parse them back with a matching object parser; the default instance for
    -- [(Text, Maybe Text)] expects 2-element arrays, so relying on it silently
    -- breaks the checkout-lock round-trip for any program with a sum type in scope
    -- (loadLock returns Nothing -> every patch fails "invalid or expired token").
    mCtors <- o .:? "constructors"
    cs <- traverse (mapM parseCtorEntry) mCtors
    bt <- o .:? "base_type"
    rec_ <- o .:? "recursive"
    pure TypeDefEntry
      { tdName = n, tdKind = k, tdConstructors = cs
      , tdBaseType = bt, tdRecursive = maybe False id rec_ }
    where
      parseCtorEntry = withObject "constructor" $ \c ->
        (,) <$> c .: "name" <*> c .:? "payload"

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
  -- v0.6.1: Hub query integration (HUB-3)
  , ctHubSuggestions    :: Maybe [QueryResult]     -- ^ matching hub functions
  -- v0.10 OBLIG-1: Obligation context fields (spec §5.1, §5.3)
  , ctContractPre       :: Maybe Text             -- ^ pre clause from enclosing function
  , ctPostconditionGoal :: Maybe Text             -- ^ post clause (the "goal")
  , ctPathCondition     :: Maybe [Text]           -- ^ path conditions from contract pre
  , ctAssumptions       :: Maybe [Text]           -- ^ assumption kind labels from trust entry
  , ctObligationId      :: Maybe Text             -- ^ obligation ID (fingerprint, spec §3)
  , ctSourceHash        :: Maybe Text             -- ^ SHA-256 of source file at checkout
  , ctVerifiedHash      :: Maybe Text             -- ^ SHA-256 of .verified.json sidecar
  -- DEMO-COMP (§3.1, §3): discharged callee postconditions consumed as available
  -- hypotheses — a SEPARATE channel from 'ctAssumptions' (TCB escape hatches).
  -- 'ctAssumptions' is left unchanged (engineer F3: no breaking type change).
  , ctConsumedGuarantees :: Maybe [Value]         -- ^ DEMO-COMP: consumed callee guarantees
  } deriving (Show, Eq, Generic)

-- | v0.10 OBLIG-1: Bundled context parameter for checkoutHoleWithContext.
-- Replaces the 4+ positional Maybe arguments (Language Team Correction 3).
data CheckoutContext = CheckoutContext
  { ccScope           :: Maybe [ScopeEntry]
  , ccExpectedReturn  :: Maybe Text
  , ccFunctions       :: Maybe [FuncEntry]
  , ccTypeDefs        :: Maybe [TypeDefEntry]
  -- v0.10 additions:
  , ccContractPre     :: Maybe Text
  , ccPostGoal        :: Maybe Text
  , ccPathCondition   :: Maybe [Text]
  , ccAssumptions     :: Maybe [Text]
  , ccObligationId    :: Maybe Text
  , ccSourceHash      :: Maybe Text
  , ccVerifiedHash    :: Maybe Text
  -- DEMO-COMP (§3): consumed callee guarantees (separate channel from ccAssumptions)
  , ccConsumedGuarantees :: Maybe [Value]
  } deriving (Show, Eq)

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
    ["scope_truncated" .= True | ctScopeTruncated ct] ++
    maybe [] (\hs -> ["hub_suggestions" .= map hubSugToJson hs]) (ctHubSuggestions ct) ++
    -- v0.10 OBLIG-1: obligation context fields (emitted unconditionally as null when absent)
    [ "contract_pre"        .= ctContractPre ct
    , "postcondition_goal"  .= ctPostconditionGoal ct
    , "path_condition"      .= ctPathCondition ct
    , "assumptions"         .= ctAssumptions ct
    , "obligation_id"       .= ctObligationId ct
    , "source_hash"         .= ctSourceHash ct
    , "verified_hash"       .= ctVerifiedHash ct
    -- DEMO-COMP (§3): consumed_guarantees channel (separate from assumptions),
    -- and brief_version (the brief was previously unversioned — engineer F4).
    , "consumed_guarantees" .= ctConsumedGuarantees ct
    , "brief_version"       .= briefVersion
    ]

-- | DEMO-COMP (§3, engineer F4): schema version for the checkout brief
-- (CheckoutToken JSON). Previously unversioned. Bumped additively whenever the
-- brief surface gains fields.
-- XMOD-SCOPE-BRIEF: 0.12.1 → 0.12.2 (additive: "imported" status value on
-- available_functions entries; imported names in in_scope / available_functions).
briefVersion :: Text
briefVersion = "0.12.2"

hubSugToJson :: QueryResult -> Value
hubSugToJson qr = object
  [ "module"       .= qrModulePath qr
  , "function"     .= qrFuncName qr
  , "signature"    .= qrSignature qr
  , "has_contract" .= qrHasContract qr
  ]

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
    -- v0.10 OBLIG-1: all new fields use (.:?) for backward compat (Correction 4)
    contractPre_ <- o .:? "contract_pre"
    postGoal_ <- o .:? "postcondition_goal"
    pathCond_ <- o .:? "path_condition"
    assumptions_ <- o .:? "assumptions"
    obligId_ <- o .:? "obligation_id"
    srcHash_ <- o .:? "source_hash"
    verHash_ <- o .:? "verified_hash"
    consumed_ <- o .:? "consumed_guarantees"  -- DEMO-COMP (additive, backward-compat)
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
      , ctHubSuggestions    = Nothing  -- populated at checkout time, not deserialization
      , ctContractPre       = contractPre_
      , ctPostconditionGoal = postGoal_
      , ctPathCondition     = pathCond_
      , ctAssumptions       = assumptions_
      , ctObligationId      = obligId_
      , ctSourceHash        = srcHash_
      , ctVerifiedHash      = verHash_
      , ctConsumedGuarantees = consumed_
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
  checkoutHoleWithContext fp astVal pointer emptyCheckoutContext

-- | v0.10 OBLIG-1: Default empty context (all fields Nothing).
emptyCheckoutContext :: CheckoutContext
emptyCheckoutContext = CheckoutContext
  { ccScope = Nothing, ccExpectedReturn = Nothing
  , ccFunctions = Nothing, ccTypeDefs = Nothing
  , ccContractPre = Nothing, ccPostGoal = Nothing
  , ccPathCondition = Nothing, ccAssumptions = Nothing
  , ccObligationId = Nothing, ccSourceHash = Nothing
  , ccVerifiedHash = Nothing
  , ccConsumedGuarantees = Nothing
  }

-- | v0.3.5 (Phase C) / v0.10 (OBLIG-1): Context-aware checkout.
-- Accepts a CheckoutContext record (refactored from positional args per Correction 3).
checkoutHoleWithContext
  :: FilePath
  -> Value               -- ^ JSON-AST
  -> Text                -- ^ pointer (user-supplied, will be normalized)
  -> CheckoutContext     -- ^ bundled context (v0.10: replaces 4+ Maybe args)
  -> IO (Either Diagnostic CheckoutToken)
checkoutHoleWithContext fp astVal rawPointer ctx = do
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

          -- 5. Check for existing lock on this pointer. An exclusive checkout is
          -- refused both by another exclusive token AND by an open R5 divergence
          -- session on the same pointer (the two mechanisms are mutually
          -- exclusive on a pointer: a session must be torn down / promoted before
          -- an exclusive checkout can proceed).
          sessions0 <- loadSessions fp
          let sessions   = expireStaleSessions now sessions0
              sessConflict = any (\ds -> dsPointer ds == pointer) sessions
              conflict = filter (\ct -> ctPointer ct == pointer) (lockTokens cleanLock)
          case (conflict, sessConflict) of
            (_, True) -> pure $ Left $ mkDiag fp $
              "hole at " <> pointer <> " has an open divergence session; "
              <> "promote a winner or tear it down before an exclusive checkout"
            ((_:_), _) -> pure $ Left $ mkDiag fp $
              "hole at " <> pointer <> " is already checked out"
            ([], False) -> do
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
                    , ctInScope           = ccScope ctx
                    , ctExpectedReturn    = ccExpectedReturn ctx
                    , ctAvailableFunctions = ccFunctions ctx
                    , ctTypeDefinitions   = ccTypeDefs ctx
                    , ctScopeTruncated    = False  -- C6 will set this
                    , ctHubSuggestions    = Nothing  -- HUB-3: populated by caller
                    -- v0.10 OBLIG-1: obligation context
                    , ctContractPre       = ccContractPre ctx
                    , ctPostconditionGoal = ccPostGoal ctx
                    , ctPathCondition     = ccPathCondition ctx
                    , ctAssumptions       = ccAssumptions ctx
                    , ctObligationId      = ccObligationId ctx
                    , ctSourceHash        = ccSourceHash ctx
                    , ctVerifiedHash      = ccVerifiedHash ctx
                    , ctConsumedGuarantees = ccConsumedGuarantees ctx
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
-- R5: Divergence sessions (checkout --multi N)
-- ---------------------------------------------------------------------------
--
-- The exclusive checkout lock refuses a second token on a pointer. A divergence
-- session RELAXES that for one pointer: up to N concurrent tokens, EACH bound
-- to its own isolated SCRATCH COPY of the source. The isolation invariant is
-- non-negotiable — multi-fills write only to their scratch copy (and its own
-- scratch lock, so the standard `patch` flow works against it), never to the
-- shared tree. The shared file is overwritten only by an explicit
-- 'promoteDivergenceWinner'.
--
-- Session state lives in its OWN sidecar (@.llmll-diverge.json@), disjoint from
-- the exclusive @.llmll-lock.json@, so neither mechanism perturbs the other's
-- schema. Exclusivity across the two is enforced at both entry points:
-- 'checkoutHoleWithContext' refuses a pointer with an open session, and
-- 'checkoutHoleMulti' refuses a pointer already held by an exclusive token.

-- | One participant in a divergence session: its bearer token and the isolated
-- scratch copy it edits.
data DivergenceMember = DivergenceMember
  { dmToken   :: Text      -- ^ bearer token (also the scratch's own lock token)
  , dmScratch :: FilePath  -- ^ isolated scratch copy path
  , dmCreated :: UTCTime   -- ^ creation time (for stale-session expiry)
  } deriving (Show, Eq, Generic)

instance ToJSON DivergenceMember where
  toJSON dm = object
    [ "token"   .= dmToken dm
    , "scratch" .= dmScratch dm
    , "created" .= dmCreated dm
    ]

instance FromJSON DivergenceMember where
  parseJSON = withObject "DivergenceMember" $ \o ->
    DivergenceMember <$> o .: "token" <*> o .: "scratch" <*> o .: "created"

-- | A divergence session: N concurrent scratch-isolated tokens on ONE pointer.
data DivergenceSession = DivergenceSession
  { dsSession  :: Text               -- ^ session id
  , dsPointer  :: Text               -- ^ the shared hole pointer
  , dsCapacity :: Int                -- ^ N — max concurrent members
  , dsTTL      :: NominalDiffTime    -- ^ session duration (default 3600s)
  , dsMembers  :: [DivergenceMember] -- ^ live participants
  } deriving (Show, Eq, Generic)

instance ToJSON DivergenceSession where
  toJSON ds = object
    [ "session"  .= dsSession ds
    , "pointer"  .= dsPointer ds
    , "capacity" .= dsCapacity ds
    , "ttl"      .= (round (dsTTL ds) :: Int)
    , "members"  .= dsMembers ds
    ]

instance FromJSON DivergenceSession where
  parseJSON = withObject "DivergenceSession" $ \o -> do
    s   <- o .: "session"
    p   <- o .: "pointer"
    cap <- o .: "capacity"
    ttl <- o .:? "ttl" .!= (3600 :: Int)
    ms  <- o .: "members"
    pure DivergenceSession
      { dsSession = s, dsPointer = p, dsCapacity = cap
      , dsTTL = fromIntegral ttl, dsMembers = ms }

-- | The result of a successful @checkout --multi@: the bearer token, the
-- session it joined, the isolated scratch copy to edit, and the slot occupancy.
data MultiCheckoutResult = MultiCheckoutResult
  { mcToken    :: CheckoutToken  -- ^ bearer token (also the scratch's lock token)
  , mcSession  :: Text           -- ^ session id
  , mcScratch  :: FilePath       -- ^ isolated scratch copy to patch/fill
  , mcSlot     :: Int            -- ^ 1-based slot occupied
  , mcCapacity :: Int            -- ^ session capacity N
  } deriving (Show, Eq, Generic)

instance ToJSON MultiCheckoutResult where
  toJSON mc = object
    [ "token"          .= mcToken mc
    , "session"        .= mcSession mc
    , "scratch"        .= mcScratch mc
    , "slot"           .= mcSlot mc
    , "capacity"       .= mcCapacity mc
    -- The scratch copy is the ONLY file this token may edit; the shared tree is
    -- untouched until a winner is promoted (isolation invariant).
    , "isolated_scratch" .= True
    ]

-- | Session sidecar path (disjoint from the exclusive lock file).
-- @program.ast.json → program.llmll-diverge.json@.
divergeSessionPath :: FilePath -> FilePath
divergeSessionPath fp
  | ".ast.json" `isSuffixOf` fp = take (length fp - 9) fp ++ ".llmll-diverge.json"
  | otherwise                   = replaceExtension fp ".llmll-diverge.json"

-- | Load the divergence-session sidecar (empty when absent / unparseable).
loadSessions :: FilePath -> IO [DivergenceSession]
loadSessions fp = do
  let sp = divergeSessionPath fp
  exists <- doesFileExist sp
  if exists
    then maybe [] id <$> A.decodeFileStrict sp
    else pure []

-- | Persist the divergence-session sidecar.
saveSessions :: FilePath -> [DivergenceSession] -> IO ()
saveSessions fp sessions = BL.writeFile (divergeSessionPath fp) (A.encode sessions)

-- | Drop members older than their session TTL; drop sessions left empty.
expireStaleSessions :: UTCTime -> [DivergenceSession] -> [DivergenceSession]
expireStaleSessions now = filter (not . null . dsMembers) . map dropStale
  where
    dropStale ds = ds { dsMembers = filter (live ds) (dsMembers ds) }
    live ds dm = diffUTCTime now (dmCreated dm) <= dsTTL ds

-- | Members of a named session (stale members filtered against the clock).
sessionMembers :: FilePath -> Text -> IO [DivergenceMember]
sessionMembers fp session = do
  now <- getCurrentTime
  sessions <- expireStaleSessions now <$> loadSessions fp
  pure $ case filter ((== session) . dsSession) sessions of
    (ds:_) -> dsMembers ds
    []     -> []

-- | Derive an isolated scratch-copy path for a (session, token) pair.
-- @program.ast.json → program.<sess8>-<tok8>.scratch.ast.json@.
scratchPathFor :: FilePath -> Text -> Text -> FilePath
scratchPathFor fp session tok =
  let tag = T.unpack (T.take 8 session <> "-" <> T.take 8 tok)
  in if ".ast.json" `isSuffixOf` fp
       then take (length fp - 9) fp ++ "." ++ tag ++ ".scratch.ast.json"
       else replaceExtension fp (tag ++ ".scratch.json")

-- | Open or join a divergence session on a pointer, allocating an isolated
-- scratch copy for a fresh token. Never writes the shared source file.
checkoutHoleMulti
  :: FilePath
  -> Value            -- ^ JSON-AST (used only for hole validation)
  -> Text             -- ^ pointer (user-supplied, will be normalized)
  -> Int              -- ^ N — session capacity (must be ≥ 2)
  -> CheckoutContext  -- ^ bundled context (same brief as an exclusive checkout)
  -> IO (Either Diagnostic MultiCheckoutResult)
checkoutHoleMulti fp astVal rawPointer n ctx
  | n < 2 = pure $ Left $ mkDiag fp $
      "checkout --multi N requires N >= 2 (a divergence session needs at least "
      <> "two concurrent fills); use a plain checkout for exclusive editing"
  | otherwise = do
      let pointer = normalizePointer rawPointer
      case resolvePointer pointer astVal of
        Nothing -> pure $ Left $ mkDiag fp $
          "pointer " <> pointer <> " does not resolve to any node in the JSON-AST"
        Just node
          | not (isHoleNode node) -> do
              let hints = findDescendantHoles pointer astVal
                  hintMsg = case hints of { [] -> ""; (h:_) -> "; did you mean " <> h <> "?" }
              pure $ Left $ mkDiag fp $
                "pointer " <> pointer <> " does not target a hole node" <> hintMsg
          | otherwise -> do
              now <- getCurrentTime
              -- Exclusive-lock conflict: refuse if an exclusive token holds the pointer.
              mLock <- loadLock fp
              let cleanLock = expireStale now (maybe (CheckoutLock fp []) id mLock)
                  exclusiveHolds = any (\ct -> ctPointer ct == pointer) (lockTokens cleanLock)
              sessions0 <- loadSessions fp
              let sessions = expireStaleSessions now sessions0
                  holeKind = case node of
                    Object o -> case KM.lookup "kind" o of
                      Just (String k) -> k
                      _               -> "hole-unknown"
                    _ -> "hole-unknown"
              if exclusiveHolds
                then pure $ Left $ mkDiag fp $
                  "hole at " <> pointer <> " is held by an exclusive checkout; "
                  <> "release it before opening a divergence session"
                else case filter ((== pointer) . dsPointer) sessions of
                  (existing:_)
                    | length (dsMembers existing) >= dsCapacity existing ->
                        pure $ Left $ mkDiag fp $
                          "divergence session " <> dsSession existing <> " on " <> pointer
                          <> " is full (" <> T.pack (show (dsCapacity existing)) <> " tokens)"
                    | otherwise ->
                        joinSession fp astVal pointer holeKind now ctx sessions existing
                  [] -> do
                    sid <- generateCheckoutToken
                    let fresh = DivergenceSession
                          { dsSession  = "sess-" <> T.take 12 sid
                          , dsPointer  = pointer
                          , dsCapacity = n
                          , dsTTL      = 3600
                          , dsMembers  = []
                          }
                    joinSession fp astVal pointer holeKind now ctx sessions fresh

-- | Allocate a token + isolated scratch copy and add it to (a possibly new)
-- session. Writes the scratch copy, its own scratch lock, and the session
-- sidecar — but never the shared source file.
joinSession
  :: FilePath -> Value -> Text -> Text -> UTCTime -> CheckoutContext
  -> [DivergenceSession] -> DivergenceSession
  -> IO (Either Diagnostic MultiCheckoutResult)
joinSession fp _astVal pointer holeKind now ctx allSessions session = do
  tok <- generateCheckoutToken
  let scratch = scratchPathFor fp (dsSession session) tok
      -- The token that patches the scratch. Staleness hashes are Nothing so the
      -- standard `patch` flow (PatchApply.checkStaleness) does not gate on the
      -- shared file's hash — the scratch is a self-contained edit surface.
      ct = CheckoutToken
        { ctPointer   = pointer
        , ctHoleKind  = holeKind
        , ctExpected  = Nothing
        , ctTimestamp = now
        , ctToken     = tok
        , ctTTL       = dsTTL session
        , ctInScope           = ccScope ctx
        , ctExpectedReturn    = ccExpectedReturn ctx
        , ctAvailableFunctions = ccFunctions ctx
        , ctTypeDefinitions   = ccTypeDefs ctx
        , ctScopeTruncated    = False
        , ctHubSuggestions    = Nothing
        , ctContractPre       = ccContractPre ctx
        , ctPostconditionGoal = ccPostGoal ctx
        , ctPathCondition     = ccPathCondition ctx
        , ctAssumptions       = ccAssumptions ctx
        , ctObligationId      = ccObligationId ctx
        , ctSourceHash        = Nothing
        , ctVerifiedHash      = Nothing
        , ctConsumedGuarantees = ccConsumedGuarantees ctx
        }
      member = DivergenceMember { dmToken = tok, dmScratch = scratch, dmCreated = now }
      session' = session { dsMembers = dsMembers session ++ [member] }
      others   = filter ((/= dsSession session) . dsSession) allSessions
  -- Isolated scratch copy = byte-for-byte snapshot of the shared source.
  copyFile fp scratch
  -- Per-scratch lock so `llmll patch <scratch>` authenticates with this token.
  saveLock scratch (CheckoutLock scratch [ct])
  -- Persist the session sidecar (NOT the shared exclusive lock).
  saveSessions fp (others ++ [session'])
  pure $ Right MultiCheckoutResult
    { mcToken    = ct
    , mcSession  = dsSession session
    , mcScratch  = scratch
    , mcSlot     = length (dsMembers session')
    , mcCapacity = dsCapacity session
    }

-- | Explicitly promote one member's scratch copy to the shared source — the
-- ONLY sanctioned write of a multi-fill back into the shared tree. Copies the
-- winning scratch over the shared file, then tears the whole session down
-- (removing every scratch copy + its scratch lock + the session record).
promoteDivergenceWinner :: FilePath -> Text -> Text -> IO (Either Diagnostic ())
promoteDivergenceWinner fp session winnerTok = do
  sessions <- loadSessions fp
  case filter ((== session) . dsSession) sessions of
    [] -> pure $ Left $ mkDiag fp $ "no divergence session " <> session
    (ds:_) -> case filter ((== winnerTok) . dmToken) (dsMembers ds) of
      [] -> pure $ Left $ mkDiag fp $
        "token " <> winnerTok <> " is not a member of session " <> session
      (winner:_) -> do
        -- Promote the winner into the shared tree.
        copyFile (dmScratch winner) fp
        -- Tear the session down: remove every scratch copy + its scratch lock.
        mapM_ (safeRemove . dmScratch) (dsMembers ds)
        mapM_ (safeRemove . lockFilePath . dmScratch) (dsMembers ds)
        saveSessions fp (filter ((/= session) . dsSession) sessions)
        pure $ Right ()
  where
    safeRemove path = do
      exists <- doesFileExist path
      if exists then removeFile path else pure ()

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

-- | OBLIG-1 (assumptions wire): surface the local hypothesis context as the
-- checkout brief's @assumptions@, in three provinces.
--
-- (v1) For each in-scope refinement-typed PARAM binder @(name, ty)@ whose type
-- resolves — directly, or through a type alias — to @TDependent x0 _ phi@, emit
-- @phi@ with the bound variable @x0@ α-renamed to the binder's actual @name@ (so
-- @amount: (where [v:int] (> v 0))@ contributes @(> amount 0)@). The @SrcParam@
-- filter is not cosmetic: @shEnv@ also carries the enclosing function's own name
-- and every in-scope type-alias name as @SrcLetBinding@ entries, and a type-alias
-- name (e.g. @Pos@, bound to @TCustom "Pos"@) would otherwise unfold to a bogus
-- @(> Pos 0)@ over a type, not a value.
--
-- (v2a) For each in-scope let-binding with a QF-LIA RHS, emit the definitional
-- equality @(= name rhs)@ (the RHS carried on @sbDef@).
--
-- (v2b) The match-scrutinee case hypotheses on the hole's path (@shHyps@,
-- outermost match first): a hole under @((Ctor x) …)@ carries @(= s (Ctor x))@;
-- a nullary arm carries @(= s Ctor)@ (bare, as nullary ctors appear in contract
-- position). Captured at sketch time by the arm traversal ('matchHypothesis'),
-- so nested and sequential matches accumulate per-path; a hypothesis whose
-- names are later shadowed is dropped at capture (the 'withTaggedEnv' guard).
-- Still out of scope: @def-invariant@ axioms (deferred pending provenance
-- tagging as an unverified TCB axiom).
--
-- Sourcing exclusively from the checked-out hole's own sketch snapshot (@shEnv@,
-- @shHyps@) keeps the field path-correct by construction: out-of-scope /
-- sibling-branch binders and sibling-arm hypotheses never appear. The alias map
-- is same-file ('buildAliasMap'); imported aliases that never unfold locally
-- contribute nothing.
assembleAssumptions :: Map.Map Name Type -> Map.Map Name ScopeBinding -> [Expr] -> [Text]
assembleAssumptions aliasMap env hyps =
  -- (v1) refinement predicates of refinement-typed PARAMS.
  [ exprToSExpr (substExpr (Map.singleton x0 (EVar name)) phi)
  | (name, binding) <- Map.toAscList env
  , sbSource binding == SrcParam
  , Just (x0, phi)  <- [resolveRefinement aliasMap (sbType binding)]
  ]
  ++
  -- (v2a) definitional equalities of in-scope let-bindings with a QF-LIA RHS.
  -- A let-binding appears in the hole's shEnv iff the hole is inside its body, so
  -- @(= y e)@ genuinely holds at the hole (the body VC assumes it, FixpointEmit).
  -- The @isQfLia@ filter keeps the field QF-LIA (a call/opaque RHS is skipped)
  -- and, since only real let-bindings carry an @sbDef@, it also excludes the
  -- type-alias-name and enclosing-fn-name leaks that ride the SrcLetBinding tag.
  [ exprToSExpr (EApp "=" [EVar name, rhs])
  | (name, binding) <- Map.toAscList env
  , sbSource binding == SrcLetBinding
  , Just rhs        <- [sbDef binding]
  , isQfLia rhs
  ]
  ++
  -- (v2b) match-scrutinee case hypotheses, already path-filtered and
  -- shadow-guarded at sketch capture — render in path order (outermost first).
  map exprToSExpr hyps

-- | Resolve a binder's type to its refinement predicate, if any. A direct
-- @TDependent@ is used as-is; a @TCustom n@ is unfolded through the alias map
-- (bounded, to tolerate a short chain of aliases) until it reaches a
-- @TDependent@ or a non-alias. A type that never reaches a @TDependent@
-- contributes no assumption. Returns the bound variable and the predicate.
resolveRefinement :: Map.Map Name Type -> Type -> Maybe (Name, Expr)
resolveRefinement aliasMap = go (8 :: Int)
  where
    go _ (TDependent x0 _ phi) = Just (x0, phi)
    go n (TCustom c) | n > 0   = Map.lookup c aliasMap >>= go (n - 1)
    go _ _                     = Nothing

-- | Build FuncEntry list from a function signature map.
buildFuncEntries :: Map.Map Name Type -> [FuncEntry]
buildFuncEntries sigs =
  -- Builtins carry no contract and no trust tier: pre/post/tier = Nothing.
  [ case ty of
      TFn params ret -> FuncEntry name
        (zipWith (\i t -> ("p" <> T.pack (show (i :: Int)), typeLabel t)) [0..] params)
        (typeLabel ret)
        "builtin" Nothing Nothing Nothing
      _ -> FuncEntry name [] (typeLabel ty) "builtin" Nothing Nothing Nothing
  | (name, ty) <- Map.toAscList sigs
  , not ("wasi." `T.isPrefixOf` name)  -- Q1: exclude wasi.* builtins
  ]

-- | The brief's available_functions list (extracted from Main for testability).
-- Same-file contracted functions, then imported exported contracted functions
-- (XMOD-SCOPE-BRIEF, named as the entry module calls them, status "imported").
--
-- HOLE-STATUS: the function whose hole is being checked out (mEnclosing) gets
-- status "hole", not "filled" — presenting it as an available filled function
-- invites a degenerate self-call fill, which type-checks and verifies SAFE at
-- partial correctness (the nonterminating body discharges its own contract
-- vacuously). Observed live: a blind fill agent answered the alert-admit brief
-- with (alert-admit latched sev). "hole" is the documented-but-never-emitted
-- third enum value of 'feStatus'.
buildCheckoutFuncs
  :: [Statement] -> ModuleCache -> Map.Map Name TrustEntry -> Maybe Name -> [FuncEntry]
buildCheckoutFuncs stmts cache trustMap mEnclosing =
  [ FuncEntry
      { feName   = fname
      , feParams = map (\(n,t) -> (n, typeLabel t)) ps
      , feReturn = maybe "?" typeLabel mRet
      , feStatus = if Just fname == mEnclosing then "hole" else "filled"
      , fePre    = fmap exprToSExpr (contractPre c)
      , fePost   = fmap exprToSExpr (contractPost c)
      , feTier   = Just (trustLabel trustMap fname)
      }
  | stmt <- stmts
  , Just (fname, ps, mRet, c, _) <- [normalizeDefStmt stmt]
  , contractPre c /= Nothing || contractPost c /= Nothing
  ]
  ++
  [ FuncEntry
      { feName   = dname
      , feParams = map (\(n,t) -> (n, typeLabel t)) ps
      , feReturn = maybe "?" typeLabel mRet
      , feStatus = "imported"
      , fePre    = fmap exprToSExpr (contractPre c)
      , fePost   = fmap exprToSExpr (contractPost c)
      , feTier   = Just (trustLabel trustMap dname)
      }
  | (dname, ps, mRet, c) <- importedContractedFns stmts cache
  ]

-- | Render ScopeSource as JSON-friendly text.
sourceLabel :: ScopeSource -> Text
sourceLabel SrcParam      = "param"
sourceLabel SrcLetBinding = "let-binding"
sourceLabel SrcMatchArm   = "match-arm"
sourceLabel SrcOpenImport = "open-import"
