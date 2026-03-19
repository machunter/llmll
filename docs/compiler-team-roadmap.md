# LLMLL Compiler Team Implementation Roadmap

> **Prepared by:** Compiler Team  
> **Date:** 2026-03-19  
> **Status:** Active — supersedes the roadmap in `LLMLL.md §14`  
> **Source documents:** `LLMLL.md` · `consolidated-proposals.md` · `proposal-haskell-target.md` · `analysis-leanstral.md` · `design-team-assessment.md` · `proposal-review-compiler-team.md`
>
> **Governing design criterion:** Every deliverable is evaluated against *one-shot correctness* — an AI agent writes a program once, the compiler accepts it, contracts verify, no iteration required.

---

## Versioning Conventions

- Items marked **[CT]** are compiler team implementation tasks.
- Items marked **[SPEC]** are language specification changes that must land in `LLMLL.md` before or alongside the implementation.
- Items marked **[DESIGN]** are design decisions resolved by the joint team, recorded here as implementation constraints.

---

## v0.1.2 — Machine-First Foundation

**Theme:** Close the two highest-priority one-shot failure modes: structural invalidity (parentheses drift) and codegen semantic drift (Rust impedance mismatch). No new language semantics.

### Decision Record

| Decision | Resolution |
|----------|------------|
| Primary AI interface | JSON-AST (S-expressions remain, human-facing only) |
| Codegen target | Switch from Rust to Haskell |
| Algebraic effects library | `effectful` — committed, not revisited |
| `Command` model | Move from opaque type to typed effect row (`Eff '[...]`) |
| Python FFI tier | Dropped from formal spec |
| Sandboxing | Docker + `seccomp-bpf` + `-XSafe` (WASM deferred to v0.4) |

---

### Deliverable 1 — JSON-AST Parser and Schema

> **One-shot impact:** Eliminates structural invalidity as a failure mode entirely.

**[CT]** `ParserJSON.hs` — new module. Ingests a `.ast.json` file validated against `docs/llmll-ast.schema.json` and produces the same `[Statement]` AST as `Parser.hs`. The two parsers must agree on every construct; any divergence is a bug.

**[CT]** `llmll build --emit json-ast` — round-trip flag. Compiles an `.llmll` source and emits the equivalent validated JSON-AST. Used for S-expression ↔ JSON conversion and regression testing.

**[CT]** JSON diagnostics — every compiler error becomes a JSON object with:
  - `"kind"`: error class (e.g., `"type-mismatch"`, `"undefined-name"`)
  - `"pointer"`: RFC 6901 JSON Pointer to the offending AST node
  - `"message"`: human-readable description
  - `"inferred-type"`: inferred type at the error site, if available

**[CT]** `llmll holes --json` — lists all unresolved `?` holes as a JSON array. Each entry includes: hole kind, inferred type, module path, agent target (for `?delegate`), and (in v0.2) `?proof-required` complexity hint.

**[CT]** Hole-density validator *(design team addition)* — a post-parse pass emitting a `WARNING` when a `def-logic` body is entirely a single `?name` hole. Threshold TBD; suggested starting value: warn when the hole-to-construct ratio across the entire body is 1.0. Nudges agents toward targeted holes rather than wholesale stubs.

**[CT]** Round-trip regression suite — every `.llmll` example in `examples/` is run through `s-expr → JSON → s-expr → compile` and asserted semantically equivalent. Must pass before v0.1.2 ships.

**[CT]** JSON Schema versioning — introduce `"schemaVersion"` field to `llmll-ast.schema.json`. The compiler rejects `.ast.json` files with an unrecognized version. Versioning policy documented in `docs/json-ast-versioning.md`.

**[SPEC]** Update `LLMLL.md §2` to document JSON-AST as a first-class source format.

**Acceptance criteria:**
- An LLM generating JSON against the schema cannot produce a structurally invalid LLMLL program.
- `llmll build` and `llmll build --from-json` produce identical binaries for all examples.
- `llmll holes --json` output is a valid JSON array parseable by `jq`.

---

### Deliverable 2 — Haskell Codegen Target

> **One-shot impact:** Eliminates codegen semantic drift; makes v0.2 LiquidHaskell a 2-week integration instead of a 3-month Z3 binding project.

**[DESIGN — COMMITTED]** Effects library: `effectful`. Effect rows are type-visible in function signatures — AI agents can inspect what capabilities a function requires. This is a direct one-shot correctness gain, not merely an implementation preference.

**[DESIGN — COMMITTED]** `Command` becomes a typed effect row. A function calling `wasi.http.response` without declaring the HTTP capability is a **type error** in generated Haskell, caught at compile time. This closes the v0.1.1 gap where missing capability declarations were silently accepted.

