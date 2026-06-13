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
  , buildSortEnv                 -- v0.10 (Language Team Correction 1)
  , applySubst
  , isConstructorDependent
  , collectCallPreObligations
    -- * Body-VC engine (exported for testing)
  , bodyToPredFrom
  , flattenBodyVC
  , countPathsBounded
    -- * Contract translation (exported for testing)
  , exprToPred
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
import Data.List (nub)
import Control.Monad (forM_, forM, when, unless)
import Control.Monad.State.Strict (State, evalState, get, put)
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
  | BranchVC FQPred BodyVC BodyVC
    -- ^ An if-then-else: guard, then-VC, else-VC
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
    aug params c = augmentContractPre am params c
    go (SDefLogic name params mRet contract _) = Just (name, (params, aug params contract, mRet))
    go (SLetrec name params mRet contract _ _) = Just (name, (params, aug params contract, mRet))
    -- LT-INV (v0.11)
    go (SDef      name params mRet contract _) = Just (name, (params, aug params contract, mRet))
    go (SDefShell name params mRet contract _) = Just (name, (params, aug params contract, mRet))
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
  let contract = augmentContractPre aliases params contract0

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
            let sortEnv = buildSortEnv aliases params
            -- Translate body
            seed <- readIORef bodyCounterRef
            let (newSeed, mBodyVC) = bodyToPredFrom seed sortEnv cenv sccSet body
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
                        retSort = maybe FQInt typeToSort mRet
                    forM_ (zip [0::Int ..] paths) $ \(pathIdx, (guard, lbs, resultPred)) -> do
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
                      -- Determine tag based on guard
                      let tag = case guard of
                                  FQTrue -> "body-post"
                                  _      -> if pathIdx < length (flattenBodyVC bvc) `div` 2
                                             then "body-post-then"
                                             else "body-post-else"
                      cid <- freshCid
                      let allEnvIds = envIds ++ lbBindIds ++ [rbid]
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
                      forM_ (zip [0::Int ..] callObligations) $ \(cpIdx, (callee, prePred, pathGuard)) -> do
                        -- Emit binders for all int-typed params (same env as body-post)
                        -- The call-pre constraint shares the function's parameter environment.
                        cid <- freshCid
                        let cpTag = "call-pre:" <> callee
                            -- LHS: path guard ∧ caller pre (context in which the call occurs)
                            lhsPred = conjoinAll $ [pathGuard | pathGuard /= FQTrue]
                                                 ++ maybe [] (:[]) mPre
                            lhs = FQReft "v" FQInt lhsPred
                            -- RHS: callee's precondition (PROVE polarity — caller must prove this)
                            rhs = FQReft "v" FQInt prePred
                            c = FQConstraint cid envIds lhs rhs [name, cpTag]
                        addConst c
                        let ptr = "/statements/" <> T.pack (show stmtIdx) <> "/body"
                        addOrigin cid (ConstraintOrigin name cpTag ptr srcFile)

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
isIntLike _  _                     = False

typeToSort :: Type -> FQSort
typeToSort TInt    = FQInt
typeToSort TBool   = FQBool
typeToSort TString = FQStr            -- NIW: opaque carrier for string measures
typeToSort (TList _) = FQList         -- NIW: opaque carrier for list measures
typeToSort (TDependent _ base _) = typeToSort base
typeToSort _     = FQInt  -- conservative default

typeSorts :: Name -> Type -> [FQDataDecl]
typeSorts name (TSumType ctors) =
  [FQDataDecl name 0 [(c, 0) | (c, _) <- ctors]]
typeSorts _ _ = []

maybeToList :: Maybe a -> [a]
maybeToList Nothing  = []
maybeToList (Just x) = [x]

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
bodyToPredFrom :: Int -> SortEnv -> ContractEnv -> Set.Set Name -> Expr -> (Int, Maybe BodyVC)
bodyToPredFrom seed sortEnv cenv sccSet expr =
  let (result, finalCounter) = runStateFrom seed (bodyToPredM Map.empty sortEnv cenv sccSet expr)
  in (finalCounter, result)
  where
    -- Run a State Int computation with a given starting value.
    -- Returns (result, finalState).
    runStateFrom :: Int -> State Int a -> (a, Int)
    runStateFrom s action =
      let go = do { r <- action; c <- get; return (r, c) }
      in evalState go s

