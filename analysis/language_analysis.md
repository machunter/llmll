# LLMLL Compiler — Implementation Language Analysis

## Rust vs Haskell vs Racket

Three languages are natural candidates for implementing a strongly-typed, functional language compiler targeting WASM. Each has real strengths and real costs.

---

## Scorecard

| Dimension | Rust | Haskell | Racket |
|---|---|---|---|
| AST modeling (ADTs, pattern matching) | ✅ Good (enums) | ✅✅ Excellent (native ADTs, GADTs) | ✅ Good (structs, `match`) |
| S-expression parsing | ⚠️ Manual or `nom` | ⚠️ Parsec/Megaparsec | ✅✅ **Native** (reader built-in) |
| Type system implementation | ✅ Manual but solid | ✅✅ Natural (monadic type checkers) | ⚠️ Doable, less idiomatic |
| WASM compilation target | ✅✅ **First-class** (`wasm32-wasi`) | ⚠️ Possible via Asterius/GHCJS, not mature | ❌ No direct path |
| WASM runtime hosting (Wasmtime) | ✅✅ **Native Rust bindings** | ⚠️ FFI to C API | ⚠️ FFI to C API |
| Property-based testing | ✅ `proptest` | ✅✅ QuickCheck (invented here) | ✅ `rackcheck` |
| Ecosystem maturity for compilers | ✅ Growing (`lalrpop`, `cranelift`) | ✅✅ **Gold standard** (decades of PL research) | ✅✅ **Gold standard** (Racket is a language lab) |
| Runtime performance | ✅✅ Best | ✅ Good (lazy eval overhead) | ⚠️ Adequate |
| Developer iteration speed | ⚠️ Slower (borrow checker friction) | ✅ Fast for PL work | ✅✅ **Fastest** (REPL-driven) |
| Team hiring / contributor pool | ✅ Growing | ⚠️ Niche | ⚠️ Niche |

---

## Rust

**Why it works:** Rust is the transpilation target (you'd be dogfooding the output language). Wasmtime has native Rust bindings, so the WASM runtime (Phase 7) is straightforward. The `enum` + `match` system is good enough for AST work. `nom` or `pest` handle S-expression parsing.

**Where it hurts:** Building a type checker in Rust means fighting the borrow checker on recursive AST walks. You'll use `Box`, `Rc`, or arena allocation extensively. Monadic patterns (essential for type inference) are verbose without HKTs. Iteration speed is slower — every refactor of the AST propagates through exhaustive `match` arms.

**Best for:** a production-quality compiler where WASM execution and runtime performance matter most.

---

## Haskell

**Why it works:** Haskell is arguably the *natural* language for this task. The entire PL research ecosystem lives here. ADTs with pattern matching model ASTs directly. Monadic type checkers (using `StateT` + `ExceptT`) are idiomatic. Parsec/Megaparsec make parser combinators effortless. QuickCheck (property-based testing) was invented in Haskell. GHC's own implementation is a living reference for every compiler phase you need.

The LLMLL spec's core concepts — immutability, pure functions, algebraic types, contracts — are Haskell's home turf. You'd be implementing a functional language *in* a functional language, and every design decision maps cleanly.

**Where it hurts:**
1. **WASM story is weak.** Compiling Haskell *to* WASM (for the runtime) requires Asterius or the experimental GHC WASM backend — neither is production-grade. Hosting WASM (running Wasmtime) requires FFI to its C API.
2. **Lazy evaluation** introduces space leaks that require profiling experience to diagnose.
3. **Hiring pool** is smaller. Contributing to a Haskell codebase requires comfort with monad transformers, type classes, and GHC extensions.

**Best for:** a research-grade compiler where correctness, type system expressiveness, and rapid prototyping matter more than WASM integration.

---

## Racket

**Why it works:** Racket is a **language laboratory** — it was designed specifically for building new programming languages. Its killer feature here is that **S-expressions are native syntax**. The LLMLL lexer/parser (Phase 1–2) is essentially free: Racket's reader already parses S-expressions into a structured data representation. You'd skip straight to semantic analysis.

Racket's `#lang` mechanism lets you define LLMLL as a new `#lang llmll` that plugs into the Racket toolchain (syntax highlighting, REPL, module system). The macro system lets you prototype new language features as syntactic transformations before committing to a full compiler pass. `rackcheck` provides property-based testing.

**Where it hurts:**
1. **No WASM path.** Racket compiles to Chez Scheme bytecode. There's no mature story for compiling Racket to WASM or hosting WASM modules from Racket. The entire WASM pipeline (Phases 7–8) would need an external tool or FFI bridge.
2. **Dynamic typing.** Racket is dynamically typed by default. Typed Racket exists but is opt-in and has a different feel. Implementing a *strongly typed* language in a *dynamically typed* host means your type checker has no assistance from the host's type system — bugs in the checker itself won't be caught by the host compiler.
3. **Performance.** Adequate for a compiler, but noticeably slower than Rust or Haskell for large-scale code generation and WASM hosting.

**Best for:** rapid prototyping of the language semantics and parser, especially if the WASM runtime is deferred or handled by an external tool.

---

## Hybrid Approaches Worth Considering

### Racket for prototyping → Rust for production

Use Racket initially to nail down the language semantics: parser (free), type checker (fast iteration), contract enforcement, PBT. Once the semantics are stable, rewrite the compiler in Rust for the WASM pipeline. The Racket prototype becomes the reference implementation and test oracle.

**Risk:** maintaining two codebases, even temporarily, is expensive.

### Haskell for compiler + Rust for runtime

The compiler front-end (lexer → parser → type checker → Rust code emitter) lives in Haskell. The output is still Rust source code, which gets compiled to WASM normally. The WASM host runtime is a separate Rust binary using Wasmtime.

**Benefit:** best of both worlds — Haskell's PL strengths for the hard parts, Rust's WASM strengths for execution.
**Risk:** two-language build system, plus guaranteed Haskell ↔ Rust interop overhead at the boundary.

---

## Recommendation

| Priority | Language | Rationale |
|---|---|---|
| **If WASM execution is day-one critical** | **Rust** | Only language where lexer-to-WASM-runtime is one toolchain |
| **If compiler correctness and speed-of-development matter most** | **Haskell** | Natural fit for every compiler phase; WASM deferred to Rust runtime binary |
| **If you want to explore language design before committing** | **Racket** | Fastest path to a working prototype; free S-expression parsing; no WASM story |

The strongest move depends on your priorities. If you're building a production system, Rust keeps everything in one stack. If you're building the *right* language first and shipping later, Haskell gets you a correct compiler faster with less friction on the hard parts (type checking, contract analysis, PBT).
