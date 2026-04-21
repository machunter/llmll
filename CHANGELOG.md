# CHANGELOG

---

## v0.5.0 — U-Full Soundness (2026-04-21)

### Compiler

- **Occurs check** — `TVar "a"` cannot unify with a type that contains itself (e.g., `list[TVar "a"]`). Prevents infinite type construction. `occursIn` helper is structurally total over the `Type` ADT, including `TSumType`.
- **Let-generalization** — Top-level `def-logic` and `letrec` functions are let-generalized: each call site gets fresh type variable instantiation. Inner `let`-bound lambdas are not generalized (deferred to v0.7).
- **TVar-TVar wildcard closure** — Type variable bindings now propagate through chains. Closes the gap where `TVar "a" ~ TVar "b"` followed by `TVar "b" ~ int` would leave `TVar "a"` unresolved.
- **Bound-TVar consistency fix** — Recursive `structuralUnify` replaces `compatibleWith` at L1044 for bound type variable comparison (Language Team Issue 2).
- **L1055 asymmetric wildcard** — Documented as safe under per-call-site scoping (Language Team Issue 3). Each `EApp` gets fresh type variables, so the asymmetry does not leak across call boundaries.

### Spec (LLMLL.md)

- §3.2 — U-Full type variable note added
- §4.17 — New section in `getting-started.md` documenting occurs check and let-generalization with examples
- §10.7 — Pipeline notes updated with v0.5.0 entry
- §14 — v0.5.0 roadmap section marked ✅ Shipped

**Tests:** 257 → 264 Haskell (+7 U-Full), 37 Python (unchanged).

---

## v0.4.0 — Lead Agent + U-Lite Soundness (2026-04-20)

### Compiler — Lead Agent

- **`llmll-orchestra --mode plan`** — Intent-to-architecture-plan generation. Produces structured JSON plan from natural language intent.
- **`llmll-orchestra --mode lead`** — Plan-to-skeleton generation. Produces validated JSON-AST skeleton with typed `def-interface` boundaries and `?` holes.
- **`llmll-orchestra --mode auto`** — End-to-end pipeline: plan → skeleton → fill → verify in sequence.
- **Quality heuristics** — Skeleton quality checks flag: low parallelism, all-string types, missing contracts, unassigned agents.

### Compiler — U-Lite Soundness

- **Per-call-site substitution-based unification** — Each `EApp` gets fresh type variable instantiation via α-renaming. Substitution map does not escape the `EApp` boundary. `list-head 42` is now correctly rejected as a type error.
- **`first`/`second` retyped** — From `TVar "p" → TVar "a"` to `TPair a b → a` / `TPair a b → b` in `builtinEnv`. `first 42` is now a type error.
- **TDependent resolution** — Strip-then-Unify (Option A). `TDependent` strips to base type during unification — no constraint propagation, no proof obligations. Formalizes existing `compatibleWith` behavior.

### Compiler — CAP-1 Capability Enforcement

- **Compile-time capability check** — `wasi.*` function calls without a matching `(import wasi.* (capability ...))` in the module's statement list produce a type error. Check is in `inferExpr (EApp ...)`, covering all nesting contexts: `let` RHS, `if` branches, `match` arms, `do` steps, contract expressions.
- **Non-transitive propagation** — Each module must declare its own capability imports. Module B cannot inherit Module A's capabilities.

### Compiler — Invariant Pattern Registry

- **`InvariantRegistry.hs`** — New module. Pattern database keyed by `(type signature, function name pattern)`. ≥5 patterns: list-preserving, sorted, round-trip, subset, idempotent.
- **`llmll typecheck --sketch`** — Now emits `invariant_suggestions` field from the pattern registry.

### Compiler — Downstream Obligation Mining

- **`ObligationMining.hs`** — New module. When `llmll verify` reports UNSAFE at a cross-function boundary, suggests postcondition strengthening on the callee. Leverages `TrustReport.hs` transitive closure infrastructure.

### Compiler — Aeson FFI

- **`(import haskell.aeson Data.Aeson)`** — Codegen emits `import Data.Aeson` + adds `aeson` to `package.yaml`. Manual Haskell bridge file required for JSON instance derivation.

### Orchestrator

- **`lead_agent.py`** — Lead Agent skeleton generation with plan/lead/auto modes.
- **`quality.py`** — Skeleton quality heuristics module.

