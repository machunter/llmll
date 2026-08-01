# Codebase Structure

**Analysis Date:** 2026-07-30

## Directory Layout

```
llmll/
├── .claude/                    # User preferences, agent skills
│   ├── CLAUDE.md              # User global instructions
│   ├── settings.json          # Project-specific settings
│   └── skills/                # Project skills (if any)
├── .agents/                    # Subagent definitions
├── .github/                    # GitHub Actions CI/CD
├── .planning/
│   └── codebase/              # GSD codebase maps (ARCHITECTURE.md, STRUCTURE.md, etc.)
├── compiler/                   # Main Haskell compiler
│   ├── app/
│   │   └── Main.hs            # CLI entry point (2738 lines)
│   ├── src/
│   │   └── LLMLL/             # Core compiler modules (flat directory, 40+ .hs files)
│   │       ├── Parser.hs      # S-expression parser
│   │       ├── ParserJSON.hs  # JSON-AST parser
│   │       ├── Syntax.hs      # Core AST definitions
│   │       ├── TypeCheck.hs   # Bidirectional type checker
│   │       ├── Sketch.hs      # Hole type inference
│   │       ├── Module.hs      # Multi-file import resolver
│   │       ├── Hub.hs         # Hub cache resolution
│   │       ├── CodegenHs.hs   # Haskell transpiler
│   │       ├── FixpointEmit.hs # Liquid-fixpoint constraint emitter
│   │       ├── DiagnosticFQ.hs # Solver result parser
│   │       ├── TrustReport.hs # Verification evidence aggregator
│   │       ├── Checkout.hs    # Hole lock management
│   │       ├── PatchApply.hs  # RFC 6902 patch application
│   │       ├── Serve.hs       # HTTP sketch endpoint
│   │       ├── Contracts.hs   # Runtime assertion instrumentation
│   │       ├── VerifiedCache.hs # .verified.json sidecar
│   │       ├── ProofArtifact.hs # Replayable proof records
│   │       ├── HoleAnalysis.hs  # Hole classification & dependency
│   │       ├── Replay.hs      # Event log replay
│   │       ├── ObligationAssembly.hs # Cross-module obligations
│   │       ├── LeanTranslate.hs # Lean proof synthesis
│   │       ├── MCPClient.hs    # Leanstral MCP client
│   │       └── [other modules] # Utilities, analysis, reporting
│   ├── test/
│   │   ├── Spec.hs            # Main test suite entry
│   │   ├── ModuleSpec.hs      # Module system tests
│   │   └── fixtures/          # Test data
│   ├── package.yaml           # Hpack descriptor
│   ├── stack.yaml             # Stack build configuration
│   └── llmll.cabal            # Cabal descriptor (generated from package.yaml)
├── tools/
│   ├── llmll-driver/          # Compiler test harness (LLMLL fixture programs)
│   │   ├── fill.llmml         # Test case: hole filling
│   │   ├── gate.llmml         # Test case: verification gates
│   │   ├── *.llmml            # Other test programs
│   │   └── EXPECTED_VERDICTS.json
│   └── llmll-orchestra/        # Python multi-agent orchestrator
│       ├── llmll_orchestra/
│       │   ├── __main__.py     # CLI entry point
│       │   ├── compiler.py     # llmml subprocess wrapper
│       │   ├── graph.py        # Topological sort + scheduling
│       │   ├── agent.py        # Anthropic SDK integration
│       │   ├── orchestrator.py # Main loop (checkout → fill → patch)
│       │   ├── lead_agent.py   # Multi-agent lead coordinator
│       │   └── quality.py      # Quality metrics
│       ├── tests/              # Python test suite
│       ├── fixtures/           # Example AST files
│       ├── pyproject.toml      # Python package config
│       └── README.md           # Orchestrator documentation
├── examples/                   # Example LLMLL programs (41 subdirectories)
│   ├── erc20_token/           # ERC20 token contract
│   ├── tftp_rfc1350/          # TFTP protocol implementation
│   ├── heartbleed/            # Heartbleed vulnerability demo
│   ├── secure-channel-emergent/ # TLS-like protocol (agent-invented)
│   ├── token-revocation-emergent/ # OAuth token revocation
│   ├── banking_ledger/        # Banking example with twin refute
│   ├── refine-demo/           # Cascading refinement demo
│   ├── replay-demo/           # Event log replay demo
│   ├── leanstral-demo/        # Lean proof synthesis demo
│   ├── withdraw-demo/         # Withdrawal pattern with outcome type
│   └── [other examples]/
├── experiments/                # Experimental branches & RFC implementations
│   ├── rfc-swarm/             # RFC test harness (gate validation)
│   ├── pbt-harness/           # Property-based testing experiments
│   └── [other experiments]/
├── docs/
│   ├── getting-started.md     # Quick start guide
│   ├── one-pager.md           # Executive summary
│   ├── compiler-team-roadmap.md # Feature roadmap
│   ├── orchestrator-walkthrough.md # Multi-agent coordination tutorial
│   ├── llmml-ast.schema.json  # AST JSON schema
│   ├── llmml-trust-report.schema.json # Trust report schema
│   ├── proof-artifact.schema.json # Proof artifact schema
│   ├── design/                # Design documents & critique
│   │   ├── data-scope-extension.md # Verification boundary extension
│   │   ├── critique-*.md      # Design reviews
│   │   └── [other design docs]/
│   └── archive/               # Retired design docs
├── site/                       # Website (blog, published docs)
│   ├── blog/                  # Blog posts (verified TLS series)
│   └── [static site files]/
├── runtime/                    # Runtime support code (Haskell preamble, stdlib)
├── scripts/
│   ├── version_gate.sh        # Release ceremony (version consistency check)
│   ├── build.sh               # Build script
│   └── [other utilities]/
├── outreach-workspace/         # Outreach & demo materials
├── .gitignore                  # Git ignore rules
├── LLMLL.md                    # Main specification (language reference)
├── README.md                   # Project readme
├── CHANGELOG.md                # Release notes (v0.14.73 current)
├── LICENSE                     # Apache 2.0 license
├── Dockerfile                  # Container image
├── Makefile                    # Build convenience targets
└── stack.yaml                  # Root stack.yaml (delegates to compiler/)
```

