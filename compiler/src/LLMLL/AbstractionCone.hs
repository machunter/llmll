-- |
-- Module      : LLMLL.AbstractionCone
-- Description : CALL-RESULT-MARK-1, the clause-1 cone of influence: is an
--               UNSAFE answer on one kept constraint able to rest on a value
--               the verifier knows only in part?
--
-- docs/design/byte-io-proposal.md, Amendment Rev 2b (2026-11-17), items 2-6
-- and 10. Clause 1 of the abstraction mark used to fire on a whole constraint
-- environment that held one result of a partially reflected builtin
-- ('LLMLL.FixpointEmit.abstractedBuiltins'). It now fires only when that
-- result can reach the goal or a path atom of the constraint through the
-- recorded facts. Pure: this module reads one constraint, its binders and the
-- record the emitter wrote for it, and changes no @.fq@ text.
--
-- THE BIT (Rev 2b item 2).
--
--   * Seeds: each clause-1 result binder in the constraint's environment, and
--     each uninterpreted symbol a clause-1 reflection introduces
--     ('clause1SeedUFs': @strCode@). A new partial UF is a seed by name.
--   * Scan (condition C2): the @lhs@, the @rhs@, and the refinement of every
--     bind id in the environment with its bound variable replaced by the
--     binder name. A kvar anywhere sets the bit.
--   * Recorded facts, by position (condition C1). An @lhs@ atom is a fact
--     only when the emitter recorded it for THIS constraint as an atom of a
--     call post on this constraint's flattened path ('crFacts'), or as an
--     atom 'addConst' injected into this constraint after all three injectors
--     ran ('crInjected'), and it is not also a guard or pre atom of this
--     constraint ('crGuards'). An environment refinement is a fact only when
--     its binder is a let binder this site created ('crLetBinds') and its name
--     is bound once in the environment. No shape test makes an atom a fact.
--   * Path atoms: every other atom. A branch guard, a conjunct of the pre,
--     the result equation, a parameter refinement, an atom a later pass
--     rewrote (the MUL-VAR-1 product pass), a bool-value fact, an atom of
--     unknown origin. A misclassified fact can only be a path atom, which can
--     only keep a mark.
--   * Frozen symbols: the function's parameters and 'coneFrozenHeads'. A
--     frozen symbol never joins D and never links two atoms.
--   * Closure: D starts as the seeds. A fact that names a symbol of D adds
--     every symbol it names that is not frozen. Repeat until nothing joins.
--   * The bit is set when a symbol of D occurs in the goal or in a path atom.
--   * Fail-closed: the bit is set when the constraint holds a kvar, or when
--     the emitter wrote no record for it (every constraint kind other than
--     body-post, call-pre and descent: well-definedness, payload subtyping,
--     measure well-foundedness, the closed RESP-FACT pre).
--
-- When the environment holds no clause-1 result, clause 1 does not run, so
-- this module is not consulted ('LLMLL.FixpointEmit', @abstracted@).
--
-- SOUNDNESS LEMMA (Rev 2b item 5, with conditions C4, F-1, F-2, F-3).
--
-- Let a kept constraint have hypotheses H and goal R, and let the bit be
-- clear. Let M be a model of H and not R. Run the program on the parameter
-- values of M, with each single-call callee returning the value M gives it
-- (the modular reading, P16). Proceed by induction along the path in
-- evaluation order (F-3), and stop at the first call whose pre fails on the
-- real values.
--
-- Each symbol outside D is one of THREE KINDS (F-2):
--
--   1. a parameter;
--   2. a value fixed by an exact equation over symbols outside D (a let
--      equation, an exact builtin reflection, an exact bit form);
--   3. a single-call result that the modular reading lets M choose.
--
-- Every other inexactly constrained symbol has its own mark: clause-1
-- results are seeds, and clause-2 results (two calls to one callee), callee
-- posts not assumed at a call (CALLEE-POST-UNASSUMED-1) and products
-- (MUL-VAR-1) are marked by their own rules, which keep the
-- whole-environment form. Bool-value facts are path atoms. So the run gives
-- each symbol outside D the value M gives it, and each path atom has the same
-- truth value as in M.
--
-- Give each D symbol its run value. ARRAY REALIZATION (F-1, Fix B): an array
-- in D takes its run value on @[0, len)@ and 0 outside, so each recorded fact
-- holds, including a byte-range fact at an out-of-range index. A NON-D ARRAY,
-- such as a parameter @b@, is realized as the model array with length
-- @bytesLen_M(b)@. A cell outside that length (@Map_select b 99@ in witness
-- N1) belongs to the encoding, not to the run, and no guard or goal can read
-- it on a run that reaches the check: a body read fails its own pre first,
-- and CLAUSE-WELLDEF-1 guards a clause read.
--
-- FROZEN HEADS ARE REALIZABLE, NOT EXACT (C4): every model value of a frozen
-- term over non-D arguments is the encoding of some real value with the same
-- observations. @bytesLen@, @strLen@, @listLen@ and the three array symbols
-- qualify. @strCode@ does not (a model may give it a value no string has at
-- that index), so it is a seed and stays off the frozen list permanently.
--
-- R names no D symbol, so R stays false. The induction ends in one of two
-- cases: the run reaches the failing point with R false, or an earlier call
-- on the path fails its own pre on the same input. Both are real defects.
-- Two side conditions: each dropped statement terminates or fails visibly
-- (the seed builtins are total under their pres, and modular calls return by
-- P16), and the fragment outside D is exact, which every unmarked constraint
-- already assumes. A newly unmarked well-definedness id reports
-- @ill-defined@ and a newly unmarked descent id reports
-- measure-not-decreasing, by the existing partition; each is a check at a
-- point on the path, so the lemma covers both.
--
-- AUDIT (condition C6, finding F-2; Rev 2b item 10). Soundness rests on two
-- lists. 'coneFrozenHeads' fails closed: an unlisted symbol links atoms.
-- 'LLMLL.FixpointEmit.abstractedBuiltins' does not fail closed, so it is
-- audited here and by an hspec test (CR-C1):
--
--   * The builtin 'CallVC' arms of 'bodyToPredM' are fourteen named arms:
--     @bytes-get@, @bytes-set@, @bytes-zero@, @map-get@, @string-code-at@,
--     @string-from-code@, @bytes-make@, @bytes-widen@, @bytes-slice@,
--     @bytes-concat@, @bytes-concat-many@, @bytes-to-list@,
--     @bytes-from-string@ and (BYTES-TABULATE-1) @bytes-tabulate@. Each is in
--     'sealedAxiomBuiltins'.
--   * Each sealed name is in exactly one of @abstractedBuiltins@ (the result
--     is reflected in part: @string-code-at@, @string-from-code@,
--     @bytes-make@, @bytes-slice@, @bytes-concat@, @bytes-concat-many@,
--     @bytes-to-list@, @bytes-from-string@, @bytes-tabulate@) and 'exactSealedBuiltins' (the
--     result is pinned by an exact reflection: @bytes-get@ and @map-get@ a
--     read, @bytes-set@ a store, @bytes-zero@ the constant array, and
--     @bytes-widen@ the identity). The CR-C1 test fails CI when a new sealed
--     arm is not classified.
--   * The two other builtin arms reflect the arithmetic term itself: the
--     exact bit forms ('exactBitBuiltins'), and (DIV-VAR-1) `/` and `mod` by
--     a divisor that is not ground ('exactDivBuiltins'), whose result is the
--     division term with a PROVE pre @d >= 1@. Neither is sealed.
--   * No other arm of 'bodyToPredM' gives a fresh result with only a lemma.
--     A user-function call is covered by clause 2 (two calls to one callee),
--     the callee-post mark (CALLEE-POST-UNASSUMED-1) and the modular reading
--     (P16): its single result is kind 3 above.

