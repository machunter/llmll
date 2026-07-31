---
name: spec-agreement-proposal
title: "SPEC-AGREE-1: independent formalization with mechanical agreement"
status: "Rev 1 - professor review folded; scope settled by measurement; Sigma_witness gap routed to compiler-engineer"
date: 2026-07-31
author: language-team
consumers: [professor, user, language-team, compiler-engineer, experiment-lead]
---

# SPEC-AGREE-1: independent formalization with mechanical agreement

## Restatement

Today the "what" of an RFC-derived specification is produced once and audited by a human. The
proposal: have **N agents independently formalize the same clause**, then **mechanically check
whether their formalizations agree**, and treat disagreement as a finding with a machine-generated
witness rather than as noise to be voted away.

The reason this is worth building is narrow and specific. The pipeline's own claim discipline
says `:source` is a traceability pointer and not a proof of fidelity, and that fidelity rests on
human audit ([`spec-from-rfc-pipeline.md`](spec-from-rfc-pipeline.md) §2). That is the last
unmechanized link in the chain from RFC text to verified artifact. Independent formalization plus
an agreement check is a mechanical signal exactly there.

## Rev 1 changes

Rev 0's §1 applicability claim and §6 effort table are withdrawn. The professor review
([`spec-agreement-review.md`](spec-agreement-review.md)) raised both as BLOCKERs (F-1, F-2) and
its F-1 disposition named a measurement to settle the scope question. That measurement is now
taken and reported in §0. Its result settles both open questions the review addressed to the
language-team, and it settles them against both shapes the review offered.

Adopted without qualification: F-2 (effective-contract comparison), F-3 (three-valued verdicts),
F-4 (product position, Zaremski-Wing naming), F-5 (new two-contract difference builder, `result`
in the witness vector), F-6 (three mechanical discriminators for the strictly-ordered case),
F-7 (T4 and levers 1 and 2 in the design), F-8 (stratified reporting, never a bare rate),
F-9 (T3 restated and measured by de-naming), F-10 (`Not-comparable` first-class, never routed
back to the inventory), F-11 (separate artifact, outside trust vocabulary), F-12 (three edge
cases). F-13's framing is adopted as the claim ceiling.

New in Rev 1 and not in the review: the **Sigma_witness limit** (§6.2), a spec/artifact drift
finding (§0.1), and two edge cases (EC-4, EC-6) surfaced by taking the measurement.

## 0. The measured comparable fraction

### 0.1 Drift finding, stated first because it moved the measurement

The review's Context located records that `examples/tftp_rfc1350/` holds only
`VERIFICATION_SCOPE.md`, and concludes that stage K has not run, so F-1's measurement can be taken
over stage-H probe contracts before authoring. At HEAD that directory holds `roots/` (frozen
contracts, `FREEZE.md`, `ROOTS.txt`) and `wave/` (filled AST, expected verdicts, mutants). Stage K
has run. Two further runs exist that the review did not see:
`experiments/rfc-swarm/runs/rfc826/` (ARP) and `runs/rfc4648/`. The measurement below is therefore
taken over **authored contracts** rather than probes, which is a stronger sample for the scope
question and a weaker one for the pre-authoring timing F-1 assumed.

### 0.2 Method

`qfContract` (`compiler/src/LLMLL/RefineReuse.hs:281-285`) transcribed and applied to every
contract-bearing `def` in the committed artifacts of the two runs that passed gate J. The gate is

```
qfContract c = classifyContractFragment c == "qf_lia"
               && not (contractMentionsArrOp c)
               && not (clauseUF (contractPre c))
               && not (clauseUF (contractPost c))
```

with `ufBearing` at `RefineReuse.hs:289-299` and the array-op families at
`FixpointEmit.hs:1577,1581`. `classifyContractFragment` was approximated as "at least one clause
present", which is generous, so every figure below is an **upper bound** on comparability. A row
is counted comparable only when every clause citing it lives in a comparable contract (EC-4).

