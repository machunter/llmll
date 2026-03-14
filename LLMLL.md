# LLMLL: Large Language Model Logical Language (v0.1.1)

**`llmll`** is a programming language designed specifically for AI-to-AI implementation under human direction. It prioritizes contract clarity, token efficiency, and ambiguity resolution over human readability.

> **v0.1.1 Scope:** This version closes all specification gaps identified during the Hangman implementation exercise. Every construct in this document has fully defined syntax, grammar, and runtime semantics. Formal compile-time verification (SMT/Z3 via liquid types) is introduced in v0.2; interactive theorem proving (Lean 4) in v0.3. See the [Version Roadmap](#14-version-roadmap) at the end of this document.

> **For AI code generators:** Every section contains at least one complete, compilable example. When generating LLMLL code, you must use only the constructs defined in this document. If a required construct is missing, emit a named `?hole` and document the gap — do not invent syntax.

---

## 1. Core Philosophy

1. **Strict Immutability:** There are no variables, only constants. State is transformed, never mutated. Re-binding the same name in the same scope is a compile error.
2. **Hole-Driven Development:** Ambiguity is a first-class citizen represented by Holes (`?`). A program with holes can be analyzed and type-checked but not executed until the holes are filled. Always prefer a typed hole over a hallucinated implementation.
3. **Typed Logic:** Every expression has a type. The type system prevents null pointer dereferences, type mismatches, and unguarded IO. Return types are inferred — never annotate them explicitly.
4. **Runtime Contract Verification:** Logic functions declare `pre` and `post` conditions enforced as runtime assertions. These contracts are the machine-checked trust interface between agents: a caller does not need to understand an implementation, only that its contract holds.
5. **Capability-Based Security:** The language runs in a WASM sandbox. It has zero access to the system unless explicitly granted via a `capability` import. Every side effect is modeled as a `Command` value returned from pure logic — never performed directly.

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
| `Command` | An opaque IO command value (see §9) | _(constructed via built-ins only)_ |

> **`Command` is opaque.** It cannot be constructed with a literal or user-defined constructor. It is only produced by the standard command constructors listed in §13.9. You can store a `Command` in a `let` binding and return it from a function, but you cannot inspect its internal fields.

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

In v0.1.1, dependent type constraints are **checked at runtime** (the predicate is evaluated when a value of that type is bound). Compile-time SMT verification of these constraints is introduced in v0.2.

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

### 4.2 The `result` Keyword in `post` Clauses

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

### 4.3 Contract Semantics

| Context | What happens on violation |
|---------|--------------------------|
| `pre` violation | `AssertionError` raised before body executes. The caller is buggy. |
| `post` violation | `AssertionError` raised before result is returned. The implementation is buggy. |
| Both satisfied | Result is returned normally. |

Contracts in v0.1.1 are **runtime assertions**. They run during `llmll test` and remain active in production execution. Compile-time proof of contracts is introduced in v0.2.

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

### 5.3 Verification Roadmap

> **v0.2 — Compile-Time SMT Verification:** A `smt-verify` block will send `pre`/`post` constraints (restricted to quantifier-free linear arithmetic) to a Z3 solver at compile time. Verified contracts are elided from the generated Rust code.
>
> **v0.3 — Interactive Proof Holes:** A `?proof-required` hole type will scaffold Lean 4 proof obligations for inductive invariants, routed to a specialist proof-synthesis agent.

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

`llmll` programs are sandboxed WASM modules. All interactions with the outside world require `import` statements that grant specific **capabilities**.

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

**External Bridge (FFI):** To use existing Rust/C code, define a Verified Wrapper:

```lisp
(import rust.ffmpeg
  (interface [extract-frame (fn [v: VideoPath] -> ImageBytes)])
  (capability sys.cpu 2-cores))
```

The wrapper maps unverified external code into the `llmll` type system and limits its capabilities. The AI does not implement the body — the compiler generates a foreign call stub.

---

## 8. Module System

```lisp
(module hangman
  (import wasi.io (capability stdin  :deterministic true))
  (import wasi.io (capability stdout :deterministic false))

  ;; Module body: type declarations, def-logic, def-interface, check, gen
  (type Word (where [s: string] (> (string-length s) 0)))

  (def-logic game-won? [state: GameState]
    (all-guessed? (state-word state) (state-guessed state))))
```

Modules declared in `llmll-hub` include verified proof metadata and are importable by name. Third-party modules must be explicitly wrapped (§7).

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
  (let [[log-cmd  (wasi.io.stderr "Request received")]
        [resp-cmd (wasi.http.response 200 "OK")]]
    (pair state (seq-commands log-cmd resp-cmd))))
