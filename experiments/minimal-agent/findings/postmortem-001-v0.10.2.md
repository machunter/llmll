# Postmortem 001 — v0.10.2 Re-validation

**Source:** Three batches across 4 model panels:
- `experiments/minimal-agent/runs/20260510T201142Z/` — top-models panel (`claude-opus-4-7`, `gemini-3-pro-preview`, `codex-gpt-5.5-codex`)
- `experiments/minimal-agent/runs/20260510T204345Z/` — codex-base attempt (`codex-gpt-5.5`)
- `experiments/minimal-agent/runs/20260510T205132Z/` — gpt-5.5 substituted (`gpt-5.5`, ChatGPT-tier-supported)

**Compiler version:** `llmll 0.10.2` (verified bare-PATH post-`stack install`)
**Harness SHA:** `b5cdbfa` (tag `v0.10.2`)
**Date:** 2026-05-10
**Manifests:** `manifest.top-models-e001.json`, `manifest.gpt-5.5-e001.json` (replaces deleted `manifest.codex-base-e001.json` after the substitution succeeded)

---

## Headline finding

The v0.10.2 soundness fixes (S1, S2, S3) close the vacuous-pass behavior identified in the v0.10.1 baseline. Across 9 evaluable attempts on `001-two-agent-auth` (Claude Opus 4.7 3/3, Gemini 3 Pro Preview 3/3, gpt-5.5 3/3 after auth-tier substitution): **zero attempts exhibit unevaluable-PBT-counted-as-pass behavior**. Eight attempts land at grade B (the design ceiling per E3); one gpt-5.5 attempt lands at grade F due to a structural feature-scan miss (`missing_required: ["Result"]`, agent omitted Result types in the solution), independent of the v0.10.2 soundness layer. **F-101 (S1+S3 acceptance) confirmed; F-102 (OpenAI auth) resolved by substitution; F-103 (B/C boundary) remains null per panel composition.**

## Sample composition

| Panel | Model | Attempts | Status | Grade |
|---|---|---|---|---|
| `20260510T201142Z` | claude-opus-4-7 | 3 | passed | B / B / B |
| `20260510T201142Z` | gemini-3-pro-preview | 3 | passed | B / B / B |
| `20260510T201142Z` | codex-gpt-5.5-codex | 3 | agent_failed | — (auth-rejected) |
| `20260510T204345Z` | codex-gpt-5.5 | 3 | agent_failed | — (auth-rejected) |
| `20260510T205132Z` | gpt-5.5 | 3 | passed | F / B / B |
| **Total** | | **15** | **9 passed, 6 agent_failed** | **8 × B, 1 × F** |

Comparable v0.10.1 baseline: 18 attempts × 5 models × 3 tries, 11 passing runs (61%), grade-B/C distribution influenced by E1 label-driven boundary and S3 vacuous-pass mechanics.

## Verified findings

### F-101. Soundness blockers closed (S1 + S3 acceptance criteria met)

**Priority:** High
**Consumer:** user (validation only — no downstream hand-off)

#### Evidence

`runs/20260510T201142Z/20260510T201142Z-claude-opus-4-7-try01-of-03-e001/evaluation.json` (representative shape; identical structure across all 6 Claude+Gemini grade-B passes):

```json
{
  "quality_grade": "B",
  "test_assessment": {
    "effective_total": 1, "effective_passed": 1,
    "excluded_delegation_dependent": 1,
    "all_applicable_passed": true
  },
  "verify_summary": { "verified": 0, "tested": 0, "asserted": 1, "no_contract": 1 }
}
```

`runs/20260510T205132Z/20260510T205132Z-gpt-5.5-try02-of-03-e001/evaluation.json` (representative gpt-5.5 grade-B):

```json
{
  "quality_grade": "B",
  "test_assessment": {
    "effective_total": 2, "effective_passed": 2,
    "excluded_delegation_dependent": 0,
    "all_applicable_passed": true
  },
  "verify_summary": { "verified": 0, "tested": 0, "asserted": 1, "no_contract": 2 }
}
```

The `excluded_delegation_dependent` count varies across solutions (1 for Claude/Gemini, 0 for gpt-5.5) because the agents structured their property bodies differently — gpt-5.5's tests were statically evaluable (concrete bool outputs) while Claude/Gemini's directly-delegating bodies were not. Both code paths are sound under v0.10.2: evaluable bodies pass on their merits, unevaluable bodies discard via `QC.discard` (S3) rather than vacuous-pass. **No attempt exhibits the v0.10.1 signature of `effective_passed > 0` driven by unevaluable property bodies.**

#### Why we saw what we saw

