# CHANGELOG

---

## Unreleased

### Compiler — NIW: path-(a) measure emission + non-int refinement widening Phase 1 (2026-06-13)

- **Measure-class refinement predicates now verify body-faithfully** (commits [`1b21973`](compiler/src/LLMLL/FixpointIR.hs), [`a0f352b`](compiler/src/LLMLL/FixpointEmit.hs), [`0a3c5c2`](compiler/src/LLMLL/FixpointEmit.hs)). Predicates using `string-length` / `list-length` with QF-LIA arithmetic on their integer images previously routed to runtime (`exprToPred` returned `Nothing`); they now emit as uninterpreted-function applications with **ground range facts** (`(strLen t) >= 0` per occurring measure-term — REF-META-2 §4 local-theory-extension discipline, not a quantified axiom), discharged as QF-LIA+EUF. Implements the path-(a) axiomatization that [`LLMLL.md §3.4.4`](LLMLL.md) / `§5.3.3` (REF-META-3 / REF-META-2) were written ahead of.
- **`.fq` IR gains uninterpreted functions** (Commit A, inert): `FQApp` term node, `FQConstant` function-sorted declarations, `FQStr`/`FQList` opaque carrier sorts. Measure-free programs emit byte-identical `.fq`.
- **Refinement-aliased params verify** (Commit C, F-NIW-1 elim-side): a param of measure-refined-alias type (`w: Word`) gets its carrier sort and its predicate folded into the effective precondition, assumed in the body VC. Stacked aliases (`NonEmptyWord` over `Word`) conjoin both predicates at one witness (`§3.4.4`). Refined `int` params get full intro+elim (call-pre proves them).
- **Intro-side call-pre for measure-refined params** (F-NIW-2, commit [`0b05916`](compiler/src/LLMLL/FixpointEmit.hs)): a caller passing a value to a `Word`-typed param now proves the refinement at the call site (carrier-aware call-argument translation + caller-side carrier binding; also closes a latent `applySubst` gap that left measure-application args un-substituted). Measure-refined params get **full intro+elim**, matching `int`-refined — NIW Phase 1 caller-side complete.
- **Identifier sanitization** (F-NIW-3, commit [`25c489d`](compiler/src/LLMLL/FixpointIR.hs)): LLMLL identifiers admit `-` / `.` / `?` (`Lexer.hs`), but liquid-fixpoint's lexer accepts only `[A-Za-z0-9_]` — a kebab-case function/param/var name with a comparison clause crashed the solver at parse (`unexpected '-'`). Names are now mapped to legal identifiers at the single `.fq` emission chokepoint (`FixpointIR.hs`), covering qualifier names, binders, references, `freshName` result vars, and type/constructor names; identity on already-legal names, so existing `.fq` output is byte-identical. Surfaced during NIW, not NIW-caused. No JSON-AST schema change. **Tests: 831 Haskell + 62 Python** (inherited from engineer `stack test`).

---

<a id="Latest"></a>

## v0.11.2 — Checkout Context Population (OBLIG-1) (2026-06-11)

### Compiler — OBLIG-1: `llmll checkout` returns the per-hole brief inline (2026-06-11)

- **`llmll checkout` now emits the hole's contract + typing context inline** instead of `null` (commit [`f2262c5`](compiler/app/Main.hs)). `doCheckout` runs parse + sketch type-check — no constraint emission, no solver, so checkout stays at type-check cost — and populates `contract_pre`, `postcondition_goal`, `path_condition` via the new shared extractor [`ObligationAssembly.holeContractBrief`](compiler/src/LLMLL/ObligationAssembly.hs) (reusing the same `enclosingFunc` / `findFunctionInfo` / `collectHoleGuards` / `exprToSExpr` primitives as `mkHoleObl`), plus `in_scope` and `type_definitions` via the Phase-C `buildScopeEntries` / `collectTypeDefinitions` producers — the C3 `Main.hs` threading marked done but never landed. Closes the **OBLIG-1 population gap**: this per-hole brief was previously delivered only by `verify --obligation-report` (OBLIG-2), which remains the whole-program view (all holes, unproven contracts, call-site failures, `refuted_fns`, cross-module).
- **Reserved, not yet populated:** `expected_return_type` and `available_functions` (require sketch-mode hole-type capture in `SketchHole`; `available_functions` additionally depends on the former for monomorphization), and `assumptions`. Cross-module hole scope uses single-file scope. All additive — populating them later needs no token-shape change. `LLMLL.md §11.2` marks these fields reserved.
- **Schema: none.** The OBLIG-1 `CheckoutToken` fields exist since v0.10; the checkout response is a CLI payload, not JSON-AST. `schemaVersion` stays `0.6.0`; `trust_report_version` stays `1.3.0`.
- **4 new tests** (OBR-1..OBR-4 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)): `holeContractBrief` on a contracted hole (pre + post, empty path), a contract-free hole (all empty), a branch hole (path condition surfaced), and an unknown pointer (empty brief). **Tests: 807 → 811 Haskell + 62 Python.**

**Tests: 811 Haskell + 62 Python.**

---

## v0.11.1 — Verify Fail-Open Closure + Schema-Gap Catch-Up (2026-06-06)

### Compiler — VERIFY-RPT-1: verify reporting fail-open + refuted trust status (2026-06-06)

- **`llmll verify` no longer fails open on UNSAFE** (commit [`b914587`](compiler/app/Main.hs)). `fqResultToReport (FQUnsafe …)` set `reportSuccess = null diags`, so an UNSAFE verdict whose constraint ids did not resolve (the text scrape of liquid-fixpoint's ANSI `Unsafe:` banner yielded `FQUnsafe []`) projected `success:true`, exit 0, empty diagnostics. Now `reportSuccess = False` unconditionally on `FQUnsafe`, a function-level fallback diagnostic (pointer `/statements/N/body`) is synthesized when no id resolves, and `doVerify` routes the exit through the `FQVerifyResult` constructor — not the lossy `reportSuccess` projection.
- **`fixpoint -q --json` for pointer recovery.** `doVerify` and `PatchApply.reVerify` now invoke the solver with `-q --json`; `DiagnosticFQ.parseFQResultJSON` decodes the tag-keyed envelope (`{"tag":"Unsafe","contents":[stats,[ids]]}`) so unsafe ids resolve to `/statements/N/body` source pointers. Also populates the previously-empty `PatchVerifyError` payload. Text `parseFQResult` retained as fallback.
- **`--trust-report` surfaces `verified` again** (Defect 2). `VerifiedCache.sidecarNeedsRevalidation`'s INT-1 field-absence trigger invalidated every v0.11 verified sidecar (LT-INT legitimately omits `overflow_tainted`), so `loadVerified` returned `Map.empty` and the report rendered `asserted`. The field-absence trigger is disarmed; an in-code trip-wire pins re-arm to `machine-int`/INT-3 via a codegen-semantics-version check, not field-absence.
- **`refuted` trust status + `--strict-verified-core` solver-verdict conjunct** (spec companion [`verified-contract-refuted-status-proposal.md`](docs/design/verified-contract-refuted-status-proposal.md), settled). A body-faithful function the solver reports UNSAFE is now *refuted* — distinct from `asserted`. `--strict-verified-core` refuses it transitively (assume-guarantee). `refuted` is an orthogonal verify-time status (not a `DisplayLevel`; `evidenceMeet`/`evidenceCovers` unchanged), surfaced as per-entry `refuted`, top-level `refuted_fns`, and a `depends-on-refuted` drift. Not persisted to `.verified.json`. **`trust_report_version` `1.2.0` → `1.3.0`** (additive). The `--trust-report`/`--obligation-report`/`--cdp` early exits are deferred under strict mode so the gate is reachable.
- **8 new tests** (VR-1..VR-8 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)); T13 updated to assert the corrected non-invalidation. No JSON-AST schema change. **Tests: 801 Haskell + 62 Python.**

### Schema — LT-INV schema-update subtask: DefCore/DefShell (2026-06-02)

- **`docs/llmll-ast.schema.json`: `DefCore` and `DefShell` definitions added to `$defs`; `Statement.oneOf` updated; `DefLogic` deprecated** (commit [`d3de0da`](compiler/test/Spec.hs)). Under `GrammarCoreInversion` (default since v0.11), `{"kind":"def-logic"}` was rejected by the compiler but `DefLogic` was still the only function-definition node in the schema — any LLM generating from the schema produced files the compiler rejected with `core-grammar-violation`. Closes the LT-INV schema-update subtask recorded in [`docs/design/core-shell-inversion-proposal.md`](docs/design/core-shell-inversion-proposal.md) Rev 4.
- **`DefCore`** (`kind:"def"`; required: `kind, name, params, body`; optional: `pre, post, spec_entropy`): strict-core function node. Description cites the core-body whitelist and the `GrammarCoreInversion` default. Two `examples` blocks added (`withdraw`, `clamp`).
- **`DefShell`** (`kind:"def-shell"`; same required/optional fields): permissive-shell function node. Description notes lambda, recursion, `wasi.*`, `?proof-required` are admitted. One `examples` block added (`factorial` with self-recursive call).
- **`DefLogic`** (`kind:"def-logic"`): retained in `$defs` with a `DEPRECATED — v0.11 (LT-INV)` description header; **removed from `Statement.oneOf`**. Schema validators now reject `kind:"def-logic"` (no matching `oneOf` branch); the compiler already rejected it since v0.11. Will be removed from `$defs` entirely in v0.12.
- **`spec_entropy` field** added to `DefCore` and `DefShell` (backfills the LT-CDP JSON-AST gap: `ParserJSON.hs:parseDefCore/parseDefShellJSON` accepted `spec_entropy` via `.:?` since LT-CDP shipped, but `additionalProperties: false` in the old `DefLogic` definition blocked schema-conforming files from including it).
- **`TrustDecl` description** updated: "Must appear before any def-logic" → "Must appear before any `def` or `def-shell` function declaration."
- **`schemaVersion` const and `$id` URL unchanged** (`"0.6.0"`, `/schemas/v0.6/`). DRIFT-CI-1 C3/C4 PASS confirmed by `scripts/version_gate.sh`.
- **4 new tests** (SCHEMA-1..4 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)): SCHEMA-1 `kind:"def-shell"` parses as `SDefShell` under `GrammarCoreInversion`; SCHEMA-2/3 `spec_entropy` round-trip for `def` and `def-shell`; SCHEMA-4 `kind:"def-logic"` diagnostic carries suggestion referencing `def`/`def-shell`. **Tests: 793 Haskell + 62 Python.**

### Schema — WeaknessOkDecl v0.6 schema gap closure (2026-06-06)

- **`docs/llmll-ast.schema.json`: `WeaknessOkDecl` added to `$defs` and `Statement.oneOf`** (commit [`6af4975`](compiler/src/LLMLL/ParserJSON.hs)). `kind:"weakness-ok"` was dispatched by `ParserJSON.hs:179` and emitted by `AstEmit.hs:200-202` since v0.6.0, but was absent from `Statement.oneOf` — `examples/totp_rfc6238/totp.ast.json` and `totp_filled.ast.json` failed external JSON Schema validation, and any LLM generating from the schema could not produce a conforming `weakness-ok` node. `WeaknessOkDecl` requires `kind, name, reason`; `reason` carries `minLength: 1`, aligning the schema with `LLMLL.md §4.5:621` ("the parser rejects bare `weakness-ok` without a reason string"). `schemaVersion` unchanged at `"0.6.0"`.
- **Empty-reason guard added to `parseWeaknessOkDecl`** ([`compiler/src/LLMLL/ParserJSON.hs:397`](compiler/src/LLMLL/ParserJSON.hs)). The S-expression parser (`Parser.hs:447`) has enforced non-empty reason since v0.6; the JSON path did not — `{"reason":""}` was silently admitted. `when (T.null reason) $ fail "weakness-ok requires a non-empty reason string"` closes the asymmetry. `Control.Monad (when)` added to imports.
- **3 new tests** (WO-J1..WO-J3 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)): WO-J1 positive parse as `SWeaknessOk`; WO-J2 empty-reason rejection (`json-decode-error`); WO-J3 co-parse alongside a `def` node. **Tests: 804 → 807 Haskell + 62 Python.**

### Doc lead — CHANGELOG `## Latest` anchor restored (2026-06-03)

- **`<a id="Latest">` anchor re-added to `CHANGELOG.md`** (commit [`84d8166`](CHANGELOG.md)). The `README.md:5` "Current version" callout links to `CHANGELOG.md#Latest`; the anchor had been dropped, breaking the deep-link. Prose backtick citations in the affected entries converted to hyperlinks. Doc-infra only; no schema, spec, code, test, or version change.

**Tests: 807 Haskell + 62 Python.**

---

## v0.11.0 — Core/Shell Grammar Inversion + Evidence-Axis Enrichment (2026-05-31)

### Compiler — LT-INV: CDP fixture + test surface def-logic cleanup (2026-05-31)

- **`compiler/test/fixtures/cdp/*.llmll` migrated `def-logic` → `def`/`def-shell`** (commit `56f00dd`). These three fixture files (`verified-strong.llmll`, `verified-weak.llmll`, `intentional.llmll`) were dead — no test loads them — but carried `def-logic` and single-semicolon comments, neither of which parse under `GrammarCoreInversion` (lexer requires `;;`). `verified-strong.llmll` and `verified-weak.llmll` → `def` (QF-LIA / `EVar-int` bodies); `intentional.llmll` → `def-shell` (`spec-entropy :intentional` marks intentional CDP suppression; `def-shell` scope is semantically appropriate). Return-type annotations (`-> int`) stripped from all three (`def`/`def-shell` do not parse return-type annotations).
- **Tests C12-C15 (`Spec.hs:6577-6604`) updated** from `GrammarLegacy`+`def-logic` to `GrammarCoreInversion`+`def-shell`. These tests cover the `(spec-entropy ...)` annotation parse path; the annotation is valid on `def-shell` under `GrammarCoreInversion`. `SDefLogic` pattern matches in C12-C13 → `SDefShell`; C14 JSON `"kind":"def-logic"` → `"kind":"def-shell"`; C15 rejection test updated to `def-shell` (grammar-mode independent for the bogus-`spec_entropy` error path). **No remaining `def-logic` keyword instances** in `compiler/test/fixtures/` or in explicit grammar-mode test paths. Residual `SDefLogic` AST constructor usages in `Spec.hs` (programmatic AST construction) are v0.12 scope when `def-logic` is removed from `GrammarLegacy`. **Tests: 788 Haskell + 62 Python** (no change).

### Compiler — LT-INV: sexp example migration complete; version bump 0.11.0 (2026-05-31)

- **17 `.llmll` S-expression example files migrated from `def-logic` to `def`/`def-shell`** (commits [`283f4e5`](compiler/test/Spec.hs), [`5241965`](compiler/package.yaml)). 38 functions → `def` (49.4%), 39 → `def-shell` (50.6%) per `isCoreBodySyntactic` ([`Syntax.hs:602-624`](compiler/src/LLMLL/Syntax.hs)) + `checkCalleeAdmissibility` ([`TypeCheck.hs:347-361`](compiler/src/LLMLL/TypeCheck.hs)) classification, cross-referenced against commit `f09c498` JSON-AST migration. All `examples/**` S-expression source now parses under the default `GrammarCoreInversion` mode without `--grammar=legacy`. Four `parseStatements GrammarLegacy` file-reading calls in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) (lines 154, 5158, 5173, 5190) updated to `GrammarCoreInversion`; three `SDefLogic` golden patterns (lines 5163, 5177, 5193) updated to `SDef`. No test count delta. **Tests: 788 Haskell + 62 Python.**
- **`tictactoe_sexp/tictactoe.llmll` and `pair_type_test/pair_type_test.llmll` migration completed (commit `17d0da6`, 2026-05-31).** These 2 files were reverted from `def-logic` → `def-shell` after `283f4e5` and remained at `def-logic` in HEAD. `tictactoe_sexp/tictactoe.llmll`: 15 `def-logic` → `def-shell` (list ops, string ops, WASI IO, pair state throughout). `pair_type_test/pair_type_test.llmll`: additionally fixes three pre-existing issues masked by the earlier parse failure — (a) return-type annotation `: (string, string)` stripped (`def`/`def-shell` do not support return-type annotations); (b) `def-main :console` → `def-main :mode console` (legacy shorthand retired); (c) `lambda` → `fn` with typed params; (d) `wasi.io` capability import added (CAP-1). `make-pair` reclassified `def-shell` (`s: string` is `EVar-non-int`). All 17 `examples/**` `.llmll` files now parse under `GrammarCoreInversion` without `--grammar=legacy`. **Tests: 788 Haskell + 62 Python** (no change).
- **Version bump `0.10.8 → 0.11.0`** in [`compiler/package.yaml`](compiler/package.yaml) and [`compiler/llmll.cabal`](compiler/llmll.cabal).

### Language team / Doc lead — LLMLL.md §2.1, §2.5, §4.1, §4.2 canonicalization (2026-05-31)

- **`LLMLL.md §4.1` rewritten: `def` and `def-shell` are now the canonical function-declaration keywords.** Section heading `### 4.1 def-logic (Pure Functions)` → `### 4.1 Function Declarations (def and def-shell)`. Opening prose, syntax skeleton, and `withdraw` example updated; `def-logic` relegated to a `> Legacy grammar` blockquote. A `def` vs `def-shell` selection rule table added.
- **`LLMLL.md §4.2` rewritten: recursive functions documented as `def-shell`.** Section heading `### 4.2 letrec (Recursive Functions with Termination Measures)` → `### 4.2 Recursive Functions (def-shell)`. `countdown` `def-shell` example replaces `letrec`; partial-correctness caveat preserved. `letrec` form relegated to `> Legacy grammar` blockquote.
- **`LLMLL.md §4.3` examples updated:** `def-logic` → `def`; `(* x 2)` function body → `(+ x x)` (multiplication not in strict-core whitelist — `isCoreBodySyntactic` rejects `EOp "*"` at `Syntax.hs:622`; `(+ x x)` is semantically equivalent and core-admissible). `also-bad [result: int]` example dropped — compiler does not enforce `result` as a reserved parameter name; prior "COMPILE ERROR" claim was inaccurate (spec-compiler drift; compiler-engineer scope).
- **`LLMLL.md §2.1` keywords bullet, §2.5 naming table, §4.4.1 trust table, §4.4.3 trust ordering:** phrase updates replacing `def-logic`/`letrec` references with `def`/`def-shell` and `--grammar=legacy` notes. No test count delta. No schema delta.

