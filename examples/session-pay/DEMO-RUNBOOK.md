# session-pay — Demo Runbook (the connected demo)

> **Artifact:** "Open a connection, then pay — and prove all three safety rules at once."
> **The integration:** one verified function composes **protocol state-safety** (tcp_rfc793), **verified payment** (payments-core), and a **bounded amount** (return-refine) — proven together on a single trust-report, through the call edges.
> **Fixtures:** `open-and-pay.llmll` + wrong twins `-bad-step`, `-unsafe`, `-unbounded`.
> **Verified against:** `llmll 0.13.9`, real `liquid-fixpoint` on PATH. Single self-contained module (no cross-module import).

Run from this directory; the climax is one `verify --trust-report`.

## What it proves

`open-and-pay [state event balance amount] -> PayOutcome` allows a payment **only** when (a) the `(state, event)` transition reaches `ESTABLISHED` (the RFC 793 state machine), (b) `balance >= amount` (the funds guard), and (c) `amount` is a `Word` (a 16-bit bounded value). It returns a real payload-bearing sum, `(type PayOutcome (| Paid int) (| Rejected int))`: `Paid(balance - amount)` on success, or `Rejected(0)` otherwise — a first-class constructor value, **not** a `-1` masquerading as a balance. The three capabilities compose:

- **State-safety** — `step` is the RFC 793 connection state machine; `open-and-pay` pays only at `ESTABLISHED`.
- **Payment** — `debit` is the verified payment leaf; `open-and-pay` discharges its precondition at the call site.
- **Bounded amount** — `amount: Word` supplies `amount >= 0`, which discharges the *other* half of `debit`'s precondition.

The `post` is the legal session-pay relation (`result = Paid(balance - amount)` iff an `ESTABLISHED`-reaching transition **and** sufficient funds; else `result = Rejected(0)`), authored from the spec — not a copy of the body. The outcome sum is **constructed natively** (COMP-4 (a)/(c), v0.13.9): the post discharges by constructor equality / injectivity, into Z3's datatype theory.

## The climax — one trust-report, verified through every edge

```bash
llmll verify ./open-and-pay.llmll --strict-verified-core --trust-report
```
```
   body-faithful: step, debit, open-and-pay
   call-pre obligations: open-and-pay
   Running liquid-fixpoint ...
✅ open-and-pay.llmll — SAFE (liquid-fixpoint)
Trust Report
  debit:         post: verified (liquid-fixpoint)
  open-and-pay:  post: verified (liquid-fixpoint)
    ↳ calls step  (post: verified (liquid-fixpoint))
    ↳ calls debit (post: verified (liquid-fixpoint))
  step:          post: verified (liquid-fixpoint)
Summary:
  verified: 3   asserted: 0
```

All three functions `verified`; `open-and-pay` verified **through** the `step` and `debit` edges — the integration holds at the solver level, not as a floor. The happy-path property also passes:

```bash
llmll test ./open-and-pay.llmll      # ✅ Passed: 1
```

## The three wrong twins — one per safety rule

**State-safety — `open-and-pay-bad-step`** pays whenever `next >= 2` (treats `SYN_SENT`/`SYN_RCVD` as payable), letting a payment through *before* the handshake completes:
```bash
llmll verify ./open-and-pay-bad-step.llmll --strict-verified-core
```
```
error: body verification of 'open-and-pay' failed (then-branch does not satisfy postcondition) (constraint #8)
ERROR: --strict-verified-core: refuted: open-and-pay
```

**Funds safety — `open-and-pay-unsafe`** drops the `balance >= amount` guard, so `debit`'s precondition is undischarged:
```bash
llmll verify ./open-and-pay-unsafe.llmll
```
```
error: call-site precondition of 'debit' not satisfied in 'open-and-pay' — caller does not prove callee's precondition (constraint #10)
```

**Bound safety — `open-and-pay-unbounded`** makes `amount` a plain `int`, so nothing proves `amount >= 0` and `debit`'s second precondition conjunct is undischarged:
```bash
llmll verify ./open-and-pay-unbounded.llmll
```
```
error: call-site precondition of 'debit' not satisfied in 'open-and-pay' — caller does not prove callee's precondition (constraint #10)
```

Three rules, three twins, three distinct verdicts — a refutation for the state-safety violation, two call-site refusals for the dropped funds-guard and the dropped bound.

## Honest scope

- **Real enum states/events AND a real outcome sum.** `ConnState`/`Event` are real nullary-enum sum types — matched and compared as values, verified (COMP-3c / COMP-3b-general). The multi-outcome RESULT is now a real payload-bearing sum, `PayOutcome` (`Paid(int)` / `Rejected(int)`), **constructed natively** (COMP-4 (a)/(c), v0.13.9) and discharged by constructor equality / injectivity. No int sentinel: `Rejected(0)` is a first-class constructor value, distinct from every `Paid(n)` by Z3's datatype distinctness — not a `-1` posing as a balance.
- **Single module.** `step`/`debit` are re-authored here, not cross-module-imported, to keep the whole composition in the body-faithful fragment (cross-module verified composition is a tracked gap).
- **Everything is `verified`, nothing opaque.** Unlike a crypto-bearing RFC demo, there is no `asserted` core — the bodies are additive/comparison QF-LIA plus the outcome's native datatype construction (COMP-4 (a)/(c)), all in the decidable fragment, so the solver (not a fallback) is the catcher throughout.

## Narration

> *"This is the whole pitch in one function. A payment is only allowed when the protocol says the session is open, the funds are there, and the amount is a real 16-bit value — and the compiler proves the implementation obeys all three, at once, through the call edges. Drop any one guard and the verifier catches exactly that: pay before the handshake — refuted; drop the funds check — refused; drop the bound — refused. Three safety properties, one proof."*

Framing: **assurance, not bug-finding** — the headline is the single green trust-report that composes state-safety, payment-conservation, and the value bound.
