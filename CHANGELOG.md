# CHANGELOG

---

## Unreleased

### Roadmap — Governing Criterion Disambiguation

- **Governing design criterion (roadmap header)** — Disambiguated the v0.10-era criterion text. Previous wording read as both (a) a design criterion for compiler deliverables and (b) a measurement stop-policy for empirical instruments. The revision preserves (a) as *progress toward one-shot correctness* and removes (b) by explicitly endorsing repair-loop experiments as a measurement regime. Resolves the internal contradiction between the roadmap header (line 6) and the v0.10 OBLIG-B success metric (line 98). Diagnosis and rationale in [`docs/design/empirical-methodology.md`](docs/design/empirical-methodology.md). Unblocks repair-loop experiment design under `experiment-lead`.

### Spec — Naming Conventions

- **`LLMLL.md` §2.5 (new)** — Documents the canonical naming conventions for LLMLL identifiers: kebab-case for functions / variables / parameters; PascalCase for type names and constructors; trailing `?` for boolean predicates; kebab-case for keywords and builtins; lowercase for reserved identifiers (`result`, `unit`, `true`, `false`). Includes a cross-language API translation note: when a language-neutral problem statement uses snake_case or camelCase, the LLMLL solution transliterates to kebab-case. Pedagogical only — the grammar continues to accept both `_` and `-` per §2.1's identifier character class; the convention is stylistic, not syntactic. Closes the gap surfaced by the repair-loop Phase-2.0 probe where agents emitted parseable but non-idiomatic identifiers and consumed evaluation budget on style drift.

### Spec — Match-Arm Surface Form Correction

- **`LLMLL.md` §3.3 / §9 / §13.5** — Corrected the informal `match` examples to use the canonical wrapped match-arm form `(pattern body)`. The §17 grammar (`match-arm = "(" pattern expr ")"`), the parser, the AST (`EMatch Expr [(Pattern, Expr)]`), the JSON-AST schema (`MatchArm = { pattern, body }`), and every shipping example in `examples/` already use the wrapped form; only the informal prose at three sites had drifted to the sibling form `(pattern) body`. Documentation-only — grammar, parser, schema, and examples are unchanged. Closes the spec self-inconsistency surfaced by the repair-loop Phase-2.0 probe (Gemini reproduced the drifted §3.3 surface and hit a parse failure at the first arm body; bisection in [`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md`](experiments/repair-loop/findings/postmortem-001-apparatus-validation.md) Addendum 10).

### Spec — Unit-Payload vs Nullary Constructor Pedagogy

- **`LLMLL.md` §3.2 / §3.3** — Resolved the spec/compiler drift on unit-payload vs nullary sum-type constructor declarations. The §3.3 prose at lines 203/216 promised that variants declared `(| Ctor unit)` would accept the elided match form `((Ctor) body)`; the typechecker at `compiler/src/LLMLL/TypeCheck.hs:1185-1208` treats declared `unit` as a payload type like any other and requires arity-1 match. The forms are observably distinct in the generated Haskell (per Semantic Anchor A in [`docs/design/verification-debate.md`](docs/design/verification-debate.md)): `(| Red unit)` codegens to `data Color = Red () | …` (a constructor of type `() → Color`) while `(| Red)` codegens to `data Color = Red | …` (a constructor of type `Color`) — see `compiler/src/LLMLL/CodegenHs.hs:413-419`. The spec moves to match the compiler: §3.2's "no literal" claim for `unit` is corrected to identify `()` as the unit literal; §3.3's introductory `Color` example is recast in truly-nullary form `(| Red) (| Green) (| Blue)`; §3.3's pattern-arity prose is rewritten so that declared arity equals match arity uniformly; the unit-payload form `(| Variant unit)` is preserved by the parser as a distinct AST shape, but **discouraged** for new declarations (reserved for the narrow case of Haskell-codegen interop where a downstream consumer destructures the `Variant ()` shape directly). Documentation-only — grammar, parser, AST, typechecker, codegen, and schema are unchanged. Discharges the adjacent drift finding surfaced in the R5a doc-lead pass (commit `ecdf42f`); fully closes F-024 acceptance.

---

## v0.10.2 — Soundness Blockers + Diagnostic Surface (2026-05-10)

### Compiler — Delegate Fallback Typechecking

- **`?delegate (on-failure e)`** — fallback expression now typechecked against delegate return type (`TypeCheck.hs` `inferHole HDelegate`). Previously parsed but never visited; ill-typed fallbacks (`Result.Error DelegationError`, unknown identifiers) silently passed.
- **`?delegate-async on_failure`** — rejected at parse time (`ParserJSON.hs`). Use sync `?delegate` with `on-failure`, or handle errors after `(await ...)`.
- **`emitHole (HDelegate spec)`** — codegen routes through fallback when present (`CodegenHs.hs`). Previously emitted unconditional runtime `error`, masking PBT-eligible properties.
- **EHole unification** — `checkExpr` for hole expressions now unifies inferred against expected type. Previously discarded.

### Compiler — PBT Discard Semantics

