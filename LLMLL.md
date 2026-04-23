# LLMLL: Large Language Model Logical Language (v0.6.0)

**`llmll`** is a programming language designed specifically for AI-to-AI implementation under human direction. It prioritizes contract clarity, token efficiency, and ambiguity resolution over human readability.

> **Current version: v0.6.0 (shipped).** Haskell codegen is the only backend. Every construct in this document has fully defined syntax, grammar, and runtime semantics, and compiles with 0 errors in the current compiler. 279 Haskell + 37 Python tests passing. See [`CHANGELOG.md`](CHANGELOG.md) for full release notes and [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) for the implementation schedule.

<details><summary><strong>Release history (v0.1.1 → v0.6.0)</strong></summary>

| Version | Headline |
|---------|----------|
| **v0.6.0** | Specification Quality: `--spec-coverage` gate classifies functions as contracted/suppressed/unspecified and computes effective coverage. `(weakness-ok fn "reason")` suppression governance. `:source` clause-level provenance on `pre`/`post` contracts. Frozen ERC-20 benchmark with verification-scope matrix. 279 total tests $+$ 15 new. |
| **v0.5.0** | U-Full Soundness: occurs check prevents infinite types. Let-generalization for top-level `def-logic`/`letrec` via TVar-TVar wildcard closure and bound-TVar consistency fix. Closes the last known unsoundness in the type checker. 264 total tests $+$ 7 new U-Full. |
| **v0.4.0** | Lead Agent (`llmll-orchestra --mode plan\|lead\|auto`). U-Lite: substitution-based unification for concrete types (`list-head 42` is a type error; `first`/`second` typed `TPair a b → a`/`b`). CAP-1: capability imports enforced at compile time (non-transitive, module-local). Invariant pattern registry via `--sketch`. Downstream obligation mining. Aeson FFI codegen. |
| **v0.3.5** | Context-aware `llmll checkout` returns local typing context (Γ, τ, Σ). `llmll verify --weakness-check` detects trivial-body spec weaknesses. Orchestrator E2E with diagnostic-driven retry, lock expiry handling, and context-aware prompts. |
| **v0.3.4** | `llmll spec` emits agent prompt specification from `builtinEnv` (36 builtins + 14 operators). 7 faithfulness property tests. Orchestrator integration with backward-compat fallback. Phase A prompt enrichment. New builtins: `string-empty?`, `regex-match`. `is-valid?` removed. |
| **v0.3.3** | Agent orchestration compiler support — `llmll holes --json --deps` with Tarjan's SCC cycle detection; `--deps-out FILE`. |
| **v0.3.2** | Trust hardening — `llmll verify --trust-report` with epistemic drift detection; cross-module trust propagation. GHC WASM PoC (conditional GO — feasibility confirmed). |
| **v0.3.1** | JSONL event log with deterministic replay (`llmll replay`). Leanstral MCP proof integration (mock-first, `--leanstral-mock`). SHA-256 proof cache (`.proof-cache.json`). |
| **v0.3** | `do`-notation (PRs 1–4). Stratified verification, `--contracts` flag, `.verified.json` sidecar. `string-concat` variadic sugar. `?scaffold` CLI. `Promise[t]` → `Async t`. |
| **Phase 2c** | Pair-type in typed parameters. `llmll typecheck --sketch` partial-program type inference. `llmll serve` HTTP sketch endpoint. |
| **Phase 2b** | Compile-time contract verification via liquid-fixpoint (`llmll verify`). `letrec` with `:decreases` termination. `match` exhaustiveness. `?proof-required` holes. |
| **Phase 2a** | Multi-file module system: `import`, `open`, `export`, `llmll-hub` registry. Cross-module `def-interface` enforcement. |
| **v0.1.2** | JSON-AST as first-class source format. Haskell codegen target. Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` sandbox. |
| **v0.1.1** | `Command` type, custom ADT sum types, `range`, `QualIdent`, Unicode aliases, `result` keyword, sequential `let`, standard command library, `def-invariant` syntax. |

</details>

> **For AI code generators:** Every section contains at least one complete, compilable example. When generating LLMLL code, you must use only the constructs defined in this document. If a required construct is missing, emit a named `?hole` and document the gap — do not invent syntax.

---

## 1. Core Philosophy

1. **Strict Immutability:** There are no variables, only constants. State is transformed, never mutated. Re-binding the same name in the same scope is a compile error.
2. **Hole-Driven Development:** Ambiguity is a first-class citizen represented by Holes (`?`). A program with holes can be analyzed and type-checked but not executed until the holes are filled. Always prefer a typed hole over a hallucinated implementation.
3. **Typed Logic:** Every expression has a type. The type system prevents null pointer dereferences, type mismatches, and unguarded IO. Return types are inferred — never annotate them explicitly.
4. **Design by Contract with Stratified Verification:** Logic functions declare `pre` and `post` conditions as formal specifications. These contracts are the trust interface between agents. Verification is stratified: contracts in the decidable arithmetic fragment are proven at compile time (liquid-fixpoint / Z3); contracts requiring induction are routed to interactive proof (Leanstral); contracts outside both fragments are enforced as runtime assertions and flagged with `?proof-required`. A caller can inspect a contract's *verification level* — proven, tested, or asserted — without reading the implementation.
5. **Capability-Based Security:** LLMLL programs run in a sandboxed environment (Docker + `seccomp-bpf` + `-XSafe` Haskell in v0.1.2–v0.6.0; WASM-WASI planned as a future deployment target). Programs have zero access to the system unless explicitly granted via a `capability` import. Every side effect is modeled as a `Command` value returned from pure logic — never performed directly. Since v0.4.0 (CAP-1), capability imports are enforced at compile time.

---

## 2. Syntax (S-Expressions)

`llmll` uses Lisp-style S-expressions to represent the Abstract Syntax Tree (AST) directly. This is token-efficient and eliminates parsing ambiguity.

### 2.1 Basic Tokens

- **Keywords:** `module`, `import`, `def-logic`, `def-interface`, `type`, `let`, `if`, `match`, `check`, `pre`, `post`, `for-all`, `gen`, `pair`, `fn`, `where`, `await`, `do`.
- **Reserved identifiers:** `result` (see §4.2), `unit`, `true`, `false`.
- **Primitive types:** `int`, `float`, `string`, `bool`, `unit`.
- **Holes:** Always start with `?` (e.g., `?logic_name`, `?choose(option1, option2)`).
- **Comments:** `;; text` — from `;;` to end of line. Ignored by the compiler.
- **Source encoding:** Source files are **UTF-8**. **Identifiers must be ASCII** (letters, digits, `-`, `_`). A curated set of Unicode mathematical symbols are accepted as **aliases** for specific keywords and operators — see §2.4. All other non-ASCII characters are a lexer error.
- **S-expression string escapes:** `\n`, `\t`, `\r`, `\\`, `\"`, and `\uXXXX` (added v0.2). Standard Haskell-style character escapes.
- **JSON-AST string values** follow RFC 8259 — non-ASCII and control characters must be encoded as `\uXXXX` (e.g. `\u001b` for ESC). The C-style `\xNN` form is not valid JSON.

### 2.2 Qualified Identifiers

Capability-namespaced names use dot notation and are called **qualified identifiers** (`QualIdent`):

```
wasi.io.stdout
wasi.http.response
wasi.fs.write
```

A `QualIdent` is one or more plain identifiers joined by `.`. They are valid in function-call position (`app` expressions) and in `import` forms. Plain identifiers (`IDENT`) may not contain dots.

### 2.3 The Arrow Token

Both `->` (ASCII) and `→` (U+2192) are accepted and produce the same ARROW token. The lexer uses **maximal munch**: `->` is always tokenized as a single ARROW, never as subtraction followed by greater-than. There is no position ambiguity: ARROW only appears in type position (after a parameter list in `fn-type` or `def-interface`), while `-` (subtraction) and `>` (comparison) only appear in expression position.

### 2.4 Unicode Symbol Aliases

A curated set of Unicode mathematical symbols are accepted everywhere their ASCII equivalents are valid. Both forms compile to **identical AST nodes**. The compiler's canonical output and error messages always use the ASCII form. LLMs may use whichever form they prefer in generated code.

| ASCII | Unicode | U+ | Meaning |
|-------|---------|----|---------|
| `->` | `→` | U+2192 | Function / return arrow |
| `>=` | `≥` | U+2265 | Greater-or-equal |
| `<=` | `≤` | U+2264 | Less-or-equal |
| `!=` | `≠` | U+2260 | Not-equal |
| `and` | `∧` | U+2227 | Logical conjunction |
| `or` | `∨` | U+2228 | Logical disjunction |
| `not` | `¬` | U+00AC | Logical negation |
| `for-all` | `∀` | U+2200 | Universal quantifier |
| `fn` | `λ` | U+03BB | Lambda / anonymous function |

**What is NOT allowed:** Unicode-encoded variable names, function names, type names, or module names. Identifiers must be ASCII. This restriction prevents homoglyph attacks and invisible-character exploits in multi-agent AST merging (see `analysis/unicode_decision.md` for full rationale).

**Mixed-form example** — both lines are semantically identical:

```lisp
;; ASCII form
(def-interface AuthSystem
  [hash-password (fn [raw: string] -> bytes[64])]
  [verify-token  (fn [token: string] -> bool)])

;; Unicode form
(def-interface AuthSystem
  [hash-password (λ [raw: string] → bytes[64])]
  [verify-token  (λ [token: string] → bool)])
```

---

## 3. The Type System

### 3.1 Primitive Types

| Type | Description | Example values |
|------|-------------|---------------|
| `int` | 64-bit signed integer | `0`, `-1`, `9999` |
| `float` | 64-bit IEEE 754 double | `3.14`, `-0.5` |
| `string` | Immutable UTF-8 byte sequence | `"hello"`, `""` |
| `bool` | Boolean | `true`, `false` |
| `unit` | No-value type (result of pure IO commands) | _(no literal; only appears as a type)_ |

### 3.2 Compound Types

| Type | Description | Example |
|------|-------------|---------|
| `bytes[n]` | Fixed-length byte array of exactly `n` bytes | `bytes[64]` |
| `list[t]` | Homogeneous ordered list | `list[int]`, `list[string]` |
| `map[k,v]` | Key-value dictionary | `map[string,int]` |
| `Result[t,e]` | Success (`t`) or Error (`e`) | `Result[int,string]` |
| `Promise[t]` | Pending async value | `Promise[ImageBytes]` |
| `(a, b)` | 2-tuple (product type) | `(int, string)` |
| `Command` | An IO effect value (see §9) | _(constructed via capability constructors only)_ |

> [!NOTE]
> **v0.3 PR 1 — `(a, b)` is now backed by `TPair`.**  
> Prior to PR 1, the type checker internally approximated `(pair a b)` as `TResult ta tb`. This caused two incorrect behaviours: (1) `llmll build --emit json-ast` emitted `{"kind":"result-type",...}` for pair-typed expressions; (2) `match` exhaustiveness on a pair-typed scrutinee incorrectly cited `Success`/`Error` constructor names.  
> Both issues are fixed. The surface syntax is unchanged — `(pair a b)` and `(a, b)` type annotations work exactly as before.

> `Command` is opaque — it cannot be constructed with a literal or user-defined constructor. It is only produced by the standard command constructors listed in §13.9. You can store a `Command` in a `let` binding and return it from a function, but you cannot inspect its internal fields. In the planned design, `Command` becomes a **typed effect row** (`Eff '[HTTP, FS, ...] r` using the `effectful` library), making a function’s required capabilities visible in its type signature. **Currently (v0.6.0):** `Command` is emitted as plain Haskell `IO ()`. **Capability enforcement is active (v0.4.0, CAP-1):** `wasi.*` function calls require a matching `(import wasi.* (capability ...))` in the module’s statement list — missing imports are compile-time type errors (checked in `inferExpr (EApp ...)`). Propagation is non-transitive: each module must declare its own capability imports. `effectful` typed effect row integration is planned alongside WASM-WASI enforcement (future, not version-pinned).


### 3.3 Algebraic Sum Types (Custom Variants)

User-defined tagged unions (also called ADTs or discriminated unions) are declared with the `type` keyword using `(| ConstructorName PayloadType)` arms:

```lisp
;; A sum type with two constructors
(type GameInput
  (| Start  Word)    ;; carries a Word value
  (| Guess  Letter)) ;; carries a Letter value

;; A sum type with unit constructors (no payload)
(type Color
  (| Red   unit)
  (| Green unit)
  (| Blue  unit))

;; A sum type with multiple fields (use pair encoding)
(type Shape
  (| Circle  float)           ;; radius
  (| Rect    (float, float))) ;; width, height
```

**Construction:** Use the constructor name as a function call:

```lisp
(let [[ev (Start "hangman")]]   ;; ev : GameInput
  ...)

(let [[c (Red unit)]]           ;; c : Color
  ...)
```

