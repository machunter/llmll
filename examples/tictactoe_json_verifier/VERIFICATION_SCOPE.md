# Verification-Scope Matrix — Tic-Tac-Toe

> **Module:** `examples/tictactoe_json_verifier/tictactoe.ast.json`  
> **Schema:** 0.6.0  
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
| Array index bounds (QF-LIA) | `board-get`, `cell-empty?`, `set-cell`, `render-row` | Asserted | `0 <= idx < 9` is linear arithmetic, but the board is a `list`: every one of these bodies falls back from body-faithful verification, so no index check is discharged |
| Board structure | `make-board` | Asserted | Size postcondition (linear) |
| Game logic (conditional) | `check-triple`, `has-won?`, `compute-status` | Not contracted | Conditional logic — testable via QuickCheck |
| String rendering | `render-board`, `render-row` | Partial | Outside decidable fragment |

## Notes

- The index bounds are simple `0 <= i < 9` checks within QF-LIA, but they do not reach **Proven**: the board is a `list`, outside the body-faithful fragment. `make-board` is refused by `app:list-prepend` and `set-cell` by `let`, so `llmll verify` reports `partial: 0 of 2`. Reaching Proven would need a board representation inside the fragment.
- `check-triple` and `has-won?` contain conditional logic that would benefit from QuickCheck-level (**Tested**) contracts.
