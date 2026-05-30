# Postmortem 006 — EL-5 Clean Gate Run: Grade A at 5/5 Claude + 2/3 Gemini (F-GATE-7+8 Fully Eliminated)

**Date:** 2026-05-30
**Harness SHA:** `b8c15dd` (f62a38b + CE-2 revert; grammar default → GrammarLegacy)
**Compiler version:** llmll 0.10.8, binary May 29 22:23 (rebuilt from HEAD `b8c15dd`)
**Experiment:** `001-two-agent-auth` (E3 Option 2, commit `0d5037e`)
**Manifest:** `experiments/minimal-agent/manifest.e001-post-e3.json`
**Run ID:** `20260530T052351Z` — 8 attempts
**Comparison baseline:** `20260528T012230Z` (pre-arm, GrammarLegacy, 6 attempts — valid; confirmed per PM-005)
**Excluded from analysis:** none — first gate run with 0 gemini quota failures across all 3 cells

---

## Headline finding

5/5 claude-opus-4-7 attempts reach grade A, 3/3 tests passed, prc_accepted=1, trust_status=asserted. F-GATE-7 evaluator contamination and F-GATE-8 compiler contamination are fully eliminated from the claude cohort. Gemini-3-pro-preview delivers 2/3 grade A and 1/3 grade C, with no quota exclusions for the first time in any gate run. The grade-C case (try02) is a PBT property coverage gap — all 3 properties gave up at 1000 discards each — unrelated to F-GATE-7 or F-GATE-8. Axis (c) `?proof-required` emission reaches 8/8 (100%) across all attempts; axis (c) prc_accepted (asserted-ceiling path) reaches 5/5 on claude and 1/3 on gemini. This is the definitive clean run for language-team gate adjudication.

---

## Sample composition

| Arm | Batch | Grammar mode | Evaluator | Binary | Models | Tries | e001 attempts |
|-----|-------|-------------|-----------|--------|--------|-------|---------------|
| Pre (baseline) | `20260528T012230Z` | `GrammarLegacy` | pre-EL-3 | llmll 0.10.8 @ `4252b5f` | claude-opus-4-7, gemini-3-pro-preview | 3 each | 6 |
| EL-5 (this run) | `20260530T052351Z` | `GrammarCoreInversion` | EL-1+EL-2+E3+F-GATE-7 | llmll 0.10.8 @ `b8c15dd` | claude-opus-4-7, gemini-3-pro-preview | 5+3 | 8 |

---

## Per-attempt results

| Agent | Try | Status | Grade | login-handler kind | def | def-shell | def-logic | prc | contracts_met | eff_total | eff_passed | all_app | dur (s) | Notes |
|-------|-----|--------|-------|-------------------|-----|-----------|-----------|-----|---------------|-----------|-----------|---------|---------|-------|
| claude-opus-4-7 | 1 | passed | **A** | def-shell | 0 | 2 | 0 | 1 | True | 3 | 3 | True | 340 | def-shell + hole-delegate → asserted (F-GATE-8 path) |
| claude-opus-4-7 | 2 | passed | **A** | def | 2 | 0 | 0 | 1 | True | 3 | 3 | True | 371 | def + hole-delegate + unevaluable pre → asserted |
| claude-opus-4-7 | 3 | passed | **A** | def | 2 | 0 | 0 | 1 | True | 3 | 3 | True | 309 | def + hole-delegate + unevaluable pre → asserted |
| claude-opus-4-7 | 4 | passed | **A** | def | 2 | 0 | 0 | 1 | True | 3 | 3 | True | 307 | def + hole-delegate + unevaluable pre → asserted |
| claude-opus-4-7 | 5 | passed | **A** | def-shell | 0 | 2 | 0 | 1 | True | 3 | 3 | True | 326 | def-shell + hole-delegate → asserted (F-GATE-8 path) |
| gemini-3-pro-preview | 1 | passed | **A** | def | 2 | 0 | 0 | 0 | True | 3 | 3 | True | 172 | def + hole-delegate + evaluable pre → tested; 3/3 props passed |
| gemini-3-pro-preview | 2 | passed | **C** | def | 2 | 0 | 0 | 1 | True | 1 | 0 | False | 420 | def + hole-delegate + unevaluable pre → asserted; 3/3 props gave up (1000 discards) |
| gemini-3-pro-preview | 3 | passed | **A** | def | 2 | 0 | 0 | 0 | True | 3 | 3 | True | 176 | def + hole-delegate + evaluable pre → tested; 3/3 props passed |