**Destruction:** Use `match` (see §3.4). Every `match` on a sum type must be exhaustive.

> **Built-in sum types:** `Result[t,e]` and `DelegationError` (§11.2) follow the same rules and are pre-declared by the compiler. You can `match` on them using their constructor names (`Success`, `Error`, `AgentTimeout`, etc.).

### 3.4 Dependent Types (Logic-Constrained)

Any base type can be constrained by a predicate using `(where [binding: base] predicate)`:

```lisp
(type PositiveInt  (where [x: int]    (> x 0)))
(type Word         (where [s: string] (> (string-length s) 0)))
(type Letter       (where [s: string] (= (string-length s) 1)))
(type GuessCount   (where [n: int]    (>= n 0)))
(type BlockID      (where [s: string] (regex-match "^[a-f0-9]{64}$" s)))
```

Dependent type constraints are **checked at compile time**: the constraint expression is type-checked with the binding variable in scope. The type checker expands type aliases structurally at call sites — passing a `string` literal where a `Word` (defined as `where [s: string] ...`) is expected works correctly. Compile-time SMT verification of constraint *values* is performed by `llmll verify` (Phase 2b).

---

## 4. Logic Structures & Design by Contract

### 4.1 `def-logic` (Pure Functions)

All logic is contained in pure functions declared with `def-logic`. Functions are stateless: they take inputs and return a value. They cannot mutate state or perform IO directly.

```lisp
(def-logic function-name [param1: Type1 param2: Type2]
  (pre  boolean-expression)   ;; optional precondition
  (post boolean-expression)   ;; optional postcondition
  body-expression)             ;; the return value
```

**Return type is always inferred.** Do not write a return type annotation — none exists in the syntax.

**Complete example:**

```lisp
(def-logic withdraw [balance: int amount: PositiveInt]
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  (- balance amount))
```

### 4.2 `letrec` (Recursive Functions with Termination Measures)

Self-recursive functions must be declared with `letrec`, not `def-logic`. The `:decreases` measure is **required** — the compiler uses it to verify termination via `llmll verify`.

```lisp
(letrec function-name [param1: Type1 ...]
  :decreases decrease-expr   ;; required: must strictly decrease each recursive call
  (pre  boolean-expression)  ;; optional
  (post boolean-expression)  ;; optional
  body-expression)
```

**Example:**

```lisp
(letrec countdown [n: int]
  :decreases n
  (if (= n 0) 0 (countdown (- n 1))))
```

- A **simple variable** measure (`:decreases n`) is verified automatically by `llmll verify`.
- A **complex expression** (`:decreases (- n 1)`) emits a `?proof-required(complex-decreases)` hole — non-blocking, but the solver skips that function.
- Using `def-logic` for a self-recursive function emits a **self-recursion warning**. `letrec` is the correct verified form.

`pre`/`post` contracts on `letrec` behave identically to `def-logic` (see §4.3–4.4).

### 4.3 The `result` Keyword in `post` Clauses

Inside a `post` clause, the identifier `result` is **automatically bound to the return value of the function body**. It is a compile error to use `result` anywhere else (including `pre` clauses, `let` bindings, or as a parameter name).

```lisp
(def-logic double [x: int]
  (post (= result (* x 2)))  ;; `result` = the value returned by the body
  (* x 2))

;; ILLEGAL — result in pre:
(def-logic bad [x: int]
  (pre (> result 0))   ;; COMPILE ERROR: result not in scope here
  x)

;; ILLEGAL — result as parameter name:
(def-logic also-bad [result: int]   ;; COMPILE ERROR: reserved keyword
  result)
```

### 4.4 Contract Semantics

| Context | What happens on violation |
|---------|--------------------------|
| `pre` violation | `AssertionError` raised before body executes. The caller is buggy. |
| `post` violation | `AssertionError` raised before result is returned. The implementation is buggy. |
| Both satisfied | Result is returned normally. |

#### 4.4.1 Verification Levels

Every `pre` and `post` clause carries a **verification level** that describes how the contract has been checked:

| Level | Meaning | When assigned |
|-------|---------|---------------|
| `proven` | Formally verified via SMT (Z3) or interactive proof (Lean). The contract holds for all well-typed inputs. | `llmll verify` reports SAFE |
| `tested` | Not formally proven, but not falsified by property-based testing. Trust is proportional to sample coverage. | `llmll test` passes; `llmll verify` skips or emits `?proof-required` |
| `asserted` | Enforced as a runtime assertion only. No static or dynamic evidence of correctness beyond the assertion itself. | Default for any contract not yet run through `verify` or `test` |

The verification level is recorded per-contract, per-function in the module's exported metadata (see §8 — `ModuleEnv` extensions).

#### 4.4.2 Runtime Assertion Modes

The `--contracts` flag controls which runtime assertions are compiled into the output:

| Mode | Assertions included | Default for |
|------|---------------------|-------------|
| `--contracts=full` | All contracts (proven + tested + asserted) | `llmll test` |
| `--contracts=unproven` | Only `tested` and `asserted` contracts; `proven` contracts are stripped | `llmll build` (when a cached verify result exists) |
| `--contracts=none` | No runtime assertions | Opt-in only; requires explicit flag |

Without a prior `llmll verify` pass, `llmll build` defaults to `--contracts=full`. The `--contracts` flag applies to Haskell code generation regardless of `--emit-only`.

> [!IMPORTANT]
> **Invariant:** Stripping a `proven` contract must not change observable behavior for any well-typed program. This invariant depends on `.fq` emitter faithfulness — see compiler team brief for verification obligations.

#### 4.4.3 Trust-Level Propagation

When module B imports module A and calls a function whose contract is `tested` or `asserted`, the compiler emits a **downstream trust warning**:

```
⚠ Function foo.bar.withdraw has an unproven postcondition.
  Your module inherits this trust gap.
```

The downstream module can acknowledge the gap explicitly:

```lisp
(trust foo.bar.withdraw :level asserted)
(trust auth.verify-token :level tested)
```

This silences the warning and makes the trust decision visible in source. An agent auditing module B can enumerate all `(trust ...)` declarations to see which unproven contracts it depends on.

`(trust ...)` declarations follow `import` semantics — per-function, multiple declarations per module, must appear before any `def-logic`. Duplicate declarations for the same function are idempotent (not an error).

When the sidecar `.verified.json` file is missing for an imported module, all contracts default to `asserted`.

#### 4.4.4 Trust Report (`--trust-report`)

`llmll verify --trust-report` prints a per-function trust summary after verification. For each function with contracts, the report shows:

- The function’s own verification level (proven/tested/asserted) for pre and post clauses
- Which cross-module functions it calls and their verification levels
- **Epistemic drift warnings:** when a `proven` conclusion depends transitively on an `asserted` or `tested` assumption upstream

```bash
stack exec llmll -- verify program.llmll --trust-report
# Trust Report
# ────────────────────────────────────────────────────────────
#   withdraw:
#     pre: proven (liquid-fixpoint)  |  post: proven (liquid-fixpoint)
#     ↳ calls auth.verify-token (pre: —, post: asserted)
#     ⚠ withdraw is proven, but depends on auth.verify-token which is asserted
```

Use `--trust-report --json` for machine-readable JSON output suitable for CI or downstream tooling.

The report walks the full module cache (entry-point module plus all imported modules) and computes the transitive trust closure. An agent auditing a module can use the trust report to identify all points where the formal verification chain breaks down.

### 4.5 Suppression Governance (`weakness-ok`) — v0.6.0

When a function is intentionally left without contracts (e.g., pure rendering logic, FFI wrappers, or configuration constants), the `weakness-ok` declaration acknowledges the gap and prevents the spec coverage gate from flagging it as unspecified:

```lisp
(weakness-ok render-board "pure string rendering — no meaningful postcondition")
(weakness-ok cache-evict "eviction policy is unspecified by design")
```

**Syntax:** `(weakness-ok fn-name "reason")`. Both arguments are required — the parser rejects bare `weakness-ok` without a reason string.

**Governance rules:**

| Rule | Code | Behavior |
|------|------|----------|
| WO-1 | `W601` | `weakness-ok` target doesn't match any function in the module → warning |
| WO-2 | `W602` | Function has contracts AND `weakness-ok` → contracts take priority; `weakness-ok` is redundant (warning) |
| D10 | `W603` | More than 50% of functions are suppressed → warning (bulk suppression guardrail) |

`weakness-ok` functions count toward `effective_coverage` (see §5.4) but are visually distinguished with a `⊘` marker in `--spec-coverage` output.

JSON-AST equivalent: `{"kind": "weakness-ok", "name": "render-board", "reason": "pure string rendering"}`.

### 4.6 Clause-Level Provenance (`:source`) — v0.6.0

In LLMLL's target domains (financial compliance, protocol implementation, cryptographic standards), auditors require per-clause traceability to the originating standard. The `:source` annotation provides free-form provenance metadata on `pre` and `post` clauses:

```lisp
(def-logic transfer [from: string to: string amount: int]
  (pre (>= amount 0)
    :source "ERC-20 §transfer — amount must be non-negative")
  (post (= (total-supply result) (total-supply state))
    :source "ERC-20 §transfer — conservation invariant")
  ?transfer-impl)
```

**Semantics:** Pure metadata — no effect on type checking, verification, or codegen. The `:source` string is stored per-clause (`contractPreSource` / `contractPostSource`) and threaded through `--trust-report` output and `.verified.json` sidecars.

**Backward compatible:** Omitting `:source` yields `Nothing` — all pre-v0.6.0 programs parse and compile unchanged.

**Multiple pre clauses:** When multiple `(pre ...)` clauses are combined with `and`, the `:source` annotation is dropped (ambiguous provenance across combined clauses).

JSON-AST fields: `"pre_source"` / `"post_source"` (optional string).

> **Design note (v0.6):** `:source` uses free-form text. Structured references (`{standard, section, clause}`) are planned for v0.7.

---

## 5. Native Testing & Verification

### 5.1 Property-Based Testing (`check`)

`check` blocks declare universal properties. The test runner generates randomized edge-case inputs and attempts to falsify the property. A `check` block must contain exactly one `(for-all ...)` — bare boolean expressions are not valid.

```lisp
(check "Addition is commutative"
  (for-all [a: int b: int]
    (= (+ a b) (+ b a))))

(check "Withdraw never produces negative balance"
  (for-all [b: int a: PositiveInt]
    (if (>= b a)
        (>= (withdraw b a) 0)
        true)))
```

The test runner generates at least 100 random samples per `check`. For primitive types it targets edge cases: `0`, `-1`, `MAX_INT`, `MIN_INT`, `""`, `[]`.

### 5.2 Generators for Dependent Types (`gen`)

When a `for-all` binds a variable of a dependent type (e.g., `Letter`), the test engine must generate values that satisfy the type's `where` predicate. The default strategy is **rejection sampling**: generate a value of the base type, check the predicate, discard and retry if it fails. This terminates when 100 valid samples are accumulated, or reports a generation failure after 10,000 attempts.

For types where rejection sampling is inefficient (e.g., a 64-hex-digit string), register a custom **generator** with `gen`:

```lisp
;; Custom generator: produce random 1-character ASCII strings
(gen Letter
  (string-char-at "abcdefghijklmnopqrstuvwxyz"
                  (mod (random-int) 26)))

;; Custom generator: produce valid block IDs
(gen BlockID
  (hex-encode (random-bytes 32)))
```

A `gen` declaration applies to all `for-all` blocks in the same module that use the named type. If no `gen` is declared for a dependent type, rejection sampling is used automatically.

### 5.3 Verification (Phase 2b — Shipped)

**`llmll verify`** is the Phase 2b compile-time verification command. It:

1. Walks the typed AST and emits a `.fq` constraint file for `liquid-fixpoint`.
2. Runs `fixpoint` (+ Z3) as a standalone binary — no GHC plugin required.
3. Reports SAFE or constraint-violation diagnostics with RFC 6901 JSON Pointers back to the original `pre`/`post` clause.

