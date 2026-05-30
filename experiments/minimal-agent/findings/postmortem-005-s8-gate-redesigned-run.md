# Postmortem 005 — §8 Gate Redesigned Run: Grade A Achieved (EL-1 + EL-2 + E3 Evaluator)

**Date:** 2026-05-28
**Harness SHA:** `5cab1b7` + uncommitted grammar-mode script changes (`prepare_run.py` staged, `run_matrix.py`/`run_agent.py` unstaged)
**Compiler version:** llmll 0.10.8, binary timestamp May 28 07:18, built at commit `4252b5f` (F-GATE-1b; GrammarCoreInversion JSON-AST enforcement present)
**Experiment:** `001-two-agent-auth` (revised spec: items 6–7 added per E3 Option 2, commit `0d5037e`)
**Manifest:** `experiments/minimal-agent/manifest.e001-post-e3.json`
**Run ID:** `20260528T204620Z` — 8 attempts
**Comparison baseline:** `20260528T012230Z` (pre-arm, GrammarLegacy, 6 attempts — valid)
**Excluded from gate:** `20260528T014158Z` (invalid — enforcement absent); `20260528T145727Z` (old evaluator, predates E3 Option 2)

---

## Headline finding

Grade A achieved for the first time across any gate run: 3 of 6 harness-passing attempts reached grade A (2 of 5 claude-opus-4-7, 1 clean gemini-3-pro-preview). Axis (c) — `?proof-required` emission on out-of-core contracts — improves from 0/6 in the pre-arm baseline to 3/6, fulfilling the §8 gate pass criterion.

Two structurally distinct grade-A paths were exercised: (1) `def` (strict-core) + bare `?proof-required` → verifier status "asserted"; (2) `def-shell` + predicate-carrying `?proof-required` (LT-PPR syntax) → verifier status "asserted". This is the first empirical exercise of the LT-PPR predicate-carrying form in a live agent run.

A new evaluator bug (F-GATE-7) caused 3 of 5 claude attempts to land at grade C rather than grade A: `normalize_trust_status` did not strip the sample-count suffix from `"tested (100 samples)"`, causing the status to fail the `TRUST_STATUS_PRESENT` membership check. Fixed in commit following this postmortem. Two gemini cells are excluded from gate analysis: try02 submitted `def-logic` without in-session correction (enforcement correctly rejected it); try03 hit TerminalQuotaError.

---

## Sample composition

| Arm | Batch | Grammar mode | Evaluator | Models | Tries | e001 attempts |
|-----|-------|-------------|-----------|--------|-------|---------------|
| Pre (baseline) | `20260528T012230Z` | `GrammarLegacy` | pre-EL-3 | claude-opus-4-7, gemini-3-pro-preview | 3 each | 6 |
| Post (this run) | `20260528T204620Z` | `GrammarCoreInversion` | EL-1+EL-2+E3 | claude-opus-4-7, gemini-3-pro-preview | 5+3 | 8 |

---

## Per-attempt results

| Agent | Try | Status | Grade | login-handler kind | def | def-shell | def-logic | prc | contracts_met | eff_total | excl_dd | dur (s) | Notes |
|-------|-----|--------|-------|-------------------|-----|-----------|-----------|-----|---------------|-----------|---------|---------|-------|
| claude-opus-4-7 | 1 | passed | **A** | def | 2 | 0 | 0 | 1 | True | 1 | 2 | 381 | bare `?proof-required`; def body → "asserted" |
| claude-opus-4-7 | 2 | passed | **A** | def-shell | 0 | 2 | 0 | 1 | True | 1 | 2 | 326 | bare `?proof-required`; arithmetic pre → "asserted" |
| claude-opus-4-7 | 3 | passed | **C** | def-shell | 0 | 2 | 0 | 0 | False | 2 | 1 | 344 | bare `?proof-required`; bool pre → "tested (100 samples)" (F-GATE-7) |
| claude-opus-4-7 | 4 | passed | **C** | def-shell | 0 | 2 | 0 | 0 | False | 2 | 1 | 321 | same (F-GATE-7) |
| claude-opus-4-7 | 5 | passed | **C** | def-shell | 0 | 2 | 0 | 0 | False | 2 | 1 | 292 | same (F-GATE-7) |
| gemini-3-pro-preview | 1 | passed | **A** | def-shell | 0 | 2 | 0 | 1 | True | 1 | 2 | 251 | predicate-carrying `?proof-required` (LT-PPR) → "asserted" |
| gemini-3-pro-preview | 2 | eval_failed | **F** | — | 0 | 0 | 2 | — | — | — | — | 180 | def-logic rejected; no in-session correction; **excluded** |
| gemini-3-pro-preview | 3 | agent_failed | — | — | — | — | — | — | — | — | — | 82 | TerminalQuotaError; 0 work product; **excluded** |

