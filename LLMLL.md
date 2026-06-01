# LLMLL: Large Language Model Logical Language (v0.10.8)

**`llmll`** is a programming language designed specifically for AI-to-AI implementation under human direction. It prioritizes contract clarity, token efficiency, and ambiguity resolution over human readability.

> **Current version: v0.10.8 (shipped).** Patch release — INT-1 `overflow_tainted` marking on body-faithful verified evidence + `--strict-verified-core` refusal extension. The verifier still proves what it proved pre-INT-1; the change is metadata layered atop the existing `DLVerified` + `erBodyFaithful = True` ground truth. `.verified.json` sidecars and trust-report JSON gain an additive `overflow_tainted` field (only-when-true); pre-v0.10.8 verified body-faithful sidecars are invalidated on read to eliminate silent under-strictness. No new language surface, no new builtins, no new SMT theory, no solver-time delta. This release also unblocks the DRIFT-1 §3 type-system catch-up (one cross-reference from §3.1 to the new §5.3.5 `overflow_tainted` callout). 672 Haskell + 37 Python tests passing. JSON-AST schemaVersion `0.5.0`. `trust_report_version` `1.1.0`. See [`CHANGELOG.md`](CHANGELOG.md) for full release notes and [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) for the implementation schedule. Next milestone is v0.11 (core/shell grammar inversion + CDP evidence axis + predicate-carrying `?proof-required` + `int → Integer` codegen, which makes the v0.10.8 taint trigger set dormant on `int`); see [`docs/design/core-shell-inversion-direction.md`](docs/design/core-shell-inversion-direction.md), [`docs/design/int-2-boundary-shims.md`](docs/design/int-2-boundary-shims.md), and [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md). v0.11 features LT-INT (`int → Integer` codegen, see §3.1) and LT-CDP (contract discriminative power evidence axis, see §4.4.6) have shipped on branch (commits `9c37a5c4`, `121815a` respectively); LT-INV (core/shell grammar inversion): `--grammar=core-inversion` opt-in flag shipped; **grammar default is now `GrammarCoreInversion` (CE-3, EL-5 gate confirmed 2026-05-30)**; schema bumped to `0.6.0`; LT-PPR (predicate-carrying `?proof-required`) shipped on branch (commit `3391713`).

<details><summary><strong>Release history</strong></summary>

| Version | Headline |
|---------|----------|
| **v0.10.8** | INT-1 Overflow-Taint Marking + Strict-Core Refusal: `erOverflowTainted :: Bool` added to `EvidenceRecord`; `bodyHasOverflowArith` at `FixpointEmit.hs:597-642` syntactically walks the body for `EOp` / `EApp` arithmetic over non-`Int64`-folding operands; activated post-body-faithful at `:506-516`. `--strict-verified-core` at `Main.hs:1119-1158` refuses `erBodyFallback ∪ erOverflowTaintedFns` with distinct diagnostics naming the `?proof-required` + Leanstral / INT-2 escape paths. Additive `overflow_tainted: true` (only-when-true) in `.verified.json` + trust-report JSON top-level `overflow_tainted_fns` + per-entry flag + obligation-report `TrustChannel`; pre-v0.10.8 verified body-faithful sidecars are invalidated on read. `trust_report_version` stays `1.1.0`; JSON-AST `schemaVersion` stays `0.5.0`. Closes DRIFT-1 §3 residual via §3.1 cross-reference to §5.3.5 callout. 672 tests (+16 from v0.10.7). |
| **v0.10.7** | TC-EOP-1 EOp Arity/Type-Check + OBLIG-PBT-5a Joint PBT Witness Exclusion: `inferExpr (EOp op args)` at `TypeCheck.hs:981` rewritten to mirror `EApp`'s arity-check + `structuralUnify` loop; arity-bad and type-incorrect operator calls now produce structured `type-mismatch` and arity diagnostics; polymorphic `=` / `!=` unify both operands against one bound `TVar` (no `any × any → bool` degrade). `TrustReport.hs` computes joint-witness hashes (post-clause hashes appearing on ≥2 distinct subjects) and demotes pure-joint `DLTested` entries to `DLAsserted`; per-entry `joint_pbt_witness: true` + top-level `joint_pbt_witnesses` JSON additions. `trust_report_version` stays `1.1.0`; JSON-AST `schemaVersion` stays `0.5.0`. 656 tests (+16 from v0.10.6). |
| **v0.10.6** | `:subjects` Metadata + PBT Body-Static-Eval Coverage + Residual Builtin Coverage: OBLIG-PBT-4 explicit-attribution `:subject`/`:subjects` metadata on `(check ...)` blocks bypasses head-position scan and lifts per declared subject (shared `pbt_witnesses` hash). F-033 `unwrap` static-eval coverage. F-034 five residual `evalBuiltinApp` clauses (`list-empty`, `list-prepend`, `list-filter`, `int-to-string`, `string-concat-many`) plus `list-head`/`list-tail` Success-wrapped return-shape correctness fix. JSON-AST schemaVersion `0.4.0 → 0.5.0` (additive `CheckDecl.subjects`). 640 tests (+26 from v0.10.5). |
| **v0.10.5** | PBT Complex-Type Generators + PBT-to-Trust-Report Write-Back: OBLIG-PBT-2 `generateValue` retyped for `TPair`/`TList`/`TResult`/`TSumType`/`TCustom` with depth-cap; `evalExprStaticWith` extended for `EPair`/`ELambda`; `evalBuiltinApp` refactored with `FuncEnv`+fuel and new builtins. OBLIG-PBT-3 `llmll test` writes `DLTested n` to `.verified.json` on PBT-pass post clauses (singleton head-position linkage rule); `pbt_witnesses` SHA-256 body-hash provenance with read-side staleness invalidation; cross-module qualified sidecar keys. `trust_report_version 1.0.0 → 1.1.0` (additive `tier_profile_pre`/`tier_profile_post`). 614 tests (+20). |
| **v0.10.4** | R6d (Trust-Report Tier Profile + Harness Predicate): `llmll verify --trust-report --json` emits six-Int `tier_profile` aggregate `{verified, proved, contract_checked, tested, asserted, no_contract}` over per-function effective tier classifications (diamond meet preserved). New `docs/llmll-trust-report.schema.json` v1.0.0 with `trust_report_version` field, independent of source JSON-AST schema. Repair-loop harness `Cred(R)` predicate consumes the profile without scalarizing the `contract_checked ‖ tested` incomparability. 594 tests (+5). |
| **v0.10.3** | Cross-Module PBT + Spec Pedagogy: MOD-PBT-1 `llmll test` resolves cross-module `def-logic` in `(check ...)` bodies via `assembleTestStatements` (filtered by `meExports` ∩ restricted-open names; imports first, locals last with shadowing). `LLMLL.md §2.5` naming conventions section added. `LLMLL.md §3.3`/§9/§13.5 match-arm form corrections to canonical wrapped form. `LLMLL.md §3.2`/§3.3 unit-payload vs nullary-constructor pedagogy resolution. Roadmap governing-criterion disambiguation. 589 tests (+5). |
| **v0.10.2** | Soundness Blockers + Diagnostic Surface: `?delegate` fallback typechecking (was silently passed); `?delegate-async on_failure` parse-rejected; `emitHole HDelegate` codegen routes through fallback; `EHole` unification fixed in `checkExpr`. PBT `runQC` returns `QC.discard` on unevaluable samples (was defaulting to `True`); FuncEnv-driven evaluation; fuel-bounded `evalExprStaticWith` recursion. `llmll check` text-mode warning surface; dotted-fn warning. JSON-AST schemaVersion `0.3.0 → 0.4.0` (identifier-shape regexes). `LLMLL.md §11.2` delegate fallback inference rule. `LLMLL.md §13.8` three-layer Result rule + `?proof-required` pedagogical hook. 584 tests (+14). |
| **v0.10.1** | Patch Release: Structural + transitive `expandAlias` with cycle guard (14 new tests). Async delegate normalization (`return_type` is inner `T`). `DelegationError` type normalization at parse time. `llmll version` command. Exit code fixes (`check`/`holes` rc=1, `--help` rc=0). ADT constructor auto-registration. macOS build warning suppression. 570 tests (+14). |
| **v0.10.0** | Obligation-Guided Agent Coding: Structured obligation reports (JSON, schema `0.10.0`) for holes, unproven contracts, and call-site failures. Three channels: type, contract, trust. `EMatch` branch obligations. Repair suggestions (`generateCandidates`). Function lists with type-compatible matching. `ObligationAssembly.hs` + `GuardClassifier.hs`. Benchmark suite (B1/B3/B5). 556 tests (+104). |
| **v0.9.0** | Compositional Verification: Assume-guarantee reasoning for function call chains (`CallVC`, `ContractEnv`). `EApp` to contracted functions is body-faithful. `EMatch` on `Result` (two-path encoding). SCC recursive fallback. Call-pre obligation emission (PROVE polarity). `--strict-verified-core` mode. Trust report loads `.verified.json` sidecar. 452 tests (+130). |
| **v0.8.1b** | Evidence Model Refactor: `VerificationLevel` total order replaced with `DisplayLevel` partial-order diamond lattice (`DLVerified > DLContractChecked ∥ DLTested > DLAsserted`). `EvidenceRecord` (level + body-faithful + source provenance). `AssumptionKind` taxonomy. `ContractStatus` restructured. `evidenceMeet` (GLB) and `evidenceCovers` (partial-order). 14 source files + test suite updated. Hard break: no backward compat for old `.verified.json`. 322 tests (+2). |
| **v0.8.1a** | Documentation Boundary Clarity: §3.4 renamed "Refinement Type Aliases." Per-construct verification matrix (§5.3.5). QF-LIA boundary and integer overflow model gap documented. One-pager and README updated. No code changes. |
| **v0.8.0** | Faithfulness Core: Body-faithful verification conditions (BODY-VC). EOp delegation + `!=` in `exprToPred`. Clause-level emission tracking (`erEmittedPre`/`erEmittedPost`). EIf-in-let hoisting. SUPP-DEBT (`spec_coverage` + `suppression_debt`). Post-only stripping when body-faithful. 320 tests (+26). |
| **v0.7** | Hardening: `string-char-at` negative index guard (BUILTIN-2), `regex-match` upgraded to POSIX ERE via `regex-tdfa` (BUILTIN-1), do-block discarded command warning (DO-1), `DLVerified` constructor replaces `Ord` instance on `VerificationLevel` (TRUST-2a). 294 tests (+5 trust-tier). |
| **v0.6.3** | Trust Model Fixes: 7 critical bugs resolved. `result` removed from pre scope (BUG-1), strict typecheck gate (BUG-4), contract instrumentation in build pipeline (BUG-2), transitive trust closure (BUG-3), body-faithful stripping guard (BUG-6), proof laundering protection (BUG-7), termination docs corrected (BUG-5). `tcStrictMode` + `llmll check --strict`. 289 tests (unchanged count; 2 expectations updated). |
| **v0.6.2** | Algebraic Interface Laws: `def-interface :laws` with `(for-all ...)` property syntax, QuickCheck `prop_` codegen, spec coverage integration, PBT wiring. VSM-1 backfill complete. 289 total tests $+$ 10 new. |
| **v0.6.1** | TOTP Benchmark & Hub Query: `hmac-sha1`/`sha1` crypto builtins (§13.11). Frozen TOTP RFC 6238 benchmark (14 CI assertions). `llmll hub query --signature` for type-driven package search. Provenance display in `--trust-report`. 279 total tests $+$ 0 Haskell $+$ 0 Python. |
| **v0.6.0** | Specification Quality: `--spec-coverage` gate classifies functions as contracted/suppressed/unspecified and computes effective coverage. `(weakness-ok fn "reason")` suppression governance. `:source` clause-level provenance on `pre`/`post` contracts. Frozen ERC-20 benchmark with verification-scope matrix. 279 total tests $+$ 15 new. |
| **v0.5.0** | U-Full Soundness: occurs check prevents infinite types. Let-generalization for top-level `def-logic`/`letrec` via TVar-TVar wildcard closure and bound-TVar consistency fix. Closes the last known unsoundness in the type checker. 264 total tests $+$ 7 new U-Full. |
| **v0.4.0** | Lead Agent (`llmll-orchestra --mode plan\|lead\|auto`). U-Lite: substitution-based unification for concrete types (`list-head 42` is a type error; `first`/`second` typed `TPair a b → a`/`b`). CAP-1: capability imports enforced at compile time (non-transitive, module-local). Invariant pattern registry via `--sketch`. Downstream obligation mining. Aeson FFI codegen. |
| **v0.3.5** | Context-aware `llmll checkout` returns local typing context (Γ, τ, Σ). `llmll verify --weakness-check` detects trivial-body spec weaknesses. Orchestrator E2E with diagnostic-driven retry, lock expiry handling, and context-aware prompts. |
| **v0.3.4** | `llmll spec` emits agent prompt specification from `builtinEnv` (36 builtins + 14 operators). 7 faithfulness property tests. Orchestrator integration with backward-compat fallback. Phase A prompt enrichment. New builtins: `string-empty?`, `regex-match`. `is-valid?` removed. |
| **v0.3.3** | Agent orchestration compiler support — `llmll holes --json --deps` with Tarjan's SCC cycle detection; `--deps-out FILE`. |
| **v0.3.2** | Trust hardening — `llmll verify --trust-report` with epistemic drift detection; cross-module trust propagation. GHC WASM PoC (conditional GO — feasibility confirmed). |
| **v0.3.1** | JSONL event log with deterministic replay (`llmll replay`). Leanstral MCP proof integration (mock-first, `--leanstral-mock`). SHA-256 proof cache (`.proof-cache.json`). |
| **v0.3** | `do`-notation (PRs 1–4). Stratified verification, `--contracts` flag, `.verified.json` sidecar. `string-concat` variadic sugar. `?scaffold` CLI. `Promise[t]` → `Async t`. |
| **Phase 2c** | Pair-type in typed parameters. `llmll typecheck --sketch` partial-program type inference. `llmll serve` HTTP sketch endpoint. |
| **Phase 2b** | Compile-time contract verification via liquid-fixpoint (`llmll verify`). `letrec` with `:decreases` termination. `match` exhaustiveness. `?proof-required` holes. |
| **Phase 2a** | Multi-file module system: `import`, `open`, `export`, `llmll-hub` registry. Cross-module `def-interface` enforcement. |
| **v0.1.2** | JSON-AST as first-class source format. Haskell codegen target. Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` sandbox. |
| **v0.1.1** | `Command` type, custom ADT sum types, `range`, `QualIdent`, Unicode aliases, `result` keyword, sequential `let`, standard command library, `def-invariant` syntax. |

</details>

> **For AI code generators:** Every section contains at least one complete, compilable example. When generating LLMLL code, you must use only the constructs defined in this document. If a required construct is missing, emit a named `?hole` and document the gap — do not invent syntax.

---

## 0.1 Semantic Foundation

LLMLL's operational semantics are defined by the generated Haskell program. The compiler is the reference implementation: if the generated Haskell compiles and runs, that is the correct behavior. There is no separate formal semantics document. Verification conditions emitted by `llmll verify` are sound with respect to this generated-program semantics under mathematical-integer (unbounded) semantics — a verified contract holds for all well-typed inputs of the generated Haskell code, modulo the `Int64` overflow gap documented in §5.3.5. Compositional reasoning (v0.9.0): when function `f` calls contracted function `g`, the verifier proves that `f` satisfies `g`'s precondition (obligation) and assumes `g`'s postcondition (hypothesis). This assume-guarantee composition is sound when both functions are independently verified. Functions in recursive call cycles are excluded from compositional encoding and verified contract-only.

---

## 1. Core Philosophy

1. **Strict Immutability:** There are no variables, only constants. State is transformed, never mutated. Re-binding the same name in the same scope is a compile error. Shadowing in nested scopes (e.g., a `let` binding that reuses a parameter name) is permitted but discouraged — the verifier alpha-renames shadowed bindings internally.
2. **Hole-Driven Development:** Ambiguity is a first-class citizen represented by Holes (`?`). A program with holes can be analyzed and type-checked but not executed until the holes are filled. Always prefer a typed hole over a hallucinated implementation.
3. **Typed Logic:** Every expression has a type. The type system prevents null pointer dereferences, type mismatches, and unguarded IO.
4a. **Design by Contract with Stratified Verification:** Logic functions declare `pre` and `post` conditions as formal specifications. These contracts are the trust interface between agents. Verification is stratified: contracts in the decidable arithmetic fragment (QF-LIA) are verified at compile time via liquid-fixpoint / Z3; contracts outside that fragment are enforced as runtime assertions and flagged with `?proof-required`. An interactive proof path (Lean 4 via Leanstral) is designed but not yet shipped (see §5.3.3). Each contract clause carries a *display level* — `verified`, `contract-checked`, `tested`, or `asserted` — so a caller can inspect trust without reading the implementation.
4b. **Transitive Trust Propagation:** Trust levels propagate through call chains: no `verified` conclusion rests silently on an `asserted` assumption. A function's effective display level is the lattice meet of its own level and all transitively reachable callees' levels.
5. **Compositional Verification:** Verification extends beyond isolated functions. When a function calls a contracted callee, the verifier proves the caller satisfies the callee's precondition and assumes the callee's postcondition holds (assume-guarantee reasoning). This enables body-faithful verification across multi-function call chains without inlining. Recursive cycles are detected and fall back to contract-only verification.
6. **Capability-Based Security:** Programs have zero access to the system unless explicitly granted via a `capability` import, enforced at compile time. Every side effect is modeled as a `Command` value returned from pure logic — never performed directly. See §7 for the sandbox implementation.

---

## 2. Syntax (S-Expressions)

`llmll` uses Lisp-style S-expressions to represent the Abstract Syntax Tree (AST) directly. This is token-efficient and eliminates parsing ambiguity.

### 2.1 Basic Tokens

- **Keywords:** `module`, `import`, `def-logic`, `def-interface`, `type`, `let`, `if`, `match`, `check`, `pre`, `post`, `for-all`, `gen`, `pair`, `fn`, `where`, `await`, `do`.
- **Reserved identifiers:** `result` (see §4.2), `unit`, `true`, `false`.
- **Primitive types:** `int`, `float`, `string`, `bool`, `unit`.
- **Holes:** Always start with `?` (e.g., `?logic_name`, `?choose(option1, option2)`).
- **Comments:** `;; text` — from `;;` to end of line. Ignored by the compiler.
- **Source encoding:** Source files are **UTF-8**. **Identifiers must be ASCII** (letters, digits, `-`, `_`, and `?` in terminal position only — e.g., `done?`, `string-empty?`, `is-game-over?`). A leading `?` denotes a hole (§6) and is lexed separately. A curated set of Unicode mathematical symbols are accepted as **aliases** for specific keywords and operators — see §2.4. All other non-ASCII characters are a lexer error.
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

### 2.5 Naming Conventions

LLMLL's identifier character class (§2.1) permits both `-` and `_`. The shipping language uses **kebab-case** as its canonical form. Agents emitting LLMLL should follow these conventions to remain idiomatic:

| Construct | Convention | Example |
|---|---|---|
| Function / variable / parameter names | **kebab-case** | `safe-subtract`, `account-id`, `from-balance` |
| Type names | **PascalCase** | `Ledger`, `Balance`, `PositiveInt` |
| Constructor / variant names | **PascalCase** | `Success`, `Error`, `Ok` |
| Boolean predicates | **kebab-case + trailing `?`** | `empty?`, `string-empty?`, `is-game-over?` |
| Built-in keywords and builtins | **kebab-case** (no underscore) | `def-logic`, `for-all`, `map-get`, `list-empty` |
| Reserved identifiers | **lowercase** | `result`, `unit`, `true`, `false` |

**Cross-language API spec translation.** When a language-neutral problem statement uses snake_case (`create_ledger`, `total_balance`) or camelCase (`createLedger`), the LLMLL solution must transliterate to kebab-case: `create-ledger`, `total-balance`. The grammar **accepts** snake_case and camelCase identifiers, but the canonical examples and built-in surface use only kebab-case; emitting non-kebab identifiers produces parseable but non-idiomatic LLMLL.

**Note on `_` vs `-` in the grammar.** Both characters are accepted in the identifier character class per §2.1. The choice is stylistic, not syntactic. The convention exists for consistency with shipping examples and built-ins, not because the grammar forbids alternative forms.

---

## 3. The Type System

### 3.1 Primitive Types

| Type | Description | Example values |
|------|-------------|---------------|
| `int` | Mathematical integer (unbounded; lowers to Haskell `Integer` at codegen — v0.11 LT-INT) | `0`, `-1`, `9999` |
| `float` | 64-bit IEEE 754 double | `3.14`, `-0.5` |
| `string` | Immutable UTF-8 byte sequence | `"hello"`, `""` |
| `bool` | Boolean | `true`, `false` |
| `unit` | No-value type (result of pure IO commands) | `()` |

> [!NOTE]
> **`int` arithmetic and the verifier (v0.11, LT-INT).** The verifier reasons over Z3 mathematical integers (unbounded), and as of v0.11 `int` lowers to Haskell `Integer` (also unbounded) at codegen — both sides of the verifier/runtime boundary are now mathematical integers, and the `Int64` overflow gap documented through v0.10.8 is **closed on `int`**. The INT-1 `overflow_tainted` machinery introduced in v0.10.8 — `erOverflowTainted` field on `EvidenceRecord`, `overflow_tainted` JSON projection, `--strict-verified-core` refusal — is preserved across the trust-report / sidecar / obligation surface; the trigger set is empty on `int` values (the body-VC emitter no longer calls the walker for `int` arithmetic). INT-3 (`machine-int` opt-in under QF-BV, post-freeze) re-arms the trigger with type-awareness. See §5.3.5 for the verification-matrix row, the historical gap callout, and the v0.11 closure note. The `int` row above describes the unbounded codegen lowering; the verifier-side semantics are at §0.1 (semantic foundation) and §5.3.5 (verification matrix + closure note).

### 3.2 Compound Types

| Type | Description | Example |
|------|-------------|---------|
| `bytes[n]` | Fixed-length byte array of exactly `n` bytes | `bytes[64]` |
| `list[t]` | Homogeneous ordered list | `list[int]`, `list[string]` |
| `map[k,v]` | Key-value dictionary | `map[string,int]` |
| `Result[t,e]` | Success (`t`) or Error (`e`) | `Result[int,string]` |
| `Promise[t]` | Pending async value | `Promise[ImageBytes]` |
| `(a, b)` | 2-tuple (product type) | `(int, string)` |
| `Command` | An IO effect (see §9) | _(constructed via capability constructors only)_ |

> `Command` is opaque — only produced by the standard command constructors (§13.9). Currently emitted as Haskell `IO ()`. Capability enforcement (§7) requires a matching `(import wasi.* (capability ...))` for any `wasi.*` call.


### 3.3 Algebraic Sum Types (Custom Variants)

User-defined tagged unions (also called ADTs or discriminated unions) are declared with the `type` keyword using `(| ConstructorName PayloadType)` arms:

```lisp
;; A sum type with two constructors
(type GameInput
  (| Start  Word)    ;; carries a Word value
  (| Guess  Letter)) ;; carries a Letter value

