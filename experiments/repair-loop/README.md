# Repair-Loop Experiment

This experiment measures **repair-loop effectiveness** — the regime where an
agent iterates against verifier feedback until reaching a terminal state (success
or budget exhaustion). It is a **sibling** to `experiments/minimal-agent/`, not a
replacement.

The two harnesses answer different questions:

| Harness | Question | Stop policy |
|---|---|---|
| `minimal-agent/` | Can an agent write a correct LLMLL solution on the first round? | First failed tool command |
| `repair-loop/` (this) | Does iterative verifier feedback drive an agent toward a terminal state, and does the verification surface produce a measurable advantage over equivalent-budget controls in other languages? | Budget exhaustion *or* terminal target reached, whichever comes first |

Both regimes are legitimate under the project's governing design criterion
(`docs/compiler-team-roadmap.md:6`, disambiguated 2026-05-11; rationale in
`docs/design/empirical-methodology.md`).

## Phases

The empirical question is multi-phase. Phase 1 is the apparatus validation;
Phase 2 calibrates *k*; Phase 3 runs the full matrix.

| Phase | Purpose | Sample | Status |
|---|---|---|---|
| 1 | Apparatus validation: prove the loop closes | 1 stub agent × 1 problem × 1 language × k=3, plus k=1 real-agent kink cells on both `.llmll` and `.ast.json` forms | **Closed** (postmortem-001 Addenda 1–2) |
| 2 | Calibration: tune *k* and verify scoring on a known-tractable cell | `gemini-default` × `002-bank-ledger` × 3 languages (`llmll` + Python + Go) × k=5 × 3 tries = 9 cells | Pending (composition pinned per `findings/postmortem-001-apparatus-validation.md` Addendum 10; launcher and manifest still to author) |
| 3 | Full campaign: test H1/H2/H3 across QF-LIA boundary | 3 agents × 3 problems × 3 languages (`llmll` + Python + Go) × k=5 × 3 tries | Pending |
| 4 | Ceiling test against a strong-typed control | + Rust as a stretch baseline; contingent on Phase 3 results | Deferred |

Each phase requires explicit user approval before launch. Phase boundaries
prevent inadvertent escalation from "validate the apparatus" to "spend $500 on a
matrix."

## Hypotheses

Pre-stated, falsifiable.

**H1 (assurance differential).** At fixed *k*, LLMLL agents reach a higher
terminal assurance score than Python or Go agents on the same problem,
holding correctness constant. (Rust as a stronger-typed ceiling baseline is
deferred to a Phase-4 stretch run; see postmortem-001 Addendum 3 for
rationale.)

**H2 (convergence differential).** On tasks whose dominant invariant class is
inside LLMLL's QF-LIA fragment (`LLMLL.md §5.3.3 / §5.3.5`), LLMLL converges in
fewer turns than Python.

**H3 (boundary-of-value, null-watcher).** On tasks whose dominant invariant
class is outside QF-LIA, LLMLL produces no measurable advantage. Confirmation
bounds the value claim; refutation extends it.

The three Phase-3 problems are chosen to span the QF-LIA boundary deliberately
so H3 has signal regardless of direction:

- `002-bank-ledger` — financial invariant, QF-LIA-dominant
- `003-rate-limiter` — bounded counter with nonlinear refill, mixed
- `001-hangman` — state-machine, non-QF-LIA-dominant

## Directory Layout

```text
experiments/repair-loop/
  README.md
  manifest.example.json         # campaign manifest schema example
  problems/                     # language-neutral product specs
    002-bank-ledger.md
  targets/                      # per-language adapter configs
    llmll.json
  testkits/                     # per-language black-box tests (per problem)
    002-bank-ledger/            # populated as targets are added
  scripts/
    run_repair_loop.py          # single-cell orchestrator
    run_matrix.py               # matrix runner over run_repair_loop
    evaluate_run.py             # target-aware evaluator
  findings/                     # per-consumer postmortems
    postmortem-001-apparatus-validation.md
  runs/                         # timestamped run directories (gitignored)
```

## Manifest Shape

