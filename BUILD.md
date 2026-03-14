# Building and Running LLMLL Programs

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| GHC + Stack | `ghc >= 9.4`, `stack >= 2.9` | Haskell compiler toolchain |
| Rust + Cargo | `>= 1.70` | Compile generated Rust code |
| wasm-pack *(optional)* | `>= 0.12` | Compile to WebAssembly |

**Install Stack:** https://docs.haskellstack.org/en/stable/install_and_upgrade/  
**Install Rust:** `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`  
**Install wasm-pack:** `curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh`

---

## 1.  Build the LLMLL Compiler

```bash
git clone <repo-url> llmll && cd llmll/compiler
stack build
```

Verify it works:

```bash
stack exec llmll -- --help
```

Expected output:
```
llmll — AI-to-AI programming language compiler

Usage: llmll COMMAND [--json]

Available commands:
  check   Parse and type-check a .llmll file
  holes   List and classify all holes in a .llmll file
  test    Run property-based tests (check blocks)
  build   Compile .llmll to Rust; optionally invoke wasm-pack
  repl    Start an interactive LLMLL REPL
```

---

## 2.  Write an LLMLL Program

LLMLL uses S-expression syntax (Lisp-style). This guide uses two examples:

| File | Description |
|------|-------------|
| [`examples/hangman.llmll`](examples/hangman.llmll) | Annotated draft with holes — shows the language iteratively |
| [`examples/hangman_complete.llmll`](examples/hangman_complete.llmll) | Complete v0.1.1 implementation — run this end-to-end |

### 2.1  Dependent types

Dependent types let you attach a logical constraint to a primitive type. The runtime checks the constraint before passing the value to your logic.

```lisp
;; A non-empty string (the secret word).
(type Word   (where [s: string] (> (string-length s) 0)))

;; Exactly one character (the player's current guess).
(type Letter (where [s: string] (= (string-length s) 1)))

;; A non-negative integer (wrong-count or max-wrong).
(type GuessCount (where [n: int] (>= n 0)))
```

### 2.2  Game state as nested pairs

LLMLL v0.1 has no record syntax. We encode the game state as nested `pair` values and expose named accessors:

```lisp
;; State = (word, (guessed-letters, (wrong-count, max-wrong)))
(def-logic make-state
    [word: Word guessed: list[Letter] wrong: GuessCount max-w: GuessCount]
  (post (= result result))          ;; trivial but required for hygiene
  (pair word (pair guessed (pair wrong max-w))))

(def-logic state-word    [s: string] (first s))
(def-logic state-guessed [s: string] (first (second s)))
(def-logic state-wrong   [s: string] (first (second (second s))))
(def-logic state-max     [s: string] (second (second (second s))))
```

### 2.3  Contracts on business logic

`pre` and `post` are runtime-checked assertions. They make the contract between caller and implementation machine-verifiable:

```lisp
;; The main state transition.
(def-logic guess
    [state: string l: Letter]

  ;; Pre-condition: the game must still be in progress.
  (pre
    (and (< (state-wrong state) (state-max state))
         (not (all-guessed? (state-word state) (state-guessed state)))))

  ;; Post-condition: a guess can ONLY increase (or maintain) wrong-count.
  (post (>= (state-wrong result) (state-wrong state)))

  ?guess_impl)    ;; implementation deferred — filled by a specialist agent
```

### 2.4  Holes

A `?name` is a **Hole** — a named placeholder for logic that has not been written yet. The compiler can still:

- **type-check** the surrounding code,
- **report** how many holes remain,
- and **generate Rust stubs** with `todo!()` in their place.

```lisp
(def-logic all-guessed? [word: Word guessed: list[Letter]]
  ?all_guessed_impl)          ;; deferred: needs character iteration
```

### 2.5  Property-based tests

```lisp
;; Every check block must contain a (for-all ...) clause.
;; The PBT engine generates 100 random samples per property.

(check "Addition is commutative"
  (for-all [a: int b: int]
    (= (+ a b) (+ b a))))

(check "Wrong count increment is commutative"
  (for-all [w: int]
    (= (+ w 1) (+ 1 w))))
```

> **Syntax rules for check blocks**
> - Must contain `(for-all [typed-params...] expr)`.
> - A bare expression like `(= (+ 0 1) 1)` is **not** valid inside `check`.
> - List literals like `["a", "b"]` are **not** valid expressions in v0.1 — use `(list-empty)` or pass lists through function parameters.

---

## 3.  Run the Compiler

All commands are run from the `compiler/` directory.

### 3.1  `check` — parse and type-check

```bash
stack exec llmll -- check ../examples/hangman.llmll
```

```
✅ ../examples/hangman.llmll — OK (18 statements)
```

With `--json` for machine consumption (e.g. CI pipelines):

```bash
stack exec llmll -- --json check ../examples/hangman.llmll
```

```json
{"diagnostics":[{"message":"unresolved named hole","severity":"warning"}, ...],"phase":"typecheck","success":true}
```

### 3.2  `holes` — inspect all holes

```bash
stack exec llmll -- holes ../examples/hangman.llmll
```

```
../examples/hangman.llmll — 3 holes (0 blocking)
  [ info] ?display_word_impl in def-logic display-word
  [ info] ?all_guessed_impl in def-logic all-guessed?
  [ info] ?guess_impl in def-logic guess
```

Holes are classified as:
| Label | Meaning |
|-------|---------|
| `BLOCK` | Execution cannot proceed — must be filled first |
| `AGENT` | Delegated to a specialist agent |
| `info`  | Non-blocking — code can run, hole is a TODO |

### 3.3  `test` — run property-based tests

```bash
stack exec llmll -- test ../examples/hangman.llmll
```

