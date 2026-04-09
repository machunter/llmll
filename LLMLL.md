# LLMLL: Large Language Model Logical Language (v0.2)

**`llmll`** is a programming language designed specifically for AI-to-AI implementation under human direction. It prioritizes contract clarity, token efficiency, and ambiguity resolution over human readability.

> **Current scope (v0.2):** Haskell codegen is the only supported backend. Every construct in this document has fully defined syntax, grammar, and runtime semantics, and compiles with 0 errors in the current compiler. Phase 2a delivers the full multi-file module system (`import`, `open`, `export`, `llmll-hub` registry). **Phase 2b is complete:** compile-time contract verification via liquid-fixpoint ships as `llmll verify`; `letrec` with `:decreases` termination measures and `match` exhaustiveness checking are now enforced. **Phase 2c is complete:** pair-type in typed parameters is fully supported; `llmll typecheck --sketch` provides partial-program type inference for agent use; `llmll serve` exposes the sketch pass as an HTTP endpoint for distributed agent swarms. **v0.3 development is underway:** PR 1 (TPair introduction), PR 2 (DoStep collapse), and PR 3 (emitDo rewrite soundness fix) have merged. `do`-notation is fully implemented with type-safe state threading and compiles to pure `let`-chains. PR 4 (pair destructuring in `let`) is in progress. Interactive theorem proving via Leanstral arrives in v0.3. For the compiler team’s implementation schedule, see [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md). For full release notes, see [`CHANGELOG.md`](CHANGELOG.md).

> **For AI code generators:** Every section contains at least one complete, compilable example. When generating LLMLL code, you must use only the constructs defined in this document. If a required construct is missing, emit a named `?hole` and document the gap — do not invent syntax.

---

## 1. Core Philosophy

1. **Strict Immutability:** There are no variables, only constants. State is transformed, never mutated. Re-binding the same name in the same scope is a compile error.
2. **Hole-Driven Development:** Ambiguity is a first-class citizen represented by Holes (`?`). A program with holes can be analyzed and type-checked but not executed until the holes are filled. Always prefer a typed hole over a hallucinated implementation.
3. **Typed Logic:** Every expression has a type. The type system prevents null pointer dereferences, type mismatches, and unguarded IO. Return types are inferred — never annotate them explicitly.
4. **Runtime Contract Verification:** Logic functions declare `pre` and `post` conditions enforced as runtime assertions. These contracts are the machine-checked trust interface between agents: a caller does not need to understand an implementation, only that its contract holds.
5. **Capability-Based Security:** LLMLL programs run in a sandboxed environment (Docker + `seccomp-bpf` + `-XSafe` Haskell in v0.1.2–v0.3; WASM-WASI in v0.4). Programs have zero access to the system unless explicitly granted via a `capability` import. Every side effect is modeled as a `Command` value returned from pure logic — never performed directly.

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

> `Command` is opaque — it cannot be constructed with a literal or user-defined constructor. It is only produced by the standard command constructors listed in §13.9. You can store a `Command` in a `let` binding and return it from a function, but you cannot inspect its internal fields. In generated Haskell, `Command` becomes a **typed effect row** (`Eff '[HTTP, FS, ...] r` using the `effectful` library). A function's required capabilities are visible in its type signature. Missing capability declarations become type errors rather than silent runtime failures.


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

**Runtime:** Contracts always run during `llmll test` and remain active in production as a belt-and-suspenders check.

