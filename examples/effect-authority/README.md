# effect-authority: which capabilities a function can reach

`llmll verify --obligation-report` includes a per-function `effect_summary`: a
sound over-approximation of the capabilities a function may exercise through
its call graph. It is informational. It does not enter the verified/asserted
trust lattice, and neither file here carries a postcondition, so plain `verify`
reports `nothing proved` for both.

| File | What it demonstrates |
|---|---|
| `bounded.llmll` | `log-amount` calls `wasi.io.stdout` and nothing else; its summary is `["stdout"]` |
| `unbounded.llmll` | `settle-payment` is a `?delegate` hole filled out of process; the summary cannot bound it and reports `"unbounded"` |
| `*.ast.json` | the same two programs in JSON-AST form |

## Commands (outputs reproduced on v0.26.5)

The report is one JSON object on the last line of stdout:

```text
$ llmll verify ./bounded.llmll --obligation-report | tail -1 | jq -c .effect_summary
[{"effects":["stdout"],"function":"log-amount"}]

$ llmll verify ./unbounded.llmll --obligation-report | tail -1 | jq -c .effect_summary
[{"effects":"unbounded","function":"settle-payment"}]
```

Both exit 0. Plain `verify` on either file prints:

```text
⚠️  ./bounded.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```

## The discriminative point

A function whose calls are all resolved gets a concrete, minimal capability
set. An opaque boundary (a delegate hole, whose code the compiler never sees)
gets the top element, `"unbounded"`, meaning it may exercise any capability.
A caller can read that difference from the report without running either
function.
