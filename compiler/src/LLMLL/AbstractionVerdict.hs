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
module LLMLL.AbstractionVerdict
  ( AbstractionOutcome(..)
  , applyAbstractionVerdict
  , aoFallbackFns
  , abstractionConstruct
  , abstractionRepair
  , postUnassumedConstruct
  , postUnassumedRepair
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Maybe (isJust, isNothing)

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
    -- ^ each function reclassified with cause 'FallbackAbstraction', with the
    -- callee that marked it, in the order its first failing id was reported
  , aoUnassumed    :: [(Text, Name)]
    -- ^ CALLEE-POST-UNASSUMED-1: each function reclassified with cause
    -- 'FallbackCalleePostUnassumed', with the callee whose post was not
    -- assumed, in the same order
  } deriving (Show)

-- | Every function the rule moved to the fallback outcome, under either
-- cause. A reader that must not count a reclassified function as proved (or
-- as a kill) reads this, not 'aoReclassified'.
aoFallbackFns :: AbstractionOutcome -> [Text]
aoFallbackFns ao = map fst (aoReclassified ao) ++ map fst (aoUnassumed ao)

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

-- | The one repair sentence 'W-BODY-FALLBACK' adds for this cause. It is true
-- when the two calls are syntactically equal (bind one, reuse the result); for
-- calls whose arguments are only equal under a guard it names the limit.
abstractionRepair :: Name -> Text
abstractionRepair g =
  " If two calls to '" <> g <> "' take equal arguments, bind one call with let and reuse its result."

-- | Apply the rule to one solver answer. 'FQSafe', 'FQError', 'FQResourceLimit' and an UNSAFE
-- answer with no ids pass through unchanged.
applyAbstractionVerdict :: EmitResult -> FQVerifyResult -> AbstractionOutcome
applyAbstractionVerdict er r = case r of
  FQUnsafe ids@(_ : _) | not (null reclassList) ->
    AbstractionOutcome
      { aoResult       = if null kept then FQSafe else FQUnsafe kept
      , aoEmit         = er'
      , aoReclassified = [ (f, g) | (f, FallbackAbstraction, g) <- reclassList ]
      , aoUnassumed    = [ (f, g) | (f, FallbackCalleePostUnassumed, g) <- reclassList ]
      }
    where
      table    = erConstraintTable er
      faithful = Set.fromList (erBodyFaithfulFns er)
      fnOf i   = coFunction <$> Map.lookup i table
      absMark i = Map.lookup i (erAbstracted er)
      cpuMark i = Map.lookup i (erPostUnassumed er)
      -- Rule 1: a candidate carries at least one mark, has an origin, and
      -- belongs to a body-faithful function. The clause does not matter: a
      -- marked descent or decreases id is a candidate too (the user-approved
      -- extension).
      candidate i = case Map.lookup i table of
        Just o | coFunction o `Set.member` faithful
               , isJust (absMark i) || isJust (cpuMark i) -> Just (coFunction o)
        _                                                 -> Nothing
      -- Rule 2: one non-candidate id keeps the whole function.
      blocked  = Set.fromList [ f | i <- ids, isNothing (candidate i), Just f <- [fnOf i] ]
      candIds  = [ (f, i) | i <- ids, Just f <- [candidate i], not (f `Set.member` blocked) ]
      reclassList = [ decide f [ i | (f', i) <- candIds, f' == f ] | f <- nubOrd (map fst candIds) ]
      -- The cause per function. Every failing id carries the abstraction
      -- mark: 'FallbackAbstraction', named by the first id's callee (the
      -- ABSTRACTION-VERDICT-1 output). Otherwise some id carries only the new
      -- mark: 'FallbackCalleePostUnassumed', named by the new-mark callee of
      -- the first failing id that carries it.
      decide f is = case ( [ g | i <- is, Just g <- [absMark i] ]
                         , [ g | i <- is, Just g <- [cpuMark i] ] ) of
        (g : gs, _) | length (g : gs) == length is -> (f, FallbackAbstraction, g)
        (_, g : _)                                 -> (f, FallbackCalleePostUnassumed, g)
        -- unreachable: a candidate carries one of the two marks
        (g : _, [])                                -> (f, FallbackAbstraction, g)
        ([], [])                                   -> (f, FallbackAbstraction, "")
      reclass  = Set.fromList [ f | (f, _, _) <- reclassList ]
      -- Rule 3: an id with no origin is kept.
      kept     = [ i | i <- ids, maybe True (not . (`Set.member` reclass)) (fnOf i) ]
      er'      = reclassifyEmit reclassList er
  _ -> AbstractionOutcome { aoResult = r, aoEmit = er, aoReclassified = [], aoUnassumed = [] }

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
reclassifyEmit :: [(Text, FallbackCause, Name)] -> EmitResult -> EmitResult
reclassifyEmit [] er = er
reclassifyEmit rs er = er
  { erBodyFaithfulFns    = [ n | n <- erBodyFaithfulFns er, not (n `Set.member` moved) ]
  , erBodyFallback       = erBodyFallback er ++ [ f | (f, _, _) <- rs ]
  , erBodyFallbackCauses = erBodyFallbackCauses er ++ [ (f, c) | (f, c, _) <- rs ]
  , erFallbackConstructs = erFallbackConstructs er ++ [ (f, [constructOf c g]) | (f, c, g) <- rs ]
  , erDiagnostics        = erDiagnostics er ++ concatMap diagsFor rs
  }
  where
    moved = Set.fromList [ f | (f, _, _) <- rs ]
    constructOf FallbackCalleePostUnassumed g = postUnassumedConstruct g
    constructOf _                           g = abstractionConstruct g
    repairOf FallbackCalleePostUnassumed g = postUnassumedRepair g
    repairOf _                           g = abstractionRepair g
    diagsFor (f, c, g) =
      let cause = renderFallbackCause c
          w     = mkBodyFallbackWarning f cause [constructOf c g] []
      in  w { diagMessage = diagMessage w <> repairOf c g }
        : [ mkDecreasesUndischarged f cause i | Just i <- [lookup f (erMeasuredRecursive er)] ]