- **Unevaluable samples** — `runQC` returns `QC.discard` on samples that do not reduce to `LitBool` (`PBT.hs`). Previously defaulted to `True`, silently counting as success.
- **FuncEnv-driven evaluation** — `runPropertyWith` threads a top-level function environment built from `def-logic` statements; property bodies reach user-defined logic.
- **Static evaluator expansion** — `evalExprStaticWith` adds fuel-bounded recursion (`maxFuel = 64`), `ELet`, `EMatch` with pattern bindings, `EHole HDelegate` fallback, and `ok`/`err`/`is-ok` builtin evaluators (`Contracts.hs`). `ok` and `err` canonicalize to internal `Success` and `Error` tags so match patterns evaluate correctly. Pure surface; no VC generation impact.
- **Operator coverage** — `evalOp` now handles `=`/`!=` on `Bool` and `String`.
- **`evalContract` isolation preserved** — contract evaluation continues to use the backward-compatible `evalExprStatic` wrapper (empty `FuncEnv`), so contracts do not silently inline `def-logic` calls.
- **Async PBT limitation** — `?delegate-async` and `await` remain unevaluable in the static evaluator; check blocks involving them report `PBTSkipped`. The async error-recovery path is exercised at runtime via `Result` matching, not compile-time evaluation.

### Compiler — Diagnostic Surface

- **`llmll check` text mode** — accumulated warnings now render on success (`Main.hs doCheck`). Previously suppressed.
- **Dotted fn warning** — `(EApp "Foo.Bar" ...)` warns at typecheck time (`TypeCheck.hs inferExpr`). Suggests `(open <module-path>)` and bare names.

### Schema — JSON-AST v0.4.0

- **`schemaVersion` const bumped 0.3.0 → 0.4.0** to signal new identifier-shape regex constraints. Compiler enforces via `expectedSchemaVersion`. 20 example fixtures updated to match.
- **`ExprApp.fn` regex** — `^[^.]+$`. Permissive on purpose: legal `app.fn` values include operator identifiers (`+`, `-`, `<=`, etc.). Stricter identifier-only validation can land in a future release via `oneOf`.
- **`ExprQualApp.qual_fn` regex** — `^[A-Za-z_][A-Za-z0-9_?\\-]*(\\.[A-Za-z_][A-Za-z0-9_?\\-]*)+$`. Enforces ≥ 1 dot per `LLMLL.md §12` EBNF.

### Spec — Delegate Fallback Typing (§11.2)

- **§11.2 inference rules** — added `?delegate @A "desc" -> T (on-failure e) ⊢ T` with side condition `Γ ⊢ e : T`, alongside the existing rules for `?delegate-async` and `await`. Formalizes the rule the v0.10.1 typechecker silently dropped.
- **§11.2 example fix** — login-handler `(on-failure ...)` example now uses `(err DelegationError)`. The previous `(Result.Error DelegationError)` form was never a registered constructor name and only typechecked via the v0.10.1 fallback dropthrough.

### Spec — Result Patterns and `?proof-required` (§13.8)

- **Three-layer Result rule** — Result values have three distinct surfaces: *construct* via `(ok x)` / `(err e)`, *match* via `Success` / `Error` patterns, *test* via `(is-ok x)`. `Result.Ok` and `Result.Error` are not registered constructor names.
- **`?proof-required` pedagogical hook** — Result-returning function contracts whose postconditions are asserted but unverifiable (delegated calls, nonlinear arithmetic, map invariants) should be marked `?proof-required`. Cross-references the formal definition at §6.

### Spec — JSON-AST Identifier Regex (§12)

- **Grammar Key Rule 9** — JSON-AST identifier shape is schema-enforced via `^[^.]+$` on `ExprApp.fn` (no dots; permissive on character class to admit operator identifiers) and the full identifier regex on `ExprQualApp.qual_fn` (≥ 1 dot, identifier character class per §2.1).

### Spec — Identifier Character Class (§2.1)

- **§2.1 identifier character class** — `?` is now documented as accepted in identifier-terminal position only (e.g., `done?`, `string-empty?`, `is-game-over?`). Documents pre-existing compiler behavior since v0.1.

### Spec — PBT Outcome Reporting (§5.1)

- **§5.1 outcomes table** — `check` blocks report one of `pass` / `fail` / `skip`. A `skip` is not a `pass`. Property bodies that fail to reduce to a literal Bool (delegate without fallback, command constructors, await) are reported `skip` and contribute zero trust evidence.

**Tests:** 584 Haskell (was 570; +14 across delegate / PBT / diagnostic / evalContract isolation), 37 Python.

---

## v0.10.1 — Patch Release (2026-05-09)

### Compiler — `llmll version` Command

- **`llmll version`** — New subcommand prints compiler version and exits. Supports `--json` for `{"version":"…"}` output.
- **`llmll --version`** — Top-level `--version` flag (via `optparse-applicative` `infoOption`) as an alternative to the subcommand.

### Compiler — Exit Code Fixes

- **`doCheck` / `doHoles` exit code** — `llmll check` and `llmll holes` now exit with rc=1 on parse errors. Previously they returned rc=0 silently on `Left ()` (parse failure), while every other command handler correctly used `exitFailure`. `llmll typecheck` (non-sketch) is also fixed since it delegates to `doCheck`.
- **`--help` exit code** — All 17 subcommands (14 top-level + 3 hub sub-subcommands) now respond to `--help` with exit 0. Previously `llmll build --help` treated `--help` as an unknown argument and exited non-zero.

### Compiler — Type Alias Resolution Overhaul

