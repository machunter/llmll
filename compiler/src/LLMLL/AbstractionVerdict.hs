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
module LLMLL.AbstractionVerdict
  ( AbstractionOutcome(..)
  , applyAbstractionVerdict
  , abstractionConstruct
  , abstractionRepair
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Maybe (isNothing)

import LLMLL.Syntax (Name)
import LLMLL.FixpointEmit (EmitResult(..), FallbackCause(..), renderFallbackCause)
import LLMLL.DiagnosticFQ (FQVerifyResult(..), ConstraintOrigin(..))
import LLMLL.Diagnostic (Diagnostic(..), mkBodyFallbackWarning, mkDecreasesUndischarged)

-- | The verdict after the rule ran.
data AbstractionOutcome = AbstractionOutcome
  { aoResult       :: FQVerifyResult
    -- ^ the effective verdict: the reclassified ids are gone, and 'FQSafe'
    -- when none remain
  , aoEmit         :: EmitResult
    -- ^ the emit result with the reclassified functions moved to the
    -- fallback lists
  , aoReclassified :: [(Text, Name)]
    -- ^ each reclassified function with the callee that marked it, in the
    -- order its first failing id was reported
  } deriving (Show)

-- | The attribution string a reclassified function carries in
-- 'erFallbackConstructs', 'W-BODY-FALLBACK' and the @abstraction_fallback@
-- verdict key.
abstractionConstruct :: Name -> Text
abstractionConstruct g = "abstraction:app:" <> g

-- | The one repair sentence 'W-BODY-FALLBACK' adds for this cause. It is true
-- when the two calls are syntactically equal (bind one, reuse the result); for
-- calls whose arguments are only equal under a guard it names the limit.
abstractionRepair :: Name -> Text
abstractionRepair g =
  " If two calls to '" <> g <> "' take equal arguments, bind one call with let and reuse its result."

-- | Apply the rule to one solver answer. 'FQSafe', 'FQError' and an UNSAFE
-- answer with no ids pass through unchanged.
applyAbstractionVerdict :: EmitResult -> FQVerifyResult -> AbstractionOutcome
applyAbstractionVerdict er r = case r of
  FQUnsafe ids@(_ : _) | not (null reclassList) ->
    AbstractionOutcome
      { aoResult       = if null kept then FQSafe else FQUnsafe kept
      , aoEmit         = er'
      , aoReclassified = reclassList
      }
    where
      table    = erConstraintTable er
      faithful = Set.fromList (erBodyFaithfulFns er)
      fnOf i   = coFunction <$> Map.lookup i table
      -- Rule 1: a candidate carries the mark, has an origin, and belongs to a
      -- body-faithful function. The clause does not matter: a marked descent
      -- or decreases id is a candidate too (the user-approved extension).
      candidate i = case (Map.lookup i (erAbstracted er), Map.lookup i table) of
        (Just g, Just o) | coFunction o `Set.member` faithful -> Just (coFunction o, g)
        _                                                    -> Nothing
      -- Rule 2: one non-candidate id keeps the whole function.
      blocked  = Set.fromList [ f | i <- ids, isNothing (candidate i), Just f <- [fnOf i] ]
      reclassList = firstPerFn [ (f, g) | i <- ids, Just (f, g) <- [candidate i]
                                        , not (f `Set.member` blocked) ]
      reclass  = Map.fromList reclassList
      -- Rule 3: an id with no origin is kept.
      kept     = [ i | i <- ids, maybe True (not . (`Map.member` reclass)) (fnOf i) ]
      er'      = reclassifyEmit reclassList er
  _ -> AbstractionOutcome { aoResult = r, aoEmit = er, aoReclassified = [] }

-- | Keep the first callee per function, in first-occurrence order.
firstPerFn :: [(Text, Name)] -> [(Text, Name)]
firstPerFn = go Set.empty
  where
    go _ [] = []
    go seen ((f, g) : rest)
      | f `Set.member` seen = go seen rest
      | otherwise           = (f, g) : go (Set.insert f seen) rest

-- | Rule 4: move each reclassified function to the fallback outcome, as the
-- emitter does for every other fallback cause.
reclassifyEmit :: [(Text, Name)] -> EmitResult -> EmitResult
reclassifyEmit [] er = er
reclassifyEmit rs er = er
  { erBodyFaithfulFns    = [ n | n <- erBodyFaithfulFns er, not (n `Set.member` moved) ]
  , erBodyFallback       = erBodyFallback er ++ map fst rs
  , erBodyFallbackCauses = erBodyFallbackCauses er ++ [ (f, FallbackAbstraction) | (f, _) <- rs ]
  , erFallbackConstructs = erFallbackConstructs er ++ [ (f, [abstractionConstruct g]) | (f, g) <- rs ]
  , erDiagnostics        = erDiagnostics er ++ concatMap diagsFor rs
  }
  where
    moved = Set.fromList (map fst rs)
    cause = renderFallbackCause FallbackAbstraction
    diagsFor (f, g) =
      let w = mkBodyFallbackWarning f cause [abstractionConstruct g] []
      in  w { diagMessage = diagMessage w <> abstractionRepair g }
        : [ mkDecreasesUndischarged f cause i | Just i <- [lookup f (erMeasuredRecursive er)] ]