**Tests:** 225 → 257 Haskell (+32), 12 → 37 Python (+25).

---

## v0.3.5 — Agent Effectiveness (2026-04-19)

### Track B: Context-Aware Checkout (C1–C6)

- **Provenance-tagged environment snapshots** — `ScopeSource` (Param | LetBinding | MatchArm | OpenImport) and `ScopeBinding` types track the origin of each in-scope binding. `SketchHole.shEnv` captures the typing environment delta at hole sites.
- **`withTaggedEnv`** — New scope combinator that pushes provenance-tagged bindings and restores on exit.
- **Context-aware `CheckoutToken`** — Extended with `ctInScope` (Γ), `ctExpectedReturnType` (τ), `ctAvailableFunctions` (Σ), and `ctTypeDefinitions`. JSON schema bumped to v0.3.0.
- **`normalizePointer`** (EC-3) — Strips leading zeros from RFC 6901 pointer segments.
- **`collectTypeDefinitions`** (C4) — Depth-bounded (5-level) recursive alias expansion with cycle detection (EC-4).
- **`monomorphizeFunctions`** (C5) — Presentation-only type variable substitution. Idempotent (INV-1), does not mutate `builtinEnv` (INV-2).
- **`truncateScope`** (C6) — Priority-based scope retention: Params > LetBindings > MatchArms > OpenImports.
- **EC-1 bug fix** — `inferExpr (ELet ...)` was leaking `tcInsert` mutations to sibling if-branches. Fixed by save/restore around the binding `foldM`.

### Track W: Weak-Spec Counter-Examples (W1–W2)

- **`WeaknessCheck.hs`** — New module. Trivial body catalog: identity, constant-zero, empty-string, true, empty-list. Type-checks synthetic statements (INV-4) before fixpoint emission.
- **`--weakness-check`** — New flag on `llmll verify`. After SAFE, runs trivial body analysis. SAFE trivial bodies produce `spec-weakness` diagnostics.
- **`mkSpecWeakness`** — Structured diagnostic with precondition text (EC-7), suggestion, and `kind: "spec-weakness"`.

### Track A: Orchestrator End-to-End (O1–O5)

- **O2: Formatted retry diagnostics** — `_format_diagnostics()` renders compiler diagnostics as human-readable actionable text (not raw JSON) for agent follow-up prompts.
- **O3: Checkout TTL handling** — `_ensure_checkout()` checks remaining TTL; re-checkouts on expiry with EC-6 token re-assignment.
- **O4: Integration tests** — 12 Python tests covering happy path, retry, lock expiry, token update, all-fail, and prompt formatting.
- **O5: Context-aware prompt** — `_format_context()` renders scope as markdown table, functions as signature list, types as definition list. Falls back to JSON for unknown keys.

**Tests:** 211 → 225 Haskell (14 new), 12 Python tests (all new).

## v0.3.1 — Event Log + Leanstral MCP (2026-04-11)

### Event Log (Phase A)

- **JSONL event logging** — Generated `Main.hs` for console programs writes `.event-log.jsonl` with true JSONL format (one JSON object per line, crash-safe).
- **stdout capture** — `captureStdout` via `hDuplicate`/`hDupTo` captures program output for the `result` field. Forced lazy I/O evaluation prevents pipe read bugs.
- **`llmll replay`** — New subcommand parses `.event-log.jsonl` files and reports events with input/result values.
- **`Replay.hs`** — JSONL line-by-line parser with crash tolerance (partial logs parseable up to last flushed line).

### Leanstral MCP (Phase B — Mock-Only)

- **`LeanTranslate.hs`** — Translates LLMLL contract AST (`EOp`/`EApp`) to Lean 4 `theorem` obligations. Supports linear arithmetic, list structural induction, quantified variables.
- **`MCPClient.hs`** — MCP JSON-RPC client with `--leanstral-mock` mode (`ProofFound "by sorry"`). Real protocol implemented but untested.
- **`ProofCache.hs`** — Per-file `.proof-cache.json` sidecar with SHA-256 invalidation. Follows `VerifiedCache` pattern.
- **`holeComplexity`** — `HoleAnalysis.hs` gains `holeComplexity :: Maybe Text` field. `normalizeComplexity` classifies proof-required holes as `:simple`, `:inductive`, or `:unknown`. JSON output includes `"complexity"` field.
- **`inferHole (HProofRequired)`** — Added missing type checker pattern for `?proof-required` holes.

