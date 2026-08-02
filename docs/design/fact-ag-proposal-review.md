---
name: fact-ag-proposal-review
title: "Professor review of fact-ag-proposal.md, rounds 0-1"
status: "Standalone review, not folded. Round 0 (seven findings against Rev 0) produced the three-stage restructure in Rev 1. Round 1 CONCEDES H2's resolution on re-measurement and REJECTS the completed Hoare criterion as stated, on an internal-inconsistency ground that does not block Stage 1 but does block promoting the criterion into TypeAdmissibility.hs"
reviewed: "FACT-AG Rev 0 (conversational) and Rev 1 (docs/design/fact-ag-proposal.md), language-team, 2026-08-01"
date: 2026-08-01
author: professor
consumers: [language-team, compiler-engineer, documentation-lead, user]
---

# Professor review: FACT-AG-LEN

Two rounds. Round 0 found the return half of the Rev 0 proposal undischargeable and produced the
three-stage restructure now in [`fact-ag-proposal.md`](fact-ag-proposal.md). Round 1 re-measures the
one finding whose resolution Rev 1 rejected, concedes it, and finds that the criterion Rev 1
introduced to replace it does not separate the two arms it is asked to separate.

## Context located

1. `compiler/src/LLMLL/FixpointEmit.hs:3332-3337`, `(bytes-zero)` translates to `Map_default(0)`;
   emitter comment states its length comes from the result binder's family-1 fact.
2. `compiler/src/LLMLL/FixpointEmit.hs:692`, `:715-716`, `:732`. The augmentation, the desugared
   rebinding, and the gate read. **Rev 1 cites `:694-696` for the `contract` binding; it is at
   `:715-716`.** See Round 1 finding R1-1.
3. `compiler/src/LLMLL/FixpointEmit.hs:1639-1648`, `arrGateActive`, three disjuncts, third is
   `calleeCarries` over direct callees in the `ContractEnv`.
4. `compiler/src/LLMLL/FixpointEmit.hs:259`, `aug params mRet c = dsContract params
   (augmentContractPost … (augmentContractPre …))`. **The stored `ContractEnv` contracts are
   augmented too.** This is the finding Rev 1 missed; see R1-2.
5. `compiler/src/LLMLL/FixpointEmit.hs:1541-1546`, `:1587`, `:1589-1592`. Mention set contains
   `"bytes-length"`; `contractMentionsBytesOp` reads both pre and post.
6. `compiler/src/LLMLL/FixpointEmit.hs:953-954`, `:968-970`, `:1450`. `typeToSort` at Result
   components, ADT payload keys, and payload-subtyping. Confirms Rev 1's rejection ground.
7. `compiler/src/LLMLL/FixpointEmit.hs:737-748`, `boolValArrs` is scoped by the **declared type** of
   params and result, not by construction history. The basis for R1-3.
8. `compiler/src/LLMLL/FixpointIR.hs`, `data FQPred`, eleven constructors, no quantifier former.
9. `docs/design/type-driven-development.md:8,14,20,70-78`, the obligations-not-indices decision.
10. External: Hoare, *Proof of Correctness of Data Representations*, Acta Informatica 1(4), 1972;
    Bradley, Manna, Sipma, *What's Decidable About Arrays?*, VMCAI 2006; Vazou et al., *Refinement
    Types for Haskell*, ICFP 2014 §3.

---

## Round 0: seven findings against Rev 0

Rev 0 proposed a two-half move: elaborate `bytes[n]` into a `TDependent` carrying
`(= (bytes-length v) n)`, route the parameter position through `augmentContractPre` and the return
position through `augmentContractPost`, and exclude the `map[k,bool]` value range on a
fragment-membership argument.

