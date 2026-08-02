---
name: fact-ag-proposal
title: "FACT-AG-LEN: earn the `bytes[n]` length instead of asserting it from a declaration"
status: "Rev 2, SETTLED, with compiler-engineer at Stage 1. Rev 0 was a two-half move (parameter + return); professor review round 0 found the return half undischargeable because the language's only bytes constructor carries no length, so Rev 1 made this a THREE-STAGE line with the constructor axiom interposed, withdrew Rev 0's false decidability claim about the map arm, completed the criterion with Hoare's establish-half, re-anchored the rationale to the project's own obligations-not-indices decision, and REJECTED the review's proposed fix for the sort/gate hazard on measured grounds. Professor review round 1 CONCEDED that rejection and returned three findings: a stale line citation on which the whole rejection rested, a third delta population (direct callers, via the augmented ContractEnv), and a contradiction between the criterion and Stage 3. Rev 2 fixes the citation, adds the caller population to the declared delta set, and repairs the criterion with a modularity clause (parametric-in-an-index versus uniform-over-inhabitants) rather than by striking a reason as the review proposed. Roadmap row: FACT-AG, to be renamed FACT-AG-LEN"
date: 2026-08-01
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# FACT-AG-LEN: earn the `bytes[n]` length

**One line.** A `bytes[n]` binder has `bytesLen(v) = n` asserted into its VC antecedent from the
declared type, with nothing discharging it; routing that fact through the refinement channel LLMLL
already uses for §3.4.1 introduction obligations makes it earned at the call site and proved at the
definition, and retires the `admits` denial list on the bytes arm.

## Background

`docs/compiler-team-roadmap.md:51` records FACT-AG as "the general form of what WILD-ASSUME
approximates: no fact derived from a *type* enters a VC antecedent unless the function that declared
that type has discharged it." ADMIT-SHARED shipped at v0.14.75 as the interim coherence fix, and its
module header states the position plainly: `admits` "is a denial list over declared types," whose
"principled terminal state is the EMPTY predicate, reached by FACT-AG"
(`compiler/src/LLMLL/TypeAdmissibility.hs`). This proposal is that terminal state, and it finds the
header's claim is not quite right: the terminal state is `boolValuedMapTy`, not empty. Section
[The criterion](#the-criterion-and-why-the-two-arms-differ) gives the reason.

Three sites assert type-derived facts today:

| Site | Fact | Where it lands |
|---|---|---|
| `emitParamBind` (`FixpointEmit.hs:1470-1472`, `bytesLenReft` at `:1553-1559`) | `bytesLen(v) = n` | parameter binder refinement |
| `resultLenFact` (`FixpointEmit.hs:1216-1217`, used `:1270`) | `bytesLen(result) = n` | the constraint **LHS**, i.e. an assumption about the body's own result |
| `injectBoolValRangeFacts` (`FixpointEmit.hs:4127-4140`) | `0 ≤ select(m$val,k) ≤ 1` per occurring select | constraint LHS |

WILD-ASSUME polices the one type-compatibility path by which an unvalidated declaration reaches the
first two. It does not make the facts earned.

## Why this is a repair, not an improvement

`docs/design/type-driven-development.md:8,14,20` records the settled decision: LLMLL implements the
type-driven-development insight "through obligations, not indexed types," with `Vect n a` explicitly
research-track only. `bytes[n]` is `Vect n Byte` with the index in the type. In Idris the index
cannot lie, because the constructors are index-respecting (`Nil : Vect 0 a`,
`(::) : a -> Vect n a -> Vect (S n) a`, quoted at `type-driven-development.md:70-78`). LLMLL's
§3.4.2 non-goals #2 through #5 foreclose dependent pattern matching, type-level computation, proof
terms, and sigma types, which is the entire machinery that makes an Idris index true by
construction.

`bytes[n]` is therefore the one place LLMLL took the indexed-type route without the discipline that
makes indices sound, and SAFE-ARG (`docs/design/finding-arg-position-false-safe.md`) is the
predictable consequence. FACT-AG-LEN converts the index back into an obligation, which is the
project's own recorded choice applied consistently.

Corroborating and weaker: Liquid Haskell has no defect of this class, because refinements are
checked at binding sites and the fact is earned by a subtyping obligation, so there is no
unvalidated declaration to launder (Vazou, Seidel, Jhala, Vytiniotis, Peyton Jones, *Refinement
Types for Haskell*, ICFP 2014, §3; the formulation `LLMLL.md:261` already cites for §3.4.1).
`docs/compiler-team-roadmap.md:51` additionally records that F\*'s length-indexed buffers discharge
the length equality at the call site and Dafny keeps length at the term level as `a.Length`.

## The criterion, and why the two arms differ

Rev 0 split the two arms on "value property versus representation invariant" and took only the
assume-half of that distinction. Hoare's discipline (*Proof of Correctness of Data Representations*,
Acta Informatica 1(4), 1972) is two-sided: an abstraction invariant may be **assumed** by every
operation only because every constructor is separately proved to **establish** it. Completed:

> **(i) Establishment.** A fact derived from a declared type may be assumed in a VC antecedent only
> if it is established by the sealed introduction forms of that type. Otherwise it must be earned as
> an obligation.
>
> **(ii) Modularity.** Establishment is visible only intraprocedurally. A fact that is *parametric
> in a type index* must additionally be re-exported as a guarantee to cross a call boundary, because
> the caller cannot see the callee's introduction forms and the index is per-declaration
> information. A fact that is *uniform over the type constructor's inhabitants* carries no
> per-declaration information, is recoverable from the type at any site that knows it, and needs no
> export channel.

Clause (ii) is not decoration; without it the criterion contradicts this proposal's own Stage 3.
Once Stage 2 lands, `bytes-zero`'s axiom plus `bytes-set`'s preservation lemma establish the length
by construction, so clause (i) alone would say the length may be assumed and Stage 3 is unnecessary.
It is not, because `bytesLen(v) = n` is parametric in `n`: a caller of a `-> bytes[64]` function
sees only the type, not the body that established 64, so the guarantee has to cross the boundary
explicitly. This is ordinary assume-guarantee (`LLMLL.md §5.3.4`), and clause (ii) is the point at
which the criterion meets it.

The parametric/uniform axis is the same index-versus-inhabitant distinction that
[Why this is a repair](#why-this-is-a-repair-not-an-improvement) draws: `n` in `bytes[n]` is a type
index in the `Vect n a` sense, whereas the bool value class of `map[k,bool]` fixes a fact holding of
every inhabitant with no index to carry.

Applied to the two arms:

- **`bytes[n]` length.** The sole introduction form is `(bytes-zero)`. It translates to
  `Map_default(0)` and carries no length; the emitter comment at `FixpointEmit.hs:3332-3337` says so
  in terms: "the result binder's family-1 fact supplies its length," which is `resultLenFact`. The
  establish-half is **absent** at clause (i), so the length must be earned. This is why Stage 2
  below has to exist. And once Stage 2 supplies establishment, clause (ii) still bites, because the
  length is parametric in `n`: that is Stage 3.
- **`map[k,bool]` value range.** The introduction forms are `map-empty` and `map-put`, both sealed
  builtins; `map-empty` defaults to 0 and `map-put` at a bool-typed value crosses the 0/1 bridge
  (LEVER-A2.2, `boolValuedMapTy`). The establish-half is **present** at clause (i), discharged by
  construction, and clause (ii) does not bite: the range holds of every inhabitant of `map[k,bool]`
  with no index to carry across a boundary, so no export channel is needed.
  The fact may be assumed, and the residual risk is a type that lies about its value component,
  which is the type channel's problem: WILD-ASSUME-2 closes the wildcard path, and ARR-RANGE-NAME
  (`docs/compiler-team-roadmap.md:54`) is the remaining hole.

The criterion is checkable per arm, and it predicts ARR-RANGE-NAME's prescribed disposition (thread
the declared type, keep the assumption) without having been tuned to it.

**Correction to `TypeAdmissibility.hs`.** The header's "principled terminal state is the EMPTY
predicate" is wrong. The terminal state is `boolValuedMapTy`: representation invariants stay on the
assumption channel by the criterion above. The header should be restated when the bytes arm is
removed.

## Design

### Surface and schema

**None.** `TBytes Int` is the only bytes former and `length` is a required JSON-AST field
(`compiler/src/LLMLL/Syntax.hs:132`, `ParserJSON.hs:496`), so there is no bare `bytes` to write and
the refinement target is not expressible in surface syntax. FACT-AG-LEN is an internal elaboration
in the emitter. No grammar change, no schema delta, no schema-version bump.

