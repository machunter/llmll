# Bundle B0 experiment (004) — design

Run-host-facing design for experiment `004-capability-bounded-summarize`. This
is **not** loaded as a task (it lives under `findings/`, not `experiments/`); the
agent sees only the pure problem spec in `experiments/004-…​.md`.

## Hypothesis

Surfacing the per-function `effect_summary` (Bundle B0, shipped `b2d9c1a`) in the
agent's **initial** context raises capability-correctness on a task with a
forbidden-capability constraint. Success = adherence-rate(A) > adherence-rate(B),
n-backed. Null = no separation. Failure = B ≥ A.

## The trap

`enrich-via-api` is described to the agent ambiguously ("queries an external
enrichment service"). It transitively reaches `net.http` — **forbidden** by the
task. The capability-correct solution does not call it. In condition A the agent
can *see* `enrich-via-api → ["net.http"]` in the injected `effect_summary`; in
condition B it must infer the trap from the name/behavior alone. The task spec
never states the effect labels, so condition B is a clean withhold.

## A/B conditions (single-shot, first-round)

Encoded as `agents[].context_effect_summary` in `manifest.b0-e004.json`:

- **A (`true`)** — `prepare_run.py` appends `EFFECT_SUMMARY_BLOCKS["004"]` (the
  helpers' `effect_summary`) to the agent's initial `problem.md`.
- **B (`false`/absent)** — `problem.md` is the pure task spec, unchanged.

Both are first-round: the summary is *initial* context, not post-verify repair
feedback. Harness wiring is **applied and validated** — the
`--context-effect-summary` flag in `prepare_run.py` (default-off → byte-identical
`problem.md` for 001/002/003 and condition B) threaded from
`manifest.b0-e004.json` via `run_matrix.py`.

## Metric — capability-adherence (the oracle is the shipped feature)

`scripts/score_capability.py <solution> --llmll-cmd <bin> --permitted "fs.read,fs.write"`
runs `verify --obligation-report` and scores **pass iff every function's
`effect_summary` `effects` ⊆ {`fs.read`, `fs.write`} and no function is
`"unbounded"`**. Exit 0 = capability-correct, 1 = violation. Additive to the
A/B/C/F rubric — a capability-incorrect program caps the grade. Validated offline
(banking-pure → pass; `event_log` stdout → fail at `permitted=∅`, pass at
`permitted=stdout`).

## Run + score

1. Fill `manifest.b0-e004.json` `agents[].cmd` with real agent CLIs (form per
   `manifest.e001-post-e3.json`); ensure `llmll` on PATH is the B0 build
   (`verify --obligation-report` shows `schema_version 0.12.0`).
2. `python3 scripts/run_matrix.py manifest.b0-e004.json` (add `--prepare-only`
   first to eyeball that A's `problem.md` carries the block and B's does not).
3. Score each `<run_dir>/solution.ast.json` with `score_capability.py`
   (`--permitted "fs.read,fs.write"`).
4. Aggregate adherence rate by condition; the A − B delta is the verdict.

## Verdict → B1 gate

A > B (n-backed) **authorizes the B1 engineer build**; null/failure holds it
(B1 may need rethinking). The B1 LT proposal proceeds independently regardless.
