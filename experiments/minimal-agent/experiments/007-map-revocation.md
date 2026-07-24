# Token Revocation in a Token Map (Fill-the-Hole, Grader-Gap)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**Grading mode:** solver-catches (a withheld postcondition is injected at grade time; the visible test is non-adversarial by construction)

## What is provided

`.llmll/templates/map-revocation/scaffold.ast.json` is a **pre-authored
program** with one body hole. Already written:

- the `revoke` signature — `revoke : map[int,string] int -> map[int,string]`,
  taking a token map `tokens` (token id → status string) and a token id `tid`;
- its input precondition: `tid` is a key of `tokens` (`(map-has tokens tid)`);
- one `check` (a property-based example test) exercising `revoke` on a concrete
  token map.

One body hole remains:

- `revoke-body` — the body of `revoke`.

**Your task is to FILL THE ONE HOLE, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold map-revocation --output scaffold` (the
template exists), copy the scaffolded program to `solution.ast.json`, and
replace the `hole-named` body with a correct expression. Do not change the
signature, the precondition, or the provided `check`, and do not add or remove
functions.

## What the body must do

`revoke` records that a token has been revoked. It returns a token map identical
to `tokens` except that the given token id `tid` now maps to the status marker
string `"revoked"`. Every other key keeps its existing value; `tid` remains
present. You may assume the precondition holds on entry (`tid` is already a key
of `tokens`).

Keep the body inside the map fragment (`map-put` / `map-get` / `map-has` /
`map-empty`) so it is eligible for body-faithful verification (LLMLL.md §5.3.3);
no auxiliary data structures are needed.

## Verification

The provided `check` asserts that `revoke` leaves the token id present on a
concrete token map. A correct fill leaves it passing. (No postcondition contract
is required of you — write the body so that it behaves as specified above for
**every** admissible input, not only the sampled one.)

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), and passes `test` on the first attempt.
The harness grades whether the submitted body provably realizes the revocation
behavior over the entire admissible input space, by a means external to this
problem statement.