- **Structural + transitive `expandAlias`** — `expandAlias` was non-structural (only resolved outermost `TCustom`) and non-transitive (stopped after one alias hop). Both defects blocked constructor-injection on aliased ADTs. Rewritten to recursively traverse composite type structures (`TList`, `TMap`, `TResult`, `TPair`, `TPromise`, `TFn`, `TSumType`, `TDependent`) and chase alias chains transitively. Per-traversal `Set` cycle guard prevents divergence on cyclic aliases.
- **`compatibleExpanded` helper** — Expand-then-compare helper migrated to 13 direct `compatibleWith` call sites. `checkPattern` now expands scrutinee type at entry, fixing `PConstructor "pair"` against alias-of-`TPair` and `"Success"`/`"Error"` against alias-of-`TResult`.
- **Unsound `TCustom`/`TSumType` bridge removed** — `compatibleWith` no longer treats any `TCustom` as compatible with any `TSumType`. All call sites now expand before reaching `compatibleWith`.
- **Alias-cycle diagnostic** — Alias cycles (e.g., `(type A B) (type B A)`) are detected at `checkStatements` time via graph-based DFS reachability. `TSumType` payloads exempted (recursive ADTs are legitimate self-reference, not alias cycles).
- **Diagnostic preservation** — `unify` reports original (unexpanded) types in diagnostics, preserving alias names like `Color` instead of `(Red | Green | Blue)`.
- **Known regression:** `structuralUnify` (EApp path) shows expanded leaf types in diagnostics instead of alias names. Follow-up needed.

### Compiler — Async Delegate Normalization

- **`?delegate-async` return type** — `return_type` is now the inner type `T`, not `Promise[T]`. The compiler wraps it in `Promise[T]` automatically. A top-level `Promise[...]` in `return_type` is stripped as a legacy compatibility measure. `Promise[Promise[T]]` is a parse error. Both `Parser.hs` and `ParserJSON.hs` updated. Inference rules added to LLMLL.md §11.2.
- **ADT constructor registration** — `collectConstructors` extracts `TFn` bindings from `TSumType` variants. Dual-stage collision detection: Phase 1 catches intra-module duplicate constructors; Phase 2 catches constructor/function shadowing (skips `TCustom` type-namespace entries).
- **`withFunctionContext` combinator** — Structural scope cleanup for `tcCurrentFn` and `tcIsLetrec`, mirroring `withTaggedEnv`. Eliminates false-positive self-recursion warnings on subsequent `SCheck`/`SDefInterface`/`SExpr` statements.

### Compiler — DelegationError Type Normalization

- **`resolveNamedType`** — Both `ParserJSON.hs` and `Parser.hs` now map well-known type names (`"DelegationError"`) to their built-in `Type` constructors (`TDelegationError`) instead of falling through to `TCustom`. Closes the `TCustom`/`TDelegationError` mismatch that caused false type errors when JSON-AST programs used `DelegationError` in type annotations.
- **Disambiguated type mismatch diagnostic** — When `typeLabel` produces identical strings for structurally different types (e.g., `TDelegationError` vs `TCustom "DelegationError"`), the error now appends the internal constructor tag: `expected DelegationError (built-in), got DelegationError (named)`.

### Compiler — Build Fix

- **macOS case-insensitive path warning suppressed** — Moved executable `Main.hs` from `src/` to `app/` so the executable component builds in a separate directory from the library's `LLMLL/` modules. Added `-optP-Wno-nonportable-include-path` and `-optc-Wno-nonportable-include-path` to executable `ghc-options`.

**Tests:** 570 Haskell (was 556; +14 alias resolution tests), 37 Python (unchanged).

---

## v0.10.0 — Obligation-Guided Agent Coding (2026-05-03)

### Compiler — Structured Obligation Reports

- **OBLIG-0** — Design spec for obligation report JSON schema (schema version `0.10.0`). Three channels: type, contract, trust. `EMatch` branch obligations. Repair suggestion generation. Benchmark suite definition.
- **MOD-1** — Cross-module `ContractEnv`: `meContracts` field in `ModuleEnv` (`Syntax.hs`). Populated from `buildModuleEnv`. `ctVerifiedHash` staleness guard for imported `.verified.json` files.
- **OBLIG-1** — Enriched typed holes: `CheckoutToken` extended with contract preconditions, postcondition goal, path condition, assumption set, source/evidence hashes. New fields emitted unconditionally on `llmll checkout`.
- **OBLIG-2** — Goal-state display: `ObligationAssembly.hs` module. Structured JSON obligation report for each `?hole`, each unproven contract clause, and each failed call-site precondition. `assembleReport` top-level entry point. `--obligation-report` flag on `llmll verify`. `GuardClassifier.hs` extracted from `FixpointEmit.hs` for shared guard classification.
- **OBLIG-3** — `EMatch` branch obligations: `assembleBranchObligations` (two-pass, parent-id linkage). `patternBindings` (recursive on `PConstructor`). `lookupConstructorPayload` with alias-aware type resolution. `inferScrutineeType` for `EVar` and `EApp` (builtin lookup via `builtinEnv`). Branch-specific fields (`parent_id`, `branch_index`, `constructor`, `bindings`) conditionally emitted.
- **OBLIG-4** — Repair suggestions: `generateCandidates` in `ObligationMining.hs` (O(n²) bounded arithmetic search, cap-8). `CandidateExpr` type. Pre-filtered via `isIntLike` with `AliasMap` (avoids double-filter bug on dependent type aliases like `PositiveInt`). Wired into `mkHoleObl` for int-typed holes.
- **OBLIG-5** — Repair loop integration: `llmll verify --obligation-report` emits reports end-to-end via `assembleReport`. Trust report records final evidence.
- **OBLIG-B** — Benchmark suite: 3 benchmark programs (`b1-withdraw`, `b3-safe-first`, `b5-double`) with golden tests. Fingerprint stability test (INT-1). 11 new Phase 4 tests.

