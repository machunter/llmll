# Postmortem-002 — Phase-3 Calibration Probe (first attempt)

> **Status:** Findings recorded; remediation in place at commit `<pending>`; re-probe authorized as a separate user turn.
> **Date:** 2026-05-15.
> **Batch dir:** `experiments/repair-loop/runs/20260515T192418Z-matrix/`.
> **Pre-stated purpose:** Verify the Phase-3 harness pipeline (manifest → `run_matrix.py` → `run_repair_loop.py` → agent CLI → verifier chain → evaluator → `matrix_report.json`) works end-to-end for the two paid agents on the existing `002-bank-ledger` testkit; pin per-cell wall-clock and cost ahead of full Phase-3 launch.
> **Outcome:** Pipeline works on the Codex side end-to-end; Claude side timed out silently. Three findings, two blockers + one defence-in-depth confirmation.

## Headline finding

The 540s per-turn timeout inherited from the Phase-2 (Gemini-calibrated) manifest is too short for Claude Code 2.1.141 and Codex 0.130.0 on the 002-bank-ledger × LLMLL cell shape. Both cells terminated at exactly 9:00 with `agent_rc = 124` (Unix timeout). Codex emitted a substantive 23-statement, parse-clean, 11-`?proof-required`-marker LLMLL solution before being killed mid-stream (its 839KB of reasoning-trace stderr confirms it was actively working, not stuck); Claude emitted 0 bytes of stdout and 0 bytes of stderr in its 540s window. Stop-fast disciplines worked as designed: discipline C (compiler health probe) caught a broken fixture on the first probe launch (rc=1, no agent cost) and the circuit breaker (B) halted the matrix at cell 2 with rc=2 once both cells returned `infrastructure-fail`, bounding total wasted cost to one probe budget (order $3–$7).

## Sample composition

- **Total cells:** 2. `claude-default × 002-bank-ledger × llmll × k=5 × try1` (cell 1); `codex-default × 002-bank-ledger × llmll × k=5 × try1` (cell 2).
- **Compiler:** 0.10.6 (toolchain pin discipline A verified at pre-flight).
- **Harness commits:** `24ad6a4` (bootstrap with stop-fast disciplines), `91162d5` (post-fixture-fix).
- **Agent versions:** Claude Code 2.1.141, codex-cli 0.130.0 (default `gpt-5.5` model at `xhigh` reasoning effort per stage-1 smoke-test capture).
- **Auth path:** Claude via OAuth/keychain (stage-1 verified `claude --print --allow-dangerously-skip-permissions --no-session-persistence` returns OK without `ANTHROPIC_API_KEY` set); Codex via `OPENAI_API_KEY`.
- **Run dirs:** `runs/20260515T192418Z-matrix/` (matrix aggregate); `runs/20260515T192418Z-claude-default-try01-of-01-c01-e002-bank-ledger-llmll/` (cell 1); `runs/20260515T193322Z-codex-default-try01-of-01-c02-e002-bank-ledger-llmll/` (cell 2).
- **Matrix rc:** 2 (circuit breaker tripped after 2/2 consecutive `infrastructure-fail` per discipline B at threshold 2).

## Verified findings

### F-035. 540s/turn timeout too short for Claude Code 2.1.141 and Codex 0.130.0 on 002-bank-ledger × LLMLL

**Priority:** Blocker (Phase-3 launch cannot proceed without resolution).
**Consumer:** experiment-lead (manifest decision) + user (R-config adjudication).

#### Evidence

Both cells exited at exactly the 540s ceiling with `agent_rc = 124` and `agent_error = "timeout after 540s on turn 1"`. From `runs/20260515T192418Z-claude-default-…-c01-…/repair_loop_log.json`: cell 1 agent started `19:24:19Z`, killed `19:33:19Z` (Δt = 540s). From `runs/20260515T193322Z-codex-default-…-c02-…/repair_loop_log.json`: cell 2 agent started `19:33:23Z`, killed `19:42:23Z` (Δt = 540s).

Codex cell partial-completion record (`verifier_results` extracted post-kill):

| Verifier command | Exit | Output summary |
|---|---|---|
| `llmll check solution.llmll` | 0 | `OK (23 statements, 11 warnings)` — 11 `?proof-required` markers correctly used |
| `llmll check solution.llmll --strict` | 0 | Same |
| `llmll test solution.llmll` | (recorded; partial extract) | Passed 2 PBT samples, skipped 4 |
| `llmll verify solution.llmll --trust-report --weakness-check --spec-coverage` | (recorded) | 2 locally-verified obligations, 0 outstanding trust acknowledgments |