### Integration (Phase C)

- `examples/event_log_test/` and `examples/proof_required_test/` — minimal programs for end-to-end validation.

### Replay Execution (Phase D)

- **`runReplay`** — Spawns compiled executable, feeds inputs step-by-step via blocking `hGetLine` (synchronized I/O), compares captured outputs against logged results.
- **`doReplay`** — Full pipeline: parse JSONL → build program → find executable → run replay → report matches/divergences.

### Verify Integration (Phase E)

- **`--leanstral-mock`** / `--leanstral-cmd` / `--leanstral-timeout`** — CLI flags on `llmll verify` to enable Leanstral proof pipeline.
- **`runLeanstralPipeline`** — Scans `[Statement]` directly for `SDefLogic`/`SLetrec` with `HProofRequired` body. Runs translate → prove → cache flow.

### SHA-256 Hardening (Phase F)

- **`computeObligationHash`** — `cryptohash-sha256` dependency. Real SHA-256 hash (64-char hex) for proof cache invalidation.

**Tests:** 145 → 181 (36 new: 5 event log + 10 Leanstral MCP + 5 integration + 16 coverage gaps).

---

## v0.3.4 — Agent Spec + Orchestrator Hardening (2026-04-19)

### Compiler — `llmll spec`

- **New `LLMLL.AgentSpec` module** — Reads `builtinEnv` from `TypeCheck.hs` directly and serializes it as a structured agent specification. Partitions builtins (36) from operators (14) via an explicit `operatorNames` set matching `CodegenHs.emitOp`. Excludes `wasi.*` functions. Deterministic alphabetical output.
- **`llmll spec [--json]` CLI command** — Emits the agent spec to stdout. Text output (default) is token-dense for direct system prompt inclusion. JSON output includes constructors, evaluation model, pattern kinds, and type nodes.
- **7 faithfulness property tests** — `covers all builtinEnv`, `no phantom entries`, `disjoint partition`, `unary not`, `deterministic order`, `excludes wasi.*`, `includes seq-commands`. Adding a new builtin without a spec entry is caught automatically.

### Compiler — Builtin changes

- **New builtin: `string-empty?`** — `string → bool`. Added to `builtinEnv` + runtime preamble (`string_empty' s = null s`). Documented in `LLMLL.md` §13.6.
- **New preamble: `regex-match`** — `string → string → bool`. Runtime implementation: `regex_match pattern subject = pattern \`isInfixOf\` subject`. Added `isInfixOf` import to generated Haskell.
- **Removed: `is-valid?`** — Phantom builtin removed from `builtinEnv`. Was not used by any example or test.
- **Exported `builtinEnv`** — Now part of the public `TypeCheck` module API for consumption by `AgentSpec`.

### Orchestrator — Phase A prompt enrichment

- **Composable system prompt** — `agent.py` refactored: `SYSTEM_PROMPT` split into `_SYSTEM_PROMPT_HEADER` + injected spec + `_SYSTEM_PROMPT_FOOTER`. New `build_system_prompt(compiler_spec)` function.
- **Compiler integration** — `compiler.py` gains `spec()` method wrapping `llmll spec` with backward-compat fallback (returns `None` for pre-v0.3.4 compilers). `orchestrator.py` calls `compiler.spec()` at start of `run()`.
- **Legacy fallback** — `_LEGACY_BUILTINS_REF` in `agent.py` provides static reference for compilers without `spec` command.
- **New prompt sections** — pair/first/second usage, Result construction vs pattern matching (ok/err vs Success/Error), letrec note, fixed-arity operator rule with parametricity note, `pair-type` and `fn-type` type nodes.

**Tests:** 194 → 211 (+7 AgentSpec faithfulness + 10 other).

---

## v0.3.3 — Agent Orchestration (2026-04-16)

### Compiler — `llmll holes --json --deps`

