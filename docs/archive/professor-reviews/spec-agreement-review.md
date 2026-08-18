---
name: spec-agreement-review
title: "Professor review of spec-agreement-proposal.md Rev 0"
status: "Rev 0, standalone review; not folded"
date: 2026-07-25
author: professor
consumers: [user, language-team, main-agent, compiler-engineer, experiment-lead]
---

# Professor review of `spec-agreement-proposal.md` Rev 0

## Restatement

SPEC-AGREE-1 replaces the single-author contract step (playbook stage K) with N blind formalizations of each `Encoded` inventory row
against frozen signatures, decides their logical relationship by bidirectional contract subsumption, emits a solver-generated
distinguishing witness on non-equivalence, and adjudicates that witness against the verbatim RFC text rather than by vote. The target is
the pipeline's admitted gap: `:source` is a traceability pointer and fidelity rests on human audit
([`spec-from-rfc-pipeline.md`](../../design/spec-from-rfc-pipeline.md) §2).

The idea is right, the epistemology needs rebuilding, and the shipped-primitives claim in §1 and §6 does not survive contact with the
code.

## Context located

1. `compiler/src/LLMLL/RefineReuse.hs:181-226`: `buildSubsumptionFQ` emits **one** `.fq` with two constraints (id 1 pre, id 2 post);
   `contractSubsumes` collapses the verdict to `Bool`. Lines 186-201: binders are `FQReft "v" sort FQTrue`, so parameter and return
   **refinements are dropped**.
2. `RefineReuse.hs:264-299`: the `qfContract` gate requires `classifyContractFragment == "qf_lia"` **and** no array op **and** no
   UF-bearing term, where `ufBearing` rejects `string-length`, `list-length`, pair selectors, `ok`/`err`, and **any uppercase head**, i.e.
   every constructor.
3. `Feasibility.hs:150-169, 187-208`: `buildQuery` builds `∃in. pre ∧ ∀result. ¬(Rret ∧ post)`, not a two-contract difference query; it
   folds param refinements into the effective pre (155-162), which subsumption does not; `baseSortText` admits **Int and Bool only**.
4. `DiagnosticFQ.hs:58-62`: `FQVerifyResult = FQSafe | FQUnsafe [ids] | FQError`. The three-way distinction and the failed-constraint ids
   exist and are discarded upstream.
5. `experiments/rfc-swarm/data/inventory-dispositioned.json`: 124 rows; the 46 `Encoded` split **C1 25, C2 10, C3 10, C4 1**.
6. `rfc-swarm-playbook.md` stages D/E, G, H, K, N: the obligation gloss, the "true by construction is not covered" rule, the probe
   contracts, the good twins. `docs/compiler-team-roadmap.md:208, 297-300`: R5 `diverge-report` classifies **observational** divergence.
   `examples/tftp_rfc1350/` holds only `VERIFICATION_SCOPE.md`, so stage K has not run: the amendment is well timed and F-1's measurement
   can still be taken before authoring.

## Findings

### F-1 (BLOCKER): the applicability claim is false; three nested fragments, not one

§1 argues that a row is `Encoded` precisely when its contract discharges in the decidable fragment, that the decidable fragment is where
subsumption is decidable, and therefore that SPEC-AGREE-1 applies to every `Encoded` row. The code shows three strictly nested fragments:

- **Σ_auto** (verification): QF-LIA, acyclic datatypes, enums, closed measures, bool, plus Lever A arrays and maps.
- **Σ_subsume** (`RefineReuse.hs:281-299`): QF-LIA scalars only. Any constructor, measure, pair, `Result` term or array op abstains. The
  module comment says why: the bare two-constraint `.fq` "declares no UF constants", so those terms "would reach liquid-fixpoint
  undeclared".
- **Σ_witness** (`Feasibility.hs:187-191`): Int and Bool base sorts only, for parameters and the declared return type.

On the motivating run the 25 `Encoded` C1 rows are state transitions over enums with outcome sums, so their contracts mention uppercase
constructors and abstain by `ufBearing`; C3 rows abstain wherever they use a length measure; the C4 row has no contract. The comparable
set is essentially the 10 C2 rows plus whichever C3 rows are plain integer ranges: **roughly a fifth to a quarter of the Encoded set**, on
the run this proposal exists to serve. That also refutes §6's effort table. "A subcommand wrapping the two library calls" is accurate only
for a tool that abstains on three quarters of its intended domain. Making it apply where §1 says it applies means giving the comparison a
real backend (the `FixpointEmit` path, which already handles datatypes, measures and the A2 component-splitting discipline) instead of the
bare `.fq`: medium-to-large compiler work, not small.

