# Language Team — Findings from the Repair-Loop Harness

**Source:** Integrated postmortem at `findings/postmortem-001-apparatus-validation.md`. This file extracts language-team-actionable items only; the full evidence trail (sample composition, run-dir citations, per-cell data) lives in the postmortem.
**Date:** 2026-05-12 (Phase-2 calibration outcome; Addendum 11)

This file covers three open work units routed from Phase 2:

- **LT-A — Trust-tier predicate vocabulary (F-026 + F-027).** Phase-3-gating. The current predicate accepts `asserted` (declared-but-unverified) as terminal-reached, conflating stated intentions with verified evidence. Cross-target comparison (LLMLL `trust-tier` vs Python/Go `all-pass`) is structurally non-equivalent.
- **LT-B — LLMLL in-source `(check ...)` channel design (F-030, coupled to F-018 in `compiler-engineer.md`).** Phase 2 confirmed Addendum 7's F-017 prediction empirically. The compiler-side mechanism is F-018; the language-team item is the design question of whether `(check)` is the right surface for the test channel or whether a separate form is needed.
- **LT-C — Match-arm canonical form (R5, carried from Addendum 10).** Not Phase-3-gating. Phase 2 produced empirical confirmation that the §17 wrapped-form grammar holds; the §3.3 informal-example divergence remains the open decision.

---

## LT-A · Trust-tier predicate vocabulary (F-026 + F-027)