`evaluation.json` citations:
- `runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try01-of-05-e001/evaluation.json`
- `runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try02-of-05-e001/evaluation.json`
- `runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try03-of-05-e001/evaluation.json` (grade C; `trust_status: "tested (100 samples)"`)
- `runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try01-of-03-e001/evaluation.json` (LT-PPR predicate-carrying)
- `runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try02-of-03-e001/evaluation.json` (def-logic rejection evidence)

---

## Gate-axis summary

Per `docs/compiler-team-roadmap.md:185`:

| Axis | Pre-arm (n=6) | Post-arm valid (n=6) | Claude-only (n=5) | Delta |
|------|--------------|----------------------|-------------------|-------|
| (a) Pass rate | 6/6 (100%) | 6/6 (100%) | 5/5 (100%) | No change |
| (a) Grade distribution | 6× B | 3× A, 3× C | 2× A, 3× C | Grade A first seen |
| (b) Verified fraction | 0/6 | 0/6 | 0/5 | No change |
| **(c) `?proof-required` emission** | **0/6 (0%)** | **3/6 (50%)** | **2/5 (40%)** | **Axis (c) improves — gate criterion met** |
| (d) def/def-shell in final solutions | 0/6 (0%) | 10/10 (100%) | 8/8 (100%) | Confirmed from postmortem-004 |
| (d) def-logic in final solutions | 12/12 (100%) | 0/10 (0%) | 0/8 (0%) | Confirmed |

Valid post-arm dataset: claude ×5 + gemini-try01 ×1. Gemini-try02 excluded (no in-session correction on enforced rejection). Gemini-try03 excluded (0 work product, TerminalQuotaError).

**§8 gate pass criterion:** at least one of (a/b/c) must improve over baseline. Axis (c) improves from 0/6 to 3/6. Gate pass confirmed. This provides empirical backing for the language-team adjudication committed at `5cab1b7`.

---

## Verified findings

### F-GATE-6. Grade A achieved; axis (c) non-trivial; two grade-A paths exercised

**Priority:** Confirmation — gate pass evidenced.
**Consumer:** language-team (gate adjudication close-out)

#### Evidence

**Path 1 — `def` (strict-core) + bare `?proof-required`** (claude try01):

`runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try01-of-05-e001/evaluation.json`:
```json
{
  "feature_scan": {
    "boundary_form_counts": {"def": 2, "def-shell": 0, "def-logic": 0}
  },
  "contract_assessment": {
    "items": [{
      "function": "login-handler", "side": "post",
      "trust_status": "asserted", "accepted": true,
      "reason": "accepted asserted proof-required ceiling"
    }],
    "proof_required_ceiling_accepted": 1,
    "all_required_contracts_met": true
  },
  "quality_grade": "A"
}
```

`login-handler` kind: `def`. Post clause: `{"kind":"hole-proof-required","reason":"non-linear-contract"}`. Verifier: `login-handler: pre: asserted | post: asserted`. The `def` body containing `hole-delegate` causes the verifier to mark the whole function's contracts as "asserted".

**Path 2a — `def-shell` + bare `?proof-required` (arithmetic pre)** (claude try02):

`runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try02-of-05-e001/evaluation.json`:
- `boundary_form_counts: {"def": 0, "def-shell": 2, "def-logic": 0}`
- `trust_status: "asserted"` for `login-handler.post` despite `def-shell` kind
- `quality_grade: A`; `proof_required_ceiling_accepted: 1`

Pre clause: `string-length(password) > 0`. Verifier output: `login-handler: pre: asserted | post: asserted`. The arithmetic pre clause (`string-length`) appears to trigger "asserted" propagation to the post clause (F-GATE-8 covers the mechanism).

**Path 2b — `def-shell` + predicate-carrying `?proof-required` (LT-PPR)** (gemini try01):

`runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try01-of-03-e001/`:
- Post clause: `{"kind":"hole-proof-required","reason":"manual","predicate":{"kind":"match","scrutinee":{"kind":"var","name":"result"},"arms":[{"pattern":{"kind":"constructor","constructor":"Success",...},"body":{"kind":"op","op":">","args":[{"kind":"app","fn":"string-length","args":[{"kind":"var","name":"hash"}]},...]}},{"pattern":{"kind":"constructor","constructor":"Error",...},"body":{"kind":"lit-bool","value":true}}]}}` — full predicate carried in `?proof-required`
- `trust_status: "asserted"`; `quality_grade: A`
- `boundary_form_counts: {"def": 0, "def-shell": 2, "def-logic": 0}`

This is the first agent-authored predicate-carrying `?proof-required` in any experiment run. The predicate matches on Result arms and asserts `string-length(hash) > 0` on the success arm.

#### Why we saw what we saw

E3 Option 2 set `login-handler.post.proof_required: True` in `CONTRACT_EXPECTATIONS`. The revised spec (items 6–7) explicitly instructed agents to mark the post clause `?proof-required`. Agents that followed the instruction correctly and whose solution structures produced `trust_status: "asserted"` (not "tested") received grade A.

#### Acceptance

Closed — gate pass confirmed by axis (c) improvement (0/6 → 3/6).

---

### F-GATE-7. `normalize_trust_status` does not strip sample-count suffix

**Priority:** High — caused 3/5 claude grade-C mislabels in this run.
**Consumer:** experiment-lead (own fix — applied to `scripts/evaluate_run.py`)

#### Evidence

`runs/20260528T204620Z/20260528T204620Z-claude-opus-4-7-try03-of-05-e001/evaluation.json` contract_assessment item:
```json
{
  "function": "login-handler", "side": "post",
  "expected_proof_required": true,
  "present_in_ast": true, "proof_required_marker": true,
  "trust_status": "tested (100 samples)",
  "accepted": false,
  "reason": "contract present but absent from trust report"
}
```

