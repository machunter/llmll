# Postmortem 001 — Post-EL-A Re-validation

**Source:** `experiments/minimal-agent/runs/20260510T235111Z/` — 9 attempts × 1 experiment
**Compiler version:** `llmll 0.10.2` (bare-PATH verified)
**Harness SHA at run time:** `78d4de4` (post-EL-A merge, pre-E3-revert)
**Date:** 2026-05-10
**Manifest:** `manifest.top-models-el-a-e001.json`
**Resolution:** E3 reverted in commit `008495f` (now on `main`). See "Resolution" section below.

---

## Headline finding

EL-A's E3 over-restricted experiment 001 and demoted the v0.10.2 grade-B baseline to grade C across the panel. All 9 attempts produced compiler-accepted solutions with contracts present and applicable tests passing — but 0 reached grade A and 8/9 graded C (one gpt-5.5 F on the `missing Result-type` per-try variance from F-104). The mechanism was unambiguous: E3 flipped `login-handler.pre.proof_required: False → True`, but zero top-tier agents emitted `?proof-required` on the pre clause because the pre clause is QF-LIA-tractable (`(password not empty)`) and the v0.10.2 §13.8 pedagogy explicitly scopes `?proof-required` to *postconditions the verifier cannot discharge*, not preconditions on input shape. The original EL-A plan's Risk #3 anticipated grade movement but mis-predicted the without-marker path ("stay at B" — actual: dropped to C via `all_required_contracts_met: false`). **E3 reverted in `008495f`.** EL-A's E1 (call-graph delegation classification) and E2 (three-signal Result feature split) remain in place — both validated as working in production by this same batch (F-202, F-203).

## Sample composition

| Model | Attempts | Grades | Notable |
|---|---|---|---|
| claude-opus-4-7 | 3 | C / C / C | All solutions valid; none emit `?proof-required` on pre |
| gemini-3-pro-preview | 3 | C / C / C | Same |
| gpt-5.5 | 3 | C / F / C | try02 F on missing Result-type (F-104 lineage); try01 improved F→C vs prior batch (agent emitted Result-type this attempt) |
| **Total** | **9** | **0 A, 0 B, 8 C, 1 F** | |

## Verified findings

### F-201. EL-A E3 over-restricts experiment 001 — semantic mismatch on pre clause

**Priority:** High
**Consumer:** user
**Status:** Resolved by revert in commit `008495f`.

#### Evidence

`runs/20260510T235111Z/20260510T235111Z-claude-opus-4-7-try01-of-03-e001/evaluation.json`, `contract_assessment`:

```json
{
  "expected_total": 1,
  "accepted_total": 0,
  "all_required_contracts_met": false,
  "items": [{
    "function": "login-handler",
    "side": "pre",
    "expected_proof_required": true,
    "present_in_ast": true,
    "proof_required_marker": false,
    "trust_status": "asserted",
    "accepted": false,
    "reason": "proof-required contract accepted"
  }]
}
```

8 of 9 attempts produced identical-shape contract assessments. Zero agents emitted `?proof-required` on `login-handler.pre`.

#### Why we saw what we saw