The measurement is reproducible. `experiments/spec-agree-1/` holds the transcription, the pinned
inputs, and the figures below; `python3 experiments/spec-agree-1/scripts/sigma_subsume.py` exits
non-zero if the corpus or the gate moves away from what this section publishes.

### 0.3 Result

| Unit | TFTP (RFC 1350) | ARP (RFC 826) | Combined |
|---|---|---|---|
| Contract-bearing defs | 12 | 9 | 21 |
| Comparable defs | 2 | 1 | 3 (14.3%) |
| `Encoded` rows | 46 | 39 | 85 |
| `Encoded` rows cited by a clause | 35 | 26 | 61 |
| **Comparable rows** | **7 (15.2%)** | **2 (5.1%)** | **9 (10.6%)** |

Abstention histogram over all 18 non-comparable contract-bearing defs: **13 nullary constructor
terms, 5 constructor applications, 0 array ops, 0 measures.**

### 0.4 Three findings, each of which moves a decision

**M-1. The fraction is below the review's estimate and below the threshold its own question
names.** F-1 put the comparable set at "roughly a fifth to a quarter" of `Encoded`. Measured on
TFTP it is 15.2%, and 10.6% across both runs. The review's Q1 asks what follows "if the comparable
fraction on TFTP is near 10/46"; the measured figure is 7/46. F-1's disposition states that under
half makes this an arithmetic study. 10.6% is far under half.

**M-2. The clause taxonomy is not a proxy for the solver fragment, so a class-scoped instrument
cannot be built as the review describes it.** The comparable rows are TFTP `{C2 5, C3 1, C1 1}`
and ARP `{C3 2}`. Of TFTP's ten `Encoded` C2 rows, five are comparable and five are not. ARP has
**zero** `Encoded` C2 rows, so a C2-scoped instrument runs on nothing at all on that run while two
comparable C3 rows sit undecided. Class and fragment partition the same set independently.

**M-3. The entire gap is constructor terms, and Lever A is not on the critical path.** All 18
abstentions fire on `ufBearing`'s uppercase-head clauses. None fires on `contractMentionsArrOp`,
and none on a measure. The review's Q2 frames the datatype-capable backend as carrying "its own
Lever A dependency"; on this evidence it carries none. What separates 10.6% from near-full
`Encoded` coverage is declaring constructors and their sorts in the subsumption query, which is
what the `FixpointEmit` path already does for the verification channel.

## 1. Scope: the instrument's domain is Sigma_subsume, computed per contract

Rev 0 §1 argued that a row is `Encoded` precisely when its contract discharges in the decidable
fragment, that the decidable fragment is where subsumption is decidable, and therefore that
SPEC-AGREE-1 applies to every `Encoded` row. F-1 refutes the middle step against the code and §0
quantifies the gap. Three strictly nested fragments exist, not one:

- **Sigma_auto** (verification): QF-LIA, acyclic datatypes, enums, closed measures, bool, plus
  Lever A arrays and maps. `LLMLL.md` §5.3.3.
- **Sigma_subsume** (`RefineReuse.hs:281-299`): QF-LIA scalars only. Any constructor, measure,
  pair, `Result` term or array op abstains, because the bare two-constraint `.fq` declares no UF
  constants.
- **Sigma_witness** (`Feasibility.hs:187-191`): Int and Bool base sorts only, for parameters and
  the declared return type. See §6.2, which is new in Rev 1.

**The scoping rule.** SPEC-AGREE-1 runs over the full `Encoded` denominator and emits per row one
of `{equivalent, ordered, incomparable, not-comparable}`. `not-comparable` is decided by
`qfContract` on that row's contracts and the row **remains in the denominator**. This promotes
F-10's disposition from an edge case to the scoping rule: the ledger records what the verifier
carries, and the instrument reports its own reach rather than trimming the ledger to match it.

It is therefore **not** a pipeline stage amending stage K for all rows, because at 10.6% it cannot
discharge stage K's obligation, and **not** class-scoped, by M-2. The comparable fraction is a
first-class published output, subject to §3's caution about readers dividing by it.