Manifests inherit from `docs/design/language-comparison-experiments.md` with two
additions for the loop's stop policy: `repair_budget_k` and `terminal_target`.

```json
{
  "experiments": ["002-bank-ledger"],
  "targets": ["llmll"],
  "run_count": 1,
  "repair_budget_k": 3,
  "terminal_target": {
    "kind": "trust-tier",
    "value": "all-expected-contracts-verified-or-asserted"
  },
  "timeout_seconds_per_turn": 600,
  "agents": [
    { "name": "claude-opus-4-7", "cmd": "<agent-command>" }
  ]
}
```

Each matrix cell is `agent × problem × target × attempt`. A cell's run directory
contains per-turn logs (`turn_NN/agent.stdout.log`, `turn_NN/verifier.json`),
the agent's accumulating solution files, and an integrated `repair_loop_log.json`.

### Matrix-runner extensions

`run_matrix.py` layers three optional manifest fields on top of the single-cell
shape:

- **`terminal_target_per_target`** — map of `target → terminal_target`. Resolved
  per cell when the matrix spans mixed verification surfaces (Phase 2 uses
  trust-tier for `llmll` and all-pass for Python / Go). Falls back to the
  manifest-level `terminal_target` when a target is not in the map.
- **`batch_label`** — string suffix on the batch directory name (default
  `matrix`). Useful when several manifests share a run timestamp.
- **Per-agent `required_env` / `required_executables`** — lists checked before
  any cell launches. The matrix exits early with the full prereq-failure list,
  so the operator sees the entire surface in one pass rather than discovering
  gaps cell-by-cell.

```json
{
  "batch_label": "phase2-calibration",
  "experiments": ["002-bank-ledger"],
  "targets": ["llmll", "python", "go"],
  "run_count": 3,
  "repair_budget_k": 5,
  "terminal_target_per_target": {
    "llmll":  { "kind": "trust-tier", "value": "all-expected-contracts-verified-or-asserted" },
    "python": { "kind": "all-pass" },
    "go":     { "kind": "all-pass" }
  },
  "timeout_seconds_per_turn": 540,
  "agents": [
    {
      "name": "gemini-default",
      "cmd": "<agent-command>",
      "required_executables": ["gemini"]
    }
  ]
}
```

## Run a Single Cell

```bash
python3 experiments/repair-loop/scripts/run_repair_loop.py \
  --manifest experiments/repair-loop/manifest.example.json \
  --experiment 002-bank-ledger \
  --target llmll \
  --agent-name claude-opus-4-7 \
  --agent-cmd '<your agent command>'
```

For apparatus validation without API spend, the orchestrator supports a stub
agent that emits deterministic per-turn outputs:

```bash
python3 experiments/repair-loop/scripts/run_repair_loop.py \
  --manifest experiments/repair-loop/manifest.example.json \
  --experiment 002-bank-ledger \
  --target llmll \
  --agent-name stub \
  --stub-agent
```

## Run a Matrix

For multi-cell campaigns use `run_matrix.py`, which enumerates cells, generates
per-cell synthetic manifests, invokes `run_repair_loop.py` once per cell, runs
`evaluate_run.py` after each, and aggregates `matrix_report.json` /
`matrix_summary.md`.

```bash
python3 experiments/repair-loop/scripts/run_matrix.py \
  experiments/repair-loop/manifest.phase2-calibration.json
```

**Cell ordering.** Cells are enumerated `target × experiment × agent × attempt`
(outer to inner). All tries of a single `(target, experiment, agent)` are
contiguous, which keeps adapter-specific failure clusters readable in the
report. The 1-based cell index is the unit `--resume-from-cell` operates on.

**Resume.** A 9-cell Phase-2 run at `k=5 × 540s/turn` has a ~6.75h wall-clock
ceiling, so partial-progress recovery is load-bearing. To resume:

```bash
python3 experiments/repair-loop/scripts/run_matrix.py \
  experiments/repair-loop/manifest.phase2-calibration.json \
  --batch-id 20260512T031938Z \
  --resume-from-cell 5
```

The runner skips cells before `--resume-from-cell` and any cell index already
recorded in the batch's `matrix_report.json` (force a retry by passing a fresh
`--batch-id`).

