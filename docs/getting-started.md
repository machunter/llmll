# LLMLL Getting Started — v0.4.0

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
  check      Parse and type-check a .llmll or .ast.json file
  holes      List and classify all holes in a file
  test       Run property-based tests (check blocks)
  build      Compile source to a Haskell application
  verify     Emit .fq constraints, run liquid-fixpoint, trust report (Phase 2b+)
  spec       Emit the agent prompt specification from builtinEnv (v0.3.4)
  typecheck  Type inference (use --sketch for partial programs)
  serve      HTTP sketch endpoint for agent swarms
  checkout   Lock a hole for exclusive agent editing (v0.3; context-aware in v0.3.5)
  patch      Apply an RFC 6902 JSON-Patch to a checked-out hole (v0.3)
  hub        llmll-hub package registry (fetch, scaffold)
  replay     Deterministic replay from event log (v0.3.1)
  repl       Start an interactive LLMLL REPL
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

#### `--deps` — dependency graph (v0.3.3)

Add `--deps` to `--json` output to include a dependency graph between holes.
The orchestrator uses this for topological sorting and parallel scheduling.

```bash
stack exec llmll -- --json holes --deps program.llmll
```

Each hole entry gains two additional fields:

```json
{
  "pointer": "/statements/2/body",
  "kind": "delegate",
  "agent": "@crypto-agent",
  "depends_on": [
    { "pointer": "/statements/0/body",
      "via": "hash-password",
      "reason": "calls-hole-body" }
  ],
  "cycle_warning": false
}
```

- `depends_on`: annotated edges — which holes this hole depends on, why, and via which function
- `cycle_warning`: `true` if this hole was in a broken dependency cycle (mutual recursion)

Only `AgentTask` and `Blocking` body-level holes participate in the graph.
`?proof-required` holes and contract-position holes (`pre`/`post`) are excluded.

#### `--deps-out FILE` — persist dependency graph

```bash
stack exec llmll -- --json holes --deps --deps-out deps.json program.llmll
```

Writes the full JSON output (with dependency data) to `deps.json`. Implies `--deps`.

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

```bash
# Scaffold a new project from a hub skeleton template
llmll hub scaffold web-api-server --output ./my-project

# Template cache: ~/.llmll/templates/
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

# v0.3.1: Run Leanstral proof pipeline on ?proof-required holes (mock mode):
stack exec llmll -- verify file.llmll --leanstral-mock
# Runs liquid-fixpoint first, then scans for ?proof-required holes,
# translates to Lean 4 obligations, resolves via mock prover,
# caches results in .proof-cache.json.

# v0.3.1: Leanstral with custom command and timeout:
stack exec llmll -- verify file.llmll --leanstral-cmd /path/to/lean-lsp-mcp --leanstral-timeout 60

# v0.3.2: Trust report — transitive trust closure with epistemic drift detection:
stack exec llmll -- verify file.llmll --trust-report
# Trust Report
# ────────────────────────────────────────────────────────────
#   withdraw:
#     pre: proven (liquid-fixpoint)  |  post: proven (liquid-fixpoint)
#     ↳ calls auth.verify-token (pre: —, post: asserted)
#     ⚠ withdraw is proven, but depends on auth.verify-token which is asserted
# ────────────────────────────────────────────────────────────
# Summary:
#   proven: 3  tested: 1  asserted: 2  no contract: 5
#   ⚠ epistemic drifts: 1

# JSON trust report (for tooling consumption):
stack exec llmll -- verify file.llmll --trust-report --json

# v0.3.5: Weakness check — detect specs that admit trivial implementations:
stack exec llmll -- verify file.llmll --weakness-check
# ✅ hangman.llmll — SAFE (liquid-fixpoint)
# ⚠ Spec weakness detected for `sort-list`:
#   Your contract: (post (= (list-length result) (list-length input)))
#   Trivial valid implementation: (def-logic sort-list [input: list[int]] input)
#   Consider strengthening the postcondition.
```

