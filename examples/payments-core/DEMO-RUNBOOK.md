# payments-core — Demo Runbook

> **Artifact:** "A verified payments core — composition that proves correct, and an assurance story you can show with a real model."
> **Fixtures:** `transfer.llmll` (+ `transfer-bad`, `transfer-unsafe`), `settle.llmll` (+ `settle-bad`).
> **Verified against:** `llmll 0.13.4`, real `liquid-fixpoint` on PATH.

Run from this directory; every beat ends at `verify` / the trust-report.

## What it proves

`transfer` is composed over a **verified `debit` call edge** and proves a conservation-flavoured contract; `settle` shows the same idea on a `Result` return (the type *is* the contract, COMP-3b). The wrong twins type-check and pass a happy-path test, but the solver refutes them — and a missing precondition is refused at the call site.

> **Honest scope (state it up front).** Two things this demo does *not* claim:
> 1. **Single-int, not two-account conservation.** The visceral "money cannot be created" framing wants a post over both balances (`(fst result) + (snd result) = from + to`), but pair-return refinements aren't expressible today (`fst`/`snd` aren't in the predicate sort env). So `transfer` proves *no-overdraft + all-or-nothing* on a single returned balance — real and asymmetric, just not the sum-conservation headline.
> 2. **The refutation twins are hand-authored.** The pitch is AI-to-AI, so the honest *assurance* evidence is the opposite of a gotcha: in a real-agent run, **two frontier models (claude-opus-4-8 and gpt-5.5) independently authored `transfer` correctly**, and the compiler *proved* each. That is the assurance story. The `-bad` twins exist to demonstrate the *capability* — that the verifier *would* catch a wrong fill — not to claim frontier models write that bug on a clear spec.

## Beat A — `transfer`: verified through a call edge

```bash
llmll verify ./transfer.llmll
```
```
   body-faithful: debit, transfer
   call-pre obligations: transfer
   Running liquid-fixpoint ...
✅ transfer.llmll — SAFE (liquid-fixpoint)
```

The trust report shows `transfer` verified **through** the `debit` edge (run `verify` first so the sidecar is warm, then `--trust-report`):

```bash
llmll verify ./transfer.llmll --trust-report
```
```
    ↳ calls debit (pre: asserted, post: verified (liquid-fixpoint))
Summary:
  verified:         2
```

**The wrong fill — caught.** `transfer-bad.llmll` "helpfully" credits the destination on the insufficient-funds branch. It type-checks and passes a happy-path test, but breaks the contract on that branch:

```bash
llmll verify ./transfer-bad.llmll --strict-verified-core
```
```
error: body verification of 'transfer' failed (else-branch does not satisfy postcondition) (constraint #2)
ERROR: --strict-verified-core: refuted: transfer
```

**The missing guarantee — refused.** `transfer-unsafe.llmll` drops the guard, so nothing discharges `debit`'s precondition at the call site:

```bash
llmll verify ./transfer-unsafe.llmll
```
```
error: call-site precondition of 'debit' not satisfied in 'transfer' — caller does not prove callee's precondition (constraint #2)
```

## Beat B — `settle`: the type is the contract (COMP-3b)

`settle [attempt: Result[int, Reason]] -> Balance` returns a refined sum-type result (`Balance ≜ {b:int | b ≥ 0}`); its body *is* the two-arm `Result` match, with no hand-written `post` — the return refinement is discharged **per arm** (COMP-3b):

```bash
llmll verify ./settle.llmll
```
```
   body-faithful: settle
   Running liquid-fixpoint ...
✅ settle.llmll — SAFE (liquid-fixpoint)
```

`settle-bad.llmll` returns a "dishonest Success" — the `Success` payload passed through unchecked, which can be negative:

```bash
llmll verify ./settle-bad.llmll --strict-verified-core
```
```
error: body verification of 'settle' failed (then-branch does not satisfy postcondition) (constraint #0)
ERROR: --strict-verified-core: refuted: settle
```

## Narration

> *"This is a payments core where the compiler proves the implementation matches the spec — and proves it through a call edge: `transfer` leans on a verified `debit`. Two frontier models wrote `transfer` and the compiler confirmed each was correct — that's the assurance. And if a fill 'helpfully' credits an account it shouldn't, or drops the guard that protects `debit`, the verifier refuses it. Correctness isn't a judgment call; it's a verdict."*

Framing: **assurance, not bug-finding.** The headline is the green trust-report; the refutations are evidence the proof is real.