- **Annotated dependency graph** — Each hole entry in `--json` output includes `depends_on` edges with `{pointer, via, reason}` and `cycle_warning` flag. Dependency = "hole B's enclosing function calls a function whose body contains hole A" (`calls-hole-body`).
- **Tarjan's SCC cycle detection** — `HoleAnalysis.hs` walks the call graph and detects mutual-recursion cycles. Deterministic back-edge removal (highest statement index). `cycle_warning: true` per hole.
- **`--deps-out FILE`** — New flag persists the dependency graph to a file (implies `--deps`). Compiler does not manage lifecycle — orchestrator owns the file.
- **RFC 6901 pointer fix** — `holePointer` rewritten to track structural AST position (`/statements/N/body`, etc.) — compatible with `llmll checkout`. Previous context-based pointer generation was non-functional.
- **Scope exclusions** — `?proof-required` holes and contract-position holes excluded from the dependency graph.
- **Call-graph analysis** — New internal functions in `HoleAnalysis.hs`: `extractCalls`, `buildCallGraph`, `buildFuncBodyHoles`, `computeHoleDeps`.

### Docs

- `docs/orchestrator-walkthrough.md` — Full end-to-end walkthrough: skeleton authoring → hole scanning → tier scheduling → agent filling → Haskell compilation. Includes conceptual model (metavariables, CEGIS), related work (Agda, Synquid, ChatDev, Airflow), and evaluation questions.
- `docs/design/agent-prompt-semantics-gap.md` — Agent prompt gap analysis: what's missing from the agent system prompt, 3-phase solution (A: enhanced prompt, B: `llmll spec --agent`, C: context-aware checkout). Reviewed and approved by Language Team and Professor.
- `docs/design/lead-agent.md` — Design for automated skeleton generation: Lead Agent loop (decompose → generate AST → `llmll check` → iterate), quality heuristics, phased implementation.
- `examples/orchestrator_walkthrough/` — Auth module exercise files (`auth_module.ast.json`, `auth_module_filled.ast.json`).

**Tests:** 194 (unchanged from v0.3.2 — this release is compiler analysis + external tooling).

---

## v0.3.2 — Trust Hardening + WASM PoC (2026-04-16)

### Compiler

- **Cross-module trust propagation tests** — 7 test cases covering the asserted/tested/proven verification level matrix, mixed levels, and `(trust ...)` declaration suppression. Validates that `VLProven` importing `VLAsserted` is correctly capped.
- **`llmll verify --trust-report`** — New output mode prints a per-function trust summary after verification: contract verification level (proven/tested/asserted), transitive closure of cross-module calls, and epistemic drift warnings ("Function `withdraw` is proven, but depends on `auth.verify-token` which is asserted"). JSON output with `--json`. New `LLMLL.TrustReport` module.
- **GHC WASM proof-of-concept** — Analyzed `hangman_json_verifier` generated Haskell for WASM compatibility. Conditional GO verdict — pure logic compiles cleanly; ~6-7 days engineering for v0.4. See `docs/wasm-poc-report.md`.

**Tests:** 181 → 194 (7 trust propagation + 6 trust report).

---

## v0.3.0-dev — Do-Notation + Type Soundness (in progress)

### Compiler — Stratified Verification + Feature Completion (2026-04-11)

- **Stratified Verification (Item 7b)** — `VerificationLevel` ADT (`VLAsserted`, `VLTested n`, `VLProven prover`) with custom `Ord` instance (asserted < tested < proven). `ContractStatus` tracks per-function pre/post levels. Type checker seeds contract status from imported modules via `VerifiedCache` sidecar files. Trust-gap warnings emitted for calls to unproven cross-module functions lacking `(trust ...)` declarations.
- **`(trust ...)` declaration (Item 7b)** — new `STrust` statement kind. Parsed in both S-expression (`(trust foo.bar :level tested)`) and JSON-AST. Silences trust-gap warnings for explicitly acknowledged dependencies.
- **`--contracts` CLI flag (Item 8)** — `llmll build --contracts=full|unproven|none`. `applyContractsMode` pre-processes statements before codegen, stripping contract clauses by mode. `ContractsNone` removes all pre/post assertions; `ContractsUnproven` strips only clauses with proven verification status; `ContractsFull` (default) preserves all.
- **`.verified.json` sidecar write (Item 9)** — `llmll verify` now calls `saveVerified` after a `FQSafe` result from liquid-fixpoint, writing per-function `ContractStatus` with `VLProven "liquid-fixpoint"` to a sidecar file. Subsequent `llmll build --contracts=unproven` reads this sidecar via `loadVerified` + `mergeCS` to strip proven assertions.
- **`string-concat` variadic sugar (Item 10)** — `Parser.hs` desugars `(string-concat e1 e2 e3 …)` with 3+ args to `(string-concat-many [e1 e2 e3 …])` at parse time. Already shipped; confirmed in audit.
- **`?scaffold` CLI (Item 11)** — `llmll hub scaffold <template> [--output DIR]`. `Hub.hs` adds `scaffoldCacheRoot` (`~/.llmll/templates/`) and `resolveScaffold`. Hub command upgraded from single `--from-file` option to `fetch`/`scaffold` subcommand group. Explicit `emitHole (HScaffold ...)` clause added to CodegenHs.
- **Async codegen verification (Item 14)** — confirmed `TPromise` → `Async.Async`, `EAwait` → `try (Async.wait ...)` with `SomeException` catch-all, generated preamble imports `Control.Concurrent.Async` + `Control.Exception`, `package.yaml` includes `async` dependency. 10 regression tests added.
- **Tests:** 69 → 121 → 128 → 145 across the v0.3 cycle.


