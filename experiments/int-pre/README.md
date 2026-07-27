# INT-PRE — `int → Integer` codegen wall-clock measurement

> **Status:** Active. Pending first run (awaits host-machine measurement window).
> **Last updated:** 2026-05-23
> **Owner:** experiment-lead
> **Gate consumer:** `docs/compiler-team-roadmap.md` row INT-PRE at `:158, 314`; INT-2 row at `:157, 313`; INT-3 row at `:321`

## 1. Purpose

INT-PRE measures wall-clock runtime cost of switching LLMLL's `int` codegen target from Haskell `Int` (machine-bounded) to `Integer` (GMP-backed mathematical integer) across five frozen benchmarks (B1, B3, B5, TOTP, ERC-20). The output is a single `adjudication` field that tells the language-team / compiler-engineer / user one of three things:

- **`int-2-clear`** — TOTP wall-clock regression < 5×, INT-2 ships in v0.11 as planned (`docs/compiler-team-roadmap.md:313`)
- **`int-3-escalate-total`** — TOTP wall-clock regression ≥ 5×, escalate INT-3 (`MachineInt` QF-BV alias) from research-track P3 to v0.11 freeze-exception candidate; promote `docs/design/int-3-machine-int-sketch.md` from Rev 0 contingency to Rev 1 settled proposal
- **`int-3-warning-user-only`** — TOTP total ratio clears 5× but user-LLMLL-arithmetic-only ratio ≥ 10× under cost-center decomposition; INT-2 proceeds with a finding routed to language-team naming the sealed-crypto-dominance contingency

The Rev 2 plan and the gate decomposition are documented at the experiment-lead conversation level; this README is the harness's reproducibility contract.

## 2. What this harness is NOT

- **Not an agent-effectiveness harness.** That's `experiments/minimal-agent/`. INT-PRE invokes zero models, makes zero API calls, has no concept of attempts or grades.
- **Not a repair-loop harness.** That's `experiments/repair-loop/`. INT-PRE does single-shot compiler invocations.
- **Not a cross-language harness.** That's the design-only `docs/design/language-comparison-experiments.md`. INT-PRE compares two LLMLL compiler variants against each other.
- **Not a CI gate.** The benchmark `make benchmark-totp` / `make benchmark-erc20` scripts are unrelated; they are correctness gates, INT-PRE is a wall-clock gate. INT-PRE deliberately does not depend on `make benchmark-totp` because of finding F-V1 (PROV-3 pre-existing regression on v0.10.7 trust-report shape, surfaced by Variant B acceptance verification).

## 3. Variant model

Two compiler variants, both pinned to git SHAs in `manifest.json`:

| label | SHA | branch/tag | description |
|---|---|---|---|
| `variant-a-baseline` | `009a6f0` | `release/v0.10.7` | Pre-INT-2 baseline. INT-1 not included (deferred to v0.10.8 per CHANGELOG v0.10.7 "What this does NOT close"); orthogonal to codegen-comparison dimension. |
| `variant-b-prototype` | `03d5722` | `int-pre/variant-b` | Realizes `docs/archive/shipped-design-specs/int-2-boundary-shims.md` §3. Polymorphic `Integral i =>` Class A boundary with `SPECIALIZE` pragmas; Class B `Integer` signatures; one-line `toHsType TInt = "Integer"` + `mapLlmllPrimType "int" = "Integer"`. |

Variant B is a throwaway measurement artifact. It graduates to the INT-2 PR for v0.11 only if INT-PRE returns `int-2-clear`.

The harness materializes each variant via `git worktree add` under `.worktrees/` and runs `stack build llmll` per variant. Worktrees are reused across reps within a single harness invocation and across invocations if the SHA is unchanged.

## 4. Gate criteria

### Primary gate (load-bearing)

**TOTP total wall-clock regression factor** = `median(variant-b totp.test) / median(variant-a totp.test)` over 10 measured reps (+ 2 warmup reps discarded). Threshold: **5.0**. Above this triggers INT-3 escalation.

The 5× threshold is the language-team's pre-stated criterion (`docs/compiler-team-roadmap.md:158, 314`). The TOTP-as-gate choice is defended by elimination: per `examples/totp_rfc6238/VERIFICATION_SCOPE.md`, TOTP has the highest user-LLMLL arithmetic density in the frozen suite (five contracted functions doing time-step computation, modular reduction, padding arithmetic). ERC-20 surface is contract-clause invariants (compile-time, no runtime arithmetic to measure). B1/B3/B5 are spec-shape proofs with no executable check blocks. TOTP is the gate by elimination.

### Secondary gate (descriptive, not blocking)

**TOTP user-LLMLL-arithmetic-only ratio** = `user_total_ms(variant-b) / user_total_ms(variant-a)`, where `user_total_ms` is derived by `ghc -prof +RTS -p -RTS` cost-center attribution. Threshold: **10.0**.

The user/builtin split is a contingency for the sealed-crypto-dominance hypothesis: HMAC-SHA1 in TOTP delegates to a builtin (per the verification scope `hmac-sha1-wrap` is `weakness-ok` and routes to the sealed `hmac_sha1` Haskell helper), which is `Word8`/`ByteString`-shaped and not affected by the `Int → Integer` switch. If the sealed-crypto dominates wall-clock (typical: ~80% per spot-check), the total ratio understates the user-LLMLL arithmetic regression by a factor of ~5×. The secondary gate catches this case: if total < 5× but user-only ≥ 10×, INT-2 proceeds with a finding to language-team rather than escalating INT-3 unilaterally.

