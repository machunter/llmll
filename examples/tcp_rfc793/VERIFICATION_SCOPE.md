# TCP RFC 793 State Machine — Verification Scope Matrix

**Claim.** The connection state machine's *state-safety invariant* — `step` maps
every `(state, event)` pair to exactly its RFC 793 §3.2 legal successor, and
**rejects every illegal pair** — is **solver-proven** (liquid-fixpoint, QF-LIA),
not merely tested or asserted. The implementation *provably cannot* perform an
illegal transition (e.g. accept application data before the handshake completes).

| # | Function | Params | Post | Body | Check | Verdict | Source |
|---|----------|--------|------|------|-------|---------|--------|
| 1 | `step` | refinement-typed (`ConnState` 0..4, `Event` 0..5) | ✅ legal-successor relation | ✅ implemented (nested `if`) | ✅ 4 RFC transitions | **verified** (body-faithful, liquid-fixpoint) | RFC 793 §3.2 |

**Proven: 1 · Asserted: 0.**

Contrast `examples/totp_rfc6238` (Proven: 0, Asserted: 5): TOTP's core is an
opaque `hmac-sha1` builtin outside QF-LIA, so it demonstrates RFC *traceability*
while every clause is `asserted`. Here the load-bearing invariant is
integer/ordering-shaped, so it lands in the auto-discharge fragment and is
`verified`. Nothing cryptographic or opaque is in scope; nothing falls back.

## Why it reaches `verified` (fragment-fit)

- States / events / result are **int-encoded** refinement aliases — not a
  `>2`-arm ADT (which would fall back to contract-only).
- The transition table is a **nested `if`** — path-split, 7 paths, far under the
  4096-path body-VC ceiling.
- The `post` is the RFC legal-successor relation in **QF-LIA** (`and`/`or`/`not`,
  linear `=`), authored from the RFC — not a copy of the body.
- No `mod` / `/` / `*` (nonlinear) and no pairs-in-predicates — both fall back.

## Files

- `step.llmll` / `step.ast.json` — clean implementation → **verified** (SAFE).
- `step-bad.llmll` — one illegal transition (SYN_SENT + SEND_DATA → ESTABLISHED:
  application data before the handshake). Type-checks, **passes the happy-path
  `check`**, but `verify --strict-verified-core` → **refuted: step** (constraint
  #6, localized to the offending branch).
- `step-weak.llmll` — the same bug under an **under-specified** contract (the six
  legal transitions, but no rejection clause). The bug **survives** (`SAFE`).

## Spec / implementation co-evolution

1. Start with `step-weak.llmll` — buggy body + incomplete contract → **SAFE**
   (the bug slips through; a realistic human spec gap).
2. Add the missing rejection clause (cite RFC 793 §3.2) → `step-bad.llmll`'s
   contract.
3. Re-verify → **refuted: step** — the bug is now caught.

The hardening is **human-driven** (notice the bug survived, tighten the
contract). Honest caveat: `--cdp` / `--weakness-check` do **not** auto-flag the
weak contract for this function shape — `--cdp` reports
`0/0 candidates [candidates-empty-under-limit]` (the trivial-candidate enumerator
generates none for an `(int, int) -> refinement` signature) and weakness-check
reports none. Automating the "your spec is too weak" signal for this shape is
future work, not a shipped claim.

## Reproduce

```
llmll verify ./step.llmll --strict-verified-core       # SAFE — verified
llmll test   ./step.llmll                              # 1/1 — handshake transitions
llmll verify ./step-bad.llmll --strict-verified-core   # refuted: step
llmll verify ./step-weak.llmll --strict-verified-core  # SAFE — bug survives the weak contract
```
