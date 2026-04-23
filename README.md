# LLMLL — v0.6.1

**LLMLL** (Large Language Model Logical Language) is a programming language designed for AI-to-AI implementation under human direction. It prioritises contract clarity, token efficiency, and ambiguity elimination over human readability — the primary consumer of LLMLL source is an LLM agent, not a human programmer.

> See [CHANGELOG.md](CHANGELOG.md) for full release notes.

> **v0.6.1 is shipped.** TOTP RFC 6238 benchmark with 100% spec coverage (4 check blocks, 6 functions). `hmac-sha1`/`sha1` crypto builtins (§13.11). `llmll hub query --signature` for type-driven package search. Provenance display in `--trust-report`. Both benchmark CI gates pass (25/25). 279 tests passing. See [`CHANGELOG.md`](CHANGELOG.md).

---

## Compiler

The active compiler is a **Haskell stack project** in `compiler/`. It is the only supported backend as of v0.2.

| Command | What it does |
|---------|--------------| 
| `llmll check <file>` | Parse + type-check; emit structured diagnostics |
| `llmll holes <file> [--deps] [--deps-out FILE]` | List all `?hole` expressions. With `--deps`: include dependency graph in `--json` output. With `--deps-out`: persist graph to file. |
| `llmll test <file>` | Run property-based tests (`check`/`for-all` blocks via QuickCheck) |
| `llmll build <file> [-o <dir>]` | Generate a Haskell package (`src/Lib.hs` + `package.yaml` + `stack.yaml`). Accepts both `.llmll` S-expression and `.ast.json` JSON-AST sources. |
| `llmll verify <file> [--fq-out FILE] [--leanstral-mock] [--trust-report] [--weakness-check] [--obligations] [--spec-coverage]` | Emit `.fq` constraint file and run `liquid-fixpoint` (if installed). With `--leanstral-mock`, also runs Leanstral proof pipeline on `?proof-required` holes. With `--trust-report`, prints per-function trust summary with transitive closure, epistemic drift warnings, and `weakness-ok` suppressions. With `--weakness-check`, detects specs that admit trivial implementations. With `--obligations`, suggests postcondition strengthening when UNSAFE at cross-function boundaries. With `--spec-coverage` (v0.6.0), classifies every function and computes effective specification coverage ratio. |
| `llmll typecheck --sketch <file>` | **Phase 2c** — partial-program type inference. Returns inferred type for every `?hole` plus `holeSensitive`-annotated errors. v0.4.0: emits `invariant_suggestions` from pattern registry. |
| `llmll serve [--host H] [--port P] [--token T]` | **Phase 2c** — expose `--sketch` as `POST /sketch` HTTP endpoint for agent swarms. Default: `127.0.0.1:7777`. |
| `llmll checkout <file.ast.json> <pointer>` | **v0.3** — lock a `?hole` for exclusive agent editing. Returns a checkout token with local typing context (Γ, τ, Σ) since v0.3.5. Use `--release` to abandon, `--status` to query TTL. v0.4.0: CAP-1 capability enforcement active — checkout context reflects capability requirements. |
| `llmll patch <file.ast.json> <patch.json>` | **v0.3** — apply an RFC 6902 JSON-Patch to a checked-out hole. Re-verifies type safety before committing. |
| `llmll hub fetch <pkg>@<ver>` | Download a package into the hub cache (`~/.llmll/modules/`). |
| `llmll hub scaffold <template> [--output DIR]` | Generate a project from a `llmll-hub` skeleton template (`~/.llmll/templates/`). |
| `llmll hub query --signature <sig>` | **v0.6.1** — search hub cache for functions matching a type signature (e.g. `"int -> int -> int"`). |
| `llmll replay <source> <log>` | **v0.3.1** — rebuild program, replay event log inputs, compare outputs for determinism verification. |
| `llmll spec [--json]` | **v0.3.4** — emit agent prompt specification from compiler builtins. Text (default) or JSON output. |
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
| `examples/event_log_test/` | S-expression | v0.3.1 event log codegen validation |
| `examples/proof_required_test/` | S-expression | v0.3.1 Leanstral proof pipeline validation |
| `examples/erc20_token/` | JSON-AST | v0.6.0 ERC-20 benchmark — frozen ground truth with verification-scope matrix |
| `examples/totp_rfc6238/` | JSON-AST | v0.6.1 TOTP RFC 6238 benchmark — crypto builtins, RFC `:source` provenance |

