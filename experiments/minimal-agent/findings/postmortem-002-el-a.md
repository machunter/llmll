# Postmortem 002 — First Run (post-EL-A, v0.10.2)

**Source:** `experiments/minimal-agent/runs/20260511T005026Z/` — 9 attempts × 1 experiment
**Compiler version:** `llmll 0.10.2` (bare-PATH verified)
**Harness SHA at run time:** `008495f` (post-E3-revert, pre-F-301-loosen)
**Date:** 2026-05-11
**Manifest:** `manifest.top-models-el-a-e002.json`
**Resolution:** F-301 loosened in commit `af35927` (now on `main`). See "Resolution" section below.

---

## Headline finding

`REQUIRED_FEATURES[2]` over-strictly demanded explicit `Promise[T]` and `Result[T, e]` type annotations that v0.10.2's `?delegate-async` / `await` inference rules elide. **All 9 top-tier attempts graded F** despite producing structurally valid solutions: every attempt successfully used `?delegate-async`, `await`, `match` on `Success`/`Error` constructors, `?proof-required` on `summarize-amounts.post`, and produced `proof_required_ceiling_accepted: 1`. But `feature_scan.missing_required = ["Promise", "Result-type"]` fired deterministically because the agents wrote the inner type at the delegation site (per `LLMLL.md §11.2` inference rules) and let the compiler infer the wrappers. The grade-F gate fires before the grade-A path is reached, so the correctly-emitted `?proof-required` marker on `summarize-amounts.post` was silently masked. **The pattern mirrors F-201 (post-EL-A 001): harness expectations diverge from the language's actual ergonomics, demoting structurally-correct solutions.** EL-A's E1 (F-302) and E2 (F-303) again work as designed in production — E2 specifically surfaces the discrepancy (`Result-pattern: true`, `Result-type: false`) that diagnoses the issue precisely. **F-301 resolved in `af35927`**: `Promise` removed from `REQUIRED_FEATURES[2]`, `Result-type` replaced with `["Result-type", "Result-pattern"]` disjunction in both 002 and 003.

## Sample composition

| Model | Attempts | Grades | Notable |
|---|---|---|---|
| claude-opus-4-7 | 3 | F / F / F | All emit `?proof-required` on post; all miss explicit Promise / Result-type annotations |
| gemini-3-pro-preview | 3 | F / F / F | Same pattern |
| gpt-5.5 | 3 | F / F / F | Same pattern |
| **Total** | **9** | **0 A, 0 B, 0 C, 9 F** | All F via `missing_required: ["Promise", "Result-type"]` |

Agent durations: ~351s (claude-opus-4-7 try01), similar across panel — 002 is ~2× longer wall-clock per attempt than 001 (matches the ★★☆ vs ★☆☆ difficulty rating).

## Verified findings

### F-301. `REQUIRED_FEATURES[2]` over-strict — demanded inferred type annotations

**Priority:** High
**Consumer:** user
**Status:** Resolved by loosening in commit `af35927`.

#### Evidence

`runs/20260511T005026Z/20260511T005026Z-claude-opus-4-7-try01-of-03-e002/evaluation.json`:

```json
{
  "quality_grade": "F",
  "feature_scan": {
    "required": ["def-interface", "delegate", "delegate-async", "await",
                 "DelegationError", "Promise", "Result-type", "proof-required",
                 "def-invariant", "check", "pre", "post"],
    "found": {
      "delegate-async": true, "await": true, "DelegationError": true,
      "proof-required": true, "Result-pattern": true,
      "Promise": false, "Result-type": false, "Result-helpers": false
    },
    "missing_required": ["Promise", "Result-type"]
  },
  "contract_assessment": {
    "expected_total": 2,
    "accepted_total": 2,
    "all_required_contracts_met": true,
    "proof_required_ceiling_accepted": 1,
    "items": [{
      "function": "summarize-amounts", "side": "post",
      "expected_proof_required": true, "proof_required_marker": true,
      "accepted": true, "reason": "accepted asserted proof-required ceiling"
    }]
  }
}
```

All 9 attempts produced `missing_required: ["Promise", "Result-type"]` with the same downstream-F mechanism. 9/9 also produced `proof_required_ceiling_accepted: 1` on `summarize-amounts.post`, meaning the grade-A path was satisfied at the contract layer but blocked by the feature gate.

#### Why we saw what we saw

Per `LLMLL.md §11.2` inference rules (added in v0.10.2 by LT-A D2.1):

```
?delegate-async @A "desc" -> T              ⊢  Promise[T]
await e : Promise[T]                         ⊢  Result[T, DelegationError]
```