## 2. Which layers of the "what" are worth agreeing on

Unchanged from Rev 0 and not disturbed by the measurement.

| Layer | Agreement meaningful? | Why |
|---|---|---|
| **Clause census** (which sentences are normative) | **Yes, already adopted** | The failure mode (overlooking a clause) is roughly independent across agents. Measured on TFTP: Jaccard 0.866, Cohen's kappa 0.938, read per §3 as a reliability statistic only. |
| **Disposition** (Encoded vs excluded) | **No** | Follows from the fragment's documented limits, which every agent reads from the same source. |
| **Architecture and signatures** | **Not mechanically** | Structural comparison of module decompositions has no decidable equivalence check. |
| **Contracts, given fixed signatures** | **Yes, within Sigma_subsume** | Equivalence is a solver query on 10.6% of rows today (§0), on more after §6.1. |
| **Bodies, given a contract** | **Already covered** | R5 `checkout --multi` + `diverge-report`. |

Per F-13, the R5 duality is sharper than "two halves of the same question": `diverge-report`
classifies observational divergence among verifying fills, an extensional relation on behaviors;
subsumption is an intensional relation on predicates whose refinement-calculus meaning is
inclusion of implementation model classes.

## 3. The procedure

**Precondition: signatures are frozen first**, with the freeze rules extended by EC-6.

1. **Gate first, author second.** For each `Encoded` row, evaluate `qfContract` on the frozen
   signature and the authored contract shape. Rows that abstain are recorded `not-comparable` and
   are **not** sent for N-way authoring, which is what keeps the experiment's cost proportional to
   its yield.
2. **Blind N-way formalization** on the comparable set. N agents independently author the contract
   clause. Per F-7 lever 2, the inventory obligation gloss is **withheld from at least one arm**
   and agreement is reported with and without it.
3. **Pairwise comparison**, three-valued per direction (F-3), yielding a **product position**
   `(pre-position, post-position)` each in `{≡, ⊐, ⊏, ⋈}` (F-4). Adopt Zaremski-Wing names where
   they apply. Comparison is over the **effective** contract, `pre ∧ param refinements` and
   `post ∧ return refinement` (F-2), matching `Feasibility.hs:155-162`.
4. **Disposition of the strictly-ordered case** by F-6's three discriminators, in decreasing
   definitiveness: feasibility of the stronger contract (`Feasibility.hs:292-304`); good-twin
   refutation (stage N); mutant kill differential. Precondition strengthening is a defect
   candidate by default, not "informative rather than fatal".
5. **Witness generation on non-equivalence**, subject to §6.2. The query is
   `∃p̄. pre_A ∧ ¬pre_B` and `∃p̄,result. post_A ∧ ¬post_B`, quantifier-free over free constants,
   with `result` in the witness vector.
6. **Adjudication against the source text, never by vote.** Majority voting is rejected: it hides
   the disagreement and can certify a shared error. Brilliant, Knight and Leveson's consistent
   comparison problem gives the second ground, that all-correct versions can disagree at a voter.
7. **Outputs.** Per §3's reporting rule below.

**Reporting rule (F-8, adopted without qualification).** Never an unstratified agreement rate.
The headline is **the count and per-row list of `Encoded` rows where witness adjudication changed
the frozen contract**, as a fraction of rows that reached comparison, published beside the
`not-comparable` count and the comparable fraction from §0. That is detection yield rather than
concordance, and weak contracts cannot inflate it. Agreement figures, where reported at all, are
stratified by discriminative power: rows whose contracts kill at least one pre-registered mutant,
complement reported separately.

## 4. What this does and does not claim

**Claims.** That N independent formalizations of a clause were produced blind and their logical
relationship was decided mechanically on the comparable fragment; that every non-equivalence was
adjudicated against the verbatim source with a recorded witness where one could be rendered.

