# bytes-bounds — index-in-bounds proven on the buffer access itself

The LEVER-A1 witness (data-scope Lever A, [`docs/design/data-scope-lever-a-arrays-proposal.md`](../../docs/archive/shipped-design-specs/data-scope-lever-a-arrays-proposal.md)):
`bytes[n]` reads and writes carry PROVE-polarity obligations — index-in-bounds
and byte value-range — discharged by the solver at the call site. The bounds
error is caught **on the buffer access**, not via a length-proxy contract.

| File | What it demonstrates |
|---|---|
| `read-at.llmll` | correct bound `(< i 64)`: SAFE, including under `--strict-verified-core` |
| `read-at-off-by-one.llmll` | the same function with `(<= i 64)` — the Heartbleed-class off-by-one — REFUTED at the `bytes-get` call site |
| `write-overflow.llmll` | index proven but value admits 300 > 255 — REFUTED at the `bytes-set` call site (a byte buffer cannot silently truncate) |
| `zero-buffer.llmll` | the constructor side: `(bytes-zero)` under a declared `-> bytes[32]` return proves its own length post — SAFE, including under `--strict-verified-core` |
| `relay-buffer.llmll` | the composition side: a length crossing a call boundary, from a **contract-free** callee to two callers that re-export and consume it — SAFE, including under `--strict-verified-core` |
| `relay-overflow.llmll` | the same relayed `bytes[32]` read at index 40 — REFUTED at the `bytes-get` call site, which is what shows the assumed length is usable rather than decorative |

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

**Fresh buffer — its length is proven, not asserted.**
```bash
llmll verify ./zero-buffer.llmll --strict-verified-core
```
```
   body-faithful: make-buffer
   Running liquid-fixpoint ...
✅ ./zero-buffer.llmll — SAFE (liquid-fixpoint)
```
Exit 0. The other three fixtures take their buffer as a parameter; this one
constructs it. `(bytes-zero)` is legal only as the whole body of a def with a
literal `-> bytes[n]` return, and the emitter reads `32` off that same
annotation to give the constructor its length axiom `bytesLen(r) = 32`. The
length comes from the declared return, never from the post: rewriting the post
to `(= (bytes-length result) 16)` refutes the program rather than verifying it.

**Relayed buffer — the length crosses a call.**
```bash
llmll verify ./relay-buffer.llmll --strict-verified-core
```
```
   body-faithful: fresh32, relay, head-of-relay
   call-pre obligations: head-of-relay
   Running liquid-fixpoint ...
✅ ./relay-buffer.llmll — SAFE (liquid-fixpoint)
```
Exit 0, and all three posts read `verified (liquid-fixpoint)` in
`--trust-report`. `fresh32` carries no contract at all: its declared
`-> bytes[32]` return is the only place the length is written down, and that
annotation becomes its effective postcondition. So `fresh32` proves the length
from the constructor axiom, `relay` re-exports it, and `head-of-relay`
discharges `bytes-get`'s index-in-bounds obligation against a length it learned
from the callee's post and nowhere else.

**Relayed buffer, read out of range — refuted.**
```bash
llmll verify ./relay-overflow.llmll
```
```
error: call-site precondition of 'bytes-get' not satisfied in 'head-out-of-range' — caller does not prove callee's precondition (constraint #2)
```
Exit 1. This is the discriminative negative for the pair: an assumed length that
cannot refute would be decorative.

## Scope note

Both surfaces are complete: verdicts, refutations, localization, and
`--strict-verified-core` admission as shown, and — since the arrays track's
stage A3 — an exactly-reflectable bytes contract classifies `qf_lia`
in `--obligation-report` and checkout briefs list the bytes ops (with their
PROVE preconditions) for holes with a bytes type in scope. This example served
as A3's acceptance fixture and now stands as its regression witness: these
contracts classify in-fragment, and the verdicts above must never move.
