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
    run_repair_loop.py          # orchestrator
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

## Scoring

The repair-loop harness reuses the two-axis scoring rubric proposed in
`docs/design/language-comparison-experiments.md:198-226`:

- **Correctness score** (100): solution discovery, build/typecheck, API
  conformance, core behavior, edge cases, determinism.
- **Assurance score** (100): static structure, runtime checks, test quality,
  contract strength, proof/trust evidence, specification adequacy.

Per-cell artifacts include both scores in `evaluation.json` plus per-turn
trajectory in `repair_loop_log.json`.
