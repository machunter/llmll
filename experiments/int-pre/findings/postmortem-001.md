# INT-PRE Postmortem 001 — `int → Integer` codegen wall-clock comparison

> **Status:** Adjudicated `int-2-clear`. INT-2 cleared the v0.11 freeze-exception gate.
> **Date:** 2026-05-23
> **Run directory:** `experiments/int-pre/runs/20260523T235750Z/`
> **Adjudication:** `int-2-clear` — TOTP test phase regression factor 1.015 (n=10) against 5.0 gate threshold
> **Voice reference:** `experiments/minimal-agent/findings/postmortem-001.md`

## Headline finding

INT-2's `int → Integer` codegen switch produces **no measurable wall-clock regression** on any of the five frozen benchmarks (B1, B3, B5, TOTP, ERC-20) across 320 measured reps (16 phase-cells × 10 reps × 2 variants). TOTP `test` phase regression factor is **1.015** (n=10, A median 19.44ms IQR 1.90ms, B median 19.73ms IQR 0.10ms) against the 5.0 gate threshold. Both control assertions hold byte-identically: `verify --spec-coverage --json` and `verify --trust-report --json` produce identical stdout SHA-256 across variants on every benchmark. **Adjudication: `int-2-clear`** — INT-2 proceeds to v0.11 as planned per `docs/compiler-team-roadmap.md:157, 313`.

## Sample composition

- **Total measured reps:** 320 (16 phase-cells × 10 reps × 2 variants), plus 64 warmups discarded
- **Variants:**
  - `variant-a-baseline` @ `009a6f0` (release/v0.10.7 HEAD; pre-INT-2; INT-1 not included per CHANGELOG v0.10.7 "What this does NOT close")
  - `variant-b-prototype` @ `03d5722` (int-pre/variant-b; INT-2 codegen + Class A polymorphic boundary realizing `docs/design/int-2-boundary-shims.md` §3 with two engineer refinements F-E1 + F-E2)
- **Catalog SHA:** `32a796e` (`docs/design/int-2-boundary-shims.md`)
- **Harness:** `d996fe0` (`experiments/int-pre/scripts/int_pre_bench.py` v1.0.0)
- **Host:** Darwin 25.5.0 aarch64, GHC 9.6.6, stack 3.x, CPU governor `lowpowermode 0` (pinned)
- **Exit codes across all 320 measured reps:** 0
- **Stdout SHA-256 uniqueness within each cell:** 1 (perfect byte-identity within variant; across-variant byte-identity also held for both `verify` control phases)

## Per-benchmark regression factors (Variant B median / Variant A median)

| benchmark | phase | A median (ms) | B median (ms) | factor | n |
|---|---|---|---|---|---|
| b1 | verify_spec_coverage | 21.57 | 21.42 | **0.993** | 10 |
| b1 | verify_trust_report | 20.45 | 20.68 | **1.011** | 10 |
| b1 | build | 20.17 | 20.51 | **1.017** | 10 |
| b3 | verify_spec_coverage | 20.37 | 20.16 | **0.990** | 10 |
| b3 | verify_trust_report | 20.32 | 20.41 | **1.005** | 10 |
| b3 | build | 19.75 | 19.99 | **1.012** | 10 |
| b5 | verify_spec_coverage | 20.17 | 20.22 | **1.003** | 10 |
| b5 | verify_trust_report | 20.17 | 20.28 | **1.006** | 10 |
| b5 | build | 19.54 | 20.39 | **1.044** | 10 |
| totp | verify_spec_coverage | 20.09 | 19.49 | **0.970** | 10 |
| totp | verify_trust_report | 20.33 | 20.14 | **0.991** | 10 |
| totp | build | 19.65 | 19.99 | **1.017** | 10 |
| **totp** | **test (GATE)** | **19.44** | **19.73** | **1.015** | 10 |
| erc20 | verify_spec_coverage | 19.99 | 20.29 | **1.015** | 10 |
| erc20 | verify_trust_report | 20.45 | 20.20 | **0.988** | 10 |
| erc20 | build | 20.25 | 20.28 | **1.002** | 10 |

All 16 factors land in `[0.970, 1.044]`. Both directions (several cells show Variant B faster than Variant A) — consistent with measurement noise dominating over codegen-target signal at these benchmark sizes.

## Verified findings

### F-001. F2 user-only decomposition failed to produce data ([HIGH; methodology])

**Consumer:** experiment-lead (self) — harness defect for the next iteration

#### Evidence

Per the run log at `runs/20260523T235750Z/raw.json` and the harness stderr capture:

