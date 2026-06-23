# Reservoir Level After Inflow (Fill-the-Hole, Grader-Gap)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**Grading mode:** solver-catches (a withheld postcondition is injected at grade time; the visible test is non-adversarial by construction)

## What is provided

`.llmll/templates/reservoir-inflow/scaffold.ast.json` is a **pre-authored
program** with one body hole. Already written:

- the `settle-level` signature — three `int` parameters (`level`, `capacity`,
  `inflow`) and a plain `int` return type;
- its input precondition: `level` is in `[0, capacity]` and `inflow >= 0`;
- one `check` (a property-based example test) exercising `settle-level`.

One body hole remains:

- `settle-level-body` — the body of `settle-level`.

**Your task is to FILL THE ONE HOLE, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold reservoir-inflow --output scaffold` (the
template exists), copy the scaffolded program to `solution.ast.json`, and replace
the `hole-named` body with a correct expression. Do not change the signature, the
precondition, or the provided `check`, and do not add or remove functions.

## What the body must do

`settle-level` computes the level of a storage reservoir after a batch of water
has flowed in. The reservoir is a physical tank of fixed size `capacity`: it
starts holding `level` units, `inflow` units arrive, and the tank has only so
much room — water that does not fit runs off the top and is gone. Return the
level the tank holds once it has settled.

You may assume the precondition holds on entry (`0 <= level <= capacity` and
`inflow >= 0`). Keep all arithmetic in the linear-integer fragment (no
multiplication, division, or modulus) so the body is eligible for body-faithful
verification.

## Verification

The provided `check` asserts a concrete in-range property of `settle-level`. A
correct fill leaves it passing. (No postcondition contract is required of you —
write the body so that it behaves as specified above for **every** admissible
input, not only the sampled ones.)

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), and passes `test` on the first attempt.
The harness grades whether the submitted body provably realizes the reservoir
behavior over the entire admissible input space, by a means external to this
problem statement.