S1 (`compiler/src/LLMLL/TypeCheck.hs:1037-1042`) typechecks the `?delegate` fallback against the return type, so ill-typed `(Result.Error DelegationError)` no longer passes typecheck. S3 (`compiler/src/LLMLL/PBT.hs:238-241`) returns `QC.discard` on samples that don't reduce to `LitBool`, eliminating the default-True path. Both fixes' acceptance criteria from `findings/compiler-engineer.md` are met.

#### Implication

Routing: **user** (validation finding). v0.10.2 fixes behave as predicted across all three model providers' top-tier panels.

#### Acceptance

Confirmed.

---

### F-102. OpenAI auth-tier rejects Codex `gpt-5.5*` family — substitution resolved

**Priority:** Defence-in-depth (resolved within this batch)
**Consumer:** user

#### Evidence

`runs/20260510T201142Z/20260510T201142Z-codex-gpt-5.5-codex-try01-of-03-e001/logs/agent.stdout.log` and `runs/20260510T204345Z/20260510T204345Z-codex-gpt-5.5-try01-of-03-e001/logs/agent.stderr.log` both record:

```
ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error",
        "message":"The 'codex-gpt-5.5{-codex,}' model is not supported when
        using Codex with a ChatGPT account."}}
```

Auth status confirmed: `codex login status` → "Logged in using ChatGPT". Substitution test (`codex exec --dangerously-bypass-approvals-and-sandbox 'Say hello'` with no `--model` flag) resolved to default `gpt-5.5`, executed cleanly: 1,351 tokens, "Hello." response, no API-400. Substituted manifest (`manifest.gpt-5.5-e001.json`) ran 3/3 evaluable attempts.

#### Why we saw what we saw

The local Codex CLI's ChatGPT-account auth tier exposes a different model surface than API-key auth. `codex-gpt-5.5-codex` and `codex-gpt-5.5` are API-key-only on this account; bare `gpt-5.5` (without the Codex prefix) is the ChatGPT-tier identifier for the same family. The CLI's own help text uses `o3` as the example model, indicating multiple ChatGPT-tier-allowed identifiers exist.

#### Implication

Routing: **user**. Resolved within this batch via model substitution. Future panels comparing OpenAI under ChatGPT-tier auth should use `gpt-5.5` (or whatever identifier `codex login status` and a no-flag default-model probe reveal at run time). API-key auth would restore the `codex-gpt-5.5*` surface but is not required for the validation hypothesis.

#### Acceptance

Resolved. Substitution path documented; the gpt-5.5 panel produced n=3 evaluable attempts that participate in F-101's validation.

---

### F-103. B/C boundary not measurable on this panel (null result)

**Priority:** Defence-in-depth
**Consumer:** user

#### Evidence

9/9 evaluable attempts → 8 grade B, 1 grade F. Zero grade-C exemplars across three panels. E1 (label-driven B/C boundary, EL-A overhaul deferred) cannot be measured without grade-C data points.

#### Why we saw what we saw

`001-two-agent-auth` carries a B ceiling per E3 (`evaluate_run.py:69-71`); top-tier models reliably reach the ceiling. The gpt-5.5 grade-F attempt is feature-scan-driven (`missing_required: ["Result"]`), not a near-pass that would have produced grade C — the F-vs-B distinction here is structural, not B/C-boundary-relevant.

#### Implication

Routing: **user**. The pre-stated tertiary prediction ("B/C boundary unchanged") is **not falsifiable on this data**. Null result.

#### Acceptance

Future panel produces ≥1 grade-C attempt enables E1 boundary measurement; or EL-A landing retires the question.

---

### F-104. gpt-5.5 per-try variance: 1/3 missed an explicitly-specified Result-type requirement

**Priority:** Defence-in-depth (descriptive)
**Consumer:** user

#### Evidence

`runs/20260510T205132Z/20260510T205132Z-gpt-5.5-try01-of-03-e001/evaluation.json`:

```json
{
  "quality_grade": "F",
  "feature_scan": {
    "required": ["def-interface", "delegate", "on-failure", "check", "pre", "Result"],
    "found": { "Result": false, "delegate": true, "on-failure": true, ... },
    "missing_required": ["Result"]
  },
  "test_summary": { "total": 2, "passed": 2 },
  "verify_summary": { "tested": 0, "asserted": 1, "no_contract": 1 }
}
```

The solution compiled, typechecked under `--strict`, ran 2/2 PBT passes, and registered the required contract — but the agent did not use `Result[…]` in any type position. Per-try outcomes for gpt-5.5: F / B / B (try01 / try02 / try03), agent durations 253 / 254 / similar seconds.

