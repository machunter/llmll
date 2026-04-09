# LLMLL Compiler Team Implementation Roadmap

> **Prepared by:** Compiler Team  
> **Date:** 2026-04-09  
> **Status:** Active — v0.3 PRs 1–3 shipped; PR 4 in progress  
> **Source documents:** `LLMLL.md` · `consolidated-proposals.md` · `proposal-haskell-target.md` · `analysis-leanstral.md` · `design-team-assessment.md` · `proposal-review-compiler-team.md`
>
> **Governing design criterion:** Every deliverable is evaluated against *one-shot correctness* — an AI agent writes a program once, the compiler accepts it, contracts verify, no iteration required.
>
> **Relationship to `LLMLL.md §14`:** The two documents are **complementary, not competing**. `LLMLL.md §14` is the *language-visible feature list* (what users and AI agents see). This document is the *engineering backlog* — implementation tickets, acceptance criteria, decision records, and bug tracking. When a feature ships it is marked complete here and the user-visible description is kept in `LLMLL.md §14`.

---

## Versioning Conventions

- Items marked **[CT]** are compiler team implementation tasks.
- Items marked **[SPEC]** are language specification changes that must land in `LLMLL.md` before or alongside the implementation.
- Items marked **[DESIGN]** are design decisions resolved by the joint team, recorded here as implementation constraints.

---

## v0.1.2 — Machine-First Foundation

**Theme:** Close the two highest-priority one-shot failure modes: structural invalidity (parentheses drift) and codegen semantic drift (Rust impedance mismatch). No new language semantics.

### Decision Record

| Decision | Resolution |
| -------- | ---------- |
| Primary AI interface | JSON-AST (S-expressions remain, human-facing only) |
| Codegen target | Switch from Rust to Haskell |
| Algebraic effects library | `effectful` — committed, not revisited |
| `Command` model | Move from opaque type to typed effect row (`Eff '[...]`) |
| Python FFI tier | Dropped from formal spec |
| Sandboxing | Docker + `seccomp-bpf` + `-XSafe` (WASM deferred to v0.4) |

---

### Deliverable 1 — JSON-AST Parser and Schema

> **One-shot impact:** Eliminates structural invalidity as a failure mode entirely.

**[CT]** `ParserJSON.hs` — new module. Ingests a `.ast.json` file validated against `docs/llmll-ast.schema.json` and produces the same `[Statement]` AST as `Parser.hs`. The two parsers must agree on every construct; any divergence is a bug.

**[CT]** `llmll build --emit json-ast` — round-trip flag. Compiles an `.llmll` source and emits the equivalent validated JSON-AST. Used for S-expression ↔ JSON conversion and regression testing.

**[CT]** JSON diagnostics — every compiler error becomes a JSON object with:

- `"kind"`: error class (e.g., `"type-mismatch"`, `"undefined-name"`)
- `"pointer"`: RFC 6901 JSON Pointer to the offending AST node
- `"message"`: human-readable description
- `"inferred-type"`: inferred type at the error site, if available

**[CT]** `llmll holes --json` — lists all unresolved `?` holes as a JSON array. Each entry includes: hole kind, inferred type, module path, agent target (for `?delegate`), and (in v0.2) `?proof-required` complexity hint.

**[CT]** Hole-density validator *(design team addition)* — a post-parse pass emitting a `WARNING` when a `def-logic` body is entirely a single `?name` hole. Threshold TBD; suggested starting value: warn when the hole-to-construct ratio across the entire body is 1.0. Nudges agents toward targeted holes rather than wholesale stubs.

**[CT]** Round-trip regression suite — every `.llmll` example in `examples/` is run through `s-expr → JSON → s-expr → compile` and asserted semantically equivalent. Must pass before v0.1.2 ships.

**[CT]** JSON Schema versioning — introduce `"schemaVersion"` field to `llmll-ast.schema.json`. The compiler rejects `.ast.json` files with an unrecognized version. Versioning policy documented in `docs/json-ast-versioning.md`.

**[SPEC]** Update `LLMLL.md §2` to document JSON-AST as a first-class source format.

**Acceptance criteria:**

- An LLM generating JSON against the schema cannot produce a structurally invalid LLMLL program.
- `llmll build` and `llmll build --from-json` produce identical binaries for all examples.
- `llmll holes --json` output is a valid JSON array parseable by `jq`.

#### Post-ship bug fixes (discovered via `examples/hangman/walkthrough.md`)

Three bugs were found by an AI developer during the Hangman JSON-AST implementation and fixed before v0.1.2 was considered complete:

| Bug | Location | Fix | Status |
| --- | -------- | --- | ------ |
| **P1** — `build-json` passes `hangman.ast` (with dot) as Cargo crate name; `cargo` rejects it immediately | `Main.hs`, `doBuildFromJson` | Strip `.ast` suffix from `rawName` **before** passing `modName` to `generateRust` | ✅ Fixed |
| **P2** — `builtinEnv` in `TypeCheck.hs` contained only 8 operator entries; all §13 stdlib calls (`string-length`, `list-map`, `first`, `second`, `range`, …) produced false-positive "unknown function" warnings, causing exit code 1 on every real program | `TypeCheck.hs`, `builtinEnv` | Seeded all ~25 §13 stdlib function signatures; polymorphic positions use `TVar "a"`/`TVar "b"` | ✅ Fixed |
| **P4** — `llmll test` always read the file as `Text` and called the S-expression parser regardless of extension; `test hangman.ast.json` silently produced a parse error | `Main.hs`, `doTest` | Replace inline `TIO.readFile` + `parseSrc` with `loadStatements json fp` (same dispatcher used by `check`, `holes`, `build`) | ✅ Fixed |

---

### Deliverable 2 — Haskell Codegen Target

> **One-shot impact:** Eliminates codegen semantic drift; makes v0.2 LiquidHaskell a 2-week integration instead of a 3-month Z3 binding project.

**[DESIGN — COMMITTED]** Effects library: `effectful`. Effect rows are type-visible in function signatures — AI agents can inspect what capabilities a function requires. This is a direct one-shot correctness gain, not merely an implementation preference.

**[DESIGN — COMMITTED]** `Command` becomes a typed effect row. A function calling `wasi.http.response` without declaring the HTTP capability is a **type error** in generated Haskell, caught at compile time. This closes the v0.1.1 gap where missing capability declarations were silently accepted.

**[CT]** Rename `Codegen.hs` → `CodegenHs.hs` (new module `LLMLL.CodegenHs`). Public symbol `generateRust` → `generateHaskell`; `CodegenResult` fields renamed (`cgRustSource` → `cgHsSource`, `cgCargoToml` → `cgPackageYaml`, etc.). Old `Codegen.hs` becomes a deprecated re-export shim; deleted in v0.2.

**[CT]** Generated file layout **(v0.1.2 — single-module)**:

> **Design decision:** For v0.1.2, all `def-logic`, type declarations, and interface definitions are emitted into a single `src/Lib.hs`. The multi-module split (`Logic.hs`, `Types.hs`, `Interfaces.hs`, `Capabilities.hs`) requires cross-module resolution and is deferred to v0.2 when the module system ships — tracked as a [CT] item in Phase 2c below.

| File | Contents |
| ---- | -------- |
| `src/Lib.hs` | All `def-logic` functions, type declarations, `def-interface` type classes, and §13 stdlib preamble |
| `src/Main.hs` | `def-main` harness (only if `SDefMain` present) |
| `src/FFI/<Name>.hs` | `foreign import ccall` stubs, generated on demand for `c.*` imports |
| `package.yaml` | hpack descriptor (replaces `Cargo.toml`) |

**[CT]** LLMLL construct → generated Haskell (normative mapping):

| LLMLL | Generated Haskell |
| ----- | ----------------- |
| `(def-logic f [x: int y: string] body)` | `f :: Int -> String -> <inferred>; f x y = body` |
| `(type T (\| A int) (\| B string))` | `data T = A Int \| B String deriving (Eq, Show)` |
| `Result[t,e]` | `Either e t` |
| `Promise[t]` | `IO t` (upgraded to `Async t` in v0.3) |
| `(def-interface I [m fn-type])` | `class I a where m :: fn-type` |
| `Command` (effect) | `Eff '[<capability-row>] r` |
| `(pre pred)` / `(post pred)` | LiquidHaskell `{-@ ... @-}` annotations (v0.2); runtime `assert` wrappers (v0.1.2) |
| `(check "..." (for-all [...] e))` | `QuickCheck.property $ \... -> e` |
| `(import haskell.aeson ...)` | `import Data.Aeson` — no stub |
| `(import c.libsodium ...)` | `foreign import ccall ...` in `src/FFI/Libsodium.hs` |
| `?name` hole | `error "hole: ?name"` + inline `{- HOLE -}` comment with inferred type |
| `?delegate @agent "..." -> T` | `error "delegate: @agent"` + JSON hole record in `llmll holes --json` |

**[CT]** Revised two-tier FFI (Python tier excluded from spec):

| Tier | Prefix | Mechanism | Stub? |
| ---- | ------ | --------- | ----- |
| 1 — Hackage | `haskell.*` | Regular `import`; added to `package.yaml` | No |
| 2 — C | `c.*` | `foreign import ccall`; GHC FFI template generated | Yes |

