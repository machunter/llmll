# LLMLL Improvement Roadmap

> **Sources:** PhD language review · Distinguished Engineer review · Developer SPEC-GAPS feedback (Hangman implementation)
>
> This document supersedes the version roadmap stub in LLMLL.md §12.

---

## Guiding Principles

Before the version plan: three lessons that cut across all feedback received.

**1. Serve the implementer first.**
The spec existed for months without being exercised against real code. The hangman exercise exposed more actionable gaps in one day than all theoretical analysis combined. Every future version must be gated on at least one non-trivial example program written under spec constraints only.

**2. Specification debt is not design debt.**
Every blocking gap found in SPEC-GAPS.md (range, ADTs, Command type, let semantics) stems from the spec being incomplete, not from the language design being wrong. The core model — holes, contracts, sandboxed IO, functional state — held up under exercise. Fix the spec before adding features.

**3. Decidability is a first-class constraint.**
The language targets LLM code generation and SMT-backed verification. Every feature introduced in v0.2+ must be evaluated against its SMT decidability profile. Features that create undecidable proof obligations must either be restricted or escalate to interactive proofs (Lean 4, v0.3).

---

## v0.1.1 — Specification Completeness Patch

> **Goal:** Zero blocking gaps. The spec must be sufficient to write any program that only uses v0.1 primitives, without any workarounds.
> **Gating example:** `hangman_complete.llmll` must be expressible without the 50-line `index-range-50` workaround.

### Spec Changes (LLMLL.md)

#### §3 Type System
- **Add `Command`** as a built-in opaque type. It is not constructable by users directly — only via capability-namespaced constructors. Add to the Compound Types table.
- **Add ADT / sum type declarations:**
  ```lisp
  (type GameInput
    (| Start Word)
    (| Guess Letter))
  ```
  This formalises what §11.2's `DelegationError` already implied. Update grammar §12 with the `type-body` production.

#### §4 Logic Structures
- **Clarify `result` scope:** Reserve `result` as a keyword bound exclusively inside `post` clauses to the return value of the function body. It is a compile error in `pre` clauses. It cannot be used as a parameter name. Document in §13 under "Clause-Scoped Bindings."

#### §8 Let Expressions
- **State explicitly:** `let` bindings are **sequential** (equivalent to Scheme `let*`). Each binding is in scope for all subsequent bindings in the same `let` block.

#### §9 IO & Side Effects
- **Add `QualIdent` to grammar:** `IDENT { "." IDENT }` — allows `wasi.io.stdout` as a valid function reference.
- **Add `(seq-commands cmd1 cmd2) -> Command`** as a built-in combinator for emitting multiple effects from one logic function.
- **Define standard command constructors** in a new §13.6:
  ```
  wasi.io.stdout   : string -> Command
  wasi.io.stderr   : string -> Command
  wasi.http.response : int -> string -> Command
  wasi.fs.read     : string -> Command
  wasi.fs.write    : string -> bytes -> Command
  ```

#### §11 Multi-Agent
- **`def-interface` fn-type:** Allow `(fn [name: type ...] -> type)` with named parameters as documentation-only. Both named and anonymous forms are accepted; names are erased before type-checking.

#### §12 Grammar
- **`->` tokenisation:** Add `ARROW = "->" ;` as a named terminal. State the lexer uses maximal munch — `->`  is always a single token.
- **`match` semantics:** `_` is the catch-all wildcard. A `match` without `_` that fails at runtime raises `MatchFailure`. Document in §6.
- **`=` polymorphism:** `=` is a polymorphic structural equality operator over all LLMLL types. String equality is byte-by-byte (UTF-8). Document in §13.2.

#### §13 Built-in Functions
- **Add `(range from: int to: int) -> list[int]`** — produces `[from, from+1, ..., to-1]`. This unblocks all bounded iteration patterns. Goes in §13.5 (List Operations).
- **Add `result` pseudo-binding** documentation in a new §13.7 (Clause-Scoped Bindings).

