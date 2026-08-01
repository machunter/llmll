-- | ADMIT-SHARED: the single type-admissibility predicate, and the alias
-- normalization it runs on, shared by the type checker ('LLMLL.TypeCheck') and
-- the constraint emitter ('LLMLL.FixpointEmit').
--
-- == Why this module exists
--
-- LLMLL previously carried two type-membership algorithms serving one semantic
-- notion, with nothing relating them: @assumesFact@ in "LLMLL.TypeCheck" on the
-- checker side (matching at the outermost constructor) and 'resolveAliasTy'
-- plus the @is*Like@ predicates on the emitter side (chasing aliases and
-- stripping refinements). CR-01 was their @TDependent@ disagreement: the
-- checker guarded a strictly narrower set than the emitter asserted for, so a
-- @where@-wrapped @bytes[n]@ or @map[k,bool]@ return position evaded the
-- WILD-ASSUME restriction on both arms while the emitter injected the ground
-- fact anyway (docs/design/finding-arg-position-false-safe.md, Rev 3-4).
--
-- The fix is not another clause. It is one predicate, in a leaf module both
-- channels import, __total on unnormalized input__: 'admits' normalizes what it
-- inspects rather than requiring its caller to have done so. A "has been
-- normalized" precondition is inexpressible in 'Type', which carries no
-- normalization index, so nothing in the project could check it.
--
-- == ADMIT-OVER (the invariant that governs this whole finding class)
--
-- For every type @t@, @admits t@ must hold whenever any emitter site can inject
-- a ground fact derived from a /declaration/ of @t@. The containment is
-- one-directional and deliberate:
--
--   * a @t@ that 'admits' accepts but the emitter never asserts for costs an
--     unnecessary rejection (ergonomic);
--   * a @t@ that 'admits' rejects but the emitter asserts for is a false SAFE
--     (soundness). CR-01 was the second kind.
--
-- So the question for a new arm is never "do the two sides agree" but "is
-- 'admits' still a superset".
--
-- == Side condition: declared type only
--
-- 'admits' is a predicate on the declared type ALONE. It deliberately does not
-- consult 'LLMLL.FixpointEmit.arrGateActive', which every injection site
-- conjoins ('LLMLL.FixpointEmit', @arrParams@ \/ @boolValArrs@ \/ @sortA1@ \/
-- @resultLenFact@). That gate is a function of the callee's contract and BODY,
-- so consulting it here would make type acceptance depend on a callee's body:
-- an unrelated body edit could flip a program between well-typed and ill-typed,
-- and the same program would type-check differently under @check@ and under
-- @verify@. 'admits' is therefore a strict over-approximation of the set of
-- types that actually inject a fact, which is exactly the safe direction under
-- ADMIT-OVER. The shipped @assumesFact@ over-approximated identically; this is
-- documentation of an existing property, not a widening.
--
-- == The normal form
--
-- @
--     n ↦ β ∈ Δ    n ∉ seen                        ─────────────────────────────
--     ─────────────────────  (Norm-Alias)          ⌈TDependent x β p⌉ = ⌈β⌉      (Norm-Refine)
--     ⌈TCustom n⌉ = ⌈β⌉
--
--     ──────────────────────────────  (Norm-Cong, one per constructor)
--     ⌈TMap κ ν⌉ = TMap ⌈κ⌉ ⌈ν⌉      ⌈TList α⌉ = TList ⌈α⌉      …
--
--     n ∉ dom(Δ) or n ∈ seen                       τ has no head alias or wrapper
--     ──────────────────────  (Norm-Stuck)         ─────────────────────  (Norm-Base)
--     ⌈TCustom n⌉ = TCustom n                      ⌈τ⌉ = τ
-- @
--
-- 'normalizeTy' is @⌈·⌉@. It is the SPECIFICATION 'admits' must be invariant
-- under, and the oracle the property tests use; it is not on the 'admits' code
-- path. 'admits' reaches the same answer by head-resolving with
-- 'resolveAliasTy' and delegating component positions to the self-normalizing
-- @is*Like@ predicates.
--
-- == Norm-Stuck covers two distinct populations
--
--   [Unbound name] @n ∉ dom(Δ)@ — the alias names nothing. No fact is derivable.
--
--   [Non-contractive alias] @n ∈ seen@ — e.g. @(type A B) (type B A)@. The
--   equation has no productive unfolding and denotes no regular tree, so there
--   is no type present to assert a fact about. 'admits' is False on it for that
--   intrinsic reason, NOT because 'LLMLL.TypeCheck' happens to report a
--   contractiveness error first; resting on pass ordering is the shape of
--   argument that produced CR-01, where the emitter was shielded by the checker
--   until the shield moved. Contrast a PRODUCTIVE recursive alias
--   (@(type L (list L))@, or a self-referential 'TSumType' payload), which is
--   well formed and normalizes to its finite unfolding.
--
-- Both yield @admits = False@, so the wildcard is admitted, and that is sound
-- because the emitter consults the same Norm-Stuck and injects nothing either.
-- Under ADMIT-SHARED that agreement holds by construction rather than by
-- coincidence.
--
-- == Acceptance criterion (two properties, not one equation)
--
--   [A1 — congruence closure]
--     @admits am t == admits am (normalizeTy am t)@ for every @t@, over a
--     generator that places 'TCustom' at COMPONENT positions ('TMap' key and
--     value, 'TSumType' payloads) as well as at the head, with names bound,
--     unbound, and non-contractive. Once 'admits' head-resolves, invariance at
--     the head is near-trivial; A1's bite is entirely at component positions,
--     because that is where a component predicate can fail to be
--     self-normalizing. The shipped @assumesFactBoolValue@ had no 'TCustom'
--     clause, which is CR-01's untriggered sibling.
--
--   [A2 — expansion equivalence]
--     @admits am (expandAlias t) == admits am t@. A2 is what makes the guard
--     independent of whether its caller pre-expanded. It does NOT license
--     deleting the call-site 'LLMLL.TypeCheck.expandAlias' calls:
--     @compatibleWith@'s nominal clause (@TCustom a@ vs @TCustom b@) and its
--     structural clauses still require expanded input. A2 scopes to the
--     admissibility guard only.
--
-- A1 and A2 are metatheoretic properties of the compiler, discharged by
-- property test rather than by liquid-fixpoint. They are not obligations in the
-- three-channel report, and a reader should not look for them there. A1 stands
-- in for the congruence lemma a type-directed algorithmic conversion would give
-- for free; LLMLL buys it with a test instead of a theorem, and the generator's
-- component coverage is what that purchase amounts to.
--
-- == Cycle guarding, and why there are still three traversals
--
-- Every alias-chasing recursion here carries a per-traversal @seen@ set. The
-- emitter's previous 'resolveAliasTy' did not, and was shielded only by
-- @check@ failing on a contractiveness error before @verify@ ran; moving the
-- predicate into the checker removes that shield, so the guard is required
-- rather than defensive.
--
-- This module holds ONE cycle-guarded resolver. Two other type traversals
-- remain, and both are deliberate:
--
--   * 'LLMLL.TypeCheck.expandAlias' is TC-monadic and REBUILDS 'TDependent'
--     rather than stripping it, because §3.4.1's introduction obligation and
--     the diagnostic label both need the refinement. @⌈·⌉@ strips. One function
--     cannot do both.
--
--   * 'LLMLL.TypeCheck' @detectCycles@ returns the SET OF NAMES participating in
--     a cycle (a normalizer computes no such set) and deliberately excludes
--     'TSumType' payloads from the cycle relation, because a recursive ADT is
--     legitimate. 'normalizeTy' has the OPPOSITE 'TSumType' policy: it must
--     descend into payloads for A1 to hold there. Both policies are correct for
--     their purpose; forcing one on the other breaks a recursive-ADT test or
--     opens an A1 hole at sum-payload positions.
--
-- == Relation to FACT-AG
--
-- 'admits' is a denial list over declared types, and ADMIT-SHARED makes it
-- coherent and cheap to extend. Its principled terminal state is the EMPTY
-- predicate, reached by FACT-AG (docs\/compiler-team-roadmap.md) routing
-- type-derived facts through the assume-guarantee channel so the fact is earned
-- at the call site rather than asserted from an annotation. This module
-- approximates FACT-AG; it is provisional against it, not settled architecture.
module LLMLL.TypeAdmissibility
  ( -- * Alias environment
    AliasMap
  , buildAliasMap
    -- * Normalization
  , resolveAliasTy
  , normalizeTy
    -- * Component predicates (self-normalizing)
  , isIntLike
  , isBoolLike
  , isStrLike
  , isScalarLike
    -- * Fact-injection type gates
  , bytesLenOf
  , boolValuedMapTy
    -- * The shared admissibility predicate
  , admits
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Maybe (isJust)

import LLMLL.Syntax

-- ---------------------------------------------------------------------------
-- Alias environment
-- ---------------------------------------------------------------------------

-- | v0.8.0: Type alias map, built from STypeDef statements.
-- Maps alias names to their structural bodies for 'isIntLike' resolution.
type AliasMap = Map Name Type

-- | Build an alias map from top-level type definitions.
buildAliasMap :: [Statement] -> AliasMap
buildAliasMap stmts = Map.fromList [(n, body) | STypeDef n body <- stmts]

-- ---------------------------------------------------------------------------
-- Normalization
-- ---------------------------------------------------------------------------

-- | Resolve TCustom aliases (and strip the refinement of a TDependent) down to
-- the underlying carrier type, for sort selection. HEAD-ONLY: components of a
-- composite type are left untouched, which is why the component predicates
-- below each normalize their own argument.
--
-- Cycle-guarded (ADMIT-SHARED): a non-contractive alias returns its stuck head
-- rather than diverging. See the Norm-Stuck note in the module header.
resolveAliasTy :: AliasMap -> Type -> Type
resolveAliasTy am = go Set.empty
  where
    go seen (TCustom n)
      | n `Set.member` seen = TCustom n                     -- Norm-Stuck: non-contractive
      | otherwise           = case Map.lookup n am of
          Nothing   -> TCustom n                            -- Norm-Stuck: unbound
          Just body -> go (Set.insert n seen) body          -- Norm-Alias
    go seen (TDependent _ b _) = go seen b                  -- Norm-Refine
    go _    t                  = t                          -- Norm-Base

-- | @⌈·⌉@ — the CONGRUENT normal form: alias-resolving, refinement-stripping,
-- and structural (unlike 'resolveAliasTy', it normalizes components too).
--
-- This is the specification 'admits' must be invariant under (property A1), and
-- the oracle the property tests compare against. It is deliberately NOT on the
-- 'admits' code path: 'admits' reaches the same answer by head-resolving and
-- delegating components to the self-normalizing predicates, which is cheaper
-- and is what makes agreement with the emitter definitional.
--
-- The @seen@ set is passed DOWN into sibling components rather than threaded
-- across them, so one component's alias chain cannot truncate another's.
normalizeTy :: AliasMap -> Type -> Type
normalizeTy am = go Set.empty
  where
    go seen t = case t of
      TCustom n
        | n `Set.member` seen -> TCustom n                  -- Norm-Stuck: non-contractive
        | otherwise           -> case Map.lookup n am of
            Nothing   -> TCustom n                          -- Norm-Stuck: unbound
            Just body -> go (Set.insert n seen) body        -- Norm-Alias
      TDependent _ b _ -> go seen b                         -- Norm-Refine: STRIP
      -- Norm-Cong, one per constructor. TSumType payloads are included on
      -- purpose: A1 must hold at component positions, and a payload is one.
      TList a          -> TList    (go seen a)
      TMap k v         -> TMap     (go seen k) (go seen v)
      TResult a b      -> TResult  (go seen a) (go seen b)
      TPair a b        -> TPair    (go seen a) (go seen b)
      TPromise a       -> TPromise (go seen a)
      TFn args ret     -> TFn      (map (go seen) args) (go seen ret)
      TSumType ctors   -> TSumType (map (\(c, mp) -> (c, fmap (go seen) mp)) ctors)
      _                -> t                                 -- Norm-Base

-- ---------------------------------------------------------------------------
-- Component predicates
--
-- Each is SELF-NORMALIZING at its own argument: it chases TCustom and strips
-- TDependent itself. That is what makes 'admits' satisfy A1 at component
-- positions without calling 'normalizeTy'. A future arm whose component
-- predicate lacks these clauses reopens CR-01 one constructor down.
-- ---------------------------------------------------------------------------

-- | Check if a type is int-like after resolving aliases.
-- Handles TDependent refinements and TCustom aliases.
-- Unresolved TCustom falls back to False (sound: rejects unknown types), and a
-- non-contractive alias does the same rather than diverging.
isIntLike :: AliasMap -> Type -> Bool
isIntLike am = go Set.empty
  where
    go _    TInt                  = True
    go seen (TDependent _ base _) = go seen base
    go seen (TCustom n)
      | n `Set.member` seen = False                         -- Norm-Stuck: non-contractive
      | otherwise           = maybe False (go (Set.insert n seen)) (Map.lookup n am)
    -- COMP-3b-general (Phase 1): a nullary enum is int-tag-encodable (each
    -- constructor → its declaration index), so its values live in the QF-LIA sort
    -- env as FQInt. Payload-bearing sum types stay non-int (→ asserted fallback).
    go _    (TSumType ctors)      = all (\(_, mp) -> case mp of Nothing -> True; Just _ -> False) ctors
    go _    _                     = False

-- | Is a type a bool after resolving aliases? (BOOL-FRAG: bool is a native SMT sort.)
isBoolLike :: AliasMap -> Type -> Bool
isBoolLike am = go Set.empty
  where
    go _    TBool                 = True
    go seen (TDependent _ base _) = go seen base
    go seen (TCustom n)
      | n `Set.member` seen = False
      | otherwise           = maybe False (go (Set.insert n seen)) (Map.lookup n am)
    go _    _                     = False

-- | A2.2-string: is the (alias-resolved) type the built-in string? Mirrors
-- 'isBoolLike'. Drives string-valued map admission + the Str $val array sort.
isStrLike :: AliasMap -> Type -> Bool
isStrLike am = go Set.empty
  where
    go _    TString               = True
    go seen (TDependent _ base _) = go seen base
    go seen (TCustom n)
      | n `Set.member` seen = False
      | otherwise           = maybe False (go (Set.insert n seen)) (Map.lookup n am)
    go _    _                     = False

-- | Translatable SCALAR types in the body-faithful fragment (Σ_auto): int-like OR bool.
-- BOOL-FRAG: a bool param/binder gets FQBool via typeToSort and is reasoned about
-- natively (QF-LIA + Bool, decidable). Used only at the sort-env sites; isIntLike stays
-- pure for the int-only decisions (measure carriers, etc.).
isScalarLike :: AliasMap -> Type -> Bool
isScalarLike am t = isIntLike am t || isBoolLike am t

-- ---------------------------------------------------------------------------
-- Fact-injection type gates
--
-- These two are the TYPE half of the emitter's fact-injection gates (the other
-- half being 'LLMLL.FixpointEmit.arrGateActive', excluded here per the
-- declared-type-only side condition in the module header). Defining 'admits'
-- over them is what makes checker/emitter agreement definitional rather than a
-- tested mirror.
-- ---------------------------------------------------------------------------