**[CT]** Sandboxing:

```bash
.llmll / .ast.json
     │  llmll build
     ▼
Generated .hs  {-# LANGUAGE Safe #-}
     │  GHC
     ▼
Native binary
     │
     ▼
Docker container
  ├── seccomp-bpf (syscall whitelist per declared capabilities)
  ├── Read-only filesystem (writable only at declared paths)
  ├── Network policy (declared URLs only)
  └── LLMLL host runtime (interprets Eff commands, enforces capability list)
```

**[CT]** WASM compatibility proof-of-concept — before merging `Codegen.hs`, compile the Hangman and Todo service generated `.hs` files with `ghc --target=wasm32-wasi`. Document results in `docs/wasm-compat-report.md`. Resolve any blockers before shipping. This validates that WASM remains on track for v0.4.

**[SPEC]** Update `LLMLL.md §7`, `§9`, `§10`, `§14` to reflect Haskell target, typed effect row, and Docker sandbox. Add explicit language to `§14`: *"WASM-WASI is the primary long-term deployment target. Docker + seccomp-bpf is the v0.1.2–v0.3 sandbox. WASM is deferred to v0.4, not abandoned."*

**Acceptance criteria:**

- `llmll build examples/hangman.llmll` produces a runnable GHC binary that passes all `check` blocks.
- A function calling `wasi.http.response` without the HTTP capability import produces a type error.
- The WASM proof-of-concept report shows no structural blockers.

---

### Deliverable 3 — Minimal Surface Syntax Fixes

> **One-shot impact:** Low — AI agents use JSON-AST. Fixes human ergonomics for test authors.

**[SPEC]** and **[CT]**:

| Current | Fixed |
| ------- | ----- |
| `(let [[x e1] [y e2]] body)` | `(let [(x e1) (y e2)] body)` |
| `(list-empty)` / `(list-append l e)` | `[]` / `[a b c]` list literals |
| `(pair a b)` | **unchanged** — current syntax is unambiguous |

**[CT]** Parser disambiguation: `[...]` in *expression position* = list literal; `[...]` in *parameter-list position* (after function name in `def-logic` or `fn`) = parameter list. Rule documented in `LLMLL.md §12`.

**[CT]** Old `(let [[x 1] ...])` syntax emits a clear error with a migration message.

---

## v0.1.3 — Type Alias Expansion ✅ Shipped (2026-03-21)

**Theme:** Close the last spurious type-checker errors affecting every real program using dependent type aliases, and fix where-clause binding variable scope.

### Deliverable — Structural Type Alias Resolution

**Implemented in `TypeCheck.hs` (commit `9931a77`):**

Instead of fixing `collectTopLevel` (which would break forward-reference resolution in function signatures), we took a lower-risk approach:

- **Added `tcAliasMap :: Map Name Type` to `TCState`** — populated from all `STypeDef` bodies at the start of each type-check run.
- **Added `expandAlias :: Type -> TC Type`** — looks up `TCustom n` in the alias map and returns the structural body; leaves all other types unchanged.
- **`unify` now calls `expandAlias` on both `expected` and `actual`** before `compatibleWith`. The existing `compatibleWith (TDependent _ a _) b = compatibleWith a b` rule handles the rest automatically.

`collectTopLevel` is unchanged — function signatures still register `TCustom name` for forward references, which is correct.

**Also shipped alongside (commit `fa008b1`):**

- **`where`-clause binding variable scope** — `TDependent` now carries the binding name; `TypeCheck.hs` uses `withEnv [(bindName, base)]` before inferring the constraint, eliminating `unbound variable 's'` / `'n'` false warnings.
- **Parser**: `_foo` treated as a single `PVar` binder (not `PWildcard` + `foo`).
- **Codegen**: `Error`→`Left`, `Success`→`Right` rewrite in `emitPat`; exhaustive `Left`+`Right` match suppresses redundant GHC warning.

**Acceptance criteria — all met:**

- ✅ `llmll check hangman_json`: **0 errors** (was 10: `expected GuessCount, got int` etc.)
- ✅ `llmll check hangman_sexp`: **0 errors** (was ~10)
- ✅ `llmll check tictactoe_json` / `tictactoe_sexp`: unaffected, still OK
- ✅ `stack test`: **25 examples, 0 failures** (was 21; 4 new tests added)
- ✅ `LLMLL.md §3.4` limitation block removed; replaced with accurate v0.1.2 description

#### Post-ship bug fixes — round 1 (discovered via `examples/hangman_json/WALKTHROUGH.md`, 2026-03-21)

