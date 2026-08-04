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
-- FACT-AG-LEN Stage 3 narrowed 'admits' by removing the @bytes[n]@ arm, and the
-- asymmetry above INVERTS for a class removed this way. The bytes length is no
-- longer injected anywhere: a param contributes it to the effective pre
-- ('LLMLL.FixpointEmit.bytesLenParamPre', proved at each call site), a return to
-- the effective post ('LLMLL.FixpointEmit.bytesLenRetPost', proved by the body
-- VC), and @(bytes-zero)@ to a sealed-builtin axiom. So for @bytes[n]@ the
-- narrow direction now costs a worse DIAGNOSTIC, not a false SAFE: a laundered
-- length that 'admits' stops rejecting becomes a refuted obligation instead of a
-- localized type error. That is why the WILD-ASSUME seams keep rejecting it via
-- 'wildAssumeRejects' below rather than going dead with the arm.
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
-- == Relation to FACT-AG-LEN
--
-- 'admits' is a denial list over declared types, and ADMIT-SHARED makes it
-- coherent and cheap to extend. This header used to say its principled terminal
-- state was the EMPTY predicate, reached by FACT-AG routing every type-derived
-- fact through the assume-guarantee channel. That was wrong, and
-- docs\/design\/fact-ag-proposal.md corrects it: __the terminal state is
-- 'boolValuedMapTy'__, and FACT-AG-LEN reached it at Stage 3.
--
-- The two arms differ on Hoare's two-sided discipline (/Proof of Correctness of
-- Data Representations/, Acta Informatica 1(4), 1972), which the proposal states
-- as a two-clause criterion:
--
--   [Establishment] a fact derived from a declared type may be assumed in a VC
--   antecedent only if the type's sealed introduction forms establish it;
--
--   [Modularity] an established fact that is /parametric in a type index/ must
--   additionally be re-exported as a guarantee to cross a call boundary, because
--   the caller cannot see the callee's introduction forms; one that is /uniform
--   over the type constructor's inhabitants/ needs no export channel.
--
--   * @bytes[n]@ length: the sole introduction form @(bytes-zero)@ established
--     nothing until FACT-AG-LEN Stage 2 gave it a length axiom, and the length is
--     parametric in @n@, so Stage 3 had to export it through the post as well.
--     Earned at both ends now, so the arm is __gone from 'admits'__.
--   * @map[k,bool]@ value range: @map-empty@ and @map-put@ are sealed builtins
--     that establish it by construction, and the range holds of every inhabitant
--     of @map[k,bool]@ with no index to carry, so there is nothing to earn and
--     nothing to export. The arm __stays__, and it is closed rather than
--     deferred. There is deliberately no @FACT-AG-RANGE@ row.
--
-- So this module is no longer provisional against FACT-AG. 'boolValuedMapTy' is
-- where it lands. The remaining hole on that arm is ARR-RANGE-NAME
-- (docs\/compiler-team-roadmap.md), which is about threading the declared type,
-- not about earning the fact.
module LLMLL.TypeAdmissibility
  ( -- * Alias environment
    AliasMap
  , buildAliasMap
  , builtinAliases
  , sealedTypeNames
  , opaqueSealedNames
  , jsonTypeName
  , mentionsJson
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
  , wildAssumeRejects
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
--
-- EFFECT-RESP: unions 'builtinAliases' underneath the module's own definitions,
-- so every consumer of this function (notably 'FixpointEmit.cacheAwareAliasMap'
-- and the VC emitter's sum-sort path) resolves @TCustom "Response"@ to its
-- 'TSumType' body rather than leaving it opaque. Local definitions win the
-- union; 'sealedTypeNames' is what keeps that from mattering in practice.
buildAliasMap :: [Statement] -> AliasMap
buildAliasMap stmts =
  Map.union (Map.fromList [(n, body) | STypeDef n body <- stmts]) builtinAliases

-- | EFFECT-RESP: type-level half of the sealed builtin types.
--
-- Seeded into every alias environment so that alias resolution reaches the
-- 'TSumType' body. That resolution is what the checker's exhaustiveness pass
-- needs: it dispatches on 'TSumType' and abstains on an unresolved 'TCustom',
-- so without this entry a @match@ on a Response missing its 'RErr' arm
-- type-checks clean. Exhaustiveness is what converts a response arm the program
-- did not expect from a crash into a value, so this entry is what bounds the
-- command-to-response pairing residue.
--
-- The VALUE half (the four constructors as callable bindings) lives in
-- 'LLMLL.TypeCheck.builtinEnv'. Both are needed and they are kept in sync by
-- hand; the constructor set here is the one the exhaustiveness check reads.
--
-- Payload classes are 'string' and 'int' only, both inside Σ_auto, which is why
-- this addition does not widen the verification fragment. There is deliberately
-- no RBytes arm: @bytes[n]@ needs a literal type-level length and a file read's
-- length is not statically known. Binary reads are a named residue.
builtinAliases :: AliasMap
builtinAliases = Map.fromList
  [ ("Response", TSumType
      [ ("RNone", Nothing)
      , ("RText", Just TString)
      , ("RCode", Just TInt)
      , ("RErr",  Just TString)
      -- Rev 5. Payload is list[string], which reflects to the opaque FQList
      -- carrier, so a body matching this arm falls back exactly as any
      -- list-mentioning body does. No fragment widening.
      , ("RList", Just (TList TString))
      ])
  ]

-- | JSON-1: the sealed opaque carrier's type name, in one place so the checker,
-- the emitter, and the seal agree.
jsonTypeName :: Name
jsonTypeName = "Json"

-- | JSON-1: sealed types that are OPAQUE, i.e. have no 'TSumType' body and
-- therefore no 'builtinAliases' entry.
--
-- 'sealedTypeNames' used to be exactly @Map.keys builtinAliases@, which cannot
-- express this class: an opaque type is sealed precisely BECAUSE it has no body
-- to put in the alias map, so keying the seal off that map left it unsealable.
-- Measured before the fix: @(def-shell f [j: Json] 1)@ type-checked clean with
-- @Json@ undeclared, and @(type Json ...)@ would have shadowed the builtin
-- silently.
opaqueSealedNames :: [Name]
opaqueSealedNames = [jsonTypeName]

-- | Type names a program may not redefine.
--
-- A module's own @STypeDef@s shadow seeded aliases by design, so without a
-- guard a program declaring @(type Response ...)@ silently replaces the harness
-- contract's type with its own: the generated loop would then hand a builtin
-- Response to a step whose parameter is the user's type, and the mismatch would
-- surface at GHC rather than at @check@.
sealedTypeNames :: [Name]
sealedTypeNames = Map.keys builtinAliases ++ opaqueSealedNames

-- | JSON-1 (JSON-NOEQ): does a type mention the sealed @Json@ carrier anywhere?
--
-- Alias-chasing and structural, because the equality denial has to hold at every
-- position @Json@ can reach: @list[Json]@ (which 'json-array' produces),
-- @Result[Json, string]@ (which every accessor produces), a pair component, and
-- through a user alias @(type MyJson Json)@.
--
-- Cycle-guarded on the same @seen@ discipline as 'isIntLike': a non-contractive
-- alias returns False rather than diverging. Sound in the denial direction --
-- a stuck alias cannot BE @Json@, because reaching @Json@ requires the chain to
-- terminate at it.
mentionsJson :: AliasMap -> Type -> Bool
mentionsJson am = go Set.empty
  where
    go seen t = case t of
      TCustom n
        | n == jsonTypeName   -> True
        | n `Set.member` seen -> False                       -- Norm-Stuck
        | otherwise           -> maybe False (go (Set.insert n seen)) (Map.lookup n am)
      TDependent _ b _ -> go seen b
      TList a          -> go seen a
      TMap k v         -> go seen k || go seen v
      TResult a b      -> go seen a || go seen b
      TPair a b        -> go seen a || go seen b
      TPromise a       -> go seen a
      TFn args ret     -> any (go seen) args || go seen ret
      TSumType ctors   -> any (maybe False (go seen) . snd) ctors
      _                -> False

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
--
-- After FACT-AG-LEN this no longer gates an INJECTION. Both injection sites it
-- used to gate are gone (a @bytesLenReft@ binder fact at Stage 1, a
-- @resultLenFact@ constraint-LHS fact at Stage 3). It now gates the two sites
-- that EARN the length instead — 'LLMLL.FixpointEmit.bytesLenParamPre' and
-- 'LLMLL.FixpointEmit.bytesLenRetPost' — plus the array-sort selection
-- (@sortA1@, @arrParams@) and the 'wildAssumeRejects' diagnostic below.
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
-- A @map[k,bool]@ binder has the per-key value range asserted from its declared
-- type ('LLMLL.FixpointEmit.injectBoolValRangeFacts'), and an obligation over
-- that map is then discharged against it — so an unvalidated declaration yields
-- a false premise and a false SAFE.
--
-- __@bytes[n]@ is no longer a member__, as of FACT-AG-LEN Stage 3. Its length is
-- earned rather than asserted: proved at each call site from the effective pre,
-- proved by the body VC from the effective post, and established at
-- @(bytes-zero)@ by a sealed-builtin axiom. Nothing injects it, so ADMIT-OVER no
-- longer requires it here. The DIAGNOSTIC value of rejecting a laundered length
-- survives separately, in 'wildAssumeRejects'.
--
-- Deliberately NOT members: refinement aliases and nullary enums, whose
-- type-level data is an OBLIGATION on the producer (LLMLL.md §3.4.1) rather than
-- an assumption, both measured REFUTED on a laundered value. That exclusion is
-- about the PREDICATE a refinement carries, not about the base type it wraps: a
-- @where@-wrapped @map[k,bool]@ still carries the same undischarged ground fact
-- from its base, and 'resolveAliasTy' strips 'TDependent' before the emitter
-- decides to assert it. That is CR-01, and it is unrepresentable here: this
-- predicate and the emitter's gates are the same functions, not mirrored ones.
--
-- TOTAL on unnormalized input: 'admits' normalizes what it inspects. Callers do
-- not have to have expanded aliases first, and the guard cannot go dead because
-- one of them forgot (property A2).
admits :: AliasMap -> Type -> Bool
admits am t = boolValuedMapTy am t

-- | SAFE-ARG \/ WILD-ASSUME, diagnostic half: which declared types reject a bare
-- inference wildcard at the two 'LLMLL.TypeCheck' laundering seams.
--
-- This is 'admits' plus the @bytes[n]@ arm, and the two predicates are separate
-- because after FACT-AG-LEN Stage 3 they answer different questions:
--
--   * 'admits' answers /does an unearned fact enter a VC antecedent/ — a
--     SOUNDNESS question, governed by ADMIT-OVER, and the emitter's injection set
--     is what it must over-approximate.
--   * 'wildAssumeRejects' answers /should the checker reject this laundering
--     hop/ — a DIAGNOSTIC question. For @bytes[n]@ the hop is now caught either
--     way (the call-site or body-VC length obligation is undischargeable against
--     an unannotated callee, so the program is REFUTED), but a type error at the
--     seam names the remedy (annotate the callee's return) where a refuted
--     obligation does not. Keeping the arm here costs nothing: every program it
--     rejects would have been refuted downstream.
--
-- @'admits' am t ==> 'wildAssumeRejects' am t@ by construction, so the seams
-- cannot become narrower than the soundness gate by accident.
wildAssumeRejects :: AliasMap -> Type -> Bool
wildAssumeRejects am t = admits am t || isJust (bytesLenOf am t)
