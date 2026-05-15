# Phase-3 Problem-Shape Audit

**Status:** Pre-launch pin (pre-registration discipline; Control #7a, `docs/design/language-comparison-experiments.md`).
**Author:** Language-team.
**Date opened:** 2026-05-15.
**Methodology-bundle predecessor commit:** `7a9b379` (`docs(design): Phase-3 methodology-discipline bundle + experiment-lead backlog registration`). The methodology surface — Control #7a, `prediction_match` field, §"Open Design Questions" #3 resolution — landed at that commit and is the procedural anchor this audit operationalizes.
**Scope:** Per-problem predicted verification-path engagement for the Phase-3 launch matrix's three problems (`001-hangman`, `002-bank-ledger`, `003-rate-limiter`) per the recommended first milestone at `docs/design/language-comparison-experiments.md:594-606`.

## Immutability protocol

Predictions in this file are immutable from the matrix-launch commit. Revisions made *before* matrix launch are in-place edits — the audit is not yet pinned. Revisions made *after* matrix launch are recorded as dated addenda appended at file end, following the `## Addendum N (YYYY-MM-DD) — <title>` voice established at `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md`; the original predictions are *not* edited in place. Post-hoc analysis cites the audit at the launch-commit hash, not at HEAD.

The immutability property — that registered predictions cannot be silently retuned to fit observed data — is the discipline that distinguishes pre-registration from re-narratable expectation (Nosek, Ebersole, DeHaven & Mellor, *The preregistration revolution*, PNAS 115(11):2600–2606, 2018). The launch-commit hash is recorded here as an in-place edit immediately before launch is authorized; post-launch revisions never re-pin the launch-commit field.

**Launch-commit hash:** *(unfilled until matrix launch; in-place edit at launch time records the hash here)*.

## Pin bindings

Per-problem prediction bindings differ by what exists on disk at audit-authoring time:

- **`002-bank-ledger`** — binds to the testkit problem statement at `experiments/repair-loop/problems/002-bank-ledger.md` (67 lines; commit `7a9b379` parent state). This is the only Phase-3-style testkit problem statement on disk; the binding is direct and full.
- **`001-hangman`** — binds to the testkit problem statement at `experiments/repair-loop/problems/001-hangman.md` (commit `24ad6a4` state). Authored at the Phase-3 bootstrap as an additive sharpening of the design-doc sketch at `docs/design/language-comparison-experiments.md:253-301` (commit `7a9b379` state); no material divergence found by language-team comparison 2026-05-15 (Required state, Required API, Behavioral Requirements, and LLMLL Assurance Requirements all preserved; additive content: explicit QF-LIA Classification section, explicit lower-bound `post apply-guess` clause, sharper API contract wording, explicit H3 expectation). Sketch-bound predictions stand without revision.
- **`003-rate-limiter`** — binds to the testkit problem statement at `experiments/repair-loop/problems/003-rate-limiter.md` (commit `24ad6a4` state). Authored at the Phase-3 bootstrap as an additive sharpening of the design-doc sketch at `docs/design/language-comparison-experiments.md:354-401` (commit `7a9b379` state); no material divergence found by language-team comparison 2026-05-15 (Required state, Required API, Behavioral Requirements, and LLMLL Assurance Requirements all preserved; additive content: explicit QF-LIA Classification section, sharper refill-semantics description with explicit `last_tick`-advance-on-deny clarification, stronger directive against silent assertion on the refill nonlinearity, explicit H3 expectation). Sketch-bound predictions stand without revision.

Testkit files for `001-hangman` and `003-rate-limiter` were authored at bootstrap commit `24ad6a4` (2026-05-15). Language-team comparison against the design-doc sketches found no material divergence on either problem (both files are additive sharpenings — Required state, API, Behavioral Requirements, and LLMLL Assurance Requirements preserved; new content limited to explicit QF-LIA Classification sections, sharper API / semantics wording, and explicit H3 expectations). Pin bindings have been rebound in place to the testkit files under the pre-launch in-place-edit window; no addendum was required. The per-problem prediction bands below stand without revision. If the testkit files are subsequently revised between this in-place rebind and matrix launch, divergence handling reverts to the original protocol: dated addendum at file end re-stating affected predictions, never an in-place edit.

**Calibration-informed-extrapolation caveat (002 only).** The `002-bank-ledger` predictions are *informed by* Phase-2 Addendum-19 empirical data on gemini-default × c01 / c02 / c03 / c01-subjects / c02-subjects (`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 19, 2026-05-15). Predictions about Phase-3 cells on agents (Claude, Codex) that did not run Phase-2 are unseen-data predictions; predictions about gemini-default Phase-3 cells on `002-bank-ledger` are informed extrapolation rather than blind pre-registration. Post-hoc analysis on the gemini-default-002 cells is read with this caveat. The audit's predictions for the unseen agent rotation are the primary pre-registration claim on this problem; the gemini-default cells function as a sanity-check anchor.

The `001-hangman` and `003-rate-limiter` predictions are blind pre-registration — no Phase-2 data exists on those problems.

---

## 002 — Bank Ledger

**Binding:** `experiments/repair-loop/problems/002-bank-ledger.md` (commit `7a9b379` parent state).
**Calibration anchor:** `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 19.

### Canonical body shape (predicted)

Map-backed ledger; `transfer` returns `Result (ledger) string`; `balance` returns `Result int string`; `total-balance` computes the conservation invariant via structural recursion over the account map (typically represented as a `list[pair[string, int]]`). Three body-shape families are expected within this problem, mirroring the Phase-2 c01 / c02 / c03 distribution: shallow-product observer-of-operation (c01-shape); deep-product with `?proof-required`-in-post on conservation (c02-shape); map-based plumbing with explicit `list-filter` / `list-prepend` over a normalized representation (c03-shape).

### Predicted contract shape

- `pre transfer (> amount 0)` — QF-LIA, auto-discharged per `LLMLL.md §5.3.5`.
- `post transfer (= (total-balance result.0) (total-balance ledger))` — quantified-over-map; escapes QF-LIA per `LLMLL.md §13.8`; predicted to land as `?proof-required` or, more frequently, as `asserted` under the current v0.10.6 fragment.
- `post transfer (= (balance result.0 from-account) (- (balance ledger from-account) amount))` — QF-LIA if `balance` is treated as uninterpreted on this lookup; map-quantified otherwise; likely lands as `asserted` under v0.10.6.

### OBLIG-PBT-4 engagement

Multi-callee metamorphic-relation idiom dominant — "operation preserves observable property" structurally requires the property body to mention both the operation (`transfer`) and the observer (`total-balance` or `balance`). Per `LLMLL.md §4.4.5` PBT-Lift-Annotated rule and the multi-callee fallback at `§4.4.5:470-480`, lifting to `tier_profile_post.tested ≥ 1` on these properties requires `:subjects [transfer total-balance]`-shape annotation. Singleton-head-position properties (single-function on `balance` or `total-balance` alone) also predicted but minority.

### Fragment classification

- `pre`-side contracts: **QF-LIA**, auto-discharged by liquid-fixpoint per `LLMLL.md §5.3.3`.
- `post`-side conservation properties: **nonlinear or quantified-over-map**; escapes QF-LIA per `LLMLL.md §13.8`; routes to `asserted` or `?proof-required` per `§5.3.5`.
- Map-lookup invariants: outside QF-LIA per `LLMLL.md §13.8`; testkit problem statement at `experiments/repair-loop/problems/002-bank-ledger.md:43,63` explicitly directs use of `?proof-required`.

### `letrec` + `:decreases` engagement

Predicted: yes, on `total-balance` (structural recursion over the account map). Predicted engagement rate: ≥70% of LLMLL cells.

### Multi-callee writeback guard

Predicted: **will fire** on unannotated transfer-preserves-total-balance properties. Phase-2 Addendum-19 empirical: 12/12 c01 PBTPassed properties hit this guard under no-`:subjects` conditions.

### Sharp falsifiable predictions

Recommended-first-milestone Phase-3 shape (`docs/design/language-comparison-experiments.md:594-606`): 3 agents × 3 tries per agent = 9 LLMLL cells on `002-bank-ledger`. Predictions stated as per-cell rates; absolute counts scale with the eventually-launched matrix size.

1. **Multi-callee `(check)` emission rate ≥ 80%** — ≥7/9 LLMLL cells emit at least one multi-callee `(check)` property whose body mentions both `transfer` and one of `total-balance` / `balance` / `has-account?`.
2. **`:subjects` annotation rate 30–60% (under S2 default)** — across the 3 agents (Claude / Codex / Gemini), the fraction of LLMLL cells emitting at least one `:subjects [...]` annotation on a multi-callee property falls in this band. Variance band is wide because OBLIG-PBT-4 is recent (shipped 2026-05-14 in v0.10.6) and cross-agent priors on the keyword are unknown.
3. **`tier_profile_post.tested ≥ 1` rate 18–48%** — bounded above by (`:subjects` rate) × (Addendum-19 lift-success rate ~60–80% under QC variance). Predicted band: 18–48% of LLMLL cells.
4. **`?proof-required` markers on conservation properties ≥ 50%** — ≥5/9 LLMLL cells emit at least one `?proof-required` marker on a `post`-clause referencing conservation or map-lookup invariants.
5. **`Cred(R) = true` rate 0–20%** — R6d's universal-`asserted` rejection bites hard on this problem family; agents are predicted to leave conservation properties at `asserted` tier rather than discharge them.

---

## 001 — Hangman

**Binding:** `experiments/repair-loop/problems/001-hangman.md` (commit `24ad6a4` state). Rebound from design-doc sketch at `docs/design/language-comparison-experiments.md:253-301` (commit `7a9b379` state) in place 2026-05-15; no material divergence. See §"Pin bindings" header for the comparison summary.

### Canonical body shape (predicted)

Pure-state game logic; ADT for game status (`playing` | `won` | `lost`); list-of-letters for the guessed set; struct `{ secret, guessed, remaining, status }`; case-insensitive character comparison via `string-to-lower` or analog. Game-state transitions are pure functions over the struct.

### Predicted contract shape

- `post initialize-game (= (remaining result) 6)` — QF-LIA, auto-discharged per `LLMLL.md §5.3.5`.
- `post apply-guess (<= (remaining result) (remaining state))` — QF-LIA, auto-discharged.
- `post apply-guess (>= (remaining result) (- (remaining state) 1))` — QF-LIA, auto-discharged.
- Repeated-guess invariance ("same letter does not double-decrement remaining attempts") — likely expressed quantifier-style or as a `(check ...)` block over guessed-set membership; if expressed as a `post`-clause, escapes QF-LIA and lands `?proof-required`.

### OBLIG-PBT-4 engagement

Singleton-head-position dominant. Properties on `apply-guess` (monotonicity of remaining attempts; lower-bound on remaining) are unary-callee. Multi-callee `(check)` rate predicted low — this problem lacks a strong conservation invariant comparable to 002's `total-balance`.

### Fragment classification

- Integer-attempt-counter contracts: **QF-LIA**, auto-discharged.
- String-membership for letter-in-secret and guessed-set: outside QF-LIA fragment (string reasoning is not in the v0.10.6 SMT scope). Predicted to be expressed as `(check)` blocks rather than `post` clauses; if attempted as `post`, lands `?proof-required`.

### `letrec` + `:decreases` engagement

Predicted: yes, on letter-revealing logic and guessed-letters list traversal. Predicted engagement rate: ≥50% of LLMLL cells.

### Multi-callee writeback guard

Predicted: unlikely to fire. Most emitted properties are singleton-head-position on `apply-guess`.

### Sharp falsifiable predictions

n = 9 LLMLL cells (3 agents × 3 tries) under recommended-first-milestone shape.

1. **Singleton-head-position `post` clauses on `apply-guess` rate ≥ 70%** — ≥7/9 LLMLL cells emit at least one `post`-clause on `apply-guess` expressing remaining-attempts monotonicity or lower-bound.
2. **Multi-callee `(check)` rate < 30%** — ≤2/9 LLMLL cells emit multi-callee `(check)` properties.
3. **`tier_profile_post.tested ≥ 1` rate 40–60%** — higher than 002 because the multi-callee writeback guard fires less often on this problem's natural body shape.
4. **`?proof-required` markers ≤ 20%** — ≤2/9 LLMLL cells emit `?proof-required` markers; concentrated on repeated-guess-invariance if expressed quantifier-style.
5. **`letrec` + `:decreases` engagement ≥ 50%** — ≥5/9 LLMLL cells engage structural recursion on letter-revealing logic.
6. **`Cred(R) = true` rate 20–50%** — higher than 002 because QF-LIA contracts on integer attempt counters auto-discharge under liquid-fixpoint; the dominant `post`-shape is in-fragment.

---

## 003 — Token Bucket Rate Limiter

**Binding:** `experiments/repair-loop/problems/003-rate-limiter.md` (commit `24ad6a4` state). Rebound from design-doc sketch at `docs/design/language-comparison-experiments.md:354-401` (commit `7a9b379` state) in place 2026-05-15; no material divergence. See §"Pin bindings" header for the comparison summary.

### Canonical body shape (predicted)

State-machine; bounded counter; deterministic tick-step; struct `{ capacity, tokens, refill_rate, last_tick }`. `allow` is a single-tick-step computation with no recursion. `tokens` is a pure projection.

### Predicted contract shape

- `pre new-limiter (and (> capacity 0) (>= refill-rate 0))` — QF-LIA, auto-discharged per `LLMLL.md §5.3.5`.
- `post allow (and (>= (tokens result.0) 0) (<= (tokens result.0) capacity))` — QF-LIA on bounds (when `capacity` is treated as a refinement-bound parameter); auto-discharged or near-auto-discharged.
- Refill arithmetic: `(* (- tick last-tick) refill-rate)` — **nonlinear** (product of two non-literal integers); escapes QF-LIA per `LLMLL.md §5.3.5`. Predicted to land as `?proof-required`, as a runtime assertion with `weakness-ok` per `LLMLL.md §4.5`, or as a solver-fallback `asserted` tier.
- Same-tick-no-refill invariant: QF-LIA-expressible if encoded as `(= last-tick tick) → (= (tokens result.0) (- (tokens state) 1))`; predicted auto-discharged when so encoded.

### OBLIG-PBT-4 engagement

Singleton-head-position dominant. Properties on `allow` (token-count bounds, single-request behavior) are unary-callee. State-machine surface does not produce metamorphic-relation properties naturally.

### Fragment classification

- Capacity / token-count bounds: **QF-LIA**, auto-discharged.
- Refill multiplication: **nonlinear**, escapes QF-LIA per `LLMLL.md §5.3.5`. Routes to `?proof-required` or `weakness-ok` per `§4.5`.
- Same-tick-no-refill invariant: **QF-LIA** when encoded with the tick-equality guard; auto-discharged.

### `letrec` + `:decreases` engagement

Predicted: unlikely. `allow` is non-recursive (single tick-step computation). Predicted engagement rate: <20% of LLMLL cells.

### Multi-callee writeback guard

Predicted: rare. State-machine surface doesn't produce metamorphic-relation properties naturally.

### Sharp falsifiable predictions

n = 9 LLMLL cells (3 agents × 3 tries) under recommended-first-milestone shape.

1. **Refill-nonlinearity surface rate ≥ 90%** — ≥8/9 LLMLL cells surface the refill multiplication as either a `?proof-required` marker, a `weakness-ok` clause, or a solver-fallback `asserted` tier on the relevant `post`-clause.
2. **Singleton-head-position `post` clauses on `allow` (bounds) rate ≥ 80%** — ≥7/9 LLMLL cells emit at least one `post`-clause on `allow` expressing token-count bounds.
3. **`:subjects` engagement rate < 20%** — ≤2/9 LLMLL cells use `:subjects` annotation. The multi-callee writeback guard rarely engages on this problem.
4. **`tier_profile_post.tested ≥ 1` rate 30–50%** — similar to 001 but lower because the dominant `post`-shape is partially nonlinear-blocked.
5. **Nonlinear-fragment escape surfacing rate ≥ 80%** — ≥7/9 LLMLL cells surface the refill nonlinearity somewhere in the trust report or as a contract clause.
6. **`Cred(R) = true` rate 10–30%** — lower than 001 because the refill nonlinearity leaves at least one `asserted` clause per cell with high probability.

---

## Cross-cutting predictions

These predictions apply to all three problems and are tracked separately from per-problem predictions to support cross-problem analysis.

### CC-1 — R5a match-arm canonical-form risk *(retrospective vacate, 2026-05-15)*

**State at audit pin (corrected from authoring time):** R5a — the canonicalization of `LLMLL.md §3.3` informal match-arm examples from sibling-form to wrapped-form — already shipped at commit `ecdf42f` (`docs(spec): correct match-arm informal examples in LLMLL.md §3.3 / §9 / §13.5 (R5a)`) as part of v0.10.3's spec pedagogy corrections (2026-05-12; roadmap at `docs/compiler-team-roadmap.md:290`), predating this audit's predecessor commit `7a9b379`. The original authoring of CC-1 read `experiments/repair-loop/findings/language-team.md` §LT-C as a still-open recommended-option; that status entry was stale relative to the spec and has been retrospectively closed in the same turn that this CC-1 revision lands. `LLMLL.md §3.3` at HEAD uses wrapped-form throughout (e.g., `((Red) "stop")` and `((Start word) ...)` on lines 213-220); the matched `§17` grammar and the shipping `examples/` all use wrapped-form. There is no sibling-form-vs-wrapped-form contamination risk for Phase 3 attributable to spec drift.

**Prediction:** Empirically vacated. Predicted contamination rate attributable to `§3.3` informal-example drift: 0% across all three problems, across all agents. Falsification would require an `LLMLL.md §3.3` surface to revert to sibling-form between this audit pin and matrix launch (no such revert is in the queue or in the roadmap).

**Channel:** apparatus (parser-front-end). The CC-1 entry is preserved in this audit as a paper trail of the original authoring mistake — readers of the launch-commit-pinned audit should see that this risk was at one point flagged, was then verified false during a `/documentation-lead` consultation, and is documented as such in the audit's pre-launch in-place-edit state. The lesson is recorded in `experiments/repair-loop/findings/language-team.md` §LT-C status update at 2026-05-15.

### CC-2 — Documentation-surface asymmetry (S8 launch-scope)

**State at audit pin:** S8 launch-scope per `docs/design/language-comparison-experiments.md` §"Open Design Questions" #3 Resolution — LLMLL cells receive full `LLMLL.md`; Python / Go cells receive short target instructions.

**Prediction:** LLMLL's H1-Assurance signal (per-target `tier_profile_post` analog) is measurably higher than Python / Go's behavioral-test pass-rate analog *on `002-bank-ledger`*, where conservation-invariant verification has no straightforward Python / Go analog; **roughly comparable** on `001-hangman`, where the problem is QF-LIA-shallow and behavioral tests catch most regressions; **LLMLL-disadvantaged or neutral** on `003-rate-limiter`, where the refill nonlinearity blocks LLMLL's strongest verification path while Python / Go assertions are unaffected.

The A3 dose-response side-arm (`experiments/language-comparison-backlog.md` B-2) becomes most informative if launched on `002-bank-ledger`, where the asymmetric-documentation hypothesis has the largest predicted differential.

**Channel:** apparatus. Falsification: any of the three per-problem H1-Assurance directional predictions fails to hold.

### CC-3 — `prediction_match` field expected distribution

Across the predicted 27 LLMLL cells (3 problems × 3 agents × 3 tries), with the audit pinned at the launch commit, the predicted per-cell `prediction_match` distribution under post-hoc human comparison is:

- **`match`**: 60–85%. Most LLMLL cells emit body shapes the audit has named; deviations are within the predicted variance bands.
- **`divergence`**: 10–30%. The audit's variance bands are wide on `:subjects` rate (002) and on R5a contamination rate; cells outside those bands are recorded as `divergence` and excluded from primary H1-Assurance aggregation per `docs/design/language-comparison-experiments.md` §"Reporting Output".
- **`unaudited`**: 5–15%. Cells whose verification-path engagement was not named in this audit at all (a body shape the audit's per-problem section did not predict).

If the realized `divergence` rate exceeds 30% across the matrix, the audit's variance bands were under-stated and the post-hoc analysis records this as a calibration finding in a dated addendum.

**Channel:** apparatus. Falsification: the realized distribution lies outside the predicted bands on more than one of the three values.

---

## Out-of-scope notes

- **Per-problem prediction *for problems not in the launch matrix*.** `004-todo-cli`, `005-password-reset-tokens`, `006-csv-sales-aggregator` (sketched at `docs/design/language-comparison-experiments.md:405-548`) are not in the recommended first milestone and are not audited here. If the experiment-lead substitutes one of these for `001-hangman` or `003-rate-limiter` before launch, audit predictions for the substitute land as a same-turn audit extension (in-place, pre-launch); after launch, as a dated addendum.
- **Audit-vs-observed *comparison logic*.** Per `experiments/language-comparison-backlog.md` B-1 scope, the comparison is human post-hoc judgment until the cross-language harness grows audit-parsing automation. The audit's predictions are stated sharply enough that human judgment can adjudicate `match` / `divergence` / `unaudited` reliably; automation is a deferred sub-item not in this audit's scope.
- **Multi-axis prediction interactions.** The audit predicts per-axis rates (e.g., `:subjects` rate on 002, `?proof-required` rate on 003) independently; multivariate interactions are not pre-stated. Post-hoc analysis on the matrix may surface joint patterns the audit does not name; those are recorded as `divergence` on the affected cells and discussed in prose, not pre-coded as numeric joint predictions.

---

## Predecessor and cross-references

- **Methodology bundle predecessor commit:** `7a9b379` (`docs/design/language-comparison-experiments.md` Control #7a + `prediction_match` field spec + §"Open Design Questions" #3 Resolution; `experiments/language-comparison-backlog.md` B-1 + B-2).
- **Calibration anchor:** `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 19 (2026-05-15).
- **Consumer references (existing):**
  - `docs/design/language-comparison-experiments.md` §"Experimental Controls" #7a — names this file as the audit's home.
  - `docs/design/language-comparison-experiments.md` §"Reporting Output" — names this file as the `prediction_match` field's pinned-commit referent.
  - `experiments/language-comparison-backlog.md` B-1 — names this file as the upstream artifact the comparison logic binds to.
- **Open downstream item:** `docs/design/INDEX.md` should gain a row for this file (rubric: "Experimental Methodology" or appended to "Verification & Soundness"). Routes through `documentation-lead` after this audit lands; not a same-turn surface.
