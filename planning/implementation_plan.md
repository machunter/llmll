# LLMLL v0.1 Compiler — Implementation Plan (Haskell + Rust)

Implement the LLMLL v0.1.0 language using **Haskell** for the compiler front-end (lexer → parser → type checker → Rust code emitter) and **Rust** for the WASM host runtime (execution, capability sandbox, event log, replay).

## Architecture Overview

```
  .llmll source
       │
       ▼
 ┌─────────────────────────┐
 │   Haskell Compiler      │
 │  (compiler/)            │
 │                         │
 │  Lexer → Parser → AST   │
 │  → TypeCheck → Contracts │
 │  → PBT → Codegen        │
 │                         │
 │  Emits: Rust source +   │
 │         Cargo.toml      │
 └──────────┬──────────────┘
            │  generated .rs files
            ▼
 ┌─────────────────────────┐
 │   rustc / cargo         │
 │  (compile to WASM)      │
 └──────────┬──────────────┘
            │  .wasm binary
            ▼
 ┌─────────────────────────┐
 │   Rust Runtime          │
 │  (runtime/)             │
 │                         │
 │  Wasmtime host          │
 │  Capability enforcement │
 │  Command/Response loop  │
 │  Event Log + Replay     │
 └─────────────────────────┘
```

## User Review Required

> [!IMPORTANT]
> **JSON IR at the boundary.** The Haskell compiler emits Rust source code directly (string templates). An alternative is to emit a **JSON intermediate representation** that a Rust codegen tool consumes. The direct approach is simpler to start; JSON IR is more maintainable long-term. This plan starts with direct emission and can be refactored later.

> [!IMPORTANT]
> **Build orchestration.** The CLI (`llmll build`) will shell out to `cargo build --target wasm32-wasi` after emitting Rust source. This requires `rustup` and the `wasm32-wasi` target installed on the developer machine. An alternative is to bundle a Rust cross-compiler, but that's heavy. Starting with the shell-out approach is pragmatic.

> [!WARNING]
> **Dependent types in v0.1 are parse-only.** Constraint ASTs from `(where ...)` are stored but not evaluated at compile time. Z3 integration is deferred to v0.2.

---

## Proposed Changes

### Repository Layout

```
llmll/
├── LLMLL.md                    # Language spec
├── analysis/                   # Prior reviews
├── compiler/                   # Haskell project (Stack)
│   ├── package.yaml            # Stack/Cabal config
│   ├── stack.yaml
│   ├── src/
│   │   ├── LLMLL/
│   │   │   ├── Syntax.hs       # AST & type definitions
│   │   │   ├── Lexer.hs        # Tokenizer
│   │   │   ├── Parser.hs       # S-expression → AST
│   │   │   ├── TypeCheck.hs    # Semantic analysis
│   │   │   ├── Contracts.hs    # Pre/post instrumentation
│   │   │   ├── PBT.hs          # check block execution
│   │   │   ├── Codegen.hs      # AST → Rust source emission
│   │   │   ├── Diagnostic.hs   # Structured error types
│   │   │   └── HoleAnalysis.hs # Hole cataloging
│   │   └── Main.hs             # CLI entry point
│   ├── test/
│   │   └── Spec.hs             # HSpec + QuickCheck tests
│   └── examples/
│       └── withdraw.llmll      # Spec examples as test fixtures
├── runtime/                    # Rust project (Cargo)
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs             # CLI entry (run/replay)
│       ├── host.rs             # Wasmtime host setup
│       ├── capabilities.rs     # Capability enforcement
│       ├── command.rs          # Command/Response loop
│       ├── event_log.rs        # Recording & replay
│       └── determinism.rs      # Clock/PRNG virtualization
└── examples/                   # End-to-end test programs
    ├── withdraw.llmll
    └── cloud_storage.llmll
```

---

### Haskell Compiler — `compiler/`

---

#### [NEW] [Syntax.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Syntax.hs)

Core AST and type definitions as Haskell ADTs:

- **`Type`** — `TInt | TFloat | TString | TBool | TUnit | TBytes Int | TList Type | TMap Type Type | TResult Type Type | TFn [Type] Type | TPromise Type | TDependent Type Expr`
- **`Expr`** — `ELit Literal | EVar Name | ELet [(Name, Expr)] Expr | EIf Expr Expr Expr | EMatch Expr [(Pattern, Expr)] | EApp Name [Expr] | EPair Expr Expr | EHole HoleKind | EAwait Expr`
- **`HoleKind`** — `HNamed Name | HChoose [Name] | HRequestCap Text | HScaffold ScaffoldSpec | HDelegate DelegateSpec | HDelegateAsync DelegateSpec | HDelegatePending Type | HConflictResolution`
- **`DelegateSpec`** — `{ agent :: Name, description :: Text, returnType :: Type, onFailure :: Maybe Expr }`
- **`Statement`** — `SDefLogic Name [(Name, Type)] (Maybe Expr) (Maybe Expr) Expr | SDefInterface Name [(Name, Type)] | SModule Name [Import] [Statement] | SImport ImportSpec | SCheck Text Property | STypeDef Name TypeDef`
- **`Capability`** — including `:deterministic` flag
- **`Diagnostic`** — `{ severity, location, message, suggestion }`

