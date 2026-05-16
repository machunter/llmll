# Postmortem-003 — Phase-3 Calibration Probe (third attempt)

> **Status:** Findings recorded; F-039 cmd-string regression closed in this commit's manifest edits; F-036 hypothesis 5 candidate-1 (`--add-dir {run_dir}`) refuted by data; escalation to candidate-2 (settings.json injection per per-cell `.claude/settings.json`) authorized as the next experiment-lead turn pending separate user "go".
> **Date:** 2026-05-15.
> **Continuity:** Continues postmortem-002's lineage. The third probe was authorized by the operator under Path B (claude-only relaunch, codex deferred for unresolved F-038 quota) at 2026-05-15T23:35Z. The F-036 hypothesis 5 disambiguation was the load-bearing question this probe was designed to answer; the cmd-string regression at commit `6514d19` (F-039) was an unanticipated finding the probe surfaced first.
> **Batch dirs:** `experiments/repair-loop/runs/20260515T233515Z-matrix/` (attempt 1, cmd-bug); `experiments/repair-loop/runs/20260515T234129Z-matrix/` (attempt 2, hypothesis-5 refutation).
> **Pre-stated purpose:** Disambiguate F-036 hypothesis 5: does Claude `--add-dir {run_dir}` lift the session-sandbox write block, or is settings.json injection (candidate-2) escalation required.
> **Outcome:** Two findings closed (F-039 cmd-string regression; F-036 hypothesis 5 candidate-1). One next-step authorization surfaced (candidate-2). One defence-in-depth confirmation continued from postmortem-002 (F-037).

## Headline finding

The third-probe sequence produced two distinct infrastructure-class findings:

1. **F-039 (new):** the `--add-dir {run_dir}` remediation shipped at commit `6514d19` had a CLI-argument-parsing collision with the trailing prompt positional. `--add-dir <directories...>` is variadic per `claude --help`; placed immediately before the prompt positional, it consumed the prompt as a second "directory", leaving Claude with no prompt argument. Attempt 1 exited rc=1 in 7 seconds with `Error: Input must be provided either through stdin or as a prompt argument when using --print`. Fix: reorder cmd to put `--add-dir {run_dir}` first, followed by `--print` (which terminates the variadic). Edit landed in three manifests this commit.
2. **F-036 hypothesis 5 candidate-1 refutation:** with the cmd fixed, attempt 2 ran 5 turns at `agent_rc=0` each (per-turn 5:09 to 9:14, total ~34 min). All 5 turns ended `NO_SOLUTION`; `verifier_results = []` each turn (no `solution.llmll` for the verifier chain to run on). Claude's stdout grew across turns (1152 → 7675 bytes) and named the failure mode in unusual specificity: every Write/Bash write path tested was blocked by the session sandbox, even with the run dir in the printed allow-list and `dangerouslyDisableSandbox: true` set. Per Claude's own diagnosis: "the `--add-dir {run_dir}` remediation flips the error-message allow-list but does not flip the underlying check." Candidate-1 is refuted; candidate-2 (per-cell settings.json injection with explicit `Write`/`Bash` permissions, supplied via `--settings <path>`) is the next remediation move from the postmortem-002 Addendum 1 menu.

Both attempts ran under the F-035 timeout-bump (1800s/turn from `d149980`); neither hit the timeout ceiling. F-035 closes definitively. F-038 (OpenAI quota) was unresolved at probe-authorization time, which is why the probe was Path B (claude-only); F-038 status unchanged.

## Sample composition

- **Total cells:** 2 (1 attempt 1 + 1 attempt 2 against the same single-cell Path B claude-only manifest).
- **Compiler:** 0.10.6 (discipline A pin verified at pre-flight on attempt 2; attempt 1 failed pre-agent invocation).
- **Harness commits:** `c969c49` (pre-launch service status check codified) carrying the `6514d19` `--add-dir` remediation; cmd-reorder edits to `manifest.phase3-calibration-probe-claude-only.json`, `manifest.phase3-calibration-probe.json`, and `manifest.phase3.json` landed mid-session and are part of this commit.
- **Agent versions:** Claude Code 2.1.141.
- **Auth path:** Claude via OAuth/keychain (unchanged from postmortem-002).
- **Run dirs:**
  - Attempt 1 (cmd-bug): `runs/20260515T233515Z-matrix/` (matrix); `runs/20260515T233516Z-claude-default-try01-of-01-c01-e002-bank-ledger-llmll/` (cell 1).
  - Attempt 2 (hypothesis-5 refutation): `runs/20260515T234129Z-matrix/` (matrix); `runs/20260515T234129Z-claude-default-try01-of-01-c01-e002-bank-ledger-llmll/` (cell 1).
- **Matrix rc:** Attempt 1 = 2 (circuit breaker tripped at threshold 1 after one infra-fail). Attempt 2 = 0 (cell completed budget-exhausted, not infra-fail; breaker correctly did not trip).
- **Manifest used:** `manifest.phase3-calibration-probe-claude-only.json` (Path B sibling carved from `manifest.phase3-calibration-probe.json` for this session; codex agent dropped, circuit-breaker threshold lowered to 1 because single-cell).
- **Probe service-status gate at authorization:** `status.claude.com` Clean and `status.openai.com` Clean (both operator-confirmed). OpenAI quota gate failed (operator: "Still exhausted / unsure") — Path B selected for that reason.

## Verified findings

### F-039. Claude `--add-dir <directories...>` variadic-positional collision broke first attempt's CLI parse

