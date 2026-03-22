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
- **New built-ins** — `(string-trim s)` (strip whitespace/newlines) and `(list-nth xs i)` (safe indexed access returning `Result[a,string]`).
- **PBT skip diagnostic** — `llmll test` skipped properties now distinguish between "Command-producing function" and "non-constant expression" — makes it clear when a property was skipped due to `Command` vs. a genuine non-evaluable expression.

### Spec (LLMLL.md)

- **§3.4** — nominal alias limitation block removed; replaced with accurate v0.1.2 description
- **§13.4** — `first`/`second` signature note: "accepts any pair, including explicitly-annotated parameters"
- **§13.5** — `list-nth` added
- **§13.6** — `string-trim` added

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
  getting-started/          ← build-instructions.md
  compiler-team-roadmap.md
  json-ast-versioning.md
  llmll-ast.schema.json     ← JSON-AST schema (use with AI agents)
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [`LLMLL.md`](LLMLL.md) | Full language specification — types, syntax, FFI, grammar, builtins |
| [`docs/getting-started/build-instructions.md`](docs/getting-started/build-instructions.md) | Step-by-step compilation walkthrough |
| [`docs/json-ast-versioning.md`](docs/json-ast-versioning.md) | JSON-AST schema versioning and AI agent guidance |
| [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) | v0.2 / v0.3 planned features |
| [`docs/llmll-ast.schema.json`](docs/llmll-ast.schema.json) | Machine-readable JSON-AST schema |

---

## License

GPLv3 with LLMLL Runtime Library Exception — see [`LICENSE`](LICENSE).
