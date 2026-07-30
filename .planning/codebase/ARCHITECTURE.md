# Architecture

**Analysis Date:** 2026-07-30

## System Overview

The LLMLL compiler is a **multi-phase AI-to-AI programming language system** that compiles LLMLL (Large Language Model Logical Language) source code into verified Haskell implementations. The architecture revolves around a staged verification and code-generation pipeline:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLI Entry Point                              │
│                      compiler/app/Main.hs                            │
│  (check, build, verify, test, checkout, patch, serve, etc.)         │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
      ┌────────────────┼────────────────┐
      │                │                │
      ▼                ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   Parsing    │ │   Module     │ │   Type       │
│   Layer      │ │   Loading    │ │   Checking   │
├──────────────┤ ├──────────────┤ ├──────────────┤
│ Parser.hs    │ │ Module.hs    │ │ TypeCheck.hs │
│ ParserJSON   │ │ Hub.hs       │ │ Sketch.hs    │
└──────────────┘ └──────────────┘ └──────────────┘
                       │
      ┌────────────────┴────────────────┐
      │                                 │
      ▼                                 ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│   Code Generation Layer  │    │   Verification Layer     │
├──────────────────────────┤    ├──────────────────────────┤
│ CodegenHs.hs             │    │ FixpointEmit.hs          │
│ generateHaskell          │    │ emitFixpoint             │
│ → generated/ Haskell pkg │    │ → .fq constraints        │
│                          │    │ DiagnosticFQ.hs          │
│                          │    │ liquid-fixpoint runner   │
└──────────────────────────┘    └──────────────────────────┘
      │                                 │
      ▼                                 ▼
┌──────────────────────────────────────────────────────┐
│           Runtime & Trust Reporting                   │
├──────────────────────────────────────────────────────┤
│ TrustReport.hs    - verification evidence aggregation │
│ VerifiedCache.hs  - sidecar .verified.json storage   │
│ ProofArtifact.hs  - replayable proof records         │
│ Checkout.hs       - hole-filling state management    │
│ PatchApply.hs     - RFC 6902 patch application       │
└──────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| **Parsing** | Parse .llmll S-expression or .ast.json AST into Statement list | `compiler/src/LLMLL/Parser.hs`, `ParserJSON.hs` |
| **Module System** | Resolve imports, load transitive dependencies, build ModuleCache | `compiler/src/LLMLL/Module.hs` |
| **Hub Resolver** | Resolve hub.* imports from ~/.llmll/modules/ cache | `compiler/src/LLMLL/Hub.hs` |
| **Type Checker** | Bidirectional type inference, contract validation, hole analysis | `compiler/src/LLMLL/TypeCheck.hs` |
| **Sketch Inference** | Bidirectional hole-type inference for agent context | `compiler/src/LLMLL/Sketch.hs` |
| **Haskell Codegen** | Transpile typed AST to Haskell source + package.yaml | `compiler/src/LLMLL/CodegenHs.hs` |
| **Verification** | Emit liquid-fixpoint constraints for QF-LIA fragment | `compiler/src/LLMLL/FixpointEmit.hs` |
| **Verification Diagnostic** | Parse liquid-fixpoint results, structure diagnostics | `compiler/src/LLMLL/DiagnosticFQ.hs` |
| **Trust Reporting** | Aggregate verification evidence per function | `compiler/src/LLMLL/TrustReport.hs` |
| **Hole Analysis** | Classify holes (blocking vs agent task), dependency analysis | `compiler/src/LLMLL/HoleAnalysis.hs` |
| **Checkout/Release** | Manage exclusive hole locks for agent editing | `compiler/src/LLMLL/Checkout.hs` |
| **Patch Application** | Apply RFC 6902 JSON-Patches to AST holes | `compiler/src/LLMLL/PatchApply.hs` |
| **Proof Artifacts** | Record and replay verification runs | `compiler/src/LLMLL/ProofArtifact.hs` |
| **Contract Instruments** | Runtime assertion generation per contract mode | `compiler/src/LLMLL/Contracts.hs` |
| **HTTP Serving** | Sketch query endpoint for agent integration | `compiler/src/LLMLL/Serve.hs` |

## Pattern Overview

**Overall:** Multi-phase compiler pipeline with decoupled verification backend and hole-filling workflow.

**Key Characteristics:**
- S-expression language with optional JSON-AST serialization
- Modular multi-file imports with hub-based package management
- Bidirectional type checking with hole-driven development support
- Contracts (pre/post conditions) as first-class verification primitives
- QF-LIA verification via liquid-fixpoint (D4 backend)
- Haskell transpilation with runtime assertion instrumentation
- Checkout/patch workflow for AI-assisted hole filling
- Trust reports recording verification evidence per function
- Proof artifacts for replayable verification records

