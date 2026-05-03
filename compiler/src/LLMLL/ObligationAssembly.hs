-- |
-- Module      : LLMLL.ObligationAssembly
-- Description : v0.10 OBLIG-2: Structured obligation report assembly.
--
-- Assembles obligation reports from existing compiler outputs (hole analysis,
-- verification results, trust reports, constraint tables) per OBLIG-0 spec §2.
-- This module performs no new analysis — it re-exports existing data in the
-- unified obligation report JSON schema.
module LLMLL.ObligationAssembly
  ( -- * Data types
    ObligationKind(..)
  , PathEntry(..)
  , ObligationObj(..)
  , TypeChannel(..)
  , ContractChannel(..)
  , TrustChannel(..)
  , ObligationReport(..)
  , ReportSummary(..)
    -- * Helpers
  , exprToSExpr
  , deriveBacking
  , classifyGuard
  , collectHoleGuards
  , classifyContractFragment
  , classifyBodyFragment
  , normalizeForFingerprint
  , obligationStatus
  , recursiveNames
    -- * Assembly
  , assembleReport
  , encodeReport
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Maybe (fromMaybe, isJust, mapMaybe, catMaybes)
import Data.List (foldl', sortOn, nub)
import Data.Aeson (Value(..), object, (.=), encode, ToJSON(..))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE
import Crypto.Hash.SHA256 (hash)
import Numeric (showHex)
import Data.Word (Word8)
import Control.Monad.State.Strict (evalState)
import Data.Graph (stronglyConnComp, SCC(..))

import LLMLL.Syntax
import LLMLL.FixpointIR (FQSort(..))
import LLMLL.FixpointEmit
  ( EmitResult(..), ContractEnv, SortEnv
  , buildAliasMap, buildSortEnv, buildContractEnv, isIntLike, AliasMap )
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable, FQVerifyResult(..))
import LLMLL.TrustReport (TrustReport(..), TrustEntry(..))
import LLMLL.HoleAnalysis
  ( HoleReport(..), HoleEntry(..), HoleStatus(..)
  , holeEntries, analyzeHoles, buildCallGraph, enclosingFunc )
import LLMLL.GuardClassifier (classifyGuardM)

-- ---------------------------------------------------------------------------
-- Data types (spec §2.2–§2.5)
-- ---------------------------------------------------------------------------

-- | Obligation kinds (spec §2.3)
data ObligationKind
  = HoleObligation
  | ContractObligation
  | PreconditionObligation
  | TerminationObligation
  | BranchObligation
  deriving (Show, Eq)

kindLabel :: ObligationKind -> Text
kindLabel HoleObligation          = "hole-obligation"
kindLabel ContractObligation      = "contract-obligation"
kindLabel PreconditionObligation  = "precondition-obligation"
kindLabel TerminationObligation   = "termination-obligation"
kindLabel BranchObligation        = "branch-obligation"

-- | Path condition entry (spec §4.2.1)
data PathEntry = PathEntry
  { peGuard :: Text   -- ^ S-expression of guard
  , peKind  :: Text   -- ^ "qf_lia" | "structural"
  } deriving (Show, Eq)

-- | Type channel (spec §4.1)
data TypeChannel = TypeChannel
  { tcExpectedType :: Text
  , tcPolymorphic  :: Bool
  , tcInScope      :: [Value]  -- ScopeEntry JSON values
  } deriving (Show)

-- | Contract channel (spec §4.2)
data ContractChannel = ContractChannel
  { ccPreconditions   :: [Text]
  , ccPostGoal        :: Maybe Text
  , ccPathCondition   :: [PathEntry]
  , ccPathTruncated   :: Bool
  , ccContractFrag    :: Text
  , ccBodyFrag        :: Text
  , ccBodyFaithful    :: Bool
  } deriving (Show)

-- | Trust channel (spec §4.3)
data TrustChannel = TrustChannel
  { trAssumptions    :: [Value]
  , trEffectiveLevel :: Text
  , trBodyFaithful   :: Bool
  } deriving (Show)

-- | Single obligation object (spec §2.2)
data ObligationObj = ObligationObj
  { ooId              :: Text
  , ooOrigin          :: Text
  , ooKind            :: ObligationKind
  , ooBacking         :: Text
  , ooStatus          :: Text
  , ooFunction        :: Text
  , ooTypeChannel     :: Maybe TypeChannel
  , ooContractChannel :: Maybe ContractChannel
  , ooTrustChannel    :: Maybe TrustChannel
  , ooContractedFns   :: [Value]
  , ooAvailableFns    :: [Value]
  , ooSuggestions     :: [Value]
  } deriving (Show)

-- | Report summary (spec §2.1)
data ReportSummary = ReportSummary
  { rsTotal      :: Int
  , rsOpen       :: Int
  , rsDischarged :: Int
  , rsDeferred   :: Int
  , rsAsserted   :: Int
  } deriving (Show)

-- | Top-level obligation report (spec §2.1)
data ObligationReport = ObligationReport
  { orSchemaVersion :: Text
  , orSourceFile    :: Text
  , orCrossModule   :: Text
  , orObligations   :: [ObligationObj]
  , orSummary       :: ReportSummary
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Render an Expr as an S-expression (F4: new helper).
exprToSExpr :: Expr -> Text
exprToSExpr (EVar v)             = v
exprToSExpr (ELit (LitInt n))    = T.pack (show n)
exprToSExpr (ELit (LitFloat f))  = T.pack (show f)
exprToSExpr (ELit (LitBool b))   = if b then "true" else "false"
exprToSExpr (ELit (LitString s)) = "\"" <> s <> "\""
exprToSExpr (EApp op args)       = "(" <> op <> " " <> T.intercalate " " (map exprToSExpr args) <> ")"
exprToSExpr (EOp op args)        = exprToSExpr (EApp op args)
exprToSExpr (EHole (HNamed n))   = "?" <> n
exprToSExpr (EHole _)            = "?_"
exprToSExpr e                    = T.pack (show e)

-- | Derive obligation backing from ConstraintTable (spec §2.4).
deriveBacking :: ConstraintTable -> Name -> ObligationKind -> Text
deriveBacking table fnName kind
  | kind `elem` [HoleObligation, BranchObligation]
  = if hasClausePrefix table fnName "body-post" then "smt" else "guidance"
  | kind == ContractObligation
  = if hasClausePrefix table fnName "pre"
    || hasClausePrefix table fnName "post"
    || hasClausePrefix table fnName "body-post"
    then "smt" else "guidance"
  | kind == PreconditionObligation
  = if hasClausePrefix table fnName "call-pre" then "smt" else "guidance"
  | kind == TerminationObligation
  = if hasClausePrefix table fnName "decreases" then "smt" else "guidance"
  | otherwise = "guidance"

hasClausePrefix :: ConstraintTable -> Name -> Text -> Bool
hasClausePrefix table fn prefix =
  any (\origin -> coFunction origin == fn && prefix `T.isPrefixOf` coClause origin)
      (Map.elems table)

-- | Classify a guard expression as a PathEntry (spec §4.2.3).
classifyGuard :: Map Name Name -> SortEnv -> Expr -> PathEntry
classifyGuard env se guard =
  let mPred = evalState (classifyGuardM env se guard) 0
  in case mPred of
       Just _  -> PathEntry (exprToSExpr guard) "qf_lia"
       Nothing -> PathEntry (exprToSExpr guard) "structural"

-- | Collect path conditions for holes in an expression (spec §4.2.3).
-- F5: Uses total pattern match on bindings (no crash on non-PVar).
collectHoleGuards :: Map Name Name -> SortEnv -> Expr -> [(Name, [PathEntry])]
collectHoleGuards env0 se0 = go env0 se0 []
  where
    maxPathEntries = 16

    go _   _  acc (EHole (HNamed n)) = [(n, take maxPathEntries acc)]
    go _   _  acc (EHole _)          = [("_anon", take maxPathEntries acc)]
    go env se acc (EIf guard thenE elseE) =
      let entry    = classifyGuard env se guard
          negEntry = PathEntry ("(not " <> peGuard entry <> ")") (peKind entry)
      in go env se (acc ++ [entry]) thenE
         ++ go env se (acc ++ [negEntry]) elseE
    go env se acc (ELet binds body) =
      let (env', se') = foldl' (\(e, s) binding -> case binding of
            (PVar v, mTy, _rhs) -> case mTy of
              Just ty | isIntLikeSimple ty -> (Map.insert v v e, Map.insert v FQInt s)
              _       -> (Map.insert v v e, s)
            _ -> (e, s)
            ) (env, se) binds
      in concatMap (\(_, _, e) -> go env se acc e) binds
         ++ go env' se' acc body
    go env se acc (EMatch scrut arms) =
      concatMap (\(i, (pat, body)) ->
        let label = case pat of
              PConstructor c _ -> c
              PVar v           -> v
              PWildcard        -> "_"
              PLiteral _       -> "<lit>"
            entry = PathEntry ("(match-" <> label <> ")") "structural"
        in go env se (acc ++ [entry]) body
      ) (zip [(0::Int)..] arms)
    go env se acc (EApp _ args)    = concatMap (go env se acc) args
    go env se acc (EOp _ args)     = concatMap (go env se acc) args
    go env se acc (EPair a b)      = go env se acc a ++ go env se acc b
    go env se acc (EAwait e)       = go env se acc e
    go env se acc (ELambda _ b)    = go env se acc b
    go env se acc (EDo steps)      = concatMap (\(DoStep _ e) -> go env se acc e) steps
    go _   _  _   _                = []

    isIntLikeSimple TInt = True
    isIntLikeSimple _    = False

-- | Classify contract fragment (spec §4.2.2).
classifyContractFragment :: Contract -> Text
classifyContractFragment c
  | contractPre c == Nothing && contractPost c == Nothing = "absent"
  | otherwise =
      let preOk  = maybe True isQfLiaExpr (contractPre c)
          postOk = maybe True isQfLiaExpr (contractPost c)
      in if preOk && postOk then "qf_lia" else "non_qf_lia"

-- | Classify body fragment (spec §4.2.2).
-- F4: Takes recursive name set for "recursive" classification.
classifyBodyFragment :: Name -> Set Name -> [Text] -> [Text] -> Expr -> Text
classifyBodyFragment fnName recNames faithful fallback body
  | fnName `Set.member` recNames        = "recursive"
  | hasHole body                        = "hole_bearing"
  | fnName `elem` faithful              = "qf_lia"
  | fnName `elem` fallback              = "unsupported"
  | otherwise                           = "unsupported"

-- | Compute recursive function names via SCC (F4).
recursiveNames :: [Statement] -> Set Name
recursiveNames stmts =
  let cg = buildCallGraph stmts
      sccs = stronglyConnComp [(n, n, deps) | (n, deps) <- Map.toList cg]
  in Set.fromList [n | CyclicSCC ns <- sccs, n <- ns]

-- | Obligation ID with alpha-normalization (spec §3).
-- F7: Uses cryptohash-sha256.
normalizeForFingerprint :: Name -> [(Name, Type)] -> Maybe Expr -> Text -> Text
normalizeForFingerprint fnName params mPost channel =
  let paramSubst = Map.fromList $ zip (map fst params) ["$p" <> T.pack (show i) | i <- [0::Int ..]]
      normPost = fmap (alphaCanonExpr paramSubst) mPost
      input = T.intercalate ":" [fnName, channel, maybe "" exprToSExpr normPost]
      hashBytes = hash (TE.encodeUtf8 input)
      hexStr = concatMap (\b -> let h = showHex b "" in if length h == 1 then '0':h else h)
                         (BS.unpack (BS.take 6 hashBytes))
  in "oblig:" <> fnName <> ":" <> channel <> ":" <> T.pack hexStr

-- | Alpha-canonicalize an expression using a substitution map.
alphaCanonExpr :: Map Name Name -> Expr -> Expr
alphaCanonExpr subst (EVar v)       = EVar (Map.findWithDefault v v subst)
alphaCanonExpr subst (EApp op args) = EApp op (map (alphaCanonExpr subst) args)
alphaCanonExpr subst (EOp op args)  = EOp op (map (alphaCanonExpr subst) args)
alphaCanonExpr _     e              = e  -- literals, holes unchanged

-- | Determine obligation status (spec §2.5).
-- F5: Takes weakness-ok suppression set for "deferred" status.
obligationStatus :: Maybe FQVerifyResult -> Name -> ObligationKind -> ConstraintTable
                 -> Set Name -> Text
obligationStatus mFqResult fnName kind table suppressedSet
  | fnName `Set.member` suppressedSet = "deferred"
  | Nothing <- mFqResult              = "open"  -- F8: no solver
  | Just FQSafe <- mFqResult          = "discharged"
  | Just (FQUnsafe failedIds) <- mFqResult =
      let fnFailed = any (\cid -> case Map.lookup cid table of
            Just co -> coFunction co == fnName
            Nothing -> False) failedIds
      in if fnFailed then "open" else "discharged"
  | otherwise = "open"

-- | Check if an expression contains any holes.
hasHole :: Expr -> Bool
hasHole (EHole _)        = True
hasHole (EApp _ args)    = any hasHole args
hasHole (EOp _ args)     = any hasHole args
hasHole (EIf c t e)      = hasHole c || hasHole t || hasHole e
hasHole (ELet bs body)   = any (\(_, _, e) -> hasHole e) bs || hasHole body
hasHole (EMatch s arms)  = hasHole s || any (hasHole . snd) arms
hasHole (EPair a b)      = hasHole a || hasHole b
hasHole (EAwait e)       = hasHole e
hasHole (ELambda _ body) = hasHole body
hasHole (EDo steps)      = any (\(DoStep _ e) -> hasHole e) steps
hasHole _                = False

-- | Simple QF-LIA check for contract expressions.
isQfLiaExpr :: Expr -> Bool
isQfLiaExpr (EVar _)          = True
isQfLiaExpr (ELit (LitInt _)) = True
isQfLiaExpr (ELit (LitBool _))= True
isQfLiaExpr (EApp op args)
  | op `elem` [">=", "<=", ">", "<", "=", "==", "/=", "!=",
                "+", "-", "not", "and", "or", "≥", "≤", "≠"]
  = all isQfLiaExpr args
isQfLiaExpr _ = False

-- ---------------------------------------------------------------------------
-- Assembly (spec §2.1)
-- ---------------------------------------------------------------------------

-- | Top-level report assembly.
assembleReport :: FilePath -> [Statement] -> ModuleCache -> EmitResult
               -> Maybe FQVerifyResult -> TrustReport -> Text
assembleReport fp stmts _cache emitR mFqResult trustRpt =
  let table      = erConstraintTable emitR
      faithful   = erBodyFaithfulFns emitR
      fallback   = erBodyFallback emitR
      recNames   = recursiveNames stmts
      suppressed = Set.fromList (map fst (trSuppressions trustRpt))
      holeReport = analyzeHoles stmts

      -- Assemble hole obligations
      holeObls = assembleHoleObligations stmts table mFqResult trustRpt
                   faithful fallback recNames suppressed holeReport

      -- Assemble contract/precondition/termination obligations from UNSAFE
      unsafeObls = case mFqResult of
        Just (FQUnsafe failedIds) ->
          assembleConstraintObligations stmts table mFqResult trustRpt
            faithful suppressed failedIds
        _ -> []

      allObls = holeObls ++ unsafeObls
      summary = ReportSummary
        { rsTotal      = length allObls
        , rsOpen       = length [o | o <- allObls, ooStatus o == "open"]
        , rsDischarged = length [o | o <- allObls, ooStatus o == "discharged"]
        , rsDeferred   = length [o | o <- allObls, ooStatus o == "deferred"]
        , rsAsserted   = length [o | o <- allObls, ooStatus o == "asserted"]
        }
      report = ObligationReport
        { orSchemaVersion = "0.10.0"
        , orSourceFile    = T.pack fp
        , orCrossModule   = "unsupported"
        , orObligations   = allObls
        , orSummary       = summary
        }
  in encodeReport report

-- | Assemble hole obligations from HoleReport.
assembleHoleObligations :: [Statement] -> ConstraintTable -> Maybe FQVerifyResult
                        -> TrustReport -> [Text] -> [Text] -> Set Name -> Set Name
                        -> HoleReport -> [ObligationObj]
assembleHoleObligations stmts table mFqResult trustRpt faithful fallback recNames suppressed hr =
  mapMaybe (mkHoleObl stmts table mFqResult trustRpt faithful fallback recNames suppressed)
           (holeEntries hr)

mkHoleObl :: [Statement] -> ConstraintTable -> Maybe FQVerifyResult
          -> TrustReport -> [Text] -> [Text] -> Set Name -> Set Name
          -> HoleEntry -> Maybe ObligationObj
mkHoleObl stmts table mFqResult trustRpt faithful fallback recNames suppressed he = do
  fnName <- enclosingFunc (holePointer he) stmts
  let (mContract, mParams, mBody) = findFunctionInfo fnName stmts
      params   = fromMaybe [] mParams
      contract = fromMaybe emptyContract mContract
      status   = obligationStatus mFqResult fnName HoleObligation table suppressed
      backing  = deriveBacking table fnName HoleObligation
      oblId    = normalizeForFingerprint fnName params (contractPost contract) "body"

      -- Type channel
      typeCh = TypeChannel
        { tcExpectedType = maybe "unknown" typeLabel (holeInferredType he)
        , tcPolymorphic  = case holeInferredType he of
            Just (TVar _) -> True
            _             -> False
        , tcInScope      = map paramToScope params
        }

      -- Contract channel
      aliases  = buildAliasMap stmts
      sortEnv  = buildSortEnv aliases params
      guards   = collectHoleGuards Map.empty sortEnv (fromMaybe (ELit (LitBool True)) mBody)
      myGuards = maybe [] snd $ lookup (holeName he) [(n, (n, gs)) | (n, gs) <- guards]
      contractCh = ContractChannel
        { ccPreconditions = maybe [] (\e -> [exprToSExpr e]) (contractPre contract)
        , ccPostGoal      = fmap exprToSExpr (contractPost contract)
        , ccPathCondition = take 16 myGuards
        , ccPathTruncated = length myGuards > 16
        , ccContractFrag  = classifyContractFragment contract
        , ccBodyFrag      = classifyBodyFragment fnName recNames faithful fallback
                              (fromMaybe (EHole (HNamed "")) mBody)
        , ccBodyFaithful  = fnName `elem` faithful
        }

      -- Trust channel
      mTrust = findTrustEntry fnName trustRpt
      trustCh = TrustChannel
        { trAssumptions    = []
        , trEffectiveLevel = maybe "asserted" (dlLabel . fromMaybe DLAsserted . teEffectiveLevel) mTrust
        , trBodyFaithful   = fnName `elem` faithful
        }

  Just ObligationObj
    { ooId              = oblId
    , ooOrigin          = holePointer he
    , ooKind            = HoleObligation
    , ooBacking         = backing
    , ooStatus          = status
    , ooFunction        = fnName
    , ooTypeChannel     = Just typeCh
    , ooContractChannel = Just contractCh
    , ooTrustChannel    = Just trustCh
    , ooContractedFns   = []  -- Phase 2: populated in future
    , ooAvailableFns    = []  -- Phase 2: populated in future
    , ooSuggestions     = []  -- Phase 3: OBLIG-4
    }

-- | Assemble contract/precondition/termination obligations from UNSAFE IDs.
assembleConstraintObligations :: [Statement] -> ConstraintTable -> Maybe FQVerifyResult
                              -> TrustReport -> [Text] -> Set Name -> [Int]
                              -> [ObligationObj]
assembleConstraintObligations stmts table mFqResult _trustRpt faithful suppressed failedIds =
  mapMaybe mkObl failedIds
  where
    mkObl cid = do
      origin <- Map.lookup cid table
      let fnName  = coFunction origin
          clause  = coClause origin
          kind    = classifyClause clause
          status  = obligationStatus mFqResult fnName kind table suppressed
          backing = deriveBacking table fnName kind
          (mContract, mParams, _) = findFunctionInfo fnName stmts
          params  = fromMaybe [] mParams
          oblId   = normalizeForFingerprint fnName params
                      (mContract >>= contractPost) (clauseChannel clause)
      Just ObligationObj
        { ooId              = oblId
        , ooOrigin          = coJsonPtr origin
        , ooKind            = kind
        , ooBacking         = backing
        , ooStatus          = status
        , ooFunction        = fnName
        , ooTypeChannel     = Nothing
        , ooContractChannel = Nothing
        , ooTrustChannel    = Nothing
        , ooContractedFns   = []
        , ooAvailableFns    = []
        , ooSuggestions     = []
        }

    classifyClause c
      | "call-pre:" `T.isPrefixOf` c = PreconditionObligation
      | c == "decreases"             = TerminationObligation
      | otherwise                    = ContractObligation

    clauseChannel c
      | "call-pre:" `T.isPrefixOf` c = "call-pre"
      | c == "decreases"             = "termination"
      | otherwise                    = "contract"

-- ---------------------------------------------------------------------------
-- Lookup helpers
-- ---------------------------------------------------------------------------

findFunctionInfo :: Name -> [Statement] -> (Maybe Contract, Maybe [(Name, Type)], Maybe Expr)
findFunctionInfo name stmts = case filter (matchesName name) stmts of
  (SDefLogic _ params mRet contract body : _) -> (Just contract, Just params, Just body)
  (SLetrec _ params mRet contract _ body : _) -> (Just contract, Just params, Just body)
  _ -> (Nothing, Nothing, Nothing)
  where
    matchesName n (SDefLogic nm _ _ _ _)    = nm == n
    matchesName n (SLetrec nm _ _ _ _ _)    = nm == n
    matchesName _ _                         = False

findTrustEntry :: Name -> TrustReport -> Maybe TrustEntry
findTrustEntry name tr = case filter (\e -> teName e == name) (trEntries tr) of
  (e:_) -> Just e
  []    -> Nothing

paramToScope :: (Name, Type) -> Value
paramToScope (n, ty) = object ["name" .= n, "type" .= typeLabel ty, "source" .= ("param" :: Text)]

emptyContract :: Contract
emptyContract = Contract Nothing Nothing Nothing Nothing

-- ---------------------------------------------------------------------------
-- JSON encoding (spec §2.1)
-- ---------------------------------------------------------------------------

encodeReport :: ObligationReport -> Text
encodeReport r = T.pack . map (toEnum . fromEnum) . BL.unpack . encode $ object
  [ "schema_version" .= orSchemaVersion r
  , "source_file"    .= orSourceFile r
  , "cross_module"   .= orCrossModule r
  , "obligations"    .= map encodeObligation (orObligations r)
  , "summary"        .= encodeSummary (orSummary r)
  ]

encodeObligation :: ObligationObj -> Value
encodeObligation o = object $
  [ "id"       .= ooId o
  , "origin"   .= ooOrigin o
  , "kind"     .= kindLabel (ooKind o)
  , "backing"  .= ooBacking o
  , "status"   .= ooStatus o
  , "function" .= ooFunction o
  ] ++ maybe [] (\tc -> ["type_channel" .= encodeTypeCh tc]) (ooTypeChannel o)
    ++ maybe [] (\cc -> ["contract_channel" .= encodeContractCh cc]) (ooContractChannel o)
    ++ maybe [] (\tr -> ["trust_channel" .= encodeTrustCh tr]) (ooTrustChannel o)
    ++ [ "contracted_functions" .= ooContractedFns o
       , "available_functions"  .= ooAvailableFns o
       , "suggestions"          .= ooSuggestions o
       ]

encodeTypeCh :: TypeChannel -> Value
encodeTypeCh tc = object
  [ "expected_type" .= tcExpectedType tc
  , "polymorphic"   .= tcPolymorphic tc
  , "in_scope"      .= tcInScope tc
  ]

encodeContractCh :: ContractChannel -> Value
encodeContractCh cc = object
  [ "preconditions"         .= ccPreconditions cc
  , "postcondition_goal"    .= ccPostGoal cc
  , "path_condition"        .= map (\pe -> object ["guard" .= peGuard pe, "kind" .= peKind pe])
                                   (ccPathCondition cc)
  , "path_truncated"        .= ccPathTruncated cc
  , "contract_fragment"     .= ccContractFrag cc
  , "body_fragment"         .= ccBodyFrag cc
  , "body_faithful_possible" .= ccBodyFaithful cc
  ]

encodeTrustCh :: TrustChannel -> Value
encodeTrustCh tr = object
  [ "assumptions"     .= trAssumptions tr
  , "effective_level" .= trEffectiveLevel tr
  , "body_faithful"   .= trBodyFaithful tr
  ]

encodeSummary :: ReportSummary -> Value
encodeSummary s = object
  [ "total"      .= rsTotal s
  , "open"       .= rsOpen s
  , "discharged" .= rsDischarged s
  , "deferred"   .= rsDeferred s
  , "asserted"   .= rsAsserted s
  ]