---

## Repository layout

```
LLMLL.md                    ← canonical language specification (v0.6.0)
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
    Hub.hs                  ← llmll-hub registry fetch, scaffold, and local cache
    Sketch.hs               ← Partial-program type inference (--sketch)
    Serve.hs                ← HTTP endpoint for agent swarms (llmll serve)
    FixpointIR.hs           ← D4: .fq constraint IR + text emitter
    FixpointEmit.hs         ← D4: typed AST → .fq + ConstraintTable builder
    DiagnosticFQ.hs         ← D4: liquid-fixpoint output → [Diagnostic] with JSON Pointers
    Replay.hs               ← v0.3.1: JSONL event log parser + replay execution
    LeanTranslate.hs        ← v0.3.1: LLMLL contracts → Lean 4 theorem obligations
    MCPClient.hs            ← v0.3.1: MCP JSON-RPC client (mock-first)
    ProofCache.hs           ← v0.3.1: per-file .proof-cache.json sidecar (SHA-256)
    TrustReport.hs          ← v0.3.2: transitive trust closure analysis (--trust-report)
    VerifiedCache.hs        ← v0.3: .verified.json sidecar read/write
    WeaknessCheck.hs        ← v0.3.5: trivial-body spec weakness detection
    InvariantRegistry.hs    ← v0.4.0: pattern-based invariant suggestion database
    ObligationMining.hs     ← v0.4.0: downstream postcondition strengthening suggestions
    SpecCoverage.hs         ← v0.6.0: specification coverage metric + governance guardrails
    JsonPointer.hs          ← RFC 6901 pointer resolution + descendant hole search
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
  erc20_token/              ← v0.6.0 ERC-20 benchmark (frozen ground truth)
  totp_rfc6238/             ← v0.6.1 TOTP RFC 6238 benchmark
  pair_type_test/           ← TPair + do-notation test fixtures
  orchestrator_walkthrough/ ← Auth module orchestration exercise
docs/
  getting-started.md        ← Build guide, known-good patterns, schema versioning
  compiler-team-roadmap.md  ← Engineering backlog (v0.6.0 shipped, v0.7 planned)
  llmll-ast.schema.json     ← JSON-AST schema v0.2.0 (use with AI agents; CheckoutToken v0.3.0)
  orchestrator-walkthrough.md ← End-to-end orchestration walkthrough
  one-pager.md              ← Project overview / pitch document
  wasm-poc-report.md        ← v0.3.2: GHC WASM feasibility assessment
  design/                   ← Design discussions, proposals, and reviews
    INDEX.md                ← Reading guide for all design documents
    agent-orchestration.md  ← Orchestrator architecture design
    agent-prompt-semantics-gap.md ← Agent prompt gap analysis (approved)
    lead-agent.md           ← Lead Agent skeleton generation design
  archive/analysis/         ← Historical analysis docs
tools/
  llmll-orchestra/          ← Python orchestrator (pip package)
    llmll_orchestra/
      orchestrator.py       ← Fill-mode orchestrator
      lead_agent.py         ← v0.4.0: Lead Agent skeleton generation (plan/lead/auto modes)
      quality.py            ← v0.4.0: Skeleton quality heuristics
      agent.py              ← LLM agent interface
      compiler.py           ← Compiler CLI wrapper
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [`LLMLL.md`](LLMLL.md) | Full language specification — types, syntax, FFI, grammar, builtins |
| [`docs/getting-started.md`](docs/getting-started.md) | Build guide + known-good patterns + schema versioning (single reference for agents) |
| [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) | Engineering backlog — v0.6.0 shipped, v0.7 planned |
| [`docs/llmll-ast.schema.json`](docs/llmll-ast.schema.json) | Machine-readable JSON-AST schema |
| [`docs/orchestrator-walkthrough.md`](docs/orchestrator-walkthrough.md) | End-to-end multi-agent orchestration walkthrough with auth module exercise |
| [`docs/one-pager.md`](docs/one-pager.md) | Project overview — problem, approach, status, related work |
| [`docs/design/INDEX.md`](docs/design/INDEX.md) | Reading guide for all active design documents |
| [`docs/wasm-poc-report.md`](docs/wasm-poc-report.md) | v0.3.2 GHC WASM feasibility assessment (conditional GO — feasibility confirmed) |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes by version |

---

## License

GPLv3 with LLMLL Runtime Library Exception — see [`LICENSE`](LICENSE).
