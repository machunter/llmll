# Conway's Game of Life — JSON-AST Walkthrough

**Date:** 2026-03-25 (original); re-verified 2026-07-02 against llmll 0.14.2 — still builds and runs, with two corrections noted inline below (a missing `(open world)` statement that broke the build until this pass, and an improved compiler error message for Problem 1)  
**Compiler:** LLMLL v0.2 (Haskell backend) at original authoring time  
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
stack exec llmll -- check ../examples/life_json/core.ast.json   # ✅ OK (5 statements)
stack exec llmll -- check ../examples/life_json/world.ast.json  # ✅ OK (18 statements)
stack exec llmll -- check ../examples/life_json/main.ast.json   # ✅ OK (7 statements, 1 warning)

stack exec llmll -- build ../examples/life_json/main.ast.json \
  -o ../generated/life_json --emit-only    # ✅ Haskell package generated

cd ../generated/life_json && stack build   # ✅ GHC 9.6.6 build succeeded
```

> **Statement counts bumped by one (world 17→18, main 6→7) since the original run:** both `world.ast.json` and `main.ast.json` were missing an `(open ...)` statement after their `(import ...)` — the LLMLL module pattern is `import → open → bare call`, and without `open`, bare calls to imported functions (`glider-grid`, `make-world`, `render-world`, `evolve`) failed with "unknown function." This wasn't a regression introduced since 2026-03-25; the files simply never had it and `llmll build` genuinely failed until this pass added it (see the repo's git history for `examples/life_json/{world,main}.ast.json`). Fixed as part of this re-verification.

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

> **Update (2026-07-02, llmll 0.14.2):** the underlying limitation is unchanged — `module.fn` calls still don't survive codegen — but the compiler now catches this immediately with a clear, actionable message instead of the confusing downstream GHC "not in scope" error described above: `warning: dotted function name 'world.glider-grid' in app position is not supported; use (open <module-path>) and call the bare exported name.` Confirmed live. (b) from the note above has effectively happened at the compiler-error level rather than in the docs.

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