**Does not claim.** That an agreed contract is correct. Per F-8, agreement is evidence about
fidelity only in the eliminative direction, as a defeater generator: a witness showing two
candidate readings differ observably falsifies the conjunction "both are faithful", while
agreement yields no corresponding entailment. The defensible wording is about the clause, not the
contract: *N formalizations produced under framing F were pairwise equivalent, so no ambiguity in
this clause was detectable at framing F*.

Four threats bound it.

- **T1, correlated error.** Knight and Leveson (IEEE TSE SE-12(1), 1986). Limiting, not fatal;
  Eckhardt and Lee and Littlewood and Miller give the difficulty-function model under which forced
  methodological diversity can drive covariance negative.
- **T2, agreement on a vacuous contract.** Weak contracts are the agreement attractor, so vacuity
  is a **confound of the statistic itself**, not merely an independent downstream filter. Handled
  by §3's stratification, not by `--cdp` alone.
- **T3, framing by the frozen signatures.** Restated per F-9: the rate is conditional on an
  architecture that itself encodes interpretive decisions, and for C1 rows the frozen outcome sum
  may already contain the answer. **Measured, not only disclosed**: on a sample, run one arm
  against the frozen signature and a second against the same signature with constructor and field
  names mechanically replaced by opaque `A0..An`, sorts preserved.
- **T4, the obligation-gloss priming channel.** New in Rev 1 per F-7. The inventory row carries a
  one-sentence obligation authored at stage D, which is a prior formalization of the same clause
  in prose fed identically to all N arms. It sits at the same layer as the artifact being produced
  and is a larger leak than T3. Handled by §3 step 2's withholding arm.

## 5. Edge cases the design must handle

1. **An agent omits a row entirely.** A coverage gap, not a disagreement. RFC-COV-1
   (`scripts/rfc_coverage.py`) catches an `Encoded` row cited by no clause.
2. **Both agents produce a vacuous contract.** Equivalent and worthless. The agreement record
   carries the CDP verdict beside it so the two are read together.
3. **Subsumption abstains.** Per F-10 this is a **first-class per-row outcome inside the full
   `Encoded` denominator**, reported alongside equivalent, ordered and incomparable. Rev 0's EC3
   inverted the ledger's authority by inferring that the row's disposition was wrong; that
   inference is invalid, since abstention is a limitation of the driver and not a statement about
   the verifier. Never dropped, never routed back to the inventory.
4. **A row whose citing clauses straddle a comparable and a non-comparable contract.** New in
   Rev 1, surfaced by taking the measurement. `:source` citations are per clause and one row can
   be cited from more than one `def`. The rule is conservative: a row is comparable only when
   **every** clause citing it lives in a comparable contract. Without this stated, two
   implementations publish different denominators from identical data.
5. **An agent writes a `pre` and declines the `post`.** `toFQ = maybe (Just FQTrue) exprToPred`
   (`RefineReuse.hs:188`) reads the absent post as `True`, so the arm registers as *strictly
   weaker*, a lattice position, rather than a coverage gap. Route absent clauses to EC1 before
   comparison. Per F-12 this is likelier than EC1's whole-row omission.
6. **A parameter named `result`.** New in Rev 1 per F-12.2. `alphaRenameMap`
   (`RefineReuse.hs:106-112`) gives the parameter mapping priority, leaving the postcondition
   result binder unnormalized, which the source comment marks as a pathological input the QF-LIA
   gate does not reject. Under frozen signatures it is preventable: **"no parameter may be named
   `result`" joins the stage-K freeze rules.**
7. **N agents produce N distinct readings.** Per F-12.3, pairwise non-equivalence is not
   transitively closed, so this is two outcomes and not one. A chain `A ⊏ B ⊏ C` has a canonical
   disposition: take the weakest reading that still kills the pre-registered mutants, then apply
   F-6. Only a three-way antichain escalates as ambiguity.

### Positive witness for the modal outcome

EC3 is not a corner case but the most common verdict, and the minimal firing input is in the
committed corpus rather than constructed. In
`examples/tftp_rfc1350/wave/tftp-filled.ast.json`, def `opcode-of`, params `[(k, PacketKind)]`,
the post clause contains