**Disposition.** Rev 1 states the comparable fragment and scopes the claim to it. Before any harness is written, run
`classifyContractFragment`, `contractMentionsArrOp` and `ufBearing` over the stage-H probe contracts and report the comparable fraction.
If it is under half, this is a C2 arithmetic study and should be described as one.

### F-2 (BLOCKER): dropped parameter and return refinements manufacture false disagreement

`buildSubsumptionFQ` binds every parameter as `FQBind i ("p"<>i) (FQReft "v" (typeToSortA aliases t) FQTrue)` (`RefineReuse.hs:194-195`)
and types the result binder by `typeToSortA` alone (line 193). `typeToSortA` yields a sort and discards the refinement, so the check
compares the authored `pre`/`post` over the **unrestricted** sort. `Feasibility.buildQuery` does the opposite, folding
`resolveAllRefinements` over parameters and return type into the effective query (`Feasibility.hs:155-162`), commenting that omitting them
"would weaken `pre` and risk a spurious REJECT".

For REFINE-REUSE the asymmetry is conservative: it costs advisory suggestions. For a measurement it is fatal in the other direction.
Frozen protocol signatures will carry refinement-typed parameters (`{v:Int | 0 <= v && v <= 65535}` for a TFTP block number is the obvious
case). Two contracts agreeing on every well-typed input but differing on a region the refinement already excludes are reported
**non-equivalent**, a witness is generated at an unreachable input, and a human is asked to adjudicate a difference that cannot arise.
**Disposition.** Compare the effective contract: `pre ∧ param refinements`, `post ∧ return refinement`, matching `buildQuery`. A
precondition of the experiment, not an optimization.

### F-3 (MAJOR): verdict conflation destroys the statistic, and the fix is one layer down

`contractSubsumes` maps everything that is not `FQSafe` to `False` (`RefineReuse.hs:226`). Non-`Safe` covers `FQUnsafe` (the implication
genuinely fails) and `FQError` (binary error, parse failure, timeout). A rate computed on that boolean cannot distinguish "the readings
differ" from "liquid-fixpoint fell over", so infrastructure noise is booked as a fidelity finding.

The information is discarded, not absent: `FQVerifyResult` carries `FQUnsafe [FQConstraintId]` and `FQError Text`
(`DiagnosticFQ.hs:58-62`), and `buildSubsumptionFQ` tags the pre constraint id 1 and the post constraint id 2 (`RefineReuse.hs:198-200`).
A comparison CLI calls `solveSubsumptionFQ` directly and never calls `contractSubsumes`. **Disposition.** Three-valued per direction.
`Unknown` rows leave both numerator and denominator and are reported as a separate coverage figure.

### F-4 (MAJOR): the lattice is the wrong shape; it is a product order, and Zaremski-Wing has the taxonomy

Subsumption is contravariant in the precondition and covariant in the postcondition (`RefineReuse.hs:17-20`, citing Liskov and Wing,
TOPLAS 16(6), 1994). The order is a **product** of two orders, and the three-point output projects it onto one axis: a single "strictly
ordered" verdict cannot say whether A demands less of the caller, promises more, or both.

**Precondition strengthening is the dangerous case.** A stronger `pre` narrows the domain on which the obligation fires. The function
still verifies, the contract still carries its `:source`, and no downstream instrument fires, because the excluded inputs are exactly the
ones no mutant exercises. This is the playbook's stage-G rule ("a row that is true by construction is not covered") recurring at the
clause level, and it should be a defect candidate by default, not "informative rather than fatal". **Postcondition strengthening** is
where the genuine better-reading-versus-over-strong ambiguity lives, and F-6 gives it a decision procedure.

The reference the proposal did not consult is Zaremski and Wing, *Specification Matching of Software Components*, TOSEM 6(4), 1997,
enumerating exact pre/post match, plug-in match, plug-in post match, weak post match and generalized match. `RefineReuse.hs:16` cites it;
the proposal does not. Their taxonomy is finer than three points and was built for this comparison problem. **Disposition.** Emit a pair
`(pre-position, post-position)`, each in `{≡, ⊐, ⊏, ⋈}`, from four solver calls or from two plus the failed-constraint ids of F-3. Adopt
the Zaremski-Wing names where they apply.

### F-5 (MAJOR): the witness machinery is claimed as shipped and is not