### Compiler — PRs 1–3 (2026-04-05 – 2026-04-08)

- **`TPair` introduction (PR 1)** — new `TPair Type Type` constructor in `Syntax.hs`. `EPair` expressions are now typed `TPair a b`, replacing the unsound `TResult a b` approximation. Fixes two incorrect behaviours: (1) `llmll build --emit json-ast` emitted `{"kind":"result-type",...}` for pair-typed expressions; (2) `match` exhaustiveness on pair-typed scrutinee incorrectly cited `Success`/`Error` constructors. Surface syntax unchanged.
- **`DoStep` collapse (PR 2)** — `DoStep (Maybe Name) Expr` replaces the previous `DoBind Name Expr` / `DoExpr Expr` split. Unified AST node simplifies all downstream passes. Type checker now enforces that every step in a `do`-block returns `(S, Command)` with identical state type `S` across all steps (pair-thread enforcement).
- **`emitDo` rewrite (PR 3)** — do-notation codegen replaced with a pure `let`-chain emitter. Named steps `[s <- expr]` bind the state component via `let`; anonymous steps `(expr)` discard it. `seq-commands` folds accumulated commands. No Haskell `do` or monads emitted — sound in `def-logic` pure contexts.
- **JSON parser do-step migration** — `ParserJSON.hs` rejects old `"bind-step"` and `"expr-step"` kinds with a clear migration error pointing to `"do-step"`. No backward compatibility — do-notation never shipped in a stable release.

### Compiler — PR 4 (shipped)

- **Pair destructuring in `let` bindings** — `(let [((pair s cmd) expr)] body)` destructures pair-typed expressions into two bindings. Nested destructuring is supported: `(let [((pair w (pair g r)) state)] ...)`.
  - `Syntax.hs`: `ELet` binding head changed from `Name` to `Pattern`.
  - `Parser.hs`: `pLetBinding` calls `pPattern`; `pPattern` now accepts `(pair p1 p2)` as a constructor despite `pair` being a reserved word.
  - `ParserJSON.hs`: `parseLet1Binding` supports `"name"` (ergonomic shorthand) and `"pattern"` (full destructuring) with strict key validation.
  - `TypeCheck.hs`: `inferExpr (ELet ...)` dispatches `PVar` (simple binding) vs `checkPattern` (destructuring); pair constructor at line 829.
  - `CodegenHs.hs`: `emitLet` uses `emitPat`; `emitPat (PConstructor "pair" [p1,p2])` emits Haskell tuple pattern.
  - `AstEmit.hs`: `bindingToJson` emits `"name"` for `PVar`, `"pattern"` for other patterns.
  - `llmll-ast.schema.json`: `ExprLet` binding items have `"name"` + `"pattern"` with `oneOf` constraint.
- **Acceptance:** All 7 criteria verified — 3 new test fixtures pass, existing examples unaffected, no `-Wincomplete-patterns`, 69/69 unit tests pass.

### Spec (LLMLL.md)

