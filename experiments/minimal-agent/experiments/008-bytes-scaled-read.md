# Byte Read From a Fixed Buffer (Fill-the-Hole, Grader-Gap)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**Grading mode:** solver-catches (a withheld postcondition is injected at grade time; the visible test is non-adversarial by construction)

## What is provided

`.llmll/templates/bytes-scaled-read/scaffold.ast.json` is a **pre-authored
program** with one body hole. Already written:

- the `read-scaled` signature — `read-scaled : bytes[8] int -> int`, taking a
  fixed 8-byte buffer `b` and an index `i`;
- its input precondition: `i` is in bounds (`0 <= i < 8`);
- a `sample-buffer : -> bytes[8]` helper (an all-zero buffer) that the visible
  test reads through;
- one `check` (a property-based example test) exercising `read-scaled` on the
  sample buffer.

One body hole remains:

- `read-scaled-body` — the body of `read-scaled`.

**Your task is to FILL THE ONE HOLE, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold bytes-scaled-read --output scaffold` (the
template exists), copy the scaffolded program to `solution.ast.json`, and
replace the `hole-named` body with a correct expression. Do not change the
signature, the precondition, the `sample-buffer` helper, or the provided
`check`, and do not add or remove functions.

## What the body must do

`read-scaled` returns the byte stored at index `i` of the buffer, as an `int`.
A byte is a value in the range `0..255`, and the returned value must be that
byte — no offset, no scaling that leaves the byte range. You may assume the
precondition holds on entry (`0 <= i < 8`).

Keep the body inside the bytes fragment (`bytes-get` / `bytes-length`) plus
linear-integer arithmetic so it is eligible for body-faithful verification
(LLMLL.md §5.3.3).

## Verification

The provided `check` asserts that `read-scaled` returns a non-negative value on
the all-zero sample buffer. A correct fill leaves it passing. (No postcondition
contract is required of you — write the body so that it behaves as specified
above for **every** admissible input, not only the sampled one.)

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), and passes `test` on the first attempt.
The harness grades whether the submitted body provably realizes the byte-read
behavior over the entire admissible input space, by a means external to this
problem statement.
