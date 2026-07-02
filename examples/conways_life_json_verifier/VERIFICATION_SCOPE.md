# Verification-Scope Matrix — Conway's Game of Life

> **Module:** `examples/conways_life_json_verifier/life.ast.json`  
> **Schema:** 0.6.0  
> **Coverage:** 6 / 21 functions contracted (29%)

## Function Classification

| Function | Contracted | Verification Level | Notes |
|----------|-----------|-------------------|-------|
| `make-world` | ✅ pre | **Asserted** | Width/height > 0 precondition |
| `count-neighbors` | ✅ post | **Verified (own post), reports Asserted** | `0 <= result <= 8`; its own body-VC discharges given `neighbor-alive`'s stated bound, but the *effective* tier is floored to Asserted — it transitively depends on `cell-at`/`neighbor-alive`, which are Asserted (epistemic drift, not a proven chain) |
| `next-cell` | ✅ pre + post | **Verified** | Neighbor count bounds + output validity; no drift — genuinely `verified (liquid-fixpoint)` at both own-post and effective tier |
| `count-alive` | ✅ post | **Asserted** | Non-negative count postcondition |
| `world-cells` | — | Unspecified | Accessor |
| `world-width` | — | Unspecified | Accessor |
| `world-height` | — | Unspecified | Accessor |
| `world-gen` | — | Unspecified | Accessor |
| `cell-at` | ✅ post | **Asserted** | `0 <= result <= 1`; body uses `list-nth`, outside the QF-LIA-plus-datatype verified fragment, so it can never itself reach body-faithful status regardless of the stated bound |
| `in-bounds?` | — | Unspecified | Bounds check predicate |
| `neighbor-alive` | ✅ post | **Asserted** | `0 <= result <= 1`; same list-indexing boundary as `cell-at` |
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
| Integer bounds (QF-LIA), composed over a list-indexing callee | `count-neighbors` | Verified (own post) / Asserted (effective) | `0 <= result <= 8` — the body-VC itself discharges by composing over `neighbor-alive`'s stated `[0,1]` bound, but the *reported* tier is floored to Asserted because that bound is itself unproven (epistemic drift) |
| Dimension validity (QF-LIA) | `make-world` | Asserted | `width > 0 && height > 0` — contracted but not yet composed into a verified caller |
| Grid indexing (list operations, outside the verified fragment) | `cell-at`, `neighbor-alive` | Asserted (structural ceiling) | Both carry `0 <= result <= 1` postconditions now, but `cell-at`'s body uses `list-nth` — lists aren't in the QF-LIA-plus-datatype body-faithful fragment, so neither can ever reach `verified` itself, only be leaned on as an assumed contract by a caller (as `count-neighbors` does) |
| Simulation correctness | `step-world` | Not contracted | Would require inductive reasoning — outside current fragment |
| String rendering | `render-*` | Not contracted | Outside decidable fragment |

## Notes

- `next-cell` is the one function that reaches `verified` cleanly (own post *and* effective tier) — it has no dependency on a list-indexing function.
- `count-neighbors` is a genuine example of the trust axis' two-level structure: its own body-VC is solver-discharged (composing over `neighbor-alive`'s stated bound), but its *effective*/reported tier stays Asserted because that dependency chain bottoms out in `cell-at`, which structurally cannot itself be verified (see below). This is the epistemic-drift mechanism working as designed, not a bug — "own post verified" and "effective tier verified" are different, both-honest claims.
- `cell-at`/`neighbor-alive` cannot reach `verified` themselves, at any coverage level, because `cell-at`'s body reads the grid via `list-nth` — general list operations are outside LLMLL's current body-faithful fragment (see `LLMLL.md §5.3.5`). Adding contracts to them (done) improves what *callers* can compositionally prove; it does not and cannot make them verified themselves without a different grid representation.
- `step-world` is the core simulation function. Specifying it would require either an inductive invariant (world size preservation) or QuickCheck properties (known patterns like gliders).