### Compiler — Function Lists (spec §8)

- **`assembleFunctionLists`** — Contracted functions (user-defined with compatible return types) and available builtins (non-WASI, type-compatible) with cap-8 and truncation signals. `isTypeCompatible` with `AliasMap`, `TVar` wildcard matching, `TDependent` refinement stripping, `TCustom` alias resolution, and `Result` unwrapping. `trustLabel` from `effectiveLevel`. Builtin params populated from `TFn` with positional names.

### Compiler — Bug Fixes

- **F7: Path condition key mismatch** — `holeName` carries `?` prefix; `collectHoleGuards` emits without. Fixed by stripping `?` prefix in consumer. Path conditions were silently empty for all hole obligations.
- **F6: `inferScrutineeType` for `EApp`** — Extended to look up `builtinEnv` for function return types (e.g., `list-head` → `Result[a, string]`). Previously returned `Nothing` for all non-`EVar` scrutinees.
- **R2: `resolveType` strips `TDependent`** — `lookupConstructorPayload` now correctly resolves dependent type aliases when looking up constructor payload types.

### Compiler — New Modules

- **`ObligationAssembly.hs`** — 800+ line module. Obligation report assembly pipeline: hole obligations, branch obligations, constraint obligations, function lists, repair suggestions, JSON encoding. Schema version `0.10.0`.
- **`GuardClassifier.hs`** — Extracted from `FixpointEmit.hs`. Shared guard classification logic used by both the `.fq` emitter (verification) and `ObligationAssembly` (presentation).

### Benchmarks

- **`examples/benchmarks/b1-withdraw.llmll`** — `withdraw` with `PositiveInt` alias (tests type-aware candidate generation)
- **`examples/benchmarks/b3-safe-first.llmll`** — `safe-first` with `EMatch` on `list-head` (tests branch obligations)
- **`examples/benchmarks/b5-double.llmll`** — `double` with single int param (tests `(+ n n)` candidate)

**Tests:** 556 Haskell (was 452; +104 across Phases 1–4), 37 Python (unchanged).

---

## v0.9.0 — Compositional Verification (2026-05-01)

### Compiler — Assume-Guarantee Reasoning

- **COMP-1** — `CallVC` constructor on `BodyVC` ADT (7 record fields: callee, args, preObligation, postAssumption, resultVar, resultSort, continuation). `ContractEnv` type and `buildContractEnv` for extracting contracts from statements. `applySubst` (capture-free predicate substitution, 7 `FQPred` cases). `isConstructorDependent` (TCB guard for constructor-dependent postconditions, Issue 2). `bodyToPredM` extended with `ContractEnv` + `Set Name` (SCC set). EApp case with three-way pre distinction (Issue 1): no pre → pass, translatable pre → obligation, untranslatable pre → fallback. `CallVC` returned directly from EApp (Issue 3). SCC guard removed — callers may use assume-guarantee against recursive functions' contracts (Issue 4). `ELet` continuation threading for `CallVC` RHS. `flattenBodyVC`/`countPathsBounded`/`prependLB` extended for `CallVC`. `collectCallPreObligations` helper. Call-pre constraint emission with PROVE polarity. `EmitResult.erCallPreFns` tracking.
- **COMP-2** — SCC detection via `Data.Graph.stronglyConnComp` in `emitFixpointWith`. Exported `buildCallGraph` from `HoleAnalysis.hs`. Recursive functions excluded from body VCs.
- **COMP-3** — `EMatch` on `Result a e` (two-path encoding): `classifyResultArms` (detects Success/Error two-arm pattern in either order), synthetic boolean guard `_match_success_N`, sort derivation from `ContractEnv` `TResult okType errType` (Issue 5), `setCallVCContinuation` for EMatch-over-call desugaring (§5.4). Falls back on non-Result types, non-two-arm matches, complex scrutinees.
- **COMP-5** — `call-pre:` tag in `ConstraintOrigin` (`DiagnosticFQ.hs`). `toDiag` mapping for UNSAFE call-site preconditions. Structured error: "call-site precondition of '<callee>' not satisfied in '<caller>'." Call-pre obligation reporting in verify output.
- **COMP-6** — `--strict-verified-core` CLI flag: hard-error if any function is in `erBodyFallback`. JSON and text error output with fallback function names.
- **COMP-T** — 18 COMP golden tests: `applySubst` (4), `isConstructorDependent` (3), `bodyToPredM` with `ContractEnv` (4), `collectCallPreObligations` (2), end-to-end call-pre emission (1), `EMatch` on Result (4). **452 total tests passing** (434 → 452).

### Design

- **COMP-0** — Design spec `docs/design/comp-0-spec.md` produced and approved (Rev 2). Five soundness issues resolved: three-way pre distinction, constructor-dependent postcondition guard, CallVC direct return, SCC guard relaxation, sort derivation from ContractEnv.

### v0.10 Carryover

> **v0.10 carryover:** COMP-5 structured repair suggestions, 13 remaining golden tests (stripping regression, trust degradation chains), and `--strict-verified-core` post-solver enforcement are deferred to v0.10 (Obligation-Guided Agent Coding).

---

## v0.8.1b — Evidence Model Refactor (2026-05-01)

### Compiler — DisplayLevel Diamond Lattice

