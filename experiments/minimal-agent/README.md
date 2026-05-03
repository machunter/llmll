# Minimal Agent Experiment

This experiment tests whether an agent can write a correct LLMLL solution from
minimal context on the first round.

Each run directory contains only:

- `LLMLL.md`
- `problem.md`
- `AGENT_INSTRUCTIONS.md`
- `PROBLEMS.md`

The agent is instructed to work only inside that directory, record every issue in
`PROBLEMS.md`, and stop at the first error. The harness also stops evaluation at
the first failing compiler/tool command.

## Prepare One Run

```bash
python3 experiments/minimal-agent/scripts/prepare_run.py --problem 1 --label agent-a
```

This prints a path like:

```text
experiments/minimal-agent/runs/20260503T120000Z-agent-a-p1
```

No agent is launched by `prepare_run.py`.

## Run One Agent

Pass any agent command. It runs with `cwd` set to the prepared run directory.

```bash
python3 experiments/minimal-agent/scripts/run_agent.py \
  experiments/minimal-agent/runs/20260503T120000Z-agent-a-p1 \
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

Use a JSON manifest for repeated runs across agents and problems:

```bash
python3 experiments/minimal-agent/scripts/run_matrix.py \
  experiments/minimal-agent/manifest.example.json \
  --prepare-only
```

Remove `--prepare-only` to launch the listed commands. The example manifest is a
template; replace each `cmd` with the actual agent invocation.

Manifest shape:

```json
{
  "problems": [1, 2, 3],
  "llmll_cmd": "llmll",
  "timeout_seconds": 1800,
  "skip_verify": false,
  "agents": [
    {"name": "agent-a", "cmd": "agent-a-command"},
    {"name": "agent-b", "cmd": "agent-b-command"}
  ]
}
```

## Evaluation

`evaluate_run.py` finds `solution.llmll` first, then `solution.ast.json`. It
runs these checks in order and stops at the first nonzero exit code:

1. `llmll check`
2. `llmll check --strict`
3. `llmll --json holes --deps`
4. `llmll test`
5. `llmll verify --trust-report --weakness-check --spec-coverage`

The evaluator writes:

- `evaluation.json`
- `summary.md`

It also performs a static feature scan for the constructs requested by each
problem. Feature scan misses are reported but do not override the first failing
tool command.

## Stop Policy

There are no retries in this experiment.

- The agent instruction says to stop after the first failed tool command.
- `run_agent.py` stops if the agent command exits nonzero or times out.
- `evaluate_run.py` stops at the first failing compiler/tool command.

This keeps the measurement focused on first-round effectiveness rather than
repair-loop effectiveness.