#### Why we saw what we saw

**Verified that the input was unambiguous.** `experiments/minimal-agent/experiments/001-two-agent-auth.md` explicitly names `Result[string, string]` three times: in the v0.3-features header (line 4), in the `login-handler` numbered requirements (line 23: `Returns a Result[string, string] — either the hashed password on success, or an error message`), and in the check-block instructions (line 32). The agent had unambiguous specification and did not satisfy it. **Not an input-surface gap; per-try model-attention failure.** Claude and Gemini produced 3/3 Result-using solutions in the same batch, but with n=3 per agent the variance comparison is observational, not inferential.

#### Implication

Routing: **user**. Not actionable on the v0.10.2 hypothesis or via input-prompt changes (the input is already explicit). Logged for descriptive context — gpt-5.5 on this manifest produces 67% structurally-complete solutions on `001` at first round; future runs against larger n could quantify whether this is systemic or per-try variance.

#### Acceptance

Larger-n run (e.g., 10+ tries per agent, or rerun against the panel after EL-A's evaluator overhaul lands) confirms or refutes the per-try variance pattern. Optional follow-up; not v0.10.2-blocking.

---

## Withdrawn items

None on this run. Pre-stated primary and secondary hypothesis predictions held; tertiary lands as null per F-103. The "Codex base substitution may pass where Codex-tuned variant failed" working hypothesis (between batches 1 and 2) was falsified — both `codex-gpt-5.5-codex` and `codex-gpt-5.5` rejected by ChatGPT-tier auth — and resolved by substituting bare `gpt-5.5` in batch 3. The "input-surface gap may explain F-104" working hypothesis (between F-104 surfacing and the read-back of `001-two-agent-auth.md`) was falsified — the input already names `Result[string, string]` three times.

## Null results

- **Tertiary prediction (B/C boundary unchanged):** null per F-103. Panel composition prevented falsification. n=0 grade-C attempts.
- **Codex `gpt-5.5*` substitution within Codex CLI's family:** falsified across both `-codex` and base variants on ChatGPT-tier auth. Resolved by stepping outside the `codex-` prefix to bare `gpt-5.5`.
- **Input-surface improvement to `001-two-agent-auth.md` would reduce gpt-5.5 Result-misses:** falsified by direct read of the problem statement. The spec already explicitly names `Result[string, string]`; further emphasis would be metric-shaping with no leverage.

## Process notes (drift gaps surfaced this run)

**Compiler-version-pin verification was incomplete in the prior run plan template.** The plan stated `Compiler version pin: llmll 0.10.2 (verified via llmll version)` but the verification step invoked `stack exec llmll -- version`, which resolves to `.stack-work/install/.../bin/llmll` (correct v0.10.2) rather than the bare `llmll` on PATH that the harness's `manifest.llmll_cmd: "llmll"` actually invokes. The bare-PATH binary at `~/.local/bin/llmll` was stale at v0.10.0 — last `stack install` predates v0.10.1. The first launch (`bd3e16r90`) was against the wrong compiler; recovered after partial scaffold (`claude-opus-4-7-try01` only, no agent execution), via `stack install` to push v0.10.2 to `~/.local/bin/llmll`, re-verifying with bare `llmll version`, and relaunching as `bji206ln0`. Batches 2 and 3 (`bmvw0ht8l`, `blw869t0b`) re-verified the bare-PATH binary before launch per the corrected procedure. **Logged for run-plan-template hygiene: future plans pin via bare `llmll version`, not `stack exec llmll --`.**

**Stale version label in `001-two-agent-auth.md` (incidental drift).** Line 4 reads `**v0.3 features exercised:** def-interface, ?delegate (blocking), on-failure, DelegationError`. The features themselves remain valid surface in v0.10.2, but the version label predates several language version bumps. Low priority; flag for the next harness-prompt hygiene pass alongside any other experiment-markdown freshening.

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| **F-101** | Soundness blockers closed (S1, S3 acceptance) | user (validation) | High | None — already shipped |
| **F-102** | OpenAI auth-tier substitution to bare `gpt-5.5` | user | Defence-in-depth | Resolved |
| **F-103** | B/C boundary null result | user | Defence-in-depth | Future panel design or post-EL-A re-run |
| **F-104** | gpt-5.5 per-try variance (descriptive, n=3) | user | Defence-in-depth | Optional larger-n follow-up |

## Per-consumer scoped files written

Single-file integrated postmortem; no per-consumer fragments. The v0.10.2 fix batch is already shipped (commits `17e11f4`, `a83eb19`, `3c811a4`, tag `v0.10.2`); no new spec, compiler, or doc-lead hand-offs surfaced.