## Directory Purposes

**`compiler/`:**
- Purpose: Main LLMLL Haskell compiler implementation
- Contains: Parser, type checker, code generator, verifier
- Key files: `compiler/app/Main.hs` (CLI), `compiler/src/LLMLL/*.hs` (modules)
- Entry: `stack exec llmml` or compiled binary at `src/Main`

**`compiler/src/LLMLL/`:**
- Purpose: Core compiler module library (flat, no subdirectories)
- Contains: 40+ .hs modules organized by phase (not by directory)
- Naming: Each module typically one .hs file (e.g., TypeCheck.hs, Parser.hs)
- Pattern: No hierarchical subdirectories; imports use qualified names (LLMLL.Parser)

**`compiler/test/`:**
- Purpose: Test suite
- Contains: `Spec.hs` (main), `ModuleSpec.hs` (module-specific), `fixtures/` (test data)
- Run: `stack test`

**`tools/llmml-orchestra/`:**
- Purpose: Python multi-agent orchestrator for hole filling
- Contains: CLI, subprocess wrapper, agent loop, DAG scheduler
- Pattern: Modular Python (agent.py, compiler.py, graph.py, orchestrator.py)
- Run: `llmml-orchestra <ast.json> --model claude-opus ...`

**`tools/llmml-driver/`:**
- Purpose: Test driver and LLMLL fixture harness for CI gates
- Contains: Small test programs (*.llmml), verdict expectations
- Pattern: LLMLL programs that exercise specific compiler features (gates)

**`examples/`:**
- Purpose: Example LLMLL programs demonstrating language features
- Contains: 41 subdirectories, each a self-contained example
- Naming: kebab-case directory names (erc20_token, tftp_rfc1350)
- Pattern: Each example has `*.llmml` source, optional `*.ast.json`, README.md

**`docs/`:**
- Purpose: User-facing documentation and language specification
- Contains: Guides, roadmaps, design documents, JSON schemas
- Pattern: Markdown + JSON schemas; design docs in `design/` subdirectory

**`site/`:**
- Purpose: Published website (blog, hosted docs)
- Contains: Static HTML, blog posts, GitHub Pages source
- Pattern: Generated from repo via GitHub Actions; blog/ subdirectory

**`experiments/`:**
- Purpose: Active research branches (RFC implementation, benchmarks)
- Contains: Experimental LLMLL programs, gate harnesses
- Pattern: Organized by RFC or research area (rfc-swarm, pbt-harness)

**`.planning/codebase/`:**
- Purpose: GSD codebase analysis documents
- Contains: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md, STACK.md, INTEGRATIONS.md
- Pattern: Generated by `/gsd-map-codebase` skill; read by `/gsd-plan-phase` and `/gsd-execute-phase`

## Key File Locations