```
../examples/hangman.llmll — 4 properties
  ✅ Passed:  4
  ❌ Failed:  0
  ⚠️  Skipped: 0
```

Properties are skipped when they contain runtime-only expressions (e.g. calls to hole-bodied functions) that cannot be symbolically evaluated.

### 3.4  `build` — generate Rust

```bash
stack exec llmll -- build ../examples/hangman.llmll
```

```
✅ Generated Rust crate: generated/hangman
   src/lib.rs — 4989 chars
   ℹ️  pass --wasm to compile to WebAssembly (requires wasm-pack)
```

Custom output directory:

```bash
stack exec llmll -- build ../examples/hangman.llmll -o /path/to/my/project
```

Compile to WebAssembly (requires `wasm-pack`):

```bash
stack exec llmll -- build ../examples/hangman.llmll --wasm
```

### 3.5  `repl` — interactive mode

```bash
stack exec llmll -- repl
```

```
LLMLL REPL v0.1 — type :help for commands, :quit to exit
llmll> :check ../examples/hangman.llmll
✅ ../examples/hangman.llmll — OK (18 statements)
llmll> :holes ../examples/hangman.llmll
../examples/hangman.llmll — 3 holes (0 blocking)
llmll> (+ 1 2)
EApp "+" [ELit (LitInt 1),ELit (LitInt 2)]
llmll> :quit
Goodbye.
```

---

## 3b. Compiling `hangman_complete.llmll` (v0.1.1 — all holes filled)

All commands are run from the `compiler/` directory.

### check — parse + type-check

```bash
stack exec llmll -- check ../examples/hangman_complete.llmll
```

```
✅ ../examples/hangman_complete.llmll — OK (29 statements)
```

*(Type-check warnings about built-in functions like `string-length`, `range`, `list-map` are expected — v0.1 type-checker does not model the standard library.)*

### holes — confirm all holes are filled

```bash
stack exec llmll -- holes ../examples/hangman_complete.llmll
```

```
../examples/hangman_complete.llmll — 0 holes (0 blocking)
```

### test — run property-based tests

```bash
stack exec llmll -- test ../examples/hangman_complete.llmll
```

```
../examples/hangman_complete.llmll — 9 properties
  ✅ Passed:  3
  ❌ Failed:  0
  ⚠️  Skipped: 6
```

6 properties are skipped because they reference custom types (`Word`, `Letter`, `GuessCount`) whose PBT generators are not yet wired to the Haskell runtime (the `gen` declaration registers them at WASM runtime only in v0.1.1). The 3 algebraic properties pass unconditionally.

### build — generate Rust crate

```bash
stack exec llmll -- build ../examples/hangman_complete.llmll -o ../generated/hangman
```

```
✅ Generated Rust crate: ../generated/hangman
   src/lib.rs — 12845 chars
   ℹ️  pass --wasm to compile to WebAssembly (requires wasm-pack)
```

The generated crate is at `generated/hangman/`. The compiler generates the core logic as a library in `src/lib.rs`. To run the game interactively in your terminal, simply add a `src/main.rs` that drives the game loop, and run:

```bash
# From the project root:
cd generated/hangman
cargo build
cargo run
```

### (optional) build to WebAssembly

```bash
# From compiler/:
stack exec llmll -- build ../examples/hangman_complete.llmll -o ../generated/hangman --wasm
```

This invokes `wasm-pack build --target web --release` and writes the WASM bundle to `generated/hangman/pkg/`.

---

## 4.  Generated Rust Crate

The `build` command writes two files:

```
generated/hangman/
  Cargo.toml       ← ready to compile with cargo
  src/lib.rs       ← pure Rust translation of your LLMLL logic
```

The generated code includes:
- **`LlmllVal` Runtime** a comprehensive dynamic runtime handling all LLMLL types and values.
- **Logic functions** with `assert!()` guards for pre/post contracts
- **Hole stubs** that compile but panic at runtime: `todo!("?guess_impl")`
- **A `#[cfg(test)]` module** with proptest-style stubs for each `check` block

To compile the generated Rust:

```bash
cd generated/hangman
cargo build
cargo test
```

---

## 5.  Syntax Quick Reference

```lisp
;; Dependent type
(type Name (where [var: basetype] constraint-expr))

;; Pure function with contracts
(def-logic name [param: type ...]
  (pre  precondition-expr)     ;; optional
  (post postcondition-expr)    ;; optional — can reference `result`
  body-expr)

;; Let binding  — each binding is its own [name expr] pair
(let [[x (expr1)]
      [y (expr2)]]
  body)

;; If expression
(if cond then-expr else-expr)

;; Named hole
?my_hole_name

;; Property-based test
(check "description"
  (for-all [param: type ...]
    property-expr))

;; Interface declaration (IO boundary)
(def-interface Name
  [fn-name (fn [arg-types...] -> ret-type)]
  ...)
```

> **Important gotchas in v0.1.1**
> - No list literal syntax (`["a"]` is invalid as an expression; use `(list-empty)` / `(list-append ...)` to build lists).
> - `check` always requires `(for-all ...)` — bare expressions aren't valid.
> - `def-logic` does not support `: ReturnType` annotations; return types are inferred.
> - **Unicode symbol aliases ARE supported** since v0.1.1: `→` `≥` `≤` `≠` `∧` `∨` `¬` `∀` `λ` are valid aliases for their ASCII counterparts. Unicode *identifiers* remain forbidden (see `analysis/unicode_decision.md`).
> - `gen TypeName expr` declares a custom PBT generator (v0.1.1 §5.2). The expression wires into the WASM runtime; Haskell-side PBT in `stack test` skips properties that reference custom-typed generators.