-- | Alias-resolved bytes[n] detection; yields the type-level length.
-- Gates 'LLMLL.FixpointEmit.bytesLenReft' (the @bytesLen(v) = n@ binder fact)
-- and @resultLenFact@ (the same fact on a declared return).
bytesLenOf :: AliasMap -> Type -> Maybe Int
bytesLenOf am t = case resolveAliasTy am t of
  TBytes n -> Just n
  _        -> Nothing

-- | LEVER-A2.2: a map whose keys are int-or-string and values are bool (the
-- 0\/1-bridged value class). Gates the value-range-fact scoping (@boolValArrs@),
-- from which @injectBoolValRangeFacts@ asserts @0 <= select(m$val,k) <= 1@.
boolValuedMapTy :: AliasMap -> Type -> Bool
boolValuedMapTy am t = case resolveAliasTy am t of
  -- A2.2-string (keys): key-agnostic — string-keyed bool maps get the same
  -- int-0/1 value bridge + range facts.
  TMap kt vt -> (isIntLike am kt || isStrLike am kt) && isBoolLike am vt
  _          -> False

-- ---------------------------------------------------------------------------
-- The shared admissibility predicate
-- ---------------------------------------------------------------------------

-- | SAFE-ARG \/ WILD-ASSUME: does a DECLARED type of this shape contribute a
-- ground fact to a VC antecedent that no obligation discharges?
--
-- A @bytes[n]@ binder has @bytesLen(v) = n@ asserted from its declared type, and
-- the index-in-bounds obligation is then discharged against it — so an
-- unvalidated declaration yields a false premise and a false SAFE. A
-- @map[k,bool]@ binder has the per-key value range asserted the same way.
--
-- Deliberately NOT members: refinement aliases and nullary enums, whose
-- type-level data is an OBLIGATION on the producer (LLMLL.md §3.4.1) rather than
-- an assumption, both measured REFUTED on a laundered value. That exclusion is
-- about the PREDICATE a refinement carries, not about the base type it wraps: a
-- @where@-wrapped @bytes[n]@ or @map[k,bool]@ still carries the same
-- undischarged ground fact from its base, and 'resolveAliasTy' strips
-- 'TDependent' before the emitter decides to assert it. That is CR-01, and it is
-- unrepresentable here: this predicate and the emitter's gates are the same
-- functions, not mirrored ones.
--
-- TOTAL on unnormalized input: 'admits' normalizes what it inspects. Callers do
-- not have to have expanded aliases first, and the guard cannot go dead because
-- one of them forgot (property A2).
admits :: AliasMap -> Type -> Bool
admits am t = isJust (bytesLenOf am t) || boolValuedMapTy am t
