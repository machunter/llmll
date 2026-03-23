# Hangman — S-expression Version Walkthrough

## What was built

A fully playable Hangman game in LLMLL S-expression syntax (`hangman.llmll`).
Semantically identical to the JSON-AST version: same word (`"hangman"`), same 6-guess
limit, same gallows art, win/lose logic, and input validation.

## Compilation

```bash
# Type-check
cd compiler
stack exec llmll -- check ../examples/hangman_sexp/hangman.llmll
# ✅ OK (no output = success)

# Generate Haskell (--emit-only due to Stack lock)
stack exec llmll -- build ../examples/hangman_sexp/hangman.llmll \
  -o ../generated/hangman_sexp --emit-only
# ✅ OK Generated Haskell package: ../generated/hangman_sexp

# [Manual patch required — see P1 below]

# Build the executable
cd ../generated/hangman_sexp && stack build
# ✅ OK (after patch)

# Run — win path
printf 'h\na\nn\ng\nm\na\n' | stack exec hangman
# ✅ "You won! Congratulations!"

# Run — lose path
printf 'z\nx\nq\nw\nv\nb\n' | stack exec hangman
# ✅ "Game over! The word was: hangman"
```

## Problems encountered

### P1 — **Codegen bug: empty `do` block in generated `Main.hs`** ⚠️

**Symptom:** `stack build` failed immediately with:

```
Main.hs:15:46: error: [GHC-82311]
    Empty 'do' block
```

**Root cause:** The S-expression codegen path for `:done?` generates this Haskell:

```haskell
-- BROKEN (compiler output):
    loop s = do
      if is_game_over' s then return () else do
      eof <- hIsEOF stdin          -- ← same indent as `if`, not inside `else do`
      if eof then return () else do
        ...
```

The `eof <- hIsEOF stdin` line and everything after it should be indented inside the
`else do` branch. Instead the compiler emitted them at the same indentation level as
the `if`, producing an empty `do` block after `else do`.

**Status: ✅ Fixed in `abea019`** — `CodegenHs.hs` now parameterises the loop body
on an indentation string (6 spaces without `:done?`, 8 spaces inside the `else do`
branch with `:done?`). No manual patch is required. The JSON-AST path was never
affected.

### P2 — `done?` check renders board twice on win/loss

Same root cause as the JSON-AST version. **Resolution:** use `:on-done` for all
end-of-game terminal output (see `LLMLL.md §9.5` and JSON-AST `WALKTHROUGH.md §P2`).

## Property-based tests

```bash
stack exec llmll -- test ../examples/hangman_sexp/hangman.llmll
# ✅ (no output = all passed)
```

Same 4 static assertion checks as the JSON-AST version, all passed.
