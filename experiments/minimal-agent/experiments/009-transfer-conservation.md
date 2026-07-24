# Balance Transfer Between Two Accounts (Fill-the-Hole, Grader-Gap)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**Grading mode:** solver-catches (a withheld postcondition is injected at grade time; the visible test is non-adversarial by construction)

## What is provided

`.llmll/templates/transfer-conservation/scaffold.ast.json` is a **pre-authored
program** with one body hole. Already written:

- the `transfer` signature — `transfer : map[int,int] int int int -> map[int,int]`,
  taking a balance map `bal` (account id → balance), a source account `a`, a
  destination account `b`, and an amount `amt`;
- its input precondition: both accounts exist and differ
  (`(map-has bal a)`, `(map-has bal b)`, `a != b`);
- one `check` (a property-based example test) exercising `transfer` on a
  concrete balance map.

One body hole remains:

- `transfer-body` — the body of `transfer`.

**Your task is to FILL THE ONE HOLE, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold transfer-conservation --output scaffold`,
copy the scaffolded program to `solution.ast.json`, and replace the `hole-named`
body with a correct expression. Do not change the signature, the precondition,
or the provided `check`, and do not add or remove functions.

## What the body must do

`transfer` moves `amt` units of balance from account `a` to account `b`. It
returns a balance map in which account `a` has been **debited** by `amt` and
account `b` has been **credited** by `amt`; every other account is unchanged,
and both `a` and `b` remain present. Money is neither created nor destroyed by a
transfer.

You may assume the precondition holds on entry. Keep the body inside the map
fragment (`map-put` / `map-get`) plus linear-integer arithmetic, straight-line
(no `if`), so it is eligible for body-faithful verification (LLMLL.md §5.3.3).

## Verification

The provided `check` asserts that `transfer` leaves an account present on a
concrete balance map. A correct fill leaves it passing. (No postcondition
contract is required of you — write the body so that it behaves as specified
above for **every** admissible input, not only the sampled one.)

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), and passes `test` on the first attempt.
The harness grades whether the submitted body provably realizes the transfer
behavior over the entire admissible input space, by a means external to this
problem statement.
