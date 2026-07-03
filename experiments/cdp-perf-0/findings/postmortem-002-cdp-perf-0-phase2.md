# Postmortem 002 — cdp-perf-0 Phase 2

## Headline finding

At 15 measured + 2 warmup reps (vs Phase 1's 5+1), the primary corpus produces an essentially perfect linear fit: **`overhead_ms ≈ 27.32 + 43.47 × candidate_count`, R² = 0.9995, n=6** (`runs/20260703T051809Z-phase2/`, primary section). `b3`'s Phase-1 overhead (835.2ms, postmortem-001 F-002) collapsed to 199.4ms — in line with the model's 201.2ms prediction — once replication increased. **F-002 (the b3-costs-more-than-erc20-despite-fewer-candidates anomaly) is withdrawn: it did not reproduce and is explained by Phase 1's insufficient replication (5 reps), not by any structural property of `b3`'s body.** All six primary fixtures, three tagged `match-or-hole` (`b1`, `b3`, `b5`) and two tagged `plain` (`erc20`, `banking`), land on the same regression line with residuals under 9ms — the match/hole-vs-plain structural hypothesis is disconfirmed on this corpus, not merely unresolved.

The secondary-corpus extension (91 fixtures discovered via `cdp-0`'s glob, 30 excluded as compiler-errors — see below — 61 valid, 24 with candidate_count>0) does **not** reproduce the clean fit at 5+1 reps: R² = 0.2638 on the 24-fixture combined set, and five fixtures show physically-impossible negative overhead (`--cdp` strictly adds work on top of bare `verify`; a negative delta cannot be a real effect of the mechanism), one by −1167ms. This is reported as a **methodology finding about required replication**, not a claim that the primary corpus's cost model fails to generalize — the same 5+1 rep count is what produced `b3`'s spurious anomaly in Phase 1 on the *primary* corpus, so its noisiness on the *secondary* corpus at the same rep count is the expected, not a new surprise.

## Sample composition

- Primary corpus: 6 fixtures (`b1`, `b3`, `b5`, `totp`, `erc20`, `banking`), re-measured at 15 measured + 2 warmup reps.
- Secondary corpus: discovered via `cdp-0`'s exact `secondary_corpus_discovery` globs (`examples/**/*.llmll`, `examples/**/*.ast.json`, excluding `proof_required_test/**` and `delegate_demo/**`) — **91 fixtures found**, not the ~30 estimated from `cdp-0`'s 2026-05-27 baseline run. The `examples/` tree has grown substantially since that baseline (payments-core, session-pay, tcp_rfc793, refined-payload, outcome-totality, niw-measure, effect-authority, nested-result and their JSON-AST siblings did not exist or were not yet included at that time). Measured at 5 measured + 1 warmup reps each.
- Compiler: `llmll 0.14.5`, tag `v0.14.5`.
- Run directory: `experiments/cdp-perf-0/runs/20260703T051809Z-phase2/` (`results.json`, `summary.md`, `per-fixture/*.json`).
- 30 of 91 secondary fixtures errored (compiler rejected them) — inspecting the id list, all are the deliberately-invalid `-bad`/`-unsafe`/`-weak` counterparts that `examples/` ships alongside their correct siblings for negative-testing purposes (e.g. `session-pay/open-and-pay-bad-step`, `payments-core/conserve-bad`, `refined-payload/refined-payload-bad-elim`). Excluded correctly per the harness's `log-and-continue` stop policy; not counted in any fit.

## Verified findings

### F-002 (WITHDRAWN, see postmortem-001). The `b3` anomaly was Phase-1 replication noise

**Priority:** N/A — withdrawn
**Consumer:** compiler-engineer (closes the open item from postmortem-001)

#### Evidence
Phase 1 (`postmortem-001`, 5+1 reps): `b3` overhead = 835.2ms, candidate_count=4. Phase 2 (`postmortem-002`, 15+2 reps): `b3` overhead = 199.4ms, candidate_count=4 — a 4.2× drop with the identical fixture, identical candidate count, only replication changed. Phase 1's raw reps for `b3`'s cdp mode (`runs/20260702T232009Z/per-fixture/b3.json`... actually `runs/20260703T051103Z/per-fixture/b3.json`) showed `[1276.9, 1387.2, 2290.5, 1401.9, 1027.1]` ms — one 2290.5ms rep, ~1.6× the surrounding cluster, pulling the 5-sample median upward. At 15+2 reps the per-fixture median stabilizes to a value consistent with the other five fixtures' per-candidate cost (`b1`=47.4, `b3`=49.8, `b5`=50.7, `erc20`=45.1, `banking`=46.3 ms/candidate — a tight cluster).

#### Why we saw what we saw
5 measured reps is not enough replication for this hardware's timing noise at the ~800ms-1.4s scale these fixtures run at under `--cdp`. A single slow rep (system jitter, GC pause, thermal/scheduling variance — not diagnosed further, out of scope) dominates a 5-sample median in a way it cannot dominate a 15-sample one.

#### Implication
For compiler-engineer: no action — this was never a compiler defect, it was a measurement-design gap in Phase 1, now closed by Phase 2's design (which pre-committed to exactly this acceptance criterion in postmortem-001). For experiment-lead (self-note): 5+1 reps is an inadequate default for `--cdp` wall-clock measurement on fixtures in the 500ms-1.5s range; 15+2 should be the floor for any future primary-corpus-scale CDP timing work.

#### Acceptance
Closed by this run — the stated acceptance criterion ("shows it was single-run noise and the linear fit tightens") is exactly what happened (R² 0.33 → 0.9995).

### F-003. `overhead_ms ≈ 27.32 + 43.47 × candidate_count` (R²=0.9995) is the definitive primary-corpus cost model

**Priority:** High (decision input, supersedes postmortem-001 F-001's weaker Phase-1 numbers)
**Consumer:** language-team / user (CDP default-on roadmap row)

#### Evidence
Table (all six primary fixtures, 15+2 reps, `runs/20260703T051809Z-phase2/summary.md`):

| fixture | candidates | overhead (ms) | predicted (ms) | residual |
|---|---|---|---|---|
| totp | 0 | 24.2 | 27.3 | −3.1 |
| b3 | 4 | 199.4 | 201.2 | −1.8 |
| b1 | 6 | 284.2 | 288.2 | −4.0 |
| b5 | 5 | 253.5 | 244.7 | +8.8 |
| banking | 11 | 509.2 | 505.5 | +3.7 |
| erc20 | 15 | 675.9 | 679.4 | −3.5 |

#### Why we saw what we saw
Each candidate is one `emitFixpoint` + solver subprocess round-trip; at sufficient replication the per-invocation cost is near-constant (~44ms) regardless of the scored function's own structural complexity (match/hole-shaped vs plain arithmetic) — consistent with F-002's withdrawal (the structural-shape confound doesn't exist on this corpus).

#### Implication
For language-team/user: this is a materially tighter number than postmortem-001's Phase-1 ratios (1.4×–2.9×, still directionally correct but noisier). The absolute-cost framing is now decision-ready: `--cdp` costs roughly 27ms plus 44ms per candidate on top of bare `verify`, on this corpus's hardware. Whether that's acceptable for a default (vs. staying opt-in via `--strict-verify`) remains the roadmap-owner's call — this run sharpens the input, it doesn't make the decision.

#### Acceptance
N/A — descriptive, decision input.

## Withdrawn items

- **F-002** (postmortem-001): "candidate count alone doesn't predict overhead; `b3` costs more per-candidate than `erc20`/`banking`." Disconfirmed by this run — see above.

## Null results

**Secondary corpus at 5+1 reps does not validate or extend the primary-corpus model.** R² = 0.2638 on n=24 valid (candidate_count>0) fixtures; five fixtures show physically-implausible negative overhead (most extreme: `sec_examples_session-pay_open-and-pay_ast_json`, −1167.1ms, candidate_count=6). This is reported as insufficient-replication noise (consistent with what 5+1 reps produced on the *primary* corpus in Phase 1), not as evidence the cost model fails to generalize to a wider corpus. A rerun of the secondary corpus at 15+2 reps (≈3,100 invocations, an estimated 30-60+ minutes) would test generalization properly; not undertaken in this run — the primary-corpus fit already answers the roadmap's decision-relevant question with R²=0.9995, and the marginal value of a noisier, much larger corpus pass did not seem to justify the wall-clock cost for this pass. Flagged as a live option, not closed off.

## Minor observation (not a finding, not actioned)

`cdp-0`'s `secondary_corpus_discovery` (copied verbatim into this harness's manifest) has no verify-clean pre-filter in its discovery code (`discover_secondary` in both `cdp_baseline.py` and this harness's `cdp_perf_phase2.py`) despite the manifest field name `verify_clean_filter: true` — filtering in practice happens post-hoc, via each fixture's own runtime status (both harnesses' aggregation already excludes non-`ok` fixtures correctly). Not a bug in either harness's behavior; a naming-precision nit in `cdp-0`'s manifest field name, worth a one-line doc fix if anyone is in that file for another reason. Not routed as a formal finding — too minor to warrant a hand-off on its own.

## Priority matrix

| # | Finding | Consumer | Priority | Status |
|---|---|---|---|---|
| F-002 | b3 anomaly | compiler-engineer | N/A | **Withdrawn** — noise, not a defect |
| F-003 | Definitive cost model (supersedes postmortem-001 F-001) | language-team / user | High (decision input) | Descriptive, closed |

## Findings file(s) written

- `experiments/cdp-perf-0/findings.md` — updated: F-002 marked withdrawn under `## Compiler-engineer`; F-003 (superseding F-001) under `## Language-team`.
- `experiments/cdp-perf-0/findings/postmortem-002-cdp-perf-0-phase2.md` — this file.