**Entry Points:**
- `compiler/app/Main.hs` - CLI main function (line 386), subcommand handlers
- `tools/llmll-orchestra/llmll_orchestra/__main__.py` - Orchestrator CLI

**Configuration:**
- `compiler/package.yaml` - Hpack build descriptor (dependencies, version)
- `compiler/stack.yaml` - Stack build configuration
- `.claude/CLAUDE.md` - User preferences & instructions
- `.claude/settings.json` - Claude Code project settings

**Core Logic:**
- `compiler/src/LLMLL/Parser.hs` - S-expression tokenization & parsing
- `compiler/src/LLMLL/ParserJSON.hs` - JSON-AST parsing
- `compiler/src/LLMLL/Syntax.hs` - Core AST (Statement, Expr, Type, Contract)
- `compiler/src/LLMLL/TypeCheck.hs` - Bidirectional type inference
- `compiler/src/LLMLL/Module.hs` - Multi-file import resolution
- `compiler/src/LLMLL/CodegenHs.hs` - Haskell code generator
- `compiler/src/LLMLL/FixpointEmit.hs` - Liquid-fixpoint constraint emitter
- `compiler/src/LLMLL/TrustReport.hs` - Verification evidence aggregation

**Testing:**
- `compiler/test/Spec.hs` - Main test suite
- `compiler/test/fixtures/` - Test data files
- `tools/llmml-driver/` - CI gate test programs

**Documentation:**
- `LLMLL.md` - Language specification (226KB)
- `README.md` - Project overview
- `CHANGELOG.md` - Release notes
- `docs/getting-started.md` - Quick start
- `docs/compiler-team-roadmap.md` - Feature roadmap

**Specification:**
- `docs/llmll-ast.schema.json` - AST JSON schema
- `docs/llmll-trust-report.schema.json` - Trust report schema
- `docs/proof-artifact.schema.json` - Proof artifact schema

## Naming Conventions

**Files:**
- Haskell modules: `PascalCase.hs` (e.g., TypeCheck.hs, CodegenHs.hs)
- LLMLL programs: `kebab-case.llmml` (e.g., erc20_token.llmml)
- JSON schemas: `kebab-case.schema.json` (e.g., llmml-ast.schema.json)
- Documentation: `kebab-case.md` (e.g., getting-started.md, compiler-team-roadmap.md)
- Test fixtures: `PascalCase` without extension or `TestName.hs`

**Directories:**
- Haskell projects: lowercase (compiler, runtime)
- Example categories: kebab-case (heartbleed, token-revocation-emergent)
- Documentation sections: lowercase (docs, design, archive)
- Python packages: snake_case (llmml_orchestra, llmml_driver)

**Functions / Exports:**
- Type checkers: `typeCheck*` prefix (typeCheck, typeCheckStrict, typeCheckWithCache)
- Generators: `generate*` or `emit*` (generateHaskell, emitFixpoint, emitJsonAST)
- Query functions: `*By*` or `query*` (queryBySignature, findHole)
- Diagnostic formatters: `format*` (formatDiagnostic, formatDiagnosticJson)
- Builders: `build*` (buildModuleEnv, buildTrustReport, buildAliasMap)

**Types:**
- Result types: `*Result` (TypeCheckResult, SketchResult, EmitResult, CodegenResult)
- Configuration: `*Options` (EmitOptions, ServeOptions, LeanstralOpts)
- Environments: `*Env` (TypeEnv, ModuleEnv, SortEnv, ContractEnv)

## Where to Add New Code

**New Compiler Phase:**
- Primary code: `compiler/src/LLMLL/<PhaseName>.hs`
- Integration: Add handler in `compiler/app/Main.hs` (subcommand + doPhase function)
- Tests: `compiler/test/<PhaseName>Spec.hs`
- Export types/functions: Add to module header's export list

**New Feature (e.g., new contract type):**
- Definition: `compiler/src/LLMLL/Syntax.hs` (add Type, Contract variant)
- Type checking: `compiler/src/LLMLL/TypeCheck.hs` (add case in checking)
- Codegen: `compiler/src/LLMLL/CodegenHs.hs` (add Haskell emission)
- Verification: `compiler/src/LLMLL/FixpointEmit.hs` (add constraint translation if applicable)
- Tests: `compiler/test/fixtures/` (add test program exercising feature)

**New Compiler Utilities:**
- Shared helpers: `compiler/src/LLMLL/Utility*.hs` (e.g., UtilityTypes.hs)
- Analysis: `compiler/src/LLMLL/<Analysis>Analysis.hs` (e.g., HoleAnalysis.hs)
- Diagnostics: `compiler/src/LLMLL/Diagnostic*.hs` (e.g., DiagnosticFQ.hs)