`evaluation.json` citations:
- `runs/20260530T052351Z/20260530T052351Z-claude-opus-4-7-try01-of-05-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-claude-opus-4-7-try02-of-05-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-claude-opus-4-7-try03-of-05-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-claude-opus-4-7-try04-of-05-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-claude-opus-4-7-try05-of-05-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-gemini-3-pro-preview-try01-of-03-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-gemini-3-pro-preview-try02-of-03-e001/evaluation.json`
- `runs/20260530T052351Z/20260530T052351Z-gemini-3-pro-preview-try03-of-03-e001/evaluation.json`

---

## Four-axis gate summary

Per `docs/compiler-team-roadmap.md:185`:

| Axis | Pre-arm (n=6) | EL-5 all (n=8) | EL-5 claude (n=5) | EL-5 gemini (n=3) | Delta (all) |
|------|--------------|----------------|-------------------|-------------------|-------------|
| (a) Pass rate | 6/6 (100%) | 8/8 (100%) | 5/5 (100%) | 3/3 (100%) | No change |
| (a) Grade A | 0/6 (0%) | 7/8 (87.5%) | 5/5 (100%) | 2/3 (67%) | **+87.5 pp** |
| (a) Grade B | 6/6 (100%) | 0/8 (0%) | 0/5 (0%) | 0/3 (0%) | B eliminated |
| (a) Grade C | 0/6 (0%) | 1/8 (12.5%) | 0/5 (0%) | 1/3 (33%) | New C (see F-EL5-2) |
| (b) Verified | 0/6 (0%) | 0/8 (0%) | 0/5 (0%) | 0/3 (0%) | No change |
| **(c) `?proof-required` emitted** | **0/6 (0%)** | **8/8 (100%)** | **5/5 (100%)** | **3/3 (100%)** | **+100 pp** |
| **(c) prc_accepted (asserted ceiling)** | **0/6 (0%)** | **6/8 (75%)** | **5/5 (100%)** | **1/3 (33%)** | **+75 pp / +100 pp claude** |
| (d) def-logic in solutions | all (100%) | 0/8 (0%) | 0/5 (0%) | 0/3 (0%) | Eliminated |

Pre-arm grade column was uniformly B (pre-E3 evaluator, post contract not required; `login-handler.post: none` in all 6 baseline `verify_details`). Pre-arm `boundary_form_counts` not populated by the pre-EL-3 evaluator; axis (d) pre-arm value is inferred from the GrammarLegacy regime (def-logic 100%, confirmed by PM-003/PM-004).

**§8 gate adjudication:** axis (c) `?proof-required` emission reaches 8/8 in EL-5 versus 0/6 pre-arm. Gate pass criterion met at this run; PM-005 established the criterion was met at 3/6 — this run confirms and strengthens. No exclusions from analysis. This is the clean dataset for language-team gate close-out.

---

## Verified findings

### F-EL5-1. Grade A confirmed 5/5 claude + 2/3 gemini; F-GATE-7+8 contamination path fully eliminated

**Priority:** Confirmation — definitive gate evidence.
**Consumer:** language-team

#### Evidence

All 5 claude-opus-4-7 attempts:
- `quality_grade: "A"`, `all_required_contracts_met: true`, `proof_required_ceiling_accepted: 1`
- `trust_status: "asserted"` for `login-handler.post` in all 5 cases
- `all_applicable_passed: true`, `effective_total: 3`, `effective_passed: 3` in all 5 cases
- `boundary_form_counts: {"def-logic": 0}` in all 5 cases; mix of `def` (try02-04: def×2) and `def-shell` (try01,05: def-shell×2)

