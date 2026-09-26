# withdraw-demo: the agent repair loop, from typed hole to verified

The repair loop an agent goes through: find a typed hole, `checkout` it (a lock
plus a brief that carries the contract, not the answer), submit a `patch`, have a
wrong fill rejected at submission with the program left unchanged, submit a
correct fill, and re-verify. Around that loop the directory adds the two-axis
trust report, composition through a call edge, the discriminative-power (CDP)
axis, and a replayable proof artifact.

| File | What it is |
|---|---|
| `withdraw.llmll` / `withdraw.ast.json` | one function with a contract and a typed hole; the input to `demo.sh` |
| `withdraw-patch-wrong.json` / `withdraw-patch-correct.json` | scripted stand-ins for two agent fills (`balance + amount`, `balance - amount`) |
| `demo.sh` | the one-hole loop end to end (the README's protocol GIF) |
| `demo.llmll` / `demo.ast.json` | the four-function program the runbook fills: `withdraw`, `double`, `maxi`, `withdraw-outcome` |
| `compose.llmll` / `compose-bad.llmll` | `guarded-withdraw` over a `withdraw` call edge; the bad twin drops the guard |
| `return-refine.llmll` / `return-refine-bad.llmll` | a refined return type used as the contract |
| `withdraw-outcome-bad.llmll` | a `Result` fill with no error branch; used for the forged-artifact beat |
| `audit.llmll` / `audit.ast.json` | a thin shell module used only for the authority axis (`effect_summary`) |

Two documents go deeper. [`DEMO-RUNBOOK.md`](DEMO-RUNBOOK.md) is the capture
script, step by step, including the swarm reservation model, stale-token resync
and the proof-artifact capstone. [`DemoPost.md`](DemoPost.md) is the same loop as
a walkthrough for developers.

## Run the loop

```bash
bash examples/withdraw-demo/demo.sh          # tap Enter to run each command
bash examples/withdraw-demo/demo.sh --auto   # unattended
```

It needs `llmll`, `fixpoint`, `z3` and `jq` on `PATH`, and works on a temp copy,
so it never rewrites the tracked files. On v0.26.5 the wrong patch returns
`"result": "PatchVerifyError"` and `cmp` confirms the program is unchanged; the
correct patch returns `PatchSuccess`, and the final `verify --strict-verify`
prints `withdraw: pre: asserted | post: verified (liquid-fixpoint)`. The
script exits 0.

## Verdicts on the committed files (reproduced on v0.26.5)

Run from this directory on a copy (`verify` writes `.verified.json` sidecars).
Output is trimmed to the verdict lines.

```text
$ llmll verify ./withdraw.llmll
⚠️  ./withdraw.llmll — SAFE (liquid-fixpoint), partial: 0 of 1 contracted functions proved; 1 assumed, not proved: withdraw

$ llmll verify ./demo.llmll
⚠️  ./demo.llmll — SAFE (liquid-fixpoint), partial: 1 of 4 contracted functions proved; 3 assumed, not proved: withdraw, maxi, withdraw-outcome

$ llmll verify ./compose.llmll --strict-verified-core
✅ ./compose.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./compose-bad.llmll
error: call-site precondition of 'withdraw' not satisfied in 'guarded-withdraw' — caller does not prove callee's precondition (constraint #2)

$ llmll verify ./return-refine.llmll
✅ ./return-refine.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./return-refine-bad.llmll --strict-verified-core
error: body verification of 'saturate' failed — implementation does not satisfy postcondition (constraint #0)
ERROR: --strict-verified-core: refuted: saturate

$ llmll verify ./audit.llmll
⚠️  ./audit.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```

`withdraw.llmll` and `demo.llmll` are the holed starting points, so they print
partial by design; the proved count rises as the runbook fills the holes.
`audit.llmll` has no postconditions by design. The two bad twins exit 1;
everything else exits 0. This directory is not gated by `make refute-crux-gate`.