### Semantics: the elaboration

At the point `augmentContractPre` / `augmentContractPost` read declared types
(`FixpointEmit.hs:4280-4317`, over `resolveAllRefinements` at `:4229`):

```
⟨bytes[n]⟩  =  TDependent v (bytes[n]) (= (bytes-length v) n)
```

The base stays `bytes[n]`. The length is still needed by `sortA1` for the array sort and by
`compatibleWith`'s exact-equality clause `compatibleWith _ (TBytes m) (TBytes n) = m == n`
(`TypeCheck.hs:2387`). The elaboration must be alias-chasing, since `resolveAllRefinements` chases
`TCustom` through the alias map (`FixpointEmit.hs:4232`) and an alias that gets no obligation while
its expansion does is CR-01's shape at a new site.

### Three stages, and the ordering is a correctness constraint

**Stage 1, parameter position.** `resolveAllRefinements` yields the elaborated pair,
`augmentContractPre` conjoins it into the effective precondition, and §5.3.4's call rule discharges
it at each call site under PROVE polarity and assumes it inside the callee. `bytesLenReft` is
deleted from `emitParamBind` (`:1470-1472`); the same fact now arrives earned.

Verified, not assumed: call-pre obligation constraints conjoin `mPre` into their LHS
(`FixpointEmit.hs:1340-1344`) and `mPre` derives from `contractAug` (formed `:692`, rebound as
`contract` at `:715-716`), so an
index-in-bounds obligation emitted mid-body still sees the length premise after it moves from the
binder refinement to the effective pre.

**Stage 2, the constructor axiom.** `(bytes-zero)` at determining context `bytes[n]` denotes the
constant-zero array **of length n**, so its VC node carries `bytesLen(result) = n`. This is an axiom
about a sealed builtin, not an assumption inherited from a user annotation: `TypeCheck.hs:1216,1250`
restricts `(bytes-zero)` to the whole body of a def with a literal `-> bytes[n]` return, so there is
no laundering path into it, and LEVER-A0 already requires the declared return
(`FixpointEmit.hs:418`).

With Stage 2 in place the bytes algebra closes: `bytes-set` already emits length preservation
`bytesLen(r) = bytesLen(b)` (`FixpointEmit.hs:3327`), so one constructor axiom plus one preservation
lemma covers every bytes introduction and update.

**Stage 3, return position.** `augmentContractPost` conjoins `(= (bytes-length result) n)` into the
effective postcondition; `resultLenFact` moves off `lhsPred` (`:1216-1217`, `:1270`) into the goal,
so the body VC proves its own result length. Call sites recover it as an assumed post through the
existing assume-guarantee step 2 (`LLMLL.md §5.3.4`). `admits` loses `bytesLenOf` at this stage.

**Stage 3 must not land before Stage 2.** Without the constructor axiom, the body VC for
`(def mk () -> bytes[64] (bytes-zero))` is `result = Map_default(0) ⟹ bytesLen(result) = 64`, which
is UNSAT. That refutes every bytes-constructing function in the corpus, including
`examples/bytes-bounds/`, which is LEVER-A3's acceptance fixture.

### Component positions: a deliberate exclusion

`resolveAllRefinements` recurses through `TDependent` and `TCustom` only
(`FixpointEmit.hs:4229-4233`); it does not descend into `TMap`, `TPair`, `TResult`, or `TSumType`.
A `bytes[n]` at a component position therefore receives no obligation. This is sound because it
agrees with the emitter: `bytesLenOf` resolves head-only through `resolveAliasTy`, so no fact is
injected at those positions either.

Stated explicitly rather than left to inference, because ADMIT-SHARED's acceptance criterion records
that "A1's bite is entirely at component positions" and that is where the next CR-01 will live.

### What is not proposed: the map arm

The `map[k,bool]` value range stays on the assumption channel. Two reasons, in order of weight:

1. **Both clauses of the criterion are satisfied.** The establish-half is discharged by `map-empty`
   and `map-put` (clause i), so there is nothing to earn; and the range is uniform over every
   inhabitant of `map[k,bool]` rather than parametric in an index (clause ii), so there is nothing
   to export either. This is the reason that does the work, and it is why the map arm is *closed*
   rather than deferred.