```

`seq-commands` executes its arguments in order (left then right). It can be nested for three or more commands:

```lisp
(seq-commands cmd1 (seq-commands cmd2 cmd3))
```

### 9.4 Runtime Execution Loop

The `llmll` runtime (the WASM host) processes each `Command` as follows:

1. **Verify** permissions against the module's declared `capability` list. A command without a matching capability raises a `CapabilityError` and halts.
2. **Intercept** sensitive commands (e.g., `wasi.fs.delete`) for human/Lead-AI review if the module is running in guarded mode.
3. **Execute** the physical IO via the OS.
4. **Feed** the result (`Success` or `Error`) back as the next `Input` to the logic.

---

## 10. Compilation & Execution Pipeline

1. **AI Implementation:** LLM generates `.llmll` source (S-expressions).
2. **Semantic Check:** Compiler verifies types, immutability, and catalogs all `?holes`. Reports structured S-expression diagnostics.
3. **Human/Lead-AI Review:** Holes and sensitive `Command` types (e.g., `wasi.fs.delete`) are resolved/approved via Chat/CLI.
4. **Transpilation:** Validated `.llmll` is converted to **Rust**.
5. **Binary Generation:** `cargo build --target wasm32-wasi` produces the `.wasm` binary.
6. **Contract & Property Testing:** The test runner executes `pre`/`post` assertions and `check` blocks against the running WASM module. Failures are reported as structured S-expression diagnostics.
7. **Event-Log Replay:** The runtime records a sequenced Event Log of `(Input, CommandResult, captures)` triples (see §10a). Replay is bitwise deterministic for all modules that use `:deterministic true` capability flags on clock and PRNG imports.

> **v0.2:** Step 2 will include compile-time liquid-type checking via Z3.
> **Lean 4** integration is deferred to v0.3 and applies only to `?proof-required` holes.

---

## 10a. Event Log Specification

Correct replay is the foundation of fault tolerance, audit trails, and (in v0.2) SMT proof validation over execution traces.

### Sources of Non-Determinism in WASM

| Source | Problem | Runtime Fix |
|--------|---------|-------------|
| **IEEE 754 floats** | NaN canonicalization differs across host platforms | Require `wasm-determinism` extension; reject non-canonical floats at the WASM boundary |
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
| All non-deterministic capabilities use `:deterministic true` + WASM determinism extension active | ✅ **replayable** |
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

After any AST merge, the compiler runs Z3 verification of all declared invariants. A merge that breaks a global invariant is rejected before it can produce runnable code. _(Note: `def-invariant` verification requires v0.2 Z3 integration; in v0.1.1 invariants are stored and reported but not checked at compile time.)_

---

## 12. Formal Grammar Reference

The grammar is given in EBNF. `{ x }` means zero or more `x`. `[ x ]` means optional `x`. `( x | y )` means a choice. Terminals are in `"double quotes"`. All source files must be **ASCII-only**.

```ebnf
(* ============================================================ *)
(* Top-level structure                                           *)
(* ============================================================ *)
program     = { statement } ;
statement   = type-decl | gen-decl | def-logic | def-interface
            | def-invariant | module-decl | import | check | expr ;

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

literal     = INT | FLOAT | STRING | "true" | "false" ;
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
do-step     = "(" "<-" IDENT expr ")" | expr ;
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
   | "and" | "or" | "not" ;
