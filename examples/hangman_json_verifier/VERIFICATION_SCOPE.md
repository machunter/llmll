# Verification-Scope Matrix — Hangman

> **Module:** `examples/hangman_json_verifier/hangman.ast.json`  
> **Schema:** 0.6.0  
> **Coverage:** 3 / 16 functions contracted (19%)

## Function Classification

| Function | Contracted | Verification Level | Notes |
|----------|-----------|-------------------|-------|
| `make-state` | ✅ pre + post | **Asserted** | State constructor — integer arithmetic guards |
| `apply-guess` | ✅ pre only | **Asserted** | Precondition: valid game state |
| `gallows` | ✅ pre only | **Asserted** | Precondition: wrong count bounds |
| `state-word` | — | Unspecified | Accessor (trivial) |
| `state-guessed` | — | Unspecified | Accessor (trivial) |
| `state-wrong-count` | — | Unspecified | Accessor (trivial) |
| `state-max-wrong` | — | Unspecified | Accessor (trivial) |
| `all-guessed?` | — | Unspecified | Pure predicate |
| `game-won?` | — | Unspecified | Pure predicate |
| `game-lost?` | — | Unspecified | Pure predicate |
| `game-over?` | — | Unspecified | Pure predicate |
| `display-word` | — | Unspecified | String rendering |
| `render-state` | — | Unspecified | String rendering |
| `start-game` | — | Unspecified | Entry point |
| `game-loop` | — | Unspecified | Entry point |
| `show-result` | — | Unspecified | String rendering |

## Verification Boundary

| Constraint class | Functions | Level | Why |
|---|---|---|---|
| Integer bounds (QF-LIA) | `make-state`, `gallows` | Asserted | The bounds are simple `>=` / `<` on integers, but the bodies fall back: `make-state` builds the state with `pair` (outside the body-faithful fragment), and no caller of `gallows` is in the fragment, so its precondition is never discharged at a call site |
| State validity | `apply-guess` | Asserted | Compound precondition |
| String operations | `display-word`, `render-state` | Not contracted | Outside decidable fragment |
| IO / game loop | `start-game`, `game-loop` | Not contracted | Effectful — excluded from spec coverage |

## Notes

- Accessor functions (`state-word`, `state-guessed`, etc.) are structurally trivial — spec coverage improvement would come from adding postconditions on `apply-guess` and the game predicates.
- The integer bounds on `make-state` and `gallows` are QF-LIA, but that is not enough for **Proven**: every contracted body falls back from body-faithful verification. `make-state` is refused by `pair` and the `state-max-wrong` accessor by `app:second`, so `llmll verify` reports `partial: 0 of 2`. Reaching Proven would need a state representation inside the fragment (for example a record type instead of nested pairs).