## Layers

**Parsing Layer:**
- Purpose: Convert source text to structured AST (S-expression parser or JSON)
- Location: `compiler/src/LLMLL/Parser.hs`, `ParserJSON.hs`, `Lexer.hs`
- Contains: Lexer (tokenization), S-expression parser, JSON-AST parser
- Depends on: none (foundational)
- Used by: Module loader, all downstream phases

**Module & Import Resolution Layer:**
- Purpose: Resolve imports, load transitive dependencies, manage ModuleCache
- Location: `compiler/src/LLMLL/Module.hs`, `Hub.hs`
- Contains: File-system resolver, hub cache resolver, cycle detection, topological sort
- Depends on: Parsing layer (parseTopLevel), Syntax (ModulePath)
- Used by: Type checker, codegen (via Main.hs orchestration)

**Type Checking Layer:**
- Purpose: Bidirectional type inference, contract validation, hole analysis
- Location: `compiler/src/LLMLL/TypeCheck.hs`, `Sketch.hs`, `HoleAnalysis.hs`
- Contains: Type environment, unification, contract checking, hole classification
- Depends on: Syntax (types, contracts), Module (qualified imports)
- Used by: Verification backend, codegen (type-checked AST assumed), hole filling

**Code Generation Layer:**
- Purpose: Transpile type-checked AST to executable Haskell
- Location: `compiler/src/LLMLL/CodegenHs.hs`
- Contains: Haskell emitter, package/stack.yaml scaffolding, FFI stub generation
- Depends on: Syntax (typed AST), Contracts (for instrumentation)
- Used by: `llmll build`, `llmll run`, Main.hs commands

**Verification Backend (D4):**
- Purpose: Emit liquid-fixpoint constraints, parse results, structure diagnostics
- Location: `compiler/src/LLMLL/FixpointEmit.hs`, `DiagnosticFQ.hs`
- Contains: AST-to-constraint translator, compositional verification (assume-guarantee), body-VC generation
- Depends on: Syntax (typed AST), Contracts, Module (for cross-module assumes)
- Used by: `llmll verify`, trust report builder

**Trust & Reporting Layer:**
- Purpose: Aggregate verification evidence, emit structured trust reports
- Location: `compiler/src/LLMLL/TrustReport.hs`, `VerifiedCache.hs`, `ProofArtifact.hs`
- Contains: Trust level computation (SAFE/TESTED/ASSERTED/UNVERIFIED), sidecar persistence, proof replay
- Depends on: Verification backend (DiagnosticFQ), Checkout (evidence records)
- Used by: `llmll verify --trust-report`, artifact replay

**Hole Filling & Checkout Layer:**
- Purpose: Manage exclusive hole locks, apply patches, coordinate agent fills
- Location: `compiler/src/LLMLL/Checkout.hs`, `PatchApply.hs`, `Replay.hs`
- Contains: Token generation, TTL tracking, JSON-Patch application, event logging
- Depends on: Syntax (AST, pointers), Module (scope context), TypeCheck (hole types)
- Used by: `llmll checkout`, `llmll patch`, orchestrator tool

**HTTP Serving Layer:**
- Purpose: Sketch query endpoint for agent integration (Phase 2c)
- Location: `compiler/src/LLMLL/Serve.hs`
- Contains: HTTP handlers, sketch inference bridge, response serialization
- Depends on: TypeCheck (sketch inference), Hole analysis
- Used by: `llmll serve` (localhost:7777)

## Data Flow

### Primary Request Path (check → build → verify)

1. **Source Load** (`loadStatementsMulti`, Main.hs:477) - reads .llmll or .ast.json file
2. **Parse** (`parseTopLevel` or `parseJSONAST`, Parser.hs) - tokenize and parse to Statement[]
3. **Module Resolution** (`loadModule`, Module.hs) - DFS import resolver, cycle detection, ModuleCache build
4. **Type Check** (`typeCheckStrictWithCache`, TypeCheck.hs:~line 150) - bidirectional checking, contract validation
5. **Code Generation** (`generateHaskellMulti`, CodegenHs.hs) - emit Haskell/package.yaml
6. **Stack Build** (`runGhcCheck`, Main.hs:911) - validate generated Haskell syntax

### Verification Path (verify)

1. **Type-checked AST** (from above path)
2. **Contract Extraction** (`buildContractEnv`, FixpointEmit.hs) - gather pre/post conditions
3. **Constraint Emission** (`emitFixpoint`, FixpointEmit.hs) - walk AST, emit .fq clauses
4. **Liquid-Fixpoint** (subprocess call) - run solver on .fq file
5. **Result Parsing** (`parseFQResult`, DiagnosticFQ.hs) - parse SAFE/UNSAFE verdict
6. **Trust Report** (`buildTrustReport`, TrustReport.hs) - aggregate evidence per function
7. **Sidecar Persist** (`saveVerified`, VerifiedCache.hs) - write .verified.json