PM-005 had 3/5 claude grade C attributed to F-GATE-7 (suffix mismatch) and F-GATE-8 (pre-clause-dependent trust status). With both fixes at HEAD, 0/5 grade C. The contamination path is closed.

Two grade-A paths for the compiler:

**Path A — `def-shell + hole-delegate`** (claude try01, try05):
F-GATE-8 fix (`f62a38b`, `PBT.hs:pbtTrustWriteback`, `guardDelegate` suppresses `DLTested` lift for `SDefShell + EHole(HDelegate _)` bodies). Post trust status: `asserted` unconditionally regardless of pre clause form. `prc_accepted: 1`.

**Path B — `def + hole-delegate + unevaluable pre`** (claude try02-04):
Pre-clause unevaluability propagation (pre-f62a38b mechanism, still active for `def` kind). Pre clause uses a builtin not in the PBT static evaluator's builtin set → whole-function "asserted" before post-clause attempt. Post trust status: `asserted`. `prc_accepted: 1`.

Gemini try01/03 (grade A, def kind, evaluable pre):
`trust_status: "tested"` for post. PBT runs on pre (evaluable), succeeds; post clause (bare `hole-proof-required`) processed by PBT → "tested". Accepted via `TRUST_STATUS_PRESENT` after F-GATE-7 suffix-strip fix. `prc_accepted: 0`; grade A via `all_applicable_passed: True` (3/3 props passed).

#### Why we saw what we saw

F-GATE-7 fix (`normalize_trust_status`, `evaluate_run.py:637`) strips sample-count suffix; F-GATE-8 fix (`f62a38b`) blocks `DLTested` write-back for `def-shell + hole-delegate`. Together, every solution structure that produces a passing harness run also produces an accepted contract. PM-005's 3 grade-C cases (claude try03-05: `def-shell + not(string-empty?)` pre → `"tested (100 samples)"`) would all reach grade A under EL-5 conditions: F-GATE-7 strips the suffix, and F-GATE-8 would have produced "asserted" for those def-shell cases anyway.

#### Implication for language-team

Axis (c) improvement is genuine and uncontaminated: 0/6 pre-arm → 8/8 EL-5. This is the clean empirical basis for definitive gate adjudication. Two structurally distinct grade-A paths exercise different parts of the trust system; neither depends on a single lucky pre-clause form.

#### Acceptance

Closed — confirmed.

---

### F-EL5-2. Gemini-try02 grade C — PBT property coverage gap; unrelated to F-GATE-7+8

**Priority:** Observation — new finding; behavioral note.
**Consumer:** experiment-lead

#### Evidence

`runs/20260530T052351Z/20260530T052351Z-gemini-3-pro-preview-try02-of-03-e001/evaluation.json`:
- `test_summary: {"total": 3, "passed": 0, "failed": 0, "skipped": 3}`
- `test_assessment: {"effective_total": 1, "effective_passed": 0, "effective_skipped": 1, "excluded_delegation_dependent": 2, "all_applicable_passed": false}`
- Test command stdout: `Gave up! Passed only 0 tests; 1000 discarded tests.` × 3 properties

All 3 properties gave up after 1000 discards each. 2 of 3 were classified delegation-dependent; 1 was non-delegation-dependent but still gave up. `effective_total: 1`, `effective_passed: 0`, `effective_skipped: 1` → `all_applicable_passed: False` → grade C.

Contrast: gemini-try01 and try03 have `effective_total: 3`, `effective_passed: 3`, `excluded_delegation_dependent: 0` — all 3 properties passed, none delegation-dependent. Duration: 172s, 176s vs 420s for try02.