§3 step 3 says "the machinery exists" and cites `buildQuery`, `minimizeWitness`, `renderWitness`. `buildQuery` takes **one** contract and
hard-wires the feasibility shape: `qInnerNeg = (not inner)`, and `scriptOf` emits `(assert pre)` plus `(assert (forall ((result …))
innerNeg))` (`Feasibility.hs:167-169, 199-208`). That is `∃in. pre ∧ ∀result. ¬(Rret ∧ post)`, not `A ∧ ¬B`. The distinguishing query is a
different and easier shape, `∃p̄. pre_A ∧ ¬pre_B` and `∃p̄, result. post_A ∧ ¬post_B`, both quantifier-free over free constants, so plain
QF-LIA SAT rather than the `qsat` tactic the feasibility gate needs. `fqPredToSMT`, `parseModel` and `renderWitness` are reusable;
`buildQuery` is not. A second defect follows: `minimizeWitness` and `witnessOf` range only over `qInputs` (`Feasibility.hs:256-284`). For
a postcondition disagreement the distinguishing value is `result`, which is not an input, so the reported witness would name the inputs
and omit the value on which the readings actually differ, which is the half a human needs. **Disposition.** Rev 1 says "a new two-contract
difference-query builder reusing `fqPredToSMT`/`parseModel`/`renderWitness`", and adds `result` to the witness vector and the minimization
cost.

### F-6 (MAJOR): the strictly-ordered case can be dispositioned mechanically, three ways, all already in the repo

§8 Q2 says nothing in the check distinguishes a better formalization from an over-strong one. True of the subsumption check alone, false
of the process. The contract order is a refinement order in the sense of Back and von Wright (*Refinement Calculus*, 1998) and Morgan
(*Programming from Specifications*, 1990): `A ⊑ B` iff every implementation satisfying `A` satisfies `B`. Morgan's limit case of
over-strengthening is the miracle, the infeasible specification, and LLMLL ships the gate for it. Three discriminators, in decreasing
definitiveness:

1. **Feasibility.** Run `feasibilityOf` (`Feasibility.hs:292-304`) on the stronger contract. `sat` means no body can ever discharge it:
   definitively over-strong, decided without a human.
2. **Good-twin refutation.** Stage N already retains good twins explicitly "as the guard against over-strong contracts". A pre-registered
   twin that verifies under the weaker contract and refutes under the stronger shows the stronger forbids a legal implementation.
3. **Mutant kill differential.** If the pre-registered taxonomy kills strictly more under the stronger contract while all good twins
   survive, the stronger is the tighter faithful reading on available evidence. Defeasible, but it orders the candidates.

Both artifacts are pre-registered (PRE-REGISTRATION §5, stage N), so the cost is a re-run, not new evidence. This turns "informative
rather than fatal", which is a non-disposition, into a decision procedure with a small residue escalating to the text. It is the
highest-value change available and it costs nothing new.

### F-7 (MAJOR): Knight-Leveson is the right citation and the wrong stopping point; the largest leak is not T3

Knight and Leveson (*An Experimental Evaluation of the Assumption of Independence in Multiversion Programming*, IEEE TSE SE-12(1), 1986)
rejected independence for 27 versions written from a common specification, with correlated failures tracing to shared misconceptions about
hard regions of the input space rather than to shared code. Limiting, not fatal, and T1 stops one step early. The models that say what to
do next are Eckhardt and Lee (IEEE TSE SE-11(12), 1985) and Littlewood and Miller (IEEE TSE 15(12), 1989): failures correlate through a
common **difficulty function** over the input space, and **forced methodological diversity can drive the covariance negative**, better
than independence, when applied along the axis the difficulty runs on. Hatton (IEEE Software 14(6), 1997) gives the bound: substantial
improvement survives the correlation. A positive result also hides in the negative literature: Brilliant, Knight and Leveson's consistent
comparison problem (IEEE TSE 15(11), 1989) shows all-correct versions can disagree at a voter, the analogue being a genuinely
under-determined clause, so the refusal to vote should be defended on that ground too.

**Strongest defensible statement about an agreement rate measured this way.** Disagreement is sound evidence: a witness exhibits an input
the readings treat differently, so at least one reading is wrong or the clause is ambiguous, and that conclusion needs no independence
assumption. Agreement supports no probability statement, because the null model under which a rate would be read (independent errors) is
known false and its bias is unestimated. The defensible wording is about the clause, not the contract: *N formalizations produced under
framing F were pairwise equivalent, so no ambiguity in this clause was detectable at framing F*. That is a lower bound on
clause-plus-framing ambiguity, not an upper bound on formalization error. Report **disagreements found and adjudicated**, never a rate as
the headline.