| Bug | Location | Fix | Status |
| --- | -------- | --- | ------ |
| **P1** — `first`/`second` reject any explicitly-typed pair parameter with `expected Result[a,b], got <T>`; agent forced to use `"untyped": true` workaround on all state accessor params | `TypeCheck.hs`, `builtinEnv` | Changed `first`/`second` input from `TResult (TVar "a") (TVar "b")` to `TVar "p"` (fully polymorphic). Without a dedicated pair type in the AST, `TResult` was the wrong constraint — TVar unifies with any argument. | ✅ Fixed (`ef6f41c`) |
| **P2** — `post` clause on a pair-returning function cannot project `result` via `first`/`second` (same root cause as P1) | Derived from P1 | Same fix | ✅ Fixed (`ef6f41c`) |
| **P3** — `llmll test` skipped properties show opaque "requires full runtime evaluation" with no reason; agent cannot distinguish Command-skip from non-constant-skip | `PBT.hs`, `runProperty` | Added `bodyMentionsCommand` heuristic walk; skip message now names the specific cause | ✅ Fixed (`ef6f41c`) |

#### Post-ship bug fixes — round 2 (discovered via hangman/tictactoe walkthroughs, 2026-03-22)

| Bug | Location | Fix | Status |
| --- | -------- | --- | ------ |
| **B1** — `check` block labels with special chars (`(`, `)`, `+`, `?`) produce invalid Haskell `prop_*` identifiers; `stack build` fails with `Invalid type signature` | `CodegenHs.hs`, `emitCheck` | Added `sanitizeCheckLabel` — replaces all non-`[a-zA-Z0-9]` with `_`, collapses runs | ✅ Fixed (`880a8ad`) |
| **B2** — `[a b c]` in S-expression expression position rejected with `unexpected '['`; agents read §13.5 list-literal docs and try this syntax | `Parser.hs`, `pExpr` | Added `pListLitExpr` — desugars `[expr ...]` to `foldr list-prepend (list-empty)`, symmetric with JSON-AST `lit-list` | ✅ Fixed (`880a8ad`) |
| **N1** — `bodyMentionsCommand` prefix list included `"step"`, `"done"`, `"command"` — too broad, caused false-positive "Command-producing" skip reason for user-defined functions | `PBT.hs`, `bodyMentionsCommand` | Narrowed prefix list to `wasi./console./http./fs.` only | ✅ Fixed (`880a8ad`) |
| **P2** — `ok`/`err` not in scope in generated `Lib.hs`; preamble only defined `llmll_ok`/`llmll_err` but codegen emits bare `ok`/`err` | `CodegenHs.hs`, preamble | Added `ok = Right` and `err = Left` short aliases to preamble | ✅ Fixed (`db8f7a6`) |
| **P3** — Extra step rendered after game over; console harness checked `:done?` after `:step`, not before; one extra stdin read triggered a final render | `CodegenHs.hs`, `emitMainBody` | Restructured generated loop: `done? s` checked at top before `getLine` | ✅ Fixed (`db8f7a6`) |
| **P1** — `llmll build` deadlocks when called from inside a running `stack exec llmll -- repl` session (Stack project lock contention) | `Main.hs`, `doBuild`/`doBuildFromJson` | Added `--emit-only` flag: writes Haskell files, skips internal `stack build` | ✅ Fixed (`38265af`) |
| **C1** — `schemaVersion: "0.1.3"` in JSON-AST sources rejected with `schema-version-mismatch`; docs showed `0.1.3` but parser gated on `0.1.2` | `ParserJSON.hs`, `expectedSchemaVersion`; `docs/llmll-ast.schema.json` | Bumped `expectedSchemaVersion` and schema `const` from `"0.1.2"` to `"0.1.3"` | ✅ Fixed (`012b048`) |
| **C2** — `:on-done` in S-expression `def-main` generated `show_result state0` after the `where` clause — a GHC parse error | `CodegenHs.hs`, `emitMainBody` | `doneGuard` now pattern-matches on `(mDone, mOnDone)` pair; when both present emits `if done? s then onDone s else do` inside the loop | ✅ Fixed (`012b048`) |
| **C3** — `:on-done` in JSON-AST `def-main` silently omitted from generated `Main.hs` (same root cause as C2) | `CodegenHs.hs`, `emitMainBody` | Same fix as C2 — removed `onDoneBlock` list item that was erroneously placed after `where` | ✅ Fixed (`012b048`) |

#### Post-ship bug fixes — round 3 (discovered via hangman re-implementation, 2026-03-23)

