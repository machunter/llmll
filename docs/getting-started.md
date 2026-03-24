# LLMLL Getting Started — v0.2

> This document is the single reference for building and running LLMLL programs,
> understanding what patterns work in the current compiler, and the JSON-AST schema versioning policy.
> If you find contradictions between this file and older documentation, this file takes precedence.

---

## Part 1 — Build the Compiler

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------| 
| GHC + Stack | `ghc >= 9.4`, `stack >= 2.9` | Build compiler and generated Haskell code |

**Install Stack:** https://docs.haskellstack.org/en/stable/install_and_upgrade/

```bash
git clone <repo-url> llmll && cd llmll/compiler
stack build
stack exec llmll -- --help
```

Expected output:
```
llmll — AI-to-AI programming language compiler

Usage: llmll COMMAND [--json]

Available commands:
  check   Parse and type-check a .llmll or .ast.json file
  holes   List and classify all holes in a file
  test    Run property-based tests (check blocks)
  build   Compile source to a Haskell application
  hub     llmll-hub package registry (fetch, cache)
  repl    Start an interactive LLMLL REPL
```

---

## Part 2 — Compiler Commands

All commands run from the `compiler/` directory.

### `check` — parse and type-check

```bash
stack exec llmll -- check ../examples/withdraw.llmll
# ✅ ../examples/withdraw.llmll — OK (5 statements)

stack exec llmll -- --json check ../examples/withdraw.llmll
# {"diagnostics":[...],"phase":"typecheck","success":true}
```

### `holes` — inspect holes

```bash
stack exec llmll -- holes ../examples/hangman_json/hangman.ast.json
# examples/hangman_json/hangman.ast.json — 0 holes (0 blocking)
```

| Label | Meaning |
|-------|---------|
| `BLOCK` | Execution cannot proceed — must be filled |
| `AGENT` | Delegated to a specialist agent |
| `info`  | Non-blocking TODO |

### `test` — property-based tests

```bash
stack exec llmll -- test ../examples/hangman_json/hangman.ast.json
# 4 properties: ✅ Passed: 4  ❌ Failed: 0  ⚠️ Skipped: 0
```

Properties are skipped when they contain `Command`-producing expressions that cannot be statically evaluated.
The skip message names which case applies.

> [!IMPORTANT]
> **Stack lock deadlock** — same lock issue as `build`. Use `--emit-only` to generate the QuickCheck Haskell without running `stack test`:
> ```bash
> stack exec llmll -- test hangman.ast.json --emit-only
> #    src/Lib.hs -- 8803 chars
> #    (stack test skipped — --emit-only)
> ```

### `build` — generate Haskell

```bash
# S-expression source
stack exec llmll -- build ../examples/withdraw.llmll

# JSON-AST source (auto-detected by .json or .ast.json extension)
stack exec llmll -- build ../examples/hangman_json/hangman.ast.json -o ../generated/hangman_json
```

> [!IMPORTANT]
> **Stack lock deadlock** — if you have a long-running `stack exec llmll -- repl` terminal open, `llmll build` will deadlock because both try to hold the Stack project lock. Use `--emit-only` to skip the internal `stack build` and run it separately:
> ```bash
> # Step 1: write Haskell files only (no stack build)
> stack exec llmll -- build hangman.ast.json -o ../generated/hangman_json --emit-only
>
> # Step 2: build independently
> cd ../generated/hangman_json && stack build
> ```

Output layout:
```
generated/hangman_json/
  package.yaml     ← hpack descriptor
  stack.yaml       ← GHC 9.6.6 pin
  src/Lib.hs       ← all def-logic, types, builtins preamble
  src/Main.hs      ← runtime harness (only if def-main present)
```

```bash
cd generated/hangman_json && stack build && stack exec hangman
```

### `hub` — package registry

```bash
# Download a package into the local cache (~/.llmll/modules/)
llmll hub fetch llmll-crypto@0.1.0

# Cache layout after fetch:
# ~/.llmll/modules/llmll-crypto/0.1.0/
#   hash/bcrypt.ast.json
#   hash/bcrypt.llmll
```

Import fetched packages using the `hub.` prefix (see §4.8).

---

## Part 3 — JSON-AST Schema Versioning

Every `.ast.json` file must include `schemaVersion` at the top level:

```json
{
  "schemaVersion": "0.2.0",
  "llmll_version": "0.2.0",
  "statements": [ ... ]
}
```

The compiler rejects mismatched versions immediately. **Strict mode:** only the exact matching version is accepted.