**Coverage:** Quantifier-free linear integer arithmetic (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`). Non-linear predicates and complex `letrec` termination measures are skipped (see `?proof-required` in §6).

**Qualifier strategy:** Qualifiers are auto-synthesized from `pre`/`post` predicates and seeded with the built-in set `{True, GEZ, GTZ, EqZ, Eq, GE, GT}`. No manual qualifier declarations are needed.

```bash
stack exec llmll -- verify ../examples/withdraw.llmll
# ✅ ../examples/withdraw.llmll — SAFE (liquid-fixpoint)
```

> **v0.3 — Interactive Proof Holes:** `?proof-required :inductive` and `:unknown` holes are routed to Leanstral (Lean 4 proof agent) via MCP. Verified proof certificates are stored and re-checked on subsequent builds.

#### 5.3.1 Spec Weakness Detection (v0.3.5)

`llmll verify --weakness-check` is an advisory pass that runs **after** a SAFE verification result. For each contracted function, the compiler constructs trivial candidate bodies (identity, constant-zero, empty-string, `true`, empty-list) and checks whether they also satisfy the contract. If any trivial body passes, a `spec-weakness` diagnostic is emitted:

```
⚠ Spec weakness detected for `sort-list`:
  Your contract: (post (= (list-length result) (list-length input)))
  Trivial valid implementation: (def-logic sort-list [input: list[int]] input)
  Consider strengthening the postcondition.
```

This diagnostic is **non-blocking**: the function remains SAFE. It is an *advisory* signal that the specification may not distinguish correct implementations from trivial ones. The structured JSON diagnostic includes `trivial_implementation` and `suggested_postcondition` fields.

Weakness checking does not modify `FixpointEmit.hs` — it constructs synthetic single-statement programs and calls the existing `emitFixpoint` pipeline.

#### 5.3.2 Spec Coverage Gate (v0.6.0)

`llmll verify --spec-coverage` classifies every function in a module and computes the **effective specification coverage**:

```
effective_coverage = (contracted + suppressed) / total_functions
```

| Classification | Meaning |
|---|---|
| **Contracted** | Has at least one `pre` or `post` clause |
| **Suppressed** | Has a `(weakness-ok name "reason")` declaration and no contracts |
| **Unspecified** | No contract, no suppression |

Example output:

```bash
stack exec llmll -- verify program.llmll --spec-coverage
# Spec Coverage Report
# ────────────────────────────────────────────
#   Functions with contracts:     4 / 7   (57%)
#     Proven:                     2
#     Tested:                     1
#     Asserted:                   1
#   Intentional Underspecification:
#     ⊘ cache-evict — "eviction policy is unspecified by design"
#   Unspecified:                  2
#     sort-list, validate-input
# ────────────────────────────────────────────
#   Effective coverage: 71% (5/7)
```

Use `--spec-coverage --json` for machine-readable output (fields: `entries`, `summary`, `warnings`).

**Division guard (SC-PO-1):** A module with 0 functions has `effective_coverage = 100%`.

**Governance guardrails:** See §4.5 for WO-1, WO-2, and D10 warning rules.

#### 5.3.3 Verification Scope (v0.6.0)

The following table precisely defines what `llmll verify` can prove, what it tracks but cannot prove, and what is designed but not yet operational:

| Fragment | Status | Prover | What it covers |
|----------|--------|--------|----------------|
| **QF-LIA** (quantifier-free linear integer arithmetic) | **Shipped** (v0.2+) | Z3 via liquid-fixpoint | `+`, `-`, `=`, `<`, `<=`, `>=`, `>` over `int`. Handles numeric bounds, conservation invariants, length preservation. ~80% of practical contracts. |
| **Termination** (`:decreases` measures) | **Shipped** (v0.2+) | liquid-fixpoint | Simple variable measures (`:decreases n`) are verified automatically. Complex measures emit `?proof-required(complex-decreases)`. |
| **Property-based testing** | **Shipped** (v0.1.1+) | QuickCheck | `check`/`for-all` blocks generate randomized inputs and attempt to falsify properties. Contracts verified this way are marked `tested`. |
| **Inductive properties** | **Designed, not shipped** | Lean 4 via Leanstral MCP | Translation infrastructure exists (`LeanTranslate.hs`, `MCPClient.hs`, `ProofCache.hs`). Currently runs in **mock mode only** (`--leanstral-mock`). Real proof integration is blocked on `lean-lsp-mcp` availability. |

**What is NOT silently dropped:** Contracts outside the QF-LIA fragment are not ignored. They are:
1. Enforced as **runtime assertions** (unless stripped via `--contracts=none`)
2. Tracked as **`asserted`** verification level
3. Flagged with `?proof-required` holes when the predicate is detected as non-linear or requiring induction
4. Propagated through the **trust report** — downstream `proven` conclusions that depend on `asserted` assumptions are flagged as epistemic drift

> [!IMPORTANT]
> **Leanstral is not a shipped verification path.** The one-pager, README, and this spec distinguish between shipped SMT verification (Z3/liquid-fixpoint) and the designed-but-mock Lean 4 path. No LLMLL claim of "proven" correctness rests on Leanstral. When `lean-lsp-mcp` becomes available, Leanstral integration will be scheduled; until then, inductive properties are tracked as `asserted` with explicit `?proof-required` holes.

---

## 6. Hole-Driven Development (`?`)

When an LLM encounters ambiguity or an unimplemented TODO, it **must** use a Hole. Never guess or hallucinate an implementation — emit a hole and document what is needed.

A program with holes can be **parsed, type-checked, and analyzed** but **not executed** until all holes are resolved. The compiler reports the type of every hole so the resolving agent knows exactly what to produce.

| Hole form | When to use |
|-----------|-------------|
| `?name` | Named placeholder. The resolving agent must provide an expression of the inferred type. |
| `?choose(opt1, opt2, ...)` | Ask the human or Lead AI to pick one of the named options. |
| `?request-cap(wasi.net.connect)` | Request a capability grant from the human operator. |
| `?scaffold(template ...)` | Cold-start a module from a `llmll-hub` skeleton (see §6.1). |
| `?delegate @agent "description" -> Type` | Delegate implementation to a named agent (see §11.2). |
| `?delegate-async @agent "description" -> Promise[Type]` | Non-blocking delegation (see §11.2). |
| `?proof-required` | A contract predicate that is outside the decidable QF arithmetic fragment (v0.2+). The compiler assigns a complexity hint: `:simple` (liquid-fixpoint track), `:inductive` (Leanstral track), or `:unknown`. Non-blocking in v0.2; resolved by Leanstral (Lean 4) in v0.3. |

**Usage in expressions:** A hole can appear anywhere an expression is expected:

```lisp
(def-logic display-word [word: Word guessed: list[Letter]]
  (post (= (string-length result) (string-length word)))
  ?display_word_impl)            ;; hole: compiler knows return type is string
```

### 6.1 Scaffold Holes (`?scaffold`)

A `?scaffold` hole solves the **cold-start problem**: before a Lead AI can write a `(def-interface ...)`, it needs a structurally valid starting point. Instead of generating a module from a blank slate (maximizing hallucination risk), the LLM requests a known-good skeleton:

```lisp
(?scaffold web-api-server
  :language llmll
  :modules  [routing auth persistence]
  :style    rest
  :version  "0.1")
```

`?scaffold` is the only hole type that **resolves at parse time** — the compiler fetches and expands the skeleton before semantic analysis begins. The expanded skeleton has all `def-interface` boundaries pre-typed and implementation details pre-filled as named `?` holes.

---

## 7. FFI & Capability System

`llmll` programs run in a capability-gated sandbox. All interactions with the outside world require `import` statements that grant specific **capabilities**. The sandbox implementation is Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` in v0.1.2–v0.6.0, with WASM-WASI planned as a future deployment target.

> [!IMPORTANT]
> **v0.4.0 (CAP-1):** Capability enforcement is now active at compile time. When a `wasi.*` function is called, the type checker verifies that a matching `SImport` with a `Capability` is present in the module’s statements. Missing imports produce a structured type error: `"wasi.io.stdout requires (import wasi.io (capability ...))"`. **Propagation is non-transitive (module-local):** Module B must re-declare `(import wasi.io ...)` even if it only calls `wasi.*` via a function imported from Module A. This matches the principle of least authority.

```lisp
(module cloud-storage
  (import wasi.filesystem (capability read-write "/data"))
  (import wasi.http       (capability post "https://api.logging.com")))
```

Capabilities can carry the `:deterministic` flag (see §10a) to opt into event-log capture for replay:

```lisp
(import wasi.clock  (capability monotonic-read :deterministic true))
(import wasi.random (capability get-bytes      :deterministic true))
```

**External Bridge (FFI):** To use existing Haskell packages or C libraries, define a Verified Wrapper using the `haskell.*` or `c.*` prefix:

```lisp
(import haskell.aeson (interface [
  [json-decode (fn [s: string] -> Result[TodoList, string])]
  [json-encode (fn [td: TodoList] -> string)]
]))
```

In LLMLL, FFI imports are resolved through a **two-tier lookup**. The compiler checks each tier in order:

| Tier | Prefix | Mechanism | Stub generated? |
|------|--------|-----------|----------------|
| **1 — Hackage** | `haskell.*` | Regular GHC `import`; package added to `package.yaml`. No stub generated. | No |
| **2 — C libraries** | `c.*` | GHC `foreign import ccall`; compiler generates `src/FFI/<lib>.hs` with typed stub. | Yes |

> The `rust.*` namespace is retired. The Haskell backend uses Tier 1 Hackage imports (e.g. `haskell.aeson`, `haskell.warp`) as direct replacements with no stub required.

**Tier 1 example — zero developer action:**

```lisp
;; Resolves to: import Data.Aeson — no stub file generated
(import haskell.aeson (interface [
  [json-decode (fn [s: string] -> Result[TodoList, string])]
  [json-encode (fn [td: TodoList] -> string)]
]))
```

**Tier 2 example — C FFI stub generated:**

```lisp
;; Compiler generates src/FFI/Libsodium.hs with foreign import ccall stubs
(import c.libsodium (interface [
  [crypto-sign (fn [msg: bytes[64] key: bytes[32]] -> bytes[96])]
]))
```

> [!CAUTION]
> **FFI stubs are NOT `?delegate` holes.**
> Tier 2 C stubs (`src/FFI/*.hs`) are resolved **by the developer writing Haskell FFI code** against the C library.
> `?delegate` holes are resolved **by the Lead-AI/Human reviewer writing LLMLL code** inside the `.llmll` source file. A `?delegate` must NEVER be manually implemented in generated code — that bypasses the verifier entirely.

> [!WARNING]
> **Pitfall: Declaring a C interface you don't fully implement.**
> If you declare `(import c.mylib (interface [...]))` but leave the generated `src/FFI/Mylib.hs` stub unimplemented, **the code will compile but fail at link time or panic at runtime**. Every `(import c.* ...)` you write must have a fully implemented stub before running the service.



---

## 8. Module System

The module system provides **multi-file compilation**, namespace isolation, export control, and the `llmll-hub` package registry.

### 8.1 Module Name and File Path

A `(module Name ...)` declaration is accepted at the top of any file. The module name is a single `IDENT` used for documentation and tooling display only — the **canonical module path** is derived from the file's location relative to the source root. This prevents mismatches between declared names and import paths.

```lisp
(module hangman
  (import wasi.io (capability stdin  :deterministic true))
  (import wasi.io (capability stdout :deterministic false))

  ;; Module body: type declarations, def-logic, def-interface, check, gen
  (type Word (where [s: string] (> (string-length s) 0)))

  (def-logic game-won? [state: GameState]
    (all-guessed? (state-word state) (state-guessed state))))
```

### 8.2 File-System Module Resolution

`(import foo.bar.baz ...)` is resolved using a configurable **module root list** (default: directory of the entry-point source file, then `~/.llmll/modules/`):

```
foo/bar/baz.llmll        (S-expression — tried first)
foo/bar/baz.ast.json     (JSON-AST      — tried second)
~/.llmll/modules/foo/bar/baz.llmll   (hub cache — tried last)
```

If both `.llmll` and `.ast.json` exist for the same path, `.llmll` takes precedence.

### 8.3 Import Ordering Rule

All `import`, `open`, and `export` declarations must appear **before** any `def-logic`, `type`, or `def-interface` statements — both inside a `(module ...)` block and at file scope. The parser reads imports in a first pass; declarations placed after logic definitions are silently ignored.

### 8.4 Cycle Detection

Circular imports are a **compile error**. The compiler performs a DFS-based cycle check before loading any module. The diagnostic names the full cycle:

```json
{
  "kind":    "circular-import",
  "cycle":   ["foo.bar", "foo.baz", "foo.bar"],
  "message": "Circular import detected: foo.bar → foo.baz → foo.bar"
}
```

### 8.5 Namespace Isolation — Prefixed Access (Default)

All names exported by an imported module are accessible via the fully qualified path. No extra declaration is needed:

```lisp
(module app.main
  (import app.auth))

;; Call the exported function with its qualified name:
(app.auth.hash-password raw-str)
```

> [!NOTE]
> **Phase 2a codegen:** All imported modules are merged into a single flat `Lib.hs`.
> Qualified references (`module.fn`) are accepted by the type-checker and resolver,
> but codegen flattens them — `world.make-world` becomes `world_make_world` in Haskell,
> which does not exist. **Call sites must use bare function names.** The `(import world)`
> statement is still required to trigger module loading and merging. Per-module Haskell
> output (so qualified names survive to GHC) is planned for Phase 2b.

This reuses the existing `QualIdent` / dot-notation infrastructure — no new runtime concept.

### 8.6 `open` — Selective Unprefixing

`(open path)` pulls a module's exports into the current scope without a prefix. An optional name list restricts which names are unprefixed:

```lisp
(open app.auth)                  ;; all exports at bare names
(open app.auth (hash-password))  ;; only hash-password unprefixed
```

`open` is a compile-time name-alias injection — it has no effect on codegen output.

> **Collision policy:** If two `(open ...)` declarations export the same bare name, the second `open` wins (last wins). The compiler emits a `WARNING` diagnostic. An agent that needs both must use prefixed access for at least one.

### 8.7 `export` — Visibility Control

```lisp
(export hash-password verify-token)   ;; only these two names visible externally
```

If no `export` declaration is present, **all** top-level `def-logic`, `type`, `def-interface`, and `gen` declarations are exported (open default). `check` and `def-invariant` blocks are **never exported**.

The `export` declaration must appear before the first `def-logic`.

### 8.8 Cross-Module `def-interface` Enforcement

When module B imports module A and calls a function declared under A's `def-interface`, the compiler:

1. Looks up the interface shape in A's exported `ModuleEnv`.
2. Checks structural compatibility for every method.
3. Expands type aliases from A's scope before comparison.
4. Emits a compile error if any method is missing or type-incompatible:

```json
{
  "kind":      "interface-mismatch",
  "module":    "app.auth",
  "interface": "AuthSystem",
  "method":    "hash-password",
  "expected":  "(fn [string] -> bytes[64])",
  "got":       "(fn [string] -> string)",
  "pointer":   "/statements/2/body"
}
```

### 8.9 `llmll-hub` Registry

The `hub.` import prefix resolves modules from the local `llmll-hub` cache (`~/.llmll/modules/`). Fetch packages with:

```bash
llmll hub fetch llmll-crypto@0.1.0
```

Import syntax:

```lisp
(import hub.llmll-crypto.hash.bcrypt (interface [
  [bcrypt-hash (fn [raw: string] -> bytes[64])]
]))
```

The `hub.` prefix prevents local files from accidentally shadowing registry packages. Publishing, semantic versioning beyond `major.minor.patch`, and a web registry API are deferred to v0.3.

Modules declared in `llmll-hub` include verified proof metadata and are importable by name. Third-party modules must be explicitly wrapped (§7). _(Full hub write-path including publishing is introduced in v0.3.)_

---

## 9. IO & Side Effects: The Command/Response Model

`llmll` uses a strictly functional approach to IO. **Logic functions never perform side effects.** Instead, they return `Command` values that *describe* the intended effect. The runtime executes these commands and feeds the result back as the next `Input`.

### 9.1 The Core Pattern

Every logic function that interacts with the world follows this signature:

```
(State, Input) -> (NewState, Command)
```

The AI's logic is pure. The runtime is the only actor that touches the OS.

```lisp
(def-logic handle-request [state: AppState request: HttpRequest]
  (if (is-valid? request)
      (pair (update-state state) (wasi.http.response 200 "OK"))
      (pair state                (wasi.http.response 400 "Bad Request"))))
```

### 9.2 Constructing Commands

Commands are constructed by calling **capability-namespaced constructor functions** (see §13.9 for the full list). These are qualified identifiers — they use dot notation and require the matching `import` declaration.

```lisp
;; Must have: (import wasi.io (capability stdout ...))
(wasi.io.stdout "Game initialized.\n")   ;; : Command

;; Must have: (import wasi.http (capability serve 8080))
(wasi.http.response 200 "OK")           ;; : Command

;; Must have: (import wasi.fs (capability write "/data"))
(wasi.fs.write "/data/log.txt" content) ;; : Command
```

Commands can be stored in `let` bindings and passed as values. They are opaque — you cannot pattern-match on a `Command` or inspect its fields.

### 9.3 Sequencing Multiple Commands (`seq-commands`)

If a single logic step must emit multiple side effects, use `seq-commands` to compose them into a single `Command`:

```lisp
(def-logic log-and-respond [state: AppState req: HttpRequest]
  (let [(log-cmd  (wasi.io.stderr "Request received"))
        (resp-cmd (wasi.http.response 200 "OK"))]
    (pair state (seq-commands log-cmd resp-cmd))))
```

`seq-commands` executes its arguments in order (left then right). It can be nested for three or more commands:

```lisp
(seq-commands cmd1 (seq-commands cmd2 cmd3))
```

### 9.4 Runtime Execution Loop

The LLMLL host runtime processes each `Command` as follows:

1. **Verify** permissions against the module's declared `capability` list. A command without a matching capability raises a `CapabilityError` and halts.
2. **Intercept** sensitive commands (e.g., `wasi.fs.delete`) for human/Lead-AI review if the module is running in guarded mode.
3. **Execute** the physical IO via the OS.
4. **Feed** the result (`Success` or `Error`) back as the next `Input` to the logic.

### 9.5 Entry Point Declaration (`def-main`)

`def-main` declares the program's runtime harness — how the compiled executable starts, reads input, and terminates. Without a `def-main`, the compiler generates a **library only** (no `Main.hs`).

#### Syntax

```lisp
(def-main
  :mode    (console | cli | http PORT)   ;; required — selects the harness template
  :init    init-expr                      ;; returns (State, Command) pair
  :step    step-fn                        ;; (State, String) -> (State, Command)
  :done?   done-pred                      ;; State -> Bool (optional; console only)
  :on-done on-done-fn)                    ;; State -> Command (optional)
```

#### Modes

| Mode | Harness behaviour |
|------|-------------------|
| `console` | Interactive loop: `:init` creates state + welcome message, then loops on stdin calling `:step` until `:done?` returns `true`. When `:on-done` is also declared, it is called with the final state when `:done?` becomes `true` — before the loop exits. |
| `cli` | Single-shot: reads OS args, calls `:step` once, prints result. |
| `http PORT` | HTTP server on `PORT`: `:init` creates initial state, each request calls `:step`. |

#### Key semantics

- `:init` must return a `(State, Command)` pair. The `Command` is executed (e.g., print welcome message), and the `State` is passed to the first `:step` call.
- `:step` receives the current state and one line of input (for `console`) or the OS args (for `cli`). It must return a `(NewState, Command)` pair.
- `:done?` (optional, console only) receives the new state after each step. If it returns `true`, the loop exits.
- The `Command` returned by `:step` is executed directly as an IO action (it is **not** printed or shown).

#### Complete example

```lisp
(def-main
  :mode console
  :init (start-game "hangman")
  :step game-loop
  :done? is-game-over?)
```

#### The `:on-done` hook — avoiding double-render

> [!IMPORTANT]
> **`:on-done` is the canonical place to print end-of-game messages.**

When `:step` prints a board *and* an end-game message in the same `Command`, the
final board will appear **twice** on game-over:

1. `:step` executes and prints `"You won!\n"`.
2. The harness checks `:done?` — it is now `true`.
3. The loop exits (or calls `:on-done`).

Because `:step` already ran its `Command` before `:done?` was checked, the output
from step 1 is always visible. If `:step` prints a win/loss message on the **same
turn it makes the game over**, that message will print once — but any
`render-state` call embedded in the *next* iteration's check can double the board.

**The fix:** move all terminal output for the final state into `:on-done`.

```lisp
;; Anti-pattern — game-loop prints the end message as part of its Command.
;; The harness then calls done? on the same state and the board may render
;; a second time on the next loop iteration.
(def-main
  :mode console
  :init (start-game "hangman")
  :step game-loop           ;; game-loop prints board AND "You won!" on win
  :done? is-game-over?)

;; Canonical pattern — game-loop prints the board only.
;; show-result prints the final message exactly once, after the loop exits.
(def-main
  :mode console
  :init   (start-game "hangman")
  :step   game-loop         ;; only prints the board on every turn
  :done?  is-game-over?
  :on-done show-result)     ;; prints "You won!" or "Game over!" exactly once
```

`show-result` has signature `State -> Command`. It is called with the final state
immediately before the loop exits. Output produced by `:on-done` appears **after**
the last `:step` output and **exactly once**, regardless of how many times
`:done?` is checked.

In JSON-AST:

```json
{
  "kind": "def-main",
  "mode": "console",
  "init": { "kind": "app", "fn": "start-game", "args": [{"kind": "lit-string", "value": "hangman"}] },
  "step": { "kind": "var", "name": "game-loop" },
  "done?": { "kind": "var", "name": "is-game-over?" }
}
```

### 9.6 `do`-notation State Threading (v0.3)

For complex sequences of actions that thread a state and accumulate commands, LLMLL provides a monadic `do`-notation block as a cleaner alternative to deeply nested `let` and `seq-commands`.

```lisp
(def-logic process-turn [state: GameState]
  (do
    [s1 <- (action1 state)]
    [s2 <- (action2 s1)]
    (action3 s2)))
```

#### Semantics

- **State threading enforced:** Every step inside a `do`-block must evaluate to exactly `(S, Command)`. The type `S` must be strictly identical across all steps in the block.
- **Named vs. Anonymous steps:** A named step `[s1 <- (expr)]` binds the state component of `expr`'s result to `s1` for subsequent steps. An anonymous step `(expr)` simply discards the state component and threads exactly the identical state. 
- **Compilation:** The `do` block is compiled directly into a pure `let` chain. No Haskell `do` or monads are emitted, ensuring soundness in `def-logic` pure contexts. Each step's `(State, Command)` pair is destructured via `let`; the final result is `(lastState, lastCommand)`. Intermediate commands from non-final steps are bound but discarded — the caller is responsible for sequencing via `seq-commands` if earlier commands must be executed.

> [!WARNING]
> Using an anonymous step `(expr)` when `expr` returns a new state will result in **state-loss**. The bound state from prior steps is retained, but the updated state from `(expr)` is discarded. Always use named steps `[s <- (expr)]` to thread modified states properly.

> [!NOTE]
> **JSON-AST schema:** `do`-blocks use a unified `"do-step"` kind with an optional `"name"` field. The old `"bind-step"` / `"expr-step"` separation is rejected. See `getting-started.md §4.13` for migration details.

---

## 10. Compilation & Execution Pipeline

The pipeline accepts two source formats: S-expressions (`.llmll`) and JSON-AST (`.ast.json`).

1. **AI Implementation:** LLM generates `.llmll` S-expressions *or* `.ast.json` (preferred for AI agents — schema-constrained, structurally valid by construction).
2. **Parse & Semantic Check:** Compiler parses the source, verifies types and immutability, catalogs all `?holes`. Reports structured JSON diagnostics with RFC 6901 JSON Pointers to offending AST nodes. `llmll holes --json` lists all unresolved holes.
3. **Human/Lead-AI Review:** Holes and sensitive `Command` effects (e.g., `wasi.fs.delete`) are resolved/approved via Chat/CLI.
4. **Transpilation:** Validated `.llmll` is converted to **Haskell** (`.hs` + `package.yaml`). Generated modules are compiled with `{-# LANGUAGE Safe #-}`, preventing any IO outside the declared capability model.
5. **Binary Generation:** `ghc` compiles the generated Haskell to a native binary.
6. **Contract & Property Testing:** The test runner executes `pre`/`post` runtime assertions and `check`/`for-all` QuickCheck blocks against the running binary. Failures are reported as JSON diagnostics.
7. **Sandboxed Execution:** The binary runs inside a Docker container with `seccomp-bpf` syscall filtering and filesystem/network policies derived from the module’s declared capabilities (v0.1.2–v0.6.0). WASM-WASI is planned as a future replacement. **Capability enforcement is active (v0.4.0, CAP-1):** `wasi.*` function calls require a matching `(import wasi.* (capability ...))` in the module’s statements — missing imports are compile-time type errors.
8. **Event-Log Replay:** The runtime records a sequenced Event Log of `(Input, CommandResult, captures)` triples (see §10a). Replay is bitwise deterministic for all modules that use `:deterministic true` capability flags on clock and PRNG imports.

> **v0.2 (shipped):** Step 2 includes compile-time contract verification via `llmll verify` (decoupled liquid-fixpoint backend). Contracts outside the decidable QF arithmetic fragment are emitted as `?proof-required` holes.
> **v0.3:** `?proof-required :inductive` holes are resolved by Leanstral (Lean 4 proof agent) via MCP. Verified proof certificates are stored and re-checked on subsequent builds without re-calling Leanstral.
> **v0.4.0:** CAP-1 capability enforcement is active — `wasi.*` calls require matching capability imports. Lead Agent ships as `llmll-orchestra --mode plan|lead|auto`. Docker sandbox remains; WASM-WASI is a planned future deployment target.
> **v0.5.0:** U-Full sound unification completes Algorithm W. Occurs check, let-generalization, and TVar-TVar wildcard closure close the last known unsoundness in the type checker.

---

## 10a. Event Log Specification

Correct replay is the foundation of fault tolerance, audit trails, and (in v0.2) SMT proof validation over execution traces.

### Sources of Non-Determinism

| Source | Problem | Runtime Fix |
|--------|---------|-------------|
| **IEEE 754 floats** | NaN canonicalization differs across host platforms | Reject non-canonical floats at the sandbox boundary (GHC NaN rules in v0.1.2–v0.6.0; `wasm-determinism` extension with WASM target) |
| **Monotonic clock** | Wall-clock calls diverge across replay runs | Virtualize via `:deterministic true`; log return value |
| **PRNG** | Non-seeded random generation diverges on replay | Log seed + call sequence; replay re-seeds from log |

### The `:deterministic` Capability Flag

```lisp
(import wasi.clock  (capability monotonic-read :deterministic true))
(import wasi.random (capability get-bytes      :deterministic true))
```

When `:deterministic true` is set, the runtime **captures the return value** of every call and appends it to the Event Log. On replay, these calls **read from the log** instead of invoking the real system call.

### Event Log Format

```lisp
(event
  :seq      42
  :input    (http.request GET "/checkout")
  :result   (http.response 200 "OK")
  :captures [(wasi.clock.monotonic 1741823200000)
             (wasi.random.bytes #x4f2a...)])
```

Replay feeds each `:input` to the logic in order. `:result` and `:captures` are injected directly, bypassing real system calls.

### Replayability Status

| Condition | Compiler Status |
|-----------|----------------|
| All non-deterministic capabilities use `:deterministic true` | ✅ **replayable** |
| Any non-deterministic capability without `:deterministic true` | ⚠️ **best-effort replay** |

---

## 11. Multi-Agent Concurrency (The Swarm Model)

`llmll` is designed to be written concurrently by a swarm of specialized AI agents. The language enforces a strict semantic division of labor to prevent hallucination propagation and merge conflicts.

### 11.1 Interface-First Compilation (The Treaty)

Before concurrent development begins, a Lead AI (or Human) defines the boundaries using `def-interface`. This establishes a contract all agents must adhere to.

```lisp
(def-interface AuthSystem
  [hash-password (fn [raw: string] -> bytes[64])]
  [verify-token  (fn [token: string] -> bool)])
```

In `def-interface`, parameter names in `fn-type` are **optional and documentation-only**. Both of the following are equivalent and valid:

```lisp
;; Named parameters (preferred: documents intent clearly)
[hash-password (fn [raw: string] -> bytes[64])]

;; Anonymous parameters (also valid)
[hash-password (fn [string] -> bytes[64])]
```

Once the interface is compiled, Agent A can implement the internal logic while Agent B concurrently writes the API that consumes it. The compiler guarantees structural compatibility.

### 11.2 Hole Delegation

A `?hole` does not always require human intervention. An AI can delegate a sub-task to a specialized agent while continuing to build the rest of its module.

#### Built-in Failure Type

`DelegationError` is a pre-declared sum type. All delegations may produce it:

```lisp
(type DelegationError
  (| AgentTimeout    unit)  ;; Agent did not respond within the runtime deadline
  (| AgentCrash      unit)  ;; Agent returned an error signal
  (| TypeMismatch    unit)  ;; Agent returned a result incompatible with the declared type
  (| AgentNotFound   unit)) ;; Named agent is unavailable
```

#### Blocking Delegation

`?delegate` requires an explicit `-> ReturnType` annotation. An optional `(on-failure ...)` clause provides a fallback:

```lisp
(def-logic login-route [req: HttpRequest]
  (let [[password  (get req :pass)]
        [hashed-pw (?delegate @crypto-agent
                     "Implement secure PBKDF2 hashing"
                     -> bytes[64]
                     (on-failure (Result.Error DelegationError)))]]
    (db.insert user hashed-pw)))
```

Without `(on-failure ...)`, an unresolved delegation becomes a `?delegate-pending` hole — analyzable but not executable:

```lisp
hashed-pw (?delegate @crypto-agent "Implement PBKDF2 hashing" -> bytes[64])
;; Compiler: ?delegate-pending [type: bytes[64]] [agent: @crypto-agent]
```

#### Async Delegation

`?delegate-async` returns `Promise[t]` immediately and continues. The module runtime resolves the promise when the agent completes.

**`await` returns `Result[t, DelegationError]`, not bare `t`.** The generated code wraps `Async.wait` in exception handling so that agent failures (crash, timeout, type mismatch) are captured as `Result.Error DelegationError` values rather than propagating as uncaught exceptions. This preserves the LLMLL invariant that logic functions cannot crash from IO.

```lisp
(def-logic build-report [state: AppState data: ReportData]
  (let [[chart-future (?delegate-async @viz-agent
                         "Render a bar chart from data"
                         -> Promise[ImageBytes])]]
    (let [[chart-result (await chart-future)]]
      (match chart-result
        (Success img) (pair state (wasi.http.response 200 img))
        (Error err)   (pair state (wasi.http.response 500 "Agent failed")))))))
```

> [!IMPORTANT]
> **Type of `await`:** `await : Promise[t] -> Result[t, DelegationError]`. The type checker infers `Result[t, DelegationError]` for any `(await expr)` where `expr : Promise[t]`. An un-`await`ed `Promise[t]` remains `Promise[t]`.

> [!WARNING]
> **Breaking change from v0.2:** In v0.2, `await` was a no-op that returned bare `t` (since `Promise[t]` was backed by `IO t`). In v0.3, `await` returns `Result[t, DelegationError]`. Code that pattern-matches the result of `await` must use `Success`/`Error` arms. Code that used `await` without matching (e.g., passing the result directly) will get a type mismatch.

#### Delegation Outcome Table

| Scenario | Compiler Result |
|----------|----------------|
| Delegation succeeds, type matches | AST node replaced with implementation |
| Delegation succeeds, type mismatch | Compile error: `TypeMismatch` |
| Agent unavailable, `on-failure` provided | Fallback expression inserted |
| Agent unavailable, no `on-failure` | `?delegate-pending` hole — blocks execution |
| `?delegate-async`, agent succeeds | `await` returns `Result.Success value` |
| `?delegate-async`, agent fails | `await` returns `Result.Error DelegationError` |

#### Hole Resolution via JSON-Patch (v0.3)

In v0.3, `?delegate` holes can be resolved programmatically by agents through the **checkout/patch lifecycle**. This is the primary agent-coordination mechanism for filling holes without human intervention.

**Workflow:**

1. **Checkout.** An agent calls `llmll checkout <file.ast.json> <pointer>` to lock a hole. The compiler validates the RFC 6901 pointer resolves to a `hole-*` node, creates a lock entry in `.llmll-lock.json`, and returns a checkout token. The lock has a 1-hour TTL; stale locks are auto-expired.

2. **Patch.** The agent submits an RFC 6902 JSON-Patch wrapped in an LLMLL envelope containing the checkout token and patch operations:

```json
{
  "token": "a1b2c3d4...",
  "patch": [
    { "op": "test",    "path": "/statements/2/body", "value": { "kind": "hole-delegate", ... } },
    { "op": "replace", "path": "/statements/2/body", "value": { "kind": "lit-int", "value": 42 } }
  ]
}
```

3. **Re-verify.** The compiler applies the patch to the JSON-AST, re-parses, and re-typechecks. If the patch introduces a type error, the diagnostic pointers reference the patch operation that caused the failure (e.g., `patch-op/1/body` instead of `/statements/2/body`).

4. **Commit or reject.** On success the updated `.ast.json` is written and the lock is cleared. On failure the original file is unchanged and the lock is preserved for retry.

**Scope containment:** All patch operations must target nodes within the checked-out subtree. A token for `/statements/2/body` cannot be used to modify `/statements/0/body` — this prevents lateral hole theft between agents.

**Supported RFC 6902 operations:** `replace`, `add`, `remove`, `test`. The `test` operation is the agent's guard against stale patches — it asserts that the hole hasn't been modified since checkout. `move` and `copy` are deferred to a future release.

**CLI commands:**

| Command | Purpose |
|---------|---------|
| `llmll checkout <file.ast.json> <pointer>` | Lock a hole, get token |
| `llmll checkout --release <file> <token>` | Explicitly abandon a checkout |
| `llmll checkout --status <file> <token>` | Query remaining TTL |
| `llmll patch <file.ast.json> <patch.json>` | Apply patch + re-verify |

**HTTP endpoints** (via `llmll serve`): `POST /checkout`, `POST /checkout/release`, `POST /patch` — governed by the same bearer token auth as `POST /sketch`.

> [!NOTE]
> Checkout requires `.ast.json` input. S-expression sources are rejected with: `"checkout requires .ast.json input; run 'llmll build --emit json-ast' first"`. Patches are restricted to hole-filling in v0.3; general AST mutation is planned for a future release.

#### Context-Aware Checkout (v0.3.5)

Since v0.3.5, `llmll checkout` returns the **local typing context** alongside the lock token. This is the single highest-impact change for agent first-attempt accuracy — agents no longer need to infer what’s in scope from surrounding AST context.

The checkout response includes four optional fields (present when the compiler has sketch data for the target hole):

| Field | Type | Content |
|-------|------|---------|
| `in_scope` | `[ScopeEntry]` | Bindings visible at the hole site (Γ delta: `tcEnv \ builtinEnv`). Each entry has `name`, `type` (LLMLL notation), and `source` (`param`, `let-binding`, `match-arm`, `open-import`). Sorted by source priority; truncated at 50 entries with `scope_truncated: true`. |
| `expected_return_type` | `string` | The inferred return type at the hole site (τ as a type label). |
| `available_functions` | `[FuncEntry]` | Non-`wasi.*` function signatures (Σ), monomorphized against concrete scope types. E.g., when `xs : list[int]` is in scope, `list-head` appears as `list[int] → Result[int, string]` rather than `list[a] → Result[a, string]`. Each entry has `name`, `params` (with types), `returns`, and `status` (`filled`, `hole`, `builtin`). |
| `type_definitions` | `[TypeDefEntry]` | User-defined types referenced by in-scope bindings. Sum types include constructors; aliases include the base type. Depth-bounded expansion (max 5 levels) with cycle detection (`recursive: true`). |
| `scope_truncated` | `bool` | `true` if the scope was truncated to the 50-entry limit; absent or `false` otherwise. |

**Pointer normalization (EC-3):** RFC 6901 pointer segments with leading zeros are normalized: `/statements/02/body` → `/statements/2/body`.

**Monomorphization (C5):** Polymorphic signatures in `available_functions` are rewritten against concrete types found in the scope. This is a presentation-only transformation — the underlying `builtinEnv` is not mutated (INV-2).

**Scope truncation (C6):** When the in-scope binding count exceeds the limit, entries are retained by source priority: `param` > `let-binding` > `match-arm` > `open-import`. Shadowing safety is structurally guaranteed by the single-entry-per-key invariant of the scope map (INV-3).

### 11.3 AST-Level Merging (Semantic Source Control)

`llmll` bypasses text-based merge conflicts by operating exclusively on the AST:

- **Concurrent additions:** Agent A adds a function + Agent B adds a type → compiler merges tree nodes seamlessly.
- **Logical conflicts:** Two agents redefine the same node incompatibly → compiler generates `?conflict-resolution` hole and flags the Lead AI. No `<<<< HEAD` markers.

### 11.4 Global Module Invariants (`def-invariant`)

A module can declare invariants that must hold over its state at all times:

```lisp
(def-invariant balance-conservation [state: LedgerState]
  (= (sum (map-values (state-accounts state)))
     (state-total-supply state)))
```

After any AST merge, the compiler runs Z3 verification of all declared invariants. A merge that breaks a global invariant is rejected before it can produce runnable code.

---

## 12. Formal Grammar Reference

The grammar is given in EBNF. `{ x }` means zero or more `x`. `[ x ]` means optional `x`. `( x | y )` means a choice. Terminals are in `"double quotes"`. All source files must be **ASCII-only**.

```ebnf
(* ============================================================ *)
(* Top-level structure                                           *)
(* ============================================================ *)
program     = { statement } ;
statement   = type-decl | gen-decl | def-logic | def-interface
            | def-invariant | def-main | module-decl | import
            | open-decl | export-decl              (* NEW in v0.2 *)
            | trust-decl                            (* NEW in v0.3 *)
            | check | expr ;

(* ============================================================ *)
(* Module                                                        *)
(* ============================================================ *)
module-decl = "(" "module" IDENT { import } { statement } ")" ;

(* ============================================================ *)
(* Imports                                                       *)
(* ============================================================ *)
import      = "(" "import" qual-ident
                [ "(" "capability" STRING { kv } ")" ]
                [ "(" "interface" { iface-fn } ")" ]
              ")" ;
kv          = ":" IDENT ( STRING | INT | "true" | "false" | IDENT ) ;

(* ============================================================ *)
(* Open and Export — NEW in v0.2                                 *)
(* ============================================================ *)
open-decl   = "(" "open" qual-ident [ "(" { IDENT } ")" ] ")" ;
              (* (open foo.bar)           — all exports into scope without prefix *)
              (* (open foo.bar (f g))     — only f and g are unprefixed           *)
              (* Must appear before any def-logic in the same scope.              *)

export-decl = "(" "export" { IDENT } ")" ;
              (* Listed names become the module's public interface.               *)
              (* Absent: all top-level defs exported (open default).             *)
              (* Must appear before the first def-logic in the file.             *)

(* ============================================================ *)
(* Trust declarations — NEW in v0.3 (§4.4.3)                    *)
(* ============================================================ *)
trust-decl  = "(" "trust" qual-ident ":level" TRUST_LEVEL ")" ;
TRUST_LEVEL = "proven" | "tested" | "asserted" ;
              (* Acknowledges an unproven contract from an imported function.    *)
              (* Per-function, multiple per module. Idempotent (duplicates OK).  *)
              (* Must appear before any def-logic (same ordering as import).     *)

(* ============================================================ *)
(* Types                                                         *)
(* ============================================================ *)
type-decl   = "(" "type" IDENT type-body ")" ;

type-body   = where-type                             (* dependent type *)
            | { "(" "|" IDENT type ")" }            (* sum type / ADT *)
            ;

type        = primitive | list-type | map-type | result-type
            | promise-type | bytes-type | fn-type | where-type
            | pair-type | command-type | IDENT ;

primitive   = "int" | "float" | "string" | "bool" | "unit" ;
list-type   = "list" "[" type "]" ;
map-type    = "map" "[" type "," type "]" ;
result-type = "Result" "[" type "," type "]" ;
promise-type= "Promise" "[" type "]" ;
bytes-type  = "bytes" "[" INT "]" ;
pair-type   = "(" type "," type ")" ;
command-type= "Command" ;

fn-type     = "(" "fn" "[" { fn-param } "]" ARROW type ")" ;
fn-param    = type | typed-param ;   (* named param is doc-only *)
where-type  = "(" "where" "[" IDENT ":" type "]" expr ")" ;

ARROW       = "->" | "→" ;  (* both produce TokArrow; canonical output is "->" *)
              (* → = U+2192. All other non-ASCII codepoints are lexer errors. *)

(* ============================================================ *)
(* Logic functions                                              *)
(* ============================================================ *)
def-logic   = "(" "def-logic" IDENT
                "[" { typed-param } "]"
                [ pre-clause ]
                [ post-clause ]
                expr
              ")" ;

typed-param = IDENT ":" type ;
pre-clause  = "(" "pre"  expr ")" ;
post-clause = "(" "post" expr ")" ;

(* ============================================================ *)
(* Interfaces                                                    *)
(* ============================================================ *)
def-interface = "(" "def-interface" IDENT { iface-fn } ")" ;
iface-fn      = "[" IDENT fn-type "]" ;

(* ============================================================ *)
(* Invariants                                                    *)
(* ============================================================ *)
def-invariant = "(" "def-invariant" IDENT "[" typed-param "]" expr ")" ;

(* ============================================================ *)
(* Entry point                                                    *)
(* ============================================================ *)
def-main    = "(" "def-main"
                ":mode" ( "console" | "cli" | "(" "http" INT ")" )
                [ ":init"    expr ]
                ":step"     expr
                [ ":read"    expr ]
                [ ":done?"   expr ]
                [ ":on-done" expr ]
              ")" ;

(* ============================================================ *)
(* Property-based tests & generators                            *)
(* ============================================================ *)
check       = "(" "check" STRING for-all ")" ;
for-all     = "(" "for-all" "[" { typed-param } "]" expr ")" ;

gen-decl    = "(" "gen" IDENT expr ")" ;
              (* expr must have the base type of the named dependent type *)

(* ============================================================ *)
(* Expressions                                                   *)
(* ============================================================ *)
expr        = literal | var | let | if | match | app | qual-app
            | op | pair | await | do | lambda | hole ;

literal     = INT | "-" INT | FLOAT | STRING | "true" | "false" ;
              (* Negative integers: '-' immediately precedes digits with no whitespace *)
var         = IDENT ;

(* let is SEQUENTIAL: each binding is in scope for all subsequent bindings *)
(* PR 4: binding head is now a pattern, not just an identifier.           *)
let         = "(" "let" "[" { let-binding } "]" expr ")" ;
let-binding = "(" pattern expr ")"          (* v0.1.2 canonical form *)
            | "[" pattern expr "]" ;        (* v0.1.1 legacy form — also accepted *)
              (* Example: (let [(x 1) (y (+ x 1))] y)  => 2 (simple vars)         *)
              (* Example: (let [((pair s cmd) (authenticate state cred))] ...)      *)

if          = "(" "if" expr expr expr ")" ;

(* match: MUST be exhaustive. Use _ as the catch-all arm.              *)
(* Failing match (no arm matches, no _ ) raises MatchFailure at runtime *)
match       = "(" "match" expr { match-arm } ")" ;
match-arm   = "(" pattern expr ")" ;
pattern     = "_"                            (* catch-all wildcard *)
            | IDENT                          (* variable binding   *)
            | literal                        (* literal equality   *)
            | "(" IDENT { pattern } ")" ;   (* constructor pattern *)

app         = "(" IDENT { expr } ")" ;          (* plain function call *)
qual-app    = "(" qual-ident { expr } ")" ;     (* capability command  *)
op          = "(" OP { expr } ")" ;
pair        = "(" "pair" expr expr ")" ;
await       = "(" "await" expr ")" ;
do          = "(" "do" { do-step } ")" ;
do-step     = "[" IDENT "<-" expr "]"        (* named: bind state component *)
            | expr ;                           (* anonymous: discard state     *)
lambda      = "(" "fn" "[" { typed-param } "]" expr ")" ;

qual-ident  = IDENT { "." IDENT } ;   (* e.g., wasi.io.stdout *)

hole        = "?" IDENT                                        (* named *)
            | "?" "choose" "(" { IDENT } ")"                  (* choice *)
            | "?" "request-cap" "(" STRING ")"                 (* capability request *)
            | "?" "scaffold" "(" IDENT { kv } ")"             (* scaffold *)
            | "?" "delegate" "@" IDENT STRING ARROW type
                [ "(" "on-failure" expr ")" ]                  (* blocking delegate *)
            | "?" "delegate-async" "@" IDENT STRING ARROW type ;  (* async delegate *)

(* ============================================================ *)
(* Operators (all built-in; see Section 13)                      *)
(* ============================================================ *)
OP = "+" | "-" | "*" | "/" | "=" | "!=" | "<" | ">" | "<=" | ">="
   | "and" | "or" | "not" | "mod" ;
```

### Grammar Key Rules

1. **No return-type annotation.** There is no `: ReturnType` after `[params]` in `def-logic`. Return types are always inferred.
2. **`check` requires exactly one `for-all`.** A bare boolean expression is not valid inside `check`.
3. **`check` block labels must be valid identifiers.** Labels become Haskell `prop_*` function names. Any character outside `[a-zA-Z0-9]` is automatically replaced with `_` by the compiler. Write labels like `"game-over-false-at-start"` rather than `"game over (initial state)"` — both are accepted but special chars are silently normalized.
4. **List literals** (`[]`, `[a b c]`) are valid in both S-expression and JSON-AST. In S-expression, `[expr ...]` in expression position desugars to `foldr list-prepend (list-empty)` — **not** a parameter list. In JSON-AST use `{ "kind": "lit-list", "items": [...] }`.

5. **`let` bindings are sequential.** Each binding sees all previous bindings. The current syntax is `(let [(x 1) (y (+ x 1))] y)` (evaluates to `2`). The double-bracket form `(let [[x 1] [y 2]] ...)` is also accepted and equivalent — both forms compile to identical AST nodes. The binding head may be a `pattern` instead of a simple identifier, enabling pair destructuring: `(let [((pair s cmd) expr)] ...)`. In JSON-AST, use `"pattern"` instead of `"name"` in the let-binding object.
6. **`match` must be exhaustive.** Use `_` as the final arm if not all cases are covered explicitly. A `match` without `_` that fails at runtime raises `MatchFailure`.
7. **`result` is reserved** inside `post` clauses. Do not use it as a variable or parameter name anywhere.
8. **Named parameters in `fn-type` are doc-only.** `(fn [raw: string] -> bytes[64])` and `(fn [string] -> bytes[64])` are type-equivalent.


---

## 13. Built-in Runtime Functions

These functions and operators are **always in scope**. They are provided by the LLMLL runtime and do not require a `capability` import, except for the command constructors in §13.9 which require the matching capability.

### 13.1 Arithmetic Operators

| Operator | Signature | Notes |
|----------|-----------|-------|
| `+` | `int int -> int` | Addition |
| `-` | `int int -> int` | Subtraction |
| `*` | `int int -> int` | Multiplication |
| `/` | `int int -> int` | Integer division; raises `DivisionByZero` if right operand is `0`. **Codegen:** compiles to Haskell `` `div` `` (not `/`, which requires `Fractional`). |
| `mod` | `int int -> int` | Modulo |

### 13.2 Comparison & Equality Operators

The `=` operator is **polymorphic structural equality** defined over all LLMLL types:

- **`int`, `float`, `bool`:** numeric/value equality.
- **`string`:** byte-by-byte equality (UTF-8; locale-independent).
- **`list[t]`:** equal if same length and each pair of elements is `=`.
- **`map[k,v]`:** equal if same key set and each value is `=`.
- **`(a, b)` pairs:** equal if both components are `=`.
- **ADT constructors:** equal if same constructor tag and payload is `=`.
- **`Command`:** comparison is **not defined** — commands are opaque.

| Operator | Signature | Notes |
|----------|-----------|-------|
| `=` | `a a -> bool` | Polymorphic structural equality (see above) |
| `!=` | `a a -> bool` | Structural inequality |
| `<` `>` `<=` `>=` | `int int -> bool` | Ordered comparison (integers only) |

### 13.3 Logic Operators

| Operator | Signature | Notes |
|----------|-----------|-------|
| `and` | `bool bool -> bool` | Short-circuit AND (right side not evaluated if left is `false`) |
| `or` | `bool bool -> bool` | Short-circuit OR (right side not evaluated if left is `true`) |
| `not` | `bool -> bool` | Logical negation |

### 13.4 Pair / Record Operations

| Function | Signature | Notes |
|----------|-----------|-------|
| `pair` | `a b -> (a, b)` | Construct a 2-tuple. **v0.3 PR 1:** now correctly typed `TPair a b` — distinct from `Result[a,b]` in diagnostics and JSON-AST output |
| `first` | `(a, b) -> a` | First projection — accepts any pair, including explicitly-annotated parameters |
| `second` | `(a, b) -> b` | Second projection — accepts any pair, including explicitly-annotated parameters |

> **Pair destructuring in `let` bindings (v0.3 PR 4 — shipped).**
> `(let [((pair s cmd) (authenticate state cred))] ...)` destructures a pair result into `s` and `cmd`. Nested destructuring is supported: `(let [((pair word (pair g rest)) state)] ...)`. This works identically to pair patterns in `match` arms. In JSON-AST, use `"pattern"` instead of `"name"` in the let-binding object.

> **Pattern for records:** LLMLL has no native record syntax. Use nested `pair` values and named accessor functions. A 4-field record uses 3 levels of nesting:
> ```lisp
> ;; State = (word, (guessed, (wrong-count, max-wrong)))
> (def-logic make-state [w: Word g: list[Letter] wc: GuessCount mx: GuessCount]
>   (pair w (pair g (pair wc mx))))
> (def-logic state-word    [s] (first s))
> (def-logic state-guessed [s] (first (second s)))
> (def-logic state-wrong   [s] (first (second (second s))))
> (def-logic state-max     [s] (second (second (second s))))
> ```

### 13.5 List Operations

| Function | Signature | Notes |
|----------|-----------|-------|
| `list-empty` | `-> list[a]` | Empty list (monomorphic; type inferred from usage) |
| `list-append` | `list[a] a -> list[a]` | Append element to **end** of list |
| `list-prepend` | `a list[a] -> list[a]` | Prepend element to **front** of list |
| `list-contains` | `list[a] a -> bool` | Membership test using `=` |
| `list-length` | `list[a] -> int` | Number of elements |
| `list-head` | `list[a] -> Result[a, string]` | First element; `Error` on empty list |
| `list-tail` | `list[a] -> Result[list[a], string]` | All but first; `Error` on empty list |
| `list-map` | `list[a] (fn [a] -> b) -> list[b]` | Transform each element |
| `list-filter` | `list[a] (fn [a] -> bool) -> list[a]` | Keep elements satisfying predicate |
| `list-fold` | `list[a] b (fn [b a] -> b) -> b` | Left fold (accumulate from left) |
| `list-nth` | `list[a] int -> Result[a, string]` | Element at index; `Error` on out-of-range |
| `range` | `int int -> list[int]` | `(range from to)` produces `[from, from+1, ..., to-1]`. If `from >= to`, returns empty list. |

> **`range` example:**
> ```lisp
> (range 0 5)   ;; => list containing 0, 1, 2, 3, 4
> (range 3 3)   ;; => empty list
> (range 5 3)   ;; => empty list
> ```
>
> **List literals:** `[]` is the empty list; `[a b c]` is a three-element list — valid in both S-expression and JSON-AST syntax. In S-expression, `[expr ...]` in expression position desugars to `foldr list-prepend (list-empty)`. In JSON-AST, use `{ "kind": "lit-list", "items": [...] }`. The `list-empty` and `list-prepend` functions remain valid alternatives.
> ```lisp
> ;; list literal with let syntax:
> (let [(n       (string-length word))
>       (indices (range 0 n))]
>   (list-map indices (fn [i: int] (string-char-at word i))))
> ```

### 13.6 String Operations

| Function | Signature | Notes |
|----------|-----------|-------|
| `string-length` | `string -> int` | Length in characters |
| `string-contains` | `string string -> bool` | Substring / character test |
| `string-concat` | `string string -> string` | Concatenation |
| `string-slice` | `string int int -> string` | `[start, end)` half-open slice |
| `string-char-at` | `string int -> string` | Single character at index (as 1-char string) |
| `string-split` | `string string -> list[string]` | Split on delimiter |
| `string-trim` | `string -> string` | Strip leading/trailing whitespace and newlines (`Space`, `\t`, `\n`, `\r`) |
| `string-concat-many` | `list[string] -> string` | Concatenate a list of strings (variadic join without separator) |
| `regex-match` | `string string -> bool` | Regex predicate (POSIX ERE) |
| `string-empty?` | `string -> bool` | True when string has length 0 |

### 13.7 Numeric Utilities

| Function | Signature | Notes |
|----------|-----------|-------|
| `int-to-string` | `int -> string` | Decimal representation |
| `string-to-int` | `string -> Result[int, string]` | Parse; `Error` on failure |
| `abs` | `int -> int` | Absolute value |
| `min` | `int int -> int` | Minimum |
| `max` | `int int -> int` | Maximum |
| `mod` | `int int -> int` | Modulo (same as `%` in C) |

### 13.8 Result Helpers

| Function | Signature | Notes |
|----------|-----------|-------|
| `ok` | `a -> Result[a, e]` | Wrap in `Success` |
| `err` | `e -> Result[a, e]` | Wrap in `Error` |
| `is-ok` | `Result[a, e] -> bool` | `true` if `Success` |
| `unwrap` | `Result[a, e] -> a` | Extract value; raises `UnwrapError` on `Error` |
| `unwrap-or` | `Result[a, e] a -> a` | Default value on `Error` |

### 13.9 Standard Command Constructors

These functions produce `Command` values. Each requires the corresponding `import` declaration — the compiler will reject a call to a command constructor whose capability has not been imported.

| Constructor | Signature | Required `import` | Effect |
|-------------|-----------|-------------------|--------|
| `wasi.io.stdout` | `string -> Command` | `(import wasi.io (capability stdout ...))` | Write text to standard output |
| `wasi.io.stderr` | `string -> Command` | `(import wasi.io (capability stderr ...))` | Write text to standard error |
| `wasi.http.response` | `int string -> Command` | `(import wasi.http (capability serve PORT))` | Return HTTP response (status, body) |
| `wasi.http.post` | `string string -> Command` | `(import wasi.http (capability post URL))` | POST body to URL |
| `wasi.fs.read` | `string -> Command` | `(import wasi.filesystem (capability read PATH))` | Read file at path |
| `wasi.fs.write` | `string string -> Command` | `(import wasi.filesystem (capability write PATH))` | Write content to file at path |
| `wasi.fs.delete` | `string -> Command` | `(import wasi.filesystem (capability delete PATH))` | Delete file at path (**sensitive** — triggers human review) |
| `seq-commands` | `Command Command -> Command` | _(none — built-in)_ | Execute two commands in order |

**Example: Using multiple commands**

```lisp
(module game
  (import wasi.io (capability stdout :deterministic false))

  (def-logic initialize-game [word: Word]
    (pre (> (string-length word) 0))
    (let [[initial-state (make-state word (list-empty) 0 6)]]
      (pair initial-state (wasi.io.stdout "Game initialized.\n")))))
```

### 13.10 Clause-Scoped Bindings

The identifier `result` is a **reserved pseudo-binding** available only inside `post` clauses. It is automatically bound to the return value produced by the function body, after the body has been evaluated and before the postcondition is checked.

| Identifier | Scope | Value |
|------------|-------|-------|
| `result` | Inside `post` only | The return value of the function body |

```lisp
(def-logic add [x: int y: int]
  (post (= result (+ x y)))  ;; result = x + y, as returned by the body
  (+ x y))
```

`result` cannot appear in:
- `pre` clauses (the body has not run yet)
- `let` bindings (not a valid expression outside `post`)
- Parameter lists (reserved keyword — compile error)

### 13.10 Building Services (FAQ)

When building practical services (REST APIs, CLIs, etc.) in LLMLL, here are solutions to common patterns. All examples use the Haskell FFI model.

1. **HTTP Requests (Input):**
   LLMLL does not have a built-in `HttpRequest` sum type with headers and paths. If your service requires routing or header inspection, use the Tier 1 Hackage FFI:
   ```lisp
   (import haskell.warp (interface [
     [parse-request (fn [s: string] -> Result[HttpRequest, string])]
   ]))
   ```
   This resolves to `import Network.Wai` — no stub generated.

2. **CLI Arguments:**
   For structured argument parsing (e.g., `--port 8080 --file data.json`), you have two options:
   - Write a naive string-splitting parser in pure LLMLL S-expressions.
   - Use the Tier 1 Hackage FFI:
   ```lisp
   (import haskell.optparse-applicative (interface [
     [parse-args (fn [s: string] -> Result[CliArgs, string])]
   ]))
   ```

3. **JSON Parsing & Serialization:**
   Use the Tier 1 Hackage FFI — no stub file generated:
   ```lisp
   (import haskell.aeson (interface [
     [json-decode (fn [s: string] -> Result[TodoList, string])]
     [json-encode (fn [td: TodoList] -> string)]
   ]))
   ```
   This resolves to `import Data.Aeson`. The developer writes a `FromJSON`/`ToJSON` instance for the LLMLL type in a thin Haskell bridge file.

4. **Atomic File Writes:**
   The built-in `wasi.fs.write` does not guarantee atomicity. For ACID-like atomic writes, use the Tier 1 Hackage FFI:
   ```lisp
   (import haskell.unix (interface [
     [atomic-write (fn [path: string content: string] -> bool)]
   ]))
   ```
   This resolves to `import System.Posix.Files` and `atomicWriteFile` — no stub required.

---

## 14. Version Roadmap

> For the compiler team's full implementation schedule, ticket-level deliverables, and acceptance criteria, see [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md). This section documents **language-visible features** only.

### v0.3.2 — Trust Hardening + WASM PoC ✅ Shipped

| Area | Feature |
|------|---------|
| Cross-module trust propagation | ✅ 7 test cases covering the asserted/tested/proven matrix, mixed verification levels, and `(trust ...)` declaration suppression. Validates that a `VLProven` function importing a `VLAsserted` dependency is correctly capped at `VLAsserted`. |
| `llmll verify --trust-report` | ✅ Per-function trust summary with transitive closure analysis. Reports verification level (proven/tested/asserted) for every contract. Flags epistemic drift: “Function `withdraw` is proven, but depends on `auth.verify-token` which is asserted.” JSON output with `--json`. New `LLMLL.TrustReport` module. |
| GHC WASM PoC | ✅ Analyzed generated Haskell output for WASM compatibility. Conditional GO verdict — pure logic compiles cleanly; ~6-7 days engineering. See [`docs/wasm-poc-report.md`](docs/wasm-poc-report.md). |

### v0.3.3 — Agent Orchestration ✅ Shipped

| Area | Feature |
|------|---------|
| `llmll holes --deps` | ✅ Annotated dependency graph in `--json` output. Each hole entry includes `depends_on` edges (pointer/via/reason) and `cycle_warning` flag. Only body-level `AgentTask`/`Blocking` holes participate; `?proof-required` and contract-position holes excluded. |
| Cycle detection | ✅ Tarjan's SCC algorithm detects mutual-recursion cycles. Deterministic back-edge removal (highest statement index). Error-level diagnostic if any SCC function lacks explicit return type. |
| `--deps-out FILE` | ✅ Persist dependency graph to file (implies `--deps`). Compiler does not manage lifecycle — orchestrator owns the file. |
| RFC 6901 pointer fix | ✅ `holePointer` now tracks structural AST position (`/statements/N/body`, etc.) — compatible with `llmll checkout`. Previous context-based pointer generation was non-functional. |
| Call-graph analysis | ✅ `extractCalls` + `buildCallGraph` + `buildFuncBodyHoles` + `computeHoleDeps` — new internal functions in `HoleAnalysis.hs`. |

### v0.3.4 — Agent Spec + Orchestrator Hardening ✅ Shipped

| Area | Feature |
|------|---------|
| `llmll spec` | ✅ Compiler-emitted agent prompt specification generated directly from `builtinEnv`. 36 builtins + 14 operators. JSON output (`--json`) includes constructors, evaluation model, pattern kinds, type nodes. Text output is token-dense for direct system prompt inclusion. |
| Spec Faithfulness tests | ✅ 7 property tests ensure spec is a superset of `builtinEnv`, partition is disjoint, output is deterministic, `wasi.*` functions excluded. Adding a new builtin without a spec entry is caught automatically. |
| Phase A prompt enrichment | ✅ ~950 tokens added to orchestrator system prompt: pair/first/second, Result construction vs pattern matching (ok/err vs Success/Error), letrec note, fixed-arity operator rule, type nodes (`pair-type`, `fn-type`). |
| Orchestrator integration | ✅ `compiler.spec()` wraps `llmll spec` with backward-compat fallback. `build_system_prompt()` injects compiler-emitted spec; falls back to static legacy reference for pre-v0.3.4 compilers. |
| New builtins | ✅ `string-empty?` (`string → bool`) added to `builtinEnv` + runtime preamble. `regex-match` preamble implemented (`isInfixOf`). `is-valid?` removed from `builtinEnv`. |

### v0.3.5 — Agent Effectiveness ✅ Shipped

| Area | Feature |
|------|---------|
| Context-aware checkout (C1–C6) | ✅ `llmll checkout` returns local typing context: `in_scope` (Γ delta with provenance tags), `expected_return_type` (τ), `available_functions` (Σ, monomorphized), `type_definitions` (depth-bounded alias expansion). `ScopeSource`/`ScopeBinding` provenance types in `TypeCheck.hs`. `withTaggedEnv` scope combinator. `truncateScope` with priority-based retention. |
| Pointer normalization (EC-3) | ✅ `normalizePointer` strips leading zeros from RFC 6901 numeric segments: `/statements/02/body` → `/statements/2/body`. |
| `ELet` env leak fix (EC-1) | ✅ Let bindings no longer leak into sibling if-branches. Env saved/restored around sequential let processing. |
| `llmll verify --weakness-check` | ✅ After SAFE, constructs trivial-body candidates (identity, constant-zero, empty-string, true, empty-list) and checks if they satisfy the contract. Advisory `spec-weakness` diagnostic with `trivial_implementation` field. New `WeaknessCheck.hs` module. |
| Orchestrator E2E | ✅ `_format_diagnostics()` converts raw compiler JSON into actionable text for agent retry prompts. `_ensure_checkout()` handles lock expiry with automatic re-checkout. Context-aware prompt construction from checkout response. 12 Python integration tests. |

### v0.3.1 — Event Log + Leanstral MCP ✅ Shipped

| Area | Feature |
|------|---------|
| Event Log | ✅ JSONL event logging for console programs (`.event-log.jsonl`). Stdout capture via `hDuplicate`/`hDupTo`. Crash-safe line-by-line format. |
| `llmll replay` | ✅ Deterministic replay: rebuilds program, feeds logged inputs step-by-step, compares outputs against recorded results. Reports match/divergence per event. |
| **Leanstral integration** | ✅ (mock-first) `?proof-required :inductive` and `:unknown` holes translated to Lean 4 `theorem` obligations (`LeanTranslate.hs`). MCP client (`MCPClient.hs`) with `--leanstral-mock` mode. Real `lean-lsp-mcp` integration deferred. |
| Proof cache | ✅ Per-file `.proof-cache.json` sidecar with SHA-256 invalidation (`ProofCache.hs`). Subsequent `llmll verify` reads cache, skips re-proving. |
| `llmll verify` extensions | ✅ `--leanstral-mock` / `--leanstral-cmd` / `--leanstral-timeout` CLI flags. `runLeanstralPipeline` scans statements for proof-required holes. |

### v0.3 — Agent Coordination + Interactive Proofs ✅ Shipped

| Area | Feature |
|------|---------|
| `?scaffold` | ✅ Cold-start module from `llmll-hub` skeleton; all `def-interface` boundaries pre-typed; implementation details as named `?` holes; resolves at parse time |
| `do`-notation | ✅ Monadic `do`-notation as surface syntax; desugars to `(State, Input) → (NewState, Command)`. No new runtime semantics. PRs 1–4 shipped: TPair introduction (PR 1), DoStep collapse (PR 2), emitDo rewrite soundness fix (PR 3), pair destructuring in `let` bindings (PR 4). |
| Stratified verification | ✅ Contracts carry a verification level (`proven`, `tested`, `asserted`). `--contracts` flag controls runtime assertion compilation. Trust-level propagation with `(trust ...)` declarations. `.verified.json` sidecar for cross-build proof caching. |
| `string-concat` sugar | ✅ Parse-level variadic: `(string-concat a b c)` desugars to `(string-concat-many [a b c])` |
| `Promise[t]` | ✅ Upgraded from `IO t` to `Async t` (`async` package). `(await x)` desugars to `Async.wait` |

### v0.4.0 — Lead Agent + U-Lite Soundness ✅ Shipped

| Area | Feature |
|------|---------|
| Lead Agent | ✅ `llmll-orchestra --mode plan|lead|auto --intent "..."` generates architecture plan, JSON-AST skeleton, fills holes, and verifies — end-to-end. Quality heuristics flag low parallelism, all-string types, missing contracts, unassigned agents. |
| U-Lite (Soundness) | ✅ Per-call-site substitution-based unification for concrete types with fresh type variable instantiation at each `EApp`. `list-head 42` is now a type error. `first`/`second` properly typed as `TPair a b → a`/`TPair a b → b`. Per-call-site scoping prevents cross-call conflicts. TDependent resolved via Strip-then-Unify (Option A). |
| CAP-1 (Capability enforcement) | ✅ `wasi.*` function calls require a matching `(import wasi.* (capability ...))` — compile-time type error if missing. Check is in `inferExpr (EApp ...)`, covering all nesting contexts. Non-transitive module-local propagation. |
| Invariant pattern registry | ✅ `llmll typecheck --sketch` emits `invariant_suggestions` from pattern database keyed by `(type signature, function name pattern)`. ≥5 patterns: list-preserving, sorted, round-trip, subset, idempotent. Stored as data, not code. |
| Downstream obligation mining | ✅ Cross-module UNSAFE results suggest postcondition strengthening on callee. Leverages `TrustReport.hs` transitive closure infrastructure. |
| Aeson FFI | ✅ `(import haskell.aeson Data.Aeson)` codegen emits `import Data.Aeson` + adds `aeson` to `package.yaml`. Manual Haskell bridge file for JSON instance derivation. |

### v0.5 — U-Full Soundness ✅ Shipped

Complete sound unification — closes the last known unsoundness in the type checker. WASM build target moved to unversioned future work (2026-04-21).

| Area | Feature |
|------|---------|
| U-full (Algorithm W) | ✅ Occurs check prevents infinite types (`a ~ list[a]` is rejected). TVar-TVar wildcard closure ensures type variable bindings propagate through chains. Bound-TVar consistency uses recursive `structuralUnify` instead of `compatibleWith` (Language Team Issue 2). `TDependent` strips to base type (two-layer architecture preserved). 7 new tests (264 total). |
| `effectful` WASM spike | ✅ **GO.** `effectful` 2.6.1.0 compiles, links, and executes under `wasm32-wasi` (GHC 9.12.4, wasmtime 44.0.0). No C shim failures. Typed effect row design is WASM-compatible. See [`docs/effectful-wasm-spike.md`](docs/effectful-wasm-spike.md). |

> [!NOTE]
> **Known limitation (v0.5):** Let-generalization applies to top-level `def-logic` and `letrec` functions only. Inner `let`-bound lambdas (e.g., `(let [(id (fn [x: a] x))] (pair (id 1) (id "hello")))`) are not generalized — the `TVar` is shared across call sites within the same `EApp` scope. An explicit generalize/instantiate pass for inner `let` is planned for v0.7.

### v0.6 — Specification Quality ✅ Shipped

The specification coverage and quality gate — the acknowledged bottleneck since v0.4.0. Functions without contracts can no longer silently proceed through the pipeline.

| Area | Feature |
|------|---------|
| Spec coverage gate (`--spec-coverage`) | ✅ `llmll verify --spec-coverage` classifies every function as contracted, suppressed (`weakness-ok`), or unspecified. Computes `effective_coverage = (contracted + suppressed) / total`. Text and JSON output. `SpecCoverage.hs` module. |
| Suppression governance (`weakness-ok`) | ✅ `(weakness-ok fn-name "reason")` — top-level declaration. Mandatory non-empty reason string. Parser support in S-expression and JSON-AST. Governance warnings: WO-1 (`W601`), WO-2 (`W602`), D10 (`W603`). |
| Clause-level provenance (`:source`) | ✅ `(pre expr :source "RFC 8446 §7.1")` — per-clause metadata on `pre`/`post`. Parsed in S-expression and JSON-AST (`pre_source`/`post_source`). Threaded through `--trust-report` and `.verified.json`. No effect on type checking or codegen. |
| ERC-20 benchmark | ✅ Frozen benchmark in `examples/erc20_token/` — skeleton, filled version, `EXPECTED_RESULTS.json` with verification-scope matrix (10 properties), end-to-end `WALKTHROUGH.md`. |
| TrustReport suppressions | ✅ `--trust-report` output includes "Intentional Underspecification" section listing all `weakness-ok` declarations with reasons. JSON output includes `suppressions` array. |

### Future — WASM Sandboxing (unversioned)

WASM-WASI is the long-term deployment target. Docker + `seccomp-bpf` remains the sandbox until WASM is scheduled. Confirmed future direction, not pinned to a release version.

| Area | Feature |
|------|---------|
| `llmll build --target wasm` | Generated Haskell compiled with GHC's `--target=wasm32-wasi` backend |
| WASM VM | Wasmtime (or equivalent) replaces Docker as the default sandbox |
| WASI capability enforcement | WASI import declarations replace Docker network/filesystem policy layers |
| `{-# LANGUAGE Safe #-}` | Already enforced from v0.1.2; guarantees generated code is structurally WASM-compatible from day one |

### v0.2 — Module System + Compile-Time Verification ✅ Shipped

The module system shipped **first within v0.2** (Phase 2a) because cross-module invariant verification (`def-invariant` + liquid-fixpoint) requires multi-file resolution as substrate.

| Area | Feature |
|------|---------|
| **Module system (Phase 2a)** | Multi-file resolution: `(import foo.bar ...)` loads and type-checks `foo/bar.llmll` or its `.ast.json` equivalent |
| **Module system (Phase 2a)** | Namespace isolation: each source file has its own top-level scope; imported names accessible as `module.name` by default |
| **Module system (Phase 2a)** | `open` / `export` — selective unprefixing and visibility control (see §8.6, §8.7) |
| **Module system (Phase 2a)** | Cross-module `def-interface` enforcement — structural compatibility checked at import time (see §8.8) |
| **Module system (Phase 2a)** | `llmll-hub` read-only registry: `llmll hub fetch <pkg>@<ver>` + `hub.` import prefix (see §8.9) |
| **Capability enforcement** | ✅ **Shipped in v0.4.0 (CAP-1).** Capability declarations are enforced at compile time: `wasi.*` calls without a matching capability import produce a type error. Check is in `inferExpr (EApp ...)`. Non-transitive module-local propagation. `effectful` typed effect row integration is planned alongside WASM-WASI enforcement (future, not version-pinned). |
| **Compile-time contracts (Phase 2b)** | `llmll verify` emits `.fq` constraints from the typed AST and runs `liquid-fixpoint` + Z3 as a standalone binary. Covers quantifier-free linear integer arithmetic. Reports SAFE or contract-violation diagnostics with JSON Pointers. No GHC plugin required. |
| **`?proof-required` holes (Phase 2b)** | Auto-emitted for predicates outside the QF fragment or complex `letrec` `:decreases` measures. Complexity hints: `complex-decreases` or `non-linear-contract`. Non-blocking — runtime assertion remains active. |
| **`letrec` (Phase 2b)** | Bounded recursion with mandatory `:decreases` termination annotation. Simple variable measures are verified by `llmll verify`. |
| **`match` exhaustiveness (Phase 2b)** | Static exhaustiveness checking for ADT sum types — a `match` missing a constructor arm is a compile error. |
| **Type system fix (Phase 2c)** | `pair-type` in `typed-param` position is now accepted: `[acc: (int, string)]` in `def-logic` params, lambda params, and `for-all` bindings. The v0.1.x untyped-parameter workaround is no longer needed. |
| `def-invariant` | liquid-fixpoint-backed module invariant verification after every AST merge |
| **`llmll typecheck --sketch`** | Partial-program type inference API: accepts a program with holes, returns inferred type of each hole and any type errors present even in the incomplete program |

### v0.1.2 — Machine-First Foundation ✅ Shipped

New language-visible features: JSON-AST as a first-class source format, Haskell codegen target, and minor surface syntax fixes.

| Area | Feature |
|------|---------|
| **Source formats** | Compiler accepts `.ast.json` files validated against `docs/llmll-ast.schema.json` as a first-class source format alongside `.llmll` S-expressions |
| JSON-AST | `llmll build --emit json-ast` round-trips S-expressions ↔ JSON |
| Diagnostics | Every compiler error is a JSON object with an RFC 6901 JSON Pointer to the offending AST node |
| Holes CLI | `llmll holes --json` lists all `?` holes with inferred type, module path, and agent target |
| **Codegen target** | Generated code is **Haskell** (`.hs` + `package.yaml`), replacing Rust. `Codegen.hs` rewritten as `CodegenHs.hs` (`generateHaskell`) |
| **`Command` model** | `Command` is emitted as plain Haskell `IO ()`. **Capability enforcement is active (v0.4.0, CAP-1):** `wasi.*` calls without matching capability import are compile-time type errors. `effectful` typed effect row integration (`Eff '[HTTP, FS, ...] r`) is planned alongside WASM-WASI (future, not version-pinned). |
| **FFI tiers** | Two tiers: (1) Hackage — `(import haskell.* ...)` resolves to a native GHC import, no stub generated; (2) C — `(import c.* ...)` generates a `foreign import ccall` stub in `src/FFI/*.hs`. The legacy `rust.*` namespace and Rust FFI stdlib are retired |
| **Sandboxing** | Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` replaces WASM as the runtime sandbox (WASM is a confirmed future direction, not version-pinned) |
| `let` syntax | `(let [(x e1) (y e2)] body)` — canonical v0.1.2 form; `(let [[x e1] [y e2]] body)` also accepted (v0.1.1 backward compat) |
| List literals | `[]` and `[a b c]` list literals added; `(list-empty)` and `(list-append ...)` remain valid |

> **Rationale — Haskell target:** LLMLL's concepts (pure functions, ADTs, algebraic effects, liquid types) map directly onto Haskell's native semantics. The Haskell target eliminates codegen semantic drift, makes v0.2 compile-time verification a liquid-fixpoint integration task (weeks, not months), and shares the compiler's own type universe with generated programs. WASM-WASI remains the long-term deployment target; Docker is the current sandbox.

> **Rationale — JSON-AST:** LLMs generating S-expressions suffer parentheses drift — a structural error whose rate is a function of generation length vs. nesting depth, not model quality. JSON schema-constrained generation (via OpenAI Structured Outputs, Gemini schema parameters, etc.) provides mathematical structural validity guarantees before the compiler runs.

### v0.1.1 ✅ Shipped

Closed all specification gaps found during real-world implementation. The spec is now sufficient to implement any program using only v0.1.1 primitives without workarounds.

| Area | Feature |
|------|---------|
| Type system | `Command` type formally defined; custom ADT sum types (`(type T (| Ctor t) ...)`) |
| Iteration | `range` built-in (`(range from to) -> list[int]`) |
| Grammar | `QualIdent` production; ARROW terminal with maximal-munch rule; exhaustive `match` spec; `=` polymorphism |
| Grammar | Unicode symbol aliases (`→` `∀` `λ` `∧` `∨` `¬` `≥` `≤` `≠`) |
| Contracts | `result` keyword formally defined for `post` clauses |
| `let` | Sequential binding semantics (`let*`) formally specified |
| IO | Standard command constructor library in §13.9; `seq-commands` combinator |
| Interfaces | Named parameters in `fn-type` formally specified as doc-only |
| PBT | Rejection-sampling fallback for dependent types; `gen` declaration for custom generators |
| Concurrency | `def-invariant` syntax (verification deferred to v0.2) |