**Outputs (per batch).**

```text
runs/<batch-id>-<batch_label>/
  matrix_manifest.json    # snapshot of the input manifest + harness git SHA
  matrix_plan.json        # enumerated cells (cell, target, experiment, agent, attempt)
  matrix_report.json      # rolling per-cell results, rewritten after each cell
  matrix_summary.md       # human-readable per-cell status table
  cells/cell_NN/
    manifest.json         # synthetic per-cell manifest passed to run_repair_loop.py
    orchestrator.stdout.log
    orchestrator.stderr.log
```

**Flags.**

- `--prepare-only` — enumerate cells, write `matrix_plan.json`, skip launch.
- `--fail-fast` — stop the matrix on the first `infrastructure-fail` /
  `harness-error` cell.
- `--skip-prereqs` — bypass per-agent `required_env` / `required_executables`
  checks (offline harness work only).
- `--no-evaluate` — do not invoke `evaluate_run.py` after each cell.
- `--batch-id <id>` — reuse an existing batch directory (required when
  resuming).
- `--llmll-cmd <cmd>` — override `manifest.llmll_cmd` for this invocation.

## Pre-Launch Service Status Check

Before launching any matrix that includes paid agents, confirm each LLM provider's status page reports a healthy service across the intended probe / launch window. Provider incidents produce the same 0-byte-output failure signature as harness or auth bugs (`findings/postmortem-002-phase3-calibration-probe.md` F-036 hypothesis 4, 2026-05-15) and silently contaminate the diagnostic signal — circuit breaker B catches the consequence but does not distinguish the cause, so a probe launched during a degraded window costs probe-budget and answers no design question.

| Provider | Agent | Status URL |
|---|---|---|
| Anthropic | `claude-default` (Claude Code CLI) | `https://status.claude.com` |
| OpenAI | `codex-default` (codex-cli) | `https://status.openai.com` |
| Google | `gemini-default` (Gemini CLI) | `https://status.cloud.google.com` — Gemini API runs under the Google Cloud / Vertex AI status surface; verify the operator-relevant region and product are reporting Clean before launch |

Operator-side discipline (no harness-side automation):

1. Open each provider's status URL at the time of launch authorization. Confirm Clean state across all of: the API endpoint the agent CLI calls, the region the operator's account uses, and the model identifier in the manifest.
2. If any provider reports a degraded incident affecting any of the above, defer the matrix launch until the incident clears. A fresh incident opening between this check and `run_matrix.py` invocation re-introduces the contamination risk; tightening the gate to "Clean throughout the launch window" is operator judgment.
3. Once launched, the provider's status state during the run is captured implicitly via per-cell `agent.stdout.log` and `agent.stderr.log` artifacts plus `repair_loop_log.json:agent_rc`. If a cell exits with `agent_rc=124` (Unix timeout) and 0-byte agent stdout/stderr, the diagnostic landscape includes a service-incident hypothesis alongside output-buffering / auth / startup hypotheses (postmortem-002 F-036).

