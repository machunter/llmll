---
name: finding-arg-position-false-safe-review
title: "Professor review of the WILD-ASSUME membership proposal (NORM-MEMBER Rev 1)"
status: "Standalone, not folded. Reviews the Rev 1 membership side-condition proposal; findings 1 and 4 were adopted and produced Rev 3 (ADMIT-SHARED). Ready for fold-and-archive once ADMIT-SHARED ships"
reviewed: "NORM-MEMBER Rev 1, language-team, 2026-08-01"
consumers: [language-team, compiler-engineer, user]
---

# Professor review: WILD-ASSUME membership normalization

Reviews the language-team's Rev 1 proposal (NORM-MEMBER): a side condition stating that
`assumes(τ)` is evaluated on a normalized type `τ ⇓`, with `⇓` defined as
`FixpointEmit.resolveAliasTy`, plus an invariant (N) requiring checker-side admission and
emitter-side injection to agree on every `τ`.

## Context located

1. `compiler/src/LLMLL/FixpointEmit.hs:1476-1479`, `resolveAliasTy`. **Head-only**: the third
   clause is `resolveAliasTy _ t = t`, so a `TMap` head is returned untouched and its components
   are not normalized.
2. `compiler/src/LLMLL/TypeCheck.hs:2374-2396`, `expandAlias`. A **congruence**: recurses into
   `TMap`, `TList`, `TResult`, `TPair`, `TFn`, `TSumType` components, unfolds `TCustom`, and
   rebuilds `TDependent`.
3. `compiler/src/LLMLL/TypeCheck.hs:376-390`, `assumesFactMapKey` / `assumesFactBoolValue`.
   Neither has a `TCustom` clause.
4. `compiler/src/LLMLL/FixpointEmit.hs:1531-1556`, `isIntLike`, `isStrLike`, `isBoolLike`. Each
   carries both a `TDependent` clause and a `TCustom` alias-lookup clause. Self-normalizing.
5. `compiler/src/LLMLL/FixpointEmit.hs:4159-4161`, `bytesRootedArr`. Decides bytes-rootedness by
   string suffix on the FQ variable name, and is **default-true**.
6. `docs/design/`, no review file paired to `finding-arg-position-false-safe.md` existed prior to
   this one.

Three probes were run against the built v0.14.74 binary to test whether component positions are
live: `map[int BoolAlias]` with `(type BoolAlias bool)`, `map[IntAlias bool]` with
`(type IntAlias int)`, and `map[int BoolDep]` with `(type BoolDep (where [b: bool] true))`. All
three are correctly rejected. That reading cuts against the proposal rather than for it, per
finding 1.

## Gaps and hazards

### 1. `⇓` is head-only, so NORM-MEMBER as formalized is weaker than the code it describes

**Soundness / spec-drift. Bite: blocks the proposal as written.**

The proposal defines `⇓` as "exactly `FixpointEmit.resolveAliasTy`" and states the rule as
`assumes(τ ⇓)`. `resolveAliasTy` normalizes only the head. For
`τ = TMap TInt (TCustom "BoolAlias")`, `τ ⇓ = τ`, and `assumesFactBoolValue (TCustom "BoolAlias")`
falls through to `_ = False` (`TypeCheck.hs:387-390`). So `assumes(τ ⇓) = False` and the wildcard is
admitted, while `boolValuedMapTy` (`FixpointEmit.hs:1780-1785`) resolves the same component through
`isBoolLike`'s `TCustom` clause and injects the fact. That is CR-01 again, one constructor deeper.

Derived from the definitions, not executed, because the shipped path does not take it: the three
probes pass only because `expandAlias`, a different and congruent normalization, rewrites the
component before `assumesFact` sees it. The proposal does not mention `expandAlias` in its `⇓`
definition. An engineer implementing NORM-MEMBER literally, and reasonably concluding that an
explicit normalization side condition makes the call-site pre-expansion redundant, would
reintroduce the defect the proposal exists to close.