Agent solutions for 002 write `?delegate-async @data-agent "..." -> list[int]` (the inner type `T`). The compiler infers `Promise[list[int]]` automatically — agents do **not** write `Promise[list[int]]` anywhere in the AST. Similarly, `(await chart-future)` returns `Result[list[int], DelegationError]` per inference — agents do **not** write that annotation; they just `match` on `(Success v)` / `(Error e)` arms. The language deliberately elides these wrappers; the harness was demanding them anyway.

The grade flow: `quality_grade(report)` at `evaluate_run.py:719-720` returns `"F"` immediately when `feature_scan.missing_required` is non-empty. The grade-A path via `proof_required_ceiling_accepted` (which the agents correctly satisfied on `summarize-amounts.post`) is never reached. Agents correctly read §13.8's pedagogical hook ("`?proof-required` on postconditions the verifier cannot discharge") — `summarize-amounts.post` involves summing arbitrary-length lists (nonlinear reasoning) — and emitted the marker. They were penalized for not also writing annotations the language doesn't require.

#### Resolution

F-301 resolved in commit `af35927`:

1. **`Promise` removed from `REQUIRED_FEATURES[2]`** — inferred from `?delegate-async`; the presence of `delegate-async: true` in `found` already signals that Promise is in play. Requiring an additional explicit annotation is asking for redundant code.
2. **`Result-type` replaced with `["Result-type", "Result-pattern"]` disjunction** in both 002 and 003. Either an explicit `kind:"result"` type annotation OR a match arm with `kind:"constructor"` + `constructor ∈ {Success, Error}` is sufficient evidence of Result usage. The E2 three-signal split makes this disjunction precise.
3. **001 unchanged** — the experiment spec explicitly mandates `Result[string, string]` as `login-handler`'s return type (`001-two-agent-auth.md:23`), so requiring `Result-type` is structurally correct for 001.
4. **Mechanism**: new `feature_present` / `feature_label` helpers in `evaluate_run.py` support spec items that are either strings or list disjunctions. `missing_required` formats disjunctions as `"A | B"`-joined strings, preserving downstream-tooling compatibility (`compare_runs.py`, `render_summary`).
5. **Regression guards**: 10 new tests in `test_evaluate_run.py` (`FeaturePresentAndLabelTests` + `RequiredFeaturesShapeTests`) lock the loosening shape so future edits can't accidentally drop the disjunction or re-add `Promise`.

#### Acceptance

After the loosening commit `af35927`, a re-run of the 9-attempt panel against the post-loosening evaluator is expected to produce ≥1 grade A (the `proof_required_ceiling_accepted` path agents already satisfy on `summarize-amounts.post` is unblocked). Not gated on this postmortem; a future re-run can verify.

---

### F-302. EL-A E1 call-graph signal works in async context (positive validation)

**Priority:** Defence-in-depth
**Consumer:** user

#### Evidence

Same evaluation.json, `test_assessment.delegation_dependent_checks`:

```json
[
  {
    "label": "awaiting-failed-delegation-produces-error",
    "delegation_dependent": true,
    "reasons": ["call graph reaches delegation", "delegation-related label"]
  }
]
```

The async-error-recovery check (per `002-async-report-pipeline.md:44`: "Awaiting a failed delegation produces an Error variant") is correctly classified as delegation-dependent via *both* the call-graph signal AND the label-regex fallback. E1's traversal works for async-shaped delegations (`hole-delegate-async` and `await` are in the `DELEGATION_KINDS` set), not just sync `?delegate`. Same pattern across all 9 attempts.

#### Why we saw what we saw

Per EL-A's E1 design, the call-graph traversal from each check body extracts callee names via `extract_callee_names`, looks them up in `build_function_table(solution_ast)`, recursively traverses their bodies, and flags if any reached node has `kind ∈ {hole-delegate, hole-delegate-async, await}`. 002's checks transitively reach `await` and `?delegate-async` via function calls → call graph reaches delegation. Cycle-safe; conservative.

#### Implication

Routing: **user**. Validates EL-A's E1 generalization from sync to async delegation in production. No change needed.

#### Acceptance

Confirmed.

---

### F-303. EL-A E2 three-signal split enables the F-301 diagnosis

**Priority:** Defence-in-depth (positive validation)
**Consumer:** user

#### Evidence

Same evaluation.json, `feature_scan.found`:

```json
{
  "Result-type": false,
  "Result-helpers": false,
  "Result-pattern": true,
  "Result": false
}
```

`Result-pattern: true` is the precise signal that the agent uses Result via match arms without writing an explicit `Result[T, e]` type annotation. **Pre-EL-A's conflated `Result` signal would have flipped `true` here** (via the now-removed `constructor in {Success, Error}` path) and the F-301 issue would have been invisible — solutions would have graded as if Result-type was satisfied, and the harness's strictness gap would have remained latent. **E2's split is what makes F-301 diagnosable**, which makes the F-301 loosening (F-301 resolution above) defensible.