### Cost-center classification

Cost centers matched as substring against the `name` column of the `.prof` file. Builtin set (pinned in `manifest.json` and reproduced here):

```
hmac_sha1, sha1_hash, hmac_sha1_inner, random_int
```

Anything not matching is counted as user-LLMLL arithmetic. Residual cost (MAIN, GC, runtime) absorbs into user totals; this biases the user_only ratio upward (conservative for the escalation question — false negatives on INT-3 warning are the failure mode to avoid).

If GHC's actual cost-center names diverge from this set on first profiled run, the harness surfaces the diff as a postmortem finding rather than silently re-attributing. The classification is reproducibility-pinned.

## 5. Reproducibility contract

The harness refuses to run unless CPU governor is pinned to `performance` mode (or equivalent: Mac `lowpowermode 0`). Override via `--no-governor-check` flag at the cost of noisier IQR.

`raw.json` captures the full host metadata:

- `uname -a` output
- `ghc --version`, `stack --version`
- Python interpreter version
- Both compiler SHAs (verified against worktree HEAD)
- Manifest SHA (catalog ref)
- Harness git HEAD

Cross-run comparisons are valid only when `host_meta`, both `compiler_ref` SHAs, and the harness SHA match. The harness does not enforce this — analysts comparing run directories cross-check the metadata.

## 6. Output schema

Per invocation, the harness writes:

```
experiments/int-pre/runs/<YYYYMMDDTHHMMSSZ>/
  raw.json    — full per-rep table, host state, manifest snapshot
  report.json — aggregated medians, regression factors, control assertions, adjudication
  report.md   — human-readable summary, gate criterion restated
```

`raw.json` shape (truncated):

```json
{
  "harness_version": "1.0.0",
  "timestamp": "20260523T...",
  "manifest": {...},
  "host_state": {"governor_pinned": true, ...},
  "host_meta": {"uname -a": "...", "ghc --version": "...", ...},
  "cells": {
    "variant-a-baseline": [
      {"benchmark_id": "totp", "phase": "test",
       "median_ms": 12.4, "iqr_ms": 0.3, "n": 10,
       "reps": [{"rep_idx": 0, "wall_ms": 12.5, "exit_code": 0, "stdout_sha256": "..."}, ...]},
      ...
    ],
    "variant-b-prototype": [...]
  },
  "profiled": {
    "variant-a-baseline": [{"benchmark_id": "totp", "total_ms": 14.1,
                             "user_total_ms": 2.8, "builtin_total_ms": 11.3,
                             "user_pct": 19.9, "builtin_pct": 80.1, ...}, ...],
    "variant-b-prototype": [...]
  },
  "halted": null
}
```

`report.json` adds derived fields:

```json
{
  "benchmarks": {
    "totp": {
      "test": {
        "variants": {"variant-a-baseline": {...}, "variant-b-prototype": {...}},
        "regression_factor": 2.3
      },
      ...
    },
    ...
  },
  "profiled": {"variant-a-baseline": {"user_total_ms_median": 2.8, ...}, ...},
  "totp_user_only_ratio": 4.7,
  "controls": [{"name": "verify_spec_coverage_byte_identity", "holds": true, "evidence": []}, ...],
  "adjudication": "int-2-clear"
}
```

## 7. Findings routing

Per `experiments/<harness>/findings/` convention (matched from `minimal-agent/findings/`):

| File | Consumer | When written |
|---|---|---|
| `findings/postmortem-NNN.md` | user (skims) | After each adjudicated run; carries the full integrated narrative |
| `findings.md` `## Language-team` | language-team | When a pattern implies a spec move (e.g., catalog-correction finding, contingency promotion) |
| `findings.md` `## Compiler-engineer` | compiler-engineer | When a pattern implies a compiler bug (e.g., the harness uncovers a real codegen regression in Variant B not anticipated by the catalog) |
| `findings.md` `## Documentation-lead` | doc-lead | Only via the loop after engineer / language-team have actioned; doc-lead is not invoked directly by experiment-lead |

The harness does not write findings automatically. Findings are surfaced for user review post-run; the user authorizes any disk write.

## 8. How to run

```
# From repo root
cd experiments/int-pre
python3 scripts/int_pre_bench.py manifest.json
```

Flags:
- `--no-governor-check` — skip CPU governor pinning enforcement
- `--skip-profiled` — skip the F2 user-only decomposition (gate adjudicates on total ratio only)

Estimated cost:
- ~5 min — worktree setup + Variant A `stack build` (cached after first run)
- ~5 min — Variant B `stack build` (cached after first run)
- ~30 min — unprofiled rep loop (5 benchmarks × 2 variants × ~3 phases × 12 reps)
- ~10 min — profiled rebuilds (`--profile` per variant) + TOTP profiled reps
- **Total: ~50 min on a quiet machine, no API spend**

## 9. References

- Run plan (Rev 2): experiment-lead conversation, 2026-05-23 turn
- INT-2 boundary-shim catalog: `docs/archive/shipped-design-specs/int-2-boundary-shims.md` (commit `32a796e`)
- INT-3 contingency sketch: `docs/design/int-3-machine-int-sketch.md` (commit `32a796e`)
- Variant B implementation: `int-pre/variant-b` branch, commit `03d5722`
- Variant A baseline: `release/v0.10.7` HEAD, commit `009a6f0`
- Gate row: `docs/compiler-team-roadmap.md:158, 314`
- Related siblings: `experiments/minimal-agent/`, `experiments/repair-loop/`