> [!IMPORTANT]
> **Migrating from v0.1.3:** Files with `"schemaVersion": "0.1.3"` are **rejected** by the v0.2 compiler. The fix is a one-line update: change both `schemaVersion` and `llmll_version` from `"0.1.3"` to `"0.2.0"`. No other structural changes are required for files that do not use the new `open`/`export` nodes.

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Version of the JSON-AST schema shape — this is what the compiler gates on |
| `llmll_version` | Version of the LLMLL language used. Currently always equal to `schemaVersion` |

**Upgrade path:** bump `schemaVersion` in `docs/llmll-ast.schema.json`, update `expectedSchemaVersion` in `ParserJSON.hs`, re-emit fixtures.

**Round-trip guarantee:** `llmll build file.llmll --emit json-ast` then `llmll build file.ast.json` produces semantically identical output. Any divergence is a bug.

---

## Part 4 — Known-Good Patterns (v0.1.3.1)

These patterns work in the **current compiler**. Each shows what works today and what the old workaround was.

### 4.1 State Accessor Functions

```json
{ "kind": "def-logic", "name": "state-word",
  "params": [{ "name": "s", "param_type": { "kind": "primitive", "name": "string" } }],
  "body": { "kind": "app", "fn": "first", "args": [{ "kind": "var", "name": "s" }] } }
```

✅ **Works.** `first`/`second` accept any pair-like value regardless of annotation.

### 4.2 Type Aliases at Call Sites

```lisp
(type NonNeg (where [n: int] (>= n 0)))
(def-logic use-nonneg [x: NonNeg] x)
```

Passing `(use-nonneg 5)` is now valid — the type checker expands `NonNeg` to its base `int` before unification.

### 4.3 List Literals in JSON-AST

```json
{ "kind": "lit-list", "items": [
    { "kind": "lit-string", "value": " " },
    { "kind": "lit-string", "value": " " },
    { "kind": "lit-string", "value": " " }
]}
```

✅ Desugared by the parser to `foldr list-prepend (list-empty)`. Works for any length including `[]`.

### 4.4 Multi-Segment String Construction

```json
{ "kind": "app", "fn": "string-concat-many",
  "args": [{ "kind": "lit-list", "items": [c0, sep, c1, sep, c2] }] }
```

✅ `string-concat-many :: list[string] -> string` — concatenates without separator.

### 4.5 New Built-ins (since v0.1.3.1)

| Function | Signature | Notes |
|----------|-----------|-------|
| `string-trim` | `string → string` | Strip leading/trailing whitespace, `\t`, `\n`, `\r` |
| `string-concat-many` | `list[string] → string` | Concat list of strings |
| `list-nth` | `list[a] int → Result[a, string]` | Safe indexed access |

### 4.6 `def-main` Initialisation and Termination

```json
{ "kind": "def-main", "mode": "console",
  "init":    { "kind": "app", "fn": "start-game", "args": [] },
  "step":    { "kind": "var", "name": "game-loop" },
  "done?":   { "kind": "var", "name": "is-game-over?" },
  "on-done": { "kind": "var", "name": "show-result" } }
```

> [!IMPORTANT]
> `:init` must be a **zero-arg function call** `{ "kind": "app", "fn": "start-game", "args": [] }`, not `{ "kind": "var", "name": "start-game" }`.

> [!IMPORTANT]
> **`:on-done` is the canonical hook for end-of-game output.** If `game-loop` prints a win/loss message on the same turn the game ends, the board can render twice. Move all terminal output for the final state into a dedicated `show-result` function and declare it via `:on-done`. See `LLMLL.md §9.5` for the full before/after pattern.

### 4.7 Still Restricted in v0.2

| Feature | Status | Workaround |
|---------|--------|------------|
| `[acc: (int, string)]` in `typed-param` | ❌ Parse error | Use bare `[acc]` — scheduled for Phase 2c |
| `[...]` list literal as direct argument to a call inside an `if` branch (S-expression only) | ❌ Parse error | Extract to a `let` binding before the `if` (see note below) |
| `pre`/`post` compile-time verification | ⚠️ Runtime assert only | Correct at runtime; SMT proof in Phase 2b |

> [!WARNING]
> **S-expression `[...]` inside `if` branches — use `let` to hoist.**  
> The S-expression parser misreads `]` when a list literal appears as a function argument inside an `if` body:
> ```lisp
> ;; FAILS — parse error 'unexpected ]':
> (if won
>     (wasi.io.stdout (string-concat-many ["You won! " word "\n"]))
>     ...)
>
> ;; WORKS — hoist the list into a let binding first:
> (let [(msg (string-concat-many ["You won! " word "\n"]))]
>   (if won (wasi.io.stdout msg) ...))
> ```
> This restriction does not apply to JSON-AST (`{"kind": "lit-list", ...}` is always unambiguous). Bug tracked as **B3** in `compiler-team-roadmap.md`.

