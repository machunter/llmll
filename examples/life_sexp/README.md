# life_sexp: Conway's Game of Life across three modules (S-expression)

Conway's Life on a 20×10 grid seeded with a glider, split into three modules
that exercise the module system: transitive imports (`main → world → core`),
an `export` list that hides `core`'s helpers, and the `import` then `open`
pattern for bare calls. This is a language and codegen example. No function
carries a postcondition, so `verify` proves nothing.

The same program in JSON-AST form is [`../life_json/`](../life_json/). The
contracted variant is [`../conways_life_json_verifier/`](../conways_life_json_verifier/).

| File | Module | Role |
|---|---|---|
| `core.llmll` | LifeCore | Cell transition rule; exports only `next-cell-state` |
| `world.llmll` | LifeWorld | Grid state, neighbor counting, `evolve`, rendering, glider seed |
| `main.llmll` | LifeMain | `def-main` console loop: prints the board, advances one generation per step |
| [`walkthrough.md`](walkthrough.md) | | Module-system checks, sample run, gotchas |

## Build and run

Output below reproduced on llmll 0.26.5.

```bash
llmll check ./main.llmll                    # ✅ ./main.llmll — OK (7 statements)
llmll build main.llmll -o /tmp/life-sexp    # generates and builds a Haskell package
cd /tmp/life-sexp && printf '\n\n' | stack exec main
```

Each line on stdin advances one generation, so two lines print the glider at
generations 0, 1 and 2:

```
Conway's Game of Life -- LLMLL v0.2 (press Ctrl-C to quit)

....................
..#.................
...#................
.###................
....................
...
----------------------------------------
Conway's Game of Life -- LLMLL v0.2

....................
....................
.#.#................
..##................
..#.................
...
```

The program declares `:done?` (always false), so when stdin runs out it exits
**70**, the disclosed exit code for input exhausted before `:done?` held
(`LLMLL.md`, console `def-main`). A run also writes `main.event-log.jsonl` in
the working directory.

## What `verify` prints

```
$ llmll verify ./world.llmll
   body-fallback: make-world, get-cell, count-neighbors, evolve-row, cell-to-char, make-empty-row, set-cell-in-row, set-cell-in-grid, glider-grid
   Running liquid-fixpoint ...
⚠️  ./world.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```

`core.llmll` and `main.llmll` print the same `nothing proved` verdict. All
three exit 0.