- §5 scope note, §9.6 do-notation, §12 EBNF grammar, §14 roadmap — updated to reflect PRs 1–3
- §12 EBNF `do-step` production corrected: `[IDENT "<-" expr]` (was `("<-" IDENT expr)`)
- Stale v0.1.x restriction notes, workarounds, and version provenance tags removed throughout
- **§11.2 `await` return type (v0.3)** — `await` now returns `Result[t, DelegationError]` instead of bare `t`. Programs using `await` must pattern-match on `Success`/`Error`. This is a breaking change from v0.2.
- **§11.2 Checkout/Patch workflow (v0.3)** — new subsection documenting the `llmll checkout` / `llmll patch` lifecycle for agent-driven hole resolution via RFC 6902 JSON-Patch.
- **Principle 4 renamed** from "Runtime Contract Verification" to "Design by Contract with Stratified Verification." Contracts now carry a verification level (`proven`, `tested`, `asserted`). `--contracts` flag controls runtime assertion compilation. Trust-level propagation warns downstream modules about unproven dependencies.
- **§4.4 Contract Semantics rewritten** — new subsections §4.4.1 (Verification Levels), §4.4.2 (Runtime Assertion Modes), §4.4.3 (Trust-Level Propagation). `(trust ...)` syntax introduced for acknowledging unproven dependencies.
- **§12 EBNF grammar** — `trust-decl` production added.

### Docs

- `getting-started.md` — §4.13 backward-compat claim corrected (bind-step/expr-step are rejected, not parsed); `typecheck` and `serve` added to `--help` output; `checkout` and `patch` command docs added
- `llmll-ast.schema.json` — stale v0.1.x notes removed from TypedParam, TypePair, ExprLambda, DoStep descriptions; `ExprAwait` description updated for `Result[t, DelegationError]` return type; `PatchEnvelope`, `PatchOp`, `CheckoutToken` companion definitions added; `TrustDecl` node kind added to `Statement` oneOf
- `README.md` — 6 missing examples and 4 missing compiler modules added to repo layout; `checkout` and `patch` added to CLI command table

---

## v0.2.0 — Phase 2a/2b/2c: Module System, Compile-Time Verification, Sketch API (2026-03-28)

### Compiler — Phase 2c (2026-03-28)

- **`llmll typecheck --sketch <file>`** — new subcommand for partial-program type inference. Accepts a program with holes anywhere; returns each hole's inferred type (`null` if indeterminate) and all detectable type errors annotated with `holeSensitive: bool`. `holeSensitive: true` means the error may resolve once holes are filled.
- **`llmll serve [--host H] [--port P] [--token T]`** — exposes `--sketch` as `POST /sketch` HTTP endpoint for distributed agent swarms. Binds `127.0.0.1:7777` by default. Every request is stateless (fresh type-check context per call — safe for concurrent agent use). `--token` enables `Authorization: Bearer` auth; TLS is delegated to a reverse proxy.
- **Pair-type in typed parameters** — `[acc: (int, string)]` is now valid in `def-logic`, lambda, and `for-all` parameter lists. Parsed as `TResult A B` internally (v0.3 PR 1 replaces this with `TPair A B`). Workaround note removed from `LLMLL.md §3.2` and `getting-started.md §4.7`.
- **`string-concat` arity hint (N2)** — arity mismatch error on `string-concat` with more than 2 arguments now appends `— use string-concat-many for joining more than 2 strings`.
- **Strict `let` key validation (N3)** — JSON-AST `let` binding objects with unexpected keys (e.g. `kind`, `op` alongside `name`/`expr`) now produce a clear parse error naming the offending key. Previously accepted silently, producing corrupt AST nodes.
- **`LLMLL.Sketch`** — new module. `HoleStatus` ADT (`HoleTyped`, `HoleAmbiguous`, `HoleUnknown`); `runSketch`; `encodeSketchResult`. Hole-constraint propagation at `EIf` (sibling branch), `EMatch` (two-pass arm loop), and `EApp` (function signature via `unify`).

### Compiler — Phase 2b (2026-03-27)