The pre clause on `login-handler` per `experiments/minimal-agent/experiments/001-two-agent-auth.md` line 35 is "the password must not be empty" — a QF-LIA-tractable input constraint, verifiable at call sites independent of the function body. Per `LLMLL.md §5.3.5` verification matrix, "contracts on functions containing delegation holes are structurally asserted" — but that statement is about *postconditions* (which depend on the body's return value), not *preconditions on input shape*. The §13.8 LT-A pedagogical hook reinforces the scope: "*When a contract on a Result-returning function asserts a property the verifier cannot discharge — typically because the postcondition involves a delegated call, nonlinear arithmetic, or map invariants — mark the contract clause `?proof-required`*." Agents reading v0.10.2's docs correctly identified that `(>=(string-length password) 1)` does not need the marker — and were demoted from B to C under EL-A's expectation flip.

The EL-A plan's Risk #3 predicted *grade movement*: "Solutions with the marker: A reachable. Solutions without the marker: still B." The second half was wrong — the `assess_contracts` mechanism flips `accepted: false` when `expected_proof_required: true` is mismatched, which flips `all_required_contracts_met: false`, which routes to grade C through `quality_grade`'s `tests_ok or contracts_ok` check.

#### Resolution

E3 reverted in commit `008495f`: `CONTRACT_EXPECTATIONS[1]["login-handler"]["pre"]["proof_required"]` set back to `False`. Test regression guard (`ContractExpectationE3Tests`) inverted to lock the value at `False` and reference this postmortem's F-201 for the empirical evidence. The v0.10.1-era B ceiling on experiment 001 is restored as the honest reflection of the verification matrix.

The original E3 finding's Option 2 (restructure `001-two-agent-auth.md` to encapsulate the delegate in an uncontracted helper) remains available for a future batch when 001's structure is updated. Until then, grade A is not reachable on 001 — that is intentional and structurally correct.

**Addendum (2026-05-28) — Option 2 landed.** The compiler-engineer plan for E3 Option 2 was approved and implemented. `CONTRACT_EXPECTATIONS[1]["login-handler"]` now carries `{"post": {"proof_required": True}}` only (pre removed to eliminate the `asserted_without_proof = 1` path that was the root cause of the B ceiling). `REQUIRED_FEATURES[1]` gains `"post"`. `001-two-agent-auth.md` items 6–7 add: a delegation-bounded post contract on `login-handler` (marked `?proof-required`), and a non-delegation-dependent check block (necessary to clear the `effective_total == 0` test-exclusion B gate, which fires independently of contract quality and was not accounted for in the original Option 1 analysis). Three new tests guard the new state. Grade A is now reachable for experiment 001. CHANGELOG entry: `CHANGELOG.md §## Unreleased → ### Experiments — E3 Option 2`. E3 finding closed in `experiments/minimal-agent/findings.md`.

#### Acceptance

Confirmed by the revert commit landing on `main` (`008495f`). A future smoke-test re-run of the 9-attempt panel against the reverted evaluator is expected to produce grades matching the v0.10.2 baseline (B/B/B Claude+Gemini, F/B/B gpt-5.5). Not gated on this postmortem.

---

### F-202. EL-A E1 call-graph signal working as designed in production

**Priority:** Defence-in-depth (positive validation)
**Consumer:** user

#### Evidence

Same evaluation.json, `delegation_dependent_checks` array:

```json
[
  {
    "label": "login-handler-always-produces-result",
    "delegation_dependent": true,
    "reasons": ["call graph reaches delegation"]
  },
  {
    "label": "validate-session-fallback-is-false",
    "delegation_dependent": true,
    "reasons": ["call graph reaches delegation", "delegation-related label"]
  }
]
```

The new `"call graph reaches delegation"` reason fires on both delegation-dependent checks across all 9 attempts. One check additionally hits the label-regex fallback (`validate-session-fallback-is-false`); the other is call-graph-only (label has no delegation keywords).

#### Why we saw what we saw

Per EL-A's E1 design, the call-graph traversal from each check body extracts callee names via `extract_callee_names`, looks them up in `build_function_table(solution_ast)`, recursively traverses their bodies, and flags if any reached node has `kind ∈ {hole-delegate, hole-delegate-async, await}`. Both checks in 001 transitively call `login-handler` or `validate-session`, both of which contain `?delegate` in their bodies → call graph reaches delegation. Cycle-safe (no infinite recursion observed). Conservative (no false negatives).

#### Implication

Routing: **user**. Validates EL-A's E1 design empirically. The label-regex fallback provides a parallel signal that catches checks with delegation keywords in their labels. No change needed.

#### Acceptance

Confirmed.

---

### F-203. EL-A E2 three-signal Result split working as designed

**Priority:** Defence-in-depth (positive validation)
**Consumer:** user

#### Evidence

Same evaluation.json, `feature_scan.found`:

```json
{
  "Result-type": true,
  "Result-helpers": true,
  "Result-pattern": false,
  "Result": true
}
```

Across the 8 C-grade attempts: `Result-type: true` and `Result-helpers: true` consistently (agents use `(ok …)`/`(err …)` for construction); `Result-pattern: false` on this run's solutions (agents used `is-ok` for testing rather than `match` on `Success`/`Error` patterns). Back-compat `Result` field correctly derives from `Result-type`. gpt-5.5 try02 F: `Result-type: false` — `missing_required: ["Result-type"]` correctly drives the F grade.

#### Why we saw what we saw

Per EL-A's E2 design, the JSON walker emits three independent signals: `Result-type` from `kind:"result"` type-positions, `Result-helpers` from `app.fn ∈ {ok, err, is-ok, unwrap, unwrap-or}`, `Result-pattern` from `kind:"constructor"` with `constructor ∈ {Success, Error}`. Only `Result-type` participates in `missing_required`. The signal split is non-conflated; informational columns surface the agent's structural choices.

#### Implication

Routing: **user**. Validates E2 in production. Descriptive observation: top-tier agents prefer `is-ok` for testing over `match` on `Success`/`Error` patterns. Not actionable.

#### Acceptance

Confirmed.

---

### F-204. gpt-5.5 missing-Result variance persists (per-try, n=2 of 6 across two batches)

**Priority:** Defence-in-depth (descriptive)
**Consumer:** user

#### Evidence

`runs/20260510T235111Z/20260510T235111Z-gpt-5.5-try02-of-03-e001/evaluation.json`: `missing_required: ["Result-type"]`. Combined with the prior v0.10.2 batch (`20260510T205132Z` gpt-5.5 try01 F on the same gap): gpt-5.5 has missed the Result-type structural requirement on 2 of 6 attempts across two independent runs against the post-fix compiler. Claude+Gemini: 0/12 misses.

#### Implication

Routing: **user**. With n=6 and 2 misses, the per-try-variance hypothesis is upgraded from "single data point" (F-104) to "small but persistent pattern" (~33% miss rate). Still descriptive only — n=6 is below the bar for an inferential claim — but worth retaining as a hypothesis to watch in future panels. No prompt-design intervention warranted (verified F-104: input is explicit).

#### Acceptance

Larger-n run (≥10 attempts on a future panel) refines the rate estimate.

---

## Withdrawn items

- **Primary hypothesis (≥1 attempt produces grade A on the post-EL-A 001 panel):** falsified, n=9, 0 grade A produced. The §13.8 pedagogical hook plus E3's expectation flip did not converge into agent behavior — see F-201.
- **Secondary prediction ("solutions without `?proof-required` marker stay at B"):** falsified — they drop to C through the `all_required_contracts_met: false` path. The EL-A plan's Risk #3 prediction was wrong about the without-marker path; the revert in `008495f` is the corrective action.

## Null results

None on this run. All three EL-A predictions resolved (one falsified per F-201, two confirmed per F-202/F-203).

## Resolution

E3 reverted in `008495f` per the F-201 finding. EL-A's E1 (F-202) and E2 (F-203) remain on `main` as validated. `main` head after revert: `008495f`.

## Priority matrix

| # | Finding | Consumer | Priority | Resolution |
|---|---|---|---|---|
| **F-201** | EL-A E3 over-restricts | user | High | **Resolved** in `008495f` (revert) |
| **F-202** | E1 call-graph validated | user | Defence-in-depth | None — confirmed |
| **F-203** | E2 three-signal validated | user | Defence-in-depth | None — confirmed |
| **F-204** | gpt-5.5 Result-type miss rate (n=2/6) | user | Defence-in-depth | Larger-n follow-up |

## Per-consumer scoped files written

Single-file integrated postmortem; no per-consumer fragments. The E3 revert was the only normative action surfaced and is already executed.