**H1. `bytes-zero` cannot discharge the return obligation Rev 0 creates.** Soundness-adjacent
regression. `FixpointEmit.hs:3332-3337`. `(bytes-zero)` translates to `Map_default(0)` and the
emitter comment says outright that "the result binder's family-1 fact supplies its length," which is
`resultLenFact`, the exact antecedent Rev 0 moves into the goal. The body VC for
`(def mk [] -> bytes[64] (bytes-zero))` becomes `result = Map_default(0) ⟹ bytesLen(result) = 64`,
which is UNSAT. `bytes-zero` is the only bytes introduction form (`bytesOpNames`, `:1542`), so Rev 0
refutes every bytes-constructing function in the corpus, `examples/bytes-bounds/` included. **Bite:
blocks the return half.**

**H2. The elaboration is unconditional; the sort assignment is `arrGate`-conditional.** Soundness,
ill-sorted `.fq`. `augmentContractPre` runs at `:692` with no reference to `arrGateActive`; `sortA1`
gives a bytes parameter `byteArraySort` only when the gate holds (`:734-752`); `typeToSort` has no
`TBytes` clause so an off-gate bytes parameter falls to `FQInt` (`:2379-2390`); `bytesLen` is
declared over `[FQArr FQInt FQInt]` (`:4222`). Rev 0's "no fragment widening" claim does not survive
this. **Bite: blocks.** Recommended resolution at the time: widen `typeToSort (TBytes n)` to
`byteArraySort`. **Rev 1 rejected that resolution and Round 1 concedes the rejection.**

**H3. The map-arm exclusion rests on a decidability claim that is false.** Scope, mis-stated as
decidability. `∀k. 0 ≤ select(m$val,k) ≤ 1` sits inside the array property fragment of Bradley,
Manna and Sipma (VMCAI 2006): universally quantified index, trivially true index guard, value
constraint a comparison over `select` at the quantified index with no nested select. Decidable, and
Z3 discharges it by E-matching on the `select` trigger; no EPR restriction is involved. The real
barrier is that `FQPred` has no quantifier former and liquid-fixpoint's Horn interface is
quantifier-free. **Bite: complicates.** The conclusion survives; the stated reason does not.

**H4. `bytes[n]` is the one place LLMLL took the Idris route without the Idris machinery.** Scope,
drift against the project's own record. `docs/design/type-driven-development.md:8,14,20` records the
settled decision to implement type-driven development "through obligations, not indexed types," with
`Vect n a` research-track only. `bytes[n]` is `Vect n Byte` with the index in the type, and §3.4.2
non-goals #2 through #5 foreclose the machinery that makes an Idris index true by construction
(`Nil : Vect 0 a`, `type-driven-development.md:70-78`). SAFE-ARG is the predictable consequence.
Rev 0 argued from Liquid Haskell, which is correct but weaker than the project's own decision.
**Bite: only matters at scale**, but it reclassifies the proposal from improvement to repair.

**H5. "Representation invariant" does not license free assumption.** Soundness of the criterion.
Hoare (1972) is two-sided: an abstraction invariant may be assumed by every operation only because
every constructor is separately proved to establish it. Rev 0 took the assume-half and omitted the
establish-half. For `map[k,bool]` the constructors are `map-empty` and `map-put`, and Rev 0 makes no
argument about them. **Bite: complicates.** *Round 1 finds Rev 1's repair of this finding introduces
a worse problem; see R1-3.*

**H6. Component positions unaddressed.** Soundness. `resolveAllRefinements` (`:4229-4233`) recurses
through `TDependent` and `TCustom` only and does not descend into `TMap`, `TPair`, `TResult`, or
`TSumType`, so a head-applied elaboration yields no obligation there. Consistent with the emitter
today, since `bytesLenOf` is head-only, but ADMIT-SHARED records that "A1's bite is entirely at
component positions." **Bite: complicates.** Needs to be a stated exclusion carrying its
emitter-agreement argument.