- **`llmll verify <file>`** — new subcommand (D4). Emits a `.fq` constraint file from the typed AST and runs `liquid-fixpoint` + Z3 as a standalone binary. Reports SAFE or contract-violation diagnostics with RFC 6901 JSON Pointers back to the original `pre`/`post` clause. Gracefully degrades when `fixpoint`/`z3` are not in `PATH`.
- **Static `match` exhaustiveness (D1)** — post-inference pass `checkExhaustive` rejects any `match` on an ADT sum type that does not cover all constructors. GHC-style error with pointer to the missing arm.
- **`letrec` + `:decreases` (D2)** — new statement kind for self-recursive functions. Mandatory `:decreases` termination measure is verified by `llmll verify`. Self-recursive `def-logic` emits a non-blocking warning.
- **`?proof-required` holes (D3)** — compiler auto-emits `?proof-required(non-linear-contract)` and `?proof-required(complex-decreases)` for predicates outside the decidable QF linear arithmetic fragment. Non-blocking; runtime assertion remains active.
- **`LLMLL.FixpointIR`** — ADT for the `.fq` constraint language (sorts, predicates, refinements, binders, constraints, qualifiers) + text emitter.
- **`LLMLL.FixpointEmit`** — typed AST walker → `FQFile` + `ConstraintTable` (constraint ID → JSON Pointer). Auto-synthesizes qualifiers from `pre`/`post` patterns, seeded with `{True, GEZ, GTZ, EqZ, Eq, GE, GT}`.
- **`LLMLL.DiagnosticFQ`** — parses `fixpoint` stdout (SAFE / UNSAFE) → `[Diagnostic]` with `diagPointer` (RFC 6901 JSON Pointer) via the `ConstraintTable`.
- **`TSumType` refactor** — structured ADT representation in `Syntax.hs` replacing the previous untyped constructor list. Prerequisite for exhaustiveness checking.
- **`unwrap` preamble alias** — generated `Lib.hs` now exports `unwrap = llmll_unwrap`. Fixes `Variable not in scope: unwrap` GHC errors at call sites.
- **Operator-as-app fix** — `emitApp` now intercepts arithmetic/comparison operators used in `{"kind":"app","fn":"/"}` position and delegates to `emitOp`. Fixes `(/ (i) (width))` fractional-section GHC errors for integer division inside lambdas.
- **`.fq` constructor casing fix** — `emitDataDecl` lowercases ADT sort names and constructor names. Fixes liquid-fixpoint parser rejection of capitalized identifiers (e.g. `X 0` in `[X 0 | O 0]`).

### New Examples

- `examples/conways_life_json_verifier/` — Conway's Game of Life with verified `count-neighbors` and `next-cell` contracts
- `examples/hangman_json_verifier/` — Hangman with verified `apply-guess` pre/post
- `examples/tictactoe_json_verifier/` — Tic-Tac-Toe with verified `set-cell` bounds and `make-board` postcondition

### Spec (LLMLL.md)

- v0.2 scope note updated: Phase 2c complete
- §3.2 — pair-type restriction removed; `[acc: (int, string)]` documented as supported
- §4.2 `letrec` — new section documenting bounded recursion with `:decreases`
- §4.4 Contract Semantics — updated: runtime + compile-time enforcement described
- §5.3 — renamed "Verification (Phase 2b — Shipped)"; documents `llmll verify` command and qualifier synthesis strategy

### Schema (`docs/llmll-ast.schema.json`)

- `hole-proof-required` expression node added with `reason` enum: `manual | non-linear-contract | complex-decreases`


---


## v0.1.3 / v0.1.3.1

### Compiler

