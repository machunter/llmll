# tcp_rfc793 — Demo Runbook

> **Artifact:** "Implement a protocol from the RFC — and prove the implementation can't violate it."
> **Fixtures:** `step.llmll` (+ `step-bad`, `step-weak`). See [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) for the proven-vs-asserted matrix (read it first — the scope matrix is the headline, not a disclaimer).
> **Verified against:** `llmll 0.13.4`, real `liquid-fixpoint` on PATH.

Run from this directory. This is the flagship "take an RFC and let the system implement it" demo — and unlike the TOTP RFC example (whose crypto core is opaque/`asserted`), a protocol **state machine** lands its core invariant in the verified QF-LIA fragment, so it reaches `verified`.

## What it proves

`step [state: ConnState, event: Event] -> ConnResult` encodes an RFC 793 (TCP) connection state-machine subset. States and events are int-encoded; the transition table is a nested `if`; the `post` is the RFC's **legal-successor relation** (each clause carries `:source "RFC 793 §3.2 …"`). The verified invariant is *protocol state-safety*: the implementation provably cannot take an illegal transition.

> **Honest scope (state it).**
> - **Co-evolution is human-in-the-loop, not auto-signaled.** `step-weak` (below) shows a too-weak contract letting a bug survive; the fix is real, but `--weakness-check`/`--cdp` does **not** auto-flag it for this `(int,int)->refinement` signature (the trivial-candidate enumerator yields none) — you *notice* the survival and tighten the spec yourself. That is the spec/implementation co-evolution: the RFC and the verifier together harden the contract.
> - **Int-sentinel return, not `Result`/COMP-3b.** Illegal transitions return a `REJECTED` sentinel rather than `Err …`; a `post` that discriminates on a `Result` value's *constructor* isn't QF-LIA-confirmed today, so the int-sentinel is the guaranteed-`verified` path. Same illegal-transition story, in-fragment.

## Beat — the state machine

**Clean: a protocol state machine that reaches `verified`.**

```bash
llmll verify ./step.llmll
```
```
   body-faithful: step
   Running liquid-fixpoint ...
✅ step.llmll — SAFE (liquid-fixpoint)
```

**Wrong: an illegal transition — refuted.** `step-bad.llmll` allows an illegal edge (e.g. accepting `SEND_DATA` in `SYN_SENT` and jumping to `ESTABLISHED`, skipping the handshake). It type-checks and passes a valid-handshake test, but the solver refutes it on that branch:

```bash
llmll verify ./step-bad.llmll --strict-verified-core
```
```
error: body verification of 'step' failed (else-branch does not satisfy postcondition) (constraint #6)
ERROR: --strict-verified-core: refuted: step
```

**The spec-imperfection lesson.** `step-weak.llmll` has the *same* bug but against an **under-specified** contract (one illegal edge the human forgot to forbid) — so the bug **survives**:

```bash
llmll verify ./step-weak.llmll
```
```
   body-faithful: step
   Running liquid-fixpoint ...
✅ step-weak.llmll — SAFE (liquid-fixpoint)
```

That green check on a wrong implementation is the point: **a spec is only as strong as you write it.** You notice the survival, add the missing legal-successor clause (citing the RFC line), and re-verify — now `step-bad`'s edge is `refuted`. The verifier and the RFC co-evolve the contract until the implementation is provably correct.

## Narration

> *"I implemented the TCP connection state machine from RFC 793, and the compiler proved it can't send data before the handshake completes — a real protocol-safety property, `verified`, not asserted. Then I showed a weaker spec letting a bad transition slip through — and that's the honest part: the proof is exactly as strong as the contract, and you harden the contract from what slips through. The RFC is the spec source; the verifier is what holds you to it."*

Framing: **assurance, not bug-finding** — and the `VERIFICATION_SCOPE.md` matrix names exactly what's proven (state-safety / legal-successor) versus trusted.