- **EVID-1** — `VerificationLevel` total order replaced with `DisplayLevel` partial-order diamond lattice in `Syntax.hs`. Four tiers: `DLVerified > DLContractChecked ∥ DLTested > DLAsserted`. `EvidenceRecord` type (display level + body-faithful flag + source provenance). `AssumptionKind` taxonomy (`AKRuntimePrimitive`, `AKCompilerBuiltin`, `AKExternalOpaque`). `ContractStatus` restructured to `csPre`/`csPost` (`Maybe EvidenceRecord`) + `csAssumptions`. `evidenceMeet` (GLB), `evidenceCovers` (partial-order check), `isSolverBacked`, `isVerifiedLevel`, `dlLabel`.
- **EVID-1a–1e** — Consumer modules updated: `ProofCache.hs`, `AstEmit.hs`, `TypeCheck.hs`, `Parser.hs`, `ParserJSON.hs`, `ObligationMining.hs`.
- **EVID-2** — `VerifiedCache.hs` rewritten with `EvidenceRecord`/`DisplayLevel`/`AssumptionKind` JSON serialization. Hard break: old `.verified.json` files return empty map (no backward compatibility).
- **EVID-3** — `TrustReport.hs` refactored: `TrustEntry` uses `Maybe EvidenceRecord`, `TrustSummary` has 6 fields (adds `tsContractChecked`), `effectiveLevel` uses `evidenceMeet`.
- **EVID-4** — `SpecCoverage.hs` refactored: `FunctionEntry` uses `Maybe DisplayLevel`, summary adds `csVerified`/`csContractChecked'`.
- **EVID-5** — `Contracts.hs` updated: `filterContracts` checks `isVerifiedLevel && erBodyFaithful`.
- **EVID-6** — `Module.hs` updated: `mkCS`/`mergeCS` use `EvidenceRecord` and `evidenceCovers`.
- **EVID-7** — `Main.hs` updated: verify pipeline builds `EvidenceRecord (DLVerified "liquid-fixpoint") True`.
- **FixpointEmit.hs** — `erBodyFaithful` renamed to `erBodyFaithfulFns` to resolve name collision with `EvidenceRecord.erBodyFaithful`.
- **EVID-T** — All 322 tests updated and passing. Replaced `vlTier`/`trustCovers` tests with `evidenceCovers`/`evidenceMeet` lattice tests.

### Design

- **EVID-0** — Design spec `docs/design/evid-0-spec.md` produced and approved.

---

## v0.8.1a — Documentation Boundary Clarity (2026-04-30)

### Spec (LLMLL.md)

- **RENAME-1** — §3.4 heading renamed from "Dependent Types (Logic-Constrained)" to "Refinement Type Aliases (Logic-Constrained)." Removed prose comparing LLMLL to Idris or Lean for dependent elimination. LLMLL has no dependent types — the terminology now accurately reflects refinement-like annotations.
- **MATRIX-1** — §5.3.5 per-construct verification matrix added (17 rows × 6 columns: typechecked, runtime-asserted, SMT contract, SMT body-faithful, QuickCheck, fallback).
- **BOUNDARY-2** — Integer overflow model gap documented in §5.3.5: Z3 reasons over mathematical integers; Haskell `Int` wraps at 2⁶³.

### README.md

- **MATRIX-2** — Compressed verification matrix added to "Verification Boundary" section.

### One-Pager (docs/one-pager.md)

- **RENAME-2** — Removed Idris/Lean comparison; reworded to "Inspired by refinement types (Liquid Haskell)."
- **MATRIX-3** — Compressed verification matrix added.
- **BOUNDARY-1** — Status section now leads with the QF-LIA boundary sentence.
- **ROADMAP-2** — What's Next table updated with v0.8.1a/v0.8.1b/v0.9 milestones.

### Roadmap (docs/compiler-team-roadmap.md)

- **ROADMAP-1** — Roadmap restructured with v0.8.1a/v0.8.1b/v0.9 plan. Feature freeze policy. Critical path diagram updated. Old v0.8.1 items moved to parking lot.

**No code changes. No test changes. Zero regression risk.**

---

## v0.8.0 — Faithfulness Core (2026-04-29)

### Compiler — Body-Faithful Verification Conditions (BODY-VC)

- **BODY-VC-1** — `bodyToPred` for QF-LIA fragment. Encodes `ELet` (with alpha-renaming for shadowed variables), `EIf` (path-sensitive constraint emission), and linear arithmetic as `.fq` body verification conditions. Conservative `Nothing` fallback for unsupported constructs (`letrec`, `EMatch`, non-linear expressions). Path limit: >4096 execution paths trigger fallback with diagnostic warning.
- **BODY-VC-2** — Wired into `emitFnConstraints` in `FixpointEmit.hs`. When `bodyToPred body = Just bvc`, flattened paths emitted as `.fq` constraints. EIf-in-let hoisting (conservative single-path). Early-exit fix: replaced no-op `when (cond) $ return ()` with actual `if/then/else/do` short-circuit.
- **BODY-VC-3** — Postconditions marked body-faithful per function via `csPostBodyFaithful` field in `ContractStatus` (`Module.hs`). `Contracts.hs` strips postcondition assertions only when `VLProvenSMT ∧ csPostBodyFaithful = True`. Preconditions never stripped.
- **BODY-VC-T** — 25 new tests: T01–T05 (body-VC golden), F01–F03 (fallback), N01–N04 (negative), P01–P04 (parsed-source), T11 (SUPP-DEBT), plus SortEnv, Parens, Flatten, E08 edge cases.

