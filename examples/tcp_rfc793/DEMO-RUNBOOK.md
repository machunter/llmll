# tcp_rfc793 — Demo Runbook

> **Artifact:** "Implement a protocol from the RFC — in idiomatic types — and prove the implementation can't violate it."
> **Fixtures:** `step.llmll` (+ `step-bad`, `step-weak`). See [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) for the proven-vs-trusted matrix (read it first — the scope matrix is the headline, not a disclaimer).
> **Verified against:** `llmll 0.13.4`, real `liquid-fixpoint` on PATH.

Run from this directory. This is the flagship "take an RFC and let the system implement it" demo — and unlike the TOTP RFC example (whose crypto core is opaque/`asserted`), a protocol **state machine** lands its core invariant in the verified QF-LIA fragment, so it reaches `verified`.

## What it proves

`step [state: ConnState, event: Event] -> ConnState` encodes an RFC 793 (TCP) connection state-machine subset. **States and events are real sum types** —
`(type ConnState (| Closed) (| Listen) (| SynSent) (| SynRcvd) (| Established))` and `(type Event …)` — and the body **matches on them**. It reaches `verified` with **no int-encoding workaround**: the compiler tags the nullary constructors internally and discharges the post in pure QF-LIA (the COMP-3b-general feature). The `post` is a state-safety property authored *from* the RFC (`:source "RFC 793 §3.2 …"`): you cannot reach `Established` without the handshake — never straight from `Closed` or `Listen`. The verified invariant: the implementation provably cannot take an illegal transition.

> **Honest scope (state it).**
> - **Co-evolution is human-in-the-loop, not auto-signaled.** `step-weak` (below) shows a too-weak contract letting a bug survive; the fix is real, but `--weakness-check`/`--cdp` does **not** auto-flag it (the trivial-candidate enumerator yields none for this signature) — you *notice* the survival and tighten the spec yourself. The RFC and the verifier together harden the contract.
> - **Verify-time, not run-time (yet).** Constructor values are discharged by the *verifier* (the COMP-3b-general desugar to internal tags); the runtime / property-test evaluator does not yet evaluate them, so `llmll test` on this demo *skips* constructor-valued vectors rather than running them. The demo's beat is **typecheck → verify** — the proof is the point, not a test pass.

## Beats — real-typed state machine

**Clean: idiomatic enum types, reaching `verified`.**
```bash
llmll verify ./step.llmll
```
```
   body-faithful: step
   Running liquid-fixpoint ...
✅ step.llmll — SAFE (liquid-fixpoint)
```

**Wrong: an illegal transition — refuted.** `step-bad.llmll` adds one illegal edge — `Closed + ActiveOpen → Established`, skipping the SYN_SENT handshake. It type-checks (`ConnState` in, `ConnState` out), but the solver refutes it against the state-safety post for that input, localized to the branch:
```bash
llmll verify ./step-bad.llmll --strict-verified-core
```
```
error: body verification of 'step' failed (then-branch does not satisfy postcondition) (constraint #1)
ERROR: --strict-verified-core: refuted: step
```

**The spec-imperfection lesson.** `step-weak.llmll` carries an **under-specified** contract — it forbids the `Closed → Established` jump but *forgets* the symmetric `Listen → Established` one — and a body that sneaks in a `Listen + RcvAck → Established` edge. Against the weak post, the bug **survives**:
```bash
llmll verify ./step-weak.llmll
```
```
   body-faithful: step
   Running liquid-fixpoint ...
✅ step-weak.llmll — SAFE (liquid-fixpoint)
```
That green check on a wrong implementation is the point: **a spec is only as strong as you write it.** You notice the survival, add the missing `Listen` clause (citing the RFC), and re-verify — and `step.llmll`'s full post `refutes` that edge. The verifier and the RFC co-evolve the contract until the implementation is provably correct.

## Narration

> *"I implemented the TCP connection state machine from RFC 793 — in real enum types, `(type ConnState …)`, matched in the body — and the compiler proved it can't reach ESTABLISHED without the handshake: a real protocol-safety property, `verified`, not asserted. Then a weaker spec lets a bad transition slip through — the honest part: the proof is exactly as strong as the contract, and you harden the contract from what slips through. The RFC is the spec source; the verifier holds you to it."*

Framing: **assurance, not bug-finding** — and the `VERIFICATION_SCOPE.md` matrix names exactly what's proven (state-safety / legal-successor) versus trusted.