`evaluation.json` for cell 2 records `correctness_subscores.core_behavior = 0.333` (2 passed / 4 skipped / 0 failed), `assurance_subscores.test_quality.pbt_sample_pass_rate = 0.333` and `agent_emitted_test_count = 6`, `assurance_subscores.proof_or_trust_evidence.locally_verified_obligations = 2`. The work produced was substantive; the kill came mid-stream.

Cell 1 emitted no artifacts in `turns/turn_01/` other than the `NO_SOLUTION` sentinel; `agent.stdout.log` and `agent.stderr.log` are both 0 bytes.

#### Why we saw what we saw

Phase-2 calibration was a Gemini-default cadence on default reasoning depth, which typically completes turns in seconds to low minutes. Phase-3 paid agents have different latency profiles:

- **Codex** at default `xhigh` reasoning effort emits 1,367 tokens for the trivial "Reply with the literal word OK" smoke-test prompt (stage-1 capture). For a real task with file injection (problem.md, TARGET.md, AGENT_INSTRUCTIONS.md), wall-clock latency under `xhigh` is multi-minute. 9 minutes was insufficient.
- **Claude Code** agentic loops include multiple tool-call rounds (file reads, file writes, multiple inference calls) per turn. Reading the injected `LLMLL.md` (131KB) alone is non-trivial, and the agent may chain multiple read/write rounds before emitting `solution.llmll`. 9 minutes was insufficient for Claude as well (though see F-036 for the orthogonal question of why Claude emitted 0 bytes rather than partial output).

The 540s ceiling was inherited from `manifest.phase2-calibration.json` without adjustment for paid-agent latency.

#### Implication

Three remediation paths, each with trade-offs:

| Path | Action | Per-cell wall ceiling | Per-cell cost (est.) | Phase-3 wall total (81 cells) | Phase-3 cost total (est.) |
|---|---|---|---|---|---|
| **R1 — bump timeout, keep reasoning** | `timeout_seconds_per_turn: 1800` (30 min); leave Codex at `xhigh` | k=5 × 1800s = 150 min worst, ~10–30 min typical | $1–$5 | ~13–40 hrs (typ.) | $80–$400 |
| **R2 — bump + reduce Codex reasoning** | `timeout_seconds_per_turn: 1200` (20 min); add `-c model_reasoning_effort=medium` to codex cmd | k=5 × 1200s = 100 min worst, ~5–15 min typical | $0.50–$2 | ~7–20 hrs (typ.) | $40–$160 |
| **R3 — per-agent timeouts** | 1800 for paid agents, 540 for Gemini (requires harness change to support per-agent timeout override) | Same as R1 for paid | Same as R1 | Same | Same |

**Chosen: a simplification of R3 → R1 in practice.** Bumping the flat `timeout_seconds_per_turn` to 1800 in both `manifest.phase3-calibration-probe.json` and `manifest.phase3.json`. Gemini under 1800s still completes well under the ceiling (Phase-2 cells were minutes-to-low-tens-of-minutes), so the higher ceiling does not slow Gemini cells. This avoids a harness-change burden for per-agent overrides while resolving the F-035 blocker.

R2's reasoning-effort reduction is a separate cost-vs-quality decision deferred until the re-probe data lands at `xhigh`. The cell-2 (Codex `xhigh`) solution looked competent on first inspection — it correctly identified map projections as outside QF-LIA and marked them `?proof-required` per spec. Whether `medium` reasoning produces similar quality is unmeasured.

#### Acceptance

Re-probe under the bumped timeout completes both cells with `terminal_state ∈ {target-reached, budget-exhausted}` and `agent_rc = 0` (clean exit, not timeout-killed). Pinned per-cell wall-clock and token spend captured for Phase-3 budgeting.

---

### F-036. Claude `--print` produced 0 bytes of stdout/stderr in 540s before timeout-kill

**Priority:** High (orthogonal to F-035; even with bumped timeout, the silence-vs-substantive-emission delta needs disambiguation).
**Consumer:** experiment-lead (diagnostic instrumentation) + user (auth-path decision if subprocess-keychain hypothesis is confirmed).

#### Evidence

`runs/20260515T192418Z-claude-default-…-c01-…/turns/turn_01/`:

- `agent.stdout.log`: 0 bytes
- `agent.stderr.log`: 0 bytes
- `NO_SOLUTION` sentinel present
- No `solution.llmll` / `solution.ast.json` / any intermediate artifact

By contrast, the Codex cell in the same 540s window emitted 839,832 bytes of reasoning-trace stderr plus a 7,851-byte `solution.llmll`. The stream difference is stark — Claude was silent throughout; Codex was active throughout.

