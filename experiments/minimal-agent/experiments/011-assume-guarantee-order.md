# Ordered Two-Step Account Processing (Fill-the-Hole, Grader-Gap)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**Grading mode:** solver-catches (a withheld precondition is injected at grade time; the visible test is non-adversarial by construction)

## What is provided

`.llmll/templates/assume-guarantee-order/scaffold.ast.json` is a **pre-authored
program** with one body hole. Two helper functions are already written, with
their contracts:

- `guard : map[int,int] int -> map[int,int]` — takes a balance map and an
  account `k`, and returns a map in which account `k` is present and its balance
  is **non-negative** (`post`: `(map-has result k)` and `(>= (map-get result k) 0)`).
- `consume : map[int,int] int -> map[int,int]` — performs the downstream step on
  account `k`. **`consume` requires that account `k`'s balance is non-negative on
  entry** (a valid, in-range balance); calling it on a possibly-negative balance
  is a contract violation.

One body hole remains:

- `process-body` — the body of `process : map[int,int] int -> map[int,int]`,
  which must prepare account `k` and then consume it.

**Your task is to FILL THE ONE HOLE, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold assume-guarantee-order --output scaffold`,
copy the scaffolded program to `solution.ast.json`, and replace the `hole-named`
body with a correct expression. Do not change the signatures, the preconditions,
or the provided `check`, and do not add or remove functions.

## What the body must do

`process` runs the two steps on account `k` **in the order their contracts
require.** `consume` may only be called when account `k`'s balance is
non-negative; `guard` is what establishes that. So `process` must **guard the
account first, then consume it**, threading `guard`'s result into `consume`.
Calling `consume` on the raw input (before guarding) is incorrect: the input
balance may be negative, which violates `consume`'s requirement.

You may assume `process`'s precondition holds on entry (account `k` is present).
Keep the body inside the map/call fragment (straight-line composition of the two
provided calls) so it is eligible for body-faithful verification (LLMLL.md
§5.3.4).

## Verification

The provided `check` asserts that `process` leaves the account present on a
concrete balance map. A correct fill leaves it passing. (No additional contract
is required of you — write the body so that it behaves as specified above for
**every** admissible input, not only the sampled one.)

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), and passes `test` on the first attempt.
The harness grades whether the submitted body provably realizes the ordered
processing over the entire admissible input space, by a means external to this
problem statement.
