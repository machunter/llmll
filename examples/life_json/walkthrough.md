# Conway's Game of Life — JSON-AST Walkthrough

**Compiler:** LLMLL (Haskell backend)
**Format:** JSON-AST (`*.ast.json`)

---

## What Was Built

A modular Conway's Game of Life with three modules exercising multi-file
compilation:

| File | Module | Role |
|------|--------|------|
| `core.ast.json` | LifeCore | Pure rule engine — cell transition logic |
| `world.ast.json` | LifeWorld | Grid state, evolve, neighbor counting, rendering |
| `main.ast.json` | LifeMain | Entry point, Glider seed, console loop |

Grid: 20×10. Seed: Classic 5-cell Glider at rows 1–3.

---

## Module System Test Results

| Test | Result |
|------|--------|
| **Transitive Dependencies** | `main → world → core` resolved correctly; `next-cell-state` (from `core`) available transitively inside `world` | ✅ |
| **Namespace Integrity** | Each module's `export` list respected; `is-underpopulated`/`is-overpopulated`/`is-stable` private to `core` | ✅ |
| **Encapsulation** | `(export next-cell-state)` restricts LifeCore's public API to one function | ✅ |
| **Selective Importing** | `(import world)` in main brings world's names into scope | ✅ |

---

## Compilation

```bash
cd compiler
stack exec llmll -- check ../examples/life_json/core.ast.json   # ✅ OK (5 statements)
stack exec llmll -- check ../examples/life_json/world.ast.json  # ✅ OK (18 statements)
stack exec llmll -- check ../examples/life_json/main.ast.json   # ✅ OK (7 statements)

stack exec llmll -- build ../examples/life_json/main.ast.json \
  -o ../generated/life_json --emit-only    # ✅ Haskell package generated

cd ../generated/life_json && stack build   # ✅ GHC 9.6.6 build succeeded
```

The module pattern is `import → open → bare call`: both `world.ast.json` and
`main.ast.json` have an `(open ...)` statement after their `(import ...)`.
Without it, a bare call to an imported function is a `check` error that names
both fixes:

```
error: 'glider-grid' is declared in world; add (open world) or write world.glider-grid
```

---

## Run Output (3 generations shown)

```
Conway's Game of Life — LLMLL v0.2 (press Ctrl-C to quit)

....................   ← Gen 0 (Glider)
..#.................
...#................
.###................
...
```

Each later generation is printed after an ANSI clear-screen (`ESC[2J ESC[H`),
and the glider moves one cell diagonally every four generations.

---

## Gotchas

### Qualified calls work without `open`

`import → qualified call` is the other pattern (`LLMLL.md` §8.5.1). With
`(import world)` and no `open`, `main.ast.json` can call `world.glider-grid`,
`world.make-world`, `world.render-world` and `world.evolve`; it checks, builds
and prints the same output. Codegen emits the bare Haskell name, which is safe
because every top-level name in a build is unique (§8.5).

If the prefix of a dotted call names no imported module, `check` warns:
`warning: dotted function name 'wrld.evolve' names no imported module; add
(import <module-path>) and call it qualified, or add (open <module-path>) as
well and call the bare exported name.`

### Imports resolve from the entry file's directory

`(import world)` resolves to `world.llmll` or `world.ast.json` in the entry
file's directory. A dotted path maps to subdirectories: `(import game.world)`
resolves to `world.ast.json` in a `game` subdirectory (§8.2).

---

## Files

```
examples/life_json/
  core.ast.json      — LifeCore (rule engine)
  world.ast.json     — LifeWorld (state, evolve, render)
  main.ast.json      — LifeMain (entry, Glider seed)
  walkthrough.md     — this file
generated/life_json/ — generated Haskell package (do not edit)
```