**Priority:** Blocker (closed in this commit's manifest edits).
**Consumer:** experiment-lead.

#### Evidence

Attempt 1 cell 1 exited rc=1 after 7 seconds (`runs/20260515T233516Z-…-c01-…/repair_loop_log.json:turns[0]`: started `2026-05-15T23:35:18Z`, finished `2026-05-15T23:35:25Z`). Stderr (`turns/turn_01/agent.stderr.log`, full 94-byte content):

```
Error: Input must be provided either through stdin or as a prompt argument when using --print
```

Stdout 0 bytes. Materialized cmd at invocation time (post `{run_dir}` substitution at [`run_repair_loop.py:386`](../scripts/run_repair_loop.py#L386)):

```
claude --print --allow-dangerously-skip-permissions --no-session-persistence \
       --add-dir /Users/.../runs/20260515T233516Z-claude-default-…-llmll \
       'Read AGENT_INSTRUCTIONS.md ...'
```

Machine-checked Claude help (this session, Claude Code 2.1.141):

```
--add-dir <directories...>   Additional directories to allow tool access to
-p, --print                  Print response and exit (useful for pipes). ...
```

`--add-dir` is variadic (`<directories...>`); `--print` is a switch (no value). With no `--`-prefixed flag between `--add-dir` and the prompt positional, the variadic consumed `'Read AGENT_INSTRUCTIONS.md ...'` as a second directory, leaving Claude with no prompt argument.

Matrix circuit breaker (discipline B at threshold 1 for this single-cell probe) tripped after cell 1; matrix returned rc=2 with `circuit_breaker_tripped: {consecutive_infra_fail: 1, threshold: 1, tripped_after_cell: 1}` (`runs/20260515T233515Z-matrix/matrix_report.json:104-108`).

#### Why we saw what we saw

Variadic argv flags consume subsequent argv tokens until either (a) another `--`-prefixed flag, (b) `--` separator, or (c) end of argv. The cmd-string at commit `6514d19` placed `--add-dir {run_dir}` immediately before the prompt positional, putting the prompt in case (c) — eaten as a directory.

The cmd-string at `6514d19` was unverified at landing time: postmortem-002's stage-1 smoke test (commit `7f323f6`) ran a different cmd shape (`--bare`-less, no `--add-dir`); the postmortem-002 Addendum 2 re-probe ran without `--add-dir` at all (which is what produced the sandbox-blocker narration that motivated the `--add-dir` remediation in the first place). Neither test exercised the actual `--add-dir`-bearing cmd, so the variadic collision shipped silently into all three Phase-3 manifests at `6514d19`.

#### Fix

Reorder the cmd to place `--add-dir {run_dir}` first, followed immediately by `--print` (which terminates the variadic):

- **Before** (broken at `6514d19`):
  ```
  claude --print --allow-dangerously-skip-permissions --no-session-persistence \
         --add-dir {run_dir} 'Read ...'
  ```
- **After** (fixed in this commit's edits):
  ```
  claude --add-dir {run_dir} --print --allow-dangerously-skip-permissions \
         --no-session-persistence 'Read ...'
  ```

Edit applied to all three manifests this session (Path B + the two original Phase-3 manifests for downstream-launch consistency):

- `experiments/repair-loop/manifest.phase3-calibration-probe-claude-only.json` (Path B sibling)
- `experiments/repair-loop/manifest.phase3-calibration-probe.json` (original 2-cell probe)
- `experiments/repair-loop/manifest.phase3.json` (81-cell Phase-3 launch)

#### Acceptance

Re-attempt produces non-rc=1 startup. **Confirmed** by attempt-2 relaunch immediately following the edits: cell 1 ran 5 full turns at `agent_rc=0` each (rc=1 cmd-parse error did not recur).

#### Defence-in-depth implication

A pre-launch agent-cmd dry-run (`<cmd> --help`-style or trivial-prompt smoke) for any agent whose cmd carries variadic-style placeholders would have caught F-039 at zero agent cost. Logged as a candidate harness extension under "future stop-fast disciplines"; not blocking now (the brittle case is rare and the discipline B circuit breaker bounded the cost to one 7-second attempt anyway). Worth raising if a similar variadic-positional collision recurs.

---

### F-036 final adjudication. Hypothesis 5 candidate-1 (`--add-dir {run_dir}`) refuted; escalation to candidate-2 (settings.json injection) authorized

**Priority:** Blocker (Phase-3 Claude side cannot launch without further remediation).
**Consumer:** experiment-lead + user (candidate-2 implementation authorization).

#### Evidence

Attempt 2 cell 1 (`runs/20260515T234129Z-claude-default-…-c01-…/repair_loop_log.json`) ran the full repair budget:

| Turn | Started | Finished | Δt | `agent_rc` | `terminal_target_match` | `terminal_target_reason` |
|---|---|---|---|---|---|---|
| 1 | 23:41:29Z | 23:50:43Z | 9:14 | 0 | false | "no expected solution file present" |
| 2 | 23:50:43Z | 23:58:11Z | 7:28 | 0 | false | "no expected solution file present" |
| 3 | 23:58:11Z | 00:03:51Z | 5:40 | 0 | false | "no expected solution file present" |
| 4 | 00:03:51Z | 00:10:26Z | 6:35 | 0 | false | "no expected solution file present" |
| 5 | 00:10:26Z | 00:15:35Z | 5:09 | 0 | false | "no expected solution file present" |

Per-turn artifacts:

| Turn | `agent.stdout.log` | `agent.stderr.log` | `solution.llmll` | `verifier_results` |
|---|---|---|---|---|
| 1 | 1152 B | 0 B | absent | `[]` |
| 2 | 1678 B | 0 B | absent | `[]` |
| 3 | 2403 B | 0 B | absent | `[]` |
| 4 | 6779 B | 0 B | absent | `[]` |
| 5 | 7675 B | 0 B | absent | `[]` |

Terminal state `budget-exhausted` (`5 turns elapsed without terminal match`); matrix rc=0; circuit breaker correctly did not trip (cell exited budget-exhausted, not infra-fail).

Turn-1 stdout (verbatim, full 1152-byte content):

> The harness sandbox is denying every write attempt to the run directory, even though the error message itself confirms that directory is the configured working directory. Both `Write` (which queues a permission prompt) and `Bash` shell redirection (which is hard-denied at the sandbox layer) fail with the same path. This matches the F-035/F-036 infrastructure-permission class documented in `findings/postmortem-002.md` — the `--add-dir {run_dir}` remediation from commit 6514d19 appears not to grant write permission, only read.
>
> I cannot write `solution.llmll` or `solution.ast.json` under these conditions. For the orchestrator's record, the solution I produced (`bank-ledger` module: list-of-pairs representation, `lookup-balance`/`account-exists?`/`apply-delta` helpers with `weakness-ok`, `transfer` with `pre (> amount 0)` and `post ?proof-required` for conservation/per-account-deltas, five `check` blocks singleton-covering `transfer` for PBT-Lift) is present verbatim in the Write tool call earlier this turn but never reached disk. This turn should be classified as an agent-infrastructure failure rather than a solution-quality failure.

Turn-5 stdout (key paragraph; full `solution.llmll` draft also present in lines 12-160 of the file):

> Solution emission blocked again — same F-035/F-036 class sandbox-vs-allow-list contradiction documented across turns 1–4. Every write path tested this turn fails with a self-contradicting error:
>
> - `Write` tool → returns "Claude requested permissions … but you haven't granted it yet" (no permission UI in headless harness).
> - `cat > solution.llmll` (heredoc, both absolute and relative path) → blocked: *"may only write to files in the allowed working directories for this session: '/Users/.../runs/…-bank-ledger-llmll'"* — that path IS the run directory.
> - `cat > …` with `dangerouslyDisableSandbox: true` → same block.
> - `python3 -c "open(...).write(...)"` and `tee solution.llmll` → "This command requires approval" (also gated).
>
> The 6514d19 `--add-dir {run_dir}` remediation flips the error-message allow-list but does not flip the underlying check.

Tested write paths exhaustively enumerated by Claude across the 5 turns (all blocked):

| Path | Failure mode |
|---|---|
| `Write` tool | "Claude requested permissions … but you haven't granted it yet" — no permission UI in headless `--print` mode |
| `cat > solution.llmll` (heredoc, abs path) | Sandbox block; error names the run dir as "allowed" |
| `cat > solution.llmll` (heredoc, rel path) | Same |
| `cat > … dangerouslyDisableSandbox: true` | Same |
| `python3 -c "open(...).write(...)"` | "This command requires approval" |
| `tee solution.llmll` | "This command requires approval" |

#### Why we saw what we saw

Per Claude's own diagnosis (load-bearing for the implication, since agent-self-reported root-causing in this domain has unusually high prior — Claude has direct access to its own tool-call surface and the sandbox's error messages): `--add-dir` modifies the displayed allow-list (the path Claude reports as "allowed working directory" in error messages includes the run dir) but does **not** modify the enforced sandbox-write check. The two allow-lists have diverged in Claude Code 2.1.141's session implementation. From the harness's perspective this is a Claude Code defect; from the experiment's perspective it is the operative constraint we work around.

Codex's `--dangerously-bypass-approvals-and-sandbox` flag (used cleanly in postmortem-002's first probe with a 23-statement solution emission) is broader: it disables the sandbox layer outright. Claude's `--allow-dangerously-skip-permissions` only bypasses per-tool **prompts** while leaving the sandbox enforcement layer intact, and `--add-dir` does not bridge the gap (per the data above).

#### Implication

F-036 hypothesis 5 candidate-1 (`--add-dir {run_dir}`) is refuted by data. The next remediation move from the postmortem-002 Addendum 1 menu is candidate-2: per-cell **settings.json injection** with explicit `Write` and `Bash` permissions for the run dir, supplied to Claude via `--settings <path>`.

Sketch (subject to candidate-2 implementation-plan adjudication):

```json
{
  "permissions": {
    "allow": [
      "Write(<run_dir>/**)",
      "Bash(cat:*>*)",
      "Bash(tee:*)",
      "Bash(python3:*)"
    ]
  }
}
```

Mechanism: orchestrator writes a per-cell `<run_dir>/.claude/settings.json` (or a dedicated path under the run dir) before invoking the agent; the agent cmd gains `--settings <path>` to read it; the per-tool permission grants explicitly authorize the write paths Claude was reaching for. The `permissions.allow` list takes precedence over the per-prompt confirmation gate in non-interactive `--print` mode (per Claude Code permissions docs; verify when implementing).

Required harness changes:

- **`run_repair_loop.py:_invoke_real_agent`** (or its caller `_run_one_turn`): write `<run_dir>/.claude/settings.json` from a manifest-supplied template, with `<run_dir>` substitution analogous to the existing `{run_dir}` placeholder substitution.
- **Manifest schema**: per-agent optional `settings_template` field (a JSON object) to allow per-agent customization (Codex agents pass through unchanged).
- **Cmd**: append `--settings {run_dir}/.claude/settings.json` (or analogous) to the Claude cmd after the existing `--add-dir {run_dir}`.

If candidate-2 also fails (possible but not predicted), the remaining options are progressively heavier:

- **Candidate 3:** use `--bare` with `ANTHROPIC_API_KEY` env auth, sidestepping the OAuth-session sandbox layer entirely. Requires operator API key; the `--bare` mode skips hooks/LSP/plugin-sync/keychain reads (per `claude --help`) so the sandbox composition is materially different. Per the existing manifest note in `manifest.phase3.json`, the operator initially declined this path; if candidate-2 fails, revisit.
- **Candidate 4:** replace Claude Code with the Anthropic SDK directly inside a shim agent process, dropping all CLI-level sandboxing. Heaviest; comparable to the Codex side's scope.

#### Acceptance

Post-candidate-2 implementation, a Claude cell against `002-bank-ledger × llmll` produces a real `solution.llmll` and runs the verifier chain to a terminal state (`target-reached` or `budget-exhausted` with verifier-extracted data, not `budget-exhausted` with `NO_SOLUTION` × k turns).

---

### F-037 update. Discipline B tripped at threshold 1 on attempt-1 cmd-bug; correctly silent on attempt-2 budget-exhaust

**Priority:** Defence-in-depth confirmation.
**Consumer:** user (informational).

Continues postmortem-002 F-037; no new closeable action.

#### Evidence

- **Attempt 1:** cell 1 `terminal_state: infrastructure-fail` (`agent_rc=1` in 7 seconds from F-039 cmd bug). Probe configured `_circuit_breaker_consecutive_infra_fail: 1` (single-cell probe; any infra-fail trips). Discipline B tripped after cell 1; matrix returned rc=2 with `circuit_breaker_tripped: {consecutive_infra_fail: 1, threshold: 1, tripped_after_cell: 1}`. Bounded the cmd bug to 7 seconds and ~$0 of agent cost.
- **Attempt 2:** cell 1 `terminal_state: budget-exhausted` (`agent_rc=0` each turn, no infra-fail). Trailing infra-fail count = 0; below threshold. Discipline B correctly did not trip; matrix returned rc=0 with `circuit_breaker_tripped: null`.

#### Implication

The threshold-1 setting on this single-cell probe was useful in attempt 1 (clean fail-fast surfacing of the cmd bug at zero agent cost) and harmless in attempt 2 (no false trip on a non-infra-fail outcome). Discipline B's calibration logic (trailing-N infra-fails distinct from non-infra-fail outcomes mixed in) preserved.

#### Acceptance

N/A — defence-in-depth confirmation, not closeable. The discipline stays in place.

---

## Orthogonal datum: extractable solution.llmll in turn-5 stdout

Claude's turn-5 `agent.stdout.log` (lines 12–160) includes a verbatim draft `solution.llmll` it would have written if the sandbox had permitted. Properties of the draft:

- **Ledger representation:** `pair(accounts, log)` with `accounts: list[(string, int)]` and `log: list[string]`.
- **QF-LIA-decidable arithmetic primitives** with body-faithful (logic) postconditions: `safe-add`, `safe-sub`, `positive?`, `at-least?`, `negate` (5 primitives × `(post (= result …))`).
- **Map-shape operations** correctly identified as outside QF-LIA per `LLMLL.md §13.8` and marked `weakness-ok` with citation: `sum-balances`, `find-balance`, `account-exists?`, `apply-delta`, `create-ledger`, `ledger-accounts`, `ledger-log`, `total-balance`, `balance`, `log-entry` (10 weakness-ok markers, each with a one-line reason citing §13.8 or the projection rationale).
- **`transfer`** carries `pre (> amount 0)` (QF-LIA-verifiable) and `post ?proof-required` (conservation + map-shape, outside QF-LIA), with the intended postcondition narrated as a multi-line comment specifying `total-balance` invariance, per-account `find-balance` deltas, and `list-length(log')` increment. Body uses nested `if`/`let` for the four error paths (source missing, dest missing, insufficient funds, success) returning `(ok …)` / `(err "…")`.
- **Five PBT-Lift singleton-head check blocks** for the QF-LIA primitives (`safe-add-correct`, `safe-sub-correct`, `positive-correct`, `at-least-correct`, `negate-correct`).

This draft matches `docs/design/phase3-problem-shape-audit.md` §"002 — Bank Ledger" predictions: Claude correctly partitioned the QF-LIA / non-QF-LIA boundary on the spec, marked the non-decidable obligations explicitly, and structured the spec coverage so PBT-Lift singleton-heads pick up the verifiable primitives.

**Implication.** Claude's LLMLL competence on the calibration problem is **not** the bottleneck; the harness/sandbox interaction is. Once candidate-2 lands and Claude can actually emit `solution.llmll` to disk, the expectation is substantive solution data within probe budget.

The hand-extractable solution **is not used as a probe data point** — it bypasses the harness contract (no per-turn iteration, no verifier feedback in the loop, no record in `repair_loop_log.json:turns[*].verifier_results`). It is recorded here for **hypothesis-priming on the candidate-2 re-probe**: if the candidate-2 cell emits a solution structurally similar to the turn-5 draft, that is consistency evidence rather than a new datum; if the candidate-2 cell produces a meaningfully different structure given the same problem and same agent, that is itself a finding about turn-on-turn variance under a working sandbox.

## Withdrawn items

None. The cmd-string regression (F-039) was not in postmortem-002's enumeration; the hypothesis-5 refutation closes a postmortem-002 hypothesis rather than withdrawing one.

## Null results

- **F-036 hypothesis 5 candidate-2 (settings.json injection)** was not tested this probe. Authorization for candidate-2 implementation work is the next live experiment-lead decision.
- **Codex re-probe data** under the F-035 1800s timeout was not collected this probe — F-038 (OpenAI quota) was unresolved at probe-authorization time, so the probe was Path B (claude-only). Codex per-cell wall+cost pinning under the bumped timeout remains unmeasured. Acceptance for F-038 closure unchanged from postmortem-002 Addendum 2: post-quota-reset codex smoke or fourth probe produces non-zero stderr volume and runs through at least one tool-call round.

## Cumulative cost across all three probe attempts (full lineage)

| Attempt | Date | Claude | Codex | Total |
|---|---|---|---|---|
| 1 (postmortem-002, 540s timeout) | 2026-05-15T19:24Z | ~$0–$1 (silent, killed at 540s) | ~$3–$5 (23-statement solution + 839KB reasoning trace; killed mid-stream) | ~$3–$6 |
| 2 (postmortem-002 Addendum 2, 1800s timeout) | 2026-05-15T21:23Z | ~$3–$8 (5 turns × default model × multi-tool reasoning, sandbox-blocked) | ~$0 (immediate quota error, F-038) | ~$3–$8 |
| 3a (this; F-039 cmd-bug) | 2026-05-15T23:35Z | ~$0 (rc=1 in 7s, no API call) | n/a (Path B) | ~$0 |
| 3b (this; F-036 hyp-5 refuted) | 2026-05-15T23:41Z | ~$3–$8 (5 turns × ~6.5min/turn, sandbox-blocked but reasoning rich) | n/a (Path B) | ~$3–$8 |
| **Cumulative** | | **~$6–$17** | **~$3–$5** | **~$9–$22** |

Cumulative spend remains within the rolling probe envelope (postmortem-002 Addendum 2 estimated ~$6–$14 cumulative across the first two probes; this probe added ~$3–$8). **No clean per-cell wall+cost datum yet on the Claude side** — three Claude attempts, three different infrastructure-class failure modes, each diagnosed and remediated in turn (timeout → cmd-bug → sandbox). The candidate-2 fix is the load-bearing next move. Per-cell cost extrapolation for the Phase-3 81-cell launch budget remains loose.

## Per-consumer scoped fragments

This postmortem is the integrated report; no per-consumer fragments routed because:

- **`findings/compiler-engineer.md`:** no compiler implication (no `solution.llmll` reached the verifier chain on either attempt; the only compiler interaction was the discipline-A pin verification on attempt 2).
- **`findings/language-team.md`:** no spec implication (LLMLL.md surface unimplicated; the candidate-2 escalation is harness-internal).
- **`findings/documentation-team.md`:** no docs-side finding. A candidate documentation move would be to add a "Claude Code sandbox interaction" subsection to `experiments/repair-loop/README.md`'s pre-launch section once candidate-2 lands (so future operators know the per-cell settings.json mechanism exists), but that is downstream of the candidate-2 outcome — premature.

## Phase-3 readiness checklist update

| Item | Owner | Status post-this-commit |
|---|---|---|
| F-035 timeout bump to 1800 | experiment-lead | ✅ closed; both probe-2 and probe-3 saw clean per-turn timing; no `agent_rc=124` |
| F-036 hypothesis 5 candidate-1 (`--add-dir`) | experiment-lead | ❌ refuted by F-036 final adjudication above; **do NOT carry into Phase-3 launch** |
| F-036 hypothesis 5 candidate-2 (settings.json injection) | experiment-lead | ⏳ next live work; candidate-2 implementation plan to be surfaced as a separate experiment-lead turn pending user "go" |
| F-037 stop-fast disciplines | experiment-lead | ✅ continued; A + B + C all behaved as designed across both probe-3 attempts |
| F-038 OpenAI quota | operator | ⏳ unchanged; reset/upgrade pending |
| F-039 cmd-string variadic collision | experiment-lead | ✅ closed; cmd reordered in three manifests (`probe`, `probe-claude-only`, `phase3`) this commit |
| Pre-launch service status check (README §) | experiment-lead | ✅ holds (codified at `c969c49`) |
| Audit `Launch-commit-hash` field fill in `docs/design/phase3-problem-shape-audit.md` | language-team | ⏳ pending (still required; no change this commit) |
| `experiments/repair-loop/README.md` phase-table flip | experiment-lead | ⏳ pending (Phase-3 row still pending until candidate-2 lands and a clean per-cell datum is captured) |

## Closing — fourth-probe gate-conditions

A fourth probe of the calibration lineage is contingent on candidate-2 implementation landing. The fourth-probe gate-conditions, derived from the third-probe outcome plus the postmortem-002 Addendum 2 carry-over:

| Gate | Status post-this-commit |
|---|---|
| Anthropic service Clean at `status.claude.com` | Operator-checks at fourth-probe launch authorization |
| OpenAI quota headroom on operator account | ⏳ unchanged (F-038 carry); operator decides whether fourth probe is full 2-cell or claude-only Path B again |
| F-036 hypothesis 5 candidate-2 (settings.json injection + harness extension) | ⏳ next experiment-lead implementation turn; user authorization needed |
| Manifest 1800s timeout (F-035) | ✅ holds |
| Manifest cmd-reorder (F-039) | ✅ holds |
| Pre-launch service status check codified | ✅ holds |

If candidate-2 implementation succeeds and produces a clean Claude-side datum on the fourth probe, the next live decision is the Phase-3 81-cell launch authorization (downstream of: language-team `Launch-commit-hash` field fill, separate user authorization on the $80–$400 launch budget). If candidate-2 also fails, postmortem-004 surfaces with candidate-3 (`--bare` + `ANTHROPIC_API_KEY`) or candidate-4 (Anthropic SDK shim) adjudication.

---

## Addendum 1 (2026-05-16) — Fourth probe under candidate-2 (2a+2b): F-036 closed; first clean Claude-side end-to-end datum; Phase-3 budget tightened

> **Status:** F-036 hypothesis 5 candidate-2 (cmd-only 2a + 2b combined) **confirmed by smoke test and probe data**. Claude side of Phase-3 readiness cleared. Codex side still pending F-038 (OpenAI quota) resolution.
> **Date:** 2026-05-16.
> **Batch dir:** `experiments/repair-loop/runs/20260516T043756Z-matrix/`.
> **Cell:** `experiments/repair-loop/runs/20260516T043758Z-claude-default-try01-of-01-c01-e002-bank-ledger-llmll/`.
> **Implementation note:** the candidate-2 sketch in postmortem-003's F-036 final adjudication anticipated a harness extension (per-cell file write + manifest schema bump). The actual implementation was lighter: `claude --help` revealed `--permission-mode <mode>` with `bypassPermissions` choice and `--settings <file-or-json>` accepting an inline JSON string. Both are manifest-only flags; no harness Python code changed this session. The 2a+2b cmd shape adds `--permission-mode bypassPermissions --settings '{"permissions":{"allow":["Write","Bash"]}}'` between the existing `--add-dir {run_dir}` and the `--print` switch.

### Pre-launch smoke tests (verbatim, this session)

Two smoke tests confirmed the new cmd before matrix launch:

1. **CLI parse + Claude responds OK.** `claude --add-dir /tmp --permission-mode bypassPermissions --settings '{"permissions":{"allow":["Write","Bash"]}}' --print --allow-dangerously-skip-permissions --no-session-persistence 'Reply with the literal word OK and nothing else.'` → returned `OK`. ~10 second wall.
2. **Write tool emits to disk.** `claude --add-dir <tmp-dir> [2a+2b flags] 'Use the Write tool to create <tmp-dir>/smoke-test.txt with the content "wrote successfully". Then reply with just the word DONE.'` → returned `DONE`; file present at `<tmp-dir>/smoke-test.txt` with 18-byte content `wrote successfully`. ~30 second wall.

Both smoke tests at order-of-pennies cost. F-036 hypothesis 5 candidate-2 vindicated empirically before any matrix spend — a deviation from postmortem-003's "next-step authorization" framing, but one consistent with the experiment-lead stop-fast discipline (cheap verification before expensive deployment).

### Per-turn trajectory

| Turn | Δt | `agent_rc` | Verifier rc (check / check-strict / holes / test / verify-fixpoint / verify) | `tier_profile` | Terminal match |
|---|---|---|---|---|---|
| 1 | 650s (10:50) | 0 | 1 / 1 / 0 / 0 / 1 / 1 | null | False |
| 2 | 508s (8:28) | 0 | 1 / 1 / 0 / 0 / 1 / 1 | null | False |
| 3 | 417s (6:57) | 0 | 0 / 0 / 0 / 0 / 0 / 0 | `{verified: 0, asserted: 15, contract_checked: 0, no_contract: 0, proved: 0, tested: 0}` | False (15 below R6d threshold) |
| 4 | 661s (11:01) | 0 | 0 / 0 / 0 / 0 / 0 / 0 | `{verified: 1, asserted: 14, contract_checked: 0, no_contract: 0, proved: 0, tested: 0}` | False (14 below threshold) |
| 5 | 664s (11:04) | 0 | 0 / 0 / 0 / 0 / 0 / 0 | `{verified: 1, asserted: 14, contract_checked: 0, no_contract: 0, proved: 0, tested: 0}` | False (14 below threshold) |

**Wall:** 48 min 35 s total; per-turn average 9 min 43 s; per-turn longest 11 min 4 s (turn 4). All five turns completed cleanly under the 1800s/turn ceiling. All `agent_rc=0` (no timeout-kill, no permission/auth error).

**Trajectory shape.** Turns 1–2 produced parse-clean stdout but `check`/`check-strict`/`verify-fixpoint`/`verify` all failed — the agent was iterating against fixable LLMLL syntax/type errors. Turn 3 reached the first all-verifier-pass state; tier_profile populated (15 obligations, all `asserted`). Turn 4 promoted one obligation from `asserted` to `verified` (the `safe-subtract` arithmetic primitive — body-faithful, discharged by `liquid-fixpoint`). Turn 5 produced an identical tier_profile to turn 4 — plateau, not further regression or progression.

### Trust report — final solution (`solution.llmll.verified.json`)

15 declared `post` obligations. Tier breakdown:

| Tier | Count | Obligations |
|---|---|---|
| `verified` (liquid-fixpoint, body-faithful) | 1 | `safe-subtract` |
| `asserted` (intended invariant narrated; no proof in scope) | 14 | `balance`, `balances-of`, `create-ledger`, `entries-with-id`, `entry-bal`, `entry-id`, `has-account`, `ids-of`, `lookup-balance`, `sum-balances`, `sum-int-list`, `total-balance`, `transfer`, `update-account` |
| `proved`, `contract_checked`, `tested`, `no_contract` | 0 | — |

All 14 `asserted` obligations relate to list/map operations cited at `LLMLL.md §13.8` as outside QF-LIA. Each carries a non-empty `source` field with the intended invariant in prose — e.g.,

- `sum-int-list.post.source`: *"result : int; intended invariant: result is Sigma over xs; homogeneous int list-fold, outside QF-LIA without an inductive invariant"*
- `transfer.post.source`: *"result : Result[(list[(string, int)], list[(string, (string, int))]), string]; intended invariant: amount > 0 (enforced internally); on (ok new-ledger), (total-balance new-ledger) = (total-balance ledger), source decreases by amount, destination increases by amount; map reasoning outside QF-LIA"*

The annotations are technically substantive (they encode the QF-LIA-boundary reasoning the agent identified in the postmortem-003 turn-5 narration); the agent did not figure out how to promote them to a higher tier (`tested`, `contract_checked`, `proved`) within k=5 turns.

### Per-axis v2 rubric scores (`evaluation.json`)

**Apparatus:** passed (12/12 checks).

**Correctness subscores:**

| Sub-category | Status | Value |
|---|---|---|
| `solution_discovery` | scored | True |
| `build_typecheck` | scored | True |
| `core_behavior` | scored | 0.533 (8 passed / 0 failed / 7 skipped of 15 PBT samples; channel `llmll-pbt`) |
| `api_conformance` | TODO(sub-3-v2) | — |
| `edge_cases` | TODO(sub-3-v2) | — |
| `determinism_isolation` | deferred | — |

**Zero PBT failures.** The agent's solution is functionally correct on every PBT sample that ran. The 7-skip count likely reflects PBT samples whose preconditions weren't satisfiable by random inputs or whose targets the solver could not discharge.

**Assurance subscores:**

| Sub-category | Status | Value |
|---|---|---|
| `test_quality` | scored | `pbt_sample_pass_rate=0.533`, `agent_emitted_test_count=16` |
| `proof_or_trust_evidence` | scored | `locally_verified_obligations=1`, `outstanding_trust_acknowledgments=0`, `compositionally_verified_module_rate=0.067` |
| `static_structure` | TODO(sub-3-v2) | — |
| `runtime_checks` | TODO(sub-3-v2) | — |
| `contract_strength` | TODO(sub-3-v2) | — |
| `specification_adequacy` | deferred | — |

**Headline metrics:** `trust_declarations_per_kloc=0.0` (no explicit `trust` declarations in the agent's solution), `compositionally_verified_module_rate=0.067` (1/15 — matches the `verified=1` from `tier_profile`).

### F-036 final disposition — CLOSED

Hypothesis 5 candidate-2 (cmd-only 2a + 2b combined) is the working remediation. F-036 closes definitively. No further candidate (2c file-based settings, candidate-3 `--bare` + `ANTHROPIC_API_KEY`, candidate-4 Anthropic SDK shim) needs to be planned. The cmd as edited into `manifest.phase3.json`, `manifest.phase3-calibration-probe.json`, and `manifest.phase3-calibration-probe-claude-only.json` is **Phase-3-launchable on the Claude side**.

### Per-cell wall+cost pin — Claude × 002-bank-ledger × llmll, k=5, default reasoning

| Measure | Value | Note |
|---|---|---|
| **Wall (single cell)** | 48 min 35 s | Within probe-budget; well under 30 min × 5-turn ceiling |
| **Per-turn average** | 9 min 43 s | |
| **Per-turn longest** | 11 min 4 s (turn 4) | Below 30 min ceiling by ~3× headroom |
| **Cost estimate** | $5–$12 | 5 substantive multi-tool reasoning turns × ~10 min each + LLMLL.md 131KB ingestion + verifier feedback ingestion + iterative solution rewrite |

This is the **first clean Claude-side per-cell wall+cost datum** of the calibration lineage. Three prior Claude attempts produced infrastructure-class failures (timeout-kill, cmd bug, sandbox block) that did not measure clean-completion wall+cost.

### Phase-3 81-cell launch budget — tightened

Phase-3 matrix per `manifest.phase3.json`: 3 agents × 3 problems × 3 languages × 3 tries = **81 cells**. With one Claude × llmll × 002-bank-ledger data point at ~$5–$12/cell, slice-level extrapolation:

| Slice | Cells | Source | Per-cell est. | Slice total |
|---|---|---|---|---|
| Claude × llmll (3 problems × 3 tries) | 9 | this addendum | $5–$12 | $45–$108 |
| Claude × Python (3 problems × 3 tries) | 9 | unmeasured | $3–$8 (tentative; ~50–80% of llmll cost — no LLMLL learning curve, but verifier chain still runs) | $27–$72 |
| Claude × Go (3 problems × 3 tries) | 9 | unmeasured | $3–$8 (same rationale) | $27–$72 |
| Codex × all-three-langs (27 cells) | 27 | postmortem-002 first probe (killed mid-stream at 540s, $3–$5/cell at partial completion) | $3–$8 (tentative; full completion under 1800s ceiling) | $80–$220 |
| Gemini × all-three-langs (27 cells) | 27 | Phase-2 calibration (low single digits per cell) | $1–$3 (tentative) | $25–$80 |
| **Sum** | **81** | | | **~$205–$550** |

**Compared to postmortem-002's original $80–$400 envelope:** above the original upper bound by ~$150. Within a 1.4× headroom of the previous upper bound. **Operator authorization on the full launch budget is still required**; this is a refined estimate for that decision, not a launch authorization.

**Wall-clock if serial:** Claude × llmll slice alone = 9 × 48 min ≈ 7.2 hours; full 81-cell matrix at varying per-cell wall ≈ 25–60 hours serial. Parallel-launching across agents independently is straightforward; per-agent parallelism is constrained by API quotas and the current matrix-runner's serial execution architecture.

### H1-Assurance signal (n=1) — Phase-3 hypothesis-priming observation

The pattern this single cell exhibits is itself a Phase-3 hypothesis-priming observation worth recording:

> **Claude × 002-bank-ledger × llmll, default reasoning, k=5:** agent produces parse-clean, type-clean, verify-clean LLMLL solution within 3 turns; achieves 6.7% compositional verification rate (1 of 15 obligations); does not figure out higher-tier promotion within budget. All 14 unpromoted obligations cluster on the QF-LIA boundary; agent correctly identifies the boundary in `source` annotations but does not move them past `asserted`.

Whether this pattern is variance-driven (a second or third try elevates the rate) or systematically-bounded (k=5 default-reasoning is the agent's ceiling on this problem) is the H1-Assurance question Phase-3's 3-try slice is designed to answer. **n=1 is not the answer; it is the calibration that the Phase-3 launch is now ready to attempt on the Claude × llmll slice.**

The data is *not* a finding to be remediated. It is the empirical-descriptive measurement the experiment-lead role exists to produce.

### Phase-3 readiness checklist — updated post-fourth-probe

| Item | Status |
|---|---|
| F-035 timeout bump to 1800 | ✅ closed |
| F-036 hypothesis 5 candidate-2 (2a + 2b cmd flags) | ✅ closed; data confirms; smoke-test pre-vindicated |
| F-037 stop-fast disciplines | ✅ continued; all four probes saw correct discipline behavior |
| F-038 OpenAI quota | ⏳ unchanged; codex-side blocker |
| F-039 cmd-string variadic collision | ✅ closed |
| Per-cell wall+cost pin (Claude × 002-bank-ledger × llmll) | ✅ pinned ~48 min / ~$5–$12 this addendum |
| Per-cell wall+cost pin (Claude × Python or Go targets) | ⏳ unmeasured; Phase-3 launch is the first data (tentative extrapolation in budget table above) |
| Per-cell wall+cost pin (Codex × llmll, clean completion) | ⏳ first probe was killed at 540s mid-stream; needs post-F-038-reset codex-only mirror probe |
| Per-cell wall+cost pin (Gemini × all) | Phase-2 calibration produced; carry |
| Audit `Launch-commit-hash` field fill in `docs/design/phase3-problem-shape-audit.md` | ⏳ language-team turn |
| `experiments/repair-loop/README.md` Phase-3 row flip | ⏳ "Pending → Ready (Claude side); Codex side pending F-038; Gemini side pinned" |
| Pre-launch service status check (README §) | ✅ holds |

### Closing — "Ready for Phase-3 launch" partial

**Claude side: cleared.** Cmd shape confirmed in three manifests; sandbox unblocked at the harness level; per-cell wall+cost pinned; first solution emitted and scored on the per-axis v2 rubric; H1-Assurance hypothesis-priming observation recorded.

**Codex side: pending F-038 (OpenAI quota) resolution.** Once quota clears, a codex-only Path-B-mirror probe (mirror of the third/fourth-probe shape, codex agent only) pins codex × llmll × 002-bank-ledger per-cell wall+cost under the 1800s ceiling. The codex side's clean-completion pin remains unmeasured; postmortem-002's first probe captured codex mid-stream at $3–$5/cell, but the post-kill solution shape is not a clean per-cell datum.

**Gemini side: pinned from Phase-2 calibration; should be Phase-3-launchable without further probe.**

**Two paths to full readiness:**

1. **Conservative recommendation: codex-only Path-B-mirror probe** once F-038 resolves. Pins codex × llmll wall+cost in a $3–$8 probe before the $205–$550 Phase-3 matrix launch. Surfaces any codex-specific issues (e.g., codex-cli flags that need the same kind of disambiguation `--add-dir` / `--permission-mode` needed for Claude) at probe cost rather than launch cost.
2. **Defer codex pinning to Phase-3 launch itself.** Saves one probe attempt; accepts that codex-specific infrastructure issues, if they exist, surface during the $205–$550 matrix instead of in a $3–$8 probe. Discipline B (circuit breaker) bounds the worst-case but does not eliminate it — a codex-specific failure that flips cell-by-cell rather than cleanly fails the threshold would burn budget before halting.

Path 1 is the recommendation given the cost asymmetry and the lineage of probe-surfaced agent-side surprises (3 different Claude failure modes across 4 probes; codex's behavior under the 1800s ceiling is genuinely unmeasured).

### Cumulative cost across all four probe attempts

| Attempt | Date | Claude | Codex | Total |
|---|---|---|---|---|
| 1 (postmortem-002, 540s timeout) | 2026-05-15T19:24Z | ~$0–$1 | ~$3–$5 | ~$3–$6 |
| 2 (postmortem-002 Addendum 2, 1800s + no --add-dir) | 2026-05-15T21:23Z | ~$3–$8 | ~$0 (F-038 quota) | ~$3–$8 |
| 3a (postmortem-003; F-039 cmd bug) | 2026-05-15T23:35Z | ~$0 (rc=1 in 7s) | n/a (Path B) | ~$0 |
| 3b (postmortem-003; F-036 hyp-5 candidate-1 refuted) | 2026-05-15T23:41Z | ~$3–$8 | n/a (Path B) | ~$3–$8 |
| 4 (this addendum; F-036 hyp-5 candidate-2 confirmed) | 2026-05-16T04:38Z | ~$5–$12 | n/a (Path B; F-038 still pending) | ~$5–$12 |
| **Cumulative** | | **~$11–$29** | **~$3–$5** | **~$14–$34** |

Within the rolling probe envelope (postmortem-003 anticipated $9–$22 cumulative; the fourth probe brings cumulative to $14–$34, ~50% over the prior-postmortem estimate but matched by the clean-completion data quality this probe produced — first such datum of the lineage).

---

## Addendum 2 (2026-05-16) — Fifth probe (codex-only mirror) target-reached at turn 3; F-038 operator-resolved; F-040 (harness rubric multi-file gap) surfaced

> **Status:** First **target-reached** outcome of the entire Phase-3 calibration lineage. Codex × 002-bank-ledger × llmll cell reached Cred(R) at turn 3 of 5 via legitimate modular decomposition (`solution.llmll` re-export façade + `bank.llmll` support module with 18 tested-tier obligations). F-038 (OpenAI quota) operator-resolved via seat upgrade. F-040 (new): post-cell evaluator (`evaluate_run.py`) does not traverse `(import …)` declarations when scoring; multi-file LLMLL solutions under-report on the per-axis rubric. Phase-3 readiness cleared on load-bearing signals (terminal classification + tier_profile) with an F-040 caveat for the per-axis rubric channel.
> **Date:** 2026-05-16.
> **Batch dir:** `experiments/repair-loop/runs/20260516T131522Z-matrix/`.
> **Cell:** `experiments/repair-loop/runs/20260516T131522Z-codex-default-try01-of-01-c01-e002-bank-ledger-llmll/`.

### Pre-launch checks (this session)

Three gate confirmations before launch:

1. **`status.openai.com` Clean** (operator-confirmed).
2. **OpenAI quota headroom: confirmed** (operator-confirmed; subsequently re-clarified as: the operator had upgraded their OpenAI seat from a ChatGPT tier to a codex-specific tier between session start and fifth-probe authorization, which removed the 5h soft cap that produced F-038's original quota error and the mid-probe "71% in 3 turns" signal).
3. **Codex API smoke test** under the exact manifest cmd shape: `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check 'Reply with the literal word OK and nothing else.'` → returned `OK`, 1,365 tokens used. Matches postmortem-002 F-035 baseline (1,367 tokens for the same prompt). Auth and API both alive. ~30 second wall at order-of-pennies cost.

### Per-turn trajectory

| Turn | Δt | `agent_rc` | Verifier rc (check / check-strict / holes / test / verify-fixpoint / verify) | `tier_profile` | Terminal match |
|---|---|---|---|---|---|
| 1 | 543s (9.1 min) | 0 | 0 / 0 / 0 / 0 / 0 / 0 | `{verified: 0, asserted: 16, contract_checked: 0, no_contract: 2, proved: 0, tested: 0}` (18 below R6d threshold) | False |
| 2 | 648s (10.8 min) | 0 | 0 / 0 / 0 / 0 / 0 / 0 | `{verified: 3, asserted: 15, contract_checked: 0, no_contract: 0, proved: 0, tested: 0}` (15 below threshold) | False |
| 3 | 416s (6.9 min) | 0 | 0 / 0 / 0 / 0 / 0 / 0 | `{verified: 0, asserted: 0, contract_checked: 0, no_contract: 0, proved: 0, tested: 18}` (0 below threshold; **Cred(R) = True**) | **True** |

**Wall: 26 min 49 s** total (3 turns to target-reached; 2 unused turns of the k=5 budget). All `agent_rc=0`. **All 6 verifier commands rc=0 from turn 1** — codex reached parse-clean + verify-clean in a single turn (vs Claude's third probe needing 3 turns to reach the same state).

### Solution shape — multi-file modular decomposition

Codex emitted **two files**:

- **`solution.llmll`** (108 bytes) — a re-export façade:
  ```
  (import bank)
  (open bank)
  (export create_ledger balance transfer total_balance create-ledger total-balance)
  ```
- **`bank.llmll`** (6,984 bytes, 156 lines) — the substantive implementation. 18 obligations: `append_transfer_log`, `balance`, `create-ledger`, `create_ledger`, `credit_balance`, `debit_balance`, `ledger_accounts`, `ledger_log`, `lookup_balance`, `make_ledger`, `make_log_entry`, `set_balance`, `sum_accounts`, `total-balance`, `total_balance`, `transfer`, `transfer_positive`, `transferred_pair_total`. Uses `?proof-required` markers for non-QF-LIA obligations (map-shape and conservation reasoning), refinement-typed wrappers (`NonNegativeBalance = (where [balance: int] (>= balance 0))`, `PositiveAmount = (where [amount: int] (> amount 0))`), and PBT-Lift check blocks for the QF-LIA arithmetic primitives.

Codex's turn-3 stdout narration explicitly records the factoring decision:

> Implemented the LLMLL repair.
>
> Updated: solution.ast.json, solution.llmll
> Added support module: bank.llmll, bank.llmll.verified.json
>
> Validation run: `llmll check solution.ast.json --strict` passed; `llmll test solution.ast.json` passed; `llmll verify solution.ast.json` passed SAFE. Trust report now has `asserted: 0`, `no_contract: 0`, `tested: 18`.

The per-turn verifier chain (run via `llmll verify solution.ast.json --trust-report --weakness-check --spec-coverage`) correctly traverses the import and aggregates obligations across both files; `tier_profile.tested = 18` is real. `bank.llmll.verified.json` confirms all 18 at `tested` tier.

### Trust-report final state

`bank.llmll.verified.json`: 18 entries, all `tested`. `solution.llmll.verified.json`: 0 entries (no obligations declared in the façade file; the re-export does not duplicate the trust signal). The harness's per-turn `tier_profile` is the **union over all `*.verified.json` files** the verifier produces — the load-bearing signal for Cred(R) evaluation.

### Per-axis v2 rubric scores — F-040 evidence

`evaluation.json` for this cell reports:

| Sub-category | Status | Value |
|---|---|---|
| `solution_discovery` | scored | True |
| `build_typecheck` | scored | True |
| `core_behavior` | scored | `passed=0, failed=0, skipped=0`, value `None` |
| `test_quality` | scored | `pbt_sample_pass_rate=None`, `agent_emitted_test_count=0` |
| `proof_or_trust_evidence` | scored | `locally_verified_obligations=0`, `outstanding_trust_acknowledgments=0`, `compositionally_verified_module_rate=0.0` |
| **Headline metrics** | | `trust_declarations_per_kloc=0.0`, `compositionally_verified_module_rate=0.0` |

Every scored sub-category that depends on parsing the solution file returns zero. This is because `evaluate_run.py` reads `solution.llmll` directly (108 bytes, re-export façade only) and does not traverse `(import bank)` to find `bank.llmll` where the 18 obligations and PBT-Lift checks actually live.

The rubric and the per-turn tier_profile disagree by construction: the verifier traverses imports (correct for terminal-target evaluation); the post-cell rubric does not (incorrect for multi-file solutions).

### F-040. `evaluate_run.py` post-cell rubric does not traverse imports

**Priority:** Medium (Phase-3 launch can proceed on load-bearing signals; rubric channel under-reports for multi-file cells).
**Consumer:** experiment-lead (harness code I own per skill discipline; bounded fix).

#### Evidence

Cell `runs/20260516T131522Z-codex-default-…-c01-…/`:

- `repair_loop_log.json:turns[2].tier_profile = {verified: 0, asserted: 0, contract_checked: 0, no_contract: 0, proved: 0, tested: 18}` — load-bearing for terminal-target match; correctly aggregates across `solution.llmll` and `bank.llmll`.
- `evaluation.json:scoring.assurance_subscores.test_quality.agent_emitted_test_count = 0` — under-reports because `evaluate_run.py` reads only `solution.llmll`.
- `evaluation.json:scoring.assurance_subscores.proof_or_trust_evidence.compositionally_verified_module_rate = 0.0` — under-reports same reason.
- `evaluation.json:scoring.correctness_subscores.core_behavior = {passed: 0, failed: 0, skipped: 0}` — under-reports same reason; the PBT samples that ran in `llmll test solution.ast.json` (per codex's stdout: "passed") don't show up because the post-cell evaluator re-runs and counts a different way.
- `solution.llmll.verified.json` (cell-dir level): 2 bytes (empty obligations dict) — confirms `solution.llmll` itself has no obligations.
- `bank.llmll.verified.json`: 3,894 bytes; 18 obligations, all `tested` — confirms `bank.llmll` is where the substantive trust signal lives.

#### Why we saw what we saw

`evaluate_run.py` reads the agent's expected solution file (per `TARGET.md:Expected solution files`: `solution.ast.json, solution.llmll` in priority order) and runs its per-axis scoring rubric on it directly. The scoring rubric does not implement `(import …)` traversal; if the agent factors implementation into a support module (here `bank.llmll`), the rubric sees an effectively empty file and reports zero on every sub-category that depends on file content.

The per-turn verifier chain is different: it runs `llmll verify solution.ast.json …` via the compiler binary, and the compiler resolves imports natively (which is why `tier_profile` correctly aggregates 18 obligations).

The two scoring channels (per-turn verifier-driven `tier_profile` vs post-cell evaluator-driven per-axis rubric) have different aggregation semantics, and the disagreement surfaces only on multi-file solutions. Monolithic emissions (Claude fourth probe; codex first probe) don't trigger the gap because all obligations live in `solution.llmll`.

#### Implication

For Phase-3 launch:

- **Load-bearing H1-Assurance signal is `tier_profile`** (per `experiments/repair-loop/README.md:283-303`, the H1-Assurance for LLMLL is reported via the six-int aggregate `tier_profile` in native vocabulary, not via the cross-paradigm-comparable rubric). This is **correct** under F-040; multi-file cells produce accurate `tier_profile`.
- **Per-axis rubric is supplementary** for cross-paradigm correctness comparison; under F-040 it under-reports on multi-file LLMLL cells. Cross-agent comparison via the rubric would systematically favor monolithic-emitting agents over multi-file-emitting agents at identical actual solution quality.

Two paths before Phase-3 launch:

1. **Fix `evaluate_run.py` to traverse imports.** Bounded harness work: parse `(import <module>)` declarations from `solution.llmll`, resolve to `<module>.llmll` in the run directory, aggregate the per-axis rubric over the union of files. ~1-2 hours of harness Python; preserves all rubric data. Recommended if the operator wants cross-paradigm rubric data to be reliable in Phase-3 findings.
2. **Document the caveat in Phase-3 findings.** Zero code; surfaces in findings: "Multi-file LLMLL cells under-report on per-axis rubric; refer to per-turn `tier_profile` for load-bearing assurance signal." Acceptable if the operator considers `tier_profile` sufficient and is willing to caveat rubric scores in cross-agent comparisons.

#### Acceptance

For path 1: a cell where the agent emits a multi-file solution (e.g., this codex cell) produces `evaluation.json` with non-zero `agent_emitted_test_count`, non-zero `compositionally_verified_module_rate`, and `core_behavior` reflecting the PBT samples that ran in the per-turn verifier chain.

For path 2: Phase-3 findings explicitly call out the multi-file caveat with an example cell citation.

### F-038 final disposition — operator-resolved by seat upgrade

F-038 (OpenAI quota exhaustion, first surfaced postmortem-002 Addendum 2; recurred as a 5h-soft-cap signal during the fifth probe's turn-2-running window) **closes at the operator-account level**. The operator upgraded their OpenAI seat from a ChatGPT tier to a codex-specific tier between session start and fifth-probe launch; this removed the 5h soft cap that the prior tier imposed on codex CLI usage. Phase-3 launch is **not rate-limit-bound** going forward on the current seat.

The 71%-in-3-turns mid-probe signal that surfaced during the fifth probe (operator-reported between turn 2 and turn 3) was a transient artifact of the prior tier's soft cap; under the upgraded tier it does not constrain Phase-3 launch.

### Cross-agent H1-Assurance / H2-convergence preliminary delta (each n=1; Phase-3-hypothesis-priming only)

The two clean Claude × llmll + Codex × llmll datums show structurally different verification strategies on the same problem:

| Metric | Claude (Addendum 1, default reasoning) | Codex (this addendum, xhigh reasoning) |
|---|---|---|
| Turns to all-verifier-pass | 3 | 1 |
| Turns to target-reached | not reached at k=5 | 3 (of 5) |
| Final `tier_profile` above-threshold | `{verified: 1}` (1 verified) | `{tested: 18}` (18 tested) |
| `verified` count (body-faithful liquid-fixpoint) | 1 (`safe-subtract`) | 0 |
| `asserted` count (final) | 14 (plateau on QF-LIA-boundary obligations) | 0 |
| Solution shape | monolithic (1 file) | multi-file (façade + `bank.llmll` support module) |
| Wall (cell total) | 48:35 | 26:49 |

**Both paths satisfy R6d Cred(R) when terminal-reached.** Codex tested-into-tier (PBT-Lift coverage across all 18 obligations); Claude verified-into-tier (one strong body-faithful proof + plateau-asserted with structured `source` annotations). Neither is "better" under the diamond's `contract_checked ‖ tested` incomparability (`LLMLL.md §4.4.1:344`); the data shows agents convergence on terminal-reaching via materially different routes. **This is exactly the Phase-3 H1/H2 signal the matrix is designed to measure across 3 problems × 3 languages × 3 tries**; the n=1-per-agent delta here is hypothesis-priming for the 3-try slice, not a finding to be remediated.

### Per-cell wall+cost pin — Codex × 002-bank-ledger × llmll, k=5, xhigh reasoning

| Measure | Value | Note |
|---|---|---|
| **Wall (single cell)** | 26 min 49 s | 3 turns to target-reached; 2 unused turns of k=5 budget |
| **Per-turn average** | 8 min 56 s | |
| **Per-turn longest** | 10 min 48 s (turn 2) | Well under 1800s ceiling |
| **Dollar cost estimate** | **unmeasured** | The fifth probe's quota signal was rate-limit-class, not dollar-class; under the operator's upgraded seat, the dollar cost is genuinely unmeasured. First-cell calibration is now a Phase-3 launch responsibility. |

The codex per-cell wall is materially **shorter** than the Claude per-cell wall (26:49 vs 48:35) — codex reached terminal target in fewer turns despite its xhigh reasoning effort. If this asymmetry holds across the matrix, codex × llmll slice wall is lower than Claude × llmll slice.

### Phase-3 readiness checklist — updated post-fifth-probe

| Item | Status |
|---|---|
| F-035 timeout bump to 1800 | ✅ closed |
| F-036 hypothesis 5 candidate-2 (2a + 2b cmd flags) | ✅ closed |
| F-037 stop-fast disciplines | ✅ continued; correct behavior across all 5 probes |
| **F-038 OpenAI quota** | ✅ **operator-resolved by seat upgrade** |
| F-039 cmd-string variadic collision | ✅ closed |
| **F-040 evaluator import-traversal gap (new)** | ⚠ harness defect; load-bearing Phase-3 signal unaffected; fix-vs-caveat operator call |
| Per-cell wall pin (Claude × 002 × llmll) | ✅ ~48:35 / monolithic (Addendum 1) |
| Per-cell wall pin (Codex × 002 × llmll) | ✅ ~26:49 / multi-file (this addendum) |
| Per-cell wall+cost pin (Claude × Python\|Go targets) | ⏳ unmeasured; Phase-3 first-cells |
| Per-cell wall+cost pin (Codex × Python\|Go targets) | ⏳ unmeasured; Phase-3 first-cells |
| Per-cell wall pin (Gemini × all) | ✅ Phase-2 calibration carried |
| Codex dollar per-cell cost | ⏳ unmeasured under upgraded seat; Phase-3 first-cells |
| Audit `Launch-commit-hash` field fill in `docs/design/phase3-problem-shape-audit.md` | ⏳ language-team turn |
| `experiments/repair-loop/README.md` Phase-3 row flip | ⏳ "Pending → Ready" pending Launch-commit-hash + operator launch authorization |
| Pre-launch service status check (README §) | ✅ holds |

### Phase-3 81-cell launch budget — Addendum 1 envelope holds (no upward revision)

| Slice | Cells | Per-cell est. | Slice total |
|---|---|---|---|
| Claude × llmll | 9 | $5–$12 (Addendum 1) | $45–$108 |
| Claude × Python\|Go | 18 | $3–$8 (tentative) | $54–$144 |
| Codex × all-three-langs | 27 | $3–$8 (tentative; **dollar cost unmeasured under upgraded seat; refine after Phase-3 first-cells**) | $80–$220 |
| Gemini × all-three-langs | 27 | $1–$3 (tentative; Phase-2 carry) | $25–$80 |
| **Sum** | **81** | | **~$205–$550** |

Reverts to Addendum 1's envelope. The prior upward revision ($310–$795) was withdrawn (see Withdrawn items below).

### Closing — "Ready for Phase-3 launch" on load-bearing signals

**Both agents pinned for wall (Claude monolithic 48:35; Codex multi-file 26:49). Both terminal-classification mechanisms (tier_profile, Cred(R), matrix circuit-breaker) verified working across substantive cells.** F-040 is a downstream rubric defect that does not block launch under the load-bearing-via-tier_profile reading of H1-Assurance.

**Operator-side blockers before Phase-3 launch:**
1. **Language-team:** `Launch-commit-hash` field fill in `docs/design/phase3-problem-shape-audit.md` (separate language-team turn).
2. **User authorization:** $205–$550 launch budget commitment, with codex dollar per-cell measured during Phase-3 first-cells under the upgraded seat.
3. **F-040 fix-vs-caveat decision:** path-1 (harness fix, ~1-2 hours) vs path-2 (caveat in findings). Operator/experiment-lead call.

**Experiment-lead-side:** all preparation work complete on the calibration arc. The Phase-3 launch authorization is the next live experiment-lead turn, downstream of the operator-side blockers.

### Withdrawn items (this addendum)

Two inferential-class corrections this session caught before findings landed; recording per the experiment-lead skill's "withdrawn items are first-class" empirical-hygiene discipline:

1. **The $310–$795 Phase-3 budget upward revision drafted between this addendum's first surface and this final write.** Drafted on the assumption that the operator's "71% of 5h limit" signal during fifth-probe turn-2 reflected dollar burn rate at ~$10–$25/cell. Withdrawn after operator clarification that the signal was a rate-limit-class artifact of the prior ChatGPT-tier seat, since replaced by an upgraded codex tier with the 5h soft cap removed. Phase-3 budget reverts to Addendum 1's $205–$550 envelope. Inferential-class lesson: signal-class disambiguation (rate-limit-vs-dollar) should be verified with the operator before depending on the signal for a budget claim; matches the user-memory entry on verifying load-bearing diagnoses empirically.

2. **The initial F-040 framing as "Cred(R) terminal predicate is gameable by stub emission."** Drafted on the observation that codex's turn-3 emission was 108 bytes of imports+exports while turn-2 emission was 47KB. Withdrawn after reading codex's turn-3 stdout narration (explicit modular-decomposition decision: "Added support module: bank.llmll"), confirming `bank.llmll` exists with 6,984-byte / 18-obligation substantive implementation, and confirming the per-turn verifier chain correctly aggregates `tier_profile` across imports. The actual finding (F-040 final framing above) is narrower: a harness rubric defect, not a predicate vulnerability or agent gaming. Inferential-class lesson: solution-shape suspicion ("file shrank dramatically") should be cross-checked against agent narration and the harness's full file-emission state before attributing intent.

### Cumulative cost across all five probe attempts

| Attempt | Date | Claude | Codex | Total |
|---|---|---|---|---|
| 1 (postmortem-002, 540s timeout) | 2026-05-15T19:24Z | ~$0–$1 | ~$3–$5 | ~$3–$6 |
| 2 (postmortem-002 Addendum 2) | 2026-05-15T21:23Z | ~$3–$8 | ~$0 (F-038 quota) | ~$3–$8 |
| 3a (postmortem-003; F-039 cmd bug) | 2026-05-15T23:35Z | ~$0 | n/a | ~$0 |
| 3b (postmortem-003; F-036 candidate-1 refuted) | 2026-05-15T23:41Z | ~$3–$8 | n/a | ~$3–$8 |
| 4 (Addendum 1; F-036 candidate-2 confirmed) | 2026-05-16T04:38Z | ~$5–$12 | n/a | ~$5–$12 |
| 5 (this addendum; codex target-reached) | 2026-05-16T13:15Z | n/a | unmeasured under upgraded seat (wall-pinned 26:49) | unmeasured |
| **Cumulative** | | **~$11–$29** | **~$3–$5 + fifth probe unmeasured** | **~$14–$34 + fifth probe unmeasured** |

The fifth-probe codex dollar cost is genuinely not knowable from this session — the operator's seat-upgrade between session start and fifth-probe authorization moved the cost-signal channel from the prior tier's soft-cap percentage display to a different (presumably dollar-line-item) display that has not been operator-reported. Phase-3 first-cells will produce the dollar pin; the wall pin (26:49) is the load-bearing Phase-3-launch-budget input for now.

### Deferred adjacent experiments surfaced during session close

Four measurable questions surfaced via session-close discussion that the calibration arc did not investigate but that the data suggests are worth scheduling around Phase-3 launch. None are blocking; each is a discrete cost-vs-quality calibration the operator can sequence before, during, or after Phase-3 first-cell data lands. Captured here so the operator's next-live-decision adjudication is informed by what was surfaced but not yet acted on.

#### 1. R2 — codex at `medium` reasoning effort (deferral condition now met)

The F-035 implication table (postmortem-002) listed R2 ("bump timeout + reduce Codex reasoning to medium") as a separate path explicitly deferred until "after clean xhigh baseline data exists." The fifth-probe data IS that baseline (target-reached at turn 3, 18 tested obligations, 26:49 wall). R2 is now unblocked.

Probe shape: single cell, same as fifth probe, codex cmd gains `-c model_reasoning_effort=medium`. Cost ~$2–$5 (estimated lower per-token at medium vs xhigh; actual dollar cost unmeasured under operator's upgraded seat). Hypothesis shapes: strong-success (target-reached at similar turn count with comparable `tier_profile` and lower wall+cost → swap medium for xhigh in Phase-3 manifest; codex slice cost cuts materially); mixed (target-reached but weaker `tier_profile` → quality-vs-cost trade-off for operator adjudication); null (budget-exhausted → keep xhigh, no change).

Placement options: sixth calibration probe before Phase-3 launch (decides codex cost slot pre-commit); deferred to post-Phase-3 retrospective; added as fourth-agent slot in Phase-3 matrix itself (+27 cells, +33% budget). Operator call.

#### 2. Format-choice as a Phase-3 measurement, not just incidental output

Codex switched output formats between probes 1 and 5: probe 1 emitted `solution.llmll` (surface form, monolithic); probe 5 emitted `solution.ast.json` (AST primary) + thin `solution.llmll` re-export façade (multi-file decomposition). Same agent, same model (gpt-5.5), same reasoning effort (xhigh), same problem. **The format choice is task-time variable within an agent, not a fixed per-agent preference.**

Currently not measured at the aggregate level. `TARGET.md` allows both formats in priority order; agents pick freely; nothing records which-format-per-cell. Phase-3 will produce 45 LLMLL-target cells (27 codex + 9 Claude + 9 Gemini) with format-choice variance. A post-Phase-3 analyzer — walk run dirs, extract primary emit format per cell, correlate with terminal-reaching rate / turns-to-terminal / tier_profile shape — surfaces whether format choice is signal or noise.

If correlation is strong (e.g., AST cells reach terminal faster), that's itself a Phase-3 finding worth elevating. If no correlation, format choice is incidental variance to subtract. Either way the measurement is cheap (post-hoc analysis on existing data; no extra probes; no harness change). Phase-3-natural analysis, not pre-launch decision.

#### 3. Spec-compaction probe — is `LLMLL.md` over-verbose for first-round correctness?

The harness injects `LLMLL.md` (131KB / ~32–40K tokens) into every agent turn. Across Phase-3's 81 cells × multi-turn × k=5 worst-case, spec re-ingestion alone is order-of-millions of tokens. Both Claude and Codex reached parse-clean solutions within 1–3 turns this session — verbosity isn't the first-round correctness bottleneck on data we have — but it MAY be a material Phase-3 cost driver.

Probe shape: single cell, same agent + problem as fifth probe, but the run-dir is staged with a compacted `LLMLL.compacted.md` (target ~60KB, dropping redundant examples and tightening prose) instead of the full 131KB. Cost ~$3–$10. Hypothesis shapes: equivalent outcome (spec verbosity is over-engineered for this task class; compaction is a Phase-3 cost-savings lever); degraded outcome (spec verbosity is doing real work; keep it).

Placement: low priority pre-Phase-3; more naturally a post-Phase-3 follow-on if first-cell data shows ingestion cost is dominating per-cell budget. Authors a sibling `LLMLL.compacted.md` (~1-2 hours of editing); the probe itself is a one-cell run. Embeddings/RAG-based partial-injection is a separate architectural class (would require harness redesign for per-cell spec slice selection) and is out of scope for the current probe lineage.

#### 4. Per-turn wall agent-equivalence observation (data-implicit, name it here)

Per-turn wall on matched turn indices between codex-xhigh (fifth probe) and Claude-default (fourth probe), same cell shape (`002-bank-ledger × llmll × k=5`):

| Turn | Claude (default reasoning) | Codex (xhigh reasoning) |
|---|---|---|
| 1 | 10:50 | 9:03 |
| 2 | 8:28 | 10:48 |
| 3 | 6:57 | 6:56 |

Matched-index walls within 2 min of each other. **The total-cell-wall delta (48:35 Claude vs 26:49 codex) is entirely from turns-to-terminal, not from per-turn pace.** Codex isn't "faster per turn"; codex needed fewer turns. Codex was at xhigh (highest reasoning tier) and Claude was at default — these landed in roughly equivalent per-turn wall budgets despite differing per-token effort.

n=1 per agent on a single cell shape; not generalizable. Phase-3's 3 tries × 9 cells per agent tests whether this near-equivalence holds across problems and tries, or is a coincidence of this one cell. Implication for Phase-3 wall extrapolation: per-cell wall should be projected on a **turns-to-terminal model**, not a per-turn-pace model — the differentiating axis across agents on the same cell appears to be convergence speed, not per-turn computation speed.

### Addendum 2 closes the postmortem-003 calibration-probe lineage

Five probes; three findings opened and closed (F-035, F-036, F-039); two operator-resolved (F-038); one defence-in-depth confirmed (F-037); one new (F-040). The calibration arc is complete on the experiment-lead side. Phase-3 launch is the next live decision, downstream of operator/language-team work named in the "Closing" section above.

If Phase-3 launch surfaces F-040 (multi-file rubric under-reporting) as load-bearing for some H1/H2/H3 measurement that wasn't visible at probe time, that surfaces as `postmortem-004-phase3-launch-…`. If F-040's path-1 fix is authorized this session or a near-future session, the fix lands as a separate harness-engineering commit with its own Phase-3-readiness checklist update.
