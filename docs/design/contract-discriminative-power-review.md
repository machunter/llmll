# Professor Review: LT-CDP — Contract Discriminative Power as First-Class Evidence Axis

**Reviewer:** Lead Consultant for Formal Language Design
**Document under review:** [`contract-discriminative-power-proposal.md`](contract-discriminative-power-proposal.md) (Rev 1)
**Date:** 2026-05-25
**Status:** Review (Rev 1) — pending language-team adjudication

---

## Restatement

LT-CDP promotes the research-track CDP concept to a v0.11 first-class evidence axis. The proposal operationalizes the existing `WeaknessCheck.hs` trivial-body enumeration into a *counted* divergence metric over a finite observational behavior space `B_{T,U,Ω}`, defines a normalized score `DP_Ω(S) = 1 - log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)` with edge cases, and ships paired `(evidence, DP)` per function in the trust report (`trust_report_version 1.1.0 → 1.2.0`, additive). The optional `(spec-entropy :strict | :intentional | :unknown)` annotation honors the healthy-diversity-vs-underspecification tension. CDP is computed against the LT-INV `def` core form in v0.11; `def-shell` and LLM-generated candidate enumeration are v0.12+.

The proposal subsumes DP-FORM-1 (P3 formalization-only) and TRUST-DP-1 (P1 schema delta) into a single implementation item.

---

## Context located

- `compiler/src/LLMLL/WeaknessCheck.hs:40-90` — the existing trivial-body enumeration (`TrivIdentity`, `TrivConstZero`, `TrivConstEmptyStr`, `TrivConstTrue`, `TrivConstEmptyList`) and the call to `emitFixpoint` per candidate; CDP extends this pipeline.
- `LLMLL.md §5.3.1:600-613` — `--weakness-check` boundary; the binary "any trivial pass yes/no" signal CDP generalizes.
- `LLMLL.md §4.4.1:325-344` — diamond lattice; CDP is *orthogonal* to this lattice, not a fifth tier.
- `LLMLL.md:412` — `tier_profile` six-Int aggregate; unchanged by LT-CDP.
- `docs/llmll-trust-report.schema.json` v1.1.0 — schema-version-bump target.
- `docs/design/critique-2026-05-23-triage.md §3.2` — narrower lattice-valuation framing adjudication.
- `docs/design/invariant-discovery-review.md §4.1, §4.2` — observational-vs-semantic distinction and the healthy-diversity-vs-underspecification tension (the in-project anchor for the `:intentional` annotation).
- John Hughes, *QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs* (ICFP 2000) — coverage tracking via `classify`/`cover`; the canonical reference for "evaluations that satisfied the precondition" vs "evaluations total."
- John Hughes, *How to Specify It! A Guide to Writing Properties of Pure Functions* (TFP 2020) §4 — explicit treatment of coverage instrumentation as the honest sample-count measure.
- Andrews, Briand, Labiche, *Is Mutation an Appropriate Tool for Testing Experiments?* (ICSE 2005) — mutation-testing literature on equivalence-class boundaries under finite test suites; the closest external precedent for the "distinct observed behaviors" partition.
- Klees, Ruef, Cooper, Wei, Hicks, *Evaluating Fuzz Testing* (CCS 2018) — coverage-guided fuzzing's treatment of equivalence classes (branch-coverage as the equivalence proxy); the corpus-bias problem is acknowledged and addressed via stratified-corpus discipline, not via metric correction.
- Pacheco, Lahiri, Ernst, Ball, *Feedback-directed Random Test Generation* (ICSE 2007) — Randoop's contract-violation-as-witness framing; informative for what CDP cannot do (Randoop does not measure spec strength, only finds counterexamples).
- Shannon, *A Mathematical Theory of Communication* (1948) — the log-based information measure; LT-CDP's choice is the canonical entropy-style normalization.
- Birkhoff, *Lattice Theory* (3rd ed., 1967) Ch. X — valuations on finite lattices; Möbius-function-based alternatives to log valuations.
- Ganter & Wille, *Formal Concept Analysis* (1999) — closure operators on contract preorders; an alternative formal anchor for the subobject-lattice framing not pursued in §4.2 but worth naming.

---

## Strengths