`--weakness-check` runs **after** a SAFE verification result. For each contracted function, it constructs trivial bodies (identity, constant-zero, empty-string, `true`, empty-list) and checks whether they also satisfy the contract. If any trivial body passes, the spec is flagged as potentially weak. This is advisory — it does not affect the verification outcome.

#### Downstream obligation mining (v0.4.0)

When `llmll verify` reports UNSAFE at a cross-function boundary, the obligation miner extracts the unsatisfied constraint and suggests a postcondition strengthening on the callee:

```bash
stack exec llmll -- verify program.llmll
# ✗ Caller requires: uniqueIds(result)
#   Producer normalizeUsers does not guarantee this.
#   Candidate strengthening: postcondition uniqueIds(output)
```

This leverages existing `TrustReport.hs` transitive closure infrastructure and the new `ObligationMining.hs` module.

`verify` is **gracefully degrading**: if `fixpoint` or `z3` is not in `PATH`, it writes the `.fq` file and exits 0 with an install hint. The file can be checked manually or in CI once the tools are installed.

> [!IMPORTANT]
> `verify` covers the **linear arithmetic fragment** only (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`). Non-linear constraints (`*`, `/`, `mod`) in `pre`/`post` automatically emit `?proof-required(non-linear-contract)` holes (see §4.11) and are skipped by the solver without error. Use `--leanstral-mock` or `--leanstral-cmd` to resolve these holes via the Leanstral proof pipeline.

### `replay` — deterministic event log replay (v0.3.1)

```bash
# Run a console program — produces .event-log.jsonl automatically:
stack exec llmll -- build ../examples/event_log_test/event_log_test.llmll
cd event_log_test && stack exec event_log_test
# (interact with program — .event-log.jsonl written on exit)

# Replay: rebuild from source, feed logged inputs, compare outputs:
stack exec llmll -- replay ../examples/event_log_test/event_log_test.llmll event_log_test.event-log.jsonl
# Replay: 5/5 events matched
```

The replay command:
1. Parses the `.event-log.jsonl` file (JSONL — one JSON object per line)
2. Builds the program from source using the standard `build` pipeline
3. Feeds each logged input to the rebuilt program step-by-step
4. Compares actual output against logged output
5. Reports match count and any divergences with sequence numbers

> [!NOTE]
> Event logs are crash-safe: if the program is killed mid-run, the log is valid up to the last flushed line. Partial logs can be replayed.

### `typecheck --sketch` — partial-program type inference (Phase 2c)

```bash
stack exec llmll -- typecheck --sketch ../examples/sketch/if_hole.ast.json
# {
#   "holes": [ { "name": "?handler", "inferredType": "Command", "pointer": "/statements/2/body/else" } ],
#   "errors": []
# }
```

Accepts a partial LLMLL program with holes anywhere. Returns:

- `holes[]` — each `?hole`’s inferred type (or `null` if indeterminate) and its RFC 6901 JSON Pointer
- `errors[]` — type errors detectable even with holes present, each annotated with `holeSensitive: bool`
- `invariant_suggestions[]` (v0.4.0) — invariant suggestions from the pattern registry, keyed by `(type signature, function name pattern)`. Contains ≥5 patterns (list-preserving, sorted, round-trip, subset, idempotent).

`holeSensitive: true` means the error may disappear once holes are filled — fix `holeSensitive: false` errors first.

#### Invariant suggestions (v0.4.0)

When a function’s type signature matches a known pattern, `--sketch` emits invariant suggestions:

```bash
stack exec llmll -- typecheck --sketch program.ast.json
# {
#   "holes": [...],
#   "errors": [],
#   "invariant_suggestions": [
#     { "function": "sort-list",
#       "pattern": "list[a] → list[a]",
#       "suggestions": ["(= (list-length result) (list-length input))", "(sorted result)"] }
#   ]
# }
```

The pattern registry is stored as data (not code) — adding new patterns does not require recompilation. See `InvariantRegistry.hs` for the full pattern set.

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

### `checkout` — lock a hole for exclusive editing (v0.3; context-aware v0.3.5; CAP-1 v0.4.0)

```bash
# Lock a hole and get a checkout token (v0.3.5: includes typing context)
stack exec llmll -- checkout ../examples/delegate_demo/program.ast.json /statements/2/body
# {
#   "pointer": "/statements/2/body",
#   "hole_kind": "hole-delegate",
#   "token": "a1b2c3d4e5f6...",
#   "ttl": 3600,
#   "in_scope": [
#     { "name": "state", "type": "(int, string)", "source": "param" },
#     { "name": "input", "type": "string", "source": "param" }
#   ],
#   "expected_return_type": "(int, Command)",
#   "available_functions": [
#     { "name": "list-head", "params": [{"name": "p0", "type": "list[int]"}],
#       "returns": "Result[int, string]", "status": "builtin" }
#   ],
#   "type_definitions": [
#     { "name": "GameState", "kind": "alias", "base_type": "(string, (list[string], (int, int)))" }
#   ]
# }

# Check remaining TTL
stack exec llmll -- checkout --status ../examples/delegate_demo/program.ast.json a1b2c3d4e5f6...
# { "remaining_ttl": 3542 }

# Explicitly release a lock (don't wait for TTL expiry)
stack exec llmll -- checkout --release ../examples/delegate_demo/program.ast.json a1b2c3d4e5f6...
# { "released": true }
```

`checkout` validates that the RFC 6901 pointer targets a `hole-*` node in the JSON-AST. If the pointer targets a non-hole node but a descendant hole exists, the error includes a hint: `"did you mean /statements/2/body?"`. Pointers are normalized (EC-3): leading zeros in numeric segments are stripped (`/statements/02/body` → `/statements/2/body`).

Locks are per-file (`.llmll-lock.json` alongside the source) with a 1-hour TTL. Stale locks are auto-expired on any `checkout` or `patch` call.

**v0.3.5+ context-aware fields** (optional — present when the compiler has sketch data):

| Field | Content |
|-------|---------|
| `in_scope` | Bindings visible at the hole site, with source provenance (`param`, `let-binding`, `match-arm`, `open-import`). Sorted by priority; truncated at 50 entries if scope is large (`scope_truncated: true`). |
| `expected_return_type` | The inferred return type at the hole site (τ). |
| `available_functions` | Non-`wasi.*` function signatures, monomorphized against concrete scope types (e.g., `list-head : list[int] → Result[int, string]` when `xs : list[int]` is in scope). |
| `type_definitions` | User-defined type aliases and sum types referenced by in-scope bindings. Depth-bounded expansion (max 5 levels) with cycle detection. |
| `scope_truncated` | `true` if the scope was truncated; absent or `false` otherwise. |

> [!IMPORTANT]
> `checkout` requires `.ast.json` input. S-expression sources are rejected with: `"checkout requires .ast.json input; run 'llmll build --emit json-ast' first"`.

### `patch` — apply an RFC 6902 JSON-Patch to a checked-out hole (v0.3)

```bash
stack exec llmll -- patch ../examples/delegate_demo/program.ast.json ../examples/delegate_demo/patch-request.json
# { "result": "PatchSuccess", "statements": 5 }
```

The patch request is a JSON envelope containing the checkout token and RFC 6902 operations:

```json
{
  "token": "a1b2c3d4e5f6...",
  "patch": [
    { "op": "test",    "path": "/statements/2/body", "value": { "kind": "hole-delegate", ... } },
    { "op": "replace", "path": "/statements/2/body", "value": { "kind": "lit-int", "value": 42 } }
  ]
}
```

Supported operations: `replace`, `add`, `remove`, `test`. The `test` op guards against stale patches. `move` and `copy` are not supported in v0.3 — use `remove` + `add` instead.

**Scope containment:** All patch operations must target nodes within the checked-out subtree. A token for `/statements/2/body` cannot mutate `/statements/0/body`.

**On success:** the updated `.ast.json` is written and the lock is cleared. **On failure:** the original file is unchanged, the lock is preserved for retry, and diagnostics reference the responsible patch operation (e.g., `patch-op/1/body`).

**HTTP endpoints** (via `llmll serve`): `POST /checkout`, `POST /checkout/release`, `POST /patch` — governed by the same bearer token auth as `POST /sketch`.

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

## Part 4 — Known-Good Patterns (Current Compiler)

These patterns work in the **current compiler**. Each shows what works today and what the old workaround was.

### 4.1 State Accessor Functions

```json
{ "kind": "def-logic", "name": "state-word",
  "params": [{ "name": "s", "param_type": { "kind": "primitive", "name": "string" } }],
  "body": { "kind": "app", "fn": "first", "args": [{ "kind": "var", "name": "s" }] } }
```

✅ **Works.** `first`/`second` accept any pair-like value regardless of annotation.

> [!NOTE]
> **v0.4.0 (U-Lite):** `first` and `second` are now properly typed as `TPair a b → a` and `TPair a b → b` respectively, with per-call-site type variable instantiation. The previous `TVar "p"` polymorphic hack is replaced by correct pair-type constraints. This means `first 42` is now a type error (correctly rejected). Existing pair-destructuring code is unaffected.

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
| `EPair` returning `TResult` approximation | ✅ **Fixed (v0.3 PR 1)** | `EPair` now correctly typed `TPair a b`; `match` on pairs no longer suggests `Success`/`Error` arms |

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
| Calling `wasi.io.stdout` without `(import wasi.io (capability ...))` | **v0.4.0 (CAP-1):** compile-time `missing-capability` error | Add `(import wasi.io (capability stdout))` before any `wasi.io.*` call |

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

### §4.12 Pair-Type JSON-AST Round-Trip (v0.3 PR 1)

Since PR 1, `llmll build --emit json-ast` on any program containing `(pair a b)` emits the correct `"pair-type"` node:

```json
{ "kind": "pair-type", "fst": { "kind": "primitive", "name": "int" }, "snd": { "kind": "primitive", "name": "string" } }
```

Previously, pair expressions were approximated as `"result-type"` in JSON-AST output. That approximation is gone. The schema `$def/TypePair` with `fst`/`snd` fields was already correct and required no change.

> [!IMPORTANT]
> If you have any tooling that post-processes `llmll build --emit json-ast` output and matches on `"kind": "result-type"` for pairs, update it to match `"kind": "pair-type"` instead. Programs that do **not** post-process the JSON-AST are unaffected.

---

### §4.13 do-notation JSON-AST Schema Migration (v0.3 PR 2)

Since PR 2, the JSON-AST schema for `do`-blocks uses a single, unified `"do-step"` node. The old separation of `"bind-step"` and `"expr-step"` is obsolete:

```json
// Named step (formerly bind-step)
{ "kind": "do-step", "name": "state1", "expr": { /* ... */ } }

// Anonymous step (formerly expr-step)
{ "kind": "do-step", "expr": { /* ... */ } }
```

> [!IMPORTANT]
> **Migrating from pre-PR2 do-blocks:** The JSON parser **rejects** old `"bind-step"` and `"expr-step"` kinds with a clear migration error. To update, rename your step `"kind"` to `"do-step"`. For named steps, keep the `"name"` property to capture the bound state.
> Furthermore, `llmll check` enforces state threading. Every step inside a `do`-block must return exactly `(S, Command)`, and the type `S` must be strictly identical across all steps. A mismatch produces a `"type-mismatch"` diagnostic.

### 4.14 Pair Destructuring in `let` Bindings (v0.3 PR 4)

The binding head of a `let` form can be a **pattern** instead of a simple name, enabling pair destructuring without a separate `match`:

```lisp
;; S-expression: (pair p1 p2) pattern in let binding
(def-logic use-pair [x: int]
  (let [((pair n msg) (make-pair x))]
    (string-concat msg (int-to-string n))))
```

Nested destructuring is supported:

```lisp
(def-logic use-nested [w: string g: int r: bool]
  (let [((pair word (pair count flag)) (make-triple w g r))]
    (if flag
      (string-concat word (int-to-string count))
      word)))
```

**JSON-AST:** Use `"pattern"` instead of `"name"` in the let-binding object. Both forms can appear in the same `"bindings"` array:

```json
{
  "kind": "let",
  "bindings": [
    { "name": "p", "expr": { "kind": "app", "fn": "make-pair", "args": [{"kind": "var", "name": "x"}] } },
    {
      "pattern": {
        "kind": "constructor", "constructor": "pair",
        "sub_patterns": [
          { "kind": "bind", "name": "n" },
          { "kind": "bind", "name": "msg" }
        ]
      },
      "expr": { "kind": "var", "name": "p" }
    }
  ],
  "body": { "kind": "var", "name": "n" }
}
```

> [!NOTE]
> Simple bindings (`"name"`) and pattern bindings (`"pattern"`) are mutually exclusive within a single binding object — the JSON parser enforces a strict `oneOf` on these two keys. Using both in the same object is a parse error.

---

### §4.15 Capability Enforcement (v0.4.0, CAP-1)

Since v0.4.0, calling a `wasi.*` function without a matching capability import is a **compile-time type error**. The check is in `inferExpr (EApp ...)` — it covers all nesting contexts: `let` RHS, `if` branches, `match` arms, `do` steps, and contract expressions.

```lisp
;; ✅ CORRECT — capability import present:
(module my-app
  (import wasi.io (capability stdout))
  (def-logic greet [name: string]
    (wasi.io.stdout (string-concat "Hello, " name))))

;; ❌ COMPILE ERROR — missing capability import:
(module my-app
  (def-logic greet [name: string]
    (wasi.io.stdout (string-concat "Hello, " name))))
;; Error: wasi.io.stdout requires (import wasi.io (capability ...))
```

**Non-transitive propagation:** If Module A imports `wasi.io` and Module B imports Module A, Module B must **also** declare `(import wasi.io (capability ...))` to call `wasi.io.*` functions directly. Calling them through a wrapper function from Module A is fine — only direct `wasi.*` calls are checked.

```lisp
;; Module B: also needs its own wasi.io import:
(module app.main
  (import app.auth)
  (import wasi.io (capability stdout))   ;; required even though app.auth has it
  (def-logic log-login [user: string]
    (wasi.io.stdout (string-concat "Login: " user))))
```

---

### §4.16 U-Lite Type Errors (v0.4.0)

U-Lite replaces the previous `compatibleWith (TVar _) _ = True` wildcard with substitution-based unification for concrete types. This catches several classes of type errors that were previously silently accepted.

**Examples of what now correctly errors:**

```lisp
;; ❌ list-head expects list[a], not int:
(list-head 42)
;; Error: type mismatch: expected list[a], got int

;; ❌ Element type mismatch caught by per-call-site substitution:
(list-map [1 2 3] (fn [x: string] x))
;; Error: type mismatch: list element type int ≠ string

;; ❌ first expects a pair, not a bare value:
(first 42)
;; Error: type mismatch: expected (a, b), got int
```

**Examples of correct usage:**

```lisp
;; ✅ first on a pair — infers type int:
(first (pair 1 "hello"))
;; type: int

;; ✅ Polymorphic builtins work across independent call sites:
(let [(x (list-head [1 2 3]))
      (y (list-head ["a" "b"]))]
  (pair x y))
;; x : Result[int, string], y : Result[string, string]
```

> [!NOTE]
> **Per-call-site scoping:** Each call to a polymorphic function gets its own fresh type variable instantiation. The substitution map does not escape the `EApp` boundary, so `list-head` on `list[int]` in one expression does not constrain `list-head` on `list[string]` elsewhere.

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
