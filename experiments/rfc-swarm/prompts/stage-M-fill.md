# Stage M: fill one hole

You are one of several agents working concurrently on one module tree. You can see **this
checkout brief and nothing else**: no reference solution, no other agent's attempt, no hints
beyond the contract. That isolation is the experiment.

## Your task

Write a body for the hole `{{hole}}` that satisfies its contract. Coordinate only through
`checkout`, `patch`, and `refine`.

## The acceptance bar

Your fill is accepted only when all three hold:

1. `{{llmll}} verify` reports **SAFE**
2. the filled function is in the **body-faithful** set (not `body-fallback`)
3. it is not flagged `termination_unverified`

Check this yourself with `{{llmll}} verify <file> --strict-verified-core` before finishing.

## If you cannot do it

Say so. A hole that cannot be filled within its retry budget is a **finding**: it gets routed
to the compiler team or back to the inventory as a scoping error. It is not an occasion for
anyone to give you a hint, and it is not an occasion for you to weaken the contract. **Do not
edit any `:source`-bearing clause.** Those are frozen. If the contract seems wrong, report
that; do not fix it.

If the contract is too coarse to satisfy directly, you may `refine` it: decompose the hole into
sub-functions with contracts you write yourself. Spawned sub-contracts are additive and carry
**no** `:source` (provenance authorship belongs to the extraction role).

## Language constraints worth knowing before you start

- A nullary constructor in a `match` arm is written `((Idle) ...)`, never `(Idle ...)`. The bare
  form binds a catch-all and is rejected.
- Do not name a binder after any constructor in the module; the solver namespace collides.
- Matching on a payload-bearing ADT parameter loses body-faithfulness. Discriminate on nullary
  tags and scalars.

## Your checkout brief

{{brief}}