The two-axis model at §1 is correct. The diamond lattice answers epistemic certainty; the discriminative axis answers spec strength; they are orthogonal questions and have been heuristically conflated in `--weakness-check`'s binary signal. Surfacing them as *paired* per-function metadata is precisely the move the four-cell matrix at §1 has been waiting for. The "verified-weak" / "tested-strong" / "asserted-strong" cells are not theoretical — they are observable in the v0.10 corpus already; the proposal makes them explicit rather than implicit.

The normalized score formula `DP_Ω(S) = 1 - log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)` is the right shape. The Shannon-style log normalization rewards rejecting *most* behaviors disproportionately to rejecting half — a contract that admits 1 of 1000 behaviors should score much higher than one that admits 500 of 1000, and log-normalization captures this monotonically. The edge cases (DP=0 admits-everything; DP=1 admits-one; DP-undefined inconsistent) are correctly enumerated.

The `(spec-entropy ...)` annotation is well-motivated. The healthy-diversity-vs-underspecification distinction at `invariant-discovery-review.md §4.1` is real — caches admitting any eviction is *correct*, not weak; schedulers admitting any ready thread is *correct*, not weak. The annotation gives agents an explicit way to declare this. The three-value design (`:strict` / `:intentional` / `:unknown`) maps cleanly to "raise diagnostic / suppress / compute-but-suppress."

The schema delta is additive on v1.1.0 — the `discriminative_axis` block is a new field per function; downstream consumers ignoring it continue to work. `trust_report_version 1.1.0 → 1.2.0` is the right increment.

The proposal subsumes DP-FORM-1 and TRUST-DP-1 cleanly, with explicit cross-references to the retired research-track row and the triage §3.2 framing.

---

## Gaps and hazards

### 1. The observational-vs-semantic distinction is buried in Risk #1; it should be load-bearing in §1

**Classify:** verification-ergonomics.

CDP is an *observational* metric over a chosen `Ω`. The score `DP_Ω(S) = 0.82` does not mean "82% of wrong implementations are ruled out" in any semantic sense — it means "82% of *observed* candidate behaviors over the chosen `Ω` are ruled out." Two implementations can be semantically distinct but observationally identical on every input in `Ω`; the inverse, that they can be semantically identical but observationally distinct, does not arise.

The proposal acknowledges this in Risk #1 and mitigates with the `basis` field's publication of `Ω`. This is correct as far as it goes, but the *interpretive* implication is not promoted to §1 motivation: readers of the proposal can come away believing CDP is a measure of spec quality rather than a heuristic for spec quality bounded by the candidate set's coverage. The `--weakness-check` predecessor was binary and inherently observational; CDP's *counted* generalization invites readers to treat the count as a semantic measure.

The honest framing: CDP is a *heuristic indicator that correlates with spec strength under enumeration discipline*, not a *measure of how many wrong implementations the spec rules out*. The four-cell matrix at §1 should carry the caveat: "verified-strong" is a *cell label*, not a *spec property*; it says "high evidence AND high observed DP given the candidate set under enumeration."

`invariant-discovery-review.md §4.2`'s framing — "Two implementations can be semantically different but observationally equivalent on all well-typed inputs" — is the in-project anchor for this caveat; it is cited in Risk #1 but the prose flow loses the warning by §5's score-reporting examples.

**Bite:** medium. The risk is *misinterpretation by downstream consumers* (CI gates, governance documents, agent-prompt-context). A 0.82 score that is read as a semantic measure could ship as a spec-quality threshold; under enumeration shifts (more candidates added in v0.12+ per §2 out-of-scope), the same spec scores differently and the threshold becomes unreliable.

---

### 2. The Shannon-style log normalization is one of three defensible families; the proposal does not justify the choice against alternatives

**Classify:** scope.

The formula `1 - log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)` is the inverse-information measure: it scores higher as the spec rejects more bits of the candidate set. This is principled but the proposal does not adjudicate between three defensible families:

(a) **Logarithmic** (the proposal's choice; Shannon-style). DP = `1 - log(|⟦S⟧|) / log(|B|)`. Rewards rejecting orders of magnitude.

(b) **Linear**. DP = `1 - |⟦S⟧| / |B|`. Rewards rejecting proportionally. Simpler; standard for coverage metrics in fuzzing (Klees et al., 2018 §3).

(c) **Möbius-function valuation on the subobject lattice** (Birkhoff, *Lattice Theory* Ch. X). The formal anchor at §4.2 places CDP on a subobject lattice; the Möbius function on this lattice provides a canonical valuation that respects the lattice structure (subobjects of subobjects are weighted correctly).

The proposal's choice (a) is *consistent with information theory* but the formal anchor at §4.2 is *lattice theory* — and the lattice-theoretic canonical valuation is (c). The Shannon-style choice is not derived from the lattice structure; it is *imposed* on the lattice from an information-theoretic argument that is not stated.

This is not a soundness issue — log-normalization produces correct relative orderings — but it is a *justification gap*. If a CI gate is set at "fail if DP < 0.7," the threshold is meaningful only under a specific valuation choice; switching from (a) to (b) shifts all thresholds.

**Bite:** low. The proposal can ship with (a) and add a §4.2 paragraph explaining why log was chosen over linear (entropy interpretation; rewards rejecting common cases) and why log was chosen over Möbius (computational simplicity; Möbius requires lattice-structure computation). Both stronger framings; both worth one sentence.

---

### 3. The trivial-body enumeration's small size is the practical-honesty problem; the proposal's mitigation is "extend to type-compatible candidates"

**Classify:** verification-ergonomics.

The five-element enumeration at `WeaknessCheck.hs:40-65` (`TrivIdentity`, `TrivConstZero`, `TrivConstEmptyStr`, `TrivConstTrue`, `TrivConstEmptyList`) is small. For most contracts, `|B_{T,U,Ω}|` is bounded by what the enumeration produces, and the candidate set is small enough that the score's denominator is unstable across small enumeration changes.

The proposal's §2 promises extension to "type-compatible candidates over the existing prelude" in v0.11 and to "LLM-generated candidates" in v0.12+. The v0.11 extension is the load-bearing one for the metric's utility — without it, CDP scores for contracts over non-trivial types (strings, lists, ADTs) collapse to "undefined-due-to-enumeration-limit" per edge case #4. With it, the candidate set is still modest (`0`, `1`, `-1`, small bool/string constants, single-element lists), and the score's stability under enumeration changes is the open question.

The proposal does not specify the extended candidate set. This is a v0.11 commitment that needs naming. Klees et al. 2018 §3 on fuzz-corpus design is the relevant external reference; the production fuzzers (AFL, libFuzzer) use *stratified* corpora that balance representativeness against coverage, and corpus *churn* (changing the candidate set across versions) is the standard reason for score instability.

**Bite:** medium. Without an explicit candidate-set definition in v0.11, the score is unstable across implementations; CI gates relying on absolute thresholds are unreliable. With an explicit definition, the score is stable but the candidate set's coverage of the *real* space of agent-emittable implementations is the next concern (v0.12+'s LLM-generated extension addresses this).

---

### 4. Equivalence-class counting under partial `Ω` exposes the metric to corpus-bias

**Classify:** verification-ergonomics.

This is the author Q1 question. Two candidate implementations are *equivalent* iff they agree on every input in `Ω`. The equivalence class boundaries depend on `Ω` — small `Ω` collapses classes; large `Ω` separates them. The metric's distinct_observed_behavior_count is corpus-dependent.

The mutation-testing literature (Andrews-Briand-Labiche, ICSE 2005) has the closest treatment: the mutation *score* (proportion of mutants killed by the test suite) is known to depend on the suite, and the "coupling effect" (Offutt 1992) studies how higher-order mutants relate to first-order mutants under the same suite. The result is empirical: the coupling effect is observed in practice but is *not* a metric correction; it is a *coverage-of-coverage* observation.

Coverage-guided fuzzing (Klees et al., 2018) handles this through stratified corpora and through reporting *coverage-of-coverage* (how much of the branch space the corpus exercises). The corpus-bias problem is acknowledged and addressed via *corpus discipline*, not via metric correction.

**The literature's honest answer to author Q1**: the bias is inherent; the standard mitigation is to publish `Ω` alongside the score (which the proposal does) and to require comparable `Ω` for cross-function score comparison. There is no canonical "corpus-bias correction" for spec-strength metrics. CDP-0's mitigation (the `basis` field with provenance) is the correct move.