`evaluate_run.py:137`: `TRUST_STATUS_PRESENT = {"verified", "contract-checked", "tested", "asserted"}`.  
`evaluate_run.py:668`: `if present_in_ast and status in TRUST_STATUS_PRESENT:` — exact membership check.  
`"tested (100 samples)" in TRUST_STATUS_PRESENT` → `False` (string literal doesn't match `"tested"`).

All three grade-C attempts (try03-05) share `trust_status: "tested (100 samples)"` for `login-handler.post`. Without the suffix, `accepted` would be `True`, `contracts_ok` would be `True`, and `quality_grade` would return `"A"` (contracts_met=True, effective_total=2, awp=0).

#### Fix applied

`evaluate_run.py:normalize_trust_status` — added regex strip before `.lower()`:
```python
value = re.sub(r"\s*\(.*\)\s*$", "", value)
```
`normalize_trust_status("tested (100 samples)")` now returns `"tested"`. `re` is already imported at module top.

Note: even with this fix, the F-GATE-8 compiler-side inconsistency means that some `def-shell` solutions will receive "tested" (not "asserted") for their post clause. With the evaluator fix, "tested" is in `TRUST_STATUS_PRESENT` and the contract is accepted — but `proof_required_ceiling_count` increments only when `status == "asserted"`, so those attempts would reach grade A via a different path (contracts_met=True, effective_total>0, awp=0 → grade A) rather than through the `prc` ceiling counter.

#### Acceptance

`normalize_trust_status("tested (100 samples)")` returns `"tested"`. Applied.

---

### F-GATE-8. `def-shell + bare hole-proof-required` post trust status is pre-clause-dependent

**Priority:** Medium — compiler-engineer investigation required.
**Consumer:** compiler-engineer

#### Evidence

Four `def-shell` functions with structurally identical post clauses and bodies produce different post trust statuses:

| Attempt | pre clause | post trust_status | Grade |
|---------|-----------|-------------------|-------|
| claude try02 | `string-length(password) > 0` | `"asserted"` | A |
| claude try03 | `not(string-empty?(password))` | `"tested (100 samples)"` | C (→A with F-GATE-7 fix) |
| claude try04 | `not(string-empty?(password))` | `"tested (100 samples)"` | C (→A with F-GATE-7 fix) |
| claude try05 | `not(string-empty?(password))` | `"tested (100 samples)"` | C (→A with F-GATE-7 fix) |

Post clause in all four: `{"kind":"hole-proof-required","reason":"non-linear-contract"}` (bare, no predicate).
Body in all four: `{"kind":"hole-delegate","agent":"crypto-agent",...}`.
Difference: try02 pre uses `string-length(password) > 0`; try03-05 pre uses `not(string-empty?(password))`.

Verify command: `llmll --grammar=core-inversion verify solution.ast.json --trust-report ...`.

Trust report text — try02: `login-handler: pre: asserted | post: asserted`.
Trust report text — try03: `login-handler: pre: asserted | post: tested (100 samples)`.

Both pre clauses are reported "asserted". The post diverges.

#### Why we saw what we saw (hypothesis — unconfirmed)

`string-length` is likely not in the static evaluator's known-builtin set for PBT. When the verifier attempts to run PBT on `string-length(password) > 0`, the predicate body is unevaluable → the whole function's contracts may be flagged "asserted" before the post clause is attempted. `not(string-empty?(password))` is evaluable (string → bool via `string-empty?`) → PBT runs to completion on the pre clause → the verifier then independently processes the bare `hole-proof-required` post as a PBT target → "tested (N)".

This is consistent with the S3 vacuity bug (unevaluable samples default to True) but the trust-status propagation behavior is distinct — it affects the classification of the post clause when the pre clause is unevaluable.

Root cause unconfirmed. Requires tracing the verifier's per-clause processing path for `def-shell` functions in `FixpointEmit.hs` or `Contracts.hs`.

#### Implication for compiler-engineer

A `def-shell` function with `hole-delegate` body should produce `trust_status: "asserted"` for the post clause unconditionally — the delegation hole makes the return value opaque and the contract cannot be verified independently of the agent. The post clause status should not vary based on whether PBT runs successfully on the pre clause. Acceptance: `def-shell + not(string-empty?(password)) pre + bare hole-proof-required post + hole-delegate body` → `post: "asserted"`.

---

### F-GATE-9. Gemini-try02 submitted `def-logic` without in-session correction after enforcement rejection

**Priority:** Observation — enforcement working; behavioral note.
**Consumer:** experiment-lead

#### Evidence

`runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try02-of-03-e001/evaluation.json` first_error:
```
stdout: (error :phase parse :file "solution.ast.json"
                :message "core-grammar-violation: 'def-logic' (function 'login-handler')
                          is not admitted under --grammar=core-inversion; use 'def' for
                          strict-core or 'def-shell' for permissive"
                :hint "Replace {\"kind\":\"def-logic\",...} with {\"kind\":\"def\",...}
                       (strict-core) or {\"kind\":\"def-shell\",...} (permissive);...")
returncode: 1
```

`boundary_form_counts: {"def": 0, "def-shell": 0, "def-logic": 2}`. Duration: 180s. Harness stop policy `first_error` fires on the `check` command failure. No retry within the session.

Contrast: postmortem-004 claude-opus-4-7-try03 corrected `def-logic` → `def-shell` in-session (+25s overhead). The enforcement signal and hint text were identical. Gemini-try02 did not apply the correction before the stop policy fired.

---

### F-GATE-10. Gemini-try03 TerminalQuotaError

**Priority:** Exclusion condition.
**Consumer:** experiment-lead

`runs/20260528T204620Z/20260528T204620Z-gemini-3-pro-preview-try03-of-03-e001/logs/agent.stderr.log`:
> `TerminalQuotaError: You have exhausted your capacity on this model. Your quota will reset after 4h11m59s.`

`status: failed, rc: 1, dur: 82s`. No work product, no evaluation.json. Third occurrence of gemini quota exhaustion across four gate runs (postmortem-004: try01 HTTP 429, try03 429-degraded; this run: try03 TerminalQuotaError). The two-model comparison remains structurally compromised. For gate axis analysis the clean gemini cell is limited to try01 only.

---

## In-session correction vs. prior runs

| Metric | Postmortem-004 (old evaluator) | Postmortem-005 (redesigned) |
|--------|-------------------------------|----------------------------|
| Total attempts | 6 | 8 |
| Harness-passing | 5 | 6 |
| Grade A | 0 | 3 |
| Grade B | 5 | 0 |
| Grade C | 0 | 3 |
| Grade F | 0 | 1 |
| def-logic in final | 0/10 (0%) | 0/10 (0%) (excl try02) |
| ?proof-required emitted | 0/5 (0%) | 3/6 (50%) |

Grade B disappears in this run because E3 Option 2 made the `login-handler.post` a required contract — without `?proof-required`, the contract expectation fails → grade C (not B). The redesigned evaluator is more discriminating: agents that emit `?proof-required` correctly get A; those that don't get C.

---

## Duration analysis

| Model | Pre-arm mean (s) | Postmortem-004 mean (s) | Postmortem-005 mean (s) |
|-------|-----------------|------------------------|------------------------|
| claude-opus-4-7 | 241.6 | 303.7 (n=3) | 332.6 (n=5) |
| gemini-3-pro-preview | 159.0 | 502 (try02 only, clean) | 251 (try01 only, clean) |

Claude mean duration trend is upward across runs. The revised spec (items 6–7: two new required elements) plausibly adds overhead. No single outlier — claude durations range 292–381s across five attempts.

---

## Null results

**Hypothesis:** all of axes (a), (b), (c) would improve.

**Data:** (a) pass rate unchanged (100% both arms). (b) verified=0 in both arms. (c) improved from 0/6 to 3/6.

(a) and (b) null is expected — grammar enforcement and `?proof-required` marking do not drive formal verification or PBT-verified status; those require the verifier to succeed on the full contract predicate against actual domain knowledge. Axis (b) improvement would require LT-CDP discriminative-power work to surface non-trivial properties that can be verified. This is out of scope for the §8 gate.

---

## Withdrawn items

None.

---

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---------|----------|----------|--------|
| **F-GATE-6** | Grade A confirmed; axis (c) improves; LT-PPR exercised | language-team | Confirmation — close gate | None |
| **F-GATE-7** | normalize_trust_status sample-count suffix mismatch | experiment-lead | High — applied fix | Done |
| **F-GATE-8** | def-shell trust status pre-clause-dependent | compiler-engineer | **Closed** — f62a38b (2026-05-29) | Done |
| **F-GATE-9** | Gemini-try02 no correction on def-logic rejection | experiment-lead | Observation | None |
| **F-GATE-10** | Gemini-try03 TerminalQuotaError | experiment-lead | Exclusion condition | None |

---

## Findings file fragments

See `experiments/minimal-agent/findings.md`:
- `## Experiment-lead` — F-GATE-6, F-GATE-7 (applied), F-GATE-9, F-GATE-10 added under EL-C
- `## Language-team` — gate adjudication close-out (postmortem-005 axis (c) confirmation)
- `## Compiler-engineer` — F-GATE-8 added