#### Implication

Routing: **user**. Validates E2 in production for the second time (after F-203 on the 001 EL-A re-validation). The split converts a previously-conflated signal into actionable diagnostics. The F-301 loosening uses the split directly: `Result-pattern` is what `["Result-type", "Result-pattern"]` accepts as an alternative to explicit annotation.

#### Acceptance

Confirmed.

---

### F-304. `?proof-required` correctly emitted on `summarize-amounts.post` across the panel

**Priority:** Defence-in-depth (positive validation)
**Consumer:** user

#### Evidence

Same evaluation.json, `contract_assessment.items[1]`:

```json
{
  "function": "summarize-amounts",
  "side": "post",
  "expected_proof_required": true,
  "proof_required_marker": true,
  "accepted": true,
  "reason": "accepted asserted proof-required ceiling"
}
```

All 9 attempts have `proof_required_ceiling_accepted: 1` on the post clause. The v0.10.2 §13.8 pedagogical hook (LT-A D3) is converting into agent behavior **when the marker is structurally meaningful** — i.e., on a postcondition whose body involves nonlinear reasoning (summing arbitrary-length lists). This is exactly the contrast against the failed 001 case (F-201): when the harness's expectation matches the spec's intended use of `?proof-required`, agents emit it correctly.

#### Implication

Routing: **user**. Validates the v0.10.2 LT-A pedagogy + `CONTRACT_EXPECTATIONS[2].summarize-amounts.post.proof_required: True` together. Confirms the F-201 conclusion: `?proof-required` on POST clauses (where verifier-discharge-failure is structural) works; on PRE clauses (where it doesn't apply) it's noise.

#### Acceptance

Confirmed. Predicts grade-A reachability on 002 *after* F-301 loosening — which has now landed in `af35927`.

---

## Withdrawn items

- **Primary hypothesis (≥1 attempt produces grade A on 002):** falsified at run time by the feature_scan F-301 gate firing before the grade-A path is reached. The contract-level grade-A path (via `?proof-required` on `summarize-amounts.post`) was correctly satisfied by all 9 attempts; the harness over-strictness masked the success. Resolved by `af35927`.
- **Secondary prediction ("E1 call-graph signal expected to fire on async-error-recovery check"):** confirmed (F-302).
- **Tertiary prediction ("Result-helpers + Result-pattern + Result-type all fire on most solutions"):** partially confirmed — `Result-pattern: true` across panel, but `Result-helpers: false` and `Result-type: false` because agents in 002 don't use `(ok …)`/`(err …)` (the inferred Result values come from `await`, not from agent-side construction) and don't write explicit Result-type annotations. The signal split made this precise rather than conflated.

## Null results

- **Async-PBT limitation re-confirmation:** `test_assessment.raw.skipped: 3` and `effective_skipped: 2` (with 1 excluded as delegation-dependent). Confirms the v0.10.2-documented async PBT limitation: check bodies touching `await` resolve to `PBTSkipped`. Not a finding per se — expected behavior.

## Resolution

F-301 is **resolved** in commit `af35927`. EL-A's E1 (F-302) and E2 (F-303) remain on `main` as validated. `main` head after loosening: `af35927`.

The grade-A reachability on 002 is now unblocked at the harness layer; whether agents reach it depends on whether they emit `?proof-required` on `summarize-amounts.post` — which 9/9 already did. A future re-run is predicted to land mostly grade A.

## Open meta-question (not a finding; for future direction)

Both F-201 (E3 over-restriction on 001 pre) and F-301 (REQUIRED_FEATURES[2] over-restriction on 002 inferred annotations) fit the same pattern: **harness expectations lagging language ergonomics**. After both corrections, the top-tier-model panel on 001+002 is likely to produce near-flat grade distributions (mostly A or B). Discrimination has shifted: the interesting question is no longer "did the agent write working LLMLL code" (top-tier does it consistently) but "did the agent produce a *good* solution by some richer metric." The current harness doesn't measure that. Worth a separate batch-design pass at some point — cross-language framework, structural-quality heuristics, harder experiments — but out of scope for this postmortem.

## Priority matrix

| # | Finding | Consumer | Priority | Resolution |
|---|---|---|---|---|
| **F-301** | `REQUIRED_FEATURES[2]` over-strict | user | High | **Resolved** in `af35927` (loosen) |
| **F-302** | E1 call-graph works in async context | user | Defence-in-depth | None — confirmed |
| **F-303** | E2 three-signal enables F-301 diagnosis | user | Defence-in-depth | None — confirmed |
| **F-304** | `?proof-required` correctly emitted on post | user | Defence-in-depth | None — confirmed |

## Per-consumer scoped files written

Single-file integrated postmortem; no per-consumer fragments. The F-301 loosening was the only normative action surfaced and is already executed.
