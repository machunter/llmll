{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- |
-- Module      : LLMLL.RefineReuse
-- Description : REFINE-REUSE — reuse-retrieval for cascading `refine`.
--
-- A NON-REJECTING retrieval/hygiene facility (design:
-- @docs/design/refine-reuse-gate-proposal.md@, Rev 1 — settled). For each
-- contracted sub-hole a `refine` SPAWNS, it surfaces in-scope @def@/@def-shell@s
-- whose contract SUBSUMES the spawned one, as an advisory @reuse_suggestions@
-- output field, plus a non-blocking @W-REUSE@ on an exact contract-equivalent.
-- It never blocks a well-formed refine; it is orthogonal to the CDP vacuity gate.
--
-- Subsumption is CONTRACT SUBTYPING (behavioral subtyping, Liskov-Wing
-- TOPLAS'94; Zaremski-Wing plug-in/exact match, TOSEM'97). A candidate @D@ with
-- contract @(pre_D, post_D)@ subsumes a spawned @Cs = (pre_s, post_s)@ iff:
--
--   * @pre_s ⟹ pre_D@   (contravariant precondition — D accepts at least as much)
--   * @post_D ⟹ post_s@ (covariant  postcondition — D promises at least as much)
--
-- Both are emitted as TWO standalone liquid-fixpoint refinement-subtyping Horn
-- constraints over the α-normalized binders (the same implication shape as the
-- COMP-4(b) payload-subtyping emitter, but a BARE two-constraint @.fq@). Both
-- SAT ⇒ D subsumes Cs. Exact-equivalence (both directions) is caught cheaply by
-- an α-normalized canonical-contract key, with no solver call.
--
-- α-normalization renames BOTH contracts' parameters POSITIONALLY to @p0..pn@ in
-- declaration order and both result binders to @v@ before comparison, so blind
-- sub-trees' divergent parameter naming does not defeat matching (professor
-- hazard 4). The candidates are same-scope in-scope defs, so free symbols
-- resolve in the common scope.
module LLMLL.RefineReuse
  ( -- * Advisory output
    ReuseSuggestion(..)
    -- * Driver
  , DefContract
  , reuseRetrieval
    -- * Pure building blocks (exported for testing)
  , signatureCompatible
  , alphaNormalizeContract
  , canonicalContractKey
  , buildSubsumptionFQ
    -- * Solver-backed single check (exported for testing)
  , solveSubsumptionFQ
  , contractSubsumes
  ) where

import           Data.Maybe (fromMaybe, catMaybes)
import           Control.Monad (forM)
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Map.Strict as Map
import           Data.Aeson (ToJSON(..), object, (.=))
import           System.Directory (getTemporaryDirectory, removeFile)
import           System.IO (openTempFile, hClose)
import           System.Process (readProcessWithExitCode)
import           Control.Exception (catch, IOException)

import           LLMLL.Syntax
  ( Name, Type(..), Expr(..), Contract(..) )
import           LLMLL.FixpointIR
  ( FQFile(..), FQBind(..), FQReft(..), FQConstraint(..)
  , FQPred(..), emptyFQFile, emitFQFile )
import           LLMLL.FixpointEmit (AliasMap, typeToSortA, exprToPred, contractMentionsArrOp)
import           LLMLL.ObligationAssembly (substExpr, classifyContractFragment)
import           LLMLL.PBT (canonicalExpr)
import           LLMLL.DiagnosticFQ
  ( FQVerifyResult(..), parseFQResult, parseFQResultJSON )

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A def with its positional signature and contract: the unit both the
-- spawned sub-holes and the candidate pool are projected to.
-- (name, params, return-type, contract)
type DefContract = (Name, [(Name, Type)], Maybe Type, Contract)

-- | One advisory reuse suggestion attached to a `refine` success. Additive;
-- never blocks. @rsRelation@ is @"subsumes"@ (plug-in match — solver-backed) or
-- @"exact-equivalent"@ (canonical-key match — also raises a non-blocking
-- @W-REUSE@).
data ReuseSuggestion = ReuseSuggestion
  { rsSpawned   :: Name   -- ^ the spawned sub-contract's def name
  , rsCandidate :: Name   -- ^ the in-scope def that subsumes it (the reuse target)
  , rsRelation  :: Text   -- ^ "subsumes" | "exact-equivalent"
  } deriving (Show, Eq)

instance ToJSON ReuseSuggestion where
  toJSON r = object
    [ "spawned_contract" .= rsSpawned r
    , "reuse"            .= rsCandidate r
    , "relation"         .= rsRelation r
    ]

-- ---------------------------------------------------------------------------
-- α-normalization
-- ---------------------------------------------------------------------------

