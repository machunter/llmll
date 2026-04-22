# Verification-Scope Matrix — Conway's Game of Life

> **Module:** `examples/conways_life_json_verifier/life.ast.json`  
> **Schema:** 0.3.0  
> **Coverage:** 4 / 21 functions contracted (19%)

## Function Classification

| Function | Contracted | Verification Level | Notes |
|----------|-----------|-------------------|-------|
| `make-world` | ✅ pre | **Asserted** | Width/height > 0 precondition |
| `count-neighbors` | ✅ post | **Asserted** | Result in [0, 8] postcondition |
| `next-cell` | ✅ pre + post | **Asserted** | Neighbor count bounds + output validity |
| `count-alive` | ✅ post | **Asserted** | Non-negative count postcondition |
| `world-cells` | — | Unspecified | Accessor |
| `world-width` | — | Unspecified | Accessor |
| `world-height` | — | Unspecified | Accessor |
| `world-gen` | — | Unspecified | Accessor |
| `cell-at` | — | Unspecified | Grid lookup |
| `in-bounds?` | — | Unspecified | Bounds check predicate |
| `neighbor-alive` | — | Unspecified | Single neighbor check |
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
| Integer bounds (QF-LIA) | `count-neighbors`, `next-cell`, `count-alive` | Asserted → Provable | `0 <= n <= 8`, `result >= 0` — pure linear arithmetic |
| Dimension validity (QF-LIA) | `make-world` | Asserted → Provable | `width > 0 && height > 0` |
| Grid indexing | `cell-at`, `in-bounds?` | Not contracted | Could benefit from bounds contracts |
| Simulation correctness | `step-world` | Not contracted | Would require inductive reasoning — outside current fragment |
| String rendering | `render-*` | Not contracted | Outside decidable fragment |

## Notes

- The contracted functions have the strongest verification potential — all postconditions are simple integer bounds within QF-LIA.
- `step-world` is the core simulation function. Specifying it would require either an inductive invariant (world size preservation) or QuickCheck properties (known patterns like gliders).
- Coverage could reach ~33% by adding bounds contracts to `cell-at` and `in-bounds?`.
