# outcome-totality: every input maps to a payload-carrying variant

`classify` maps every `int` to a constructed, payload-bearing result:
`Accepted(n)` when `n >= 0` and `Rejected(n)` when `n < 0`. The postcondition
states both directions, and the verifier proves them through native FQData
construction of the `Outcome` sum type. Before this capability, demos such as
`tcp_rfc793` and `session-pay` used an int sentinel (`-1 = REJECTED`) because a
constructed variant could not appear in a proved post.

| File | What it demonstrates |
|---|---|
| `classify.llmll` | `(if (>= n 0) (Accepted n) (Rejected n))` satisfies both clauses: SAFE |
| `classify-bad.llmll` | always returns `(Accepted n)`, which violates the `n < 0 -> Rejected n` clause: refuted |
| `*.ast.json` | the same two programs in JSON-AST form |
| `EXPECTED_VERDICTS.json` | frozen verdicts and exit codes, checked by `make refute-crux-gate` |

## Commands (outputs reproduced on v0.26.5)

```text
$ llmll verify ./classify.llmll --strict-verified-core
   body-faithful: classify
   Running liquid-fixpoint ...
✅ ./classify.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./classify-bad.llmll --strict-verified-core
   body-faithful: classify
   Running liquid-fixpoint ...
error: body verification of 'classify' failed — implementation does not satisfy postcondition (constraint #0)
ERROR: --strict-verified-core: refuted: classify
```

Exit 0 and exit 1. (The `.fq written to` and `.verified.json written to` lines
are omitted.)

## The discriminative point

The contract is total over the input space: each half of the `int` range has
exactly one allowed variant, and the payload must equal the input. An
implementation that accepts everything type-checks and runs, and the solver
refutes it.
