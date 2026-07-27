# CDP-0 — v0.10-baseline Contract-Discriminative-Power measurement

> **Status:** Active. Pending first run (awaits user authorization to execute).
> **Last updated:** 2026-05-26
> **Owner:** experiment-lead
> **Gate consumer:** `docs/archive/shipped-design-specs/core-shell-inversion-proposal.md` §8 empirical-validation gate; LT-INV-engineer post-gate measurement loads `runs/<timestamp>-baseline/baseline.json` as the comparison anchor for the *spec-strength distribution* axis.
> **Design ref:** [`docs/design/contract-discriminative-power-proposal.md`](../../docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) Rev 2 §2 (baseline-first sequencing).

## 1. Purpose

CDP-0 measures the v0.10-baseline distribution of contract-discriminative-power (`DP_Ω(S)`) scores across the existing pre-LT-INV LLMLL corpus. The output is a single aggregated `baseline.json` artifact that:

1. Publishes the score distribution (`n_contracted_fns`, `n_defined_scores`, score `mean / median / p10 / p50 / p90`, per-warning counts) so the LT-INV §8 empirical-validation gate can compare a post-LT-INV re-run against an independently-established baseline rather than against the metric's first deployment.
2. Adjudicates one of four mutually-exclusive outcome labels — **`cdp-discriminating`** / **`cdp-discriminating-weak`** / **`cdp-null`** / **`cdp-corpus-inadequate`** — that tell the language-team / compiler-engineer / user whether CDP is viable as a comparative axis for the LT-INV gate at all.

The baseline-first sequencing is load-bearing: the LT-INV §8 gate measures (among other axes) the spec-strength distribution, which *uses* the CDP metric LT-CDP defines. Measuring the baseline *before* LT-INV ships breaks the self-reference — the gate's pre/post comparison runs against this CDP-0 artifact, not against a measurement taken simultaneously with LT-INV's grammar change.

## 2. What this harness is NOT

- **Not an agent-effectiveness harness.** That's `experiments/minimal-agent/`. CDP-0 invokes zero models, makes zero API calls, has no concept of attempts or grades.
- **Not a repair-loop harness.** That's `experiments/repair-loop/`. CDP-0 does single-shot compiler invocations.
- **Not a wall-clock harness.** That's `experiments/int-pre/`. CDP-0 measures DP-score distributions, not solver wall-clock.
- **Not a cross-language harness.** That's the design-only `docs/design/language-comparison-experiments.md`. CDP-0 measures a single-language metric over a single compiler revision.
- **Not a CI gate.** The harness emits adjudication-bearing JSON consumed by the future LT-INV gate; it does not gate any current CI pipeline.

## 3. Corpus

Two corpora are scored: a frozen **primary corpus** (the same five canonical benchmarks INT-PRE used, plus the post-LT-INT `banking_ledger` example) and a discovered **secondary corpus** (every other verify-clean fixture under `examples/`). The primary corpus is the load-bearing comparison anchor for the LT-INV §8 gate; the secondary corpus surfaces signal beyond the canonical benchmarks but is reported separately so the gate-comparison stays narrow.

| Layer | Source | Reason for inclusion |
|---|---|---|
| Primary — `b1` | `examples/benchmarks/b1-withdraw.llmll` | OBLIG-B Tier 1 benchmark; INT-PRE primary |
| Primary — `b3` | `examples/benchmarks/b3-safe-first.llmll` | OBLIG-B Tier 1 benchmark; INT-PRE primary |
| Primary — `b5` | `examples/benchmarks/b5-double.llmll` | OBLIG-B Tier 1 benchmark; INT-PRE primary |
| Primary — `totp` | `examples/totp_rfc6238/totp_filled.ast.json` | RFC-anchored real-world spec; INT-PRE primary |
| Primary — `erc20` | `examples/erc20_token/erc20_filled.ast.json` | Real-world contract surface; INT-PRE primary |
| Primary — `banking` | `examples/banking_ledger/banking.llmll` | LT-INT canonical; `--strict-verified-core`-clean post-LT-INT |
| Secondary | `examples/**/*.llmll`, `examples/**/*.ast.json` minus exclusions | Discovery sweep; filtered to verify-clean fixtures |

Exclusions from secondary discovery:
- `examples/proof_required_test/**` — purpose is to exercise the `?proof-required` pipeline, not contract-discriminative measurement.
- `examples/delegate_demo/**` — agent-delegation demonstration; contracts are placeholders.