### Doc lead — getting-started.md §1–§4.13 def-logic/letrec prose canonicalization (2026-06-01)

- **`docs/getting-started.md §1–§4.13`: prose references to `def-logic` and `letrec` updated** to name `def`/`def-shell` as canonical and `def-logic`/`letrec` as `--grammar=legacy`-only forms. Seven prose sites updated; code-block examples left untouched (stale code-block findings are compiler-engineer scope). §4.10 section heading and prose rewritten around the existing `letrec` code blocks; §4.11 `?proof-required(complex-decreases)` table row qualified; §3 coverage sentence updated; §4.7 import-ordering table and blockquote prose updated; §4.8 export-ordering prose updated. No test count delta. No schema delta.
- **`docs/getting-started.md §4.15+`: two remaining prose sites updated.** `§4.17` let-generalization sentence and `§4.17` `Known limitation` NOTE updated: `def-logic`/`letrec` → `def`/`def-shell` (canonical) plus `def-logic`/`letrec` (legacy). Six stale `def-logic` code-block examples in §4.15–§4.19 deferred to compiler-engineer pass.

### Compiler — self-recursion warning gated to GrammarLegacy (2026-05-31)

- **Self-recursion warning suppressed under `GrammarCoreInversion`** ([`TypeCheck.hs:1043`](compiler/src/LLMLL/TypeCheck.hs)). Previously, a `def-shell` self-recursive call emitted `"self-recursive call to '…' inside def-logic; use (letrec … [...] :decreases ...) …"` — a stale message referencing `def-logic` and `letrec`, neither of which are available under the default grammar. Under `GrammarCoreInversion`, `def-shell` self-calls are correct by design (`LLMLL.md §4.2`); `def` self-calls already receive the more precise `core-membership-violation` from `checkCalleeAdmissibility`. Warning retained unchanged under `GrammarLegacy` where `def-logic` and `letrec` are the applicable forms. Existing mixed-mode test (`Spec.hs:801`) corrected: `typeCheck GrammarCoreInversion` → `typeCheck GrammarLegacy` to match the `GrammarLegacy` parse side. New test: `def-shell` self-recursive call under `GrammarCoreInversion` asserts no self-recursion warning. **Tests: 789 Haskell + 62 Python.**

### Doc lead — getting-started.md §4.15–§4.19 code-block migration (2026-06-01)

- **17 stale `def-logic` code-block instances in `docs/getting-started.md` migrated to `def`/`def-shell`** (commits `ed009f0` / merge `eb5f82e`). Pure functions (`use-nonneg`, `use-pair`, `use-nested`, `id`, `bad`, `safe-divide`, `clear-screen`, `sort`, name-template pattern) → `def`; side-effecting and hole-bearing functions (`transfer`, `greet` ×2, `log-login`, `build-report` ×2) → `def-shell`. One prose line in the §2 output-layout table updated (`"all def-logic, types, builtins preamble"` → `"all def/def-shell, types, builtins preamble"`); the `--weakness-check` trivial-body output snippet in §3 updated (`def-logic sort-list` → `def sort-list`). Intentional legacy-prose references (the `--grammar=legacy` section at §4.14, the let-generalization NOTE at §4.17, and the pitfall table) preserved unchanged. Closes the "compiler-engineer scope" deferral in `### Doc lead — getting-started.md §1–§4.13 def-logic/letrec prose canonicalization` above. No test count delta. No schema delta.

### Experiments — §8 gate: EL-5 clean gate run (20260530T052351Z)

- **Run `20260530T052351Z`** ([`experiments/minimal-agent/findings/postmortem-006-el5-clean-gate.md`](experiments/minimal-agent/findings/postmortem-006-el5-clean-gate.md)) used the EL-1+EL-2+E3+F-GATE-7 evaluator under `GrammarCoreInversion` enforcement (llmll `b8c15dd`, compiled 2026-05-29). 8 attempts: claude-opus-4-7 ×5, gemini-3-pro-preview ×3; 0 exclusions — first gate run with 0 gemini quota failures across all 3 cells.
- **Axis (c): 8/8 (100%) `?proof-required` emission; 6/8 `prc_accepted` (asserted-ceiling path).** F-GATE-7 (`normalize_trust_status` suffix-strip) and F-GATE-8 (`guardDelegate` blocks `DLTested` lift for `def-shell + hole-delegate`) fully eliminate all prior contamination. Grade-A paths confirmed: Path A — `def-shell + hole-delegate` → `asserted` via F-GATE-8 (claude try01, try05); Path B — `def + hole-delegate + unevaluable pre` → whole-function `asserted` via pre-clause unevaluability propagation (claude try02–04). Gemini try01/03 grade A via `tested` trust status accepted under F-GATE-7 fix.
- **Grade distribution: 7/8 grade A, 1/8 grade C.** Gemini-try02 grade C is a PBT property coverage gap (3/3 properties gave up after 1000 discards each) — unrelated to grammar mode, trust guard, or contract quality (`contracts_met: True`, `prc_accepted: 1`). F-EL5-2 filed as observation for experiment-lead.
- **§8 gate adjudication: PASS — definitive.** Axis (c) 0/6 pre-arm → 8/8 EL-5. No exclusions. PM-005 was not a clean reference run (F-GATE-7 + F-GATE-8 confounders); PM-006 is the clean dataset. Grammar default flip and schema bump unblocked. See [`experiments/minimal-agent/findings.md`](experiments/minimal-agent/findings.md) §Language-team for the four-axis gate table. F-EL5-3 (language-team + compiler): `def + hole-delegate` → `asserted` unconditionally; adjudicated language-team 2026-05-30; compiler fix (commit `63b9bb3`) confirmed; `LLMLL.md §4.4.5/§5.3.5/§6` pending markers closed this pass; see `### Compiler — F-EL5-3` below. **Tests: 783 Haskell + 62 Python** (no change this pass).

### Compiler — LT-INV CE-3: grammar default → GrammarCoreInversion; schema re-bump 0.5.0 → 0.6.0 (EL-5 confirmed, 2026-05-30)

- **`GrammarCoreInversion` is now the default grammar mode** — re-applied after CE-2 rollback (`b8c15dd`, 2026-05-29). EL-5 clean gate run (PM-006, above) is the definitive empirical basis; §8 gate PASS is no longer conditional. All `llmll` subcommands parse under `--grammar=core-inversion` by default. Programs using `def-logic` or `letrec` must pass `--grammar=legacy` explicitly. `llmll --help` reports "core-inversion (default) or legacy (v0.10 compatibility)".
- **`expectedSchemaVersion` re-bumped to `"0.6.0"`** in [`compiler/src/LLMLL/ParserJSON.hs:41`](compiler/src/LLMLL/ParserJSON.hs). Files with `"schemaVersion": "0.5.0"` are rejected with `schema-version-mismatch` (exit 1). Submitted `.ast.json` files must carry `"schemaVersion": "0.6.0"`.
- **`docs/llmll-ast.schema.json` re-bumped:** `$id` URL `v0.5 → v0.6`, `title` updated, `schemaVersion.const` → `"0.6.0"`, `schemaVersion.description` updated. DRIFT-CI-1 C3+C4 PASS confirmed by `scripts/version_gate.sh`.
- **Internal test fixture sync.** Six `.llmll` fixtures (`compiler/test/fixtures/modules/` ×4 + `compiler/test/fixtures/pbt-cross-module/imported.llmll`) re-migrated `def-logic` → `def` (reversal of CE-2). Two `ModuleSpec.hs` call sites (M-06, M-08.5) re-flipped to `GrammarCoreInversion`. 20 inline JSON `"schemaVersion"` strings in `Spec.hs` re-bumped to `"0.6.0"`.
- **`examples/withdraw-demo/withdraw.ast.json` `schemaVersion` bumped to `"0.6.0"`.** Required because `applyPatch` in [`compiler/src/LLMLL/PatchApply.hs`](compiler/src/LLMLL/PatchApply.hs) calls `parseJSONASTValue` which gates on `expectedSchemaVersion`; OBLIG-1/OBLIG-2 tests exercise this path. The `"kind":"def-logic"` body in this file is unchanged — `parseJSONASTValue` hardcodes `GrammarLegacy`. This is the only `examples/` file migrated on this pass; remaining 20 `.ast.json` + 17 `.llmll` S-expression files were deferred (see migration-complete bullet below).
- **`examples/**` JSON-AST migration complete (commit `f09c498`, 2026-05-30).** 20 `.ast.json` files bumped `schemaVersion` `0.5.0`/`0.1.3` → `0.6.0`; 145 `def-logic` nodes reclassified to `"kind":"def"` (72, 47.7%) or `"kind":"def-shell"` (73, 52.3%) per LT-INV §6 classifier (`isCoreBodySyntactic` + trusted-callee check, `TypeCheck.hs:338-361`); 6 `letrec` nodes → `"kind":"def-shell"` with `decreases` field removed. `withdraw-demo/withdraw.ast.json` `def-logic` → `def` (schema already `0.6.0`). Boundary-form distribution 47.7% `def` satisfies §8.1 ≥25% gate. All `examples/**` `.ast.json` files now parse under default `GrammarCoreInversion` without `--grammar=legacy`. OBLIG-1/OBLIG-2 confirmed clean (`parseJSONASTValue` accepts `"kind":"def"` under `GrammarLegacy`). **Pending: 17 `.llmll` S-expression files** (separate compiler-engineer pass); four `parseStatements GrammarLegacy` calls in `Spec.hs` (B1, B3, withdraw benchmarks) + three `SDefLogic` golden patterns.
- **Tests: 785 Haskell + 62 Python.** Count as of `f09c498`; no new tests added in this pass. 2-test delta from CE-3 baseline (783→785) is not attributable to this pass — intermediate tests not captured in a prior CHANGELOG entry.
- **`getting-started.md §4.1` JSON example corrected (commit `13eab90`, 2026-05-30).** `"kind":"def-logic"` renamed to `"kind":"def"` in the State Accessor Functions JSON snippet; the legacy form emitted `core-grammar-violation` under default `GrammarCoreInversion`. No test delta. Residuals tracked: (a) param `s: string` is a pre-existing type mismatch against `first :: pair[a,b] → a` (`TypeCheck.hs:93`, U2-lite v0.4; same issue in `examples/hangman_json_verifier/hangman.ast.json:state-word`) — compiler-engineer scope, correct param to `pair-type`; (b) prose note at §4.1 "first/second accept any pair-like value regardless of annotation" deferred pending param fix to avoid note/example inconsistency — doc-lead scope after (a) lands.
- **`getting-started.md §4.1` param-type and `hangman.ast.json` state type corrected (commit `67c1e15`, 2026-05-30).** Closes CE-3 doc-pass residuals (a) and (b) from `13eab90`. (a) `s: string` → `s: pair-type[string,string]` in the §4.1 JSON snippet; `first :: pair[a,b] → a` (`TypeCheck.hs:93`, U2-lite v0.4) now correctly typed at the call site. (b) Prose note "first/second accept any pair-like value regardless of annotation" corrected: "`first :: pair[a,b] → a` and `second :: pair[a,b] → b` require a `pair-type` parameter." Additionally, 11 `unit`-typed state/accessor params in [`examples/hangman_json_verifier/hangman.ast.json`](examples/hangman_json_verifier/hangman.ast.json) corrected to `pair[string,pair[list[string],pair[int,MaxWrong]]]` per `make-state` body shape. No test delta. Remaining findings for next CE pass: `examples/conways_life_json_verifier/life.ast.json` (9 world-state `unit` params) and `examples/tictactoe_json_verifier/tictactoe.ast.json` (6 game-state `unit` params).
- **`life.ast.json` and `tictactoe.ast.json` state/world params corrected (commit `d3deb7d`, 2026-05-30).** Closes the CE-3 `unit`-param residual chain flagged in `67c1e15`. [`examples/conways_life_json_verifier/life.ast.json`](examples/conways_life_json_verifier/life.ast.json): 9 `w`/`world` params corrected to `pair[list[int],pair[int,pair[int,int]]]` per `make-world` body shape. [`examples/tictactoe_json_verifier/tictactoe.ast.json`](examples/tictactoe_json_verifier/tictactoe.ast.json): 6 `s`/`state` params corrected to `pair[list[string],pair[string,string]]` per `make-state` body shape. No test delta. CE-3 `unit`-param residual chain fully closed across all three example files (`hangman`, `life`, `tictactoe`).

### Compiler — F-EL5-3: extend delegation-hole guard to SDef (2026-05-30)

- **`pbtTrustWriteback` now blocks `DLTested` write-back for `def` (strict-core) functions whose body is a `?delegate` or `?delegate-async` hole.** F-GATE-8 (`f62a38b`, 2026-05-29) introduced the `delegateBodies` guard for `def-shell`; F-EL5-3 extends it to `SDef` on the same rationale — delegation holes make return values opaque pre-resolution regardless of enclosing grammar form. [`compiler/src/LLMLL/PBT.hs:693-694`](compiler/src/LLMLL/PBT.hs) gains two new list-comprehension arms (`SDef + EHole(HDelegate _)` and `SDef + EHole(HDelegateAsync _)`) added to `delegateBodies`; the `guardDelegate` helper is unchanged. Pre-fix, a `def` function with an evaluable precondition and a `?delegate` body could be incorrectly promoted to `DLTested n` when a passing `(check ...)` block called it — the static evaluator observed only the `delegateOnFailure` fallback, not the real delegated implementation. Post-fix, `trust_status` reports `asserted` unconditionally for delegation-bounded `def` functions under `llmll verify --trust-report`, consistent with the language-team adjudication in the 2026-05-30 spec-track doc pass. The fix applies to both the OBLIG-PBT-4 explicit-`:subject` path and the singleton-head-position scan.
- **2 new tests** (FG8-7, FG8-8) added under the existing `"F-GATE-8 def-shell hole-delegate PBT trust guard"` describe block in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): FG8-7 asserts `SDef + EHole(HDelegate _)` body suppresses lift; FG8-8 asserts `SDef + EHole(HDelegateAsync _)` body also suppressed. These tests account for the 2-test delta noted in the CE-3 entry (783 → 785). **Tests: 785 Haskell + 62 Python.**
- **Spec closed (this pass):** PBT-Lift inference rule at `LLMLL.md §4.4.5` generalized — `SDefLogic f _ _ c _` premise replaced by `f ∈ contractedNames(Σ ∪ importedExposed(Σ))` covering all contracted statement forms (`SDefLogic`, `SLetrec`, `SDef`, `SDefShell`); `body(f) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) }` side condition (SC-7) added. Same generalization applied to PBT-Lift-Annotated per-subject premise and conclusion range. Side condition 5 generalized from "`def-logic` posts" to "contracted-callee posts." `LLMLL.md §5.3.5` row 883 and `§6` NOTE box F-EL5-3 "pending" markers closed. No schema delta; no `trust_report_version` bump; no new surface.

### Language team — spec NOTE: hub-import grammar-mode; LT-INV Rev 4; v0.12 direction (2026-05-31)

- **`LLMLL.md §8.2`:** NOTE added documenting grammar-mode inheritance for imported modules. All imports — resolved from local source root, extra roots, or the `llmll-hub` cache — are parsed under the invoking command's `GrammarMode` (default `GrammarCoreInversion` in v0.11+). Hub publishers must ship `schemaVersion 0.6.0` modules using `def`/`def-shell` node kinds. `wasi.*`/`haskell.*`/`c.*` builtin-namespace imports are exempt (they carry no parseable file). Source: [`compiler/src/LLMLL/Module.hs:138,215`](compiler/src/LLMLL/Module.hs) — `loadModule`/`parseFile` thread `GrammarMode` from the entry-point parse, including the hub-cache path at `:99`. Closes the deferred item "checkStatement (SImport imp) guard for hub-import grammar enforcement" from `### Compiler — LT-INV: TypeCheck GrammarMode API collapse (2026-05-30)`: no statement-level grammar guard is needed; `parseFile` enforces the grammar mode before `checkStatement` is called. (Note: `doHubQuery` in `Main.hs` passes `GrammarLegacy` explicitly for the `llmll hub query` signature-search command — that path loads hub files for signature matching, not compilation import, and is unaffected by this NOTE.)
- **`LLMLL.md §8.9`:** One-sentence cross-reference NOTE added pointing hub-import users to §8.2.
- **`docs/design/core-shell-inversion-proposal.md` → Rev 4:** Def-logic deprecation timeline settled — v0.12 removes `def-logic` entirely (parse error under all grammar modes; no auto-rewrite). The 17 pending `.llmll` S-expression files (engineer scope) are the v0.12 release gate for this removal. v0.11 auto-rewrite-with-warning remains the migration aid through the v0.11 release cycle.
- **`docs/design/v0.12-direction.md` published (Rev 1):** Sequences three post-freeze clusters — REF-META-2..5 (spec-track, parallel LT proposals, no gate), Bundle B (B0 additive obligation-report effect-summary field in-scope for v0.12 spec+engineer; B1 LT proposal in v0.12, engineer build gated on B0 experiment result), non-int widening (LT proposal after REF-META-3; engineer build gated on `FixpointEmit.hs` path-a axiomatization). No code change.
- **`docs/design/INDEX.md`:** Updated in the language-team pass: LT-INV row → Settled (Rev 4); v0.11 direction memo row amended; v0.12 direction memo row added. No further change in this doc-lead pass.
- **Tests: 788 Haskell + 62 Python** (no change this pass).

### Compiler — LT-INV: TypeCheck GrammarMode API collapse (2026-05-30)

