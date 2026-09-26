# life_json: Conway's Game of Life across three modules (JSON-AST)

Conway's Life on a 20×10 grid seeded with a glider, written directly in the
JSON-AST format (`*.ast.json`) that agents emit. Three modules exercise the
module system: transitive imports (`main → world → core`), an `export` list
that keeps `core`'s helpers private, and `import` plus `open` for bare calls.
This is a language and codegen example. No function carries a postcondition,
so `verify` proves nothing.

The same program in S-expression form is [`../life_sexp/`](../life_sexp/). The
contracted variant is [`../conways_life_json_verifier/`](../conways_life_json_verifier/).

| File | Module | Role |
|---|---|---|
| `core.ast.json` | LifeCore | Cell transition rule; exports only `next-cell-state` |
| `world.ast.json` | LifeWorld | Grid state, neighbor counting, `evolve`, rendering, glider seed |
| `main.ast.json` | LifeMain | `def-main` console loop: redraws the board, one generation per step |
| [`walkthrough.md`](walkthrough.md) | | Module pattern, gotchas (qualified names, flat-directory imports) |

## Build and run

Reproduced on llmll 0.26.5.

```bash
llmll check ./main.ast.json                     # ✅ ./main.ast.json — OK (7 statements)
llmll build main.ast.json -o /tmp/life-json     # generates and builds a Haskell package
cd /tmp/life-json && printf '\n\n' | stack exec main
```

Each line on stdin advances one generation. The board and glider are the same
as in `life_sexp`; this version clears the screen (ANSI `ESC[2J ESC[H`) before
each generation instead of printing a separator line. With `:done?` declared
and always false, the program exits **70** when stdin runs out (input
exhausted before `:done?` held). A run writes `main.event-log.jsonl` in the
working directory.

## What `verify` prints

```
$ llmll verify ./world.ast.json
   body-fallback: make-world, get-cell, count-neighbors, evolve-row, cell-to-char, make-empty-row, set-cell-in-row, set-cell-in-grid, glider-grid
   Running liquid-fixpoint ...
⚠️  ./world.ast.json — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```

`core.ast.json` and `main.ast.json` print the same `nothing proved` verdict.
All three exit 0.