-- | Positional α-rename map: each parameter → @p0..pn@ in declaration order,
-- and the result binder @result@ → @v@ (unless a parameter is itself named
-- @result@, in which case the parameter mapping wins — the postcondition result
-- binder cannot then be normalized, a pathological input the QF-LIA gate does
-- not otherwise reject).
alphaRenameMap :: [(Name, Type)] -> Map.Map Name Expr
alphaRenameMap params =
  let pm = Map.fromList [ (pn, EVar ("p" <> tshow i))
                        | (i, (pn, _)) <- zip [0 :: Int ..] params ]
  in if Map.member "result" pm then pm else Map.insert "result" (EVar "v") pm

-- | α-normalize a contract's pre/post to the shared @p0..pn@ / @v@ binders.
alphaNormalizeContract :: [(Name, Type)] -> Contract -> (Maybe Expr, Maybe Expr)
alphaNormalizeContract params c =
  let m = alphaRenameMap params
  in ( fmap (substExpr m) (contractPre c)
     , fmap (substExpr m) (contractPost c) )

-- | Normalize operator representation for the canonical key. The parser may
-- emit an operator as either 'EOp' or 'EApp'; 'canonicalExpr' distinguishes
-- them, so rewrite 'EOp' → 'EApp' (they are semantically identical in a
-- contract, and 'exprToPred' already collapses them on the solver path) so the
-- exact-match key does not spuriously split on surface representation.
normOps :: Expr -> Expr
normOps (EOp n args) = EApp n (map normOps args)
normOps (EApp n args) = EApp n (map normOps args)
normOps (EIf a b c)  = EIf (normOps a) (normOps b) (normOps c)
normOps e            = e

-- ---------------------------------------------------------------------------
-- Canonical-contract key (exact-match index — no solver)
-- ---------------------------------------------------------------------------

-- | An α-normalized normal-form key for a contract. Two contracts with equal
-- keys are exact-equivalent (sound-but-incomplete: it catches
-- syntactic-after-normalization equality, not full semantic equality, which the
-- solver-backed subsumption path covers). Compared only among
-- signature-compatible candidates, so the key is predicate-only.
canonicalContractKey :: [(Name, Type)] -> Contract -> Text
canonicalContractKey params c =
  let (pre, post) = alphaNormalizeContract params c
      key = maybe "T" (canonicalExpr . normOps)
  in key pre <> " | " <> key post

-- ---------------------------------------------------------------------------
-- Signature pre-filter (cost lever — no solver)
-- ---------------------------------------------------------------------------

-- | Cheap boolean gate: equal arity AND positional param sort-vector match AND
-- result sort match, after alias resolution. Only survivors reach the key
-- compare or the solver.
signatureCompatible :: AliasMap
                    -> ([(Name, Type)], Maybe Type)
                    -> ([(Name, Type)], Maybe Type)
                    -> Bool
signatureCompatible aliases (psA, rA) (psB, rB) =
     length psA == length psB
  && and (zipWith (\(_, ta) (_, tb) -> srt ta == srt tb) psA psB)
  && srtR rA == srtR rB
  where
    srt  = typeToSortA aliases
    srtR = srt . fromMaybe TUnit

-- ---------------------------------------------------------------------------
-- Subsumption solve (bare two-constraint .fq)
-- ---------------------------------------------------------------------------

