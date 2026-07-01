# tcp_rfc793 — Demo Runbook

> **Artifact:** "Implement a protocol from the RFC — in idiomatic types, with a real outcome sum — and prove the implementation maps every input to the right outcome."
> **Fixtures:** `step.llmll` (+ `step-bad`, `step-weak`). See [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) for the proven-vs-trusted matrix (read it first — the scope matrix is the headline, not a disclaimer).
> **Verified against:** `llmll 0.14.2`, real `liquid-fixpoint` on PATH.

Run from this directory. This is the flagship "take an RFC and let the system implement it" demo — and unlike the TOTP RFC example (whose crypto core is opaque/`asserted`), a protocol **state machine** lands its core invariant in the verified fragment, so it reaches `verified`.

## What it proves

`step [state: ConnState, event: Event] -> StepOutcome` encodes an RFC 793 (TCP) connection state-machine subset. **States and events are real sum types** — `(type ConnState (| Closed) (| Listen) (| SynSent) (| SynRcvd) (| Established))` and `(type Event …)` — and **the outcome is a real payload-bearing sum**, `(type StepOutcome (| Next int) (| Rejected int))`: a legal transition yields `Next(tag)` (the next-state tag), an illegal pair yields `Rejected(code)`. The outcome is **constructed natively** (the COMP-4 (a)/(c) feature, v0.13.9): the constructor application reflects into a native datatype term and the post discharges by **constructor equality**, refuting wrong outcomes by **injectivity**. There is **no `5 = REJECTED` int sentinel** — the reject is a first-class constructor value, distinct from every `Next(s)` by Z3's datatype theory.

The `post` is the **full transition-table totality** authored *from* the RFC (`:source "RFC 793 §3.2 …"`): each of the five legal pairs maps to its specific `Next(tag)`, and every other pair maps to `Rejected`. The verified invariant: the implementation provably cannot take an illegal transition (in particular, cannot reach `Established` without the handshake) and provably rejects every non-legal pair.

> **Honest scope (state it).**
> - **Co-evolution is human-in-the-loop, not auto-signaled.** `step-weak` (below) shows a too-weak contract letting a bug survive; the fix is real, but `--weakness-check`/`--cdp` does **not** auto-flag it — you *notice* the survival and tighten the spec yourself. The RFC and the verifier together harden the contract.
> - **Verify-time, not run-time (yet).** Constructor values are discharged by the *verifier* (native datatype reflection); the runtime / property-test evaluator does not yet evaluate the constructed outcome, so `llmll test` on this demo *skips* constructor-valued vectors rather than running them. The demo's beat is **typecheck → verify** — the proof is the point, not a test pass.

## Beats — real-typed state machine, real outcome sum

**Clean: idiomatic enum inputs + a constructed outcome sum, reaching `verified`.**
```bash
llmll verify ./step.llmll --strict-verified-core
```
```
   body-faithful: step
   Running liquid-fixpoint ...
✅ step.llmll — SAFE (liquid-fixpoint)
```

**Wrong: an illegal transition — refuted.** `step-bad.llmll` makes one arm wrong — `Closed + ActiveOpen` returns `(Next 4)` (ESTABLISHED) instead of the correct `(Next 2)` (SYN_SENT), skipping the handshake. It type-checks (`ConnState`/`Event` in, `StepOutcome` out), but the solver refutes it against the totality post for that input — the post pins the pair to `(Next 2)` and datatype injectivity rejects the `(Next 4)` body, localized to the branch:
```bash
llmll verify ./step-bad.llmll --strict-verified-core
```
```
error: body verification of 'step' failed (else-branch does not satisfy postcondition) (constraint #1)
ERROR: --strict-verified-core: refuted: step
```

**The spec-imperfection lesson.** `step-weak.llmll` carries an **under-specified** contract — it pins the five legal transitions but *forgets* the `illegal → Rejected` totality clause — and a body that sneaks in a `Listen + RcvAck → (Next 4)` edge (pretending LISTEN can establish). Against the weak post, the bug **survives**:
```bash
llmll verify ./step-weak.llmll --strict-verified-core
```
```
   body-faithful: step
   Running liquid-fixpoint ...
✅ step-weak.llmll — SAFE (liquid-fixpoint)
```
That green check on a wrong implementation is the point: **a spec is only as strong as you write it.** You notice the survival, add the missing totality clause (citing the RFC), and re-verify — and `step.llmll`'s full post `refutes` that edge. The verifier and the RFC co-evolve the contract until the implementation is provably correct.

## Narration

> *"I implemented the TCP connection state machine from RFC 793 — in real enum types, matched in the body, returning a real outcome sum `(| Next int) (| Rejected int)` — and the compiler proved it maps every (state, event) to the right outcome: legal transitions to the right next state, every illegal pair to a real `Rejected` value, not a magic `-1`. A protocol-totality property, `verified`, not asserted. Then a weaker spec lets a bad transition slip through — the honest part: the proof is exactly as strong as the contract, and you harden the contract from what slips through. The RFC is the spec source; the verifier holds you to it."*

Framing: **assurance, not bug-finding** — and the `VERIFICATION_SCOPE.md` matrix names exactly what's proven (the full transition-table totality) versus trusted.
