---
title: "Professor review: SPEC-AGREE-1 §8, the evidential weight of an unrendered defeater"
status: "Standalone review. Not folded into the proposal; language-team folds on revision."
author: professor
date: 2026-07-31
reviews: "docs/design/spec-agreement-proposal.md §8 (Rev 1)"
also_consulted: "docs/design/spec-agree-1-feasibility-read.md (compiler-engineer, 2026-07-31)"
---

# SPEC-AGREE-1 §8: does an unrendered defeater carry evidential weight on its own?

## Restatement

§8 asks whether a solver verdict establishing that two candidate formalizations of an RFC clause
are non-equivalent, without producing the distinguishing input, is worth anything on its own, and
therefore whether widening `Sigma_witness` beyond Int and Bool is a prerequisite of §6.1's
constructor-capable comparison or an enhancement to it.

The short answer is that the question as posed is premature, its two framings are answering
different questions, and the design's own §3 has already decided it in a way §8 does not notice.

## Context located

1. `docs/design/spec-agreement-proposal.md` §3 reporting rule (`:181-187`) — the headline metric is
   rows **where witness adjudication changed the frozen contract**. Decisive; see hazard 2.
2. `docs/design/spec-agreement-proposal.md` §4 (`:195-200`) — the eliminative claim, F-8 adopted
   without qualification.
3. `docs/design/spec-agreement-review.md` F-13 (`:259-277`) — the exhibit is the mechanism credited
   for the design's advantage over open-ended audit, grounded in Jackson's instance-level
   validation, and F-13's own bound already says the witness is "absent on C1 transition rows,
   where audit is hardest and where the pipeline's documented failure lives (`step-weak`)".
4. `compiler/src/LLMLL/DiagnosticFQ.hs:58-62` — **`FQVerifyResult = FQSafe | FQUnsafe
   [FQConstraintId] | FQError Text`.** No model, for any sort. This is hazard 1 and it is the
   finding that makes §8 premature.
5. `compiler/src/LLMLL/RefineReuse.hs:205-226` — `solveSubsumptionFQ` and `contractSubsumes`; the
   latter collapses the result to `Bool`.
6. `compiler/src/LLMLL/Feasibility.hs:150-169, 199-208, 292-304` — `buildQuery` and `feasibilityOf`.
   The query shape is `∃ params. ∀ result. ¬(Rret ∧ post)` over a **single** contract. Not a
   two-contract difference query.
7. `docs/design/spec-agree-1-feasibility-read.md` — the tier split and the `qsat` completeness
   observation, both of which sharpen the recommendation below.

## Gaps and hazards

**1. The question is not yet live: no difference-witness machinery exists on either path.**
Classification: scope, bordering spec-drift in §6.2. Evidence: `DiagnosticFQ.hs:58-62`. The
subsumption path routes through liquid-fixpoint, whose result type carries constraint identifiers
and nothing else. `contractSubsumes` (`RefineReuse.hs:220-226`) further collapses that to a boolean.
**The subsumption query produces no witness for Int contracts either.** §6.2 attributes the
rendering gap to `baseSortText`'s Int/Bool restriction, which locates it in `Feasibility.hs`; but
`Feasibility.hs` answers a different question (is one contract vacuously unsatisfiable) with a
different query shape (`:150-169`), and `witnessOf` (`:283-284`) renders that query's inputs, not a
distinguishing input between two contracts. A two-contract difference query is a third artifact
neither path builds. Bite: **blocks §8 from being answerable as posed**. Widening `baseSortText`
is neither prerequisite nor enhancement to §6.1 until the difference query exists, because §6.1's
current output cannot render a witness at any sort.

**2. §3's adopted reporting rule already makes the witness a precondition of the headline number.**
Classification: internal consistency of the instrument's claim. Evidence: `:181-187`, "the count and
per-row list of `Encoded` rows where **witness adjudication changed the frozen contract**". An
unrendered defeater cannot change the frozen contract, because adjudication is the step that decides
which reading the source text supports, and that step consumes the distinguishing input. So an
unrendered defeater contributes exactly zero to the numerator the design committed to in §3 and
increments only the denominator. §8 asks whether the value "collapses to the bare count of
disagreeing rows"; §3 has already ruled that the bare count is not the headline. The two sections
are inconsistent, and §3 is the one adopted "without qualification". Bite: **forecloses the
"enhancement" answer** on the design's own terms, for any row class where the witness is
unavailable.

**3. The two framings equivocate between a classical and a constructive existential.**
Classification: soundness of the argument, not of the system. F-8's eliminative claim is that `sat`
falsifies the conjunction "both readings are faithful". That is valid, and it is valid classically:
a decision procedure asserting `∃x. φ_A(x) ≢ φ_B(x)` licenses the falsification without exhibiting
`x`. F-13's claim is that the design's advantage over open-ended audit is forced-choice
discrimination at a concrete instance, which consumes the **constructive content** of the same
existential. These are the two standard readings of `∃`, and the design needs both from one verdict
while §8 argues as though establishing the classical one settles the matter. The relevant precedent
is CEGAR (Clarke, Grumberg, Jha, Lu and Veith, CAV 2000): a bare "the abstraction is too coarse" bit
is sound and useless, because the counterexample trace is what drives the refinement step. Bite:
complicates rather than blocks; it identifies what the answer must distinguish.

