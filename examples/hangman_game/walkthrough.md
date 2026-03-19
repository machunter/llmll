# Hangman — LLMLL JSON AST Walkthrough

## What Was Built

A complete Hangman game written in **LLMLL v0.1.2 JSON-AST format**, placed in its own folder under `examples/`, with all artifacts. The program was compiled, built, and played end-to-end from the CLI.

## Files Created

| File | Description |
|------|-------------|
| `hangman.ast.json` | Complete Hangman as JSON-AST (schema v0.1.2) |
| `hangman.llmll` | S-expression companion (same program) |
| `README.md` | Usage docs |
| `generated/hangman_game/src/Lib.hs` | Generated Haskell library |
| `generated/hangman_game/app/Main.hs` | Interactive harness |

## Compiler Pipeline Results

### `llmll holes` (JSON-AST)
```
../examples/hangman_game/hangman.ast.json — 0 holes (0 blocking)
```
✅ No holes — implementation is complete.

### `llmll test` (JSON-AST)
```
../examples/hangman_game/hangman.ast.json — 9 properties
  ✅ Passed:  3
  ❌ Failed:  0
  ⚠️  Skipped: 6
```
3 purely algebraic properties pass. 6 skipped — expected per spec (§3b): custom type PBT generators not yet wired to Haskell QuickCheck runtime in v0.1.x.

### `llmll check` — type-checker output
The type-checker produces the same warnings on this file as it does on the reference `hangman_complete.llmll`. These are all the **known v0.1.x nominal type alias limitation** (§3.4 of LLMLL.md): the checker stores `TCustom "Word"` instead of the expanded `where`-type, so it flags mismatches between `Word`/`Letter` and `string`. Build still proceeds.

### `llmll build` → `stack build` → `stack run`
```
stack build OK
```

## Live Game Session

```
Enter the secret word: Game initialized.

Guess a letter: Word:    _a___a_
Guesses: a
Wrong:   0 / 6
Status:  in-progress

Guess a letter: Word:    _a___a_
Guesses: a e
Wrong:   1 / 6
...

Guess a letter: Word:    hangman
Guesses: a e i o u h n m g
Wrong:   4 / 6
Status:  won

Game over! Status: won
The word was: hangman
```

The word **hangman** was guessed in 9 turns (4 misses on vowels e/i/o/u, 5 hits).

## Post-Mortem: What Blocked One-Shot Success

### Compiler bugs (3) — in `Codegen.hs`, not fixable from docs

| # | Bug | Fix applied |
|---|-----|-------------|
| 1 | **Sum-type constructors lose payloads.** `(\| StartGame Word)` generated as `StartGame` with no `String` arg — GHC pattern-match fails. | Fixed `data GameInput` to carry `String` payload. |
| 2 | **`PositiveInt` used but never emitted.** `check` props reference this type but it never appears in generated output. GHC rejects. | Added `type PositiveInt = Int`. |
| 3 | **`check` labels with `(parens)` become illegal Haskell identifiers.** Label text converted verbatim, including literal `(` `)`. GHC rejects. | Sanitized prop function name. |

All three appear identically when building the reference `hangman_complete.llmll` — they are not specific to this file.

### Documentation gap (1)

`build-instructions.md` states `.ast.json` is a *"first-class source format"*, but `llmll build` on a `.ast.json` file falls back to the S-expression parser and emits a parse error. `check`, `holes`, and `test` all work on JSON. The docs should note that JSON-AST `build` is not yet wired (likely a partially-landed v0.1.2 deliverable).

### What worked perfectly (spec-driven, first try)

- JSON-AST structure and schema conformance
- All type declarations, `def-logic`, `check`, `gen`, `def-interface` nodes
- `qual-app` for `wasi.io.stdout`, nested pair state encoding
- `holes` and `test` on both `.ast.json` and `.llmll`

**Bottom line:** The spec is clear and complete. Every blocker was at the codegen boundary — two straightforward codegen fixes (payload emission, alias emission) and one identifier sanitization bug.
