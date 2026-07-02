# Conway's Game of Life — S-expression Walkthrough

**Compiler:** LLMLL (Haskell backend)
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

## Gotchas

### Qualified names

Same flat-namespace behavior as the JSON-AST version — see
`life_json/walkthrough.md`.

### Parenthesis counting in deeply nested forms

Multi-level nesting like `(let [...] (list-fold ... (fn [...] (let [...] ...)))))`
is easy to miscount by one paren. This is exactly the failure mode the JSON-AST
format avoids for AI-authored code.

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