The proposal claims it generalizes the v0.14.74 spec sentence in three ways, one being "it includes
`TCustom` unfolding." It does not. `resolveAliasTy` unfolds `TCustom` at the head only, and the
head in every map case is `TMap`.

### 2. Two conversion relations with no theorem relating them

**Soundness. Bite: complicates; it is the root of both CR-01 and finding 1.**

LLMLL has two type-normalization algorithms serving one semantic notion. `expandAlias` implements
δ-reduction on `TCustom` as a congruence but preserves `TDependent`. `resolveAliasTy` implements δ
plus refinement-stripping at the head only. Neither is specified as *the* conversion and no
property relates them. CR-01 was the `TDependent` disagreement; finding 1 is the component-position
disagreement waiting behind it.

This is a coherence problem in the precise sense: two derivation paths for one judgment must denote
the same thing (Breazu-Tannen, Coquand, Gunter, Scedrov, *Inheritance as Implicit Coercion*,
Information and Computation 93(1), 1991; Reynolds on coherence for intersection types, 1991). The
dependent-type-theory literature requires conversion to be a single relation with a completeness
theorem against the declarative presentation, not two implementations hoped to agree (Abel, Öhman,
Vezzosi, *Decidability of Conversion for Type Theory in Type Theory*, POPL 2018). LLMLL is not
obliged to adopt that machinery and this review does not recommend it. The observation is that the
project has incurred the cost the machinery prevents while getting none of its guarantees.

Both architectures currently in the tree are defensible in isolation. The emitter head-normalizes
then dispatches to self-normalizing component predicates. The checker congruently pre-normalizes at
the boundary then dispatches to non-normalizing predicates carrying an unstated precondition. They
agree today by coincidence of call-site discipline, not by construction.

### 3. Invariant (N) is unfalsifiable as stated

**Ergonomic / spec-drift. Bite: complicates.**

(N) quantifies over "any predicate `P` that decides whether a declared type contributes a ground
fact" and asserts checker and emitter agree on every `τ`. It cannot be discharged or checked,
because it does not pin the normalization architecture on either side, and finding 1 shows the two
sides currently use different ones. An invariant whose violation is invisible to any mechanical
check is a comment, not a side condition. The project's own claim discipline (agreement and
absence-of-failure are not evidence) applies to spec text as much as to test results.

### 4. `bytesRootedArr` is default-open and intensional, and the proposal under-rates it

**Soundness, pre-existing. Bite: blocks nothing here, but it should not sit as a risk bullet.**

The proposal describes this as deciding "by binder name." The code is worse:
`bytesRootedArr (FQVar n) = not ("$has" isSuffixOf n || "$val" isSuffixOf n)` (`:4159`). Every
array-sorted FQ variable without a map-component suffix is treated as bytes-rooted and receives
ground `0 ≤ select(…) ≤ 255` facts (`:4155-4156`). The discriminant is **default-true**, inverting
the fail-closed posture the project claims as its core value, and **intensional**: it decides a
semantic property by inspecting a generated name, so it is not stable under renaming.
α-equivalence is the floor invariant of a typed language, and a predicate that violates it is not
repairable by normalization, because normalization operates on types and this predicate operates on
names.

The finding's own table already records that this injects false value-range facts on a laundered
non-byte array. That is a second false-fact channel in the same family as SAFE-ARG, unguarded by
any WILD-ASSUME arm, and it should carry its own roadmap row.

## Recommendation

**Reject the side-condition framing. Make the predicates self-normalizing and delete the
precondition.** The smallest principled change is not to state (N), it is to make (N) hold by
construction so there is nothing to state.

