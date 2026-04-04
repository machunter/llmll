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
| `fixpoint` + `z3` | any stable | **Optional** (Phase 2b `verify` command only): `stack install liquid-fixpoint` then `brew install z3` |

**Install Stack:** <https://docs.haskellstack.org/en/stable/install_and_upgrade/>

```bash
git clone <repo-url> llmll && cd llmll/compiler
stack build
stack exec llmll -- --help
```

Expected output:

```bash
llmll — AI-to-AI programming language compiler

Usage: llmll COMMAND [--json]

Available commands:
  check   Parse and type-check a .llmll or .ast.json file
  holes   List and classify all holes in a file
  test    Run property-based tests (check blocks)
  build   Compile source to a Haskell application
  verify  Emit .fq constraints and run liquid-fixpoint (Phase 2b)
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
| ------- | --------- |
| `BLOCK` | Execution cannot proceed — must be filled |
| `AGENT` | Delegated to a specialist agent |
| `info` | Non-blocking TODO |

### `test` — property-based tests

```bash
stack exec llmll -- test ../examples/hangman_json/hangman.ast.json
# 4 properties: ✅ Passed: 4  ❌ Failed: 0  ⚠️ Skipped: 0
```

Properties are skipped when they contain `Command`-producing expressions that cannot be statically evaluated.
The skip message names which case applies.

> [!IMPORTANT]
> **Stack lock deadlock** — same lock issue as `build`. Use `--emit-only` to generate the QuickCheck Haskell without running `stack test`:
>
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
>
> ```bash
> # Step 1: write Haskell files only (no stack build)
> stack exec llmll -- build hangman.ast.json -o ../generated/hangman_json --emit-only
>
> # Step 2: build independently
> cd ../generated/hangman_json && stack build
> ```

Output layout:

```bash
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

### `verify` — liquid-fixpoint contract verification

```bash
# Verify linear arithmetic pre/post contracts at compile time:
stack exec llmll -- verify ../examples/hangman_sexp/hangman.llmll
#    .fq written to /tmp/hangman.fq
#    Running liquid-fixpoint ...
# ✅ hangman.llmll — SAFE (liquid-fixpoint)

# Emit .fq only, specify output path:
stack exec llmll -- verify file.llmll --fq-out out.fq

# JSON output:
stack exec llmll -- --json verify file.llmll
```

`verify` is **gracefully degrading**: if `fixpoint` or `z3` is not in `PATH`, it writes the `.fq` file and exits 0 with an install hint. The file can be checked manually or in CI once the tools are installed.

> [!IMPORTANT]
> `verify` covers the **linear arithmetic fragment** only (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`). Non-linear constraints (`*`, `/`, `mod`) in `pre`/`post` automatically emit `?proof-required(non-linear-contract)` holes (see §4.11) and are skipped by the solver without error.

### `typecheck --sketch` — partial-program type inference (Phase 2c)

```bash
stack exec llmll -- typecheck --sketch ../examples/sketch/if_hole.ast.json
# {
#   "holes": [ { "name": "?handler", "inferredType": "Command", "pointer": "/statements/2/body/else" } ],
#   "errors": []
# }
```

Accepts a partial LLMLL program with holes anywhere. Returns:

- `holes[]` — each `?hole`'s inferred type (or `null` if indeterminate) and its RFC 6901 JSON Pointer
- `errors[]` — type errors detectable even with holes present, each annotated with `holeSensitive: bool`

`holeSensitive: true` means the error may disappear once holes are filled — fix `holeSensitive: false` errors first.

### `serve` — HTTP sketch endpoint (Phase 2c)

```bash
# Start on default localhost:7777
stack exec llmll -- serve

# Custom host/port/token
stack exec llmll -- serve --host 0.0.0.0 --port 8888 --token my-secret

# Query from an agent
curl -s -X POST localhost:7777/sketch \
     -H "Content-Type: application/json" \
     -d @partial.ast.json | jq '.holes'
```

Every `POST /sketch` is **stateless** — a fresh type-check context per request. Safe for concurrent agent use with no locking. TLS is handled by a reverse proxy (nginx/Caddy); `llmll serve` binds plaintext only.

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
| -------- | --------- | ----- |
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

### 4.7 Known Restrictions (v0.2 fully shipped)

| Feature | Status | Notes |
| ------- | ------ | ----- |
| `[...]` list literal as direct argument inside S-expression `if` branch | ❌ Parse error | Hoist into a `let` binding before the `if` (workaround below) |
| `pre`/`post` **linear** contracts | ✅ Verified at compile time via `llmll verify` | — |
| `pre`/`post` **non-linear** contracts (`*`, `/`, `mod`) | ⚠️ Emits `?proof-required` hole; runtime assert still active | v0.3 |

> [!WARNING]
> **S-expression `[...]` inside `if` branches — use `let` to hoist.**  
> The S-expression parser misreads `]` when a list literal appears as a function argument inside an `if` body:
>
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
>
> This restriction does not apply to JSON-AST (`{"kind": "lit-list", ...}` is always unambiguous). Bug tracked as **B3** in `compiler-team-roadmap.md`.

---

### 4.8 Common Agent Mistakes

| Mistake | Effect | Correct form |
| ------- | ------ | ------------ |
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

;; Call the exported function with its qualified name:
(app.auth.hash-password raw-str)
```

