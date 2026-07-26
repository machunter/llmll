# Stage M: fill one hole

You are one of several agents working concurrently on one module tree. You can see **this
checkout brief and nothing else**: no reference solution, no other agent's attempt, no hints
beyond the contract. That isolation is the experiment, so do not go looking for the rest of the
tree, and do not search the filesystem for an implementation.

## Your task

Write a body for the hole `{{hole}}` that satisfies the contract in the brief below.

Write it to **`body.json`** in your working directory, as a single JSON-AST **expression node**
(just the body, not the whole program, not a patch). The driver wraps it in the JSON-Patch and
applies it under your checkout token.

Example of the expected file, for a body `(if (> x 0) x 0)`:

```json
{"kind": "if",
 "cond": {"kind": "app", "fn": ">", "args": [{"kind": "var", "name": "x"},
                                             {"kind": "lit-int", "value": 0}]},
 "then_branch": {"kind": "var", "name": "x"},
 "else_branch": {"kind": "lit-int", "value": 0}}
```

Note `then_branch` / `else_branch`, not `then` / `else`. **`llmll-ast.schema.json` in
your directory is the authority on every node's shape — check it rather than trusting
this example.** An `if` written with the wrong key names type-checks as LLMLL source but
is rejected when the JSON is applied.

The brief's `postcondition_goal` is what you must satisfy, `expected_return_type` is the type
you must return, `in_scope` lists every name you may use, and `type_definitions` gives each sum
type's constructors with their payloads.

## The acceptance bar

Your fill is accepted only when all three hold:

1. `verify` reports **SAFE**
2. the filled function is **body-faithful** (not `body-fallback`)
3. it is not flagged `termination_unverified`

**Check your own work before submitting.** Your directory contains `scratch.llmll`: a private
copy of the module with every hole, including yours, still unfilled. It is pristine, so it
contains no other agent's work, and nothing you do to it affects anyone else. Replace your
function's `?impl` there with your candidate body in LLMLL surface syntax and run:

```
{{llmll}} verify scratch.llmll
```

Your function must appear in the `body-faithful:` list and the module must report SAFE. Do NOT
gate on `--strict-verified-core` here: every hole other than yours is still empty, so that flag
will always fail during a wave and tells you nothing about your own fill.

Iterate on `scratch.llmll` as much as you like. When you are satisfied, write the body to
`body.json`. Do not modify any file outside your own directory.

## Language constraints that will otherwise cost you an attempt

- **A nullary constructor in a `match` arm is written `((Idle) ...)`, never `(Idle ...)`.** The
  bare form is a binder, not a pattern, and is rejected.
- **Do not name a binder after any constructor** in the module.
- **Matching on a payload-bearing ADT parameter loses body-faithfulness.** Discriminate on
  nullary tags and integer scalars; construct payload-bearing values freely.
- **Import no ordering the specification does not define.** If the brief's contract reasons
  about block or sequence numbers by equality and successor only, do not introduce `<` or `>`
  on them.

## If you cannot do it

Say so, and write no `body.json`. A hole that cannot be filled within its budget is a
**finding**: it gets routed to the compiler team or back to the clause inventory as a scoping
error. It is not an occasion for anyone to give you a hint, and it is not an occasion for you to
weaken the contract.

**Do not edit any `:source`-bearing clause.** Those are frozen. If you believe the contract is
wrong, report that; do not fix it.

If the contract is too coarse to satisfy directly, you may decompose the hole into
sub-functions with contracts you write yourself. Spawned sub-contracts are additive and carry
**no** `:source`: provenance authorship belongs to the extraction role, not to you.

## Compiler output from your previous attempt

{{errors}}

## Your checkout brief

```json
{{brief}}
```