**H7. Two Rev 0 assertions checked rather than accepted, both holding.** Call-pre obligation
constraints conjoin `mPre` into their LHS (`:1340-1344`) and `mPre` derives from the augmented
contract, so deleting `bytesLenReft` preserves index-in-bounds premises. `CodegenHs.hs:569` reads the
raw `contractPre`, not the augmented one, so the elaboration produces no runtime assertion and
§3.4.5's alias-predicate channel distinction survives.

### Round 0 recommendation

Adopt the parameter half; fix the constructor before adopting the return half; restate the map-arm
exclusion. Ranked: (1) ship Stage 1 after resolving H2; (2) give `bytes-zero` a constructor post
before moving `resultLenFact`, since landing the return half first refutes the corpus; (3) keep the
map arm out but rewrite the reason; (4) keep both WILD-ASSUME seams as diagnostics; (5) do not open
a peer `FACT-AG-RANGE` row; (6) cite `type-driven-development.md` as the primary rationale.

### Round 0 open questions

1. Is a syntactic restriction on where an introduction form may appear an accepted way to discharge
   Hoare's establish-half, or does the discipline require the constructor to be index-respecting in
   its own signature?
2. Is there a standard name for "sealed introduction forms establish the invariant," and does the
   literature record a failure mode where a constructor-established invariant is unsound under
   composition?

---

## Round 1: adjudication of Rev 1

Rev 1 adopted H1, H3, H4, H5, H6 and recorded H7. It rejected H2's proposed resolution. Three
findings follow.

### R1-1. H2's resolution: conceded, with a citation correction

**Conceded.** Re-measured at HEAD, Rev 1 is right and the Round 0 recommendation was wrong.

- `contractAug` is bound at `:692`.
- `contract` is rebound at `:715-716` as `contractAug` with `dsAll` applied to both clauses.
- `arrGate = arrGateActive cenv contract mBody` at `:732` reads that rebinding.
- `arrGateActive`'s first disjunct is `contractMentionsArrOp contract` (`:1640`), which reads pre and
  post (`:1589-1592`) against a mention set containing `"bytes-length"` (`:1542`, `:1587`).

So an elaborated precondition sets the gate for the function that carries it, the parameter binds at
`byteArraySort` through `sortA1`, and the ill-sorted off-gate population predicted in H2 does not
arise. Rev 1's ground for rejecting the `typeToSort` widening is also confirmed: `typeToSort` serves
Result `$ok`/`$err` components (`:953-954`), ADT payload keys (`:968-970`), and payload-subtyping
(`:1450`), where widening would array-sort a bytes component with no gate and no binder fact in
scope. The Round 0 recommendation would have traded one ill-sorted population for another.

The composition is monotone and one-pass, as Rev 1 claims: the augmentation is a function of declared
types only and does not read the gate, so there is no fixpoint.

**Citation defect.** Rev 1 cites `FixpointEmit.hs:694-696` for the `contract` binding in three places
(the Stage 1 paragraph, the sort/gate section, and the review-history table). The binding is at
`:715-716`; `:694-696` is `ctorTags` / `dsExpr` and the MATCH-WIDEN comment block. The whole H2
rejection turns on this line, and an engineer sent to `:694-696` will not find it. Classify:
spec-drift, cosmetic. Bite: **complicates**, fix before hand-off.

### R1-2. NEW: gate self-activation propagates through the ContractEnv, and Rev 1 understates its blast radius

Not in Rev 0, not in Round 0, not in Rev 1. Classify: verification-ergonomics. Bite: **complicates**;
it enlarges the acceptance gate's declared delta set, which Rev 1 sizes at two entries.

`FixpointEmit.hs:259` builds the stored `ContractEnv` with
`aug params mRet c = dsContract params (augmentContractPost am mRet (augmentContractPre am params c))`.
The stored contracts are augmented by the same function the definition site uses. After the
elaboration lands, **every function with a `bytes[n]` parameter or return has a stored contract
mentioning `bytes-length`**.

