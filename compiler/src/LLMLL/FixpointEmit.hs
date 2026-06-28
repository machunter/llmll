{-# LANGUAGE FlexibleContexts #-}
-- |
-- Module      : LLMLL.FixpointEmit
-- Description : Walk LLMLL typed AST → .fq constraint file + ConstraintTable.
--
-- D4: Decoupled verification backend.
--
-- Coverage: QF linear integer arithmetic only.
--   - Integer params / return types
--   - Linear pre/post predicates (+, -, =, <, <=, >=, >)
--   - Simple letrec termination measures (single-variable or constant)
--   - TSumType sort declarations
--
-- Non-linear sites (HProofRequired holes from D3) are skipped — the compiler
-- already flagged them; the verifier simply omits them from the .fq output.
--
-- FAITHFULNESS INVARIANT (v0.3, updated v0.8.0):
-- This module's output is trusted by --contracts=unproven. If emitFixpoint
-- reports SAFE for a contract, the runtime assertion for that contract must
-- be semantically redundant for all well-typed inputs. Any extension to
-- exprToPred must preserve this invariant: never translate a contract to a
-- weaker .fq constraint that the solver accepts trivially.
--
-- BODY-VC (v0.8.0):
-- When EmitOptions.emitBodyVCs is True, function bodies in the supported
-- QF-LIA fragment are translated to verification conditions via bodyToPredM.
-- Body VCs prove: P ∧ (result = ⟦body⟧) ⟹ Q (postcondition faithfulness).
-- Functions outside the fragment fall back to contract-only verification.
--
-- COMPOSITIONAL VERIFICATION (v0.9.0, COMP-0 Rev 2):
-- When a function f calls a contracted function g, the emitter uses
-- assume-guarantee reasoning: f must PROVE g's precondition (obligation)
-- and may ASSUME g's postcondition (hypothesis). Recursive functions'
-- own body VCs are excluded; callers may use assume-guarantee against
-- recursive functions' contracts with trust degradation via evidenceMeet.

module LLMLL.FixpointEmit
  ( -- * Top-level emitter
    emitFixpoint
  , emitFixpointWith
    -- * Configuration
  , EmitOptions(..)
  , defaultEmitOptions
    -- * Result
  , EmitResult(..)
    -- * Alias map (v0.8.0)
  , AliasMap
  , buildAliasMap
  , isIntLike
    -- * Body-VC types (exported for testing)
  , BodyVC(..)
  , LetBinding(..)
  , FlatPath
  , SortEnv
    -- * Compositional verification (v0.9.0)
  , ContractEnv
  , buildContractEnv
  , buildContractEnvWithImports  -- v0.10 MOD-1
  , augmentContractPost          -- DEF-RET Unit 2: return-refinement → effective post
  , buildSortEnv                 -- v0.10 (Language Team Correction 1)
  , applySubst
  , isConstructorDependent
  , collectCallPreObligations
    -- * Body-VC engine (exported for testing)
  , bodyToPredFrom
  , bodyToPredFromR
  , flattenBodyVC
  , pathBranchSides              -- COMP-3b-general: structural branch provenance (localization)
  , collectBranchBinders         -- COMP-3b-general: match-binder tree-walk
  , collectCallSites             -- COMP-4 (b): call sites for payload-subtyping
  , payloadRefinement            -- COMP-4 (b): payload type → (bindingVar, pred)
  , payloadArms                  -- COMP-4 (b): two-arm payload types per arm key
  , countPathsBounded
    -- * Contract translation (exported for testing)
  , exprToPred
    -- * COMP-3b-general Phase 1 (exported for testing)
  , desugarCtorValues
  , buildCtorTagMap
    -- * INT-1 (v0.10.8): overflow taint scan
  , bodyHasOverflowArith
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.IORef
import Data.Maybe (fromMaybe, mapMaybe, isJust, catMaybes)
import Data.List (nub, partition)
import Control.Monad (forM_, forM, when, unless)
import Control.Monad.State.Strict (State, evalState, get, put, MonadState)
import Control.Monad.Reader (ReaderT, runReaderT, ask, lift)
import Data.Graph (stronglyConnComp, SCC(..))

import LLMLL.Syntax
import LLMLL.FixpointIR
import LLMLL.DiagnosticFQ (ConstraintOrigin(..), ConstraintTable)
import LLMLL.Diagnostic (Diagnostic, mkWarning)
import LLMLL.HoleAnalysis (buildCallGraph)
import LLMLL.GuardClassifier (classifyGuardM, lookupPredOp, lookupArithOp)

-- ---------------------------------------------------------------------------
-- Configuration (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Options controlling what the emitter generates.
data EmitOptions = EmitOptions
  { emitBodyVCs :: Bool   -- ^ Emit body-faithful verification conditions
  } deriving (Show, Eq)

defaultEmitOptions :: EmitOptions
defaultEmitOptions = EmitOptions { emitBodyVCs = False }

-- ---------------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------------

data EmitResult = EmitResult
  { erFQFile            :: FQFile           -- ^ the assembled .fq data structure
  , erFQText            :: Text             -- ^ .fq text ready to write to disk
  , erConstraintTable   :: ConstraintTable  -- ^ ID → origin (for DiagnosticFQ)
  , erSkipped           :: [Text]           -- ^ names of skipped non-linear functions
  , erBodyFaithfulFns   :: [Text]           -- ^ v0.8.0: functions with successful body VCs
  , erBodyFallback      :: [Text]           -- ^ v0.8.0: functions that fell back
  , erDiagnostics       :: [Diagnostic]     -- ^ v0.8.0: path-limit warnings, etc.
  , erEmittedPre        :: [Text]           -- ^ v0.8.0: functions whose pre emitted a constraint
  , erEmittedPost       :: [Text]           -- ^ v0.8.0: functions whose post emitted a constraint
  , erCallPreFns        :: [Text]           -- ^ v0.9.0: functions that emitted call-pre obligations
  , erOverflowTaintedFns :: [Text]          -- ^ INT-1 (v0.10.8): body-faithful fns whose body uses unbounded-Int arithmetic
  } deriving (Show)

-- ---------------------------------------------------------------------------
-- Body-VC types (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Sort environment: maps variable names to their FQ sorts.
-- Used by bodyToPredM to reject non-int vars in the QF-LIA fragment.
type SortEnv = Map Name FQSort

-- | A body verification condition tree.
data BodyVC
  = SimpleVC [LetBinding] FQPred
    -- ^ A straight-line sequence of let-bindings followed by a result predicate
  | BranchVC FQPred [(Name, FQSort, FQPred)] BodyVC BodyVC
    -- ^ A two-way branch: guard; binders INTRODUCED at this node (the synthetic
    --   match guard + arm payloads for a Result elimination, each later declared
    --   at trivial refinement FQTrue by 'collectBranchBinders'; empty @[]@ for an
    --   if-then-else or a hoisted branch); then-VC; else-VC.
  | CallVC                               -- ^ v0.9.0: Compositional call site
    { cvCallee         :: Name           -- ^ callee function name
    , cvArgs           :: [FQPred]       -- ^ translated argument predicates
    , cvPreObligation  :: Maybe FQPred   -- ^ callee pre after substitution (PROVE polarity)
    , cvPostAssumption :: Maybe FQPred   -- ^ callee post after substitution (ASSUME polarity)
    , cvResultVar      :: Name           -- ^ fresh result variable (_call_g_N)
    , cvResultSort     :: FQSort         -- ^ sort of the result
    , cvContinuation   :: BodyVC         -- ^ rest of the body after the call
    }
  deriving (Show, Eq)

-- | A single let-binding in the body VC.
data LetBinding = LetBinding
  { lbName :: Text     -- ^ Alpha-renamed variable name
  , lbSort :: FQSort   -- ^ Sort of the binding
  , lbRhs  :: FQPred   -- ^ RHS predicate (what the variable equals)
  } deriving (Show, Eq)

-- | A flattened path through the body-VC tree:
-- (path guard conjunction, accumulated let-bindings, result predicate)
type FlatPath = (FQPred, [LetBinding], FQPred)

-- ---------------------------------------------------------------------------
-- Compositional verification types (v0.9.0 COMP-1)
-- ---------------------------------------------------------------------------

-- | Contract environment: maps function names to their parameter lists,
-- contracts, and optional return type annotations.
-- Return type is needed for EMatch sort derivation (COMP-0 §5.3, Issue 5).
type ContractEnv = Map Name ([(Name, Type)], Contract, Maybe Type)

-- | Build a ContractEnv from top-level statements.
buildContractEnv :: [Statement] -> ContractEnv
buildContractEnv stmts = Map.fromList $ mapMaybe go stmts
  where
    -- NIW (v0.12, F-NIW-1): fold refinement-aliased param predicates into each
    -- contract's effective precondition, so call-pre obligations prove them at
    -- call sites (intro-side). Uses the alias map from the same statement set.
    am = buildAliasMap stmts
    -- DEF-RET Unit 2: fold the return refinement into the EXPORTED post (the
    -- caller-assumable guarantee, consumed via assume-guarantee), the dual of
    -- the param-refinement pre fold. Unconditional/syntactic; verdict-gating is
    -- the downstream trust closure (refutedClosure / asserted-floor meet).
    ctorTags = buildCtorTagMap am
    -- COMP-3c / COMP-3b-general (cenv-desugar fix): desugar nullary-enum
    -- constructors in the STORED contract, not just at the definition site
    -- (emitFnConstraints, ~:415-419). The ContractEnv is consumed by CALLERS via
    -- assume-guarantee (CallVC); without this, a caller of a function whose contract
    -- uses nullary-enum constructors pulls them RAW into its .fq → liquid-fixpoint
    -- "Constraint with free vars" crash. The per-function bound-set (params)
    -- preserves shadowing, exactly as the definition-site desugar does.
    dsContract params c =
      let ds = desugarCtorValues ctorTags (Set.fromList (map fst params))
      in c { contractPre = ds <$> contractPre c, contractPost = ds <$> contractPost c }
    aug params mRet c = dsContract params (augmentContractPost am mRet (augmentContractPre am params c))
    go (SDefLogic name params mRet contract _) = Just (name, (params, aug params mRet contract, mRet))
    go (SLetrec name params mRet contract _ _) = Just (name, (params, aug params mRet contract, mRet))
    -- LT-INV (v0.11)
    go (SDef      name params mRet contract _) = Just (name, (params, aug params mRet contract, mRet))
    go (SDefShell name params mRet contract _) = Just (name, (params, aug params mRet contract, mRet))
    -- v0.12.1: def-invariant registers in the VC env identically to SDefLogic.
    go (SDefInvariant name params mRet contract _) = Just (name, (params, aug params mRet contract, mRet))
    go _ = Nothing

-- | v0.10 MOD-1: Build a ContractEnv merging local contracts with imported
-- module contracts from the ModuleCache. Local contracts shadow imports
-- (Map.union has left-bias). This is the entry point for cross-module
-- compositional verification in OBLIG-2.
buildContractEnvWithImports :: [Statement] -> Map ModulePath ModuleEnv -> ContractEnv
buildContractEnvWithImports stmts cache =
  let localContracts    = buildContractEnv stmts
      importedContracts = Map.foldl' (\acc menv -> Map.union acc (meContracts menv))
                                     Map.empty cache
  -- Local contracts shadow imported contracts (name collision resolution).
  in Map.union localContracts importedContracts

-- ---------------------------------------------------------------------------
-- Built-in qualifier safety net
-- ---------------------------------------------------------------------------

builtinQualifiers :: [FQQualifier]
builtinQualifiers =
  [ FQQualifier "True"  [("v", FQInt)]                       FQTrue
  , FQQualifier "GEZ"   [("v", FQInt)]                       (FQBinPred FQGe (FQVar "v") (FQLit 0))
  , FQQualifier "GTZ"   [("v", FQInt)]                       (FQBinPred FQGt (FQVar "v") (FQLit 0))
  , FQQualifier "EqZ"   [("v", FQInt)]                       (FQBinPred FQEq (FQVar "v") (FQLit 0))
  , FQQualifier "Eq"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQEq (FQVar "v") (FQVar "w"))
  , FQQualifier "GE"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQGe (FQVar "v") (FQVar "w"))
  , FQQualifier "GT"    [("v", FQInt), ("w", FQInt)]         (FQBinPred FQGt (FQVar "v") (FQVar "w"))
  ]

-- ---------------------------------------------------------------------------
-- Top-level emitter
-- ---------------------------------------------------------------------------

-- | Walk a list of top-level statements and emit a .fq constraint file.
-- The function is pure in terms of result, but uses IORef internally for
-- the sequential constraint-ID counter and ConstraintTable accumulator.
-- | Emit constraints using default options (no body VCs).
emitFixpoint :: FilePath -> [Statement] -> IO EmitResult
emitFixpoint = emitFixpointWith defaultEmitOptions

-- | Emit constraints with explicit options.
emitFixpointWith :: EmitOptions -> FilePath -> [Statement] -> IO EmitResult
emitFixpointWith opts srcFile stmts = do
  -- v0.8.0: build alias map from STypeDef statements for isIntLike resolution
  let aliases = buildAliasMap stmts
  -- v0.9.0: build contract environment and SCC set for compositional verification
  let cenv = buildContractEnv stmts
      callGraph = buildCallGraph stmts
      sccs = stronglyConnComp
        [(name, name, deps) | (name, deps) <- Map.toList callGraph]
      recursiveNames = Set.fromList $ concatMap getRecursive sccs
        where
          getRecursive (AcyclicSCC _) = []
          getRecursive (CyclicSCC ns) = ns
  ctrRef    <- newIORef (0 :: Int)  -- constraint ID counter
  bindRef   <- newIORef (0 :: Int)  -- binder ID counter
  tableRef  <- newIORef (Map.empty :: ConstraintTable)
  skippedRef<- newIORef ([] :: [Text])
  bindsRef  <- newIORef ([] :: [FQBind])
  constsRef <- newIORef ([] :: [FQConstraint])
  qualsRef  <- newIORef builtinQualifiers
  dataRef   <- newIORef ([] :: [FQDataDecl])
  -- v0.8.0: body-VC global alpha-renaming counter (E08: shared across functions)
  bodyCounterRef <- newIORef (0 :: Int)
  bodyFaithfulRef <- newIORef ([] :: [Text])
  bodyFallbackRef <- newIORef ([] :: [Text])
  diagsRef <- newIORef ([] :: [Diagnostic])
  emittedPreRef <- newIORef ([] :: [Text])
  emittedPostRef <- newIORef ([] :: [Text])
  callPreRef <- newIORef ([] :: [Text])  -- v0.9.0: functions with call-pre obligations
  overflowTaintedRef <- newIORef ([] :: [Text])  -- INT-1: body-faithful fns with unbounded-Int arithmetic

  let freshCid = do
        n <- readIORef ctrRef
        modifyIORef' ctrRef (+1)
        return n

  let freshBid = do
        n <- readIORef bindRef
        modifyIORef' bindRef (+1)
        return n

  let addBind b   = modifyIORef' bindsRef (++ [b])
  -- NIW (v0.12): inject ground measure range facts (m t >= 0) per occurring
  -- measure-term at the single point all constraints flow through. No-op when a
  -- constraint contains no FQApp, so measure-free .fq output is byte-identical.
  let addConst c  = modifyIORef' constsRef (++ [injectRangeFacts c])
  let addQuals qs = modifyIORef' qualsRef (++ qs)
  let addData  d  = modifyIORef' dataRef  (++ [d])
  let addSkip  n  = modifyIORef' skippedRef (++ [n])
  let addOrigin cid orig = modifyIORef' tableRef (Map.insert cid orig)
  let addBodyFaithful n = modifyIORef' bodyFaithfulRef (++ [n])
  let addBodyFallback n = modifyIORef' bodyFallbackRef (++ [n])
  let addDiag d = modifyIORef' diagsRef (++ [d])
  let addEmittedPre n = modifyIORef' emittedPreRef (++ [n])
  let addEmittedPost n = modifyIORef' emittedPostRef (++ [n])
  let addCallPre n = modifyIORef' callPreRef (++ [n])  -- v0.9.0
  let addOverflowTainted n = modifyIORef' overflowTaintedRef (++ [n])  -- INT-1

  -- Process each statement
  forM_ (zip [0..] stmts) $ \(idx, stmt) ->
    case stmt of
      STypeDef name body ->
        -- Emit ADT sorts for TSumType members
        forM_ (typeSorts name body) addData

      SDefLogic name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames
          name params mRet contract (Just body) Nothing idx

      SLetrec name params mRet contract dec body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames
          name params mRet contract Nothing (Just dec) idx

      -- LT-INV (v0.11): SDef and SDefShell emit constraints identically to SDefLogic.
      SDef name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames
          name params mRet contract (Just body) Nothing idx

      SDefShell name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames
          name params mRet contract (Just body) Nothing idx

      -- v0.12.1: def-invariant emits constraints identically to SDefLogic.
      SDefInvariant name params mRet contract body ->
        emitFnConstraints opts srcFile freshCid freshBid addBind addConst
          addQuals addSkip addOrigin addBodyFaithful addBodyFallback addDiag
          addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv recursiveNames
          name params mRet contract (Just body) Nothing idx

      _ -> pure ()

  -- Assemble result
  dataDecs  <- readIORef dataRef
  quals     <- readIORef qualsRef
  binds     <- readIORef bindsRef
  consts    <- readIORef constsRef
  table     <- readIORef tableRef
  skipped   <- readIORef skippedRef
  bfaithful <- readIORef bodyFaithfulRef
  bfallback <- readIORef bodyFallbackRef
  diags     <- readIORef diagsRef
  emPre     <- readIORef emittedPreRef
  emPost    <- readIORef emittedPostRef
  callPre   <- readIORef callPreRef
  ovTainted <- readIORef overflowTaintedRef
  -- NIW (v0.12): declare a UF constant for each measure symbol actually used in
  -- any constraint or binder. None used → empty section → byte-identical .fq.
  let usedMeasures = Set.unions $
           [ Set.union (appNames (reftPred (conLhs c))) (appNames (reftPred (conRhs c)))
           | c <- consts ]
        ++ [ appNames (reftPred (bindReft b)) | b <- binds ]
      measureConsts = map measureConstant (Set.toList usedMeasures)
  let fqFile = FQFile measureConsts dataDecs quals binds consts
  return EmitResult
    { erFQFile            = fqFile
    , erFQText            = emitFQFile fqFile
    , erConstraintTable   = table
    , erSkipped           = skipped
    , erBodyFaithfulFns   = bfaithful
    , erBodyFallback      = bfallback
    , erDiagnostics       = diags
    , erEmittedPre        = emPre
    , erEmittedPost       = emPost
    , erCallPreFns        = callPre
    , erOverflowTaintedFns = ovTainted
    }

-- ---------------------------------------------------------------------------
-- Per-function constraint emission
-- ---------------------------------------------------------------------------

emitFnConstraints
  :: EmitOptions
  -> FilePath
  -> IO FQConstraintId    -- fresh constraint ID
  -> IO FQBindId          -- fresh binder ID
  -> (FQBind       -> IO ())
  -> (FQConstraint -> IO ())
  -> ([FQQualifier] -> IO ())
  -> (Text -> IO ())       -- record skipped function
  -> (FQConstraintId -> ConstraintOrigin -> IO ())
  -> (Text -> IO ())       -- record body-faithful function
  -> (Text -> IO ())       -- record body-fallback function
  -> (Diagnostic -> IO ()) -- emit diagnostics
  -> (Text -> IO ())       -- v0.8.0: record emitted pre clause
  -> (Text -> IO ())       -- v0.8.0: record emitted post clause
  -> (Text -> IO ())       -- v0.9.0: record call-pre obligation
  -> (Text -> IO ())       -- INT-1: record overflow-tainted function
  -> IORef Int             -- body-VC alpha-renaming counter
  -> AliasMap              -- v0.8.0: type alias map for isIntLike
  -> ContractEnv           -- v0.9.0: contract environment for compositional VC
  -> Set.Set Name          -- v0.9.0: recursive SCC set
  -> Name
  -> [(Name, Type)]
  -> Maybe Type
  -> Contract
  -> Maybe Expr            -- Just body = function body (Nothing for letrec)
  -> Maybe Expr            -- Just dec = letrec :decreases
  -> Int                   -- statement index (for JSON Pointer)
  -> IO ()
emitFnConstraints opts srcFile freshCid freshBid addBind addConst addQuals
    addSkip addOrigin addBodyFaithful addBodyFallback addDiag
    addEmittedPre addEmittedPost addCallPre addOverflowTainted bodyCounterRef aliases cenv sccSet
    name params mRet contract0 mBody mDec stmtIdx = do

  -- NIW (v0.12, F-NIW-1): fold refinement-aliased param predicates into this
  -- function's own effective precondition, so the body VC assumes them
  -- (elim-side). The intro-side (callers prove them) is handled via the
  -- augmented cenv in buildContractEnv.
  -- DEF-RET Unit 2: dually, fold a refinement-aliased RETURN into the effective
  -- postcondition, so the body VC PROVES it (introduction, §3.4.1). A non-Σ_auto
  -- return refinement makes the augmented post untranslatable → existing
  -- mPostPred=Nothing fallback (the §3.4.5 firewall) — no special guard needed.
  -- COMP-3b-general (Phase 1): desugar nullary-constructor values to int tags in
  -- the contract (and, below, the body) before translation, so an idiomatic enum
  -- function reduces to the int-tag QF-LIA form the verifier already discharges.
  let contractAug = augmentContractPost aliases mRet (augmentContractPre aliases params contract0)
      ctorTags    = buildCtorTagMap aliases
      dsExpr      = desugarCtorValues ctorTags (Set.fromList (map fst params))
      contract    = contractAug { contractPre  = dsExpr <$> contractPre contractAug
                                , contractPost = dsExpr <$> contractPost contractAug }

  -- Only handle integer-typed parameters (linear arithmetic fragment)
  let intParams = [ (n, t) | (n, t) <- params, isIntLike aliases t ]
  -- NIW (v0.12): non-int params used as measure arguments get an opaque carrier
  -- binder so (strLen s) / (listLen xs) resolve to an in-scope symbol. Scoped to
  -- genuinely-used measure args (scan of contract + body) so measure-free
  -- functions emit byte-identical .fq.
  let measureVars = Set.unions
        [ maybe Set.empty measureArgVars (contractPre contract)
        , maybe Set.empty measureArgVars (contractPost contract)
        , maybe Set.empty measureArgVars mBody
        -- F-NIW-2: carrier vars passed as arguments to a measure-refined callee
        -- param need binding too, so the emitted call-pre obligation references
        -- an in-scope symbol (intro-side).
        , maybe Set.empty (collectCallArgCarrierVars aliases cenv) mBody ]
      measureParams = [ (n, t) | (n, t) <- params
                      , n `Set.member` measureVars
                      , isMeasureSort aliases t
                      , not (isIntLike aliases t) ]
  -- v0.8.0: Fix dead early-exit — check condition and exit early if nothing to verify.
  let hasContract = isJust (contractPre contract) || isJust (contractPost contract)
      hasIntParams = not (null intParams)
  -- Only proceed if there are int params or contracts to verify
  if not hasIntParams && not hasContract
    then pure ()
    else do

    -- Emit binders for int params plus any measure-argument carrier params (NIW)
    paramBinds <- mapM (emitParamBind aliases freshBid addBind) (intParams ++ measureParams)
    let envIds = map bindId paramBinds

    -- Emit qualifiers extracted from pre/post
    let preQuals  = maybe [] (extractQualifiers "pre"  name) (contractPre contract)
        postQuals = maybe [] (extractQualifiers "post" name) (contractPost contract)
    addQuals (preQuals ++ postQuals)

    -- Emit standalone pre-condition constraint (legacy, non-body-VC mode only)
    -- v0.8.0: When body VCs are active, standalone pre/post constraints are
    -- suppressed. Body VCs encode the correct proof obligation:
    --   P ∧ (result = ⟦body⟧) ⟹ Q
    -- Standalone constraints (lhs true, rhs P) are not sound proof obligations.
    unless (emitBodyVCs opts) $ case contractPre contract of
      Nothing  -> pure ()
      Just pre ->
        case exprToPred pre of
          Nothing   -> addSkip name  -- non-linear: skip with note
          Just pred -> do
            cid  <- freshCid
            let lhs = FQReft "v" FQInt FQTrue   -- no lhs restriction
                rhs = FQReft "v" FQInt pred
                c   = FQConstraint cid envIds lhs rhs [name, "pre"]
            addConst c
            addEmittedPre name  -- v0.8.0: track that this pre actually emitted
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/pre"
            addOrigin cid (ConstraintOrigin name "pre" ptr srcFile)

    -- Emit standalone post-condition constraint (legacy, non-body-VC mode only)
    unless (emitBodyVCs opts) $ case contractPost contract of
      Nothing   -> pure ()
      Just post ->
        case exprToPred post of
          Nothing   -> addSkip name
          Just pred -> do
            cid    <- freshCid
            -- 'result' binder: type inferred from return annotation
            let retSort = maybe FQInt typeToSort mRet
            rbid   <- freshBid
            let resultBind = FQBind rbid "result" (FQReft "v" retSort FQTrue)
            addBind resultBind
            let lhs = FQReft "result" retSort FQTrue
                rhs = FQReft "result" retSort pred
                c   = FQConstraint cid (envIds ++ [rbid]) lhs rhs [name, "post"]
            addConst c
            addEmittedPost name  -- v0.8.0: track that this post actually emitted
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/post"
            addOrigin cid (ConstraintOrigin name "post" ptr srcFile)

    -- Emit termination constraint for letrec :decreases
    case mDec of
      Nothing  -> pure ()
      Just dec ->
        case exprToPred dec of
          Nothing   -> addSkip name  -- complex decrease: D3 already flagged ?proof-required
          Just decPred -> do
            cid  <- freshCid
            -- well-foundedness: decreases >= 0 (necessary condition for termination)
            let lhs = FQReft "v" FQInt decPred
                rhs = FQReft "v" FQInt (FQBinPred FQGe (FQVar "v") (FQLit 0))
                c   = FQConstraint cid envIds lhs rhs [name, "decreases"]
            addConst c
            let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/decreases"
            addOrigin cid (ConstraintOrigin name "decreases" ptr srcFile)

    -- v0.8.0: Emit body-faithful verification conditions
    -- Body VCs prove: P ∧ (result = ⟦body⟧) ⟹ Q
    when (emitBodyVCs opts) $ case mBody of
      Nothing -> pure ()  -- letrec: no body VC (recursive, excluded from BODY-VC-0)
      Just body -> do
        -- Fallback policy (§0.7): require translatable post. If pre exists, it must
        -- also be translatable, otherwise fallback conservatively.
        -- DEF-RET Unit 2: `contract` here already has the return refinement folded
        -- into its post (augmentContractPost above), so a refinement-aliased return
        -- is proven as part of the post goal. A non-Σ_auto return refinement makes
        -- this post untranslatable → mPostPred=Nothing → fallback (§3.4.5 firewall),
        -- exactly the Unit-1 conservative behavior, now via the existing path.
        let mPostPred = contractPost contract >>= exprToPred
            mPrePred  = case contractPre contract of
                          Nothing  -> Just Nothing       -- no pre is fine
                          Just pre -> case exprToPred pre of
                                        Nothing -> Nothing    -- pre exists but untranslatable → fallback
                                        Just p  -> Just (Just p)
        case (mPostPred, mPrePred) of
          (Nothing, _) -> addBodyFallback name  -- no translatable post → fallback
          (_, Nothing) -> addBodyFallback name  -- untranslatable pre → fallback
          (Just postPred, Just mPre) -> do
            -- Build SortEnv from int-typed parameters
            let body' = dsExpr body  -- COMP-3b-general: desugar enum match + ctor values
            -- COMP-3b-general (opaque-sum elimination): a Result-typed *variable*
            -- scrutinee (param or let-bound) is opaque to the int-only SortEnv, so
            -- the generic EMatch path cannot resolve its arm payload sorts. Seed the
            -- SortEnv with derived payload-sort keys ("<v>$ok"/"<v>$err"; '$' is not
            -- a legal source identifier char, so these cannot collide) for every
            -- Result-typed param; the EMatch case reads them to build the branch at
            -- ANY nesting depth (not just top level). The match guard and arm
            -- payloads are declared by 'collectBranchBinders' over the whole VC tree
            -- (generalizing the former single-shot extraResultBinds). This subsumes
            -- the former top-level-only flat-Result special-case.
            let sortEnv0 = buildSortEnv aliases params
                resultKeys =
                  [ kv
                  | (v, t) <- params
                  , TResult okT errT <- [resolveAliasTy aliases t]
                  , kv <- [ (v <> "$ok",  typeToSort okT)
                          , (v <> "$err", typeToSort errT) ] ]
                -- COMP-4 (d-elim): per-constructor payload-sort keys for an
                -- admissible two-arm USER sum-type param, so the generic EMatch
                -- path can opaque-sum-eliminate a match on it (same skolem-branch
                -- as Result). Seeded ONLY when both payloads are QF-LIA scalars
                -- (admissiblePayload); a sum/recursive payload is not seeded → the
                -- match falls back (firewall, design §5). Param-scoped, matching
                -- the Result seeding above.
                adtKeys =
                  [ (v <> "$" <> c, typeToSort pt)
                  | (v, t) <- params
                  , TSumType [(c1, Just t1), (c2, Just t2)] <- [resolveAliasTy aliases t]
                  , admissiblePayload aliases t1, admissiblePayload aliases t2
                  , (c, pt) <- [(c1, t1), (c2, t2)] ]
                sortEnv = foldr (uncurry Map.insert) sortEnv0 (resultKeys ++ adtKeys)
                -- COMP-4 (b): parallel refinement env — each refined-payload
                -- Result/two-arm-ADT param payload's declared refinement, keyed
                -- identically to the sort keys. Unrefined payloads contribute
                -- nothing (FQTrue skolem, the d-elim behavior).
                resultRefs =
                  [ (key, ref)
                  | (v, t) <- params
                  , TResult okT errT <- [resolveAliasTy aliases t]
                  , (key, pt) <- [ (v <> "$ok", okT), (v <> "$err", errT) ]
                  , Just ref <- [payloadRefinement aliases pt] ]
                adtRefs =
                  [ (v <> "$" <> c, ref)
                  | (v, t) <- params
                  , TSumType [(c1, Just t1), (c2, Just t2)] <- [resolveAliasTy aliases t]
                  , admissiblePayload aliases t1, admissiblePayload aliases t2
                  , (c, pt) <- [(c1, t1), (c2, t2)]
                  , Just ref <- [payloadRefinement aliases pt] ]
                refEnv = Map.fromList (resultRefs ++ adtRefs)
            -- Translate body (generic path; Result-var matches handled within).
            seed <- readIORef bodyCounterRef
            let (newSeed, mBodyVC) = bodyToPredFromR seed sortEnv refEnv cenv sccSet body'
            writeIORef bodyCounterRef newSeed
            case mBodyVC of
              Nothing -> addBodyFallback name  -- body outside QF-LIA fragment
              Just bvc -> do
                -- Path count check (bounded)
                let pathCount = countPathsBounded 4097 bvc  -- stop at 4097
                if pathCount > 4096
                  then do
                    -- >4096: fallback, not error
                    addBodyFallback name
                    addDiag $ mkWarning Nothing $
                      "body VC for '" <> name <> "' exceeded 4096 path limit — "
                      <> "falling back to contract-only verification"
                  else do
                    -- Warn at 257-4096
                    when (pathCount > 256) $
                      addDiag $ mkWarning Nothing $
                        "body VC for '" <> name <> "' has "
                        <> T.pack (show pathCount) <> " paths (high path count may slow solver)"
                    -- Flatten and emit constraints
                    let paths = flattenBodyVC bvc
                        provs = pathBranchSides bvc  -- structural then/else provenance, positionally aligned with paths
                        retSort = maybe FQInt typeToSort mRet
                    -- COMP-3b-general: declare every match-introduced binder across
                    -- the WHOLE VC tree (synthetic guard + arm payloads, at their
                    -- ok/err sort) so the per-arm body-VC constraints have no free
                    -- vars. Trivial refinement FQTrue = an arbitrary value of the
                    -- sort = the universal per-arm hypothesis. 'collectBranchBinders'
                    -- is the SOLE emitter of these binders (no double-declaration);
                    -- empty for a branch-free body.
                    extraBindIds <- mapM (\(vn, vs, vp) -> do
                      ebid <- freshBid
                      addBind (FQBind ebid vn (FQReft "v" vs vp))
                      return ebid) (collectBranchBinders bvc)
                    forM_ (zip provs paths) $ \(prov, (guard, lbs, resultPred)) -> do
                      -- Emit binders for each let-binding in this path
                      lbBindIds <- mapM (\lb -> do
                        bid <- freshBid
                        let b = FQBind bid (lbName lb) (FQReft "v" (lbSort lb)
                                  (FQBinPred FQEq (FQVar "v") (lbRhs lb)))
                        addBind b
                        return bid) lbs
                      -- Emit result binder
                      rbid <- freshBid
                      let resultBind = FQBind rbid "result" (FQReft "v" retSort FQTrue)
                      addBind resultBind
                      -- Build LHS: guard ∧ pre ∧ (result = body-result)
                      let resultEq = FQBinPred FQEq (FQVar "result") resultPred
                          lhsPred  = conjoinAll $ [guard | guard /= FQTrue]
                                                ++ maybe [] (:[]) mPre
                                                ++ [resultEq]
                          lhs = FQReft "result" retSort lhsPred
                          rhs = FQReft "result" retSort postPred
                      -- Determine tag from structural branch provenance (the
                      -- outermost branch side this path descends from), not a
                      -- path-index midpoint — the midpoint mislabeled the refuted
                      -- arm under unbalanced nesting (unequal then/else path counts).
                      let tag = case prov of
                                  Nothing    -> "body-post"
                                  Just True  -> "body-post-then"
                                  Just False -> "body-post-else"
                      cid <- freshCid
                      let allEnvIds = envIds ++ extraBindIds ++ lbBindIds ++ [rbid]
                          c = FQConstraint cid allEnvIds lhs rhs [name, tag]
                      addConst c
                      let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                      addOrigin cid (ConstraintOrigin name tag ptr srcFile)
                    -- Mark as body-faithful
                    addBodyFaithful name

                    -- INT-1 (v0.10.8): tagged body-faithful fns whose body used
                    -- LLMLL-level integer arithmetic over non-literal operands.
                    -- LT-INT (v0.11): trigger set is empty — `int` is now Integer
                    -- at codegen, so no `int` arithmetic can overflow at runtime.
                    -- The walker `bodyHasOverflowArith` and the `erOverflowTainted`
                    -- field are preserved across the module surface; INT-3 re-arms
                    -- the trigger when the `machine-int` primitive lands (gated by
                    -- callee/operand type-awareness, not by the syntactic walker).
                    -- See docs/design/int-2-boundary-shims.md §4.
                    -- when (bodyHasOverflowArith body) (addOverflowTainted name)

                    -- v0.9.0: Emit call-pre obligations for any CallVC nodes
                    -- Each obligation is a separate constraint proving the callee's
                    -- precondition is satisfied at the call site.
                    let callObligations = collectCallPreObligations bvc
                    unless (null callObligations) $ do
                      addCallPre name
                      forM_ (zip [0::Int ..] callObligations) $ \(cpIdx, (callee, prePred, pathGuard, ctxCalls, pathLbs)) -> do
                        -- F-NIW-4: declare the prior-call result vars on this path so
                        -- a precondition referencing one is not a free variable; their
                        -- assumed posts join the LHS hypothesis (assume-guarantee).
                        ctxBindIds <- mapM (\(rv, rs, _) -> do
                          bid <- freshBid
                          addBind (FQBind bid rv (FQReft "v" rs FQTrue))
                          return bid) ctxCalls
                        -- F-NIW-4b: declare the in-scope let-bound non-call values on
                        -- this path with their defining equality, so a precondition
                        -- referencing one is provable. Filtered to the subset whose RHS
                        -- is in scope (params ∪ prior results ∪ earlier lbs).
                        let priorRVars = [ rv | (rv, _, _) <- ctxCalls ]
                            scope0     = Set.fromList (map bindName paramBinds ++ priorRVars)
                            usableLbs  = inScopeLbs scope0 (nub pathLbs)
                        lbCtxBindIds <- mapM (\lb -> do
                          bid <- freshBid
                          addBind (FQBind bid (lbName lb) (FQReft "v" (lbSort lb)
                                    (FQBinPred FQEq (FQVar "v") (lbRhs lb))))
                          return bid) usableLbs
                        cid <- freshCid
                        let cpTag = "call-pre:" <> callee
                            ctxPosts = [ post | (_, _, post) <- ctxCalls, post /= FQTrue ]
                            -- LHS: path guard ∧ caller pre ∧ prior-call assumed posts
                            lhsPred = conjoinAll $ [pathGuard | pathGuard /= FQTrue]
                                                 ++ maybe [] (:[]) mPre
                                                 ++ ctxPosts
                            lhs = FQReft "v" FQInt lhsPred
                            -- RHS: callee's precondition (PROVE polarity — caller must prove this)
                            rhs = FQReft "v" FQInt prePred
                            c = FQConstraint cid (envIds ++ ctxBindIds ++ lbCtxBindIds) lhs rhs [name, cpTag]
                        addConst c
                        let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                        addOrigin cid (ConstraintOrigin name cpTag ptr srcFile)

                    -- COMP-4 (b) intro-side: payload-subtyping obligations. For
                    -- each call passing an arg to a refined-payload Result/ADT
                    -- param, emit ∀v. p_arg(v) ⟹ p_param(v) as a standalone
                    -- refinement-subtyping constraint (Vazou ICFP14; liquid-
                    -- fixpoint's native operation). Syntactic-reflexivity fast-
                    -- path: NO constraint when the arg's payload refinement equals
                    -- the param's (the param-forwarding case). A forwarded-param
                    -- arg sources p_arg from refEnv; any other arg is unrefined
                    -- (FQTrue) → a refined param payload is then unprovable →
                    -- refused (sound). The declaration-driven obligation makes the
                    -- elim-side assumption (Stage 1b) sound.
                    forM_ (collectCallSites bvc) $ \(callee, callArgs) ->
                      case Map.lookup callee cenv of
                        Nothing -> return ()
                        Just (calleeParams, _, _) ->
                          forM_ (zip calleeParams callArgs) $ \((_, pt), argPred) ->
                            forM_ (payloadArms aliases pt) $ \(armKey, payT) ->
                              case payloadRefinement aliases payT of
                                Nothing -> return ()
                                Just (xbP, pParamE) -> do
                                  let mArgRef = case argPred of
                                        FQVar a -> Map.lookup (a <> armKey) refEnv
                                        _       -> Nothing
                                      reflexive = case mArgRef of
                                        Just (xbA, pA) -> renameVar xbA "v" pA == renameVar xbP "v" pParamE
                                        Nothing        -> False
                                  unless reflexive $ do
                                    let psort    = typeToSort (resolveAliasTy aliases payT)
                                        pParamFQ = fromMaybe FQTrue (exprToPred (renameVar xbP "v" pParamE))
                                        pArgFQ   = case mArgRef of
                                          Just (xbA, pA) -> fromMaybe FQTrue (exprToPred (renameVar xbA "v" pA))
                                          Nothing        -> FQTrue
                                        subTag   = "payload-sub:" <> callee
                                    scid <- freshCid
                                    let sc = FQConstraint scid envIds (FQReft "v" psort pArgFQ) (FQReft "v" psort pParamFQ) [name, subTag]
                                    addConst sc
                                    let sptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                                    addOrigin scid (ConstraintOrigin name subTag sptr srcFile)

-- NIW (v0.12): alias-aware so a refinement-aliased param (e.g. `w : Word`)
-- gets its carrier sort (Str/Lst) rather than the typeToSort default (int).
emitParamBind :: AliasMap -> IO FQBindId -> (FQBind -> IO ()) -> (Name, Type) -> IO FQBind
emitParamBind aliases freshBid addBind (n, t) = do
  bid <- freshBid
  let b = FQBind bid n (FQReft "v" (typeToSort (resolveAliasTy aliases t)) FQTrue)
  addBind b
  return b

-- | Resolve TCustom aliases (and strip the refinement of a TDependent) down to
-- the underlying carrier type, for sort selection.
resolveAliasTy :: AliasMap -> Type -> Type
resolveAliasTy am (TCustom n)        = maybe (TCustom n) (resolveAliasTy am) (Map.lookup n am)
resolveAliasTy am (TDependent _ b _) = resolveAliasTy am b
resolveAliasTy _  t                  = t

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | v0.8.0: Type alias map, built from STypeDef statements.
-- Maps alias names to their structural bodies for isIntLike resolution.
type AliasMap = Map Name Type

-- | Build an alias map from top-level type definitions.
buildAliasMap :: [Statement] -> AliasMap
buildAliasMap stmts = Map.fromList [(n, body) | STypeDef n body <- stmts]

-- | Check if a type is int-like after resolving aliases.
-- Handles TDependent refinements and TCustom aliases.
-- Unresolved TCustom falls back to False (sound: rejects unknown types).
isIntLike :: AliasMap -> Type -> Bool
isIntLike _  TInt                  = True
isIntLike am (TDependent _ base _) = isIntLike am base
isIntLike am (TCustom n)           = case Map.lookup n am of
                                        Just t  -> isIntLike am t
                                        Nothing -> False  -- unresolved: reject
-- COMP-3b-general (Phase 1): a nullary enum is int-tag-encodable (each
-- constructor → its declaration index), so its values live in the QF-LIA sort
-- env as FQInt. Payload-bearing sum types stay non-int (→ asserted fallback).
isIntLike _  (TSumType ctors)      = all (\(_, mp) -> case mp of Nothing -> True; Just _ -> False) ctors
isIntLike _  _                     = False

typeToSort :: Type -> FQSort
typeToSort TInt    = FQInt
typeToSort TBool   = FQBool
typeToSort TString = FQStr            -- NIW: opaque carrier for string measures
typeToSort (TList _) = FQList         -- NIW: opaque carrier for list measures
typeToSort (TDependent _ base _) = typeToSort base
typeToSort _     = FQInt  -- conservative default

-- | COMP-4 (d-elim): a two-arm-ADT payload is admissible to opaque-sum
-- elimination iff its sort is a QF-LIA-representable scalar (int / bool /
-- string-measure carrier). A payload that is itself a sum/Result/list/etc. type
-- is NOT admissible — it would need the datatype theory of COMP-4 (a) /
-- construction reasoning — so the match falls back via the §5.3.3 firewall.
-- (Enum-tag and list payloads are deliberate follow-ups, not this slice.)
admissiblePayload :: AliasMap -> Type -> Bool
admissiblePayload am t = case resolveAliasTy am t of
  TInt    -> True
  TBool   -> True
  TString -> True
  _       -> False

typeSorts :: Name -> Type -> [FQDataDecl]
typeSorts name (TSumType ctors) =
  [FQDataDecl name 0 [(c, 0) | (c, _) <- ctors]]
typeSorts _ _ = []

maybeToList :: Maybe a -> [a]
maybeToList Nothing  = []
maybeToList (Just x) = [x]

-- ---------------------------------------------------------------------------
-- COMP-3b-general (Phase 1): nullary-enum constructor-value desugaring
-- ---------------------------------------------------------------------------

-- | Tag table for nullary-enum constructors: each constructor of an in-scope
-- nullary 'TSumType' maps to its declaration index (its int tag). Only names
-- that are UNAMBIGUOUS across all in-scope enums are kept — a name that is a
-- constructor of more than one enum is excluded, so the desugar leaves it as a
-- variable (→ unbound symbol → 'asserted' fallback, sound, never mis-tagged).
buildCtorTagMap :: AliasMap -> Map Name Int
buildCtorTagMap am =
  let perEnum = [ (c, i)
                | t <- Map.elems am
                , TSumType ctors <- [t]
                , all (\(_, mp) -> case mp of Nothing -> True; Just _ -> False) ctors
                , (i, (c, _)) <- zip [0 ..] ctors ]
      grouped = Map.fromListWith (++) [ (c, [i]) | (c, i) <- perEnum ]
  in Map.fromList [ (c, i) | (c, [i]) <- Map.toList grouped ]  -- unambiguous only

-- | Scope-aware desugar that lowers nullary-constructor VALUES and nullary-enum
-- matches to the int-tag QF-LIA form the existing VC machinery already verifies:
--   (a) a value-position @EVar n@ that resolves to a nullary constructor (n in
--       the tag table, not shadowed by a local binding) → @ELit (LitInt tag)@;
--   (b) an @EMatch@ on a variable whose arms are all nullary constructors (or a
--       catch-all) → a right-nested @EIf@ on @(= scrut tag_i)@.
-- Result matches (Success/Error, payload-bearing) are untouched — their
-- constructors are not in the tag table — and flow to the existing COMP-3 path.
-- The bound-set makes a @let@/param sharing a constructor's name win (it stays a
-- variable). Payload-bearing constructors and payload-projecting posts are left
-- alone (→ 'asserted'), keeping the QF-LIA boundary intact (no datatype theory).
desugarCtorValues :: Map Name Int -> Set.Set Name -> Expr -> Expr
desugarCtorValues tags = go
  where
    tagLit c = ELit (LitInt (toInteger (tags Map.! c)))

    go bound e = case e of
      EVar n
        | n `Map.member` tags && not (n `Set.member` bound) -> tagLit n
        | otherwise                                         -> e
      ELit _      -> e
      EHole _     -> e
      EOp op as   -> EOp op (map (go bound) as)
      EApp f as   -> EApp f (map (go bound) as)
      EPair a b   -> EPair (go bound a) (go bound b)
      EAwait a    -> EAwait (go bound a)
      EIf c t el  -> EIf (go bound c) (go bound t) (go bound el)
      ELambda ps body ->
        ELambda ps (go (foldr (Set.insert . fst) bound ps) body)
      ELet binds body ->
        let bound' = foldr Set.insert bound (concatMap (\(p,_,_) -> patVars p) binds)
        in ELet [ (p, mt, go bound' rhs) | (p, mt, rhs) <- binds ] (go bound' body)
      EDo steps   -> EDo [ DoStep mn (go bound se) | DoStep mn se <- steps ]
      EMatch scr arms
        | EVar _ <- scr, not (null arms), all (rewritableArm . fst) arms
          -> buildChain (go bound scr) bound arms
        | otherwise
          -> EMatch (go bound scr)
               [ (p, go (foldr Set.insert bound (patVars p)) b) | (p, b) <- arms ]

    rewritableArm (PConstructor c []) = c `Map.member` tags
    rewritableArm (PVar _)            = True
    rewritableArm PWildcard           = True
    rewritableArm _                   = False

    -- Right-nested EIf. The LAST arm is the bare else (exhaustiveness — enforced
    -- by the type checker — guarantees it covers the remaining constructor); a
    -- PVar/PWildcard arm is a catch-all and becomes the else, ignoring later arms.
    buildChain _    bound [(_, b)]        = go bound b
    buildChain scr' bound ((p, b) : rest) = case p of
      PConstructor c [] -> EIf (EOp "=" [scr', tagLit c]) (go bound b) (buildChain scr' bound rest)
      _                 -> go bound b
    buildChain _    _     []              = ELit LitUnit  -- unreachable (arms non-empty)

    patVars (PVar n)            = [n]
    patVars (PConstructor _ ps) = concatMap patVars ps
    patVars _                   = []

-- | INT-1 (v0.10.8): True when an expression tree contains LLMLL-level
-- integer arithmetic over operands that are not all integer literals whose
-- folded value fits 'Int64'. The check is purely syntactic — it does not
-- consult refinement predicates that might witness bounds. This is the
-- conservative-honest discharge of the Int64 overflow gap documented at
-- 'LLMLL.md §5.3.5'; the principled clearance paths are (i) ?proof-required
-- + Leanstral, (ii) post-v0.11 INT-2 unbounded 'int', or (iii) post-freeze
-- INT-3 'machine-int' under QF-BV.
--
-- The arithmetic operators recognised are the LLMLL surface forms emitted by
-- both 'EOp' and 'EApp' nodes: '+', '-', '*', '/', 'mod', 'rem', '^', '**'.
-- Predicate, boolean, list, and string operators are not arithmetic and do
-- not taint. Literal folding clears only the simplest case (a constant value
-- inside Int64 range); any non-literal operand taints the surrounding op.
bodyHasOverflowArith :: Expr -> Bool
bodyHasOverflowArith = go
  where
    arithOps :: [Name]
    arithOps = ["+", "-", "*", "/", "mod", "rem", "^", "**"]

    -- All operands are integer literals whose computed value fits Int64.
    -- Used to clear the taint for compile-time constant expressions like
    -- (+ 40 2). The arithmetic itself is performed on Haskell Integer and
    -- the result is range-checked; out-of-range constants taint, matching
    -- the semantic claim "arithmetic that may overflow at Haskell level."
    allLitsInBounds :: [Expr] -> Bool
    allLitsInBounds es =
      let lits = traverse litValue es
      in case lits of
           Just vs -> all (\v -> v >= toInteger (minBound :: Int)
                              && v <= toInteger (maxBound :: Int)) vs
           Nothing -> False

    litValue :: Expr -> Maybe Integer
    litValue (ELit (LitInt n)) = Just n
    litValue _                 = Nothing

    isArith :: Name -> Bool
    isArith op = op `elem` arithOps

    go :: Expr -> Bool
    go (EOp op args)  | isArith op = not (allLitsInBounds args) || any go args
                      | otherwise  = any go args
    go (EApp op args) | isArith op = not (allLitsInBounds args) || any go args
                      | otherwise  = any go args
    go (ELit _)         = False
    go (EVar _)         = False
    go (EHole _)        = False
    go (EIf c t e)      = go c || go t || go e
    go (ELet bindings body) = any (\(_, _, rhs) -> go rhs) bindings || go body
    go (EMatch scr arms) = go scr || any (go . snd) arms
    go (ELambda _ body) = go body
    go (EDo steps)      = any (\(DoStep _ e) -> go e) steps
    go (EPair l r)      = go l || go r
    go (EAwait e)       = go e

-- | Convert a linear arithmetic LLMLL Expr to a FQPred.
-- Returns Nothing for non-linear or unsupported expressions (→ skip/proof-required).
exprToPred :: Expr -> Maybe FQPred
exprToPred (EVar v)   = Just (FQVar v)
exprToPred (ELit (LitInt n)) = Just (FQLit n)
exprToPred (ELit (LitBool True))  = Just FQTrue
exprToPred (ELit (LitBool False)) = Just FQFalse
exprToPred (EApp op [l, r])
  | op `elem` [">=", "≥"] = (\a b -> FQBinPred FQGe  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` [">"]        = (\a b -> FQBinPred FQGt  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["<=", "≤"] = (\a b -> FQBinPred FQLe  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["<"]        = (\a b -> FQBinPred FQLt  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["=", "=="]  = (\a b -> FQBinPred FQEq  a b) <$> exprToPred l <*> exprToPred r
  | op `elem` ["/=", "!=", "≠"] = (\a b -> FQBinPred FQNeq a b) <$> exprToPred l <*> exprToPred r
  | op == "+"              = (\a b -> FQBinArith FQAdd a b) <$> exprToPred l <*> exprToPred r
  | op == "-"              = (\a b -> FQBinArith FQSub a b) <$> exprToPred l <*> exprToPred r
  -- non-linear ops: reject
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = Nothing
exprToPred (EApp "and" args) = FQAnd <$> mapM exprToPred args
exprToPred (EApp "or"  args) = FQOr  <$> mapM exprToPred args
exprToPred (EApp "not" [a])  = FQNot <$> exprToPred a
-- NIW (v0.12): measure-class applications → uninterpreted-function terms.
-- The argument is a WF base term (REF-META-3 M3); exprToPred (EVar v) = FQVar v
-- carries it through unconditionally. Range facts (m t >= 0) are injected
-- centrally at addConst, not here. Only string-length / list-length are admitted.
exprToPred (EApp "string-length" [a]) = (\x -> FQApp "strLen"  [x]) <$> exprToPred a
exprToPred (EApp "list-length"   [a]) = (\x -> FQApp "listLen" [x]) <$> exprToPred a
-- v0.8.0: Parser emits operators as EOp; delegate to EApp for uniform handling.
exprToPred (EOp op args)     = exprToPred (EApp op args)
exprToPred _ = Nothing  -- lambda, let, match, etc. → not in QF linear arith

-- | Extract qualifiers from an expression (auto-synthesis from pre/post).
-- Each atomic comparison at the top level becomes a qualifier template.
extractQualifiers :: Text -> Name -> Expr -> [FQQualifier]
extractQualifiers clause fnName expr =
  case exprToPred expr of
    Nothing   -> []  -- non-linear, no qualifiers
    Just pred -> atomicQualifiers fnName clause pred

atomicQualifiers :: Name -> Text -> FQPred -> [FQQualifier]
atomicQualifiers fn clause pred =
  case pred of
    FQBinPred op l r ->
      let vars = nubT (predVars l ++ predVars r)
          params = map (\v -> (v, FQInt)) ("v" : vars)
          qname  = "Q_" <> fn <> "_" <> clause <> "_" <> T.pack (show (hashPred pred))
      in [FQQualifier qname params pred]
    FQAnd ps -> concatMap (atomicQualifiers fn clause) ps
    FQOr  ps -> concatMap (atomicQualifiers fn clause) ps
    _ -> []

predVars :: FQPred -> [Text]
predVars (FQVar v)            = [v]
predVars (FQLit _)            = []
predVars FQTrue               = []
predVars FQFalse              = []
predVars (FQBinPred _ l r)   = predVars l ++ predVars r
predVars (FQBinArith _ l r)  = predVars l ++ predVars r
predVars (FQAnd ps)           = concatMap predVars ps
predVars (FQOr  ps)           = concatMap predVars ps
predVars (FQNot p)            = predVars p
predVars (FQKVar _ args)      = concatMap predVars args
predVars (FQApp _ args)       = concatMap predVars args  -- NIW: measure args carry the free vars

nubT :: [Text] -> [Text]
nubT [] = []
nubT (x:xs) = x : nubT (filter (/= x) xs)

-- Simple hash for unique qualifier names (not cryptographic)
hashPred :: FQPred -> Int
hashPred = T.length . T.pack . show

-- ---------------------------------------------------------------------------
-- Body-VC translation engine (v0.8.0 BODY-VC-1, extended v0.9.0 COMP-1)
-- ---------------------------------------------------------------------------

-- | Pure entry point: translates a function body to a BodyVC tree.
-- Takes a seed counter value and a sort environment (built from int params).
-- Returns (updatedCounter, Maybe BodyVC). Nothing = unsupported expression.
--
-- v0.9.0: accepts ContractEnv and SCC set for compositional verification.
-- Pass Map.empty / Set.empty for leaf functions (backward compat).
-- | COMP-4 (b): the elimination-side refinement env. Keyed by the same
-- "<scrutinee>$<arm>" derived keys as the sort env; the value is the matched
-- arm payload's declared refinement as (bindingVar, pred). Read-only, seeded
-- once by the driver (bodyToPredFromR); threaded as a Reader context so the
-- bodyToPredM equations and their recursive calls are untouched.
type RefEnv = Map Name (Name, Expr)

bodyToPredFrom :: Int -> SortEnv -> ContractEnv -> Set.Set Name -> Expr -> (Int, Maybe BodyVC)
bodyToPredFrom seed sortEnv cenv sccSet expr =
  bodyToPredFromR seed sortEnv Map.empty cenv sccSet expr

-- | COMP-4 (b): bodyToPredFrom with an explicit elimination-side RefEnv. The
-- driver seeds it from refined-payload Result/two-arm-ADT params; existing
-- callers use 'bodyToPredFrom' (empty RefEnv → FQTrue payload skolems, the
-- pre-(b) behavior).
bodyToPredFromR :: Int -> SortEnv -> RefEnv -> ContractEnv -> Set.Set Name -> Expr -> (Int, Maybe BodyVC)
bodyToPredFromR seed sortEnv refEnv cenv sccSet expr =
  let (result, finalCounter) = runStateFrom seed (runReaderT (bodyToPredM Map.empty sortEnv cenv sccSet expr) refEnv)
  in (finalCounter, result)
  where
    -- Run a State Int computation with a given starting value.
    -- Returns (result, finalState).
    runStateFrom :: Int -> State Int a -> (a, Int)
    runStateFrom s action =
      let go = do { r <- action; c <- get; return (r, c) }
      in evalState go s

-- | Fresh name generator for alpha-renaming.
freshName :: MonadState Int m => Name -> m Text
freshName base = do
  n <- get
  put (n + 1)
  return ("_bv_" <> base <> "_" <> T.pack (show n))

-- | Core body-to-predicate translation. Handles all operators directly
-- (NOT delegating to exprToPred) to preserve the alpha-renaming environment.
--
-- exprToPred does not consult the renaming env — it translates EVar v as
-- FQVar v using the original name. If a let-bound variable (renamed to
-- _bv_x_0) appears inside an operator expression and we delegate to
-- exprToPred, the .fq output will reference the un-renamed name, which
-- the solver cannot resolve.
--
-- v0.9.0: Extended with ContractEnv and SCC set for compositional verification.
-- When encountering EApp to a contracted user function, uses assume-guarantee
-- reasoning (COMP-0 §2). SCC set excludes recursive functions' own body VCs
-- but allows callers to use assume-guarantee (Issue 4 relaxation).
bodyToPredM :: Map Name Name  -- ^ renaming env
            -> SortEnv        -- ^ sort env
            -> ContractEnv    -- ^ v0.9.0: contract lookup
            -> Set.Set Name   -- ^ v0.9.0: recursive SCC set (for own-body exclusion)
            -> Expr
            -> ReaderT RefEnv (State Int) (Maybe BodyVC)

-- Literals
bodyToPredM _ _ _ _ (ELit (LitInt n)) = return (Just (SimpleVC [] (FQLit n)))
bodyToPredM _ _ _ _ (ELit (LitBool True))  = return (Just (SimpleVC [] FQTrue))
bodyToPredM _ _ _ _ (ELit (LitBool False)) = return (Just (SimpleVC [] FQFalse))

-- Variables: look up renamed name, check sort env
bodyToPredM env sortEnv _ _ (EVar v) =
  let renamed = fromMaybe v (Map.lookup v env)
  in case Map.lookup renamed sortEnv of
       Just FQInt -> return (Just (SimpleVC [] (FQVar renamed)))
       _          -> return Nothing  -- non-int or unknown sort → fallback

-- v0.9.0: User-defined function call with contract (COMP-0 §2, §3)
-- Issue 4 resolution: SCC guard REMOVED. Callers of recursive functions
-- may use assume-guarantee against the recursive function's contract.
-- The recursive function's own body VC remains excluded (§4.1).
-- Trust degrades via evidenceMeet — see §4.4.
bodyToPredM env se cenv _sccSet (EApp fname args)
  | fname `Map.member` cenv
  , lookupArithOp fname == Nothing   -- not a builtin operator
  , lookupPredOp fname == Nothing    -- not a builtin operator
  , fname `notElem` ["not", "and", "or", "*", "/", "mod", "rem", "^", "**"]
  = do
    -- Translate arguments. F-NIW-2: a bare-variable argument translates to its
    -- FQVar regardless of sort — the type checker guarantees its uses in the
    -- callee contract are sort-consistent, and this lets a carrier (string/list)
    -- argument reach the call-pre substitution so a measure-refined param's
    -- obligation is emitted instead of forcing whole-call fallback. Non-variable
    -- arguments still route through bodyToPredM (int/QF-LIA only).
    let translateCallArg (EVar v) =
          return (Just (FQVar (fromMaybe v (Map.lookup v env))))
        translateCallArg a = do
          mvc <- bodyToPredM env se cenv _sccSet a
          return $ case mvc of Just (SimpleVC [] p) -> Just p; _ -> Nothing
    mArgPredsList <- mapM translateCallArg args
    let mArgPreds = sequence mArgPredsList
    case mArgPreds of
      Nothing -> return Nothing  -- argument translation failed
      Just argPreds -> do
        let (params, contract, mRetType) = cenv Map.! fname
            paramNames = map fst params
        -- Build substitution: callee params → translated args
        let subst = Map.fromList (zip paramNames argPreds)
        -- Issue 1 resolution: three-way pre distinction (soundness-critical)
        --   callee has no pre        → no obligation, assumption valid
        --   callee has pre, translates → obligation emitted
        --   callee has pre, fails     → ENTIRE CALL FALLS BACK
        let mPreResult = case contractPre contract of
              Nothing  -> Just Nothing
              Just pre -> case exprToPred pre of
                            Nothing -> Nothing       -- untranslatable pre → fallback
                            Just p  -> Just (Just (applySubst subst p))
        case mPreResult of
          Nothing -> return Nothing  -- soundness: cannot assume post without verifying pre
          Just mPrePred -> do
            -- Translate post (Nothing = no post → no assumption)
            let mPostPred = contractPost contract >>= exprToPred
            -- Fresh result variable
            resultVar <- freshName ("call_" <> fname)
            let mPostSubst = fmap (\p -> applySubst (Map.insert "result" (FQVar resultVar) subst) p) mPostPred
                retSort = maybe FQInt typeToSort mRetType
            -- Issue 3 resolution: return CallVC directly (Option A)
            -- The enclosing ELet case fills the real continuation.
            return $ Just $ CallVC
              { cvCallee         = fname
              , cvArgs           = argPreds
              , cvPreObligation  = mPrePred
              , cvPostAssumption = mPostSubst
              , cvResultVar      = resultVar
              , cvResultSort     = retSort
              , cvContinuation   = SimpleVC [] (FQVar resultVar)
              }

-- Binary arithmetic operators (+, -)
bodyToPredM env se cenv sccSet (EApp op [l, r])
  | Just binOp <- lookupArithOp op = do
      lvc <- bodyToPredM env se cenv sccSet l
      rvc <- bodyToPredM env se cenv sccSet r
      case (lvc, rvc) of
        (Just (SimpleVC [] lp), Just (SimpleVC [] rp)) ->
          return . Just $ SimpleVC [] (FQBinArith binOp lp rp)
        _ -> return Nothing

-- Binary comparison operators (>=, >, <=, <, =, /=, plus Unicode)
bodyToPredM env se cenv sccSet (EApp op [l, r])
  | Just binOp <- lookupPredOp op = do
      lvc <- bodyToPredM env se cenv sccSet l
      rvc <- bodyToPredM env se cenv sccSet r
      case (lvc, rvc) of
        (Just (SimpleVC [] lp), Just (SimpleVC [] rp)) ->
          return . Just $ SimpleVC [] (FQBinPred binOp lp rp)
        _ -> return Nothing

-- Non-linear operators: reject
bodyToPredM _ _ _ _ (EApp op [_, _])
  | op `elem` ["*", "/", "mod", "rem", "^", "**"] = return Nothing

-- Logical operators: not, and, or
bodyToPredM env se cenv sccSet (EApp "not" [a]) = do
  avc <- bodyToPredM env se cenv sccSet a
  case avc of
    Just (SimpleVC [] p) -> return . Just $ SimpleVC [] (FQNot p)
    _ -> return Nothing

bodyToPredM env se cenv sccSet (EApp "and" args) = do
  avcs <- mapM (bodyToPredM env se cenv sccSet) args
  let preds = [p | Just (SimpleVC [] p) <- avcs]
  if length preds == length args
    then return . Just $ SimpleVC [] (FQAnd preds)
    else return Nothing

bodyToPredM env se cenv sccSet (EApp "or" args) = do
  avcs <- mapM (bodyToPredM env se cenv sccSet) args
  let preds = [p | Just (SimpleVC [] p) <- avcs]
  if length preds == length args
    then return . Just $ SimpleVC [] (FQOr preds)
    else return Nothing

-- NIW (v0.12): measure-class application in a body → uninterpreted-function term.
-- The argument is a bare base-typed binding (Phase 1, REF-META-3 M3); we translate
-- it directly to an FQVar under the renaming env rather than recursing through
-- bodyToPredM (whose EVar case admits only int-sorted vars). Nested/non-var args
-- fall through to the catch-all (→ body fallback), which is sound.
bodyToPredM env _ _ _ (EApp "string-length" [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "strLen"  [FQVar (fromMaybe v (Map.lookup v env))])
bodyToPredM env _ _ _ (EApp "list-length"   [EVar v]) =
  return . Just $ SimpleVC [] (FQApp "listLen" [FQVar (fromMaybe v (Map.lookup v env))])

-- Normalize EOp to EApp
bodyToPredM env se cenv sccSet (EOp name args) = bodyToPredM env se cenv sccSet (EApp name args)

-- EIf: branch into guard + then-VC + else-VC
bodyToPredM env se cenv sccSet (EIf guard thenE elseE) = do
  mGuard <- lift (guardToPredM env se guard)
  case mGuard of
    Nothing -> return Nothing
    Just gp -> do
      mthen <- bodyToPredM env se cenv sccSet thenE
      melse <- bodyToPredM env se cenv sccSet elseE
      case (mthen, melse) of
        (Just tvc, Just evc) -> return (Just (BranchVC gp [] tvc evc))
        _                    -> return Nothing

-- ELet with single PVar binding: alpha-rename, emit LetBinding, recurse
bodyToPredM env se cenv sccSet (ELet [(PVar v, _mType, rhs)] body) = do
  -- Translate the RHS
  mRhsVC <- bodyToPredM env se cenv sccSet rhs
  case mRhsVC of
    Nothing -> return Nothing
    Just (SimpleVC [] rhsPred) -> do
      -- Alpha-rename the bound variable
      renamed <- freshName v
      let env'  = Map.insert v renamed env
          sort  = predSortOf rhsPred
          se'   = Map.insert renamed sort se
          lb    = LetBinding renamed sort rhsPred
      -- Recurse on body with updated env
      mBodyVC <- bodyToPredM env' se' cenv sccSet body
      case mBodyVC of
        Nothing -> return Nothing
        Just (SimpleVC lbs resultP) ->
          return (Just (SimpleVC (lb : lbs) resultP))
        Just (BranchVC gp bs tvc evc) ->
          -- Prepend this binding to both branches
          return (Just (BranchVC gp bs (prependLB lb tvc) (prependLB lb evc)))
        -- v0.9.0: SimpleVC RHS but body produces CallVC — prepend binding
        Just cvc@(CallVC {}) ->
          return (Just (prependLB lb cvc))
    -- v0.9.0: RHS is a CallVC — thread the body as the continuation (Issue 3).
    -- F-NIW-4: alias the let variable directly to the call's result var (rVar),
    -- which the CallVC continuation binds with the callee's post. Minting a fresh
    -- name here left the let var unbound (never equated to rVar) — a free variable
    -- in every constraint that referenced it (the withdraw-twice / banking_ledger
    -- crash, masked pre-F-NIW-3 by liquid-fixpoint's hyphen mis-lex).
    Just (CallVC cal callArgs mPre mPost rVar rSort _cont) -> do
      let env' = Map.insert v rVar env
          se'  = Map.insert rVar rSort se
      mBodyVC <- bodyToPredM env' se' cenv sccSet body
      case mBodyVC of
        Nothing -> return Nothing
        Just bvc -> return $ Just $ CallVC cal callArgs mPre mPost rVar rSort bvc
    -- RHS is a branch (EIf in let RHS) — hoist via flattening.
    -- Single-path degenerate branches are handled; multi-path falls back.
    Just bvc@(BranchVC _ _ _ _) -> do
      renamed <- freshName v
      let env'  = Map.insert v renamed env
          se'   = Map.insert renamed FQInt se
          paths = flattenBodyVC bvc
      case paths of
        -- Degenerate single-path: the branch always takes one path
        [(_, pathLBs, pathResult)] -> do
          let lb = LetBinding renamed FQInt pathResult
          mBodyVC <- bodyToPredM env' se' cenv sccSet body
          case mBodyVC of
            Nothing -> return Nothing
            Just (SimpleVC lbs resultP) ->
              return (Just (SimpleVC (pathLBs ++ [lb] ++ lbs) resultP))
            Just (BranchVC gp bs tvc evc) ->
              return (Just (BranchVC gp bs
                (prependLBs (pathLBs ++ [lb]) tvc)
                (prependLBs (pathLBs ++ [lb]) evc)))
        -- Multi-path: fall back (conservative, sound)
        _ -> return Nothing
    _ -> return Nothing

-- ELet with multiple bindings: desugar to nested single-binding ELets
bodyToPredM env se cenv sccSet (ELet (b:bs) body) =
  bodyToPredM env se cenv sccSet (ELet [b] (ELet bs body))

-- ELet with no bindings (degenerate): just translate the body
bodyToPredM env se cenv sccSet (ELet [] body) = bodyToPredM env se cenv sccSet body

-- v0.9.0 COMP-3: EMatch on Result (two-path encoding)
-- Handles: (match scrutinee ((Success s) bodyS) ((Error e) bodyE))
-- Produces: BranchVC (FQVar "_match_success_N") bodyS_VC bodyE_VC
-- Falls back on:
--   - Non-two-arm matches (general ADT → future)
--   - Constructors other than Success/Error
--   - Scrutinee translation failure
--   - Constructor-dependent postconditions (Issue 2)
--   - Unannotated return types on scrutinee calls
-- COMP-3b-general (opaque-sum elimination): a Result-typed VARIABLE scrutinee
-- (param or let-bound), detected by the derived "<v>$ok"/"<v>$err" payload-sort
-- keys the driver/ELet seeded into the SortEnv. The variable's value is opaque
-- (it is not in the value SortEnv), so we do NOT translate the scrutinee; we
-- case-split on a fresh free guard and bind each arm's payload at its declared
-- sort. Guard + payloads ride the BranchVC binder field for 'collectBranchBinders'
-- to declare (FQTrue skolems). Subsumes the former top-level flat-Result
-- special-case; fires at any nesting depth.
bodyToPredM env se cenv sccSet (EMatch (EVar r) arms)
  | Just (sV, sB, eV, eB) <- classifyResultArms arms
  , Just okSort  <- Map.lookup (r <> "$ok")  se
  , Just errSort <- Map.lookup (r <> "$err") se
  = do refEnv <- ask
       buildOpaqueSumBranch env se cenv sccSet
         (sV, okSort,  Map.lookup (r <> "$ok")  refEnv, sB)
         (eV, errSort, Map.lookup (r <> "$err") refEnv, eB)

-- COMP-4 (d-elim): the same opaque-sum elimination for an arbitrary admissible
-- two-arm USER sum type, detected by per-constructor "<v>$<Ctor>" payload-sort
-- keys the driver seeded for the scrutinee variable. Ctor-agnostic generalization
-- of the Result clause above (which keeps its "$ok"/"$err" key scheme). A match
-- whose scrutinee var was not seeded (non-admissible/recursive payload) does not
-- match here and falls through to the generic path → fallback.
bodyToPredM env se cenv sccSet (EMatch (EVar r) arms)
  | Just (c1, v1, b1, c2, v2, b2) <- classifyTwoArmAdtArms arms
  , Just s1 <- Map.lookup (r <> "$" <> c1) se
  , Just s2 <- Map.lookup (r <> "$" <> c2) se
  = do refEnv <- ask
       buildOpaqueSumBranch env se cenv sccSet
         (v1, s1, Map.lookup (r <> "$" <> c1) refEnv, b1)
         (v2, s2, Map.lookup (r <> "$" <> c2) refEnv, b2)

bodyToPredM env se cenv sccSet (EMatch scrutinee arms)
  -- Must be exactly 2 arms with Success and Error constructors
  | Just (successVar, successBody, errorVar, errorBody) <- classifyResultArms arms
  = do
    -- Translate scrutinee
    mScrutVC <- bodyToPredM env se cenv sccSet scrutinee
    case mScrutVC of
      Nothing -> return Nothing
      Just scrutVC -> do
        -- Determine the ok/err sorts from the scrutinee's type
        -- For EVar: look up in sort env (conservative: assume FQInt)
        -- For CallVC: use the callee's return type from ContractEnv
        let (okSort, errSort) = case scrutinee of
              EApp fname _ | fname `Map.member` cenv ->
                let (_, _, mRetType) = cenv Map.! fname
                in case mRetType of
                     Just (TResult okT errT) -> (typeToSort okT, typeToSort errT)
                     _                       -> (FQInt, FQInt)
              _ -> (FQInt, FQInt)  -- fallback: assume int payloads

        -- Generate fresh names for payload variables and match guard
        successRenamed <- freshName successVar
        errorRenamed   <- freshName errorVar
        guardVar       <- freshName "_match_success"

        -- Success branch: bind payload variable, translate body
        let envS = Map.insert successVar successRenamed env
            seS  = Map.insert successRenamed okSort se
        mSuccessVC <- bodyToPredM envS seS cenv sccSet successBody

        -- Error branch: bind payload variable, translate body
        let envE = Map.insert errorVar errorRenamed env
            seE  = Map.insert errorRenamed errSort se
        mErrorVC <- bodyToPredM envE seE cenv sccSet errorBody

        case (mSuccessVC, mErrorVC) of
          (Just svc, Just evc) -> do
            -- For CallVC scrutinee: thread as let-binding + branch
            -- For SimpleVC scrutinee: just branch with synthetic guard
            let matchBinders = [(guardVar, FQBool, FQTrue), (successRenamed, okSort, FQTrue), (errorRenamed, errSort, FQTrue)]
            case scrutVC of
              SimpleVC [] _scrutPred ->
                return (Just (BranchVC (FQVar guardVar) matchBinders svc evc))
              CallVC {} ->
                -- The scrutinee is a function call — wrap the branch as CallVC continuation
                -- The CallVC result is the match scrutinee; branch discriminates its constructor
                return (Just (setCallVCContinuation scrutVC (BranchVC (FQVar guardVar) matchBinders svc evc)))
              _ ->
                -- Scrutinee produced a complex VC (branch, etc.) — fallback
                return Nothing
          _ -> return Nothing

-- Everything else: match, app (user-defined without contract), lambda, etc. → fallback
bodyToPredM _ _ _ _ _ = return Nothing

-- | COMP-3b-general / COMP-4 (d-elim): build the opaque-sum elimination
-- skolem-branch for a two-arm match on an opaque (param/let-bound) variable
-- scrutinee. Each arm's payload binds as an FQTrue skolem at its declared sort;
-- the synthetic free guard + the two payloads ride the BranchVC binder field for
-- 'collectBranchBinders' to declare. The scrutinee value is opaque (absent from
-- the value SortEnv), so it is never translated — the case-split is on the fresh
-- guard, and exhaustiveness/distinctness are discharged structurally (the
-- type-checker's two-arm coverage + the boolean guard), staying in QF-LIA.
buildOpaqueSumBranch
  :: Map Name Name -> SortEnv -> ContractEnv -> Set.Set Name
  -> (Name, FQSort, Maybe (Name, Expr), Expr)   -- ^ arm 1: payload var, sort, declared refinement, body
  -> (Name, FQSort, Maybe (Name, Expr), Expr)   -- ^ arm 2
  -> ReaderT RefEnv (State Int) (Maybe BodyVC)
buildOpaqueSumBranch env se cenv sccSet (v1, s1, mref1, b1) (v2, s2, mref2, b2) = do
  r1 <- freshName v1
  r2 <- freshName v2
  guardVar <- freshName "_match_success"
  let env1 = Map.insert v1 r1 env
      se1  = Map.insert r1 s1 se
  mvc1 <- bodyToPredM env1 se1 cenv sccSet b1
  let env2 = Map.insert v2 r2 env
      se2  = Map.insert r2 s2 se
  mvc2 <- bodyToPredM env2 se2 cenv sccSet b2
  -- COMP-4 (b): declare each payload at its DECLARED refinement (sound because
  -- the intro-side obligation makes every caller prove it), not FQTrue. The
  -- refinement (over its binding var xb) is instantiated at the renamed payload
  -- var; a base/unrefined payload (Nothing) stays FQTrue, preserving d-elim.
  let armPred rv mref = case mref of
        Nothing      -> FQTrue
        Just (xb, p) -> fromMaybe FQTrue (exprToPred (renameVar xb rv p))
  return $ case (mvc1, mvc2) of
    (Just vc1, Just vc2) ->
      Just (BranchVC (FQVar guardVar)
                     [(guardVar, FQBool, FQTrue), (r1, s1, armPred r1 mref1), (r2, s2, armPred r2 mref2)]
                     vc1 vc2)
    _ -> Nothing

-- ---------------------------------------------------------------------------
-- Guard translation (v0.8.0, v0.10: extracted to GuardClassifier.hs)
-- ---------------------------------------------------------------------------

-- | Translates guard expressions to FQPred. Delegates to the shared
-- classifyGuardM core in GuardClassifier.hs (v0.10 drift mitigation,
-- spec §4.2.4). Behavioral equivalent of the pre-extraction guardToPredM.
guardToPredM :: Map Name Name -> SortEnv -> Expr -> State Int (Maybe FQPred)
guardToPredM = classifyGuardM

-- ---------------------------------------------------------------------------
-- Flattening and path counting (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Flatten a BodyVC tree into a list of paths.
-- Each path is (guard, let-bindings, result predicate).
-- For SimpleVC, the guard is FQTrue (unconditional).
-- For BranchVC, each branch produces paths with guard conjunction.
flattenBodyVC :: BodyVC -> [FlatPath]
flattenBodyVC (SimpleVC lbs result) = [(FQTrue, lbs, result)]
flattenBodyVC (BranchVC guard _ thenVC elseVC) =
  let thenPaths = [(conjoin guard g, lbs, r) | (g, lbs, r) <- flattenBodyVC thenVC]
      elsePaths = [(conjoin (FQNot guard) g, lbs, r) | (g, lbs, r) <- flattenBodyVC elseVC]
  in thenPaths ++ elsePaths
-- v0.9.0: Flatten a CallVC by threading postcondition as guard and
-- result variable as let-binding into the continuation paths.
-- The precondition obligation is emitted separately during constraint
-- emission — it is NOT folded into the body-post constraint.
flattenBodyVC (CallVC _callee _args _mPre mPost resultVar resultSort cont) =
  let contPaths = flattenBodyVC cont
      -- Add result variable as a let-binding and postcondition as guard
      resultLB = LetBinding resultVar resultSort (FQVar resultVar)
  in [ ( conjoinAll [guard, fromMaybe FQTrue mPost]
       , resultLB : lbs
       , resultPred )
     | (guard, lbs, resultPred) <- contPaths
     ]

-- | Per-path outermost-branch provenance, in the SAME order as 'flattenBodyVC'.
-- For each flattened path: @Just True@ if it descends from the then-subtree of
-- the outermost 'BranchVC', @Just False@ from the else-subtree, @Nothing@ if the
-- tree has no branch (unconditional). Used to localize a refuted arm structurally
-- rather than by a path-index midpoint, which mislabels under unbalanced nesting
-- (unequal then/else path counts). Mirrors 'flattenBodyVC's recursion so the two
-- lists align positionally.
pathBranchSides :: BodyVC -> [Maybe Bool]
pathBranchSides (SimpleVC _ _)             = [Nothing]
pathBranchSides (BranchVC _ _ thenVC elseVC) =
  [Just True  | _ <- flattenBodyVC thenVC] ++
  [Just False | _ <- flattenBodyVC elseVC]
pathBranchSides (CallVC _ _ _ _ _ _ cont)  = pathBranchSides cont

-- | Count paths in a BodyVC tree with an upper bound.
-- Stops counting once the limit is exceeded (avoids state explosion).
countPathsBounded :: Int -> BodyVC -> Int
countPathsBounded limit = go
  where
    go (SimpleVC _ _) = 1
    go (BranchVC _ _ tvc evc) =
      let tc = go tvc
      in if tc >= limit then tc
         else let ec = go evc
              in min limit (tc + ec)
    go (CallVC _ _ _ _ _ _ cont) = go cont  -- v0.9.0: paths determined by continuation

-- | v0.9.0: Collect all call-pre obligations from a BodyVC tree.
-- Returns (calleeName, preconditionPred, pathGuard) for each CallVC
-- that has a non-Nothing precondition obligation.
-- Path guards are accumulated through BranchVC nodes.
-- F-NIW-4: each obligation carries its path's prior-call context — the result var,
-- sort, and assumed post of every CallVC on the path before it. A later call whose
-- precondition references an earlier call's result (e.g. withdraw-twice's
-- `(withdraw after-first second)`) is then provable under the earlier call's
-- assumed post (assume-guarantee; the trust meet over those callees is taken
-- downstream by TrustReport over the syntactic call graph). Without this context
-- the result var is a free variable in the param-scoped call-pre constraint.
-- | COMP-4 (b) intro-side: every (callee, translated-args) call site in the VC
-- tree, for emitting per-call payload-subtyping obligations. Path-independent
-- (the subtyping is a static fact about the arg/param types, not a runtime
-- obligation), so guards/context are not collected.
collectCallSites :: BodyVC -> [(Name, [FQPred])]
collectCallSites (SimpleVC _ _)               = []
collectCallSites (BranchVC _ _ t e)           = collectCallSites t ++ collectCallSites e
collectCallSites (CallVC c args _ _ _ _ cont) = (c, args) : collectCallSites cont

collectCallPreObligations :: BodyVC -> [(Name, FQPred, FQPred, [(Text, FQSort, FQPred)], [LetBinding])]
collectCallPreObligations = go FQTrue []
  where
    go _guard _calls (SimpleVC _ _) = []
    go guard calls (BranchVC g _ thenVC elseVC) =
      go (conjoin guard g) calls thenVC ++ go (conjoin guard (FQNot g)) calls elseVC
    go guard calls (CallVC callee _args mPre mPost rVar rSort cont) =
      let preObligs = case mPre of
            -- F-NIW-4b: attach the path's let-bindings (which prependLB has pushed
            -- into the leaf of `cont`) so a precondition referencing a let-bound
            -- non-call value (e.g. `(g y)` where `y = x+1`) can be proved under
            -- that value's defining equality. The emission filters them to the
            -- subset in scope at the call.
            Just prePred -> [(callee, prePred, guard, calls, subtreeLbs cont)]
            Nothing      -> []
          -- subsequent obligations may assume this call's post over its result var
          calls' = calls ++ [(rVar, rSort, fromMaybe FQTrue mPost)]
          contObligs = go guard calls' cont
      in preObligs ++ contObligs

-- | F-NIW-4b: all let-bindings reachable in a BodyVC. `prependLB` parks
-- let-bindings at the leaf SimpleVC of a CallVC continuation, so a call-pre
-- obligation's path lbs are gathered from its continuation subtree.
subtreeLbs :: BodyVC -> [LetBinding]
subtreeLbs (SimpleVC lbs _)          = lbs
subtreeLbs (BranchVC _ _ t e)        = subtreeLbs t ++ subtreeLbs e
subtreeLbs (CallVC _ _ _ _ _ _ cont) = subtreeLbs cont

-- | COMP-3b-general: every match-introduced binder (synthetic guard + arm
-- payloads) carried in a 'BranchVC' binder field across the whole VC tree, so the
-- driver can declare them all at trivial refinement FQTrue. This is the SOLE
-- emitter of these binders — it generalizes the former single-shot
-- @extraResultBinds@ from one top-level match to arbitrarily-nested matches.
-- Soundness (professor confirm gate, Q1): each binder is 'freshName'-unique
-- (globally distinct, well-formed flat context) and a payload symbol only occurs
-- in its own arm's path predicates, so a flat FQTrue declaration is vacuous on any
-- constraint where it does not occur — the validity-preserving weakening lemma.
collectBranchBinders :: BodyVC -> [(Name, FQSort, FQPred)]
collectBranchBinders (SimpleVC _ _)            = []
collectBranchBinders (BranchVC _ bs t e)       = bs ++ collectBranchBinders t ++ collectBranchBinders e
collectBranchBinders (CallVC _ _ _ _ _ _ cont) = collectBranchBinders cont

-- | F-NIW-4b: the subset of candidate let-bindings whose RHS free variables are
-- all already in scope (params ∪ prior-call results ∪ already-included lbs),
-- to a fixpoint and in dependency order. Out-of-scope lbs (e.g. branch-local, or
-- bound after the call) are excluded — admitting them would re-introduce free
-- variables. Sound: an lb is a let-definition equality, a tautology in context.
inScopeLbs :: Set.Set Text -> [LetBinding] -> [LetBinding]
inScopeLbs scope lbs0 =
  let (ok, rest) = partition (\lb -> all (`Set.member` scope) (predVars (lbRhs lb))) lbs0
  in if null ok
       then []
       else ok ++ inScopeLbs (foldr (Set.insert . lbName) scope ok) rest

-- ---------------------------------------------------------------------------
-- Predicate helpers (v0.8.0)
-- ---------------------------------------------------------------------------

-- | Conjoin two predicates, simplifying FQTrue identity.
conjoin :: FQPred -> FQPred -> FQPred
conjoin FQTrue q     = q
conjoin p      FQTrue = p
conjoin p      q      = FQAnd [p, q]

-- | Conjoin a list of predicates.
conjoinAll :: [FQPred] -> FQPred
conjoinAll = foldr conjoin FQTrue

-- ---------------------------------------------------------------------------
-- NIW (v0.12): measure-class emission helpers (REF-META-2 §4 / REF-META-3 §4.2)
-- ---------------------------------------------------------------------------

-- | Variables appearing as the argument of a measure application
-- (string-length / list-length) anywhere in an expression. Drives which non-int
-- params need an opaque carrier binder, preserving byte-identical .fq output for
-- measure-free functions.
measureArgVars :: Expr -> Set.Set Name
measureArgVars e = case e of
  EApp "string-length" [EVar v] -> Set.singleton v
  EApp "list-length"   [EVar v] -> Set.singleton v
  EApp _ args   -> Set.unions (map measureArgVars args)
  EOp _ args    -> Set.unions (map measureArgVars args)
  EIf a b c     -> Set.unions (map measureArgVars [a, b, c])
  ELet bs body  -> Set.unions (measureArgVars body : [measureArgVars r | (_, _, r) <- bs])
  EMatch s arms -> Set.unions (measureArgVars s : map (measureArgVars . snd) arms)
  EPair a b     -> Set.union (measureArgVars a) (measureArgVars b)
  ELambda _ b   -> measureArgVars b
  EAwait a      -> measureArgVars a
  EDo steps     -> Set.unions [measureArgVars x | DoStep _ x <- steps]
  _             -> Set.empty

-- | True when a type resolves (through aliases / refinements) to a measure
-- carrier sort (string or list).
isMeasureSort :: AliasMap -> Type -> Bool
isMeasureSort _  TString            = True
isMeasureSort _  (TList _)          = True
isMeasureSort am (TDependent _ b _) = isMeasureSort am b
isMeasureSort am (TCustom n)        = maybe False (isMeasureSort am) (Map.lookup n am)
isMeasureSort _  _                  = False

-- | REF-META-2 §4 emission side-condition: for every measure-term m(t) in a
-- constraint, conjoin the ground range fact (m t) >= 0 into the LHS as a
-- hypothesis — the local-theory-extension instantiation, ground facts per
-- occurring term (never a quantified axiom). Byte-inert when no FQApp is present.
injectRangeFacts :: FQConstraint -> FQConstraint
injectRangeFacts c =
  let apps  = nub (collectApps (reftPred (conLhs c)) ++ collectApps (reftPred (conRhs c)))
      facts = [ FQBinPred FQGe a (FQLit 0) | a <- apps ]
  in if null facts
       then c
       else c { conLhs = (conLhs c) { reftPred = foldr conjoin (reftPred (conLhs c)) facts } }

-- | Measure-application subterms of a predicate.
collectApps :: FQPred -> [FQPred]
collectApps p = case p of
  FQApp _ args     -> p : concatMap collectApps args
  FQBinPred _ l r  -> collectApps l ++ collectApps r
  FQBinArith _ l r -> collectApps l ++ collectApps r
  FQAnd ps         -> concatMap collectApps ps
  FQOr  ps         -> concatMap collectApps ps
  FQNot q          -> collectApps q
  FQKVar _ args    -> concatMap collectApps args
  _                -> []

-- | Head symbol names of the measure applications in a predicate.
appNames :: FQPred -> Set.Set Text
appNames p = case p of
  FQApp f args     -> Set.insert f (Set.unions (map appNames args))
  FQBinPred _ l r  -> Set.union (appNames l) (appNames r)
  FQBinArith _ l r -> Set.union (appNames l) (appNames r)
  FQAnd ps         -> Set.unions (map appNames ps)
  FQOr  ps         -> Set.unions (map appNames ps)
  FQNot q          -> appNames q
  FQKVar _ args    -> Set.unions (map appNames args)
  _                -> Set.empty

-- | UF constant declaration for a measure symbol.
measureConstant :: Text -> FQConstant
measureConstant "listLen" = FQConstant "listLen" [FQList] FQInt
measureConstant n         = FQConstant n          [FQStr]  FQInt  -- strLen + default

-- | F-NIW-1: collect every refinement predicate along a (possibly aliased) type's
-- chain, with its binding variable. Stacked aliases (e.g. NonEmptyWord over Word,
-- §3.4.4 conjunction-at-introduction) contribute all their predicates; each is
-- α-identified to the single param witness by the caller (REF-META-3 review F3).
resolveAllRefinements :: AliasMap -> Type -> [(Name, Expr)]
resolveAllRefinements am t = case t of
  TDependent x base p -> (x, p) : resolveAllRefinements am base
  TCustom n           -> maybe [] (resolveAllRefinements am) (Map.lookup n am)
  _                   -> []

-- | COMP-4 (b): a payload type's declared refinement as (bindingVar, pred),
-- or Nothing for a base/unrefined payload. Conjoins multiply-refined aliases,
-- renamed to a common binding var. Reuses resolveAllRefinements, which already
-- descends a refinement-aliased payload type (PositiveInt → n>0); the Result/
-- TSumType wrapper is peeled by the caller (the driver works per payload arm).
payloadRefinement :: AliasMap -> Type -> Maybe (Name, Expr)
payloadRefinement am t = case resolveAllRefinements am t of
  []             -> Nothing
  ps@((x0, _):_) -> Just (x0, foldr1 (\a b -> EApp "and" [a, b]) [ renameVar x x0 p | (x, p) <- ps ])

-- | COMP-4 (b): the per-arm payload TYPES of a two-arm sum type, each tagged
-- with the "$<arm>" key suffix the driver/refEnv key by. Result → $ok/$err; a
-- two-arm user ADT → $<Ctor>. Empty for a non-sum type. Mirrors the driver's
-- resultKeys/adtKeys arm scheme so the intro-side keys align with the elim-side.
payloadArms :: AliasMap -> Type -> [(Text, Type)]
payloadArms am t = case resolveAliasTy am t of
  TResult okT errT                        -> [("$ok", okT), ("$err", errT)]
  TSumType [(c1, Just t1), (c2, Just t2)] -> [("$" <> c1, t1), ("$" <> c2, t2)]
  _                                       -> []

-- | Rename a free variable in an expression (the refinement binding var → the
-- param name). Refinement predicates are first-order and closed over the single
-- binding var (REF-META-3 W-FirstOrder / W-Closed), so naive capture-free
-- substitution is sound — no inner binder shadows the binding var.
renameVar :: Name -> Name -> Expr -> Expr
renameVar from to = go
  where
    go (EVar v)        = EVar (if v == from then to else v)
    go (EApp f as)     = EApp f (map go as)
    go (EOp o as)      = EOp o (map go as)
    go (EIf a b c)     = EIf (go a) (go b) (go c)
    go (ELet bs bd)    = ELet [(bn, bt, go r) | (bn, bt, r) <- bs] (go bd)
    go (EMatch s arms) = EMatch (go s) [(pat, go bdy) | (pat, bdy) <- arms]
    go (EPair a b)     = EPair (go a) (go b)
    go (ELambda ps bd) = ELambda ps (go bd)
    go (EAwait a)      = EAwait (go a)
    go e               = e

-- | F-NIW-1: the conjoined refinement predicate contributed by refinement-aliased
-- params, each instantiated at the param name (p[param/x]). Nothing if no param
-- is refinement-typed. This becomes part of the function's effective precondition,
-- so the existing pre machinery discharges it both ways: assumed in the body VC
-- (elim) and proven at call sites via call-pre obligations (intro).
paramRefinementPre :: AliasMap -> [(Name, Type)] -> Maybe Expr
paramRefinementPre am params =
  case [ renameVar x n p | (n, t) <- params, (x, p) <- resolveAllRefinements am t ] of
    []    -> Nothing
    preds -> Just (foldr1 (\a b -> EApp "and" [a, b]) preds)

-- | Fold param refinements into a contract's precondition.
augmentContractPre :: AliasMap -> [(Name, Type)] -> Contract -> Contract
augmentContractPre am params c =
  case paramRefinementPre am params of
    Nothing   -> c
    Just rpre -> c { contractPre = Just (andPre (contractPre c) rpre) }
  where
    andPre Nothing  r = r
    andPre (Just p) r = EApp "and" [p, r]

-- | DEF-RET Unit 2: the conjoined refinement predicate contributed by a
-- refinement-aliased RETURN type, instantiated at @result@ (p[result/x]).
-- Nothing if the return is unannotated or base-typed. The guarantee-side dual
-- of 'paramRefinementPre': folded into the function's effective POSTcondition,
-- so the existing post machinery discharges it both ways — proven in the body
-- VC (introduction, §3.4.1) and assumed at call sites via assume-guarantee
-- (elimination). Folds UNCONDITIONALLY (syntactic, pre-verdict, like a hand-
-- written @post@ clause); verdict-gating (asserted floor / refuted exclusion)
-- is the existing trust-closure machinery, not this fold.
returnRefinementPost :: AliasMap -> Maybe Type -> Maybe Expr
returnRefinementPost am mRet = case mRet of
  Nothing -> Nothing
  Just t  -> case [ renameVar x "result" p | (x, p) <- resolveAllRefinements am t ] of
               []    -> Nothing
               preds -> Just (foldr1 (\a b -> EApp "and" [a, b]) preds)

-- | Fold the return refinement into a contract's postcondition (DEF-RET Unit 2).
augmentContractPost :: AliasMap -> Maybe Type -> Contract -> Contract
augmentContractPost am mRet c =
  case returnRefinementPost am mRet of
    Nothing    -> c
    Just rpost -> c { contractPost = Just (andPost (contractPost c) rpost) }
  where
    andPost Nothing  r = r
    andPost (Just p) r = EApp "and" [p, r]

-- | F-NIW-2: bare-variable arguments passed to a measure-refined callee param,
-- anywhere in an expression. These caller vars need carrier binders so the
-- intro-side call-pre obligation (the callee's refinement, substituted) refers
-- to an in-scope symbol. Gated on the callee param being refinement-typed AND
-- carrier-sorted, so measure-free callees contribute nothing (byte-identity).
collectCallArgCarrierVars :: AliasMap -> ContractEnv -> Expr -> Set.Set Name
collectCallArgCarrierVars am cenv = go
  where
    go e = case e of
      EApp f args ->
        let here = case Map.lookup f cenv of
              Just (ps, _, _) ->
                Set.fromList
                  [ v
                  | (EVar v, (_, t)) <- zip args ps
                  , not (null (resolveAllRefinements am t))
                  , isMeasureSort am t ]
              Nothing -> Set.empty
        in Set.union here (Set.unions (map go args))
      EOp _ args    -> Set.unions (map go args)
      EIf a b c     -> Set.unions (map go [a, b, c])
      ELet bs body  -> Set.unions (go body : [go r | (_, _, r) <- bs])
      EMatch s arms -> Set.unions (go s : map (go . snd) arms)
      EPair a b     -> Set.union (go a) (go b)
      ELambda _ b   -> go b
      EAwait a      -> go a
      EDo steps     -> Set.unions [go x | DoStep _ x <- steps]
      _             -> Set.empty

-- | Prepend a let-binding to a BodyVC.
prependLB :: LetBinding -> BodyVC -> BodyVC
prependLB lb (SimpleVC lbs r) = SimpleVC (lb : lbs) r
prependLB lb (BranchVC g bs t e) = BranchVC g bs (prependLB lb t) (prependLB lb e)
prependLB lb (CallVC cal args mPre mPost rVar rSort cont) =
  CallVC cal args mPre mPost rVar rSort (prependLB lb cont)  -- v0.9.0

prependLBs :: [LetBinding] -> BodyVC -> BodyVC
prependLBs lbs bvc = foldr prependLB bvc lbs

-- | v0.9.0 COMP-3: Classify match arms as Result (Success/Error) pattern.
-- Returns Just (successVar, successBody, errorVar, errorBody) if the arms
-- are exactly two with Success and Error constructors (in either order).
-- Returns Nothing for non-Result patterns.
classifyResultArms :: [(Pattern, Expr)] -> Maybe (Name, Expr, Name, Expr)
classifyResultArms arms = case arms of
  [(PConstructor "Success" [PVar s], bodyS), (PConstructor "Error" [PVar e], bodyE)] ->
    Just (s, bodyS, e, bodyE)
  [(PConstructor "Error" [PVar e], bodyE), (PConstructor "Success" [PVar s], bodyS)] ->
    Just (s, bodyS, e, bodyE)
  _ -> Nothing

-- | COMP-4 (d-elim): classify a two-arm match on an arbitrary user sum type.
-- Each arm is a single-payload constructor pattern over two DISTINCT
-- constructors; returns (ctor1, payloadVar1, body1, ctor2, payloadVar2, body2)
-- in source order. Ctor-agnostic generalization of 'classifyResultArms'; the
-- caller resolves each arm's payload sort from the "<v>$<Ctor>" derived keys.
classifyTwoArmAdtArms :: [(Pattern, Expr)] -> Maybe (Name, Name, Expr, Name, Name, Expr)
classifyTwoArmAdtArms arms = case arms of
  [(PConstructor c1 [PVar v1], b1), (PConstructor c2 [PVar v2], b2)]
    | c1 /= c2 -> Just (c1, v1, b1, c2, v2, b2)
  _ -> Nothing

-- | v0.9.0 COMP-3: Replace the continuation of a CallVC.
-- Used for EMatch-over-call: the match's BranchVC becomes the call's continuation.
setCallVCContinuation :: BodyVC -> BodyVC -> BodyVC
setCallVCContinuation (CallVC cal args mPre mPost rVar rSort _cont) newCont =
  CallVC cal args mPre mPost rVar rSort newCont
setCallVCContinuation bvc _newCont = bvc  -- no-op for non-CallVC (shouldn't happen)

-- | Infer the FQSort of a predicate result.
-- In BODY-VC-0, we only support int-typed results.
predSortOf :: FQPred -> FQSort
predSortOf (FQLit _)         = FQInt
predSortOf (FQVar _)         = FQInt  -- in BODY-VC-0, all vars in SortEnv are FQInt
predSortOf (FQBinArith _ _ _) = FQInt
predSortOf (FQBinPred _ _ _) = FQBool  -- comparisons return bool
predSortOf FQTrue            = FQBool
predSortOf FQFalse           = FQBool
predSortOf (FQNot _)         = FQBool
predSortOf (FQAnd _)         = FQBool
predSortOf (FQOr _)          = FQBool
predSortOf (FQKVar _ _)      = FQInt  -- fallback
predSortOf (FQApp _ _)       = FQInt  -- NIW: measures are integer-valued

-- | Build a SortEnv from function parameters (int-typed only for BODY-VC-0).
-- v0.8.0: uses isIntLike with alias map to resolve type aliases.
buildSortEnv :: AliasMap -> [(Name, Type)] -> SortEnv
buildSortEnv aliases params = Map.fromList
  [ (n, typeToSort t) | (n, t) <- params, isIntLike aliases t ]

-- ---------------------------------------------------------------------------
-- Operator lookup tables (v0.8.0, v0.10: moved to GuardClassifier.hs)
-- ---------------------------------------------------------------------------
-- lookupArithOp and lookupPredOp are now imported from LLMLL.GuardClassifier.
-- Internal uses in this module (exprToPred, bodyToPredM) go through the import.

-- ---------------------------------------------------------------------------
-- Compositional verification helpers (v0.9.0 COMP-1)
-- ---------------------------------------------------------------------------

-- | Capture-free predicate substitution.
-- Replaces free variables in a FQPred according to the substitution map.
-- Variables not in the map are left unchanged.
applySubst :: Map Name FQPred -> FQPred -> FQPred
applySubst subst (FQVar v) = Map.findWithDefault (FQVar v) v subst
applySubst subst (FQBinPred op l r) = FQBinPred op (applySubst subst l) (applySubst subst r)
applySubst subst (FQBinArith op l r) = FQBinArith op (applySubst subst l) (applySubst subst r)
applySubst subst (FQAnd ps) = FQAnd (map (applySubst subst) ps)
applySubst subst (FQOr ps) = FQOr (map (applySubst subst) ps)
applySubst subst (FQNot p) = FQNot (applySubst subst p)
applySubst subst (FQApp f args) = FQApp f (map (applySubst subst) args)  -- NIW: substitute measure args
applySubst _ p = p  -- FQLit, FQTrue, FQFalse unchanged

-- | Does the postcondition use constructor-dependent reasoning?
-- If the postcondition contains EMatch on "result", the EMatch encoding
-- cannot safely assume the same postcondition on both branches.
-- Full constructor-decomposed postconditions are deferred (COMP-0 §13).
-- Added to TCB (COMP-0 Rev 2, Issue 2).
isConstructorDependent :: Expr -> Bool
isConstructorDependent (EMatch (EVar "result") _) = True
isConstructorDependent (EMatch _ _)                = False
isConstructorDependent (EApp _ args) = any isConstructorDependent args
isConstructorDependent (ELet _ body) = isConstructorDependent body
isConstructorDependent (EIf _ t e)   = isConstructorDependent t || isConstructorDependent e
isConstructorDependent _             = False