```json
{"kind":"op","op":"=","args":[{"kind":"var","name":"k"},{"kind":"var","name":"KRRQ"}]}
```

`ufBearing` returns `True` at the `var` node named `KRRQ` (`RefineReuse.hs:291-292`, uppercase
head, nullary constructor term). Verdict: `not-comparable`; the row stays in the `Encoded`
denominator; no witness; no route back to the inventory. This shape fires 13 of 18 times in §0's
histogram.

## 6. Implementation surface

Rev 0's §6 priced the `[CT]` item as "small: a subcommand wrapping the two library calls, no new
theory, no new solver path". F-1 and F-5 refute that and §0 quantifies why. Corrected:

| Piece | Status |
|---|---|
| Contract subsumption over alpha-normalized contracts | **Shipped**, `RefineReuse.solveSubsumptionFQ` / `buildSubsumptionFQ`, exported. Applies to 10.6% of `Encoded` (§0) |
| Signature compatibility pre-filter | **Shipped**, `RefineReuse.signatureCompatible` |
| SMT plumbing: `fqPredToSMT`, `parseModel`, `renderWitness` | **Shipped and reusable** |
| Effective-contract comparison (F-2) | **Missing.** `RefineReuse.hs:194-195` binds parameters as `FQReft "v" sort FQTrue`, dropping refinements. Precondition of any meaningful number |
| Three-valued verdict (F-3) | **Missing.** `contractSubsumes` collapses non-`FQSafe` to `False` (`:226`), booking solver errors as fidelity findings. The information exists at `DiagnosticFQ.hs:58-62` |
| Two-contract difference query (F-5) | **Missing.** `Feasibility.buildQuery` takes one contract and hard-wires `∃in. pre ∧ ∀result. ¬(Rret ∧ post)` (`:167-169, 199-208`). Not reusable. The difference query is an easier shape, plain QF-LIA SAT |
| `result` in the witness vector (F-5) | **Missing.** `minimizeWitness` and `witnessOf` range only over `qInputs` (`:256-284`) |
| **Constructor-capable comparison backend** | **Missing.** See §6.1 |
| **Constructor-capable witness rendering** | **Missing.** See §6.2 |
| Harness to run N blind authors and tabulate | **Missing**, `[EXP]`, Python, beside the existing runner |

Corrected effort: `[CT]` **medium-to-large**, not small. `[EXP]` medium, and gated on §6.1.

### 6.1 The constructor-capable backend is the critical path, and it is in scope

Answering the review's Q2: in scope for this track, re-sequenced ahead of the harness, and
**without a Lever A dependency** (M-3). The argument is arithmetic. An N-way run costs N agent
authorings per row and, at 10.6%, returns a decidable verdict on one row in ten while excluding by
construction every state-transition row, which is where the pipeline's documented failure lives
(`step-weak`, pipeline §S4.4). Running the harness first spends the expensive resource on the
fragment where side-by-side audit is already easiest, which is F-13's bound restated as a
scheduling constraint.

The work is declaring constructors and their sorts in the subsumption query by reusing the
`FixpointEmit` declaration path, rather than the bare two-constraint `.fq` that "declares no UF
constants". §0's histogram shows zero array and zero measure abstentions in the measured corpus,
so the A2 component-splitting discipline is not implicated on this evidence and the Lever A
dependency the review assumed does not bind.

### 6.2 Sigma_witness is limited independently of Sigma_subsume, and this bounds §6.1's payoff

New in Rev 1; not in the review. `baseSortText` (`Feasibility.hs:187-191`) returns `Just "Int"` or
`Just "Bool"` and `Nothing`, which abstains, for every other type after alias and refinement
resolution. `witnessOf` and `minimizeWitness` (`:256-284`) range only over `qInputs`.

Consequence: widening comparison to constructor terms per §6.1 unlocks the C1 transition rows,
whose distinguishing input **is** a constructor value, and that value cannot be rendered. Those
rows would return a bare "these differ" bit with no exhibit. That undercuts the mechanism F-13
credits for the design's value, which is converting disagreement into "at input x, reading A
permits what B forbids; what does the text say about x".