-- LENGTH OF A PARTIAL RESULT (ABSTRACTION-LEN-EXACT-1; Rev 2b item 7, with
-- the professor addendum and the user-approved @bytes-make@ and @bytes-set@
-- rows).
--
-- For a result @x@ of an 'exactLengthBuiltins' call, the term @bytesLen(x)@
-- (or @listLen(x)@, or @strLen(x)@) is a symbol of its own, @L_x@, separate
-- from the content @x@. The seed is the content @x@. @L_x@ is outside D only
-- when the constraint holds the exact length equation of @x@ as a recorded
-- fact AND its right side names no D symbol. Three conditions:
--
--   1. One monotone fixpoint. @L_x@ starts outside D and joins D as soon as a
--      symbol of its equation's right side joins D; it never leaves. Both
--      rules only add, so the least fixpoint does not depend on worklist
--      order. (A two-pass form is unsound for a chain such as a slice whose
--      bound reads a later D symbol.)
--   2. The equation defines @L_x@ only. It is not a D-atom of @x@: it never
--      pulls @e@ and @s@ (or any right-side symbol) into D.
--   3. By position (C1, C2). The equation is the @"lemma"@ part of the
--      qualifying arm ('crLenDefs', written by the emitter for each call
--      result of the body), and it counts only when that atom is a recorded
--      call-post fact of THIS constraint's @lhs@, that is, its call is on this
--      constraint's path. A text match elsewhere does not count. Any other
--      occurrence of @x@ (a @Map_select@, a @Map_store@, an array equality, a
--      callee argument) still names @x@; only the length leaves.
--
-- A length known only by congruence (an alias @y = x@, or @bytes-widen@) is
-- not a symbol: @bytesLen(y)@ names @y@, which is in D with @x@.
--
-- Rows ('exactLengthBuiltins'): @bytes-slice b s e@ (@bytesLen(r) = e - s@,
-- exact when the slice pre holds), @bytes-concat a b@
-- (@bytesLen(r) = bytesLen(a) + bytesLen(b)@), @bytes-to-list b@
-- (@listLen(r) = bytesLen(b)@), @string-from-code c@ (@strLen(r) = 1@, exact
-- when the pre holds), @bytes-make n v@ (@bytesLen(r) = n@: the runtime builds
-- exactly @n@ bytes when the pre holds), @bytes-set b i v@
-- (@bytesLen(r) = bytesLen(b)@: a store keeps the length; @r@ is in D only
-- through its reflection @r = Map_store(b, i, v)@ when @b@ is), and
-- @bytes-tabulate n g …@ (@bytesLen(r) = n@: the runtime builds exactly @n@
-- bytes or stops, when T1 holds; BYTES-TABULATE-1). Not rows:
-- @bytes-concat-many@ (@bytesLen(r) >= 0@), @bytes-from-string@ (a range),
-- @string-code-at@ (no length), @bytes-widen@ (no lemma).
--
-- Soundness, as the lemma: when the call's pre holds, the run meets the
-- equation and its right side has the same value in the run and in M, so
-- @L_x@ does too. When the pre fails, the run stops there (the lemma's
-- earlier-failing-call case).