**Bite:** low-medium. The proposal's mitigation is correct; the *naming* of the bite could be sharper. The honest framing: CDP scores are *comparable within a single `Ω`* and *not directly comparable across different `Ω`s*. Cross-function comparison requires same-`Ω` discipline that the proposal correctly enforces via the `basis` field but does not yet enforce in the trust-report consumer side.

---

### 5. The `(spec-entropy :intentional)` annotation has a self-suppression failure mode the 30% threshold does not solve

**Classify:** scope.

Risk #3 names the abuse pattern: agents annotate every low-DP contract as `:intentional` to silence diagnostics. The mitigation is a 30% over-annotation threshold raising an informational warning. This is reasonable but the threshold is configurable and not load-bearing.

The deeper issue: `:intentional` is a *self-attestation*, and self-attestations have no independent verification. The agent declaring the annotation is the same agent whose spec is being measured. Compare to LH's `{-@ assume @-}`: it is a *self-attestation* but the LH community treats it as a code-review signal — the assume is human-audited, and the social pressure against unjustified assumes is the enforcement mechanism.

LLMLL has no equivalent social pressure if the corpus is agent-emitted. The 30% threshold is a *statistical* check — it asks "is this codebase abusing :intentional?" but cannot ask "is *this specific annotation* justified?" The annotation's justification (per the trust report's `spec_entropy_annotation` field) is recorded but not adjudicated.

The Rust attribute system's precedent is informative: `#[allow(...)]` suppresses lints, and crater (`crater.rust-lang.org`) audits the rate at which `#[allow(...)]` is used across the ecosystem to detect lint over-suppression. The audit is empirical; the per-instance justification is enforced by code review.

**Bite:** low. The mitigation is correct in shape; the limitation is that *automated* enforcement cannot do better than the threshold heuristic without a human-audit step. Worth flagging in the proposal that `:intentional` is a self-attestation channel and that the 30% threshold is an *abuse-rate* check, not a *per-instance justification* check.

---

### 6. The score's interaction with the LT-INV empirical gate is partially self-referential

**Classify:** scope.

Risk #4 names this concern. LT-INV's §8 empirical gate measures (among other things) the *spec-strength distribution* axis (axis 3 in `core-shell-inversion-direction.md` §8.1). CDP-0 is the metric for spec strength. The gate is partly self-referential: does CDP improve under inversion? CDP itself defines the question.

The proposal's mitigation — baseline DP on the pre-inversion corpus; gate measures *distribution shifts* in the expected direction — is correct but creates a coupling between LT-INV's gate-pass criteria and LT-CDP's shipping. If LT-CDP ships and *then* the LT-INV gate measures DP, the measurement uses the CDP metric LT-CDP just defined. If LT-CDP ships and the *baseline* is the pre-inversion DP on the same metric, the comparison is consistent but the metric is new and unvalidated.

The cleaner sequencing: ship CDP-0, measure baseline DP on the v0.10 corpus, *then* run the LT-INV gate. This is what §2 out-of-scope's sequencing implies (LT-CDP ships after LT-INV) but it inverts what's natural for the measurement (CDP-0 measurement should happen *before* LT-INV measurement to establish the baseline).

The proposal's recommended sequencing in roadmap §8.4 is LT-INV first behind opt-in, then CDP/PPR/INT in parallel. This means CDP-0 ships *concurrent with* the LT-INV gate run. The gate then measures with a CDP metric that has not been independently validated against the v0.10 baseline.

**Bite:** low-medium. The methodological concern is real but the mitigation (baseline-first) is implementable. Worth committing in the proposal: CDP-0 ships with a v0.10-baseline DP report published before the LT-INV gate measurement runs.

---

### 7. The `def-shell` exclusion (per §2) creates a CDP-blind region exactly where measurement is most needed

**Classify:** scope.

§2 out-of-scope: "Reporting on the shell form (`def-shell`)." v0.11 reports against `def` only. The sequencing is correct (CDP enumeration is decidable in core form; shell-form constructs require non-trivial enumeration). But the *measurement* implication is: CDP scores are reported for the most-disciplined fraction of the corpus and absent for the rest.

