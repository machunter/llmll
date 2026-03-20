# Walkthrough: Tic-Tac-Toe (JSON-AST Version)

**Author:** AI (Antigravity)  
**Date:** 2026-03-19  
**Compiler version:** LLMLL v0.1.2, GHC 9.6.6  
**Source:** `examples/tictactoe_json/tictactoe.ast.json`  
**Generated output:** `generated/tictactoe_json/`

---

## What Was Built

A fully functional two-player CLI tic-tac-toe game:

- 3×3 board, players X and O alternate turns
- Input: cell index 0–8 via stdin
- Detects all 8 win lines (3 rows, 3 columns, 2 diagonals)
- Detects draw (full board, no winner)
- Validates input: rejects non-numbers, out-of-range values, and already-occupied cells

---

## Program Structure

State is encoded as nested pairs (no record syntax in v0.1.1):

```
State = (board, (current-player, (game-over, winner)))
```

| Binding | Type | Description |
|---|---|---|
| `board` | `list[string]` | 9 cells, each `" "`, `"X"`, or `"O"` |
| `current-player` | `string` | `"X"` or `"O"` |
| `game-over` | `bool` | True once win or draw |
| `winner` | `string` | `"X"`, `"O"`, `"draw"`, or `""` |

Key functions: `init-board`, `make-state`, `state-*` accessors, `cell-at`, `set-cell`, `three-match?`, `player-wins?`, `board-full?`, `render-row`, `render-board`, `make-move`, `game-step`, `init-game`, `game-done?`.

---

## Problems Encountered

### Problem 1: `Error`/`Success` constructors do not exist in generated Haskell

**Symptom:** GHC error:
```
Not in scope: data constructor 'Error'
Not in scope: data constructor 'Success'
```

**Root cause:** LLMLL.md documents `Result[t,e]` with constructors `Success` and `Error`. However, the Haskell codegen maps `Result[t,e]` to Haskell's built-in `Either String Int` and its standard constructors `Right` (success) and `Left` (error). The constructor name mapping is **not documented** in `LLMLL.md` or the schema — it is a codegen implementation detail.

**Fix:** In `match` arms on a `Result`, use `Left` and `Right` as constructor names, not `Error` and `Success`.

```json
// WRONG (matches LLMLL.md docs but fails to compile):
{"kind": "constructor", "constructor": "Success", ...}
{"kind": "constructor", "constructor": "Error",   ...}

// CORRECT (matches actual Haskell codegen):
{"kind": "constructor", "constructor": "Right", ...}
{"kind": "constructor", "constructor": "Left",  ...}
```

**Recommendation for compiler team:** Either (a) document that `Result` maps to `Either` with `Left`/`Right`, (b) emit a Haskell `type alias` / `newtype` that exposes `Success`/`Error` as constructor names, or (c) add a codegen rewrite rule that translates `Success`→`Right` and `Error`→`Left` in pattern positions. Option (c) is lowest friction for AI code generators.

---

### Problem 2: Redundant wildcard pattern warning

**Symptom:** GHC warning `-Woverlapping-patterns` on the `_` catch-all arm of the `Either` match.

**Root cause:** The LLMLL language spec requires all `match` expressions to be exhaustive and encourages a `_` catch-all arm. However, a match on `Either` (Left/Right) that already covers both constructors makes `_` unreachable, triggering GHC's overlap warning.

**Fix:** Harmless at runtime — the generated binary works correctly. Could be suppressed with `{-# OPTIONS_GHC -Wno-overlapping-patterns #-}` in generated code, or the codegen could omit the `_` arm when the match is provably exhaustive.

**Recommendation for compiler team:** Detect exhaustive ADT matches during codegen and suppress the default `_` arm emission.

---

## Build Steps

```bash
# From compiler/
stack exec llmll -- check ../examples/tictactoe_json/tictactoe.ast.json
# ✅ OK (21 statements)

stack exec llmll -- build ../examples/tictactoe_json/tictactoe.ast.json -o ../generated/tictactoe_json
# OK Generated Haskell package from JSON-AST

cd ../generated/tictactoe_json
stack build
# ✅ Compiled (1 warning: redundant _ pattern)
```

---

## Test Results

### Win scenario (X wins top row)

```
Input: 0 3 1 4 2

=== Tic-Tac-Toe ===
...
 X | X | X
---+---+---
 O | O |  
---+---+---
   |   |  

Player X wins!
```

### Draw scenario

```
Input: 4 0 2 6 8 [abc=invalid] 1 3 5 7

...
 O | O | X
---+---+---
 X | X | O
---+---+---
 O | X | X

It's a draw!
```

Invalid input `abc` was correctly rejected with `Invalid input — enter a number 0-8.`