The secondary corpus is enumerated dynamically by the driver; the resulting verify-clean fixture list is captured verbatim in the postmortem.

## 4. Outcome labels

The driver emits exactly one of four labels per run, computed mechanically from the aggregated stats:

| Label | Definition | Implication |
|---|---|---|
| **`cdp-discriminating`** | Defined-score functions ≥ 50% of contracted total **AND** ≥ 25% of defined scores fall in (0.0, 1.0) | CDP is a viable LT-INV §8 axis; baseline publishable as continuous-shift comparison anchor |
| **`cdp-discriminating-weak`** | Defined-score functions ≥ 50% **BUT** scores cluster at extremes (≥ 75% are 0.0 or 1.0) | CDP viable but low-resolution; LT-INV gate uses CDP with a coarse pass/fail rule, not a continuous-shift threshold |
| **`cdp-null`** | Defined-score functions < 30% of contracted total | Binding finding: proposal §10 Risk #2 (small enumeration) fires. LT-INV §8 gate cannot use CDP as discriminating axis. Routes to language-team for §4.3.1 enumeration widening or to compiler-engineer for candidate-set extension. |
| **`cdp-corpus-inadequate`** | Total contracted functions across the verify-clean corpus < 10 | Sample too small to publish baseline; route to language-team to settle "what's the canonical CDP corpus" before re-running |

## 5. Compiler pin

The harness pins to a single compiler SHA per run. CDP-0 Rev 1 pins to:

| Field | Value |
|---|---|
| Compiler SHA | `121815a` (commit `121815a8c45596f8d125e85b3333bdf7b850582b`) |
| Branch | `lt-cdp/discriminative-power-axis` |
| `llmll version` runtime output | `llmll 0.10.8` |
| `CDPScope` | `CDPScopeAllDefLogic` (pre-LT-INV default) |

The `121815a` commit is the LT-CDP-shipped state: LT-INT and LT-CDP both landed pre-LT-INV. Per proposal §2 Rev 2, "pre-inversion" means pre-LT-INV (not pre-LT-INT), so this commit is the v0.10-baseline-equivalent for CDP purposes.

## 6. Running

```bash
cd experiments/cdp-0/
python3 scripts/cdp_baseline.py
```

The driver:
1. Reads `manifest.json` and discovers the secondary corpus.
2. For each fixture, invokes `stack exec llmll -- verify --cdp --trust-report --json <path>` with cwd at the repo root and captures stdout JSON.
3. Aggregates per-function `discriminative_axis` blocks from `entries[*]`.
4. Computes the four-label adjudication and the distribution summary.
5. Writes `runs/<YYYYMMDDTHHMMSSZ>-baseline/baseline.json` (full per-fixture JSON + aggregated stats) and `runs/<ts>-baseline/summary.md` (one-page human-readable summary).

No network access, no model invocation, no API spend. Pure single-shot compiler measurement.

## 7. Reproducibility

A repeat run at the same compiler SHA against the same primary corpus is byte-deterministic — the solver is liquid-fixpoint, the candidate set is closed per proposal §4.3.1, and the score formula is pure arithmetic on integer counts. Secondary corpus contents may shift if `examples/*` adds or removes fixtures between runs; the postmortem cites the exact secondary-corpus list per run so cross-run comparisons over the primary corpus stay clean.

## 8. Findings surface

Per DOC-CONSOLIDATE M1: `findings.md` carries H2-per-role anchors (`## Compiler-engineer`, `## Language-team`, `## Experiment-lead`, `## Documentation-lead`); the integrated postmortem lives under `findings/postmortem-NNN-<slug>.md`.

## 9. Out of scope

- **Score-shift prediction under LT-INV.** That comparison is post-hoc against the CDP-0 baseline; not a hypothesis CDP-0 itself tests.
- **`(spec-entropy :intentional)` over-annotation rate.** The current corpus has zero `(spec-entropy …)` annotations (the feature shipped with LT-CDP at commit `121815a` and `examples/*` has not been migrated); the baseline serves as the zero-annotation reference point and any future drift is measurable against it.
- **Cross-language DP comparison.** The cross-language harness at `docs/design/language-comparison-experiments.md` is a separate design with its own scoring rubric; CDP-0 stays single-language.
