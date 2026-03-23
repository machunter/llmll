# LLMLL

**LLMLL** (Large Language Model Logical Language) is a programming language designed for AI-to-AI implementation under human direction. It prioritises contract clarity, token efficiency, and ambiguity elimination over human readability — the primary consumer of LLMLL source is an LLM agent, not a human programmer.

## Compiler status — v0.1.3.1

The active compiler is a **Haskell stack project** in `compiler/`. It replaces the earlier Rust/WASM backend and is the only supported backend as of v0.1.3.

| Command | What it does |
|---------|--------------|
| `llmll check <file>` | Parse + type-check; emit structured diagnostics |
| `llmll holes <file>` | List all `?hole` expressions (blocking and informational) |
| `llmll test <file>` | Run property-based tests (`check`/`for-all` blocks via QuickCheck) |
| `llmll build <file> [-o <dir>]` | Generate a Haskell package (`src/Lib.hs` + `package.yaml` + `stack.yaml`). Accepts both `.llmll` S-expression and `.ast.json` JSON-AST sources. |

### Input formats

Both source formats compile to identical AST nodes:

| Format | Extension | Best for |
|--------|-----------|----------|
| S-expressions | `.llmll` | Human editing, concise iteration |
| JSON-AST | `.ast.json` | AI agents — schema-constrained, structurally valid by construction |

The JSON-AST schema is at `docs/llmll-ast.schema.json`.

### Building the compiler

```bash
cd compiler
stack build          # compile
stack test           # run test suite
stack exec llmll -- --help
```

Requires GHC 9.6.6 + Stack. Run `stack setup` if the resolver is missing.

---

## Quick start

```bash
cd compiler

# Check the example
stack exec llmll -- check ../examples/hangman_sexp/hangman.llmll

# Build a Haskell package in generated/hangman_sexp
stack exec llmll -- build ../examples/hangman_sexp/hangman.llmll -o ../generated/hangman_sexp

# Build from JSON-AST
stack exec llmll -- build ../examples/hangman_json/hangman.ast.json -o ../generated/hangman_json

# Run the generated game
cd ../generated/hangman_json && stack build && stack exec hangman
```

---

## Examples

| Example | Format | Description |
|---------|--------|-------------|
| `examples/hangman_sexp/` | S-expression | Full Hangman game with ASCII gallows art; uses `def-main :mode console` |
| `examples/hangman_json/` | JSON-AST | Same program, JSON-AST schema-constrained version |
| `examples/withdraw.llmll` | S-expression | Simple withdraw with `pre`/`post` contracts; acceptance gate |

---

## What's new in v0.1.3

### Compiler

- **`first`/`second` pair projectors** — now accept any pair argument regardless of explicit type annotations. Previously a parameter annotated as any type (e.g. `s: string`) that was actually a pair would cause `expected Result[a,b], got string`. The `untyped: true` workaround is no longer required on state accessor parameters.
- **`where`-clause binding variable in scope** — `TDependent` now carries the binding name; `TypeCheck.hs` uses `withEnv` during constraint type-checking. Eliminates `unbound variable 's'` false warnings on all dependent type aliases.
- **Nominal alias expansion** — `TCustom "Word"` is now expanded to its structural body before `compatibleWith`. Eliminates all `expected Word, got string` / `expected GuessCount, got int` spurious errors. All examples now check with **0 errors**.
- **New built-ins** — `(string-trim s)`, `(list-nth xs i)`, `(string-concat-many parts)`, `(lit-list ...)` (JSON-AST list literal node).
- **PBT skip diagnostic** — `llmll test` skipped properties now distinguish between "Command-producing function" and "non-constant expression". `bodyMentionsCommand` heuristic narrowed to only genuine WASI/IO prefixes — eliminates false-positive skips on user-defined functions.
- **Check label sanitization** — `check` block labels containing special characters (`(`, `)`, `+`, `?`, spaces) are now automatically sanitized before being used as Haskell `prop_*` function names. Previously these caused `stack build` failures with `Invalid type signature`.
- **S-expression list literals in expression position** — `[a b c]` and `[]` are now valid in S-expression expression position (not just parameter lists). Desugars to `foldr list-prepend (list-empty)`, symmetric with JSON-AST `lit-list`.
- **`ok`/`err` preamble aliases** — generated `Lib.hs` now exports `ok = Right` and `err = Left` alongside the existing `llmll_ok`/`llmll_err`. Fixes `Variable not in scope: ok` GHC errors on programs using `Result` values.
- **Console harness `done?` ordering** — `:done?` predicate is now checked at the **top** of the loop (before reading stdin) instead of after `step`. Eliminates the extra render that occurred when a game ended.
- **`--emit-only` flag** — `llmll build` and `llmll build-json` accept `--emit-only` to write Haskell files without invoking the internal `stack build`. Resolves the Stack project lock deadlock when build is called from inside a running `stack exec llmll -- repl` session.
- **`-Wno-overlapping-patterns` pragma** — generated `Lib.hs` now suppresses GHC spurious overlapping-pattern warnings from match catch-all arms. Also extended exhaustiveness detection for Bool matches and any-variable-arm matches.
- **JSON-AST schema version `0.1.3`** — `expectedSchemaVersion` in `ParserJSON.hs` and `llmll-ast.schema.json` bumped from `0.1.2` to `0.1.3`. The docs already showed `0.1.3` in examples; now the compiler accepts it.
- **`:on-done` codegen fix** — generated console harness now calls `:on-done fn` inside the loop when `:done?` returns `true`, before exiting. Previously it was emitted after the `where` clause (S-expression path: GHC parse error) or silently omitted (JSON-AST path).

