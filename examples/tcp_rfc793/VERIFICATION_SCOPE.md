# TCP RFC 793 State Machine — Verification Scope Matrix

**Claim.** The connection state machine's *transition-table totality* — `step` maps
**every** `(state, event)` input to the correct outcome: each of the five legal
transitions to its specific `Next(tag)`, and every illegal pair to `Rejected` — is
**solver-proven** (liquid-fixpoint + Z3 datatype theory), not merely tested or
asserted, on an implementation written in **idiomatic enum types with a real
payload-bearing outcome sum**. The implementation *provably cannot* skip the
handshake (it cannot reach `Established` from `Closed`/`Listen`) and *provably*
rejects every non-legal pair.

| # | Function | Types | Post | Body | Verdict | Source |
|---|----------|-------|------|------|---------|--------|
| 1 | `step` | real sum types: `(type ConnState …)`, `(type Event …)`, outcome `(type StepOutcome (\| Next int) (\| Rejected int))` | ✅ transition-table totality (legal → `Next(tag)`, illegal → `Rejected`) | ✅ nested `if` constructing the outcome sum | **verified** (body-faithful, liquid-fixpoint + datatypes) | RFC 793 §3.2 |

**Proven: 1 · Asserted: 0.**

Contrast `examples/totp_rfc6238` (Proven: 0, Asserted: 5): TOTP's core is an opaque
`hmac-sha1` builtin outside the decidable fragment — RFC *traceability* with every
clause `asserted`. Here the load-bearing invariant is integer/ordering- and
constructor-shaped, so it lands in the auto-discharge fragment and is `verified`.
Nothing cryptographic or opaque is in scope.

## Why it reaches `verified` (fragment-fit)

- States and events are **real nullary-enum sum types**; the compiler internally
  tags the constructors (`Closed=0 … Established=4`) — the COMP-3b-general feature.
- The **outcome** is a **real payload-bearing sum**, `StepOutcome`, with two
  payload-carrying variants `Next(int)` / `Rejected(int)`. It is **constructed
  natively** (COMP-4 (a)/(c), v0.13.9): a constructor application reflects into a
  native `FQData` term, the post discharges by **constructor equality**, and a
  wrong-payload body is **refuted by injectivity** (selector mismatch). This is the
  first verification beyond pure QF-LIA — into Z3's **non-recursive datatype
  theory**, decidable by polite theory combination.
- `StepOutcome` is a flat, acyclic two-arm sum — **admissible** under
  `admissibleDatatype`; recursive datatypes are firewalled out and fall back.
- The match lowers to a **nested `if`** on the constructor tags — path-split, well
  under the 4096-path body-VC ceiling.
- The `post` is a totality property over constructor values in QF-LIA + datatypes
  (`and`/`or`/`not`, linear `=`, constructor `=`), authored from the RFC — not a
  copy of the body.

## What is proven (the full totality — no sentinel)

- **Proven:** the **full transition-table totality** — each legal pair maps to its
  specific `Next(tag)`, and every other pair maps to `Rejected`. This is **stronger**
  than the earlier idiomatic-enum re-type, which proved only the *partial*
  state-safety property (no `Closed`/`Listen → Established`) because a distinct
  `Rejected` result was not yet expressible. COMP-4 (a)/(c) lifts that: the outcome
  is now a **real constructor value** (`Rejected(0)`), distinct from any `Next(s)` by
  Z3's datatype distinctness — **no `5 = REJECTED` int sentinel**.
- **Verify-time, not run-time (yet):** constructor values are discharged by the
  verifier; the runtime / property-test path does not evaluate the constructed
  outcome yet, so `llmll test` *skips* constructor-valued vectors. The demo's beat is
  **typecheck → verify**.

## Files

- `step.llmll` / `step.ast.json` — clean implementation → **verified** (SAFE).
- `step-bad.llmll` — one illegal edge: `Closed + ActiveOpen` returns `(Next 4)`
  (ESTABLISHED) instead of the correct `(Next 2)` (SYN_SENT), skipping the handshake.
  Type-checks, but `verify --strict-verified-core` → **refuted: step** (the totality
  post pins that pair to `(Next 2)`; injectivity refutes the `(Next 4)` body),
  localized to that branch.
- `step-weak.llmll` — the co-evolution start: a weak post that pins the five legal
  transitions but *omits* the `illegal → Rejected` totality clause, plus a body that
  sneaks a `Listen + RcvAck → (Next 4)` edge. The bug **survives** (`SAFE`).

## Spec / implementation co-evolution

1. Start with `step-weak.llmll` — buggy body + incomplete contract → **SAFE** (the
   bug slips through; a realistic human spec gap — the post never says non-legal
   pairs must `Reject`).
2. Add the missing `illegal → Rejected` totality clause (cite RFC 793 §3.2) →
   `step.llmll`'s full post.
3. Re-verify the buggy edge → **refuted** — the bug is now caught.

The hardening is **human-driven** (notice the survival, tighten the contract).
Honest caveat: `--cdp` / `--weakness-check` do **not** auto-flag the weak contract
for this function shape; automating the "your spec is too weak" signal is future
work, not a shipped claim.

## Reproduce

```
llmll verify ./step.llmll --strict-verified-core       # SAFE — verified
llmll verify ./step-bad.llmll --strict-verified-core   # refuted: step
llmll verify ./step-weak.llmll --strict-verified-core  # SAFE — bug survives the weak contract
```
