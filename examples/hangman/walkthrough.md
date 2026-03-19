# Hangman in LLMLL JSON-AST Format — Walkthrough

> **Audience:** Compiler and language team. This document includes a [Problems Encountered](#problems-encountered--feedback-for-compiler--language-team) section at the bottom with concrete feedback gathered during the JSON-AST Hangman implementation.

## What Was Done

A complete, hole-free Hangman game was implemented in **LLMLL JSON-AST format** (schema version `0.1.2`), faithfully translating the canonical `hangman_complete.llmll` S-expression source into the machine-preferred JSON representation.

## Files Created

| File | Description |
|------|-------------|
| [hangman.ast.json](file:///Users/burcsahinoglu/Documents/llmll/examples/hangman/hangman.ast.json) | Canonical JSON-AST source (dot-named, per LLMLL convention) |
| [hangman_ast.json](file:///Users/burcsahinoglu/Documents/llmll/examples/hangman/hangman_ast.json) | Underscore-named copy for `build-json` (Cargo requires no dots in crate names) |
| [generated/hangman/](file:///Users/burcsahinoglu/Documents/llmll/generated/hangman) | Auto-generated Rust crate from `build-json` |

## Program Structure

The JSON-AST file contains 30 top-level statements:

```
imports        → wasi.io stdin + stdout
type-decls     → GameInput (sum), Word, Letter, GuessCount, PositiveInt (dependent)
gen-decl       → Letter custom generator (random lowercase ASCII)
def-logics     → make-state, state-word/guessed/wrong/max, word-chars,
                 display-word, all-guessed?, guess,
                 game-lost?, game-won?, game-status, render-state,
                 initialize-game, handle-guess, game-step
def-interface  → HangmanIO
check blocks   → 8 property-based tests
```

## Key Design Decisions

- **State as nested pairs**: `(word, (guessed, (wrong-count, max-wrong)))` — no record syntax in v0.1.1
- **`game-step` dispatches on the `GameInput` ADT**: `StartGame` → `initialize-game`, `Guess` → `handle-guess` (or echo if game over)
- **Pre/post contracts on `guess`**: pre guards that the game is in-progress; post asserts wrong-count is monotonically non-decreasing
- **`display-word` post**: `(string-length result) = (string-length word)` — verifiable by the type checker
- **`gen Letter`**: custom generator avoids slow rejection sampling for 1-char strings

## Compiler Verification Results

### `llmll holes` — Zero holes (program is complete and executable)
```
../examples/hangman.ast.json — 0 holes (0 blocking)
```

### `llmll build-json` — Rust crate generated successfully
```
OK Generated Rust crate from JSON-AST: ../generated/hangman
  cargo check OK
```

### `llmll check` — Type-check output
The type checker emits the same warnings/errors as the reference `hangman_complete.llmll`:
- **Warnings** (expected): stdlib functions (`string-length`, `list-map`, etc.) are not yet in scope for the type checker; dependent-type where-bindings appear as "unbound" in v0.1.1
- **Errors** (known compiler limitation): `int` literals `0`/`6` where `GuessCount` is expected; `Letter` passed where `Word` is expected in property-based test bodies. **These same errors appear in the reference `.llmll` file.**

### `llmll test` (on reference hangman_complete.llmll)
```
9 properties
  ✅ Passed:  3
  ❌ Failed:  0
  ⚠️  Skipped: 6   (stdlib-dependent expressions not evaluable by PBT engine)
```

## How to Run

```bash
cd /Users/burcsahinoglu/Documents/llmll/compiler

# Parse and hole-check
stack exec llmll -- holes ../examples/hangman/hangman.ast.json

# Type-check
stack exec llmll -- check ../examples/hangman/hangman.ast.json

# Build to Rust
stack exec llmll -- build-json ../examples/hangman/hangman_ast.json --output ../generated/hangman

# Run property-based tests (on the .llmll reference)
stack exec llmll -- test ../examples/hangman_complete.llmll
```

---

## Problems Encountered — Feedback for Compiler & Language Team

### P1 — `build-json` uses the raw basename as the Cargo crate name  *(bug — hard failure)*

**Reproduction:**
```bash
stack exec llmll -- build-json ../examples/hangman.ast.json
# → error: invalid character `.` in package name: `hangman.ast`
```

**Root cause** (`Main.hs`, `doBuildFromJson`):
```haskell
let modName = T.pack $ takeBaseName fp     -- "hangman.ast"
    result  = generateRust modName stmts   -- BUG: dot passed to Cargo
    outDir  = "generated/" <> T.unpack (T.replace ".ast" "" modName)  -- cleaned here only
```
`T.replace ".ast" ""` is applied to `outDir` but **not** to `modName` before it reaches `generateRust`. Cargo receives `hangman.ast` as the crate name and rejects it.

**Suggested fix:**
```haskell
let rawName = T.pack $ takeBaseName fp
    modName = T.replace ".ast" "" rawName  -- clean BEFORE codegen
    result  = generateRust modName stmts
```
Apply the same fix in the `doBuild` `--emit json-ast` code path for consistency.

**Workaround used here:** Copied the file to `hangman_ast.json` (underscore) before calling `build-json`.

---

### P2 — Type checker has no stdlib function signatures  *(missing feature — noisy false-positive output)*

**Observed output:** Every call to a built-in function produces a warning:
```
warning: call to unknown function 'string-length'
warning: unbound variable 'len' (may be in scope at runtime)
```
This affects `string-length`, `list-map`, `list-fold`, `list-contains`, `string-concat`, `range`, `first`, `second`, `int-to-string`, `string-char-at`, and every other §13 stdlib function. The compiler exits with code 1 for every valid Hangman program, including the canonical `hangman_complete.llmll`.

**Impact:** There is no way for an AI code generator (or a human) to distinguish a real type error from this noise without reading each warning line manually. The high false-positive rate undermines trust in the type checker's output.

**Suggested fix:** Seed `TypeCheck.hs` with the stdlib signature table from LLMLL.md §13 (`string-length : string -> int`, `list-map : list[a] (fn [a] -> b) -> list[b]`, etc.). This would validate argument arities, catch real type mismatches, and eliminate false-positive "unknown function" warnings in one step.

---

### P3 — Dependent-type literals not widened at call sites  *(missing feature — spurious type errors)*

**Observed output:**
```
error: type mismatch in 'make-state': expected GuessCount, got int
```
This fires when integer literals `0` or `6` are passed where `GuessCount` (`(where [n: int] (>= n 0))`) is expected. Both values trivially satisfy the constraint, but the type checker does not widen constant literals to their dependent type.

**Impact:** All `check` blocks that construct game states with literal counts fail type-checking. The same errors appear in `hangman_complete.llmll`, confirming this is a pre-existing gap, not introduced by the JSON parser.

**Suggested fix (v0.1.1):** Widen integer literal constants to the expected dependent type when the literal value is a compile-time constant that satisfies the `where` predicate. This is a conservative special case that requires no SMT.

**Suggested fix (v0.2):** Resolves automatically once LiquidHaskell refinement checking ships — Z3 will prove `0 : GuessCount` statically.

---

### P4 — `llmll test` does not route `.ast.json` files to the JSON parser  *(bug — silent failure)*

**Reproduction:**
```bash
stack exec llmll -- test ../examples/hangman.ast.json
# → S-expression parse error (JSON fed to wrong parser, no PBT results)
```

**Root cause** (`Main.hs`, `doTest`):
```haskell
doTest json fp = do
  src <- TIO.readFile fp      -- always reads as Text
  case parseSrc fp src of ... -- always takes the S-expression path
```
`doTest` does not call `loadStatements`, which dispatches on the `.json` extension. The `check`, `holes`, and `build` subcommands already use `loadStatements` correctly — `doTest` missed the same treatment. As a result, property-based tests for JSON-AST programs cannot be run via the CLI today.

**Suggested fix:** Replace the inline `TIO.readFile` + `parseSrc` pair in `doTest` with `loadStatements json fp`:
```haskell
doTest json fp = do
  stmts <- loadStatements json fp
  case stmts of
    Left ()  -> pure ()
    Right ss -> do
      result <- runPropertyTests ss
      if json
        then TIO.putStrLn (pbtResultJson fp result)
        else printPbtResult fp result
      if pbtFailed result > 0 then exitFailure else exitSuccess
```
This makes `llmll test` consistent with all other subcommands and makes `.ast.json` files first-class inputs for property testing.