**[CT]** Rewrite `Codegen.hs` to emit Haskell. All other compiler modules are unchanged (`Lexer.hs`, `Parser.hs`, `ParserJSON.hs`, `TypeCheck.hs`, `HoleAnalysis.hs`).

**[CT]** Generated file layout:

| File | Contents |
|------|----------|
| `src/Main.hs` | `def-main` harness |
| `src/Logic.hs` | All `def-logic` functions |
| `src/Types.hs` | ADT declarations and `where`-type newtype wrappers |
| `src/Interfaces.hs` | `def-interface` type class declarations |
| `src/Capabilities.hs` | Effect row definitions (`data HTTP`, `data FS`, etc.) |
| `src/FFI/*.hs` | Tier 2 (C) FFI stubs, generated on demand |
| `package.yaml` | Haskell package descriptor (replaces `Cargo.toml`) |

**[CT]** LLMLL construct → generated Haskell (normative mapping):

| LLMLL | Generated Haskell |
|-------|-------------------|
| `(def-logic f [x: int y: string] body)` | `f :: Int -> String -> <inferred>; f x y = body` |
| `(type T (| A int) (| B string))` | `data T = A Int \| B String deriving (Eq, Show)` |
| `Result[t,e]` | `Either e t` |
| `Promise[t]` | `IO t` (upgraded to `Async t` in v0.3) |
| `(def-interface I [m fn-type])` | `class I a where m :: fn-type` |
| `Command` (effect) | `Eff '[<capability-row>] r` |
| `(pre pred)` / `(post pred)` | LiquidHaskell `{-@ ... @-}` annotations (v0.2); runtime `assert` wrappers (v0.1.2) |
| `(check "..." (for-all [...] e))` | `QuickCheck.property $ \... -> e` |
| `(import haskell.aeson ...)` | `import Data.Aeson` — no stub |
| `(import c.libsodium ...)` | `foreign import ccall ...` in `src/FFI/Libsodium.hs` |
| `?name` hole | `error "hole: ?name"` + inline `{- HOLE -}` comment with inferred type |
| `?delegate @agent "..." -> T` | `error "delegate: @agent"` + JSON hole record in `llmll holes --json` |

**[CT]** Revised two-tier FFI (Python tier excluded from spec):

| Tier | Prefix | Mechanism | Stub? |
|------|--------|-----------|-------|
| 1 — Hackage | `haskell.*` | Regular `import`; added to `package.yaml` | No |
| 2 — C | `c.*` | `foreign import ccall`; GHC FFI template generated | Yes |

**[CT]** Sandboxing:

```
.llmll / .ast.json
     │  llmll build
     ▼
Generated .hs  {-# LANGUAGE Safe #-}
     │  GHC
     ▼
Native binary
     │
     ▼
Docker container
  ├── seccomp-bpf (syscall whitelist per declared capabilities)
  ├── Read-only filesystem (writable only at declared paths)
  ├── Network policy (declared URLs only)
  └── LLMLL host runtime (interprets Eff commands, enforces capability list)
```

**[CT]** WASM compatibility proof-of-concept — before merging `Codegen.hs`, compile the Hangman and Todo service generated `.hs` files with `ghc --target=wasm32-wasi`. Document results in `docs/wasm-compat-report.md`. Resolve any blockers before shipping. This validates that WASM remains on track for v0.4.

**[SPEC]** Update `LLMLL.md §7`, `§9`, `§10`, `§14` to reflect Haskell target, typed effect row, and Docker sandbox. Add explicit language to `§14`: *"WASM-WASI is the primary long-term deployment target. Docker + seccomp-bpf is the v0.1.2–v0.3 sandbox. WASM is deferred to v0.4, not abandoned."*

**Acceptance criteria:**
- `llmll build examples/hangman.llmll` produces a runnable GHC binary that passes all `check` blocks.
- A function calling `wasi.http.response` without the HTTP capability import produces a type error.
- The WASM proof-of-concept report shows no structural blockers.

---

### Deliverable 3 — Minimal Surface Syntax Fixes

> **One-shot impact:** Low — AI agents use JSON-AST. Fixes human ergonomics for test authors.

**[SPEC]** and **[CT]**:

| Current | Fixed |
|---------|-------|
| `(let [[x e1] [y e2]] body)` | `(let [(x e1) (y e2)] body)` |
| `(list-empty)` / `(list-append l e)` | `[]` / `[a b c]` list literals |
| `(pair a b)` | **unchanged** — current syntax is unambiguous |

**[CT]** Parser disambiguation: `[...]` in *expression position* = list literal; `[...]` in *parameter-list position* (after function name in `def-logic` or `fn`) = parameter list. Rule documented in `LLMLL.md §12`.

**[CT]** Old `(let [[x 1] ...])` syntax emits a clear error with a migration message.

---

## v0.2 — Module System + Compile-Time Verification

