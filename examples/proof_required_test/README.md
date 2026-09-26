# proof_required_test: pipeline fixture for `?proof-required` holes

**A test input, not a demo.** `proof_required_test.llmll` is a small console
program whose `safe-div` function has a contract (`pre (> d 0)`,
`post (>= result 0)`) and a `?proof-required` body hole.
`scripts/tests/test_console_init_1.py` pins it by path, and a comment in the
Haskell code generator names it as one of the console programs with no
`:done?`. Update those references if you rename or reshape it.

## What it prints (reproduced on v0.26.5)

```text
$ llmll --json holes proof_required_test.llmll
[{"agent":null,"complexity":":unknown","inferred-type":null,"kind":"proof-required","message":"hole: ?proof-required(manual)","module-path":"def-shell safe-div","pointer":"/statements/1/body","status":"non-blocking"}]

$ llmll verify ./proof_required_test.llmll
   body-fallback: safe-div
   Running liquid-fixpoint ...
⚠️  ./proof_required_test.llmll — SAFE (liquid-fixpoint), partial: 0 of 1 contracted functions proved; 1 assumed, not proved: safe-div
   (--strict-verified-core fails on assumed functions)
```

Both exit 0.

## The header procedure is stale

The comment at the top of the file describes a three-step Leanstral check
(`--leanstral-mock` finds a proof, then a second run reads it from the cache).
Step 1 still holds. Steps 2 and 3 no longer reproduce: `--leanstral-mock` now
fails closed on this program, because `safe-div` declares no return type.

```text
$ llmll verify --leanstral-mock ./proof_required_test.llmll
   ...
   1 obligation(s) for Leanstral.
   safe-div: unsupported (return type required to bind `result`)
```

Exit 0, no proof recorded. For a working Lean-tier example, see
[`../leanstral-demo/`](../leanstral-demo/).