### Compiler — Soundness Fixes

- **EOp delegation** — `exprToPred (EOp op args) = exprToPred (EApp op args)`. The parser emits `EOp` for operators, but `exprToPred` only handled `EApp`. Contract clauses using operators were silently skipped and falsely marked as proven.
- **`!=` operator** — Added to both `exprToPred` and `lookupPredOp` (parser emits `!=`, not `/=`).
- **Clause-level emission tracking** — `erEmittedPre`/`erEmittedPost` fields in `EmitResult`. Sidecar generation checks membership before promoting to `VLProvenSMT`; skipped clauses remain `VLAsserted`.

### Compiler — Spec Coverage

- **SUPP-DEBT** — `spec_coverage` (contracted / total) and `suppression_debt` (suppressed / total) fields added to `--spec-coverage` JSON output alongside existing `effective_coverage`.

### Compiler — Verify JSON

- Verify JSON output now includes `body_faithful` and `body_fallback` metadata per function.

### Spec (LLMLL.md)

- §0.1 — Semantic foundation section added
- §4.4.1 — Body-faithfulness caveat added to trust tier documentation
- §5.3.2 — SUPP-DEBT fields documented in spec coverage JSON example
- §5.3.4 — New section: Body-Faithful Verification (BODY-VC coverage, path limit, two-tier status)

**Tests:** 320 Haskell (was 294; +26), 37 Python (unchanged).

---

## v0.7 — Hardening (2026-04-29)

### Compiler — Builtin Hardening

- **BUILTIN-2** — `string-char-at` negative index guard. Added `i >= 0` check to prevent negative index crash. The function now returns `""` for out-of-bounds indices in both directions.
- **BUILTIN-1** — `regex-match` → POSIX ERE via `regex-tdfa`. Replaces the `isInfixOf` stub with proper regex matching. Invalid patterns are caught via `unsafePerformIO`/`try`/`evaluate` and return `False` (total function). `PREAMBLE COMPROMISE` comment explains the `unsafePerformIO` usage. Import cleanup: removed `isInfixOf`; added `evaluate`, `Text.Regex.TDFA`, `System.IO.Unsafe`. Added `regex-tdfa` to generated `package.yaml` dependencies.

### Compiler — Do-Block Diagnostic

- **DO-1** — Discarded command warning. Intermediate `TCustom "Command"` types in `do`-blocks now emit a warning: "current codegen discards" (blames codegen limitation, not user). Step 0 now binds `cmd0` (was `_`); recursive steps bind `cmdTy` (was `_`). `checkDiscardedCommand` helper in `TypeCheck.hs`. Warning-only in all modes; hard error deferred to v0.8 (DO-2: `(discard expr)`).

### Compiler — Trust Model Refinement

- **TRUST-2a** — `VLProvenSMT` constructor + `Ord` instance removal. Added `VLProvenSMT { vlSMTSolver :: Text }` to `VerificationLevel`. Removed `instance Ord VerificationLevel` — replaced with explicit preorder helpers: `trustCovers` (was `>=`), `trustMin` (was `min`), `isProvenLevel`, `vlProverName`. All four helpers exported from `Syntax`. 10 consumer files updated: `TypeCheck.hs`, `TrustReport.hs`, `SpecCoverage.hs`, `AstEmit.hs`, `Contracts.hs`, `VerifiedCache.hs`, `Main.hs`, `ProofCache.hs`, `Module.hs`. `.verified.json` serializes as `"proven-smt"`.

### Spec (LLMLL.md)

- §4.4.1 — Trust tier vs. evidence provenance note + body-faithfulness caveat added
- §13.6 — `string-char-at` and `regex-match` documentation updated

### Discovered Issues (not in original plan)

- **Module.hs `mergeCS`** — Used `max` on `VerificationLevel`, which depended on the removed `Ord` instance. Fixed with explicit `vlTier` comparison. Not caught in the original 18 planned consumer sites because it appeared in the module loader.
- **Spec.hs `compare` tests** — Five tests tested the `Ord` instance via `compare`. Replaced with `vlTier`/`trustCovers`/`isProvenLevel` tests. Added `VLProvenSMT` tier equality test.
- **Spec.hs round-trip test** — Used `VLProven "liquid-fixpoint"` which now serializes as `"proven-smt"`. Updated to `VLProvenSMT`.

**Tests:** 294 Haskell (was 289; +5 trust-tier tests), 37 Python (unchanged). Build compiles cleanly (`stack build`, no `Ord` residuals).

---

## Pre-v0.7 Hygiene (2026-04-28)

> Items from the external consultant review (2026-04-28). Not a versioned release — these are test drift and documentation drift fixes applied before starting v0.7.

### Test — TEST-DRIFT

- **Python dry-run fixture updated** — Stub plan in `agent.py:385` defined `stub-fn` with no contract, which was rejected by the spec-quality gate added in v0.6.0. Fixture now includes a minimal `(post true)` contract.

### Spec (LLMLL.md) — DOC-DRIFT

- **§5.3.2 JSON example reconciled with `SpecCoverage.hs`** — The spec described `suppression_debt` and `spec_coverage` as current JSON fields, but `SpecCoverage.hs` only emits `effective_coverage`. Fixed: JSON example updated to match the actual `summary`/`entries`/`laws`/`warnings` envelope emitted by `formatCoverageJson`. Deferred fields (`suppression_debt`, `spec_coverage`) moved to a "Planned (v0.8.0, SUPP-DEBT)" note.

