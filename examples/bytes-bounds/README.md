# bytes-bounds — index-in-bounds proven on the buffer access itself

The LEVER-A1 witness (data-scope Lever A, [`docs/design/data-scope-lever-a-arrays-proposal.md`](../../docs/design/data-scope-lever-a-arrays-proposal.md)):
`bytes[n]` reads and writes carry PROVE-polarity obligations — index-in-bounds
and byte value-range — discharged by the solver at the call site. The bounds
error is caught **on the buffer access**, not via a length-proxy contract.

| File | What it demonstrates |
|---|---|
| `read-at.llmll` | correct bound `(< i 64)`: SAFE, including under `--strict-verified-core` |
| `read-at-off-by-one.llmll` | the same function with `(<= i 64)` — the Heartbleed-class off-by-one — REFUTED at the `bytes-get` call site |
| `write-overflow.llmll` | index proven but value admits 300 > 255 — REFUTED at the `bytes-set` call site (a byte buffer cannot silently truncate) |

## Commands (outputs reproduced against the shipped binary)

**Correct bound — proven.**
```bash
llmll verify ./read-at.llmll --strict-verified-core
```
```
   body-faithful: read-at
   call-pre obligations: read-at
   Running liquid-fixpoint ...
✅ ./read-at.llmll — SAFE (liquid-fixpoint)
```
Exit 0.

**Off-by-one — refuted, localized to the access.**
```bash
llmll verify ./read-at-off-by-one.llmll
```
```
error: call-site precondition of 'bytes-get' not satisfied in 'read-at' — caller does not prove callee's precondition (constraint #1)
```
Exit 1. The precondition admits `i = 64`, one past the end of `bytes[64]`;
nothing proves `bytes-get`'s `i < bytes-length b`, so the solver refutes the
call — the exact single-character mistake (`<=` for `<`) behind a
Heartbleed-class overread.

**Out-of-range write — refuted.**
```bash
llmll verify ./write-overflow.llmll
```
```
error: call-site precondition of 'bytes-set' not satisfied in 'write-at' — caller does not prove callee's precondition (constraint #1)
```
Exit 1. The index is proven but the admitted value range reaches 300;
`bytes-set` requires `0 ≤ v ≤ 255`.

## Scope caveat (stated up front)

The **verify surface is complete today**: verdicts, refutations, localization,
and `--strict-verified-core` admission all work as shown. The **reporting
surface catches up at stage A3** of the arrays track: until then, a contract
mentioning bytes ops still classifies `non_qf_lia` in `--obligation-report`
(Advisory tier) even though the verifier discharges it body-faithful, and
checkout briefs do not yet carry array vocabulary. This example is the
acceptance fixture for that A3 flip: when A3 lands, these contracts must
classify in-fragment with no verdict change.