| Bug | Location | Fix | Status |
| --- | -------- | --- | ------ |
| **B3** — `[...]` list literal in S-expression fails with `unexpected ']'` when used as a function argument inside an `if` branch body. Top-level `let` bindings and direct expressions work fine; the failure is specific to the nested call-inside-if position. `pListLitExpr` was added in B2 for expression position but the `pExpr` grammar inside if-`then`/`else` branches does not correctly disambiguate `]` from a surrounding parameter-list close when nesting is deep. | `Parser.hs`, `pExpr` / `pIf` | Fix: ensure `pListLitExpr` is tried with the correct bracket-depth context inside `pIf`. Alternatively, disambiguate by requiring list literals to be wrapped in parens when nested: `([ a b c ])`. Workaround: hoist list literals into `let` bindings before the `if` (see `getting-started.md §4.7`). JSON-AST is unaffected. | ⚠️ Cannot reproduce — retested 2026-03-23 against all developer-reported patterns (`hangman.llmll`, `tictactoe.llmll`, `wasi.io.stdout (string-concat-many [...])` inside `if`, nested `let`+`if`) — all pass ✅. May have been fixed as part of B2. Workaround in §4.7 is still good practice; bug remains documented in case it resurfaces. |
| **N2** — `string-concat` arity errors (2 args required, >2 given) now suggest `string-concat-many`. | `TypeCheck.hs`, arity error path | Appended `— use string-concat-many for joining more than 2 strings` to the arity mismatch error when `func == "string-concat"` and `actual > expected`. | ✅ Fixed (2026-03-27) |
| **N3** — JSON-AST `let` binding objects with extra keys silently accepted despite schema declaring `additionalProperties: false`. | `ParserJSON.hs`, `parseLet1Binding` | Added `Data.Aeson.KeyMap` key-whitelist check; fails with `let binding has unexpected keys: [...]` on any key outside `{"name", "expr"}`. | ✅ Fixed (2026-03-27) |

---

## v0.2 — Module System + Compile-Time Verification

**Theme:** Make multi-file composition real and make contracts compile-time verified.

### Internal Ordering (design team requirement)

```text
Phase 2a: Module System  →  Phase 2b: LiquidHaskell  →  Phase 2c: Type System Fixes + Sketch API
```

Rationale: `def-invariant` + Z3 verification requires multi-file resolution as substrate. Cross-module invariant checking is meaningless without cross-module compilation.

---

### Phase 2a — Module System

**[CT]** Multi-file resolution: `(import foo.bar ...)` loads and type-checks `foo/bar.llmll` or its `.ast.json` equivalent. Compiler maintains a module cache; circular imports are a compile error with cycle listed in the diagnostic.

**[CT]** Namespace isolation: each source file has its own top-level scope. Names from imported modules are prefixed by module path unless opened with `(open foo.bar)`.

**[CT]** Cross-module `def-interface` enforcement: when module A imports module B and relies on B's implementation of an interface, the compiler verifies structural compatibility at import time.

**[CT]** `llmll-hub` registry — `llmll hub fetch <package>@<version>` downloads a package and its `.ast.json` to the local cache. The compiler resolves `(import hub.<package>.<module> ...)` from the cache.

**Acceptance criteria:**

- A two-file program (A defines `def-interface`, B implements it) compiles and links.
- Circular imports produce a diagnostic naming the import cycle.

---

### Phase 2b — Compile-Time Verification via liquid-fixpoint ✅ Shipped (2026-03-27)

> **One-shot impact:** `pre`/`post` violations in the linear arithmetic fragment become compile-time errors. ~80% of practical contracts are decidable.

**Design pivot (approved by language team):** Rather than integrating LiquidHaskell as a GHC plugin (fragile, version-locked), Phase 2b uses a **decoupled backend**: the compiler emits `.fq` constraint files directly from the LLMLL typed AST, then invokes `liquid-fixpoint` (the stable Z3-backed solver engine that LH sits on top of) as a standalone binary.

#### D1 — Static `match` Exhaustiveness ✅

**[CT]** Post-inference pass `checkExhaustive` — collects all ADT definitions from `STypeDef`, checks every `EMatch` covers all constructors, emits `DiagError` with kind `"non-exhaustive-match"` if any arm is missing.

**Acceptance criteria — met:** `match` on `Color` with missing arm rejected at compile time. `Result[t,e]` with both arms accepted. Wildcard `_` satisfies exhaustiveness.

#### D2 — `letrec` + `:decreases` Termination Annotation ✅

**[CT]** `SLetrec` statement variant in `Syntax.hs`. Parser (`Parser.hs` + `ParserJSON.hs`) parse `(letrec name [params] :decreases expr body)` / JSON `{"kind": "letrec", "decreases": ...}`. Codegen emits `:decreases` comment marker. Self-recursive `def-logic` emits a non-blocking self-recursion warning.