The stage-1 smoke test (commit `7f323f6`) ran `claude --print --allow-dangerously-skip-permissions --no-session-persistence 'Reply with the literal word OK'` in the same Bash-subprocess context the matrix uses and returned `OK` in seconds, confirming the cmd shape works for trivial prompts.

#### Why we saw what we saw — three candidate hypotheses, no disambiguation yet

1. **Output buffering hypothesis.** Claude `--print` (default text output mode) may buffer its output until completion. If killed mid-stream by SIGKILL at 540s, nothing has been flushed to stdout. Codex by contrast streams its reasoning trace progressively to stderr, which is why Codex's stderr remains large even after kill. Diagnostic move: bump timeout (R1) and observe whether Claude completes and flushes within 1800s. If yes, this hypothesis is confirmed and the fix is the bumped timeout itself.

2. **Subprocess keychain hang hypothesis.** macOS Security framework may not give a multi-layer-subprocess context the same keychain access a TTY-attached shell has. Claude might silently hang trying to resolve OAuth credentials in the subprocess environment. *Partially weakened*: the stage-1 smoke test ran via the same Bash-subprocess chain and worked. Either the subprocess context retains keychain access through the chain, or Claude's auth resolution differs between trivial-prompt and real-task code paths (plausible but unverified). Diagnostic move: set `ANTHROPIC_API_KEY` explicitly in the subprocess environment for a focused re-test; the operator has to supply the key value.

3. **Slow-startup hypothesis.** Claude Code's CLI startup involves plugin sync, MCP server resolution, and other cold-start work even with `--allow-dangerously-skip-permissions`. Stage-1's `--bare` flag (which suppresses these) was dropped at commit `7f323f6` because `--bare` strictly requires `ANTHROPIC_API_KEY` and the operator authed via OAuth. With `--bare` removed, Claude may be spending a substantial fraction of the 540s on startup before reaching the actual task. Diagnostic move: set `ANTHROPIC_API_KEY` *and* re-add `--bare` to the cmd; the auth-model switch is in operator scope.

Hypothesis 1 is the cheapest to disambiguate — it requires no operator action beyond the bumped-timeout re-probe authorized in F-035. Hypotheses 2 and 3 require operator-side credential management.

#### Implication

F-036 is *underdetermined on probe data alone.* The bumped-timeout re-probe (F-035 remediation) is also the first-pass diagnostic for hypothesis 1. If Claude completes cleanly under 1800s, F-036 is closed under hypothesis 1; if Claude still emits 0 bytes after 1800s, hypotheses 2/3 are live and the operator needs to either set `ANTHROPIC_API_KEY` (testing hypothesis 2) or set it + re-add `--bare` (testing hypothesis 3 jointly).

Without resolution, Claude is unusable in the Phase-3 matrix even with a bumped timeout.

#### Acceptance

A re-probe Claude cell produces non-zero stdout-or-stderr volume during its turn. The operator can attribute the silence (or its resolution) to one of the three hypotheses or surface a fourth.

---

### F-037. Stop-fast disciplines A, B, C all fired as designed; total wasted cost bounded to probe budget

**Priority:** Defence-in-depth (validation finding; no closeable action).
**Consumer:** user (informational); future experiment-lead turns benefit from the empirical confirmation.

#### Evidence

- **Discipline C (compiler health probe).** First probe launch (background task `bj5svli0r`, 2026-05-15T19:22Z) aborted at pre-flight with rc=1. `run_matrix.py:check_compiler_health` ran `llmll check` on `scripts/fixtures/health-probe.llmll` and found a parse error at line 14 col 3 on the `:type` keyword — the fixture authored at bootstrap commit `24ad6a4` used a `:type [(int) -> int]` form and `(lambda (n) n)` body wrap that do not exist in the v0.10.6 LLMLL surface. The matrix did not start; zero agent cost. Fix landed at commit `91162d5`; second launch passed the health probe.
- **Discipline A (toolchain pin verification).** Second launch passed `llmll 0.10.6` pin verification at pre-flight (no failure surfaced; otherwise the matrix would not have started).
- **Discipline B (per-cell circuit breaker).** Both cells returned `terminal_state: infrastructure-fail`. Threshold for the probe was 2 (per `manifest.phase3-calibration-probe.json:_circuit_breaker_consecutive_infra_fail`). Discipline B tripped at cell 2; matrix returned rc=2 with `circuit_breaker_tripped: {consecutive_infra_fail: 2, threshold: 2, tripped_after_cell: 2}` recorded in `matrix_report.json`. (The probe only had 2 cells; the trip prevented any phantom cell 3 by structure, but the mechanism worked as designed and the field landed in the report for post-hoc inspection.)

