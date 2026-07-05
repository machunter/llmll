# Task — fill ONE hole in an LLMLL program

`scaffold.llmll` in this directory is a complete LLMLL program with exactly one
hole marked `?hole`. Replace `?hole` with a correct implementation.

Hole: `clamp_tight`
  parameters in scope: dec: fn[1 args] -> int, n: int
  precondition (assumed true): None
  postcondition you MUST satisfy: (= result (- n 1))

Sibling functions you MAY call (already verified — use their contracts):
    dec(n) -> int   pre None   post (= result (- n 1))

Rules:
- Do NOT change the contract (pre/post), the function signature, or any sibling
  definition. Change ONLY the `?hole` expression.
- The body must type-check and satisfy the postcondition.
- Write the COMPLETE resulting program (scaffold with `?hole` replaced) to a new
  file `solution.llmll` in this directory. Output nothing else.

You have the `llmll` compiler on PATH: `llmll verify solution.llmll` checks your
work (SAFE = the postcondition is proven).