---

## v0.6.3 — Trust Model Fixes (2026-04-26)

### Compiler — Trust Model Hardening

Seven critical bugs from the v0.6.3 engineering audit, all resolved:

- **BUG-1** — `result` removed from precondition environments (`TypeCheck.hs`). `result` in a `pre` clause is now a hard error per §4.3. `exprContainsVar` helper validates recursively.
- **BUG-2** — Contract instrumentation wired into `doBuild`/`doBuildFromJson`/`doRun`. `instrumentContracts` replaces `applyContractsMode` in the build pipeline. `CodegenHs.hs` lowers `(runtime-error msg)` to Haskell `error msg`.
- **BUG-3** — Transitive trust closure (`TrustReport.hs`). Fixed-point iteration via `transitiveClose` computes the full reachable set. `enrichEntry` recomputes drifts and `teEffectiveLevel = min(self, transitive deps)`. JSON output includes `effective_level`.
- **BUG-4** — Typecheck gate before codegen. `typeCheckStrict`/`typeCheckStrictWithCache` enforce hard errors on unbound variables, unknown functions, type mismatches, and unknown operators. `doBuild`, `doBuildFromJson`, `doRun`, and `doVerify` all gate on strict typecheck. `llmll check --strict` CLI flag added.
- **BUG-5** — Termination documentation corrected (`LLMLL.md` §4.2, §5.3.3). Claims of "verified automatically" replaced with accurate "checked for non-negativity (`n ≥ 0`)". Strict descent encoding deferred to v0.7 research track.
- **BUG-6** — Body-faithfulness guard on contract stripping (`Contracts.hs`). `filterContracts` now only strips `VLProven` clauses when `isBodyFaithful` returns `True` (currently returns `False` for all provers). Prevents unsound assertion removal.
- **BUG-7** — Proof laundering protection (`ProofCache.hs`). `isTaintedProof` detects `sorry`/`mock`/`admit` in proof text. `proofToLevel` caps tainted proofs at `VLAsserted`. Mock prover tagged `"mock"` instead of `"leanstral"`.

### Compiler — Strict Mode (`tcStrictMode`)

- **`TCState.tcStrictMode`** — New field. When `True`, `tcWarnOrError` emits errors instead of warnings at four permissive sites (unbound variables, unknown functions, unknown operators, branch type mismatch).
- **`typeCheckStrict`** — Strict counterpart to `typeCheck` (no module cache).
- **`typeCheckStrictWithCache`** — Strict counterpart to `typeCheckWithCache`.
- **`llmll check --strict`** — CLI flag for CI gates on completed programs.

### Spec (LLMLL.md)

- §4.2 — Termination claims corrected (non-negativity only, not strict descent)
- §5.3.3 — Verification-scope matrix updated to reflect actual capability

**Tests:** 289 examples, 0 failures. ERC-20 (11/11) and TOTP (14/14) benchmarks green.

---

## v0.6.2 — Algebraic Interface Laws (2026-04-24)

### Compiler — Interface Laws (`def-interface :laws`)

- **`:laws` clause** — `def-interface` gains an optional `:laws` section containing `(for-all ...)` algebraic properties. Laws are first-class: parsed, type-checked (methods + bindings in scope), and enforced via QuickCheck codegen.
- **`Syntax.hs`** — `defInterfaceLaws` field changed from `[Expr]` to `[Property]` (LAWS-1).
- **`Parser.hs`** — `:laws [(for-all [x: T] expr)]` clause parsing (LAWS-2).
- **`ParserJSON.hs`** — `parseLawProperty` for JSON-AST law round-trip (LAWS-3).
- **`TypeCheck.hs`** — `for-all` law expressions type-checked with interface methods and bindings in scope (LAWS-4).
- **`CodegenHs.hs`** — QuickCheck `prop_` function emission for each law property (LAWS-5).
- **`AstEmit.hs`** — JSON-AST law emission for round-trip compatibility (LAWS-6).
- **`SpecCoverage.hs`** — Separate "Interface laws" section in spec coverage report (LAWS-7).
- **`PBT.hs`** — Interface laws wired into `runPropertyTests` (LAWS-PBT).

### Compiler — Verification-Scope Matrix Backfill

- **VSM-1** — All three verifier examples (`hangman_json_verifier`, `tictactoe_json_verifier`, `conways_life_json_verifier`) now have `VERIFICATION_SCOPE.md` files documenting per-function classification and verification boundary.

### Spec (LLMLL.md)

- §8.8.1 — New section: `def-interface :laws` syntax and semantics
- §14 — v0.6.2 roadmap section marked ✅ Shipped

**Tests:** 279 → 289 Haskell (+10: T1–T10 interface laws), 37 Python (unchanged).

---

## v0.6.1 — TOTP Benchmark & Hub Query (2026-04-23)

### Compiler — Cryptographic Builtins (§13.11)

- **`hmac-sha1`** — New builtin: `bytes[20] → bytes[20] → bytes[20]`. RFC 2104 HMAC with SHA-1. Preamble implementation in `CodegenHs.hs` using `Data.Bits.xor`.
- **`sha1`** — New builtin: `bytes[20] → bytes[20]`. Simplified SHA-1 stub. Returns 20 bytes derived from input.
- **Agent spec** — Both builtins auto-reflected in `llmll spec` output.