**Compile-time (Phase 2b):** `llmll verify` translates `pre`/`post` constraints in the **quantifier-free linear arithmetic fragment** (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`) to `.fq` constraints and solves them via `liquid-fixpoint` + Z3. Violations are reported as diagnostics with JSON Pointers before any binary is produced.

Predicates outside the decidable fragment (`*`, `/`, `mod`, non-linear) are emitted as `?proof-required(non-linear-contract)` holes (see §6). The runtime assertion remains active for those sites.

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

`llmll` programs run in a capability-gated sandbox. All interactions with the outside world require `import` statements that grant specific **capabilities**. The sandbox implementation is Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` in v0.1.2–v0.3, and WASM-WASI in v0.4.

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
- **Compilation:** The `do` block is compiled directly into a pure `let` chain. No Haskell `do` or monads are emitted, ensuring soundness in `def-logic` pure contexts. `seq-commands` is used automatically under the hood to fold the commands into a single `Command` return value.

> [!WARNING]
> Using an anonymous step `(expr)` when `expr` returns a new state will result in **state-loss**. The bound state from prior steps is retained, but the updated state from `(expr)` is discarded. Always use named steps `[s <- (expr)]` to thread modified states properly.

---

## 10. Compilation & Execution Pipeline

The pipeline accepts two source formats: S-expressions (`.llmll`) and JSON-AST (`.ast.json`).

1. **AI Implementation:** LLM generates `.llmll` S-expressions *or* `.ast.json` (preferred for AI agents — schema-constrained, structurally valid by construction).
2. **Parse & Semantic Check:** Compiler parses the source, verifies types and immutability, catalogs all `?holes`. Reports structured JSON diagnostics with RFC 6901 JSON Pointers to offending AST nodes. `llmll holes --json` lists all unresolved holes.
3. **Human/Lead-AI Review:** Holes and sensitive `Command` effects (e.g., `wasi.fs.delete`) are resolved/approved via Chat/CLI.
4. **Transpilation:** Validated `.llmll` is converted to **Haskell** (`.hs` + `package.yaml`). Generated modules are compiled with `{-# LANGUAGE Safe #-}`, preventing any IO outside the declared capability model.
5. **Binary Generation:** `ghc` compiles the generated Haskell to a native binary.
6. **Contract & Property Testing:** The test runner executes `pre`/`post` runtime assertions and `check`/`for-all` QuickCheck blocks against the running binary. Failures are reported as JSON diagnostics.
7. **Sandboxed Execution:** The binary runs inside a Docker container with `seccomp-bpf` syscall filtering and filesystem/network policies derived from the module's declared capabilities (v0.1.2–v0.3). In v0.4 this is replaced by a WASM-WASI VM.
8. **Event-Log Replay:** The runtime records a sequenced Event Log of `(Input, CommandResult, captures)` triples (see §10a). Replay is bitwise deterministic for all modules that use `:deterministic true` capability flags on clock and PRNG imports.

> **v0.2 (shipped):** Step 2 includes compile-time contract verification via `llmll verify` (decoupled liquid-fixpoint backend). Contracts outside the decidable QF arithmetic fragment are emitted as `?proof-required` holes.
> **v0.3:** `?proof-required :inductive` holes are resolved by Leanstral (Lean 4 proof agent) via MCP. Verified proof certificates are stored and re-checked on subsequent builds without re-calling Leanstral.
> **v0.4:** Docker sandbox is replaced by a WASM-WASI VM. `llmll build --target wasm` is available as an opt-in in v0.3.

---

## 10a. Event Log Specification

Correct replay is the foundation of fault tolerance, audit trails, and (in v0.2) SMT proof validation over execution traces.

### Sources of Non-Determinism

| Source | Problem | Runtime Fix |
|--------|---------|-------------|
| **IEEE 754 floats** | NaN canonicalization differs across host platforms | Reject non-canonical floats at the sandbox boundary (GHC NaN rules in v0.1.2–v0.3; `wasm-determinism` extension in v0.4) |
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

`?delegate-async` returns `Promise[t]` immediately and continues. The module runtime resolves the promise when the agent completes:

```lisp
(def-logic build-report [data: ReportData]
  (let [[chart-future (?delegate-async @viz-agent
                         "Render a bar chart from data"
                         -> Promise[ImageBytes])]]
    (pair state (wasi.http.response 202 (await chart-future)))))
```

#### Delegation Outcome Table

| Scenario | Compiler Result |
|----------|----------------|
| Delegation succeeds, type matches | AST node replaced with implementation |
| Delegation succeeds, type mismatch | Compile error: `TypeMismatch` |
| Agent unavailable, `on-failure` provided | Fallback expression inserted |
| Agent unavailable, no `on-failure` | `?delegate-pending` hole — blocks execution |
| `?delegate-async` failure | `Promise` resolves to `Result.Error DelegationError` at runtime |

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
let         = "(" "let" "[" { "[" IDENT expr "]" } "]" expr ")" ;
              (* Example: (let [[x 1] [y (+ x 1)]] y)  => 2          *)
              (* y can reference x because bindings are sequential.   *)

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

5. **`let` bindings are sequential.** Each binding sees all previous bindings. The current syntax is `(let [(x 1) (y (+ x 1))] y)` (evaluates to `2`). The double-bracket form `(let [[x 1] [y 2]] ...)` is also accepted and equivalent — both forms compile to identical AST nodes.
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

### v0.1.1

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

### v0.1.2 — Machine-First Foundation

New language-visible features: JSON-AST as a first-class source format, Haskell codegen target, typed effect row for `Command`, and minor surface syntax fixes.

| Area | Feature |
|------|---------|
| **Source formats** | Compiler accepts `.ast.json` files validated against `docs/llmll-ast.schema.json` as a first-class source format alongside `.llmll` S-expressions |
| JSON-AST | `llmll build --emit json-ast` round-trips S-expressions ↔ JSON |
| Diagnostics | Every compiler error is a JSON object with an RFC 6901 JSON Pointer to the offending AST node |
| Holes CLI | `llmll holes --json` lists all `?` holes with inferred type, module path, and agent target |
| **Codegen target** | Generated code is **Haskell** (`.hs` + `package.yaml`), replacing Rust. `Codegen.hs` rewritten as `CodegenHs.hs` (`generateHaskell`); old `Codegen.hs` retained as a deprecated re-export shim |
| **`Command` model** | `Command` is no longer an opaque type. In generated Haskell it becomes a **typed effect row** (`Eff '[HTTP, FS, ...]`) using the `effectful` library. A function's required capabilities are visible in its type signature. Missing capability declarations are **type errors**, not silently accepted |
| **FFI tiers** | Two tiers: (1) Hackage — `(import haskell.* ...)` resolves to a native GHC import, no stub generated; (2) C — `(import c.* ...)` generates a `foreign import ccall` stub in `src/FFI/*.hs`. The legacy `rust.*` namespace and Rust FFI stdlib are retired |
| **Sandboxing** | Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` replaces WASM as the runtime sandbox (WASM deferred to v0.4) |
| `let` syntax | `(let [(x e1) (y e2)] body)` — canonical v0.1.2 form; `(let [[x e1] [y e2]] body)` also accepted (v0.1.1 backward compat) |
| List literals | `[]` and `[a b c]` list literals added; `(list-empty)` and `(list-append ...)` remain valid |

> **Rationale — Haskell target:** LLMLL's concepts (pure functions, ADTs, algebraic effects, liquid types) map directly onto Haskell's native semantics. The Haskell target eliminates codegen semantic drift, makes v0.2 compile-time verification a liquid-fixpoint integration task (weeks, not months), and shares the compiler's own type universe with generated programs. WASM-WASI remains the long-term deployment target (v0.4); Docker is the research-stage sandbox.

> **Rationale — JSON-AST:** LLMs generating S-expressions suffer parentheses drift — a structural error whose rate is a function of generation length vs. nesting depth, not model quality. JSON schema-constrained generation (via OpenAI Structured Outputs, Gemini schema parameters, etc.) provides mathematical structural validity guarantees before the compiler runs.

### v0.2 — Module System + Compile-Time Verification

The module system shipped **first within v0.2** (Phase 2a) because cross-module invariant verification (`def-invariant` + liquid-fixpoint) requires multi-file resolution as substrate.

| Area | Feature |
|------|---------|
| **Module system (Phase 2a)** | Multi-file resolution: `(import foo.bar ...)` loads and type-checks `foo/bar.llmll` or its `.ast.json` equivalent |
| **Module system (Phase 2a)** | Namespace isolation: each source file has its own top-level scope; imported names accessible as `module.name` by default |
| **Module system (Phase 2a)** | `open` / `export` — selective unprefixing and visibility control (see §8.6, §8.7) |
| **Module system (Phase 2a)** | Cross-module `def-interface` enforcement — structural compatibility checked at import time (see §8.8) |
| **Module system (Phase 2a)** | `llmll-hub` read-only registry: `llmll hub fetch <pkg>@<ver>` + `hub.` import prefix (see §8.9) |
| **Capability enforcement** | Capability declarations fully enforced by the typed effect row — missing imports are type errors at compile time |
| **Compile-time contracts (Phase 2b)** | `llmll verify` emits `.fq` constraints from the typed AST and runs `liquid-fixpoint` + Z3 as a standalone binary. Covers quantifier-free linear integer arithmetic. Reports SAFE or contract-violation diagnostics with JSON Pointers. No GHC plugin required. |
| **`?proof-required` holes (Phase 2b)** | Auto-emitted for predicates outside the QF fragment or complex `letrec` `:decreases` measures. Complexity hints: `complex-decreases` or `non-linear-contract`. Non-blocking — runtime assertion remains active. |
| **`letrec` (Phase 2b)** | Bounded recursion with mandatory `:decreases` termination annotation. Simple variable measures are verified by `llmll verify`. |
| **`match` exhaustiveness (Phase 2b)** | Static exhaustiveness checking for ADT sum types — a `match` missing a constructor arm is a compile error. |
| **Type system fix (Phase 2c)** | `pair-type` in `typed-param` position is now accepted: `[acc: (int, string)]` in `def-logic` params, lambda params, and `for-all` bindings. The v0.1.x untyped-parameter workaround is no longer needed. |
| `def-invariant` | liquid-fixpoint-backed module invariant verification after every AST merge |
| **`llmll typecheck --sketch`** | Partial-program type inference API: accepts a program with holes, returns inferred type of each hole and any type errors present even in the incomplete program |

### v0.3 — Agent Coordination + Interactive Proofs

| Area | Feature |
|------|---------|
| `?delegate` protocol | Formal lifecycle: check-out → implementation → RFC 6902 JSON-Patch submission → compiler re-verification + merge |
| `?scaffold` | Cold-start module from `llmll-hub` skeleton; all `def-interface` boundaries pre-typed; implementation details as named `?` holes; resolves at parse time |
| **Leanstral integration** | `?proof-required :inductive` and `:unknown` holes are routed to [Leanstral](https://mistral.ai/news/leanstral) (open-source Lean 4 MCP proof agent) via `lean-lsp-mcp`. The compiler translates LLMLL `TypeWhere` constraints to Lean 4 `theorem` obligations. Verified proof certificates are stored alongside the source; subsequent builds verify certificates without re-calling Leanstral |
| `llmll check` | Verifies stored Lean 4 proof certificates without re-running Leanstral |
| Event Log | Formalized deterministic replay spec: `(Input, CommandResult, captures)` triples; NaN rejected at the GHC/WASM boundary |
| Trace proofs | SMT validation of `pre`/`post` over replayed Event Log traces (requires ✅ replayable modules) |
| `do`-notation | Monadic `do`-notation as surface syntax; desugars to `(State, Input) → (NewState, Command)`. No new runtime semantics. **PRs 1–3 shipped:** TPair introduction (PR 1), DoStep collapse (PR 2), emitDo rewrite soundness fix (PR 3). `do`-notation is fully implemented with type-safe state threading and compiles to pure `let`-chains. PR 4 (pair destructuring in `let`) is in progress. |
| `Promise[t]` | Upgraded from `IO t` to `Async t` (`async` package). `(await x)` desugars to `Async.wait` |

### v0.4 — WASM Hardening

WASM-WASI is the primary long-term deployment target. Docker + `seccomp-bpf` remains the sandbox through v0.3; v0.4 replaces it.

| Area | Feature |
|------|---------|
| `llmll build --target wasm` | Generated Haskell compiled with GHC's `--target=wasm32-wasi` backend |
| WASM VM | Wasmtime (or equivalent) replaces Docker as the default sandbox |
| Capability enforcement | WASI import declarations replace Docker network/filesystem policy layers |
| `{-# LANGUAGE Safe #-}` | Already enforced from v0.1.2; guarantees generated code is structurally WASM-compatible from day one |