The eliminative claim survives this: the solver's `sat` verdict establishes that a distinguishing
input exists, which falsifies "both readings are faithful" without depending on rendering the
model. What is lost is the adjudication affordance, not the soundness of the defeat. Whether that
makes §6.1 conditional on widening `baseSortText` to enum sorts, or merely enhanced by it, is
§8's question to the professor and §7's feasibility read for the engineer.

### 6.3 Build order

Amending the review's Recommendation 1. Each step has standalone value, so the sequence degrades
gracefully if it stops early.

- **(a)** `[CT]` SPEC-AGREE-1a, the constructor-capable comparison backend (§6.1), with the
  `baseSortText` widening scoped alongside it pending §7's feasibility read (§6.2). Acceptance:
  the comparable fraction over the same committed corpus rises from 9/85, republished.
- **(b)** F-2 and F-3 together, both preconditions of a meaningful number and cheap relative to (a).
- **(c)** The comparison CLI emitting the product position (F-4) with the difference query and
  `result` in the witness (F-5).
- **(d)** The two-arm gloss experiment (F-7 lever 2) on whatever fragment (a) delivers. The
  cheapest manipulation that determines whether anything else here means anything.
- **(e)** N = 3 with adversarial framings (F-7 lever 1).

Steps (a) through (c) have value for `refine` hygiene and accidental-duplication detection
independent of whether the experiment runs, which preserves the review's Recommendation 2 as a
fallback rather than an alternative.

## 7. Where it lands in the process

[`rfc-swarm-playbook.md`](rfc-swarm-playbook.md) stage K currently says root contracts are authored
by "agent(s)". The amendment is narrower than Rev 0 proposed: fix signatures **and add EC-6's
naming rule to the freeze**, evaluate `qfContract` per row, send only the comparable set for N-way
blind authoring, auto-accept unanimous rows, route non-equivalence to witness-based adjudication
subject to §6.2, record `not-comparable` rows in the denominator, then proceed to the coverage lint
and the freeze as before. Stage D (dual blind extraction) is the same pattern one layer up.

## 8. Open question for the professor

One question, replacing Rev 0's five. Four of those are answered by the review and the fifth by
F-13.

**Does an unrendered defeater carry evidential weight on its own?** Per §6.2, widening comparison
to constructor terms (§6.1) would produce rows where the solver decides that the two readings
differ but no witness can be rendered, because the distinguishing value is a constructor and
`baseSortText` admits Int and Bool only. In F-8's eliminative frame the `sat` verdict alone
falsifies "both readings are faithful", so the defeater is sound without the model. But the
design's claimed advantage over human audit is the exhibit, the forced-choice discrimination on a
concrete instance that F-13 grounds in Jackson's instance-level validation. If the exhibit is
absent, does unlocking C1 comparison add anything a coverage count would not already show, or does
the evidential value collapse to the bare count of disagreeing rows?

The answer decides whether widening `baseSortText` to enum sorts is a **prerequisite** of §6.1 or
an **enhancement** to it, which is the difference between one `[CT]` item and two.

## 9. Open item for the compiler-engineer

Feasibility read, not an implementation plan. See §7 of the hand-off: the cost of (i) reusing the
`FixpointEmit` declaration path for the subsumption query (§6.1) and (ii) widening `baseSortText`
to enum and constructor sorts with `witnessOf` extended to match (§6.2), and whether (ii) is
separable from (i) or forced by it.

## Provenance of §0

The measurement transcribes `qfContract` and applies it to committed artifacts; it does not invoke
the compiler. Before any figure here is published outside this document it should be re-run through
the real `classifyContractFragment`, `contractMentionsArrOp` and `ufBearing`, since §0.2's
approximation is generous and the true fraction is at or below 10.6%. Re-deriving it is
experiment-lead's slot and belongs beside the existing runner rather than in this document.