-- | Build the BARE two-constraint refinement-subtyping @.fq@ that decides
-- whether candidate @D@ subsumes spawned @Cs@. Both contracts are α-normalized
-- to shared @p0..pn@ / @v@; the parameter binders take the spawned contract's
-- sorts (equal to the candidate's by the signature pre-filter). Returns
-- 'Nothing' if either predicate escapes QF-LIA ('exprToPred' fails) — the
-- caller then abstains (advisory-only, no obligation).
--
-- Constraint 1 (pre, contravariant):  @∀p̄.   pre_s ⟹ pre_D@
-- Constraint 2 (post, covariant):     @∀p̄,v. post_D ⟹ post_s@
--
-- Both SAT (the whole @.fq@ is @Safe@) ⇒ D subsumes Cs.
buildSubsumptionFQ :: AliasMap
                   -> ([(Name, Type)], Maybe Type, Contract)  -- ^ spawned Cs
                   -> ([(Name, Type)], Maybe Type, Contract)  -- ^ candidate D
                   -> Maybe FQFile
buildSubsumptionFQ aliases (sPs, sRet, sC) (dPs, _dRet, dC) = do
  let (preS, postS) = alphaNormalizeContract sPs sC
      (preD, postD) = alphaNormalizeContract dPs dC
      toFQ = maybe (Just FQTrue) exprToPred
  preSfq  <- toFQ preS
  preDfq  <- toFQ preD
  postSfq <- toFQ postS
  postDfq <- toFQ postD
  let retSort = typeToSortA aliases (fromMaybe TUnit sRet)
      binds   = [ FQBind i ("p" <> tshow i) (FQReft "v" (typeToSortA aliases t) FQTrue)
                | (i, (_, t)) <- zip [0 :: Int ..] sPs ]
      envIds  = map bindId binds
      -- pre:  ∀p̄. pre_s ⟹ pre_D   (contravariant precondition)
      cPre  = FQConstraint 1 envIds (FQReft "v" retSort preSfq)  (FQReft "v" retSort preDfq)  ["reuse", "pre"]
      -- post: ∀p̄,v. post_D ⟹ post_s (covariant postcondition; v is the result)
      cPost = FQConstraint 2 envIds (FQReft "v" retSort postDfq) (FQReft "v" retSort postSfq) ["reuse", "post"]
  pure emptyFQFile { fqBinds = binds, fqConstraints = [cPre, cPost] }

-- | Run liquid-fixpoint on a bare subsumption @.fq@ and return its verdict.
-- Writes to a unique temp file (removed after), mirroring the PatchApply solve.
solveSubsumptionFQ :: FilePath -> FQFile -> IO FQVerifyResult
solveSubsumptionFQ lfBin fq = do
  tmpDir     <- getTemporaryDirectory
  (path, h)  <- openTempFile tmpDir "llmll-reuse.fq"
  TIO.hPutStr h (emitFQFile fq)
  hClose h
  (_, out, err) <- readProcessWithExitCode lfBin ["-q", "--json", path] ""
  removeFile path `catch` \(_ :: IOException) -> pure ()
  let merged = T.pack out <> T.pack err
  pure (fromMaybe (parseFQResult merged) (parseFQResultJSON merged))

-- | Solver-backed subsumption check: does candidate @D@ subsume spawned @Cs@?
-- Abstains ('False') when the constraint cannot be built (non-QF-LIA) or the
-- solver does not return @Safe@ (Unsafe, or a solver error — fail-safe: a
-- solver hiccup degrades a suggestion, never a program).
contractSubsumes :: FilePath -> AliasMap -> DefContract -> DefContract -> IO Bool
contractSubsumes lfBin aliases (_, sPs, sRet, sC) (_, dPs, dRet, dC) =
  case buildSubsumptionFQ aliases (sPs, sRet, sC) (dPs, dRet, dC) of
    Nothing -> pure False
    Just fq -> do
      r <- solveSubsumptionFQ lfBin fq
      pure $ case r of FQSafe -> True; _ -> False

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------

-- | The advisory reuse-retrieval pass. For each spawned sub-contract, surface
-- the in-scope candidates that subsume it. NON-REJECTING: returns suggestions
-- only; the caller attaches them to the refine success and derives @W-REUSE@
-- from the @"exact-equivalent"@ rows. Graceful skip: with no solver
-- (@mLF == Nothing@) only the no-solver exact-key tier runs, so subsumption
-- (but not exact-equivalence) suggestions are dropped.
--
-- Per (spawned Cs, candidate D): skip self; require signature-compatible; skip
-- unless BOTH contracts are QF-LIA; then exact-key match ⇒ @exact-equivalent@
-- (no solver), else the bare-@.fq@ subsumption solve ⇒ @subsumes@.
reuseRetrieval :: Maybe FilePath      -- ^ liquid-fixpoint binary, or Nothing (skip solver tier)
               -> AliasMap
               -> [DefContract]       -- ^ spawned sub-contracts (Cs)
               -> [DefContract]       -- ^ candidate pool (in-scope defs)
               -> IO [ReuseSuggestion]
reuseRetrieval mLF aliases spawned pool =
  fmap concat $ forM spawned $ \s@(sn, sPs, sRet, sC) ->
    if not (qfContract sC) then pure []
    else fmap catMaybes $ forM pool $ \d@(dn, dPs, dRet, dC) ->
      if sn == dn
        then pure Nothing
      else if not (signatureCompatible aliases (sPs, sRet) (dPs, dRet))
        then pure Nothing
      else if not (qfContract dC)
        then pure Nothing
      else if canonicalContractKey sPs sC == canonicalContractKey dPs dC
        then pure (Just (ReuseSuggestion sn dn "exact-equivalent"))
      else case mLF of
             Nothing -> pure Nothing
             Just lf -> do
               ok <- contractSubsumes lf aliases s d
               pure (if ok then Just (ReuseSuggestion sn dn "subsumes") else Nothing)
  where
    -- Only QF-LIA contracts reach the solver; a fully-absent or Lean-escaping
    -- contract abstains (no suggestion). classifyContractFragment returns
    -- "qf_lia" when at least one clause is present and both are QF-LIA — it
    -- recognizes the parser's EOp operator form directly (since CLASSIFY-EOP).
    -- LEVER-A3: array-op contracts now classify in-fragment, but THIS driver
    -- cannot discharge them — its standalone Horn constraints sort binders via
    -- typeToSortA (FQInt for bytes/map, no $has/$val component splitting), so
    -- an array term would emit ill-sorted or free. Abstain on them here — a
    -- driver limitation, not a classification: reuse retrieval over array
    -- contracts is an A3.x follow-on (needs the A2 splitting discipline).
    qfContract c = classifyContractFragment c == "qf_lia"
                   && not (contractMentionsArrOp c)

-- ---------------------------------------------------------------------------
-- local helper
-- ---------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = T.pack . show
