# Task — fill ONE hole in an LLMLL program

`scaffold.llmll` in this directory is a complete LLMLL program with exactly one
hole marked `?hole`. Replace `?hole` with a correct implementation.

Hole: `transfer_helper`
  parameters in scope: amount: int, balance: int, debit: fn[2 args] -> int, transfer: fn[2 args] -> int
  precondition (assumed true): (and (>= balance 0) (>= amount 0))
  postcondition you MUST satisfy: (>= result 0)

Sibling functions you MAY call (already verified — use their contracts):
    debit(balance, amount) -> int   pre (and (>= balance amount) (>= amount 0))   post (and (= result (- balance amount)) (>= result 0))
    transfer(balance, amount) -> int   pre (and (>= balance 0) (>= amount 0))   post (>= result 0)

Rules:
- Do NOT change the contract (pre/post), the function signature, or any sibling
  definition. Change ONLY the `?hole` expression.
- The body must type-check and satisfy the postcondition.
- Write the COMPLETE resulting program (scaffold with `?hole` replaced) to a new
  file `solution.llmll` in this directory. Output nothing else.

You have the `llmll` compiler on PATH: `llmll verify solution.llmll` checks your
work (SAFE = the postcondition is proven).
