# session-pay: three safety properties proved in one function

`open-and-pay [state event balance amount] -> PayOutcome` pays only when the
RFC 793 transition reaches `ESTABLISHED`, the balance covers the amount, and the
amount is a `Word` (0 to 65535). It returns a sum type with payloads,
`Paid(balance - amount)` or `Rejected(0)`, with no integer sentinel. The file
composes three earlier demos in one module: protocol state safety
([`tcp_rfc793`](../tcp_rfc793/)), a verified payment leaf
([`payments-core`](../payments-core/)), and a refined bounded parameter. Each
wrong twin drops one of the three rules and is caught on its own.

| File | What it demonstrates |
|---|---|
| `open-and-pay.llmll` | `step`, `debit` and `open-and-pay` all verified; `open-and-pay` through both call edges |
| `open-and-pay-bad-step.llmll` | pays before the handshake completes (`SYN_SENT`/`SYN_RCVD` treated as payable): refuted |
| `open-and-pay-unsafe.llmll` | drops the `balance >= amount` guard: `debit`'s precondition refused at the call site |
| `open-and-pay-unbounded.llmll` | `amount` is a plain `int`, so nothing proves `amount >= 0`: refused at the call site |
| `*.ast.json` | JSON-AST forms of the same programs |

The full walkthrough, including the three-function trust report, is
[`DEMO-RUNBOOK.md`](DEMO-RUNBOOK.md). What is proved versus trusted is in
[`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md).

## Commands (outputs reproduced on v0.26.5)

Run from this directory, with `fixpoint` and `z3` on `PATH`. Output is trimmed
to the verdict lines.

```text
$ llmll verify ./open-and-pay.llmll --strict-verified-core
✅ ./open-and-pay.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./open-and-pay-bad-step.llmll --strict-verified-core
error: body verification of 'open-and-pay' failed (then-branch does not satisfy postcondition) (constraint #8)
ERROR: --strict-verified-core: refuted: open-and-pay

$ llmll verify ./open-and-pay-unsafe.llmll
error: call-site precondition of 'debit' not satisfied in 'open-and-pay' — caller does not prove callee's precondition (constraint #10)

$ llmll verify ./open-and-pay-unbounded.llmll
error: call-site precondition of 'debit' not satisfied in 'open-and-pay' — caller does not prove callee's precondition (constraint #10)
```

The good file exits 0 and every twin exits 1. Add `--trust-report` to the first
command to see all three functions at `verified`. `llmll test ./open-and-pay.llmll`
passes its one property. The verdicts are frozen in
[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) and checked by
`make refute-crux-gate`.

## Scope

`step` and `debit` are re-authored in this file rather than imported, so the
whole composition stays in one module. Every obligation is linear integer
arithmetic plus non-recursive datatypes, so all three postconditions reach
`verified` with no opaque or fallback core.