1. **Adopt the emitter's architecture on the checker side.** Give the component predicates their own
   `TCustom` and `TDependent` clauses, mirroring `isIntLike:1534-1536` and `isBoolLike:1546-1547`,
   and have the entry predicate head-normalize. The call-site `expandAlias` precondition becomes an
   optimization rather than a correctness dependency, and finding 1 cannot arise. This is the
   normalization-by-evaluation discipline in miniature (Berger and Schwichtenberg, LICS 1991): make
   normalization idempotent and total at the predicate so no consumer carries a "has been
   normalized" obligation it cannot express in a type.

2. **Better, and ranked first: share one function.** The checker should call the emitter's
   admissibility predicates rather than mirroring them. The design rationale on record
   ("mirroring `FixpointEmit.isIntLike`/`isStrLike`/`isBoolLike` minus their `AliasMap` lookups")
   describes deliberately building a second copy with a deliberately weaker normalization, and that
   decision is the proximate cause of CR-01. One shared predicate makes coherence a type-level fact
   instead of a documented hope.

3. **Keep the spec text minimal.** With self-normalizing predicates, §3.4.6 needs one sentence
   stating that class membership is a property of the normal form, and does not need `⇓` as
   inference rules or invariant (N) at all. The `Norm-*` triple should not ship: it formalizes the
   head-only relation, which is the wrong one, and a corrected congruent version would duplicate
   `expandAlias`'s specification for no gain.

4. **Route `bytesRootedArr` separately.** Its fix is a type-keyed discriminant threaded from the
   binder's declared type, a different change from anything the membership proposal touches.

**On the correction to the non-member prose, concur without reservation.** `Q2_alias` witnesses
that a refinement over a non-member base is a non-member, and the implementation generalized it to
"every refinement is a non-member." That correction is the strongest part of the proposal and
should survive revision intact.

## Answers to the two questions put to the reviewer

**Is invariant (N) a named coherence condition?** Yes; citations in finding 2. But naming it is the
wrong move. In the traditions where this condition is named it is discharged by a theorem or
eliminated by construction, never asserted as a side condition. Asserting it buys a citation and no
guarantee.

**Does Liquid Haskell carry a corresponding invariant?** No, and the reason is structural: Liquid
Haskell does not inject facts from declared types at all. Refinements are checked at binding sites
and the fact is earned by a subtyping obligation, so there is no unvalidated declaration to launder
(Vazou, Seidel, Jhala, Vytiniotis, Peyton Jones, *Refinement Types for Haskell*, ICFP 2014, §3; the
same formulation `LLMLL.md:261` already cites for §3.4.1). This is the sharpest available argument
that **FACT-AG is not a nice-to-have but the removal of a self-inflicted wound**. LLMLL's closest
design-reference neighbours have already made this choice: F\*'s length-indexed buffers discharge
the length equality at the call site, and Dafny keeps length at the term level as `a.Length` so no
type-level lie is expressible, both of which `docs/compiler-team-roadmap.md:51` records. The
proposal rates FACT-AG subsumption as "only matters at scale." Rate it higher: every additional
WILD-ASSUME arm widens a surface FACT-AG deletes, the marginal arm is getting more expensive, and
CR-01 cost a release-cycle defect on an arm that had already shipped.

## Disposition

Findings 1, 3 and 4 were adopted in the language-team's Rev 2 and folded into
`finding-arg-position-false-safe.md` Rev 3 as ADMIT-SHARED. Finding 2's framing carries into that
section verbatim. The recommendation was adopted with one refinement from the module graph:
`FixpointEmit` does not import `TypeCheck` (`:120-125`) so a direct edge would be acyclic, but the
predicates depend only on `Type` and `Map Name Type`, so the shared home is a leaf module rather
than a new edge between the two largest modules.

Two questions were put back to the language-team (definitional home of the predicates; whether a
redundant-but-subsumed normalization is stable). Both were adjudicated as non-critical and answered
inward rather than routed: the first is a modularity call the module graph settles, and the second
was converted into the mechanical acceptance criterion `admits τ = admits ⌈τ⌉` recorded in Rev 3.
