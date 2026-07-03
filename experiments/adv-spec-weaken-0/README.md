# adv-spec-weaken-0 — Adversarial spec-weakening benchmark

> **Status:** Active. First run complete; definitive data at `runs/20260703T001150Z/` (`runs/20260702T232009Z/` superseded — see `findings/postmortem-001...md` self-correction note). F-001 fixed on branch `fix/trust-report-over-annotation-json` (uncommitted).
> **Owner:** experiment-lead
> **Roadmap anchor:** `docs/compiler-team-roadmap.md` § Adversarial benchmark (experiment-lead-owned).

## 1. Purpose

Measures whether `--weakness-check` / `--cdp` / `--spec-coverage` (and the bundle `--strict-verify`) catch an actor that deliberately weakens a contract until a genuinely wrong implementation verifies ("spec laundering"). Distinct from `cdp-0` (single-shot DP-score baseline over an *honest* corpus) and from OBLIG-B (obligation completeness). Two independent attack mechanisms are in scope:

- **AX1 — self-attestation gaming (CDP proposal §10 Risk #3).** `(spec-entropy :intentional)` suppresses the per-function diagnostic under both `--weakness-check` and `--cdp` (shared `raiseLowDP` gate). The module-level `over-annotation-warning` (ratio > 30%, `CDP.hs` `overAnnotationThreshold`) is the only guardrail against bulk laundering.
- **AX2 — observational-vs-semantic blind spot (`LLMLL.md §4.4.6`).** The closed candidate set Ω (§4.3.1) is finite; a contract can be surgically widened to admit exactly one wrong implementation outside Ω without needing any annotation at all.

## 2. What this harness is NOT

- **Not `cdp-0`.** That harness measures the DP-score distribution over an honest, pre-existing corpus with zero adversarial intent. This harness hand-authors honest/adversarial fixture pairs designed to probe two specific documented risk mechanisms.
- **Not an agent-effectiveness harness.** No model is invoked. All fixtures are hand-authored `.llmll` programs; the "adversary" is the fixture author (a live-agent version, prompting a model to discover the laundering strategy unprompted, is an explicitly out-of-scope Phase 2 — see `findings.md` under `## Experiment-lead`).
- **Not a CI gate.** Pure descriptive measurement.

## 3. Corpus

8 fixtures under `fixtures/`, each a `.llmll` program, run through 4 CLI configs per `manifest.json`. Two are honest controls (`ax1-00`, `ax2-00`); the rest pair a specific weakening/laundering mechanism against its control.

| ID | Axis | Mechanism |
|---|---|---|
| `ax1-00-honest-baseline` | control | tight contract, correct impl |
| `ax1-01-loud-naked` | AX1 | contract weakened to admit the closed candidate set's trivial bodies; no annotation |
| `ax1-02-loud-laundered-singlefn` | AX1 | same weakening + `(spec-entropy :intentional)`, single-function module (ratio 100%) |
| `ax1-03-diluted-above-threshold` | AX1 | same laundering in a 2-fn module (ratio 50%, above the 30% threshold) |
| `ax1-04-diluted-below-threshold` | AX1 | same laundering in a 5-fn module (ratio 20%, below the 30% threshold) |
| `ax2-00-list-honest-baseline` | control | tight list-length post, correct impl |
| `ax2-01-arith-tolerance-band` | AX2 | post widened to a ±1 band around an unbounded arithmetic quantity; wrong impl has a single-input off-by-one bug; no annotation |
| `ax2-02-list-length-trapdoor` | AX2 | same pattern over a `list-length` measure quantity; wrong impl bugs at exactly one list length |

**CLI configs** (`manifest.json` `cli_configs`): `weakness-check-json` (`--weakness-check --json`), `cdp-json` (`--cdp --trust-report --json`), `strict-verify-json` (`--strict-verify --json`), `strict-verify-text` (`--strict-verify`, no `--json`) — the last exists specifically to check a json/non-json asymmetry surfaced during fixture validation (see `findings.md`).

## 4. Running

```bash
python3 experiments/adv-spec-weaken-0/scripts/run_adv_weaken.py
```

Writes `runs/<UTC-timestamp>/{results.json, summary.md, per-fixture/*.json}`. No network access, no model invocation, no API spend — pure compiler invocations, `stack exec llmll -- [--json] verify <flags> <fixture>` (note `--json` precedes the subcommand per `cdp-0` postmortem-001 F-003 convention).

## 5. Compiler pin

`llmll 0.14.4`, commit `4d104c5`, branch `main`. A repeat run at this pin is deterministic (same argument as `cdp-0` §7: pure compiler invocations over a fixed fixture set, no model or network variance).

## 6. Findings surface

`findings.md` (H2-per-role) + `findings/postmortem-NNN-<slug>.md`, per DOC-CONSOLIDATE M1 — same convention as `cdp-0` and `minimal-agent`.

## 7. Out of scope

- **Live-agent laundering discovery.** Whether a model spontaneously discovers the weaken-and-launder strategy under repair-loop-style pressure is a distinct, real-API-cost question. Not run here; flagged as a Phase 2 candidate in `findings.md`.
- **Fixing the observed gaps.** This harness is descriptive. Compiler-shaped implications (the JSON/`--json` asymmetry, the `if`-guard-over-raw-measure body-fallback) are handed off, not patched, here.
