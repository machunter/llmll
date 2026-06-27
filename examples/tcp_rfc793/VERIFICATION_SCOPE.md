# TCP RFC 793 State Machine — Verification Scope Matrix

**Claim.** The connection state machine's *state-safety invariant* — `step` cannot
reach `Established` without the handshake (never a direct `Closed → Established` or
`Listen → Established`) — is **solver-proven** (liquid-fixpoint, QF-LIA), not merely
tested or asserted, on an implementation written in **idiomatic enum types**. The
implementation *provably cannot* skip the handshake.

| # | Function | Types | Post | Body | Verdict | Source |
|---|----------|-------|------|------|---------|--------|
| 1 | `step` | real sum types: `(type ConnState (\| Closed) …)`, `(type Event …)` | ✅ state-safety (no CLOSED/LISTEN → ESTABLISHED) | ✅ nested `match` on the enums | **verified** (body-faithful, liquid-fixpoint) | RFC 793 §3.2 |

**Proven: 1 · Asserted: 0.**

Contrast `examples/totp_rfc6238` (Proven: 0, Asserted: 5): TOTP's core is an opaque
`hmac-sha1` builtin outside QF-LIA — RFC *traceability* with every clause `asserted`.
Here the load-bearing invariant is integer/ordering-shaped, so it lands in the
auto-discharge fragment and is `verified`. Nothing cryptographic or opaque is in scope.

## Why it reaches `verified` (fragment-fit)

- States and events are **real nullary-enum sum types**, matched in the body. The
  compiler internally tags the constructors (`Closed=0 … Established=4`) and
  discharges the post in pure **QF-LIA** — the COMP-3b-general feature; **no
  int-encoding workaround in the source**.
- The match lowers to a **nested `if`** on the constructor tags — path-split, well
  under the 4096-path body-VC ceiling.
- The `post` is a state-safety property over constructor values in **QF-LIA**
  (`and`/`or`/`not`, linear `=`), authored from the RFC — not a copy of the body.
- No `mod` / `/` / `*` (nonlinear), no payload-bearing constructors, no
  pairs-in-predicates — all of which fall back.

## What is proven vs. left for later

- **Proven:** the *state-safety* property — no `Closed`/`Listen → Established` skip.
- **Not (yet) proven:** the *full* "every illegal pair is REJECTED" totality. That
  needs a distinct `Rejected` result (a `Result`-style return or a sentinel
  variant) whose constructor-dependent post is beyond the nullary-enum Phase-1
  fragment (the COMP-3b-general Phase-2 / payload work). The earlier int-encoded
  version expressed the full table via a `5 = REJECTED` int sentinel; the idiomatic
  re-type trades that totality for **real types + the proven safety property**.
- **Verify-time, not run-time (yet):** constructor values are discharged by the
  verifier (the COMP-3b-general desugar to internal tags); the runtime /
  property-test path does not evaluate them yet, so `llmll test` *skips*
  constructor-valued vectors. The demo's beat is **typecheck → verify**.

## Files

- `step.llmll` / `step.ast.json` — clean implementation → **verified** (SAFE).
- `step-bad.llmll` — one illegal edge: `Closed + ActiveOpen → Established` (skips the
  SYN_SENT handshake). Type-checks, but `verify --strict-verified-core` → **refuted:
  step** (then-branch, constraint #1), localized to that branch.
- `step-weak.llmll` — the co-evolution start: a weak post that forbids the `Closed`
  jump but *omits* the symmetric `Listen` clause, plus a body that sneaks a
  `Listen + RcvAck → Established` edge. The bug **survives** (`SAFE`).

## Spec / implementation co-evolution

1. Start with `step-weak.llmll` — buggy body + incomplete contract → **SAFE** (the
   bug slips through; a realistic human spec gap).
2. Add the missing `Listen` clause (cite RFC 793 §3.2) → `step.llmll`'s full post.
3. Re-verify the buggy edge → **refuted** — the bug is now caught.

The hardening is **human-driven** (notice the survival, tighten the contract).
Honest caveat: `--cdp` / `--weakness-check` do **not** auto-flag the weak contract
for this function shape (`--cdp` reports `0/0 candidates [candidates-empty-under-limit]`);
automating the "your spec is too weak" signal is future work, not a shipped claim.

## Reproduce

```
llmll verify ./step.llmll --strict-verified-core       # SAFE — verified
llmll verify ./step-bad.llmll --strict-verified-core   # refuted: step
llmll verify ./step-weak.llmll --strict-verified-core  # SAFE — bug survives the weak contract
```