### Compiler — TOTP RFC 6238 Benchmark

- **`examples/totp_rfc6238/totp.ast.json`** — Skeleton with 6 functions (all holes), RFC `:source` annotations, 100% effective spec coverage.
- **`examples/totp_rfc6238/totp_filled.ast.json`** — Complete implementation with 4 check blocks (RFC 6238 §A.1 test vectors, reflexive validation, padding).
- **`examples/totp_rfc6238/EXPECTED_RESULTS.json`** — Frozen expected results for CI regression.
- **`scripts/benchmark-totp.sh`** — CI gate script (14 assertions: parse, spec coverage, trust report, provenance, scope matrix, check blocks).
- **`make benchmark-totp`** — Makefile target. `make benchmark-all` now runs both ERC-20 (11) and TOTP (14) gates.

### Compiler — Hub Query-by-Signature

- **`LLMLL.HubQuery`** — New module. Brute-force scan of `~/.llmll/modules/` for functions matching a type signature.
- **`structuralMatch`** — Structural type matching: TVar wildcards, TDependent stripping, order-sensitive parameter matching.
- **`llmll hub query --signature "int -> int -> int"`** — New CLI subcommand (text + JSON output).
- **`CheckoutToken.ctHubSuggestions`** — New `Maybe [QueryResult]` field for checkout-time hub suggestions (HUB-3).

### Compiler — v0.6.0 Carryover

- **PROV-3** — `:source` annotations now displayed in `--trust-report` text output (`formatEntry`) and JSON output (`entryJson`).
- **BM-4** — ERC-20 CI gate (`scripts/benchmark-erc20.sh`, `make benchmark-erc20`) with 11 frozen assertions.

---

## v0.6.0 — Specification Quality (2026-04-22)

### Compiler — Spec Coverage Gate

- **`SpecCoverage.hs`** — New module. Classifies every function in a module as **contracted** (has `pre`/`post`), **suppressed** (has `weakness-ok`), or **unspecified**, then computes the effective coverage ratio. Used by `llmll verify --spec-coverage`.
- **`llmll verify --spec-coverage`** — New flag. Walks `[Statement]`, counts `SDefLogic`/`SLetrec` with/without contracts, cross-references `.verified.json` sidecar for verification levels. Emits coverage report with per-function breakdown (text and JSON).
- **`effective_coverage` metric** — Formula: `(contracted + suppressed) / total_functions`. SC-PO-1: division guard — 0 functions → 100%.
- **Governance guardrails** — WO-1 (`W601`): `weakness-ok` target doesn't match any function. WO-2 (`W602`): function has contracts AND `weakness-ok` (contracts take priority). D10 (`W603`): more than 50% of functions are suppressed.

### Compiler — Suppression Governance (`weakness-ok`)

- **`SWeaknessOk` AST node** — New `Statement` constructor: `SWeaknessOk { weaknessTarget :: Name, weaknessReason :: Text }`.
- **`(weakness-ok fn-name "reason")`** — S-expression parser support. Mandatory non-empty reason string (empty reason is a parse error).
- **JSON-AST support** — `ParserJSON.hs` accepts `{"kind": "weakness-ok", "name": "...", "reason": "..."}`.
- **Integration** — Handled in `TypeCheck.hs` (no-op), `CodegenHs.hs` (no-op), `AstEmit.hs` (round-trip), `HoleAnalysis.hs` (excluded from hole analysis).
- **TrustReport integration** — `--trust-report` output includes an "Intentional Underspecification" section listing all `weakness-ok` declarations with reasons. JSON output includes `suppressions` array.

### Compiler — Clause-Level Provenance (`:source`)

- **`:source` annotation** — S-expression syntax: `(pre expr :source "RFC 8446 §7.1")` and `(post expr :source "safety invariant")`. JSON-AST: `"pre_source"` / `"post_source"` optional string fields.
- **`contractPreSource` / `contractPostSource`** — New `Maybe Text` fields in `Contract` (`Syntax.hs`). Per-clause provenance, not per-contract.
- **`csPreSource` / `csPostSource`** — New `Maybe Text` fields in `ContractStatus` for sidecar persistence and trust report threading.
- **Multiple pre clauses** — When multiple `(pre ...)` clauses are combined with `and`, the `:source` annotation is dropped (ambiguous provenance).
- **Backward compatible** — Omitting `:source` yields `Nothing`. No effect on type checking, verification, or codegen.

### Compiler — ERC-20 Benchmark

- **`examples/erc20_token/`** — Frozen benchmark with 4 files:
  - `erc20.ast.json` — Full ERC-20 skeleton with 6 typed functions and contracts
  - `erc20_filled.ast.json` — Filled version with implementations
  - `EXPECTED_RESULTS.json` — Ground truth: verification-scope matrix (10 properties), expected spec coverage (100%), weakness check (no weak functions), trust report
  - `WALKTHROUGH.md` — End-to-end: external spec → LLMLL contracts → verified code → weakness detection → spec coverage

### Spec (LLMLL.md)

- §4.5 — New section: `weakness-ok` syntax and governance rules
- §5.4 — New section: `--spec-coverage` command and effective coverage formula
- §4.1 — `:source` annotation documented in contract syntax
- §14 — v0.6.0 roadmap section marked ✅ Shipped
- Release history table — v0.6.0 entry added

**Tests:** 264 → 279 Haskell (+15: 4 `:source` annotation, 11 spec coverage + weakness-ok), 37 Python (unchanged).

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