#### Why we saw what we saw

Disciplines A, B, C were designed for this class of failure mode and worked as designed. No surprise.

#### Implication

Discipline value empirically confirmed:

- Discipline C caught a fixture-shaped failure that would have produced confusing behavior under a less-protected harness — the matrix would have launched, run agents, and produced inscrutable parse-failure data with no operator-facing signal pointing at the fixture. Instead the fixture was flagged explicitly and zero agent cost was spent.
- Discipline B caught the F-035 timeout misconfiguration at the 2-cell mark. Under a non-circuit-broken harness, a full 81-cell Phase-3 launch would have run all 81 cells to the 540s timeout each, burning through real money before the operator noticed the pattern. Discipline B halted at cell 2; the cost of the misconfiguration was bounded to the probe budget — order-of-magnitude saving on wasted spend.

#### Acceptance

N/A — defence-in-depth confirmation, not closeable. The disciplines stay in place.

---

## Withdrawn items

None. The probe's pre-stated hypotheses (`harness pipeline works end-to-end`, `per-cell cost pins`) are partially supported: the Codex side ran end-to-end (modulo the timeout-kill); cost per cell pins at order $3–$5 for Codex `xhigh` (the second-pass cost-extrapolation in F-035's implication table is informed by this single data point and remains loose).

## Null results

The probe's H1 / H2 / H3 hypotheses (`docs/design/phase3-problem-shape-audit.md` §"002 — Bank Ledger" predictions) cannot be evaluated from this run. Both cells terminated as infra-fail before the relevant signals (`tier_profile_post`, behavioral test pass-rate, agent convergence) could be aggregated for hypothesis testing. Re-probe after F-035 + F-036 are addressed.

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| F-035 | 540s/turn timeout too short for paid agents | experiment-lead + user | Blocker | Manifest one-line edit (landed in this commit) + re-probe (~$5–$15) |
| F-036 | Claude `--print` silent in 540s window | experiment-lead + user | High (orthogonal) | Re-probe-as-disambiguation (hypothesis 1); if unresolved, $0 + operator-side env-var setup (hypotheses 2/3) |
| F-037 | Stop-fast disciplines worked as designed | user (informational) | Defence-in-depth | None |

## Per-consumer scoped files

This postmortem is the integrated report; no per-consumer fragments are routed because:

- `findings/compiler-engineer.md`: no compiler-side finding from this probe (Codex's solution passed `llmll check` and `check-strict`; the only compiler interaction was a verified-clean health-probe parse on the corrected fixture).
- `findings/language-team.md`: no spec-side finding from this probe (no `LLMLL.md` surface implicated; no audit prediction revised — predictions remain unevaluable until re-probe data lands).
- `findings/documentation-team.md`: no docs-side finding.

If the re-probe surfaces spec-side or compiler-side issues, those will route through fresh per-consumer fragments at that time.

## Closing — re-probe readiness

`timeout_seconds_per_turn` is bumped to 1800 in both `manifest.phase3-calibration-probe.json` and `manifest.phase3.json` in the same commit as this postmortem. The probe is now re-launchable without further configuration changes. Re-launch cost estimate: $5–$15 (informed by the single Codex data point; could trend higher if Claude's silence resolves and Claude burns comparable tokens). The re-probe is the next experiment-lead-authored turn, but requires a separate user "go" authorization given the cost.

Pre-launch checklist for Phase-3 (from `commit 24ad6a4` surfacing, status updated):

| Item | Owner | Status |
|---|---|---|
| 001 / 003 testkits + manifest.phase3.json + stop-fast disciplines | experiment-lead | ✅ `24ad6a4` |
| Audit pin rebind to testkit files | language-team | ✅ `e63ebd9` |
| Claude / Codex CLI invocation pattern verification | experiment-lead / operator | ✅ `7f323f6` (stage 1) |
| **Per-turn timeout calibration for paid agents** | experiment-lead | ✅ `<this commit>` (postmortem-002 F-035) |
| **Claude silence diagnostic (F-036 hypothesis 1 first-pass)** | experiment-lead | ⏳ pending re-probe |
| Calibration probe — agents × `002` × `llmll` smoke | experiment-lead | ⏳ partial (first attempt; re-probe needed) |
| Audit `Launch-commit-hash` field fill | language-team | ⏳ pending (at launch) |
| `experiments/repair-loop/README.md` phase-table flip | experiment-lead | ⏳ pending (after re-probe clean) |
| `docs/design/INDEX.md` row for phase3-problem-shape-audit | doc-lead | ⏳ optional, non-blocking |
