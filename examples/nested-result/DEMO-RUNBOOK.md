# nested-result — Demo Runbook

> **Artifact:** "A `Result` match verifies even when it's *nested* — one level down, inside a `let`."
> **Feature:** COMP-3b-general (v0.13.6) — a `Result`-typed VARIABLE match verifies body-faithfully at ANY nesting depth (under `let`/`if`, param- or let-bound). Before v0.13.6 a nested Result-var match fell back to `asserted`.
> **Fixtures:** `safe-withdraw.llmll` (+ `safe-withdraw-bad`). See [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) for the proven-vs-trusted matrix.
> **Verified against:** `llmll 0.13.6`, real `liquid-fixpoint` on PATH.

Run from this directory.

## What it proves

`safe-withdraw [attempt: Result[int, string], floor: int] -> Balance` returns a
`Balance` — a refinement type `{b : int | b >= 0}`. There is **no hand-written
post**: the return refinement is the entire spec, discharged **per arm** by the
solver. The body is a `let`, and the two-arm match on the `Result`-typed `attempt`
lives **inside the `let` body** — the *nested* form. The let-bound `guard` is
provably non-negative, so both arms establish `b >= 0`.

This is the headline of v0.13.6: `payments-core/settle` is the **top-level**
Result-match (the body *is* the match); here the match is **one level down**, under a
`let` — the case COMP-3b-general added.

## Beats

**Clean: nested Result-var match, reaching `verified`.**
```bash
llmll verify ./safe-withdraw.llmll
```
```
   body-faithful: safe-withdraw
✅ ./safe-withdraw.llmll — SAFE (liquid-fixpoint)
```

**Wrong: the Success arm returns the raw payload — refuted.** `safe-withdraw-bad.llmll`
returns `n` directly from the `Success` arm; `n` can be negative, violating the
`Balance` refinement. It type-checks and passes a happy-path test, but the solver
refutes on exactly the `Success` arm (per-arm localization, through the `let`-nested
match):
```bash
llmll verify ./safe-withdraw-bad.llmll --strict-verified-core
```
```
   body-faithful: safe-withdraw
error: body verification of 'safe-withdraw' failed (then-branch does not satisfy postcondition) (constraint #0)
ERROR: --strict-verified-core: refuted: safe-withdraw
```

## Narration

> *"A `Result` match doesn't have to be the whole function body to be proven. Here it's
> buried one level down inside a `let` — and the compiler still discharges the return
> refinement per arm: the result is provably never negative. Return the raw payload
> from the success arm instead, and the verifier refutes exactly that arm."*

Framing: **assurance, not bug-finding** — the same return-refinement discipline as
`settle`, now at depth.