;; A sum type with nullary constructors (no payload)
(type Color
  (| Red)
  (| Green)
  (| Blue))

;; A sum type with multiple fields (use pair encoding)
(type Shape
  (| Circle  float)           ;; radius
  (| Rect    (float, float))) ;; width, height
```

**Construction:** A nullary constructor (`(| Variant)`) is written as a bareword identifier. A payload-bearing constructor is written as a function call with the payload:

```lisp
(let [[c Red]]                  ;; c : Color (nullary, bareword)
  ...)

(let [[ev (Start "hangman")]]   ;; ev : GameInput (payload-bearing, call form)
  ...)
```

For unit-payload constructors (discouraged for new code; see "Idiomatic guidance" below), the unit literal `()` is the payload — not the bareword `unit`, which parses only as a type:

```lisp
(let [[s (Idle ())]]            ;; s : Status, where Status is declared (| Idle unit)
  ...)
```

**Destruction:** Use `match` (see §3.4). Every `match` on a sum type must be exhaustive.

**Pattern arity.** Each constructor pattern's sub-pattern count must equal the declared arity of the constructor at its declaration site. A constructor declared `(| Red)` has arity 0 and matches with zero sub-patterns. A constructor declared `(| Red unit)` has arity 1 and matches with one sub-pattern (conventionally `_`). A constructor declared `(| Circle float)` has arity 1 and matches with one sub-pattern bound to the payload. Mismatch produces a typechecker warning.

```lisp
(match light
  ((Red)    "stop")
  ((Green)  "go")
  ((Blue)   "wait"))

(match event
  ((Start word)      ...)           ;; payload bound to `word`
  ((Guess letter)    ...))
