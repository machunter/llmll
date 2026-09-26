# TOTP RFC 6238 Benchmark — Walkthrough

> **RFC:** [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238) — TOTP: Time-Based One-Time Password Algorithm  
> **Status:** Frozen benchmark with a local regression gate (`make benchmark-totp`; not run in CI)

## Overview

This benchmark **specifies** the TOTP algorithm from RFC 6238 with placeholder, `asserted`-tier bodies (the crypto core is opaque and the arithmetic is nonlinear, so nothing here is solver-proven). It demonstrates LLMLL's capability to:

1. **Specify cryptographic algorithms** with formal contracts and RFC `:source` provenance
2. **Handle opaque primitives** (HMAC-SHA1) with `weakness-ok` suppression governance
3. **Achieve 100% spec coverage** through a combination of contracted and intentionally underspecified functions
4. **Freeze benchmark results** for local regression testing

## Functions

| Function | Pre | Post | RFC Source | Notes |
|----------|-----|------|-----------|-------|
| `compute-time-step` | `x > 0 ∧ t ≥ t0` | `result ≥ 0` | §4.2 | Floor division: `(t - t0) / x` |
| `dynamic-truncate` | `0 < digits ≤ 10` | `0 ≤ result < 10^10` | §5.3 (RFC 4226) | Contract: modular truncation. Body is an asserted placeholder (ignores `hmac-result`) |
| `hmac-sha1-wrap` | *(weakness-ok)* | *(weakness-ok)* | RFC 2104 | Delegates to `hmac-sha1` builtin |
| `generate-totp` | `time-step > 0 ∧ 0 < digits ≤ 10` | `result ≥ 0` | §4 | Contract: compose time-step → HMAC → truncate. Body is an asserted placeholder (time step not fed to the HMAC) |
| `validate-totp` | `expected ≥ 0 ∧ actual ≥ 0` | — | §5.2 | Pure equality comparison |
| `pad-otp` | — | `|result| = d` | §5.4 (RFC 4226) | Zero-pad OTP to `d` digits |

> **Bodies are asserted placeholders, by design.** No function here is solver-proven: the crypto core is opaque (HMAC-SHA1) and truncation/compose are nonlinear, so every body lands at the `asserted` tier. The bodies satisfy the *types* and the delegation chain, not the RFC algorithm: `dynamic-truncate` returns `mod(abs(digits), …)` without consuming `hmac-result`, and `generate-totp` does not thread its time step into the HMAC. The benchmark's value is the contract + `:source` + spec-coverage + weakness-governance layer over opaque crypto, not a runnable TOTP.

## Spec Coverage

```
Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     5 / 6   (83%)
    Verified:                   0
    Tested:                     0
    Asserted:                   5
  Intentional Underspecification:
    ⊘ hmac-sha1-wrap — "Cryptographic hash correctness is outside QF-LIA; asserted per RFC 2104"
────────────────────────────────────────────
  Effective coverage: 100% (6/6)
```

> **Note:** the trust report (`llmll verify totp_filled.ast.json --trust-report`) counts `verified: 0, asserted: 5, no contract: 1`. `hmac-sha1-wrap` has no written `pre`/`post`, but its RFC 2104 `:source` post counts as an asserted post, so it lands in `asserted`. The one `no contract` function is `validate-totp`, which has a `pre` but no `post` (no effective post-level). See `EXPECTED_RESULTS.json`'s `expected_trust_report`.

## Check Blocks (Test Vectors)

The filled implementation includes 4 check blocks from RFC 6238 §A.1:

1. **Time step T=59, X=30 → step 1** — verifies the floor division formula
2. **Time step T=1111111109, X=30 → step 37037036** — large timestamp test vector
3. **validate-totp reflexive** — `∀n. validate-totp(n, n) = true` (skipped at runtime: QuickCheck discards all 1000 samples, so it reports as skipped, not passed)
4. **pad-otp 42 6 → "000042"** — zero-padding to 6 digits

## Design Decisions

### Crypto as Opaque Builtins

`hmac-sha1` and `sha1` are typed as `TBytes 20 → TBytes 20 → TBytes 20` and `TBytes 20 → TBytes 20` respectively. This is deliberate:

- RFC 6238 SHA-1 test vectors use 20-byte keys and outputs
- The concrete length enables the type checker to verify structural correctness
- Hash correctness is **asserted** (classified as such in the trust report) — it is not provable in QF-LIA

### Weakness-Ok Governance

`hmac-sha1-wrap` uses `weakness-ok` to suppress the spec weakness alert. This is the intended governance pattern: the function's cryptographic correctness is outside the decidable fragment, but the **structural** correctness (types, argument count, delegation chain) is fully verified.

## Regression Gate

The gate is a local make target; no workflow under `.github/` runs it. Run it directly:

```bash
make benchmark-totp
# or directly:
./scripts/benchmark-totp.sh
```

The gate checks 14 assertions against `EXPECTED_RESULTS.json`:
- Skeleton parses correctly
- Spec coverage matches frozen values
- Trust report structure is correct
- Source provenance annotations are present
- Verification-scope matrix has all 6 entries
- Check block count matches

## Files

| File | Purpose |
|------|---------|
| `totp.ast.json` | Skeleton with holes |
| `totp_filled.ast.json` | Complete implementation |
| `EXPECTED_RESULTS.json` | Frozen expected results |
| `WALKTHROUGH.md` | This document |
| `scripts/benchmark-totp.sh` | Local gate script (`make benchmark-totp`) |