2. **The quantified form is inexpressible** in LLMLL's refinement IR. `FQPred`
   (`compiler/src/LLMLL/FixpointIR.hs`) has eleven constructors and no quantifier former, and
   liquid-fixpoint's Horn-constraint interface is quantifier-free by construction.

Rev 0 gave a third reason, that `∀k. 0 ≤ select(m$val,k) ≤ 1` escapes QF-LIA and would need an EPR
restriction. **That claim is withdrawn as false.** The formula sits inside the array property
fragment of Bradley, Manna and Sipma, *What's Decidable About Arrays?* (VMCAI 2006): a universally
quantified index variable, a trivially true index guard, and a value constraint that is a comparison
over `select` at the quantified index with no nested select. The fragment is decidable and Z3
discharges instances of it by E-matching on the `select` trigger. The barrier is LLMLL's chosen
tooling interface, not fragment membership, and the roadmap should not record a decidability claim
that a reviewer can refute in one citation.

**Roadmap consequence.** The FACT-AG row becomes `FACT-AG-LEN`, staged 1/2/3, plus a **closed**
disposition note for the range arm. An open `FACT-AG-RANGE` row would imply work that this section
says should never be done.

## Edge cases and degenerate inputs

1. **Positive witness, Stage 1, argument position.**
   ```lisp
   (def read-tag [b: bytes[64]] -> int (post (>= result 0)) (bytes-get b 40))
   (def make-key [] (bytes-zero))                    ;; unannotated: tau_ret = ?
   (def caller [] -> int (read-tag (make-key)))
   ```
   `caller` owes `(= (bytes-length (make-key)) 64)`. `make-key` exports no length guarantee, so the
   obligation is undischargeable and `caller` is **refuted** rather than SAFE. Channel: contract.
   Cite `LLMLL.md §5.3.4` call rule, `FixpointEmit.hs:4285`, `:1340-1344`.

2. **Positive witness, Stage 2, the case that forces its existence.**
   `(def mk [] -> bytes[64] (bytes-zero))`. Under Stage 3 without Stage 2: refuted, wrongly. Under
   Stage 2: the constructor axiom supplies `bytesLen(result) = 64` and the goal discharges. Channel:
   contract. Cite `FixpointEmit.hs:3332-3337`.

3. **Gate self-activation widens beyond bytes.** A function carrying both a `bytes[n]` and a
   `map[int,int]` parameter that is off-gate today becomes gated once the elaborated pre mentions
   `bytes-length`, so `mapParams` also becomes non-empty and the map splits into the `$has`/`$val`
   encoding (`FixpointEmit.hs:734-745`). Expected: verdict-preserving, `.fq` non-identical. Channel:
   contract. This delta belongs in the declared delta set before the corpus sweep runs.

4. **Over-breadth, non-`Σ_auto` contract.** A `bytes[n]` parameter on a function whose precondition
   already escapes `Σ_auto`: the conjunction is emittable only if both conjuncts are, so the
   function was already at `erBodyFallback` and stays there, byte-inert. The converse population
   (emittable pre plus newly emittable conjunct) changes. Channel: contract / trust. Cite
   `LLMLL.md:348` (soundness firewall).

5. **Aliased bytes.** `(type Key bytes[32])`. `resolveAllRefinements` chases `TCustom`
   (`FixpointEmit.hs:4232`), so an aliased `bytes[n]` elaborates identically provided the
   elaboration is itself alias-chasing. If it is not, `Key` gets no obligation while `bytes[32]`
   does. Channel: type / contract. Cite `TypeAdmissibility` property A1.

6. **`bytes[0]`.** `(= (bytes-length v) 0)` is satisfiable; every read is refuted by the
   index-in-bounds obligation, unchanged. `lintContractReads`'s `bytesLens` (`TypeCheck.hs:2541`)
   must keep matching the base type rather than the elaborated wrapper, or CONTRACT-READ-LINT goes
   dead. Channel: contract.

7. **Recursive `bytes[n]`-returning function.** Excluded from body-VC emission for its own body
   (`LLMLL.md §5.3.4`), so Stage 3's post conjunct has no VC to prove it while callers still assume
   it. This is the same position as a hand-written `post` on a recursive function, with the tier
   riding the §4.4 meet. FACT-AG-LEN does **not** close the class for recursive functions, and that
   scope boundary belongs in the spec text. Channel: trust.

## Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Stage 1: `(= (bytes-length arg) n)` at a call site | contract, call-pre, PROVE | **QF-LIA + the `bytesLen` UF over `FQArr FQInt FQInt`.** In `Σ_auto` today: `exprToPred` at `FixpointEmit.hs:2797`, `measureConstant` at `:4222`. Well-sorted because the elaboration self-activates `arrGate` (see below), so the argument binds at `byteArraySort`. No widening. Cite `LLMLL.md §5.3.3`. |
| Stage 2: `bytesLen(result) = n` at `(bytes-zero)` | contract, established by a sealed builtin | QF-LIA + same UF. Not an obligation on user code; an axiom whose no-laundering side condition is `TypeCheck.hs:1216,1250`. |
| Stage 3: `(= (bytes-length result) n)` in the effective post | contract, post, PROVE in the body VC | QF-LIA + same UF. Structurally the §3.4.1 introduction obligation for a refinement-aliased return, `LLMLL.md:1038`. Emitted by `augmentContractPost`, `FixpointEmit.hs:4311`. |
| Map arm: `∀k. 0 ≤ select(m$val,k) ≤ 1` (**not proposed**) | contract | Decidable (array property fragment, Bradley-Manna-Sipma VMCAI 2006) but inexpressible: `FQPred` has no quantifier former and the Horn interface is quantifier-free. Moot regardless, since the establish-half is discharged. |
| A1-congruence of the elaboration under alias resolution | metatheory, not the three-channel report | Property test, as with ADMIT-SHARED's A1/A2. Not an obligation in the obligation report. |
| Verdict-preservation with a declared delta set | trust | Empirical acceptance gate. Byte-identity is unavailable (edge cases 3 and 4). |

Nothing in this proposal escapes to Lean, and no `?proof-required` hole is introduced.

## The sort/gate hazard, and why no fix is needed

The professor review flagged a real hazard Rev 0 missed: `augmentContractPre` runs unconditionally
(`FixpointEmit.hs:692`) while the array sort is `arrGate`-conditional (`:734-752`), and `typeToSort`
has no `TBytes` clause so an off-gate bytes parameter falls to the conservative `FQInt` default
(`:2379-2390`), whereas `bytesLen` is declared over `[FQArr FQInt FQInt]` (`:4222`). Emitting
`bytesLen(b)` against `b : FQInt` would be ill-sorted.

The review proposed widening `typeToSort (TBytes n)` to `byteArraySort`. **Rejected on measured
grounds.** `typeToSort` is also the sort function at `Result` `$ok`/`$err` component positions
(`:953-954`), ADT payload keys (`:968`), and payload-subtyping (`:1450`); widening it would
array-sort a `Result bytes[32] E`'s `$ok` component with no `bytesLen` machinery, no `arrGate`, and
no binder fact in scope. That trades an ill-sorted off-gate population for an ill-sorted component
population.

The other available horn, gating the elaboration on `arrGateActive`, is the one that would forfeit
ADMIT-SHARED's declared-type-only side condition and make `check` and `verify` disagree about a
program's contract.

**Neither horn is real.** Measured at HEAD:

- `contractAug` is formed at `FixpointEmit.hs:692` from `contract0`, and `contract` is rebound from
  it at `:715-716` (the desugaring pass), so `contract` is the **augmented** contract, not
  `contract0`.
- `arrGate = arrGateActive cenv contract mBody` at `:732` reads that `contract`.
- `arrGateActive`'s first disjunct is `contractMentionsArrOp contract` (`:1639-1642`), and the
  mention set is `bytesOpNames ++ mapOpNames` where `bytesOpNames` contains `"bytes-length"`
  (`:1541-1542`, `:1587`); `exprMentionsOpIn` matches `EApp f args` with `f elem ops` anywhere in a
  contract predicate.

So inserting `(= (bytes-length v) n)` into the effective precondition **self-activates the gate for
exactly the functions carrying a `bytes[n]` parameter or return**. The off-gate bytes population,
which is the population that would be ill-sorted, ceases to exist the moment the elaboration lands.
No `typeToSort` change, no `arrGateActive` change, no ordering change.

