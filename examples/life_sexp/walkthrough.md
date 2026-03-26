# Conway's Game of Life — S-expression Walkthrough

**Date:** 2026-03-25  
**Compiler:** LLMLL v0.2 (Haskell backend)  
**Format:** S-expression (`*.llmll`)

---

## What Was Built

Same modular architecture as the JSON-AST version, using S-expression syntax:

| File | Module | Role |
|------|--------|------|
| `core.llmll` | LifeCore | Pure rule engine — cell transition logic |
| `world.llmll` | LifeWorld | Grid state, evolve, neighbor counting, rendering |
| `main.llmll` | LifeMain | Entry point, Glider seed, console loop |

Grid: 20×10. Seed: Classic 5-cell Glider at rows 1–3.

---

## Module System Test Results

| Test | Result |
|------|--------|
| **Transitive Dependencies** | `main → world → core` resolved correctly | ✅ |
| **Namespace Integrity** | `export` list respected; private helpers not visible externally | ✅ |
| **Encapsulation** | `(export next-cell-state)` restricts LifeCore's public API | ✅ |
| **Selective Importing** | `(import world)` loads world's definitions | ✅ |

---

## Compilation

```bash
cd compiler
stack exec llmll -- check ../examples/life_sexp/core.llmll   # ✅ OK (5 statements)
stack exec llmll -- check ../examples/life_sexp/world.llmll  # ✅ OK (17 statements)
stack exec llmll -- check ../examples/life_sexp/main.llmll   # ✅ OK (6 statements)

stack exec llmll -- build ../examples/life_sexp/main.llmll \
  -o ../generated/life_sexp --emit-only   # ✅ Haskell package generated

cd ../generated/life_sexp && stack build  # ✅ GHC 9.6.6 build succeeded
```

---

## Run Output (3 generations shown)

```
Conway's Game of Life -- LLMLL v0.2 (press Ctrl-C to quit)

....................   ← Gen 0 (Glider)
..#.................
...#................
.###................
...
----------------------------------------
Conway's Game of Life -- LLMLL v0.2

....................   ← Gen 1
....................
.#.#................
..##................
..#.................
...
----------------------------------------
Conway's Game of Life -- LLMLL v0.2

....................   ← Gen 2
....................
...#................
.#.#................
..##................
```

Glider evolution confirmed correct (matches reference pattern).

---

## Problems Encountered

### Problem 1 — Negative integer literals rejected in expression position

**Symptom:** Used `(pair -1 -1)` inside a `list-prepend` chain to build the 8-direction delta list for neighbor counting. Parse error at the `-1` literal:
```
unexpected '('
expecting ')'
```

**Root cause:** The S-expression parser rejects bare negative integers (e.g. `-1`) in expression position — they are treated as a `-` operator token followed by `1`, not as a negative literal. This worked in JSON-AST (`{"kind": "lit-int", "value": -1}`) because JSON natively supports negative integers.

**Fix:** Bind intermediate values `(neg1 (- 0 1))`, `(zero 0)`, `(pos1 1)` in a `let` at the top of `count-neighbors` and use those variables in the `pair` calls.

**Compiler team note:** Negative integer literals in expression position (`-1`, `-42`) are valid LLMLL syntax per §3.1 but parsing them in S-expression mode fails in certain positions. The lexer likely tokenizes `-` as OP before seeing the digit. The JSON-AST path handles it correctly through the `lit-int` node. Consider adding `-[digit]` as a valid `INT` token production to the S-expression lexer.

---

### Problem 2 — `\u001b` escape not valid in S-expression strings

**Symptom:** Used `"\u001b[2J\u001b[H"` (ANSI clear-screen) in S-expression `main.llmll`. Parse error:
```
unexpected '\'
expecting '"' or literal character
```

**Root cause:** JSON-AST string `value` fields follow RFC 8259 where `\uXXXX` is valid. S-expression strings follow Haskell/C-style escapes — `\uXXXX` is not recognized. The JSON-AST version works correctly using `"\u001b[2J\u001b[H"`.

**Fix:** Replaced clear-screen ANSI escape with a `"---...---\n"` separator line in the S-expression version. This avoids the escape entirely.

**Compiler team note:** Document in `getting-started.md §4.9` that S-expression strings do NOT support `\uXXXX` JSON escapes. Options for terminal escape in S-expr: (a) embed the literal ESC byte (U+001B) directly in the UTF-8 source file, or (b) add `\uXXXX` as a recognized S-expression escape like the Unicode operator aliases.

---

### Problem 3 — Qualified names (inherited from JSON-AST investigation)

Same flat-namespace finding as JSON-AST version. Used bare function names throughout.

---

### Problem 4 — Extra closing parenthesis (paren drift)

**Symptom:** When translating `count-neighbors` from JSON-AST to S-expression, the nested `list-fold` + `fn` + `let` accumulated one extra `)` giving 7 closing parens where 6 were needed. Parse error at the unexpected `)`.

**Fix:** Manual paren count. The multi-nesting of `(let [...] (list-fold ... (fn [...] (let [...] ...)))))` is error-prone in S-expressions — this is exactly the failure mode that motivated the JSON-AST format for AI agents.

---

## Files

```
examples/life_sexp/
  core.llmll       — LifeCore (rule engine)
  world.llmll      — LifeWorld (state, evolve, render)
  main.llmll       — LifeMain (entry, Glider seed)
  walkthrough.md   — this file
generated/life_sexp/ — generated Haskell package (do not edit)
```
