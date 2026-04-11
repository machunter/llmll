# LLMLL — v0.2 (v0.3 in development)

**LLMLL** (Large Language Model Logical Language) is a programming language designed for AI-to-AI implementation under human direction. It prioritises contract clarity, token efficiency, and ambiguity elimination over human readability — the primary consumer of LLMLL source is an LLM agent, not a human programmer.

> See [CHANGELOG.md](CHANGELOG.md) for full release notes.

> **v0.3 development is underway.** PRs 1–4 have merged: TPair introduction (PR 1), DoStep collapse (PR 2), emitDo rewrite soundness fix (PR 3), and pair destructuring in `let` bindings (PR 4). `EPair` expressions are correctly typed `TPair a b`. `do`-notation is fully implemented with type-safe state threading and compiles to pure `let`-chains. Pair destructuring — `(let [((pair s cmd) expr)] ...)` — is now available in both S-expression and JSON-AST. See [`docs/archive/analysis/do_notation/do_notation_implementation_plan.md`](docs/archive/analysis/do_notation/do_notation_implementation_plan.md).

---

## Compiler

The active compiler is a **Haskell stack project** in `compiler/`. It is the only supported backend as of v0.2.

| Command | What it does |
|---------|--------------| 
| `llmll check <file>` | Parse + type-check; emit structured diagnostics |
| `llmll holes <file>` | List all `?hole` expressions (blocking and informational) |
| `llmll test <file>` | Run property-based tests (`check`/`for-all` blocks via QuickCheck) |
| `llmll build <file> [-o <dir>]` | Generate a Haskell package (`src/Lib.hs` + `package.yaml` + `stack.yaml`). Accepts both `.llmll` S-expression and `.ast.json` JSON-AST sources. |
| `llmll verify <file> [--fq-out FILE]` | Emit `.fq` constraint file and run `liquid-fixpoint` (if installed). Reports SAFE or contract-violation diagnostics with JSON Pointers. |
| `llmll typecheck --sketch <file>` | **Phase 2c** — partial-program type inference. Returns inferred type for every `?hole` plus `holeSensitive`-annotated errors. |
| `llmll serve [--host H] [--port P] [--token T]` | **Phase 2c** — expose `--sketch` as `POST /sketch` HTTP endpoint for agent swarms. Default: `127.0.0.1:7777`. |
| `llmll checkout <file.ast.json> <pointer>` | **v0.3** — lock a `?hole` for exclusive agent editing. Returns a checkout token. Use `--release` to abandon, `--status` to query TTL. |
| `llmll patch <file.ast.json> <patch.json>` | **v0.3** — apply an RFC 6902 JSON-Patch to a checked-out hole. Re-verifies type safety before committing. |
| `llmll hub --from-file <tarball>` | Install a local `.tar.gz` package into the hub cache (`~/.llmll/modules/`). |
| `llmll repl` | Start an interactive LLMLL REPL |

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
| `examples/life_sexp/` | S-expression | Conway's Game of Life; multi-module (`core`, `world`, `main`) |
| `examples/life_json/` | JSON-AST | Same Life program in JSON-AST format |
| `examples/withdraw.llmll` | S-expression | Simple withdraw with `pre`/`post` contracts; acceptance gate |
| `examples/hangman_json_verifier/` | JSON-AST | Hangman with verified `apply-guess` contracts (`llmll verify`) |
| `examples/tictactoe_json_verifier/` | JSON-AST | Tic-Tac-Toe with verified `set-cell` contracts |
| `examples/conways_life_json_verifier/` | JSON-AST | Conway's Life with verified `count-neighbors` and `next-cell` contracts |
| `examples/pair_type_test/` | Mixed | TPair type system and do-notation test fixtures |

---

## Repository layout

```
LLMLL.md                    ← canonical language specification (v0.2; v0.3 in development)
CHANGELOG.md                ← release notes
compiler/                   ← Haskell compiler (stack project)
  src/LLMLL/
    Parser.hs               ← S-expression parser (Megaparsec)
    Lexer.hs                ← Megaparsec lexer (tokens, whitespace, layout)
    ParserJSON.hs           ← JSON-AST parser
    Syntax.hs               ← AST types (incl. ModulePath, ModuleEnv, ModuleCache, TPair — v0.3)
    TypeCheck.hs            ← Bidirectional type checker
    HoleAnalysis.hs         ← Hole collector (?hole expressions)
    CodegenHs.hs            ← Haskell code emitter
    AstEmit.hs              ← JSON-AST emitter (--emit json-ast round-trip)
    Contracts.hs            ← Runtime contract assertion generator
    PBT.hs                  ← QuickCheck property runner
    Diagnostic.hs           ← Structured error/warning types
    Module.hs               ← Multi-file module resolver, cycle detection, ModuleCache
    Hub.hs                  ← llmll-hub registry fetch and local cache
    Sketch.hs               ← Partial-program type inference (--sketch)
    Serve.hs                ← HTTP endpoint for agent swarms (llmll serve)
    FixpointIR.hs           ← D4: .fq constraint IR + text emitter
    FixpointEmit.hs         ← D4: typed AST → .fq + ConstraintTable builder
    DiagnosticFQ.hs         ← D4: liquid-fixpoint output → [Diagnostic] with JSON Pointers
  package.yaml / stack.yaml
examples/
  hangman_sexp/             ← Full Hangman (S-expression)
  hangman_json/             ← Full Hangman (JSON-AST)
  tictactoe_sexp/           ← Tic-Tac-Toe (S-expression)
  tictactoe_json/           ← Tic-Tac-Toe (JSON-AST)
  life_sexp/                ← Conway's Life (S-expression, multi-module)
  life_json/                ← Conway's Life (JSON-AST, multi-module)
  withdraw.llmll            ← Contract demo
  hangman_json_verifier/    ← Hangman with verified contracts
  tictactoe_json_verifier/  ← Tic-Tac-Toe with verified contracts
  conways_life_json_verifier/ ← Life with verified contracts
  pair_type_test/           ← TPair + do-notation test fixtures
docs/
  getting-started.md        ← Build guide, known-good patterns, schema versioning
  compiler-team-roadmap.md  ← Engineering backlog
  llmll-ast.schema.json     ← JSON-AST schema v0.2.0 (use with AI agents)
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