---

### 4.8 Common Agent Mistakes

| Mistake | Effect | Correct form |
|---------|--------|--------------|
| `def-main` field `"done"` instead of `"done?"` | Silently ignored by JSON parsers; game never terminates | `"done?"` (with `?`) |
| `def-main` field `"onDone"` or `"on_done"` | Silently ignored | `"on-done"` (with hyphen) |
| `"isDone"` instead of `"done?"` | Silently ignored | `"done?"` |
| `:init` as `{ "kind": "var", "name": "start-game" }` | Passes the function, not its result | Must be `{ "kind": "app", "fn": "start-game", "args": [] }` |
| `[...]` list literal as direct argument inside S-expression `if` branch | Parse error: `unexpected ]` | Hoist into a `let` binding before the `if` (see §4.7) |
| `import` after `def-logic` inside `(module ...)` | Import silently ignored; unknown function at call site | All `import` statements must come before any `def-logic` |

> [!IMPORTANT]
> **`(module ...)` block — import ordering.** Inside a `(module ...)` wrapper, all `import` statements must appear **before** any `def-logic`, `type`, or `def-interface` statements. The parser reads imports in a first-pass and will silently ignore imports placed after definitions, causing unexpected "unknown function" errors at the call site. This ordering rule applies to both single-file and multi-file programs.
>
> ```lisp
> ;; CORRECT — imports first:
> (module my-app
>   (import wasi.io stdout)
>   (import haskell.aeson Data.Aeson)
>   (def-logic greet [name: string] (wasi.io.stdout name)))
>
> ;; WRONG — import after def-logic is ignored:
> (module my-app
>   (def-logic greet [name: string] (wasi.io.stdout name))
>   (import wasi.io stdout))   ;; ← ignored, wasi.io.stdout unknown
> ```

---

### 4.8 Multi-File Modules: `open`, `export`, and `hub` (v0.2)

Phase 2a ships real multi-file compilation. Use these patterns when authoring or consuming multi-module programs.

#### Prefixed access (default)

When `app.main` imports `app.auth`, all exported names from `app.auth` are accessible with the full qualified path — no extra declaration needed:

```lisp
(module app.main
  (import app.auth))

;; Call the qualified name:
(app.auth.hash-password raw-str)
```

#### `open` — pull names into local scope

```lisp
;; Bring ALL exports from app.auth into scope as bare names:
(open app.auth)
(hash-password raw-str)   ;; no prefix needed

;; Selective — only hash-password is unprefixed; others still need prefix:
(open app.auth (hash-password))
```

> [!WARNING]
> **Open shadowing.** If two `(open ...)` declarations export the same name, the second wins (last wins, LISP-style). The compiler emits a `WARNING` diagnostic. Use prefixed access when two modules share a function name.

#### `export` — restrict what a module exposes

```lisp
;; Only hash-password and verify-token are visible to importers:
(export hash-password verify-token)

;; Omitting export entirely: all top-level defs are exported by default.
```

The `export` declaration must appear before the first `def-logic` — consistent with the "imports before defs" rule.

#### Hub imports

After fetching a package with `llmll hub fetch`, import it with the `hub.` prefix:

```lisp
(import hub.llmll-crypto.hash.bcrypt (interface [
  [bcrypt-hash   (fn [raw: string] -> bytes[64])]
  [bcrypt-verify (fn [raw: string hash: bytes[64]] -> bool)]
]))
```

The `hub.` prefix tells the resolver to search only `~/.llmll/modules/`, never the local source tree.

#### JSON-AST nodes for `open` and `export`

```json
{ "kind": "open",   "path": "app.auth", "names": ["hash-password"] }
{ "kind": "open",   "path": "app.auth" }
{ "kind": "export", "names": ["hash-password", "verify-token"] }
```

Omit `"names"` in an `open` node to bring all exports into scope.

---

## Part 5 — Core Language Quick Reference

```lisp
;; Dependent type (runtime-checked constraint)
(type Name (where [var: basetype] constraint-expr))

;; Pure function with contracts
(def-logic name [param: type ...]
  (pre  precondition-expr)      ;; optional
  (post postcondition-expr)     ;; optional — can reference `result`
  body-expr)

;; Let binding (sequential)
(let [(x expr1) (y expr2)] body)

;; If expression
(if cond then-expr else-expr)

;; Named hole
?my_hole_name

;; Property-based test
(check "description"
  (for-all [param: type ...]
    property-expr))

;; Entry point
(def-main :mode console :init (start-game) :step game-loop)
```

> Unicode aliases are supported since v0.1.1: `→` `≥` `≤` `≠` `∧` `∨` `¬` `∀` `λ`