```

### Grammar Key Rules

1. **No return-type annotation.** There is no `: ReturnType` after `[params]` in `def-logic`. Return types are always inferred.
2. **`check` requires exactly one `for-all`.** A bare boolean expression is not valid inside `check`.
3. **List literals do not exist.** Use `(list-empty)` and `(list-append list elem)` to build lists.
4. **`let` bindings are sequential.** Each binding sees all previous bindings. `(let [[x 1] [y (+ x 1)]] y)` is valid and evaluates to `2`.
5. **`match` must be exhaustive.** Use `_` as the final arm if not all cases are covered explicitly. A `match` without `_` that fails at runtime raises `MatchFailure`.
6. **`result` is reserved** inside `post` clauses. Do not use it as a variable or parameter name anywhere.
7. **Named parameters in `fn-type` are doc-only.** `(fn [raw: string] -> bytes[64])` and `(fn [string] -> bytes[64])` are type-equivalent.

---

## 13. Built-in Runtime Functions

These functions and operators are **always in scope**. They are provided by the LLMLL runtime and do not require a `capability` import, except for the command constructors in §13.9 which require the matching capability.

### 13.1 Arithmetic Operators

| Operator | Signature | Notes |
|----------|-----------|-------|
| `+` | `int int -> int` | Addition |
| `-` | `int int -> int` | Subtraction |
| `*` | `int int -> int` | Multiplication |
| `/` | `int int -> int` | Integer division; raises `DivisionByZero` if right operand is `0` |
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
| `pair` | `a b -> (a, b)` | Construct a 2-tuple |
| `first` | `(a, b) -> a` | First projection |
| `second` | `(a, b) -> b` | Second projection |

> **Pattern for records:** LLMLL v0.1.1 has no native record syntax. Use nested `pair` values and named accessor functions. A 4-field record uses 3 levels of nesting:
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
| `range` | `int int -> list[int]` | `(range from to)` produces `[from, from+1, ..., to-1]`. If `from >= to`, returns empty list. |

> **`range` example:**
> ```lisp
> (range 0 5)   ;; => list containing 0, 1, 2, 3, 4
> (range 3 3)   ;; => empty list
> (range 5 3)   ;; => empty list
> ```
>
> **List literals don't exist.** Build lists with `list-empty`, `list-append`, or `range`:
> ```lisp
> ;; Build [0, 1, 2, ..., n-1] for a word of length n
> (let [[n       (string-length word)]
>       [indices (range 0 n)]]
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

---

## 14. Version Roadmap

### v0.1.1 — Current Version

Closed all specification gaps found during real-world implementation. The spec is now sufficient to implement any program using only v0.1.1 primitives without workarounds.

| Area | Feature |
|------|---------|
| Type system | `Command` type formally defined; custom ADT sum types (`(type T (| Ctor t) ...)`) |
| Iteration | `range` built-in (`(range from to) -> list[int]`) |
| Grammar | `QualIdent` production; ARROW terminal with maximal-munch rule; exhaustive `match` spec; `=` polymorphism |
| Contracts | `result` keyword formally defined for `post` clauses |
| `let` | Sequential binding semantics (`let*`) formally specified |
| IO | Standard command constructor library in §13.9; `seq-commands` combinator |
| Interfaces | Named parameters in `fn-type` formally specified as doc-only |
| PBT | Rejection-sampling fallback for dependent types; `gen` declaration for custom generators |
| Concurrency | `def-invariant` syntax (verification deferred to v0.2) |

### v0.2 — Compile-Time Verification

| Area | Feature |
|------|---------|
| Type system | Liquid types: `{base \| predicate}` refinement syntax, Z3-backed compile-time checking |
| Constraint language | Quantifier-free linear arithmetic + regex — Z3 guaranteed to terminate |
| Inference | Compiler infers missing `pre`/`post` annotations from function bodies |
| `letrec` | Bounded recursion with mandatory `:decreases` termination annotation (Z3-verified) |
| `match` | Static exhaustiveness checking for ADT types |
| `def-invariant` | Z3-backed module invariant verification after every AST merge |
| Sequential IO | Monadic `do`-notation as surface syntax; desugars to `(State, Input) -> (NewState, Command)` |
| Syntax | JSON-AST accepted as alternate surface syntax; compiler round-trips both forms |

### v0.3 — Interactive Proofs

| Area | Feature |
|------|---------|
| Proof holes | `?proof-required` hole for predicates outside the liquid-type decidable fragment |
| Proof agent | Specialist Lean 4 proof-synthesis agent; receives AST node + constraint; returns verified proof term |
| Tactic library | Built-in proof tactics as S-expression macros (`prove-by-induction`, `prove-by-exhaustion`) |
| Trace proofs | SMT validation of `pre`/`post` over replayed Event Log traces (requires ✅ replayable modules) |
| `llmll-hub` | Curated skeleton library for `?scaffold`: `web-api-server`, `cli-tool`, `data-pipeline` |