The composition is one-directional and needs no fixpoint: the augmentation is a pure function of
declared types, so ADMIT-SHARED's declared-type-only side condition survives intact; the gate is a
function of the augmented contract and the body, as it already is; and the augmentation does not
read the gate. The observable consequence is edge case 3, and it is a `.fq` delta, not a soundness
question.

## Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: elaboration ahead of `paramRefinementPre` /
  `returnRefinementPost` (`:4229`, `:4280`, `:4311`); Stage 2 at `bodyToPredM`'s `bytes-zero` case
  (`:3336`); Stage 3 moves `resultLenFact` (`:1216-1217`, `:1270`). **No change** to `typeToSort`,
  `arrGateActive`, or the gate's read order.

  Two corrections from Stage 1 implementation, both of which this section got wrong:

  1. **Do not delete `bytesLenReft` from `emitParamBind` (`:1470-1472`).** That clause supplies the
     `byteArraySort` *as well as* the fact, and deleting it falls through to `typeToSort`'s
     conservative `FQInt` default, which emits ill-sorted `bytesLen` applications. The correct
     change keeps the sort and drops only the predicate.
  2. **Do not fold the elaboration into `resolveAllRefinements`.** It has four other consumers that
     must not see it: `returnRefinementPost` (**that is Stage 3**, so folding lands Stage 3
     prematurely and violates the stage ordering this proposal calls a correctness constraint),
     `payloadRefinement` (component positions, the deliberate exclusion above), `LLMLL.Feasibility`
     (a separate SMT lowering for the no-miracle gate), and `collectCallArgCarrierVars`
     (measure-carrier binding). The elaboration belongs in its own function conjoined at
     `paramRefinementPre`.
- `compiler/src/LLMLL/TypeAdmissibility.hs`: `admits` loses `bytesLenOf` at Stage 3. Header
  corrections: the terminal state is `boolValuedMapTy`, not empty; the criterion is Hoare's
  two-sided one; ADMIT-OVER's asymmetry inverts once the bytes arm is gone, since too narrow then
  costs a worse diagnostic rather than a false SAFE.
- `compiler/src/LLMLL/TypeCheck.hs`: both WILD-ASSUME seams (`:2292`, `:2372`) demote from
  soundness to diagnostic and are **kept, not deleted**; `wildAssumeFactNoun` (`:428-432`) rewords
  its bytes arm; `lintContractReads`'s `bytesLens` (`:2541`) keeps matching the base type.
- `compiler/src/LLMLL/TrustReport.hs:586`, `:684`: `canonicalDefEvidenceHash` folds
  `augmentContractPost`, so Stage 3 changes the evidence hash of every `bytes[n]`-returning function
  and needs the SAFE-ARG revalidation ceremony (`checker_soundness_version`).
- `LLMLL.md`: §3.4.1 (the elaboration joins the introduction-obligation family), §5.3.3 (state that
  `Σ_auto` is unchanged), §5.3.4 (the call rule discharges type-derived length; recursion carve-out
  per edge case 7), §5.3.5 matrix (a `bytes[n]` parameter/return row), §13 (`bytes-zero`'s length
  axiom).
- `docs/compiler-team-roadmap.md`: FACT-AG becomes `FACT-AG-LEN`, staged; closed disposition note
  for the range arm; ADMIT-SHARED's "provisional against FACT-AG" narrows to the bytes arm.
- `docs/design/type-driven-development.md`: cited as the rationale anchor. No edit.
- `docs/design/finding-arg-position-false-safe.md`: its "FACT-AG, re-rated" bullet is superseded by
  this proposal. No edit; the pointer is one-directional.
- Schema: **no delta**. Feature freeze: not applicable, lifted at v0.11
  (`docs/compiler-team-roadmap.md:240`), and no construct is introduced regardless.

## Acceptance gate

**Byte-identity is not available.** Unlike RET-RESOLVE, whose gate is a byte-identical `.fq` across
128 files (`docs/compiler-team-roadmap.md:50`), FACT-AG-LEN changes the `.fq` by construction. The
gate is **verdict-preservation over the corpus with a declared delta set**, and two deltas are known
in advance:

1. Functions whose precondition was already emittable gain a conjunct.
2. Functions carrying both a `bytes[n]` and a `map[int,int]` parameter that were off-gate become
   gated, so their maps split into the `$has`/`$val` encoding (edge case 3).
