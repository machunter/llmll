# Verification-Scope Matrix — Tic-Tac-Toe

> **Module:** `examples/tictactoe_json_verifier/tictactoe.ast.json`  
> **Schema:** 0.3.0  
> **Coverage:** 5 / 19 functions contracted (26%)

## Function Classification

| Function | Contracted | Verification Level | Notes |
|----------|-----------|-------------------|-------|
| `make-board` | ✅ post | **Asserted** | Board size postcondition |
| `board-get` | ✅ pre | **Asserted** | Index bounds precondition |
| `cell-empty?` | ✅ pre | **Asserted** | Index bounds precondition |
| `set-cell` | ✅ pre + post | **Asserted** | Bounds + mutation postcondition |
| `render-row` | ✅ pre | **Asserted** | Row index bounds |
| `make-state` | — | Unspecified | State constructor |
| `state-board` | — | Unspecified | Accessor |
| `state-player` | — | Unspecified | Accessor |
| `state-status` | — | Unspecified | Accessor |
| `other-player` | — | Unspecified | Pure function |
| `check-triple` | — | Unspecified | Win detection logic |
| `has-won?` | — | Unspecified | Win detection logic |
| `board-full?` | — | Unspecified | Board state predicate |
| `compute-status` | — | Unspecified | Game status logic |
| `render-board` | — | Unspecified | String rendering |
| `start-game` | — | Unspecified | Entry point |
| `game-loop` | — | Unspecified | Entry point |
| `game-over?` | — | Unspecified | Game predicate |
| `show-result` | — | Unspecified | String rendering |

## Verification Boundary

| Constraint class | Functions | Level | Why |
|---|---|---|---|
| Array index bounds (QF-LIA) | `board-get`, `cell-empty?`, `set-cell`, `render-row` | Asserted → Provable | `0 <= idx < 9` is linear arithmetic |
| Board structure | `make-board` | Asserted | Size postcondition (linear) |
| Game logic (conditional) | `check-triple`, `has-won?`, `compute-status` | Not contracted | Conditional logic — testable via QuickCheck |
| String rendering | `render-board`, `render-row` | Partial | Outside decidable fragment |

## Notes

- Index bounds contracts are the strongest candidates for **Proven** upgrade — all are simple `0 <= i < 9` checks within QF-LIA.
- `check-triple` and `has-won?` contain conditional logic that would benefit from QuickCheck-level (**Tested**) contracts.