If LT-INV's empirical gate confirms the boundary-form distribution skews toward `def-shell` (Risk #7 of LT-INV), the CDP report covers a small fraction of code. The dashboard's four-cell matrix at §1 then reflects only the `def`-form subset — exactly the subset for which the trust-report's existing `tier_profile.verified` slot already provides a strong signal.

The cells the project most needs visibility into — `def-shell` functions with strong evidence but unmeasured DP, or `def-shell` functions with weak evidence and unknown DP — are exactly the cells LT-CDP cannot report on.

**Bite:** medium. The proposal correctly defers shell-form reporting to v0.12+ but the trust-report consumer documentation should be explicit that "no DP reported" for shell-form functions means *not measured*, not *measured as zero* or *measured as undefined*. The current Edge case #4 (`undefined-due-to-enumeration-limit`) collides semantically with "shell-form: not measured" — both produce no score, but for different reasons. The trust-report schema should distinguish them.

---

## Answers to author-surfaced questions

### Q-PROF-1. Equivalence-class counting under partial `Ω` — corpus-bias correction in PBT literature?

**The bias is inherent; the literature does not establish a canonical correction.** The standard mitigation is corpus discipline plus publication of `Ω` alongside the score. The proposal's `basis` field is the correct move.

The detailed literature reading:

- **Hughes' QuickCheck papers** (Claessen-Hughes ICFP 2000; Hughes TFP 2020) treat coverage tracking (`classify`/`cover`) as the discipline for understanding *what the corpus measures*, not as a correction for *what the corpus does not measure*. Hughes 2020 §4 explicitly: "the `classify` combinator does not change the test's correctness, only its informativeness."
- **Mutation testing** (Andrews-Briand-Labiche ICSE 2005; Offutt 1992 coupling effect) is the closest analog. The mutation score is corpus-dependent and the coupling effect is *empirically* observed (suites that kill first-order mutants tend to kill higher-order mutants) but no metric correction is canonical.
- **Coverage-guided fuzzing** (Klees-Ruef-Cooper-Wei-Hicks CCS 2018) handles corpus bias via stratified corpora and coverage-of-coverage reporting; the corpus-bias problem is *addressed by corpus design*, not by metric correction.
- **Metamorphic testing** (Chen et al., 1998; Pacheco-Lahiri-Ernst-Ball ICSE 2007 §2) defines *equivalence-via-relation* — two implementations are equivalent iff they preserve a known relation under input transformation. This is a *semantic* equivalence on top of the test corpus; it is not corpus-dependent. But it requires the relation to be specified, which moves the burden from corpus design to relation design.

**Recommendation for the proposal:** retain the publish-with-provenance mitigation; add a sentence to §4.3 naming that the metric is "comparable within a single `Ω`, not directly comparable across different `Ω`s." Add a footnote pointing to Klees et al. 2018 for the corpus-discipline tradition that LLMLL is inheriting.

### Q-PROF-2. Lattice valuation choice — Shannon vs alternatives?