module LLMLL.AbstractionCone
  ( ConeRec(..)
  , emptyConeRec
  , ConeInput(..)
  , coneInput
  , coneBit
  , coneHits
  , clause1SeedUFs
  , coneFrozenHeads
  , atomsOf
  , exactLengthBuiltins
  , lengthHeads
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Set as Set
import Data.Set (Set)

import LLMLL.FixpointIR

-- | What the emitter recorded for one constraint, at the site that built it
-- (condition C1). Atoms are compared structurally with the constraint's own
-- @lhs@ atoms, so an atom a later pass rewrote no longer matches its record
-- and reads as a path atom.
data ConeRec = ConeRec
  { crFacts    :: [FQPred]
    -- ^ atoms of each call post on this constraint's path (a callee post, or
    -- a builtin's reflection and lemma)
  , crGuards   :: [FQPred]
    -- ^ atoms of the path guard and of the function's pre, as built here
  , crLetBinds :: Set FQBindId
    -- ^ the env binders this site created for a let equation ('selfEqReft')
  , crInjected :: [FQPred]
    -- ^ the @lhs@ atoms 'addConst' added, after all three injectors ran
  , crParams   :: Set Text
    -- ^ the owner's parameter binders, in emitted (sanitized) form; frozen
  , crLenDefs  :: Map Text FQPred
    -- ^ ABSTRACTION-LEN-EXACT-1: each 'exactLengthBuiltins' call result of
    -- the body (raw name) with the @"lemma"@ atom of its arm. It counts for a
    -- constraint only when the atom is also one of that constraint's recorded
    -- call-post facts ('crFacts') in its @lhs@
  } deriving (Show, Eq)

emptyConeRec :: ConeRec
emptyConeRec = ConeRec [] [] Set.empty [] Set.empty Map.empty

-- | ABSTRACTION-LEN-EXACT-1 (Rev 2b item 7): the builtins whose length lemma
-- is an exact equation. The engineer's adopted rows include @bytes-make@ and
-- @bytes-set@. BYTES-TABULATE-1: @bytes-tabulate n g …@ (@bytesLen(r) = n@),
-- so L is exact when @n@ is (image-library-proposal edge case 4a).
exactLengthBuiltins :: Set Text
exactLengthBuiltins = Set.fromList
  [ "bytes-slice", "bytes-concat", "bytes-to-list", "string-from-code", "bytes-make", "bytes-set"
  , "bytes-tabulate" ]

-- | The length heads a length symbol @L_x@ stands for.
lengthHeads :: Set Text
lengthHeads = Set.fromList ["bytesLen", "listLen", "strLen"]

-- | One constraint, classified. Every set holds emitted symbol names
-- ('predSymbols').
data ConeInput = ConeInput
  { ciSeeds  :: Set Text     -- ^ the seed binders and 'clause1SeedUFs'
  , ciFrozen :: Set Text     -- ^ the parameters and 'coneFrozenHeads'
  , ciGoal   :: Set Text     -- ^ the symbols of the @rhs@
  , ciFacts  :: [Set Text]   -- ^ one symbol set per recorded fact
  , ciPath   :: [Set Text]   -- ^ one symbol set per path atom
  , ciKVar   :: Bool         -- ^ a kvar occurs in the scanned predicates
  , ciLenEqs :: [(Text, Set Text)]
    -- ^ ABSTRACTION-LEN-EXACT-1: each length symbol @L_x@ with the symbols of
    -- its recorded equation's right side
  } deriving (Show, Eq)

-- | Rev 2b item 2.1: the partial uninterpreted symbols a clause-1 reflection
-- introduces. A seed by name. @band@ joins when BITWISE-WIDTH-1 ships.
clause1SeedUFs :: Set Text
clause1SeedUFs = Set.fromList ["strCode"]

-- | Rev 2b item 2.5: the interpreted symbols that are frozen. Each is
-- realizable (C4). Nothing else is frozen except the owner's parameters.
coneFrozenHeads :: Set Text
coneFrozenHeads = Set.fromList
  ["bytesLen", "strLen", "listLen", "Map_select", "Map_store", "Map_default"]

-- | The conjuncts of a predicate, nested conjunctions spliced, @true@ dropped.
atomsOf :: FQPred -> [FQPred]
atomsOf p = filter (/= FQTrue) (go p)
  where go (FQAnd qs) = concatMap go qs
        go q          = [q]

-- | Classify one constraint. 'Nothing' when the emitter wrote no record for
-- it: the caller then keeps the whole-environment mark (fail-closed).
--
-- The third argument names the seed binders (raw binder names, as in the
-- environment).
coneInput :: Map FQBindId FQBind -> Maybe ConeRec -> Set Text -> FQConstraint -> Maybe ConeInput
coneInput _ Nothing _ _ = Nothing
coneInput bindById (Just rec) seedNames c = Just ConeInput
  { ciSeeds  = Set.map symOf seedNames `Set.union` clause1SeedUFs
  , ciFrozen = crParams rec `Set.union` coneFrozenHeads
  , ciGoal   = Set.unions (map syms rhsAtoms)
  , ciFacts  = map syms ([ a | a <- lhsFacts, a `notElem` lenEqAtoms ] ++ envFacts)
  , ciPath   = map syms (lhsPath ++ envPath)
  , ciKVar   = any hasKVar (lhsAtoms ++ rhsAtoms ++ concatMap snd envAtoms)
  , ciLenEqs = [ (lenSym (symOf x), syms rhs) | (x, rhs) <- lenDefs ]
  }
  where
    -- ABSTRACTION-LEN-EXACT-1: the length equations that count here (by
    -- position: a call-post fact of this constraint's lhs), and the symbol
    -- reading that turns their lengths into @L_x@.
    lenDefs = [ (x, rhs)
              | (x, a@(FQBinPred FQEq (FQApp h [FQVar x']) rhs)) <- Map.toList (crLenDefs rec)
              , x' == x, h `Set.member` lengthHeads
              , a `elem` crFacts rec, a `elem` lhsFacts ]
    lenEqAtoms = [ a | (x, a) <- Map.toList (crLenDefs rec), x `elem` map fst lenDefs ]
    defined = Set.fromList [ symOf x | (x, _) <- lenDefs ]
    syms = lenSymbols defined
    lhsAtoms = atomsOf (reftPred (conLhs c))
    rhsAtoms = atomsOf (reftPred (conRhs c))
    isFact a = (a `elem` crFacts rec || a `elem` crInjected rec)
               && not (a `elem` crGuards rec)
    lhsFacts = filter isFact lhsAtoms
    lhsPath  = filter (not . isFact) lhsAtoms
    envBinds = [ b | i <- conEnv c, Just b <- [Map.lookup i bindById] ]
    nameCount = Map.fromListWith (+) [ (bindName b, 1 :: Int) | b <- envBinds ]
    -- Each refinement with its bound variable replaced by the binder name;
    -- `true` and `x = x` carry no atom.
    envAtoms =
      [ (b, [ a | a <- atomsOf (renameVarFQ (reftVar r) (bindName b) (reftPred r))
                , not (trivialSelf (bindName b) a) ])
      | b <- envBinds, let r = bindReft b ]
    letFact b = bindId b `Set.member` crLetBinds rec
                && Map.findWithDefault 0 (bindName b) nameCount == 1
    envFacts = concat [ as | (b, as) <- envAtoms, letFact b ]
    envPath  = concat [ as | (b, as) <- envAtoms, not (letFact b) ]
    trivialSelf n (FQBinPred FQEq (FQVar x) (FQVar y)) = x == n && y == n
    trivialSelf _ _ = False

-- | Rev 2b items 2.6-2.8: the closure and the bit.
coneBit :: ConeInput -> Bool
coneBit ci
  | ciKVar ci = True
  | otherwise = any touches (ciGoal ci : ciPath ci)
  where
    unfrozen s = s `Set.difference` ciFrozen ci
    facts = map unfrozen (ciFacts ci)
    d0 = ciSeeds ci `Set.difference` ciFrozen ci
    -- One monotone step: rule (a) over the facts, rule (b) over the length
    -- equations (only L_x joins). Iterated to the least fixpoint.
    step d =
      let da = foldl (\acc f -> if Set.null (Set.intersection f acc) then acc else Set.union acc f) d facts
      in foldl (\acc (l, r) -> if Set.null (Set.intersection r acc) then acc else Set.insert l acc) da (ciLenEqs ci)
    close d =
      let d' = step d
      in if Set.size d' == Set.size d then d else close d'
    dFinal = close d0
    touches s = not (Set.null (Set.intersection s dFinal))

-- | Does clause 1 mark this constraint? True when there is no record
-- (fail-closed) or when the cone reaches the goal or a path atom.
coneHits :: Map FQBindId FQBind -> Maybe ConeRec -> Set Text -> FQConstraint -> Bool
coneHits bindById mRec seedNames c =
  maybe True coneBit (coneInput bindById mRec seedNames c)

-- | ABSTRACTION-LEN-EXACT-1: the length symbol of a defined result.
lenSym :: Text -> Text
lenSym x = "L#" <> x

-- | 'predSymbols', except that a length head applied to a defined result
-- reads as its length symbol and does not name the result.
lenSymbols :: Set Text -> FQPred -> Set Text
lenSymbols defined = go
  where
    go p = case p of
      FQApp h [FQVar x]
        | h `Set.member` lengthHeads, symOf x `Set.member` defined -> Set.singleton (lenSym (symOf x))
      FQApp f as       -> Set.insert (symOf f) (Set.unions (map go as))
      FQNot q          -> go q
      FQAnd ps         -> Set.unions (map go ps)
      FQOr ps          -> Set.unions (map go ps)
      FQBinPred _ a b  -> go a `Set.union` go b
      FQBinArith _ a b -> go a `Set.union` go b
      FQKVar _ as      -> Set.unions (map go as)
      FQIte a b q      -> Set.unions [go a, go b, go q]
      FQImplies a b    -> go a `Set.union` go b
      _                -> predSymbols p

-- | The emitted form of one name.
symOf :: Text -> Text
symOf n = case Set.toList (predSymbols (FQVar n)) of
  [s] -> s
  _   -> n

hasKVar :: FQPred -> Bool
hasKVar p = case p of
  FQKVar _ _       -> True
  FQNot q          -> hasKVar q
  FQAnd ps         -> any hasKVar ps
  FQOr ps          -> any hasKVar ps
  FQBinPred _ a b  -> hasKVar a || hasKVar b
  FQBinArith _ a b -> hasKVar a || hasKVar b
  FQApp _ as       -> any hasKVar as
  FQIte a b q      -> hasKVar a || hasKVar b || hasKVar q
  FQImplies a b    -> hasKVar a || hasKVar b
  _                -> False

-- | Replace a variable. A predicate binds no variable, so this is plain
-- substitution.
renameVarFQ :: Text -> Text -> FQPred -> FQPred
renameVarFQ from to = go
  where
    go p = case p of
      FQVar x | x == from -> FQVar to
      FQNot q          -> FQNot (go q)
      FQAnd ps         -> FQAnd (map go ps)
      FQOr ps          -> FQOr (map go ps)
      FQBinPred o a b  -> FQBinPred o (go a) (go b)
      FQBinArith o a b -> FQBinArith o (go a) (go b)
      FQKVar k as      -> FQKVar k (map go as)
      FQApp f as       -> FQApp f (map go as)
      FQIte a b q      -> FQIte (go a) (go b) (go q)
      FQImplies a b    -> FQImplies (go a) (go b)
      _                -> p