### Hole-Filling Workflow (checkout → patch cycle)

1. **Scan Holes** (`doHoles`, Main.hs:546) - list holes with type info
2. **Checkout Lock** (`checkoutHole`, Checkout.hs) - acquire exclusive token with TTL
3. **Sketch Query** (agent calls `llmll serve` or `llmll typecheck --sketch`) - infer hole type
4. **Patch Request** (agent constructs RFC 6902 patch.json)
5. **Apply Patch** (`applyPatch`, PatchApply.hs) - validate and apply patch to AST
6. **Release Token** (`releaseHole`, Checkout.hs) - unlock hole
7. **Re-check** (agent runs `llmll check` on patched file)

### State Management

- **ModuleCache**: `Map ModulePath (TypeEnv, ContractStatus)` - module type environments
- **VerifiedCache**: `.verified.json` sidecar - per-function trust levels, proof records
- **Checkout Tokens**: in-memory TTL-tracked exclusive locks per pointer
- **Proof Artifacts**: JSON record of verify run (reproduce-able via `llmll replay-artifact`)

## Key Abstractions

**Statement / Expression (Syntax.hs):**
- Purpose: Represent parsed LLMLL program as AST
- Examples: `SDefFun`, `SDefData`, `SDefModule`, `Expr`, `Pattern`
- Pattern: Algebraic data types; immutable; no side effects during construction

**Type (Syntax.hs):**
- Purpose: Represent LLMLL type system
- Examples: `TInt`, `TBool`, `TFun`, `TDependent`, `TData`, `TSum`
- Pattern: Closed-world types; verification fragment is QF-LIA integers + data constructors

**Contract (Syntax.hs):**
- Purpose: Pre/post conditions and specification entropy
- Examples: `Contract (precond) (postcond)`, `SPrecond`, `SPostcond`
- Pattern: Boolean expressions (predicates); associated with function definitions

**HoleKind (Syntax.hs):**
- Purpose: Classify holes (execution vs verification)
- Examples: `HoleExpr`, `HoleDefBody`, `HoleProof`
- Pattern: Determines fill strategy (agent-expression vs proof-obligation)

**DelegateSpec (Syntax.hs):**
- Purpose: Async delegation site (agent task scheduling)
- Examples: Specify agent model, temperature, max retries
- Pattern: Metadata for hole-filling orchestration

**TypeEnv (TypeCheck.hs):**
- Purpose: Map names to types, contracts, function definitions
- Pattern: `Map Name TypeEntry` with qualified name handling for imports

**ModuleEnv (Syntax.hs):**
- Purpose: Per-module namespace: types, contracts, definitions
- Pattern: Bundled with ModuleCache for transitive import resolution

**CheckoutToken (Checkout.hs):**
- Purpose: Exclusive hole lock with expiration
- Pattern: Opaque string; TTL-tracked; 1:1 with pointer + session

**PatchRequest (PatchApply.hs):**
- Purpose: RFC 6902 JSON-Patch + scope context for hole fill
- Pattern: Paths are RFC 6901 JSON-Pointers; ops are add/remove/replace/test

## Entry Points

**CLI Main (`compiler/app/Main.hs`):**
- Location: `Main.hs`, `main` function (line 386)
- Triggers: `llmll <command>` invocation
- Responsibilities:
  - Parse CLI arguments (command, options, flags)
  - Route to handler: doCheck, doBuild, doVerify, doCheckout, doServe, etc.
  - Load source files via `loadStatementsMulti` (module resolution)
  - Manage exit codes and error formatting (JSON or S-expression)

**Check Command (`doCheck`, Main.hs:517):**
- Entry: parse + type-check file
- Flows to: `typeCheckStrictWithCache`, formats diagnostics
- Exit: success iff no errors (warnings non-fatal unless --strict)

**Build Command (`doBuild`, Main.hs:674):**
- Entry: parse → module load → type-check → codegen → stack build
- Flows to: `generateHaskellMulti`, `runGhcCheck`
- Exit: generates `<outDir>/src/Lib.hs` + package.yaml

**Verify Command (`doVerify`, Main.hs:2404 in full file):**
- Entry: parse → module load → type-check → emit constraints → run solver
- Flows to: `emitFixpointWithCache`, subprocess liquid-fixpoint
- Exit: trust report + .verified.json sidecar

**Serve Command (`CmdServe`, Main.hs:407):**
- Entry: HTTP server on localhost:7777
- Flows to: `Serve.hs`, sketch inference handlers
- Exit: listens until signal

