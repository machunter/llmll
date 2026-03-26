# Conway's Game of Life — JSON-AST Walkthrough

**Date:** 2026-03-25  
**Compiler:** LLMLL v0.2 (Haskell backend)  
**Format:** JSON-AST (`*.ast.json`)

---

## What Was Built

A modular Conway's Game of Life with three modules exercising Phase 2a multi-file compilation:

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
stack exec llmll -- check ../examples/life_json/core.ast.json   # ✅ OK
stack exec llmll -- check ../examples/life_json/world.ast.json  # ✅ OK (17 statements)
stack exec llmll -- check ../examples/life_json/main.ast.json   # ✅ OK (6 statements)

stack exec llmll -- build ../examples/life_json/main.ast.json \
  -o ../generated/life_json --emit-only    # ✅ Haskell package generated

cd ../generated/life_json && stack build   # ✅ GHC 9.6.6 build succeeded
```

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

## Problems Encountered

### Problem 1 — Qualified names codegen to undefined Haskell identifiers

**Symptom:** Used `world.glider-grid`, `world.make-world`, `world.evolve`, `world.render-world` in `main.ast.json` (following §8.5 qualified-access docs). Generated Haskell contained `world_glider_grid` etc. which were **not in scope** — GHC error: `Variable not in scope: world_glider_grid`.

**Root cause:** The LLMLL Phase 2a codegen merges all imported modules into a **single flat `Lib.hs`**. Functions from `world` are emitted as bare Haskell names (`glider_grid`, `make_world`, etc.) without any module prefix. Qualified references from `main` are translated to `world_X` which don't exist.

**Fix:** Use bare function names in `main.ast.json` even for functions imported from other modules. The `(import world)` statement is still required for the resolver to load and merge the module, but call sites must use plain names.

**Compiler team note:** This is a known Phase 2a limitation. The docs (§4.8) correctly describe flat-layout requirements but do not explicitly state that qualified-access calls (`world.fn`) do NOT survive codegen in the current implementation. Consider either: (a) emitting Haskell modules per LLMLL module (Phase 2b multi-module layout), or (b) documenting in getting-started.md that `module.fn` call syntax is parsed/type-checked but currently flattened in codegen.

---

### Problem 2 — `(import world)` import path resolution

**Observation:** `llmll check ../examples/life_json/main.ast.json` correctly resolves `(import world)` to `world.ast.json` in the same directory (flat layout per §4.8 Phase 2a constraint). Cross-directory imports would break. This matches documented limitation.

**No fix required** — followed documented flat layout. Compiler team: the `--lib <dir>` flag planned for Phase 2b will resolve this.

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