**Theme:** Make multi-file composition real and make contracts compile-time verified.

### Internal Ordering (design team requirement)

```
Phase 2a: Module System  →  Phase 2b: LiquidHaskell  →  Phase 2c: Type System Fixes + Sketch API
```

Rationale: `def-invariant` + Z3 verification requires multi-file resolution as substrate. Cross-module invariant checking is meaningless without cross-module compilation.

---

### Phase 2a — Module System

**[CT]** Multi-file resolution: `(import foo.bar ...)` loads and type-checks `foo/bar.llmll` or its `.ast.json` equivalent. Compiler maintains a module cache; circular imports are a compile error with cycle listed in the diagnostic.

**[CT]** Namespace isolation: each source file has its own top-level scope. Names from imported modules are prefixed by module path unless opened with `(open foo.bar)`.

**[CT]** Cross-module `def-interface` enforcement: when module A imports module B and relies on B's implementation of an interface, the compiler verifies structural compatibility at import time.

**[CT]** `llmll-hub` registry — `llmll hub fetch <package>@<version>` downloads a package and its `.ast.json` to the local cache. The compiler resolves `(import hub.<package>.<module> ...)` from the cache.

**Acceptance criteria:**
- A two-file program (A defines `def-interface`, B implements it) compiles and links.
- Circular imports produce a diagnostic naming the import cycle.

---

### Phase 2b — LiquidHaskell Compile-Time Verification

> **One-shot impact:** `pre`/`post` and `where`-type violations become compile-time errors. ~80% of practical contracts are in the decidable QF arithmetic fragment.

**[CT]** `Codegen.hs` annotation layer: translate LLMLL `(pre pred)`, `(post pred)`, and `(where [x: t] pred)` to LiquidHaskell `{-@ ... @-}` refinement annotations.

**[CT]** Translation table (initial coverage):

| LLMLL | LiquidHaskell |
|-------|---------------|
| `(where [x: int] (> x 0))` | `{-@ type PositiveInt = {v:Int \| v > 0} @-}` |
| `(pre (>= balance amount))` | `{-@ withdraw :: {b:Int} -> {a:Int \| b >= a} -> ... @-}` |
| `(post (= result (* x 2)))` | `{-@ double :: x:Int -> {v:Int \| v = x * 2} @-}` |

**[CT]** Build pipeline: `llmll build` invokes LiquidHaskell as a GHC plugin. LiquidHaskell failures are translated back to LLMLL JSON diagnostics with JSON Pointer references to the original LLMLL AST node.

**[CT]** Out-of-fragment constraints emit `?proof-required` holes with complexity hints:
  - `:simple` — QF linear arithmetic; LH/Z3 decides
  - `:inductive` — structural/inductive; Leanstral track (v0.3)
  - `:unknown` — compiler cannot classify; deferred to human review

In v0.2, `:inductive` and `:unknown` holes compile to `error "proof-required"` at the callsite (non-blocking unless on a hot path).

**[CT]** `letrec` — bounded recursion with mandatory `:decreases` termination annotation. LiquidHaskell verifies the termination measure.

**[CT]** Static `match` exhaustiveness for ADT types. Every `match` without `_` must cover all constructors or the compiler rejects it.

**[CT]** `def-invariant` + Z3 verification after every `llmll build` or AST merge. A merge breaking a global invariant is rejected before producing runnable code.

**[CT]** Capability enforcement fully wired: the typed effect row enforces declared capabilities at compile time — missing capability imports are type errors.

**Acceptance criteria:**
- A correct `withdraw` implementation has no LiquidHaskell errors.
- A `withdraw` violating its `(post ...)` is rejected at compile time with a diagnostic pointing to the LLMLL `post` clause.
- A `match` with a missing constructor arm produces a static error.

---

### Phase 2c — Type System Fixes + Sketch API

**[SPEC]** and **[CT]** Lift `pair-type` in `typed-param` limitation *(escalated by design team from v0.1.1 documented limitation to v0.2 fix)*. Accept `[acc: (int, string)]` in `def-logic` params, lambda params, and `for-all` bindings. Propagate the pair type normally through the type checker. Remove the workaround note from `LLMLL.md §3.2` and `§12`.

**[CT]** `llmll typecheck --sketch <file>` *(new design team proposal)* — accepts a partial LLMLL program (holes allowed everywhere). Runs constraint-propagation type inference. Returns a JSON object mapping each hole's JSON Pointer to its inferred type, plus any type errors that exist even with holes present:

```json
{
  "holes": [
    { "pointer": "/body/let/bindings/0/expr", "kind": "?name",
      "name": "?impl", "inferredType": "Result[int, string]" }
  ],
  "errors": [
    { "pointer": "/body/if/condition", "kind": "type-mismatch",
      "expected": "bool", "got": "int" }
  ]
}
```

