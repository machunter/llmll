# banking_ledger — assume-guarantee across a 3-level call chain

A ledger whose safety (`balance >= 0`, `result = balance - amount`) is proven
compositionally through `transfer → withdraw → safe-subtract`. Each function
proves its own postcondition; at every call site the caller must prove the
callee's precondition; the callee's postcondition is then assumed. No function
is inlined, and no precondition is ever assumed for free.

## The discriminative point

`banking.llmll` verifies SAFE; `banking-bad.llmll` is the refuting twin. The
only change is `clamp-withdraw`: the correct version guards the call
(`(if (>= balance requested) (withdraw balance requested) balance)`), the twin
drops the guard and withdraws unconditionally. That is the use-after-check /
goto-fail shape: with the guard gone, `withdraw`'s precondition
(`>= balance requested`) is no longer established, so a `requested > balance`
call would overdraw the account below zero.

The verifier refutes it **at the call site**, not by running the body:

```text
$ llmll verify examples/banking_ledger/banking.llmll --strict-verified-core
✅ examples/banking_ledger/banking.llmll — SAFE (liquid-fixpoint)

$ llmll verify examples/banking_ledger/banking-bad.llmll --strict-verified-core
error: call-site precondition of 'withdraw' not satisfied in 'clamp-withdraw'
       — caller does not prove callee's precondition (constraint #6)
ERROR: --strict-verified-core: refuted: clamp-withdraw
```

A caller must **prove** the callee's precondition; it is never assumed. That is
the whole content of the assume-guarantee chain, and dropping one guard breaks
it. The frozen verdicts are gated by `make refute-crux-gate`.