**No canonical valuation; Shannon-style is defensible.** Three families are admissible: logarithmic (entropy-style, the proposal's choice), linear (coverage-style), and Möbius-function (lattice-theoretic-canonical).

The detailed literature reading:

- **Shannon-style logarithmic valuation** is the canonical entropy measure (Shannon 1948). It rewards orders-of-magnitude rejection. For a contract that admits 1 of 1000 behaviors, Shannon gives DP ≈ 1 - log(1)/log(1000) = 1.0; linear gives DP = 1 - 1/1000 = 0.999. The Shannon measure compresses the score's high end and expands the low end — which is the right shape for spec-strength signaling (the difference between "admits 1 of 10" and "admits 1 of 1000" matters more than the difference between "admits 1 of 990" and "admits 1 of 999").
- **Linear valuation** is the standard for fuzz-coverage metrics (Klees et al., 2018 §3) and for mutation scores (Andrews-Briand-Labiche, ICSE 2005). It is simpler, more intuitive, and tracks proportional coverage. The trade-off: it does not reward exponential rejection.
- **Möbius-function valuation** (Birkhoff, *Lattice Theory* Ch. X §3) is the canonical lattice-theoretic measure. It respects the subobject-lattice structure (a subobject's value is computed from its place in the lattice, not from cardinality). For finite distributive lattices, the Möbius function is computable; for the contract preorder under implication, it would give DP weighted by the number of *distinct* implication levels rather than by absolute count.

**The lattice-theoretic anchor at §4.2 points to Möbius, but the proposal ships Shannon.** This is defensible — Shannon is computationally trivial; Möbius requires computing the lattice structure of the candidate set, which is expensive at scale. The proposal can ship Shannon and document why: (a) Shannon's bit-rejection interpretation is more communicable to downstream agent-consumers; (b) Möbius requires per-batch lattice computation that does not scale linearly with candidate-set size.

**Recommendation:** retain Shannon; add a §4.2 paragraph (two sentences) acknowledging that the formal anchor admits Möbius as the canonical lattice valuation, that Shannon is chosen on computational and interpretability grounds, and that future work may explore Möbius-based scoring on smaller candidate sets where the lattice structure is tractable. This closes the credit-loss against the lattice framing without committing to a redesign.

---

## Cross-proposal observation

LT-CDP depends on LT-INV's `def`/`def-shell` distinction for its scope (`def` only in v0.11). If LT-INV adopts the relaxed callee-closure per `core-shell-inversion-review.md` Gap #1 / Q-PROF-1, the `def` subset grows, and CDP-0's baseline measurement shifts proportionally. The CDP `discriminative_axis` block reports against a moving target unless the empirical gate is run with both proposals settled.

LT-CDP also rests on REF-META-1's refinement-predicate semantics: the contracts CDP measures are predicates over `def` bodies whose intro/elim rules are codified in REF-META-1 §4.1. If REF-META-1's checking-mode rule is revised (per `refinement-metatheory-of-record-review.md`), the contract semantics CDP measures change — though for the v0.11 surface, the introduction-site equivalence to Vazou's framing means CDP is insulated from the elimination-context refinements.

The fuller cross-proposal sequencing observation appears in `refinement-metatheory-of-record-review.md`.

---

## Recommendation

**Approve with revisions.**

The two-axis model is the right move and the divergence metric is principled. Three revisions are load-bearing:

1. **Promote the observational-vs-semantic caveat from Risk #1 to §1 motivation (per Gap #1).** Two sentences in the framing of the four-cell matrix: "DP is a heuristic indicator under enumeration discipline, not a measure of semantic spec strength. The four cells are *interpretable signals*, not *spec properties*." Without this, downstream consumers will read 0.82 as a semantic measure and set CI gates accordingly, which is unsafe under enumeration changes.

2. **Specify the v0.11 extended trivial-body enumeration explicitly (per Gap #3).** "Type-compatible candidates over the existing prelude" is too loose; commit to a numbered list (`0`, `1`, `-1`, `true`, `false`, `""`, `"a"`, empty list, single-element list, etc.) in §4.3. The list can be expanded over time but the v0.11 set should be a settled artifact so consumers comparing scores across versions can audit the baseline.

3. **Address the LT-INV empirical-gate self-reference (per Gap #6).** Commit in §2 sequencing: CDP-0 ships *and* publishes a v0.10-baseline DP report *before* the LT-INV §8 empirical gate measurement runs. This decouples LT-CDP's metric definition from LT-INV's metric application.

The remaining gaps (#2 normalization-choice justification, #4 corpus-bias inherent, #5 :intentional self-attestation, #7 def-shell blindness) are addressable in-prose without structural revision; Rev 2 incorporates them as risk-section enrichments or text-level corrections.

The empirical gate's self-reference (Gap #6) is the methodological concern that warrants the most attention. With it addressed, the proposal is ready for engineer hand-off.

---

## Open questions for the language-team

1. **Commit to a specific extended trivial-body enumeration for v0.11.** Enumerate the candidate set in §4.3 (or a §4.3a sub-section). The score's stability across implementations depends on the enumeration being stable; the score's *usability* depends on the enumeration being non-trivial. Without explicit enumeration, the v0.11 baseline is unreproducible.

2. **Specify the trust-report distinction between "DP undefined (enumeration too small)" and "DP not measured (def-shell)."** Both surface as no-score in the trust-report consumer; semantically they are different. The trust-report schema should distinguish them via the `warnings` field or a typed status enumeration. This matters for the four-cell dashboard's coverage signaling.