**[CT]** HTTP interface for agent use: `POST localhost:7777/sketch` with a `.ast.json` body. Agents call this incrementally during generation, filling holes consistent with inferred types before final submission. Target latency: < 200ms for programs up to 500 nodes.

**Acceptance criteria:**
- `[acc: (int, string)]` in a lambda parameter list parses and type-checks without a workaround.
- Given a partial program with three holes, `llmll typecheck --sketch` returns each hole's inferred type.
- A type conflict in a partial program is reported even when the surrounding program is incomplete.

---

## v0.3 — Agent Coordination + Interactive Proofs

**Theme:** Make the swarm model operational end-to-end.

**[CT]** `?delegate` JSON-Patch lifecycle:
1. Lead AI checks out a hole: `llmll holes --checkout <pointer>`
2. Agent submits implementation as RFC 6902 JSON-Patch against the program's JSON-AST
3. Compiler applies patch, re-runs type checking and contract verification
4. Success → patch merged; failure → JSON diagnostics targeting patch node pointers

**[CT]** `?scaffold` — `llmll hub scaffold <template>` fetches a pre-typed skeleton from `llmll-hub`. `def-interface` boundaries are pre-typed; implementation details are named `?` holes. Resolves at parse time.

**[CT]** Leanstral MCP integration — `?proof-required :inductive` and `:unknown` hole resolution:
1. `llmll holes --json` emits holes with complexity hints
2. Compiler translates LLMLL `TypeWhere` AST node → Lean 4 `theorem` obligation *(the only novel engineering piece)*
3. MCP call to Leanstral's `lean-lsp-mcp`
4. Leanstral returns verified Lean 4 proof term
5. `llmll check` stores certificate; subsequent builds verify certificate without re-calling Leanstral
6. Fallback: if Leanstral unreachable, hole becomes `?delegate-pending` (blocks execution, does not fail build)

**[SPEC]** Document `?proof-required :simple | :inductive | :unknown` hint syntax in `LLMLL.md §6`.

**[CT]** `do`-notation sugar: `(do (<- x expr) ...)` desugars to the Command/Response model at AST level. No new runtime semantics.

**[CT]** Event Log spec — formalized `(Input, CommandResult, captures)` deterministic replay. NaN rejected at GHC/WASM boundary.

**[CT]** `Promise[t]` upgrade: `IO t` → `Async t` from the `async` package. `(await x)` desugars to `Async.wait`.

**Acceptance criteria:**
- Two-agent demo: Agent A writes a module with `?delegate`, Agent B submits a JSON-Patch; compiler accepts the merge.
- A `?proof-required :inductive` hole for a structural list property is resolved by Leanstral; certificate verified on next build without a Leanstral call.

---

## v0.4 — WASM Hardening

**Theme:** Replace Docker with WASM-WASI as the primary sandbox. No new language semantics.

**[CT]** `llmll build --target wasm` — compile generated Haskell with `ghc --target=wasm32-wasi`.

**[CT]** WASM VM (Wasmtime) replaces Docker as default sandbox.

**[CT]** Capability enforcement via WASI import declarations (replaces Docker network/filesystem policy layer).

**[CT]** Resolve any GHC WASM backend compatibility issues for `effectful`, `QuickCheck`, and other vendored dependencies. Maintain a minimal shim package if needed.

**Acceptance criteria:**
- `llmll build --target wasm examples/hangman.llmll` produces a `.wasm` binary that runs in Wasmtime and passes all `check` blocks.
- A capability violation terminates the WASM instance with a typed error.

---

## Summary: What Changed from LLMLL.md §14

| Version | Original | Revised |
|---------|----------|---------|
| **v0.1.2** | JSON-AST + FFI stdlib | JSON-AST + **Haskell codegen** + typed effect row + hole-density validator + Docker sandbox |
| **v0.2** | Module system (unscheduled) + Z3 liquid types | Module system **first** → **LiquidHaskell** (replaces Z3 binding project) → pair-type fix + `--sketch` API |
| **v0.3** | Agent coordination + Lean 4 agent *(to be built)* | Agent coordination + **Leanstral MCP integration** *(agent exists; build translation layer only)* + `do`-notation |
| **v0.4** | *(not planned)* | WASM hardening: `--target wasm`, WASM VM replaces Docker |

### Items Removed from Scope

| Item | Reason |
|------|--------|
| Rust FFI stdlib (`serde_json`, `clap`, etc.) | Replaced by native Hackage imports |
| Z3 binding layer (build from scratch) | Replaced by LiquidHaskell GHC plugin |
| Lean 4 proof agent (build from scratch) | Replaced by Leanstral MCP integration |
| Python FFI tier | Breaks WASM compatibility; dynamically typed; dropped from spec |
| Opaque `Command` type | Replaced by typed effect row (`Eff '[...]`) |
