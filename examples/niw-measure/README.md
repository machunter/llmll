# niw-measure: a `string-length` measure inside a refinement predicate

`Word` is a string refined by a measure: `{s : string | string-length s > 0}`.
When a function takes a `Word`, that predicate is folded into its effective
precondition and assumed in the body VC. The measure emits as one uninterpreted
function carrying only its range axiom (`string-length s >= 0`), so the
obligation stays in QF-LIA + EUF and reaches body-faithful `verified` with no
structural string reasoning (`LLMLL.md` §3.4.4).

| File | What it demonstrates |
|---|---|
| `word-pad.llmll` | `min-pad [tok: Word]` returns `(string-length tok)` and proves `result >= 1`: SAFE |
| `word-pad-bad.llmll` | same body and post, but the parameter is a bare `string`: refuted, because the empty string has length 0 |
| `*.ast.json` | the same two programs in JSON-AST form |
| `EXPECTED_VERDICTS.json` | frozen verdicts and exit codes, checked by `make refute-crux-gate` |

## Commands (outputs reproduced on v0.26.5)

```text
$ llmll verify ./word-pad.llmll --strict-verified-core
   body-faithful: min-pad
   Running liquid-fixpoint ...
✅ ./word-pad.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./word-pad-bad.llmll --strict-verified-core
   body-faithful: min-pad
   Running liquid-fixpoint ...
error: body verification of 'min-pad' failed — implementation does not satisfy postcondition (constraint #0)
ERROR: --strict-verified-core: refuted: min-pad
```

Exit 0 and exit 1. (The `.fq written to` and `.verified.json written to` lines
are omitted.)

## The discriminative point

The two files differ in one token: the parameter type `Word` versus `string`.
The body and the postcondition are identical. The verdict flips because the
measure predicate on the parameter type is the only fact that rules out a
length-0 input, so the proof depends on the refinement and not on the body.