```

**Idiomatic guidance.** For Boolean-style enums where no constructor carries a payload, declare each variant in the **nullary form** `(| Variant)`. The unit-payload form `(| Variant unit)` is accepted by the parser and produces a distinct AST shape — the generated Haskell encodes it as `Variant ()`, not `Variant` (per `compiler/src/LLMLL/CodegenHs.hs:413-419`) — but is **discouraged** for new declarations. The unit-payload form is preserved for backward compatibility and for the narrow case of Haskell-codegen interop where a downstream consumer destructures the `Variant ()` shape directly.

**Note on `unit`.** The type `unit` is a singleton, with sole inhabitant `()`. A wildcard match `((Variant _) body)` against a unit-payload variant is information-free at the value level, but the AST and the generated Haskell preserve the unit-payload slot regardless. The arity-1 requirement is what keeps the surface consistent with the AST and the codegen target.



### 3.4 Refinement Type Aliases (Logic-Constrained)

Any base type can be constrained by a predicate using `(where [binding: base] predicate)`. These are **refinement-like annotations** — the predicates are checked by the verification layer (`llmll verify`) within the QF-LIA fragment, or enforced as runtime assertions depending on trust level. They are not dependent types in the Idris/Lean sense: LLMLL has no dependent elimination, proof terms, or sigma types.

```lisp
(type PositiveInt  (where [x: int]    (> x 0)))
(type Word         (where [s: string] (> (string-length s) 0)))
(type Letter       (where [s: string] (= (string-length s) 1)))
(type GuessCount   (where [n: int]    (>= n 0)))
(type BlockID      (where [s: string] (regex-match "^[a-f0-9]{64}$" s)))
```

Refinement type alias constraints are **checked at compile time**: the constraint expression is type-checked with the binding variable in scope. The type checker expands type aliases structurally at call sites — passing a `string` literal where a `Word` (defined as `where [s: string] ...`) is expected works correctly. Compile-time SMT verification of constraint *values* is performed by `llmll verify`. See §5.3.5 for a precise matrix of which constructs are verified at each level.

> [!NOTE]
> **Obligation-guided agent coding (v0.10, shipped).** LLMLL v0.10.0 provides the Idris workflow *feel* — goal-directed construction from rich obligations — through structured obligation reports that expose type, contract, and trust obligations to agents. `llmll verify --obligation-report` emits a JSON report with three channels per obligation, repair suggestions, and function lists. See [compiler-team-roadmap.md](docs/compiler-team-roadmap.md) § v0.10.

#### 3.4.1 Checking-mode inference rule (REF-META-1)

For a refinement-aliased type `A ≜ (where [x: τ] p)` (where `A` is the alias name, `τ` the underlying base type, and `p` the refinement predicate), the **checking-mode rule** is:

```
Γ ⊢ e : τ ⇝ O
Γ ⊢ p[e/x] obligation
─────────────────────────
Γ ⊢ e ⇐ A ⇝ O ∪ { p[e/x] }
```

**Introduction.** When checking `e` against `A`, the type checker confirms `e` synthesizes the underlying base type `τ` (structural compatibility via `expandAlias` at [`TypeCheck.hs:1443`](compiler/src/LLMLL/TypeCheck.hs#L1443) and `unify` at [`TypeCheck.hs:969-1003`](compiler/src/LLMLL/TypeCheck.hs#L969)), and the refinement predicate `p[e/x]` joins the obligation set.

**Elimination** is the dual: when `Γ` binds `x : A`, uses of `x` add `p` as a hypothesis to the typing context for downstream obligations within `x`'s scope:

```
Γ, x : A ⊢ e' : τ' ⇝ O'
─────────────────────────────────────
Γ, x : τ, p ⊢ e' : τ' ⇝ O'   (elim)
```

Introduction emits an obligation; elimination introduces a hypothesis. The pair makes refinement aliases *checked invariants* without exposing a user-visible subtyping relation.

**Two-phase implementation.** [`TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs) handles structural compatibility via `inferExpr` / `checkExpr` / `unify`; [`Contracts.hs`](compiler/src/LLMLL/Contracts.hs) and [`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs) emit the refinement-predicate obligation at introduction sites and add the hypothesis at elimination sites. The unified spec-level judgment is the conjunction of both phases; no single-pass refactor is implied.

**Hypothesis lexical scoping.** The refinement hypothesis introduced at a binding site is *lexically scoped* — available within the binding's body but not propagated outside or across function boundaries. LLMLL has no flow-sensitive refinement reasoning; a variable's refinement hypothesis is determined by its declared type at the binding site (consequence of non-goal §3.4.2 #1).

#### 3.4.2 Non-goals (exhaustive for v0.11)

The following features are **deliberately absent** from LLMLL's refinement surface for v0.11. The list is closed; any addition requires explicit team consensus with a written soundness argument per [`docs/compiler-team-roadmap.md:33-36`](docs/compiler-team-roadmap.md).

1. **No general refinement subtyping (`<:`).** LLMLL has no user-visible subtyping relation between refinement-aliased types. Refinement aliases interact only via the checking-mode rule (§3.4.1), which generates obligations at concrete introduction sites. This is operationally equivalent to Liquid Haskell's subtyping formulation at introduction sites (both produce the same obligation `p[e/x]`) — see Vazou et al. *Refinement Types for Haskell*, POPL 2014 — but the narrower surface pre-empts the closure of abstract, parametric, and bounded refinements that the broader subtyping framing invites.

2. **No dependent pattern matching.** Pattern matching on a refinement-aliased value binds the underlying base type. A `match` arm on a `Letter` value (where `Letter ≜ (where [s: string] (= (string-length s) 1))`) binds `s : string`. The refinement hypothesis is available within the arm's lexical scope via the elimination rule (§3.4.1) but does not refine the bound variable's declared type.

3. **No type-level computation.** Refinement predicates are first-order propositions in the QF-LIA fragment (or escape to `?proof-required`); they are not types. `(where [n: int] (> (factorial n) 0))` is not legal — the predicate must be a first-order proposition over base-typed bindings.

4. **No proof terms.** Users do not author proof terms in LLMLL surface. Proof obligations are discharged by the verifier (QF-LIA fragment via liquid-fixpoint, §5.3.3) or routed to `?proof-required` for offline discharge (Leanstral pipeline).

5. **No sigma types.** LLMLL has no dependent pair `Σ x : τ. p[x]`. A refinement-aliased type `A ≜ (where [x: τ] p)` is not a pair — no first projection extracting `x`, no second projection extracting a proof of `p[x]`.

6. **No boolean-expression-as-type-equality.** LLMLL has no propositional equality type `e₁ ≡ e₂`. A refinement predicate may use an equality expression (`(= x 0)`), but no type-level proposition `e₁ ≡ e₂` exists.

> Refinement-polymorphic functions and termination-via-refinement (Liquid Haskell, Vazou et al. ESOP 2013) are consequences of non-goals #1 and #3 respectively; deferred to REF-META-3 (predicate well-formedness rule) for explicit treatment of refinement-variable binding shapes.

#### 3.4.3 Soundness statement of record (tier-aware, Path A)

> If `Γ ⊢ e : τ ⇝ O`, all obligations in `O` are discharged at solver-backed evidence level, codegen is faithful for the involved constructs, and no trusted FFI/opaque primitive is used, then the erased generated program preserves the declared refinement predicates at checked introduction and elimination sites.

All four preconditions are load-bearing:

1. **Obligations discharged at solver-backed evidence level.** The function's evidence record (§4.4) is `verified` with body-faithful discharge — not `tested`, not `asserted`, not `verified` with body-fallback (per [`FixpointEmit.hs:506-516`](compiler/src/LLMLL/FixpointEmit.hs#L506-L516)).
2. **Codegen is faithful.** Per §5.3.5: non-recursive QF-LIA with compositional call-chain reasoning. Constructs outside that set lower into runtime assertions or fall back to contract-only verification; the soundness claim does not extend to them under the same tier.
3. **No trusted FFI or opaque primitive.** Functions reaching crypto stubs (§13.11) or other `asserted`-tier dependencies do not satisfy the precondition.
4. **`erBodyFallback` and `erOverflowTainted` are not set.** The INT-1 mechanism ([`Syntax.hs:326-331`](compiler/src/LLMLL/Syntax.hs#L326-L331)) marks overflow-tainted verified evidence; `--strict-verified-core` refuses such evidence ([`Main.hs:1119-1158`](compiler/app/Main.hs#L1119-L1158)).

**Operational enforcement.** `--strict-verified-core` is the operational embodiment of this statement. The strict-tier admissibility set is the *closure under composition*: a function fails admission if any callee in its transitive call graph has `erBodyFallback = True`, `erOverflowTainted = True`, or an `asserted`-tier dependency. Formal derivation of the compositional closure is REF-META-4 territory (erasure theorem with construction-side discipline).

**Out-of-process-agent carve-out.** Values introduced by `?delegate` / `?delegate-async` / `?scaffold` holes are not checked-introduction sites — they arrive from out-of-process agents and fall under the trust tier per §4.4. The soundness statement does not extend to them.

**Path B declined.** A mechanized soundness theorem against an independently-defined operational semantics remains declined per [`docs/design/verification-debate.md`](docs/design/verification-debate.md). This statement is a precise *commitment*, not a mechanized *theorem*.

---

## 4. Logic Structures & Design by Contract

### 4.1 `def-logic` (Pure Functions)

All logic is contained in pure functions declared with `def-logic`. Functions are stateless: they take inputs and return a value. They cannot mutate state or perform IO directly.

Under `--grammar=core-inversion`, the keyword `def-logic` is rejected at parse time (exit 1, `core-grammar-violation` diagnostic); use `def` for the strict-core form or `def-shell` for the permissive form.

> **Note (v0.11 LT-INV):** Under `--grammar=core-inversion`, the strict-core equivalent of `def-logic` is `def`, which restricts the function body to a whitelist of verifiable constructs (linear-arithmetic `EOp`, `ELet`, `EIf`, `EApp` to admitted callees, `EMatch` on `Result` 2-arm). The permissive form is `def-shell` (no body restriction). Both parse only when `--grammar=core-inversion` is active. Under `--grammar=core-inversion`, `def-logic` and `letrec` are **not accepted**: the compiler emits a `core-grammar-violation` diagnostic and exits non-zero. **`GrammarCoreInversion` is now the default** (CE-3, EL-5 gate confirmed 2026-05-30). Use `--grammar=legacy` to parse v0.10 `def-logic` / `letrec` programs. Under `--grammar=legacy`, `def` and `def-shell` are unavailable. See [`docs/getting-started.md §4.14`](docs/getting-started.md) for a worked example and `LLMLL.md §12` for the EBNF.

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

Self-recursive functions must be declared with `letrec`, not `def-logic`. The `:decreases` measure is **required** — the compiler verifies that the measure expression is well-founded (`measure ≥ 0`) via `llmll verify`. Strict recursive descent (`measure(args') < measure(args)` at each call site) is **not yet verified** — it is a research-track item (see [`docs/research-track.md`](docs/research-track.md) §7).

```lisp
(letrec function-name [param1: Type1 ...]
  :decreases decrease-expr   ;; required: checked for well-foundedness (≥ 0)
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

- A **simple variable** measure (`:decreases n`) is checked for well-founded domain membership (`n ≥ 0`) by `llmll verify`. Strict recursive descent (`measure(args') < measure(args)` at each call site) is not yet verified; it is a research-track item (see [`docs/research-track.md`](docs/research-track.md) §7).
- A **complex expression** (`:decreases (- n 1)`) emits a `?proof-required(complex-decreases)` hole — non-blocking, but the solver skips that function.
- Using `def-logic` for a self-recursive function emits a **self-recursion warning**. `letrec` is the correct verified form.

> [!IMPORTANT]
> **Partial-correctness reading.** Because strict recursive descent is not discharged in v0.10, postconditions on `letrec` functions hold **conditionally on termination**: the verifier proves *if the function returns, then the postcondition holds* (standard partial-correctness reading; see [`docs/design/verification-debate.md`](docs/design/verification-debate.md) Q4 "Where is totality enforced?"). The trust report flags `letrec`-derived `verified` claims as partial-correctness when the descent obligation is unfulfilled. Total-correctness reasoning awaits the call-site strict-descent encoding tracked at [`docs/research-track.md`](docs/research-track.md) §7.

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

#### 4.4.1 Display Levels

Every `pre` and `post` clause carries a **display level** — a structured evidence record describing how the contract has been checked. Display levels form a partial-order diamond lattice, not a total order:

```
        verified
       /        \
contract-checked  tested
       \        /
       asserted
```

| Level | Meaning | When assigned |
|-------|---------|---------------|
| `verified` | Body-faithful SMT proof: the solver proved the function body satisfies the contract for all well-typed inputs. | `llmll verify` reports SAFE and the function's body VC was emitted |
| `contract-checked` | The solver proved contract consistency (pre ⇒ post is valid — holds for all models of the contract pair), but the function body was not encoded as a VC. | `llmll verify` reports SAFE for a fallback function (non-QF-LIA body, `letrec`, path-limit exceeded) |
| `tested` | Not formally proven, but not falsified by property-based testing. Trust is proportional to sample coverage. | `llmll test` reports `pass` and the property body resolves to a singleton head-position contracted callee under the PBT-Lift rule in §4.4.5 (a unique `def-logic`/`letrec` reachable as an `EApp` operator inside `propBody` whose contract has a `post` clause). Multi-subject properties produce a diagnostic and no lift. Also assignable via `:trust tested` source annotation. |
| `asserted` | Enforced as a runtime assertion only. No static or dynamic evidence of correctness beyond the assertion itself. | Default for any contract not yet run through `verify` or `test` |

`contract-checked` and `tested` are **incomparable** — neither implies the other. Their meet (greatest lower bound) is `asserted`. This prevents a `tested`-only function from being silently treated as equivalent to a solver-checked function, or vice versa.

> [!NOTE]
> **Epistemic status distinction.** `contract-checked` provides **logical evidence** over the contract pair: the solver proved that the pre/post relationship is internally consistent, independent of the function body. It cannot be falsified by a counterexample (though the body may still violate it). `tested` provides **statistical evidence** over a random sample of size N (default 100): the property was not falsified, but may fail on the N+1th input. These are categorically different kinds of evidence and should not be treated as interchangeable trust signals.

> [!NOTE]
> **Design divergence from Liquid Haskell.** LLMLL admits a statistical evidence channel (`tested`) into the trust-report partial order. This is a deliberate departure from Liquid Haskell (Vazou et al., *Refinement Types for Haskell*, POPL 2014), which restricts its refinement-display to logical evidence only. The rationale is that AI-agent-emitted code is often outside the QF-LIA fragment that admits liquid-fixpoint discharge, and an empirical channel — honest about its statistical character per the epistemic-status note above — gives the trust report something to surface for that majority. The diamond lattice's incomparability between `contract-checked` and `tested` prevents agents or readers from silently treating statistical evidence as logical (their meet is `asserted`, not either of them).

The display level is recorded per-clause in an `EvidenceRecord` that also carries a `body-faithful` flag and an optional `:source` provenance annotation. Display levels are stored per-function in the module's exported metadata (see §8 — `ModuleEnv` extensions).

> The `verified` and `contract-checked` levels carry a prover tag (e.g., `verified (liquid-fixpoint)`). This tag appears in `.verified.json` sidecars and `--trust-report` output but does not affect the surface grammar. The `(trust ...)` declaration accepts four keywords: `verified`, `contract-checked`, `tested`, `asserted`. For details on how body-faithfulness distinguishes `verified` from `contract-checked`, see §5.3.4.

#### 4.4.2 Runtime Assertion Modes

The `--contracts` flag controls which runtime assertions are compiled into the output:

| Mode | Assertions included | Default for |
|------|---------------------|-------------|
| `--contracts=full` | All contracts (verified + contract-checked + tested + asserted) | `llmll test` |
| `--contracts=unproven` | Only non-verified contracts; `verified` body-faithful postconditions are stripped | `llmll build` (when a cached verify result exists) |
| `--contracts=none` | No runtime assertions | Opt-in only; requires explicit flag |

Without a prior `llmll verify` pass, `llmll build` defaults to `--contracts=full`. The `--contracts` flag applies to Haskell code generation regardless of `--emit-only`.

> [!IMPORTANT]
> **Invariant:** Stripping a `verified` contract must not change observable behavior for any well-typed program. This invariant depends on `.fq` emitter faithfulness — see the [faithfulness invariant in FixpointEmit.hs](compiler/src/LLMLL/FixpointEmit.hs#L16-L27) and the [BODY-VC-0 design spec](docs/archive/shipped-design-specs/body-vc-0-spec.md).

#### 4.4.3 Trust-Level Propagation

When module B imports module A and calls a function whose contract is `tested` or `asserted`, the compiler emits a **downstream trust warning**:

```
⚠ Function foo.bar.withdraw has an unproven postcondition.
  Your module inherits this trust gap.
```

The downstream module can acknowledge the gap explicitly:

<!-- ci:roundtrip -->
```lisp
(trust foo.bar.withdraw :level asserted)
(trust auth.verify-token :level tested)
```

This silences the warning and makes the trust decision visible in source. An agent auditing module B can enumerate all `(trust ...)` declarations to see which unproven contracts it depends on.

`(trust ...)` declarations follow `import` semantics — per-function, multiple declarations per module, must appear before any `def-logic`. Duplicate declarations for the same function are idempotent (not an error).

When the sidecar `.verified.json` file is missing for an imported module, all contracts default to `asserted`.

#### 4.4.4 Trust Report (`--trust-report`)

`llmll verify --trust-report` prints a per-function trust summary after verification. For each function with contracts, the report shows:

- The function's own verification level (verified/contract-checked/tested/asserted) for pre and post clauses
- Which cross-module functions it calls and their verification levels
- **Epistemic drift warnings:** when a `verified` conclusion depends transitively on an `asserted` or `tested` assumption upstream



```bash
stack exec llmll -- verify program.llmll --trust-report
# Trust Report
# ────────────────────────────────────────────────────────────
#   withdraw:
#     pre: asserted  |  post: verified (liquid-fixpoint)
#     ↳ calls safe-subtract (pre: asserted, post: verified (liquid-fixpoint))
```

Use `--trust-report --json` for machine-readable JSON output suitable for CI or downstream tooling. The JSON emit carries a `trust_report_version` field plus a six-Int `tier_profile` aggregate `{verified, proved, contract_checked, tested, asserted, no_contract}` over per-function effective tier classifications, intended for downstream tooling that needs a fixed-arity summary without scalarizing the diamond lattice — see [`docs/llmll-trust-report.schema.json`](docs/llmll-trust-report.schema.json) for the full shape.

**OBLIG-PBT-3 (v0.10.5).** `trust_report_version` bumps `1.0.0 → 1.1.0` and the JSON emit gains two new top-level fields parallel to `tier_profile`: `tier_profile_pre` and `tier_profile_post`. Each classifies functions by their per-clause effective level (the clause's own evidence record meeting the transitive-callee effective level), rather than by the per-function meet of pre and post. A function with `pre = asserted` and `post = tested n` increments `tier_profile_pre.asserted` and `tier_profile_post.tested`, where the unchanged scalar `tier_profile.asserted` collapses both clauses via the diamond meet at §4.4.1. Downstream tooling that needs the post-side empirical signal (the R6d harness `Cred(R)` predicate is the canonical consumer) reads `tier_profile_post`. Existing v1.0.0 consumers see the new fields as unknown keys and ignore them.

**Sidecar invariant change.** The `.verified.json` sidecar for a source file `S` may carry entries keyed by **qualified imported names** (e.g., `lib.f`) when a `(check ...)` block in `S` lifted the contract of an imported function `f` from module `lib`. This extends the prior invariant that sidecars were keyed by locally-defined names only. Downstream consumers must accept qualified keys; the trust-report's `collectAllContractStatus` build path already merges by qualified name across the module cache (`compiler/src/LLMLL/TrustReport.hs:148-155`), so the change is read-side compatible. The sidecar-write target for a PBT-lifted entry is the source file's sidecar (where the `(check)` lives), not the imported module's sidecar.

**`pbt_witnesses` provenance and staleness.** Each PBT-derived `tested` evidence record in `.verified.json` carries a `pbt_witnesses` list of `[{hash, description}]` entries, where `hash` is `sha256:` + 64 hex chars over a canonical s-expression serialization of `propBody`. On read, `buildTrustReport` validates each record's witnesses against the set of live property-body hashes (entry module + every cached imported module); records whose witness list is non-empty and disjoint from the live set are downgraded to `asserted` with a per-clause diagnostic in `--trust-report`. Editing a property body invalidates the cached `tested` evidence (next `llmll test` re-lifts with fresh hashes); deleting the property removes the lift entirely. This composes with the existing `ctVerifiedHash` staleness guard for imported-sidecar drift.

The report walks the full module cache (entry-point module plus all imported modules) and computes the transitive trust closure. An agent auditing a module can use the trust report to identify all points where the formal verification chain breaks down.

#### 4.4.5 PBT-Derived Trust Evidence

The `tested` display level can be assigned to a function's post clause from either (a) a source-annotated `(trust f :level tested)` declaration, or (b) a passing `(check ...)` block under the OBLIG-PBT-3 lift rule. The lift rule, formalised:

```
              (SCheck p) ∈ Σ
              status(p) = PBTPassed
              evaluatedSamples(p) = n
              HEAD-contracted(propBody p, Σ) = {f}     (singleton)
              f ∈ contractedNames(Σ ∪ importedExposed(Σ))
              contractPost(f) = Just _
              body(f) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) }
              hash(propBody p) = h
            ─────────────────────────────────────────────────────       (PBT-Lift)
            csPost(f) ⊑  DLTested n   with  pbt_witnesses ∋ {h, desc(p)}
```

where `contractedNames(Σ)` is the set of names bound by any contracted statement form in `Σ`: `SDefLogic`, `SLetrec`, `SDef`, and `SDefShell`. This matches the `contractByName` union at [`compiler/src/LLMLL/PBT.hs:662–670`](compiler/src/LLMLL/PBT.hs#L662-L670). `⊑` denotes lattice-respecting monotonic upgrade: the lift applies only when `csPost.erDisplayLevel` is currently `DLAsserted`. Pre-existing `DLTested`, `DLContractChecked`, or `DLVerified` entries are preserved by the `evidenceCovers` rule at §4.4.1.

**Side conditions.**

1. **Subject scoping.** `f` may be a name local to the source file or a name imported via `(open path …)` and resolved through the assembled test statement list (`compiler/src/LLMLL/PBT.hs` `assembleTestStatements`). Imported subjects are keyed in the local sidecar under their qualified name `lib.f` per the sidecar invariant at §4.4.4.
2. **Multi-subject suppression (default path).** Properties whose head-position set contains two or more contracted callees, *without* explicit `:subject` / `:subjects` metadata, do not lift any of them; the property is reported as an informational diagnostic from `llmll test` ("property covers multiple contracted callees; no trust evidence recorded"). The explicit-attribution route is `:subject` / `:subjects` metadata, shipped in v0.10.6; see the **Annotated-subject branch** below.
3. **Skip and fail suppress the lift.** `PBTSkipped` (static-evaluator bottoms, QuickCheck-discard saturation) contributes zero evidence per §5.1's outcome table. `PBTFailed` runs are surfaced as user-facing diagnostics but record no `pbt_witnesses` and do not retract any prior `DLTested` evidence.
4. **`PBTError` is treated as `PBTSkipped` for write-back.** Exceptions during QuickCheck propagate as user-facing diagnostics; the trust-report channel ignores them.
5. **Interface laws do not lift contracted-callee posts.** Properties extracted from `def-interface :laws` are parametric over implementations, not concrete evidence for contracted callees (`def-logic`, `def`, or `def-shell` form) invoked in the law body; they live on a distinct trust channel.
6. **Lift targets `csPost` only.** Preconditions are caller-side obligations whose evidence channel is the call-site VC at §5.3.4. Lifting `csPre` from PBT would conflate two evidence channels and produce false trust; the lift rule above is therefore strictly asymmetric.
7. **Delegation-body suppression (F-EL5-3, extending F-GATE-8).** When `body(f) ∈ { EHole(HDelegate _), EHole(HDelegateAsync _) }`, the lift is suppressed unconditionally regardless of whether the pre clause is evaluable by the static evaluator. `processRun` at [`compiler/src/LLMLL/PBT.hs:736–744`](compiler/src/LLMLL/PBT.hs#L736-L744) returns `(Map.empty, [d])` with an informational diagnostic; `csPost(f)` remains at its current display level (typically `DLAsserted`). The rationale: `evalExprStaticWith` on `EHole(HDelegate _)` cannot execute the function body — it observes only the `on-failure` fallback path if present, or bottoms otherwise. Any `PBTPassed` result on an evaluable pre clause reflects the property's pre-condition exercise only; it carries no evidence about the actual postcondition. The grammar distinction (`def` vs. `def-shell`) is irrelevant pre-resolution. In PBT-Lift-Annotated, suppression is per-subject: `fᵢ` with a delegation body is excluded from the conclusion range; other subjects in the `:subjects` list still lift. See `compiler/src/LLMLL/PBT.hs:681–694` (`delegateBodies`); §5.3.5 rows 882–883.

**Multi-property accumulation.** When multiple `(check ...)` blocks lift the same `f` (each singleton on `f`, each `PBTPassed`):

```
n_total(f)       = max  { evaluatedSamples(p) | p covers f, status(p) = PBTPassed }
pbt_witnesses(f) =   ⋃  {     hash(p), desc(p) | p covers f, status(p) = PBTPassed }
```

`max` is the **within-channel join**: independent passing properties each constitute a witness; the strongest single witness dominates. This is distinct from `evidenceMeet` at §4.4.1, which uses `min` on `(DLTested, DLTested)` pairs by design — that operation is the GLB across pre/post of a single function, not the join across independent properties on the same clause.

The compiler implementation, including the within-channel join and the sidecar staleness mechanic, lives at `compiler/src/LLMLL/PBT.hs` (`pbtTrustWriteback`, `mergePbtWriteback`, `canonicalPropBodyHash`).

**Annotated-subject branch (OBLIG-PBT-4, v0.10.6+).** When a `(check ...)` block carries explicit subject metadata — sexp `(check "d" :subject f (for-all …))` (singleton sugar) or `(check "d" :subjects [f₁ … fₖ] (for-all …))` (joint form), JSON-AST `CheckDecl.subjects: [...]` under the v0.5.0 schema — the head-position scan is bypassed entirely and the lift rule fires per declared subject:

```
              (SCheck p) ∈ Σ
              status(p) = PBTPassed
              evaluatedSamples(p) = n
              subjects(p) = [f₁ … fₖ]                  (non-empty)
              fᵢ ∈ contractedNames(Σ ∪ importedExposed(Σ))              for each i
              contractPost(fᵢ) = Just _                                  for each i in lifted
              body(fᵢ) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) } for each i in lifted
              hash(propBody p) = h
            ──────────────────────────────────────────────────────  (PBT-Lift-Annotated)
            csPost(fᵢ) ⊑  DLTested n     with shared pbt_witnesses ∋ {h, desc(p)}
                          for each fᵢ with contractPost(fᵢ) = Just _
                              and body(fᵢ) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) }
```

Subjects declared in `:subjects` but lacking a `post` clause are skipped with an informational diagnostic (the S3 case from `processRun`); the remaining annotated subjects still lift. Duplicate names are deduped (`:subjects [f f]` produces one record per `f`). Empty `:subjects []` is rejected at parse time (S6). The shared `pbt_witnesses` hash across all per-subject records of one property is the canonical-body-hash invariant from the PBT-Lift rule above; consumers can detect joint provenance by inspection of the shared hash. Cross-module subjects key under their qualified path via the existing `qualMap` (the S8 case), preserving the §4.4.4 sidecar invariant.

The annotated branch is the language's explicit-attribution route for **metamorphic-relation properties** (Hughes 2020 *How to Specify It! A Guide to Specifying Properties*, §3 — a single property over a structural relation across multiple callees, where joint evidence is the agent's intent). LLMLL does not adopt `eqc_statem`-style command sequences ("state-machine properties" in the QuickCheck literature); `:subjects` is per-property explicit attribution at a single point, not a state machine.

**Pacheco-Lahiri-Ernst overallocation discipline.** The unannotated multi-callee diagnostic at side-condition 2 above continues to refuse implicit lift; the `:subjects` metadata is the agent's explicit consent to joint-evidence allocation across the declared callees. The schema-cost trade was deliberate: the additive optional `subjects: [Name]` AST field is a minor bump (`schemaVersion 0.4.0 → 0.5.0`); a conjoint-record alternative (`DLJointTested [Name] n` or a `subjects: [Name]` field on `DLTested`) would have required `trust_report_version 1.2.0`, coupling downstream tooling (notably the repair-loop harness's `Cred(R)` consumer) with a trust-report schema change at Phase 3 launch.

#### 4.4.6 Contract Discriminative Power (CDP, v0.11)

The diamond-lattice evidence axis at §4.4.1 answers one question: *do we know this implementation satisfies the specification?* A second, orthogonal question — *does the specification rule out enough wrong implementations?* — is the **contract-discriminative-power (CDP)** axis, shipped in v0.11 LT-CDP. A function can simultaneously be `verified` (high evidence) and `0.18` DP (weak spec, admits most observable behaviors); the pair makes this visible without collapsing to a scalar.

**Score.** Shannon-normalized over a closed observation set `Ω`,

```
DP_Ω(S) = 1 − log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)
```

where `B_{T,U,Ω}` is the finite set of observable behaviors of functions `T → U` over candidate set `Ω`, and `⟦S⟧_Ω = { b ∈ B | b satisfies contract S }`. `DP = 0` when the contract admits every observable behavior; `DP = 1` when it admits exactly one. Inconsistent contracts (`|⟦S⟧_Ω| = 0`) surface as a distinct `spec-inconsistent` warning rather than score 0.

**Observational, not semantic.** The score is meaningful relative to `Ω` only — two implementations that disagree semantically but agree on every input in `Ω` collapse to one observed behavior. Cross-function and cross-version score comparison requires same-`Ω` discipline; the `basis` field in the trust-report `discriminative_axis` block records `Ω`'s identity for auditability. Consumers setting CI gates on CDP scores must respect this distinction or risk gating on the wrong reading. See [`docs/design/contract-discriminative-power-proposal.md`](docs/design/contract-discriminative-power-proposal.md) §1 Rev 2.

**`(spec-entropy …)` annotation.** Three values per contracted `def` / `def-shell` function (under `--grammar=core-inversion`; also accepted on `def-logic` under `--grammar=legacy` but `def-logic` functions receive `WarnDefShellOutOfScope` under `--cdp` and are not scored):

```lisp
;; Requires --grammar=core-inversion. Under --grammar=legacy, use def-logic (out of CDP scope under --cdp).
(def transfer [from: AccountId to: AccountId amount: PositiveInt]
  (pre  (>= (balance-of from) amount))
  (post (and (= (balance-of from) (- (old (balance-of from)) amount))
             (= (balance-of to)   (+ (old (balance-of to))   amount))))
  ;; (spec-entropy :strict)  — default; can be elided
  ...)

(def cache-lookup [k: Key]
  (post (or (is-ok result) (is-error result)))
  (spec-entropy :intentional)
  ...)
```

- **`:strict`** (default; can be elided) — low DP raises a diagnostic via `--cdp` / `--weakness-check`.
- **`:intentional`** — low DP is the design (caches admit any eviction; schedulers admit any ready thread; hash-map iteration order is unspecified). The annotation is the agent's explicit declaration; CDP is still computed and reported, but the diagnostic is suppressed. Self-attestation discipline: agents may over-annotate to silence warnings, so the trust report surfaces the annotation in `spec_entropy_annotation` and a module-level `over-annotation-warning` fires when the ratio of `:intentional` contracts exceeds 30% (configurable later).
- **`:unknown`** — CDP is computed and reported but does not raise. For spec-development workflows where the contract is in flux.

**CLI.** `llmll verify <file> --cdp` runs the closed v0.11 candidate-set sweep per §4.3.1 of the proposal after the SAFE result and emits one `discriminative_axis` block per contracted function. Combined with `--trust-report --json`, the score is paired with the diamond-lattice evidence level in the trust-report JSON (`trust_report_version 1.2.0`, additive over v1.1.0 — existing consumers ignore `discriminative_axis`).

**Scope (CDPScopeCoreOnly, v0.11).** `--cdp` scores only `def`-form (`SDef`) functions regardless of grammar mode. `def-shell` and legacy `def-logic` functions appear in the trust-report `discriminative_axis` block with `"score": null` and `"warnings": ["def-shell-out-of-scope"]`; the result map is uniform — every contracted function has an entry. `CDPScopeAllDefLogic` is available in the compiler for testing contexts but is not exposed via a CLI flag in v0.11. See [`docs/design/contract-discriminative-power-proposal.md §2`](docs/design/contract-discriminative-power-proposal.md) for the scope-selection rationale under LT-INV gate Outcome 0.

### 4.5 Suppression Governance (`weakness-ok`)

When a function is intentionally left without contracts (e.g., pure rendering logic, FFI wrappers, or configuration constants), the `weakness-ok` declaration acknowledges the gap and prevents the spec coverage gate from flagging it as unspecified:

```lisp
(weakness-ok render-board "pure string rendering — no meaningful postcondition")
(weakness-ok cache-evict "eviction policy is unspecified by design")
```

**Syntax:** `(weakness-ok fn-name "reason")`. Both arguments are required — the parser rejects bare `weakness-ok` without a reason string.

**Governance rules:**

| Rule | Code | Behavior |
|------|------|----------|
| WO-1 | `W601` | `weakness-ok` target doesn't match any function in the module → warning |
| WO-2 | `W602` | Function has contracts AND `weakness-ok` → contracts take priority; `weakness-ok` is redundant (warning) |
| D10 | `W603` | More than 50% of functions are suppressed → warning (bulk suppression guardrail) |

`weakness-ok` functions count toward `effective_coverage` (see §5.4) but are visually distinguished with a `⊘` marker in `--spec-coverage` output.

JSON-AST equivalent: `{"kind": "weakness-ok", "name": "render-board", "reason": "pure string rendering"}`.

### 4.6 Clause-Level Provenance (`:source`)

In LLMLL's target domains (financial compliance, protocol implementation, cryptographic standards), auditors require per-clause traceability to the originating standard. The `:source` annotation provides free-form provenance metadata on `pre` and `post` clauses:

```lisp
(def-logic transfer [from: string to: string amount: int]
  (pre (>= amount 0)
    :source "ERC-20 §transfer — amount must be non-negative")
  (post (= (total-supply result) (total-supply state))
    :source "ERC-20 §transfer — conservation invariant")
  ?transfer-impl)
```

**Semantics:** Pure metadata — no effect on type checking, verification, or codegen. The `:source` string is stored per-clause (`contractPreSource` / `contractPostSource`) and threaded through `--trust-report` output and `.verified.json` sidecars.

**Backward compatible:** Omitting `:source` yields `Nothing` — all existing programs parse and compile unchanged.

**Multiple pre clauses:** When multiple `(pre ...)` clauses are combined with `and`, the `:source` annotation is dropped (ambiguous provenance across combined clauses).

JSON-AST fields: `"pre_source"` / `"post_source"` (optional string).



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

**Property outcomes.** Each `check` block reports one of three statuses:

| Status | When | Trust contribution |
|--------|------|--------------------|
| `pass` | All samples evaluated to `true` | `tested` evidence on the singleton head-position contracted callee's post clause per the PBT-Lift rule in §4.4.5 (multi-subject properties produce a diagnostic and no lift). Persisted in `.verified.json` with a `pbt_witnesses` hash for staleness invalidation. |
| `fail` | At least one sample evaluated to `false`; counterexample reported | None — verification gate fails |
| `skip` | Property body could not reduce to a literal Bool on every sample (e.g., body calls `?delegate` without `on-failure`, or calls runtime-only operations like `wasi.io.stdout`) | None — does not contribute trust evidence |

A `skip` is **not** a `pass`. Property bodies that reach unevaluable terms (`?delegate` without fallback, `?proof-required` postcondition references, command constructors, `await`) are reported `skip` and contribute zero trust evidence. Static-evaluator coverage is documented at `compiler/src/LLMLL/Contracts.hs` `evalExprStaticWith` and `compiler/src/LLMLL/PBT.hs` `runPropertyWith` (v0.10.2+).

#### 5.1.1 `evaluatedSamples` Semantics

`DLTested n` records that `n` property-body evaluations reduced to `True`, with no evaluation reducing to `False`. This is a **lower bound on assertions of the postcondition**: under an implication-shape property `(if pre then post else true)`, samples for which `pre` fails count as `True` evaluations vacuously. A coverage-instrumented count distinguishing genuine postcondition witnesses from vacuous evaluations is a follow-on (OBLIG-PBT-4); under v0.10.5, `n` is honest about evaluation but not about exercise. The static-evaluator path always reports `n = 100`; the QuickCheck fallback path reports the non-discarded evaluation count from `Result.Success.numTests`.

### 5.2 Generators for Refinement Types (`gen`)

When a `for-all` binds a variable of a refinement type (e.g., `Letter`), the test engine must generate values that satisfy the type's `where` predicate. The default strategy is **rejection sampling**: generate a value of the base type, check the predicate, discard and retry if it fails. This terminates when 100 valid samples are accumulated, or reports a generation failure after 10,000 attempts.

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

A `gen` declaration applies to all `for-all` blocks in the same module that use the named type. If no `gen` is declared for a refinement type, rejection sampling is used automatically.

### 5.3 Verification

**`llmll verify`** is the compile-time verification command. It:

1. Walks the typed AST and emits a `.fq` constraint file for `liquid-fixpoint`.
2. Runs `fixpoint` (+ Z3) as a standalone binary — no GHC plugin required.
3. Reports SAFE or constraint-violation diagnostics with RFC 6901 JSON Pointers back to the original `pre`/`post` clause.

**Coverage:** Quantifier-free linear integer arithmetic (`+`, `-`, `=`, `<`, `<=`, `>=`, `>`). Non-linear predicates and complex `letrec` termination measures are skipped (see `?proof-required` in §6).

**Qualifier strategy:** Qualifiers are auto-synthesized from `pre`/`post` predicates and seeded with the built-in set `{True, GEZ, GTZ, EqZ, Eq, GE, GT}`. No manual qualifier declarations are needed.

```bash
stack exec llmll -- verify ../examples/withdraw.llmll
# ✅ ../examples/withdraw.llmll — SAFE (liquid-fixpoint)
```


#### 5.3.1 Spec Weakness Detection

`llmll verify --weakness-check` is an advisory pass that runs **after** a SAFE verification result. For each contracted function, the compiler constructs trivial candidate bodies (identity, constant-zero, empty-string, `true`, empty-list) and checks whether they also satisfy the contract. If any trivial body passes, a `spec-weakness` diagnostic is emitted:

```
⚠ Spec weakness detected for `sort-list`:
  Your contract: (post (= (list-length result) (list-length input)))
  Trivial valid implementation: (def-logic sort-list [input: list[int]] input)
  Consider strengthening the postcondition.
```

This diagnostic is **non-blocking**: the function remains SAFE. It is an *advisory* signal that the specification may not distinguish correct implementations from trivial ones. The structured JSON diagnostic includes `trivial_implementation` and `suggested_postcondition` fields.

Weakness checking does not modify `FixpointEmit.hs` — it constructs synthetic single-statement programs and calls the existing `emitFixpoint` pipeline.

**v0.11 LT-CDP extends the trivial-body enumeration to a counted divergence metric.** Where legacy `--weakness-check` reports a binary "any trivial body passes?" diagnostic over the v0.10 five-enumerator catalog, `llmll verify --cdp` extends the same per-candidate `emitFixpoint` + solver loop to count: `|{candidates that satisfy S}| / |{type-compatible candidates}|`, normalized as `DP_Ω(S) = 1 − log|⟦S⟧_Ω| / log|B_{T,U,Ω}|`. The v0.11 candidate set is closed at [`docs/design/contract-discriminative-power-proposal.md`](docs/design/contract-discriminative-power-proposal.md) §4.3.1 (identity over each param + small ints `{0, 1, -1, 42}` + both bools + `{"", "a"}` + list-empty / list-singleton + `Success`-default / `Error "default"` + pair-of-defaults); the score is reported with provenance in the trust-report `discriminative_axis` block. Legacy `--weakness-check` keeps the v0.10 5-enumerator catalog and the binary diagnostic surface unchanged; the two flags are orthogonal. See §4.4.6 for the evidence-axis framing and the load-bearing observational-vs-semantic caveat.

#### 5.3.2 Spec Coverage Gate

`llmll verify --spec-coverage` classifies every function in a module and computes the **effective specification coverage**:

```
effective_coverage = (contracted + suppressed) / total_functions
```

| Classification | Meaning |
|---|---|
| **Contracted** | Has at least one `pre` or `post` clause |
| **Suppressed** | Has a `(weakness-ok name "reason")` declaration and no contracts |
| **Unspecified** | No contract, no suppression |

> [!NOTE]
> **Suppression accounting rationale.** `effective_coverage` includes suppressed
> functions because a documented `(weakness-ok "reason")` represents an explicit
> engineering decision — the team has reviewed the function and determined that a
> contract is not required at this time. This is qualitatively different from an
> un-reviewed function with no contract.
>
> However, suppression is not specification. The D10 warning (>50% suppressed)
> guards against gaming. For governance reporting, `suppression_debt`
> (= suppressed / total) is reported alongside `effective_coverage` for governance visibility.

Example output:

```bash
stack exec llmll -- verify program.llmll --spec-coverage
# Spec Coverage Report
# ────────────────────────────────────────────
#   Functions with contracts:     4 / 7   (57%)
#     Proven:                     2
#     Tested:                     1
#     Asserted:                   1
#   Intentional Underspecification:
#     ⊘ cache-evict — "eviction policy is unspecified by design"
#   Unspecified:                  2
#     sort-list, validate-input
# ────────────────────────────────────────────
#   Effective coverage: 71% (5/7)
```

Use `--spec-coverage --json` for machine-readable output:

```json
{
  "summary": {
    "contracted": 12,
    "suppressed": 5,
    "unspecified": 3,
    "total": 20,
    "proven": 4,
    "tested": 3,
    "asserted": 5,
    "effective_coverage": 0.85
  },
  "entries": ["..."],
  "laws": [],
  "warnings": []
}
```

The JSON output includes per-function `entries`, aggregate `summary`, interface `laws`, and governance `warnings`. Summary fields: `effective_coverage` (= (contracted + suppressed) / total), `spec_coverage` (= contracted / total, excluding suppressions), and `suppression_debt` (= suppressed / total).

**Division guard (SC-PO-1):** A module with 0 functions has `effective_coverage = 100%`.

**Governance guardrails:** See §4.5 for WO-1, WO-2, and D10 warning rules.

#### 5.3.3 Verification Scope

The following table precisely defines what `llmll verify` can prove, what it tracks but cannot prove, and what is designed but not yet operational:

| Fragment | Status | Prover | What it covers |
|----------|--------|--------|----------------|
| **QF-LIA** (quantifier-free linear integer arithmetic) | **Shipped** | Z3 via liquid-fixpoint | `+`, `-`, `=`, `<`, `<=`, `>=`, `>` over `int`. Handles numeric bounds, conservation invariants, length preservation. ~80% of practical contracts. |
| **Termination** (`:decreases` measures) | **Shipped** | liquid-fixpoint | Simple variable measures (`:decreases n`) are checked for non-negativity (`n ≥ 0`). Call-site strict descent (`measure(args') < measure(args)`) is not yet encoded — it is a research-track item (see [`docs/research-track.md`](docs/research-track.md) §7). Complex measures emit `?proof-required(complex-decreases)`. |
| **Property-based testing** | **Shipped** | QuickCheck | `check`/`for-all` blocks generate randomized inputs and attempt to falsify properties. Contracts verified this way are marked `tested`. |
| **Inductive properties** | **Designed, not shipped** | Lean 4 via Leanstral MCP | Translation infrastructure exists (`LeanTranslate.hs`, `MCPClient.hs`, `ProofCache.hs`). Currently runs in **mock mode only** (`--leanstral-mock`). Real proof integration is blocked on `lean-lsp-mcp` availability. |
| **Cryptographic primitives** | **Asserted** | _(opaque — outside any decidable fragment)_ | `hmac-sha1` and `sha1` builtins are treated as axiomatically correct. Contracts on functions that use them are capped at `asserted` in the trust report. The TOTP benchmark (`examples/totp_rfc6238/`) demonstrates mixed display levels (verified + asserted + tested) across a single module. |

**What is NOT silently dropped:** Contracts outside the QF-LIA fragment are not ignored. They are:
1. Enforced as **runtime assertions** (unless stripped via `--contracts=none`)
2. Tracked as **`asserted`** verification level
3. Flagged with `?proof-required` holes when the predicate is detected as non-linear or requiring induction
4. Propagated through the **trust report** — downstream `verified` conclusions that depend on `asserted` assumptions are flagged as epistemic drift

**Refinement-alias predicate routing.** Refinement-alias predicate obligations — generated at introduction sites by the checking-mode rule at §3.4.1 — route through the same channels as ordinary contract obligations; no separate channel is introduced. A predicate `p` in `(where [x: τ] p)` that is linear over the base-type binding is QF-LIA and auto-discharged by liquid-fixpoint (contract channel, `Contracts.hs` / `FixpointEmit.hs`); a predicate outside QF-LIA falls to items 1–4 above. See §5.3.5 for per-construct rows.

> [!IMPORTANT]
> **Leanstral is not a shipped verification path.** The one-pager, README, and this spec distinguish between shipped SMT verification (Z3/liquid-fixpoint) and the designed-but-mock Lean 4 path. No LLMLL claim of `verified` correctness rests on Leanstral. When `lean-lsp-mcp` becomes available, Leanstral integration will be scheduled; until then, inductive properties are tracked as `asserted` with explicit `?proof-required` holes.

#### 5.3.4 Body-Faithful Verification

The `.fq` emitter now encodes function bodies as verification conditions for functions in the decidable QF-LIA fragment. For a function with postcondition Q, precondition P, and body B, the emitter generates constraints of the form:

```
P ∧ (result = ⟦B⟧) ⟹ Q
```

where ⟦B⟧ is the body's symbolic translation into the liquid-fixpoint constraint language. This closes the faithfulness gap: when both the contract and the body are in the QF-LIA fragment, `DLVerified "liquid-fixpoint"` with `erBodyFaithful = True` means "the implementation satisfies the contract for all well-typed inputs."

**Coverage:** `ELet` with alpha-renaming (shadowing-safe), `EIf` with path-sensitive constraint emission, `EApp` to contracted functions (v0.9.0, assume-guarantee), `EMatch` on `Result` with two-arm Success/Error pattern (v0.9.0), and all QF-LIA operators. General `EMatch`, `letrec` (own body), and non-linear expressions fall back conservatively to contract-only verification.

**Compositional call-chain verification (v0.9.0):** When a body-faithful function calls a contracted callee, the verifier:
1. **Proves** the callee's precondition is satisfied at the call site (PROVE polarity — caller obligation)
2. **Assumes** the callee's postcondition holds for the call result (assume-guarantee)
3. **Binds** a fresh symbolic variable for the call result

Recursive functions (detected via `stronglyConnComp` SCC analysis) are excluded from body VC emission for their own body, but non-recursive callers may still use assume-guarantee against their contracts.

**Path limit:** Functions with >4096 execution paths (from deeply nested `EIf`) fall back to contract-only verification with a diagnostic warning. This prevents solver timeouts while maintaining soundness.

**Contract stripping:** `--contracts=unproven` strips postcondition runtime assertions for functions that are both `DLVerified` and body-faithful (`erBodyFaithful = True`). Preconditions are never stripped — body VCs prove postconditions, not preconditions. Functions that fall back to contract-only verification retain all runtime assertions regardless of proof status.

**Strict verified core:** `--strict-verified-core` hard-errors if any function falls back from body-faithful verification (i.e., appears in `erBodyFallback`). Use this to enforce that all functions in a module are fully verified.



#### 5.3.5 Verification Matrix

The following matrix documents the verification status of each syntax construct as of v0.9.0, updated through v0.11. "Typechecked" means the construct is accepted by the type checker. "Runtime assert" means contracts on functions using the construct are enforced as runtime assertions. "SMT contract" means the construct's contracts can be checked by the solver. "SMT body-faithful" means the construct's implementation is encoded as a verification condition.

| Construct | Typechecked | Runtime assert | SMT contract | SMT body-faithful | QuickCheck | Fallback behavior |
|---|---|---|---|---|---|---|
| `ELit` (int, bool) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `EVar` (int-typed) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `EVar` (non-int) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| `EOp`/`EApp` (+, -, =, <, <=, >=, >, !=) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `EOp`/`EApp` (*, /, mod, rem) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime + `?proof-required` |
| `ELet` (single `PVar`, int RHS) | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `ELet` (pattern/non-int RHS) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| `EIf` (int guards, ≤4096 paths) | ✅ | ✅ | ✅ | ✅ (path-split) | ✅ | — |
| `EIf` (>4096 paths) | ✅ | ✅ | ✅ | ❌ | ✅ | contract-only + warning |
| `EApp` (contracted callee, non-recursive) | ✅ | ✅ | ✅ | ✅ (v0.9.0 assume-guarantee) | ✅ | — |
| `EApp` (uncontracted / recursive self) | ✅ | ✅ | ✅ | ❌ | ✅ | contract-only |
| `EApp` (builtins: `string-length` etc.) | ✅ | ✅ | ✅ | ❌ | ✅ | contract-only |
| `EMatch` on `Result` (2-arm Success/Error) | ✅ | ✅ | ✅ | ✅ (v0.9.0 two-path) | ✅ | — |
| `EMatch` (general ADT, >2 arms) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| `EPair`/`first`/`second` | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| `letrec` (own body VC) | ✅ | ✅ | ⚠ measure well-formedness only | ❌ | ✅ | runtime + `:decreases` check |
| `EDo` | ✅ | ✅ | ❌ | ❌ | limited | runtime |
| `ELambda` | ✅ | ✅ | ❌ | ❌ | ✅ | runtime |
| **Int overflow** | ✅ | ✅ | ✅ on `int` (Z3 `Int` = Haskell `Integer`, both unbounded — v0.11 LT-INT) | n/a on `int` | ✅ | gap closed on `int`; re-arms on `machine-int` (INT-3) |
| `TCustom` alias predicate obligation at intro site (QF-LIA `p`) | ✅ | ✅ | ✅ (contract channel) | ✅ | ✅ | no separate channel; routes via `Contracts.hs` / `FixpointEmit.hs`; §3.4.1 checking-mode rule |
| `TCustom` alias predicate obligation at intro site (non-QF-LIA `p`) | ✅ | ✅ | ❌ | ❌ | ✅ | runtime assertion + `?proof-required`; same fallback as non-QF-LIA contract obligation |
| `?delegate` / `?delegate-async` body (`def-shell`) | ✅ | ❌ (`on-failure` clause executes at runtime if present; unresolved → `?delegate-pending`) | ❌ (`asserted` tier; host-function contracts verified contract-only) | ❌ | skip | `asserted`; F-GATE-8 (`guardDelegate` in `PBT.hs:641–755`) blocks `DLTested` PBT write-back on delegate-body functions regardless of `on-failure` fallback path; `on-failure` enables runtime execution but does not promote trust; see §11.2 |
| `?delegate` / `?delegate-async` body (`def`, pre-resolution) | ✅ | ❌ | ❌ | ❌ | skip | authoring intermediate (LT-INV §3.5 Rev 2); admitted in `def` pending resolution; post-resolution, agent loop re-typechecks resolving value's admissibility before merging into `def`-form host; pre-resolution trust is `asserted` unconditionally regardless of pre-clause evaluability — two mechanisms converge: (a) `guardDelegate` in `PBT.hs:pbtTrustWriteback` (F-EL5-3, extending F-GATE-8) blocks `DLTested` write-back when body is `EHole(HDelegate _)` / `EHole(HDelegateAsync _)` for `SDef` forms — evaluable-pre path; (b) pre-clause unevaluability propagation (`QC.discard` saturation → `PBTSkipped` → no lift) — unevaluable-pre path (EL-5 grade-A path B, PM-006). Mechanisms are independent and non-interfering. Post-resolution, the merging agent re-runs `checkCalleeAdmissibility` and re-verifies the resolved body; see §11.2. F-EL5-3 adjudicated language-team 2026-05-30 |

> [!NOTE]
> **LT-PPR (v0.11) — predicate-carrying `?proof-required` in `pre`/`post`.** When the predicate-carrying form `(?proof-required :reason "tag" pred-expr)` appears in a `pre` or `post` clause, the predicate `pred-expr` is type-checked as `bool` and emits a Haskell runtime assertion at codegen (Runtime assert column: ✅ — actively executed, not a no-op). If `pred-expr` contains non-linear operators (`*`, `/`, `mod`, `^`), `llmll check` emits a `QF-LIA` warning naming the function and clause. SMT contract and SMT body-faithful columns are ❌ for the carrying form regardless of predicate linearity — the predicate is enforced at runtime, not submitted to the solver. The bare `?proof-required` leaf in `pre`/`post` is unchanged: Runtime assert is ✅ but the generated assertion was previously a no-op; the predicate-carrying form is what enables active runtime enforcement. Body-position `?proof-required` (either form) emits an `error` stub and is not affected by LT-PPR.

> [!NOTE]
> **Callee admissibility in `def` bodies (LT-INV, v0.11).** Built-in LLMLL operators (members of `builtinEnv`) are unconditionally admitted inside `def` bodies, including operators appearing in contract clause expressions. The core-mode callee-admissibility check at `checkCalleeAdmissibility` ([`TypeCheck.hs:346`](compiler/src/LLMLL/TypeCheck.hs#L346)) applies three admission legs — body-faithful `EvidenceRecord`, `trustedPrelude` membership, and `builtinEnv` membership — identically whether the `EApp` node appears in the function body or in a `pre`/`post` predicate clause. The trust tier of `builtinEnv` callees propagates into the caller via the lattice meet per §4.4.1: QF-LIA primitives (`+`, `-`, `=`, `<`, etc.) are body-faithful by construction and leave the meet unchanged; axiomatized trusted-prelude builtins (`string-length`, `list-head`, etc.) produce the v0.9.0 assume-guarantee tier at the call site. See the `§12` grammar production comment for the production-level statement.

> [!NOTE]
> **Integer overflow model — gap closed on `int` (v0.11, LT-INT).** Z3 reasons over mathematical integers (unbounded). Through v0.10.8, Haskell `Int` was 64-bit and the verifier/runtime semantics diverged at overflow boundaries — the documented gap. As of v0.11 LT-INT, LLMLL `int` lowers to Haskell `Integer` (unbounded) at codegen, and the verifier/runtime semantics agree on `int`. The gap re-arms only for programs that opt into a future bounded `machine-int` primitive (post-freeze, per [`docs/design/int-3-machine-int-sketch.md`](docs/design/int-3-machine-int-sketch.md)) under QF-BV verification with the higher solver cost that implies; on `int` there is no overflow event. Pre-v0.11 historical note: programs operating near `Int64` boundaries under the v0.10.8 codegen used QuickCheck tests with edge-case generators targeting `maxBound` and `minBound`; that discipline transfers to `machine-int` if/when it ships.

> [!IMPORTANT]
> **`overflow_tainted` marking — dormant on `int` post-v0.11 LT-INT.** The v0.10.8 INT-1 machinery (`erOverflowTainted` field on `EvidenceRecord`, `overflow_tainted` JSON projection in trust report / `.verified.json` sidecar / obligation-report trust channel, `--strict-verified-core` refusal, `bodyHasOverflowArith` walker) is preserved across the trust-report / sidecar / obligation surface, but the trigger is disarmed on `int`: the body-VC emitter call to `addOverflowTainted` at [`compiler/src/LLMLL/FixpointEmit.hs:516`](compiler/src/LLMLL/FixpointEmit.hs#L516) is commented out under LT-INT, and the walker — though still defined and round-trippable — is no longer reached on production verify runs. Pre-v0.11 sidecars carrying `overflow_tainted: true` regenerate without the tag on next verify; `examples/banking_ledger/banking.llmll`'s `safe-subtract` is the demonstrating case (refused under `--strict-verified-core` in v0.10.8; admitted in v0.11). INT-3 (`machine-int` opt-in under QF-BV, post-freeze, per [`docs/design/int-3-machine-int-sketch.md`](docs/design/int-3-machine-int-sketch.md)) re-arms the trigger by re-enabling the emitter call with a type-aware predicate that fires on `machine-int` but not `int`.
>
> **Historical record (v0.8.1a → v0.10.8):** the v0.10.8 marking is purely syntactic — it does not consult refinement predicates that might witness bounds — and the trigger set is `EOp` / `EApp` applications of `+`, `-`, `*`, `/`, `mod`, `rem`, `^`, `**` whose operands are not all integer literals whose folded value fits `Int64`. Compile-time constant arithmetic like `(+ 40 2)` is cleared. The taint never propagates transitively across calls — it is per-function-body — because the call-site verification still proves the callee's post against the caller's pre under Z3's unbounded-integer semantics. The principled discharge paths under v0.10.8 were: (i) wrap the post-condition in `?proof-required` and complete via Leanstral; (ii) the v0.11 INT-2 codegen switch — now shipped; (iii) post-freeze `machine-int` under QF-BV per INT-3.

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
| `?delegate-async @agent "description" -> Type` | Non-blocking delegation. `return_type` is the inner type `T`; the compiler wraps it in `Promise[T]` (see §11.2). |
| `?proof-required` | A contract predicate outside the decidable QF arithmetic fragment. Two forms: (1) bare leaf `?proof-required` — marks the clause `asserted`, emits no runtime assertion; (2) predicate-carrying `(?proof-required :reason "tag" pred-expr)` in `pre`/`post` position (LT-PPR, v0.11) — `pred-expr` is type-checked as `bool` and emits a Haskell runtime assertion at codegen; non-linear predicates emit a `QF-LIA` warning at `llmll check`. Body-position `?proof-required` (either form) emits an `error` stub and is unchanged. Non-blocking. See §6 and `getting-started.md §4.11`. |

> [!NOTE]
> **`?delegate` / `?delegate-async` trust and verification.** These hole forms are authoring intermediates admitted by the typechecker anywhere an expression of the declared type is expected. In `def-shell` bodies, the host function's trust tier is `asserted`; PBT `DLTested` write-back is suppressed by F-GATE-8 (`guardDelegate`) regardless of whether an `on-failure` clause provides a runtime fallback. In `def` bodies (LT-INV), both forms are admitted pending out-of-process resolution; post-resolution, the agent loop re-runs the typechecker's core-membership predicate before merging the resolving value into the `def`-form host. Pre-resolution trust is `asserted` unconditionally regardless of pre-clause evaluability: F-EL5-3 (adjudicated language-team 2026-05-30) extends `guardDelegate` (F-GATE-8) to `SDef` forms, blocking `DLTested` write-back on the evaluable-pre path; pre-clause unevaluability independently produces `PBTSkipped` on the unevaluable-pre path (EL-5 grade-A path B, PM-006). Both paths converge on `asserted`. See §5.3.5 (verification matrix rows) and §11.2 (inference rules, `on-failure` type rule, async delegation flow).

> [!NOTE]
> **Bare `?proof-required`: a gap signal without a predicate payload.** The bare leaf form records that the clause involves reasoning outside the verifier's decidable fragment; no predicate expression is embedded. The intended predicate is documented in source comments, function docstrings, or trust-report annotations. The compiler treats bare `?proof-required` as `asserted` for trust-level purposes (per §5.3.5). **LT-PPR (v0.11) predicate-carrying form:** `(?proof-required :reason "tag" pred-expr)` in `pre`/`post` position *does* embed the predicate as an optional `Expr` payload — `HoleKind.HProofRequired Text (Maybe Expr)` in [`compiler/src/LLMLL/Syntax.hs`](compiler/src/LLMLL/Syntax.hs). The compiler type-checks `pred-expr` as `bool` and emits a runtime assertion at codegen. Body-position `?proof-required` (either form) is unchanged and emits an `error` stub regardless of predicate presence.

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

`llmll` programs run in a capability-gated sandbox. All interactions with the outside world require `import` statements that grant specific **capabilities**. The sandbox implementation is Docker + `seccomp-bpf` + `{-# LANGUAGE Safe #-}` with WASM-WASI planned as a future deployment target. Capability enforcement is active at compile time: when a `wasi.*` function is called, the type checker verifies that a matching `SImport` with a `Capability` is present in the module’s statements. Missing imports produce a structured type error, and propagation is non-transitive — each module must re-declare its own capability imports, matching the principle of least authority. Non-transitive capability enforcement is implemented in [`TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs#L641-L660) (CAP-1, shipped v0.4) and verified by the capability test fixtures in [`compiler/test/fixtures/`](compiler/test/fixtures/).

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

> [!NOTE]
> **Grammar-mode inheritance for imported modules.** All imported modules — whether
> resolved from the local source root, `extraRoots`, or the `llmll-hub` cache
> (`~/.llmll/modules/`) — are parsed under the **same `GrammarMode` as the invoking
> command**. In v0.11+, the default grammar mode is `GrammarCoreInversion`.
>
> Under `GrammarCoreInversion`, any imported `.ast.json` file containing
> `{"kind": "def-logic"}` or `{"kind": "letrec"}` nodes produces a
> `core-grammar-violation` diagnostic (exit 1). Hub publishers must ship
> `schemaVersion 0.6.0` modules using `def`/`def-shell` node kinds.
>
> `wasi.*`, `haskell.*`, and `c.*` builtin-namespace imports carry no parseable
> file and are exempt from grammar-mode checking.

### 8.3 Declaration Ordering

All `import`, `open`, and `export` declarations should appear **before** any `def-logic`, `type`, or `def-interface` statements — both inside a `(module ...)` block and at file scope. The parser accepts declarations in any position, but **ordering has semantic impact**: the type-checker processes statements sequentially, so an `(open A)` placed after a `(def-logic f ...)` will not inject A's names into `f`'s body scope.

Recommended order:
1. `import` declarations (trigger module loading)
2. `open` declarations (inject bare names into scope)
3. `export` declaration (restrict visibility to importers)
4. `type`, `def-interface`, `def-logic`, `letrec`, `check` declarations

### 8.4 Cycle Detection

Circular imports are a **compile error**. The compiler performs a DFS-based cycle check before loading any module. The diagnostic names the full cycle:

```json
{
  "kind":    "circular-import",
  "cycle":   ["foo.bar", "foo.baz", "foo.bar"],
  "message": "Circular import detected: foo.bar → foo.baz → foo.bar"
}
```

### 8.5 Namespace Resolution (Current Behavior)

`(import foo)` triggers DFS file loading and seeds the type-checker with **qualified names only** (`foo.f`, `foo.g`). Codegen concatenates all imported module statements into a single flat `Lib.hs` with bare Haskell names.

To call imported functions, use `(open foo)` to inject bare aliases into the type-checker's scope, then call with bare names:

```lisp
(import app.auth)
(open app.auth)                  ;; inject bare aliases for all exports

;; Call with bare name:
(hash-password raw-str)
```

The usable pattern is: **`import` → `open` → bare call.**

Qualified references (`app.auth.hash-password`) are accepted by the type-checker but **fail at codegen** — the flat `Lib.hs` emits bare Haskell names, not qualified ones.

> [!NOTE]
> **Loader permissiveness.** The DFS module loader uses permissive typechecking for
> imported modules — unbound bare names produce warnings, not errors. The entry-point
> file is checked with strict typechecking during `llmll build`. This asymmetry means
> imported modules may omit `(open ...)` declarations and still load successfully,
> but the entry-point file must include them.

#### 8.5.1 Qualified Access (Planned — Not Shipped)

The language design supports fully qualified access as the default namespace model:

```lisp
;; PLANNED (not currently operational at codegen):
(app.auth.hash-password raw-str)
```

This will become operational when codegen emits per-module Haskell files with proper qualified imports, replacing the current single-`Lib.hs` concatenation model.

### 8.6 `open` — Bare-Name Injection

`(open path)` injects a module's exported names into the current scope as bare names. This is **required** for calling imported functions under strict typechecking (used by `llmll build`). An optional name list restricts which names are injected:

```lisp
(open app.auth)                  ;; all exports as bare names
(open app.auth (hash-password))  ;; only hash-password as a bare name
```

`open` is a compile-time alias injection — it makes the type-checker aware of bare names. Codegen is unaffected (bare names already exist in the concatenated `Lib.hs`).

`(import A)` alone loads module A's definitions into `Lib.hs` but does **not** make them accessible by bare name in the type-checker. Without `(open A)`, only qualified names (`A.f`) are in scope, and qualified names do not resolve at runtime under the current flat-codegen model.

> **Collision policy:** If two `(open ...)` declarations export the same bare name, the second `open` wins (last wins). The compiler emits a `WARNING` diagnostic.

> **Property-based testing.** The PBT static evaluator used by `llmll test` honors the same bare-name injection rule: a `(check ...)` block whose body calls an imported function evaluates only when the imported module is in bare-name scope via `(open ...)`. Without `open`, the property body cannot reduce to a literal Bool and `llmll test` reports the check as `Skipped`. Qualified references (`module.fn ...`) inside check bodies share the codegen limitation described in §8.5.1 and currently do not resolve at runtime.

### 8.7 `export` — Visibility Control

```lisp
(export hash-password verify-token)   ;; only these two names visible externally
```

If no `export` declaration is present, **all** top-level `def-logic`, `type`, `def-interface`, and `gen` declarations are exported (open default). `check` and `def-invariant` blocks are **never exported**.

The `export` declaration must appear before the first `def-logic`.

> [!NOTE]
> **Export enforcement scope.** Export control is enforced at compile time during
> `llmll build` (which uses strict typechecking). Permissive `llmll check` reports
> unexported-name access as warnings, not errors.
>
> The generated `Lib.hs` contains all definitions from all imported modules, including
> unexported ones, because exported functions may depend on private helpers and type
> aliases. True codegen-level hiding requires per-module Haskell file emission with
> Haskell `module` export lists, planned for a future release.

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

### 8.8.1 Algebraic Laws for Interfaces (`:laws`)

Interfaces can declare **algebraic laws** that any conforming implementation must satisfy. Laws are `(for-all ...)` properties attached to a `def-interface` via the `:laws` clause. The compiler type-checks law expressions with interface methods and bindings in scope, and generates QuickCheck `prop_` functions for automated enforcement.

```lisp
;; Idempotent normalizer: normalizing twice is the same as normalizing once
(def-interface Normalizer
  [normalize (fn [x: string] -> string)]
  :laws [(for-all [x: string] (= (normalize (normalize x)) (normalize x)))])

;; Monoid laws: identity and associativity
(def-interface Monoid
  [mempty   string]
  [mappend  (fn [a: string b: string] -> string)]
  :laws [(for-all [x: string] (= (mappend mempty x) x))
         (for-all [x: string] (= (mappend x mempty) x))
         (for-all [a: string b: string c: string]
           (= (mappend (mappend a b) c) (mappend a (mappend b c))))])
```

**Syntax:** `:laws` is an optional clause after the method list. It contains a list of `(for-all [bindings] expr)` properties. Each `for-all` binding follows standard typed-parameter syntax.

**Type checking:** Law expressions are type-checked in a scope where all interface methods are available as bound variables. The `for-all` bindings are added to this scope. The body expression must have type `bool`.

**Codegen:** Each law property generates a QuickCheck `prop_` function in the emitted Haskell. The properties are wired into `runPropertyTests` and appear as a separate "Interface laws" section in `--spec-coverage` reports.

**JSON-AST:** Laws are represented as an array of property objects in the `def-interface` node. `parseLawProperty` and `AstEmit.hs` law emission ensure round-trip compatibility.

```json
{
  "kind": "def-interface",
  "name": "Normalizer",
  "methods": [
    { "name": "normalize", "type": { "kind": "fn-type", "params": [{"name": "x", "param_type": {"kind": "primitive", "name": "string"}}], "return_type": {"kind": "primitive", "name": "string"} } }
  ],
  "laws": [
    { "kind": "for-all",
      "bindings": [{"name": "x", "param_type": {"kind": "primitive", "name": "string"}}],
      "body": { "kind": "app", "fn": "=", "args": [
        { "kind": "app", "fn": "normalize", "args": [{ "kind": "app", "fn": "normalize", "args": [{ "kind": "var", "name": "x" }] }] },
        { "kind": "app", "fn": "normalize", "args": [{ "kind": "var", "name": "x" }] }
      ] }
    }
  ]
}
```

Omitting `:laws` is valid — interfaces without laws parse and compile unchanged.

> [!NOTE]
> **Cross-module contract metadata (v0.10, shipped).** `ModuleEnv` now stores per-function
> contract metadata via `meContracts :: Map Name ([(Name, Type)], Contract, Maybe Type)`,
> populated from `buildModuleEnv`. This enables cross-module compositional verification
> and obligation reports that reference imported contracts. See MOD-1 in
> [`CHANGELOG.md`](CHANGELOG.md).

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

The `hub.` prefix prevents local files from accidentally shadowing registry packages. Publishing, semantic versioning beyond `major.minor.patch`, and a web registry API are deferred (not version-pinned).

Modules declared in `llmll-hub` include verified proof metadata and are importable by name. Third-party modules must be explicitly wrapped (§7).

> [!NOTE]
> Hub-cached modules (both `.llmll` and `.ast.json`) inherit the invoking command's
> grammar mode per §8.2. Hub publishers must ship `def`/`def-shell` node kinds.

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
(def-logic handle-request [state: AppState request: string]
  (if (string-contains request "/valid")
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

### 9.6 `do`-notation State Threading

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
- **Compilation:** The `do` block is compiled directly into a pure `let` chain. No Haskell `do` or monads are emitted, ensuring soundness in `def-logic` pure contexts. Each step's `(State, Command)` pair is destructured via `let`; the final result is `(lastState, lastCommand)`.
- **Intermediate commands are silently discarded by default.** Non-final steps' `Command` components are bound but not executed unless explicitly wrapped in `seq-commands` (see §9.3) or the future `(discard cmd)` marker (post-v0.11). This is a known surprise relative to monadic `do`-notation in other languages where the point of sequencing is to execute effects in order. **In LLMLL `def-logic`, effects are values, not statements; sequencing them is the agent's explicit responsibility.** Generated code that looks effectful can silently drop effects unless the agent uses `seq-commands` or returns the intermediate `Command` value in the final tuple. This will tighten in v0.11+ to a warn-or-error on non-final `Command`-typed binds without explicit-discard wrapping; the syntactic surface is preserved during the warning phase.

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
7. **Sandboxed Execution:** The binary runs inside a Docker container with `seccomp-bpf` syscall filtering and filesystem/network policies derived from the module’s declared capabilities. WASM-WASI is planned as a future replacement.
8. **Event-Log Replay:** The runtime records a sequenced Event Log of `(Input, CommandResult, captures)` triples (see §10a). Replay is bitwise deterministic for all modules that use `:deterministic true` capability flags on clock and PRNG imports.



---

## 10a. Event Log Specification

Correct replay is the foundation of fault tolerance, audit trails, and SMT proof validation over execution traces.

### Sources of Non-Determinism

| Source | Problem | Runtime Fix |
|--------|---------|-------------|
| **IEEE 754 floats** | NaN canonicalization differs across host platforms | Reject non-canonical floats at the sandbox boundary (GHC NaN rules in v0.1.2–v0.6.0; `wasm-determinism` extension with WASM target) |
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
                     (on-failure (err DelegationError)))]]
    (db.insert user hashed-pw)))
```

Without `(on-failure ...)`, an unresolved delegation becomes a `?delegate-pending` hole — analyzable but not executable:

```lisp
hashed-pw (?delegate @crypto-agent "Implement PBKDF2 hashing" -> bytes[64])
;; Compiler: ?delegate-pending [type: bytes[64]] [agent: @crypto-agent]
```

#### Async Delegation

`?delegate-async` returns `Promise[t]` immediately and continues. The module runtime resolves the promise when the agent completes.

`return_type` is the inner type `T`, not `Promise[T]`. The compiler wraps it in `Promise[T]` automatically. A top-level `Promise[...]` in `return_type` is stripped as a legacy compatibility measure. `Promise[Promise[T]]` is a parse error.

**`await` returns `Result[t, DelegationError]`, not bare `t`.** The generated code wraps `Async.wait` in exception handling so that agent failures (crash, timeout, type mismatch) are captured as `Error` values carrying a `DelegationError` payload (constructed via `(err …)`; see §13.8) rather than propagating as uncaught exceptions. This preserves the LLMLL invariant that logic functions cannot crash from IO.

**Inference rules:**

```
?delegate @A "desc" -> T                    ⊢  T
?delegate @A "desc" -> T (on-failure e)     ⊢  T,  given Γ ⊢ e : T
?delegate-async @A "desc" -> T              ⊢  Promise[T]
await e : Promise[T]                         ⊢  Result[T, DelegationError]
```

The `(on-failure e)` rule's `Γ ⊢ e : T` side condition is enforced by `compiler/src/LLMLL/TypeCheck.hs` `inferHole HDelegate` (v0.10.2+). Ill-typed fallbacks (e.g., a `string`-returning fallback on an `int`-returning delegate) produce a typecheck error.

**Delegate return type vs interface method signature.** The `?delegate ... -> T` return type is determined at the delegation site, not by any `def-interface` method the agent identifier might also satisfy. A `def-interface` declares the agent's contract surface; a `?delegate` is a placeholder for a value of type `T` to be supplied at the delegation site. The two are linked by the agent identifier (`@agent-name`), not by syntactic return-type equality — the agent may produce a `T` shaped differently than any specific interface method's signature, and the typechecker checks only the local `?delegate -> T` and the `Γ ⊢ e : T` side condition on the fallback.

**JSON-AST `agent` field convention.** In JSON-AST, the `agent` field of `hole-delegate` / `hole-delegate-async` stores the **bare agent identifier without the `@` sigil**. The `@` is surface S-expression syntax (and `llmll holes` display-time rendering); it is not part of the stored identifier in the typed AST or the JSON. Example: surface `?delegate @crypto-agent ...` corresponds to JSON-AST `"agent": "crypto-agent"`.

```lisp
(def-logic build-report [state: AppState data: ReportData]
  (let [[chart-future (?delegate-async @viz-agent
                         "Render a bar chart from data"
                         -> ImageBytes)]]
    (let [[chart-result (await chart-future)]]
      (match chart-result
        ((Success img) (pair state (wasi.http.response 200 img)))
        ((Error err)   (pair state (wasi.http.response 500 "Agent failed"))))))))
```

> [!IMPORTANT]
> **Type of `await`:** `await : Promise[t] -> Result[t, DelegationError]`. The type checker infers `Result[t, DelegationError]` for any `(await expr)` where `expr : Promise[t]`. An un-`await`ed `Promise[t]` remains `Promise[t]`.



#### Delegation Outcome Table

| Scenario | Compiler Result |
|----------|----------------|
| Delegation succeeds, type matches | AST node replaced with implementation |
| Delegation succeeds, type mismatch | Compile error: `TypeMismatch` |
| Agent unavailable, `on-failure` provided | Fallback expression inserted |
| Agent unavailable, no `on-failure` | `?delegate-pending` hole — blocks execution |
| `?delegate-async`, agent succeeds | `await` returns a `Success` value (matched as `(Success v)`) |
| `?delegate-async`, agent fails | `await` returns an `Error` value carrying `DelegationError` (matched as `(Error e)`) |

#### Hole Resolution via JSON-Patch

`?delegate` holes can be resolved programmatically by agents through the **checkout/patch lifecycle**. This is the primary agent-coordination mechanism for filling holes without human intervention.

**Workflow:**

1. **Checkout.** An agent calls `llmll checkout <file.ast.json> <pointer>` to lock a hole. The compiler validates the RFC 6901 pointer resolves to a `hole-*` node, creates a lock entry in `.llmll-lock.json`, and returns a checkout token. The lock has a 1-hour TTL; stale locks are auto-expired.

2. **Patch.** The agent submits an RFC 6902 JSON-Patch wrapped in an LLMLL envelope containing the checkout token and patch operations:

```json
{
  "token": "a1b2c3d4...",
  "patch": [
    { "op": "test",    "path": "/statements/2/body", "value": { "kind": "hole-delegate", ... } },
    { "op": "replace", "path": "/statements/2/body", "value": { "kind": "lit-int", "value": 42 } }
  ]
}
```

3. **Re-verify.** The compiler applies the patch to the JSON-AST, re-parses, re-typechecks, and — if the function carries contracts — re-verifies via SMT (`emitFixpoint` + `liquid-fixpoint`). If the patch introduces a type error, the result is `PatchTypeError` with diagnostic pointers referencing the patch operation (e.g., `patch-op/1/body` instead of `/statements/2/body`). If the patch violates a contract, the result is `PatchVerifyError` with SMT diagnostics. If `liquid-fixpoint` is not installed, the patch proceeds on typecheck success alone (graceful degradation).

4. **Commit or reject.** On success (`PatchSuccess`) the updated `.ast.json` is written and the lock is cleared. On failure (`PatchTypeError`, `PatchVerifyError`, `PatchApplyError`, `PatchAuthError`) the original file is unchanged and the lock is preserved for retry.

**Scope containment:** All patch operations must target nodes within the checked-out subtree. A token for `/statements/2/body` cannot be used to modify `/statements/0/body` — this prevents lateral hole theft between agents.

**Supported RFC 6902 operations:** `replace`, `add`, `remove`, `test`. The `test` operation is the agent's guard against stale patches — it asserts that the hole hasn't been modified since checkout.

**CLI commands:**

| Command | Purpose |
|---------|---------|
| `llmll checkout <file.ast.json> <pointer>` | Lock a hole, get token |
| `llmll checkout --release <file> <token>` | Explicitly abandon a checkout |
| `llmll checkout --status <file> <token>` | Query remaining TTL |
| `llmll patch <file.ast.json> <patch.json>` | Apply patch + re-verify |

**HTTP endpoints** (via `llmll serve`): `POST /checkout`, `POST /checkout/release`, `POST /patch` — governed by the same bearer token auth as `POST /sketch`.

> Checkout requires `.ast.json` input. S-expression sources are rejected with: `"checkout requires .ast.json input; run 'llmll build --emit json-ast' first"`. Patches are restricted to hole-filling; general AST mutation is planned for a future release.

#### Context-Aware Checkout

`llmll checkout` returns the **local typing context** alongside the lock token. This is the single highest-impact feature for agent first-attempt accuracy — agents no longer need to infer what’s in scope from surrounding AST context.

The checkout response includes four optional fields (present when the compiler has sketch data for the target hole):

| Field | Type | Content |
|-------|------|---------|
| `in_scope` | `[ScopeEntry]` | Bindings visible at the hole site (Γ delta: `tcEnv \ builtinEnv`). Each entry has `name`, `type` (LLMLL notation), and `source` (`param`, `let-binding`, `match-arm`, `open-import`). Sorted by source priority; truncated at 50 entries with `scope_truncated: true`. |
| `expected_return_type` | `string` | The inferred return type at the hole site (τ as a type label). |
| `available_functions` | `[FuncEntry]` | Non-`wasi.*` function signatures (Σ), monomorphized against concrete scope types. E.g., when `xs : list[int]` is in scope, `list-head` appears as `list[int] → Result[int, string]` rather than `list[a] → Result[a, string]`. Each entry has `name`, `params` (with types), `returns`, and `status` (`filled`, `hole`, `builtin`). |
| `type_definitions` | `[TypeDefEntry]` | User-defined types referenced by in-scope bindings. Sum types include constructors; aliases include the base type. Depth-bounded expansion (max 5 levels) with cycle detection (`recursive: true`). |
| `scope_truncated` | `bool` | `true` if the scope was truncated to the 50-entry limit; absent or `false` otherwise. |

**Pointer normalization:** RFC 6901 pointer segments with leading zeros are normalized: `/statements/02/body` → `/statements/2/body`.

**Monomorphization:** Polymorphic signatures in `available_functions` are rewritten against concrete types found in the scope. This is a presentation-only transformation — the underlying `builtinEnv` is not mutated.

**Scope truncation:** When the in-scope binding count exceeds the limit, entries are retained by source priority: `param` > `let-binding` > `match-arm` > `open-import`. Shadowing safety is structurally guaranteed by the single-entry-per-key invariant of the scope map.

### 11.3 AST-Level Merging (Semantic Source Control)

> [!WARNING]
> **Designed, not yet implemented.** The following describes planned behavior for a future release. The current compiler does not implement AST-level merging beyond the JSON-Patch hole-filling pipeline of §11.2.

The design envisions that `llmll` will bypass text-based merge conflicts by operating exclusively on the AST:

- **Concurrent additions:** Agent A adds a function + Agent B adds a type → the compiler will merge tree nodes seamlessly.
- **Logical conflicts:** Two agents redefine the same node incompatibly → the compiler is designed to generate a `?conflict-resolution` hole and flag the Lead AI. No `<<<< HEAD` markers.

The current module system provides `mergeModuleEnvs` (name unification across imports) and `mergeCS` (evidence-record reconciliation) in [`Module.hs`](compiler/src/LLMLL/Module.hs), but there is no `?conflict-resolution` hole generator or general AST-merge mechanism.

### 11.4 Global Module Invariants (`def-invariant`)

> [!WARNING]
> **Designed, not yet implemented.** `def-invariant` is parsed (reduced to `SDefLogic`) but semantic enforcement is deferred. Z3 invariant verification on merge is not yet implemented.

A module can declare invariants that must hold over its state at all times:

```lisp
(def-invariant balance-conservation [state: LedgerState]
  (= (sum (map-values (state-accounts state)))
     (state-total-supply state)))
```

The design intent is that after any AST merge, the compiler will run Z3 verification of all declared invariants. A merge that breaks a global invariant would be rejected before it can produce runnable code. This is not yet implemented — the `def-invariant` form is accepted by the parser but has no runtime or verification effect.

---

## 12. Formal Grammar Reference

The grammar is given in EBNF. `{ x }` means zero or more `x`. `[ x ]` means optional `x`. `( x | y )` means a choice. Terminals are in `"double quotes"`. All source files must be **ASCII-only**.

```ebnf
(* ============================================================ *)
(* Top-level structure                                           *)
(* ============================================================ *)
program     = { statement } ;
statement   = type-decl | gen-decl | weakness-ok | def-logic | def | def-shell
            | def-interface | def-invariant | def-main | module-decl | import
            | open-decl | export-decl              (* NEW in v0.2 *)
            | trust-decl                            (* NEW in v0.3 *)
            | check | expr ;
              (* def / def-shell available only under --grammar=core-inversion;
                 def-logic / letrec unavailable under --grammar=core-inversion
                 (core-grammar-violation diagnostic + exit non-zero)             *)

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
(* Trust declarations — NEW in v0.3 (§4.4.3)                    *)
(* ============================================================ *)
trust-decl  = "(" "trust" qual-ident ":level" TRUST_LEVEL ")" ;
TRUST_LEVEL = "verified" | "contract-checked" | "tested" | "asserted" ;
              (* Acknowledges an unproven contract from an imported function.    *)
              (* Per-function, multiple per module. Idempotent (duplicates OK).  *)
              (* Must appear before any def-logic (same ordering as import).     *)

(* ============================================================ *)
(* Types                                                         *)
(* ============================================================ *)
type-decl   = "(" "type" IDENT type-body ")" ;

type-body   = where-type                             (* refinement type alias *)
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
                [ entropy-clause ]                  (* NEW in v0.11 LT-CDP *)
                expr
              ")" ;

typed-param    = IDENT ":" type ;
pre-clause     = "(" "pre"  expr [ ":source" STRING ] ")" ;
post-clause    = "(" "post" expr [ ":source" STRING ] ")" ;
entropy-clause = "(" "spec-entropy" SPEC_ENTROPY ")" ;
SPEC_ENTROPY   = ":strict" | ":intentional" | ":unknown" ;
                  (* LT-CDP v0.11: optional per-contract annotation; defaults to *)
                  (* :strict when absent. :intentional suppresses the low-DP     *)
                  (* diagnostic per §4.4.6. The parser also accepts the clause  *)
                  (* on `letrec`. Unknown labels are a parse error.             *)

(* ============================================================ *)
(* Core/shell grammar — GrammarCoreInversion is the default (v0.11 LT-INV; CE-3, EL-5 gate confirmed 2026-05-30) *)
(* Pass --grammar=legacy to parse v0.10 def-logic / letrec programs. *)
(* ============================================================ *)
def          = "(" "def"       IDENT "[" { typed-param } "]"
                 [ pre-clause ] [ post-clause ] [ entropy-clause ]
                 core-expr
               ")" ;
                 (* Strict-core: body must satisfy isCoreBodySyntactic.         *)
                 (* Callee admission at EApp: body-faithful evidence, OR        *)
                 (* trustedPrelude membership, OR builtinEnv membership.        *)

def-shell    = "(" "def-shell" IDENT "[" { typed-param } "]"
                 [ pre-clause ] [ post-clause ] [ entropy-clause ]
                 expr
               ")" ;
                 (* Permissive form: no body restriction; no callee check.      *)

core-expr    = literal | var | let | if | match | app | linear-op-expr | hole ;
                 (* Excluded: lambda, do, pair, await, non-linear ops.         *)

linear-op-expr = "(" ( "+" | "-" | "=" | "<" | "<=" | ">" | ">=" | "!=" )
                     expr expr { expr } ")" ;

(* ============================================================ *)
(* Interfaces                                                    *)
(* ============================================================ *)
def-interface = "(" "def-interface" IDENT { iface-fn }
                  [ ":laws" "[" { for-all } "]" ]
                ")" ;
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
check       = "(" "check" STRING [ subject-meta ] for-all ")" ;
subject-meta = ":subject" IDENT
             | ":subjects" "[" IDENT { IDENT } "]" ;
              (* Optional v0.10.6+ explicit-attribution clause; see Rule 10. *)
for-all     = "(" "for-all" "[" { typed-param } "]" expr ")" ;

gen-decl    = "(" "gen" IDENT expr ")" ;
              (* expr must have the base type of the named refinement type *)

weakness-ok = "(" "weakness-ok" IDENT STRING ")" ;
              (* Suppression governance — see §4.5.                        *)
              (* STRING is a non-empty reason for the suppression.         *)

(* ============================================================ *)
(* Expressions                                                   *)
(* ============================================================ *)
expr        = literal | var | let | if | match | app | qual-app
            | op | pair | await | do | lambda | hole ;

literal     = INT | "-" INT | FLOAT | STRING | "true" | "false" ;
              (* Negative integers: '-' immediately precedes digits with no whitespace *)
var         = IDENT ;

(* let is SEQUENTIAL: each binding is in scope for all subsequent bindings *)
(* PR 4: binding head is now a pattern, not just an identifier.           *)
let         = "(" "let" "[" { let-binding } "]" expr ")" ;
let-binding = "(" pattern expr ")"          (* v0.1.2 canonical form *)
            | "[" pattern expr "]" ;        (* v0.1.1 legacy form — also accepted *)
              (* Example: (let [(x 1) (y (+ x 1))] y)  => 2 (simple vars)         *)
              (* Example: (let [((pair s cmd) (authenticate state cred))] ...)      *)

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
            | "?" "delegate-async" "@" IDENT STRING ARROW type ;  (* async delegate; type is inner T, not Promise[T] *)

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

5. **`let` bindings are sequential.** Each binding sees all previous bindings. The current syntax is `(let [(x 1) (y (+ x 1))] y)` (evaluates to `2`). The double-bracket form `(let [[x 1] [y 2]] ...)` is also accepted and equivalent — both forms compile to identical AST nodes. The binding head may be a `pattern` instead of a simple identifier, enabling pair destructuring: `(let [((pair s cmd) expr)] ...)`. In JSON-AST, use `"pattern"` instead of `"name"` in the let-binding object.
6. **`match` must be exhaustive.** Use `_` as the final arm if not all cases are covered explicitly. A `match` without `_` that fails at runtime raises `MatchFailure`.
7. **`result` is reserved** inside `post` clauses. Do not use it as a variable or parameter name anywhere.
8. **Named parameters in `fn-type` are doc-only.** `(fn [raw: string] -> bytes[64])` and `(fn [string] -> bytes[64])` are type-equivalent.
9. **JSON-AST identifier shape is schema-enforced** (schema version `0.4.0`, v0.10.2+). The JSON-AST schema at `docs/llmll-ast.schema.json` enforces:
   - `ExprApp.fn` matches `^[^.]+$` — no dots permitted in plain function-call position. The character class is intentionally permissive to accept operator identifiers (`+`, `-`, `<=`, `mod`, etc.) that may appear in `app` position when emitted by JSON-AST agents that do not partition operators into `EOp`.
   - `ExprQualApp.qual_fn` matches `^[A-Za-z_][A-Za-z0-9_?\-]*(\.[A-Za-z_][A-Za-z0-9_?\-]*)+$` — at least one dot required, character class matches `IDENT` per §2.1. This formalizes the `qual-ident = IDENT { "." IDENT }` EBNF rule above.
   Schema-level rejection happens before parser entry; the typechecker also emits a warning on dotted `app.fn` for S-expression sources where the schema is not consulted (`compiler/src/LLMLL/TypeCheck.hs` `inferExpr`, v0.10.2+).
10. **`check` may carry explicit subject metadata** (v0.10.6+, schemaVersion `0.5.0`). The optional `subject-meta` clause between the label STRING and the `for-all` expresses agent intent to lift trust evidence per declared callee. `:subject f` is singleton sugar for `:subjects [f]`. The annotated branch bypasses the head-position scan rule and lifts trust evidence per declared subject (§4.4.5). Empty `:subjects []` is rejected at parse time; duplicate names are deduplicated; cross-module subjects qualify through the existing `qualMap`. JSON-AST encodes this via the optional `CheckDecl.subjects: [Name]` field at schemaVersion `0.5.0`. See §4.4.5 *Annotated-subject branch* for the PBT-Lift semantics and the joint-witness scalar-exclusion rule (OBLIG-PBT-5a, v0.10.7+).


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
| `pair` | `a b -> (a, b)` | Construct a 2-tuple (typed `TPair a b` internally) |
| `first` | `(a, b) -> a` | First projection — accepts any pair, including explicitly-annotated parameters |
| `second` | `(a, b) -> b` | Second projection — accepts any pair, including explicitly-annotated parameters |

> **Pair destructuring in `let` bindings.**
> `(let [((pair s cmd) (authenticate state cred))] ...)` destructures a pair result into `s` and `cmd`. Nested destructuring is supported: `(let [((pair word (pair g rest)) state)] ...)`. This works identically to pair patterns in `match` arms. In JSON-AST, use `"pattern"` instead of `"name"` in the let-binding object.

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
| `string-char-at` | `string int -> string` | Single character at index (as 1-char string). Returns `""` for negative or out-of-bounds indices (v0.7). |
| `string-split` | `string string -> list[string]` | Split on delimiter |
| `string-trim` | `string -> string` | Strip leading/trailing whitespace and newlines (`Space`, `\t`, `\n`, `\r`) |
| `string-concat-many` | `list[string] -> string` | Concatenate a list of strings (variadic join without separator) |
| `regex-match` | `string string -> bool` | POSIX ERE match via `regex-tdfa` (v0.7). Invalid patterns return `False` (total). Replaces `isInfixOf` stub. |
| `string-empty?` | `string -> bool` | True when string has length 0 |

> [!NOTE]
> **Class A indexing primitives — boundary trust closure (v0.11 LT-INT).** The indexing primitives `list-length`, `list-nth` (§13.5), `string-length`, `string-slice`, `string-char-at` (§13.6) keep concrete `Int` (`Int64`) signatures at the Haskell runtime layer per [`docs/design/int-2-boundary-shims.md`](docs/design/int-2-boundary-shims.md) §3.1; codegen inserts `fromIntegral` shims at the LLMLL-to-Haskell call seam at [`compiler/src/LLMLL/CodegenHs.hs:595-603`](compiler/src/LLMLL/CodegenHs.hs#L595-L603). The primitives assume the underlying Haskell representation fits in `Int64` — lists and strings whose length is at most `2⁶³ − 1 = 9_223_372_036_854_775_807` elements. Programs constructing collections beyond this bound are outside the builtin's input domain; the verification report does not cover their behavior. This is a sub-case of the existing FFI-builtin trust closure at §7.

### 13.7 Numeric Utilities

| Function | Signature | Notes |
|----------|-----------|-------|
| `int-to-string` | `int -> string` | Decimal representation |
| `string-to-int` | `string -> Result[int, string]` | Parse; `Error` on failure |
| `abs` | `int -> int` | Absolute value |
| `min` | `int int -> int` | Minimum |
| `max` | `int int -> int` | Maximum |

### 13.8 Result Helpers

| Function | Signature | Notes |
|----------|-----------|-------|
| `ok` | `a -> Result[a, e]` | Wrap in `Success` |
| `err` | `e -> Result[a, e]` | Wrap in `Error` |
| `is-ok` | `Result[a, e] -> bool` | `true` if `Success` |
| `unwrap` | `Result[a, e] -> a` | Extract value; raises `UnwrapError` on `Error` |
| `unwrap-or` | `Result[a, e] a -> a` | Default value on `Error` |

**The three layers of Result.**

LLMLL distinguishes three syntactic surfaces for `Result[t, e]` values, each with a distinct constructor name. AI agents must use the right surface in the right position; mixing them is a typecheck error.

| Layer | Surface | Where used | Compiler citation |
|-------|---------|------------|-------------------|
| **Construct** | `(ok x)`, `(err e)` | Expression position — function bodies, `on-failure` clauses, `let` RHS | `compiler/src/LLMLL/TypeCheck.hs` (`Result`-related builtins) |
| **Match** | `(Success v)`, `(Error e)` | `match`-arm pattern position only | `compiler/src/LLMLL/CodegenHs.hs` (rewrites to Haskell `Right`/`Left`) |
| **Test** | `(is-ok x)` | Boolean test in expression position | `compiler/src/LLMLL/TypeCheck.hs` |

`Result.Ok` and `Result.Error` are **not** registered constructor names. They were tolerated in v0.10.1 because the typechecker did not visit `?delegate`'s `on-failure` expression (fixed in v0.10.2). Use `(ok x)` and `(err e)` for construction and `(Success v)` / `(Error e)` for match arms.

```lisp
;; Construct
(def-logic safe-divide [a: int b: int]
  (if (= b 0) (err "division by zero") (ok (/ a b))))

;; Match
(match (safe-divide x y)
  ((Success q)  q)
  ((Error  msg) -1))

;; Test
(if (is-ok (safe-divide x y)) "ok" "fail")
```

**`?proof-required` for Result-returning contracts.**

When a contract on a Result-returning function asserts a property the verifier cannot discharge — typically because the postcondition involves a delegated call, nonlinear arithmetic, or map invariants — mark the contract clause `?proof-required` rather than weakening the spec or relying on `(weakness-ok ...)`. The marker promotes the obligation to the trust channel as `asserted` (per §5.3.5 verification matrix), records the gap in the trust report, and surfaces a structured hole to the obligation report. Agents receive credit for declaring the obligation; weakening the spec to silence the verifier is an anti-pattern.

```lisp
(def-logic verify-token [token: string]
  ;; Postcondition intent: result is Success or `err "invalid"`.
  ;; The predicate is non-linear (depends on the delegated body),
  ;; so the verifier cannot discharge it. Marker emitted; trust=asserted.
  (post ?proof-required)
  (?delegate @auth-agent "verify the token" -> Result[Claims, string]
    (on-failure (err "invalid"))))
```

**Bare-leaf form** (used in the example above): `?proof-required` records that the clause is outside the verifier's decidable fragment without embedding the predicate. In JSON-AST: `{"kind": "hole-proof-required", "reason": "non-linear-contract"}`. The intended predicate is documented in the surrounding source comment or trust-report annotation. Trust tier: `asserted`. See §6.

**Predicate-carrying form (LT-PPR, v0.11):** `(?proof-required :reason "non-linear-contract" pred-expr)` in `pre`/`post` position embeds the predicate and emits a Haskell runtime assertion at codegen. In JSON-AST: `{"kind": "hole-proof-required", "reason": "non-linear-contract", "predicate": { "kind": "op", "op": ">=", "args": [{"kind": "var", "name": "result"}, {"kind": "lit-int", "value": 0}] }}`. Non-linear predicates also emit a `QF-LIA` warning at `llmll check`.

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

### 13.11a Building Services (FAQ)

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

### 13.11 Cryptographic Operations

Cryptographic builtins are **opaque primitives** — the compiler does not attempt to verify their correctness. Their results are classified as `asserted` in the trust report. Downstream contracts that depend on these builtins are capped at the `asserted` verification level.

| Function | Signature | RFC Reference | Notes |
|----------|-----------|---------------|-------|
| `hmac-sha1` | `bytes[20] bytes[20] → bytes[20]` | RFC 2104 (HMAC) | Key and message are both `bytes[20]`. Returns 20-byte MAC. |
| `sha1` | `bytes[20] → bytes[20]` | FIPS 180-4 (SHA-1) | Input is `bytes[20]`, output is 20-byte hash. |

> [!IMPORTANT]
> **Implementation note:** The preamble SHA-1 implementation in `CodegenHs.hs` is a **simplified stub** (polynomial hash, not a faithful SHA-1). The trust report correctly classifies all functions depending on these builtins as `asserted`. For production use, replace the preamble with a real Haskell crypto library (`crypton` or `cryptohash-sha1`). The comment at `CodegenHs.hs` line 370 marks this.

> [!NOTE]
> **Extensible namespace.** `§13.11` is designed as an extensible section. Future builtins (`sha256`, `aes-128-cbc`, etc.) follow the same pattern: opaque primitive with concrete `bytes[N]` types, backed by a real Haskell crypto library in the preamble. Variable-length byte types (`bytes` without a length parameter) are deferred to v0.7.

> [!IMPORTANT]
> **Stub-backend trust-tier annotation.** Distribution builds intended for production use **must** replace the preamble `sha1` / `hmac-sha1` stub at `CodegenHs.hs:370-383` with a verified crypto backend (`crypton` or `cryptohash-sha1`). The trust report annotates dependencies on these builtins as `asserted-with-stub-backend` until backend replacement is verified — a machine-readable signal distinguishing "asserted because the algorithm is opaque" (the diamond-lattice `asserted` tier per §4.4.1) from "asserted with a known-incorrect runtime implementation" (the additional stub-backend caveat). The symbols `sha1` and `hmac-sha1` retain their RFC 2104 / FIPS 180-4 contract names — they are not renamed to `sha1_stub` — because the contract is the standards specification; the stub status is an implementation defect documented in the trust report for downstream consumer transparency.

**Usage in TOTP benchmark:**

```lisp
(def-logic hmac-sha1-wrap [key: bytes[20] msg: bytes[20]]
  :source "RFC 2104"
  (hmac-sha1 key msg))

(weakness-ok hmac-sha1-wrap "wrapper around opaque crypto primitive")
```

The `weakness-ok` declaration acknowledges that the wrapper has no meaningful contract — its correctness rests entirely on the axiomatically assumed `hmac-sha1` builtin.

---