-- | Fresh name generator for alpha-renaming.
freshName :: Name -> State Int Text
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
            -> State Int (Maybe BodyVC)

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
  mGuard <- guardToPredM env se guard
  case mGuard of
    Nothing -> return Nothing
    Just gp -> do
      mthen <- bodyToPredM env se cenv sccSet thenE
      melse <- bodyToPredM env se cenv sccSet elseE
      case (mthen, melse) of
        (Just tvc, Just evc) -> return (Just (BranchVC gp tvc evc))
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
        Just (BranchVC gp tvc evc) ->
          -- Prepend this binding to both branches
          return (Just (BranchVC gp (prependLB lb tvc) (prependLB lb evc)))
        -- v0.9.0: SimpleVC RHS but body produces CallVC — prepend binding
        Just cvc@(CallVC {}) ->
          return (Just (prependLB lb cvc))
    -- v0.9.0: RHS is a CallVC — thread the body as the continuation (Issue 3)
    Just (CallVC cal callArgs mPre mPost rVar rSort _cont) -> do
      renamed <- freshName v
      let env' = Map.insert v renamed env
          se'  = Map.insert renamed rSort se
      mBodyVC <- bodyToPredM env' se' cenv sccSet body
      case mBodyVC of
        Nothing -> return Nothing
        Just bvc -> return $ Just $ CallVC cal callArgs mPre mPost rVar rSort bvc
    -- RHS is a branch (EIf in let RHS) — hoist via flattening.
    -- Single-path degenerate branches are handled; multi-path falls back.
    Just bvc@(BranchVC _ _ _) -> do
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
            Just (BranchVC gp tvc evc) ->
              return (Just (BranchVC gp
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
            case scrutVC of
              SimpleVC [] _scrutPred ->
                return (Just (BranchVC (FQVar guardVar) svc evc))
              CallVC {} ->
                -- The scrutinee is a function call — wrap the branch as CallVC continuation
                -- The CallVC result is the match scrutinee; branch discriminates its constructor
                return (Just (setCallVCContinuation scrutVC (BranchVC (FQVar guardVar) svc evc)))
              _ ->
                -- Scrutinee produced a complex VC (branch, etc.) — fallback
                return Nothing
          _ -> return Nothing

-- Everything else: match, app (user-defined without contract), lambda, etc. → fallback
bodyToPredM _ _ _ _ _ = return Nothing

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
flattenBodyVC (BranchVC guard thenVC elseVC) =
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

-- | Count paths in a BodyVC tree with an upper bound.
-- Stops counting once the limit is exceeded (avoids state explosion).
countPathsBounded :: Int -> BodyVC -> Int
countPathsBounded limit = go
  where
    go (SimpleVC _ _) = 1
    go (BranchVC _ tvc evc) =
      let tc = go tvc
      in if tc >= limit then tc
         else let ec = go evc
              in min limit (tc + ec)
    go (CallVC _ _ _ _ _ _ cont) = go cont  -- v0.9.0: paths determined by continuation

-- | v0.9.0: Collect all call-pre obligations from a BodyVC tree.
-- Returns (calleeName, preconditionPred, pathGuard) for each CallVC
-- that has a non-Nothing precondition obligation.
-- Path guards are accumulated through BranchVC nodes.
collectCallPreObligations :: BodyVC -> [(Name, FQPred, FQPred)]
collectCallPreObligations = go FQTrue
  where
    go _guard (SimpleVC _ _) = []
    go guard (BranchVC g thenVC elseVC) =
      go (conjoin guard g) thenVC ++ go (conjoin guard (FQNot g)) elseVC
    go guard (CallVC callee _args mPre _mPost _rVar _rSort cont) =
      let preObligs = case mPre of
            Just prePred -> [(callee, prePred, guard)]
            Nothing      -> []
          contObligs = go guard cont
      in preObligs ++ contObligs

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
prependLB lb (BranchVC g t e) = BranchVC g (prependLB lb t) (prependLB lb e)
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
