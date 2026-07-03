# cdp-perf-0 findings — H2-per-role index

> Per DOC-CONSOLIDATE M1: downstream skills grep their own H2 anchor in this file. Postmortems are episodic under `findings/postmortem-NNN-<slug>.md`; this file is the consumer-routed surface that points into them.
>
> **Active postmortems:**
> - [`postmortem-001-cdp-perf-0-first-run.md`](findings/postmortem-001-cdp-perf-0-first-run.md) — F-001 (superseded by F-003, Phase 2), F-002 (withdrawn, Phase 2), `runs/20260703T051103Z/`.
> - [`postmortem-002-cdp-perf-0-phase2.md`](findings/postmortem-002-cdp-perf-0-phase2.md) — F-002 withdrawn (Phase-1 replication noise, not a real effect); F-003 supersedes F-001 with a much tighter model (R²=0.9995). `runs/20260703T051809Z-phase2/`.

## Compiler-engineer

### F-002. ~~Candidate count alone does not predict `--cdp` overhead~~ — WITHDRAWN

**Priority:** N/A
**Status:** **Withdrawn** (Phase 2, `postmortem-002`). Did not reproduce at 15+2 reps (vs Phase 1's 5+1) — `b3`'s anomalous overhead (835ms) collapsed to 199.4ms, in line with the same linear model every other primary fixture fits (R²=0.9995). Was Phase-1 replication noise (a single 2.3s outlier rep dominating a 5-sample median), not a structural property of `b3`'s body. No compiler action was ever warranted; none is now. Full evidence at [`findings/postmortem-002-cdp-perf-0-phase2.md`](findings/postmortem-002-cdp-perf-0-phase2.md).

## Language-team

### F-003. `--cdp` overhead ≈ 27ms + 44ms × candidate_count (R²=0.9995) — decision input for CDP default-on, supersedes F-001

**Priority:** High (decision input, not a defect)
**Status:** Descriptive — routed to whoever owns the `docs/compiler-team-roadmap.md` "CDP default-on" default-flip decision.

At 15+2 reps on `cdp-0`'s 6-fixture primary corpus, `--cdp --trust-report`'s wall-clock overhead over bare `verify` fits `overhead_ms ≈ 27.32 + 43.47 × candidate_count` almost exactly (R²=0.9995, n=6; max residual 8.8ms). This is a materially tighter number than the original Phase-1 finding (1.4×–2.9× ratios, R²=0.33) — same direction, much higher confidence. Concretely: `erc20` (15 candidates) costs +676ms over its ~430ms bare-verify baseline; `b1` (6 candidates) costs +284ms over ~400ms. Whether this cost is acceptable for a *default* (vs. staying opt-in via `--strict-verify`, the current v0.14.4 design) remains the roadmap-owner's call. Full data at [`findings/postmortem-002-cdp-perf-0-phase2.md` §F-003](findings/postmortem-002-cdp-perf-0-phase2.md).

## Experiment-lead

### Resolved: `overhead_ms ~ a + b * candidate_count` fits cleanly once replication is adequate

Phase 1's weak fit (R²=0.3347, 5+1 reps) was itself a symptom of insufficient replication, not evidence against the linear model. Phase 2 (15+2 reps, same primary corpus) resolved it to R²=0.9995. **Methodology takeaway for future CDP wall-clock work on this hardware: 5+1 reps is inadequate for fixtures in the 400ms-1.5s range; 15+2 is the floor.** The secondary-corpus extension (91 fixtures, 5+1 reps) reproduced the same noisiness pattern (R²=0.26, several physically-impossible negative-overhead readings) — consistent with the methodology takeaway, not a separate finding about the secondary corpus's cost structure. A 15+2-rep secondary-corpus pass (~3,100 invocations) would test generalization properly; not run in this pass (the primary-corpus fit already answers the decision-relevant question). See [`findings/postmortem-002-cdp-perf-0-phase2.md`](findings/postmortem-002-cdp-perf-0-phase2.md) Null results section.

## Documentation-lead

*(No findings routed to doc-lead. F-003's decision-input framing may eventually update the "CDP default-on" roadmap row's Next Action once language-team/the user adjudicates the default-flip question — that's a future hand-off, not this run's. A minor `cdp-0` manifest-field naming nit — `verify_clean_filter` describes post-hoc aggregation behavior, not an actual discovery-time filter — is noted in `postmortem-002` but not routed as a formal finding; too minor to warrant a hand-off on its own.)*