**New Example:**
- Location: `examples/<kebab-case-name>/`
- Files: `*.llmml` (source), `*.ast.json` (optional pre-parsed), `README.md` (description)
- Pattern: Self-contained directory with all supporting files

**New Test:**
- Location: `compiler/test/` or `tools/llmml-orchestra/tests/`
- Naming: `<Feature>Spec.hs` (Haskell) or `test_<feature>.py` (Python)
- Structure: Use HSpec (Haskell) or pytest (Python) framework

**New Experiment:**
- Location: `experiments/<rfc-name>/ or <topic>/`
- Contents: LLMLL programs, harness scripts, findings document
- Pattern: Self-contained research branch; document gate criteria

## Special Directories

**`compiler/.stack-work/`:**
- Purpose: Stack build artifacts (compiled binaries, object files)
- Generated: Yes (by `stack build`)
- Committed: No (.gitignore)
- Manual cleanup: `rm -rf compiler/.stack-work` if stuck

**`compiler/generated/`:**
- Purpose: Generated code examples (output from `llmml build`)
- Generated: Yes (by running compiler on examples)
- Committed: Partially (some hand-maintained examples)
- Update: Run `llmml build examples/<name>/<name>.llmml` to regenerate

**`.planning/codebase/`:**
- Purpose: GSD codebase analysis documents (this STRUCTURE.md, ARCHITECTURE.md, etc.)
- Generated: Yes (by `/gsd-map-codebase` skill)
- Committed: Yes (tracked in git; used by planning/execution agents)
- Manual update: Via `/gsd-map-codebase` command, not direct edit

**`outreach-workspace/`:**
- Purpose: Demo materials, presentation slides, promotional content
- Committed: Partially (some files are large; consider external hosting)

## Import Patterns & Module Organization

**Haskell Imports (compiler/src/LLMLL/*.hs):**
- Qualified import style: `import qualified Data.Map.Strict as Map` (to avoid ambiguity)
- Module imports: `import LLMLL.Parser` (qualified for LLMLL namespace)
- Pattern: All imports at top of file (Haskell requirement)

**Circular dependency avoidance:**
- Parser → Syntax (OK; Syntax has no imports)
- TypeCheck → Syntax, Parser, Module (OK; acyclic)
- Module → Parser, TypeCheck (OK; file-system mediated)
- CodegenHs → Syntax, Contracts, TypeCheck (OK; downstream of type check)
- FixpointEmit → Syntax, Contracts, Module, TypeCheck (OK; parallel to codegen)

**CLI Layer (Main.hs):**
- Imports all compiler phases as needed by subcommands
- Orchestrates: parse → module load → type check → codegen/verify
- Pattern: Single file; handler per subcommand (doCheck, doBuild, doVerify, etc.)

**Python Imports (tools/llmml-orchestra/):**
- Standard layout: `from llmml_orchestra import agent, compiler, orchestrator`
- Pattern: Flat module structure, no deep nesting

## Versioning & Release

**Version location:** `compiler/package.yaml` (version field)
- Bumped manually before release
- Reflected in: CHANGELOG.md, LLMLL.md (line 1), README.md (line 5)
- Gate check: `scripts/version_gate.sh` (enforces consistency)

**Release ceremony:** `scripts/version_gate.sh` runs before push
- Validates version in all 4 locations
- Ensures CHANGELOG is up-to-date
- Ensures README pin (line 5) matches version

## Build & Runtime

**Build system:** Haskell Stack (stack.yaml in root and compiler/)
- Build: `stack build` (in compiler/ directory)
- Test: `stack test`
- Executable: `compiler/src/Main` (compiled binary) or `stack exec llmml`

**Generated code layout (output of `llmml build`):**
```
<outDir>/
  src/
    Lib.hs       — all LLMLL definitions translated to Haskell
    Main.hs      — if SDefMain present; orchestrates def-main call
    FFI/         — FFI stubs for c.* imports (auto-generated)
      *.hs       — one per library (generated once, not overwritten)
  package.yaml   — Haskell package descriptor (hpack format)
  stack.yaml     — Build configuration
```

**Python runtime:** `tools/llmml-orchestra/`
- Install: `pip install -e .` (editable mode)
- Run: `llmml-orchestra <ast.json> [options]`
- Dependencies: `pyproject.toml` specifies (anthropic SDK, pytest, etc.)

---

*Structure analysis: 2026-07-30*
