# LLMLL — v0.1.3.1

**LLMLL** (Large Language Model Logical Language) is a programming language designed for AI-to-AI implementation under human direction. It prioritises contract clarity, token efficiency, and ambiguity elimination over human readability — the primary consumer of LLMLL source is an LLM agent, not a human programmer.

> See [CHANGELOG.md](CHANGELOG.md) for full release notes.

---

## Compiler

The active compiler is a **Haskell stack project** in `compiler/`. It is the only supported backend as of v0.1.3.

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

### Build the compiler

Requires GHC ≥ 9.4 + Stack ≥ 2.9.

```bash
cd compiler
stack build
stack exec llmll -- --help
```

→ Full build guide and known-good patterns: [`docs/getting-started.md`](docs/getting-started.md)

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
| `examples/tictactoe_sexp/` | S-expression | Two-player Tic-Tac-Toe; demonstrates `:done?` + `:on-done` |
| `examples/tictactoe_json/` | JSON-AST | Same Tic-Tac-Toe program in JSON-AST format |
| `examples/withdraw.llmll` | S-expression | Simple withdraw with `pre`/`post` contracts; acceptance gate |

---

## Repository layout

```
LLMLL.md                    ← canonical language specification (v0.1.3.1)
CHANGELOG.md                ← release notes
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
  tictactoe_sexp/           ← Tic-Tac-Toe (S-expression)
  tictactoe_json/           ← Tic-Tac-Toe (JSON-AST)
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
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes by version |

---

## License

GPLv3 with LLMLL Runtime Library Exception — see [`LICENSE`](LICENSE).