> [!IMPORTANT]
> **Phase 2a codegen limitation — use bare names at call sites.**
> Qualified access (`module.fn`) is *accepted by the type-checker and resolver*, but
> Phase 2a codegen merges all modules into a single flat `Lib.hs` with bare Haskell
> identifiers. A call written as `(world.make-world ...)` becomes `world_make_world`
> in the generated Haskell, which **does not exist** — GHC will error with
> `Variable not in scope: world_make_world`.
>
> **Rule for Phase 2a:** always use **bare function names** at call sites, even for
> functions imported from other modules. The `(import world)` statement is still
> required (it triggers module loading and merging); only call sites must be bare.
>
> ```lisp
> ;; ✅ correct in Phase 2a:
> (import world)
> (make-world 20 10)
>
> ;; ❌ wrong — produces undefined Haskell identifier:
> (world.make-world 20 10)
> ```
>
> Per-module Haskell output (so `world.make-world` compiles correctly) is planned for Phase 2b.

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

#### ⚠️ Phase 2a Limitation: module search root is anchored to the **entry-point** file

> [!WARNING]
> **All `import` paths are resolved relative to the directory of the file you pass to `llmll check` / `llmll build` (the entry-point), not relative to the file that contains the `import` statement.**
>
> This means sub-modules can import sibling sub-modules correctly only when they all live **in the same directory as the entry-point**, or in a flat peer layout.
>
> **What works:**
>
> ```text
> examples/life_json/
>   main.ast.json       ← entry-point: llmll check main.ast.json
>   world.ast.json      ← (import world)   → resolved to ./world.ast.json ✅
>   core.ast.json       ← (import core)    → resolved to ./core.ast.json  ✅
> ```
>
> **What does NOT work in Phase 2a:**
>
> ```text
> examples/life_json/
>   main.ast.json       ← entry-point
>   life/
>     world.ast.json    ← (import life.core) → searched in examples/life_json/
>     core.ast.json     ← found ✅, but world.ast.json's own imports...
>       ↑   world.ast.json then tries (import life.core)
>           → resolved to examples/life_json/life/core.ast.json ✅ first time,
>             but if world.ast.json's dir ≠ srcRoot, a second-level import
>             from world.ast.json resolves against the entry-point root,
>             not world's directory — so relative sibling imports inside
>             life/ break unless life/ = the entry-point directory.
> ```
>
> **Recommended layout for Phase 2a:** keep all module files at the **same directory level** as the entry-point. Use single-segment import names (`import core`, `import world`).
>
> A `--lib <dir>` flag that adds extra search roots is planned for Phase 2b.

---

### §4.10 `letrec` — Recursive Functions with Termination Measures

Use `letrec` (not `def-logic`) for any self-recursive function. The `:decreases` measure is required — the compiler uses it to verify termination.

```lisp
;; Simple variable measure — verified automatically by llmll verify:
(letrec countdown [n: int] :decreases n
  (if (= n 0) 0 (countdown (- n 1))))

;; With pre/post contracts:
(letrec list-sum [xs: list[int]] :decreases (list-length xs)
  (pre  (>= (list-length xs) 0))
  (post (>= result 0))\n  (if (list-empty? xs) 0 (+ (list-head xs) (list-sum (list-tail xs)))))
```

JSON-AST:

```json
{ "kind": "letrec",
  "name": "countdown",
  "params": [{ "name": "n", "param_type": { "kind": "primitive", "name": "int" } }],
  "decreases": { "kind": "var", "name": "n" },
  "body": { "kind": "if", "..." : "..." } }
```

> [!IMPORTANT]
> A **simple variable** measure (`:decreases n`) is verified by `llmll verify`. A **complex expression** (`:decreases (- n 1)`) emits a `?proof-required(complex-decreases)` hole — non-blocking, but the solver skips that function.

> [!WARNING]
> Using `def-logic` for a self-recursive function emits a self-recursion warning. `letrec` is the correct verified form.

---

### §4.11 `?proof-required` Holes

The compiler auto-emits `?proof-required` holes for constraints outside the decidable linear arithmetic fragment. These holes are **non-blocking**: code compiles with a runtime assertion fallback.

| Hole | Emitted when | Blocking? |
|------|-------------|-----------|
| `?proof-required(complex-decreases)` | `letrec :decreases` is a non-variable expression | No |
| `?proof-required(non-linear-contract)` | `pre`/`post` contains `*`, `/`, `mod`, `^` | No |

**Manual annotation** (S-expression):

```lisp
?proof-required    ;; skip this expression in the verifier
```

**JSON-AST node:**

```json
{ "kind": "hole-proof-required", "reason": "non-linear-contract" }
```

`llmll holes --json` reports all `?proof-required` holes. `llmll verify` skips them without error and lists skipped function names.

---

### §4.9 String Escape Sequences by Format

S-expression (`.llmll`) and JSON-AST (`.ast.json`) files use different string escape rules. Mixing them up is a common source of parse errors.

| Escape | JSON-AST | S-expression (v0.2+) |
| ------ | -------- | -------------------- |
| `\n` newline | ✅ | ✅ |
| `\t` tab | ✅ | ✅ |
| `\r` CR | ✅ | ✅ |
| `\\` backslash | ✅ | ✅ |
| `\"` quote | ✅ | ✅ |
| `\uXXXX` Unicode | ✅ | ✅ added v0.2 |
| `\xNN` hex | ❌ not valid JSON | ❌ not supported |

**JSON-AST:** follows RFC 8259. Use `\uXXXX` for control characters:

```json
{ "kind": "lit-string", "value": "\u001b[2J\u001b[H" }  // ✅ VT100 clear-screen
{ "kind": "lit-string", "value": "\x1b[2J\x1b[H" }    // ❌ \x1b not valid JSON
```

The compiler emits a hint when it detects the `\x1b` pattern:

```
:hint "JSON strings must use \\uXXXX for control/non-ASCII chars (e.g. \\u001b not \\x1b)"
```

**S-expression:** uses Haskell-style escapes. `\uXXXX` is now also supported (v0.2):

```lisp
(def-logic clear-screen [] "\u001b[2J\u001b[H")  ;; ✅ works in v0.2
```

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
