# Verification-Scope Matrix — Hangman

> **Module:** `examples/hangman_json_verifier/hangman.ast.json`  
> **Schema:** 0.3.0  
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
| Integer bounds (QF-LIA) | `make-state`, `gallows` | Asserted → Provable | Simple `>=` / `<` on integers |
| State validity | `apply-guess` | Asserted | Compound precondition |
| String operations | `display-word`, `render-state` | Not contracted | Outside decidable fragment |
| IO / game loop | `start-game`, `game-loop` | Not contracted | Effectful — excluded from spec coverage |

## Notes

- Accessor functions (`state-word`, `state-guessed`, etc.) are structurally trivial — spec coverage improvement would come from adding postconditions on `apply-guess` and the game predicates.
- The integer bounds on `make-state` and `gallows` are within QF-LIA and could be upgraded to **Proven** with `liquid-fixpoint`.