The caution runs backwards to published numbers: Cohen's kappa of 0.938 (PRE-REGISTRATION §2) is an inter-rater **reliability** statistic
licensing "the rubric is operationalizable", not a validity claim, and any capture-recapture estimate of residual clauses from the
dual-extraction overlap should be resisted, since Briand, El Emam, Freimut and Laitenberger (IEEE TSE 26(6), 2000) show those estimators
are badly biased under positively correlated reviewers.

**Cheaper routes to independence, ranked by value per unit cost.**

1. **Adversarially different framings, near-zero cost, highest value.** One arm authors the contract from the clause; a second enumerates
   what the clause *forbids* and negates; a third writes the strongest contract a legal implementation could still violate. Forced
   diversity applied to the difficulty function, and the inspection literature supports it: Porter, Votta and Basili (IEEE TSE 21(6),
   1995) found scenario-based reading, each reviewer working a different structured perspective, beat both ad-hoc and checklist reading;
   Basili et al.'s Perspective-Based Reading (1996) is the named technique.
2. **Withhold the inventory gloss, near-zero cost, and it closes a leak the proposal missed.** §3 step 1 gives every agent "the verbatim
   RFC text, the inventory row, and the frozen signatures". The inventory row carries a one-sentence obligation authored by an extractor
   at stage D and adjudicated at stage E. That sentence is **a prior formalization of the same clause in prose**, fed identically to all N
   arms, and it is a larger leak than T3 because it sits at the same layer as the artifact being produced. Withhold it from at least one
   arm and report agreement with and without it: that converts the run from a measurement of agreement into a measurement of a priming
   channel's effect on agreement, which is the more informative result.
3. **Different model families, low cost, partial effect.** Attacks shared weights, not the shared corpus. Every frontier model has read
   the same RFCs and the same secondary accounts. Worth doing, not to be sold as the fix.

**Disposition.** Add T4, the obligation-gloss priming channel. Make levers 1 and 2 part of the design, not future work.

### F-8 (MAJOR): agreement is evidence about fidelity only as a defeater generator, and the rate is confounded

Separate three propositions. (P1) predicate φ is a faithful formalization of clause c. (P2) the implementation satisfies φ. (P3) the
implementation does what c requires. LLMLL mechanizes P2. P1 is not a formal proposition, because c is a natural-language artifact: it is
Boehm's validation question, not his verification question, and **no mechanical procedure can be positive evidence for it the way a proof
is evidence for P2**. What a mechanical procedure can do is produce *defeaters*: a witness showing two candidate readings differ
observably falsifies the conjunction "both are faithful". Agreement yields no corresponding entailment. That is the eliminative-induction
frame, where confidence comes from eliminating identified doubts rather than accumulating positive instances (Goodenough, Weinstock and
Klein, *Eliminative Induction: A Basis for Arguing System Confidence*, ICSE 2013; Rushby, *The Interpretation and Evaluation of Assurance
Cases*, SRI CSL-15-01, 2015). Built as a defeater generator the claim is defensible; built as a confidence meter it is not.

**A better-matched lineage than implementation diversity exists.** The formal-methods answer to "is this the right specification" is
animation and challenge, not replication: Jackson, *Software Abstractions* (2006), and the small-scope hypothesis, where you validate a
specification by having the tool exhibit concrete instances and checking them against intent; Leuschel and Butler's ProB (FME 2003) for B.
Witness adjudication is the Alloy move, and Jackson is a better foundation for it than Knight-Leveson. For the ambiguity claim, Berry and
Kamsties (*Ambiguity in Requirements Specification*, 2004) separate ambiguity from vagueness and generality and argue that multiple
independent readers detect ambiguity rather than establish correctness, which is precisely what this design can defend.

**The rate is confounded, and T2 does not cover it.** Weak contracts are the agreement attractor: a trivially-true post agrees with a
trivially-true post, so agreement rate is positively correlated with contract weakness *by construction*. T2 treats vacuity as an
independent downstream filter, which is necessary and not sufficient, because vacuity is a **confound of the statistic itself**. The
unstratified rate is uninterpretable in principle.

