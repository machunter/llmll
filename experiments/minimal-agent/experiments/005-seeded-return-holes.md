# Seeded Return-Type Holes (Fill-the-Hole)

**Difficulty:** ★★☆
**Regime:** fill-the-hole (NOT blank-slate authoring)
**v0.13 features exercised:** DEF-RET `expected_return_type` brief surface, a refinement-aliased return, a two-channel (success / error) return, hole-filling against a pre-authored scaffold

## What is provided

`.llmll/templates/seeded-return-holes/scaffold.ast.json` is a **pre-authored
program** with everything written except two function bodies. The supporting
value types (`Account`, `LookupError`) and the `def-interface AccountStore` are
already in place, along with the two function signatures (parameter types only —
the seed leaves each function's **return type undeclared**, and it is your job to
determine and declare it). Two body holes remain:

- `clamp-to-word-body` — the body of `clamp-to-word`, a `def` taking one `int`
  parameter `n`.
- `find-account-body` — the body of `find-account`, a `def-shell` taking one
  `string` parameter `account-id`.

**Your task is to FILL THE TWO HOLES, not to author a new program.** Start from
the scaffold: run `llmll hub scaffold seeded-return-holes --output scaffold`
(the template exists), copy the scaffolded program to `solution.ast.json`, and
replace the two `hole-named` bodies with correct expressions. Do not redefine the
seeded value types or the interface, and do not add or remove functions. You
**must** declare each function's return type (omitted in the seed) and, where the
correct return type is a refinement alias the seed does not provide, you may add
that `type` declaration.

## What each body must do

1. `clamp-to-word`: clamp the input `n` into the valid output range — values
   below the floor map to the floor, values above the ceiling map to the ceiling,
   and in-range values pass through unchanged. The output must satisfy the
   declared return type of `clamp-to-word`. The return type is **not** plain
   `int`; it is the refinement alias the signature requires, and your body must
   produce a value that provably inhabits it.

2. `find-account`: parse and validate `account-id`, returning a success value on
   a well-formed id and an error value on a malformed or absent one. The return
   type is **not** a bare value and **not** a bare `string`; it is the two-channel
   (success / error) shape the signature requires, and you must construct both
   channels with the right constructors.

The two return types are deliberately **non-obvious from the parameter list
alone** — `clamp-to-word` takes an `int` but does not return a plain `int`, and
`find-account` takes a `string` but does not return a bare value. Determine each
return type from the available signals, declare it on the `def` / `def-shell`
(`return_type`), and write a body that the verifier accepts against it.

## Verification

3. Include a `check` block asserting a pure property of `clamp-to-word` on a
   concrete in-range input (e.g. that clamping a known in-range value returns that
   value), without delegating.
4. Include a `post` contract on `clamp-to-word` stating the result is within the
   valid range (`(and (>= result 0) (<= result 65535))`).

## Acceptance

A correct submission parses, type-checks under `--strict`, leaves **no remaining
holes** (`holes --deps` reports none), passes `test`, and `verify` accepts both
bodies against their declared return types on the first attempt. The
refinement-aliased return on `clamp-to-word` carries the §3.4.1 return obligation;
a correct body discharges it.
