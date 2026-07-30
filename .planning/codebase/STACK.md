# Technology Stack

**Analysis Date:** 2026-07-30

## Languages

**Primary:**
- Haskell — Compiler (GHC 9.6.6 via lts-22.43)
  - All core verification logic resides in `compiler/src`
  - Executable entry point: `compiler/app/Main.hs`

**Secondary:**
- Rust — Runtime sandbox and event log (Rust 2021 edition)
  - Location: `runtime/` with cdylib + rlib crate types
  - Minimal footprint: serde, serde_json, thiserror only

**Tertiary:**
- Python — Multi-agent orchestrator (3.10+)
  - Location: `tools/llmll-orchestra/`
  - Single dependency: anthropic SDK

- Markdown/Jekyll — Static documentation and blog
  - Location: `site/` (Jekyll-based)

## Runtime

**Environment:**
- Haskell: GHC 9.6.6 (LTS Haskell 22.43 resolver)
- Rust: Cargo (2021 edition, minimal)
- Python: CPython 3.10+ with pip/setuptools

**Package Manager:**
- Haskell Stack (primary build tool)
  - Lockfile: `compiler/stack.yaml.lock` (committed)
  - Resolver pins all transitive Haskell dependencies

- Cargo (Rust runtime)
  - Lockfile: `runtime/Cargo.lock` (committed)
  - Patched: `getrandom` pinned to v0.2.15 to avoid edition2024 requirement

- setuptools (Python orchestrator)
  - No lock file; anthropic>=0.25.0 is the only runtime dependency

## Frameworks

**Core:**
- warp (3.3+) — HTTP server for the `/serve` endpoint
  - Binds to 127.0.0.1:7777 by default (configurable via `--host`, `--port`)
  - Located in `compiler/src/LLMLL/Serve.hs`

- wai (3.2+) — WAI application interface (abstracts HTTP request/response)
- http-types (0.12+) — HTTP status codes and header constants

**Parsing & AST:**
- megaparsec (9.5+) — Parser combinator library
  - Used in `compiler/src/LLMLL/Parser.hs` for S-expression syntax
  - Also parses JSON-AST variant in `compiler/src/LLMLL/ParserJSON.hs`

- parser-combinators (1.3+) — Additional parser primitives

**Serialization:**
- aeson (2.1+) — JSON encoding/decoding
- aeson-pretty (0.8+) — Pretty-printing JSON output

**Testing:**
- hspec (2.11+) — BDD-style test framework for Haskell
  - Tests located in `compiler/test/Spec.hs`
  - Run via `stack test`

- hspec-megaparsec (2.2+) — Parser testing utilities
- QuickCheck (2.14+) — Property-based testing
  - Used for property-based verification tests (check blocks in `.llmll`)

- pytest (via `tools/llmll-orchestra/`)
  - Test runner for Python orchestrator

**Build/Dev:**
- Stack — Haskell project management (resolver lts-22.43)
- Cargo — Rust project management
- setuptools — Python package build backend

**Verification Backend:**
- liquid-fixpoint (0.9.6.3.1) — SMT verification backend
  - Installed separately in Docker (not a Haskell dependency)
  - Emits `.fq` constraints from Haskell code, invokes `fixpoint` CLI
  - Lives in `/usr/local/bin/fixpoint` in Docker image

- z3 — SMT solver (required at runtime)
  - Invoked by liquid-fixpoint via process calls
  - Installed in Docker via `apt-get install z3`
  - Not a package dependency; discovered on PATH by main CLI

## Key Dependencies

**Critical:**
- aeson (2.1+) — JSON serialization is central to HTTP APIs and output formats
- megaparsec (9.5+) — Parsing S-expressions and `.llmll` syntax is the first phase of compilation
- warp (3.3+) / wai (3.2+) — HTTP server required for agent integration (`serve` subcommand)
- cryptohash-sha256 — Proof cache obligation hashing (v0.3.1 addition)
  - Used in `compiler/src/LLMLL/ProofCache.hs` for cache invalidation

**Infrastructure:**
- network (3.1+) — Socket server primitives (kept for `getAddrInfo` in Serve)
- time (1.12+) — Checkout lock timestamps (v0.3 addition)
- random (1.2+) — Token generation for sketch auth
- process (1.6+) — Subprocess management for liquid-fixpoint, Lean kernel check, event log replay
- directory (1.3+) — File system operations (creating token dirs, finding binaries)
- filepath (1.4+) — Path manipulation
- bytestring (0.11+) — Efficient byte handling
- text (2.0+) — Unicode string operations throughout
- containers (0.6+) — Map/Set data structures (core to type checking)
- vector (0.13+) — Array operations (event log + runtime)
- mtl (2.3+) — Monad transformers (ReaderT + StateT for type checking)
- tar (0.5+) — Archive handling for hub scaffolds
- zlib (0.6+) — Compression for archives
- unix (2.7+) — POSIX operations (stderr/stdout encoding)

**Dev/Tools:**
- optparse-applicative (0.18+) — CLI argument parsing (all subcommands)
- pretty-simple (4.1+) — Pretty printing for diagnostics

**Anthropic/LLM (Python Orchestrator):**
- anthropic (>=0.25.0) — Claude API client
  - Used in `tools/llmll-orchestra/llmll_orchestra/lead_agent.py`
  - For multi-agent hole-filling orchestration

**Test Data:**
- Fixtures stored in `compiler/test/fixtures/` (S-expressions) and `examples/` (`.llmll` files)

## Configuration

**Environment:**
- Haskell Stack resolves all versions from `compiler/stack.yaml` (lts-22.43)
- Docker build pins GHC 9.6.6 explicitly (FROM haskell:9.6.6 AS build)
- Rust Cargo.toml specifies dependencies declaratively

**Key Environment Variables:**
- `LLMLL_LEANSTRAL_API_KEY` — Mistral API key for proof generation (read-only, never logged)
  - Set by caller; passed to `compiler/src/LLMLL/MCPClient.hs::proveWithLeanstral`
- `LLMLL_WORKSPACE_DIR` (inferred from memory) — May be used for cache directories
- `.env` file present (contains local development config; not read in code)

**Build:**
- `compiler/stack.yaml.lock` — Committed; locks Haskell transitive graph
- `runtime/Cargo.lock` — Committed; locks Rust transitive graph
- `Dockerfile` — Multi-stage build (builder + slim runtime)
  - Builder stage: haskell:9.6.6 (GHC 9.6.6 + stack pre-installed)
  - Runtime stage: debian:bookworm-slim (minimal; only z3, libgmp10, zlib1g)

**Flags (Haskell):**
- `crypton` C extensions disabled for aarch64-osx builds (stack.yaml)
  - Transitive via warp → tls → crypton

## Platform Requirements

**Development:**
- GHC 9.6.6 (provided by Stack or docker)
- Haskell Stack 2.x+
- Rust toolchain (1.70+) for runtime compilation
- Python 3.10+ (for orchestrator)
- jq (shell script dependencies in CI)

**Production:**
- Linux or macOS (tested on aarch64-osx, x86_64-linux)
- z3 SMT solver on PATH (required for `verify` subcommand)
- liquid-fixpoint binary on PATH (required for `verify` subcommand)
- Debian bookworm-slim (Docker runtime base)

**Docker:**
- Multi-stage build reduces final image size
- Runtime image: ~600MB+ (GHC binaries + z3 + examples)
- Build requires Docker BuildKit for syntax=docker/dockerfile:1

---

*Stack analysis: 2026-07-30*
