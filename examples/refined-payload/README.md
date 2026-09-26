# refined-payload: a matched payload carries its declared refinement

`Pos` is `{n : int | n > 0}`. A function that matches a `Result[Pos, string]`
knows, inside the `Success` arm, that its payload is positive (elimination). A
caller that passes a `Result` to such a function must prove the payload
refinement at the call site (introduction). Both directions are checked, and
the matched refinement has exactly its declared strength, no more.

| File | What it demonstrates |
|---|---|
| `refined-payload.llmll` | `first-positive` uses the `Pos` payload to prove `result >= 1`; `forward` passes its own `Result[Pos, string]` through (reflexive subtyping, no obligation): SAFE |
| `refined-payload-bad-elim.llmll` | same match, but the post claims `result >= 2`; `Pos` only gives `n >= 1`: refuted |
| `refined-payload-bad-forward.llmll` | `forward-bad` passes a `Result[int, string]` to a `Result[Pos, string]` parameter: the payload-subtyping obligation is refused at the call site |
| `*.ast.json` | the same three programs in JSON-AST form |

## Commands (outputs reproduced on v0.26.5)

```text
$ llmll verify ./refined-payload.llmll --strict-verified-core
   body-faithful: first-positive, forward
   Running liquid-fixpoint ...
✅ ./refined-payload.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./refined-payload-bad-elim.llmll --strict-verified-core
   body-faithful: first-positive
   Running liquid-fixpoint ...
error: body verification of 'first-positive' failed (then-branch does not satisfy postcondition) (constraint #0)
ERROR: --strict-verified-core: refuted: first-positive

$ llmll verify ./refined-payload-bad-forward.llmll
   body-faithful: first-positive, forward-bad
   Running liquid-fixpoint ...
error: payload subtyping for call to 'first-positive' not satisfied in 'forward-bad' — argument's payload does not satisfy the callee param's declared refinement (COMP-4 b) (constraint #3)
```

Exit 0, exit 1, exit 1. (The `.fq written to` and `.verified.json written to`
lines are omitted.)

## The discriminative point

The two bad twins fail on different channels. `bad-elim` asks the payload for
more than `Pos` promises, and fails on the body postcondition. `bad-forward`
has a correct body but a caller that cannot establish `n > 0` for the payload
it forwards, and fails on the payload-subtyping obligation. `int` is not a
subtype of `Pos`, so a weaker `Result` cannot reach a function that relies on
the refinement.

This family is not in `make refute-crux-gate`. The unit tests in
`compiler/test/Spec.hs` (`COMP-4 (b): refined-payload elimination + subtyping`)
cover the same behavior.
