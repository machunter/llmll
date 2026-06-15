# Bundle B0 experiment (004) — design

Run-host-facing design for experiment `004-capability-bounded-summarize`. This
is **not** loaded as a task (it lives under `findings/`, not `experiments/`); the
agent sees only the pure problem spec in `experiments/004-…​.md`.

## Status — RE-SCOPED (F-B0-3, 2026-06-15)

The pilot (`20260615T005559Z`) returned an uninformative null and the redesign hit a
**structural block** (postmortem-007 F-B0-3): in single-file LLMLL every capability is
syntactically evident — direct `wasi.*` calls self-telegraph, and an opaque imported
helper's effect is **not** propagated into the caller's `effect_summary`
(`computeEffectSummary` walks the flattened single-file call graph; cross-module is
`"unsupported"`). So 004 cannot be made B0-powerful by rewording the task.

- **Actioned:** `REQUIRED_FEATURES[4] = ["check","post"]` (`evaluate_run.py`) — stops the
  evaluator grading vacuous stubs A (the pilot defect).
- **Gated:** a powerful 004 needs **cross-module `effect_summary` propagation** (routed to
  compiler-engineer). Until it lands, the **Trap** section below is *superseded* — do not
  run 004 as a B0 verdict instrument. The Run + score procedure (scoring with
  `--require fs.read,fs.write`) stands for the eventual re-run.

## Hypothesis

Surfacing the per-function `effect_summary` (Bundle B0, shipped `b2d9c1a`) in the
agent's **initial** context raises capability-correctness on a task with a
forbidden-capability constraint. Success = adherence-rate(A) > adherence-rate(B),
n-backed. Null = no separation. Failure = B ≥ A.

## The trap (SUPERSEDED — see Status above)

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
