# Saturating Byte Brighten (Fill-the-Hole, Grader-Gap)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**Grading mode:** solver-catches (a withheld postcondition is injected at grade time; the visible test is non-adversarial by construction)

## What is provided

`.llmll/templates/byte-saturate/scaffold.ast.json` is a **pre-authored program**
with one body hole. Already written:

- the `brighten` signature — `brighten : bytes[8] int -> int`, taking a fixed
  8-byte buffer `b` and an index `i`;
- its input precondition: `i` is in bounds (`0 <= i < 8`);
- a `sample-buffer : -> bytes[8]` helper (an all-zero buffer) that the visible
  test reads through;
- one `check` (a property-based example test) exercising `brighten` on the
  sample buffer.

One body hole remains:

- `brighten-body` — the body of `brighten`.

**Your task is to FILL THE ONE HOLE, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold byte-saturate --output scaffold`, copy the
scaffolded program to `solution.ast.json`, and replace the `hole-named` body with
a correct expression. Do not change the signature, the precondition, the
`sample-buffer` helper, or the provided `check`, and do not add or remove
functions.

## What the body must do

`brighten` increases the brightness of the byte at index `i` by adding `50` to
it. A byte holds a value in `0..255`, so the result must **saturate** at the top
of that range: if adding `50` would exceed `255`, the result is `255`, not the
overflowed value. Otherwise the result is the byte plus `50`. The returned value
is always a valid byte in `0..255`.

You may assume the precondition holds on entry (`0 <= i < 8`). Keep the body
inside the bytes fragment (`bytes-get`) plus linear-integer arithmetic and an
`if` so it is eligible for body-faithful verification (LLMLL.md §5.3.3).

## Verification

The provided `check` asserts that `brighten` returns a non-negative value on the
all-zero sample buffer. A correct fill leaves it passing. (No postcondition
contract is required of you — write the body so that it behaves as specified
above for **every** admissible input, not only the sampled one.)

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), and passes `test` on the first attempt.
The harness grades whether the submitted body provably realizes the saturating
brighten behavior over the entire admissible input space, by a means external to
this problem statement.