**Disposition.** Never report an unstratified agreement rate. Stratify by discriminative power: agreement among rows whose contracts kill
at least one pre-registered mutant, complement reported separately. For T2's instrument, the model-checking vacuity line is sharper than
`--cdp` and should be the named reference point: Beer, Ben-David, Eisner and Rodeh (CAV 1997; FMSD 2001), Kupferman and Vardi (STTT 2003),
and Chockler, Kupferman and Vardi on coverage metrics (TACAS 2001).

### F-9 (MAJOR): T3 ruling, resolve toward comparability, but T3 is understated and mislocated

The resolution is correct. Without shared vocabulary there is no decidable comparison, and an incomparable set of formalizations produces
no witnesses and therefore no defeaters, which is worse than a conditional measurement. Keep the freeze.

T3 is nevertheless understated. Comparability requires only **sort** agreement: `signatureCompatible` checks equal arity, positional
parameter sort vector, and result sort after alias resolution (`RefineReuse.hs:154-164`). The freeze as described also fixes the **state
decomposition**, including the arms of the outcome sum, and those arms are a formalization of the clause's case analysis. A frozen outcome
sum has already decided how many outcomes the RFC 1123 duplicate-ACK clause has, so agents writing posts over it are choosing among arms
someone else enumerated. For C1, 25 of the 46 Encoded rows, the frozen signature can contain most of the answer.

**Disposition.** Restate T3: the agreement rate is conditional on an architecture that itself encodes interpretive decisions, and for C1
rows that architecture may already contain the answer. Then measure the leak instead of only disclosing it. On a sample of rows, run one
arm against the frozen signature and a second against the same signature with constructor and field names mechanically replaced by opaque
`A0..An` (sorts preserved, semantic hints removed). Agreement that survives de-naming is materially stronger evidence, and the
manipulation is a renaming pass.

### F-10 (MAJOR): §5 edge case 3 inverts the ledger's authority

EC3 says subsumption abstention "should not occur on an `Encoded` row; if it does, the row's disposition was wrong". By F-1 that inference
is invalid: abstention is a limitation of the bare-`.fq` driver, not a statement about the verifier. Acting on EC3 would re-disposition
correct C1 and C3 rows out of `Encoded` to preserve a tool's applicability claim, corrupting the ledger to protect the instrument. The
ledger records what the verifier carries.

**Disposition.** `Not-comparable` becomes a first-class per-row outcome inside the **full** Encoded denominator, reported alongside
equivalent, ordered and incomparable. Never dropped, never routed back to the inventory.

### F-11 (MINOR): keep the agreement record out of the trust-tier vocabulary

If an agreement verdict lands in `--trust-report` or `.verified.json` beside the verification tiers, a downstream reader will read
"agreed" as an assurance level, when it is a process attestation about how a contract was authored and carries no verification content.
TRUST-PRE settled the same category error: a precondition must not floor a function's verified tier. **Disposition.** A separate artifact
keyed by inventory row; the words `verified`, `asserted` and `trust` do not appear in it; emitted by the harness, not by `verify`.

### F-12 (MINOR): three missing edge cases, one of them likely

1. **Empty post is treated as `True`.** `toFQ = maybe (Just FQTrue) exprToPred` (`RefineReuse.hs:188`). An agent that writes a `pre` and
   declines the `post` registers as *strictly weaker*, a lattice position, rather than a coverage gap. EC1 covers "omits the row
   entirely"; this is the likelier failure and lands in the wrong bucket. Route an absent clause to EC1 before comparison.
2. **A parameter named `result`.** `alphaRenameMap` (`RefineReuse.hs:106-112`) gives the parameter mapping priority, leaving the
   postcondition result binder unnormalized; the code flags this as a pathological input the QF-LIA gate does not reject. Under frozen
   signatures it is preventable: add "no parameter may be named `result`" to the freeze rules.
3. **EC5 conflates a chain with an antichain.** With N = 3 pairwise non-equivalence is not transitively closed, so "N distinct readings"
   is not one outcome. A chain `A ⊏ B ⊏ C` has a canonical disposition (take the weakest reading that still kills the pre-registered
   mutants, then apply F-6). A three-way antichain does not, and only that case escalates as ambiguity.

### F-13 (OBSERVATION): witness adjudication relocates human judgment, a real but smaller win than §8 Q5 assumes