- **All `TypeCheck` entry points take `GrammarMode` as first argument; dual-tier `*WithMode` variants retired.** `typeCheck`, `typeCheckModule`, `typeCheckWithCache`, `typeCheckStrict`, `typeCheckStrictWithCache`, `runTC`, `runTCSketch`, and `runTCStrict` in [`compiler/src/LLMLL/TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs) each take `GrammarMode` as first parameter; the mode is threaded into `TCState.tcGrammarMode` at construction, replacing the hardcoded `GrammarLegacy` default. `typeCheckWithCacheMode` becomes the sole shared implementation parameterised by both `GrammarMode` and the strict flag. Consumer call sites updated: [`compiler/app/Main.hs`](compiler/app/Main.hs) (`doCheck`, `doBuild`, `doBuildFromJson`, `doRun`, `replLoop`; `doHubQuery` passes `GrammarLegacy` explicitly per hub pre-migration policy); [`compiler/src/LLMLL/CDP.hs`](compiler/src/LLMLL/CDP.hs); [`compiler/src/LLMLL/Module.hs`](compiler/src/LLMLL/Module.hs); [`compiler/src/LLMLL/Serve.hs`](compiler/src/LLMLL/Serve.hs); [`compiler/src/LLMLL/WeaknessCheck.hs`](compiler/src/LLMLL/WeaknessCheck.hs) (`generateWeaknessCandidates`, `generateCDPCandidates`, and `generateForStmt` each gain `GrammarMode` as first parameter). All `typeCheck`/`runTC`/`runTCSketch` call sites in `Spec.hs` and `ModuleSpec.hs` updated to pass explicit `GrammarCoreInversion`. No user-visible CLI or behavior change; no new diagnostics, flags, or exit codes; no schema delta; `schemaVersion` stays `"0.6.0"`. Deferred: `checkStatement (SImport imp)` guard for hub-import grammar enforcement — open design question; filed as separate follow-on item.
- **No new tests.** Tests: 788 Haskell + 62 Python (unchanged from `8542033`).

### Compiler — parser: JSON-AST def/def-shell guard under --grammar=legacy (2026-05-30)

- **`parseStatement` in `ParserJSON.hs` now rejects `{"kind":"def"}` and `{"kind":"def-shell"}` under `--grammar=legacy` with a `legacy-grammar-violation` diagnostic** (commit `8542033`). Previously both forms were admitted unconditionally regardless of grammar mode, contradicting `LLMLL.md §4.1` ("Under `--grammar=legacy`, `def` and `def-shell` are unavailable") and the `§12` EBNF comment. The text parser (`Parser.hs`) already enforced the symmetric constraint via `GrammarMode` arms in `pStatement`; the JSON-AST parser did not. Defect found by language-team during §4.1 audit post-CE-3. `diagSuggestion` for `legacy-grammar-violation` advises dropping `--grammar=legacy` or reverting to `def-logic`/`letrec` for v0.10-compatible output. `diagCode` is `E011` (same as `core-grammar-violation`).
- **`parseJSONASTValue` signature changed to `GrammarMode -> Value -> Either [Diagnostic] [Statement]`**, resolving the hardcoded-`GrammarLegacy` TODO at former `ParserJSON.hs:86-87`. `GrammarMode` is now threaded through `applyPatch` (`PatchApply.hs`; first parameter), `doPatch` (`Main.hs`; CLI `gm` value propagated from `optGrammarMode`), and `Serve.handlePatch` (`Serve.hs`; hardcoded `GrammarCoreInversion`, consistent with `Serve.hs`'s own parse paths at `Serve.hs:143-150`). Patch-apply against a `--grammar=legacy` host now parses the patched JSON under `GrammarLegacy`, preserving correct behavior for legacy-mode patch-apply.
- **3 new tests:** INV-P15 (JSON-AST `def` rejected under `GrammarLegacy`), INV-P16 (JSON-AST `def-shell` rejected under `GrammarLegacy`), INV-P17 (`parseJSONASTValue GrammarCoreInversion` accepts `def`). Three pre-existing `applyPatch` call sites in `Spec.hs` (OBLIG-1, OBLIG-2, OBLIG-3) updated to pass `GrammarCoreInversion`; OBLIG-3 inline fixture migrated from `"kind":"def-logic"` → `"kind":"def"`. No schema delta; no `.verified.json` invalidation. **Tests: 788 Haskell + 62 Python.**

### Compiler — F-GATE-8: def-shell hole-delegate PBT trust guard

- **`pbtTrustWriteback` now blocks `DLTested` write-back for `def-shell` functions whose body is a `hole-delegate` or `hole-delegate-async` hole.** Pre-fix, a check block whose body evaluated successfully via the delegate's `on_failure` fallback could lift the function's post-clause trust to `tested`, even though the static evaluator never observed the real delegated implementation — only the `delegateOnFailure` path. `processRun` in [`compiler/src/LLMLL/PBT.hs:641–755`](compiler/src/LLMLL/PBT.hs) gains a `guardDelegate` predicate: when the resolved PBT subject is in the `delegateBodies` set (any `SDefShell` with `EHole(HDelegate _)` or `EHole(HDelegateAsync _)` body), the `DLTested` lift is suppressed and an informational diagnostic is emitted. The fix applies to both the OBLIG-PBT-4 explicit-`:subject` path and the singleton-head-position scan. Post-clause trust for delegation-bounded functions now consistently reports `asserted` under `llmll verify --trust-report`, matching the grade-B/A boundary in the experiment harness's `delegation-excluded` gate. Root cause of the pre-fix inconsistency: two runs in `experiments/minimal-agent/runs/20260528T204620Z/` — `try02` (pre `string-length` guard, accidentally correct `asserted`) and `try03` (tautology check block, incorrect `tested`) — differed only in check-block structure, not in function structure.
- **`evalBuiltinApp` in [`compiler/src/LLMLL/Contracts.hs`](compiler/src/LLMLL/Contracts.hs) gains `string-length` and `string-empty?`.** Both were registered in `TypeCheck.hs:109,118` but absent from the static evaluator. `string-length` returns `T.length` of a `LitString` literal as a `LitInt`; `string-empty?` returns `T.null` as a `LitBool`. Non-literal arguments fall through to `Nothing` (constant-folding only). Without the primary `delegateBodies` fix, adding these would have caused check blocks using `string-length` in their conditions to also incorrectly lift; both fixes are required for correctness.
- **6 new tests** (FG8-1–FG8-6) under `"F-GATE-8 def-shell hole-delegate PBT trust guard"` in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): `string-length`/`string-empty?` literal evals; `HDelegate` body blocks lift; non-delegate concrete body permits lift (regression guard); `HDelegateAsync` body also blocked. **Tests: 783 Haskell + 62 Python.**

### Experiments — §8 gate: redesigned run (20260528T204620Z, EL-1+EL-2+E3)

- **Run `20260528T204620Z`** ([`experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md`](experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md)) used the EL-1+EL-2+E3 evaluator (E3 Option 2, commit `0d5037e`) under `GrammarCoreInversion` enforcement (F-GATE-1 + F-GATE-1b). 8 attempts: claude-opus-4-7 ×5, gemini-3-pro-preview ×3; 2 excluded (gemini-try02: `def-logic` with no in-session correction; gemini-try03: TerminalQuotaError). Valid dataset: n=6.
- **Axis (c) improves: `?proof-required` emission 0/6 → 3/6 (50%)** — gate pass criterion met. Three grade-A paths exercised: (1) `def` + bare `?proof-required` → `"asserted"`; (2) `def-shell` + arithmetic `string-length` pre → `"asserted"`; (3) `def-shell` + predicate-carrying LT-PPR form → `"asserted"`. First empirical exercise of the predicate-carrying form in a live agent run. Grade distribution: 3× A, 3× C; grade B absent (E3 Option 2 makes `login-handler.post` a required contract — absent `?proof-required` → grade C, not B). Axis (d): `def-logic` in final solutions 0/10 (0%); `def`/`def-shell` 10/10. Axes (a)(b): no change from baseline.
- **Run contaminated — gate pass conditional.** F-GATE-7 (`normalize_trust_status` did not strip `"tested (100 samples)"` suffix; 3/5 claude attempts mislabelled grade C; fix applied to `evaluate_run.py` post-run). F-GATE-8 (`def-shell` + `hole-delegate` body post trust-status pre-clause-dependent; compiler fix `f62a38b`, 2026-05-29). PM-005 is not a clean reference run; sample composition post-fix would differ.
- **§8 gate adjudication (language-team, 2026-05-29):** axis (c) criterion met; run contaminated by F-GATE-7 and F-GATE-8 post-hoc fixes; gate pass conditional. Rollback path (1) adopted per [`docs/design/v0.11-cross-proposal-rollback-discipline.md §2.2`](docs/design/v0.11-cross-proposal-rollback-discipline.md): `--grammar=core-inversion` remains the explicit opt-in; grammar default and schema bump deferred; redesigned gate experiment scheduled post-F-GATE-8 fix. **Tests: 783 Haskell + 62 Python** (from F-GATE-8 entry; no count change this pass).
- **Gate adjudication definitive (2026-05-29):** F-GATE-8 fix (commit `f62a38b`, `### Compiler — F-GATE-8` above) removes the contamination source. Rollback path (1) is no longer conditional — it is the definitive §8 gate outcome. Redesigned gate experiment is unblocked; scheduling is experiment-lead scope.

### LT-INV — §8 rollback: grammar default deferred; schema stays at 0.5.0 (2026-05-29)

- **Grammar default reverts to `GrammarLegacy`.** Commit `5cab1b7` flipped `GrammarCoreInversion` to the CLI default (2026-05-28). Rolled back: grammar default returns to `GrammarLegacy`. `--grammar=core-inversion` is the explicit opt-in for `def`/`def-shell`. **Compiler-engineer action required:** revert `compiler/app/Main.hs` grammar default; revert `compiler/test/fixtures/` `def` → `def-logic` fixture migrations (commit `5cab1b7`); revert `compiler/test/Spec.hs` `GrammarCoreInversion` test-mode changes and inline version-string changes.
- **`docs/llmll-ast.schema.json` reverted to 0.5.0.** `$id` `v0.6/ast.schema.json` → `v0.5/ast.schema.json`; `title` `v0.6` → `v0.5`; `schemaVersion.const` `"0.6.0"` → `"0.5.0"`. `kind:"def"` / `kind:"def-shell"` JSON-AST nodes remain admitted by the `Statement.kind` enum for opt-in consumers under `--grammar=core-inversion`; they are not canon at `0.5.0` and not required. Bump to `0.6.0` deferred. **Compiler-engineer action required (DRIFT-CI-1 C3 blocker):** revert `compiler/src/LLMLL/ParserJSON.hs:41` `expectedSchemaVersion` `"0.6.0"` → `"0.5.0"`; revert `examples/**` `schemaVersion` and `kind` migrations (commit `afe80df`); revert `compiler/test/Spec.hs` 20 inline `"0.6.0"` strings.
- **`examples/*` migration not applied.** Per `v0.11-cross-proposal-rollback-discipline.md §2.2`: example migration applies only under Outcome 0. The migration committed at `afe80df` is rolled back under compiler-engineer scope above.
- **`kind:"def"` / `kind:"def-shell"` additions remain in the grammar** behind `--grammar=core-inversion`. Not finalized as canonical. Redesigned gate experiment will determine Outcome 0 / 1 / 2 definitively.
- **Doc surface reverted (this pass):** `docs/llmll-ast.schema.json`, `LLMLL.md §5/§12`, `docs/getting-started.md §4.14`, `README.md` version callout. Roadmap LT-INV summary updated; grammar-default-flip and schema-bump Unreleased entries annotated below.

### Experiments — E3 Option 2: experiment 001 grade-A gate and axes (b)/(c)

- **`CONTRACT_EXPECTATIONS[1]["login-handler"]` restructured** in [`experiments/minimal-agent/scripts/evaluate_run.py`](experiments/minimal-agent/scripts/evaluate_run.py): the `pre` expectation (`proof_required: False`) is removed; a `post` expectation (`proof_required: True`) is added. The pre clause on `login-handler` is QF-LIA-tractable but structurally asserted (the function contains `?delegate`); keeping it with `proof_required: False` caused `asserted_without_proof = 1` on every solution, imposing a B ceiling that no contract configuration could lift. Removes the latent grade-B floor from the contract-assessment path. See [`experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md`](experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md) F-201 for the prior E3-revert history.
- **`REQUIRED_FEATURES[1]` gains `"post"`**: solutions that omit the post clause on `login-handler` receive F on the feature scan, not merely a contract-quality penalty. Grade gradient: missing post → F; post present but no `?proof-required` marker → C (`all_required_contracts_met: false`); post with `?proof-required`, all tests delegation-excluded → B; post with `?proof-required` and at least one non-delegation-dependent check → A.
- **[`experiments/minimal-agent/experiments/001-two-agent-auth.md`](experiments/minimal-agent/experiments/001-two-agent-auth.md)** gains two new items: item 6 — a `post` contract on `login-handler` asserting the returned hash is non-empty, marked `?proof-required` (delegation-bounded postcondition per `LLMLL.md §13.8`); item 7 — a non-delegation-dependent `check` block asserting a pure property of the pre-condition predicate without invoking `login-handler` or `validate-session`. Item 7 is necessary to clear the `effective_total == 0` test-exclusion B gate, which fires independently of contract quality.
- **3 new Python tests** in [`experiments/minimal-agent/scripts/test_evaluate_run.py`](experiments/minimal-agent/scripts/test_evaluate_run.py): `ContractExpectationE3Tests` restructured (pre-absent guard, post-proof-required guard, post-in-REQUIRED_FEATURES guard); `QualityGradeTests.test_e001_grade_a_with_nondelegation_check_and_proof_required_post` added. **Tests: 770 Haskell + 62 Python** (resolves the acknowledged EL-A count discrepancy; canonical suite is now 41 `test_evaluate_run.py` + 21 `scripts/tests/`).

### Compiler — LT-INV grammar default flip (§8 gate: PASS)

- **`GrammarCoreInversion` is now the default grammar mode** (commit `5cab1b7`, 2026-05-28). All `llmll` subcommands (`check`, `verify`, `test`, `build`, `holes`, `typecheck`, and the HTTP serve endpoint) parse under `--grammar=core-inversion` by default. Programs using `def-logic` or `letrec` must pass `--grammar=legacy` explicitly; the flag is available on all subcommands. `llmll --help` reports "core-inversion (default) or legacy (v0.10 compatibility)".
- **`GrammarMode` threaded through the module-import loader.** `Module.hs::loadModule`, `loadFromFile`, `loadOneImport`, and `parseFile` accept and propagate the active grammar mode; imported `.llmll` modules are parsed with the same grammar as the entry file. Previously all imports were hardcoded to `GrammarLegacy`. `HubQuery.hs` retains `GrammarLegacy` explicitly (hub packages are pre-migration). The HTTP serve endpoint (`Serve.hs`) follows the CLI default.
- **Test fixture migration.** Six `.llmll` fixtures (`compiler/test/fixtures/modules/` ×4 + `compiler/test/fixtures/pbt-cross-module/` ×2) migrated from `def-logic` to `def`.
- **§8 empirical-validation gate:** PASS. Combined postmortem-004/005 data (2026-05-28): axis (a) grade A achieved for first time (2/5 claude-opus-4-7 primary-arm attempts); axis (c) `?proof-required` emission non-zero for first time (2/5 `proof_required_ceiling_accepted`); axis (d) 0 `def-logic` in all primary-arm final solutions. Gate adjudicated by language-team, 2026-05-28. See [`experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md`](experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md).
- **Pending (next pass):** `examples/*` migration from `def-logic` → `def`/`def-shell` (compiler-engineer scope); schema bump `0.5.0 → 0.6.0` (blocked on `expectedSchemaVersion` update in `compiler/src/LLMLL/ParserJSON.hs:41`).
- **+3 Haskell tests** (INV-DEFAULT-1, INV-DEFAULT-2, INV-MODULE-THREAD-1). **Tests: 773 Haskell + 62 Python.**
- **Rolled back 2026-05-29.** Redesigned gate run `20260528T204620Z` (PM-005) was contaminated by F-GATE-7 (evaluator suffix mismatch) and F-GATE-8 (compiler trust-status bug; fix `f62a38b`); language-team adjudicated rollback path (1) per [`v0.11-cross-proposal-rollback-discipline.md §2.2`](docs/design/v0.11-cross-proposal-rollback-discipline.md). Grammar default reverts to `GrammarLegacy`; schema stays `0.5.0`. See `### LT-INV — §8 rollback` above.

### Experiments — §8 gate: post-arm checkpoint (20260528T145727Z)

- **Gate run IDs:** pre-arm `20260528T012230Z` (GrammarLegacy, 6 attempts); post-arm checkpoint `20260528T145727Z` (GrammarCoreInversion, 5 valid attempts; `20260528T014158Z` excluded — F-GATE-1 enforcement absent). See [`experiments/minimal-agent/findings/postmortem-004-s8-gate-post-arm-rerun.md`](experiments/minimal-agent/findings/postmortem-004-s8-gate-post-arm-rerun.md).
- **Axis (d): complete shift.** `def-logic` in final solutions: pre-arm 12/12 (100%) → post-arm 0/10 (0%). `def`/`def-shell` statements: 0/12 → 10/10. Claude-only pass rate 3/3 both arms; gemini compromised by API HTTP 429 throttling (try01 excluded, 0 output; try03 grade F, 20 retries, 429-degraded — excluded from grade analysis).
- **Axes (a), (b), (c): flat.** Overall harness pass rate: claude-only 3/3 pre and post. Verified fraction: 0/6 → 0/5. `?proof-required` emission: 0/6 → 0/5.
- **E3 instrument limitation.** Axis (c) flatness is not a clean null result. The pre-E3 evaluator held `CONTRACT_EXPECTATIONS[1]["login-handler"]` with `proof_required: False` on the pre clause, imposing a structural B ceiling on every solution regardless of `?proof-required` authoring — agents had no harness-backed incentive to emit the marker. Axes (b) and (c) were not meaningfully measurable; flatness on these axes does not constitute evidence against the polarity claim. See F-201 in [`experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md`](experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md) and `### Experiments — E3 Option 2` above for the E3 defect and fix.
- **Rollback path (1) adopted; polarity claim deferred.** Language-team / experiment-lead adjudication at `20260528T145727Z`: gate pass/fail undecidable given E3 instrument defect. Rollback path (1) — inversion retained behind `--grammar=core-inversion` flag, grammar default not flipped — adopted pending E3 fix and re-run. Polarity claim deferred. E3 Option 2 fix (commit `0d5037e`) corrected `CONTRACT_EXPECTATIONS` and added item 7 (non-delegation-dependent check); follow-up run `20260528T204620Z` (postmortem-005) shifted axis (c) from 0/6 to 3/6; gate declared PASS; polarity claim reinstated; grammar default flipped at `5cab1b7` (see `### Compiler — LT-INV grammar default flip` above).

### Compiler — LT-INV schema bump 0.5.0 → 0.6.0 + examples migration

- **`expectedSchemaVersion` bumped to `"0.6.0"`** in [`compiler/src/LLMLL/ParserJSON.hs:41`](compiler/src/LLMLL/ParserJSON.hs) (commit `afe80df`, 2026-05-28). Files with `"schemaVersion": "0.5.0"` are rejected with a `schema-version-mismatch` diagnostic (exit 1). All submitted `.ast.json` files must carry `"schemaVersion": "0.6.0"`. Closes the schema-bump gate gated on the §8 empirical-validation gate pass.
- **`docs/llmll-ast.schema.json` bumped:** `$id` URL `v0.5 → v0.6`, `title` updated, `schemaVersion.const` updated, `schemaVersion.description` updated. DRIFT-CI-1 C3 confirms `schema.const == ParserJSON.expectedSchemaVersion`. No new fields, no deprecated fields, no node-shape change.
- **`examples/**` migration:** 17 `.llmll` files (`def-logic` → `def-shell`); 21 `.ast.json` files (`"kind":"def-logic"` → `"kind":"def-shell"`, `schemaVersion` `"0.5.0"` → `"0.6.0"`; legacy `"0.1.3"` → `"0.6.0"` in `tictactoe_json`, `hangman_json`); 3 `.ast.json` files with `"kind":"letrec"` migrated to `"kind":"def-shell"` with `"decreases"` field removed (`hangman_json_verifier` ×2, `conways_life_json_verifier` ×3, `tictactoe_json_verifier` ×1). Conservative first-pass migration: all `def-logic` → `def-shell` (semantically equivalent to `def-logic` under v0.10 semantics); selective `def` upgrade (functions whose bodies satisfy `isCoreBodySyntactic`) is a future pass.
- **Zero test count delta.** 20 inline `"0.5.0"` strings in `Spec.hs` updated to `"0.6.0"`; 4 example-reading tests updated from `GrammarLegacy` to `GrammarCoreInversion`; 3 `SDefLogic` pattern matches updated to `SDefShell` in benchmark golden tests. **Tests: 773 Haskell + 62 Python.**
- **Rolled back 2026-05-29.** `docs/llmll-ast.schema.json` reverted to `0.5.0` in this doc pass. Compiler-engineer must revert `expectedSchemaVersion` in `ParserJSON.hs:41` and `examples/**` migration as a companion PR; DRIFT-CI-1 C3 is blocked until both are done. See `### LT-INV — §8 rollback` above.

### Compiler — LT-CDP: CDPScopeCoreOnly flip + WarnSpecTooTightForOmega rename (§8 Outcome 0)

- **`CDPScopeAllDefLogic` → `CDPScopeCoreOnly` in [`compiler/app/Main.hs:1339`](compiler/app/Main.hs) (commit `3af3c06`, 2026-05-29).** Per [`v0.11-cross-proposal-rollback-discipline.md §2.1`](docs/design/v0.11-cross-proposal-rollback-discipline.md) Outcome 0 (§8 gate PASSED 2026-05-28), `--cdp` now measures `discriminative_axis` for `def`-form (`SDef`) functions only. `def-shell` and legacy `def-logic` functions receive `WarnDefShellOutOfScope` entries with `"score": null` and `"warnings": ["def-shell-out-of-scope"]`; the result map remains uniform (every contracted function has an entry).
- **`computeCDPFor` scope filtering wired in [`compiler/src/LLMLL/CDP.hs:207-271`](compiler/src/LLMLL/CDP.hs).** The `_scope` parameter was previously accepted but ignored. Under `CDPScopeCoreOnly`, only `SDef` enters the measurement pipeline; `SDefShell`, `SDefLogic`, and `SLetrec` are routed to `outOfScopeResult` (no solver call). `CDPScopeAllDefLogic` retains all-forms measurement for `--grammar=legacy` contexts.
- **`WarnVacuousOverOmega` → `WarnSpecTooTightForOmega`; wire-line label `"vacuous-over-omega"` → `"spec-too-tight-for-omega"` (F-005 CE follow-up, [`docs/design/contract-discriminative-power-proposal.md §5 Rev 4`](docs/design/contract-discriminative-power-proposal.md)).** Fires when a body-faithful-verified contract admits no §4.3.1 trivial-body candidate — the spec is tight with respect to the candidate set, not semantically inconsistent. `"spec-inconsistent"` is retained for the distinct case where no verification evidence exists.
- **+4 Haskell tests** (CDP-SCOPE-1–4) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) under `"CDP-SCOPE: CDPScopeCoreOnly scope filtering"`: `SDef` in-scope (score populated); `SDefLogic` and `SDefShell` out-of-scope (`WarnDefShellOutOfScope`); `CDPScopeAllDefLogic` + `SDefLogic` legacy path (score populated). **Tests: 777 Haskell + 62 Python.**