3. **Direct callers of a bytes-typed function**, one hop, which have no bytes type of their own.
   `emitFixpointWithCache`'s `aug` (`FixpointEmit.hs:259`) applies the same augmentation to the
   contracts stored in the `ContractEnv`, and that env is consumed by callers via assume-guarantee
   (the comment at `:250-255` says so). `arrGateActive`'s third disjunct is `calleeCarries`
   (`:1643-1645`), which tests `contractMentionsArrOp` against each callee's stored contract, so a
   caller of a bytes-typed callee gates on the elaborated `bytes-length` it now finds there. One hop
   only, not transitive: the caller's own contract gains no `bytes-length` unless it has a bytes
   type itself. Ergonomic, not soundness.

Declare all three before the sweep. A silent delta reads as a regression.

**What the Stage 1 sweep actually establishes.** Measured in-tree before the sweep ran: D1 is 8
`.llmll` functions across 8 files plus 11 JSON-AST functions across 7 files; D2 (off-gate becoming
gated) is 1 `.llmll` plus 7 JSON-AST. **D3 and D4 are both zero.** The corpus contains no function
carrying a `bytes[n]` and a `map[int,int]` parameter together, and no non-bytes direct caller of a
bytes-typed function. So the 251-file, zero-verdict-delta result validates D1 and D2 and says
**nothing** about delta 2 or delta 3 above: those populations have no in-tree witness and are
**unmeasurable by this sweep, not passing it**. Whoever lands Stage 2 or Stage 3 should not read the
Stage 1 green as covering them, and the cheapest repair is a purpose-built fixture for each rather
than waiting for the corpus to grow one.

## Risks

1. **Stage ordering is a correctness constraint, not a preference.** Soundness / scope.
   `FixpointEmit.hs:3332-3337`. Landing Stage 3 before Stage 2 refutes every bytes-constructing
   function. Bite: **blocks** if violated; free if respected.
2. **Gate self-activation deltas beyond the bytes population.** Verification-ergonomics.
   `FixpointEmit.hs:734-745` for co-resident maps, and `:259` with `:1643-1645` for direct callers
   of a bytes-typed function, which gate through the augmented `ContractEnv` without carrying a
   bytes type themselves. Two distinct populations, both one-hop-bounded. Bite: **complicates**;
   both belong in the declared delta set, and the caller population is the one most likely to be
   missed because nothing in those functions' own signatures mentions bytes.
3. **Evidence-hash invalidation at Stage 3.** Release ops. `TrustReport.hs:586`. Bite:
   **complicates**; the SAFE-ARG revalidation ceremony applies.
4. **No byte-identity gate.** Acceptance. Bite: **complicates**; weaker evidence than RET-RESOLVE's.
5. **Diagnostic regression at the argument seam.** Verification-ergonomics. `TypeCheck.hs:2292`.
   Today a laundered length is a localized type error naming the remedy; after Stage 1 it is a
   refuted obligation, or an `erBodyFallback` with no localization when `bytes-length` over an
   unannotated call result is non-emittable. Mitigated by keeping both WILD-ASSUME seams as
   diagnostics. Bite: **complicates**.
6. **Recursive functions stay on the assumption channel.** Soundness scope. `LLMLL.md §5.3.4`. Bite:
   **only matters at scale**; must be written into the spec rather than left implicit.
7. **`resultLenFact`'s current soundness is shielded, not discharged.** Soundness.
   `FixpointEmit.hs:1216-1217`, `:1270`. Given `compatibleWith _ (TBytes m) (TBytes n) = m == n`
   (`TypeCheck.hs:2387`), a concrete length mismatch is a type error, so the current assertion rests
   on an earlier pass rather than on a discharged obligation. That is the shielding-by-another-pass
   argument that produced CR-01.

   **Measured at Stage 1: ten shapes attempted, no witness constructed.** That is a measured
   absence, not a proof. One result refines the risk rather than closing it: an `(if f c b)` whose
   arms have different declared lengths passes `llmll check` with only a **warning**, which refutes
   the strong form of the claim above; `llmll verify` promotes it to a hard error, so nothing
   reaches the emitter. **The shield is `verify`, not the type checker.** That is a weaker shield
   than this section originally asserted, because it means `check` and `verify` disagree about the
   program, and it is the same shape of cross-pass dependency the finding warns about. Bite: **only
   matters at scale**, and Stage 3 retires the shield entirely by making the return length a proved
   goal.

