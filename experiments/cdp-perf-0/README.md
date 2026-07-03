# cdp-perf-0 — CDP candidate-sweep wall-clock characterization

> **Status:** Active. Phase 1 + Phase 2 complete — definitive primary-corpus cost model at `runs/20260703T051809Z-phase2/` (`overhead_ms ≈ 27.32 + 43.47 × candidate_count`, R²=0.9995). See `findings.md`.
> **Owner:** experiment-lead
> **Gate consumer:** `docs/compiler-team-roadmap.md`'s "CDP default-on" row — the stated remaining blocker to promoting `--cdp` into the default serious-verify path ("no wall-clock characterization of the `--cdp` candidate-sweep exists").

## 1. Purpose

Measures the wall-clock cost of `llmll verify --cdp --trust-report` versus bare `llmll verify` across the shared `cdp-0` primary corpus, and fits `overhead_ms ~ a + b * total_candidate_count` (one data point per fixture — wall-clock is measured per whole compiler invocation, so `total_candidate_count` is summed across all contracted functions in that fixture). This is descriptive input to the default-flip decision, not the decision itself — no ratio/threshold is pre-committed as pass/fail.

## 2. What this harness is NOT

- **Not `cdp-0`.** That harness measures DP-score distributions over a corpus; zero timing instrumentation. This harness measures wall-clock only; it does not compute or report DP scores (though it reads `candidate_count` out of the same `discriminative_axis` JSON block `cdp-0` reads).
- **Not `int-pre`.** That harness compares two *compiler variants* (different codegen) on *generated-program runtime*. This harness compares two *CLI flag modes* of the *same compiler build* on *compile-time* (verify-time) latency. Lighter replication discipline follows from that difference (5+1 reps, not 10+2; no CPU-governor enforcement, only a documented note).
- **Not an agent-effectiveness harness.** Zero models invoked.

## 3. Corpus

`cdp-0`'s 6-fixture primary corpus (`b1`, `b3`, `b5`, `totp`, `erc20`, `banking`), not the 30-fixture secondary discovery — this is a cost-model-fitting run (n=6 fixtures is enough range for a two-parameter linear fit given `candidate_count` spans 0–12 per function in this corpus), not a corpus-representativeness claim. Secondary corpus is a Phase 2 option if the primary-corpus fit has high residual variance.

## 4. Running

```bash
python3 experiments/cdp-perf-0/scripts/cdp_perf.py
```

Writes `runs/<UTC-timestamp>/{results.json, summary.md, per-fixture/*.json}`. Each fixture is measured under both modes (`bare`: no flags; `cdp`: `--cdp --trust-report`), 1 warmup + 5 measured reps each (`manifest.json` `reps`), median reported. No network access, no model invocation.

## 5. Compiler pin

`llmll 0.14.5`, tag `v0.14.5`, commit `e50b1f1`, branch `main`.

## 6. Findings surface

`findings.md` (H2-per-role) + `findings/postmortem-NNN-<slug>.md`, per DOC-CONSOLIDATE M1 — same convention as `cdp-0`/`int-pre`/`adv-spec-weaken-0`.

## 7. Out of scope

- **The default-flip decision itself.** This harness produces the wall-clock number(s); whether that number justifies flipping bare `verify`'s default is a roadmap-owner (language-team/user) call, not this harness's.
- **Secondary-corpus validation, profiling-level cost-center attribution** (à la `int-pre`'s `ghc -prof` secondary gate) — both are Phase 2 candidates if the primary-corpus fit is inconclusive, not run here.