Derives `Eq`, `Show`, `Generic` for all types. Uses `Data.Text` throughout.

---

#### [NEW] [Lexer.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Lexer.hs)

Built with **Megaparsec**. Tokenizes:
- Parens `(` `)`, brackets `[` `]`
- String/int/float/bool literals
- Keywords: `module`, `import`, `def-logic`, `def-interface`, `let`, `if`, `match`, `check`, `pre`, `post`, `for-all`, `type`, `where`, `pair`, `await`, `do`, `on-failure`
- Hole syntax: `?name`, `?choose(...)`, `?request-cap(...)`, `?scaffold(...)`, `?delegate`, `?delegate-async`
- Capability flags: `:deterministic`, `:language`, `:modules`, `:style`, `:version`
- Comments: `;; ...` to end of line
- Identifiers and type names
- Span tracking for error reporting

---

#### [NEW] [Parser.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Parser.hs)

Megaparsec parser combinators over the token stream:
- Recursive-descent over S-expressions
- Produces `[Statement]` (module-level AST)
- Handles all spec constructs: `(def-logic ...)`, `(def-interface ...)`, `(module ...)`, `(import ...)`, `(type ...)`, `(check ...)`, `(let ...)`, `(if ...)`, `(match ...)`, `(pair ...)`
- Parses dependent type `(where ...)` → stores constraint as AST subtree
- Reports errors as `Diagnostic` with source spans

---

#### [NEW] [TypeCheck.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs)

Monadic type checker using `ExceptT Diagnostic (State TypeEnv)`:
- **TypeEnv**: maps names to types, scoped via `Map` stack
- **Bidirectional checking**: infer bottom-up, check top-down
- **Immutability**: reject any shadowing/reassignment within the same scope
- **`def-interface`**: validate all function signatures are well-formed
- **`def-logic`**: check body against return type; validate `pre`/`post` are `bool`-typed
- **`?delegate`**: verify declared return type is valid; type-check `on-failure` expression
- **Capability analysis**: collect imports, compute `ReplayStatus` (✅ vs ⚠️)
- **Module well-formedness**: duplicate detection, import resolution

---

#### [NEW] [HoleAnalysis.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/HoleAnalysis.hs)

AST traversal cataloging every `?` node:
- Name, kind, inferred/declared type, agent target (for delegates), status
- Structured report as S-expression or JSON
- Flags unresolved holes that block execution vs holes that block only analysis

---

#### [NEW] [Contracts.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Contracts.hs)

AST-to-AST transform pass:
- Wraps each `def-logic` body with `pre`/`post` assertion nodes
- `pre` violation → `AssertionError` with contract expression + argument values
- `post` violation → `AssertionError` with contract expression + expected vs actual result
- These transform into `assert!()` macros in the Rust codegen

---

#### [NEW] [PBT.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/PBT.hs)

Interprets `(check ...)` blocks using QuickCheck:
- `for-all` → QuickCheck `forAll` with `Arbitrary` instances for LLMLL types
- Edge case generation: 0, -1, MAX_INT, MIN_INT, empty string, empty list
- Dependent type generation: generate base type, filter by constraint predicate
- Counterexample shrinking
- Report: pass/fail with minimal counterexample as S-expression

---

#### [NEW] [Codegen.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Codegen.hs)

Walks typed AST, emits Rust source code as `Text`:

| LLMLL | Rust |
|---|---|
| `int` | `i64` |
| `float` | `f64` |
| `string` | `String` |
| `bool` | `bool` |
| `bytes[n]` | `[u8; N]` |
| `list[t]` | `Vec<T>` |
| `map[k,v]` | `HashMap<K,V>` |
| `Result[t,e]` | `Result<T,E>` |
| `unit` | `()` |
| `def-logic` | `fn name(args) -> ReturnType { ... }` |
| `pre`/`post` | `assert!(...)` |
| `let` | `let name = ...;` |
| `if` | `if cond { ... } else { ... }` |
| `match` | `match expr { ... }` |
| Holes | `compile_error!("Unresolved hole: ...")` |
| Commands | Struct implementing `Command` trait |

Also emits a `Cargo.toml` for the generated project targeting `wasm32-wasi`.

---

#### [NEW] [Diagnostic.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Diagnostic.hs)

