-- |
-- Module      : LLMLL.AbstractionVerdict
-- Description : ABSTRACTION-VERDICT-1, an UNSAFE answer that may rest on the
--               missing call congruence is a fallback, not a refutation.
--
-- docs/design/byte-io-proposal.md Rev 2, Part 0, clause 2 (P1 narrowing and
-- the professor appendix, P15 to P18).
--
-- The body VC gives every call a fresh result binder and asserts no equality
-- between two of them. When one constraint holds two or more call results of
-- one callee (a contracted callee, a self-call, or a call through a
-- function-typed parameter), an UNSAFE answer can be a model in which two
-- equal calls return different values. No pure function does that, so the
-- answer is not a disproof. The emitter marks those constraints
-- ('erAbstracted'); this module reads the mark AFTER the solver ran.
--
-- A function is reclassified when every UNSAFE constraint it owns carries the
-- mark. It leaves the body-faithful set and takes the fallback outcome with
-- cause 'FallbackAbstraction' and the construct @abstraction:app:<callee>@: its
-- post is assumed, not proved, and it is not reported refuted. A function with
-- one UNSAFE constraint that does NOT carry the mark keeps every id: it stays
-- refuted (or measure-not-decreasing) exactly as before, because a single
-- unmarked failure is a modular disproof on its own (P16, P17).
--
-- The cost is stated, not hidden (A4 in the design): a post that is false and
-- whose only refutation needs two self-calls is reported as a fallback too.
--
-- The rule only ever moves an UNSAFE answer toward a weaker claim. It never
-- turns a constraint the solver did not answer SAFE into a proof: a function
-- it reclassifies is NOT body-faithful afterwards, so no @verified@ record is
-- written for it.
--
-- CALLEE-POST-UNASSUMED-1 (post-conj-split professor review P1, P8) shares
-- this path with a second mark. The emitter also marks a constraint whose
-- environment holds the result of a call whose callee post exists and was not
-- assumed at that call ('erPostUnassumed'). The verifier dropped an authored
-- hypothesis there, so an UNSAFE answer on it is not a disproof either: a
-- function is reported refuted only when every hypothesis of every failing
-- constraint is the authored one. A failing id is a candidate when it carries
-- EITHER mark; rules 2 to 4 are unchanged. The cause is decided per function:
-- 'FallbackAbstraction' when every failing id of the function carries the
-- abstraction mark (the ABSTRACTION-VERDICT-1 output, byte for byte), and
-- 'FallbackCalleePostUnassumed' with the construct
-- @post-unassumed:app:<callee>@ otherwise. The stated cost (P1): a wrong
-- caller of such a callee falls back too.
--
-- CLAUSE-WELLDEF-1 (clause-welldef-proposal.md Rev 3 §4.4) partitions each
-- failing id by its clause: WD (@wd-pre@, @wd-post@), MEAS (@descent@,
-- @decreases@) and TRUTH (the rest). An id is complete unless it is a
-- candidate (it carries a mark and its function is body-faithful).
--
-- Rule 1: a function with a complete failing id keeps every id, and gets the
-- hard marker of each partition that holds a complete id: 'aoIllDefined'
-- (WD, no body VC needed), 'aoMeasureBad' (MEAS) and 'aoRefuted' (TRUTH, the
-- function body-faithful). A marked id never sets a hard marker, so a marked
-- TRUTH id beside a complete MEAS id is no longer 'refuted' (V14), and a
-- marked MEAS id beside a complete TRUTH id is no longer
-- measure-not-decreasing (V14b).
--
-- Rule 2: otherwise the function falls back with one cause. Step 1: every
-- failing id is WD gives 'FallbackClauseWelldefUnproved', whose construct is
-- @welldef:@ plus the construct steps 2-3 pick over the same ids. Steps 2-4
-- are the shipped 'decide'.

