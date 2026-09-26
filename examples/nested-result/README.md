# nested-result: a Result match verified inside a let

`safe-withdraw [attempt: Result[int, string], floor: int] -> Balance` returns a
refinement type, `Balance = {b : int | b >= 0}`, and has no explicit post:
the return refinement is the whole spec. The body is a `let`, and the two-arm
match on `attempt` sits inside it, one level below the top. The solver
discharges the refinement for each arm through the `let`.
[`payments-core/settle`](../payments-core/) shows the same discipline with the
match at the top level.

| File | What it demonstrates |
|---|---|
| `safe-withdraw.llmll` | both arms return a value `>= 0`: SAFE |
| `safe-withdraw-bad.llmll` | the `Success` arm returns the raw payload `n`, which can be negative: refuted on that arm |
| `*.ast.json` | JSON-AST forms of the same programs |

[`DEMO-RUNBOOK.md`](DEMO-RUNBOOK.md) walks the two beats;
[`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) is the proved-versus-trusted
matrix.

## Commands (outputs reproduced on v0.26.5)

Run from this directory, with `fixpoint` and `z3` on `PATH`. Output is trimmed
to the verdict lines.

```text
$ llmll verify ./safe-withdraw.llmll --strict-verified-core
✅ ./safe-withdraw.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./safe-withdraw-bad.llmll --strict-verified-core
error: body verification of 'safe-withdraw' failed (then-branch does not satisfy postcondition) (constraint #0)
ERROR: --strict-verified-core: refuted: safe-withdraw
```

The good file exits 0 and the twin exits 1. These verdicts are frozen in
[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) and checked by
`make refute-crux-gate`.