Structured error/warning type with S-expression and JSON serialization. All compiler phases produce `Diagnostic` values instead of raw strings.

---

#### [NEW] [Main.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs)

CLI entry point using `optparse-applicative`:
- `llmll check <file>` — parse + typecheck + hole report
- `llmll test <file>` — run `check` property tests via QuickCheck
- `llmll build <file> -o <dir>` — full pipeline: parse → typecheck → codegen → shell out to `cargo build --target wasm32-wasi`
- `llmll holes <file>` — list all holes with types and status
- `--json` flag for JSON output (default: S-expression diagnostics)

---

### Rust Runtime — `runtime/`

---

#### [NEW] [Cargo.toml](file:///Users/burcsahinoglu/Documents/llmll/runtime/Cargo.toml)

Dependencies: `wasmtime`, `wasmtime-wasi`, `serde`, `serde_json`, `clap`, `tokio`.

---

#### [NEW] [host.rs](file:///Users/burcsahinoglu/Documents/llmll/runtime/src/host.rs)

Wasmtime host setup:
- Load `.wasm` module
- Configure WASI with restricted capabilities based on module's declared imports
- Link host functions for each declared capability

---

#### [NEW] [capabilities.rs](file:///Users/burcsahinoglu/Documents/llmll/runtime/src/capabilities.rs)

Capability enforcement:
- Parse capability manifest from the WASM module's custom section (emitted by compiler)
- Allow/deny WASI calls based on imported capabilities
- Flag sensitive commands (e.g., `fs.delete`) for human review

---

#### [NEW] [command.rs](file:///Users/burcsahinoglu/Documents/llmll/runtime/src/command.rs)

Command/Response execution loop:
- Receive `Command` structs from WASM module
- Check permissions against capability list
- Execute IO via OS
- Feed `Result` back as next `Input`

---

#### [NEW] [event_log.rs](file:///Users/burcsahinoglu/Documents/llmll/runtime/src/event_log.rs)

Event Log recording and replay:
- Record: append `(event :seq N :input ... :result ... :captures [...])` per step
- Replay: read log, feed `:input` to module, inject `:result` and `:captures`
- Format: S-expression entries in a sequential file

---

#### [NEW] [determinism.rs](file:///Users/burcsahinoglu/Documents/llmll/runtime/src/determinism.rs)

Virtualization of non-deterministic WASI calls:
- **Clock:** intercept `wasi.clock.time_get`; record mode captures return value; replay mode returns captured value
- **PRNG:** intercept `wasi.random.get`; record mode captures seed + bytes; replay mode re-seeds from log
- **Float:** reject non-canonical NaN at WASM boundary

---

#### [NEW] [main.rs](file:///Users/burcsahinoglu/Documents/llmll/runtime/src/main.rs)

CLI using `clap`:
- `llmll-runtime run <file.wasm>` — execute with sandbox
- `llmll-runtime replay <file.wasm> <event-log>` — replay from log
- Reports execution results as structured S-expressions

---

## Verification Plan

### Automated Tests

**Haskell compiler tests** (HSpec + QuickCheck):
```bash
cd /Users/burcsahinoglu/Documents/llmll/compiler && stack test
```

| Module | Tests |
|---|---|
| `Lexer` | Tokenize every spec example; error on malformed tokens |
| `Parser` | Parse every code block from Sections 3–11 of LLMLL.md; round-trip (parse → pretty-print → parse → compare) |
| `TypeCheck` | `withdraw` types correctly; reassignment rejected; hole types inferred; `?delegate` return types validated; `ReplayStatus` computed |
| `Contracts` | `pre` violation caught; `post` violation caught; correct execution passes both |
| `PBT` | Commutativity check passes; deliberate violation found with counterexample; dependent type generation respects constraints |
| `Codegen` | `withdraw` → valid Rust source; compile output with `rustc`; holes → `compile_error!()` |
| `HoleAnalysis` | Correct catalog of all hole variants in a multi-hole program |

**Rust runtime tests:**
```bash
cd /Users/burcsahinoglu/Documents/llmll/runtime && cargo test
```

| Module | Tests |
|---|---|
| `capabilities` | Allow declared caps; deny undeclared caps |
| `event_log` | Record → replay produces identical state sequence |
| `determinism` | Clock/PRNG virtualization returns captured values on replay |

### End-to-End Smoke Test

```bash
# Parse + typecheck + hole report
llmll check examples/withdraw.llmll

# Run property tests
llmll test examples/withdraw.llmll

# Build to WASM
llmll build examples/withdraw.llmll -o build/

# Execute in sandbox
llmll-runtime run build/withdraw.wasm
```

### Manual Verification

- Inspect generated Rust code for readability
- Review structured diagnostic output for programs with intentional errors
- Confirm modules with `?delegate-pending` holes pass `check` but fail `build`