### Spec (LLMLL.md)

- **§3.2** — pair-type issues split into Issue A (pair-type-param, parse error, Fixed v0.2) and Issue B (first/second, Fixed v0.1.3.1)
- **§12** — check label identifier rule added; S-expr list-literal production documented
- **§13.5** — `lit-list` JSON-AST node and S-expr `[...]` syntax documented (v0.1.3.1+)
- **§10** — `:on-done` console harness note updated: callback now fires inside the loop, not after the `where` clause

---

## What's new in v0.1.2

### Compiler

- **Haskell codegen backend** — replaces the Rust backend entirely. Generated output: `src/Lib.hs` + `package.yaml` + `stack.yaml`, buildable with `stack build`.
- **JSON-AST input** — `llmll build` auto-detects `.ast.json` extension and parses JSON directly. Avoids S-expression parser ambiguities for AI-generated code.
- **`def-main` support** — new `def-main :mode console|cli|http` entry-point declaration generates a full `src/Main.hs` harness:
  - `:mode console` — interactive stdin/stdout loop with `hIsEOF` guard (no `hGetLine: end of file` on exit)
  - `:mode cli` — single-shot from OS args
  - `:mode http PORT` — stub HTTP server
- **`llmll holes`** — works on files with `def-main` (previously crashed with non-exhaustive pattern)
- **Let-scope fix** — sequential `let` bindings now each extend the type environment for subsequent bindings; unbound variable false-positives eliminated
- **Overlapping pattern fix** — `match` codegen no longer emits a redundant `_ -> error "..."` arm when the last explicit arm is already a wildcard
- **Both `let` syntaxes accepted** — single-bracket `(let [(x e)] body)` (v0.1.2 canonical) and double-bracket `(let [[x e]] body)` (v0.1.1, backward-compat) both compile to identical AST

### Spec (LLMLL.md)

- **§9.5 `def-main`** — fully documented: syntax, all three modes, key semantics, S-expression + JSON-AST examples
- **§12 Formal Grammar** — `def-main` EBNF production added; `def-main` added to `statement` production
- **§14 Migration notes** — corrected: both `let` forms are accepted; not "replaced"

### Examples

- Rust-era examples removed (`tictactoe`, `my_ttt`, `ttt_3`, `tasks_service`, `todo_service`, `hangman_complete`, `specifications/`)
- `examples/hangman_sexp/` and `examples/hangman_json/` added — both compile and run end-to-end

---

## Repository layout

```
LLMLL.md                    ← canonical language specification (v0.1.2)
compiler/                   ← Haskell compiler (stack project)
  src/LLMLL/
    Parser.hs               ← S-expression parser (Megaparsec)
    ParserJSON.hs           ← JSON-AST parser
    Syntax.hs               ← AST types
    TypeCheck.hs            ← Bidirectional type checker
    HoleAnalysis.hs         ← Hole collector (?hole expressions)
    CodegenHs.hs            ← Haskell code emitter
    PBT.hs                  ← QuickCheck property runner
    Diagnostic.hs           ← Structured error/warning types
  package.yaml / stack.yaml
examples/
  hangman_sexp/             ← Full Hangman (S-expression)
  hangman_json/             ← Full Hangman (JSON-AST)
  withdraw.llmll            ← Contract demo
docs/
  getting-started.md        ← Build guide, known-good patterns, schema versioning
  compiler-team-roadmap.md  ← Engineering backlog
  llmll-ast.schema.json     ← JSON-AST schema (use with AI agents)
  archive/analysis/         ← Historical analysis docs
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [`LLMLL.md`](LLMLL.md) | Full language specification — types, syntax, FFI, grammar, builtins |
| [`docs/getting-started.md`](docs/getting-started.md) | Build guide + known-good patterns + schema versioning (single reference for agents) |
| [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) | Engineering backlog — v0.2 / v0.3 planned features |
| [`docs/llmll-ast.schema.json`](docs/llmll-ast.schema.json) | Machine-readable JSON-AST schema |

---

## License

GPLv3 with LLMLL Runtime Library Exception — see [`LICENSE`](LICENSE).
