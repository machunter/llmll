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
--
-- MUL-VAR-1 (mul-var-proposal.md Rev 3a, "The mark", "Verdict and recheck")
-- adds a third mark. The emitter marks each constraint that names a monomial
-- symbol @mul##k@ ('erProductMarked'): an UNSAFE answer on it may rest on the
-- product abstraction. The first argument holds the ids the native recheck
-- ('LLMLL.ProductRecheck') cleared with a validated model; a cleared id loses
-- the product mark, and it keeps any other mark. Three branches:
--
-- 1. A product-marked id is a candidate whether or not its function is
--    body-faithful. The other marks keep their rule.
-- 2. A function already in fallback keeps its first cause: 'reclassifyEmit'
--    gives it no second entry in 'erBodyFallback' or 'erBodyFallbackCauses'.
-- 3. The welldef warning of such a function says that the clause's truth was
--    not checked, because its body is outside the fragment.
--
-- A function whose failing ids are all marked, and some only by the product
-- mark, falls back with the construct @abstraction:nonlinear:*@.
--
-- CALL-RESULT-MARK-1 (byte-io-proposal Rev 2b items 2 and 8). Clause 1 of the
-- abstraction mark is now the cone of influence ('LLMLL.AbstractionCone'), so
-- a constraint whose failure does not depend on a partially known result is
-- unmarked and refutes. What a refuted function CITES changes too (H4): rule
-- 1 still keeps every id of a function with a complete failing id, but a kept
-- id that carries a mark ('aoMarkedIds') is shown as "may fail" (diagnostic
-- kind @lh-may-fail@, a warning), with the construct of the mark that hit it
-- ('aoMarkCause'). The obligation report and @patch@ read 'aoCitedResult',
-- the kept ids without the marked ones. Exit codes, the solver verdict and
-- the per-function sets do not change. Every function in 'aoRefuted',
-- 'aoIllDefined' or 'aoMeasureBad' keeps at least one cited id: it is kept
-- only through a non-candidate id (rule 2), and the hard sets read only
-- non-candidate ids.
--
-- BYTES-TABULATE-1 (image-library-proposal Part B, "The generator is a
-- callee"; plan finding 5) adds a second rule, 'applyTabulateGenVerdict', run
-- after the one above on every answer. A body-faithful function that
-- tabulates over a generator that is not body-faithful and verified moves to
-- the fallback outcome with cause 'FallbackTabulateGenUnverified' and the
-- construct @tabulate-gen:<g>@. A function in a hard set (refuted, ill-defined,
-- measure-not-decreasing) is never moved: T2 and T3 rest on the generator's
-- contract, not its body, so its own failure stands.

module LLMLL.AbstractionVerdict
  ( AbstractionOutcome(..)
  , applyAbstractionVerdict
  , aoCitedResult
  , aoFallbackFns
  , aoReportCtx
  , abstractionConstruct
  , nonlinearConstruct
  , abstractionRepair
  , productRepair
  , postUnassumedConstruct
  , postUnassumedRepair
  , welldefConstruct
  , WdFailKind(..)
    -- * BYTES-TABULATE-1: the post-solver generator rule
  , applyTabulateGenVerdict
  , tabulateGenConstruct
  , tabulateGenRepair
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
import LLMLL.Diagnostic (Diagnostic(..), mkBodyFallbackWarning, mkDecreasesUndischarged, mkWarning, mkBodyFallbackProduct, ProductWhy(..))
import qualified LLMLL.ProductNF as PNF

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
    -- (MUL-VAR-1: the callee is empty for a product; read
    -- 'aoAbstractionConstructs' for the construct)
  , aoAbstractionConstructs :: [(Text, Text)]
    -- ^ MUL-VAR-1 (finding F11): the same functions, each with its construct:
    -- @abstraction:app:<callee>@, or @abstraction:nonlinear:*@ for a product.
    -- The @abstraction_fallback@ key and the text lines read this.
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
  , aoMarkCause    :: Map FQConstraintId Text
    -- ^ CALL-RESULT-MARK-1 (H4): for each id in 'aoMarkedIds', the construct
    -- of the mark that hit it: @abstraction:app:<g>@, else
    -- @post-unassumed:app:<g>@, else @abstraction:nonlinear:*@
  , aoTabulateUnverified :: [(Text, Name)]
    -- ^ BYTES-TABULATE-1: each function 'applyTabulateGenVerdict' moved with
    -- cause 'FallbackTabulateGenUnverified', with the first generator that is
    -- not verified, in body-faithful order
  } deriving (Show)

-- | CALL-RESULT-MARK-1 (H4): the failing ids a refuted function cites. The
-- kept ids that carry no mark; the effective result unchanged when it is not
-- 'FQUnsafe'. Never an empty 'FQUnsafe' for a kept function (see the module
-- header), but a defensive fallback returns the effective result when every
-- kept id is marked.
aoCitedResult :: AbstractionOutcome -> FQVerifyResult
aoCitedResult ao = case aoResult ao of
  FQUnsafe kept
    | cited@(_ : _) <- [ i | i <- kept, not (i `Set.member` aoMarkedIds ao) ] -> FQUnsafe cited
  r -> r

-- | Every function the rule moved to the fallback outcome, under any cause.
-- A reader that must not count a reclassified function as proved (or as a
-- kill) reads this, not 'aoReclassified'.
aoFallbackFns :: AbstractionOutcome -> [Text]
aoFallbackFns ao = map fst (aoReclassified ao) ++ map fst (aoUnassumed ao)
                ++ map fst (aoWelldefUnproved ao) ++ map fst (aoTabulateUnverified ao)

-- | CLAUSE-WELLDEF-1: what the diagnostics renderer needs from the verdict.
aoReportCtx :: AbstractionOutcome -> WdReportCtx
aoReportCtx ao = WdReportCtx (aoMarkedIds ao) (aoWdFailing ao) (aoMarkCause ao)

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

-- | BYTES-TABULATE-1: the construct of a function that tabulates over a
-- generator that is not verified.
tabulateGenConstruct :: Name -> Text
tabulateGenConstruct g = "tabulate-gen:" <> g

-- | BYTES-TABULATE-1: the repair sentence 'W-BODY-FALLBACK' adds for
-- 'FallbackTabulateGenUnverified'.
tabulateGenRepair :: Name -> Text
tabulateGenRepair g =
  " The generator '" <> g <> "' is not verified, and the buffer's content is its values. Verify the module of '"
  <> g <> "' first, with its body inside the decidable fragment."

-- | The attribution string a reclassified function carries in
-- 'erFallbackConstructs', 'W-BODY-FALLBACK' and the @abstraction_fallback@
-- verdict key.
abstractionConstruct :: Name -> Text
abstractionConstruct g = "abstraction:app:" <> g

-- | MUL-VAR-1: the construct of a function whose failing ids rest on the
-- product abstraction.
nonlinearConstruct :: Text
nonlinearConstruct = "abstraction:nonlinear:*"

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

-- | MUL-VAR-1 ("Messages", the "two calls" texts): the repair sentence for a
-- product, which needs no second call.
productRepair :: Text
productRepair = " Restate the post, or supply evidence with ?proof-required."

-- | One reclassified function: its cause, the callee its marks name, and for
-- 'FallbackClauseWelldefUnproved' the inner cause steps 2-3 picked (the cause
-- itself otherwise), with its failing WD ids.
data Reclass = Reclass
  { rcFn     :: Text
  , rcCause  :: FallbackCause
  , rcCallee :: Name
  , rcInner  :: FallbackCause
  , rcWdIds  :: [FQConstraintId]
  , rcProduct :: Bool
    -- ^ MUL-VAR-1: the construct is @abstraction:nonlinear:*@ ('rcCallee' is
    -- then empty)
  , rcProdIds :: [FQConstraintId]
    -- ^ MUL-VAR-1: the failing ids that carry the product mark, in report
    -- order; 'W-BODY-FALLBACK' points at one of them
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
--
-- MUL-VAR-1: the first argument is the set of ids the native recheck cleared
-- (a validated counterexample). A caller with no recheck passes 'Set.empty'.
applyAbstractionVerdict :: Set FQConstraintId -> EmitResult -> FQVerifyResult -> AbstractionOutcome
applyAbstractionVerdict cleared er r = case r of
  FQUnsafe ids ->
    AbstractionOutcome
      { aoResult       = if null reclassList then r
                         else if null kept then FQSafe else FQUnsafe kept
      , aoEmit         = er'
      , aoReclassified = [ (rcFn c, rcCallee c) | c <- reclassList, rcCause c == FallbackAbstraction ]
      , aoAbstractionConstructs = [ (rcFn c, constructOf c) | c <- reclassList, rcCause c == FallbackAbstraction ]
      , aoUnassumed    = [ (rcFn c, rcCallee c) | c <- reclassList, rcCause c == FallbackCalleePostUnassumed ]
      , aoWelldefUnproved = [ (rcFn c, constructOf c) | c <- reclassList, rcCause c == FallbackClauseWelldefUnproved ]
      , aoIllDefined   = hardFns PWd
      , aoMeasureBad   = hardFns PMeas
      , aoRefuted      = Set.filter (`Set.member` faithful) (hardFns PTruth)
      , aoWdFailing    = Map.fromListWith worst
                           [ (coFunction o, if isNothing (candidate i) then WdComplete else WdMarkedOnly)
                           | i <- ids, Just o <- [Map.lookup i table], isWdClause (coClause o) ]
      , aoMarkedIds    = Set.fromList [ i | i <- kept, isJust (candidate i) ]
      , aoMarkCause    = Map.fromList [ (i, k) | i <- kept, isJust (candidate i), Just k <- [markCause i] ]
      , aoTabulateUnverified = []
      }
    where
      table    = erConstraintTable er
      faithful = Set.fromList (erBodyFaithfulFns er)
      fnOf i   = coFunction <$> Map.lookup i table
      partOf i = maybe PTruth (partitionOf . coClause) (Map.lookup i table)
      absMark i = Map.lookup i (erAbstracted er)
      cpuMark i = Map.lookup i (erPostUnassumed er)
      -- MUL-VAR-1: the product mark, unless the recheck cleared the id.
      prodMark i = i `Set.member` erProductMarked er && not (i `Set.member` cleared)
      -- Rule 1: a candidate carries at least one mark, has an origin, and
      -- belongs to a body-faithful function. The clause does not matter: a
      -- marked descent or decreases id is a candidate too (the user-approved
      -- extension), and so is a marked WD id (CLAUSE-WELLDEF-1).
      -- MUL-VAR-1: a product-marked id needs no body-faithful function.
      candidate i = case Map.lookup i table of
        Just o | coFunction o `Set.member` faithful
               , isJust (absMark i) || isJust (cpuMark i) -> Just (coFunction o)
               | prodMark i                               -> Just (coFunction o)
        _                                                 -> Nothing
      -- CALL-RESULT-MARK-1 (H4): the construct of the mark that hit an id.
      markCause i
        | Just g <- absMark i = Just (abstractionConstruct g)
        | Just g <- cpuMark i = Just (postUnassumedConstruct g)
        | prodMark i          = Just nonlinearConstruct
        | otherwise           = Nothing
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
      -- MUL-VAR-1: when not every id carries the abstraction mark and none
      -- carries the callee-post mark, some id carries only the product mark,
      -- and the construct is @abstraction:nonlinear:*@.
      decide f is =
        let (inner, g, prod) = shipped is
            wdIds      = [ i | i <- is, partOf i == PWd ]
            prodIds    = [ i | i <- is, prodMark i ]
        in if length wdIds == length is
             then Reclass f FallbackClauseWelldefUnproved g inner wdIds prod prodIds
             else Reclass f inner g inner wdIds prod prodIds
      shipped is = case ( [ g | i <- is, Just g <- [absMark (i :: FQConstraintId)] ]
                        , [ g | i <- is, Just g <- [cpuMark i] ] ) of
        (g : gs, _) | length (g : gs) == length is -> (FallbackAbstraction, g, False)
        (_, g : _)                                 -> (FallbackCalleePostUnassumed, g, False)
        -- a candidate with neither mark, or with the abstraction mark on
        -- some ids only, carries the product mark on the rest
        _                                          -> (FallbackAbstraction, "", True)
      reclass  = Set.fromList (map rcFn reclassList)
      -- Rule 3: an id with no origin is kept.
      kept     = [ i | i <- ids, maybe True (not . (`Set.member` reclass)) (fnOf i) ]
      er'      = reclassifyEmit table reclassList er
  _ -> AbstractionOutcome { aoResult = r, aoEmit = er, aoReclassified = [], aoAbstractionConstructs = [], aoUnassumed = []
                          , aoWelldefUnproved = [], aoIllDefined = Set.empty
                          , aoMeasureBad = Set.empty, aoRefuted = Set.empty
                          , aoWdFailing = Map.empty, aoMarkedIds = Set.empty, aoMarkCause = Map.empty
                          , aoTabulateUnverified = [] }

-- | The construct a reclassified function carries.
constructOf :: Reclass -> Text
constructOf c = case rcCause c of
  FallbackClauseWelldefUnproved -> welldefConstruct (innerConstruct (rcInner c) (rcCallee c))
  cause                         -> innerConstruct cause (rcCallee c)
  where
    innerConstruct FallbackCalleePostUnassumed g = postUnassumedConstruct g
    innerConstruct FallbackTabulateGenUnverified g = tabulateGenConstruct g
    innerConstruct _                           g
      | rcProduct c = nonlinearConstruct
      | otherwise   = abstractionConstruct g

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
--
-- MUL-VAR-1: a function that is already in fallback (a product-marked id
-- needs no body-faithful function) keeps its first cause. It gets no second
-- entry in 'erBodyFallback', 'erBodyFallbackCauses' or 'erFallbackConstructs',
-- and no second @W-BODY-FALLBACK@; its welldef warnings say that the clause's
-- truth was not checked.
reclassifyEmit :: Map FQConstraintId ConstraintOrigin -> [Reclass] -> EmitResult -> EmitResult
reclassifyEmit _ [] er = er
reclassifyEmit table rs er = er
  { erBodyFaithfulFns    = [ n | n <- erBodyFaithfulFns er, not (n `Set.member` moved) ]
  , erBodyFallback       = erBodyFallback er ++ map rcFn fresh
  , erBodyFallbackCauses = erBodyFallbackCauses er ++ [ (rcFn c, rcCause c) | c <- fresh ]
  , erFallbackConstructs = erFallbackConstructs er ++ [ (rcFn c, [constructOf c]) | c <- fresh ]
  , erDiagnostics        = erDiagnostics er ++ concatMap diagsFor rs
  }
  where
    moved = Set.fromList (map rcFn rs)
    already = Set.fromList (erBodyFallback er)
    fresh = [ c | c <- rs, not (rcFn c `Set.member` already) ]
    repairOf FallbackCalleePostUnassumed g = postUnassumedRepair g
    repairOf FallbackTabulateGenUnverified g = tabulateGenRepair g
    repairOf _                           g = abstractionRepair g
    -- MUL-VAR-1 (finding F11): a product names no callee, so it gets its own
    -- repair sentence and never "two calls to ''".
    repairFor c
      | rcProduct c && rcInner c /= FallbackCalleePostUnassumed = productRepair
      | otherwise = repairOf (rcInner c) (rcCallee c)
    -- MUL-VAR-1 ("Messages"): the product text names the construct and points
    -- at a product-marked failing constraint: the first one over the pair
    -- limit, else the first one.
    productWarning c =
      let overCap = [ (i, k) | i <- rcProdIds c, Just k <- [Map.lookup i (erProductPairs er)] ]
          (target, why) = case overCap of
            (i, k) : _ -> (Just i, ProductPairLimit k PNF.maxPairs)
            []         -> (case rcProdIds c of { i : _ -> Just i; [] -> Nothing }, ProductNotProved)
          ptr = coJsonPtr <$> (target >>= (`Map.lookup` table))
      in mkBodyFallbackProduct (rcFn c) (constructOf c) ptr why
    diagsFor c =
      let f     = rcFn c
          cause = renderFallbackCause (rcCause c)
          w | rcProduct c && rcCause c == FallbackAbstraction = productWarning c
            | otherwise = let w0 = mkBodyFallbackWarning f cause [constructOf c] []
                          in w0 { diagMessage = diagMessage w0 <> repairFor c }
          wds   = [ welldefWarning (f `Set.member` already) f o
                  | rcCause c == FallbackClauseWelldefUnproved
                  , i <- rcWdIds c, Just o <- [Map.lookup i table] ]
      in if f `Set.member` already
           then wds
           else w : wds
                  ++ [ mkDecreasesUndischarged f cause i | Just i <- [lookup f (erMeasuredRecursive er)] ]
    welldefWarning notChecked f o =
      let clause = if coClause o == "wd-pre" then "pre" else "post"
          why | notChecked = ". Its truth was not checked, because the body is outside the fragment. The clause is kept and checked at run time."
              | otherwise  = ". Its truth was proved, but on the path that reaches it the verifier did not assume every fact of a call it makes, so the clause is kept and checked at run time."
          msg = "W-CLAUSE-WELLDEF-UNPROVED: the " <> clause <> " of '" <> f
                <> "' is not proved defined where it is evaluated"
                <> maybe "" (": " <>) (coSite o)
                <> why
      in (mkWarning Nothing msg)
           { diagCode    = Just "W-CLAUSE-WELLDEF-UNPROVED"
           , diagPointer = Just (coJsonPtr o) }

-- | BYTES-TABULATE-1 (image-library-proposal Part B, "The generator is a
-- callee"; plan finding 5): the post-solver rule for 'FallbackTabulateGenUnverified'.
--
-- A local generator's verdict is known only now, so the rule runs here, after
-- 'applyAbstractionVerdict', on every answer (SAFE included). The candidates
-- are the body-faithful functions outside the hard sets ('aoRefuted',
-- 'aoIllDefined', 'aoMeasureBad'): a hard function keeps its own outcome,
-- because T2 and T3 rest on the generator's contract, not its body. A
-- candidate moves when one of its generators ('erTabulateGens') is imported
-- and not fully verified, or is local and not in the verified-local set. That
-- set is the candidates minus the moved, so a generator that itself tabulates
-- over an unverified one moves too: the rule iterates to a fixed point, which
-- exists because the moved set only grows over a finite set. A moved function
-- leaves the body-faithful set through 'reclassifyEmit', as every other cause
-- does, so no verified record is written for it.
applyTabulateGenVerdict :: AbstractionOutcome -> AbstractionOutcome
applyTabulateGenVerdict ao
  | null rs   = ao
  | otherwise = ao { aoEmit = reclassifyEmit (erConstraintTable er) rs er
                   , aoTabulateUnverified = aoTabulateUnverified ao ++ [ (rcFn c, rcCallee c) | c <- rs ] }
  where
    er    = aoEmit ao
    gens  = erTabulateGens er
    hard  = Set.unions [aoRefuted ao, aoIllDefined ao, aoMeasureBad ao]
    cands = [ f | f <- erBodyFaithfulFns er, not (f `Set.member` hard) ]
    unverifiedGens vl f =
      [ g | (g, st) <- Map.findWithDefault [] f gens
          , case st of
              Just ok -> not ok
              Nothing -> not (g `Set.member` vl) ]
    fixMoved mv =
      let vl  = Set.fromList [ f | f <- cands, not (f `Set.member` mv) ]
          new = [ f | f <- cands, not (f `Set.member` mv), not (null (unverifiedGens vl f)) ]
      in if null new then mv else fixMoved (Set.union mv (Set.fromList new))
    moved    = fixMoved Set.empty
    finalVL  = Set.fromList [ f | f <- cands, not (f `Set.member` moved) ]
    rs = [ Reclass f FallbackTabulateGenUnverified g FallbackTabulateGenUnverified [] False []
         | f <- cands, f `Set.member` moved
         , g : _ <- [unverifiedGens finalVL f] ]