- **`first`/`second` pair projectors** — now accept any pair argument regardless of explicit type annotations. Previously a parameter annotated as any type (e.g. `s: string`) that was actually a pair would cause `expected Result[a,b], got string`. The `untyped: true` workaround is no longer required on state accessor parameters.
- **`where`-clause binding variable in scope** — `TDependent` now carries the binding name; `TypeCheck.hs` uses `withEnv` during constraint type-checking. Eliminates `unbound variable 's'` false warnings on all dependent type aliases.
- **Nominal alias expansion** — `TCustom "Word"` is now expanded to its structural body before `compatibleWith`. Eliminates all `expected Word, got string` / `expected GuessCount, got int` spurious errors. All examples now check with **0 errors**.
- **New built-ins** — `(string-trim s)`, `(list-nth xs i)`, `(string-concat-many parts)`, `(lit-list ...)` (JSON-AST list literal node).
- **PBT skip diagnostic** — `llmll test` skipped properties now distinguish between "Command-producing function" and "non-constant expression". `bodyMentionsCommand` heuristic narrowed to only genuine WASI/IO prefixes — eliminates false-positive skips on user-defined functions.
- **Check label sanitization** — `check` block labels containing special characters (`(`, `)`, `+`, `?`, spaces) are now automatically sanitized before being used as Haskell `prop_*` function names. Previously these caused `stack build` failures with `Invalid type signature`.
- **S-expression list literals in expression position** — `[a b c]` and `[]` are now valid in S-expression expression position (not just parameter lists). Desugars to `foldr list-prepend (list-empty)`, symmetric with JSON-AST `lit-list`.
- **`ok`/`err` preamble aliases** — generated `Lib.hs` now exports `ok = Right` and `err = Left` alongside the existing `llmll_ok`/`llmll_err`. Fixes `Variable not in scope: ok` GHC errors on programs using `Result` values.
- **Console harness `done?` ordering** — `:done?` predicate is now checked at the **top** of the loop (before reading stdin) instead of after `step`. Eliminates the extra render that occurred when a game ended.
- **`--emit-only` flag** — `llmll build` and `llmll build-json` accept `--emit-only` to write Haskell files without invoking the internal `stack build`. Resolves the Stack project lock deadlock when build is called from inside a running `stack exec llmll -- repl` session.
- **`-Wno-overlapping-patterns` pragma** — generated `Lib.hs` now suppresses GHC spurious overlapping-pattern warnings from match catch-all arms. Also extended exhaustiveness detection for Bool matches and any-variable-arm matches.
- **JSON-AST schema version `0.1.3`** — `expectedSchemaVersion` in `ParserJSON.hs` and `llmll-ast.schema.json` bumped from `0.1.2` to `0.1.3`. The docs already showed `0.1.3` in examples; now the compiler accepts it.
- **`:on-done` codegen fix** — generated console harness now calls `:on-done fn` inside the loop when `:done?` returns `true`, before exiting. Previously it was emitted after the `where` clause (S-expression path: GHC parse error) or silently omitted (JSON-AST path).

### Spec (LLMLL.md)

- **§3.2** — pair-type issues split into Issue A (pair-type-param, parse error, Fixed v0.2) and Issue B (first/second, Fixed v0.1.3.1)
- **§12** — check label identifier rule added; S-expr list-literal production documented
- **§13.5** — `lit-list` JSON-AST node and S-expr `[...]` syntax documented (v0.1.3.1+)
- **§10** — `:on-done` console harness note updated: callback now fires inside the loop, not after the `where` clause

---

## v0.1.2

### Compiler

- **Haskell codegen backend** — replaces the Rust backend entirely. Generated output: `src/Lib.hs` + `package.yaml` + `stack.yaml`, buildable with `stack build`.
- **JSON-AST input** — `llmll build` auto-detects `.ast.json` extension and parses JSON directly. Avoids S-expression parser ambiguities for AI-generated code.
- **`def-main` support** — new `def-main :mode console|cli|http` entry-point declaration generates a full `src/Main.hs` harness:
  - `:mode console` — interactive stdin/stdout loop with `hIsEOF` guard (no `hGetLine: end of file` on exit)
  - `:mode cli` — single-shot from OS args
  - `:mode http PORT` — stub HTTP server
- **`llmll holes`** — works on files with `def-main` (previously crashed with non-exhaustive pattern)
- **Let-scope fix** — sequential `let` bindings now each extend the type environment for subsequent bindings; unbound variable false-positives eliminated
- **Overlapping pattern fix** — `match` codegen no longer emits a redundant `_ -> error "..."` arm when the last explicit arm is already a wildcard
- **Both `let` syntaxes accepted** — single-bracket `(let [(x e)] body)` (v0.1.2 canonical) and double-bracket `(let [[x e]] body)` (v0.1.1, backward-compat) both compile to identical AST

### Spec (LLMLL.md)

- **§9.5 `def-main`** — fully documented: syntax, all three modes, key semantics, S-expression + JSON-AST examples
- **§12 Formal Grammar** — `def-main` EBNF production added; `def-main` added to `statement` production
- **§14 Migration notes** — corrected: both `let` forms are accepted; not "replaced"

### Examples

- Rust-era examples removed (`tictactoe`, `my_ttt`, `ttt_3`, `tasks_service`, `todo_service`, `hangman_complete`, `specifications/`)
- `examples/hangman_sexp/` and `examples/hangman_json/` added — both compile and run end-to-end