**Checkout Command (`doCheckout`, Main.hs:2528 in full file):**
- Entry: acquire exclusive hole lock
- Flows to: `checkoutHole`, generates token
- Exit: token JSON response (TTL embedded)

## Architectural Constraints

- **Threading:** Single-threaded event loop (GHC IO monad). Concurrent hole-filling is coordinated by the llmll-orchestra orchestrator tool, not by the compiler itself.
- **Global state:** Minimal. ModuleCache is passed as parameter through call chain; no mutable global state (pure functional design). Checkout tokens are ephemeral in-memory; sidecar .verified.json persists to disk.
- **Circular imports:** Not permitted. Module system enforces acyclic DAG via cycle detection in `loadModule`.
- **Type-checked invariant:** All code downstream of TypeCheck assumes AST is type-correct. Parse errors and type errors are caught before codegen.
- **Verification fragment:** QF-LIA integers + simple recursive data constructors. Non-linear arithmetic and custom induction trigger fallback (HProofRequired, later resolved via Leanstral MCP).
- **Contract faithfulness:** `FixpointEmit` output is trusted by runtime assertions (`--contracts=unproven`). Constraint translation must never weaken contracts; any extension must preserve semantic equivalence.

## Anti-Patterns

### Parsing Without Module Resolution

**What happens:** Code calls `Parser.parseTopLevel` directly, skipping module import resolution via `Module.loadModule`.

**Why it's wrong:** Imports won't be resolved; forward references to imported functions will fail type checking. Single-file quick checks (e.g., early parse diagnostics) must still route through `loadStatementsMulti`.

**Do this instead:** Always use `loadStatementsMulti` (Main.hs:477) to load a source file; it handles both S-expr and JSON-AST, resolves imports, and returns a ModuleCache for type checking. For single-file sources, the cache will be empty but the loader handles that gracefully.

### Skipping Type Check Before Codegen

**What happens:** Codegen receives an AST without going through TypeCheck.

**Why it's wrong:** Generated Haskell will be ill-typed. Contracts won't be instrumented. Examples: `doBuild` (line 710) includes a type-check gate; if that's removed, codegen produces garbage.

**Do this instead:** Always run `typeCheckStrictWithCache` before `generateHaskellMulti`. The gate at line 710 models this; follow the pattern.

### Applying Patches Without Validation

**What happens:** A patch is applied without re-checking the file afterward.

**Why it's wrong:** Patched holes may introduce type errors or contract violations. The orchestrator must call `llmll check` or `llmml verify` after patch application.

**Do this instead:** Patches are applied via `applyPatch` (safe syntactically), but the agent is responsible for re-checking. The checkout/patch workflow is transactional at the agent level (checkout → fill → patch → verify) not at the compiler level.

### Trusting Liquid-Fixpoint Output Without Validation

**What happens:** A "SAFE" verdict from liquid-fixpoint is directly written to .verified.json without checking solver diagnostics.

**Why it's wrong:** The solver may timeout, have a bug, or be misconfigured. Unsat cores and witness diagnostics should be inspected.

**Do this instead:** `parseFQResult` and `fqResultToReport` (DiagnosticFQ.hs) structure the solver output. Trust report builder can downgrade evidence if solver confidence is low or timeouts occurred.

## Error Handling

**Strategy:** Multi-layer diagnostics (parse, type-check, verification, runtime).

**Patterns:**
- **Parse errors:** Routed to `megaparsecToDiagnostic` (Diagnostic.hs), formatted as S-expression or JSON (Main.hs:453).
- **Type errors:** Collected in `DiagnosticReport` by `TypeCheckResult` (TypeCheck.hs); formatted with source location.
- **Verification errors:** Liquid-fixpoint counterexamples parsed via `parseFQResult`, reported with constraint origin (ConstraintOrigin in DiagnosticFQ.hs).
- **Runtime errors:** Contracts are enforced at runtime if `--contracts=full` or `--contracts=unproven`. Failures logged to stderr or via capabilities (Capabilities.hs).

## Cross-Cutting Concerns

**Logging:** Minimal; diagnostics are structured and routed to stdout/stderr. Verbosity is controlled by CLI flags (`-v` for agent orchestrator, not compiler itself). Compiler uses `hPutStrLn` for direct output (Main.hs:558).

**Validation:** All inputs validated before processing. Parse errors caught early; type errors during type-check pass; verification failures reported by solver.

**Authentication:** Not built into compiler. Checkout tokens are opaque strings; agents authenticate via out-of-band (e.g., HTTP Bearer token passed to `llmml serve`). Leanstral MCP uses LLMLL_LEANSTRAL_API_KEY environment variable.

---

*Architecture analysis: 2026-07-30*
