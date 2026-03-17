# LLMLL Strategic Proposals — Consolidated Team Document

> **Status:** Ready for Team Review  
> **Prepared by:** PhD Research Team  
> **Date:** 2026-03-17  
> **Related documents:** `LLMLL.md` · `docs/project-management/roadmap.md` · `docs/proposals/proposal-haskell-target.md` · `docs/proposals/analysis-leanstral.md`

---

## Executive Summary

This document consolidates three research discussions into a set of actionable, prioritized proposals. The central argument is:

> LLMLL's design was originally optimized for human-directed, Rust-targeting code generation. Given that the language's primary writers are AI agents, and given new tools available in the ecosystem, several foundational decisions should be revisited before the compiler matures further.

The proposals are ordered by impact and urgency.

---

## Priority 1 — JSON-AST as the Primary AI-to-Compiler Interface

**Urgency: Immediate (v0.1.2)**

### Problem
AI agents generating LLMLL S-expressions suffer **parentheses drift** — a structural error where the LLM loses track of nesting depth across long generations. This causes syntax errors at the compiler boundary, which the AI cannot reliably parse or fix, leading to hallucination loops.

### Proposal
Make JSON-AST the **primary** compiler input format. S-expressions remain as a human-readable surface layer only.

- A formal JSON Schema has been written: [`docs/llmll-ast.schema.json`](file:///Users/burcsahinoglu/Documents/llmll/docs/llmll-ast.schema.json)
- Every node is discriminated by a `"kind"` field; `additionalProperties: false` everywhere prevents hallucination of extra fields
- LLM inference APIs (OpenAI Structured Outputs, Gemini schema parameters) can enforce the schema at generation time — structural validity is **mathematically guaranteed** before the compiler runs

### Key changes
| Deliverable | Description |
|-------------|-------------|
| `ParserJSON.hs` | New compiler module; ingests `.ast.json` → same `[Statement]` AST as the S-expression parser |
| `llmll build --emit json-ast` | Round-trips S-expressions ↔ JSON |
| JSON diagnostics | Every compiler error is a JSON object with RFC 6901 JSON Pointer to the offending node |
| `llmll holes --json` | Lists all `?` holes with inferred type, module path, and agent target |

### Impact on the surface syntax debate
Since AI agents write JSON, the S-expression syntax only needs to serve **human developers** writing small examples and tests. Only minimal S-expression fixes are warranted (Option A: `let` double brackets, `pair` keyword, list literals). A full syntax redesign (Option B) is not justified given that AI uses JSON.

---

## Priority 2 — Move Code Generation Target from Rust to Haskell

**Urgency: v0.1.2 alongside JSON-AST**

### Problem
The compiler is written in Haskell, but generates Rust. This creates a **semantic impedance mismatch**: LLMLL's concepts (pure functions, ADTs, algebraic effects, liquid types) map directly onto Haskell's native semantics, yet codegen translates them into an ownership-based language not designed for them. More critically, the primary justification for Rust — WASM sandboxing — is not a hard constraint at the current research stage.

### Proposal
Switch `Codegen.hs` to emit **Haskell** instead of Rust.

**What disappears:** Most of the FFI standard library (`serde_json`, `clap`, `env`, `atomic_fs`, `timer`) becomes native Hackage imports — no stubs, no `todo!()`, no `Cargo.toml` editing.

**Semantic gains:**

| LLMLL concept | Generated Haskell (native) |
|---------------|---------------------------|
| `def-logic`, pure functions | Haskell functions |
| ADT `(type T ...)` | `data T = ...` |
| `def-interface` | Type classes |
| `pre`/`post` contracts | LiquidHaskell annotations |
| `check`/`for-all` | QuickCheck `property`/`forAll` |
| `Command` / effect model | Algebraic effects (`polysemy`/`fused-effects`) |

**Revised FFI model (three tiers):**

| Tier | Prefix | Mechanism | Examples |
|------|--------|-----------|---------|
| 1 — Hackage | `haskell.*` | Regular GHC `import`; no stub | `Data.Aeson`, `Options.Applicative` |
| 2 — C libraries | `c.*` | GHC `foreign import ccall`; `.hs` stub generated | SQLite, libsodium |
| 3 — Python | `python.*` | `inline-python` bridge; `.hs` stub generated | NumPy, PyTorch |

**Sandboxing without WASM (three layers):**

| Layer | Mechanism | Guarantee |
|-------|-----------|-----------|
| Source | `-XSafe` GHC pragma on generated modules | Generated code **cannot** perform IO outside declared capabilities — enforced by type system |
| Process | `seccomp-bpf` (Linux) / `Sandbox.framework` (macOS) | Syscall whitelist matching declared capabilities — violations terminate with `SIGSYS` |
| Container | **Docker** | Filesystem/network isolation; writable volumes only for declared paths; resource limits |

**Path to WASM (incremental, not abandoned):**

| Phase | Action |
|-------|--------|
| v0.1.2 | Haskell codegen + Docker sandboxing |
| v0.2 | Validate generated `.hs` compiles with GHC WASM backend |
| v0.3 | `llmll build --target wasm` opt-in flag |
| v0.4 | WASM VM replaces Docker as primary sandbox |

**Migration cost:** `Codegen.hs` is one module. The rest of the compiler (`Lexer.hs`, `Parser.hs`, `TypeCheck.hs`, `HoleAnalysis.hs`) is unchanged. The JSON-AST schema is target-independent.

---

## Priority 3 — Promote the Module System to an Explicit v0.2 Deliverable

**Urgency: v0.2 (currently unscheduled)**

### Problem
`LLMLL.md §8` explicitly states that multi-file module resolution is "deferred to v0.2." However, the `docs/project-management/roadmap.md` v0.2 section does not schedule it — it goes directly to Liquid Types. The module system is a **prerequisite** for the multi-agent swarm model (`def-interface` treaty, `?delegate` protocol) and for cross-module invariant verification. Without it, §11 (Multi-Agent Concurrency) is entirely theoretical.

### Proposal
Add as explicit v0.2 deliverables:
- Multi-file resolution: `(import foo.bar ...)` loads and type-checks `foo/bar.llmll`
- Namespace isolation: each source file has its own top-level scope
- `llmll-hub` read-only module registry (prerequisite for `?scaffold` in v0.3)

---

## Priority 4 — Integrate Leanstral as the v0.3 Proof Agent

**Urgency: v0.3 (or late v0.2)**

### Background
Mistral AI has released **Leanstral** ([announcement](https://mistral.ai/news/leanstral)): an open-source (Apache 2.0), 6B-active-parameter model trained specifically for Lean 4 proof engineering in realistic formal repositories. It outperforms Claude Sonnet on formal proof tasks at 1/15th the cost ($36 vs $549 per run).

### Impact on LLMLL v0.3
The roadmap item *"Specialist Lean 4 proof-synthesis agent — must be built"* is now an **integration task**:

| LLMLL v0.3 item | Previous status | After Leanstral |
|---|---|---|
| Lean 4 proof-synthesis agent | Must be built | **Exists — integrate via MCP** |
| `?proof-required` hole resolution | Blocked on agent | Unblocked |
| Tactic library S-expression macros | Must be curated | Leanstral handles tactics natively |

### Integration architecture
1. `llmll holes --json` emits `?proof-required` holes as structured JSON (already designed in v0.1.2)
2. Compiler translates LLMLL `(where [x: int] predicate)` → Lean 4 `theorem` obligation
3. Leanstral MCP call returns verified proof term
4. `llmll check` stores certificate; verifies it on subsequent runs without re-calling Leanstral

### Recommendation
Consider pulling `?proof-required` holes into **late v0.2** — since the hardest engineering piece (the model) is now given for free, only the translation layer needs to be built.

---

## Priority 5 — Minimal Surface Syntax Fixes (Option A)

**Urgency: Low (v0.1.2 maintenance, humans only)**

Since AI agents write JSON-AST, S-expression fixes only affect human developer ergonomics. Three targeted changes are sufficient:

| Current | Fixed | Pain point removed |
|---------|-------|--------------------|
| `(let [[x e1] [y e2]] body)` | `(let [x = e1, y = e2] body)` | Double-bracket confusion |
| `(pair a b)` | `(, a b)` or allow `(a , b)` | Constructor/type-notation mismatch |
| `(list-empty)` / `(list-append l e)` | `[]` / `[a b c]` literals | Verbose for humans writing tests |

A full syntax redesign (Option B — Haskell-inspired infix) is not warranted. The human audience tolerates idiomatic Lisp; the AI audience uses JSON.

---

## Revised Roadmap Summary

| Version | Theme | Key Deliverables |
|---------|-------|-----------------|
| **v0.1.1** | Spec completeness | Current — `range`, ADTs, `Command`, `let*`, standard command library |
| **v0.1.2** | Machine-first foundation | **JSON-AST ingest**, **Haskell codegen**, JSON diagnostics, `llmll holes --json`, FFI-stdlib → Hackage, S-expression Option A fixes |
| **v0.2** | Module system + verification | **Multi-file module resolution**, `llmll-hub` registry, LiquidHaskell integration, `letrec`, static `match` exhaustiveness, `def-invariant` Z3 verification, capability enforcement, (optionally: `?proof-required` + Leanstral) |
| **v0.3** | Agent coordination + proofs | `?delegate` JSON-Patch protocol, `?scaffold`, **Leanstral MCP integration**, Event Log spec, deterministic replay, monadic `do`-notation |
| **v0.4** | WASM hardening | `llmll build --target wasm`, WASM VM replaces Docker sandbox |

---

## Decision Points Requiring Team Consensus

> [!IMPORTANT]
> The following decisions have significant downstream consequences and require explicit team agreement before implementation begins.

| Decision | Options | Recommendation |
|----------|---------|----------------|
| **Rust → Haskell codegen** | Keep Rust / Switch to Haskell | Switch to Haskell — eliminates Z3 binding layer, FFI-stdlib, and codegen complexity |
| **WASM requirement** | WASM now / Docker + WASM later | Docker in v0.1.2; WASM in v0.4 — unblocks research velocity immediately |
| **Leanstral timing** | v0.2 / v0.3 | Late v0.2 if translation layer is simple; v0.3 if not |
| **Surface syntax** | Option A (minimal) / Option B (Haskell-inspired) / No change | Option A — humans only, low priority |
