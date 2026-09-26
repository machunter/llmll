# totp_rfc6238: RFC provenance and weakness governance over opaque crypto

TOTP (RFC 6238, with RFC 4226 truncation and RFC 2104 HMAC) specified as six
contracted functions, each clause carrying a `:source` citation to the RFC section it
encodes. HMAC-SHA1 is an opaque builtin, and `hmac-sha1-wrap` records its
underspecification with `weakness-ok` and a stated reason, so spec coverage still
reaches 100%.

**The bodies are `asserted` placeholders, by design.** Nothing here is solver-proven:
the crypto is opaque and truncation and composition are nonlinear. The bodies satisfy
the types and the delegation chain, not the RFC algorithm (`dynamic-truncate` ignores
its HMAC input; `generate-totp` does not feed its time step to the HMAC). What the
example demonstrates is the contract, `:source`, coverage and weakness-governance
layer, not a runnable TOTP. Details: [`WALKTHROUGH.md`](WALKTHROUGH.md).

| File | What it is |
|---|---|
| `totp.ast.json` | Skeleton with holes |
| `totp_filled.ast.json` | Filled version, with 4 check blocks from RFC 6238 §A.1 |
| `totp_filled.ast.json.verified.json` | Tracked sidecar; `verify` rewrites it |
| [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) | Per-function matrix: pre, post, body, checks, source |
| [`EXPECTED_RESULTS.json`](EXPECTED_RESULTS.json) | Frozen coverage, trust counts, suppressions |
| [`WALKTHROUGH.md`](WALKTHROUGH.md) | Functions, design decisions, the benchmark gate |

## Commands (outputs reproduced against llmll 0.26.5)

Run from this directory, on a copy (`verify` rewrites the tracked sidecar).

```bash
llmll check ./totp.ast.json
```
```
✅ ./totp.ast.json — OK (7 statements)
```

**Nothing proved, and `verify` says so.**
```bash
llmll verify ./totp_filled.ast.json
```
```
⚠️  ./totp_filled.ast.json — SAFE (liquid-fixpoint), partial: 0 of 5 contracted functions proved; 5 assumed, not proved: compute-time-step, dynamic-truncate, hmac-sha1-wrap, generate-totp, pad-otp
   (--strict-verified-core fails on assumed functions)
```
Exit 0. Before that line, `W-BODY-FALLBACK` warnings name what took each body out of
the fragment (`nonlinear:/`, `app:hmac-sha1`, `let`). `--trust-report` summarizes it
as `verified: 0`, `asserted: 5`, `no contract: 1` (`validate-totp`, which has a pre
but no post).

**Spec coverage: 5 contracted plus 1 intentional underspecification.**
```bash
llmll verify ./totp_filled.ast.json --spec-coverage
```
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

`make benchmark-totp` (`scripts/benchmark-totp.sh`) checks these results against
`EXPECTED_RESULTS.json`. It is a local target; CI does not run it.
