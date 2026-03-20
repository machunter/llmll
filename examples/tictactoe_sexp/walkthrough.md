# Walkthrough: Tic-Tac-Toe (S-Expression Version)

**Author:** AI (Antigravity)  
**Date:** 2026-03-19  
**Compiler version:** LLMLL v0.1.2, GHC 9.6.6  
**Source:** `examples/tictactoe_sexp/tictactoe.llmll`  
**Generated output:** `generated/tictactoe_sexp/`

---

## What Was Built

A fully functional two-player CLI tic-tac-toe game in LLMLL S-expression syntax, functionally identical to the JSON-AST version:

- 3×3 board, players X and O alternate turns
- Input: cell index 0–8 via stdin  
- Detects all 8 win lines (3 rows, 3 columns, 2 diagonals)
- Detects draw (full board, no winner)
- Validates input: rejects non-numbers, out-of-range, and occupied cells

---

## Program Structure

State is encoded as nested pairs (no record syntax in v0.1.1):

```lisp
;; State = (board, (current-player, (game-over, winner)))
(def-logic make-state [board: list[string] player: string gameover: bool winner: string]
  (pair board (pair player (pair gameover winner))))
```

---

## Problems Encountered

### Problem 1: `_err` in constructor patterns is parsed as two sub-patterns

**Symptom:** GHC error:
```
The constructor 'Left' should have 1 argument, but has been given 2
In the pattern: Left _ err
```

**Root cause:** In LLMLL S-expression syntax, the match arm:
```lisp
((Left _err) ...)
```
is tokenized as constructor `Left` followed by **two** sub-patterns: the wildcard `_` and the variable `err` — because `_` is its own lexer token (the catch-all pattern character) and `err` is a separate identifier. The `_err` string is not treated as a single identifier.

This is surprising because in most ML-family languages (Haskell, OCaml, Rust), `_foo` is a valid single wildcard-prefixed variable name. In LLMLL's lexer, `_` is a reserved pattern token and is not a valid identifier prefix.

**Fix:** Use a plain single-word variable name instead:
```lisp
;; WRONG — parsed as wildcard _ + variable err (two sub-patterns):
((Left _err) ...)

;; CORRECT — single variable pattern e:
((Left e) ...)
```

**Recommendation for compiler team:** Either (a) document that `_` is a reserved pattern token and cannot appear as an identifier prefix, or (b) treat `_foo` as a single "don't-care named binder" pattern (as in Haskell). Option (b) would be more ergonomic for AI code generators accustomed to Haskell/Rust conventions.

---

### Problem 2: `result` is a reserved keyword — cannot use as struct pattern variable

**Note (not encountered here, but a latent risk):** The `result` identifier is reserved for use inside `post` clauses only. Any match arm binding named `result` would cause a compile error. This was documented but worth re-emphasizing since it is a common variable name choice.

---

### Problem 3: Redundant wildcard pattern warning (same as JSON-AST version)

**Symptom:** GHC warning `-Woverlapping-patterns` on the auto-generated `_` catch-all.

Same root cause and recommendation as in the JSON-AST walkthrough.

---

## Build Steps

```bash
# From compiler/
stack exec llmll -- check ../examples/tictactoe_sexp/tictactoe.llmll
# ✅ OK (21 statements)

stack exec llmll -- build ../examples/tictactoe_sexp/tictactoe.llmll -o ../generated/tictactoe_sexp
# OK Generated Haskell package

cd ../generated/tictactoe_sexp
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
Input: 4 0 2 6 8 [foo=invalid] 1 3 5 7

...
 O | O | X
---+---+---
 X | X | O
---+---+---
 O | X | X

It's a draw!
```

Invalid input `foo` was correctly rejected with `Invalid input — enter a number 0-8.`

---

## Comparison: S-Expression vs JSON-AST

| Criterion | S-Expression | JSON-AST |
|---|---|---|
| Lines of source | ~160 | ~550 |
| Structural validity | Checked at parse time | Schema-validated before parse |
| Parenthesis drift risk | Higher (deep nesting) | None (JSON guarantees) |
| AI generation | More natural for LLMs trained on Lisp/Haskell | Better for schema-constrained generation modes |
| Bugs discovered | `_err` two-pattern bug | `Error`/`Success` vs `Left`/`Right` naming |
