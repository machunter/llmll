# Verification-Scope Matrix — Conway's Game of Life

> **Module:** `examples/conways_life_json_verifier/life.ast.json`  
> **Schema:** 0.6.0  
> **Coverage:** 6 / 21 functions contracted (29%)

## Function Classification

| Function | Contracted | Verification Level | Notes |
|----------|-----------|-------------------|-------|
| `make-world` | ✅ pre | **Asserted** | Width/height > 0 precondition |
| `count-neighbors` | ✅ post | **Verified (own post), reports Asserted** | `0 <= result <= 8`; its own body-VC discharges given `neighbor-alive`'s bound, but the *effective* tier is floored to Asserted because the chain bottoms out in `cell-at`, which is Asserted (epistemic drift, not a proven chain) |
| `next-cell` | ✅ pre + post | **Verified** | Neighbor count bounds + output validity; no drift — genuinely `verified (liquid-fixpoint)` at both own-post and effective tier |
| `count-alive` | ✅ post | **Asserted** | Non-negative count postcondition |
| `world-cells` | — | Unspecified | Accessor |
| `world-width` | — | Unspecified | Accessor |
| `world-height` | — | Unspecified | Accessor |
| `world-gen` | — | Unspecified | Accessor |
| `cell-at` | ✅ post | **Asserted** | `0 <= result <= 1`; body uses `list-nth`, outside the QF-LIA-plus-datatype verified fragment, so it can never itself reach body-faithful status regardless of the stated bound |
| `in-bounds?` | — | Unspecified | Bounds check predicate |
| `neighbor-alive` | ✅ post | **Verified (own post), reports Asserted** | `0 <= result <= 1`; its body is an `in-bounds?` branch over a `cell-at` call, so its own body-VC discharges from `cell-at`'s stated bound. The effective tier is floored to Asserted by that dependency (epistemic drift) |
| `step-world` | — | Unspecified | Core simulation step |
| `render-cell` | — | Unspecified | String rendering |
| `render-row-life` | — | Unspecified | String rendering |
| `render-grid` | — | Unspecified | String rendering |
| `render-world` | — | Unspecified | String rendering |
| `set-alive` | — | Unspecified | Grid mutation |
| `seed-glider` | — | Unspecified | Initial state setup |
| `start-life` | — | Unspecified | Entry point |
| `life-loop` | — | Unspecified | Entry point |
| `life-over?` | — | Unspecified | Termination predicate |

## Verification Boundary

| Constraint class | Functions | Level | Why |
|---|---|---|---|
| Integer bounds (QF-LIA), no list-op dependency | `next-cell` | **Verified** | `0 <= neighbors <= 8` precondition + output validity postcondition — pure linear arithmetic, no dependency on list-indexing functions |
| Integer bounds (QF-LIA), composed over a list-indexing callee | `count-neighbors`, `neighbor-alive` | Verified (own post) / Asserted (effective) | The body-VCs discharge by composing over the stated `[0,1]` bound of the callee (`neighbor-alive` for `count-neighbors`, `cell-at` for `neighbor-alive`), but the *reported* tier is floored to Asserted because `cell-at`'s bound is unproven (epistemic drift) |
| Dimension validity (QF-LIA) | `make-world` | Asserted | `width > 0 && height > 0` — contracted but not yet composed into a verified caller |
| Grid indexing (list operations, outside the verified fragment) | `cell-at` | Asserted (structural ceiling) | Carries a `0 <= result <= 1` postcondition, but its body uses `list-nth`; lists are not in the QF-LIA-plus-datatype body-faithful fragment, so it cannot reach `verified` itself, only be leaned on as an assumed contract by a caller (as `neighbor-alive` does) |
| Simulation correctness | `step-world` | Not contracted | Would require inductive reasoning — outside current fragment |
| String rendering | `render-*` | Not contracted | Outside decidable fragment |

## Notes

- `next-cell` is the one function that reaches `verified` cleanly (own post *and* effective tier) — it has no dependency on a list-indexing function.
- `count-neighbors` and `neighbor-alive` show the trust axis' two-level structure: each own body-VC is solver-discharged, but the *effective*/reported tier stays Asserted because the dependency chain bottoms out in `cell-at`, which cannot itself be verified (see below). This is the epistemic-drift mechanism working as designed, not a bug: "own post verified" and "effective tier verified" are different claims, and both are accurate. `llmll verify` counts both functions among its 3 proved of 5 contracted.
- `cell-at` cannot reach `verified` itself, at any coverage level, because its body reads the grid via `list-nth`; general list operations are outside LLMLL's current body-faithful fragment (see `LLMLL.md §5.3.5`). Its contract improves what *callers* can compositionally prove (`neighbor-alive` and `count-neighbors` both lean on it); it cannot make `cell-at` verified without a different grid representation.
- `step-world` is the core simulation function. Specifying it would require either an inductive invariant (world size preservation) or QuickCheck properties (known patterns like gliders).
