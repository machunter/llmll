# Postmortem 001 — Apparatus Validation

> **Phase:** 1 (apparatus validation, golden cell)
> **Date:** 2026-05-11
> **Author role:** experiment-lead
> **Status:** apparatus passed; Phase 2 unblocked pending user approval

## Headline finding

The repair-loop orchestrator closes the loop cleanly across `k=3` turns on a
golden-cell run using the deterministic stub agent (n=1 cell, 3 turns, 5
verifier commands per turn = 15 verifier invocations captured). All 10
apparatus-validation checks pass. Per-turn verifier output is captured
structurally and re-injected into the next turn's agent context; the
re-injection is empirically proven by the stub recording the prior turn's
context filename in its own stdout. The apparatus is ready for Phase 2 (real
agent on a known-tractable cell to exercise the terminal-target accept path).

## Sample composition

- **Cells:** 1 (n=1)
- **Agent:** stub (deterministic; not a real model)
- **Experiment:** `002-bank-ledger` (problem text from `problems/002-bank-ledger.md`)
- **Target:** `llmll`
- **Tries:** 1
- **Repair budget *k*:** 3
- **Turns executed:** 3 (full budget; terminal target not reached, by design — stub solution is intentionally invalid)
- **Compiler version pin:** `llmll 0.10.2` (captured automatically into `repair_loop_log.json:compiler_version_pin`)
- **Harness commit:** working tree post-`bb5b07e`; orchestrator and evaluator scaffolded this turn, not yet committed
- **Run directory:** `experiments/repair-loop/runs/20260511T132025Z-golden-cell-e002-bank-ledger-llmll/`
- **Terminal state:** `budget-exhausted` (expected; stub never produces a verifying solution)

## Verified findings

### F-001. Loop closes cleanly across the full repair budget

**Priority:** N/A (Phase 1 acceptance criterion satisfied)
**Consumer:** user

#### Evidence

`experiments/repair-loop/runs/20260511T132025Z-golden-cell-e002-bank-ledger-llmll/evaluation.json:apparatus.checks` records 10 of 10 apparatus checks passing. Of those, six are per-turn (artefact existence + verifier-result non-emptiness for each of turns 01/02/03), two are loop-level (terminal-state legal, ≥1 turn), and two are stub-specific (re-injection — see F-002).

#### Why we saw what we saw

`scripts/run_repair_loop.py:_run_one_turn` invokes the agent, runs the verifier chain via `_run_verifier_chain`, writes both `turns/turn_NN/verifier.json` and `context/turn_NN_verifier.json`, and evaluates the terminal predicate. The loop in `main` iterates up to `k` times, early-exits on terminal match or infrastructure failure, and sets `terminal_state` exhaustively (`target-reached` / `infrastructure-fail` / `budget-exhausted`). All three branches are reachable in code; this run exercised the `budget-exhausted` branch.

#### Implication

Phase 1 acceptance criterion is met: the apparatus is ready to be exercised on a real agent. No language-team or compiler-engineer hand-off is implied by this finding.

#### Acceptance

A second stub-agent run with `k=5` and the same configuration should also produce 10/10 apparatus checks passing and `terminal_state: budget-exhausted` with 5 turns. (Not run; not required for closing F-001.)

---

### F-002. Verifier-output re-injection is empirically proven

**Priority:** N/A (load-bearing design property; validation requirement of Phase 1)
**Consumer:** user

#### Evidence

`turns/turn_02/agent.stdout.log` line 2: `prior contexts: ['turn_01_verifier.json']`. `turns/turn_03/agent.stdout.log` analogously records seeing `turn_02_verifier.json`. The apparatus checks `stub-saw-prior-context-02` and `stub-saw-prior-context-03` both pass in `evaluation.json:apparatus.checks[6-7]`.

#### Why we saw what we saw

The stub at `scripts/run_repair_loop.py:_invoke_stub_agent` reads `context/turn_*_verifier.json` from the run directory at the start of each turn and writes the filenames into its own stdout. The orchestrator writes the prior turn's verifier output to `context/turn_NN_verifier.json` *before* invoking the agent for turn N+1, so the stub's read of the context directory between turns shows monotonic growth.

#### Implication

The orchestrator's re-injection seam — write context file → invoke agent → agent reads context file — is sound for stub. For a *real* agent (Claude / Gemini / Codex), the same seam will surface the verifier output to the agent through its file-reading tool. No additional plumbing is required between Phase 1 and Phase 2.

#### Acceptance

Closed by this run. Re-validates on every subsequent stub run as a regression sentinel.

---

### F-003. Verifier output is structurally usable for re-injection

**Priority:** Defence-in-depth
**Consumer:** user (forward-looking for Phase 2/3)

#### Evidence

Per-turn `verifier.json` captures all five LLMLL verifier commands (`check`, `check-strict`, `holes`, `test`, `verify`) with their `exit_code`, full `stdout`, full `stderr`, and parsed JSON where the command emits JSON. Truncation cap is 16k chars per channel (`_truncate` in `run_repair_loop.py`); on parse-error outputs the cap did not engage (largest captured stdout: ~1.1k chars).

Sample captured from turn 1, `check` command:

```
(error :phase parse :file "solution.llmll" :line 1 :col 1 :message "|
1 | ; stub agent — turn 1
  | ^
unexpected ';'
exp..."
```

JSON channels (`holes`, `verify`) produce parseable JSON even on rejection (e.g., `{"code":"E001","col":1,"file":"solution.llmll",...}`).

#### Why we saw what we saw

`llmll`'s diagnostic surface already emits structured S-expression or JSON on every command path, including the parse-error path. The orchestrator preserves both stdout and `parsed_json` so the next turn's agent context contains a fully machine-readable payload, not just truncated text.

#### Implication

Verifier-output ergonomics for repair-loop consumption appear adequate at the parse-error layer. **Open question for Phase 2/3:** whether the success-path payloads (specifically the trust report from `llmll verify`) are equally clean to consume; F-004 below names this as a Phase 2 prerequisite.

#### Acceptance

Phase 2 turns produce parseable trust reports that the orchestrator can read via `_count_bad_trust_tiers` without falling through to the schema-tolerant default.

---

### F-004. Terminal-target accept-path is unexercised by Phase 1

**Priority:** Medium (Phase 2 prerequisite)
**Consumer:** experiment-lead (self, Phase 2 design)

#### Evidence

`run_repair_loop.py:_evaluate_terminal_target` and `_count_bad_trust_tiers` contain the success-path predicate logic. In the Phase 1 stub run, every turn's `check` command fails at parse phase (`exit_code=1`), so the predicate short-circuits at `first_fail is not None` and the trust-report traversal never executes. The accept-branch (`return True, "all expected contracts verified or asserted"`) has zero coverage in Phase 1 runs.

#### Why we saw what we saw

The stub is engineered to produce an invalid solution, so the verifier chain fails immediately. The accept-branch of the predicate cannot be reached without a syntactically-valid LLMLL solution. This is by design for Phase 1 (we are testing the loop, not the predicate).

#### Implication

Phase 2 must include at least one cell where a real (or carefully crafted near-real) solution intentionally reaches `terminal_state: target-reached`, so the trust-tier traversal logic is empirically validated before Phase 3 commits to a full 81-cell matrix. Until F-004 is closed, the terminal-target predicate is *plausibly* correct but not *empirically* correct.

#### Acceptance

A Phase 2 cell produces `terminal_state: target-reached` with `terminal_reason: "all expected contracts verified or asserted"`. The `_count_bad_trust_tiers` traversal executes and returns 0.

---

### F-005. Compiler version pin is captured per-run automatically

**Priority:** N/A (skill-contract requirement satisfied)
**Consumer:** user

#### Evidence

`repair_loop_log.json:compiler_version_pin = {"version": "0.10.2"}`. Captured by `_capture_compiler_version` running `llmll version --json` (per `targets/llmll.json:version_pin_command`) at the start of the orchestrator run.

#### Implication

Reproducibility constraint satisfied without manual pin discipline. Future runs against later compiler versions will record the pin automatically; cross-run comparisons can filter on it.

## Withdrawn items

None. This is the first run; no prior claims to verify against.

## Null results

The run's `terminal_state: budget-exhausted` is itself an *expected null* on the convergence axis: the stub agent is engineered to not converge. This is not a failure mode of the apparatus or the language. It is documented here so future readers do not misread `budget-exhausted` as evidence against H1/H2/H3 — those hypotheses are evaluated only under Phase 3, and only against real agents.

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| F-001 | Loop closes cleanly | user | N/A (closed) | - |
| F-002 | Re-injection empirically proven | user | N/A (closed) | - |
| F-003 | Verifier output structurally usable | user | Defence-in-depth | tracked into Phase 2 |
| F-004 | Accept-path unexercised | experiment-lead | Medium | resolved by Phase 2 calibration cell (1 cell) |
| F-005 | Version pin captured automatically | user | N/A (closed) | - |

## Per-consumer scoped files

None written for this run. Phase 1 findings are integrated only. Per-consumer scoped files (`findings/compiler-team.md`, `findings/language-team.md`, `findings/documentation-team.md`) will be authored as Phase 2/3 surface findings against those consumers.

## Phase 2 readiness

Phase 1 satisfies its stated acceptance criterion. Phase 2 (calibration) prerequisites:

1. **F-004 resolution.** Phase 2 must include at least one cell where the terminal target is reached. Recommended: a 1-cell calibration run with `claude-opus-4-7` on `002-bank-ledger × llmll × k=5 × 1 try`, deliberately targeting a verifying solution.
2. **Python target adapter.** Phase 2's calibration matrix spans 3 languages. The `llmll` target adapter is built; `python` and `rust` adapters need to be authored. Approx 30-60 min per adapter following the shape of `targets/llmll.json`.
3. **Test kits for `002-bank-ledger` per language.** Empty `testkits/002-bank-ledger/{llmll,python,rust}/` directories exist; per-language black-box tests need authoring against the spec in `problems/002-bank-ledger.md`.
4. **Phase 2 user approval.** Per my skill contract, separate approval from Phase 1.

Phase 2 estimated cost (indicative, pending separate approval): ≤ 45 agent invocations, ≤ $50 API spend, ≤ 6 hours wall-clock serial.