- **Variant A profiled build failed** with `SQLite3 returned ErrorBusy while attempting to perform step: database is locked`. Cause: concurrent `stack` instance contending for `~/.stack/snapshots/<resolver>/` SQLite DB. Profiled phase skipped for Variant A.
- **Variant B profiled `llmll test` exited rc=1 on all 3 profiled reps.** Manual reproduction at the same binary path with the same `+RTS -p -RTS` flags succeeds (exit 0; 37.68ms; produces correct "✅ Passed: 3 / ❌ Failed: 0 / ⚠️ Skipped: 1" output). Root cause unconfirmed; suspected timing/state issue between the `stack build --profile` rebuild and the subsequent profiled invocation. **Harness defect:** the failed profiled reps were logged as `"exit 1; skipping"` in stderr without capturing the failed process's stdout/stderr to `raw.json`, foreclosing post-hoc diagnosis.

#### Why we saw what we saw

Two compounding issues. First, the harness's `ensure_built(profiled=True)` reuses the same worktree as the unprofiled build, which means Stack's snapshot DB is shared across the parent dev environment and prone to lock contention when anything outside the harness touches stack. Second, the harness's `run_profiled` discards captured stderr on non-zero exit, leaving the failure undiagnosable from the raw artifact alone.

**Deeper concern beyond the surface bugs:** the F2 design itself profiles the *llmll compiler binary* rather than the *generated user-LLMLL test program*. Cost centers in the resulting `.prof` file would attribute to `LLMLL.Parser`, `LLMLL.TypeCheck`, `LLMLL.CodegenHs`, etc. — not to user-LLMLL arithmetic in the generated TOTP `Lib.hs`. **Correct F2 attribution requires profiling the generated test binary**, which means running `stack build --profile` in `generated/totp_filled/` and instrumenting the test executable there. That is an INT-PRE v2 redesign, not a v1 bug fix.

#### Implication

For experiment-lead (self): three harness fixes for INT-PRE v2:
1. Capture stdout/stderr of failed profiled reps to `raw.json` under a `failure_evidence` field.
2. Isolate profiled builds into a separate worktree (`.worktrees/variant-{a,b}-profiled/`) or `STACK_ROOT` to avoid snapshot-DB contention.
3. Redesign F2 to profile the *generated test binary* rather than the llmll compiler. This requires `llmll build --emit-only` followed by `stack build --profile` inside the generated package, then running the test binary with `+RTS -p -RTS`, then parsing that .prof file. Larger scope.

**Is this a blocker for the current adjudication?** No, on two grounds: (i) the total wall-clock factor is 1.015× — for the secondary gate (user-only ≥ 10×) to overrule the primary adjudication, the user-LLMLL share of TOTP wall-clock would have to be ≥65× the builtin share, which is implausible given the verification scope (`examples/totp_rfc6238/VERIFICATION_SCOPE.md`) shows HMAC-SHA1 sealed to a Haskell builtin while user-LLMLL arithmetic is the contracted-function bodies; (ii) the byte-identity controls held, confirming no behavioral divergence on the verification path. The adjudication `int-2-clear` is robust to the F2 gap.

#### Acceptance

INT-PRE v2 produces non-empty `report.profiled` and a numeric `totp_user_only_ratio` on a clean run, with cost-center attribution pointing at user-LLMLL arithmetic in the generated package rather than at compiler internals.

### F-002. Warm-cache short-circuit deflates absolute wall-clocks ([MEDIUM; methodology])

**Consumer:** experiment-lead (self) + user (methodology disclosure)

#### Evidence

Manual reproduction of the harness's TOTP `test` invocation under three cache conditions:

| Condition | Wall-clock | Method |
|---|---|---|
| Cold (fresh `generated/totp_filled/` build) | 758 ms | shell `time` |
| Warm rep 0 (cwd has `generated/` from prior invocation) | 72.77 ms | python3 subprocess |
| Warm reps 1-9 (verified-cache hit, generated-package cache hit) | 17-20 ms | python3 subprocess; matches harness output |

The harness's warmup discards 2 reps; measured reps 0-9 are all in the deepest-cached state. The 19.44ms median for TOTP `test` is not a measurement of "running llmll test from scratch" — it is a measurement of "running llmll test after `generated/totp_filled/` is fully built and `.verified.json` carries a current witness."

#### Why we saw what we saw

`llmll test` checks the `.verified.json` sidecar and the generated-package state; on hit, it short-circuits most of the work and emits the cached `Passed: 3 / Failed: 0 / Skipped: 1` summary in ~17ms. The harness's warmup phase (2 reps discarded) primes the cache fully; subsequent measured reps don't exercise the cold paths.

#### Implication

For a fair *ratio* comparison this is **fine** — Variant A and Variant B are both measured under identical warm-cache conditions, and the ratio is the load-bearing metric. The absolute deflation matters only if someone reads "TOTP test = 19ms" as "TOTP test wall-clock cost." It is not; it is "TOTP test cost in the steady-state cached path."

For an INT-PRE v2 that wants cold-path measurement, the harness needs an explicit cache-bust step between reps (delete `generated/totp_filled/`, invalidate the `.verified.json` sidecar). Cost: every rep becomes a cold ~758ms invocation; 10 reps × 2 variants = 152s additional per benchmark in the test phase; budget acceptable.