#### §5 Property-Based Testing
- **PBT generation for dependent types:** If no custom generator is registered, the engine uses rejection sampling with a minimum floor of 100 valid samples before reporting a generation error.
- **Add `(gen TypeName generator-expr)` declaration** for user-defined generators.

### Compiler Changes (Haskell)
- `Syntax.hs`: Add `TCommand`, `TSum [(Name, Type)]` to the `Type` ADT.
- `Parser.hs`: Add `QualIdent` parsing; `(type T (| ...))` sum type declarations; `(gen ...)` declarations.
- `TypeCheck.hs`: Resolve qualified identifiers against capability imports; type-check ADT constructors and `match` arms against declared ADT.
- `Codegen.hs`: Map ADT → Rust `enum`; `Command` → `Box<dyn Command>` trait object; `range` → `(from..to).collect::<Vec<_>>()`.
- `PBT.hs`: Add rejection-sampling generator for `TDependent`; add `(gen ...)` registration.

---

## v0.2 — Compile-Time Verification (Liquid Types)

> **Goal:** Move from runtime contract assertions to compile-time SMT verification. Introduce liquid types as the formal specification of the constraint language.
> **Gating example:** `hangman_complete.llmll` compiles with all `pre`/`post` contracts verified statically by Z3.

### What Are Liquid Types and Why Now

Liquid types (Rondon, Kawaguchi, Jhala — PLDI 2008) are refinement types where the constraint predicate is restricted to a **decidable fragment of logic** — quantifier-free linear arithmetic and equality over uninterpreted functions. Z3 is guaranteed to terminate on any such predicate.

The syntax maps directly onto LLMLL's dependent type annotation:

```lisp
;; A liquid-typed function: Z3 verifies the postcondition at compile time
(def-logic withdraw [balance: {int | (>= v 0)} amount: {int | (> v 0)}]
  :pre  (>= balance amount)
  :post (= result (- balance amount))
  (- balance amount))
```

This is the concrete realisation of the PhD review's "Turing-incomplete proof sublanguage" recommendation, and the specification of the constraint language the current v0.2 roadmap left undefined.

### Language Changes
- Formalise the liquid type constraint language: quantifier-free linear arithmetic + uninterpreted functions. Any `(where ...)` predicate that falls outside this fragment is a compile error in v0.2 with a suggestion to use `?proof-required`.
- Add `{base | predicate}` as an inline liquid type annotation (in addition to the standalone `(type T (where ...))` form).
- Add `?proof-required` hole: a constraint the liquid type checker cannot decide. Generates a typed hole for the Lean 4 agent (v0.3).

