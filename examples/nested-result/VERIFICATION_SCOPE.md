# nested-result — Verification Scope

**Claim.** A `Result`-typed **variable** match verifies body-faithfully even when the
match is **nested under a `let`** (not the top-level body) — the COMP-3b-general
feature (v0.13.6). The return refinement `Balance = {b : int | b >= 0}` is the
*entire* specification, discharged **per arm** by the solver, through the `let`.

| # | Function | Types | Spec | Body | Verdict | Basis |
|---|----------|-------|------|------|---------|-------|
| 1 | `safe-withdraw` | `Result[int, string]` scrutinee; `Balance = {b:int \| b>=0}` return | return refinement (no hand-written post) | `let` whose body is a two-arm `match` on the `Result`-typed `attempt` | **verified** (body-faithful, liquid-fixpoint) | per-arm VC, QF-LIA |

**Proven: 1 · Asserted: 0.**

## Why it reaches `verified` (fragment-fit)

- The scrutinee `attempt` is a **`Result`-typed variable**; the match is **nested
  inside the `let` body**, not at the top level. Before v0.13.6 a nested
  Result-variable match fell back to `asserted`; COMP-3b-general makes it
  body-faithful at **any** nesting depth (under `let`/`if`, param- or let-bound).
- The let-bound `guard = (if (>= floor 0) floor 0)` is provably `>= 0`, so each arm
  establishes `b >= 0`: the `Success` arm returns `n` when `n >= guard` (hence
  `>= guard >= 0`) else `guard`; the `Error` arm returns `guard`.
- The obligation is integer/ordering-shaped — pure **QF-LIA** (`>=`, `if`) — so it
  lands in the auto-discharge fragment. No `mod` / `/` / `*`, no payload-bearing
  constructors, no pairs-in-predicates.

## Contrast with `payments-core/settle`

`settle` is the **top-level** Result-match (the older v0.13.3 COMP-3b case): the
function body *is* the match. Here the body is a `let` and the match is **one level
down**, inside the `let` body — the case COMP-3b-general added. Same return-refinement
discipline, deeper nesting.

## Files

- `safe-withdraw.llmll` / `safe-withdraw.ast.json` — clean → **verified** (SAFE).
- `safe-withdraw-bad.llmll` — the Success arm returns the payload `n` directly
  (can be negative). Type-checks and passes a happy-path test, but
  `verify --strict-verified-core` → **refuted: safe-withdraw**, localized to the
  Success arm.

## Reproduce

```
llmll verify ./safe-withdraw.llmll                              # SAFE — verified
llmll verify ./safe-withdraw-bad.llmll --strict-verified-core   # refuted: safe-withdraw
```

**Trusted (TCB):** the LLMLL compiler, liquid-fixpoint, and z3 — same as any LLMLL
`verify`. Nothing demo-specific is assumed.
