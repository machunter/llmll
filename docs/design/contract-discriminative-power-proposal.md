# LT-CDP — Contract Discriminative Power as First-Class Evidence Axis

> **Version:** Rev 2 — incorporates professor review findings (seven gaps and two author-question answers folded; cross-proposal C-2 settlement referenced per LT-INV-gate sequencing)
> **Date:** 2026-05-23 (Rev 1); 2026-05-25 (Rev 2)
> **Implements:** `docs/compiler-team-roadmap.md` v0.11 milestone, Implementation Item 2 (LT-CDP / CDP-0)
> **Prerequisites:** LT-INV grammar inversion (sequenced after — CDP-0 reports against the *core* form first, where the trivial-body enumeration is decidable; extending to the shell is a later step). Cross-proposal shipping under LT-INV gate outcomes specified at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) §2.
> **Origin:** 2026-05-23 external critique processed via professor channel ([`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §2); language-team triage at [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §3.2; supersedes the triage rows DP-FORM-1 (P3 formalization-only) and TRUST-DP-1 (P1 schema delta) into a single v0.11 implementation item
> **Promotes:** [`docs/research-track.md:145-151`](../research-track.md) "Contract discriminative power" research-track item to v0.11 implementation (research-track row was retired with cross-reference in Pass 3 of the 2026-05-23 catch-up branch)
> **Reviewed:** Professor review at [`contract-discriminative-power-review.md`](contract-discriminative-power-review.md) (Rev 1, 2026-05-25); recommendation `approve with revisions`. Seven gaps and two author-question answers folded into this Rev 2. Standalone review awaits doc-lead M2 fold-and-archive.
> **Status:** Settled (Rev 2) — professor review folded; pending compiler-engineer hand-off, sequenced after LT-INV per §2

---

## 1. Motivation

LLMLL's evidence model at [`LLMLL.md §4.4.1:325-344`](../../LLMLL.md) answers one question per function: *do we know this implementation satisfies the specification?* The diamond lattice (`verified` / `contract-checked` / `tested` / `asserted`) is the partial order on epistemic certainty. The lattice is load-bearing for downstream tooling — the `tier_profile` six-Int aggregate at [`LLMLL.md:412`](../../LLMLL.md) plus the OBLIG-PBT-3 per-clause split into `tier_profile_pre` / `tier_profile_post` give consumers a structured signal on what is known.

It does not answer a different, equally important question: *does the specification rule out enough wrong implementations?* A `verified` weak spec and a `verified` strong spec receive the same label. The v0.10 obligation report has a measurable blind spot the existing axes do not cover.

`--weakness-check` at [`LLMLL.md §5.3.1:600-613`](../../LLMLL.md) is the operational predecessor. It enumerates trivial candidate bodies — identity, constant-zero, constant-empty-string, constant-true, constant-empty-list — and checks whether any of them satisfy the contract. If any trivial body passes, a `spec-weakness` diagnostic fires. This is a *binary* signal (any trivial pass yes/no); it is the heuristic precursor to a *counted* divergence metric.

The professor direction memo at [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §2 makes the gap explicit:

> The original professor turn defended this status as *already named*. That defense was too weak. Naming a concept in a research-track row is not the same as exposing it as a routine reporting dimension, and the v0.10 obligation report has a measurable blind spot the existing axes do not cover.

LT-CDP promotes contract discriminative power (CDP) from research-track to a v0.11 first-class evidence axis. The proposal makes the metric operational, formalizes it as a valuation on a finite subobject lattice (per the amended critic's narrower categorical reading at [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §3.2), and ships it alongside the existing diamond-lattice evidence axis in a paired `(evidence, DP)` trust-report representation.

The two axes are orthogonal:

- **Evidence axis** answers: *do we know this implementation satisfies the specification?*
- **Discriminative axis** answers: *does the specification rule out enough wrong implementations?*

A function can simultaneously be `verified` (high evidence, body-faithfully discharged) and 0.18 DP (weak spec, admitting most observable behaviors). The pair makes this visible without collapsing to a scalar. The four spec-quality cells the project has been heuristically reaching for since `--weakness-check` shipped in v0.3.5 become explicit:

| Evidence | DP | Cell |
|---|---|---|
| `verified` | high | **verified-strong** — the ideal |
| `verified` | low | **verified-weak** — high certainty about a permissive contract |
| `tested` | high | **tested-strong** — lower certainty about a tight contract |
| `asserted` | high | **asserted-strong** — promising spec, poor evidence |

The four-cell matrix is the spec-quality dashboard the project has been reaching for. LT-CDP makes it operational.

**Observational-vs-semantic framing (Rev 2, per the professor review's Gap #1 — load-bearing caveat).** CDP is a *heuristic indicator under enumeration discipline*, not a *measure of semantic spec strength*. The score `DP_Ω(S) = 0.82` does not mean "82% of wrong implementations are ruled out" in any semantic sense — it means "82% of *observed* candidate behaviors over the chosen observation set `Ω` are ruled out." Two implementations can be semantically distinct but observationally identical on every input in `Ω`. The four cells above are *interpretable signals* under a given `Ω`, not *spec properties* in the semantic sense; consumers comparing scores across functions or across versions must compare against the same `Ω`. This caveat is load-bearing for downstream consumers: a CDP score read as a semantic measure would set CI gates on the wrong reading, and under enumeration changes (per §4.3 candidate-set enumeration; v0.12+ widening) the same spec scores differently. The trust report's `basis` field (per §5) records `Ω`'s identity for auditability; see Risk #1 below and [`docs/design/invariant-discovery-review.md §4.2`](invariant-discovery-review.md) for the in-project anchor for this distinction.

---

## 2. Scope

**In scope:**
- Promote CDP from research-track formalization to v0.11 implementation; retire [`docs/research-track.md:145-151`](../research-track.md) row (already done in Pass 3 of the 2026-05-23 catch-up)
- Operationalize the divergence metric on top of the existing `--weakness-check` trivial-body enumeration at [`compiler/src/LLMLL/WeaknessCheck.hs:40-90`](../../compiler/src/LLMLL/WeaknessCheck.hs)
- Define the normalized DP score with edge cases (every behavior, single behavior, inconsistent)
- Introduce the optional `(spec-entropy :strict | :intentional | :unknown)` annotation honoring the healthy-diversity-vs-underspecification tension at [`docs/design/invariant-discovery-review.md §4.1:267-279`](invariant-discovery-review.md)
- Extend the trust-report JSON with paired `(evidence, DP)` per function: `evidence_axis` + `discriminative_axis` blocks with provenance
- `trust_report_version` bump `1.1.0 → 1.2.0` (additive)
- Subsume the triage rows DP-FORM-1 and TRUST-DP-1 into this proposal (DP-FORM-1 was P3 formalization-only; TRUST-DP-1 was P1 schema delta; LT-CDP combines both into a single v0.11 implementation item)

**Out of scope (deferred):**
- **Behavior-equivalence semantic decision procedure.** The metric reports observational equivalence over the observation set `Ω`; a true semantic-equivalence check requires the richer fragment that lives outside QF-LIA. See Risk #1 below and [`invariant-discovery-review.md §4.2`](invariant-discovery-review.md).
- **LLM-generated candidate enumeration.** v0.11 extends the trivial-body enumeration to type-compatible candidates over the existing prelude; v0.12+ widens to LLM-generated candidates per the Phase B item at [`invariant-discovery-review.md §5`](invariant-discovery-review.md).
- **CDP as a CI-gate threshold mechanism.** v0.11 reports the score with provenance; consumers can set CI gates locally. A normative project-wide CDP threshold is a policy decision deferred until empirical data on the v0.11 baseline establishes what thresholds are meaningful.
- **Reporting on the shell form (`def-shell`).** v0.11 reports against `def` (the core form) first, where the trivial-body enumeration is decidable and the verifier discharges per the body-faithful pipeline. Extending to `def-shell` is a v0.12+ widening with non-trivial enumeration questions for fallback constructs.

**Out of scope under v0.11 surface — sequencing:**
- LT-CDP ships **after** LT-INV (`def`/`def-shell` grammar split). The CDP metric's first-pass scope is the core form; the report extends to shell form only after LT-INV's grammatical boundary is in place.
- **Baseline-first sequencing (Rev 2, per the professor review's Gap #6).** CDP-0 ships **and publishes a v0.10-baseline DP report on the pre-inversion corpus before** the LT-INV §8 empirical-gate measurement runs. The LT-INV gate measures (among other axes) the *spec-strength distribution* — which uses the CDP metric LT-CDP defines, creating a self-reference. The baseline-first sequencing breaks the self-reference: the v0.10 baseline is measured *before* the LT-INV grammar change ships behind opt-in, so the gate's pre/post comparison compares against an independently-established baseline rather than against the metric's first deployment. The baseline report lives at [`experiments/minimal-agent/findings/cdp-v0.10-baseline.md`](../../experiments/minimal-agent/findings/) (created by experiment-lead post-CDP-0 ship); the engineer hand-off names this baseline as a prerequisite for the LT-INV §8 gate run.
- **Cross-proposal shipping under LT-INV gate outcomes.** Per [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) §2: Outcome 0 (gate passes) ships LT-CDP as proposed; Outcome 1 (LT-INV opt-in-only) reports `discriminative_axis` only under the `--grammar=core-inversion` flag; Outcome 2 (LT-INV retracted) ships LT-CDP against `def-logic` with the body-faithful set as implicit scope. Schema bump under Outcomes 0 and 1 is `trust_report_version 1.1.0 → 1.2.0` (additive); Outcome 2 ships independently and coordinates with LT-PPR per the C-2 settlement.

---

## 3. Surface

LT-CDP introduces no new keyword. The optional `(spec-entropy ...)` annotation per memo §2 and per [`invariant-discovery-review.md §4.1`](invariant-discovery-review.md)'s required-mitigation note:

```lisp
;; Default: strict — low DP raises a diagnostic per `--weakness-check`
(def transfer [from: AccountId to: AccountId amount: PositiveInt]
  (pre  (>= (balance-of from) amount))
  (post (and (= (balance-of from) (- (old (balance-of from)) amount))
             (= (balance-of to)   (+ (old (balance-of to))   amount))))
  ;; (spec-entropy :strict)  -- default; can be elided
  ...)

;; Intentional: permissive contract, never raises
(def-shell cache-lookup [k: Key]
  (post (or (is-ok result) (is-error result)))
  (spec-entropy :intentional)
  ...)

;; Unknown: computed and reported, never raises (useful during spec development)
(def-shell new-feature-stub [...]
  (post (or (is-ok result) (is-error result)))
  (spec-entropy :unknown)
  ...)
```

Three values:

- **`:strict`** (default) — low DP raises a diagnostic via `--weakness-check`. This is the default for `def` (core form, where contracts should be tight) and for `def-shell` functions without an explicit annotation.
- **`:intentional`** — low DP is the design (caches admit any eviction; schedulers admit any ready thread; hash-map iteration order is unspecified). The annotation is the agent's explicit declaration; CDP is still computed and reported, but does not raise a diagnostic.
- **`:unknown`** — CDP is computed and reported but does not raise. Useful for spec-development workflows where the agent is iterating on the contract and does not want noise from a partially-formed spec.

The annotation lives at the same syntactic level as other function-level metadata (`:source`, `:trust`, etc.); the parser slots it in via standard keyword-metadata handling. No grammar change beyond the keyword recognition.

---

## 4. Semantics — divergence metric over trivial-body enumeration

The score builds on `WeaknessCheck.hs`'s existing trivial-body enumeration but extends it from a binary "any trivial body passes?" to a counted measure.

### 4.1 Definition

Let `B_{T,U,Ω}` be the finite set of observational behaviors for functions `T → U` over observation set `Ω` (the union of: existing harness tests, generated edge cases from `--weakness-check`'s extended enumeration, and PBT samples — the OBLIG-PBT-4 sample set already lives in the trust report; CDP reuses it). Let `⟦S⟧_Ω = { b ∈ B_{T,U,Ω} | b satisfies contract S }`.

The normalized discriminative-power score:

```
DP_Ω(S) = 1 - log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)
```

with edge cases:

- `DP_Ω(S) = 0` if S admits every observable behavior (`|⟦S⟧_Ω| = |B_{T,U,Ω}|`)
- `DP_Ω(S) = 1` if S admits exactly one observable behavior (`|⟦S⟧_Ω| = 1`)
- `DP_Ω(S) = undefined / flagged` if S is inconsistent (`|⟦S⟧_Ω| = 0` — distinct failure mode from low DP, surfaces as separate `spec_inconsistent: true` diagnostic)

### 4.2 Lattice-theoretic interpretation (formal anchor)

Per [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §3.2, the formal anchor is:

- Contracts form a preorder under implication: `S ≤ T` ⇔ S is stronger than T ⇔ every behavior satisfying S also satisfies T
- Denotation maps contracts to subobjects of behavior space: `S ↦ ⟦S⟧_Ω ⊆ B_{T,U,Ω}`
- Strengthening shrinks the denotation: `S ≤ T` ⇒ `⟦S⟧_Ω ⊆ ⟦T⟧_Ω`
- DP is a valuation on the subobject lattice: smaller denotation ⇒ higher DP

This is undergraduate-level apparatus (finite-lattice + valuation, not fibration + graded monad). The narrower unification was adopted per the amended critic's revised position at [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §3.2; the broader categorical unification (the original critique's §13) was declined per professor adjudication. The patch-merge invariant remains stipulated (not derived from the lattice), per Sub-proposal 3 of the language-team triage.

**Valuation choice — Shannon over Möbius (Rev 2, per the professor review's Gap #2 / Q-PROF-2).** The formal anchor above admits multiple defensible valuations on the subobject lattice. Three families are admissible: **logarithmic** (the §4.1 choice, Shannon-style — `1 - log(|⟦S⟧|) / log(|B|)`), **linear** (coverage-style — `1 - |⟦S⟧| / |B|`, the standard for fuzz-coverage metrics per Klees et al. CCS 2018), and **Möbius-function** (the canonical lattice-theoretic valuation per Birkhoff *Lattice Theory* Ch. X §3, weighted by the lattice's structure rather than by cardinality). The lattice-theoretic anchor *strictly* points to Möbius as the canonical valuation; Shannon is chosen on two pragmatic grounds: (i) the bit-rejection / entropy interpretation is more communicable to downstream agent-consumers than the Möbius-function combinatorics, and (ii) Shannon is computationally trivial at the v0.11 candidate-set sizes (10s of candidates per contract), whereas Möbius requires computing the lattice structure of the candidate set, which is expensive at v0.12+ scale. Future work on smaller candidate sets where the lattice structure is tractable may explore Möbius-based scoring as a supplementary metric; v0.11 ships Shannon-only. The professor review's Q-PROF-2 answer (no canonical valuation; Shannon defensible) is the literature reading.

### 4.3 Counted-divergence operationalization

The metric extends `WeaknessCheck.hs`'s existing trivial-body enumeration:

```
candidate_count                  = |TrivialBody| extended per §4.3.1 enumeration (Rev 2)
satisfying_candidate_count       = number of candidates passing the contract
distinct_observed_behaviors      = number of equivalence classes over observation set Ω
```

The current `WeaknessCheck.hs` reports `satisfying_candidate_count > 0` as a binary flag (and emits the `spec-weakness` diagnostic). LT-CDP extends the same pipeline to count: the `emitFixpoint` call is made for each trivial candidate; the pass/fail outcome contributes to the count rather than to a binary disjunction.

The behavior-equivalence partition over `Ω` is heuristic — two candidate implementations are *equivalent* iff they agree on every input in `Ω`. The equivalence is observation-set-relative, not semantic. See Risk #1 below.

The corpus-bias question — that small `Ω` collapses equivalence classes and large `Ω` separates them — is **inherent** per the literature reading. Hughes' QuickCheck papers (Claessen-Hughes ICFP 2000; Hughes TFP 2020 §4) treat coverage tracking as discipline for understanding *what the corpus measures*, not as a correction for *what the corpus does not measure*; mutation testing (Andrews-Briand-Labiche ICSE 2005; Offutt 1992 coupling effect) accepts the corpus-dependence empirically without canonical correction; **coverage-guided fuzzing addresses corpus bias through stratified corpora and coverage-of-coverage reporting** (Klees et al. *Evaluating Fuzz Testing* CCS 2018 §3), *not* through metric correction. LT-CDP inherits this stance: scores are *comparable within a single `Ω`*, not directly comparable across different `Ω`s; the trust report's `basis` field per §5 makes `Ω`'s identity auditable, and cross-function score comparison requires same-`Ω` discipline.

### 4.3.1 v0.11 candidate-set enumeration (Rev 2, per the professor review's Gap #3)

The v0.11 trivial-body extension consists of the following candidates, evaluated per contract per emitFixpoint pass. The enumeration is *closed* for v0.11; v0.12+ widens to LLM-generated candidates per [`docs/design/invariant-discovery-review.md §5`](invariant-discovery-review.md).

| Candidate class | Members | Type admissibility |
|---|---|---|
| **Existing `WeaknessCheck.hs` enumerators** | `TrivIdentity` (return input), `TrivConstZero` (return `0`), `TrivConstEmptyStr` (return `""`), `TrivConstTrue` (return `true`), `TrivConstEmptyList` (return `(list)`) | per existing `WeaknessCheck.hs:40-65` |
| **Int constants** | `0`, `1`, `-1`, `42` | functions returning `int` |
| **Bool constants** | `true`, `false` | functions returning `bool` |
| **String constants** | `""`, `"a"` | functions returning `string` |
| **List constants** | empty list of each admitted base type; single-element list with the type's canonical default value | functions returning `list[T]` for admitted `T` |
| **Sum-type constants** | `Success` wrapping each admitted base-type default; `Error "default"` for `Result[T, string]` | functions returning sum types |
| **Pair constants** | pairs of admitted base-type defaults | functions returning `pair[A, B]` |

Total enumeration size: ~12-15 candidates per `int → T` function, scaling roughly by the cardinality of the admitted return-type domain. The list is small but discrete; consumers comparing scores across versions audit the enumeration against this table.

**Score stability across versions.** Because the enumeration is closed, the score for a given function under a fixed contract is reproducible across v0.11 patch releases. v0.12+ expansions will produce score shifts; consumers comparing across-version scores must account for enumeration changes via the `basis` field's `enumeration_version` sub-field (added in v0.12+, not v0.11).

---

## 5. Two-axis assurance report

The trust-report JSON per [`docs/design/critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §3.2 gains the CDP field per function. The current per-function entry shape (post-OBLIG-PBT-3 at v1.1.0) gains a parallel `discriminative_axis` block alongside the existing evidence fields:

```json
{
  "function": "transfer",
  "evidence_axis": {
    "level": "verified",
    "body_faithful": true,
    "prover": "liquid-fixpoint"
  },
  "discriminative_axis": {
    "score": 0.82,
    "basis": "observational-candidate-set",
    "candidate_count": 500,
    "satisfying_candidate_count": 12,
    "distinct_observed_behavior_count": 12,
    "distinguishing_inputs": [
      "(from=A, to=B, amount=1)",
      "(from=A, to=A, amount=10)"
    ],
    "spec_entropy_annotation": "strict",
    "warnings": []
  }
}
```

Key shape decisions:

- **Paired, not collapsed.** Evidence and DP are orthogonal; collapsing into a scalar would erase the four-cell matrix at §1. Downstream consumers that previously read `tier_profile.verified` and treated it as the strong-spec signal now have a strictly more informative pair.
- **`basis`** field names the source of the candidate set (`observational-candidate-set` for the v0.11 trivial-body extension; future values: `llm-generated-candidates`, `mutation-based`, `external-corpus` for v0.12+ extensions).
- **`candidate_count` vs `satisfying_candidate_count`** — the raw inputs to the score formula. Reported alongside the normalized score so consumers can recompute the metric under different normalizations if desired.
- **`distinct_observed_behavior_count`** — the equivalence-class count after partition over `Ω`. Distinct from `satisfying_candidate_count` because multiple candidates may collapse to one observed behavior.
- **`distinguishing_inputs`** — concrete inputs that separate satisfying behaviors from non-satisfying behaviors. Useful for the `--weakness-check`-derived diagnostic that surfaces a low-DP signal to the agent.
- **`spec_entropy_annotation`** — echoes the source `(spec-entropy ...)` annotation so consumers can distinguish low DP (`:strict`, flagged) from low DP (`:intentional`, suppressed by design).
- **`warnings`** — typed diagnostic strings using the enumeration below (Rev 2, per the professor review's Gap #7). The Rev 2 enumeration distinguishes *why* DP is not reported as a numeric score; downstream consumers must distinguish "DP undefined (enumeration too small)" from "DP not measured (def-shell out of v0.11 scope)" to avoid conflating non-applicability with measurement weakness:
  - `"identity-satisfies-post"` — the trivial identity body passes the contract; the spec admits the input-pass-through behavior.
  - `"const-satisfies-post"` — a trivial constant body passes; the spec admits a constant value (often the type's default).
  - `"spec-inconsistent"` — no candidate satisfies the contract and the post-condition carries no verification evidence (DLAsserted or DLTested only). `score` is suppressed; this is a distinct diagnostic from low DP.
  - `"vacuous-over-omega"` — no candidate satisfies the contract, but the post-condition carries DLVerified or DLContractChecked evidence: the spec is provably correct and tight with respect to the §4.3.1 trivial-body enumeration. `score` is suppressed. Consumers should treat this as a strong-spec signal, not a defect. Emitted only when `--trust-report` is active; without it, `"spec-inconsistent"` is used conservatively and a notice is written to stderr.
  - `"enumeration-too-narrow"` — `|B_{T,U,Ω}| ≤ 1`; the observation set yields too few distinct behaviors for the score formula. `score: undefined`; consumers rely on the evidence axis.
  - `"def-shell-out-of-scope"` — the function is `def-shell` (per LT-INV grammar); CDP is not reported on shell-form functions in v0.11. `score: not_measured`; semantically distinct from `undefined`. This case is *not* a measurement weakness — it is an explicit non-applicability per §2 out-of-scope.
  - `"candidates-empty-under-limit"` — no type-compatible candidate from the §4.3.1 enumeration applies (e.g., a function over a type the v0.11 enumeration does not cover). `score: undefined-due-to-enumeration-limit`; v0.12+ widening may close this case.
  - `"over-annotation-warning"` — module-level: ratio of `:intentional` to `:strict` exceeds the configurable threshold (default 30%) per Risk #3.

`tier` and `tier_profile` (v1.1.0) are unchanged; DP is an *orthogonal per-function field*, not a tier_profile member.

---

## 6. Schema delta

`trust_report_version` 1.1.0 → 1.2.0 (additive on the existing v1.1.0 shape). Downstream consumers that ignore `discriminative_axis` continue to work; consumers wanting CDP signal opt in by reading the new block.

The schema additions are additive at every layer:

- New top-level field `discriminative_axis` on the per-function trust entry
- New field shape definition in [`docs/llmll-trust-report.schema.json`](../llmll-trust-report.schema.json)
- `tier_profile` six-Int aggregate at [`LLMLL.md:412`](../../LLMLL.md) is unchanged in shape
- `tier_profile_pre` / `tier_profile_post` (OBLIG-PBT-3 v1.1.0) are unchanged

JSON-AST source schema gets a small addition: the `(spec-entropy ...)` annotation is a new optional field on the contract metadata block. Bundled with LT-INV's `schemaVersion 0.5.0 → 0.6.0` bump rather than carrying its own bump.

---

## 7. Edge cases

1. **A contract with `?proof-required` somewhere in `post`.** Input shape: `(def-shell f [n: int] (post (?proof-required (> result 0))) ...)`. **Expected behavior:** CDP is computed over the *non-proof-required* portion of the contract; the `?proof-required` clause is treated as `true` for satisfaction-counting purposes. The behavior is consistent with the marker's gap-signal semantics — the verifier already treats it as `asserted`, and CDP must be honest that the proof-required clause is gap-signalled, not enforced. **Channel:** trust (the score must report `predicate_form: "predicate-carrying"` or `"leaf"` per LT-PPR alongside the CDP score so consumers can distinguish "the spec is weak because of an explicit gap" from "the spec is weak because the agent wrote a weak spec"). **Citation:** [`LLMLL.md §6:780`](../../LLMLL.md); LT-PPR §5.

2. **An intentionally-permissive contract with `(spec-entropy :intentional)`.** Input shape: `(def-shell cache-lookup ... (post (or (is-ok result) (is-error result))) (spec-entropy :intentional))`. **Expected behavior:** DP is computed (low, near 0.0), reported in the trust report's `discriminative_axis.score` field, and the `spec_entropy_annotation: "intentional"` field is set. No diagnostic is raised. Consumers reading the score can apply their own policy; the annotation distinguishes "low DP by design" from "low DP because the spec is incomplete." **Channel:** trust. **Citation:** [`invariant-discovery-review.md §4.1`](invariant-discovery-review.md); §3 above.

3. **An inconsistent contract** (no behavior satisfies). Input shape: `(def f [n: int] (pre (and (> n 0) (< n 0))) ...)`. **Expected behavior:** `discriminative_axis.score` is undefined; a separate `spec_inconsistent: true` diagnostic fires and lands in the `warnings` field. Distinguished from low DP because inconsistency is a *contract bug*, not a *contract weakness*. The diagnostic surfaces at `--weakness-check` and the obligation report. **Channel:** trust (the inconsistency diagnostic is its own channel; the score field is suppressed rather than zero). **Citation:** §4.1 edge-cases; current `WeaknessCheck.hs` does not surface this case but the extension should.

4. **A `def` function whose contract is entirely outside QF-LIA-enumerable trivial bodies.** Input shape: a contract over refinement-aliased ADT-field flows where no `TrivialBody` enumerator type-checks. **Expected behavior:** `candidate_count` is small or zero; `discriminative_axis.score` reports as `undefined-due-to-enumeration-limit` with a warning in the `warnings` field rather than a raw 1.0 or 0.0. The honest report is "the metric did not have a candidate set to work from"; v0.12+ widens the enumeration to LLM-generated candidates. **Channel:** trust (honest non-applicability signal). **Citation:** [`compiler/src/LLMLL/WeaknessCheck.hs:40-90`](../../compiler/src/LLMLL/WeaknessCheck.hs) — current enumeration scope.

5. **A `def-shell` function whose body uses `?hole`** (still being authored). **Expected behavior:** CDP is computed over the contract; the body's incompleteness is irrelevant (DP is a *spec-strength* metric, not an implementation metric). The score is published. The agent receives signal on the spec quality independent of whether the implementation is complete. **Channel:** trust. **Citation:** [`LLMLL.md §6`](../../LLMLL.md) — holes do not block parse/typecheck.

6. **A contract that admits exactly one observable behavior** (`DP = 1`). Input shape: `(def increment [n: int] (post (= result (+ n 1))) ...)` over an observation set `Ω` where every input produces a distinct `n+1` output. **Expected behavior:** `score: 1.0`, `satisfying_candidate_count: 1`, `distinct_observed_behavior_count: 1`. The maximally-specific case. No diagnostic; the spec is fully discriminative. **Channel:** trust (the report records the ideal-cell signal). **Citation:** §4.1 edge cases.

---

## 8. Verification mapping

- **Channel:** trust (CDP is a new sub-channel of the trust report; not a type or contract obligation).
- **Fragment:** the score computation reuses the existing `WeaknessCheck.hs` pipeline (which calls `emitFixpoint` per [`LLMLL.md §5.3.1:600-613`](../../LLMLL.md)); no new SMT-fragment expansion. The trivial-body enumeration stays QF-LIA-bounded. The behavior-equivalence partition is heuristic over the observation set — *not* a soundness obligation, an *empirical estimate* with provenance.
- **Cite:** [`LLMLL.md §5.3.1:600-613`](../../LLMLL.md) for the trivial-body enumeration boundary; [`LLMLL.md §5.3.5`](../../LLMLL.md) for the verification-matrix scope CDP inherits.

No new SMT obligations are emitted beyond what `--weakness-check` already does. No new fragment expansion. The verifier-side work is bounded by the existing trivial-body-vs-contract check loop.

---

## 9. Affected surface

- [`LLMLL.md`](../../LLMLL.md) — §4.4 (gains the `(spec-entropy ...)` annotation documentation), §5.3.1 (extend to "Spec Weakness Detection and Discriminative Power (CDP-0)" with normative CDP definition added or new §5.3.1a), §5.3.5 verification matrix (most rows: ✅ CDP-applicable; opaque/asserted rows: enumeration-limit warning per Edge 4 above)
- [`compiler/src/LLMLL/WeaknessCheck.hs`](../../compiler/src/LLMLL/WeaknessCheck.hs) — extend trivial-body enumeration to type-compatible candidates over the existing prelude; add equivalence-class counting; emit CDP score per function via a new `computeCDP` function
- [`compiler/src/LLMLL/TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs) — emit `discriminative_axis` field per function in the trust-report JSON
- [`compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs) — parse `(spec-entropy ...)` annotation; new field on `Contract` or sibling annotation type (one of `SpecEntropyStrict`, `SpecEntropyIntentional`, `SpecEntropyUnknown`; default `SpecEntropyStrict` when unannotated)
- [`compiler/src/LLMLL/Parser.hs`](../../compiler/src/LLMLL/Parser.hs), [`compiler/src/LLMLL/ParserJSON.hs`](../../compiler/src/LLMLL/ParserJSON.hs) — parse the new annotation in both frontends
- [`docs/llmll-trust-report.schema.json`](../llmll-trust-report.schema.json) — `trust_report_version 1.1.0 → 1.2.0`; new `discriminative_axis` field shape definition
- [`docs/llmll-ast.schema.json`](../llmll-ast.schema.json) — `(spec-entropy ...)` annotation field added (bundled with LT-INV `schemaVersion 0.5.0 → 0.6.0` bump)
- [`docs/research-track.md:145-151`](../research-track.md) — already retired in Pass 3 of the catch-up branch with cross-reference to v0.11 CDP-0; this proposal closes the cross-reference loop
- [`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md) — v0.11 milestone Implementation Item 2 (LT-CDP) is the authoritative routing surface for this work
- [`docs/design/critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) — DP-FORM-1 and TRUST-DP-1 rows superseded; cross-references to this proposal

---

## 10. Risks and open questions

1. **Behavior-equivalence partition is heuristic and observation-set-dependent.** Severity: high (per [`invariant-discovery-review.md §4.2`](invariant-discovery-review.md)). Classification: verification-ergonomics. Cite: invariant-discovery-review §4.2 — "Two implementations can be semantically different but observationally equivalent on all well-typed inputs." Bite: CDP is an *observational* metric, not a semantic one; for richer types (strings, lists, ADTs) the distinction matters. **Mitigation:** report observation set explicitly via `basis` field per §5 above ("with provenance" requirement). CDP score is meaningful *relative to Ω*, not absolutely; consumers comparing scores across functions or across versions must compare against the same `Ω`. The trust report makes `Ω`'s identity explicit so this is auditable.

2. **Trivial-body enumeration is small.** Severity: medium. Classification: verification-ergonomics. Cite: [`compiler/src/LLMLL/WeaknessCheck.hs:40-65`](../../compiler/src/LLMLL/WeaknessCheck.hs) lists five enumerators today (`TrivIdentity`, `TrivConstZero`, `TrivConstEmptyStr`, `TrivConstTrue`, `TrivConstEmptyList`). Bite: `candidate_count` is bounded by the enumeration; for many contracts, the candidate set is empty and CDP cannot compute. **Mitigation:** v0.11 extends the enumeration to type-compatible candidates over the existing prelude (constants of admitted types: small ints `0`, `1`, `-1`; bools; common strings); v0.12+ widens to LLM-generated candidates per the Phase B item in [`invariant-discovery-review.md §5`](invariant-discovery-review.md). **Empirical confirmation (F-005 post-ship):** the banking-ledger corpus confirms that tight-equality posts (`= result (- a b)`) produce zero-satisfying candidates under the v0.11 enumeration; the `WarnVacuousOverOmega` / `WarnSpecInconsistent` disambiguation (committed with F-005) correctly distinguishes these verified-but-tight specs from genuinely inconsistent contracts, resolving the ambiguity flagged in the original risk statement.

3. **`(spec-entropy :intentional)` annotation can be over-applied to silence diagnostics.** Severity: medium. Classification: scope. Cite: [`invariant-discovery-review.md §4.1`](invariant-discovery-review.md). Bite: agents under pressure to ship may annotate every low-DP contract as intentional, hiding genuine spec weakness behind the suppression. **Mitigation:** `:intentional` annotations are themselves surfaced in the trust report's `spec_entropy_annotation` field (auditable). A high-`:intentional`-density module raises a separate `over-annotation-warning` diagnostic when the ratio of `:intentional` to `:strict` exceeds a configurable threshold (default 30%); the warning is informational, not blocking, but visible to code review. **Self-attestation framing (Rev 2, per the professor review's Gap #5).** `:intentional` is a *self-attestation* channel — the agent declaring the annotation is the same agent whose spec is being measured, and *automated* enforcement cannot do better than the threshold heuristic without a human-audit step. This matches the LH `{-@ assume @-}` precedent (Vazou et al. POPL 2014 §3) and the Rust `#[allow(...)]` precedent (per `crater.rust-lang.org` audit pattern): the social-pressure-against-unjustified-attestations enforcement holds in human-audited code review but does not transfer cleanly to agent-emitted corpora. The 30% threshold is therefore an *abuse-rate* check, not a *per-instance justification* check; per-instance justification requires human review.

4. **CDP-0 is an empirical metric; the §8 empirical gate of LT-INV measures DP-distribution shifts, but DP itself is one of the axes the gate measures.** Severity: low (methodological). Classification: scope. Cite: [`core-shell-inversion-direction.md`](core-shell-inversion-direction.md) §8.1 "Spec-strength distribution" axis. Bite: the gate is partly self-referential — does CDP improve under inversion? CDP itself defines the question. **Mitigation:** baseline DP on the pre-inversion corpus; the gate criterion is *DP distribution shifts in the expected direction* (more `def`-form bodies → expect higher DP because the syntactic guarantee tightens the spec-strength relationship), not absolute thresholds.

5. **Equivalence-class counting is `O(N²)` in the candidate-set size for the naive partition.** Severity: low. Classification: verification-ergonomics. Cite: standard equivalence-class partition algorithms. Bite: at v0.11 candidate-set sizes (10s of candidates per contract), the cost is negligible; at v0.12+ scale (LLM-generated candidates, potentially 100s) the partition cost becomes measurable. **Mitigation:** v0.11 ships the naive partition; v0.12+ adopts a Union-Find-based partition with `O(N α(N))` cost; the implementation switch is local to `WeaknessCheck.hs` and does not affect the spec.

6. **The score formula `1 - log(|⟦S⟧|) / log(|B|)` has a degenerate case when `|B| ≤ 1`.** Severity: low. Classification: spec-strength edge case. Cite: §4.1 edge cases. Bite: a function type so narrow that the observation set yields ≤ 1 distinct behavior makes the formula undefined or trivially 0/1. **Mitigation:** the trust report reports `score: undefined` with `warnings: ["observation-set-too-narrow"]` for `|B_{T,U,Ω}| ≤ 1` cases; consumers ignore the score for such functions and rely on the evidence axis alone.

---

## 11. Open questions for the professor review

**Status (Rev 2):** both questions answered in the Rev 1 professor review at [`contract-discriminative-power-review.md`](contract-discriminative-power-review.md) §"Answers to author-surfaced questions"; the answers are folded into Rev 2 at §4.3 (Q-PROF-1: corpus-bias is inherent; publish-with-provenance is the canonical mitigation; Klees et al. CCS 2018 cited) and §4.2 (Q-PROF-2: no canonical valuation; Shannon defensible on computational and interpretability grounds; Möbius is the lattice-theoretic canonical, deferred to future work). The questions are retained below as the historical record of the Rev 1 → Rev 2 transition.

1. **For the equivalence-class counting in §4.3, is there an established treatment in the property-based-testing literature** (Hughes' QuickCheck papers; Pacheco-Lahiri-Ernst on metamorphic testing; recent work on coverage-guided fuzzing) **of how to define "distinct observed behaviors" when the observation set is partial and the equivalence classes are bound by the test corpus rather than by semantic equality?** The naive read — "two implementations are equivalent iff they agree on Ω" — is observationally correct but exposes the metric to test-corpus bias. Is there a corpus-bias correction the literature recommends, or is the bias inherent and the right move is to publish Ω alongside the score (as proposed)? — *Rev 2 answer: the bias is inherent; the literature does not establish a canonical correction. Hughes (2020) treats coverage as informativeness, not correction. Coverage-guided fuzzing (Klees et al. 2018) addresses corpus bias through stratified corpora and coverage-of-coverage reporting. LT-CDP's publish-with-provenance mitigation is the correct move.*

2. **The lattice-valuation framing in §4.2 places CDP on a subobject lattice over a finite behavior space.** This is the narrower unification the amended critic settled on, declining the full categorical reading (fibrations, graded monads, patch-merge derivation) that the professor had rejected. **Is there a known objection to the narrower framing — particularly to treating "the number of admissible behaviors" as a meaningful valuation on the lattice — that the proposal should address?** The Shannon-style normalization (log-based) is one choice; alternative valuations (linear, polynomial) are also defensible. Does the literature establish a canonical valuation for this kind of finite-observational-equivalence setting? — *Rev 2 answer: no canonical valuation. Three families admissible (logarithmic, linear, Möbius-function). Shannon is defensible on computational and interpretability grounds; the lattice-theoretic canonical is Möbius (Birkhoff Lattice Theory Ch. X §3), deferred to future work on smaller candidate sets where the lattice structure is tractable.*

---

## 12. Companion review

Professor review landed at [`contract-discriminative-power-review.md`](contract-discriminative-power-review.md) (Rev 1, 2026-05-25) as part of the batched four-proposal review turn (LT-INV, LT-CDP, LT-PPR, REF-META-1). Recommendation: `approve with revisions` on seven gaps and two author-question answers, all folded into this Rev 2 inline at the marked "Rev 2" touchpoints (§1 observational-vs-semantic caveat; §2 baseline-first sequencing + C-2 cross-proposal references; §4.2 Shannon-vs-Möbius justification; §4.3 + §4.3.1 explicit candidate-set enumeration + Klees et al. corpus-discipline citation; §5 typed-warnings enumeration; §10 Risk #3 self-attestation framing). The review carried the v0.11 cluster's cross-proposal observations C-1 through C-4; the C-2 settlement landed at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md) (Rev 1, 2026-05-25) as a coordination artifact, referenced from §2 above.

The standalone `contract-discriminative-power-review.md` was folded into the §"Appendix — Professor review log" below and archived to [`docs/archive/professor-reviews/contract-discriminative-power-review.md`](../archive/professor-reviews/contract-discriminative-power-review.md) under DOC-CONSOLIDATE §M2 (doc-lead Pass 10, 2026-05-25).

This proposal promotes the [`docs/research-track.md:145-151`](../research-track.md) row to v0.11 implementation (research-track row retired with cross-reference in Pass 3 of the 2026-05-23 catch-up branch) and supersedes the triage rows DP-FORM-1 and TRUST-DP-1 from [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) §4.

---

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal has been folded into this appendix and the source file archived to `docs/archive/professor-reviews/contract-discriminative-power-review.md`. One line per finding; all resolved in Rev 2 of this proposal.

**Source:** `docs/design/contract-discriminative-power-review.md` at commit `5f31580` (review dated 2026-05-25; reviewer: Lead Consultant for Formal Language Design).

### Gaps (all resolved in Rev 2)

1. **Observational-vs-semantic caveat buried in Risk #1.** Rev 1 framing risked CI gate misinterpretation. Resolved: Rev 2 §1 promotes the caveat to motivation-level, naming the four cells as *interpretable signals* not *spec properties*.
2. **Shannon-vs-alternative-valuation justification absent.** Rev 1 §4.2 ships Shannon without ranking against linear or Möbius. Resolved: Rev 2 §4.2 adds the three-family justification — Shannon defensible on computational + interpretability grounds; Möbius is lattice-canonical, deferred to future work.
3. **Trivial-body enumeration not explicit.** Rev 1 §4.3 said "type-compatible candidates" without naming the set. Resolved: Rev 2 §4.3.1 ships the closed v0.11 candidate-set enumeration.
4. **Corpus-bias literature reading absent.** Rev 1 Risk #1 mitigation correct but uncited. Resolved: Rev 2 §4.3 cites Klees et al. CCS 2018 + Hughes' QuickCheck papers; the bias is inherent per the literature, publish-with-provenance is the canonical mitigation.
5. **`:intentional` self-attestation framing not named.** Rev 1 Risk #3 had the mitigation without naming the trust-model. Resolved: Rev 2 Risk #3 adds the self-attestation paragraph with LH `{-@ assume @-}` + Rust `#[allow(...)]` precedents.
6. **LT-INV empirical-gate self-reference.** Rev 1 §2 sequencing had CDP-0 ship concurrent with the LT-INV gate run. Resolved: Rev 2 §2 baseline-first sequencing commits CDP-0 to publish a v0.10-baseline DP report *before* the LT-INV §8 gate measurement runs.
7. **`def-shell` blindness vs `undefined` indistinguishable.** Rev 1 §5 `warnings` field conflated non-applicability with measurement weakness. Resolved: Rev 2 §5 ships the typed-warnings enumeration distinguishing `def-shell-out-of-scope` (not measured) from `enumeration-too-narrow` (undefined) plus four other typed states.

### Open questions (both resolved in Rev 2)

- **Q-PROF-1.** Corpus-bias correction in PBT literature. Resolved: Rev 2 §4.3 — the bias is inherent; Klees et al. CCS 2018 corpus-discipline approach is the canonical mitigation; LT-CDP publish-with-provenance is correct.
- **Q-PROF-2.** Lattice valuation choice — Shannon vs alternatives. Resolved: Rev 2 §4.2 — three families admissible (logarithmic, linear, Möbius). Shannon defensible on computational + interpretability grounds; Möbius lattice-canonical, deferred.

### Cross-proposal observations (C-1 through C-4)

The review carried the v0.11 cluster's cross-proposal observations; full text in `refinement-metatheory-of-record-proposal.md` §"Appendix — Professor review log" / Cross-proposal observations subsection. C-2 (cross-proposal rollback discipline) settled at [`v0.11-cross-proposal-rollback-discipline.md`](v0.11-cross-proposal-rollback-discipline.md); §2 Rev 2 sequencing references the C-2 settlement for Outcome-1/2 shipping conditions.

### Overall assessment (recorded)

The review recommended `approve with revisions` on seven gaps and two author-question answers. Rev 2 (settled 2026-05-25) carries each resolution inline at the cited §-references above. The standalone `contract-discriminative-power-review.md` is archived; this appendix is the in-proposal pointer.