## Open questions for the professor

1. Stage 2 makes `bytes-zero`'s length an axiom about a sealed builtin, justified by
   `TypeCheck.hs:1216,1250` restricting the form to a def body with a literal `-> bytes[n]` return.
   Is a syntactic restriction on where an introduction form may appear an accepted way to discharge
   Hoare's establish-half, or does the discipline require the constructor to be index-respecting in
   its own signature (the Idris `Nil : Vect 0 a` shape) for the axiom to be more than a relocated
   assumption?

2. The criterion turns on whether a type's sealed introduction forms establish its invariant, which
   is checkable per arm today because LLMLL has few sealed constructors. Is there a standard name
   for this property, and does the literature record a failure mode where a constructor-established
   invariant is nonetheless unsound under composition, i.e. an operation that preserves the abstract
   invariant but not the concrete representation?

Neither question blocks Stage 1. Both bear only on Stage 2's justification text.

## Review history

Rev 0 (conversational, 2026-08-01) proposed a two-half move: parameter position via
`augmentContractPre`, return position via `augmentContractPost`, with the map arm excluded on a
fragment-membership argument.

Professor review, same day, returned seven findings. Six were adopted:

| Finding | Disposition in Rev 1 |
|---|---|
| `bytes-zero` cannot discharge the return obligation | Adopted, blocking. Stage 2 interposed; ordering made a stated correctness constraint. |
| Elaboration unconditional, sort `arrGate`-conditional | Hazard adopted. **Resolution rejected**; see [The sort/gate hazard](#the-sortgate-hazard-and-why-no-fix-is-needed). |
| Array property fragment decides the map formula | Adopted. Rev 0's decidability claim withdrawn. |
| `bytes[n]` is an index without the index discipline | Adopted. Rationale re-anchored to `type-driven-development.md`. |
| Representation invariant needs its establish-half | Adopted. Criterion completed; it now supplies both the Stage 2 justification and the map-arm exclusion. |
| Component positions unaddressed | Adopted. Now a stated exclusion with its emitter-agreement argument. |
| Two Rev 0 assertions verified (`mPre` reaches call-pre LHS; codegen reads the raw `contractPre`) | Recorded as checked. |

Professor review round 1 (`docs/design/fact-ag-proposal-review.md`) adjudicated Rev 1. It
**conceded** the sort/gate rejection after re-measuring at HEAD, and confirmed that the proposed
`typeToSort` widening would have array-sorted Result and ADT components. It returned three findings:

| Finding | Disposition in Rev 2 |
|---|---|
| **R1-1.** Rev 1 cited `FixpointEmit.hs:694-696` for the `contract` binding three times; `:694` is `dsExpr` and the binding is at `:715-716`. The whole sort/gate rejection rested on that citation. | Adopted. Verified independently: `contractAug` is formed at `:692`, `contract` is rebound at `:715-716`. Citations corrected. The substance was unaffected, but a wrong line number under an argument this load-carrying is a defect in its own right. |
| **R1-2.** `emitFixpointWithCache`'s `aug` (`:259`) augments the **stored** `ContractEnv` contracts, so `arrGateActive`'s `calleeCarries` disjunct gates every direct caller of a bytes-typed function. Rev 1's delta set omitted that population. | Adopted. Verified: the `:250-255` comment states the env is consumed by callers via assume-guarantee. Added as delta 3 in [Acceptance gate](#acceptance-gate), with the one-hop bound stated. |
| **R1-3.** The criterion contradicts Stage 3: once Stage 2 lands, `bytes-zero` plus `bytes-set` establish the length by construction, so clause (i) alone predicts Stage 3 is unnecessary. | Adopted as a real contradiction. **Repaired differently from the review's recommendation.** The review proposed striking the establish-half reason from the map-arm exclusion and resting it solely on `FQPred` having no quantifier former. Rev 2 instead adds clause (ii), modularity: an established fact that is *parametric in a type index* must still be exported across a call boundary, while one that is *uniform over the type constructor's inhabitants* need not. That keeps both arms decided by one criterion, preserves the map arm's closure on substantive rather than expressiveness grounds, and lines the axis up with the `Vect n a` framing the proposal already uses. |

Rev 2 diverges from the review only on R1-3's repair, and the divergence is about which criterion
survives, not about whether the contradiction is real.