**Acceptance criteria — met:** `letrec` with `:decreases` parses and type-checks. Recursive `def-logic` emits warning.

#### D3 — `?proof-required` Holes ✅

**[CT]** `HProofRequired Text` constructor added to `HoleKind` in `Syntax.hs`. Auto-detection in `HoleAnalysis.hs`: non-linear contracts emit `?proof-required(non-linear-contract)`; complex `letrec :decreases` emit `?proof-required(complex-decreases)`. Codegen emits `error "proof-required"` — non-blocking.

**Acceptance criteria — met:** `llmll holes` reports `?proof-required` with correct hint. `?proof-required` parses in S-expression form. JSON-AST `{"kind": "hole-proof-required"}` accepted.

#### D4 — Decoupled `.fq` Verification Backend ✅

**[CT]** Three new modules:

| Module | Role |
| ------ | ---- |
| `LLMLL.FixpointIR` | ADT for `.fq` constraint language (sorts, predicates, refinements, binders, constraints, qualifiers) + text emitter |
| `LLMLL.FixpointEmit` | Walks typed AST → `FQFile` + `ConstraintTable` (constraint ID → JSON Pointer). Covers QF linear integer arithmetic. Auto-synthesizes qualifiers from `pre`/`post`. |
| `LLMLL.DiagnosticFQ` | Parses `fixpoint` stdout (SAFE / UNSAFE) → `[Diagnostic]` with `diagPointer` (RFC 6901 JSON Pointer) using `ConstraintTable`. |

**[CT]** `llmll verify <file> [--fq-out FILE]` subcommand in `Main.hs`. Tries `fixpoint` and `liquid-fixpoint` binary names. Graceful degradation when not installed.

**Prerequisites:** `stack install liquid-fixpoint` + `brew install z3`.

**Acceptance criteria — met:**

- `llmll verify hangman_sexp/hangman.llmll` → `✅ SAFE (liquid-fixpoint)`
- JSON `--json verify` returns `{"success": true}`
- Contract violation returns diagnostic with `diagPointer` referencing original `pre`/`post` clause
- All 47 existing tests still pass

---

### Phase 2c — Type System Fixes + Sketch API ✅ Shipped (2026-03-28)

**[SPEC]** and **[CT]** ~~Lift `pair-type` in `typed-param` limitation~~ ✅ **Shipped (2026-03-27)** — `[acc: (int, string)]` accepted in `def-logic` params, lambda params, and `for-all` bindings. Parsed as `TPair A B` (v0.3 PR 1 introduced `TPair` — the `TResult` approximation is obsolete). Workaround note removed from `LLMLL.md §3.2` and `getting-started.md §4.7`.

**[CT]** ~~`llmll typecheck --sketch <file>`~~ ✅ **Shipped (2026-03-28)** — accepts a partial LLMLL program (holes allowed everywhere). Runs constraint-propagation type inference. Returns a JSON object mapping each hole's JSON Pointer to its inferred type (`null` if indeterminate) plus `holeSensitive`-annotated errors.

**[CT]** ~~HTTP interface for agent use~~ ✅ **Shipped (2026-03-28)** — `llmll serve [--host H] [--port P] [--token T]`. Default: `127.0.0.1:7777`. Stateless per request; `--token` enables `Authorization: Bearer` auth; TLS delegated to reverse proxy.

**[CT]** `--sketch` hole-constraint propagation (*language team design, 2026-03-27*) — `--sketch` must propagate checking types to hole expressions at all three sites where a peer expression provides the constraint:

| Site | Constraint source | Implementation |
| ---- | ----------------- | -------------- |
| `EIf` then/else | sibling branch synthesises type `T`; hole branch checked against `T` | `inferExpr (EIf ...)` — try-and-fallback |
| `EMatch` arms | non-hole arms unified to `T`; hole arms checked against `T` | two-pass arm loop (see below) |
| `EApp` arguments | function signature via `unify` | ✅ already handled |
| `ELet` binding RHS | explicit annotation | ✅ already handled |
| `fn` / lambda body | outer checking context propagates inward | ✅ already handled |

`EMatch` requires a **two-pass arm loop** in `inferExpr (EMatch ...)`:

- Pass 1 — synthesise all non-hole arm bodies → unify to `T` (or emit type-mismatch error as today)
- Pass 2 — check all hole arm bodies against `T`; record `T` as `inferredType` in sketch output

If pass 1 unification fails (arm type conflict), `T` is indeterminate. `--sketch` reports the conflict as an `errors` entry with `"kind": "ambiguous-hole"` and records `inferredType: null` for hole arms — it does not fall silent.