module LLMLL.AbstractionVerdict
  ( AbstractionOutcome(..)
  , applyAbstractionVerdict
  , aoFallbackFns
  , aoReportCtx
  , abstractionConstruct
  , abstractionRepair
  , postUnassumedConstruct
  , postUnassumedRepair
  , welldefConstruct
  , WdFailKind(..)
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Maybe (isJust, isNothing)

import LLMLL.Syntax (Name)
import LLMLL.FixpointEmit (EmitResult(..), FallbackCause(..), renderFallbackCause, abstractedBuiltins)
import LLMLL.FixpointIR (FQConstraintId)
import LLMLL.DiagnosticFQ (FQVerifyResult(..), ConstraintOrigin(..), isWdClause, WdFailKind(..), WdReportCtx(..))
import LLMLL.Diagnostic (Diagnostic(..), mkBodyFallbackWarning, mkDecreasesUndischarged, mkWarning)

-- | The verdict after the rule ran.
data AbstractionOutcome = AbstractionOutcome
  { aoResult       :: FQVerifyResult
    -- ^ the effective verdict: the reclassified ids are gone, and 'FQSafe'
    -- when none remain
  , aoEmit         :: EmitResult
    -- ^ the emit result with the reclassified functions moved to the
    -- fallback lists
  , aoReclassified :: [(Text, Name)]
    -- ^ each function reclassified with cause 'FallbackAbstraction', with the
    -- callee that marked it, in the order its first failing id was reported
  , aoUnassumed    :: [(Text, Name)]
    -- ^ CALLEE-POST-UNASSUMED-1: each function reclassified with cause
    -- 'FallbackCalleePostUnassumed', with the callee whose post was not
    -- assumed, in the same order
  , aoWelldefUnproved :: [(Text, Text)]
    -- ^ CLAUSE-WELLDEF-1: each function reclassified with cause
    -- 'FallbackClauseWelldefUnproved', with its @welldef:@ construct
  , aoIllDefined   :: Set Text
    -- ^ CLAUSE-WELLDEF-1: functions with a complete failing WD id (no body
    -- VC needed: a @wd-pre@ id does not read the body, V12)
  , aoMeasureBad   :: Set Text
    -- ^ functions with a complete failing MEAS id (measure-not-decreasing)
  , aoRefuted      :: Set Text
    -- ^ body-faithful functions with a complete failing TRUTH id
  , aoWdFailing    :: Map Text WdFailKind
    -- ^ each function with a failing WD id, complete or marked only (N5)
  , aoMarkedIds    :: Set FQConstraintId
    -- ^ the kept failing ids that carry a mark
  } deriving (Show)

-- | Every function the rule moved to the fallback outcome, under any cause.
-- A reader that must not count a reclassified function as proved (or as a
-- kill) reads this, not 'aoReclassified'.
aoFallbackFns :: AbstractionOutcome -> [Text]
aoFallbackFns ao = map fst (aoReclassified ao) ++ map fst (aoUnassumed ao)
                ++ map fst (aoWelldefUnproved ao)

-- | CLAUSE-WELLDEF-1: what the diagnostics renderer needs from the verdict.
aoReportCtx :: AbstractionOutcome -> WdReportCtx
aoReportCtx ao = WdReportCtx (aoMarkedIds ao) (aoWdFailing ao)

-- | CALLEE-POST-UNASSUMED-1: the attribution string of a function reclassified
-- because a callee post was not assumed at a call.
postUnassumedConstruct :: Name -> Text
postUnassumedConstruct g = "post-unassumed:app:" <> g

-- | The repair sentence 'W-BODY-FALLBACK' adds for 'FallbackCalleePostUnassumed'.
-- The second sentence is true while a callee post is assumed whole or not at
-- all; POST-CONJ-SPLIT-1 must change it.
postUnassumedRepair :: Name -> Text
postUnassumedRepair g =
  " The solver's counterexample may need a fact from the post of '" <> g
  <> "', which the verifier did not assume at this call. A callee post is assumed only when all of it is inside the decidable fragment."

-- | The attribution string a reclassified function carries in
-- 'erFallbackConstructs', 'W-BODY-FALLBACK' and the @abstraction_fallback@
-- verdict key.
abstractionConstruct :: Name -> Text
abstractionConstruct g = "abstraction:app:" <> g

-- | CLAUSE-WELLDEF-1: the construct of a 'FallbackClauseWelldefUnproved'
-- function, @welldef:@ plus the construct of the inner cause.
welldefConstruct :: Text -> Text
welldefConstruct inner = "welldef:" <> inner

-- | The one repair sentence 'W-BODY-FALLBACK' adds for this cause. It is true
-- when the two calls are syntactically equal (bind one, reuse the result); for
-- calls whose arguments are only equal under a guard it names the limit.
abstractionRepair :: Name -> Text
abstractionRepair g
  -- CHAR-CODE-1: a clause 1 mark needs no second call, so there is nothing to
  -- bind: the verifier holds only a partial fact about the one result.
  | g `Set.member` abstractedBuiltins =
      " The verifier knows only part of what '" <> g <> "' returns, so the counterexample may be one no run can produce."
  | otherwise =
      " If two calls to '" <> g <> "' take equal arguments, bind one call with let and reuse its result."

-- | One reclassified function: its cause, the callee its marks name, and for
-- 'FallbackClauseWelldefUnproved' the inner cause steps 2-3 picked (the cause
-- itself otherwise), with its failing WD ids.
data Reclass = Reclass
  { rcFn     :: Text
  , rcCause  :: FallbackCause
  , rcCallee :: Name
  , rcInner  :: FallbackCause
  , rcWdIds  :: [FQConstraintId]
  }

-- | The failing-id partition of §4.4.
data Partition = PWd | PMeas | PTruth
  deriving (Eq)

partitionOf :: Text -> Partition
partitionOf c
  | isWdClause c                      = PWd
  | c `elem` ["descent", "decreases"] = PMeas
  | otherwise                         = PTruth

-- | Apply the rule to one solver answer. 'FQSafe', 'FQError' and
-- 'FQResourceLimit' pass through unchanged, with empty sets.
applyAbstractionVerdict :: EmitResult -> FQVerifyResult -> AbstractionOutcome
applyAbstractionVerdict er r = case r of
  FQUnsafe ids ->
    AbstractionOutcome
      { aoResult       = if null reclassList then r
                         else if null kept then FQSafe else FQUnsafe kept
      , aoEmit         = er'
      , aoReclassified = [ (rcFn c, rcCallee c) | c <- reclassList, rcCause c == FallbackAbstraction ]
      , aoUnassumed    = [ (rcFn c, rcCallee c) | c <- reclassList, rcCause c == FallbackCalleePostUnassumed ]
      , aoWelldefUnproved = [ (rcFn c, constructOf c) | c <- reclassList, rcCause c == FallbackClauseWelldefUnproved ]
      , aoIllDefined   = hardFns PWd
      , aoMeasureBad   = hardFns PMeas
      , aoRefuted      = Set.filter (`Set.member` faithful) (hardFns PTruth)
      , aoWdFailing    = Map.fromListWith worst
                           [ (coFunction o, if isNothing (candidate i) then WdComplete else WdMarkedOnly)
                           | i <- ids, Just o <- [Map.lookup i table], isWdClause (coClause o) ]
      , aoMarkedIds    = Set.fromList [ i | i <- kept, isJust (candidate i) ]
      }
    where
      table    = erConstraintTable er
      faithful = Set.fromList (erBodyFaithfulFns er)
      fnOf i   = coFunction <$> Map.lookup i table
      partOf i = maybe PTruth (partitionOf . coClause) (Map.lookup i table)
      absMark i = Map.lookup i (erAbstracted er)
      cpuMark i = Map.lookup i (erPostUnassumed er)
      -- Rule 1: a candidate carries at least one mark, has an origin, and
      -- belongs to a body-faithful function. The clause does not matter: a
      -- marked descent or decreases id is a candidate too (the user-approved
      -- extension), and so is a marked WD id (CLAUSE-WELLDEF-1).
      candidate i = case Map.lookup i table of
        Just o | coFunction o `Set.member` faithful
               , isJust (absMark i) || isJust (cpuMark i) -> Just (coFunction o)
        _                                                 -> Nothing
      -- Rule 2: one non-candidate id keeps the whole function.
      blocked  = Set.fromList [ f | i <- ids, isNothing (candidate i), Just f <- [fnOf i] ]
      candIds  = [ (f, i) | i <- ids, Just f <- [candidate i], not (f `Set.member` blocked) ]
      reclassList = [ decide f [ i | (f', i) <- candIds, f' == f ] | f <- nubOrd (map fst candIds) ]
      -- CLAUSE-WELLDEF-1 rule 1: the hard markers come from the complete
      -- (non-candidate) ids only, by partition.
      hardFns p = Set.fromList [ f | i <- ids, isNothing (candidate i), partOf i == p, Just f <- [fnOf i] ]
      worst WdComplete _ = WdComplete
      worst _ WdComplete = WdComplete
      worst _ _          = WdMarkedOnly
      -- The cause per function. CLAUSE-WELLDEF-1 step 1: every failing id is
      -- WD → 'FallbackClauseWelldefUnproved', its construct the one steps 2-3
      -- pick over the same ids. Step 2: every failing id carries the
      -- abstraction mark → 'FallbackAbstraction', named by the first id's
      -- callee (the ABSTRACTION-VERDICT-1 output). Step 3: some id carries
      -- only the new mark → 'FallbackCalleePostUnassumed', named by the
      -- new-mark callee of the first failing id that carries it.
      decide f is =
        let (inner, g) = shipped is
            wdIds      = [ i | i <- is, partOf i == PWd ]
        in if length wdIds == length is
             then Reclass f FallbackClauseWelldefUnproved g inner wdIds
             else Reclass f inner g inner wdIds
      shipped is = case ( [ g | i <- is, Just g <- [absMark i] ]
                        , [ g | i <- is, Just g <- [cpuMark i] ] ) of
        (g : gs, _) | length (g : gs) == length is -> (FallbackAbstraction, g)
        (_, g : _)                                 -> (FallbackCalleePostUnassumed, g)
        -- unreachable: a candidate carries one of the two marks
        (g : _, [])                                -> (FallbackAbstraction, g)
        ([], [])                                   -> (FallbackAbstraction, "")
      reclass  = Set.fromList (map rcFn reclassList)
      -- Rule 3: an id with no origin is kept.
      kept     = [ i | i <- ids, maybe True (not . (`Set.member` reclass)) (fnOf i) ]
      er'      = reclassifyEmit table reclassList er
  _ -> AbstractionOutcome { aoResult = r, aoEmit = er, aoReclassified = [], aoUnassumed = []
                          , aoWelldefUnproved = [], aoIllDefined = Set.empty
                          , aoMeasureBad = Set.empty, aoRefuted = Set.empty
                          , aoWdFailing = Map.empty, aoMarkedIds = Set.empty }

-- | The construct a reclassified function carries.
constructOf :: Reclass -> Text
constructOf c = case rcCause c of
  FallbackClauseWelldefUnproved -> welldefConstruct (innerConstruct (rcInner c) (rcCallee c))
  cause                         -> innerConstruct cause (rcCallee c)
  where
    innerConstruct FallbackCalleePostUnassumed g = postUnassumedConstruct g
    innerConstruct _                           g = abstractionConstruct g

-- | First-occurrence order, without duplicates.
nubOrd :: [Text] -> [Text]
nubOrd = go Set.empty
  where
    go _ [] = []
    go seen (x : rest)
      | x `Set.member` seen = go seen rest
      | otherwise           = x : go (Set.insert x seen) rest

-- | Rule 4: move each reclassified function to the fallback outcome, as the
-- emitter does for every other fallback cause, with its own cause.
-- CLAUSE-WELLDEF-1: a 'FallbackClauseWelldefUnproved' function also gets one
-- @W-CLAUSE-WELLDEF-UNPROVED@ warning per failing WD id, pointed at the clause.
reclassifyEmit :: Map FQConstraintId ConstraintOrigin -> [Reclass] -> EmitResult -> EmitResult
reclassifyEmit _ [] er = er
reclassifyEmit table rs er = er
  { erBodyFaithfulFns    = [ n | n <- erBodyFaithfulFns er, not (n `Set.member` moved) ]
  , erBodyFallback       = erBodyFallback er ++ map rcFn rs
  , erBodyFallbackCauses = erBodyFallbackCauses er ++ [ (rcFn c, rcCause c) | c <- rs ]
  , erFallbackConstructs = erFallbackConstructs er ++ [ (rcFn c, [constructOf c]) | c <- rs ]
  , erDiagnostics        = erDiagnostics er ++ concatMap diagsFor rs
  }
  where
    moved = Set.fromList (map rcFn rs)
    repairOf FallbackCalleePostUnassumed g = postUnassumedRepair g
    repairOf _                           g = abstractionRepair g
    diagsFor c =
      let f     = rcFn c
          cause = renderFallbackCause (rcCause c)
          w     = mkBodyFallbackWarning f cause [constructOf c] []
      in  w { diagMessage = diagMessage w <> repairOf (rcInner c) (rcCallee c) }
        : [ welldefWarning f o | rcCause c == FallbackClauseWelldefUnproved
                               , i <- rcWdIds c, Just o <- [Map.lookup i table] ]
        ++ [ mkDecreasesUndischarged f cause i | Just i <- [lookup f (erMeasuredRecursive er)] ]
    welldefWarning f o =
      let clause = if coClause o == "wd-pre" then "pre" else "post"
          msg = "W-CLAUSE-WELLDEF-UNPROVED: the " <> clause <> " of '" <> f
                <> "' is not proved defined where it is evaluated"
                <> maybe "" (": " <>) (coSite o)
                <> ". Its truth was proved, but on the path that reaches it the verifier did not assume every fact of a call it makes, so the clause is kept and checked at run time."
      in (mkWarning Nothing msg)
           { diagCode    = Just "W-CLAUSE-WELLDEF-UNPROVED"
           , diagPointer = Just (coJsonPtr o) }
