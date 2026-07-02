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
stack exec llmll -- check ../examples/life_json/main.ast.json   # ✅ OK (7 statements, 1 warning)

stack exec llmll -- build ../examples/life_json/main.ast.json \
  -o ../generated/life_json --emit-only    # ✅ Haskell package generated

cd ../generated/life_json && stack build   # ✅ GHC 9.6.6 build succeeded
```

The module pattern is `import → open → bare call`: both `world.ast.json` and
`main.ast.json` need an `(open ...)` statement after their `(import ...)` —
without it, bare calls to imported functions (`glider-grid`, `make-world`,
`render-world`, `evolve`) fail with `unknown function`.

---

## Run Output (3 generations shown)

```
Conway's Game of Life — LLMLL v0.2 (press Ctrl-C to quit)

....................   ← Gen 0 (Glider)
....................
....................
..#.#...............
...##...............
...#................
```

Subsequent generations show correct Glider movement confirmed against reference.

---

## Gotchas

### Qualified names are not preserved through codegen

Calling an imported function with a qualified name (`world.glider-grid`) parses
and type-checks, but codegen merges all imported modules into a single flat
module — qualified calls don't survive to the generated Haskell. Use the bare
function name at call sites instead (`glider-grid`), even for functions imported
from another module; the `(import world)` statement is still required for the
resolver to load and merge the module.

If you write a dotted call anyway, the compiler catches it with:
`warning: dotted function name 'world.glider-grid' in app position is not
supported; use (open <module-path>) and call the bare exported name.`

### Import resolution is flat-directory-only

`(import world)` resolves to `world.ast.json` in the same directory as the
importing file. Cross-directory imports aren't supported.

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
