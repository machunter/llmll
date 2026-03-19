# Hangman Game — LLMLL JSON-AST Example

This example implements the classic Hangman word-guessing game in **LLMLL v0.1.2
JSON-AST format**. Every node is schema-constrained and structurally valid by
construction — no parenthesis drift possible.

## Files

| File | Description |
|------|-------------|
| `hangman.ast.json` | Complete Hangman implementation as a JSON AST |
| `README.md` | This file |

## Game Rules

- The runtime provides a secret word via `wasi.io.stdin`.
- The player guesses one letter at a time.
- **Duplicate guess** → no penalty; state is unchanged.
- **Wrong guess** → `wrong-count` incremented by 1.
- **Won** when every letter in the word has been guessed.
- **Lost** when `wrong-count >= max-wrong` (default max: 6).

## What the AST Demonstrates

- **Dependent types** — `Word`, `Letter`, `GuessCount` with `where` predicates
- **Sum type ADT** — `GameInput` with `StartGame` and `Guess` constructors
- **`match`** — exhaustive pattern matching on `GameInput`
- **`def-logic` with `pre`/`post` contracts** — `guess` validates game-in-progress and wrong-count monotonicity
- **State encoded as nested pairs** — `(word, (guessed, (wrong, max-wrong)))`
- **IO via `Command` model** — `wasi.io.stdout` returns a `Command`, never performs IO directly
- **`seq-commands`** — composing multiple `Command` values
- **`gen` declaration** — custom PBT generator for `Letter`
- **Nine `check`/`for-all` properties** — algebraic laws + game-correctness properties
- **`qual-app`** — capability-namespaced command constructors in JSON form

## Running with the LLMLL Compiler

All commands run from `compiler/` (the root of the compiler project).

### Parse and type-check

```bash
stack exec llmll -- check ../examples/hangman_game/hangman.ast.json
```

### Inspect holes

```bash
stack exec llmll -- holes ../examples/hangman_game/hangman.ast.json
```

Expected: **0 holes** (the implementation is complete).

### Run property-based tests

```bash
stack exec llmll -- test ../examples/hangman_game/hangman.ast.json
```

### Build and run

`llmll build` auto-detects `.json` files and routes them through the JSON-AST parser:

```bash
stack exec llmll -- build ../examples/hangman_game/hangman.ast.json \
  -o ../generated/hangman_game

cd ../generated/hangman_game
stack build
```

To run interactively (requires a `def-main` block):

```bash
stack run
```

> **Note (v0.1.2):** `hangman.ast.json` produces a library (`Lib.hs`) only — no `def-main` is defined, so no `Main.hs` is generated. Interactive play requires adding a `def-main` node or importing the library from a separate harness.

## Design Notes

### Why JSON-AST?

LLMLL v0.1.2 accepts `.ast.json` files alongside `.llmll` S-expressions.
JSON schema-constrained generation prevents the parenthesis-drift errors that
can occur with S-expression generation at large nesting depth. The compiler
validates the JSON against `docs/llmll-ast.schema.json` before semantic
analysis begins.

### State Encoding

LLMLL v0.1.1/v0.1.2 has no record syntax. The game state is a nested pair:

```
GameState = (Word, (list[Letter], (GuessCount, GuessCount)))
            word    guessed        wrong         max-wrong
```

Named accessor functions (`state-word`, `state-guessed`, `state-wrong`,
`state-max`) give symbolic names to each field position.

### IO Model

All IO is mediated via `Command` values returned from pure logic functions.
The runtime executes the command and feeds the result back. Logic is pure;
the runtime is the only actor that touches the OS.
