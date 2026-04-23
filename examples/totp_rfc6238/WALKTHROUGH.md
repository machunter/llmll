# TOTP RFC 6238 Benchmark — Walkthrough

> **Version:** v0.6.1  
> **RFC:** [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238) — TOTP: Time-Based One-Time Password Algorithm  
> **Status:** Frozen benchmark with CI gate

## Overview

This benchmark implements the core TOTP algorithm from RFC 6238, demonstrating LLMLL's capability to:

1. **Specify cryptographic algorithms** with formal contracts and RFC `:source` provenance
2. **Handle opaque primitives** (HMAC-SHA1) with `weakness-ok` suppression governance
3. **Achieve 100% spec coverage** through a combination of contracted and intentionally underspecified functions
4. **Freeze benchmark results** for CI regression testing

## Functions

| Function | Pre | Post | RFC Source | Notes |
|----------|-----|------|-----------|-------|
| `compute-time-step` | `x > 0 ∧ t ≥ t0` | `result ≥ 0` | §4.2 | Floor division: `(t - t0) / x` |
| `dynamic-truncate` | `0 < digits ≤ 10` | `0 ≤ result < 10^10` | §5.3 (RFC 4226) | Modular truncation of HMAC output |
| `hmac-sha1-wrap` | *(weakness-ok)* | *(weakness-ok)* | RFC 2104 | Delegates to `hmac-sha1` builtin |
| `generate-totp` | `time-step > 0 ∧ 0 < digits ≤ 10` | `result ≥ 0` | §4 | Composes time-step → HMAC → truncate |
| `validate-totp` | `expected ≥ 0 ∧ actual ≥ 0` | — | §5.2 | Pure equality comparison |
| `pad-otp` | — | `|result| = d` | §5.4 (RFC 4226) | Zero-pad OTP to `d` digits |

## Spec Coverage

```
Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     5 / 6   (83%)
    Proven:                     0
    Tested:                     0
    Asserted:                   5
  Intentional Underspecification:
    ⊘ hmac-sha1-wrap — "Cryptographic hash correctness is outside QF-LIA; asserted per RFC 2104"
────────────────────────────────────────────
  Effective coverage: 100% (6/6)
```

## Check Blocks (Test Vectors)

The filled implementation includes 4 check blocks from RFC 6238 §A.1:

1. **Time step T=59, X=30 → step 1** — verifies the floor division formula
2. **Time step T=1111111109, X=30 → step 37037036** — large timestamp test vector
3. **validate-totp reflexive** — `∀n. validate-totp(n, n) = true`
4. **pad-otp 42 6 → "000042"** — zero-padding to 6 digits

## Design Decisions

### Crypto as Opaque Builtins

Per SC-2 and IN-2, `hmac-sha1` and `sha1` are typed as `TBytes 20 → TBytes 20 → TBytes 20` and `TBytes 20 → TBytes 20` respectively. This is deliberate:

- RFC 6238 SHA-1 test vectors use 20-byte keys and outputs
- The concrete length enables the type checker to verify structural correctness
- Hash correctness is **asserted** (classified as such in the trust report) — it is not provable in QF-LIA

### Weakness-Ok Governance

`hmac-sha1-wrap` uses `weakness-ok` to suppress the spec weakness alert. This is the intended governance pattern: the function's cryptographic correctness is outside the decidable fragment, but the **structural** correctness (types, argument count, delegation chain) is fully verified.

## CI Gate

Run the benchmark gate:

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
| `totp.ast.json` | Skeleton with holes (BM2-1) |
| `totp_filled.ast.json` | Complete implementation (BM2-2) |
| `EXPECTED_RESULTS.json` | Frozen expected results (BM2-3) |
| `WALKTHROUGH.md` | This document (BM2-5) |
| `scripts/benchmark-totp.sh` | CI gate script (BM2-4) |