Programmatic status-check automation (HTTP fetch + parse of each provider's status page) is *not* implemented as a stop-fast discipline because provider status-page formats vary, change without notice, and are slow-moving relative to the probe cadence. Operator-side 30-second check is the cheaper discipline. Circuit breaker B remains the runtime safety net if an incident opens mid-run.

## Stop Policy

Each cell runs *up to* `repair_budget_k` turns. Each turn:

1. Orchestrator invokes the agent with the current run-directory state
   (problem.md, target adapter, prior turns' verifier output).
2. Agent writes solution files into the run directory.
3. Orchestrator runs the target adapter's verifier commands and captures their
   structured output.
4. Orchestrator evaluates the terminal-target predicate against the verifier
   output. If matched, the cell exits with `terminal_state: target-reached`.
5. Otherwise, the verifier output is appended to context for turn N+1 and the
   loop continues.

If *k* turns elapse without reaching the terminal target, the cell exits with
`terminal_state: budget-exhausted`. Both are valid outcomes; divergence rate
across the matrix is itself a measurable.

**Exclusion conditions for analysis:** infrastructure failures (agent did not
invoke) and toolchain failures (per-language adapter could not run) are logged
distinctly from agent failures, per
`docs/design/language-comparison-experiments.md:241`.

## Credibility predicate and the H1 split (R6d)

The trust-tier predicate that decides target-reached is split from the
*assurance* signal that flows into H1. Both derive from the trust report,
but they answer different questions.

**`Cred(R)`** — boolean, loop-control. `Cred(R) ≡ (|R| > 0) ∧
(n_asserted(R) = 0) ∧ (n_no_contract(R) = 0)`. Universal lattice-meet
reading: every obligation must clear above-`asserted` for the cell to
count as target-reached. The pre-R6d predicate accepted `asserted` as
terminal; the R6d adjudication (`findings/language-team.md` §LT-A,
settled 2026-05-12 after a professor pass) tightens that to the meet
over the diamond at-or-above the asserted threshold. The reading is
universal, not existential — a single `asserted` or `no_contract` entry
fails the cell.

**`tier_profile`** — six-Int aggregate emitted by the compiler in the
trust-report JSON (`docs/llmll-trust-report.schema.json`, introduced
2026-05-12 via `bb1bd98`). Fields: `verified, proved, contract_checked,
tested, asserted, no_contract`. Reported per-cell as the LLMLL-side
**Assurance** signal. Component-wise dominance is the only legitimate
partial order; reports incomparable under it are *legitimately
incomparable*, faithful to `LLMLL.md §4.4.1:344` (`contract_checked ‖
tested`).

The split implements the H1 bifurcation:

- **H1-Correctness** — same testkit black-box tests applied to all three
  targets (LLMLL testable here via `CodegenHs`). Cross-paradigm-
  comparable measurement.
- **H1-Assurance** — reported per-target in native vocabulary, never
  scalarized cross-paradigm. LLMLL reports `tier_profile`; Python and Go
  report their native binaries (`all-tests-pass`-style). The harness
  refuses to aggregate `tier_profile` into a single number — six fields
  are reported side-by-side; component-wise dominance is the only
  operation that respects the diamond.

**No-scalarization discipline.** A cardinal-weighted mean over
`tier_profile` (`verified=1.0, contract_checked=0.75, tested=0.5, …`)
was proposed during the language-team adjudication and rejected on
review: any total order over `contract_checked` vs `tested` collapses
`LLMLL.md §4.4.1:344`'s diamond, contradicting the spec's
epistemic-status note at `:346-347` (logical evidence vs statistical
evidence as categorically different kinds of trust signal). The design
folder's prior commitment (`docs/design/language-comparison-experiments.md:27`:
*"avoid a single 'winner' score that treats unit tests and body-faithful
verification as equivalent"*) stands. If a scalar becomes operationally
necessary later for plotting, the harness must derive it outside this
section with explicit `weights_version` plus a monotonicity-preservation
invariant under re-tune.

**References.**

- `LLMLL.md §4.4.1:344` — diamond incomparability declaration
- `LLMLL.md §4.4.1:346-347` — epistemic-status rationale (load-bearing)
- `docs/design/language-comparison-experiments.md:20-35` — Correctness /
  Assurance separation; single-winner-score prohibition
- `docs/llmll-trust-report.schema.json:5` — trust-report versioning is
  independent of the AST schema
- `findings/language-team.md` §LT-A — R6a / R6b / R6c framing; R6d
  resolution
- `findings/postmortem-001-apparatus-validation.md` F-026 / F-027 — the
  empirical batch that surfaced the predicate-vocabulary question

## Scoring

The repair-loop harness reuses the two-axis scoring rubric proposed in
`docs/design/language-comparison-experiments.md:198-226`:

- **Correctness score** (100): solution discovery, build/typecheck, API
  conformance, core behavior, edge cases, determinism.
- **Assurance score** (100): static structure, runtime checks, test quality,
  contract strength, proof/trust evidence, specification adequacy.

Per-cell artifacts include both scores in `evaluation.json` plus per-turn
trajectory in `repair_loop_log.json`.