**4. F-13's bound inverts under §6.1, which is the substantive point §8 gestures at.**
Classification: scope. F-13 already recorded that the witness is sharpest on C2 arithmetic rows,
where side-by-side audit is easiest, and absent on C1 transition rows, where audit is hardest and
where `step-weak` lives. §6.1 unlocks C1 comparison. So the rows the widening would newly compare
are precisely the rows whose witnesses would be unrenderable, and precisely the rows the exercise
exists to reach. The unrendered-defeater case is not a residual corner; on the measured corpus it is
39 of the 61 citable rows (§0.4 M-2 records ARP as 31 C1 of 39 `Encoded`). Bite: this is what makes
the answer "prerequisite" rather than "enhancement" for the payload-sum tier.

**5. The `qsat` completeness envelope is a second, independent reason not to reach for native
datatype sorts.** Classification: decidability. The engineer's read (`spec-agree-1-feasibility-read.md`
risk 2) cites `Feasibility.hs:206-207`, which pins the tactic choice to LIA and to a specific z3
build. A datatype sort under the `forall (result …)` binder at `:204` leaves that envelope. Bite:
complicates; and it is dissolved entirely by the recommendation below.

## Recommendation

**Answer to §8, stated for the record: an unrendered defeater carries eliminative weight but no
adjudicative weight, and the instrument as specified in §3 counts only adjudicative weight.** It is
therefore a triage signal, not a finding. It tells the auditor which rows to spend budget on and
then hands back exactly the open-ended recall task F-13 identifies as the unreliable one, now merely
flagged. That is a real improvement over nothing and a much weaker claim than §6.1's framing
assumes. Do not report unrendered defeats in the same column as adjudicated ones.

**Do not answer "prerequisite or enhancement" as posed. Dissolve it by finite case-splitting.**

For a payload-free sum of `k` constructors, do not quantify over a datatype sort at all. Instantiate:
run `k` queries with the constructor fixed, each of which stays in QF-LIA. The query that returns
`sat` names the constructor, so the witness is rendered by construction, and nothing leaves the
`qsat` envelope hazard 5 describes. For a sum whose payloads are Int or Bool, the same split leaves
the payload existentially quantified inside LIA. This is the standard finite-domain instantiation
move and it is what Alloy does within a bound (Jackson, *Software Abstractions*, 2nd ed., §5.1: the
small scope hypothesis is exactly the claim that finite instantiation retains the discriminating
instances). Illustrative shape only, for the language-team to formalize: for each `c ∈ ctors(T)`,
emit the query with `param ≡ c` conjoined, collect the `sat` arm.

Cost is `Π kᵢ` over constructor-typed parameters. On the measured corpus that is small: ARP's
`HwType × Len` is 4; the widest payload sums are 3 and 4 constructors over 1 to 3 params, so the
worst case is tens of trivial queries. This is cheaper than the alternative it replaces, since the
alternative requires new SMT-LIB datatype rendering in `Feasibility.hs` plus a completeness argument
for `qsat` outside LIA that nobody currently has.

**Consequently, the ordering is:**

1. Build the two-contract difference query. It does not exist (hazard 1) and everything in §8 and
   §6.2 presupposes it. It must be a `(get-model)`-bearing z3 query in the `Feasibility.hs` style,
   not a liquid-fixpoint solve, because `FQVerifyResult` structurally cannot carry a model. This is
   a **new** item; §6.3's build order does not contain it.
2. §6.1 tier 1 (nullary enums). Witness renders via the reverse tag map the engineer's read
   describes. §8's question does not arise for this tier.
3. §6.1 tier 2 (payload sums) **with case-splitting**, which renders the witness rather than
   widening `baseSortText` to native datatype sorts.

Under this ordering, `baseSortText` widening to *native datatype sorts* is neither prerequisite nor
enhancement. It is **unnecessary**, and it should be dropped from §6.3(a)'s scope rather than
sequenced. What §6.2 correctly identified is that C1 rows need renderable witnesses; what it
misidentified is the mechanism.

**One correction to the proposal's self-description.** §4's "Does not claim" is careful and correct.
§6.2's sentence "the eliminative claim survives this: … What is lost is the adjudication affordance,
not the soundness of the defeat" is also correct in isolation, but it is doing rhetorical work it
cannot support once §3 is read alongside it: the adjudication affordance is not a nice-to-have on
top of the defeat, it is the thing §3 counts. The language-team should reconcile §6.2 with §3
explicitly rather than leaving the two in different registers.

## Open questions for the language-team

1. **Does the case-splitting recommendation change the `not-comparable` disposition for C1 rows?**
   EC-4 and §0's row accounting treat comparability as a per-contract property decided by
   `qfContract`. Case-splitting makes comparability depend on the *arity of the constructor product*
   rather than on the fragment, which is a different partition of the same set and a second instance
   of M-2's finding. Specify whether a row whose split exceeds a budget is recorded `not-comparable`
   or a new disposition.

2. **Reconcile §6.2 with §3, and state which column an unrendered defeat is reported in.** If the
   answer is that it is reported separately from adjudicated changes, say so in §3's reporting rule
   where the stratification already lives, so that a reader cannot read the headline as including
   it.
