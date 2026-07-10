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
  , EffectLabel(..)
  , EffectSummary(..)
    -- * Helpers
  , computeEffectSummary
  , encodeEff
  , exprToSExpr
  , deriveBacking
  , classifyGuard
  , collectHoleGuards
  , holeContractBrief
  , classifyContractFragment
  , classifyBodyFragment
  , normalizeForFingerprint
  , obligationStatus
  , recursiveNames
  , patternBindings
  , isTypeCompatible
  , trustLabel
    -- * Assembly
  , assembleReport
  , encodeReport
    -- * DEMO-COMP: compositional trust closure surfacing
  , assembleConsumedGuarantees
  , assembleFunctionLists
  , importedContractedFns   -- XMOD-SCOPE-BRIEF: imported callables under callable names
  , assembleSafePreObligations
  , ObligationObj(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Maybe (fromMaybe, isJust, mapMaybe, catMaybes)
import Data.List (foldl', sortOn, sort, nub)
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
import LLMLL.TrustReport (TrustReport(..), TrustEntry(..), injectOpenedAliases)
import LLMLL.HoleAnalysis
  ( HoleReport(..), HoleEntry(..), HoleStatus(..)
  , holeEntries, analyzeHoles, buildCallGraph, enclosingFunc )
import LLMLL.ObligationMining (isQfLia, generateCandidates, CandidateExpr(..))
import LLMLL.TypeCheck (builtinEnv)
import LLMLL.GuardClassifier (classifyGuardM, lookupArithOp, lookupPredOp)

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
  { trAssumptions     :: [Value]
  , trEffectiveLevel  :: Text
  , trBodyFaithful    :: Bool
  , trOverflowTainted :: Bool  -- ^ INT-1: body-faithful evidence carries unbounded-Int arithmetic
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
  , ooContractedFns       :: [Value]
  , ooAvailableFns        :: [Value]
  , ooSuggestions         :: [Value]
  , ooContractedTruncated :: Bool       -- F5: spec §8.2 truncation signal
  , ooAvailableTruncated  :: Bool       -- F5: spec §8.2 truncation signal
  -- Branch-specific fields (F4: only populated for BranchObligation)
  , ooParentId        :: Maybe Text
  , ooBranchIndex     :: Maybe Int
  , ooConstructor     :: Maybe Text
  , ooBindings        :: [Value]
  } deriving (Show)

-- | Report summary (spec §2.1)
data ReportSummary = ReportSummary
  { rsTotal      :: Int
  , rsOpen       :: Int
  , rsDischarged :: Int
  , rsDeferred   :: Int
  , rsAsserted   :: Int
  , rsRefuted    :: Int   -- VERIFY-RPT-1 (Commit 4): body-faithful disproved
  } deriving (Show)

-- | Top-level obligation report (spec §2.1)
data ObligationReport = ObligationReport
  { orSchemaVersion :: Text
  , orSourceFile    :: Text
  , orCrossModule   :: Text
  , orObligations   :: [ObligationObj]
  , orSummary       :: ReportSummary
  , orRefutedFns    :: [Name]   -- VERIFY-RPT-1 (Commit 4): top-level refuted_fns
  , orEffectSummary :: [(Name, EffectSummary)]  -- Bundle B0: per-function authority summary (informational)
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
      let preOk  = maybe True isQfLia (contractPre c)
          postOk = maybe True isQfLia (contractPost c)
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

-- ---------------------------------------------------------------------------
-- Bundle B0: per-function effect / authority summary (4th informational channel)
--
-- A sound MAY-over-approximation of the coarse capabilities a function may
-- exercise ("at most S"). 'Unbounded' is the lattice top ⊤ — "may exercise any
-- capability, including outside the catalog" — distinct from the full 6-set;
-- reached at opaque boundaries (?delegate/?scaffold holes, haskell.*/c.* FFI,
-- unrecognized wasi.*). Informational ONLY: computed here and written solely to
-- the report — never feeds the trust meet / EvidenceRecord / verified
-- admissibility. See docs/design/bundle-b0-effect-summary-proposal.md.
-- ---------------------------------------------------------------------------

-- | Closed coarse capability catalog Σ_eff (v0.12).
data EffectLabel = EStdout | EFsRead | EFsWrite | ENetHttp | ERandom | ECrypto
  deriving (Eq, Ord, Show, Enum, Bounded)

effectLabelText :: EffectLabel -> Text
effectLabelText EStdout  = "stdout"
effectLabelText EFsRead  = "fs.read"
effectLabelText EFsWrite = "fs.write"
effectLabelText ENetHttp = "net.http"
effectLabelText ERandom  = "random"
effectLabelText ECrypto  = "crypto"

-- | Authority summary. 'Unbounded' (⊤) is distinct from the full 6-set.
data EffectSummary = Caps (Set EffectLabel) | Unbounded
  deriving (Eq, Show)

bottomEff :: EffectSummary
bottomEff = Caps Set.empty

joinEff :: EffectSummary -> EffectSummary -> EffectSummary
joinEff Unbounded _       = Unbounded
joinEff _ Unbounded       = Unbounded
joinEff (Caps a) (Caps b) = Caps (Set.union a b)

joinEffs :: [EffectSummary] -> EffectSummary
joinEffs = foldl' joinEff bottomEff

-- | Own-effect contribution of a directly-applied name. 'Nothing' = no own
-- effect (pure builtin, or a user function — the latter resolved transitively
-- by the call-graph closure). The effectful-builtin surface is closed
-- (builtinEnv, TypeCheck.hs:132-144,342); FFI / unrecognized wasi.* → ⊤.
primEffect :: Name -> Maybe EffectSummary
primEffect n
  | n == "wasi.io.stdout"   || n == "wasi.io.stderr"   = one EStdout
  | n == "wasi.http.response" || n == "wasi.http.post" = one ENetHttp
  | n == "wasi.fs.read"                                = one EFsRead
  | n == "wasi.fs.write"    || n == "wasi.fs.delete"   = one EFsWrite
  | n == "hmac-sha1"        || n == "sha1"             = one ECrypto
  | n == "random-int"                                  = one ERandom
  | "haskell." `T.isPrefixOf` n                        = Just Unbounded
  | "c." `T.isPrefixOf` n                              = Just Unbounded
  | "wasi." `T.isPrefixOf` n                           = Just Unbounded
  | otherwise                                          = Nothing
  where one x = Just (Caps (Set.singleton x))

-- | A function's OWN effects: a walk of its body collecting primitive-call
-- labels, with ⊤ for opaque (delegate/scaffold) holes. Excludes transitive
-- callee effects (added by 'computeEffectSummary' over the call graph).
ownEffects :: Expr -> EffectSummary
ownEffects = go
  where
    go e = case e of
      EApp f args   -> joinEffs (fromMaybe bottomEff (primEffect f) : map go args)
      EOp  o args   -> joinEffs (fromMaybe bottomEff (primEffect o) : map go args)
      ELet bs body  -> joinEffs (go body : [go r | (_, _, r) <- bs])
      EIf a b c     -> joinEffs [go a, go b, go c]
      EMatch s arms -> joinEffs (go s : map (go . snd) arms)
      EPair a b     -> joinEff (go a) (go b)
      EAwait a      -> go a
      ELambda _ b   -> go b
      EDo steps     -> joinEffs [go se | DoStep _ se <- steps]
      EHole hk      -> if opaque hk then Unbounded else bottomEff
      _             -> bottomEff
    opaque HDelegate{}        = True
    opaque HDelegateAsync{}   = True
    opaque HDelegatePending{} = True
    opaque HScaffold{}        = True
    opaque _                  = False

-- | Per-function authority summary: own effects joined with the transitive
-- closure over the call graph. Least fixpoint on the finite lattice
-- 2^Σ_eff ∪ {⊤} (monotone; terminates). Name-sorted. Informational (header).
computeEffectSummary :: ModuleCache -> [Statement] -> [(Name, EffectSummary)]
computeEffectSummary cache stmts =
  let importedStmts = concatMap meStatements (Map.elems cache)
      allStmts      = stmts ++ importedStmts
      cg            = buildCallGraph allStmts
      ownMap        = Map.fromList [(n, ownEffects b) | (n, b) <- fnBodies allStmts]
      -- Names whose effect is known without further walking: known builtins
      -- (their capability, if any, is already folded into the caller's
      -- ownEffects via primEffect) and declared data constructors (effect-free).
      knownPure = Map.keysSet builtinEnv `Set.union`
        Set.fromList [ cn | STypeDef _ (TSumType ctors) <- allStmts, (cn, _) <- ctors ]
      -- ∅-iff-fully-walked (professor Hazard 1, language-team-settled): a callee
      -- contributes ∅ ONLY if it is a resolved function (local or imported, in
      -- ownMap), a known builtin/constructor, or a recognized primitive (already
      -- counted in ownEffects). Any OTHER applied name is opaque/unresolved — e.g.
      -- a call into a module not in the cache — and joins ⊤, never silently ∅.
      calleeEff m c
        | Just e <- Map.lookup c m  = e
        | c `Set.member` knownPure  = bottomEff
        | Just _ <- primEffect c    = bottomEff
        | otherwise                 = Unbounded
      step m = Map.mapWithKey
        (\n o -> joinEffs (o : [ calleeEff m c
                               | c <- Map.findWithDefault [] n cg ]))
        ownMap
      fixp m = let m' = step m in if m' == m then m else fixp m'
      -- Report only the local module's functions; the imported defs were folded
      -- in solely to resolve cross-module callees during the fixpoint.
      localNames = Set.fromList (map fst (fnBodies stmts))
  in sortOn fst
       [ (n, e) | (n, e) <- Map.toList (fixp ownMap), n `Set.member` localNames ]
  where
    fnBodies = mapMaybe $ \s -> case s of
      SDef      n _ _ _ b   -> Just (n, b)
      SDefShell n _ _ _ b _   -> Just (n, b)
      SDefLogic n _ _ _ b   -> Just (n, b)
      SLetrec   n _ _ _ _ b -> Just (n, b)
      -- v0.12.1
      SDefInvariant n _ _ _ b -> Just (n, b)
      _                     -> Nothing

encodeEffectSummary :: [(Name, EffectSummary)] -> Value
encodeEffectSummary xs =
  toJSON [ object ["function" .= n, "effects" .= encodeEff e] | (n, e) <- xs ]

encodeEff :: EffectSummary -> Value
encodeEff Unbounded   = String "unbounded"
encodeEff (Caps s) = toJSON (sort (map effectLabelText (Set.toList s)))

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
-- VERIFY-RPT-1 (Commit 4): takes the refuted set (body-faithful functions the
-- solver disproved, per verified-contract-refuted-status-proposal §3.2). A
-- refuted function's obligation reports "refuted" — distinct from "open"
-- (un-discharged / unknown) — and refuted takes precedence over every other
-- status: a disproved implementation is neither merely open nor deferrable.
obligationStatus :: Maybe FQVerifyResult -> Name -> ObligationKind -> ConstraintTable
                 -> Set Name -> Set Name -> Text
obligationStatus mFqResult fnName kind table suppressedSet refutedSet
  | fnName `Set.member` refutedSet    = "refuted"
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

-- | isQfLia is now imported from ObligationMining (F5: predicate drift fix).

-- ---------------------------------------------------------------------------
-- Phase 3: Branch obligation helpers (OBLIG-3)
-- ---------------------------------------------------------------------------

-- | Extract variable bindings from a pattern (F2: recursive on PConstructor).
patternBindings :: Pattern -> [(Name, Text)]
patternBindings (PVar v)            = [(v, "match-arm")]
patternBindings (PConstructor _ ps) = concatMap patternBindings ps
patternBindings PWildcard           = []
patternBindings (PLiteral _)        = []

-- | Best-effort type recovery for scrutinee (Q1/b2, F6).
-- Handles EVar (param lookup) and EApp (builtinEnv lookup).
inferScrutineeType :: [(Name, Type)] -> Expr -> Maybe Type
inferScrutineeType params (EVar v) = lookup v params
inferScrutineeType _params (EApp fn _args) =
  case Map.lookup fn builtinEnv of
    Just ty -> Just (returnType ty)
    Nothing -> Nothing
inferScrutineeType _ _ = Nothing

-- | Look up a constructor's payload type from a sum type (R1).
lookupConstructorPayload :: AliasMap -> Type -> Name -> Maybe Type
lookupConstructorPayload aliases scrutTy ctorName =
  case resolveType scrutTy of
    TSumType ctors ->
      lookup ctorName ctors >>= id
    TResult okTy errTy
      | ctorName == "Success" -> Just okTy
      | ctorName == "Error"   -> Just errTy
    _ -> Nothing
  where
    resolveType (TCustom n)        = maybe (TCustom n) resolveType (Map.lookup n aliases)
    resolveType (TDependent _ b _) = resolveType b   -- R2: strip refinement
    resolveType t                  = t

-- | Assemble branch obligations from EMatch in hole-bearing functions (F1).
-- Two-pass: takes hole obligations for parent_id linkage.
-- VERIFY-RPT-1 (Commit 4): 'refutedSet' threaded through the branch path
-- because branch obligations (body-post-then/else) of a refuted body-faithful
-- function must report "refuted" too. This path carries no TrustReport, so the
-- set is passed explicitly from 'assembleReport'.
assembleBranchObligations :: [ObligationObj] -> [Statement] -> ConstraintTable
                          -> Maybe FQVerifyResult -> Set Name -> Set Name -> AliasMap
                          -> [ObligationObj]
assembleBranchObligations holeObls stmts table mFqResult suppressed refutedSet aliases =
  concatMap (branchesForHole stmts table mFqResult suppressed refutedSet aliases) holeObls

branchesForHole :: [Statement] -> ConstraintTable -> Maybe FQVerifyResult
                -> Set Name -> Set Name -> AliasMap -> ObligationObj -> [ObligationObj]
branchesForHole stmts table mFqResult suppressed refutedSet aliases parentObl =
  let fnName = ooFunction parentObl
      (mContract, mParams, mBody) = findFunctionInfo fnName stmts
      params = fromMaybe [] mParams
      contract = fromMaybe emptyContract mContract
  in case mBody of
    Nothing -> []
    Just body -> findMatchBranches fnName params contract parentObl
                   table mFqResult suppressed refutedSet aliases body

findMatchBranches :: Name -> [(Name, Type)] -> Contract -> ObligationObj
                  -> ConstraintTable -> Maybe FQVerifyResult -> Set Name -> Set Name
                  -> AliasMap -> Expr -> [ObligationObj]
findMatchBranches fnName params contract parentObl table mFqResult suppressed refutedSet aliases = go
  where
    go (EMatch scrut arms) =
      let scrutTy = inferScrutineeType params scrut
      in concatMap (\(i, (pat, armBody)) ->
        let ctorName = case pat of
              PConstructor c _ -> c
              PVar v           -> v
              PWildcard        -> "_"
              PLiteral _       -> "<lit>"
            binds = patternBindings pat
            typedBinds = case scrutTy of
              Just sty -> map (\(n, src) ->
                let ty = case pat of
                      PConstructor c _ -> maybe "_" typeLabel
                                           (lookupConstructorPayload aliases sty c)
                      _ -> "_"
                in object ["name" .= n, "type" .= (ty :: Text), "source" .= src]) binds
              Nothing -> map (\(n, src) ->
                object ["name" .= n, "type" .= ("_" :: Text), "source" .= src]) binds
            pathEntry = PathEntry ("(match-" <> ctorName <> ")") "structural"
            status = obligationStatus mFqResult fnName BranchObligation table suppressed refutedSet
            backing = deriveBacking table fnName BranchObligation
            oblId = normalizeForFingerprint fnName params (contractPost contract)
                      ("branch-" <> T.pack (show i))
        in [ObligationObj
              { ooId              = oblId
              , ooOrigin          = ooOrigin parentObl <> "/arms/" <> T.pack (show i)
              , ooKind            = BranchObligation
              , ooBacking         = backing
              , ooStatus          = status
              , ooFunction        = fnName
              , ooTypeChannel     = Nothing
              , ooContractChannel = Nothing
              , ooTrustChannel    = Nothing
              , ooContractedFns       = []
              , ooAvailableFns        = []
              , ooSuggestions         = []
              , ooContractedTruncated = False
              , ooAvailableTruncated  = False
              , ooParentId        = Just (ooId parentObl)
              , ooBranchIndex     = Just i
              , ooConstructor     = Just ctorName
              , ooBindings        = typedBinds
              }] ++ go armBody
        ) (zip [0..] arms)
    go (EIf _ t e)       = go t ++ go e
    go (ELet _ body)     = go body
    go (EApp _ args)     = concatMap go args
    go (EOp _ args)      = concatMap go args
    go (EPair a b)       = go a ++ go b
    go (EAwait e)        = go e
    go (ELambda _ b)     = go b
    go (EDo steps)       = concatMap (\(DoStep _ e) -> go e) steps
    go _                 = []

-- ---------------------------------------------------------------------------
-- Phase 3: Function lists (spec §8)
-- ---------------------------------------------------------------------------

-- | Type-compatibility with Result-unwrapping (F8, R1, C2).
-- TVar overapproximation acceptable for v0.10 (F2): LLMLL builtins
-- have concrete return types in practice. Spec §8.2 zonking deferred to v0.11.
isTypeCompatible :: AliasMap -> Type -> Type -> Bool
isTypeCompatible _      _ (TVar _)                  = True
isTypeCompatible _      (TVar _) _                  = True
isTypeCompatible aliases expected actual@(TResult ok _) =
  typeLabel expected == typeLabel actual
  || isTypeCompatible aliases expected ok
isTypeCompatible aliases expected (TCustom n) =
  case Map.lookup n aliases of
    Just resolved -> isTypeCompatible aliases expected resolved
    Nothing       -> typeLabel expected == typeLabel (TCustom n)
isTypeCompatible aliases (TCustom n) actual =
  case Map.lookup n aliases of
    Just resolved -> isTypeCompatible aliases resolved actual
    Nothing       -> typeLabel (TCustom n) == typeLabel actual
isTypeCompatible aliases expected (TDependent _ base _) =   -- R1
  isTypeCompatible aliases expected base
isTypeCompatible aliases (TDependent _ base _) actual =      -- R1
  isTypeCompatible aliases base actual
isTypeCompatible _ expected actual = typeLabel expected == typeLabel actual

-- | Trust label for function lists (F9, R3).
--
-- TRUST-PRE (Position B, transitive-callee fix): reads the POST-side effective
-- level ('teEffectivePostLevel'), not the historically pre-inclusive
-- 'teEffectiveLevel'. The 'callee_tier' soundness lever (§5 edge 3) leans on the
-- callee's POST — what the consumer actually depends on — not the callee's own
-- precondition (the consumer's call-site obligation, discharged by a SAFE
-- call-pre VC). So a verified-post pre-bearing callee surfaces 'verified' here,
-- which is correct: the consumer inherits the proven post, and the callee's pre
-- is the consumer's own obligation, tracked on the orthogonal caller_obligations
-- axis. The two fields are equal after the convergence in 'enrichEntry', but we
-- key on the post-side one explicitly to name the intended source.
trustLabel :: Map Name TrustEntry -> Name -> Text
trustLabel trustMap name = case Map.lookup name trustMap of
  Just te -> case teEffectivePostLevel te of
    Just (DLVerified _)       -> "verified"
    Just (DLVerifiedLean _)   -> "verified-lean"
    Just (DLContractChecked _) -> "contract-checked"
    Just DLAsserted           -> "asserted"
    _                         -> "asserted"
  Nothing -> "builtin"

-- ---------------------------------------------------------------------------
-- DEMO-COMP (§3.1, §5 edge 3): consumed_guarantees channel
--
-- Surfaces the shipped v0.9.0 assume-guarantee accounting: for each contracted
-- callee a function calls, the callee's discharged postcondition is consumed as
-- an available hypothesis. This is NOT a TCB assumption (that channel is
-- 'trAssumptions' / 'ctAssumptions') — it is a *consumed guarantee*, sound iff
-- the callee was itself verified. No new verification logic; the discharge
-- already happened in 'CallVC' (FixpointEmit). This is field-surfacing only.
--
-- SOUNDNESS (§5 edge 3, engineer F1): 'callee_tier' is sourced from the
-- callee's actual 'teEffectiveLevel' (never hardcoded "verified"). A recursive
-- callee's tier is already degraded (its own body VC is excluded by design,
-- FixpointEmit), so reading the real tier keeps the channel honest.
-- Additionally, self / SCC self-edges are filtered via 'recursiveNames' — a
-- function must never list its own post as a consumed guarantee.
-- ---------------------------------------------------------------------------

-- | Assemble the 'consumed_guarantees' channel for a single function.
-- Returns one record per contracted-callee call site in the function body.
--
-- For each call '(callee a1 .. an)' where 'callee' is in the ContractEnv and
-- carries a post, the record carries:
--   * the raw 'guarantee' (callee.post, rendered)
--   * the 'instantiated' up-hypothesis post[ai/xi, result/<call-result>]
--     re-derived by pure Expr-level substitution (engineer F5: re-derived, not
--     solver-witnessed — the discharge claim rests on 'callee_tier', not this
--     string)
--   * 'callee_tier' from teEffectiveLevel (soundness lever)
--   * 'status' = "discharged"
assembleConsumedGuarantees
  :: [Statement] -> ContractEnv -> Map Name TrustEntry -> Set Name -> Name -> [Value]
assembleConsumedGuarantees stmts cenv trustMap recNames fnName =
  case [ body | stmt <- stmts
              , Just (nm, _params, _ret, _c, body) <- [normalizeDefStmt stmt]
              , nm == fnName ] of
    []        -> []
    (body:_)  ->
      [ guaranteeRecord callee args post cparams
      | (callee, args) <- collectContractedCalls cenv body
        -- §5 edge 3: a function must never list its OWN post as a consumed
        -- guarantee. Drop direct self-calls, and any self-edge within an SCC.
      , callee /= fnName
      , not (callee `Set.member` recNames && fnName `Set.member` recNames
             && callee == fnName)
      , Just (cparams, ccontract, _cret) <- [Map.lookup callee cenv]
      , Just post <- [contractPost ccontract]
      ]
  where
    guaranteeRecord callee args post cparams =
      let cparamNames = map fst cparams
          -- Re-derive the instantiated up-hypothesis by pure substitution:
          -- callee params → actual arg Exprs, result → <call-result>.
          subst       = Map.fromList (zip cparamNames args)
          instExpr    = substExpr (Map.insert "result" (EVar "<call-result>") subst) post
          -- callee_tier from the callee's actual effective level (§5 edge 3).
          calleeTier  = trustLabel trustMap callee
      in object
           [ "callee"       .= callee
           , "guarantee"    .= exprToSExpr post
           , "instantiated" .= exprToSExpr instExpr
           , "callee_tier"  .= calleeTier
           , "status"       .= ("discharged" :: Text)
           ]

-- | Pure Expr-level capture-free substitution over the QF-LIA / refinement
-- predicate fragment (vars → Exprs). Mirrors 'applySubst' (FixpointEmit) but at
-- the surface-Expr level so the rendered s-expression matches the demo shape
-- '(= <call-result> (+ x x))' rather than the .fq infix form. Only the predicate
-- fragment occurring in contracts is traversed.
substExpr :: Map Name Expr -> Expr -> Expr
substExpr s (EVar v)          = Map.findWithDefault (EVar v) v s
substExpr s (EApp op args)    = EApp op (map (substExpr s) args)
substExpr s (EOp op args)     = EOp op (map (substExpr s) args)
substExpr _ e@(ELit _)        = e
substExpr _ e@(EHole _)       = e
substExpr s (EIf c t e)       = EIf (substExpr s c) (substExpr s t) (substExpr s e)
substExpr _ e                 = e

-- | Collect '(callee a1 .. an)' calls to contracted user functions in a body,
-- using the same callee-admissibility predicate as the emitter (in ContractEnv,
-- not a builtin operator). Returns (callee, argExprs) per call site, in
-- left-to-right textual order (so nested 'double (double x)' yields the outer
-- call first, then the inner — matching call-site obligation ordering).
collectContractedCalls :: ContractEnv -> Expr -> [(Name, [Expr])]
collectContractedCalls cenv = go
  where
    isContractedCall fname =
      fname `Map.member` cenv
        && lookupArithOp fname == Nothing
        && lookupPredOp fname == Nothing
        && fname `notElem` ["not", "and", "or", "*", "/", "mod", "rem", "^", "**"]
    go (EApp fname args)
      | isContractedCall fname = (fname, args) : concatMap go args
      | otherwise              = concatMap go args
    go (EOp _ args)            = concatMap go args
    go (EIf c t e)             = go c ++ go t ++ go e
    go (ELet binds body)      = concatMap (\(_, _, e) -> go e) binds ++ go body
    go (EMatch scrut arms)    = go scrut ++ concatMap (go . snd) arms
    go (EPair a b)            = go a ++ go b
    go (EAwait e)             = go e
    go (ELambda _ body)       = go body
    go (EDo steps)            = concatMap (\(DoStep _ e) -> go e) steps
    go _                       = []

-- | XMOD-SCOPE-BRIEF: imported contracted functions visible to the entry
-- module, each under the name the entry module calls it by — bare when an
-- '(open ...)' admits it (selective filter honored; a same-named local def
-- shadows the import, which then falls back to its qualified name),
-- qualified otherwise. Only EXPORTED names appear (the type checker admits
-- nothing else), so a brief never suggests a call that cannot type-check —
-- note 'meContracts' itself is unfiltered, hence the 'meExports' membership
-- gate here.
importedContractedFns
  :: [Statement] -> ModuleCache -> [(Name, [(Name, Type)], Maybe Type, Contract)]
importedContractedFns stmts cache =
  [ (displayName, ps, mRet, c)
  | (path, menv) <- Map.toList cache
  , (fname, (ps, c, mRet)) <- Map.toList (meContracts menv)
  , contractPre c /= Nothing || contractPost c /= Nothing
  , fname `Map.member` meExports menv
  , let qualified   = T.intercalate "." path <> "." <> fname
        displayName = if openedBare path fname then fname else qualified
  ]
  where
    localNames = Set.fromList
      [ n | s <- stmts, Just (n, _, _, _, _) <- [normalizeDefStmt s] ]
    opens = [ (p, ns) | SOpen p ns <- stmts ]
    openedBare path fname =
      fname `Set.notMember` localNames
        && any (\(p, ns) -> p == path && maybe True (fname `elem`) ns) opens

-- | Assemble function lists with cap-8 and truncation signals (spec §8.2).
-- Ordering: alphabetical (v0.10). Spec §8.2 zonking priority deferred to v0.11 (F8).
-- XMOD-SCOPE-BRIEF: the contracted list is cache-aware — imported exported
-- contracted functions appear after the same-file ones, under their callable
-- names ('importedContractedFns'); empty cache ⇒ unchanged.
-- OBLIG-VOCAB-GATE: the expected type is 'Maybe' — the return-type
-- compatibility gate applies only when the hole's type is KNOWN. Previously
-- an unknown type defaulted to 'TUnit', which silently emptied the lists
-- (every '-> T'-annotated function and every monomorphic-return builtin
-- failed the unit comparison) — "no callable functions" where the truth was
-- "type unknown". Unknown now means the full (still capped) vocabulary.
assembleFunctionLists :: [Statement] -> ModuleCache -> AliasMap -> Map Name TrustEntry -> Maybe Type
                      -> ([Value], Bool, [Value], Bool)
assembleFunctionLists stmts cache aliases trustMap mExpectedTy =
  let cap = 8
      -- DEMO-COMP fallback, kept per clause: an unannotated declaration
      -- (mRet = Nothing — the common case before DEF-RET's optional
      -- '-> RetType', v0.13.1) is gated and displayed as the hole's expected
      -- type when that is known; with BOTH unknown it passes the gate and
      -- displays "?" (matching the checkout brief's 'feReturn' convention).
      retCompatible mRet = case mExpectedTy of
        Nothing         -> True
        Just expectedTy -> isTypeCompatible aliases expectedTy (fromMaybe expectedTy mRet)
      retLabel mRet = case (mRet, mExpectedTy) of
        (Just r,  _)             -> typeLabel r
        (Nothing, Just expectedTy) -> typeLabel expectedTy
        (Nothing, Nothing)       -> "?" :: Text
      -- Contracted: user functions with contracts and compatible return types (C3: + SLetrec)
      allContracted =
        -- DEMO-COMP (§3.2, engineer F2): the contracted-user vocabulary now
        -- carries pre/post/tier/return_type so an agent sees the contract it
        -- must discharge and may assume. pre is null for a pre-free callee
        -- (e.g. double), so a pre-free callee → zero call-site obligations is
        -- legible from the record alone. tier is the function's own
        -- effective-level trust label (verified / contract-checked / asserted).
        [ object [ "name"        .= fname
                 , "params"      .= map (\(n,t) -> [toJSON n, toJSON (typeLabel t)]) ps
                 , "returns"     .= retLabel mRet
                 , "return_type" .= retLabel mRet   -- alias of returns (§3.2)
                 , "status"      .= trustLabel trustMap fname
                 , "pre"         .= fmap exprToSExpr (contractPre c)
                 , "post"        .= fmap exprToSExpr (contractPost c)
                 , "tier"        .= trustLabel trustMap fname ]
        | stmt <- stmts
        , Just (fname, ps, mRet, c, _) <- [normalizeDefStmt stmt]
        , contractPre c /= Nothing || contractPost c /= Nothing
        , retCompatible mRet
        ]
        ++
        -- XMOD-SCOPE-BRIEF: imported exported contracted functions, same
        -- record shape and gating, named as the entry module calls them.
        [ object [ "name"        .= dname
                 , "params"      .= map (\(n,t) -> [toJSON n, toJSON (typeLabel t)]) ps
                 , "returns"     .= retLabel mRet
                 , "return_type" .= retLabel mRet
                 , "status"      .= trustLabel trustMap dname
                 , "pre"         .= fmap exprToSExpr (contractPre c)
                 , "post"        .= fmap exprToSExpr (contractPost c)
                 , "tier"        .= trustLabel trustMap dname ]
        | (dname, ps, mRet, c) <- importedContractedFns stmts cache
        , retCompatible mRet
        ]
      contracted = take cap allContracted
      contractedT = length allContracted > cap
      -- Available: builtins (non-wasi) with compatible return types (C4: params populated)
      builtins = Map.toList builtinEnv
      allAvailable =
        [ object [ "name"    .= bname
                 , "params"  .= builtinParams bty
                 , "returns" .= typeLabel (returnType bty)
                 , "status"  .= ("builtin" :: Text) ]
        | (bname, bty) <- builtins
        , not ("wasi." `T.isPrefixOf` bname)
        , maybe True (\expectedTy -> isTypeCompatible aliases expectedTy (returnType bty)) mExpectedTy
        ]
      available = take cap allAvailable
      availableT = length allAvailable > cap
  in (contracted, contractedT, available, availableT)

-- | Extract parameter types from a function type for builtin display (C4, F4).
builtinParams :: Type -> [[Value]]
builtinParams (TFn argTys _) =
  zipWith (\i t -> [toJSON ("arg" <> T.pack (show i) :: Text), toJSON (typeLabel t)])
          [1::Int ..] argTys
builtinParams _ = []

-- | Extract return type (last arrow result or self).
returnType :: Type -> Type
returnType (TFn _ r) = r
returnType t         = t

-- | Encode a candidate expression as JSON.
encodeCand :: CandidateExpr -> Value
encodeCand c = object
  [ "expr"     .= ceExpr c
  , "verified" .= ceVerified c
  , "kind"     .= ceKind c ]

-- ---------------------------------------------------------------------------
-- Assembly (spec §2.1)
-- ---------------------------------------------------------------------------

-- | Top-level report assembly.
assembleReport :: FilePath -> [Statement] -> ModuleCache -> EmitResult
               -> Maybe FQVerifyResult -> TrustReport -> Text
assembleReport fp stmts cache emitR mFqResult trustRpt =
  let table      = erConstraintTable emitR
      faithful   = erBodyFaithfulFns emitR
      fallback   = erBodyFallback emitR
      tainted    = erOverflowTaintedFns emitR  -- INT-1: per-fn overflow-taint set
      recNames   = recursiveNames stmts
      suppressed = Set.fromList (map fst (trSuppressions trustRpt))
      -- VERIFY-RPT-1 (Commit 4): the refuted set is whatever 'markRefuted'
      -- stamped onto the trust report upstream (Main.hs); empty when no
      -- body-faithful function was disproved.
      refutedSet = trRefutedFns trustRpt
      holeReport = analyzeHoles stmts

      -- Assemble hole obligations (XMOD-SCOPE-BRIEF: cache-aware, so the
      -- per-hole contracted-function vocabulary includes imported callables)
      holeObls = assembleHoleObligations stmts cache table mFqResult trustRpt
                   faithful fallback tainted recNames suppressed holeReport

      -- Assemble branch obligations from EMatch (F1: two-pass)
      aliases = buildAliasMap stmts
      branchObls = assembleBranchObligations holeObls stmts table
                     mFqResult suppressed refutedSet aliases

      -- Assemble contract/precondition/termination obligations from UNSAFE
      unsafeObls = case mFqResult of
        Just (FQUnsafe failedIds) ->
          assembleConstraintObligations stmts table mFqResult trustRpt
            faithful suppressed failedIds
        _ -> []

      -- DEMO-COMP (§3.3): surface per-call-site precondition obligations on SAFE
      -- too. These are a report-level read of 'call-pre:' constraints already
      -- solved (status "discharged"); the count rises by the contracted-call-site
      -- count (withdraw-twice → 2, quadruple → 0). Suppressed on UNSAFE because
      -- the failing call-pre obligations are already surfaced by 'unsafeObls'
      -- (assembleConstraintObligations classifies "call-pre:" → PreconditionObligation).
      safePreObls = case mFqResult of
        Just FQSafe -> assembleSafePreObligations stmts table mFqResult trustRpt suppressed
        _           -> []

      allObls = holeObls ++ branchObls ++ unsafeObls ++ safePreObls
      summary = ReportSummary
        { rsTotal      = length allObls
        , rsOpen       = length [o | o <- allObls, ooStatus o == "open"]
        , rsDischarged = length [o | o <- allObls, ooStatus o == "discharged"]
        , rsDeferred   = length [o | o <- allObls, ooStatus o == "deferred"]
        , rsAsserted   = length [o | o <- allObls, ooStatus o == "asserted"]
        , rsRefuted    = length [o | o <- allObls, ooStatus o == "refuted"]
        }
      report = ObligationReport
        -- VERIFY-RPT-1 (Commit 4): 0.10.0 -> 0.11.0 (additive: "refuted" status
        -- enum value, top-level refuted_fns, summary refuted count).
        -- Bundle B0: 0.11.0 -> 0.12.0 (additive: per-function effect_summary).
        -- DEMO-COMP: 0.12.0 -> 0.12.1 (additive: contracted_functions.{pre,post,
        -- tier,return_type}, SAFE precondition-obligation entries, consumed_guarantees).
        { orSchemaVersion = "0.12.1"
        , orSourceFile    = T.pack fp
        , orCrossModule   = if Map.null cache then "single-file" else "supported"
        , orObligations   = allObls
        , orSummary       = summary
        , orRefutedFns    = Set.toList refutedSet
        , orEffectSummary = computeEffectSummary cache stmts
        }
  in encodeReport report

-- | Assemble hole obligations from HoleReport.
assembleHoleObligations :: [Statement] -> ModuleCache -> ConstraintTable -> Maybe FQVerifyResult
                        -> TrustReport -> [Text] -> [Text] -> [Text] -> Set Name -> Set Name
                        -> HoleReport -> [ObligationObj]
assembleHoleObligations stmts cache table mFqResult trustRpt faithful fallback tainted recNames suppressed hr =
  mapMaybe (mkHoleObl stmts cache table mFqResult trustRpt faithful fallback tainted recNames suppressed)
           (holeEntries hr)

mkHoleObl :: [Statement] -> ModuleCache -> ConstraintTable -> Maybe FQVerifyResult
          -> TrustReport -> [Text] -> [Text] -> [Text] -> Set Name -> Set Name
          -> HoleEntry -> Maybe ObligationObj
mkHoleObl stmts cache table mFqResult trustRpt faithful fallback tainted recNames suppressed he = do
  fnName <- enclosingFunc (holePointer he) stmts
  let (mContract, mParams, mBody) = findFunctionInfo fnName stmts
      params   = fromMaybe [] mParams
      contract = fromMaybe emptyContract mContract
      status   = obligationStatus mFqResult fnName HoleObligation table suppressed (trRefutedFns trustRpt)
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
      -- F7 fix: holeName has "?" prefix, collectHoleGuards emits without
      hName    = T.dropWhile (== '?') (holeName he)
      myGuards = maybe [] snd $ lookup hName [(n, (n, gs)) | (n, gs) <- guards]
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
        { trAssumptions     = []
        -- TRUST-PRE (Position B): the channel's effective tier is the POST-side
        -- level — a precondition is the caller's obligation, off this axis.
        , trEffectiveLevel  = maybe "asserted" (dlLabel . fromMaybe DLAsserted . teEffectivePostLevel) mTrust
        , trBodyFaithful    = fnName `elem` faithful
        , trOverflowTainted = fnName `elem` tainted
        }

      -- Function lists (§8)
      -- XMOD-SCOPE-BRIEF: bare-alias opened imports so a bare imported
      -- callable's tier resolves to its qualified trust entry, not "builtin".
      trustMap = injectOpenedAliases stmts $
                   Map.fromList [(teName e, e) | e <- trEntries trustRpt]
      -- OBLIG-VOCAB-GATE: pass the hole's inferred type as-is — an unknown
      -- type must NOT gate the vocabulary (it used to default to TUnit).
      (contracted, contractedT, available, availableT) =
        assembleFunctionLists stmts cache aliases trustMap (holeInferredType he)

      -- Repair suggestions (OBLIG-4)
      suggestions = case holeInferredType he of
        Just ty | isIntLike aliases ty ->
          map encodeCand (generateCandidates [n | (n, t) <- params, isIntLike aliases t])
        _ -> []

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
    , ooContractedFns       = contracted
    , ooAvailableFns        = available
    , ooSuggestions         = suggestions
    , ooContractedTruncated = contractedT
    , ooAvailableTruncated  = availableT
    , ooParentId        = Nothing
    , ooBranchIndex     = Nothing
    , ooConstructor     = Nothing
    , ooBindings        = []
    }

-- | Assemble contract/precondition/termination obligations from UNSAFE IDs.
assembleConstraintObligations :: [Statement] -> ConstraintTable -> Maybe FQVerifyResult
                              -> TrustReport -> [Text] -> Set Name -> [Int]
                              -> [ObligationObj]
assembleConstraintObligations stmts table mFqResult trustRpt faithful suppressed failedIds =
  mapMaybe mkObl failedIds
  where
    mkObl cid = do
      origin <- Map.lookup cid table
      let fnName  = coFunction origin
          clause  = coClause origin
          kind    = classifyClause clause
          status  = obligationStatus mFqResult fnName kind table suppressed (trRefutedFns trustRpt)
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
        , ooContractedFns       = []
        , ooAvailableFns        = []
        , ooSuggestions         = []
        , ooContractedTruncated = False
        , ooAvailableTruncated  = False
        , ooParentId        = Nothing
        , ooBranchIndex     = Nothing
        , ooConstructor     = Nothing
        , ooBindings        = []
        }

    classifyClause c
      | "call-pre:" `T.isPrefixOf` c = PreconditionObligation
      | c == "decreases"             = TerminationObligation
      | otherwise                    = ContractObligation

    clauseChannel c
      | "call-pre:" `T.isPrefixOf` c = "call-pre"
      | c == "decreases"             = "termination"
      | otherwise                    = "contract"

-- | DEMO-COMP (§3.3): assemble per-call-site PreconditionObligation entries on
-- SAFE. A report-level read of the 'call-pre:<callee>' constraints the solver
-- already discharged: one obligation per origin, carrying the call-site
-- 'coJsonPtr' pointer and the callee name. Status is "discharged" (the solver
-- returned SAFE). No new constraint generation — this re-exports existing
-- solved constraints.
assembleSafePreObligations :: [Statement] -> ConstraintTable -> Maybe FQVerifyResult
                           -> TrustReport -> Set Name -> [ObligationObj]
assembleSafePreObligations stmts table mFqResult trustRpt suppressed =
  [ mkPreObl origin
  | origin <- Map.elems table
  , "call-pre:" `T.isPrefixOf` coClause origin
  ]
  where
    mkPreObl origin =
      let fnName  = coFunction origin
          callee  = T.drop (T.length "call-pre:") (coClause origin)
          status  = obligationStatus mFqResult fnName PreconditionObligation
                      table suppressed (trRefutedFns trustRpt)
          backing = deriveBacking table fnName PreconditionObligation
          (mContract, mParams, _) = findFunctionInfo fnName stmts
          params  = fromMaybe [] mParams
          oblId   = normalizeForFingerprint fnName params
                      (mContract >>= contractPost) ("call-pre-" <> callee)
      in ObligationObj
           { ooId              = oblId
           , ooOrigin          = coJsonPtr origin
           , ooKind            = PreconditionObligation
           , ooBacking         = backing
           , ooStatus          = status
           , ooFunction        = fnName
           , ooTypeChannel     = Nothing
           , ooContractChannel = Nothing
           , ooTrustChannel    = Nothing
           , ooContractedFns       = []
           , ooAvailableFns        = []
           , ooSuggestions         = []
           , ooContractedTruncated = False
           , ooAvailableTruncated  = False
           , ooParentId        = Nothing
           , ooBranchIndex     = Nothing
           , ooConstructor     = Nothing
           , ooBindings        = []
           }

-- ---------------------------------------------------------------------------
-- Lookup helpers
-- ---------------------------------------------------------------------------

findFunctionInfo :: Name -> [Statement] -> (Maybe Contract, Maybe [(Name, Type)], Maybe Expr)
findFunctionInfo name stmts = case filter (matchesName name) stmts of
  (SDefLogic _ params _mRet contract body : _) -> (Just contract, Just params, Just body)
  (SLetrec _ params _mRet contract _ body : _) -> (Just contract, Just params, Just body)
  -- LT-INV (v0.11)
  (SDef      _ params _mRet contract body : _) -> (Just contract, Just params, Just body)
  (SDefShell _ params _mRet contract body _ : _) -> (Just contract, Just params, Just body)
  -- v0.12.1
  (SDefInvariant _ params _mRet contract body : _) -> (Just contract, Just params, Just body)
  _ -> (Nothing, Nothing, Nothing)
  where
    matchesName n (SDefLogic nm _ _ _ _)    = nm == n
    matchesName n (SLetrec nm _ _ _ _ _)    = nm == n
    -- LT-INV (v0.11)
    matchesName n (SDef      nm _ _ _ _)    = nm == n
    matchesName n (SDefShell nm _ _ _ _ _)    = nm == n
    -- v0.12.1
    matchesName n (SDefInvariant nm _ _ _ _) = nm == n
    matchesName _ _                         = False

findTrustEntry :: Name -> TrustReport -> Maybe TrustEntry
findTrustEntry name tr = case filter (\e -> teName e == name) (trEntries tr) of
  (e:_) -> Just e
  []    -> Nothing

paramToScope :: (Name, Type) -> Value
paramToScope (n, ty) = object ["name" .= n, "type" .= typeLabel ty, "source" .= ("param" :: Text)]

emptyContract :: Contract
emptyContract = Contract Nothing Nothing Nothing Nothing Nothing

-- | OBLIG-1: per-hole contract brief for @llmll checkout@. Shares the exact
-- primitives 'mkHoleObl' uses (enclosingFunc / findFunctionInfo /
-- collectHoleGuards / exprToSExpr) so the checkout path and the obligation
-- report agree by construction. Given the hole's normalized JSON pointer and
-- its name, returns @(precondition, postcondition-goal, path-condition guard
-- texts)@ for the enclosing function. Pure: no constraint emission, no solver.
holeContractBrief :: [Statement] -> Text -> Text -> (Maybe Text, Maybe Text, [Text])
holeContractBrief stmts pointer holeNm =
  case enclosingFunc pointer stmts of
    Nothing -> (Nothing, Nothing, [])
    Just fnName ->
      let (mContract, mParams, mBody) = findFunctionInfo fnName stmts
          contract = fromMaybe emptyContract mContract
          params   = fromMaybe [] mParams
          aliases  = buildAliasMap stmts
          sortEnv  = buildSortEnv aliases params
          guards   = collectHoleGuards Map.empty sortEnv
                       (fromMaybe (ELit (LitBool True)) mBody)
          hName    = T.dropWhile (== '?') holeNm
          myGuards = fromMaybe [] (lookup hName guards)
      in ( fmap exprToSExpr (contractPre contract)
         , fmap exprToSExpr (contractPost contract)
         , map peGuard (take 16 myGuards)
         )

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
  , "refuted_fns"    .= orRefutedFns r
  , "effect_summary" .= encodeEffectSummary (orEffectSummary r)
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
    ++ [ "contracted_functions"           .= ooContractedFns o
       , "contracted_functions_truncated" .= ooContractedTruncated o
       , "available_functions"            .= ooAvailableFns o
       , "available_functions_truncated"  .= ooAvailableTruncated o
       , "suggestions"                    .= ooSuggestions o
       ]
    ++ case ooKind o of
         BranchObligation ->
           [ "parent_id"    .= ooParentId o
           , "branch_index" .= ooBranchIndex o
           , "constructor"  .= ooConstructor o
           , "bindings"     .= ooBindings o
           ]
         _ -> []

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
encodeTrustCh tr = object $
  [ "assumptions"     .= trAssumptions tr
  , "effective_level" .= trEffectiveLevel tr
  , "body_faithful"   .= trBodyFaithful tr
  ]
  -- INT-1 (v0.10.8): emit only when True so non-tainted obligations preserve
  -- their pre-v0.10.8 trust-channel JSON byte-identically.
  ++ [ "overflow_tainted" .= True | trOverflowTainted tr ]

encodeSummary :: ReportSummary -> Value
encodeSummary s = object
  [ "total"      .= rsTotal s
  , "open"       .= rsOpen s
  , "discharged" .= rsDischarged s
  , "deferred"   .= rsDeferred s
  , "asserted"   .= rsAsserted s
  , "refuted"    .= rsRefuted s
  ]