The try02 solution's contract was fully met (`contracts_met: True`, `prc_accepted: 1`, `trust_status: "asserted"`). Grade C is driven exclusively by the test-coverage gap, not by contract quality. The agent appears to have written properties with preconditions too tight for random test generation — the generator discards all 1000 candidates per property.

#### Why we saw what we saw

Gemini try02 used a `def` function body with an unevaluable pre clause (same mechanism as claude path B). The unevaluable pre propagated to "asserted" trust status for the post clause — identical outcome to claude try02-04 on the contract axis. The behavioral difference is in how the agent wrote the PBT properties: try02's property preconditions are over-constrained relative to the generator's sampling distribution. Try01/03 wrote properties that passed PBT; try02 wrote properties whose preconditions the generator could not satisfy. This is not a compiler defect — the evaluator correctly identifies `all_applicable_passed: False` and assigns grade C per the harness contract (`README.md:180-185`).

The grade-C finding also intersects with the delegation-dependent detection: try02 has 2 delegation-dependent properties excluded (`excl_dd: 2`) while try01/03 have `excl_dd: 0`. Gemini produces structurally different property sets across attempts; the delegation-dependent call-graph analysis (E1, `evaluate_run.py:430-454`) treats them differently.

#### Implication

No action required at compiler or spec level. This is a behavioral note about gemini-3-pro-preview's property-writing quality variability. For future experiment design: the grade-A threshold requires both correct contract emission AND passing PBT properties on the non-delegation-dependent effective test set. Agents that write over-constrained properties will be graded C even with a correct contract.

#### Acceptance

N/A — observation only.

---

### F-EL5-3. `def + hole-delegate` post trust-status remains pre-clause-dependent; does not affect grade

**Priority:** Observation — residual F-GATE-8 pattern for `def` kind; non-blocking.
**Consumer:** compiler-engineer (for awareness)

#### Evidence

Across EL-5, `def` kind with `hole-delegate` body produces two distinct post trust statuses correlated with pre-clause evaluability:

| Agent | Pre clause form | Post trust_status | Grade |
|-------|----------------|-------------------|-------|
| claude try02-04 | unevaluable (likely `string-length` or similar) | `"asserted"` | A |
| gemini try01/03 | evaluable (e.g., `not(string-empty?)`) | `"tested"` | A |
| gemini try02 | unevaluable | `"asserted"` | C (test coverage gap, not trust status) |

F-GATE-8 fix (`f62a38b`) blocked `DLTested` write-back for `SDefShell + EHole(HDelegate _)` bodies specifically. For `def` kind (strict-core), the verifier still attempts PBT on the whole function when the pre clause is evaluable → post trust status becomes "tested". When the pre clause is unevaluable, the pre-clause unevaluability propagation path fires → "asserted" for the whole function.

The `def` kind pre-clause-dependent behavior does NOT affect grade A: "tested" is in `TRUST_STATUS_PRESENT` (after F-GATE-7 fix) and is accepted by the contract assessor as `reason: "proof-required contract accepted"`. Grade A is reachable via either trust status ("asserted" via `prc_accepted: 1` path; "tested" via `TRUST_STATUS_PRESENT` acceptance path).

#### Why we saw what we saw

The F-GATE-8 fix did not extend to `def` kind by design (`commit f62a38b` message: "block DLTested write-back for hole-delegate **def-shell** functions"). `def` (strict-core) semantics permit the verifier to attempt PBT on the post clause when the body has a `hole-delegate` — the strict-core form is not opaque in the same way as `def-shell`. Whether `def + hole-delegate` should also produce "asserted" unconditionally is a spec question (what is the intended verification semantics for a strict-core function whose body contains a delegation hole?).

#### Implication for compiler-engineer

The pre-clause-dependent behavior for `def + hole-delegate` is a residual analog of F-GATE-8 for the strict-core form. It does not currently affect grade — either trust status is accepted. If the spec decision is that `def + hole-delegate` should be "asserted" unconditionally (same rationale as `def-shell`: the delegation hole makes the return value opaque), the F-GATE-8 fix in `PBT.hs:pbtTrustWriteback` would need to be extended to include `SDef` with `EHole(HDelegate _)` or `EHole(HDelegateAsync _)` body alongside `SDefShell`. Acceptance criterion (if fix is desired): `def + evaluable-pre + hole-delegate + hole-proof-required post` → `post: "asserted"`.

