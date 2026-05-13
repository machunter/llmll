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
