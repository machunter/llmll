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

`settle-level` computes the new level of a fixed-capacity reservoir after an
inflow.

- Normally the new level is the current `level` plus the `inflow`.
- The reservoir has a hard maximum, `capacity`: the level **can never exceed
  `capacity`**. If adding the inflow would push the level above `capacity`, the
  reservoir fills to exactly `capacity` and the excess spills (is discarded).
- The level is never reduced by an inflow.

You may assume the precondition holds on entry (`0 <= level <= capacity` and
`inflow >= 0`). The body must keep all arithmetic in the linear-integer fragment
(no multiplication, division, or modulus) so it is eligible for body-faithful
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