`arrGateActive`'s third disjunct is `calleeCarries` (`:1642`, `:1645-1647`), which fires when any
direct callee's stored contract mentions an array op. So every **direct caller** of a bytes-typed
function self-activates the gate, whether or not the caller touches bytes or maps at all. If that
caller happens to carry a `map[int,int]` parameter, the map now splits into the `$has`/`$val`
encoding.

Rev 1's edge case 3 and delta-set entry 2 describe only "a function carrying both a `bytes[n]` and a
`map[int,int]` parameter." The actual population is that set **plus the direct-caller set of every
bytes-typed function**, intersected with functions carrying admissible maps. On a corpus where
`bytes[n]` appears in eight source files this is small, but it is not the population Rev 1 declares,
and an undeclared delta reads as a regression during the sweep, which is Rev 1's own stated concern.

Two mitigating facts, both worth recording rather than leaving to be rediscovered. First, the
propagation is **one hop, not transitive closure**: `calledNames` walks the caller's own body
(`:1649-1656`), and a gated caller gains no `bytes-length` in its own contract unless it declares
bytes itself, so the cascade terminates immediately. Second, activation is monotone in the direction
of *more* array machinery, so it is a `.fq` and solver-load question, not a soundness one.

### R1-3. Rev 1's completed Hoare criterion does not separate the two arms

This is the substantive Round 1 finding. Classify: soundness of the criterion, not of the code. Bite:
**does not block Stage 1**; blocks promoting the criterion into `TypeAdmissibility.hs`'s header,
which Rev 1's "Affected surface" instructs.

Rev 1 states the criterion as:

> A fact derived from a declared type may be assumed in a VC antecedent only if it is established by
> the sealed introduction forms of that type. Otherwise it must be earned as an obligation.

and applies it to conclude that the bytes length must be earned (establish-half absent) while the
bool-map value range may be assumed (establish-half present, discharged by `map-empty` and
`map-put`).

**The criterion, applied consistently, contradicts Rev 1's own Stage 3.** Rev 1 writes, of Stage 2:
"With Stage 2 in place the bytes algebra closes: `bytes-set` already emits length preservation
`bytesLen(r) = bytesLen(b)` (`:3327`), so one constructor axiom plus one preservation lemma covers
every bytes introduction and update." That is precisely Hoare's establish-half for `bytes[n]`. If
"established by the sealed introduction forms" licenses assumption, then after Stage 2 the bytes
length is established by its sealed introduction forms, and Stage 3 is unnecessary by Rev 1's own
rule. Rev 1 nonetheless ships Stage 3. Either the criterion is wrong or Stage 3 is redundant, and
Stage 3 is not redundant.

**What the criterion omits is modularity.** Hoare's discipline is a whole-program argument: the
invariant holds of every reachable representation value because every operation that can produce one
is in the checked set. LLMLL verifies modularly (`LLMLL.md §5.3.4`): the emitter sees one function at
a time and never sees the construction history of a parameter, which may originate in another
function or across an `import`. `boolValArrs` makes this concrete: it is scoped by the **declared
type** of params and result (`:737-748`), not by any construction history, so the range fact for a
bool-map parameter is asserted from the declaration exactly as `bytesLenReft` asserts the length.
Under modular verification, "the sealed constructors establish it" reduces to "the type channel
carried it here intact," which is the trust SAFE-ARG showed can be broken.

**Both arms are in the same position.** `compatibleWith` checks bytes lengths by exact equality
(`TypeCheck.hs:2387`) and map components structurally, so neither a `bytes[32]` nor a `map[k,int]`
can reach the wrong parameter except through the bare wildcard, which WILD-ASSUME and WILD-ASSUME-2
close. FACT-AG's motivating argument is not that the wildcard is open; it is that guarding it is a
denial list requiring per-arm extension, and that CR-01 cost a release-cycle defect on an arm that
had already shipped. That argument applies to the map arm with equal force.

