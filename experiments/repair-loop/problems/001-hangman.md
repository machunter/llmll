# 001 — Hangman

> **Source:** Adapted from `docs/design/language-comparison-experiments.md:253-301`.
> **Class:** Pure-state game logic. QF-LIA-shallow.
> **H3 expectation:** No specific LLMLL advantage predicted. QF-LIA contracts on the integer attempt counter auto-discharge, but the problem lacks a strong conservation invariant comparable to `002-bank-ledger`'s `total_balance`; LLMLL's verification surface and Python type hints / Go's type system are expected to produce roughly comparable assurance signals. Predicted in detail at `experiments/repair-loop/findings/phase3-problem-shape-audit.md` §"001 — Hangman".

## Specification

Build the core logic for a command-line Hangman game. The core is pure (no IO, no ambient time / randomness); CLI plumbing is out of scope.

### Required State

- Secret word (string of alphabetic characters; matched case-insensitively).
- Set of guessed letters (lower-case).
- Remaining incorrect attempts (integer; starts at 6).
- Game status: one of `playing`, `won`, `lost`.

### Required API

- `initialize_game(secret)` — creates a new game state with 6 remaining incorrect attempts, the secret normalized to lower case, and `status = playing`.
- `apply_guess(state, guess)` — returns the next game state after applying `guess` (a single alphabetic character).
- `render_state(state)` — returns a display string where unrevealed letters appear as `_`. Spacing convention: one space between characters (`_ a _ a _ a` for `banana` with `a` guessed).
- `game_status(state)` — returns `playing`, `won`, or `lost`.

### Behavioral Requirements

- Guesses are one alphabetic character.
- Guess matching is case-insensitive (both for the secret and for the guess letter).
- Repeated guesses do not consume attempts (state is unchanged when the letter is already in the guessed set).
- Correct guesses reveal every matching position in the secret in one step.
- Incorrect new guesses consume exactly one attempt.
- The game is won when every distinct letter of the secret has been guessed.
- The game is lost when remaining attempts reaches zero.
- Once `won` or `lost`, further guesses do not change the state.

### LLMLL Assurance Requirements (Suggested)

The LLMLL target should express at least the following:

- `post initialize-game`: `(= (remaining result) 6)` — QF-LIA, auto-discharged.
- `post apply-guess`: `(<= (remaining result) (remaining state))` — QF-LIA monotonicity, auto-discharged.
- `post apply-guess`: `(>= (remaining result) (- (remaining state) 1))` — QF-LIA lower bound, auto-discharged.
- Repeated-guess invariance: if expressible as a `post` clause on `apply-guess` ("a guess already in the guessed set leaves the state unchanged"), mark `?proof-required` — string-membership reasoning over the guessed set is outside QF-LIA per `LLMLL.md §13.8`. Alternatively cover with focused `(check ...)` blocks.

## Harness Tests

Tests live under `experiments/repair-loop/testkits/001-hangman/<target>/`.
Black-box tests should enforce:

- `initialize_game("banana")` followed by `apply_guess(state, "a")` renders the secret as `_ a _ a _ a` (or equivalent normalized display under the chosen render convention).
- Repeating a wrong guess (e.g., `x` twice) consumes at most one attempt across the two calls.
- Six distinct wrong guesses lose the game (status `lost`, remaining 0).
- Guessing every unique letter of the secret wins the game (status `won`).
- Guessing after `won` or `lost` leaves the state unchanged.

## QF-LIA Classification

- **Inside QF-LIA:** integer attempt-counter arithmetic; remaining-attempts monotonicity; lower-bound on remaining; counter bounds. These auto-discharge under liquid-fixpoint per `LLMLL.md §5.3.5`.
- **Outside QF-LIA / string reasoning:** letter-in-secret membership; letter-in-guessed-set membership; set-equality between guessed-set and secret-letter-set (the "won" predicate). These should be expressed as `(check ...)` blocks (where the trust ladder routes them to `tested` via the PBT-Lift rule at `LLMLL.md §4.4.5`) or marked `?proof-required` per `LLMLL.md §13.8`.

H1 / H2 / H3 expectations: LLMLL is expected to expose remaining-attempts-monotonicity as verified evidence while Python (with `pyright`) and Go (with type checker + tests) catch the same regressions through type signatures and behavioral tests. H1-Assurance differential predicted to be small or absent on this problem; the audit's per-cell predictions are at `experiments/repair-loop/findings/phase3-problem-shape-audit.md` §"001 — Hangman".