### Compiler — LT-INV (v0.11): core/shell grammar inversion

- **`--grammar=core-inversion` global flag activates the core/shell grammar split** across all `llmll` subcommands. Under this mode, `def` declares a strict-core function (`SDef`) and `def-shell` declares a permissive function (`SDefShell`). Default is `--grammar=legacy`; all existing programs are unaffected. The flag is threaded through `parseSrc` / `loadStatements` / `loadStatementsMulti` in [`compiler/app/Main.hs`](compiler/app/Main.hs) and forwarded to the REPL loop; library-internal callers (`HubQuery`, `Module`, `Serve`) unconditionally use `GrammarLegacy`. `GrammarMode` is the discriminant in [`compiler/src/LLMLL/Syntax.hs`](compiler/src/LLMLL/Syntax.hs); parser entry-points in [`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs) and [`compiler/src/LLMLL/ParserJSON.hs`](compiler/src/LLMLL/ParserJSON.hs) dispatch on `GrammarCoreInversion` to activate `pDef` / `pDefShell`; `{"kind":"def-logic"}` in JSON-AST is rejected with a `core-grammar-violation` diagnostic under this mode (F-GATE-1, commit `cabb1fd`).
- **`def` (SDef) admits a restricted core-body whitelist** enforced by `isCoreBodySyntactic` in [`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs): `ELit`, `EVar` (int-typed), QF-LIA `EOp` (linear ops only — `*` and `/` are excluded), `ELet` (PVar + int RHS), `EIf`, `EApp` to admitted callees, `EMatch` on `Result` 2-arm, and `?hole`/`?name`/`?choose`/`?request-cap`/`?scaffold`/`?delegate`/`?delegate-async`. Excluded: `ELambda`, `EDo`, `EPair`, non-linear arithmetic, `?proof-required`. The type-checker enforces the transitive callee restriction at every `EApp` inside an `SDef` body via `checkCalleeAdmissibility` in [`compiler/src/LLMLL/TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs): a callee is admitted if it has body-faithful verified evidence, is in the `trustedPrelude` set (11 pure stdlib functions), or is a member of `builtinEnv` (all built-in LLMLL operators, including those used in contract clause expressions such as `>=`, `+`, `and`). The third condition — `builtinEnv` admission — is formalized in [`docs/design/core-shell-inversion-proposal.md`](docs/design/core-shell-inversion-proposal.md) §4 Rev 3 (language-team, 2026-05-27) and promoted to `LLMLL.md §5.3.5`.
- **`def-shell` (SDefShell) is the permissive form**: no body whitelist, no callee admission check. Functions declared with `def-shell` may freely call unverified callees, use `ELambda`, `EDo`, etc. The type-checker does not emit `core-grammar-violation` or `core-membership-violation` inside `SDefShell` bodies.
- **Two new diagnostic kinds** in [`compiler/src/LLMLL/Diagnostic.hs`](compiler/src/LLMLL/Diagnostic.hs): `core-grammar-violation` (body contains a disallowed construct) and `core-membership-violation` (callee not body-faithful, not in `trustedPrelude`, not a builtin). Both are errors (not warnings) when emitted inside an `SDef` body.
- **Full compiler fan-out:** `SDef`/`SDefShell` arms added to all 15 modules with pattern-exhaustive matches: `Module.hs`, `CodegenHs.hs`, `AstEmit.hs`, `TrustReport.hs`, `FixpointEmit.hs`, `ObligationAssembly.hs`, `ObligationMining.hs`, `WeaknessCheck.hs`, `Contracts.hs`, `SpecCoverage.hs`, `CDP.hs`, `PBT.hs`, `HubQuery.hs`, `PatchApply.hs`, `HoleAnalysis.hs`. `extractContract` and `runLeanstralPipeline` in `Main.hs` extended with `SDef`/`SDefShell` cases (two missed fan-out sites found during build). Library callers `HubQuery.hs`, `Module.hs`, `Serve.hs` updated to pass `GrammarLegacy` to parser entry-points.
- **No schema bump on this pass.** `schemaVersion` stays `0.5.0`. `SDef`/`SDefShell` dispatch rides `"kind": "def"` / `"kind": "def-shell"` JSON keys via `ParserJSON.hs` dispatchers without new required-field declarations. Schema bump `0.5.0 → 0.6.0` and default-flip from `GrammarLegacy` to `GrammarCoreInversion` are gated on the §8 empirical-validation gate (per [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) §8.4 step 4).
- **28 new LT-INV regression tests** (`INV-P1`–`INV-P8`, `INV-W1`–`INV-W7`, `INV-A1`–`INV-A5`, `INV-C1`–`INV-C5`, `INV-G1`–`INV-G3`) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) under a new `LT-INV (v0.11): core/shell grammar inversion` `describe` block.
- **F-GATE-1 (`parseJSONAST` grammar enforcement, commit [`cabb1fd`](compiler/src/LLMLL/ParserJSON.hs)): `{"kind":"def-logic"}` in `.ast.json` input is now rejected under `--grammar=core-inversion`** with a `core-grammar-violation` diagnostic (exit 1). Pre-fix, `parseJSONAST` ignored `GrammarMode` entirely — agents could submit `def-logic` solutions under `--grammar=core-inversion` and receive exit 0, making the §8 empirical-validation gate produce null data across all four axes (confirmed by Postmortem 003, `experiments/minimal-agent/findings/postmortem-003-s8-gate-pre-post.md`). Fix: `parseJSONAST` gains a `GrammarMode` parameter threaded to `parseProgram` / `parseStatement`; the `"def-logic"` dispatch branch fails with a `core-grammar-violation` sentinel under `GrammarCoreInversion`. `parseJSONASTValue` (used by `PatchApply`) retains its current signature and routes internally to `GrammarLegacy` (patch callers have no grammar-mode context). **3 new tests** INV-P9/P10/P11 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): INV-P9 — JSON-AST `def-logic` rejected under `GrammarCoreInversion`; INV-P10 — JSON-AST `def` accepted under `GrammarCoreInversion`; INV-P11 — JSON-AST `def-logic` still accepted under `GrammarLegacy` (backwards-compatibility regression guard).
- **F-GATE-1b (`letrec` enforcement + S-expression symmetry):** `{"kind":"letrec"}` in `.ast.json` input is now rejected under `--grammar=core-inversion`** with a `core-grammar-violation` diagnostic (exit 1), symmetric with `{"kind":"def-logic"}` (F-GATE-1). Companion fix: `pDefLogic` and `pLetrec` moved from the unconditional tail of `pStatement`'s `choice` list into the `GrammarLegacy` arm — `GrammarCoreInversion` arm: `[pDef, pDefShell]`; `GrammarLegacy` arm: `[pDefLogic, pLetrec]` — closing the S-expression-path asymmetry noted in F-GATE-1. `diagSuggestion` on `core-grammar-violation` updated to name both `def-logic` and `letrec` as rejected kinds. INV-P6 assertion inverted from "parses as SDefLogic" to "fails to parse" (the assertion was documenting the unintended behaviour; it now documents correct rejection). **3 new tests** INV-P12/P13/P14 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): INV-P12 — S-expression `(letrec ...)` fails to parse under `GrammarCoreInversion`; INV-P13 — JSON-AST `{"kind":"letrec"}` rejected with `core-grammar-violation`; INV-P14 — JSON-AST `{"kind":"letrec"}` accepted under `GrammarLegacy`. **Spec alignment note:** `LLMLL.md §4.1` and `getting-started.md §4.14` already stated that `letrec` is rejected under `--grammar=core-inversion`; this fix brings the compiler into alignment with the existing spec text.
- **Tests: 770 Haskell + 58 Python** (F-GATE-1b +3 INV-P12–P14; F-GATE-1 +3 INV-P9–P11; LT-INV +28; 4 additional tests from F-005 `WarnVacuousOverOmega` fix, commit `0b5b249`, account for the gap between the F-006/F-005 entry count of 712 and the 716 pre-LT-INV baseline).

### Compiler — LT-INT (v0.11): `int → Integer` codegen switch

- **LLMLL `int` lowers to Haskell `Integer` (unbounded mathematical-integer semantics)** at codegen, closing the documented `Int64` overflow gap on file since v0.8.1a per [`LLMLL.md §5.3.5`](LLMLL.md). Three primary codegen sites flip per [`docs/design/int-2-boundary-shims.md`](docs/design/int-2-boundary-shims.md) §8: [`compiler/src/LLMLL/CodegenHs.hs:441`](compiler/src/LLMLL/CodegenHs.hs#L441) `mapLlmllPrimType "int"`, [`:706`](compiler/src/LLMLL/CodegenHs.hs#L706) `emitLit (LitInt n)` ascription, [`:723`](compiler/src/LLMLL/CodegenHs.hs#L723) `toHsType TInt`. The verifier already reasoned over unbounded mathematical integers at [`compiler/src/LLMLL/FixpointEmit.hs:188-194`](compiler/src/LLMLL/FixpointEmit.hs#L188-L194); INT-2 aligns the Haskell-runtime side with the verifier-side semantics. INT-PRE cleared the regression at 1.015× TOTP test-phase against the 5× gate threshold (commit `8cac520`, [`experiments/int-pre/findings/postmortem-001.md`](experiments/int-pre/findings/postmortem-001.md)). Closes LT-INT / INT-2 row at [`docs/compiler-team-roadmap.md:170`](docs/compiler-team-roadmap.md).
- **Class B preamble entries lifted to `Integer`** per catalog §3.2: `llmll_abs`, `llmll_min`, `llmll_max` (polymorphic `abs`/`min`/`max` instantiated at `Integer`), `int_to_string` (`show` polymorphic), `string_to_int` (reads-target retyped `ReadS Integer`; closes a silent-truncation hazard for inputs exceeding `maxBound :: Int`), `range :: Integer -> Integer -> [Integer]`.
- **Class A indexing primitives keep concrete `Int` Haskell signatures** per catalog §3.1 rows 1–6 (`list_length`, `list_nth`, `string_length`, `string_slice`, `string_char_at`); codegen wraps `int`-typed arguments in `fromIntegral` at the LLMLL-to-Haskell call seam via new `emitApp` clauses at [`compiler/src/LLMLL/CodegenHs.hs:595-603`](compiler/src/LLMLL/CodegenHs.hs#L595-L603). `Int`-returning primitives (`list_length`, `string_length`) lift back to `Integer` at the call site. `wasi_http_response` refactored to `Integral i => i -> String -> IO ()` with `{-# SPECIALIZE :: Integer #-}` pragma (catalog §3.1 row 7, polymorphic sub-pattern).
- **INT-1 overflow-taint trigger dormant on `int`** per catalog §4. The body-VC emitter call to `addOverflowTainted` at [`compiler/src/LLMLL/FixpointEmit.hs:516`](compiler/src/LLMLL/FixpointEmit.hs#L516) is commented out under LT-INT; the walker `bodyHasOverflowArith` and the `erOverflowTainted` record field remain defined across the trust-report / sidecar / obligation surface (constructor, propagation rule, strict-core refusal preserved per catalog §4 "machinery preserved"). INT-3 (`machine-int`) re-arms the trigger by re-enabling the call with a type-aware predicate.
- **`examples/banking_ledger/banking.llmll` now passes `--strict-verified-core`.** `safe-subtract`'s `(- balance amount)` body — overflow-tainted in v0.10.8 — is no longer refused under the dormant trigger. Sidecar regenerated at [`examples/banking_ledger/banking.llmll.verified.json`](examples/banking_ledger/banking.llmll.verified.json) without the `overflow_tainted: true` tag.
- **8 new LT-INT regression tests** (L1–L8) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) cover the three primary sites, composite-type lowering, Class A shim assertions for `list-length` / `list-nth` / `string-slice`, and a preamble structure check. T10 (INT-1 end-to-end) repurposed as the dormant-trigger regression: a `(+ x 1)` body must NOT taint post-INT-2 while remaining body-faithful. Three Async codegen tests updated to reflect `TInt → Integer` lowering inside `TPromise`.
- **No language-surface change.** No new keywords, builtins, syntax constructs, or SMT theory. **No schema bump:** `schemaVersion` stays `0.5.0`; `trust_report_version` stays `1.1.0`. **No JSON-AST migration.** Pre-v0.11 `.verified.json` sidecars on `int`-only verified evidence load cleanly; sidecars previously carrying `overflow_tainted: true` are regenerated to drop the tag on next verify.
- **Spec drifts flagged (catalog Rev 4 candidates, routed to language-team):** (i) [`docs/design/int-2-boundary-shims.md`](docs/design/int-2-boundary-shims.md) §8 says "no `FixpointEmit.hs` changes" but §4 requires the trigger to be empty on `int`; engineer resolved by disarming at the emitter call site rather than the walker. (ii) The §3.4 `range`/`range_idx` split is intentionally not realized — corpus audit (`examples/{life,hangman,tictactoe}_sexp/*.llmll`) shows all `range` uses are `(range 0 N)` index-iteration patterns handled correctly by Class A `fromIntegral` shims; per-element conversion cost is within the INT-PRE budget. Engineer-shipped on branch `lt-int/integer-codegen-switch`, commit `9c37a5c4fd0bec7fe1076813c69085d2fbee4077`. **Tests:** 680 Haskell + 58 Python tests (LT-INT adds 8 Haskell tests; Python suite unchanged from the DRIFT-CI-1 entry below).

### Compiler — LT-CDP (v0.11): contract discriminative power evidence axis

- **`llmll verify --cdp` computes contract discriminative power per function** alongside the existing diamond-lattice evidence axis. The new metric extends [`compiler/src/LLMLL/WeaknessCheck.hs`](compiler/src/LLMLL/WeaknessCheck.hs)'s trivial-body enumeration from a binary "any trivial body passes?" check (legacy `--weakness-check`) to a Shannon-normalized counted-divergence score `DP_Ω(S) = 1 − log|⟦S⟧_Ω| / log|B_{T,U,Ω}|` over the closed v0.11 candidate set at [`docs/design/contract-discriminative-power-proposal.md`](docs/design/contract-discriminative-power-proposal.md) §4.3.1 (identity over each param + small ints `{0, 1, -1, 42}` + both bools + `{"", "a"}` + list-empty / list-singleton + `Success`-default / `Error "default"` + pair-of-defaults). Implements [LT-CDP](docs/compiler-team-roadmap.md) v0.11 Implementation Item 2.
- **New module [`compiler/src/LLMLL/CDP.hs`](compiler/src/LLMLL/CDP.hs)** owns score computation, observational-equivalence partition (naive O(N²) per proposal Risk #5; v0.12+ adopts Union-Find), and the typed-warning enumeration of proposal §5 — `identity-satisfies-post`, `const-satisfies-post`, `spec-inconsistent`, `enumeration-too-narrow`, `def-shell-out-of-scope`, `candidates-empty-under-limit`, `over-annotation-warning`, `not-requested`. The seven warnings distinguish *non-applicability* (`def-shell-out-of-scope`, `not-requested`) from *measurement weakness* (`enumeration-too-narrow`, `candidates-empty-under-limit`); downstream consumers must respect the distinction.
- **`CDPScope` is gate-conditional** per [`docs/design/v0.11-cross-proposal-rollback-discipline.md`](docs/design/v0.11-cross-proposal-rollback-discipline.md) §2 — defaults to `CDPScopeAllDefLogic` (Outcome 2 semantics) until LT-INV ships and the §8 empirical gate selects the post-gate default. The CDP implementation does not need re-shipping when the gate runs; only the scope-parameter default flips.
- **New `(spec-entropy :strict | :intentional | :unknown)` contract-level annotation** on `def-logic` / `letrec`, parsed in both S-expression ([`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs) `pSpecEntropyClause`) and JSON-AST ([`compiler/src/LLMLL/ParserJSON.hs`](compiler/src/LLMLL/ParserJSON.hs) `parseSpecEntropyField`) frontends. Strict — unknown labels are a parse error, not a silent default. Absent annotation defaults to `Nothing` on the `Contract` record (treated as `:strict` at consumption sites); `Just _` is explicit author intent. `:intentional` suppresses the low-DP diagnostic per proposal §3 / Risk #3 (self-attestation discipline; LH `{-@ assume @-}` precedent).
- **`trust_report_version` bumped `1.1.0 → 1.2.0` (additive)** at [`compiler/src/LLMLL/TrustReport.hs`](compiler/src/LLMLL/TrustReport.hs). New per-entry `discriminative_axis` JSON block per proposal §5 carrying `score`, `basis`, `candidate_count`, `satisfying_candidate_count`, `distinct_observed_behavior_count`, `distinguishing_inputs`, `spec_entropy_annotation`, `warnings`. Without `--cdp`, the block populates with `score: null`, `basis: "not-measured"`, and `warnings: ["not-requested"]` so consumers see a uniform shape and do not need to special-case absence. [`docs/llmll-trust-report.schema.json`](docs/llmll-trust-report.schema.json) `$id` URL `v1.1 → v1.2`, new `$defs/DiscriminativeAxis` with strict warning enumeration. Existing `tier_profile`, `tier_profile_pre/post`, `joint_pbt_witnesses`, `overflow_tainted_fns` unchanged.
- **Module-level `over-annotation-warning` diagnostic** fires when the ratio of `(spec-entropy :intentional)` to total contracted functions exceeds the threshold (default 30%, per proposal §10 Risk #3). Informational, not blocking; threshold is fixed in v0.11 (env-var configurability deferred).
- **Score is observational over Ω.** Load-bearing per proposal §1 Rev 2: `DP_Ω(S) = 0.82` means "82% of *observed* candidate behaviors over the chosen observation set `Ω` are ruled out," **not** "82% of wrong implementations are ruled out" in any semantic sense. Cross-function and cross-version score comparison requires same-`Ω` discipline; the `basis` field makes `Ω`'s identity auditable. Consumers setting CI gates on CDP scores must respect this distinction or risk gating on the wrong reading.
- **Catalog widening — legacy `--weakness-check` unchanged.** `WeaknessCheck.hs` factors into two entry points: `generateWeaknessCandidates` preserves the v0.10 5-enumerator catalog (`TrivConstZero` subsumed into `TrivConstInt 0`, `TrivConstEmptyStr` into `TrivConstString ""`, `TrivConstTrue` into `TrivConstBool True`); `generateCDPCandidates` ships the §4.3.1 closed enumeration. Legacy `--weakness-check` diagnostic surface is unchanged — no new spec-weakness flags fire on existing programs.
- **Schema notes.** **No JSON-AST `schemaVersion` bump** — stays `0.5.0`. Per [`v0.11-cross-proposal-rollback-discipline.md`](docs/design/v0.11-cross-proposal-rollback-discipline.md) §2, the `(spec-entropy …)` annotation rides the LT-INV bundle (Outcomes 0/1 — `0.5.0 → 0.6.0`) or coordinates with LT-PPR (Outcome 2 — independent `0.5.0 → 0.5.1`). The parser accepts the field today; the schema declaration follows in the sibling-ship turn. **No `expectedSchemaVersion` change**, **no `.verified.json` migration**, **no solver-time delta** (CDP reuses the existing `emitFixpoint` + liquid-fixpoint loop per candidate; no new SMT fragment expansion per proposal §8).
- **22 new tests** (`C1`–`C22`) under a new `LT-CDP (v0.11): contract discriminative power` `describe` block in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) — candidate enumeration per return type (C1–C7), score-formula edge cases (C8–C11), spec-entropy parse + roundtrip in both frontends (C12–C15), trust-report JSON shape and the seven typed warnings (C16–C19), joint-witness compatibility regression guard (C20), over-annotation diagnostic (C21), and `computeCDPFor` end-to-end with a stub solver (C22). Three new fixtures under [`compiler/test/fixtures/cdp/`](compiler/test/fixtures/cdp/) (`verified-strong.llmll`, `verified-weak.llmll`, `intentional.llmll`). Engineer-shipped on branch `lt-cdp/discriminative-power-axis`, commit `121815a`. Intermediate test count: 702 Haskell + 58 Python.

### Compiler — LT-PPR (v0.11): predicate-carrying `?proof-required`

- **`(?proof-required :reason "tag" pred-expr)` is a new S-expression form** accepted in `pre` and `post` contract positions inside `def-logic` and `def-shell` (LT-PPR, commit `3391713`). The bare `?proof-required` leaf and the `(?proof-required :reason "tag")` form without a predicate are unchanged. `pred-expr` is type-checked as `bool` by [`compiler/src/LLMLL/TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs). `isCoreBodySyntactic` in [`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs) rejects `?proof-required` (both forms) from strict-core `def` bodies under `--grammar=core-inversion`, consistent with its pre-LT-PPR treatment.
- **A predicate-carrying `?proof-required` in `pre`/`post` position emits a Haskell runtime assertion** in generated code (`if <pred> then () else error "proof-required: <reason>"`), instead of the previous no-op. Pre-LT-PPR, all `?proof-required` in `pre`/`post` were no-ops at codegen; the clause was marked `asserted` and otherwise ignored at runtime. Body-position `?proof-required` continues to emit an `error "proof-required"` stub; no runtime assertion change there.
- **Non-linear predicates in the predicate-carrying form emit a `QF-LIA` warning at `llmll check`** when `pred-expr` contains `*`, `/`, `mod`, or `^`. The warning names the function and clause. Non-linearity detection reuses `isNonLinear` now exported from [`compiler/src/LLMLL/HoleAnalysis.hs`](compiler/src/LLMLL/HoleAnalysis.hs) and shared with the type-checker.
- **`hole-proof-required` JSON-AST node gains an optional `"predicate"` field** (`{ "$ref": "#/$defs/Expr" }`). The bare-leaf form omits the field; the predicate-carrying form sets it. The `"reason"` field semantics are unchanged. **No `schemaVersion` bump** — stays `0.5.0` per [`docs/design/v0.11-cross-proposal-rollback-discipline.md`](docs/design/v0.11-cross-proposal-rollback-discipline.md) §2; schema bump is bundled with the LT-INV default-flip gate.
- **`--trust-report --json` per-entry output gains six additive fields** when a predicate-carrying `?proof-required` is present on the entry's function: `pre_predicate_form` (form-mode label: `"runtime"` in v0.11), `pre_predicate_text` (JSON-encoded predicate expression), `pre_runtime_check_emitted` (only-when-true bool), and `post_*` equivalents. Note: `predicate_form` is the enforcement-mode label, not an expression string; `predicate_text` is the expression, not a label — these descriptions correct an inversion in a prior draft of this entry. Fields are emitted only when non-default; absent-predicate entries see no shape change. `trust_report_version` stays `1.2.0` (set by LT-CDP; PPR fields are strictly additive). Schema: [`docs/llmll-trust-report.schema.json`](docs/llmll-trust-report.schema.json) `$defs/TrustEntry` gains the six fields.
- **+20 new LT-PPR regression tests** (`PPR-P1`–`PPR-P4`, `PPR-T1`–`PPR-T5`, `PPR-A1`–`PPR-A2`, `PPR-TR1`–`PPR-TR4`, `PPR-CG1`–`PPR-CG3`, `PPR-G1`–`PPR-G2`) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs). Running total at cluster commit `3391713`: 764 Haskell + 58 Python (before F-GATE-1 follow-ons; see LT-INV entry above for post-F-GATE-1 aggregate).

### Compiler — fix: DiagnosticFQ partial-record crash on `--json verify` SAFE (F-001)

- **Three branches of `fqResultToReport` in [`compiler/src/LLMLL/DiagnosticFQ.hs:94-115`](compiler/src/LLMLL/DiagnosticFQ.hs) now initialize the `reportPhase :: Text` field to `"lh-fixpoint"`.** Pre-fix the field was omitted at construction and fell to ⊥; any consumer accessing it — notably `formatReportJson` at [`compiler/src/LLMLL/Diagnostic.hs:352`](compiler/src/LLMLL/Diagnostic.hs) — crashed with `Missing field in record construction reportPhase`. Latent across the entire `--trust-report` lifetime because the typical `--json verify --trust-report` SAFE path early-exited at [`compiler/app/Main.hs:1078`](compiler/app/Main.hs) before reaching the verifier loop; surfaced by the LT-CDP code-path change at commit `121815a` and reproduced empirically by the experiment-lead CDP-0 baseline harness (finding F-001 in `experiments/cdp-0/findings/postmortem-001-cdp-baseline-blocked.md`).
- **Phase string `"lh-fixpoint"`** follows the convention at [`compiler/src/LLMLL/TypeCheck.hs:413`](compiler/src/LLMLL/TypeCheck.hs) (`"typecheck"`) and [`compiler/src/LLMLL/PatchApply.hs:254`](compiler/src/LLMLL/PatchApply.hs) (`"patch"`) — short lowercase kebab tokens naming the source phase.
- **GHC `-Wmissing-fields` warned at compile time** (GHC-20125 at lines 96, 102, 108) but was filtered as "pre-existing" during the LT-CDP build inventory; the bug had zero test coverage (no test imported `fqResultToReport` or `formatReportJson`). Four regression tests (DF-1 through DF-4) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) close the test gap by forcing evaluation of `reportPhase` both directly and through the Aeson JSON encoder; drop the field-init and DF-4 fails with the same runtime exception observed on the CLI.
- **End-to-end smoke verified.** `stack exec llmll -- --json verify ../examples/benchmarks/b1-withdraw.llmll` returns exit 0 with a JSON object containing `"phase":"lh-fixpoint"`; the CDP-0 harness is unblocked. Net build-warning delta: −5 (three `-Wmissing-fields` + two `-Wunused-matches` eliminated by the same field-initialization patch).
- **Zero schema delta, zero solver-time delta, zero trust-model effect, zero language-surface change.** Engineer-shipped on branch `fix/diagnosticfq-partial-record` (off `lt-cdp/discriminative-power-axis`), commit `e5e6d04`. **Tests:** 706 Haskell + 58 Python (LT-CDP added 22 Haskell tests; F-001 added 4; Python suite unchanged from the LT-INT entry above; observed-vs-published Python-count discrepancy of +3 carried forward as a follow-up routing item).

### Compiler — fix: WeaknessCheck zero-candidate generation (F-006 / F-005 ancillary)

- **`generateCDPCandidates` now produces non-zero `candidate_count` for functions whose parameters carry custom type aliases (e.g. `PositiveInt`).** Root cause (F-006): `tryCandidate` called `typeCheck builtinEnv [syntheticStmt]` with an empty `tcAliasMap`; `expandAlias (TCustom "PositiveInt")` returned the opaque `TCustom` node unchanged, causing `structuralUnify` to fail the synthetic pre-condition check and filter every candidate. Fix: `generateForStmt` now receives the full module-level `[Statement]` list; `tryCandidate` prepends `[s | s@STypeDef{} <- allStmts]` to the synthetic type-check call, so `checkStatements` populates `tcAliasMap` with module-level aliases before checking the contract. Restores `b1::withdraw` and `b3::safe-first` from `candidate_count = 0` to `candidate_count ≥ 2` per [`experiments/cdp-0/findings/postmortem-002-cdp-baseline-rerun.md`](experiments/cdp-0/findings/postmortem-002-cdp-baseline-rerun.md) acceptance criteria.
- **`cdpCatalog` now generates the full §4.3.1 constant enumeration for sexp-parsed functions whose return type is unannotated (`mRet = Nothing`).** Root cause (F-005 ancillary): `matchesReturnType _ Nothing = False` suppressed all constant generation; only identity candidates were produced. Fix: new private helper `matchesReturnTypeOrUnknown :: Type -> Maybe Type -> Bool` (`_ Nothing = True`) used in the `ints`, `bools`, and `strings` arms of `cdpCatalog`; `Nothing` arms added to the `lists` (`[TrivConstEmptyList]`) and `sums` (`[TrivConstError]`) cases. The type-checker (INV-4) filters incompatible candidates before the solver. `legacyCatalog` and the `--weakness-check` diagnostic surface are unchanged. Restores `b5::double` from `candidate_count = 1` (identity-only) to `candidate_count ≥ 5` (1 identity + 4 int constants).
- **`WarnVacuousOverOmega` CDP warning added** for the tight-but-verified case: when a `def-logic` function has body-faithful verified evidence (`DLVerified`/`DLContractChecked`) and no candidate satisfies the contract over Ω, the warning is `WarnVacuousOverOmega` rather than `WarnSpecInconsistent`. `WarnSpecInconsistent` is now reserved for functions without verification evidence. `provenCS` hoisted out of the `FQSafe` sidecar arm to share the verified-map oracle between CDP and the trust-report path. Engineer-shipped on branch `fix/diagnosticfq-partial-record`, commit `0b5b249` (F-005 follow-on). +4 Haskell tests.
- **Zero language-surface change, zero CLI flag change, zero schema change.** `--cdp` behavior is externally identical for functions with fully annotated types; the fix removes false-negative filtering on the type-alias and unannotated-return code paths only. Engineer-shipped on branch `fix/diagnosticfq-partial-record`, commit `6f2ea39`. **Tests:** 716 Haskell + 58 Python (+6 Haskell: F6-1–F6-6 candidate-generation regression tests in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) under the `"LT-CDP (v0.11): contract discriminative power"` describe block; +4 Haskell: `WarnVacuousOverOmega` disambiguation tests, commit `0b5b249`).

### CI — DRIFT-CI-1 version-gate workflow + harness

- **Closes both DRIFT-CI-1 residuals named on [`docs/compiler-team-roadmap.md:304`](docs/compiler-team-roadmap.md) and [`docs/design/critique-2026-05-23-triage.md:111`](docs/design/critique-2026-05-23-triage.md):** the `.github/workflows/version-gate.yml` automation and the whole-spec round-trip harness for C5. Content (C1–C5) was already satisfied at v0.10.8 via doc-lead Pass 6 + Pass 7; this patch adds the mechanical enforcement that prevents future drift.
- **[`scripts/version_gate.sh`](scripts/version_gate.sh)** implements C1+C2+C3+C4. C1+C2: banner equality across `README.md` line 1, `LLMLL.md` line 1, the first `## vX.Y.Z` heading in `CHANGELOG.md`, `compiler/package.yaml` `version:` field, and `compiler/llmll.cabal` `version:` field. C3: `docs/llmll-ast.schema.json` `$defs.Program.properties.schemaVersion.const` equals `compiler/src/LLMLL/ParserJSON.hs::expectedSchemaVersion`. C4: schema `$id` URL contains `/schemas/vMAJOR.MINOR/` derived from the `schemaVersion` const. Pure POSIX shell + `grep`/`awk`/`jq`; no Stack/GHC dependency; runs in well under a second locally. Exits 0 on all-pass, exits 1 with a single-line `DRIFT-CI-1 FAIL: <criterion> ...` message on first failure.
- **[`scripts/spec_roundtrip.py`](scripts/spec_roundtrip.py)** implements C5 as an *opt-in* harness. Spec authors mark a fenced ` ```lisp ` or ` ```llmll ` block with `<!-- ci:roundtrip -->` (or `<!-- ci:roundtrip: strict -->` for warnings-as-errors) immediately above the fence opener, allowing at most one blank line in between. The script writes each opted-in block to a tempfile and shells out to `llmll check` (overridable via `LLMLL_BIN`; default `stack exec llmll --`). Failures surface as `FAIL <path>:<line> ...` and a non-zero exit. Opt-in (rather than default-on with skip annotations) was chosen after on-tree inspection of `LLMLL.md`: nearly every `lisp` block references unbound names or undefined refinement types per spec convention, so default-on would require ~50+ skip markers and pollute the spec with CI noise. Doc-lead extends the opt-in surface in subsequent passes.
- **Initial opt-in set: one block** at [`LLMLL.md:396`](LLMLL.md) (the §4.4.3 `(trust ...)` example), chosen because it parses cleanly without external context. The block exercises the harness end-to-end against the real `llmll` binary in CI so a misconfigured `LLMLL_BIN` invocation surfaces in the workflow rather than silently passing on zero blocks.
- **[`.github/workflows/version-gate.yml`](.github/workflows/version-gate.yml)** is the first GitHub Actions workflow in this repository. Two jobs trigger on `push` to `main` and on `pull_request` against `main`. Job `version-gate` (Ubuntu, no Stack toolchain, target wall-clock <1 min): installs `jq`, runs `scripts/version_gate.sh`, runs the 21-case pytest suite at `scripts/tests/`. Job `spec-roundtrip` (Ubuntu, Stack toolchain with `~/.stack` + `compiler/.stack-work` cached against `compiler/stack.yaml.lock`, target wall-clock ~5 min steady-state): builds `llmll`, runs `scripts/spec_roundtrip.py` against `LLMLL.md` opt-in blocks. Scope discipline: workflow is intentionally named `version-gate.yml`, not `ci.yml`, and does not run `stack test` or the harness/orchestra Python suites — those belong to a separate ticket. Security posture: no `run:` block interpolates `${{ github.event.* }}` or any attacker-controllable context; the only `${{ }}` expressions used are `runner.os` and `hashFiles(...)`.
- **21 new pytest cases at [`scripts/tests/`](scripts/tests/)** — 11 for `version_gate.sh` (live-tree pass, synthetic-repo pass, one failure case per criterion + a substring-extraction edge case) and 10 for `spec_roundtrip.py` (no-opt-in pass, opt-in stub pass/fail, blank-line-gap allowed, distance-gap rejected, `strict` flag pass-through both directions, `llmll` tag accepted alongside `lisp`, mixed pass/fail aggregation, missing-spec-file error). Tests inject a Python `llmll` stub via the `LLMLL_BIN` env var so they have no Stack dependency and run in under a second.
- **Inside-freeze, narrowing.** No new syntax, no new builtins, no new SMT theory, no schema bump (`expectedSchemaVersion` stays `0.5.0`), no `trust_report_version` change, no verifier or type-checker surface change, no `.verified.json` migration, no solver-time delta. Pure CI scaffolding; rollback is a single revert. **Test count: 672 Haskell + 58 Python (37 prior + 21 new DRIFT-CI-1 harness cases).**

### Docs — DOC-CONSOLIDATE documentation consolidation and SOP

- **DOC-CONSOLIDATE — Project documentation consolidation and SOP** (settled at [`docs/design/doc-consolidation-2026-05-24-proposal.md`](docs/design/doc-consolidation-2026-05-24-proposal.md) Rev 1, 2026-05-24). Introduces [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) codifying P1 canonical-source bindings and the per-change update matrix (§3.1–3.3 verbatim); collapses per-experiment per-role findings to a single `experiments/<harness>/findings.md` with H2-per-role per §M1/§4.3; folds settled professor reviews into proposal `## Appendix — Professor review log` sections per §M2 and archives the standalone review files; archives pre-roadmap-reorganization wasm spike docs per §M4; H2-anchor reorg of [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) per §M5 small-cut plus P1 strip of the roadmap header's version stamp; migrates the active items from `docs/research-track.md` into the roadmap with a deferred-overlap-audit wrapper. No language-surface change, no schema bump (`expectedSchemaVersion` stays `0.5.0`), no `trust_report_version` change, no compiler change, no test count delta. Eliminates the three-source status-drift pattern flagged in proposal §1 by routing through P1 canonical sources for the *version* and *implementation-routing* bindings; the *design-doc-status* P1 binding (M6 INDEX.md demotion to one-liners) is deferred to a follow-up doc-lead pass.
- **Files added:** [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) (§3 verbatim); [`experiments/minimal-agent/findings.md`](experiments/minimal-agent/findings.md), [`experiments/int-pre/findings.md`](experiments/int-pre/findings.md), [`experiments/repair-loop/findings.md`](experiments/repair-loop/findings.md) (H2-per-role per §M1); `docs/archive/professor-reviews/` and `docs/archive/wasm-investigations/` subdirs.
- **Files archived (with 2-line redirect stub at old path for one release cycle):** `docs/design/{invariant-discovery,oblig-pbt-3}-review.md` → `docs/archive/professor-reviews/` (M2 case 1; preceded by `## Appendix — Professor review log` fold into the matching proposals); `docs/{effectful-wasm-spike,wasm-poc-report}.md` → `docs/archive/wasm-investigations/` (M4); `docs/design/proof-required-predicate-carrier.md` → `docs/archive/shipped-design-specs/` (M2 case 2 superseded-seed); `docs/research-track.md` → `docs/archive/` (M4; per-item overlap audit deferred to language-team).
- **Files edited:** [`README.md`](README.md) (M3 ~70-line CHANGELOG-shaped-paragraph strip; stale-callout refresh; repository-layout and Documentation-table refresh); [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) (M5 small-cut ToC + H2-anchor normalization for `Upcoming Releases` / `Cross-cutting concerns` / `Summary` / `Shipped Releases`; P1 header version-stamp strip; research-track migration R1–R7 with overlap-audit-deferred wrapper); [`docs/design/invariant-discovery-proposal.md`](docs/design/invariant-discovery-proposal.md) and [`docs/design/oblig-pbt-3-proposal.md`](docs/design/oblig-pbt-3-proposal.md) (`## Appendix — Professor review log` fold per §M2).
- **Skill blocks (verified, no edit):** all 5 `.claude/skills/*/SKILL.md` files already carry `## Documentation discipline` sections per §4.1–4.5 referencing [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md); applied in a prior pass, no further edit on this PR.
- **Deferred to follow-up:** `docs/design/INDEX.md` M6 demotion to one-line entries; per-item overlap audit of migrated research-track items R1–R7 against existing roadmap rows. Both surfaced as findings in the doc-lead plan and routed to language-team for the follow-up pass.
- **R1–R7 overlap audit close-out** (DOC-CONSOLIDATE §11 follow-up): four cross-references applied to roadmap research-track section, R3 partial-criterion flagged; DOC-CONSOLIDATE fully closed.
- **Net active doc surface:** −11 active files (−9 role files folded; −6 docs/ files archived; +4 new files: UPDATE-PROTOCOL.md + 3 findings.md). All archive moves carry 2-line redirect stubs at the old paths for one release cycle. **No test count delta** — the closing 672 Haskell + 58 Python figure inherited from the DRIFT-CI-1 entry above stands for the whole Unreleased section.
- **Design-folder Phase 2 cleanup** (DOC-CONSOLIDATE §4.4 follow-up): re-homed two orphan empirical docs to `experiments/` ([`experiments/methodology.md`](experiments/methodology.md), [`experiments/repair-loop/findings/phase3-problem-shape-audit.md`](experiments/repair-loop/findings/phase3-problem-shape-audit.md)) with 2-line redirect stubs at the old `docs/design/` paths for one release cycle; codified pre-planned archive moves as [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) §3.4 (gated archive-trajectory table for ten in-flight design docs); flagged the `docs/archive/shipped-design-specs/` sub-categorization threshold (~20 entries; currently 11) and a forward-looking `docs/archive/dormant-explorations/` subdir in §3.3; deleted the resolved `## Orphan / Empirical-Track Notes` section from [`docs/design/INDEX.md`](docs/design/INDEX.md). Net active-doc delta: −2 files in `docs/design/` (orphan-section removal + 2 relocations); +2 redirect stubs (auto-delete one release cycle later); +1 protocol appendix; +2 files under `experiments/`. Zero schema, spec, code, test, version, or trust-report change.
- **Design-folder N1 status audit** (DOC-CONSOLIDATE §4.4 follow-up): archived `docs/design/lead-agent.md` → `docs/archive/shipped-design-specs/lead-agent.md` (v0.4 design shipped end-to-end per [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) §v0.4 phases 0–2; status-drift closure matching the existing shipped-design-specs pattern) with 2-line redirect stub at the old path for one release cycle; relabeled `agent-orchestration.md`, `component-hub.md`, `type-driven-development.md` as **Dormant** with reason suffixes (no change to `language-comparison-experiments.md`, which stays Active per audit). [`docs/design/INDEX.md`](docs/design/INDEX.md) Future Infrastructure row count: 5 → 4 (1 active + 3 dormant); Archived Material `shipped-design-specs/` listing extended. Net delta: −1 active doc in `docs/design/`; +1 archive file; +1 redirect stub. Zero schema, spec, code, test, version, or trust-report change.

---

## v0.10.8 — INT-1 Overflow-Taint Marking + Strict-Core Refusal (2026-05-24)

### Compiler — INT-1 Overflow-Taint Propagation on Verified Evidence

- **`erOverflowTainted :: Bool` added to `EvidenceRecord` at [`compiler/src/LLMLL/Syntax.hs:326-331`](compiler/src/LLMLL/Syntax.hs#L326-L331).** The flag marks `DLVerified` body-faithful evidence whose function body contains LLMLL-level integer arithmetic over non-literal operands. The flag's semantic is: "this evidence is sound at the verifier level but the underlying Haskell `Int` arithmetic may overflow, making the codegen-level guarantee weaker than the Z3-level guarantee." This is the operational discharge of the documented `Int64` overflow gap at [`LLMLL.md §5.3.5:765-770`](LLMLL.md#L765-L770), which has been on the books since v0.8.1a's documentation-boundary pass. Per the 2026-05-23 critique-triage routing at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) row INT-1; inside-freeze, narrowing fix.
- **Body-VC emitter activates the tag.** [`compiler/src/LLMLL/FixpointEmit.hs:506-516`](compiler/src/LLMLL/FixpointEmit.hs#L506-L516) calls `when (bodyHasOverflowArith body) (addOverflowTainted name)` immediately after `addBodyFaithful name`, gated on body-faithful VC success. The new helper `bodyHasOverflowArith :: Expr -> Bool` (exported for testing, defined at [`compiler/src/LLMLL/FixpointEmit.hs:597-642`](compiler/src/LLMLL/FixpointEmit.hs#L597-L642)) runs a pure syntactic walk over the body Expr looking for `EOp` / `EApp` whose head is in `{+, -, *, /, mod, rem, ^, **}` and whose operands are not all integer literals whose folded value fits `Int64`. Pure-literal arithmetic like `(+ 40 2)` clears (the compile-time constant is in `Int64`); any non-literal operand or out-of-range literal taints the surrounding op. No new SMT constraints emitted, no QF-BV introduced, no solver-time delta — the cost is one Expr walk per body-faithful function (estimated <100µs on TOTP-scale inputs).
- **`--strict-verified-core` refuses overflow-tainted verified evidence.** [`compiler/app/Main.hs:1119-1158`](compiler/app/Main.hs#L1119-L1158) extends the refusal set from `erBodyFallback` to `erBodyFallback ∪ erOverflowTaintedFns`. The two causes are mutually exclusive (taint is gated on body-faithful success) and each gets a distinct error message: fallbacks report "fell back from body-faithful verification"; taints report "carry overflow-tainted verified evidence (unbounded-Int arithmetic; clear via `?proof-required` + Leanstral or wait for INT-2 unbounded `int`)". JSON-mode output structures the two causes as separate `strict_errors` entries with `cause`, `fns`, and `msg` fields. The non-strict consumer behavior is unchanged: trust report, obligation report, and sidecar continue to surface the tag without exiting non-zero.
- **Trigger set is empty post-INT-2.** Once the v0.11 INT-2 codegen switch lands (`int → Integer` at codegen, per [`docs/design/int-2-boundary-shims.md`](docs/design/int-2-boundary-shims.md) §4), `int`-typed arithmetic lowers to unbounded `Haskell.Integer`; no overflow event exists to propagate. The taint machinery becomes dormant on `int` and re-arms naturally on the post-freeze `machine-int` opt-in primitive tracked at [`docs/design/int-3-machine-int-sketch.md`](docs/design/int-3-machine-int-sketch.md) §3.2. INT-1 is therefore neither dead code post-INT-2 nor active-on-`int` post-INT-2 — it is dormant on `int`, armed for `machine-int`.
- **Closes `LLMLL.md §3` doc-lead gating.** [`docs/compiler-team-roadmap.md:300`](docs/compiler-team-roadmap.md) (DRIFT-1 row) explicitly gated the §3 type-system catch-up on INT-1 shipping; this release unblocks the doc-lead Pass 7 on `LLMLL.md §3`.

### Compiler — Sidecar JSON Encoding + Invalidate-on-Missing

- **`.verified.json` gains optional `overflow_tainted: true` per-clause.** [`compiler/src/LLMLL/VerifiedCache.hs:71-94`](compiler/src/LLMLL/VerifiedCache.hs#L71-L94) extends `erToJSON` to emit the field only when `True` (matching the additive-back-compat shape used for `pbt_witnesses` at line 78). `erFromJSON` defaults the absent field to `False` for additive-back-compat reads; the older v0.10.7-vintage sidecars without the field decode cleanly into untainted records.
- **`loadVerified` invalidates pre-v0.10.8 sidecars to avoid silent under-strictness.** [`compiler/src/LLMLL/VerifiedCache.hs:158-216`](compiler/src/LLMLL/VerifiedCache.hs#L158-L216) gains `sidecarNeedsRevalidation` that returns `True` when any `DLVerified` body-faithful entry lacks the `overflow_tainted` field. Such sidecars return `Map.empty`, forcing a re-verify under v0.10.8's taint scan. The targeted-invalidation contract is: untainted entries that lack the field are read as untainted (back-compat), but verified body-faithful entries are re-checked under the new rule so strict-core consumers never see a silent false-negative on a stale sidecar. CI pipelines that hash-pin `.verified.json` artefacts may see one-time hash changes after upgrading; the new shape is stable thereafter.

### Compiler — Trust-Report and Obligation-Report Surfacing

- **`--trust-report --json` aggregates `overflow_tainted_fns` at the top level + per-entry `overflow_tainted: true`.** [`compiler/src/LLMLL/TrustReport.hs:701-735`](compiler/src/LLMLL/TrustReport.hs#L701-L735) adds an `"overflow_tainted_fns": [names…]` array next to the existing `"joint_pbt_witnesses"` aggregate, and a per-entry `"overflow_tainted": true` (emitted only when true) on the matching trust-report entries. `trust_report_version` stays `"1.1.0"` per the OBLIG-PBT-5a precedent at line 712: the field is purely additive at JSON-shape level, readers ignore unknown keys, the JSON shape grows monotonically.
- **`--obligation-report --json` per-clause trust channel gains `overflow_tainted`.** [`compiler/src/LLMLL/ObligationAssembly.hs:114-119, 543, 549-550, 582-592, 628-634, 802-812`](compiler/src/LLMLL/ObligationAssembly.hs#L114-L119) extends `TrustChannel` with `trOverflowTainted :: Bool`, threads the `erOverflowTaintedFns` set from `EmitResult` through `assembleHoleObligations` / `mkHoleObl`, and emits `"overflow_tainted": true` on the trust channel only when set. Untainted obligations preserve their pre-v0.10.8 trust-channel JSON byte-identically.
- **Verify-text mode summary line.** [`compiler/app/Main.hs:1107-1119`](compiler/app/Main.hs#L1107-L1119) adds an `overflow-tainted: <names>` summary line, parallel to existing `body-faithful` and `body-fallback`. Emitted only when non-empty.

### Examples — Regen with Overflow-Taint Awareness

- **`examples/banking_ledger/banking.llmll.verified.json` regenerated.** The `safe-subtract` function (body `(- a b)` over two `int` parameters) now carries `overflow_tainted: true` on its DLVerified body-faithful post. `withdraw`, `transfer`, `clamp-withdraw`, and `withdraw-twice` do not taint at their own body level (each body is a user-function call, not direct arithmetic); transitive trust over the tainted `safe-subtract` is not propagated to caller-level taint because the taint is per-function-body, not per-trust-closure. `--strict-verified-core` on this fixture now hard-errors at `safe-subtract` — design-intended per the deliberate narrowing.
- **Other tracked sidecars unchanged in semantic content.** `examples/erc20_token/erc20_filled.ast.json.verified.json` uses a pre-v0.8.1b sidecar shape (`level` field directly, no `display_level` wrapper) that was already stale on read before INT-1; not regenerated in this release.

### Schema — Trust-Report Output Schema Additive Update

- **`docs/llmll-trust-report.schema.json`** (post-engineer-ship doc-lead scope) is expected to gain an optional `overflow_tainted_fns: [string]` top-level property and an optional `overflow_tainted: const true` boolean on `TrustEntry`. `trust_report_version` stays `"1.1.0"` per the additive-field policy.
- **`docs/llmll-ast.schema.json`** unchanged. No AST node shape change in this release; `expectedSchemaVersion` stays `0.5.0`.

### Test surface

- **+16 Haskell test cases** under `describe "INT-1 (v0.10.8): overflow taint propagation"` in [`compiler/test/Spec.hs`](compiler/test/Spec.hs), covering: T1 literal-only arithmetic clearance; T2-T6 propagation across `EOp` / `EApp` / nested heads; T7 Class A indexing primitives stay untainted; T8 `ELet` rhs propagation; T9 `EIf` branch propagation; T10 end-to-end emit through `emitFixpointWith`; T11 pure-predicate body stays untainted end-to-end; T12 sidecar round-trip preserves `overflow_tainted: true`; T13 pre-v0.10.8 verified body-faithful sidecar is invalidated; T14 v0.10.7 asserted-only sidecar loads normally (targeted invalidation); T15 trust-report JSON aggregation; T16 small-sample literal-arithmetic clearance property.
- **Test count: 656 → 672 Haskell + 37 Python = 709 total passing.** No existing test regressed under the EvidenceRecord field addition (eight positional construction sites in `compiler/src/LLMLL/{Module,TrustReport,PBT}.hs`, `compiler/app/Main.hs`, and ~30 sites in `compiler/test/Spec.hs` were mechanically updated to add the fifth `False` argument; one `Spec.hs:5521` multi-line case kept the literal in place).

---

## v0.10.7 — EOp Arity/Type-Check Fix + Joint PBT Witness Exclusion (2026-05-23)

### Compiler — TC-EOP-1 EOp Arity and Argument-Type Checking

- **`inferExpr (EOp op args)` now checks arity and unifies each argument against the corresponding parameter type.** Pre-fix the function ignored `args` entirely at [`compiler/src/LLMLL/TypeCheck.hs:981-988`](compiler/src/LLMLL/TypeCheck.hs#L981-L988) and returned the `builtinEnv` result type unconditionally, so `(+ 1)`, `(+ 1 2 3)`, `(+ "x" 1)`, `(not 1)`, `(= 1 "1")`, `(and true 0)`, etc. silently typechecked. The rewrite mirrors the `EApp` path at lines 920-973: arity check + `foldM` over args with `structuralUnify`'s per-call-site substitution map, `withSegment "args"` pointer-stack discipline, and `EHole` bypass via `checkExpr`. Polymorphic operators (`=`, `!=`) bind `TVar "a"` from arg 0 and require arg 1 to unify against the same type — no `any × any → bool` degrade. Per the 2026-05-23 critique-triage routing at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) row TC-EOP-1; narrowing fix admitted under the v0.10-era freeze.
- **No example regressions.** The full `examples/` corpus (16 `.llmll` + 18 `.ast.json` shipping fixtures) typechecks unchanged under the new arity/type discipline. Pre-existing parse failures on `examples/pair_type_test/pair_type_test.llmll` (return-type comma surface) are orthogonal.

### Compiler — OBLIG-PBT-5a Joint PBT Witness Exclusion

- **Scalar `tested` counts no longer over-credit `:subjects [f g …]` joint lifts.** OBLIG-PBT-4 emits one `EvidenceRecord` per declared subject with a shared `canonicalPropBodyHash`; the v0.10.6 trust-report counted each as `+1 tested`, so N subjects sharing one property body contributed N to `summary.tested` / `tier_profile.tested` / `tier_profile_post.tested`. v0.10.7 computes a `jointHashes :: Set Text` (hashes appearing on ≥2 distinct subjects' post-clause witnesses) in [`compiler/src/LLMLL/TrustReport.hs`](compiler/src/LLMLL/TrustReport.hs) and demotes any `DLTested` entry whose post-clause evidence has non-empty `erPbtWitnesses` AND every hash in `jointHashes` to `DLAsserted` at classification time. The underlying `EvidenceRecord` is left intact on the entry (and in `.verified.json` sidecars) so the clean OBLIG-PBT-5b fix can promote a `tested-joint` display level post-freeze without losing data.
- **"Every witness is joint" predicate is load-bearing.** A subject with both a joint-shared witness AND a solo (single-subject) witness on the same evidence record keeps its `+1 tested` credit — only pure-joint entries are demoted. Source-annotated `DLTested` from `:trust tested` markers (empty `pbt_witnesses`) is also unaffected because the predicate requires non-empty witnesses. This preserves OBLIG-PBT-3 v0.10.5 semantics for the non-`:subjects` path.
- **Additive emit at every surface.** Per-entry JSON gains an optional `joint_pbt_witness: true` field (omitted when false to keep emit minimal). Top-level JSON gains `joint_pbt_witnesses: [{hash, subjects: [...]}]` listing the deterministic-ordered groupings. Text mode adds a "Joint PBT witnesses" section between the existing suppressions and stale-downgrade blocks. `trust_report_version` stays `1.1.0` per the 2026-05-23 triage explicit constraint at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) row OBLIG-PBT-5a; the clean version-bumped fix is OBLIG-PBT-5b in the v0.12+ post-freeze lane.
- **Demotion target.** Joint-only `DLTested` demotes to `DLAsserted` (the existing diamond-meet sink), not into a new `tested-joint-only` slot — the latter requires a `trust_report_version` bump (OBLIG-PBT-5b). Documented at [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) v0.10.x patch-lane row.

### Schema — Trust-Report Output Schema Additive Update

- **`docs/llmll-trust-report.schema.json`** gains optional `joint_pbt_witnesses` top-level property (`JointPbtWitness` `$def` requires `subjects.length >= 2` and `hash` matches `^sha256:[0-9a-f]{64}$`) and an optional `joint_pbt_witness: const true` boolean on `TrustEntry`. `additionalProperties: false` on the top-level object now lists the new key explicitly; `TrustEntry`'s pre-existing `additionalProperties: true` admits the per-entry flag without further change. `trust_report_version` stays `1.1.0`.
- **`docs/llmll-ast.schema.json`** unchanged. No AST node shape change in this release; `expectedSchemaVersion` stays `0.5.0`.

### Test surface

- **656 Haskell tests + 37 Python tests** (up from 640 + 37 at v0.10.6). New: 10 tests under `TC-EOP-1 EOp arity and arg-type checking` covering arity errors (under/over), arg-type mismatches across `+` / `not` / `=` / `and`, polymorphic equality both positive and negative, the `EHole`-in-EOp bypass, and JSON-AST frontend parity; 6 tests under `OBLIG-PBT-5a joint PBT witness exclusion` covering the joint-only demotion (J1), the solo+joint mix predicate (J2), the source-annotated empty-witness non-demotion (J3), the singleton-head-position non-demotion (J4), the per-entry `joint_pbt_witness: true` emit gating (J5), and the no-`trust_report_version`-bump additive emit invariant (J6).
- **No solver-time delta.** TC-EOP-1 is a type-checker-only tightening; OBLIG-PBT-5a is a trust-report consumer-side classification refinement after VC emission has completed. Verification fragment unchanged (stays in QF-LIA).

### Empirical close-state

- **TC-EOP-1 closed.** Pre-fix `(+ "x" 1)`, `(not 1)`, `(= 1 "1")`, `(+ 1)` all silently typechecked; post-fix all four produce structured `type-mismatch` / arity diagnostics with `expected` / `got` fields. Both the S-expression and JSON-AST frontends route through the same `inferExpr (EOp ...)` path, regression-locked by case 9 of the test block.
- **OBLIG-PBT-5a closed.** A `:subjects [encrypt decrypt]` roundtrip property that previously credited 2 against `tpTested` now credits 0; the same property combined with a solo `:subject encrypt` property credits 1 (encrypt) instead of 2.

### What this does NOT close

- **INT-1 (`overflow_tainted` marking).** P1 inside-freeze item from the same triage record; not bundled in v0.10.7 to keep the patch tightly scoped to TC-EOP-1 + OBLIG-PBT-5a per the engineer hand-off prompt at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) §6. Deferred to v0.10.8 paired with INT-PRE measurement.
- **DRIFT-CI-1 (5-criterion version-gate CI).** Infra / doc-lead scope; not in the engineer turn. Tracked for the next doc-lead pass.
- **OBLIG-PBT-5b (clean fix with new `tested-joint` display level).** Requires `trust_report_version` major bump and a new `DisplayLevel` constructor; explicitly post-freeze per [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) v0.12+ lane.

---

## v0.10.6 — :subjects Metadata + PBT Body-Static-Eval Coverage + Residual Builtin Coverage (2026-05-14)

### Compiler — OBLIG-PBT-4 `:subject` / `:subjects` Metadata on `(check ...)`

- **`(check "d" :subject f (for-all …))` and `(check "d" :subjects [f₁ … fₖ] (for-all …))` accepted.** Optional keyword metadata between the description and the for-all opts a property into explicit-subject lift mode at the OBLIG-PBT-3 writeback site. Absent annotation = the v0.10.5 head-position singleton-fallback continues to apply; non-empty annotation = head-position scan is bypassed entirely and each declared subject with a postcondition receives its own `DLTested n` evidence record, all sharing one `pbt_witnesses` hash (per `docs/design/oblig-pbt-3-proposal.md` §11.1, pinned 2026-05-14). Empty `:subjects []` is rejected at parse time per S6. Duplicates are deduped.
- **`Property` record gains `propSubjects :: [Name]`.** Default `[]` preserves all existing constructions; both parsers (sexp `Parser.hs:pCheckBlock`, JSON `ParserJSON.hs:parseCheckDecl`) populate from the new keyword/field. `AstEmit.hs` emits `subjects` only when non-empty.
- **`pbtTrustWriteback`'s `processRun` branches on `propSubjects`.** When non-empty: fold over the subject list, emit one `csPost` `EvidenceRecord` per subject (with shared `PbtWitness`); subjects without a postcondition skip with an info diagnostic (S3); cross-module subjects key under their qualified path via the existing `qualMap` (S8). When empty: the v0.10.5 singleton-head-position path is unchanged.
- **Pacheco-Lahiri-Ernst overallocation mitigation: explicit annotation is the agent's consent to joint-evidence allocation.** The unannotated multi-callee diagnostic at `PBT.hs:pbtTrustWriteback` continues to refuse implicit lift; the new keyword opts in. Matches the JML `@testing`-per-method route over the conjoint-record alternative on schema-cost grounds (no `trust_report_version` bump, no `EvidenceRecord` reshape).

### Compiler — F-033 Body-Side Static-Eval Coverage Extension

- **`Contracts.hs:evalBuiltinApp` gains `unwrap` clauses.** `unwrap (Success v) → Just v`; `unwrap (Error _) → Nothing`; `unwrap _ → Nothing`. The `unwrap` builtin was already registered in `TypeCheck.hs:128` but had no static-evaluator clause — c02-shape property bodies dereferencing `(unwrap (balance …))` discarded universally on every pre-generated sample (`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 17 §"F-033 / Evidence"). The Error path returns `Nothing` because the static evaluator has no panic value; the property body then discards on Error samples, which is the soundness-preserving conservative.
- **`PBT.hs:runQC` threads an `IORef`-counted body-discard counter through the `forAll` property.** `resultsToQCRun` consumes the count alongside QuickCheck's `Result`; on `GaveUp { numTests = 0 }` with `bodyDiscards > 0`, the new `gaveUpDiag` returns `"property body did not reduce on any sample (… likely unmodeled builtin or unreduced callee body in property body)"` instead of the previous misleading `"too many precondition failures"`. The `samples_run > 0` `GaveUp` arm keeps the precondition-failure phrasing.

### Compiler — F-034 Residual `evalBuiltinApp` Coverage on c02/c03-shape

- **Five missing clauses added at `Contracts.hs:evalBuiltinApp`** for builtins already registered in `TypeCheck.hs:88-119` but absent from the static evaluator: `list-empty` (returns `(nil)`), `list-prepend` (cons cell with head prepended; distinct from `list-append` which appends at the tail), `list-filter` (delegates to a new `filterCons` helper mirroring `mapCons`' fuel discipline), `int-to-string` (canonical decimal via `T.pack ∘ show`), `string-concat-many` (delegates to a new `stringConcatMany` helper walking a cons-chain of `LitString` literals; returns `Nothing` on non-literal elements so the property body discards). Addendum-18 surfaced these clauses as the proximate c02/c03 unblocker — every transfer-body dispatch through `map_get` / `map_insert` / `create_ledger` / `find-account` short-circuited to `Nothing` and the property discarded universally on every QuickCheck sample.
- **`list-head` / `list-tail` return-shape correctness fix.** The pre-F-034 clauses at `Contracts.hs:434-435` returned the raw element / tail, but the type-checker signatures at `TypeCheck.hs:100-101` are `[list[a]] -> Result a string` / `[list[a]] -> Result (list[a]) string`. Any property body matching `(match (list-head xs) ((Success v) ...) ((Error _) ...))` against the typed surface failed to reduce. Post-F-034: `list-head [hd, …]` → `(Success hd)`, `list-head [nil]` → `(Error "list-head: empty list")`; symmetric for `list-tail`. The fix is back-compatible with `(unwrap-or (list-head xs) default)` patterns widespread in `examples/*` (e.g., `life_json/world.ast.json`, `tictactoe_json_verifier/tictactoe.ast.json`) — `unwrap-or` of a `Success`-tag returns the payload exactly as before; the only behavior change is that `(match (list-head xs) ((Success v) ...) ((Error _) ...))` now reduces instead of discarding.
- **`filterCons` returns `Nothing` if the predicate fails to reduce to a `Bool` literal** — conservative behavior matching `mapCons` / `foldCons`. `stringConcatMany` returns `Nothing` on any non-literal cons element or unresolved structure. Both helpers share `applyLambda`'s existing fuel decrement.

### JSON-AST Schema — Additive `CheckDecl.subjects` Field

- **`schemaVersion` bumped `0.4.0 → 0.5.0`** (`ParserJSON.hs:41` and `docs/llmll-ast.schema.json`). `CheckDecl` now has an optional `subjects: [string]` field with `minItems: 1` — `additionalProperties: false` is preserved. Existing fixtures (~30 `.ast.json`) bumped mechanically; no shape changes elsewhere.
- **`trust_report_version` stays `1.1.0`.** No change to `EvidenceRecord`, `tier_profile_pre`/`tier_profile_post`, `DLTested n`, or `pbt_witnesses` shape. The per-subject records under `:subjects [f g]` reuse the same record kind; the shared `pbt_witnesses` hash is detectable by inspection.

### Test surface

- **640 Haskell tests + 37 Python tests** (up from 614 + 37 at v0.10.5). New: F-033 `unwrap` static-eval coverage (3 tests), F-033 PBTSkipped diagnostic classification (1 test), F-034 residual builtin coverage `F-034 evalBuiltinApp residual builtin coverage` block (10 tests covering `list-empty`, `list-prepend`, `list-filter` true/false predicates, `int-to-string`, `string-concat-many`, `list-head`/`list-tail` Success-wrap and nil-Error arms, end-to-end `list-filter ∘ list-head` chain), OBLIG-PBT-4 `:subjects` edge cases S1/S2/S3/S4/S5/S7/S9 (7 tests), OBLIG-PBT-4 parser surface sexp + JSON (4 tests), OBLIG-PBT-4 S8 cross-module in `ModuleSpec.hs` (1 test).
- **No solver-time delta.** PBT does not feed liquid-fixpoint; verifier surface unchanged. F-034 is body-evaluator-only.

### Empirical close-state

- **c01-shape (OBLIG-PBT-4) closed empirically** under the Addendum-18 re-probe: c01-subjects (5/5 tries) emit per-subject `DLTested(100)` records with shared canonical-body hash; 4/5 tries lift `tier_profile_post.tested = 1` (the remaining 1/5 missed on orthogonal near-threshold QC variance, not an OBLIG-PBT-4 defect). The 3 contracted callees with `asserted` upstream dependencies remain correctly bounded by R6d's `effective_level` body-faithful meet.
- **c02/c03-shape (F-034) closed empirically** under the Addendum-19 re-probe (2026-05-15) on the v0.10.6-shipped binary: c02 **10/10** and c03 **10/10** property×try records achieve `samples_run ≥ 1` (Addendum-18 candidate-binary baseline: 0/10 + 0/10). PBTPassed rates c02 9/10, c03 7/10; residual PBTSkipped on both shapes is near-threshold QC precondition-failure discard, orthogonal to F-034. Run: `experiments/repair-loop/runs/20260515T072155Z-reprobe-pbt45-c01c02c03-v0.10.6-shipped/`. Addendum-19 additionally validates the OBLIG-PBT-4 `:subjects` path on c02-shape end-to-end (c02-subjects 3/5 tries `tier_profile_post.tested ≥ 1`).

### What this does NOT close

- **Coverage-instrumented `evaluatedSamples` (QC `classify`/`cover`)** named in the original OBLIG-PBT-4 row is sequenced to a later iteration. The current ship is the linkage rule + diagnostic — sufficient for the c01 / c02 / c03 representative shapes per the Addendum-18 close-state above.
- **R6d `effective_level` upgrade past `asserted`** for `transfer` / `balance` on c01-shape requires upstream `find-balance` / `update-balance` to reach `contract_checked` or `tested` independently — body-faithful behavior, not a F-034 / OBLIG-PBT-4 defect.

---

## v0.10.5 — PBT Complex-Type Generators + PBT-to-Trust-Report Write-Back (2026-05-13)

### Compiler — PBT Complex-Type Generators + Static Evaluator Extensions (OBLIG-PBT-2, F-032)

- **`llmll test` now executes `(check ...)` blocks whose `for-all` bindings include complex types.** Properties bound at `TPair`, `TList`, `TResult`, `TSumType`, or `TCustom` aliases run end-to-end instead of skipping with the previous "Property contains non-constant expressions — requires full runtime evaluation" message. The prior `PBT.hs:generateValue` catch-all returned `LitInt` for any non-primitive type, producing type-incorrect samples the static evaluator could not reduce. Closes F-032 (`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 16).
- **`generateValue` retyped** from `Type → IO Literal` to `TypeAliasEnv → Int → Type → IO Expr`. New cases for `TPair` (element-wise recurse, return `EPair`), `TList` (length-bounded cons-chain via `EApp "cons"/"nil"`), `TResult` (random tag + recurse), `TSumType` (random constructor choice + recurse, preferring nullary at depth-cap), `TCustom` (resolve via pure `expandAliasPure` against the `STypeDef`-extracted alias env, cycle-guarded). Recursion bounded by `maxGenDepth = 5` and `listMaxLen = 8`.
- **`evalExprStaticWith` extended for `EPair` and `ELambda`.** Pairs reduce element-wise; lambdas are first-class values for higher-order builtins. The extension also benefits contract VC constant-folding at `Contracts.hs:275, 286` — contracts that destructure pairs or fold lists now fold to constants before reaching liquid-fixpoint.
- **`evalBuiltinApp` signature refactored** from `Name → [Expr] → Maybe Expr` to `FuncEnv → Int → Name → [Expr] → Maybe Expr`. New §13 builtin reductions: `pair` / `first` / `second`; `cons` / `nil` / `list-head` / `list-tail` / `list-is-empty?` / `list-length` / `list-append`; `list-fold` / `list-map` (higher-order via new `applyLambda` helper, fuel-decremented); `unwrap-or` / `some` / `none` / `is-some`.
- **`maxFuel` raised 64 → 256.** Realistic agent emissions (`transfer → find-balance → list-fold → update-balance → list-fold` chains) exhausted the prior budget before reaching a terminal Bool. The 4× bump preserves the non-termination guard while giving real property bodies room to reduce.
- **`tryQuickCheck`'s `isSimpleType` whitelist removed.** The prior `TInt | TBool | TDependent _ TInt` gate excluded `TString` and every complex type. Replaced with universal fall-through routed through the broadened generator.
- **No syntax change, no schema bump.** Surface form of `(check ...)` and `(for-all [...] ...)` unchanged; `expectedSchemaVersion` stays `"0.4.0"`. The change is an evaluator-and-generator extension, not a language extension.
- **Empirical:** Phase-2 cell c01's solution lifts from `0/3 skipped` to `3/3 passed` under `llmll test`. Cells c02 and c03 still skip via QuickCheck-discard saturation (deeper unfold chains; orthogonal to type coverage).
- **Tests:** 10 new tests under two `OBLIG-PBT-2` describe blocks in `Spec.hs` covering (a) `TPair` / `TList` / `TResult` / `TSumType` / `TCustom`-alias PBT end-to-end, (b) recursive `STypeDef` depth-cap termination, (c) `evalExprStaticWith` `EPair` reduction, (d) `evalBuiltinApp` `first`/`second`, `list-fold` over a 3-element cons-chain, `list-length ∘ list-append`. 594 → 604 Haskell tests; 37 Python tests unchanged.

### Closed — F-033 PBT-to-Trust-Report Write-Back

- **Closed by OBLIG-PBT-3** (see below). `PBTPassed` results now lift the post clause of the singleton head-position contracted callee to `DLTested n` evidence; the `tier_profile.tested` slot of `--trust-report` reflects actually-passing `(check ...)` blocks through the new `tier_profile_post` per-clause aggregate (the per-function meet of pre and post is structurally unchanged).

### Compiler — PBT-to-Trust-Report Write-Back (OBLIG-PBT-3, F-033)

- **`llmll test` now writes `DLTested n` evidence to `.verified.json` on the post clause of the singleton head-position contracted callee inside every `PBTPassed` property body.** The linkage rule: a `(check ...)` block lifts at most one function — the unique `def-logic`/`letrec` reachable as an `EApp` operator inside `propBody` whose contract has a `post` clause. Multi-subject properties (≥2 contracted callees in head position) produce an informational diagnostic and no lift. `PBTFailed`, `PBTSkipped`, and `PBTError` runs contribute zero evidence. Closes F-033 (`postmortem-001-apparatus-validation.md` Addendum 16). Settled design + paired professor review at `docs/design/oblig-pbt-3-proposal.md` and `docs/design/oblig-pbt-3-review.md`.
- **New `pbt_witnesses` field on `.verified.json` evidence records** (`compiler/src/LLMLL/Syntax.hs:320-340`, `compiler/src/LLMLL/VerifiedCache.hs:70-110`). Each PBT-derived `DLTested` entry carries a list `[{hash, description}]` where `hash` is `sha256:` + 64 hex chars over a canonical s-expression serialization of the property body (`canonicalPropBodyHash` in `PBT.hs`; an exhaustive `Expr` walker independent of the incomplete `ObligationAssembly.exprToSExpr`). On read, `buildTrustReport` validates each evidence record's `pbt_witnesses` against the set of live property-body hashes and downgrades stale entries to `DLAsserted` with a per-clause diagnostic surfaced under `--trust-report`. Editing a property body invalidates its cached `DLTested`; deleting a property removes the lift. Back-compatible read of v0.10.4 sidecars (missing `pbt_witnesses` defaults to `[]`).
- **Within-channel `max` join across multiple properties on the same subject** (`mergePbtWriteback` in `PBT.hs`). When N passing `(check ...)` blocks cover the same `f`, `evaluatedSamples` aggregates as `max { samples(p) | p covers f }` and `pbt_witnesses` is the union deduplicated by `pwHash`. Distinct from `Module.mergeCS`'s cross-load lattice-monotonic merge, which is the GLB across sidecar-vs-base. Independence assumptions are not made — `sum` was considered and rejected.
- **Cross-module qualified sidecar keys.** A local `(check ...)` covering an imported function `f` from module `lib` writes the entry under qualified key `lib.f` in the local file's sidecar. The existing `collectAllContractStatus` build path at `TrustReport.hs:148-155` already merges by qualified name across the module cache, so the change is read-side compatible. The sidecar invariant statement is documented in `LLMLL.md §4.4.4`.
- **`trust_report_version` bumps `1.0.0 → 1.1.0`.** The JSON emit gains two new top-level fields parallel to `tier_profile`: `tier_profile_pre` and `tier_profile_post`. Each classifies functions by their per-clause effective level (clause own ER meeting the transitive-callee effective level); a function with `pre=DLAsserted` and `post=DLTested n` increments `tier_profile_pre.asserted` and `tier_profile_post.tested` rather than collapsing both into `tier_profile.asserted` via the diamond meet. The scalar `tier_profile` is unchanged in shape and continues to use the per-function meet — existing v1.0.0 consumers ignore the new fields. The schema at `docs/llmll-trust-report.schema.json` bumps to v1.1.0 additively. The source JSON-AST `expectedSchemaVersion` stays `"0.4.0"` — no source-schema delta; the parallel-track versioning between source `schemaVersion` and emit `trust_report_version` is the same separation established at v0.10.4.
- **`evaluatedSamples` semantics.** `DLTested n` records that `n` property-body evaluations reduced to `True`, with no evaluation reducing to `False`. This is a lower bound on assertions of the postcondition: under an implication-shape property `(if pre then post else true)`, samples for which `pre` fails count as `True` evaluations vacuously. Coverage-instrumented counts distinguishing genuine postcondition witnesses from vacuous evaluations are routed to **OBLIG-PBT-4** (new roadmap row). Disclosure in `LLMLL.md §5.1.1`.
- **PBT-Lift inference rule.** Formalised in the new `LLMLL.md §4.4.5` ("PBT-Derived Trust Evidence"), slotted between the existing §4.4.4 (Trust Report) and §4.5 (Suppression Governance). The rule's six side conditions (subject scoping, multi-subject suppression, skip/fail suppression, `PBTError` treated as skipped, interface laws excluded, `csPost`-only target) are stated alongside the within-channel `max` accumulation formula.
- **`:subject` keyword deferred to OBLIG-PBT-4.** The head-position-singleton fallback is the v0.10.5 mechanism; agents that wish to explicitly declare joint-evidence across multiple contracted callees in a single property will use `:subject f` (or `:subjects [f g]`) metadata in a future release. Existing canonical agent-emitted properties (`withdraw`, the F-032 closure cells, typical Phase-3 problem shapes) are already singleton and lift without annotation.
- **Design-divergence disclosure.** `LLMLL.md §4.4.1` documents the deliberate departure from Liquid Haskell (`Vazou et al., POPL 2014`) on admitting a statistical evidence channel into the trust-report partial order. The diamond-incomparability of `DLContractChecked` and `DLTested` at `Syntax.hs:355-357` (their meet is `DLAsserted`, not either) prevents agents from silently treating statistical evidence as logical.
- **Verification fragment unchanged.** No new SMT VCs, no new EMatch instantiations, no new Lean obligations. `aggregateTiers` is a pure traversal; `aggregateTiersPre` / `aggregateTiersPost` add two more passes. Sub-millisecond runtime delta on `llmll verify --trust-report`. Two file-I/O ops added to `llmll test` (`loadVerified` + `saveVerified`).
- **Tests:** 10 new tests under an `OBLIG-PBT-3 PBT-to-trust-report write-back` describe block in `Spec.hs` covering (E2) same function in multiple head positions lifts once, (E3) multi-subject diagnostic and no lift, (E5) per-clause split surfaces post-tested under asserted-pre meet, (E6) `DLVerified` preserved by `mergeCS` (non-degrading), (E8) cross-module subject keys writeback under qualified name, (E10) idempotent re-run dedups `pbt_witnesses` by hash, (E12) mixed pass/fail on same fn — passing run lifts and failing does not, (E13) edited property body downgrades stale `DLTested` to `DLAsserted`, (E14) deleted property downgrades stale `DLTested` to `DLAsserted`, (E15) v1.1.0 emit carries parallel `tier_profile_{pre,post}`. Pre-existing R6d JSON-emit test re-pinned at `trust_report_version: "1.1.0"`. 604 → 614 Haskell tests; 37 Python tests unchanged.

---

## v0.10.4 — R6d (Trust-Report Tier Profile + Harness Predicate) (2026-05-13)

### Compiler — Trust Report Tier-Count Aggregate (R6d)

- **`llmll verify --trust-report --json` now emits a `tier_profile` aggregate** alongside the existing `entries` / `summary` / `suppressions` blocks. The aggregate is a six-Int record `{verified, proved, contract_checked, tested, asserted, no_contract}` over per-function effective tier classifications (the same path that backs `summary` — `teEffectiveLevel`, falling back to the local meet of `tePre` / `tePost`). The repair-loop harness consumes this profile to compose its credibility predicate `Cred(R)` over LLMLL cells without ranking the diamond-incomparable `contract_checked ‖ tested` levels.
- **Diamond-meet semantics.** Per `LLMLL.md §4.4.1:344` and `Syntax.hs:356-357` (`evidenceMeet`), a function with `pre = contract-checked` and `post = tested` has effective level `asserted` (the diamond meet) and increments only `tpAsserted` — never both `tpContractChecked` and `tpTested`. Test `TP-3` in `Spec.hs` regression-locks this against future drift.
- **`proved` slot is structural-zero in v1.0.0.** No `DLProved` constructor exists in `DisplayLevel` today; the field is reserved for a future Lean-discharged tier so that a later compiler version can populate it without bumping the trust-report emit's major version. Documented in `docs/llmll-trust-report.schema.json`.
- **No spec change.** `LLMLL.md` gains no consumer-predicate prose; per R6d, `Cred` lives in `experiments/repair-loop/` harness docs, not in the language spec. The trust-report emit's pre-existing `summary` block is unchanged (consumers and the v0.3.2 substring tests at `Spec.hs:2253-2256` keep passing).
- **No verifier delta.** `aggregateTiers` is a pure traversal over the already-enriched entries; zero solver work, zero EMatch instantiations, zero new VC constraints, sub-microsecond runtime on a typical module.
- **Tests:** 5 new tests under a `v0.10.4 tier-count profile (R6d)` describe block in `Spec.hs` covering (a) empty → zero vector, (b) uniform-`verified`, (c) diamond-asymmetry (contract-checked / tested / mixed-meet → asserted), (d) mixed-tier, (e) JSON emit carries `trust_report_version` and structurally-valid `tier_profile`. 589 → 594 Haskell tests; 37 Python tests unchanged.

### Schema — Trust-Report Output Schema v1.0.0

- **New file `docs/llmll-trust-report.schema.json`** documents the trust-report JSON emit shape. Independent of the source JSON-AST schema (`docs/llmll-ast.schema.json`); the two surfaces are versioned separately because they describe different artifacts — parser input vs verifier emit. `$id`: `https://llmll.dev/schemas/v0.2/trust-report.schema.json`.
- **New `trust_report_version: "1.0.0"` field** on every `--trust-report --json` emit. Consumers can pin to this version to detect breaking shape changes; additive-only changes within a major version.
- **`tier_profile` shape**: six required integer fields (`verified`, `proved`, `contract_checked`, `tested`, `asserted`, `no_contract`), each with `minimum: 0` and `additionalProperties: false`. Schema explicitly documents the diamond-meet classification rule and the structural-zero `proved` slot.
- **Source JSON-AST `schemaVersion` is NOT bumped.** `expectedSchemaVersion` stays `"0.4.0"` (`ParserJSON.hs:41`). The change is to an emit-only output, semantically orthogonal to the source-input parser version; bumping the source schema would force ~22 `.ast.json` fixture rewrites for a change those fixtures do not touch. The R6d plan's `schemaVersion 0.4.0 → 0.5.0` line is honored by the new emit-side `trust_report_version` field instead — same versioning intent, smaller blast radius.
- **Round-trip semantics.** The trust-report JSON is emit-only; `ParserJSON.hs` and `AstEmit.hs` do not ingest or emit it. JSON-level re-decode (via `Aeson.Value`) preserves the field; full Haskell-side `TrustReport ↔ JSON` round-trip is N/A by design.

### Experiments — Repair-Loop Harness Cred(R) + H1 Bifurcation (R6d)

- **`experiments/repair-loop/README.md`** — new "Credibility predicate and the H1 split (R6d)" section. Defines `Cred(R) ≡ (|R| > 0) ∧ (n_asserted = 0) ∧ (n_no_contract = 0)` as the universal lattice-meet reading; defines the H1 bifurcation (H1-Correctness via testkit cross-target; H1-Assurance via per-target `tier_profile`, never scalarized cross-paradigm); states the no-scalarization discipline with citations to `LLMLL.md §4.4.1:344, :346-347` and `docs/design/language-comparison-experiments.md:27, :29-35`.
- **`experiments/repair-loop/scripts/run_repair_loop.py`** — `_count_bad_trust_tiers` drops `"asserted"` from `accepted_levels` (R6d universal tightening); docstrings cite §LT-A. `_run_turn` extracts `tier_profile` from the verify result and surfaces it at the per-turn `verifier.json` payload and the returned turn-record dict.
- **`experiments/repair-loop/scripts/evaluate_run.py`** — `_summarize_trust_report` extended with `tier_profile`, `cred`, `trust_report_version` fields (None on pre-R6d trust reports).
- **`experiments/repair-loop/manifest.phase2-calibration.json`** — `terminal_target.value` strings relabelled `"all-expected-contracts-verified-or-asserted"` → `"all-expected-contracts-above-asserted"`. Added `_r6d_note` field cross-referencing the README section.
- **Closes §LT-A / F-026 / F-027.** Re-probe of three Phase-2 cells (`runs/20260512T031938Z-matrix/`) under the v0.10.4-pre compiler: all three invert to `Cred=false`; `tier_profile` distinguishes c02 (6 asserted) from c03 (3 asserted + 3 no_contract). Full evidence: `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 15. No new agent runs, no API spend.

### Experiments — Repair-Loop Matrix Runner

- **New `experiments/repair-loop/scripts/run_matrix.py`** (`5895792`) — matrix runner layered on top of `run_repair_loop.py` that enumerates cells in `(target × experiment × agent × attempt)` order, generates per-cell synthetic manifests, invokes the single-cell orchestrator, runs `evaluate_run.py` after each cell, and aggregates `matrix_report.json` / `matrix_summary.md`. Cells contiguous-by-`(target, experiment, agent)` for adapter-specific debugging.
- **`--resume-from-cell N`** — 1-based cell indexing required under the ~6.75h wall-clock ceiling of a 9-cell Phase-2 run at k=5 × 540s/turn. Load-bearing for crash recovery.
- **Pre-flight prereq checks** — per-agent `required_env` and `required_executables` declared in the manifest, validated before any cell launches; failures accumulated and surfaced in one pass.
- **`terminal_target_per_target` dispatch** — matrices spanning mixed verification surfaces (Phase 2 uses `trust-tier` for `llmll` and `all-pass` for Python / Go) resolve the per-target terminal target from a manifest-level map, falling back to the manifest's default `terminal_target` when a target is not in the map. This is the dispatch the R6d harness patch's predicate change rides on top of.
- **Harness README** (`experiments/repair-loop/README.md`) — new "Run a Matrix" and "Matrix-runner extensions" sections documenting the script and its manifest extensions.

---

## v0.10.3 — Cross-Module PBT + Spec Pedagogy (2026-05-12)

### Compiler — PBT Cross-Module Visibility (MOD-PBT-1, F-018)

- **`llmll test` now resolves cross-module `def-logic` in `(check ...)` bodies.** `doTest` switches from `loadStatements` (single-module) to `loadStatementsMulti`; a new `assembleTestStatements` helper in `LLMLL.PBT` concatenates each `(open path)`-targeted imported module's `SDefLogic` declarations ahead of the local statement list before invoking `runPropertyTests`. The PBT static evaluator's `FuncEnv` (built unchanged by `buildFuncEnv`) now sees imported function bodies, so a `(check ...)` block calling an imported function evaluates instead of silently skipping. Closes F-018 / F-030 (repair-loop Phase-2 postmortem Addendum 8 / Addendum 11); LLMLL cells whose `(check ...)` blocks depend on standard-prelude or sibling-module `def-logic` can now elevate trust-report entries from `asserted` to `tested` tier.
  > **Erratum (post-OBLIG-PBT-2):** The closing claim that MOD-PBT-1 elevates trust-report entries from `asserted` to `tested` was aspirational and is empirically not true — the PBT-to-trust-report write-back is tracked separately as F-033 / OBLIG-PBT-3 and remains unimplemented. MOD-PBT-1 does correctly make imported `def-logic` resolvable in `(check)` bodies; the FuncEnv-visibility claim is intact.
- **Filtering:** imported declarations are filtered by `meExports` (respects `(export ...)`) and by the optional restricted-open name list (`(open path (n1 n2))`). Imports come first, local stmts last — `Map.fromList` right-bias gives local-shadows-import semantics matching the type-checker's `(open ...)` resolution.
- **Scope boundaries (intentional):** Only `SDefLogic` is forwarded — imported `SCheck` blocks and `SDefInterface` laws stay with their owning module (`llmll test foo.llmll` should not silently run imports' own tests). Qualified-name resolution (`solution.plus-one`) remains out of scope per `LLMLL.md §8.5`; under the current flat-codegen runtime, qualified names do not resolve, and PBT honoring them would over-promise relative to the rest of the runtime. The existing `SLetrec` exclusion in `buildFuncEnv` (`Contracts.hs:306`) propagates to imports — recursive imported `def-logic` remains invisible to the static evaluator; tracked separately under PBT fuel-bound recursion handling.
- **Surface preserved:** `runPropertyTests :: [Statement] -> IO PBTResult` signature unchanged; the existing in-process Spec.hs tests calling it directly are untouched. JSON-AST schema unchanged (no shape changes). No solver-time delta (PBT does not feed liquid-fixpoint). `llmll test small.llmll` with no imports is identical to pre-patch behavior.
- **Tests:** 5 new tests in `ModuleSpec.hs` M-08 block — `M-08.1` full open, `M-08.2` restricted-open filter, `M-08.3` `meExports` filter (covers Risk #3 from approved plan), `M-08.4` local-shadows-import via `Map.fromList` right-bias, `M-08.5` fixture-driven end-to-end via `loadModule` against `test/fixtures/pbt-cross-module/{imported,local}.llmll`. 584 → 589 Haskell tests. 37 Python tests unchanged.

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
