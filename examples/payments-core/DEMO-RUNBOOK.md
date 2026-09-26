# payments-core — Demo Runbook

> **Artifact:** "A verified payments core — composition that proves correct, and an assurance story you can show with a real model."
> **Fixtures:** `transfer.llmll` (+ `transfer-bad`, `transfer-unsafe`), `settle.llmll` (+ `settle-bad`), `conserve.llmll` (+ `conserve-bad`).
> **Requires:** real `liquid-fixpoint` on PATH.

Run from this directory; every beat ends at `verify` / the trust-report.

## What it proves

`transfer` is composed over a **verified `debit` call edge** and proves a conservation-flavoured contract; `settle` shows the same idea on a `Result` return (the type *is* the contract). The wrong twins type-check and pass a happy-path test, but the solver refutes them — and a missing precondition is refused at the call site.

> **Two-account conservation.** The visceral "money cannot be created" framing wants a post over *both* balances at once — `(first result) + (second result) = from + to`. `conserve.llmll` (Beat C) now proves exactly that at the body-faithful tier: the pair is constructed in the body and the projections discharge through z3's datatype theory (the single-constructor product restriction on native datatype construction). `conserve-bad.llmll` credits one extra unit — money creation — and is refuted.
>
> **Scope (state it up front).** **The refutation twins are hand-authored.** The pitch is AI-to-AI, so the *assurance* evidence is the opposite of a gotcha: in one real-agent run (2026-06-23, one attempt per model), **claude-opus-4-8 and gpt-5.5 each filled `transfer`**, both fills called `debit`, the two fills were byte-identical, and the compiler verified each. The record is the "Real on-disk datapoint" bullet in [`experiments/r5-validation/findings.md`](../../experiments/r5-validation/findings.md#addendum-2026-07-05--case-5-sibling-call-suppression-fixed-v0149); the raw run directory (`experiments/minimal-agent/runs/20260623T145513Z-payments-core-realfill`) is not committed. One attempt per model is a datapoint, not a rate. The `-bad` twins exist to demonstrate the *capability* (that the verifier *would* catch a wrong fill), not to claim frontier models write that bug on a clear spec.

## Beat A — `transfer`: verified through a call edge

```bash
llmll verify ./transfer.llmll
```
```
   ...
   body-faithful: debit, transfer
   call-pre obligations: transfer
   Running liquid-fixpoint ...
✅ ./transfer.llmll — SAFE (liquid-fixpoint)
   ...
```

The trust report shows `transfer` verified **through** the `debit` edge. Pass `--strict-verified-core` with `--trust-report` so the report comes from this run of the solver, not only from the `.verified.json` sidecar:

```bash
llmll verify ./transfer.llmll --strict-verified-core --trust-report
```
```
   ...
✅ ./transfer.llmll — SAFE (liquid-fixpoint)
   ...
Trust Report
────────────────────────────────────────────────────────────
  debit:
    pre:  asserted  |  post: verified (liquid-fixpoint)
  transfer:
    pre:  asserted  |  post: verified (liquid-fixpoint)
    ↳ calls debit (pre: asserted, post: verified (liquid-fixpoint))
────────────────────────────────────────────────────────────
Summary:
  verified:         2
  tested:           0
  asserted:         0
  no contract:      0
```

`--trust-report` on its own reads the sidecar and ends with `(sidecar-only report: evidence is read from .verified.json and was NOT validated against a run of the VC emitter; use --strict-verify for that)`. `--strict-verify` removes that note but also runs the weakness check, which prints a spec-weakness warning for `transfer` (its post admits returning `balance` unchanged). `--strict-verified-core` re-runs the solver and prints neither, so it is the headline command.

**The wrong fill — caught.** `transfer-bad.llmll` "helpfully" credits the destination on the insufficient-funds branch. It type-checks and passes a happy-path test, but breaks the contract on that branch:

```bash
llmll verify ./transfer-bad.llmll --strict-verified-core
```
```
   ...
error: body verification of 'transfer' failed (else-branch does not satisfy postcondition) (constraint #2)
ERROR: --strict-verified-core: refuted: transfer
```

**The missing guarantee — refused.** `transfer-unsafe.llmll` drops the guard, so nothing discharges `debit`'s precondition at the call site:

```bash
llmll verify ./transfer-unsafe.llmll
```
```
   ...
error: call-site precondition of 'debit' not satisfied in 'transfer' — caller does not prove callee's precondition (constraint #2)
```

## Beat B — `settle`: the type is the contract

`settle [attempt: Result[int, Reason]] -> Balance` returns a refined sum-type result (`Balance ≜ {b:int | b ≥ 0}`); its body *is* the two-arm `Result` match, with no explicit `post` — the return refinement is discharged **per arm**:

```bash
llmll verify ./settle.llmll
```
```
   ...
   body-faithful: settle
   Running liquid-fixpoint ...
✅ ./settle.llmll — SAFE (liquid-fixpoint)
   ...
```

`settle-bad.llmll` returns a "dishonest Success" — the `Success` payload passed through unchecked, which can be negative:

```bash
llmll verify ./settle-bad.llmll --strict-verified-core
```
```
   ...
error: body verification of 'settle' failed (then-branch does not satisfy postcondition) (constraint #0)
ERROR: --strict-verified-core: refuted: settle
```

## Beat C — `conserve`: two-account conservation over a pair return

`conserve [from to amount] -> (int, int)` returns *both* post-transfer balances and proves the conservation sum directly — `(first result) + (second result) = from + to` — at the body-faithful tier. The projections discharge through z3's datatype theory (the single-constructor product restriction on native datatype construction), so this is a proof, not a tested sample:

```bash
llmll verify ./conserve.llmll
```
```
   ...
   body-faithful: conserve
   Running liquid-fixpoint ...
✅ ./conserve.llmll — SAFE (liquid-fixpoint)
   ...
```

`conserve-bad.llmll` credits the destination with one unit more than it debits — the balances sum to `from + to + 1`. The body-faithful VC refutes it:

```bash
llmll verify ./conserve-bad.llmll
```
```
   ...
error: body verification of 'conserve-bad' failed — implementation does not satisfy postcondition (constraint #0)
```

## Narration

> *"This is a payments core where the compiler proves the implementation matches the spec — and proves it through a call edge: `transfer` leans on a verified `debit`. When we gave `transfer` to two frontier models, each wrote a fill the compiler verified. That's the assurance. And if a fill 'helpfully' credits an account it shouldn't, or drops the guard that protects `debit`, the verifier refuses it. Correctness isn't a judgment call; it's a verdict."*

Framing: **assurance, not bug-finding.** The headline is the green trust-report; the refutations are evidence the proof is real.
