# LLMLL v0.1 — Implementation Tasks (Haskell + Rust)

## Phase 0: Spec & Planning
- [x] Read LLMLL.md spec
- [x] Read prior analysis documents
- [x] Analyze implementation language options (Rust vs Haskell vs Racket)
- [x] Choose Haskell compiler + Rust runtime architecture
- [x] Create and save implementation plan, language analysis, agent distribution
- [x] Save all planning documents to `planning/` subfolder

## Phase 1: Toolchain Setup (Agent A)
- [x] Install Haskell toolchain (GHCup: GHC 9.6.6, cabal 3.14, stack 3.7.1, HLS 2.13)
- [x] Verify Rust/Cargo 1.78.0 already installed
- [x] Scaffold Stack project (`package.yaml`, `stack.yaml`)

## Phase 2: Lexer & Parser (Agent A)
- [x] Syntax.hs — Full AST, types, holes, contracts, properties, modules, capabilities
- [x] Diagnostic.hs — Structured error types with S-expression formatting
- [x] Lexer.hs — Megaparsec tokenizer (all token kinds, hole syntax, operators)
- [x] Parser.hs — Full S-expression parser (module, def-logic, def-interface, type definitions, check blocks, holes, all expressions)
- [x] Main.hs — CLI with subcommands: check, holes, test, build
- [x] Test suite — 10 tests (4 lexer + 6 parser), all passing
- [x] Example file — `withdraw.llmll` from spec Section 4

## Phase 3: Type Checker (Agent B)
- [x] TypeCheck.hs — implemented
- [x] Two-pass checking with forward reference collection
- [x] Expression type inference (let, if, match, app, ops, holes, await, do-notation)
- [x] Pattern checking (Success/Error → Ok/Err, wildcards, literals)
- [x] Contract boolean validation (pre/post must be bool)
- [x] Type compatibility with TDependent and TVar wildcards

## Phase 4: Hole Analysis (Agent B)
- [x] HoleAnalysis.hs — implemented
- [x] Full AST traversal across all expression/type/statement forms
- [x] All 8 hole kinds classified (Blocking/AgentTask/NonBlocking)
- [x] S-expression and human-readable report formatting

## Phase 5: Contracts & PBT (Agent C)
- [x] Contracts.hs — implemented
- [x] Pre/post contract AST instrumentation (wrapPre/wrapPost via ELet assertions)
- [x] Symbolic evaluator with constant folding (all integer/bool operators)
- [x] Static contract violation detection
- [x] PBT.hs — implemented
- [x] 100-sample symbolic property testing with QuickCheck Gen
- [x] Direct QuickCheck integration for integer/bool properties
- [x] Counterexample extraction and reporting

## Phase 6: Rust Code Generation (Agent D)
- [x] Codegen.hs — implemented
- [x] Type alias and TDependent runtime validator emitter
- [x] Trait emitter for def-interface → Rust trait
- [x] Function emitter with assert!() contracts
- [x] Full expression translator (all ops, if/let/match/do/holes→todo!())
- [x] Proptest-flavoured check block test module emitter
- [x] Cargo.toml generation
- [x] `llmll build` wired to write src/lib.rs + Cargo.toml

## Phase 7: Rust WASM Runtime (Agent E)
- [x] runtime/ Rust crate scaffolded
- [x] Capability system with 14 kinds and prefix-based subsumption
- [x] Command/Response IO enum (HTTP, FS, DB, Noop, Sequence, Custom)
- [x] AppendOnly EventLog with JSON roundtrip serialization
- [x] ReplayEngine with command sequence validation
- [x] Runtime executor with capability checking before any IO
- [x] LlmllValue runtime value enum with Display
- [x] DelegationError kinds matching LLMLL spec
- [x] 8 unit tests passing

## Phase 8: CLI & Integration
- [x] CLI skeleton with `check`, `holes`, `test`, `build`, `repl` subcommands
- [x] `check` — parse + type-check, report diagnostics
- [x] `holes` — full hole analysis with blocking count + per-entry display
- [x] `test` — run all check blocks via PBT, report pass/fail/skip
- [x] `build` — emit Rust lib.rs + Cargo.toml, -o flag for custom output dir
- [x] `repl` — interactive REPL with :help/:quit/:check F/:holes F + AST display
- [x] `--json` flag — all subcommands emit structured JSON diagnostics
- [x] `--wasm` flag — detects wasm-pack, invokes `wasm-pack build` with JSON result
- [x] JSON ToJSON instances in Diagnostic.hs (aeson)
- [x] `putJsonError` helper for consistent error JSON across all commands