**[CT]** ~~N2 — `string-concat` arity hint~~ ✅ **Shipped (2026-03-27)** — arity mismatch on `string-concat` with actual > 2 now appends `— use string-concat-many for joining more than 2 strings`.

**[CT]** ~~N3 — Strict key validation for JSON-AST `let` binding objects~~ ✅ **Shipped (2026-03-27)** — `parseLet1Binding` now fails explicitly on unexpected keys, emitting a clear error naming the offending key.

**Acceptance criteria:**

- `[acc: (int, string)]` in a lambda parameter list parses and type-checks without a workaround.
- Given a partial program with three holes, `llmll typecheck --sketch` returns each hole's inferred type.
- A type conflict in a partial program is reported even when the surrounding program is incomplete.
- A hole in the `then` (or `else`) branch of an `if`, where the sibling branch synthesises type `T`, is reported by `--sketch` as `inferredType: T`.
- A hole in a `match` arm body, where at least one other arm synthesises type `T`, is reported by `--sketch` as `inferredType: T`.
- A `match` where non-hole arms have conflicting types reports the conflict as an `errors` entry; hole arms in that `match` report `inferredType: "<conflict>"` rather than being omitted.
- `(string-concat a b c)` arity error includes the `string-concat-many` hint.
- A JSON-AST `let` binding object with an extra key produces a clear parse error naming the offending key.

---

## v0.3 — Agent Coordination + Interactive Proofs

### Shipped: Do-Notation (PRs 1–3, 2026-04-05 – 2026-04-08)

> **One-shot impact:** Eliminates deeply nested `let`/`seq-commands` boilerplate for stateful action sequences. Type checker enforces state-type consistency across all steps.

**[CT]** ~~`TPair` type system foundation~~ ✅ **PR 1 (2026-04-05)** — new `TPair Type Type` constructor in `Syntax.hs`. `EPair` expressions typed `TPair a b`, replacing the unsound `TResult a b` approximation. Fixes JSON-AST round-trip (`"result-type"` → `"pair-type"`) and `match` exhaustiveness (no longer cites `Success`/`Error` for pairs). Surface syntax unchanged.

**[CT]** ~~`DoStep` collapse~~ ✅ **PR 2 (2026-04-06)** — unified `DoStep (Maybe Name) Expr` replaces `DoBind`/`DoExpr` split. Type checker enforces pair-thread: every step returns `(S, Command)` with identical `S`. JSON parser rejects old `"bind-step"`/`"expr-step"` kinds.

**[CT]** ~~`emitDo` rewrite~~ ✅ **PR 3 (2026-04-08)** — pure `let`-chain codegen. Named steps `[s <- expr]` bind state via `let`; anonymous steps discard it. `seq-commands` folds accumulated commands. No Haskell `do` or monads emitted.

**Acceptance criteria — all met:**

- ✅ `(do [s1 <- (action1 state)] [s2 <- (action2 s1)] (action3 s2))` parses, type-checks, and compiles
- ✅ Mismatched state type `S` across steps produces a `"type-mismatch"` diagnostic
- ✅ Anonymous step `(expr)` with non-matching state emits state-loss warning
- ✅ `llmll build --emit json-ast` round-trips `do`-blocks with `"do-step"` nodes
- ✅ All 47 existing tests still pass

---

### In Progress: Pair Destructuring (PR 4)

**[CT]** Pair destructuring in `let` bindings — `(let [((a b) expr)] body)` pattern. Extends `ELet` binding target from `Name` to `Pattern`. Implementation in progress across Syntax, Parser, TypeCheck, and Codegen.

---

### Planned: Agent Coordination + Interactive Proofs

**[CT]** `string-concat` parse-level variadic sugar (S-expression only) *(language team proposal, 2026-03-27)*. In the S-expression parser, desugar `(string-concat e1 e2 e3 …)` with 3+ arguments into `(string-concat-many [e1 e2 e3 …])` at parse time. The type checker never sees a 3-arg `string-concat` — the fixed-arity invariant is fully preserved. The binary form `(string-concat a b)` remains unchanged and retains first-class partial-application semantics. JSON-AST is unaffected: agents already use `{"kind": "app", "fn": "string-concat-many", "args": [{"kind": "lit-list", ...}]}` naturally. Implementation: `Parser.hs` `pApp` / `pExpr` only — zero `TypeCheck.hs` impact.

> **Decision record:** Type-checker variadic special-casing rejected (breaks fixed-arity invariant; JSON-AST complexity). Binary `string-concat` deprecation rejected (breaks partial application). Parse-level sugar is the minimal, correct resolution.

**Acceptance criteria (v0.3):**

