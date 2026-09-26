# tcp_rfc793: an RFC 793 state machine proved total

`step [state: ConnState, event: Event] -> StepOutcome` encodes the connection
setup subset of the RFC 793 TCP state machine (5 states, 6 events). States and
events are enum sum types, and the result is a sum type with payloads,
`Next(tag)` or `Rejected(code)`. The postcondition, written from RFC 793 §3.2,
states the full transition table: each of the five legal pairs maps to its
specific `Next(tag)`, and every other pair maps to `Rejected`. The solver proves
the body meets it, so `step` cannot reach `Established` without the handshake.

| File | What it demonstrates |
|---|---|
| `step.llmll` | full transition-table post, correct body: SAFE |
| `step-bad.llmll` | `Closed + ActiveOpen` returns `(Next 4)` (ESTABLISHED) instead of `(Next 2)` (SYN_SENT): refuted |
| `step-weak.llmll` | a post that omits the "every illegal pair is `Rejected`" clause, with a body that adds a `Listen + RcvAck` edge to ESTABLISHED: the bug survives (SAFE) |
| `*.ast.json` | JSON-AST forms of the same programs |

[`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) is the proved-versus-trusted
matrix (proven 1, asserted 0). [`DEMO-RUNBOOK.md`](DEMO-RUNBOOK.md) walks the
beats with narration.

## Commands (outputs reproduced on v0.26.5)

Run from this directory, with `fixpoint` and `z3` on `PATH`. Output is trimmed
to the verdict lines.

```text
$ llmll verify ./step.llmll --strict-verified-core
✅ ./step.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./step-bad.llmll --strict-verified-core
error: body verification of 'step' failed (else-branch does not satisfy postcondition) (constraint #1)
ERROR: --strict-verified-core: refuted: step

$ llmll verify ./step-weak.llmll --strict-verified-core
✅ ./step-weak.llmll — SAFE (liquid-fixpoint)
```

`step` and `step-weak` exit 0; `step-bad` exits 1. These verdicts are frozen in
[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) and checked by
`make refute-crux-gate`.

## The discriminative point

`step-bad` shows the contract catching a skipped handshake. `step-weak` shows the
limit: a proof is only as strong as the contract. With the totality clause
missing, a wrong edge verifies. The fix is to add the clause from the RFC, which
gives `step.llmll`'s post, and that post refutes the edge. Noticing the weak
contract is a human step; `--weakness-check` and `--cdp` do not flag it for this
function shape.