Challenged directly: it does not replace human audit and does not reduce the quantity of human judgment. It changes the task from
generation to discrimination, and the failure mode from silent omission to recorded decision. The current audit (pipeline §2) is
open-ended recall: read the RFC text and the predicate side by side, confirm direction, totality, units. Its known failure mode is that
the auditor reads the predicate first and reconstructs a reading of the RFC that the predicate satisfies, which is why inspection practice
since Fagan (IBM Systems Journal 15(3), 1976) uses checklists and why Porter, Votta and Basili found structured perspectives beat ad-hoc
reading. Witness adjudication instead asks: at input x, reading A permits what reading B forbids; what does the text say about x.
Forced-choice discrimination on a concrete instance is a different and more reliable task, for the reason Jackson gives for instance-level
validation in Alloy.

Two bounds. The improvement is bounded by the fragment: by F-1 and F-5 the witness is sharpest on C2 arithmetic rows, where side-by-side
audit is already easiest, and absent on C1 transition rows, where audit is hardest and where the pipeline's documented failure lives
(`step-weak`, a dropped totality clause, pipeline §S4.4). The tool is strongest where the problem is weakest, which argues for
prioritizing F-1's backend rather than against building anything. And the residual human step is unchanged in kind, so the defensible
claim is process-level: adjudication makes disagreement enumerable and countable, forces a per-row record carrying a machine-generated
exhibit, and removes the auditor's ability to fail to notice. The pipeline already values exactly this (§S4.4: it "makes the weakness
visible and enumerable, it does not auto-detect it"). Frame SPEC-AGREE-1 as extending that sentence to the fidelity link and the claim
holds; frame it as mechanizing fidelity and it does not.

On §2's R5 duality, in passing: it understates itself. `diverge-report` classifies observational divergence among verifying fills, an
extensional relation on behaviors; subsumption is an intensional relation on predicates whose refinement-calculus meaning is inclusion of
the implementation model classes. Extensional and intensional views of one lattice is sharper than "two halves of the same question".

## Recommendation

1. **Build it with named changes, and re-sequence the build. Recommended.** Order: (a) measure the comparable fraction over the stage-H
   probe contracts before writing any harness (F-1); (b) fix the effective-contract defect (F-2) and the verdict conflation (F-3), both
   preconditions of a meaningful number; (c) ship the CLI emitting the `(pre, post)` position pair with three-valued verdicts (F-4) and
   the new two-contract difference query including `result` in the witness (F-5); (d) run a **two-arm framing experiment on the comparable
   subset only**, the arms being with and without the inventory obligation gloss (F-7 lever 2), the cheapest manipulation that determines
   whether anything else here means anything; (e) only then scale to N = 3 with adversarial framings (F-7 lever 1). Adopt F-6's three
   discriminators, F-10's `Not-comparable` outcome, F-8's stratified reporting, and the T4 threat.
2. **Build only the comparison CLI as a developer tool and defer the experiment.** Acceptable if F-1 comes back very low. The CLI has
   standalone value for `refine` hygiene and for detecting accidental contract duplication, and it keeps the option open.
3. **Do not build.** Rejected. The disagreement half is sound evidence independent of any independence assumption, the project reports
   nothing about the fidelity link today, and a C2-only defeater generator beats zero.

**On the specific questions.** Independence: limiting, not fatal, and the largest leak is the obligation gloss rather than the frozen
signatures. Agreement is evidence about fidelity only in the eliminative direction, as a defeater generator; the positive direction
supports no claim. The lattice output is the wrong shape and becomes a product position, with the strictly-ordered case decided by F-6's
three discriminators. T3's resolution toward comparability is right, understated, and should be measured by constructor de-naming rather
than only disclosed.

## The one measurement to report if it ships

**The count and per-row list of `Encoded` rows where witness adjudication changed the contract that was frozen**, as a fraction of the
rows that reached comparison, published beside the `Not-comparable` count and the comparable-fragment fraction from F-1. It is the only
number here that is falsifiable, cannot be inflated by weak contracts or by correlated agreement, and measures what the process claims to
add over human audit: detection yield rather than concordance. An agreement rate measures the models; this measures the method. If it
returns zero across a full RFC, that is a publishable negative result and should be published as one.

## Open questions for the language-team

1. Justify the `Encoded` denominator in light of F-1: if the comparable fraction on TFTP is near 10/46, does SPEC-AGREE-1 remain a
   pipeline stage amending stage K for all rows, or become a class-scoped instrument that runs on C2 and reports `Not-comparable`
   elsewhere? Rev 1 needs one of those shapes, not both.
2. State whether the datatype-capable comparison backend (reusing the `FixpointEmit` path with the A2 component-splitting discipline
   instead of the bare two-constraint `.fq`) is in scope for this track or a separate `[CT]` item with its own Lever A dependency. §6's
   effort table assumes it is not needed, which F-1 contradicts.
