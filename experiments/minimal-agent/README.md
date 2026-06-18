# Minimal Agent Experiment

This experiment tests whether an agent can write a correct LLMLL solution from
minimal context on the first round.

Each run directory contains only:

- `LLMLL.md`
- `llmll-ast.schema.json`
- `bin/llmll`
- `problem.md`
- `AGENT_INSTRUCTIONS.md`
- `PROBLEMS.md`
- optional run-local scaffold templates under `.llmll/templates/`

`llmll-ast.schema.json` is copied from `docs/llmll-ast.schema.json` so JSON-AST
runs have the complete machine-readable node schema in their isolated directory.
Experiment `003` runs also receive
`.llmll/templates/ecommerce-order-handler/scaffold.ast.json`. The harness puts
`bin/llmll` first on `PATH`; that wrapper delegates to the real compiler and
sets `HOME=$PWD` only for `llmll hub scaffold`, keeping template resolution
inside the run directory.

The agent is instructed to work only inside that directory, record every issue in
`PROBLEMS.md`, and stop at the first error. The harness also stops evaluation at
the first failing compiler/tool command.

## Prepare One Run

Experiments live as one markdown file per task under
`experiments/minimal-agent/experiments/`.

Naming convention:

- `NNN-kebab-case-slug.md`
- `NNN` is a stable three-digit experiment id
- the slug is human-readable and stable enough for manifests

Selectors accepted by `prepare_run.py`:

- `001`
- `1`
- `two-agent-auth`
- `001-two-agent-auth`
- `001-two-agent-auth.md`
- `all`

```bash
python3 experiments/minimal-agent/scripts/prepare_run.py --experiment 001 --label agent-a
```

This prints a path like:

```text
experiments/minimal-agent/runs/20260503T120000Z-agent-a-e001
```

No agent is launched by `prepare_run.py`.

`--problem 1`, `--problem 2`, and `--problem 3` remain compatibility aliases
for `--experiment 001`, `--experiment 002`, and `--experiment 003`.

## Run One Agent

Pass any agent command. It runs with `cwd` set to the prepared run directory.

```bash
python3 experiments/minimal-agent/scripts/run_agent.py \
  experiments/minimal-agent/runs/20260503T120000Z-agent-a-e001 \
  --agent-name agent-a \
  --agent-cmd 'your-agent-command "Read AGENT_INSTRUCTIONS.md and complete the task."'
```

If the agent exits successfully, the harness runs evaluation automatically. If
the agent exits nonzero or times out, the harness stops there.

If `llmll` is not on `PATH`, pass a compiler command prefix:

```bash
--llmll-cmd "stack --stack-yaml /absolute/path/to/compiler/stack.yaml exec llmll --"
```

## Mixed-Agent Matrix

Use a JSON manifest for repeated runs across agents and experiments:

```bash
python3 experiments/minimal-agent/scripts/run_matrix.py \
  experiments/minimal-agent/manifest.example.json \
  --prepare-only
```

Remove `--prepare-only` to launch the listed commands. The example manifest is a
template; replace each `cmd` with the actual agent invocation.

Each agent/experiment cell runs three independent attempts by default. Set
`run_count` in the manifest, set per-agent `run_count`, or pass `--run-count` to
override it. The matrix runner continues after failed attempts unless
`--fail-fast` is set.

Manifest shape:

```json
{
  "experiments": ["001", "002", "003"],
  "run_count": 3,
  "llmll_cmd": "llmll",
  "timeout_seconds": 1800,
  "skip_verify": false,
  "agents": [
    {"name": "agent-a", "cmd": "agent-a-command"},
    {"name": "agent-b", "cmd": "agent-b-command"}
  ]
}
```

The older `"problems": [1, 2, 3]` manifest field is still accepted as a
compatibility alias.

The matrix runner writes both:

- `matrix_report.json`: all attempts with harness/evaluation summaries, first
  errors, grades, feature gaps, test summaries, and contract summaries
- `matrix_summary.md`: a compact table with one row per attempt

## Evaluation

`evaluate_run.py` finds `solution.ast.json` first, then `solution.llmll`. It
runs these checks in order and stops at the first effective error:

1. `llmll check`
2. `llmll check --strict`
3. `llmll --json holes --deps`
4. `llmll test`
5. `llmll verify --trust-report --weakness-check --spec-coverage`

An effective error includes a nonzero exit code and compiler diagnostics printed
with exit code 0, such as parse errors emitted by `llmll check`.

After the graded sequence succeeds, the evaluator runs one additional, ungraded
`llmll verify --obligation-report` to capture the v0.12.0 Bundle B0 effect/authority
summary (see `effect_summary` below). It is a separate run because `--obligation-report`
does not compose with `--trust-report` (mutually-exclusive output modes). This probe is
capture-only: it sits outside the first-error stop policy, runs only on the success path,
and never changes the grade.

The evaluator writes:

- `evaluation.json`
- `summary.md`

It also performs a static feature scan for the constructs requested by each
experiment. Feature scan misses are reported but do not override the first failing
tool command. Conditional constructs are required only when the harness provides
the matching input. For example, experiment `003` requires `scaffold` when
`.llmll/templates/ecommerce-order-handler/scaffold.ast.json` is present in the
run metadata; older runs without the template do not require it.

`evaluation.json` also includes:

- `quality_grade`: `A`, `B`, `C`, or `F`
- `test_summary`: parsed property totals, passed, failed, and skipped
- `test_assessment`: adjusted test counts after excluding delegation-dependent
  checks that cannot run statically
- `verify_summary`: parsed trust-report counts
- `verify_details`: per-function trust-report pre/post status
- `contract_assessment`: expected-contract scoring for only the contracts
  explicitly requested by the problem
- `effect_summary`: v0.12.0 Bundle B0 per-function effect/authority summary — the
  object-capability authority each function may reach (`∅`, declared capabilities such
  as `fs.read` / `fs.write` / `stdout`, or `unbounded` ⊤ at `?delegate`/FFI boundaries),
  plus `all_bounded` / `any_unbounded` roll-up, `cross_module`, and the obligation-report
  schema version. **Descriptive only** — does not affect `quality_grade` or the stop
  policy; `null` if the probe emitted no obligation-report JSON
- `problems_md`: entry count and stale marker checks
- `agent_duration_seconds`
- `total_eval_duration_seconds`

Grades are intentionally conservative, but they score the exercise contract
rather than raw compiler totals:

- Raw `no contract` functions do not lower the grade unless the problem
  explicitly required a contract on that function.
- A contract marked with `?proof-required` can satisfy the expected contract
  even if the trust report can only mark it `asserted`.
- Delegation-dependent failed or skipped checks are excluded from the effective
  test pass rate because the static runner cannot execute live agents.

Grade meanings:

- `A`: all applicable tests passed and expected contracts are met without
  unproved non-proof contracts
- `B`: commands passed and expected contracts are met, but evidence is bounded
  by assertions or delegation-only checks
- `C`: commands passed, but applicable tests or expected contracts are still
  incomplete
- `F`: the agent or evaluator failed

## Compare Runs

Generate a Markdown table for all runs:

```bash
python3 experiments/minimal-agent/scripts/compare_runs.py
```

Write the same table to a file:

```bash
python3 experiments/minimal-agent/scripts/compare_runs.py \
  --write experiments/minimal-agent/runs/comparison.md
```

Compare selected runs:

```bash
python3 experiments/minimal-agent/scripts/compare_runs.py \
  experiments/minimal-agent/runs/20260508T233513Z-codex-v010-e001 \
  experiments/minimal-agent/runs/20260508T234941Z-codex-v010-e002
```

## Stop Policy

Prepared runs still measure one first-round solution attempt; the matrix runner
can create three independent prepared runs per agent/experiment cell by default.

- The agent instruction says to stop after the first failed tool command.
- `run_agent.py` stops if the agent command exits nonzero or times out.
- `evaluate_run.py` stops at the first failing compiler/tool command or emitted
  compiler diagnostic.

This keeps the measurement focused on **first-round effectiveness** — one
empirical regime under the project's governing design criterion
(`docs/compiler-team-roadmap.md:6`, disambiguated 2026-05-11; rationale in
`docs/design/empirical-methodology.md`). Repair-loop effectiveness is a
sibling regime measured by a separate harness (`experiments/repair-loop/`,
in design); it is not measured here by design.