- `(string-concat "a" "b" "c")` in S-expression compiles to the same Haskell as `(string-concat-many ["a" "b" "c"])`.
- `(string-concat prefix)` partial application still type-checks as `string → string`.
- JSON-AST `{"fn": "string-concat", "args": [a, b, c]}` produces a clear arity error (unchanged behavior — sugar is parse-time S-expression only).

---

**[CT]** `?delegate` JSON-Patch lifecycle:

1. Lead AI checks out a hole: `llmll holes --checkout <pointer>`
2. Agent submits implementation as RFC 6902 JSON-Patch against the program's JSON-AST
3. Compiler applies patch, re-runs type checking and contract verification
4. Success → patch merged; failure → JSON diagnostics targeting patch node pointers

**[CT]** `?scaffold` — `llmll hub scaffold <template>` fetches a pre-typed skeleton from `llmll-hub`. `def-interface` boundaries are pre-typed; implementation details are named `?` holes. Resolves at parse time.

**[CT]** Leanstral MCP integration — `?proof-required :inductive` and `:unknown` hole resolution:

1. `llmll holes --json` emits holes with complexity hints
2. Compiler translates LLMLL `TypeWhere` AST node → Lean 4 `theorem` obligation *(the only novel engineering piece)*
3. MCP call to Leanstral's `lean-lsp-mcp`
4. Leanstral returns verified Lean 4 proof term
5. `llmll check` stores certificate; subsequent builds verify certificate without re-calling Leanstral
6. Fallback: if Leanstral unreachable, hole becomes `?delegate-pending` (blocks execution, does not fail build)

**[SPEC]** Document `?proof-required :simple | :inductive | :unknown` hint syntax in `LLMLL.md §6`.

**[CT]** ~~`do`-notation sugar~~ ✅ **Shipped (PRs 1–3)** — see "Shipped" section above.

**[CT]** Event Log spec — formalized `(Input, CommandResult, captures)` deterministic replay. NaN rejected at GHC/WASM boundary.

**[CT]** `Promise[t]` upgrade: `IO t` → `Async t` from the `async` package. `(await x)` desugars to `Async.wait`.

**Acceptance criteria:**

- Two-agent demo: Agent A writes a module with `?delegate`, Agent B submits a JSON-Patch; compiler accepts the merge.
- A `?proof-required :inductive` hole for a structural list property is resolved by Leanstral; certificate verified on next build without a Leanstral call.

---

## v0.4 — WASM Hardening

**Theme:** Replace Docker with WASM-WASI as the primary sandbox. No new language semantics.

**[CT]** `llmll build --target wasm` — compile generated Haskell with `ghc --target=wasm32-wasi`.

**[CT]** WASM VM (Wasmtime) replaces Docker as default sandbox.

**[CT]** Capability enforcement via WASI import declarations (replaces Docker network/filesystem policy layer).

**[CT]** Resolve any GHC WASM backend compatibility issues for `effectful`, `QuickCheck`, and other vendored dependencies. Maintain a minimal shim package if needed.

**Acceptance criteria:**

- `llmll build --target wasm examples/hangman.llmll` produces a `.wasm` binary that runs in Wasmtime and passes all `check` blocks.
- A capability violation terminates the WASM instance with a typed error.

---

## Summary: What Changed from LLMLL.md §14

| Version | Original | Revised |
| ------- | -------- | ------- |
| **v0.1.2** | JSON-AST + FFI stdlib | JSON-AST + **Haskell codegen** + typed effect row + hole-density validator + Docker sandbox |
| **v0.2** | Module system (unscheduled) + Z3 liquid types | Module system **first** → **decoupled liquid-fixpoint** (replaces Z3 binding project) → pair-type fix + `--sketch` API |
| **v0.3** | Agent coordination + Lean 4 agent *(to be built)* | Agent coordination + **Leanstral MCP integration** + `do`-notation ✅ (PRs 1–3 shipped) + pair destructuring (PR 4 in progress) |
| **v0.4** | *(not planned)* | WASM hardening: `--target wasm`, WASM VM replaces Docker |

### Items Removed from Scope

| Item | Reason |
| ---- | ------ |
| Rust FFI stdlib (`serde_json`, `clap`, etc.) | Replaced by native Hackage imports |
| Z3 binding layer (build from scratch) | Replaced by decoupled liquid-fixpoint backend (no GHC plugin) |
| Lean 4 proof agent (build from scratch) | Replaced by Leanstral MCP integration |
| Python FFI tier | Breaks WASM compatibility; dynamically typed; dropped from spec |
| Opaque `Command` type | Replaced by typed effect row (`Eff '[...]`) |
