# payments-core: conservation proved through a call edge

A small payments core in three parts. `transfer` proves its contract through a
verified `debit` call edge; `settle` returns a refined `Balance` from a
two-arm `Result` match with no explicit post; `conserve` returns both
post-transfer balances as a pair and proves `(first result) + (second result) =
from + to`, the "money can't be created" property. Each good file has a wrong
twin that type-checks and passes a happy-path test, and the solver refutes it.

| File | What it demonstrates |
|---|---|
| `transfer.llmll` | `transfer` verified through the `debit` edge: SAFE |
| `transfer-bad.llmll` | credits the destination on the insufficient-funds branch: refuted |
| `transfer-unsafe.llmll` | drops the guard, so `debit`'s precondition is not proven at the call site: refused |
| `settle.llmll` | return refinement `Balance = {b:int \| b >= 0}` discharged per `Result` arm: SAFE |
| `settle-bad.llmll` | passes the `Success` payload through unchecked (can be negative): refuted |
| `conserve.llmll` | two-account conservation over a pair return, body-faithful: SAFE |
| `conserve-bad.llmll` | credits one unit more than it debits: refuted |
| `demo.sh` | scripted, typed-out run of the beats (for recording) |
| `*.ast.json` | JSON-AST forms of the same programs |

The step-by-step walkthrough, with trust-report output and narration, is
[`DEMO-RUNBOOK.md`](DEMO-RUNBOOK.md).

## Commands (outputs reproduced on v0.26.5)

Run from this directory, with `fixpoint` and `z3` on `PATH`. Output is trimmed
to the verdict lines.

```text
$ llmll verify ./transfer.llmll
✅ ./transfer.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./transfer-bad.llmll --strict-verified-core
error: body verification of 'transfer' failed (else-branch does not satisfy postcondition) (constraint #2)
ERROR: --strict-verified-core: refuted: transfer

$ llmll verify ./transfer-unsafe.llmll
error: call-site precondition of 'debit' not satisfied in 'transfer' — caller does not prove callee's precondition (constraint #2)

$ llmll verify ./settle.llmll
✅ ./settle.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./settle-bad.llmll --strict-verified-core
error: body verification of 'settle' failed (then-branch does not satisfy postcondition) (constraint #0)
ERROR: --strict-verified-core: refuted: settle

$ llmll verify ./conserve.llmll
✅ ./conserve.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./conserve-bad.llmll
error: body verification of 'conserve-bad' failed — implementation does not satisfy postcondition (constraint #0)
```

The good files exit 0 and every twin exits 1. These verdicts are frozen in
[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) and checked by
`make refute-crux-gate`.

## Scope

The `-bad` twins are hand-authored. They show that the verifier would catch a
wrong fill; they do not claim that frontier models write that bug on a clear
spec. The runbook records one real-agent run in which two models each filled
`transfer` and the compiler verified both fills (one attempt per model, a
datapoint and not a rate).
