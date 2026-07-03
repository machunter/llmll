# Postmortem 001 — cdp-perf-0 first run

## Headline finding

Across n=6 fixtures (`b1`, `b3`, `b5`, `totp`, `erc20`, `banking`; 5 measured + 1 warmup rep each, `runs/20260703T051103Z/`), `--cdp --trust-report` roughly **doubles to triples wall-clock verify time on every fixture with at least one candidate** (1.37×–2.91× across 5 of 6 fixtures; the sixth, `totp`, has zero candidates and shows no overhead, 1.01×). The pre-registered hypothesis — that overhead scales cleanly with `total_candidate_count` via `overhead_ms ≈ a + b × candidate_count` — is **not well supported**: the linear fit's R² is 0.33 (weak), driven by `b3` (4 candidates, 835ms overhead) costing more in absolute terms than `erc20` (15 candidates, 775ms overhead) despite having roughly a third the candidates. Candidate count alone does not explain per-fixture overhead; something fixture-specific (not yet identified) drives per-candidate cost higher for `b3` than for `erc20`/`banking`. This is a null result on the specific linear-model hypothesis, not a null result on "does `--cdp` cost something" — it clearly does, substantially, in absolute terms.

## Sample composition

- 6 fixtures, 2 modes (`bare`, `cdp`) each, 5 measured + 1 warmup reps per fixture×mode = 72 compiler invocations total.
- Compiler: `llmll 0.14.5`, tag `v0.14.5`, commit `e50b1f1`, branch `main`.
- Harness SHA: commit landing this postmortem (not yet committed as of writing).
- Run directory: `experiments/cdp-perf-0/runs/20260703T051103Z/` (`results.json`, `summary.md`, `per-fixture/*.json`).
- No CPU-governor enforcement was applied (per `manifest.json`'s `reproducibility.note` — this is a compile-time latency question, not a tight-threshold runtime gate; noted as a caveat, not a blocker).

## Per-fixture data

| fixture | bare median (ms) | cdp median (ms) | overhead (ms) | ratio | total candidate_count |
|---|---|---|---|---|---|
| `b1` | 436.1 | 799.6 | 363.5 | 1.83× | 6 |
| `b3` | 551.9 | 1387.2 | 835.2 | 2.51× | 4 |
| `b5` | 578.9 | 794.0 | 215.1 | 1.37× | 5 |
| `totp` | 413.9 | 418.9 | 4.9 | 1.01× | 0 |
| `erc20` | 405.7 | 1181.1 | 775.4 | 2.91× | 15 |
| `banking` | 536.5 | 950.7 | 414.3 | 1.77× | 11 |

Fit: `overhead_ms ≈ 197.40 + 34.73 × total_candidate_count`, R² = 0.3347, n = 6.

## Verified findings

### F-001. `--cdp` roughly doubles-to-triples verify wall-clock on every fixture with ≥1 candidate

**Priority:** High (decision input)
**Consumer:** user / language-team (CDP default-on roadmap row)

#### Evidence
Table above. `totp` (0 candidates) is the clean control: 1.01× ratio, 4.9ms overhead — confirms the overhead mechanism is specifically the candidate-sweep, not general `--cdp`/`--trust-report` bookkeeping. The other 5 fixtures range 1.37×–2.91×.

#### Why we saw what we saw
Each candidate triggers a full `emitFixpoint` + solver subprocess round-trip (`compiler/src/LLMLL/CDP.hs`'s `checkCDPCandidate`, mirroring `WeaknessCheck.hs`'s `checkWeaknessCandidate` structure) — i.e., `--cdp` runs on the order of `1 + candidate_count` solver invocations per function versus bare `verify`'s 1. `totp`'s zero-candidate result confirms no other `--cdp`-specific fixed cost beyond the sweep itself.

#### Implication
For the CDP default-on decision: flipping bare `verify`'s default to include `--cdp` would roughly double-to-triple the wall-clock cost of every `verify` invocation on a module with any type-compatible candidates — which is the common case (5 of 6 fixtures here). Whether that's acceptable depends on what `verify`'s typical invocation context is (interactive iteration loop vs. CI gate) — a judgment this harness does not make. The `--strict-verify` opt-in design (v0.14.4) already avoids paying this cost by default; this data is consistent with that being the right call for *now*, without asserting it's the right call *permanently*.

#### Acceptance
N/A — this is the descriptive number the roadmap row asked for, not a condition to close.

### F-002. Candidate count alone does not predict overhead — `b3` costs more per-candidate than `erc20`/`banking`

**Priority:** Medium (mechanism unclear — routed for investigation, not a confirmed bug)
**Consumer:** compiler-engineer

#### Evidence
`b3` (`examples/benchmarks/b3-safe-first.llmll`, `safe-first` function, `list[int] → int`, body is `(match (list-head xs) ((Success val) ?success_impl) ((Error e) 0))`): candidate_count=4, all four candidates plain int constants (`-1, 0, 1, 42`) per direct CLI check (`stack exec llmll -- --json verify --cdp --trust-report examples/benchmarks/b3-safe-first.llmll`). `erc20`'s scored functions (`total-supply`, `balance-of`, `allowance`) each have candidate_count=5, structurally similar int/identity candidates. Yet `b3`'s median cdp time (1387.2ms) exceeds `erc20`'s (1181.1ms) despite `erc20` running roughly 3× the total candidate checks (15 vs 4) across its module. `b3`'s cdp reps show higher variance than other fixtures (`runs/20260703T051103Z/per-fixture/b3.json`: raw timings `[1276.9, 1387.2, 2290.5, 1401.9, 1027.1]` ms — one rep at 2290.5ms, roughly 1.6× the median), but even discounting that outlier, `b3`'s median is unaffected (median of 5 already excludes the single high value) and still exceeds `erc20`'s.

#### Why we saw what we saw
Mechanism not identified. The candidates themselves are structurally similar (plain int constants) across both fixtures, so the discrepancy isn't explained by candidate *type* heterogeneity at the level this run inspected. `b3`'s body contains an unfilled hole (`?success_impl`) and a `match`/`Result`-shaped scrutinee (`list-head`) that `erc20`'s scored functions don't have — whether the per-candidate `emitFixpoint` pass costs more when the *original* function's structure (hole, match, Result type) is more complex, independent of the candidate body's own simplicity, is a plausible hypothesis, not a confirmed one. `n=6` fixtures is too small to distinguish "this is `b3`-specific noise" from "match/hole-shaped functions are more expensive to CDP-check" — the data does not resolve this.

#### Implication
For compiler-engineer: if this pattern reproduces (a Phase 2 rerun with more reps and/or the `cdp-0` secondary corpus would test it), the per-candidate cost driver may not be `candidate_count` alone but something about the *original* function's shape that the candidate-generation/emission path re-touches per candidate. Worth a profiling trace (`checkCDPCandidate`/`emitFixpoint` call path) if the default-flip decision needs a tighter cost model than "roughly 2-3×" — not undertaken here.

#### Acceptance
A rerun with ≥15 reps per fixture, or extending to the `cdp-0` secondary corpus (30 more fixtures, more `match`/`Result`-shaped functions to compare against plain-arithmetic ones), that either (a) shows `b3`'s elevated per-candidate cost is reproducible and correlates with hole/match presence, or (b) shows it was single-run noise and the linear fit tightens — would close this.

## Withdrawn items

None.

## Null results

**H1 (pre-registered): `overhead_ms ≈ a + b × candidate_count` fits cleanly (informal bar: a visually/numerically clean fit).** R² = 0.3347 on n=6 — does not meet that bar. Reported as a null result per the pre-registered null-result definition, not suppressed or reframed as a stronger claim than the data supports. See F-002 for what plausibly drives the residual.

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| F-001 | `--cdp` roughly 1.4×–2.9× verify wall-clock on fixtures with candidates | user / language-team | High (decision input) | N/A — descriptive |
| F-002 | Candidate count alone doesn't predict overhead; `b3` anomaly unexplained | compiler-engineer | Medium | Rerun with more reps / secondary corpus, or a profiling trace — not undertaken here |

## Findings file(s) written

- `experiments/cdp-perf-0/findings.md` — F-001 under `## Language-team` (decision input) and `## Experiment-lead` (user-facing summary); F-002 under `## Compiler-engineer`.
- `experiments/cdp-perf-0/findings/postmortem-001-cdp-perf-0-first-run.md` — this file.