### Compiler Changes
- Add Z3 binding layer (via Haskell `z3` package or subprocess to Z3 binary).
- Upgrade `Contracts.hs` to a `LiquidCheck.hs` pass that sends predicate constraints to Z3 instead of emitting runtime `assert!()` calls.
- Implement type inference: the checker infers the strongest liquid invariant consistent with the function body, so the programmer rarely has to annotate manually.
- For each `pre`/`post` on which Z3 provides a proof: elide the runtime `assert!()` in the generated Rust code (sound because equivalently verified statically).
- For each `pre`/`post` on which Z3 times out or the predicate is out of fragment: emit a `?proof-required` hole in the hole report and retain the runtime assertion.
- Cache Z3 results per module (invalidated on any change to the module's AST) to make incremental compilation fast.

### Recursion with Termination Annotations
- Add `letrec` with mandatory termination annotation:
  ```lisp
  (letrec [f (fn [n: int] :decreases n
              (if (= n 0) 1 (* n (f (- n 1)))))]
    (f 10))
  ```
- The termination metric (`:decreases <expr>`) is verified by Z3 (linear arithmetic can express `n - 1 < n` for natural number induction). Non-linear or structural recursion generates `?proof-required`.

### match Exhaustiveness (Static)
- With ADTs now in the type system, `match` on an ADT value is statically verified exhaustive. Missing arms are compile errors.
- `_` wildcard remains valid; the checker warns if it shadows a specific arm.

---

## v0.3 — Interactive Proofs & Multi-Agent at Scale

> **Goal:** Escape hatch for properties outside the liquid type decidable fragment. Full multi-agent infrastructure with fault semantics.

### Lean 4 Proof Agent
- `?proof-required` holes generated in v0.2 are routed to a specialised Lean 4 agent.
- The compiler emits a Lean 4 proof obligation from the LLMLL AST: the agent fills it, the result is a certificate stored alongside the `.llmll` source.
- The `llmll check` command verifies the Lean 4 certificate without re-running the prover.

### Macro-Driven Tactic Library
- Provide a built-in library of proof tactics as S-expression macros so the Lean 4 agent has a structured vocabulary:
  ```lisp
  (prove-by-induction :on n :base (= (f 0) 1) :step ...)
  (prove-by-exhaustion :cases GameInput)
  ```
  This reduces the Lean 4 agent's output to a structured tactic selection rather than raw proof term generation.

### Cold-Start / Scaffold Holes
- Add `?scaffold` as a first-class hole type:
  ```lisp
  (?scaffold web-api-server
    :language llmll
    :modules  [routing auth persistence]
    :style    rest)
  ```
- Resolves to a pre-typed, hole-populated AST skeleton from the `llmll-hub` template library.
- Skeletons have all `def-interface` boundaries pre-defined and type-checked; implementation details are pre-filled as named `?` holes ready for delegation.

### Global Module Invariants
- Add `(def-invariant [state: AppState] predicate)` at module level.
- After any AST merge (concurrent agent development), the compiler runs SMT verification of all module invariants automatically. A merge that breaks a global invariant is rejected at the compiler level, not at runtime.

### Event Log Specification (Deterministic Replay)
- Formalise the event log format in a new §10a of LLMLL.md:
  - Every `(Input, ExternalCommandResult)` pair is recorded, not just inputs.
  - The runtime virtualises `wasi.clock` and `wasi.random` through loggable capability wrappers (`:deterministic true`); captured values are stored in the event log.
  - Non-canonical NaN is rejected at the WASM boundary.
- This is the prerequisite for SMT reasoning over replayed execution traces.

### Async IO — Monadic `do` Surface Syntax
- Add `do`-block syntactic sugar over S-expressions for sequential IO:
  ```lisp
  (do
    [user  <- (db.query :users {:id request-id})]
    [token <- (auth.create-token user)]
    (http.respond 200 token))
  ```
- The compiler desugars `do`-blocks into the canonical `(State, Input) -> (NewState, Command)` form. The LLM generates linear sequential code; the IO model remains pure.

---

## Open Questions (Not Yet Scheduled)

These items require empirical data or design decisions before scheduling.

| Question | Status | Next Step |
|---|---|---|
| **S-expression vs. JSON-AST syntax** | Unresolved | Benchmark both on LLM code generation: measure syntax error rate, hole placement accuracy, token count on identical programs |
| **`repeat` / bounded accumulator** | Deferred (v0.2+) | Assess whether `letrec` + termination annotations make this redundant |
| **`let-parallel` form** | Likely unnecessary | Revisit after v0.1.1 sequential `let` lands; only add if a concrete use case demands simultaneous binding |
| **JSON-AST interchange format** | Desired (v0.2) | Ship a JSON-AST alternate surface syntax in v0.2 to reduce syntax experiment cost; keeps S-expression as canonical |

---

## Version Summary

| Version | Theme | Key Deliverables |
|---|---|---|
| **v0.1.1** | Spec completeness + developer ergonomics | `range`, `Command` type, ADTs, `let` semantics, `result` keyword, `QualIdent`, standard command library; **Unicode symbol aliases** (`→` `∀` `λ` `∧` `∨` `¬` `≥` `≤` `≠`) |
| **v0.2** | Compile-time safety | Liquid types + Z3, `letrec` with termination, static `match` exhaustiveness, JSON-AST interchange |
| **v0.3** | Scale & correctness | Lean 4 proof agent, `?scaffold`, `def-invariant`, deterministic replay spec, monadic `do`-blocks |
