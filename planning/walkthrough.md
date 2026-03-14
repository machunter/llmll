# LLMLL Compiler — Complete Build Walkthrough

## All Phases Complete ✅

| Phase | What | Status |
|-------|------|--------|
| 0 | Spec, planning, agent distribution | ✅ |
| 1 | Haskell/Rust toolchain setup | ✅ |
| 2 | Lexer + Parser (Agent A) | ✅ 10/10 tests |
| 3 | Type Checker (Agent B) | ✅ |
| 4 | Hole Analysis (Agent B) | ✅ |
| 5 | Contracts + PBT (Agent C) | ✅ |
| 6 | Rust Codegen (Agent D) | ✅ |
| 7 | Rust WASM Runtime (Agent E) | ✅ 8/8 tests |
| 8 | CLI polish: --json, REPL, WASM, -o | ✅ |

## Test Results

**Haskell — 10/10 ✅**

```
Lexer: 4 passed | Parser: 6 passed | 0 failures
```

**Rust runtime — 8/8 ✅**

```
capability_subsumes_all, capability_subsumes_prefix, capability_readwrite_subsumes_read,
capability_set_denies_missing, event_log_append, runtime_noop,
runtime_capability_denied, event_log_serialization — all ok
```

## CLI Validation

### Human-readable output

```
$ llmll check withdraw.llmll
✅ withdraw.llmll — OK (4 statements)

$ llmll holes withdraw.llmll
withdraw.llmll — 0 holes (0 blocking)

$ llmll test withdraw.llmll
withdraw.llmll — 2 properties
  ✅ Passed:  1
  ⚠️  Skipped: 1

$ llmll build withdraw.llmll -o /tmp/llmll_out
✅ Generated Rust crate: /tmp/llmll_out
   ℹ️  pass --wasm to compile to WebAssembly

$ llmll repl
LLMLL REPL v0.1 — type :help for commands, :quit to exit
llmll> :help
  :check F  — parse and type-check file
  :holes F  — show holes in file
  :quit     — exit
```

### JSON output (`--json` flag)

```json
// llmll --json check withdraw.llmll
{"diagnostics":[],"phase":"typecheck","success":true}

// llmll --json holes withdraw.llmll
{"blocking":0,"file":"withdraw.llmll","holes":[],"total":0}

// llmll --json test withdraw.llmll
{"failed":0,"passed":1,"skipped":1,"total":2,"results":[...]}

// llmll --json build withdraw.llmll
{"file":"withdraw.llmll","out_dir":"generated/withdraw","success":true,"warnings":[]}
```

### WASM pipeline

```
$ llmll build withdraw.llmll --wasm
# If wasm-pack is missing:
❌ wasm-pack not found in PATH — install from https://rustwasm.github.io/wasm-pack/

# If wasm-pack is present:
🔨 Running wasm-pack build generated/withdraw --target web --release
✅ WASM output: generated/withdraw/pkg
```

## Architecture

```
compiler/
  Syntax.hs       — Full AST
  Lexer.hs        — Megaparsec tokenizer
  Parser.hs       — S-expression → AST
  TypeCheck.hs    — Bidirectional type checker (State monad)
  HoleAnalysis.hs — AST traversal, 8 hole kinds
  Contracts.hs    — Pre/post instrumentation + symbolic evaluator
  PBT.hs          — QuickCheck property runner
  Codegen.hs      — AST → Rust source emitter
  Diagnostic.hs   — Structured errors + JSON (aeson)
  Main.hs         — CLI: check/holes/test/build/repl + --json/--wasm/-o

runtime/ (Rust)
  Capability      — 14 kinds, prefix-based subsumption
  Command         — IO intent enum
  EventLog        — Append-only, JSON roundtrip
  ReplayEngine    — Deterministic replay
  Runtime         — Capability-gated executor
  LlmllValue      — Runtime value enum
```