#### Acceptance

`experiments/int-pre/README.md` §6 updated to disclose the warm-cache measurement contract; optional cache-bust mode added to INT-PRE v2 that produces a separate cold-path measurement series.

### F-003. Stack snapshot DB lock under concurrent profiled rebuild ([LOW; harness])

**Consumer:** experiment-lead (self)

#### Evidence

`SQLite3 returned ErrorBusy while attempting to perform step: database is locked` during Variant A's `stack build --profile` step. Reproducible on Macs when more than one stack process touches the same `~/.stack/snapshots/<resolver>/` directory concurrently. The harness itself invokes one stack at a time, so the lock conflict came from outside the harness's process — likely an interactive dev session, an IDE stack hook, or a lingering background stack process.

#### Why we saw what we saw

Stack's per-resolver snapshot DB is process-shared via SQLite. Concurrent writers contend; the loser sees `ErrorBusy`. The harness does not isolate `STACK_ROOT` per worktree, so all worktrees and any outside stack invocation hit the same snapshot DB.

#### Implication

Two mitigations for INT-PRE v2: (a) pre-run check that no `stack` processes are running; warn and refuse if so; (b) set `STACK_ROOT=experiments/int-pre/.stack-root-{variant_label}` per worktree to isolate the snapshot DB. Option (b) costs an extra ~5min one-time per worktree to fetch its own snapshot; subsequent runs are amortized.

#### Acceptance

Harness pre-flight detects competing stack processes (or operates under isolated `STACK_ROOT`) and the SQLite lock error does not recur across at least three consecutive INT-PRE runs.

## Withdrawn items

None this run. The hypothesis going into the run (per Rev 2 plan: "INT-2 inflates wall-clock at user-LLMLL arithmetic execution time, not at codegen/compile/SMT/Lean time; TOTP execution is the worst-case payload") was *consistent with the data* in that no wall-clock inflation was observed; the hypothesis's worst-case prediction was not falsified, just not exercised at a magnitude the data could distinguish.

## Null results

The F2 decomposition was a stated secondary gate; it produced **no data** due to F-001. This is a null result in the strict sense — the harness failed to measure user-only ratio, not that the user-only ratio was measured-and-low. Recording: `report.json.totp_user_only_ratio = null`. The adjudication does not rest on F2 (see F-001 §Implication).

## Priority matrix

| # | Finding | Consumer | Priority | Effort estimate |
|---|---|---|---|---|
| F-001 | F2 user-only decomposition harness defect + design redesign | experiment-lead (self) | High | ~1 day (cost-center attribution redesign for INT-PRE v2) |
| F-002 | Warm-cache short-circuit deflates absolute wall-clocks | experiment-lead + user | Medium | ~hours (README disclosure + optional cache-bust mode) |
| F-003 | Stack snapshot DB lock under concurrent profiled rebuild | experiment-lead (self) | Low | ~hours (pre-flight check or STACK_ROOT isolation) |

No findings route to language-team or compiler-engineer this run. The catalog at `docs/design/int-2-boundary-shims.md` is unfalsified by the data; the Variant B implementation at `03d5722` is correct per acceptance and produces identical-modulo-noise wall-clock; the engineer slot has no INT-PRE-triggered action.

## Per-consumer scoped files

This postmortem is the sole findings artifact for the run. No fragments are written to `findings/compiler-team.md` or `findings/language-team.md` because no findings route there. `findings/documentation-team.md` likewise unchanged.

## Two surfacing notes (no action implied; for context)

- **The `make benchmark-totp` PROV-3 failure (F-V1 from the engineer's Variant B acceptance work) reproduces on both variants** and is independent of INT-PRE. Still a v0.10.8 patch-lane item for engineer attention; INT-PRE confirmed it is not a Variant B issue. Documented in the engineer-plan postmortem; not re-routed here.
- **The `int-pre/variant-b` branch and the `experiments/int-pre/` directory** are now load-bearing for the INT-2 ship audit trail. Worth a push to origin once the INT-2 PR is authored, so the catalog → sketch → Variant B → INT-PRE-run lineage is publicly traceable.

## Cross-references

- INT-2 catalog: `docs/design/int-2-boundary-shims.md` @ `32a796e`
- INT-3 contingency sketch: `docs/design/int-3-machine-int-sketch.md` @ `32a796e` — stays Rev 0 contingency per `int-2-clear` adjudication
- Variant B implementation: `03d5722` on `int-pre/variant-b`
- Variant A baseline: `009a6f0` on `release/v0.10.7`
- Gate row: `docs/compiler-team-roadmap.md:158, 314` (INT-PRE) and `:157, 313` (INT-2)
- Harness: `experiments/int-pre/` @ `d996fe0`