**Disposition.** The map arm should stay off the obligation channel, and Rev 1's recommendation is
right, but it rests on reason #2 alone: the quantified form is inexpressible in `FQPred`, and
LLMLL's Horn interface is quantifier-free by construction. That is a scope decision about the
verification tooling, it is defensible, and it needs no appeal to Hoare. Reason #1 should be struck
or restated with the modularity qualifier that makes it true, roughly: a representation invariant may
be assumed at a parameter only when the type channel is trusted to carry it, and that trust is what
the WILD-ASSUME family polices. Stated that way it explains why both arms currently sit where they
do, and it stops predicting that Stage 3 is unnecessary.

The claim in Rev 1 that the criterion "predicts ARR-RANGE-NAME's prescribed disposition without
having been tuned to it" is one row, and one drawn from the family the criterion was written around.
Per this project's own claim discipline, that is corroboration, not evidence, and it should not be
cited as independent support.

### Round 1 answers to the two open questions

**Question 1: does a syntactic restriction on where an introduction form may appear discharge the
establish-half?** Yes, and the standard name for the mechanism is an *abstract data type with a
sealed constructor interface*; the restriction at `TypeCheck.hs:1216,1250` is doing the work that a
module-level export list does in Modula-2 or a `newtype` with a hidden constructor does in Haskell.
It is weaker than the Idris `Nil : Vect 0 a` shape in one respect that matters here: an
index-respecting constructor signature makes the invariant *checkable at every use site by the type
checker*, whereas a syntactic placement restriction makes it checkable only where the restriction is
enforced, and a later relaxation of that restriction silently invalidates the axiom with no local
signal. Recommend that Stage 2's axiom carry an explicit note tying its validity to
`TypeCheck.hs:1216,1250`, so that relaxing the placement rule fails loudly.

**Question 2: can a constructor-established invariant be unsound under composition?** Yes, and the
canonical treatment is the *abstraction function plus representation invariant* pair rather than the
invariant alone (Hoare 1972; Liskov and Guttag's formulation of the rep invariant and abstraction
function; Mitchell and Plotkin's existential-type reading of abstract types, TOPLAS 1988, gives the
type-theoretic version). The failure mode is precisely R1-3's: the invariant is established by the
constructors and preserved by the operations, but a value crosses an abstraction boundary by a route
that is not one of those operations, so the invariant travels on the boundary's guarantee rather than
on the algebra's. That is what a modular verifier's parameter position is.

---

## Round 1 recommendation

Ship Stage 1. The three findings above change text, not the design.

1. **Fix the `:694-696` citation to `:715-716`** in all three places before the engineer hand-off
   (R1-1). The rejection of the Round 0 resolution stands on that line.
2. **Enlarge the declared delta set** to include the direct-caller set of every bytes-typed function
   intersected with map-carrying functions, and record that propagation is one hop (R1-2). Rev 1's
   acceptance gate is verdict-preservation against a declared delta set, so an underdeclared set is
   the gate failing, not the implementation.
3. **Strike reason #1 from the map-arm exclusion, or add the modularity qualifier** (R1-3). Do not
   promote the criterion as currently worded into `TypeAdmissibility.hs`'s header; as stated it
   implies Stage 3 is unnecessary.
4. Everything else in Rev 1 stands, including the three-stage ordering, the Stage 2 constructor
   axiom, the component-position exclusion, the retention of both WILD-ASSUME seams, and the refusal
   to open a peer `FACT-AG-RANGE` row.

## Open questions for the language-team

1. R1-3 leaves the map arm excluded on the inexpressibility ground alone. If `FQPred` ever gains a
   quantifier former, that ground disappears and the map arm becomes a live FACT-AG candidate under
   the same argument that motivates the bytes arm. State whether the closed disposition note for the
   range arm should carry that reopening trigger explicitly, in the manner of
   [`strict-sibling-disposition.md`](strict-sibling-disposition.md), rather than being closed
   unconditionally.