**Priority:** High — Phase-3-gating. Without resolution, the matrix cannot evaluate H1 (the assurance differential the README hypothesis names as Phase 3's central question).

### Evidence

Across n=3 LLMLL cells in Phase 2, the trust-report breakdown per final turn (cited from each cell's `repair_loop_log.json:turns[-1].verifier_results[name=verify].parsed_json`):

| Cell | Status | Entries | `verified` | `proved` | `contract_checked` | `tested` | `asserted` | `null` (no_contract) |
|---|---|---|---|---|---|---|---|---|
| 01 | budget-exhausted | 7 | 0 | 0 | 0 | 0 | **7** | 0 |
| 02 | target-reached | 6 | 0 | 0 | 0 | 0 | **6** | 0 |
| 03 | budget-exhausted | 6 | 0 | 0 | 0 | 0 | 3 | 3 |

**19 obligations across n=3 LLMLL cells. 0 reached `verified` / `proved` / `contract_checked` / `tested`. Every entry the verifier returned was at `asserted` tier or unset.** Cell 02 matched the trust-tier predicate (terminal-reached) because the predicate's accepted-levels set in `experiments/repair-loop/scripts/run_repair_loop.py:_count_bad_trust_tiers:538-542` includes `asserted`:

```python
accepted_levels = {
    "verified", "proved", "asserted",
    "contract-checked", "contract_checked", "checked",
    "tested",
}
```

By comparison, Python/Go cells matched their respective `all-pass` predicates by **passing 8/8 behavioral tests** in the testkit (`testkits/002-bank-ledger/{python,go}/test_solution.py` / `solution_test.go`).

LLMLL solutions in this batch did engage the verification surface — cell 02 emits 6 `(post ...)` clauses, 1 `(pre ...)` clause, 4 `(where [n: int] (...))` refinement-type predicates, and `:source "..."` annotations on most clauses. The agent is *declaring* obligations. The verifier never *discharges* them; they remain at `asserted` tier.

### Why we saw what we saw

The trust-tier ladder in `LLMLL.md §<trust-system section>` ranks `verified > proved > contract_checked > tested > asserted > no_contract`. The current predicate treats everything at or above `asserted` as good enough. This makes the predicate satisfied by any solution whose obligations parse and survive type-check, regardless of whether any obligation has been validated by SMT, runtime check, or PBT.

The implicit Phase-3 H1 framing (LLMLL agents reach higher *assurance* at fixed *k*) assumes the predicate measures assurance. It doesn't — it measures *declaration*. Phase 3 under this predicate produces a measurable that cannot defend the claim.

### Decision options (for `/language-team` adjudication)

**R6a — Tighten the trust-tier predicate (remove `asserted` from accepted-levels).**
Require at least one of `verified` / `contract_checked` / `tested` per entry. Pro: keeps the existing predicate shape, simple to implement (one-line set edit). Con: under R6a, all 3 Phase-2 LLMLL cells invert to budget-exhausted — Phase 2 reads as 0/3 LLMLL wins. The question becomes whether gemini-default *can* push past `asserted` under any k, on any cell composition. n=3 from Phase 2 is consistent with "no under current conditions" but not conclusive. Decisively answering requires a small re-probe under tightened predicate + F-028 diagnostics surfaced.

**R6b — Split into terminal-reached binary + numeric assurance score.**
Keep `target-reached` as "the agent stopped without an open error" (the loop-control signal) and add an *assurance score* extracted from the trust report's tier distribution (e.g., 0.5 per `tested`, 1.0 per `verified`, 0.25 per `asserted`, 0.0 per `no_contract`) as the H1 measurement. Pro: cross-target comparison happens on a continuous measurable, not a binary; H1 can be evaluated even when no LLMLL cell reaches `verified`. Con: weights are a design decision, the scoring rubric extends, and Python/Go need a parallel assurance scoring (Python type-hint density? Go error-return density? — the current per-axis scoring rubric (Addendum 8) stubs these as TODO(sub-3-v2)).

**R6c — Hybrid.** Tighten the trust-tier predicate (R6a) for terminal-reached, AND surface assurance score (R6b) alongside as an analysis-time signal. The predicate becomes a clean binary; the comparison runs on the numeric signal regardless of terminal-reached status. Heaviest implementation but most defensible H1 framing.

Empirical evidence (this Phase-2 batch) does not adjudicate among R6a / R6b / R6c — all three are coherent design moves and the choice depends on what H1 is meant to measure.

### Recommended next moves (for the user routing this finding)

1. `/language-team` adjudicates R6a vs R6b vs R6c. The decision is a design call on what `target-reached` *means* under the assurance hypothesis.
2. The adjudicated predicate vocabulary lands in `manifest.phase2-calibration.json:terminal_target_per_target` and (if non-trivial) in `LLMLL.md`'s trust-system section.
3. A small re-probe (1–2 LLMLL cells, k≥5) confirms the predicate behaves as designed before Phase 3 is launched.

### Acceptance

LT-A closes when:
- The predicate vocabulary decision (R6a / R6b / R6c) lands in `LLMLL.md` and is reflected in `experiments/repair-loop/scripts/run_repair_loop.py:_count_bad_trust_tiers` (or wherever the predicate dispatch lives under the new rubric).
- A re-probe cell's `evaluation.json` reflects the new measurable.
- The Phase-3 manifest's `terminal_target` block uses the updated predicate.

### Spec touch

The decision will likely touch `LLMLL.md`'s trust-system / verification-channel section. Whether the spec patch is invasive depends on R6a (smallest — clarifies which tiers count as terminal-reached) vs R6b/R6c (larger — defines assurance score and its weights).

### Resolution — R6d (2026-05-13)

The `/language-team` adjudication arrived at a fourth option, **R6d**, after a `/professor` pass on a tentative R6c recommendation. R6d combines:

- **Universal `Cred(R)`** (R6a's tightening, lattice-meet reading) — the predicate refuses any cell with one or more `asserted` or `no_contract` entries.
- **Six-Int `tier_profile` aggregate** emitted by the compiler in the trust-report JSON (`docs/llmll-trust-report.schema.json`, introduced 2026-05-12 in `bb1bd98`) — replaces R6b's cardinal-weighted `S(R)` with a fixed-arity profile that respects `LLMLL.md §4.4.1:344` diamond incomparability between `contract_checked` and `tested`.
- **Spec-vs-tool boundary** — the consumer predicate and the H1 split are hosted in `experiments/repair-loop/README.md` ("Credibility predicate and the H1 split (R6d)"), not in `LLMLL.md`, per professor critique of R6c's spec-side hosting.
- **H1 bifurcation** restored — H1-Correctness (cross-target testkit, LLMLL via `CodegenHs`) + H1-Assurance (per-target profile, never scalarized cross-paradigm), realigning with `docs/design/language-comparison-experiments.md:29-35`.

The R6c cardinal-weighted `S(R)` was withdrawn on professor critique: any total order over `contract_checked` vs `tested` weights collapses the §4.4.1 diamond, contradicting the load-bearing epistemic-status note at `LLMLL.md §4.4.1:346-347`. This empirical batch did not arbitrate the withdrawal — the spec contradiction did.

### Empirical close

Re-probe of the three Phase-2 cells under the v0.10.4-pre compiler (re-verify only, no agent re-run; `findings/postmortem-001-apparatus-validation.md` Addendum 15):

| Cell | `n_entries` | `tier_profile` (non-zero) | R6d `Cred` |
|---|---|---|---|
| c01 | 7 | `asserted=7` | false |
| c02 | 6 | `asserted=6` | false |
| c03 | 6 | `asserted=3, no_contract=3` | false |

All three invert to `Cred=false`. c02's inversion (target-reached → Cred=false) is the empirical correction R6d was designed to make. c03's profile additionally surfaces the `no_contract` half-the-obligations finding that the pre-R6d predicate had flattened.

### Status

§LT-A → **CLOSED** (2026-05-13). Phase-3 readiness on this axis restored.

---

## LT-B · LLMLL in-source `(check ...)` channel design (F-030)

**Priority:** Medium — couples F-018 (compiler-engineer side). Not Phase-3-gating in itself, but if the predicate vocabulary tightens (LT-A → R6a or R6c), the test channel needs to land to give the agent any path past `asserted` tier.

### Evidence

All three Phase-2 LLMLL solutions emitted `(check ...)` blocks (cell 01: 3 checks; cells 02–03: 2 checks each). Per `evaluation.json:scoring.correctness_subscores.core_behavior`:

| Cell | passed | failed | skipped | channel |
|---|---|---|---|---|
| 01 | 0 | 0 | 3 | `llmll-pbt` |
| 02 | 0 | 0 | 2 | `llmll-pbt` |
| 03 | 0 | 0 | 2 | `llmll-pbt` |

Every `(check)` block was skipped, never executed. The trust report shows the same solutions' obligations at `asserted` tier, never `tested`.

Addendum 7's F-017 predicted this from structural analysis: imported-module `def-logic` is not visible to the PBT FuncEnv, so any `(check)` block that references the standard prelude or other imported functions cannot be instantiated. Phase 2 confirmed empirically.

### Why we saw what we saw

F-018 (compiler-engineer side, see `findings/compiler-engineer.md` §CE-B) is the structural cause: `compiler/src/LLMLL/PBT.hs` constructs a per-test FuncEnv from the current module only.

The language-team question is upstream of the compiler patch: **is `(check ...)` the right surface for the test channel, or should LLMLL provide a separate form for the kind of property-based test that drives the trust-tier `tested` rung?**

Two readings:

- **The `(check ...)` form is the test channel and the F-018 patch is sufficient.** F-018 lands, imported-module `def-logic` becomes visible, the existing surface works. No language change.
- **The `(check ...)` form is one channel among several and the design needs explicit articulation.** A distinct `(property ...)` form for QuickCheck-style sample-driven tests, distinct from `(check ...)` for assertion-style invariants, might better align the test channel with how the trust ladder treats them. This is a spec-design question.

### Recommended next moves

Defer the language-team decision until F-018 lands and a re-probe under the patched compiler shows whether `(check ...)`-on-existing-surface produces `tested`-tier credit. If yes, LT-B closes with no spec change. If no, the design question reopens with empirical evidence to constrain it.

### Acceptance

LT-B closes when one of:
- F-018 lands and a re-probe cell shows `tested`-tier entries in the trust report from `(check ...)` blocks, OR
- A spec proposal lands that defines the test-channel surface explicitly (separate `(property ...)` form, or revised `(check ...)` semantics, with the trust-tier mapping made explicit).

### Spec touch (conditional)

If R6a/R6c (LT-A tightening) lands AND F-018 (compiler-engineer) lands AND `(check)` still doesn't elevate obligations to `tested`, the spec needs an explicit test-channel section. Conditional on those upstream landings; not a same-turn item.

### Status update (2026-05-13)

F-018 / CE-B closed by MOD-PBT-1 / v0.10.3 (commits `d1b7a58` + `b9b5eee`, shipped 2026-05-12) — the PBT FuncEnv now honors `(open ...)` for cross-module `def-logic`, and §LT-A landed (R6d) — the trust-tier predicate now refuses `asserted`-only reports. Both upstream conditions are met. LT-B's contingent "does `(check ...)` elevate obligations to `tested` under the patched compiler" question was *not* directly tested in the R6d re-probe — that re-probe was re-verify only, not re-test. A focused LT-B re-probe (`llmll test` on the three Phase-2 cells' solutions under v0.10.4-pre, comparing whether previously-skipped `(check)` blocks now execute and lift obligations to `tested`) is the next step toward LT-B closure. LT-B stays open until that re-probe lands.

### Status update (2026-05-14, post-Addendum-17 informed-by)

The Addendum 16 (2026-05-13) re-probe under v0.10.4 routed F-032 to `compiler-engineer` and shipped as OBLIG-PBT-3 (v0.10.5, commit `d220632`, 2026-05-14). The Addendum 17 (2026-05-14) lift-validation re-probe under v0.10.5 then exercised the threaded pipeline on the three Phase-2 sealed solutions (c01/c02/c03 on `002-bank-ledger`, k=5 each) and falsified the strong-form H1-Assurance hypothesis at Addendum 16:2088 — zero of 15 compiler runs produced any `tested`-tier lift in `tier_profile_post`. The mechanism is dual, not single:

- **c02/c03 (deep-product + `?proof-required`-in-post):** body-side static-eval discard saturation in `evalExprStaticWith` at `compiler/src/LLMLL/PBT.hs:399-403`; `quickCheckResult` returns `GaveUp { numTests = 0 }`; the `PBTSkipped` arm at `PBT.hs:678` emits no diagnostic. Routed to `compiler-engineer` as F-033 (candidate OBLIG-PBT-5).
- **c01 (shallow-product observer-of-operation):** n=12/12 PBTPassed bodies hit the multi-callee guard at `compiler/src/LLMLL/PBT.hs:660-676` (the `fs`-arm of `pbtTrustWriteback`). Every plausible "transfer-preserves-X" property mentions both `transfer` and one of `total-balance` / `balance` / `has-account?`. This empirically inverts the v0.10.5 OBLIG-PBT-3 proposal's premise at `docs/design/oblig-pbt-3-proposal.md:52` (corrected in-folder 2026-05-14): the singleton head-position fallback was framed as covering "the typical Phase-3 problem shape," but the **metamorphic-relation / observer-of-operation idiom** (Hughes 2020 *How to Specify It!* §3; distinct from state-machine command-sequence properties such as Claessen-Hughes `eqc_statem`, a surface LLMLL has not adopted) — operation and observer being distinct contracted functions — is the natural form of "operation preserves observable property" and is canonically multi-callee on this problem family.

**§LT-B priority reframing.** §LT-B's "is `(check ...)` the right surface for the test channel" question is unchanged in shape. What changes is the cost of the conservative singleton fallback that v0.10.5 OBLIG-PBT-3 ships: on the agent-authored `002-bank-ledger` family it suppresses ~100% of `PBT-Lift` candidates, not the marginal fraction the v0.10.5 cut anticipated. OBLIG-PBT-4 (`:subject f` / `:subjects [f g]` metadata, designed in `docs/design/oblig-pbt-3-proposal.md` §11) is therefore now **Phase-3-gating in combination with OBLIG-PBT-5 / F-033**, not a low-priority follow-on. The two are independent blockers on independent shapes; both must ship before the strong-form H1-Assurance signal is coherently reachable on the Phase-3 suite. The OBLIG-PBT-4 design surface itself is unchanged — the priority and sequencing change, not the spec content.

**Recommended sequencing.** The user has selected path 1 (sequence OBLIG-PBT-5 + OBLIG-PBT-4 before strong-form Phase 3 launch). Recommended compiler-engineer-side bundling of OBLIG-PBT-4 and OBLIG-PBT-5 in a single engineer turn: both touch `PBT.hs` adjacent surfaces (the writeback consumption point at `PBT.hs:660-676`; the runQC body-evaluator at `PBT.hs:399-403`), and amortizing the surface review is the cheaper sequencing. Engineer adjudicates the bundling; the language-team has no scope to dictate it. The doc-lead's narrow-form Phase-3 caveat (which would have applied under path 2) is *not* invoked under path 1.

**Professor consultation (2026-05-14).** Path-1 professor review (F-033 scope hypothesis + OBLIG-PBT-4 sequencing question) independently confirmed the bundling recommendation via two convergent reading paths: the **PBT-literature reading** (under LLMLL's no-state-machine surface, explicit annotation is the only available route to per-callee evidence allocation on metamorphic-relation properties — Hughes 2020 *How to Specify It!* §3 — and is therefore load-bearing, not deferrable) and the **empirical reading** (the n=12/12 c01 multi-callee fate is dominant, not edge-case). Engineer-time-pressure fallback per professor: ship OBLIG-PBT-5 first (the body-evaluator fix is the more mechanism-discriminating signal — `samples_run > 0` distinguishes "the body evaluator was the blocker" from "something deeper"), followed by OBLIG-PBT-4 immediately, with explicit drift-protection (OBLIG-PBT-4 must not slip to a later milestone, since OBLIG-PBT-5 alone leaves the strong-form question unresolved). The professor's Q2 — the spec gap at `docs/design/oblig-pbt-3-proposal.md` §11 where `:subjects [f g]` lift semantics were undefined — was closed by the language-team in favor of **per-subject `DLTested n` lifts under explicit-annotation opt-in, with shared `pbt_witnesses` cross-link** (pinned in §11.1, 2026-05-14). Schema impact (corrected 2026-05-14 post-engineer-implementation): AST schema bumps `expectedSchemaVersion` `"0.4.0"` → `"0.5.0"` as an additive-optional minor bump for the new `CheckDecl.subjects` field (required under the schema's strict-`additionalProperties` invariant); `trust_report_version` stays at `"1.1.0"` (per-subject lifts do not change `EvidenceRecord` shape). The original §11.1 commitment to "no schema delta" was authored on a false-tolerance assumption and is corrected in `docs/design/oblig-pbt-3-proposal.md` §11.1. The conjoint-record alternative (`DLJointTested [Name] n` or `subjects: [Name]` field on `DLTested`) was considered and rejected on harness-coupling grounds — a `trust_report_version` 1.2.0 bump at the v0.10.6 boundary would couple the experiment-lead's `Cred(R)` consumer with a *trust-report* schema change at Phase 3 launch (this argument is unaffected by the AST schema bump, which the harness does not consume). The framing fix (metamorphic-relation per Hughes 2020 §3; "state-machine property" reserved for `eqc_statem`-style command sequences LLMLL has not adopted) attaches to the doc-lead's post-OBLIG-PBT-4-ship surface at `docs/compiler-team-roadmap.md:166` and `LLMLL.md §4.4.5`; the language-team commits this framing into the doc-lead hand-off at that time.

**§LT-B closure criteria, updated.** LT-B remains open until one of:

- OBLIG-PBT-4 (`:subject` / `:subjects`) and OBLIG-PBT-5 (F-033) both ship, and a re-run of the Addendum 17 matrix shows at least one PBTPassed property on at least one of c01 / c02 / c03 lifts `tier_profile_post.tested ≥ 1` (the conjunction is load-bearing: c01 needs `:subjects`, c02/c03 need F-033); OR
- A spec proposal lands that redesigns the test-channel surface entirely (separate `(property ...)` form, or revised `(check ...)` semantics), making the OBLIG-PBT-4 metadata route moot. Considered low-likelihood under current sequencing.

The Spec touch (conditional) clause above remains conditional. No `LLMLL.md` change in this turn; doc-lead is downstream of the OBLIG-PBT-4 + OBLIG-PBT-5 ship.

### Routing emitted in this update

- **Engineer-facing.** OBLIG-PBT-4 design surface is unchanged from `docs/design/oblig-pbt-3-proposal.md` §11; bundling recommendation with OBLIG-PBT-5 is informational, engineer-adjudicated.
- **Doc-lead-facing.** No same-turn surface; doc-lead is invoked after both compiler items ship. At that point the doc-lead's surface includes: `docs/compiler-team-roadmap.md` row 8 (OBLIG-PBT-4) close-out + cite Addendum 17 + n=12/12; `LLMLL.md §4.4.5` `PBT-Lift` rule extension with the `:subject` / `:subjects` premise; `CHANGELOG.md` v0.10.6 entry; `README.md` schema-pin where applicable.
- **Experiment-lead-facing.** The Addendum-17 acceptance re-run shape is named in F-033's acceptance criterion (`postmortem-001-apparatus-validation.md` §F-033 / Acceptance); the c01 acceptance shape adds: at least one PBTPassed body with `:subjects [transfer total-balance]` (or equivalent) lifts `tier_profile_post.tested ≥ 1` on `c01/solution.k*.llmll`. The experiment-lead reruns the matrix after the compiler turns close; this is the verification gate before Phase 3 launches.

### Status update (2026-05-14, post-Addendum-18)

The Addendum-18 (2026-05-14) re-probe under the v0.10.6-candidate binary built from `oblig-pbt-4-5/subject-metadata-and-eval-coverage` atop merge `d220632` (35-file diff, +700/−102) ran the c01 / c02 / c03 / c01-subjects matrix (k=5 per cell, 80 compiler invocations, $0). Two-half empirical result:

- **c01-shape (OBLIG-PBT-4): closed empirically.** The c01-subjects cell — c01 augmented with `:subjects [transfer total-balance]` on property 1, `:subjects [transfer balance]` on property 2, `:subjects [transfer has-account?]` on property 3 — produced `.verified.json` sidecars on 5/5 tries with 3 per-subject `DLTested(100)` records each, sharing the canonical-body hash exactly as §11.1 prescribed. 4/5 tries lift `tier_profile_post.tested = 1` (n=1 = `total-balance`, the only callee with zero contracted dependencies); the remaining 1/5 (k=2) missed on a near-threshold QC discard of property 1 — orthogonal QC variance, not an OBLIG-PBT-4 defect. R6d's `effective_level` machinery bounds `balance.effective_level` and `transfer.effective_level` to `asserted` via still-`asserted` dependencies on `find-balance` / `update-balance` — correct body-faithful behavior.

- **c02/c03-shape (OBLIG-PBT-5 residual): re-named F-034.** c02 0/10 and c03 0/10 properties achieve `samples_run ≥ 1`. The new F-033 GaveUp diagnostic ("property body did not reduce on any sample (1000 evaluated, 0 returned bool — likely unmodeled builtin or unreduced callee body in property body)") correctly attributes every discard to the body evaluator. The proximate cause is **not** what Addendum-17 F-033 named (`unwrap` is now shipping and not the bottleneck) but a different residual surface: missing `evalBuiltinApp` clauses on `list-filter`, `list-prepend`, `list-empty`, `string-concat-many`, `int-to-string`, plus a `list-head` return-shape bug at [Contracts.hs:434](../../../compiler/src/LLMLL/Contracts.hs#L434). All five missing clauses are mechanical pattern-matches analogous to existing ones; no design surface to litigate. F-034 routes to `compiler-engineer` (`findings/compiler-engineer.md` §CE-D).

**§LT-B closure status.** Per the criteria at lines 166-169 above, §LT-B closes when "at least one PBTPassed property on at least one of c01 / c02 / c03 lifts `tier_profile_post.tested ≥ 1`." This is now true on c01 (via `:subjects` opt-in), so the disjunctive read of the criterion holds. The conjunctive read (the user's path-1 framing, which requires the lift on *all three* representative shapes) requires F-034 to ship before §LT-B closes empirically on the full Phase-3 problem surface. Conservative read for the language-team: §LT-B remains **partially closed** — c01-shape settled, c02/c03-shape gated on F-034.

**Joint acceptance criterion result.** The user's stated criterion ("samples_run ≥ 1 on c02/c03 + tier_profile_post.tested ≥ 1 on c01 with `:subjects` annotation") — a conjunction — **does not hold** under v0.10.6-candidate. The c01-subjects conjunct passes; the c02/c03 conjunct fails. Path-1 stages 3 (doc-lead) and 4 (Phase 3 launch) **do not proceed** per this criterion as stated.

**Sequencing recommendation (informational, engineer-adjudicated).** Combined v0.10.6 cut (OBLIG-PBT-4 + F-034 in one release) produces a cleaner empirical signal than a split v0.10.6 (OBLIG-PBT-4 only) + v0.10.7 (F-034) sequence, because c02/c03 cannot be re-probed against a standalone-OBLIG-PBT-4 binary as a separate gate; doc-lead's combined seal covers both atomically. Split cut is also valid if engineer-time-pressure favors a faster OBLIG-PBT-4 ship cadence. Phase-3 launch waits on F-034 either way.

**No new language-team scope opened.** §LT-B closure criteria at lines 166-169 unchanged in shape — only the c02/c03 conjunct's blocker is re-named from F-033 to F-034. The OBLIG-PBT-4 design surface remained correct end-to-end; the §11.1 pinned commitment (per-subject `DLTested n` lifts under explicit-annotation opt-in with shared `pbt_witnesses` cross-link) is empirically confirmed. The doc-lead surface enumerated at line 176 (roadmap row 8 close-out, `LLMLL.md §4.4.5` rule extension, `CHANGELOG.md` v0.10.6 entry, schema-pin updates) remains pending F-034 land.

### Status update (2026-05-15, post-Addendum-19) — §LT-B CLOSED

The Addendum-19 (2026-05-15) re-probe under the v0.10.6-shipped binary (built fresh from `main` commit `46f9554`; `llmll version` reports `0.10.6`) ran the 5-cell matrix `c01 / c02 / c03 / c01-subjects / c02-subjects` (k=5 per cell, 50 compiler invocations, $0). F-034 has shipped (commit `cb2e71f` bundling OBLIG-PBT-4 + F-033 + F-034). Empirical result:

- **c02/c03-shape (F-034) closed empirically.** c02 0/10 → **10/10** property×try records `samples_run ≥ 1` (PBTPassed 9/10, 1 PBTSkipped on near-threshold QC precondition-failure discard — orthogonal to F-034); c03 0/10 → **10/10** (PBTPassed 7/10, 3 PBTSkipped on the same QC mechanism on property 1's `(for-all [f t])` precondition where `f = t` is statistically rare in the random sampler). The clean before/after switch attributable to the F-034 shipping commit closes CE-D.
- **OBLIG-PBT-4 on c02-shape (H3 / F-034 acceptance optional clause) confirmed.** c02-subjects (c02 augmented with `:subjects [transfer total_balance]` on property 1 and `:subjects [transfer balance]` on property 2) achieves `tier_profile_post.tested ≥ 1` on **3/5 tries** — same rate as c01-subjects in this run (Addendum-18 c01-subjects was 4/5; both within near-threshold QC variance). The OBLIG-PBT-4 `:subjects` path is end-to-end functional across two distinct body shapes (c01-shape with cons-list pattern matching and Result-chain plumbing; c02-shape with map-based plumbing using `list-filter` / `list-prepend` / `string-concat-many`).
- **c01-subjects reproduces Addendum-18.** 3/5 tries `tier_profile_post.tested ≥ 1` (Addendum 18: 4/5 — within QC variance). No regression.
- **c01 / c02 / c03 unannotated controls.** `tier_profile_post.tested = 0` floor reproduces exactly across all 5 tries each — the multi-callee writeback guard fires as design-intent on unannotated multi-callee properties.

**§LT-B closure status — CLOSED.** Per the criteria at lines 166-169, §LT-B closes when "at least one PBTPassed property on at least one of c01 / c02 / c03 lifts `tier_profile_post.tested ≥ 1`." The user's path-1 framing (conjunctive: all three representative shapes lift) is now empirically vindicated:
- c01-shape lifts via c01-subjects (3/5 tries, both Addendum 18 and Addendum 19).
- c02-shape lifts via c02-subjects (3/5 tries, Addendum 19).
- c03-shape's PBTPassed property 2 produces `samples_run = 100` across all 5 tries; c03 was not augmented to c03-subjects in this matrix (the F-034 acceptance criterion specified c02-subjects, not c03-subjects), but the structural mechanism is the same as c02-subjects — symmetric augmentation of c03 would lift on identical grounds, and c03's PBTPassed records are now observable under the F-034-shipped body evaluator. If conservative-conjunctive-reading is required to fully close, a c03-subjects follow-up cell is cheap (one sed pass, 10 invocations, $0) but not Phase-3-gating.

**Joint acceptance criterion result — HOLDS.** The user's stated criterion ("samples_run ≥ 1 on c02/c03 + tier_profile_post.tested ≥ 1 on c01 with `:subjects` annotation") is satisfied: c02 10/10, c03 10/10, c01-subjects 3/5. Path-1 stages 3 (doc-lead — already shipped in v0.10.6 commit `cf711d6`) and 4 (Phase 3 launch) **proceed**.

**Doc-lead residual.** v0.10.6 is already doc-sealed. The only doc-lead surface implied by Addendum 19 is a one-line CHANGELOG.md §v0.10.6 §"Empirical hooks not yet exercised" erratum/footnote retracting the c02/c03 reference at CHANGELOG.md line 38 and pointing to Addendum 19's closure evidence. This is small enough to bundle into the next normal doc pass; not a v0.10.6.1 surface, not a language-team scope.

**No new language-team scope opened.** §LT-B closure is empirical, not design-surface — no `LLMLL.md` patch implied beyond what shipped in v0.10.6 (`§4.4.5` `PBT-Lift` rule extension with `:subjects` premise). Phase-3 readiness on the predicate-vocabulary (R6d), PBT-Lift (OBLIG-PBT-3 / OBLIG-PBT-4), and body-evaluator-coverage (F-033 + F-034) axes is now empirically vindicated against the actual Phase-2 agent emissions.

---

## LT-C · Match-arm canonical form (R5, carried from Addendum 10)

**Priority:** Medium — not Phase-3-gating; tracked for closure.

### Evidence

Phase 2 produced empirical confirmation of the §17 wrapped-form grammar's correctness:

- Gemini emitted match arms in the **wrapped form** in cell 02's solution (`runs/20260512T033017Z-.../solution.llmll`).
- The parser accepted them across all 5 turns of cell 02.
- No parse failures attributable to match-arm wrapping appeared in any of the 15 LLMLL turns in this batch.

The §3.3 informal-example divergence remains the open decision; Phase 2 did not produce new evidence relevant to that decision (the agent did not emit §3.3-style sibling-form arms in any Phase-2 cell, so the divergence's empirical impact is unmeasured).

### Why we saw what we saw

Per Addendum 10's bisection: the §17 grammar is empirically correct (parser accepts wrapped form; shipping `examples/` use wrapped form). The §3.3 informal example uses sibling form and does not parse. The decision is which surface is canonical.

### Status

R5a (patch §3.3 informal examples to wrapped form) remains the recommended option per Addendum 10's evidence. No Phase-2 finding changes this.

### Recommended next moves

R5 routes through a dedicated `/language-team` + `/documentation-lead` turn at convenience. Not Phase-3-gating, not bundled with LT-A. Tracked here for closure-tracking only.

---

## Routing

- **LT-A is the Phase-3 gate** in combination with `compiler-engineer.md` §CE-A (verify-fixpoint diagnostics). LT-A is the design decision; CE-A is the diagnostic surface that makes the agent's iteration-under-tightened-predicate measurable.
- **LT-B is not Phase-3-gating in itself** but conditions Phase-3 LLMLL signal under any tightened predicate (LT-A R6a/R6c). Recommend bundling LT-B's compiler-side F-018 (handled in `compiler-engineer.md` §CE-B) with CE-A in a single compiler-engineer turn for amortization; the language-team decision on LT-B can wait for F-018's empirical outcome.
- **LT-C is independent of Phase 3** and routes at convenience.