This is not a blocker. Route to language-team for spec decision before any compiler change.

---

### F-EL5-4. First gate run with 0 gemini quota failures

**Priority:** Observation.
**Consumer:** experiment-lead

All 3 gemini-3-pro-preview attempts completed without TerminalQuotaError or HTTP 429. Prior occurrences: PM-004 try01 (0 output, 234s, 10 retries), PM-004 try03 (F, 805s, 20 retries, 429-degraded), PM-005 try03 (TerminalQuotaError, 82s, 0 output). EL-5 run was launched approximately 4 hours after PM-005's last known quota reset window (`4h11m59s` from `logs/agent.stderr.log` in PM-005 try03). Run IDs confirm EL-5 launched at `20260530T052351Z` — approximately 26 hours after the PM-005 batch, well past the reset window.

The structural throttling risk noted in the EL-5 run plan has resolved for this run. The two-model comparison is now complete across all 8 cells with no infrastructure exclusions.

---

## Duration analysis

| Model | Pre-arm mean (s) | PM-005 mean (s) | EL-5 mean (s) |
|-------|-----------------|-----------------|---------------|
| claude-opus-4-7 | 241.6 (n=3) | 332.6 (n=5) | 330.6 (n=5) |
| gemini-3-pro-preview | 159.0 (n=3, pre-arm) | 251 (n=1 clean) | 256.3 (n=3) |

Claude mean duration is stable between PM-005 and EL-5 (332.6 → 330.6s). The revised spec (items 6–7) overhead appears to have plateaued. Gemini mean is now meaningful with n=3 (vs n=1 in PM-005): 256s, consistent with the PM-005 single clean cell. Gemini try02 at 420s is the outlier (property generation loop overhead).

---

## Null results

**Hypothesis:** F-GATE-7+8 fixes together would eliminate all claude grade-C cases.
**Data:** 0/5 claude grade C. Hypothesis supported.

**Hypothesis:** axis (b) (verified fraction) would improve.
**Data:** 0/8 verified. Null — expected. Formal verification requires the full contract predicate to be discharged against domain knowledge. `?proof-required` marking signals that the obligation exists but does not constitute proof. Axis (b) improvement would require discriminative-power work (LT-CDP) to surface non-trivial verifiable properties. Out of scope for §8 gate.

**Hypothesis:** gemini quota would interfere.
**Data:** 0/3 quota failures. Hypothesis not realized.

---

## Withdrawn items

None.

---

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---------|----------|----------|--------|
| **F-EL5-1** | Grade A confirmed; F-GATE-7+8 eliminated; clean gate dataset | language-team | Confirmation — close gate | None |
| **F-EL5-2** | Gemini-try02 grade C — PBT property coverage gap | experiment-lead | Observation | None |
| **F-EL5-3** | `def + hole-delegate` trust status pre-clause-dependent (residual) | compiler-engineer | Observation — non-blocking | Low (spec decision needed first) |
| **F-EL5-4** | First run with 0 gemini quota failures | experiment-lead | Observation | None |

---

## Findings file fragments

See `experiments/minimal-agent/findings.md`:
- `## Language-team` — §8 gate adjudication (EL-5 clean run) added under EL-E
- `## Experiment-lead` — F-EL5-2 through F-EL5-4 added under EL-E; priority matrix updated
- `## Compiler-engineer` — F-EL5-3 observation added under EL-E

Hand-off to language-team: F-EL5-1 provides the clean empirical dataset for §8 gate close-out. The four-axis table above is the input for adjudication. F-EL5-3 spec question (should `def + hole-delegate` be "asserted" unconditionally?) should be addressed before any follow-on compiler work.
