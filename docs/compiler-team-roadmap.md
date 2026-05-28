# LLMLL Compiler Team Implementation Roadmap

> **Status:** Active — see [`../CHANGELOG.md`](../CHANGELOG.md) `## Latest` for shipped version (canonical per DOC-CONSOLIDATE P1; this header no longer version-stamps).  
> **Source documents:** `LLMLL.md` · `consolidated-proposals.md` · `proposal-haskell-target.md` · `analysis-leanstral.md` · `design-team-assessment.md` · `proposal-review-compiler-team.md` · Professor's five-round review (2026-04-30)
>
> **Governing design criterion:** Every compiler deliverable is evaluated against *progress toward one-shot correctness* — does this release reduce the iteration burden, increase obligation completeness, or shorten the repair distance for an AI agent producing LLMLL code? The intended terminal state is that an agent writes a program once, the compiler accepts it, contracts verify.
>
> We measure progress toward that state empirically, including via repair-loop experiments where the verification surface's iteration aid is the dependent variable. First-round measurement is one such empirical regime; it is not the only one, and it is not load-bearing for every feature. See [`docs/design/empirical-methodology.md`](design/empirical-methodology.md) for the diagnosis and rationale.
>
> **Relationship to `LLMLL.md §14`:** The two documents are **complementary, not competing**. `LLMLL.md §14` is the *language-visible feature list* (what users and AI agents see). This document is the *engineering backlog* — implementation tickets, acceptance criteria, decision records, and bug tracking. When a feature ships it is marked complete here and the user-visible description is kept in `LLMLL.md §14`.

---

## Versioning Conventions

- Items marked **[CT]** are compiler team implementation tasks.
- Items marked **[SPEC]** are language specification changes that must land in `LLMLL.md` before or alongside the implementation.
- Items marked **[DESIGN]** are design decisions resolved by the joint team, recorded here as implementation constraints.

---

## Table of contents (DOC-CONSOLIDATE M5 small-cut)

- [Upcoming Releases](#upcoming-releases) (high-churn)
- [Active Items](#active-items) (high-churn — nested under Cross-cutting concerns)
- [Feature Freeze Policy](#feature-freeze-policy) (low-churn)
- [Cross-cutting concerns](#cross-cutting-concerns) (low-churn)
- [Summary: Version Plan and Critical Path](#summary-version-plan-and-critical-path)
- [Shipped Releases](#shipped-releases) (append-only)

> Skills deep-link into these anchors per `docs/UPDATE-PROTOCOL.md` §3.1. Larger M5 cut (extracting Shipped Releases to `docs/archive/roadmap-history.md`) deferred until in-file Shipped history crosses ~500 lines.

---

## Upcoming Releases

> **Roadmap reorganization (2026-04-30):** Professor's five-round review identified that the old v0.8.1 was entirely blocked on external availability (`lean-lsp-mcp`). Replaced with three actionable milestones: v0.8.1a (documentation boundary clarity), v0.8.1b (evidence model refactor), v0.9 (compositional verification). Feature freeze active through v0.9. LEAN-GA, TRUST-2b, MCP moved to externally-blocked parking lot. Research items in [research-track.md](research-track.md).

---

## Feature Freeze Policy

> [!IMPORTANT]
> **Original freeze (v0.8.1a through v0.10) — concluded with v0.10.6 ship.** Preserved as historical record. The freeze constrained the project to narrowing the verification boundary and deepening the obligation-feedback architecture rather than expanding the language surface, on the rationale that each unverified feature is a semantic escape hatch. Source: Professor's five-round review (2026-04-30), extended 2026-05-01.

> [!IMPORTANT]
> **Freeze lifted for v0.11 (architectural correction).** The freeze-exception soundness argument: v0.11's core/shell grammar inversion *narrows* the verification surface by making the verified-core fragment syntactically canonical rather than reachable through a CLI flag; CDP-0 (contract discriminative power as first-class evidence axis) and predicate-carrying `?proof-required` are evidence-channel enrichments without new escape hatches; LT-INT (`int` = mathematical integer, `Integer` backend) closes the documented Z3-Int-vs-Haskell-Int64 misalignment rather than introducing a new surface. See [`docs/design/core-shell-inversion-direction.md`](design/core-shell-inversion-direction.md) §Background for the full rationale and the no-backward-compat-shim position; [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) for the underlying external-critique adjudication.
>
> **Source:** Professor direction memo (2026-05-23) consolidating external critique (2026-05-23) into v0.11 routing; consensus of language team and professor. Original freeze (v0.8.1a–v0.10) preserved above as historical record.


---


## v0.10 — Obligation-Guided Agent Coding ✅ SHIPPED

**Theme:** Make LLMLL's obligation reports the clearest machine-readable goal state for code synthesis. Aim for the Idris workflow *feel* (goal-directed construction from rich obligations) without the Idris type-system *architecture* (indexed types, GADTs, dependent elimination).

**Effort:** ~5–7 days.

> **Source:** Professor's review (2026-05-01). Consensus: the highest-value part of "type-driven development" is not indexed types — it is exposing structured obligations to agents. LLMLL combines three independent feedback channels (type obligations, contract obligations, trust obligations) into a single agent loop. No other agent-facing system integrates all three.

> [!IMPORTANT]
> **Indexed types are NOT in scope for v0.10.** `Vect n a`, state-indexed commands, dependent pattern matching, type-level arithmetic, GADTs, and full Idris-style elaboration remain in the research track. v0.10 achieves 80% of the agent-facing benefit of Idris-style development through richer obligation reporting, without requiring changes to Algorithm W or the core type inference engine.

### Structured Obligation Report

The primary artifact is a structured JSON obligation report for every hole or failed verification step:

```json
{
  "kind": "hole-obligation",
  "hole": "?h3",
  "function": "withdraw",
  "expected_type": "int",
  "contract_context": {
    "preconditions": ["(>= balance amount)", "(> amount 0)"],
    "postcondition_goal": "(>= result 0)"
  },
  "path_condition": ["(>= balance amount)"],
  "in_scope": { "balance": "int", "amount": "int" },
  "available_functions": ["safe_subtract", "max", "min"],
  "assumptions": [{ "name": "int-minus", "kind": "runtime-primitive" }],
  "suggestions": [{
    "expression": "(- balance amount)",
    "reason": "satisfies non-negative result under current precondition"
  }]
}
```

This is the thing an agent can actually use. Three obligation channels:

| Channel | Question answered | Source |
|---|---|---|
| **Type obligations** | What shape must this expression have? | Type checker (`--sketch`) |
| **Contract obligations** | What logical property must it satisfy? | Verifier (liquid-fixpoint) |
| **Trust obligations** | What evidence is still missing? | Trust report (v0.8.1b evidence model) |

### Implementation Items

| # | ID | Description | Prerequisite | Status |
|---|-----|-------------|-------------|--------|
| 1 | **OBLIG-0** | **[DESIGN]** Design spec: obligation report JSON schema, enriched typed holes (expected type + contract context + path condition + assumption set), `EMatch` branch obligation encoding, repair suggestion generation, benchmark suite definition. | COMP-0 | ☑ |
| 2 | **MOD-1** | **[CT]** Cross-module `ContractEnv`: add `meContracts :: Map Name ([(Name, Type)], Contract)` field to `ModuleEnv` in `Syntax.hs`. Populate from `buildModuleEnv`. Wire into `ContractEnv` construction for imported modules. Extend `ctVerifiedHash` staleness guard to hash all imported `.verified.json` files (OBLIG-0 §5.3 Rev 6 Finding 3). Required for cross-module obligation reports (OBLIG-2/3). See `TODO(v0.10)` in `Syntax.hs:530`. | COMP-1 | ☑ |
| 3 | **OBLIG-1** | **[CT]** Enriched typed holes: extend `CheckoutToken` to include contract preconditions, postcondition goal, path condition, assumption set, source/evidence hashes for staleness detection. New fields emitted unconditionally on `llmll checkout` (no extra flag). | OBLIG-0 | ☑ |
| 4 | **OBLIG-2** | **[CT]** Goal-state display: structured obligation report (JSON) for each `?hole`, each unproven contract clause, and each failed call-site precondition. Reuse v0.9 path-condition infrastructure (`FlatPath` guards from `bodyToPred`). | OBLIG-0, MOD-1, COMP-1 | ☑ |
| 5 | **OBLIG-3** | **[CT]** `EMatch` branch obligations: for each branch of a `match` on `Result`/sum types, emit a sub-obligation with per-branch context (constructor-refined bindings) and per-branch contract sub-goals. | OBLIG-0, MOD-1, COMP-3 | ☑ |
| 6 | **OBLIG-4** | **[CT]** Refinement-aware repair suggestions: `ObligationMining.hs` proposes concrete repairs — add guard before call, strengthen caller precondition, weaken callee precondition, choose candidate expression from in-scope terms that satisfy the postcondition goal. | OBLIG-2 | ☑ |
| 7 | **OBLIG-5** | **[CT]** Repair loop integration: `llmll verify --obligation-report` emits obligation reports; orchestrator consumes reports, patches, re-verifies. Trust report records final evidence. End-to-end pipeline test. | OBLIG-1, OBLIG-4 | ☑ |
| 8 | **OBLIG-B** | **[LT+CT]** Obligation quality benchmark suite: for a set of known programs with known holes, verify that the obligation report contains enough information for a mechanical repair procedure. Measures obligation *completeness*, not synthesis *capability*. | OBLIG-2 | ☑ |

### Obligation Quality Benchmark

The success metric for v0.10:

> *Can a simple repair loop fill common holes using only the structured obligation report, without hidden compiler knowledge?*

**Tier 1 — Arithmetic Candidates (gates OBLIG-4 initial)**

| Program | Hole | Required obligation fields | Expected candidate |
|---|---|---|---|
| `withdraw(balance, amount)` | body | expected type, path condition (`balance >= amount`), postcondition goal (`result >= 0`), in-scope vars | `(- balance amount)` |
| `double(n)` | body | expected type (`int`), postcondition (`result = n + n`), in-scope vars | `(+ n n)` |

**Tier 1 — Branch Obligations (gates OBLIG-3)**

| Program | Hole | Required obligation fields | Expected |
|---|---|---|---|
| `safe-first(xs)` | body | expected type (`Result[int, string]`), 2-arm branch obligations from `(match (list-head xs) ...)` | Branch obligations with `backing` derived from actual body VC emission (`"smt"` iff `body-post` constraints emitted) |

**Tier 2 — Conditional Synthesis (gates OBLIG-4 extension, deferred)**

| Program | Hole | Required obligation fields | Expected candidate |
|---|---|---|---|
| `clamp(value, lo, hi)` | body | expected type, two-branch path conditions | `(if (< value lo) lo (if (> value hi) hi value))` |
| `abs(n)` | body | expected type, postcondition goal (`result >= 0`), single branch split | `(if (< n 0) (- 0 n) n)` |

### Architectural Note: Path Conditions Bridge v0.9 → v0.10

`bodyToPred` (v0.9) already computes path conditions for each `EIf`/`EMatch` branch — they are the guards in each `FlatPath`. v0.10 re-exports these same path conditions to the agent via the obligation report. For hole-bearing functions (where `bodyToPredM` returns `Nothing`), a separate presentation-only guard-walker in `ObligationAssembly.hs` collects accumulated path conditions at each hole site (see OBLIG-0 spec §4.2.3).

**Acceptance criteria:**
- Obligation reports produced for all `?hole` sites, unproven contracts, and failed call-site preconditions
- Obligation reports contain all three channels: type, contract, trust
- `EMatch` branch obligations include per-branch context, sub-goals, and `backing` label (`"smt"` vs `"guidance"`)
- Repair suggestions include at least: strengthen pre, weaken callee pre, candidate expression (arithmetic Tier 1)
- Tier 1 benchmark passes (B1, B5, B3); Tier 2 benchmarks gate OBLIG-4 extension
- Orchestrator end-to-end test: obligations → patch → verify → trust report

---

## v0.11 — Core/Shell Inversion + Evidence-Axis Enrichment

**Theme:** Invert LLMLL's source-grammar polarity so the verified-core fragment is the canonical definition form and the permissive regime is explicitly marked. Pair the syntactic guarantee with an orthogonal spec-strength axis (contract discriminative power) and a richer escape-hatch (predicate-carrying `?proof-required`). Close the long-documented Z3-mathematical-Int vs Haskell-Int64 misalignment by committing `int` to mathematical-integer semantics with `Integer` backend.

**Effort:** Multi-week (LT-INV alone is the largest grammar change since v0.5's U-Full Soundness). Estimated 4–6 weeks engineer + experiment-lead time across all four LT items, sequenced per §8.4 below.

> **Source:** Professor v0.11 direction memo (Rev 2) at [`docs/design/core-shell-inversion-direction.md`](design/core-shell-inversion-direction.md), consolidating external critique (2026-05-23) processed through both the language-team and professor channels. Four LT proposals (LT-INV, LT-CDP, LT-PPR, LT-INT) settled in conversation 2026-05-23; design-doc drafts pending (see Implementation Items below). Two over-corrected memo footnotes (TC-EOP-1, OBLIG-PBT-5) adjudicated and resolved into v0.10.x patch lane, not v0.11.

> [!IMPORTANT]
> **v0.11 is a deliberate breaking change with no source-level backward-compatibility shim.** The freeze rationale through v0.10 was *narrow the verification boundary*; the v0.11 lift is a *correction* of the architectural default toward the same goal — the core/shell inversion makes the narrowing syntactic rather than flag-gated. Migration of `examples/*` from v0.10 `def-logic` to v0.11 `def` / `def-shell` is mechanical (per memo §1.5); the JSON-AST schema bumps `0.5.0 → 0.6.0`. No source-level compatibility shim is provided.

### Implementation Items

| # | ID | Description | Prerequisite | Status |
|---|-----|-------------|-------------|--------|
| 1 | **LT-INV** | **[LT+CT]** Core/shell grammar inversion. Rename `def-logic` → `def` for the strict-core form; introduce `def-shell` for the permissive form. Whitelist grammar production for core bodies (admitted: `ELit`, `EVar` int-typed, QF-LIA `EOp`, `ELet` PVar+int, `EIf` under path-limit, `EApp` to body-faithful callees, `EMatch` on `Result` 2-arm, refinement-aliased base-int types, `?hole`/`?name`/`?choose`/`?request-cap`/`?scaffold`/`?delegate`/`?delegate-async`). Excluded from core: `?proof-required`, `letrec`, general-ADT `EMatch`, `EPair`, `ELambda`, `EDo`, non-linear arithmetic, opaque crypto, untrusted FFI. Transitive body-faithful callee restriction at `EApp` inside `def`. Schema bump `0.5.0 → 0.6.0`. LT-proposal/review pair land at [`docs/design/core-shell-inversion-proposal.md`](design/core-shell-inversion-proposal.md) + `core-shell-inversion-review.md` (pending). | None | ☑ *(opt-in flag shipped; schema bump `0.5.0 → 0.6.0` + default flip to `GrammarCoreInversion` gated on §8 empirical-validation gate)* |
| 2 | **LT-CDP** | **[LT+CT]** Contract discriminative power as first-class evidence axis. Promotes [`docs/research-track.md:145-151`](research-track.md) to v0.11 implementation built on [`compiler/src/LLMLL/WeaknessCheck.hs`](../compiler/src/LLMLL/WeaknessCheck.hs). Two-axis assurance report — paired `(evidence, DP)` per function rather than collapsed scalar. Normalized score `DP_Ω(S) = 1 - log(|⟦S⟧_Ω|) / log(|B_{T,U,Ω}|)`. Optional `(spec-entropy :strict | :intentional | :unknown)` annotation honors the healthy-diversity-vs-underspecification tension at [`docs/design/invariant-discovery-review.md §4.1`](design/invariant-discovery-review.md). `trust_report_version` bump 1.1.0 → 1.2.0 (additive). Subsumes the prior triage rows DP-FORM-1 + TRUST-DP-1. LT-proposal/review pair land at [`docs/design/contract-discriminative-power-proposal.md`](design/contract-discriminative-power-proposal.md) + `-review.md` (pending). | LT-INV (sequenced after) | ☑ |
| 3 | **LT-PPR** | **[LT+CT]** Predicate-carrying `?proof-required`. Re-opens the deferred design at [`docs/design/proof-required-predicate-carrier.md`](design/proof-required-predicate-carrier.md). Extends `HoleKind.HProofRequired Text` at [`compiler/src/LLMLL/Syntax.hs:243`](../compiler/src/LLMLL/Syntax.hs) to `HProofRequired Text (Maybe Expr)`. Informational only: predicate typechecks as `bool`, recorded in trust report, runtime-assertion fallback emitted in codegen — verifier does NOT consume the predicate; trust label stays `asserted`. Predicate-carrying form is `def-shell`-only; forbidden inside `def` per LT-INV §1.4. LT-proposal/review pair land at [`docs/design/proof-required-predicate-carrier-proposal.md`](design/proof-required-predicate-carrier-proposal.md) + `-review.md` (pending, supersedes the deferred-exploration doc). | LT-INV (sequenced after) | ☐ |
| 4 | **LT-INT / INT-2** | **[CT]** Integer semantics: `int` = mathematical integer, codegen emits `Integer`. Three sites flipped per [`int-2-boundary-shims.md`](design/int-2-boundary-shims.md) §8 (Rev 3, F-E1/E2/E3): [`CodegenHs.hs:441`](../compiler/src/LLMLL/CodegenHs.hs) `mapLlmllPrimType`, `:706` `emitLit (LitInt n)`, `:723` `toHsType TInt`. Class B preamble entries lifted to `Integer` (`llmll_abs`/`min`/`max`, `int_to_string`, `string_to_int`, `range`); Class A indexing primitives keep `Int` with codegen `fromIntegral` shims at [`CodegenHs.hs:594-599`](../compiler/src/LLMLL/CodegenHs.hs); `wasi_http_response` polymorphic `Integral` with SPECIALIZE Integer. INT-1 overflow-taint trigger dormant on `int` (disarmed at [`FixpointEmit.hs:516`](../compiler/src/LLMLL/FixpointEmit.hs)); machinery preserved for INT-3 re-arm. `examples/banking_ledger` now passes `--strict-verified-core`. Verifier already operates under unbounded integers at [`FixpointEmit.hs:188-194`](../compiler/src/LLMLL/FixpointEmit.hs); no verifier-side change. INT-3 (`MachineInt` post-freeze alias under QF-BV) deferred to v0.12+. **Shipped on branch `lt-int/integer-codegen-switch`, commit `9c37a5c4`.** | INT-PRE | ☑ |
| 5 | **INT-PRE** | **[experiment-lead]** Cost pre-check: baseline measurement of `int → Int` codegen vs `int → Integer` codegen on benchmark suite (B1, B3, B5, TOTP at `examples/totp_rfc6238/`, ERC-20 at `examples/erc20_token/`). Per-benchmark regression factor reported. Gate criterion: if TOTP regresses >5×, escalate INT-3 to freeze-exception; otherwise INT-2 proceeds. Runs before INT-2 commits. **Cleared 2026-05-24** (commit `8cac520`) — adjudicated `int-2-clear`: TOTP test-phase regression factor 1.015 (n=10, A median 19.44 ms IQR 1.90 ms, B median 19.73 ms IQR 0.10 ms) against 5.0 gate threshold; byte-identity controls hold on `verify --spec-coverage --json` and `verify --trust-report --json` across all five benchmarks. INT-2 gate cleared; LT-INT engineer build unblocked. See [`experiments/int-pre/findings/postmortem-001.md`](../experiments/int-pre/findings/postmortem-001.md). | None | ☑ |

### Empirical Validation Gate (§8 of direction memo)

The v0.11 inversion ships **only if** an empirical pre/post comparison on the existing experimental harness confirms the architectural bet. The original v0.10 obligation report was the project's prior bet on what helps LLMs (*surface rich obligations*); the inversion is a *different* bet (*limit the grammar surface*). Both are defensible. Choosing between them is empirical, and the project has the discipline to make it empirically.

**Instrument:** [`experiments/minimal-agent/001-two-agent-auth`](../experiments/minimal-agent/) (18 attempts × 5 models) plus post-DL-B follow-up batches.

**Axes measured (`experiment-lead` formalizes the protocol):**
- **Grade distribution** — does the inversion shift the pass/fail distribution on `001-two-agent-auth` and post-DL-B follow-ups, holding model and prompt budget fixed? Improvement on at least one of (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts is the success signal.
- **First-pass success vs retry count** — does the inversion reduce agent-loop iteration count before passing? Competing prediction: smaller grammar surface → more parse errors → more retries. If iteration count rises while pass rate stays flat, the inversion has made authoring harder without making outcomes better.
- **Spec-strength distribution** — does the CDP axis (LT-CDP) surface a non-trivial number of `verified` weak-spec functions in existing benchmarks? If the metric never flags anything, it is not paying for its complexity.
- **Boundary-form usage distribution** — across migrated examples, what fraction of functions land in `def` (core) vs `def-shell`? If migration produces near-100% `def-shell` usage, the inversion has not changed where LLM-generated code lives; the canonical form is canonical in name only.

**Pass criteria (`language-team` adjudicates against `experiment-lead` results):** at least one of (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts must improve over the pre-inversion baseline — **and** no axis must regress materially. *Materially* is `experiment-lead`'s call against the existing variance baseline established in [`experiments/minimal-agent/findings/`](../experiments/minimal-agent/findings/).

**Rollback paths if the gate fails:**

1. **Demote the inversion to opt-in.** Keep the grammar change available behind a per-module pragma or `--grammar=core-inversion` flag; default remains the v0.10 mixed regime. Grammar work preserved; polarity claim retracted until a future cycle.
2. **Retract the grammar change; ship LT-CDP + LT-PPR only.** Contract discriminative power and predicate-carrying `?proof-required` are valuable independently of the inversion; both can ship without LT-INV. v0.11 becomes an evidence-axis and obligation-channel release rather than an architectural-polarity release.

### Sequencing (§8.4)

The v0.11 implementation **must** be sequenced so the empirical gate runs **before** the schema-version bump and example-program migration are finalized. This protects against shipping a v0.11 that the existing benchmarks reveal as a regression after schema and example migration are irreversible.

1. `language-team` settles LT-proposal docs for LT-INV, LT-CDP, LT-PPR (LT-INT is ratified-not-relitigated and proceeds directly).
2. `compiler-engineer` ships the LT-INV grammar change behind an explicit opt-in flag (`--grammar=core-inversion`), not as default. LT-CDP and LT-PPR ship in parallel (gate-independent).
3. `experiment-lead` runs INT-PRE (in parallel with above) and the §8 pre/post comparison on `001-two-agent-auth` plus post-DL-B batches.
4. **If the §8 gate passes**, `compiler-engineer` flips the grammar default; `documentation-lead` migrates `examples/*` and bumps `schemaVersion 0.5.0 → 0.6.0`.
5. **If the §8 gate fails**, route to rollback path (1) or (2) per `language-team` + `experiment-lead` adjudication.

§8 sequencing is **not** load-bearing for LT-CDP or LT-PPR — both ship under either rollback path.

### Acceptance criteria

- LT-INV grammar inversion lands behind `--grammar=core-inversion` opt-in flag first; default flips only on §8 gate pass.
- LT-CDP `(evidence, DP)` paired trust-report representation lands with `trust_report_version` 1.1.0 → 1.2.0; `--weakness-check` extended to the divergence metric per LT-CDP §Semantics.
- LT-PPR predicate-carrying form parses, typechecks the predicate as `bool`, records in trust report, emits runtime-assertion fallback; remains forbidden inside `def`.
- LT-INT codegen switch ships with INT-PRE gate result reported; INT-3 promotion-or-deferral adjudicated.
- §8 empirical-gate result published before final v0.11 ship; if rolled back, the rollback path (1) or (2) is named in the CHANGELOG entry.
- Migration tooling rewrites existing `examples/*` from `def-logic` to `def`/`def-shell` mechanically; manual review for ambiguous cases per LT-INV §Risks.
- DRIFT-1 / DRIFT-CI-1 / TC-EOP-1 / OBLIG-PBT-5a / INT-1 (v0.10.x patch lane) ship before v0.11 final to ensure the v0.11 baseline starts from a drift-free spec.

---

## Externally-Blocked Parking Lot

Items from the old v0.8.1 that depend on external availability. Tracked but not on the critical path.

| ID | Description | Trigger |
|-----|-------------|---------|
| **LEAN-GA** | Real Leanstral integration (non-mock proofs). When shipped, adds `verified-lean` evidence kind. | `lean-lsp-mcp` availability |
| **TRUST-2b** | `VLProvenLean` constructor — superseded by `EvidenceRecord` with `prover: "lean"`. Redesign against new evidence model when LEAN-GA triggers. | LEAN-GA |
| **STRIP-GA** | Safe assertion stripping — absorbed into v0.8.1b (evidence model) and v0.9 (stripping regression tests). | v0.8.1b + v0.9 |
| **MCP** | MCP integration for compiler CLI | Concrete external integration request |

**What changed from old v0.8.1:** LEAN-GA, TRUST-2b, and MCP were entirely blocked on external availability. STRIP-GA depends on evidence model clarity (v0.8.1b), not Lean. All moved to parking lot. New v0.8.1a/v0.8.1b/v0.9 have zero external blockers.

---

## Future — Module System Codegen (unversioned)

**Theme:** Complete the module system's codegen-level guarantees.

> **Source:** Professor's review (2026-05-01) and module system hardening audit (v0.9.1). Current module system is compile-time correct but codegen-level enforcement is absent.

| # | ID | Description | Prerequisite | Status |
|---|-----|-------------|-------------|--------|
| 1 | **MOD-2** | **[CT]** Per-module Haskell file emission: instead of concatenating all module statements into a single `Lib.hs`, emit one `.hs` file per module with Haskell `module` export lists. Enables true codegen-level export hiding and qualified access. | None | ☐ |
| 2 | **MOD-3** | **[CT]** Qualified access at codegen: with per-module `.hs` files, translate `module.function` to Haskell qualified imports. Makes §8.5.1 "Qualified Access" operational. | MOD-2 | ☐ |
| 3 | **MOD-4** | **[CT]** `loadFromFile` strict typecheck migration: switch the DFS module loader from permissive `typeCheck` to strict `typeCheckStrictWithCache`. Requires all examples and library modules to have correct `(open ...)` declarations. | MOD-1 | ☐ |
| 4 | **MOD-5** | **[CT]** `checkInterfaceMismatch` wiring: add `interfaceName` field to `Import` AST in `Syntax.hs`, parse `(interface ...)` clause in `Parser.hs`, expand `meAliasMap` types before comparison in `Module.hs`. | MOD-2 | ☐ |
| 5 | **MOD-PBT-1** | **[CT]** PBT FuncEnv visibility under `(open ...)`: `llmll test` now uses `loadStatementsMulti`; a new `assembleTestStatements` helper in `LLMLL.PBT` forwards imported modules' `SDefLogic` (filtered by `meExports` ∩ the optional `(open path (names))` restriction) ahead of the local statements so `buildFuncEnv` resolves cross-module calls inside `(check ...)` blocks. Local-shadows-import via `Map.fromList` right-bias. Honors `LLMLL.md §8.6`; qualified-name (`solution.plus-one`) resolution remains out of scope per §8.5. Closes F-018 / F-030 (repair-loop Phase 2 postmortem Addendum 8). 5 new ModuleSpec tests (M-08.1–M-08.5) + `test/fixtures/pbt-cross-module/`. | MOD-1 | ☑ |
| 6 | **OBLIG-PBT-2** | **[CT]** PBT complex-type sample generators + static-evaluator extensions: `PBT.hs:generateValue` retyped `Type → IO Literal` → `TypeAliasEnv → Int → Type → IO Expr` with new cases for `TPair` / `TList` (length-bounded cons-chain) / `TResult` / `TSumType` / `TCustom` (resolved via pure `expandAliasPure` against `STypeDef`-extracted alias env, depth-capped at `maxGenDepth = 5`). `Contracts.hs:evalExprStaticWith` extended for `EPair` (element-wise reduction) and `ELambda` (first-class value passthrough); `evalBuiltinApp` refactored to take `FuncEnv` + `fuel` with new builtins (`pair`/`first`/`second`/`cons`/`nil`/`list-head`/`list-tail`/`list-is-empty?`/`list-length`/`list-append`/`list-fold`/`list-map` + `applyLambda` helper / `unwrap-or`/`some`/`none`/`is-some`). `maxFuel` raised 64 → 256 for realistic agent emissions. `tryQuickCheck`'s `isSimpleType` whitelist removed (universal fallback through broadened generator). No syntax change; no schema bump. Closes F-032 (repair-loop apparatus postmortem Addendum 16). Empirical: Phase-2 c01 lifts from `0/3 skipped` to `3/3 passed` under `llmll test`; c02/c03 still skip via QuickCheck-discard saturation (deeper unfold chains). 10 new tests in `Spec.hs` (two `OBLIG-PBT-2` describe blocks); 594 → 604 Haskell. | MOD-PBT-1 | ☑ |
| 7 | **OBLIG-PBT-3** | **[CT]** PBT-to-trust-report write-back (F-033): wire `runPropertyTests` results into trust-report entries so `PBTPassed` produces `DLTested n` evidence at the corresponding `def-logic` site. Surfaced by OBLIG-PBT-2's implementation — currently `DLTested n` is only constructed from source-annotated `:trust tested` markers (`Parser.hs:381`, `ParserJSON.hs:289`) and the `.verified.json` cache (`VerifiedCache.hs:52`); no code path threads PBT results into `TrustReport.hs:enrichEntry`. Required for the trust report's `tier_profile.tested` field to reflect actually-passing `(check ...)` blocks — the v0.10.3 CHANGELOG's claim that MOD-PBT-1 elevates entries from `asserted → tested` was aspirational and remains untrue under v0.10.5. | OBLIG-PBT-2 | ☑ |
| 8 | **OBLIG-PBT-4** | **[CT]** PBT linkage v2 — `:subject` keyword metadata on `(check ...)` blocks (`:subject f` for singleton explicit, `:subjects [f g]` for joint-evidence opt-in). Annotated check blocks bypass the head-position scan; existing programs continue to work. Per-subject `DLTested n` lifts under explicit-annotation opt-in, with shared `pbt_witnesses` cross-link (pinned in `docs/design/oblig-pbt-3-proposal.md` §11.1, 2026-05-14). JSON-AST schema bump `0.4.0 → 0.5.0` (additive optional `CheckDecl.subjects`); `trust_report_version` stays `1.1.0`. Coverage-instrumented `evaluatedSamples` (QC `classify`/`cover`) sequenced to a later iteration; current ship is the linkage rule + diagnostic improvement. Bundled with **F-033** in the same engineer turn. | OBLIG-PBT-3 | ☑ |
| 9 | **F-033** | **[CT]** Body-side static-eval coverage extension (post-Addendum-17): `Contracts.hs:evalBuiltinApp` gains an `unwrap` clause paralleling `unwrap-or` (Success ↦ payload; Error ↦ Nothing — static evaluator has no panic value, so property body discards the sample, soundness-preserving). `PBT.hs:runQC` adds an `IORef`-threaded body-discard counter; `resultsToQCRun`/`gaveUpDiag` classify `GaveUp{numTests=0}` as "property body did not reduce on any sample (… likely unmodeled builtin or unreduced callee body in property body)" — distinguishes the c02-shape unreducible-body discard from a precondition-saturation discard, so the next round of diagnosis on c03-style residuals can read the failure mode directly. The named c02 acceptance criterion at `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 17 §"F-033 / Acceptance" (`samples_run ≥ 1` on the c02 fixture) is the empirical gate — the engineer-side change is the `unwrap` clause plus diagnostic refinement; the empirical re-run lives with `experiment-lead`. Bundled with **OBLIG-PBT-4** in the same engineer turn. | OBLIG-PBT-3 | ☑ |
| 10 | **F-034** | **[CT]** Residual `evalBuiltinApp` coverage on c02/c03-shape (post-Addendum-18): five missing clauses (`list-empty`, `list-prepend`, `list-filter`, `int-to-string`, `string-concat-many`) added at `Contracts.hs:evalBuiltinApp` for builtins already registered in `TypeCheck.hs:88-119` but absent from the static evaluator. `list-filter` delegates to a new `filterCons` helper that mirrors `mapCons`'s fuel discipline; `string-concat-many` delegates to a new `stringConcatMany` helper that walks the cons-chain of `LitString` literals. Correctness fix: `list-head` / `list-tail` now return `Success`-wrapped payloads matching their `[list[a]] -> Result a string` / `[list[a]] -> Result (list[a]) string` signatures at `TypeCheck.hs:100-101` (pre-fix they returned the raw element / tail, mis-typed against the type-checker — any property body pattern-matching `(match (list-head xs) ((Success v) ...))` failed to reduce); empty-list arms newly return `Error`-tagged so `(match (list-head xs) ((Error _) ...))` reduces. No schema bump (`expectedSchemaVersion` stays `0.5.0`); no `trust_report_version` change; no `LLMLL.md` surface change; verification fragment unchanged. Closes the Addendum-18 c02/c03 `samples_run ≥ 1` gate at `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 18 §"F-034 / Acceptance". Bundled with **OBLIG-PBT-4** + **F-033** in v0.10.6. 10 new tests in `Spec.hs` (`F-034 evalBuiltinApp residual builtin coverage` describe block); 630 → 640 Haskell. | OBLIG-PBT-3 | ☑ |

**Trigger criteria:** v0.10 shipped, or any production use case requiring true namespace isolation.

---

## Future — WASM Sandboxing (unversioned)

**Theme:** Replace Docker with WASM-WASI as the primary sandbox.

> **Source:** [wasm-poc-report.md](wasm-poc-report.md) — conditional GO (v0.3.2 assessment).
>
> **Decision (2026-04-21):** WASM is a confirmed future direction but not pinned to a release version. Docker + CAP-1 provide two functional enforcement layers (compile-time capability gating + OS-level container isolation). WASM adds a third layer (hardware-enforced capability boundary) and becomes a priority when there are real users running untrusted agent code in production. The v0.3.2 PoC confirmed feasibility; the `effectful` compatibility spike (v0.5) will determine whether the typed effect row design needs changes.

### WASM Build Target (~7 days)

| Phase | Work | Effort | Status |
|-------|------|--------|--------|
| Phase 0 | Install `ghc-wasm-meta` + `wasmtime`, manual compile of hangman | 1 day | ☐ |
| Phase 1 | `--target wasm` flag, generate `.cabal` file, invoke `wasm32-wasi-cabal` | 2–3 days | ☐ |
| Phase 2 | Strip check blocks for WASM, WASI capability import mapping | 2 days | ☐ |
| Phase 3 | CI integration, setup script, docs | 1 day | ☐ |

> [!WARNING]
> **`effectful` library compatibility with GHC WASM backend is untested.** The v0.3.2 PoC compiled `hangman_json_verifier` which doesn't use `effectful`. A real WASM build with typed effect rows needs the v0.5 `effectful` spike to validate `effectful`'s C shims under `wasm32-wasi`. If this fails, typed effect rows must be shimmed or deferred.

**Acceptance criteria:**

- `llmll build --target wasm examples/hangman_sexp/hangman.llmll` produces a `.wasm` binary
- `wasmtime hangman.wasm` runs the game correctly
- WASI capability imports align with LLMLL capability declarations
- Typed effect rows (`effectful`) integrate with WASI enforcement

**Risk:** `ghc-wasm-meta` toolchain maintenance is low-bus-factor. If it falls behind GHC releases, this work slips without affecting anything else.

**Trigger criteria — when to schedule this:**

- Real users running untrusted agent code outside development environments
- Docker proving insufficient as a sandbox (capability granularity, startup latency, distribution)
- `effectful` WASM compatibility spike (v0.5) returns GO

---

## Cross-cutting concerns

### Active Items

> **Routing:** items below are organized into three lanes by milestone target. Tags follow the `XXX-N` pattern; full triage record at [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) §4; v0.11 architectural items detailed in the `## v0.11` milestone section below.

#### Standing items

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **Feature freeze** | **Lifted for v0.11** (architectural correction) | See `## Feature Freeze Policy` above; original freeze v0.8.1a–v0.10 preserved as historical record |
| **External critique triage** (2026-05-23) | **Adjudicated** — 17 tagged items routed across three lanes below | See [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) §4 |
| **Obligation-guided agent coding** (v0.10) | **Shipped** (2026-05-03; final patch v0.10.6 on 2026-05-14) | (unchanged) 640 Haskell + 37 Python tests |
| **Module system hardening** (v0.9.1) | **Shipped** (2026-05-01) | (unchanged) |
| **Cross-module ContractEnv** (MOD-1) | **v0.10 prerequisite** — shipped with v0.10 | Drift note: should move to Resolved block on a future doc pass |
| **Evidence model design** (EVID-0) | **Approved** (Rev 2) — shipped via v0.8.1b | (unchanged) |
| **TRUST-2b** (`VLProvenLean`) | **Parked** (2026-04-30) | Externally-blocked parking lot — redesign against new evidence model when LEAN-GA triggers |

#### v0.10.x patch lane (in-freeze, narrowing fixes)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **DRIFT-1** | **Shipped (closed Pass 7, v0.10.8)** | doc-lead: Pass 5 (`7ccd925`, 2026-05-23) closed §4.2 letrec TERM-1 partiality disclaimer, §9.6 DO-1 explicit-discard clarification, §13.11 CRYPTO-1 stub-backend trust-tier annotation, LLMLL.md banner v0.10.1 → v0.10.6 + release-history rows v0.10.2–v0.10.6, and schema `$id` v0.2 → v0.5 reconciliation. Pass 6 (`623c46f`) closed LLMLL.md banner v0.10.6 → v0.10.7 under DRIFT-CI-1 C1+C2 strict-equality, the v0.10.7 release-history row, and §12 `check` grammar amendment for v0.10.6's `:subjects` metadata (Grammar Rule 10). Pass 7 (this commit, v0.10.8): LLMLL.md banner v0.10.7 → v0.10.8 + v0.10.8 release-history row + v0.10.8 status paragraph; README banner v0.10.7 → v0.10.8 + status paragraph rewrite + command-table `--strict-verified-core` bullet extended for INT-1; §3 type-system catch-up closed via §3.1 NOTE pointing to the v0.10.8 §5.3.5 `overflow_tainted` callout (INT-1 ship at engineer commits `900e5ab` + `1585de2` unblocked the residual). |
| **TC-EOP-1** | **Shipped v0.10.7** | engineer: `compiler/src/LLMLL/TypeCheck.hs:981-1010` rewritten to mirror the EApp arity/`structuralUnify` loop (per-call-site substitution + EHole bypass); polymorphic `=`/`!=` unify both operands against the same TVar (no `any × any → bool` degrade). 9 regression tests under `TC-EOP-1 EOp arity and arg-type checking` in `Spec.hs` cover arity (under/over), arg-type errors, polymorphic equality both positive and negative, JSON-AST frontend parity, and the EHole-in-EOp bypass. All shipping examples typecheck unchanged. |
| **OBLIG-PBT-5a** | **Shipped v0.10.7** | engineer: `joint_pbt_witness` per-entry flag + top-level `joint_pbt_witnesses` grouping in trust-report JSON; scalar `tested` count demotes joint-only `DLTested` entries to `DLAsserted` across `computeSummary` / `aggregateTiers` / `aggregateTiersPost`. Joint-only predicate is "non-empty witnesses AND every hash is shared with ≥1 other subject" so solo+joint-mix entries keep their +1 credit. Source-annotated (empty-witness) `DLTested` unaffected. 6 regression tests under `OBLIG-PBT-5a joint PBT witness exclusion` in `Spec.hs`. Schema additive — `trust_report_version` stays `1.1.0`. |
| **INT-1** | **Shipped v0.10.8** | engineer: `erOverflowTainted :: Bool` added to `EvidenceRecord` at [`compiler/src/LLMLL/Syntax.hs:326-331`](../compiler/src/LLMLL/Syntax.hs); `bodyHasOverflowArith` syntactic walker at [`compiler/src/LLMLL/FixpointEmit.hs:597-642`](../compiler/src/LLMLL/FixpointEmit.hs) fires on `EOp` / `EApp` arithmetic-headed nodes whose operands are not all `Int64`-folding literals; activated after `addBodyFaithful` at line 506-516 (taint gated on body-faithful success). `--strict-verified-core` at [`compiler/app/Main.hs:1119-1158`](../compiler/app/Main.hs) refuses overflow-tainted-verified entries with a dedicated diagnostic naming the `?proof-required` / INT-2 escape paths. Sidecar gains additive `overflow_tainted: true` (only-when-true) with invalidate-on-missing for pre-v0.10.8 verified body-faithful entries at [`compiler/src/LLMLL/VerifiedCache.hs:158-216`](../compiler/src/LLMLL/VerifiedCache.hs). Trust-report JSON gains top-level `overflow_tainted_fns` and per-entry `overflow_tainted` (additive, `trust_report_version` stays `1.1.0`). Obligation-report trust channel gains `overflow_tainted` per clause. 16 regression tests under `INT-1 (v0.10.8): overflow taint propagation` in `Spec.hs`. `examples/banking_ledger/banking.llmll.verified.json` regenerated; `safe-subtract` now carries the tag. Trigger set becomes dormant on `int` post-INT-2 and re-arms on `machine-int` per [`docs/design/int-2-boundary-shims.md`](design/int-2-boundary-shims.md) §4 and [`docs/design/int-3-machine-int-sketch.md`](design/int-3-machine-int-sketch.md) §3.2. Unblocks the DRIFT-1 §3 catch-up doc-lead pass. |
| **DRIFT-CI-1** | **Shipped (engineer infra patch, branch `drift-ci-1/version-gate`)** | engineer: workflow + harness landed. [`scripts/version_gate.sh`](../scripts/version_gate.sh) implements C1+C2 (banner equality across README.md, LLMLL.md, CHANGELOG.md `## vX.Y.Z` top heading, `compiler/package.yaml`, `compiler/llmll.cabal`), C3 (`docs/llmll-ast.schema.json` `$defs.Program.properties.schemaVersion.const` == `compiler/src/LLMLL/ParserJSON.hs::expectedSchemaVersion`), and C4 (schema `$id` URL contains `/schemas/vMAJOR.MINOR/` derived from `schemaVersion`); pure shell + `jq`, no Stack/GHC dependency. [`scripts/spec_roundtrip.py`](../scripts/spec_roundtrip.py) implements C5 as an *opt-in* harness: spec authors mark a fenced ` ```lisp ` or ` ```llmll ` block with `<!-- ci:roundtrip -->` (or `<!-- ci:roundtrip: strict -->`) immediately above the fence opener, and the script writes each opted-in block to a tempfile and shells out to `llmll check`. Opt-in over opt-out is a deliberate design deviation from the original plan after on-tree inspection showed default-on would require ~50+ skip annotations; doc-lead extends the opt-in surface in subsequent passes. Initial opt-in set: one block at [`LLMLL.md:396`](../LLMLL.md) (§4.4.3 trust declaration example) as the end-to-end smoke. [`.github/workflows/version-gate.yml`](../.github/workflows/version-gate.yml) wires two jobs (`version-gate` Ubuntu+jq+pytest in <1 min; `spec-roundtrip` Ubuntu+Stack-cached+`llmll check` in ~5 min steady-state). 21 new pytest cases at [`scripts/tests/`](../scripts/tests/) cover script behaviour with `llmll`-binary stubs (no Stack dependency in the pytest path). Closure removes both residuals named in the prior row text. |

#### v0.11 architectural lane (freeze-lifted)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **v0.11 milestone** | **Planned** — see `## v0.11` section below | LT proposals settled; engineer build sequenced per §8.4 |
| **LT-INV** (core/shell grammar inversion) | **Settled (Rev 2) — review folded; engineer build shipped on branch** | LT proposal at [`docs/design/core-shell-inversion-proposal.md`](design/core-shell-inversion-proposal.md) settled Rev 2 (commit `5f31580`, 2026-05-25) incorporating seven gaps + two author-question answers from professor review; review folded as §"Appendix — Professor review log" (commit `f1ef0c0`); standalone archived to [`docs/archive/professor-reviews/core-shell-inversion-review.md`](../docs/archive/professor-reviews/core-shell-inversion-review.md). Engineer build shipped: `--grammar=core-inversion` opt-in flag active on all subcommands; `GrammarCoreInversion` mode parses `def`/`def-shell`, enforces `isCoreBodySyntactic` whitelist and `checkCalleeAdmissibility` (body-faithful | trustedPrelude | builtinEnv); two new diagnostic kinds `core-grammar-violation`/`core-membership-violation`; full 15-module fan-out; 28 LT-INV regression tests (`INV-P/W/A/C/G` series); 744 Haskell + 58 Python tests total. Schema bump `0.5.0 → 0.6.0` + default flip to `GrammarCoreInversion` gated on §8 empirical-validation gate; `CDPScope` default flip to `CDPScopeOnlyDef` also pending §8 gate result. Spec-drift finding: `builtinEnv` admission in `checkCalleeAdmissibility` not yet formalized in `LLMLL.md §5.3.5`; routed to `language-team`. Subsumes STRICT-CORE-1 sub-item. Cross-proposal shipping under gate outcomes per [`v0.11-cross-proposal-rollback-discipline.md`](design/v0.11-cross-proposal-rollback-discipline.md). **F-GATE-1 patch (commit `cabb1fd`, 2026-05-28):** `parseJSONAST` now enforces `GrammarCoreInversion` — `{"kind":"def-logic"}` in `.ast.json` input is rejected with a `core-grammar-violation` diagnostic (exit 1) under `--grammar=core-inversion`; §8 empirical-validation gate unblocked for re-run. 3 new tests INV-P9/P10/P11; **767 Haskell + 58 Python** tests total. **F-GATE-1b patch (2026-05-28):** `letrec` enforcement added to both parser paths — `{"kind":"letrec"}` rejected under `GrammarCoreInversion` in `ParserJSON.hs`; `pDefLogic`/`pLetrec` moved to `GrammarLegacy` arm of `pStatement` in `Parser.hs`, closing the S-expression-path asymmetry. INV-P6 inverted; INV-P12/P13/P14 added. **770 Haskell + 58 Python** tests total. Routing-note closures: S-expression-path asymmetry (INV-P6) resolved by F-GATE-1b. F-GATE-2 (`LLMLL.md §4.1` prose gap) was already resolved — `LLMLL.md §4.1` and `getting-started.md §4.14` already stated `def-logic` and `letrec` are rejected under `--grammar=core-inversion`; no `language-team` action owed. |
| **LT-CDP** (contract discriminative power evidence axis) | **Shipped on branch (commit `121815a`)** | Engineer-shipped on `lt-cdp/discriminative-power-axis`: new [`compiler/src/LLMLL/CDP.hs`](../compiler/src/LLMLL/CDP.hs) module owns score / partition / typed warnings per proposal §5; closed v0.11 candidate-set enumeration in [`compiler/src/LLMLL/WeaknessCheck.hs`](../compiler/src/LLMLL/WeaknessCheck.hs) `generateCDPCandidates` per proposal §4.3.1; `(spec-entropy …)` annotation parsed in both frontends; `trust_report_version` bumped `1.1.0 → 1.2.0` with additive `discriminative_axis` per entry; new `--cdp` CLI flag at [`compiler/app/Main.hs`](../compiler/app/Main.hs); `CDPScope` gate-conditional parameter defaults to `CDPScopeAllDefLogic` until LT-INV §8 gate flips it. 712 Haskell + 58 Python tests (LT-CDP adds 22 regression C1–C22; F-001 adds 4 DF-1–DF-4, commit `e5e6d04`; F-006/F-005 adds 6 F6-1–F6-6, commit `6f2ea39`). **JSON-AST `schemaVersion` not bumped** — deferred to LT-INV bundle (Outcomes 0/1, `0.5.0 → 0.6.0`) or coordinates with LT-PPR (Outcome 2, `0.5.0 → 0.5.1`) per [`v0.11-cross-proposal-rollback-discipline.md`](design/v0.11-cross-proposal-rollback-discipline.md) §2. **Owed to `experiment-lead`:** CDP-0 baseline DP report at `experiments/cdp-0/runs/<ts>-baseline/baseline.json` *before* the LT-INV §8 gate runs (proposal §2 Rev 2 baseline-first sequencing). Subsumes DP-FORM-1 + TRUST-DP-1 sub-items. |
| **LT-PPR** (predicate-carrying `?proof-required`) | **Settled (Rev 2) — review folded** | LT proposal at [`docs/design/proof-required-predicate-carrier-proposal.md`](design/proof-required-predicate-carrier-proposal.md) settled Rev 2 (commit `5f31580`, 2026-05-25) incorporating six gaps + two author-question answers from professor review; review folded as §"Appendix — Professor review log" (commit `f1ef0c0`); standalone archived to [`docs/archive/professor-reviews/proof-required-predicate-carrier-review.md`](../docs/archive/professor-reviews/proof-required-predicate-carrier-review.md). Engineer build contingent on LT-INV gate per §6.3; supersedes deferred-exploration at [`docs/design/proof-required-predicate-carrier.md`](design/proof-required-predicate-carrier.md). Cross-proposal shipping under gate outcomes per [`v0.11-cross-proposal-rollback-discipline.md`](design/v0.11-cross-proposal-rollback-discipline.md). |
| **LT-INT / INT-2** (`int → Integer` codegen switch) | **Shipped on branch (commit `9c37a5c4`)** | Engineer-shipped on `lt-int/integer-codegen-switch`: three codegen sites flipped per [`int-2-boundary-shims.md`](design/int-2-boundary-shims.md) §8 Rev 3 (F-E1/E2/E3); Class B preamble Integer-lifted; Class A indexing primitives keep `Int` with codegen `fromIntegral` shims at [`CodegenHs.hs:594-599`](../compiler/src/LLMLL/CodegenHs.hs); `wasi_http_response` polymorphic `Integral` with SPECIALIZE Integer; INT-1 overflow-taint trigger dormant on `int` (disarmed at [`FixpointEmit.hs:516`](../compiler/src/LLMLL/FixpointEmit.hs); walker + record field preserved for INT-3 re-arm); `examples/banking_ledger` passes `--strict-verified-core`. 680 Haskell + 58 Python tests (+8 LT-INT regression L1–L8). **Catalog Rev 4 candidates (routed to language-team):** §8-vs-§4 emitter-call-site reconciliation; §3.4 `range_idx` split deferred (corpus audit shows all uses are index iteration handled by Class A shims). |
| **INT-PRE** | **Cleared — `int-2-clear` adjudication** | experiment-lead postmortem-001 (2026-05-24, commit `8cac520`): TOTP test-phase regression factor 1.015 (n=10) against 5.0 gate threshold; byte-identity controls hold on `verify --spec-coverage --json` + `verify --trust-report --json` across all five benchmarks (B1, B3, B5, TOTP, ERC-20). INT-2 gate cleared; LT-INT engineer build unblocked. See [`experiments/int-pre/findings/postmortem-001.md`](../experiments/int-pre/findings/postmortem-001.md). |
| **REF-META-1** (refinement metatheory of record) | **Promoted to LLMLL.md §3.4/§5 (doc-lead pass, 2026-05-27)** | LT proposal at [`docs/design/refinement-metatheory-of-record-proposal.md`](design/refinement-metatheory-of-record-proposal.md) settled Rev 2 (commit `5f31580`, 2026-05-25) incorporating six gaps + two author-question answers from professor review; review folded as §"Appendix — Professor review log" (commit `f1ef0c0`); standalone archived to [`docs/archive/professor-reviews/refinement-metatheory-of-record-review.md`](../docs/archive/professor-reviews/refinement-metatheory-of-record-review.md). Spec-track only (no compiler work). Promoted (doc-lead pass 2026-05-27): §3.4.1 checking-mode rule, §3.4.2 non-goals, §3.4.3 soundness statement, §5.3.3 routing clarification, §5.3.5 matrix rows. Carries the cross-proposal observations C-1 through C-4 from the batched professor review; C-2 settled at [`docs/design/v0.11-cross-proposal-rollback-discipline.md`](design/v0.11-cross-proposal-rollback-discipline.md). |

#### v0.12+ post-freeze lane

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **INT-3** (`MachineInt` QF-BV alias) | **P3 — open** | LT design when freeze lifts again; promote to P1 (freeze-exception candidate) if INT-PRE shows TOTP regression > 5× |
| **OBLIG-PBT-5b** (clean `EvidenceRecord.scope`) | **P2 — open** | engineer post-freeze; `trust_report_version` 1.1.0 → 1.2.0; new `tested-joint` display level |
| **REF-META-2..5** (solver-completeness, erasure, predicate WF, typing judgment) | **P2-P3 — open** | LT drafts → doc-lead promotion; sequenced after REF-META-1 |
| **Bundle B** (effect rows on `Command`) | **Reclassified** out of indexed-types research bundle per memo §4 | Separate v0.12+ design track; staged B0 → B3 (function-level effect summaries → row-polymorphic `Command {ρ} a` → effect-aware contracts). NOT WASM-coupled. |

#### Research track (no v0.x targets, no Active Items rows)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **Contract discriminative power formalization** | ~~Proposed by Professor / Research track~~ → **Promoted to v0.11 CDP-0** (LT-CDP) | See v0.11 milestone below; [`docs/research-track.md:145-151`](research-track.md) needs retirement on a separate pass |
| **Full categorical unification** (fibrations / graded monads / patch-merge derivation) | **Declined** | Disproportionate per professor adjudication; amended critic did not re-propose. See [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) §5 |
| **Path B mechanized soundness theorem** | **Declined** | Inherited Path A stance from [`docs/design/verification-debate.md`](design/verification-debate.md) |

#### Research track (migrated from `docs/research-track.md`, 2026-05-25)

> Per DOC-CONSOLIDATE M4 (settled 2026-05-24, shipped at `1a8733f`), `docs/research-track.md` has been archived to `docs/archive/research-track.md`. The six remaining active items (item #6 Contract Discriminative Power was promoted to v0.11 CDP-0 on 2026-05-23) are summarized below with archive cite and the cross-references identified by the language-team R1–R7 overlap audit (settled 2026-05-25, per DOC-CONSOLIDATE §11 follow-up). Audit outcome: no R-item is subsumed by an existing roadmap row. The new Cross-reference column states the design or empirical sibling identified by the audit; R3 is flagged with a partial-criterion note (`examples/totp_rfc6238/` partially satisfies the worked-example promotion criterion). Items remain authoritative at the archived source.

| # | Item | Original promotion criterion | Cross-reference (per R1–R7 audit, 2026-05-25) | Archive source |
|---|------|------------------------------|------------------------------------------------|----------------|
| **R1** | **Indexed / Dependent Types** (`Vect n a`, GADTs, type-level arithmetic, bidirectional typechecking) | Design spec with typing rules, bidirectional migration plan, erasure strategy | Source design exploration: [`docs/design/type-driven-development.md`](design/type-driven-development.md) (partially promoted — obligation-guided part shipped in v0.10). Consistent with "What's NOT on this Roadmap" row Indexed/dependent types — Research track. | [`docs/archive/research-track.md §1`](archive/research-track.md) |
| **R2** | **Self-Hosted Orchestrator** (rewrite `llmll-orchestra` as LLMLL `def-main :mode cli`) | Agent accuracy ≥80% on auth module exercise when filling LLMLL-source holes | Source design draft: [`docs/design/agent-orchestration.md`](design/agent-orchestration.md) §Option B (Future Infrastructure category in INDEX). No competing roadmap row. | [`docs/archive/research-track.md §2`](archive/research-track.md) |
| **R3** | **Spec-from-RFC Pipeline** (RFC text → LLMLL contracts with clause provenance traceability) | Concrete pipeline design doc with at least one worked example (e.g., ERC-20) | Promotion criterion partially met: [`examples/totp_rfc6238/`](../examples/totp_rfc6238/) (v0.6.1 shipped) demonstrates the RFC-to-LLMLL pattern with `:source` provenance per [`LLMLL.md §13.11`](../LLMLL.md). Generalizable pipeline design doc still owed before full promotion. | [`docs/archive/research-track.md §3`](archive/research-track.md) |
| **R4** | **Synthetic Training Corpus** (Hackage back-translation; transpiler + spec lifting + benchmark) | Research proposal with measurable hypothesis and evaluation methodology | No competing roadmap row; independent. | [`docs/archive/research-track.md §4`](archive/research-track.md) |
| **R5** | **Differential Implementation Pressure** (`llmll checkout --multi`; N agents fill same `?delegate`; divergence analysis as new module `DivergenceCheck.hs`) | Agent accuracy baseline established | Empirical sibling (not subsumption): [`experiments/repair-loop/`](../experiments/repair-loop/) measures single-agent repair, R5 measures multi-agent divergence — different feature surfaces. Not subsumed by the `OBLIG-*` family (OBLIG-0…OBLIG-5 + OBLIG-B enrich single-agent obligation reports; R5 is a distinct multi-agent feature). | [`docs/archive/research-track.md §5`](archive/research-track.md) |
| **R7** | **Call-Site Strict Descent** (`measure(args') < measure(args)` constraint at each recursive call site; independent of BODY-VC per consultant correction 2026-04-28) | Independent design spec for descent constraint generation | Complementary (not overlapping) with TERM-1 from [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) row 7: TERM-1 is documentation-side (partiality disclaimer); R7 is implementation-side (descent constraint emission). Sequence: TERM-1 ships first as honest-documentation-now; R7 is the eventual implementation that retires TERM-1's disclaimer. | [`docs/archive/research-track.md §7`](archive/research-track.md) |

> **External Consultant Review (2026-04-28)** and **Impact Analysis (2026-05-01)** preserved in archive at [`docs/archive/research-track.md §§Impact-Analysis,External-Consultant-Review`](archive/research-track.md). Near-term recommendations 1–4 closed; items 5 (R5) and 6 (R3) remain open.

<details><summary><strong>Resolved cross-cutting items (click to expand)</strong></summary>

| Item | Resolution |
|------|------------|
| Orchestration event log format (Q3 from v0.3.3) | **Shipped** (v0.8.0, EVENT-LOG) |
| MCP integration (Q5 from v0.3.3) | Moved to v0.8.1 |
| Real Leanstral integration | Moved to v0.8.1 as LEAN-GA. Product claim narrowed (v0.6 CLAIM-1..2). |
| Spec coverage metric (`--spec-coverage`) | **Shipped** (v0.6.0, SC-1..SC-4) |
| Spec-adequacy benchmark (ERC-20) | **Shipped** (v0.6.0 BM-1..3/5, v0.6.1 BM-4) |
| Spec-adequacy benchmark (TOTP) | **Shipped** (v0.6.1, BM2-1..BM2-5) |
| Verification-scope matrix policy | **Shipped** (VSM-2 policy, VSM-1 backfill in v0.6.2) |
| Suppression governance (`weakness-ok`) | **Shipped** (v0.6.0) |
| Claim-to-evidence appendix | **Shipped** in one-pager (2026-04-23) |
| Contract clause-level provenance | **Shipped** (v0.6.0 PROV-1/2/4, v0.6.1 PROV-3) |
| Hub query-by-signature | **Shipped** (v0.6.1, HUB-1..HUB-3) |
| Algorithm W `TDependent` interaction | **Resolved** (Strip-then-Unify, Option A, 2026-04-19) |
| `TSumType` wildcarding in `compatibleWith` | **Fixed** in U-Lite (v0.4, U7-lite) |

</details>

### What's NOT on this Roadmap (and why)

| Item | Reason |
|------|--------|
| Rust codegen backend | Dropped in v0.1.2; Haskell is the permanent target |
| Python FFI tier | Breaks WASM compatibility; dynamically typed |
| Full Lean 4 proof agent from scratch | Replaced by Leanstral MCP integration |
| UI/web frontend | LLMLL's target domains are backend, not UI |
| IDE plugins (VS Code, etc.) | Premature — stabilize the CLI/HTTP interface first |
| New builtins | **Feature freeze** — each unverified builtin is a semantic escape hatch |
| New syntax constructs | **Feature freeze** |
| Broader FFI | **Feature freeze** |
| More WASI surface | **Feature freeze** |
| Orchestration features (compiler-side) | **Feature freeze** |
| Typeclass law machinery | **Feature freeze** |
| Lean integration | Externally blocked (parking lot) |
| Indexed/dependent types | Research track — explicitly excluded from v0.10 (professor consensus, 2026-05-01) |

---

## Summary: Version Plan and Critical Path

> **Roadmap restructure (2026-04-30, extended 2026-05-01):** Professor's review + language team consensus. Old v0.8.1 (blocked on `lean-lsp-mcp`) replaced with four actionable milestones. Feature freeze active from v0.8.1a through v0.10.

```
v0.8.0 (SHIPPED)  v0.8.1a (SHIPPED)  v0.8.1b (SHIPPED)   v0.9 (SHIPPED)        v0.10 (SHIPPED)         Parked
────────────────  ──────────────     ──────────────────  ────────────────────  ─────────────────────   ──────
BODY-VC ✅         RENAME-1/2 ✅       EVID-0 (design ✅)   COMP-0 (design ✅)    OBLIG-0 (design ✅)      LEAN-GA
SUPP-DEBT ✅       MATRIX-1/2/3 ✅     EVID-1 (ADT ✅)       COMP-1 (EApp ✅)      OBLIG-1 (holes ✅)      TRUST-2b
EVENT-LOG ✅       BOUNDARY-1/2 ✅     EVID-2 (sidecar ✅)  COMP-2 (SCC ✅)       OBLIG-2 (goal-state ✅) MCP
SPEC-* ✅          ROADMAP-1/2 ✅      EVID-3 (trust ✅)    COMP-3 (EMatch ✅)    OBLIG-3 (branches ✅)
320 tests                             EVID-4 (coverage ✅) COMP-4 (trust ✅)     OBLIG-4 (suggestions ✅)
                   9/9 shipped        EVID-5 (contracts✅) COMP-5 (diags ✅)     OBLIG-5 (repair ✅)
                   no code            EVID-6 (module ✅)   COMP-6 (strict ✅)    OBLIG-B (benchmark ✅)
                   zero risk          EVID-7/8 (CLI ✅)    COMP-T (tests ✅)
                                      EVID-T (tests ✅)    8/8 shipped           8/8 shipped
                                      10/10 shipped                              570 tests (v0.10.1)
                                       322 tests
```

**Critical path:** EVID-0 design review ✅ → v0.8.1b implementation ✅ → COMP-0 design review ✅ → v0.9 implementation ✅ → OBLIG-0 design review ✅ → v0.10 implementation ✅. **All milestones complete.**

**v0.10.2 patch shipped (2026-05-10):** soundness blockers (delegate fallback typecheck, PBT discard, evaluator expansion) + diagnostic surface + JSON-AST schema bump 0.3.0 → 0.4.0. 584 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.2.

**v0.10.3 patch shipped (2026-05-12):** cross-module PBT visibility (MOD-PBT-1 / F-018 — `(open ...)`-targeted `def-logic` now reaches the PBT FuncEnv, closing the Phase-3 gating finding from the repair-loop apparatus postmortem) + spec pedagogy corrections (§2.5 Naming Conventions, §3.3 / §9 / §13.5 match-arm canonical form, §3.2 / §3.3 unit-payload vs nullary constructor) + roadmap disambiguation of the one-shot correctness criterion. 589 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.3.

**v0.10.4 patch shipped (2026-05-13):** R6d trust-report tier-count profile aggregate (`bb1bd98` — `TierProfile` + `aggregateTiers` in `TrustReport.hs`; new `docs/llmll-trust-report.schema.json` versioned independently at `trust_report_version: "1.0.0"`) + `LLMLL.md §4.4.4` spec note (`bbab67b`) + repair-loop harness Cred + H1 bifurcation (`90a5bb9` — `accepted_levels` drops `asserted`, `tier_profile` consumed by evaluator, `experiments/repair-loop/README.md` "Credibility predicate and the H1 split (R6d)" section, closes §LT-A / F-026 / F-027 with re-probe of three Phase-2 cells) + repair-loop matrix runner (`5895792` — `scripts/run_matrix.py` with `--resume-from-cell`, pre-flight prereq checks, and `terminal_target_per_target` dispatch for mixed-surface matrices). 594 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.4.

**v0.10.5 patch shipped (2026-05-13):** PBT complex-type generators + static-evaluator extensions (`262e1a2` — `PBT.hs:generateValue` retyped `Type → IO Literal` → `TypeAliasEnv → Int → Type → IO Expr` with `TPair`/`TList`/`TResult`/`TSumType`/`TCustom` cases (depth-capped at `maxGenDepth = 5`); `evalExprStaticWith` extended for `EPair`/`ELambda`; `evalBuiltinApp` refactored with new §13 list/option/pair builtins via `applyLambda`; `maxFuel` raised 64 → 256; `tryQuickCheck`'s `isSimpleType` whitelist removed; closes F-032) + PBT-to-trust-report write-back (`fb236c9` — `PBTPassed` lifts post clause of the singleton head-position contracted callee to `DLTested n`; `pbt_witnesses` SHA-256 hashes persisted in `.verified.json` for staleness invalidation; parallel `tier_profile_pre` / `tier_profile_post` aggregates added to trust-report emit; `trust_report_version` 1.0.0 → 1.1.0 additive; PBT-Lift rule formalised in `LLMLL.md §4.4.5`; closes F-033). 614 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.5.

**v0.10.6 patch shipped (2026-05-14):** OBLIG-PBT-4 `:subject` / `:subjects` keyword metadata on `(check ...)` blocks (`cb2e71f` — `Property` record gains `propSubjects :: [Name]`; sexp `Parser.hs:pCheckBlock` and `ParserJSON.hs:parseCheckDecl` populate from the new keyword/field; `pbtTrustWriteback`'s `processRun` branches on `propSubjects` to emit per-subject `DLTested n` records with shared `pbt_witnesses`; subjects without a postcondition skip with an info diagnostic; cross-module subjects key under the qualified path via the existing `qualMap`; JSON-AST `schemaVersion` bumped `0.4.0 → 0.5.0` additively for `CheckDecl.subjects`; closes OBLIG-PBT-4) + F-033 body-side static-eval coverage extension (`unwrap` clause in `Contracts.hs:evalBuiltinApp`, `IORef`-threaded body-discard counter through `runQC`, refined `gaveUpDiag` distinguishing body-unreducibility from precondition-saturation; closes F-033) + F-034 residual `evalBuiltinApp` coverage (five missing clauses `list-empty`/`list-prepend`/`list-filter`/`int-to-string`/`string-concat-many` for builtins already registered in `TypeCheck.hs:88-119`; correctness fix on `list-head`/`list-tail` Success-wrapping matching the `Result a string` / `Result (list[a]) string` type-checker signatures with new Error-tagged empty-list arms; new `filterCons`/`stringConcatMany` helpers mirror `mapCons`' fuel discipline; closes the Addendum-18 c02/c03 `samples_run ≥ 1` gate; closes F-034). `LLMLL.md §4.4.5` PBT-Lift rule extended with the annotated-subject premise (`PBT-Lift-Annotated`). 640 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.6.

**v0.10.7 patch shipped (2026-05-23):** TC-EOP-1 EOp arity and argument-type checking (`c8a68de` — `inferExpr (EOp op args)` at `TypeCheck.hs:981` rewritten to mirror the `EApp` arity-check + `structuralUnify` per-call-site-substitution loop with `withSegment "args"` pointer-stack discipline and `EHole` bypass; polymorphic `=` / `!=` unify both operands against one bound `TVar`; closes TC-EOP-1) + OBLIG-PBT-5a joint PBT witness scalar exclusion (`fbb8f28` — `TrustReport.hs` computes `jointHashes :: Set Text` (post-clause hashes appearing on ≥2 distinct subjects) and demotes pure-joint `DLTested` entries to `DLAsserted` in `computeSummary` / `aggregateTiers` / `aggregateTiersPost`; the "every witness is joint" predicate preserves the `+1` credit for solo+joint mixes; per-entry `joint_pbt_witness: true` and top-level `joint_pbt_witnesses` JSON additions; `trust_report_version` stays `1.1.0` per the 2026-05-23 critique-triage no-bump constraint; closes OBLIG-PBT-5a) + release chore (`a4fc234` — version bump `0.10.6 → 0.10.7` in `package.yaml` and `llmll.cabal`; CHANGELOG entry; roadmap rows TC-EOP-1 / OBLIG-PBT-5a marked Shipped; INT-1 explicitly deferred to v0.10.8; DRIFT-CI-1 flagged out of v0.10.7 engineer scope; OBLIG-PBT-5b post-freeze). 656 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.7.

**v0.10.8 patch shipped (2026-05-24):** INT-1 `overflow_tainted` propagation on body-faithful verified evidence + strict-verified-core refusal. `EvidenceRecord` at `Syntax.hs:326-331` gains a fifth field `erOverflowTainted :: Bool`. `bodyHasOverflowArith :: Expr -> Bool` at `FixpointEmit.hs:597-642` syntactically walks the function body looking for `EOp` / `EApp` arithmetic over non-`Int64`-folding operands; activated at `FixpointEmit.hs:506-516` immediately after `addBodyFaithful` (trigger gated on body-faithful success). `--strict-verified-core` at `Main.hs:1119-1158` refuses the union of `erBodyFallback` and `erOverflowTaintedFns` with distinct diagnostics naming the `?proof-required` + Leanstral escape and the INT-2 path. `.verified.json` sidecars gain optional `overflow_tainted: true` (only-when-true) with invalidate-on-missing for pre-v0.10.8 DLVerified body-faithful entries at `VerifiedCache.hs:158-216`, eliminating silent under-strictness on stale sidecars. Trust-report JSON gains top-level `overflow_tainted_fns` and per-entry `overflow_tainted` (additive, `trust_report_version` stays `1.1.0`). Obligation-report trust channel gains `overflow_tainted` per clause at `ObligationAssembly.hs:114-119, 802-812`. Eight `EvidenceRecord` positional construction sites updated mechanically across `Module.hs`, `TrustReport.hs`, `PBT.hs`, `Main.hs`; ~30 test-side positional constructions in `Spec.hs` likewise updated. 16 new tests under `INT-1 (v0.10.8): overflow taint propagation`; `examples/banking_ledger/banking.llmll.verified.json` regenerated with `safe-subtract` carrying the tag. Closes the DRIFT-1 §3 doc-lead gating per row `:300`. Inside-freeze, narrowing — no new syntax, no new builtins, no new SMT theory, no solver-time delta. Trigger set becomes dormant on `int` post-INT-2 and re-arms on `machine-int` per `int-2-boundary-shims.md` §4 / `int-3-machine-int-sketch.md` §3.2. 672 Haskell + 37 Python tests. No milestone advancement. See `CHANGELOG.md` v0.10.8.

**Feature freeze** active from v0.8.1a through v0.10 ship.

**v0.7 result:** All 4 items shipped. 294 Haskell + 37 Python tests. 3 discovered issues resolved (Module.hs `max`, compare tests, round-trip serialization).

**v0.8.0 result:** All 10 items shipped. BODY-VC-0 ✅ → BODY-VC-1 ✅ → BODY-VC-2 ✅ → BODY-VC-3 ✅. BODY-VC-T (25 tests) validated all translation rules. EOp soundness fix and clause-level emission tracking closed two critical soundness gaps. SUPP-DEBT, EVENT-LOG, SPEC-FOUNDATION, SPEC-EFFECTS, SPEC-TRUST all shipped. 320 Haskell + 37 Python tests.

**v0.8.1a scope:** Documentation only. Rename "Dependent Types" → "Refinement Type Aliases." Add verification matrix to LLMLL.md, README, and one-pager. Document integer overflow model gap. ~1 day, zero code risk.

**v0.8.1a result:** All 9 items shipped (commit `58c0f26`, 2026-04-30). RENAME-1/2 ✅, MATRIX-1/2/3 ✅, BOUNDARY-1/2 ✅, ROADMAP-1/2 ✅. No code changes, no test changes. 320 Haskell + 37 Python tests unchanged.

**v0.8.1b scope:** Evidence model refactor. Replace `VerificationLevel` total order with four-tier `DisplayLevel` partial order + assumption taxonomy. Touches `Syntax.hs`, `VerifiedCache.hs`, `TrustReport.hs`, `SpecCoverage.hs`, `Contracts.hs`, `Module.hs`, `Main.hs`. Design review (EVID-0) required before implementation. ~3–5 days.

**v0.8.1b result:** All 10 items shipped (commit `bf98797`, 2026-05-01). EVID-0 ✅ (design spec), EVID-1/1a–1e ✅ (core ADT + 12 consumer files), EVID-2 ✅ (VerifiedCache rewrite), EVID-3 ✅ (TrustReport), EVID-4 ✅ (SpecCoverage), EVID-5 ✅ (Contracts), EVID-6 ✅ (Module), EVID-7 ✅ (Main), EVID-8 ✅ (spec update), EVID-T ✅ (test migration). 14 source files + test suite updated. Hard break: no backward compat for old `.verified.json`. 322 Haskell + 37 Python tests.

**v0.9 result:** All 8 items shipped (2026-05-01). COMP-0 ✅ (Rev 2 design spec), COMP-1 ✅ (CallVC + ContractEnv + call-pre emission), COMP-2 ✅ (SCC detection), COMP-3 ✅ (EMatch on Result), COMP-4 ✅ (trust degradation via existing enrichEntry), COMP-5 ✅ (call-pre diagnostics), COMP-6 ✅ (--strict-verified-core), COMP-T ✅ (18 golden tests). 4 source files + test suite updated. 452 Haskell + 37 Python tests.

**v0.9.1 result (module system hardening):** Professor's review audit (2026-05-01). Spec restructured (§8.3 ordering, §8.5 namespace resolution, §8.6 open semantics, §8.7 export scope). Cycle detection fixed (`Set` → list stack + visit-order slicing). `life_sexp` example corrected (`open` declarations added). `ModuleEnv` TODO annotated. 11 new module system tests (M-01–M-07). 474 Haskell + 37 Python tests. 4 items deferred: MOD-1 (v0.10), MOD-2/3/4/5 (future — per-module codegen, strict loader, interface wiring).

**v0.10 result:** All 8 items shipped (2026-05-03). OBLIG-0 ✅ (design spec Rev 8), MOD-1 ✅ (cross-module ContractEnv), OBLIG-1 ✅ (enriched CheckoutToken — 7 new fields), OBLIG-2 ✅ (ObligationAssembly.hs — 800+ lines, --obligation-report flag), OBLIG-3 ✅ (EMatch branch obligations with parent-id linkage), OBLIG-4 ✅ (arithmetic repair suggestions, cap-8), OBLIG-5 ✅ (repair loop end-to-end), OBLIG-B ✅ (3 benchmark programs, 11 golden tests). GuardClassifier.hs extracted from FixpointEmit.hs. 3 bugs fixed (F6, F7, R2). 556 Haskell + 37 Python tests.

**v0.10.1 result (patch):** `llmll version` command + `--version` flag. Exit code fixes: `check`/`holes` rc=1 on parse errors, `--help` rc=0 on all 17 subcommands. Structural + transitive `expandAlias` with cycle guard: composite type traversal (`TList`, `TMap`, `TResult`, `TPair`, `TPromise`, `TFn`, `TSumType`, `TDependent`), alias-chain chasing, DFS cycle detection. `compatibleExpanded` helper replaces 13 `compatibleWith` call sites. Unsound `TCustom`/`TSumType` bridge removed. `?delegate-async` normalization (`return_type` is inner `T`). `DelegationError` parse-time normalization. ADT constructor auto-registration with collision detection. `withFunctionContext` combinator. macOS build warning suppression. 570 Haskell + 37 Python tests (+14 alias resolution tests).

**Parked items:** LEAN-GA, TRUST-2b, MCP — triggered by external availability, not on the critical path.

Research-track items are tracked separately in [research-track.md](research-track.md) — not part of the compiler engineering backlog. WASM is a confirmed future direction, not pinned to a version.

### What Changed from LLMLL.md §14

| Version | Original | Revised |
| ------- | -------- | ------- |
| **v0.1.2** | JSON-AST + FFI stdlib | JSON-AST + **Haskell codegen** + hole-density validator + Docker sandbox. `effectful` typed effect row **[UNIMPLEMENTED]** — `Command` emitted as plain `IO`. |
| **v0.2** | Module system (unscheduled) + Z3 liquid types | Module system **first** → **decoupled liquid-fixpoint** (replaces Z3 binding project) → pair-type fix + `--sketch` API |
| **v0.3** | Agent coordination + Lean 4 agent *(to be built)* | Agent coordination + **Leanstral MCP integration** + `do`-notation ✅ (PRs 1–3) + pair destructuring ✅ (PR 4) + stratified verification ✅ + scaffold CLI ✅ + async codegen ✅ + checkout/patch primitives ✅ — **12/12 shipped** |
| **v0.3.1** | *(split from v0.3)* | Leanstral MCP integration + Event Log spec — **shipped** |
| **v0.3.2** | 2026-04-16 | Trust hardening (`--trust-report`, cross-module propagation tests) + GHC WASM PoC — **shipped** |
| **v0.3.3** | *(new)* | Agent orchestration: `--json --deps` hole flag (compiler) + Python orchestrator `llmll-orchestra` v0.1 (external) + **agent prompt semantic reference** (Phase A) — **shipped** |
| **v0.3.4** | *(new)* | Compiler-emitted agent spec: `llmll spec` (Phase B) + Spec Faithfulness property tests — **shipped** |
| **v0.3.5** | *(new)* | Context-aware checkout (Phase C, C1–C6) + C5 monomorphization + orchestrator E2E + weak-spec counter-examples — **shipped** |
| **v0.4** | *(was: WASM + checkout)* | Lead Agent (skeleton gen) + **U-lite soundness** + **CAP-1** (capability enforcement) + invariant registry + obligation mining + JSON parsing — **shipped** |
| **v0.5** | *(revised 2026-04-21)* | **U-full Algorithm W** (occurs check + TVar-TVar closure + bound-TVar consistency) + `effectful` WASM compat spike (**GO**) — **shipped** |
| **v0.6.0** | *(revised 2026-04-23)* | Spec quality: **spec coverage gate + suppression governance (P0) ✅** + **frozen ERC-20 benchmark (P0) ✅** + **clause-level provenance (P1) ✅** + **Leanstral claim narrowing ✅** + **claim-to-evidence table ✅** — **shipped (2026-04-22)**. |
| **v0.6.1** | *(shipped, 2026-04-23)* | TOTP frozen benchmark (BM2-1..5) ✅ + hub query-by-signature (HUB-1..3) ✅ + crypto builtins (§13.11) ✅ + v0.6.0 carryover (PROV-3, BM-4) ✅ — **shipped (2026-04-23)**. |
| **v0.6.2** | *(shipped, 2026-04-24)* | Algebraic interface laws: `def-interface :laws` with `for-all` property syntax + QuickCheck codegen + VSM-1 backfill — **shipped (2026-04-24)**. Research-track items (Spec-from-RFC, Synthetic Corpus, Differential Impl) moved to unversioned Research Track. |
| **v0.6.3** | *(shipped, 2026-04-26)* | Trust model fixes: 7 critical bugs (BUG-1..7). `tcStrictMode` typecheck gate, transitive trust closure, body-faithful stripping guard, proof laundering protection, contract instrumentation in build pipeline, termination documentation correction — **shipped (2026-04-26)**. |
| **v0.7** | *(reorganized, 2026-04-28)* | **Hardening:** BUILTIN-1/2 (total builtins), DO-1 (discarded command warning), TRUST-2a (`VLProvenSMT` + `Ord` removal). 294 tests. — **shipped (2026-04-29)**. |
| **v0.8.0** | *(new, 2026-04-28)* | **Faithfulness Core:** BODY-VC (body-faithful verification conditions — design spec ✅ + `bodyToPred` + emitter integration + postcondition body-faithfulness per-function + golden tests) + SUPP-DEBT + EVENT-LOG + SPEC-FOUNDATION. No external blockers. — **shipped (2026-04-29)**. |
| **v0.8.1a** | *(new, 2026-04-30)* | **Documentation Boundary Clarity:** Rename "Dependent Types" → "Refinement Type Aliases." Verification matrix in LLMLL.md, README, one-pager. Integer overflow model gap. ~1 day, docs only. — **shipped (2026-04-30)**. |
| **v0.8.1b** | *(new, 2026-04-30)* | **Evidence Model Refactor:** Four-tier `DisplayLevel` partial order replaces `VerificationLevel` total order. `EvidenceRecord` with body-faithfulness + source provenance. `AssumptionKind` taxonomy. Hard break for `.verified.json`. 14 source files + test suite. 322 tests (+2). — **shipped (2026-05-01)**. |
| **v0.9** | *(shipped, 2026-05-01)* | **Compositional Verification:** Assume-guarantee `EApp` encoding (`CallVC`, `ContractEnv`, three-way pre distinction). `EMatch` on `Result` (two-path encoding). SCC recursive fallback via `stronglyConnComp`. Call-pre constraint emission (PROVE polarity). `--strict-verified-core` mode. 452 tests (+130). **v0.9.1:** Module system hardening (spec, cycle fix, 11 tests, `life_sexp` fix). 474 tests. — **shipped (2026-05-01)**. |
| **v0.10** | *(shipped, 2026-05-03)* | **Obligation-Guided Agent Coding:** Structured obligation reports (JSON) for holes, unproven contracts, call-site failures. Three channels: type, contract, trust. `EMatch` branch obligations. Repair suggestions. Function lists. Benchmark suite (B1/B3/B5). 556 tests (+104). — **shipped (2026-05-03)**. |
| **Parked** | *(was v0.8.1, 2026-04-28)* | LEAN-GA, TRUST-2b, MCP — externally blocked, moved to parking lot (2026-04-30). |
| **Future** | *(unversioned, 2026-04-21)* | WASM build target + WASI capability enforcement — **confirmed direction, not version-pinned** |

### Items Removed from Scope

| Item | Reason |
| ---- | ------ |
| Rust FFI stdlib (`serde_json`, `clap`, etc.) | Replaced by native Hackage imports |
| Z3 binding layer (build from scratch) | Replaced by decoupled liquid-fixpoint backend (no GHC plugin) |
| Lean 4 proof agent (build from scratch) | Replaced by Leanstral MCP integration |
| Python FFI tier | Breaks WASM compatibility; dynamically typed; dropped from spec |
| Opaque `Command` type | Replaced by typed effect row (`Eff '[...]`) |

## Shipped Releases

<details><summary><strong>Click to expand shipped release details (v0.1.1 → v0.10.0)</strong></summary>


## v0.10 — Obligation-Guided Agent Coding ✅ SHIPPED

**Theme:** Make LLMLL's obligation reports the clearest machine-readable goal state for code synthesis.

> Shipped 2026-05-03. 8 items. 556 Haskell + 37 Python tests.

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | OBLIG-0 | Design spec: obligation report JSON schema (Rev 8 approved) | ✅ |
| 2 | MOD-1 | Cross-module `ContractEnv` (`meContracts` in `ModuleEnv`) | ✅ |
| 3 | OBLIG-1 | Enriched `CheckoutToken` (7 new fields: contract context, path conditions, assumptions) | ✅ |
| 4 | OBLIG-2 | `ObligationAssembly.hs` + `--obligation-report` flag + `GuardClassifier.hs` extraction | ✅ |
| 5 | OBLIG-3 | `EMatch` branch obligations (two-pass, parent-id linkage) | ✅ |
| 6 | OBLIG-4 | Repair suggestions (`generateCandidates`, O(n²) bounded, cap-8) | ✅ |
| 7 | OBLIG-5 | Repair loop integration (end-to-end `--obligation-report` pipeline) | ✅ |
| 8 | OBLIG-B | Benchmark suite: 3 programs (B1/B3/B5), 11 golden tests, fingerprint stability | ✅ |

**Bugs fixed:** F7 (path condition key mismatch), F6 (`inferScrutineeType` for `EApp`), R2 (`resolveType` strips `TDependent`).


## v0.9 — Compositional Verification ✅ SHIPPED

**Theme:** Extend body-faithful verification from isolated leaf functions to function call chains.

> Shipped 2026-05-01. 8 items. 452 Haskell + 37 Python tests.

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | COMP-0 | Design spec: assume-guarantee encoding rules (Rev 2 approved) | ✅ |
| 2 | COMP-1 | `CallVC` constructor, `ContractEnv`, call-pre emission with PROVE polarity | ✅ |
| 3 | COMP-2 | SCC detection via `stronglyConnComp`, recursive fallback | ✅ |
| 4 | COMP-3 | `EMatch` on `Result` (two-path encoding) | ✅ |
| 5 | COMP-4 | Transitive trust degradation via `evidenceMeet` | ✅ |
| 6 | COMP-5 | `call-pre:` diagnostics | ✅ |
| 7 | COMP-6 | `--strict-verified-core` CLI flag | ✅ |
| 8 | COMP-T | 18 golden tests | ✅ |

**v0.9.1 (module system hardening):** Spec restructured (§8.3/5/6/7). Cycle detection fixed (`Set` → list stack + visit-order slicing). `life_sexp` example corrected. 11 new module system tests (M-01–M-07). 474 Haskell + 37 Python tests.


## v0.8.1b — Evidence Model Refactor ✅ SHIPPED

**Theme:** Replace the linear trust lattice with a structured evidence model.

> Shipped 2026-05-01. 10 items. 322 Haskell + 37 Python tests.

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | EVID-0 | Design spec: evidence model ADT, JSON schema, assumption taxonomy | ✅ |
| 2 | EVID-1/1a–1e | `EvidenceRecord` type, `DisplayLevel` ADT, 12 consumer files updated | ✅ |
| 3 | EVID-2 | `VerifiedCache.hs` rewrite (hard break for old `.verified.json`) | ✅ |
| 4 | EVID-3 | `TrustReport.hs` — display-level projection, assumption display | ✅ |
| 5 | EVID-4 | `SpecCoverage.hs` — evidence tier classification | ✅ |
| 6 | EVID-5 | `Contracts.hs` — stripping uses `DLVerified` + `body_faithful` | ✅ |
| 7 | EVID-6 | `Module.hs` — `mergeCS` lattice meet | ✅ |
| 8 | EVID-7 | `Main.hs` — CLI output with new labels | ✅ |
| 9 | EVID-8 | LLMLL.md §4.4.1, §5.3.3, §5.3.4 — new trust tier vocabulary | ✅ |
| 10 | EVID-T | Test migration — lattice property tests | ✅ |


## v0.8.1a — Documentation Boundary Clarity ✅ SHIPPED

**Theme:** Make the verification boundary impossible to miss. No code changes, no regression risk.

> Shipped 2026-04-30. 9 items.

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | RENAME-1 | §3.4 "Dependent Types" → "Refinement Type Aliases" | ✅ |
| 2 | RENAME-2 | One-pager: removed Idris/Lean comparison | ✅ |
| 3 | MATRIX-1 | Per-construct verification matrix in LLMLL.md §5.3.5 | ✅ |
| 4 | MATRIX-2 | Compressed verification matrix in README | ✅ |
| 5 | MATRIX-3 | Compressed verification matrix in one-pager | ✅ |
| 6 | BOUNDARY-1 | One-pager QF-LIA boundary rewrite | ✅ |
| 7 | BOUNDARY-2 | Integer overflow model gap documented | ✅ |
| 8 | ROADMAP-1 | Roadmap restructured with v0.8.1a/v0.8.1b/v0.9 | ✅ |
| 9 | ROADMAP-2 | One-pager "What's Next" table updated | ✅ |

**Test count:** 320 Haskell (unchanged), 37 Python (unchanged). No code changes.


## v0.8.0 — Faithfulness Core ✅ SHIPPED

**Theme:** Close the faithfulness gap. 320 Haskell tests (was 294; +26).

> Shipped 2026-04-29. 10 items.

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | BODY-VC-0 | Design spec (approved by all 5 agents) | ✅ |
| 2 | BODY-VC-1 | `bodyToPred` for QF-LIA fragment | ✅ |
| 3 | BODY-VC-2 | Wire into `emitFnConstraints` | ✅ |
| 4 | BODY-VC-3 | `csPostBodyFaithful` per-function marking | ✅ |
| 5 | BODY-VC-T | 25 new tests | ✅ |
| 6 | SUPP-DEBT | `suppression_debt` in `--spec-coverage` | ✅ |
| 7 | EVENT-LOG | Orchestration event log schema | ✅ |
| 8 | SPEC-FOUNDATION | §0.1 "Semantic Foundation" | ✅ |
| 9 | SPEC-EFFECTS | §3.3 "Effect Model" | ✅ |
| 10 | SPEC-TRUST | Elevated `(trust ...)` documentation | ✅ |


## Pre-v0.7 Hygiene ✅

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | TEST-DRIFT | Fix Python dry-run Lead Agent fixture | ✅ |
| 2 | DOC-DRIFT | Reconcile LLMLL.md with `SpecCoverage.hs` JSON output | ✅ |


## v0.7 — Hardening ✅ SHIPPED

**Theme:** Close the remaining concrete, fully-spec'd fixes from the external review.

> Shipped 2026-04-29. 4 items, 3 discovered issues resolved.

| # | ID | Description | Status |
|---|-----|-------------|--------|
| 1 | BUILTIN-2 | `string-char-at` negative index guard (`i >= 0` check, returns `""`) | ✅ |
| 2 | BUILTIN-1 | `regex-match` → POSIX ERE via `regex-tdfa`. Invalid patterns return `False` (total). `isInfixOf` import removed. `regex-tdfa` added to generated `package.yaml`. | ✅ |
| 3 | DO-1 | Discarded command warning. Intermediate `TCustom "Command"` in do-blocks. `checkDiscardedCommand` helper. Warning-only; hard error deferred to v0.8 (DO-2). | ✅ |
| 4 | TRUST-2a | `VLProvenSMT { vlSMTSolver }` constructor. `Ord` instance removed. `trustCovers`/`trustMin`/`isProvenLevel`/`vlProverName` helpers. 10 consumer files updated. `.verified.json` serializes as `"proven-smt"`. | ✅ |
| 5 | — | Discovered: `Module.hs:mergeCS` used `max` on removed `Ord`. Fixed with `vlTier`. | ✅ |
| 6 | — | Discovered: 5 `compare` tests replaced with `vlTier`/`trustCovers`/`isProvenLevel` + `VLProvenSMT` tier equality test. | ✅ |
| 7 | — | Discovered: round-trip test updated for `"proven-smt"` serialization. | ✅ |

**Test count:** 294 Haskell (was 289; +5 trust-tier), 37 Python (unchanged).

---

## v0.6.3 — Trust Model Fixes ✅ SHIPPED

**Theme:** Stabilize the trust model, enforce type-checking gates, and ensure verifiable correctness.

> 7 critical bugs from the v0.6.3 engineering audit. All resolved.

| # | Bug | Action | Status |
|---|-----|--------|--------|
| 1 | BUG-1 | Remove `result` from precondition environments; hard error on `result` in `pre` | ✅ |
| 2 | BUG-7 | `isTaintedProof`/`proofToLevel` guards in ProofCache; mock prover tagged `"mock"` | ✅ |
| 3 | BUG-5 | Termination documentation corrected (§4.2, §5.3.3): non-negativity only, not strict descent | ✅ |
| 4 | BUG-4 | `tcStrictMode` field + `typeCheckStrict`/`typeCheckStrictWithCache` + gates in `doBuild`/`doBuildFromJson`/`doRun`/`doVerify` + `--strict` CLI flag | ✅ |
| 5 | BUG-2 | `instrumentContracts` replaces `applyContractsMode` in build pipeline; `runtime-error` lowered to `error` in CodegenHs | ✅ |
| 6 | BUG-6 | `isBodyFaithful` guard on `filterContracts` (returns `False` for all current provers) | ✅ |
| 7 | BUG-3 | `transitiveClose` fixed-point iteration; `enrichEntry` with `teEffectiveLevel = min(self, transitive deps)` | ✅ |
| 8 | — | Regression sweep: 289/289 tests, ERC-20 (11/11), TOTP (14/14) benchmarks green | ✅ |

**Test count:** 289 Haskell + 37 Python (unchanged count; 2 test expectations updated for BUG-6 behavior change)

---

## v0.6.2 — Algebraic Interface Laws ✅ SHIPPED

**Theme:** First-class algebraic law enforcement for `def-interface`.

> v0.6.2 is a single-feature release. VSM-1 was completed during v0.6.1 (all three verifier examples already had `VERIFICATION_SCOPE.md` files). Research-track items (Spec-from-RFC, Synthetic Corpus, Differential Impl) moved to **Research Track (unversioned)** above.

| # | Action | Effort | Status |
|---|--------|--------|--------|
| VSM-1 | Add verification-scope matrices to verifier examples | 0.5 day | ✅ (already complete) |
| LAWS-1 | `Syntax.hs`: `defInterfaceLaws :: [Expr]` → `[Property]` | 0.5 hr | ✅ |
| LAWS-2 | `Parser.hs`: `:laws [(for-all ...)]` clause parsing | 1 hr | ✅ |
| LAWS-3 | `ParserJSON.hs`: JSON-AST law parsing (`parseLawProperty`) | 0.5 hr | ✅ |
| LAWS-4 | `TypeCheck.hs`: for-all scoping (methods + bindings in scope) | 1 hr | ✅ |
| LAWS-5 | `CodegenHs.hs`: QuickCheck `prop_` emission | 2 hr | ✅ |
| LAWS-6 | `AstEmit.hs`: JSON-AST law emission (round-trip compat) | 0.5 hr | ✅ |
| LAWS-7 | `SpecCoverage.hs`: separate "Interface laws" section in report | 1 hr | ✅ |
| LAWS-PBT | `PBT.hs`: wire interface laws into `runPropertyTests` | 0.5 hr | ✅ |
| LAWS-8 | Tests: 10 new tests (T1–T10), 279 existing tests pass | 2 hr | ✅ |

**Test count:** 289 Haskell + 37 Python

```lisp
;; Example: idempotent normalizer
(def-interface Normalizer
  [normalize (fn [x: string] -> string)]
  :laws [(for-all [x: string] (= (normalize (normalize x)) (normalize x)))])
```

---

## v0.6.1 — TOTP Benchmark & Hub Query ✅ SHIPPED

**Theme:** Second frozen benchmark (RFC 6238 TOTP), hub query-by-signature, and v0.6.0 carryover closure.

### Cryptographic Builtins (§13.11)

- `hmac-sha1 : bytes[20] → bytes[20] → bytes[20]` — RFC 2104 HMAC. Preamble in `CodegenHs.hs` using `Data.Bits.xor`. ✅
- `sha1 : bytes[20] → bytes[20]` — Simplified SHA-1 stub. Trust level: `asserted`. ✅

### TOTP RFC 6238 Benchmark

| # | Action | Status |
|---|--------|--------|
| BM2-1 | `examples/totp_rfc6238/totp.ast.json` — TOTP skeleton with contracts derived from RFC 6238 | ✅ |
| BM2-2 | `examples/totp_rfc6238/totp_filled.ast.json` — filled version with 4 check blocks | ✅ |
| BM2-3 | `examples/totp_rfc6238/EXPECTED_RESULTS.json` — frozen ground truth with verification-scope matrix | ✅ |
| BM2-4 | CI gate: `make benchmark-totp` (14 assertions) | ✅ |
| BM2-5 | `examples/totp_rfc6238/WALKTHROUGH.md` — RFC clause traceability via `:source` annotations | ✅ |

### Hub Query-by-Signature

| # | Action | Status |
|---|--------|--------|
| HUB-1 | `LLMLL.HubQuery` module — brute-force scan of `~/.llmll/modules/` with `structuralMatch` (TVar wildcards, TDependent stripping, order-sensitive) | ✅ |
| HUB-2 | `llmll hub query --signature` CLI subcommand (text + JSON output) | ✅ |
| HUB-3 | `CheckoutToken.ctHubSuggestions` field scaffolded (always `Nothing` — populated by future orchestrator wiring) | ✅ |

### v0.6.0 Carryover

| # | Action | Status |
|---|--------|--------|
| PROV-3 | `:source` annotations threaded through `--trust-report` text and JSON output (`formatEntry`, `entryJson`) | ✅ |
| BM-4 | ERC-20 CI gate: `scripts/benchmark-erc20.sh` (11 assertions), `make benchmark-erc20` | ✅ |

---

## v0.6.0 — Specification Quality ✅ SHIPPED

**Theme:** Attack the acknowledged bottleneck — specification coverage and quality.

> P0 items (spec coverage gate, frozen ERC-20 benchmark, suppression governance, clause-level provenance) **shipped 2026-04-22**. Leanstral claim narrowing and claim-to-evidence table also shipped.

### Spec Coverage Gate (SC-1..SC-4) ✅

| # | Action | Status |
|---|--------|--------|
| SC-1 | `llmll verify --spec-coverage` — walk `[Statement]`, count functions, emit coverage report | ✅ |
| SC-2 | `effective_coverage` metric in `quality.py` | ✅ |
| SC-3 | Coverage threshold parameter in `--mode lead` / `--mode auto` | ✅ |
| SC-4 | Blocking behavior: `--mode auto` fails below threshold | ✅ |

### Suppression Governance (`weakness-ok`) ✅

- `SWeaknessOk` AST node with mandatory reason string. ✅
- Governance warnings: WO-1 (`W601`), WO-2 (`W602`), D10 (`W603`). ✅
- Trust report integration ("Intentional Underspecification" section). ✅

### Frozen ERC-20 Benchmark (BM-1..BM-3, BM-5) ✅

| # | Action | Status |
|---|--------|--------|
| BM-1 | `examples/erc20_token/erc20.ast.json` — skeleton | ✅ |
| BM-2 | `examples/erc20_token/erc20_filled.ast.json` — filled | ✅ |
| BM-3 | `examples/erc20_token/EXPECTED_RESULTS.json` — frozen ground truth with verification-scope matrix | ✅ |
| BM-5 | `examples/erc20_token/WALKTHROUGH.md` | ✅ |

### Clause-Level Provenance (PROV-1, PROV-2, PROV-4) ✅

| # | Action | Status |
|---|--------|--------|
| PROV-1 | `sourceRef :: Maybe Text` field in `Syntax.hs` | ✅ |
| PROV-2 | Parse `:source` in `Parser.hs` and `ParserJSON.hs` | ✅ |
| PROV-4 | Document in `LLMLL.md §4.1` and `getting-started.md` | ✅ |

### Leanstral Claim Narrowing (CLAIM-1..2) ✅

| # | Action | Status |
|---|--------|--------|
| CLAIM-1 | Revise `one-pager.md` — distinguish shipped SMT from designed-but-mock Lean 4 | ✅ |
| CLAIM-2 | Add `Verification Scope` subsection to `LLMLL.md §5.3` | ✅ |

### Verification-Scope Matrix Policy (VSM-2) ✅

| # | Action | Status |
|---|--------|--------|
| VSM-2 | Document policy in `docs/getting-started.md` | ✅ |

---

## v0.5 — U-Full Soundness ✅ SHIPPED

**Theme:** Complete sound unification — closes the last known unsoundness in the type checker.

> **Source:** Language team roadmap proposal (2026-04-19). Algorithm W split into U-lite (v0.4) and U-full (v0.5) per compiler team review.
>
> **Decision (2026-04-21):** WASM build target removed from v0.5 and moved to unversioned future work. U-Full is a type-system correctness obligation that directly services one-shot correctness. WASM is an operational deployment concern — Docker + CAP-1 provide two functional enforcement layers for the current threat model.

### U-Full — Sound Unification ✅ shipped

> **TDependent resolution applied:** Strip-then-Unify (Option A, Language Team 2026-04-19). `TDependent` strips to base type during unification — no constraint propagation, no proof obligations. This is consistent with the two-layer architecture.

Complete Algorithm W with occurs check and let-generalization.

| # | Action | Status |
|---|--------|--------|
| U1-full | Occurs check in unification (`TVar "a"` cannot unify with `TList (TVar "a")`). `occursIn` helper is structurally total over the `Type` ADT (including `TSumType`). | ✅ |
| U2-full | Let-generalization for top-level `def-logic` / `letrec` via TVar-TVar wildcard closure + bound-TVar consistency fix (recursive `structuralUnify` replaces `compatibleWith` at L1044, Language Team Issue 2). Inner `let`-bound lambdas deferred to v0.7. L1055 asymmetric wildcard documented as safe under per-call-site scoping (Language Team Issue 3). | ✅ |
| U3-full | Regression test sweep: 264 tests (257 existing + 7 new U-Full), 0 failures | ✅ |

### `effectful` WASM Compatibility Spike ✅ shipped

> **Source:** Extracted from WASM Phase 0 as a standalone risk-reduction item (2026-04-21).

Binary test: do `effectful`'s C shims compile under `wasm32-wasi`? Result: **GO** — no C shims, no linker errors, correct execution. See [`docs/effectful-wasm-spike.md`](effectful-wasm-spike.md).

| # | Action | Status |
|---|--------|--------|
| EFF-1 | Install `ghc-wasm-meta` (GHC 9.12.4) + `wasmtime` (v44.0.0), compile a minimal `effectful` (v2.6.1.0) program under `wasm32-wasi` | ✅ |
| EFF-2 | Document result: **GO** — `effectful-core` and `effectful` compile with zero C shim failures. Binary executes correctly in wasmtime. | ✅ |

---


## v0.4 — Lead Agent + U-Lite Soundness ✅ SHIPPED

**Theme:** Close the last manual step (skeleton authoring) and fix the most visible soundness gap in unification.

> **Source:** Language team roadmap proposal (2026-04-19). Algorithm W split into U-lite (v0.4) and U-full (v0.5) per compiler team review.

### Lead Agent — Automated Skeleton Generation (~10 days, incremental)

> **Source:** [lead-agent.md](design/lead-agent.md)

Phased delivery shipping incrementally within v0.4:

| Phase | Deliverable | Effort | Status |
|-------|-------------|--------|--------|
| Phase 0 | `--mode plan` — intent → structured architecture plan (JSON) | ~3 days | ✅ |
| Phase 1 | `--mode lead` — plan → JSON-AST skeleton, validated by `llmll check`, quality heuristics | ~4 days | ✅ |
| Phase 2 | `--mode auto` — lead → fill → verify in sequence | ~3 days | ✅ |

**Acceptance criteria:**

- `llmll-orchestra --mode auto --intent "Build an auth module..."` produces a filled, verified program
- Quality heuristics flag: low parallelism, all-string types, missing contracts, unassigned agents
- Lead Agent uses `llmll spec` output in its system prompt

**Open questions (from lead-agent.md, to resolve during implementation):**

- Q1: Same or different model for lead vs specialist? (Affects spec format — `llmll spec` is model-agnostic, JSON output may not be)
- Q3: How to evaluate skeleton quality beyond type-correctness?
- Q4: When quality heuristics fire (low parallelism, all-string types, missing contracts, unassigned agents), what does the Lead Agent do? Options: **(a)** reject and re-prompt with the specific heuristic failure (bounded to 2 retries), **(b)** accept with structured warnings in skeleton metadata, **(c)** auto-repair (e.g., add `(post true)` for missing contracts, assign `@general-agent` for unassigned holes). Decide during Phase 0 implementation.

### U-Lite — Concrete Type Unification (~5 days)

> **Source:** [agent-prompt-semantics-gap.md §1](design/agent-prompt-semantics-gap.md) — parametricity gap
>
> **Decision:** Algorithm W split into two phases (compiler team review, 2026-04-19). U-lite catches obvious type errors. U-full (v0.5) adds occurs check and let-generalization.
>
> **TDependent resolution (Language Team, 2026-04-19):** Strip-then-Unify (Option A). Unification strips `TDependent` to its base type; refinement constraints are NOT propagated through substitution. This formalizes existing `compatibleWith` behavior and preserves the two-layer architecture (types = structure, contracts = behavior). Full analysis: `algorithm_w_tdependent_resolution.md`.

Replace `compatibleWith (TVar _) _ = True` with substitution-based unification **for concrete types only**. `TVar` still wildcards against other `TVar` to preserve existing polymorphic builtin behavior.

> **Substitution scope (Language Team review, 2026-04-20):** Per-call-site with fresh type variable instantiation at each `EApp`. Each call to a polymorphic function gets its own α-renamed type variables and a local substitution map. The substitution does NOT escape the `EApp` boundary. This prevents cross-call conflicts (e.g., `list-head xs` binding `a → int` would incorrectly block `list-head ys` where `ys : list[string]` if scoping were per-function).

#### Pre-implementation: Regression triage (P0-3)

Before starting U-lite implementation:

| # | Task |
|---|------|
| 1 | Run the full test suite with a **diagnostic-only** version of U-lite that logs substitution failures but doesn't change `compatibleWith` behavior. Count divergences. |
| 2 | Classify each divergence: **(a)** true bug (currently silently accepted, will now correctly error), or **(b)** cosmetic (different message, same outcome). |
| 3 | Produce an explicit list: "The following N programs currently type-check incorrectly. U-lite fixes them." This is the acceptance criterion. |
| 4 | Assess `TSumType` wildcarding impact: `compatibleWith (TSumType _) (TSumType _) = True` conflates all sum types. Run with fix, count breakage. If no breakage, include in U-lite. If breakage, defer to U-full with documented test case. (Language Team §6.1, 2026-04-20) |
| 5 | No `--legacy-compat` flag. If U-lite surfaces true bugs, those are bugs — not options. |

#### Implementation steps

| # | Action | Status |
|---|--------|--------|
| U1-lite | Per-call-site substitution with fresh type variable instantiation at each `EApp`: α-rename all `TVar`s in the looked-up function signature, create a local substitution map, unify arguments against freshened parameter types. Substitution map does NOT escape the `EApp` boundary. | ✅ |
| U2-lite | Re-type `first`/`second` from `TVar "p" → TVar "a"` to `TPair a b → a` / `TPair a b → b` in `builtinEnv` | ✅ |
| U3-lite | Ensure all 225+ existing tests still pass (divergence list from triage step) | ✅ |
| U4-lite | Add tests for currently-silent type errors: `list-head 42`, `list-map 5 f` | ✅ |
| U5-lite | Test per-call-site scoping: `list-map [1,2,3] (fn [x: string] x)` → type error (element type mismatch caught by per-call-site substitution). (Language Team verification requirement, 2026-04-20) | ✅ |
| U6-lite | Regression test: `(type PositiveInt (where [x: int] (>= x 0)))`, `list-head` on `list[PositiveInt]` → `Result[int, string]` (alias expansion + stripDep). | ✅ |
| U7-lite | If TSumType triage (pre-implementation step 4) shows no breakage: fix `TSumType` wildcarding in `compatibleWith`. | ✅ |

> [!WARNING]
> **U2-lite (`first`/`second` retype) is prerequisite.** The current `TVar "p"` hack exists because the old unifier couldn't express the pair constraint. With substitution tracking, `first : TPair a b → a` works correctly.

#### `letrec` handling

> LLMLL's `letrec` has explicit type annotations. Under U-lite, the self-call unifies against the declared signature — no special treatment needed. Under U-full, `letrec` is not let-generalized (standard monomorphic recursion). The fixpoint emitter is unaffected — it emits constraints for the function boundary, not for recursive call sites.

#### Alias-through-substitution ordering

Under U-lite, the `unify` function must apply the current substitution before alias expansion:

```haskell
unify ctx expected actual = do
    s <- getSubst
    let expected' = applySubst s expected
        actual'   = applySubst s actual
    expected'' <- expandAlias expected'
    actual''   <- expandAlias actual'
    -- strip TDependent, then structural unify
    unifyStructural ctx (stripDep expected'') (stripDep actual'')
```

> **Regression test:** Define `(type PositiveInt (where [x: int] (> x 0)))`. Call `list-head` on a `list[PositiveInt]`. Verify the result type is `Result[int, string]` (not `Result[PositiveInt, string]` — the dependent wrapper is stripped after alias expansion).

**Acceptance criteria:**

- `list-head 42` produces a type error (currently silently accepted)
- `first (pair 1 "hello")` infers type `int` (not `TVar "a"`)
- `list-map [1,2,3] (fn [x: string] x)` produces a type error (per-call-site substitution)
- All existing examples and tests pass
- Parametricity prompt note remains in agent prompt
- Regression triage list reviewed and all true bugs documented

**Explicitly deferred to U-full (v0.5):**

- Occurs check
- Let-generalization
- `TVar-TVar` wildcard closure (accepted for U-lite per Language Team review 2026-04-20; must close in U-full)

### CAP-1 — Capability Enforcement in TypeCheck.hs (~2 days)

> **Source:** Professor critique P0-1 (2026-04-19). The spec (LLMLL.md §3.2, §10.7, §14) claimed `effectful` typed effect rows enforce capability safety at compile time. Verified false: `wasi.*` functions are unconditionally in `builtinEnv` and type-check without a matching `import`.
>
> **Check location (Language Team review, 2026-04-20):** The check must go in `inferExpr (EApp ...)` — the single convergence point for all function calls. Placing it in `checkStatement (SExpr (EApp ...))` would miss `wasi.*` calls nested inside `let`, `if`, `match`, `do`, or contract expressions.
>
> **Capability propagation (Language Team review, 2026-04-20):** Non-transitive (module-local). Module B must re-declare `(import wasi.io ...)` even if it only calls `wasi.*` via a function imported from module A. This matches the principle of least authority. Requires LLMLL.md §7 update.

When `wasi.*` functions are called, check that a matching `SImport` with a `Capability` is present in the module's statements. Emit a type error if not. This does NOT require `effectful` — it's a simple presence check. Thread module statements through `TCState` so `inferExpr` can access them.

| # | Action | Status |
|---|--------|--------|
| CAP-1a | In `inferExpr (EApp func args)`, if `func` starts with `wasi.`, verify a matching `SImport` exists in the module's statement list (accessed via `TCState`). Covers all nesting contexts: `let` RHS, `if` branches, `match` arms, `do` steps, contract expressions. | ✅ |
| CAP-1b | Emit structured type error: `"wasi.io.stdout requires (import wasi.io (capability ...))"` | ✅ |
| CAP-1c | Test: `wasi.io.stdout` call with no `(import wasi.io ...)` → compile error | ✅ |
| CAP-1d | Test: `wasi.io.stdout` inside a `let` binding with no import → error (nested call coverage) | ✅ |
| CAP-1e | Test: `wasi.io.stdout` with `(import wasi.io ...)` → OK (positive case) | ✅ |
| CAP-1f | Test: `wasi.fs.write` with `(import wasi.io ...)` but no `wasi.fs` import → error (per-namespace) | ✅ |
| CAP-1g | Test: Module A imports `wasi.io`; Module B imports Module A, calls `wasi.io.stdout` → error (non-transitive) | ✅ |

### Invariant Pattern Registry (~3 days)

> **Source:** [invariant-discovery-review.md §9](design/invariant-discovery-review.md)

Extend `llmll typecheck --sketch` to emit invariant suggestions from a pattern registry keyed by `(type signature × function name pattern)`.

| Pattern | Trigger | Suggested invariant |
|---------|---------|---------------------|
| `list[a] → list[a]` | Same element type | `(= (list-length result) (list-length input))` |
| `encode`/`decode` pair | Complementary names | `(= (decode (encode x)) x)` |
| Name contains "sort" | Semantic signal | `(sorted result)` ∧ `(permutation input result)` |
| Idempotent operations | `f(f(x)) = f(x)` pattern | `(= (f (f x)) (f x))` |
| Subset operations | `filter`, `take`, `drop` | `(<= (list-length result) (list-length input))` |

**Acceptance criteria:**

- `llmll typecheck --sketch` on a function with signature `list[a] → list[a]` emits at least one invariant suggestion
- Suggestions are keyed by `(type signature, function name pattern)` and returned in a structured JSON field `invariant_suggestions`
- Registry contains ≥5 patterns at launch (list-preserving, sorted, round-trip, subset, idempotent)
- Adding a new pattern to the registry does not require recompilation — patterns stored as data, not code

### Downstream Obligation Mining (~6 days)

> **Source:** [invariant-discovery-review.md §4](design/invariant-discovery-review.md)

When `llmll verify` reports UNSAFE at a cross-function boundary, extract the unsatisfied constraint and suggest a postcondition strengthening on the callee.

```
✗ Caller requires: uniqueIds(result)
  Producer normalizeUsers does not guarantee this.
  Candidate strengthening: postcondition uniqueIds(output)
```

Leverages existing `TrustReport.hs` transitive closure infrastructure.

### JSON Parsing via Aeson FFI (~2 days)

> **Source:** [agent-orchestration.md](design/agent-orchestration.md)

Unblocks self-hosted orchestrator experimentation. Uses Haskell FFI tier:

```lisp
(import haskell.aeson Data.Aeson)
```

Codegen emits `import Data.Aeson` in `Lib.hs`, adds `aeson` to `package.yaml`. No new compiler module needed.

> **Scoping note (P2-2):** v0.4 Aeson FFI requires a manual Haskell bridge file for JSON instance derivation (developer writes `FromJSON`/`ToJSON` instances). Auto-generation of `deriving (FromJSON, ToJSON)` from LLMLL type declarations is a **v0.7 codegen change**, not part of the v0.4 scope.

### Orchestration Event Log Format (Q3 resolution) — DEFERRED

> Both teams agreed (2026-04-20) to defer until the Lead Agent ships and real
> orchestration event patterns are observable. The Lead Agent (Sprint 2) adds new
> event types (plan_generated, skeleton_validated, quality_check) that would force
> a schema revision if formalized now.

| # | Action | Status |
|---|--------|--------|
| EV1 | Finalize `orchestration-events-schema.json` | ☐ deferred |
| EV2 | `llmll-orchestra` emits events in the finalized format | ☐ deferred |
| EV3 | Add replay support for orchestration events (extend `llmll replay`) | ☐ deferred |

---
## v0.3.5 — Agent Effectiveness ✅ (Shipped 2026-04-19)

**Theme:** Make the existing multi-agent pipeline actually work end-to-end with high first-attempt success rates.

> **Rationale:** All the compiler primitives exist (checkout, patch, holes, spec, verify). But no real orchestration session runs without heavy manual intervention. This release closes that gap.
>
> **Source:** Language team roadmap proposal (2026-04-19), approved with compiler team adjustments.

### Parallel Track A: Orchestrator End-to-End (`llmll-orchestra` fill mode) — ~3 days

> **Source:** [agent-orchestration.md](design/agent-orchestration.md), existing `tools/llmll-orchestra/`

Complete the Python orchestrator to the point where it fills the auth module exercise without manual intervention.

| # | Action | Status |
|---|--------|--------|
| O1 | `llmll-orchestra --mode fill auth_module.ast.json` fills both `?delegate @crypto-agent` holes | ✅ |
| O2 | Retry with diagnostics (max 3 attempts, structured error feedback) | ✅ |
| O3 | Lock expiry handling (re-queue, not crash) | ✅ |
| O4 | Integration test: malformed patch → retry with diagnostics → success | ✅ |

**Acceptance criteria:**

- Two-agent auth module exercise completes end-to-end
- Deliberately malformed patch triggers retry with diagnostics fed back to the agent
- Report shows per-hole success/failure with attempt count

### Parallel Track B: Context-Aware Checkout (Phase C) — ~5 days (C5 deferred)

> **Source:** [`docs/design/agent-prompt-semantics-gap.md §4 Option C`](design/agent-prompt-semantics-gap.md)

`llmll checkout` returns the local typing context alongside the lock token. This is the single highest-impact change for agent accuracy.

| # | Action | Module | Status |
|---|--------|--------|--------|
| C1 | Extend `SketchHole` with `shEnv :: Map Name ScopeBinding` | `TypeCheck.hs` | ✅ |
| C2 | Snapshot `gets tcEnv` in `recordHole` with provenance tagging | `TypeCheck.hs` | ✅ |
| C3 | Serialize delta (`tcEnv \ builtinEnv`) in checkout response via `Main.hs` threading | `Checkout.hs`, `Main.hs` | ✅ |
| C4 | Include `tcAliasMap` entries for `TCustom` types referenced by Γ or τ (`collectTypeDefinitions`) | `Checkout.hs` | ✅ |
| C6 | `truncateScope` with priority-based retention + shadowing-safety invariant (INV-3) | `Checkout.hs` | ✅ |

> [!NOTE]
> **C5 (monomorphize polymorphic Σ signatures) included in v0.3.5.** C5 can be implemented as a `Map Name Type` substitution pass over the `available_functions` list in the checkout response: when Γ contains `xs : list[int]`, rewrite `list-head : list[a] → Result[a, string]` to `list-head : list[int] → Result[int, string]`. This is a straightforward find-and-replace, not unification. Implement after C1–C4 land. (~1 day)

| # | Action | Module | Status |
|---|--------|--------|--------|
| C5 | Monomorphize polymorphic Σ signatures against concrete Γ types in checkout response via `Map Name Type` substitution (`monomorphizeFunctions`). INV-2: presentation-only, no `builtinEnv` mutation. | `Checkout.hs` | ✅ |

**Acceptance criteria:**

- `llmll checkout` response includes `in_scope`, `expected_return_type`, and `available_functions` fields
- `available_functions` entries are monomorphized against concrete Γ types (e.g., `list-head : list[int] → Result[int, string]` when `xs : list[int]` is in scope)
- Shadowed bindings are never exposed by truncation
- Orchestrator agent prompt includes typing context from checkout

### Integration Track: O5 — Checkout Context in Orchestrator (~1 day, after tracks A+B)

| # | Action | Status |
|---|--------|--------|
| O5 | Context-aware checkout integration — consume C1–C4+C6 output in agent prompt | ✅ |

### Counter-Example Display for Weak Specs — ~4 days

> **Source:** [invariant-discovery.md §6](design/invariant-discovery.md)

When a spec admits trivial implementations, show the trivial implementation as evidence.

```
⚠ Spec weakness detected for `sort-list`:
  Your contract: (post (= (length result) (length input)))
  Trivial valid implementation: (lambda [xs] xs)
  Consider adding: (post (sorted result))
```

| # | Action | Module | Status |
|---|--------|--------|--------|
| W1 | `llmll verify --weakness-check` — after SAFE result, attempt trivial fills (identity, constant-zero, empty-string, true, empty-list) | New `WeaknessCheck.hs` | ✅ |
| W2 | Emit structured diagnostic with the trivial implementation and `spec-weakness` kind (`mkSpecWeakness`) | `Diagnostic.hs` | ✅ |

**Design note:** `WeaknessCheck.hs` constructs a synthetic `SDefLogic` (same params, same contract, trivial body e.g. `EVar "xs"` for identity), calls `emitFixpoint` on `[syntheticStmt]`, and checks for SAFE. `emitFixpoint :: FilePath -> [Statement] -> IO EmitResult` accepts a full statement list — the synthetic single-statement list is valid input. This does NOT require modifications to `FixpointEmit.hs`.

**Acceptance criteria:**

- `llmll verify --weakness-check` on `sort-list` with only `length-preserving` post detects identity as valid
- Structured JSON diagnostic includes `trivial_implementation` and `suggested_postcondition` fields
- WeaknessCheck does not require modifications to `FixpointEmit.hs`

### Deferred items resolved

| Item | Decision |
|------|----------|
| Q3 (orchestration events reusing Event Log) | Defer to v0.4 — orchestrator must stabilize first |
| E1 (orchestration event JSONL schema) | Defer to v0.4 — no consumer until orchestrator stabilizes |
| `domain_hints` on holes | Defer — existing metadata sufficient |
| `type-reference` dependency edges | Defer — `calls-hole-body` sufficient for v0.3 orchestration |
| `?delegate-async` fire-and-forget filtering | Defer — requires data-flow analysis |

**Actual tests:** 211 → 225 Haskell (+14), 12 Python integration tests (all new)

---

## v0.3.4 — Agent Spec + Orchestrator Hardening ✅ (Shipped 2026-04-19)

**Theme:** Compiler-emitted agent prompt spec (Phase B from agent-prompt-semantics-gap.md) — eliminates hand-maintained prompt references by generating the spec directly from `builtinEnv`.

> **Source:** [`docs/design/agent-prompt-semantics-gap.md §4 Option B`](design/agent-prompt-semantics-gap.md)

**[CT]** ✅ B1 — New module `LLMLL/AgentSpec.hs`:
- Imports `LLMLL.TypeCheck (builtinEnv)` and serializes it directly
- Partitions functions vs operators via `operatorNames` set (matches `CodegenHs.emitOp` exactly)
- Excludes `wasi.*` functions (capability-gated)
- Uses LLMLL type notation (`int`, `string`, `Result[ok, err]`)
- Deterministic alphabetical output (36 builtins + 14 operators)
- JSON output includes constructors, evaluation model, pattern kinds, type nodes
- Text output is token-dense for direct system prompt inclusion

**[CT]** ✅ B2 — `llmll spec [--json]` CLI command:
- Emits the agent spec to stdout (text by default, JSON with `--json`)
- No source file argument required — reads from compiled-in `builtinEnv`

**[CT]** ✅ B3 — Spec Faithfulness property tests (7 tests):
- `covers all non-excluded builtinEnv entries` — sort(specNames) = sort(builtinKeys - wasi.*)
- `does not contain entries absent from builtinEnv` — all specNames ∈ builtinEnv
- `partition is disjoint` — builtins ∩ operators = ∅
- `handles unary operator (not) with 1 param`
- `output is deterministically ordered`
- `excludes all wasi.* functions`
- `includes seq-commands` — verifies preamble-implemented functions included

**[EXT]** ✅ B4 — Orchestrator integration (`agent.py` + `compiler.py` + `orchestrator.py`):
- `compiler.spec()` wraps `llmll spec` with backward-compat fallback (returns None for pre-v0.3.4)
- `build_system_prompt(compiler_spec)` injects spec into prompt; falls back to `_LEGACY_BUILTINS_REF`
- `orchestrator.py` calls `compiler.spec()` at start of `run()`, before hole scanning

**Acceptance criteria:**

- ✅ `llmll spec` output is a superset of the Phase A prompt reference (36 builtins + 14 operators + constructors + pattern kinds)
- ✅ All 7 faithfulness property tests pass
- ✅ Adding a new builtin to `builtinEnv` without corresponding spec entry is caught automatically
- ✅ `llmll-orchestra` uses `llmll spec` output instead of hardcoded prompt text (with legacy fallback)
- ✅ 211 tests passing (194 → 211: +7 AgentSpec + 10 other)

**Open questions resolved:**

- Q3 (from v0.3.3): orchestration events — **deferred to v0.4.1 or later**. Orchestrator must stabilize first. Define JSONL schema in v0.3.5 as a placeholder.
- `domain_hints` — **deferred**. Existing hole metadata sufficient for orchestrator routing.
- `type-reference` edges — **deferred**. Only `calls-hole-body` edges needed for v0.3 orchestration.
- `?delegate-async` fire-and-forget filtering — **deferred**. Requires data-flow analysis.

---

## v0.3.3 — Agent Orchestration ✅ (Shipped 2026-04-16)

**Theme:** First end-to-end multi-agent coordination demo. Validates the checkout/patch primitives shipped in v0.3.

> **Note:** The orchestrator ships as a separate package (`llmll-orchestra`), not as part of the compiler binary. M2 is a compiler deliverable; M1 is an external tool that consumes the compiler's CLI/HTTP contract.

**[CT]** ✅ M2 — `llmll holes --json --deps` flag:
- Added annotated `depends_on` edges per hole entry: `{pointer, via, reason}`
- Dependency = "hole B's enclosing function calls a function whose body contains hole A" (`calls-hole-body`)
- Cycle detection via Tarjan's SCC with deterministic back-edge removal; `cycle_warning` flag per hole
- P0 fix: rewrote pointer generation to produce RFC 6901-compatible structural paths (`/statements/N/body`)
- Scope exclusions: `?proof-required` holes and contract-position holes excluded from dependency graph
- New `--deps-out FILE` flag persists the dependency graph to a file
- Implementation in `HoleAnalysis.hs` — `computeHoleDeps`, `detectCycles`, `extractCalls`, `buildCallGraph`

**[EXT]** ☐ M1 — Python orchestrator (`llmll-orchestra` v0.1):
- ~200-line Python script validating the two-agent auth module exercise
- Reads `llmll holes --json --deps`, calls `llmll checkout` + `llmll patch` via CLI
- Sends hole context + LLMLL.md to Claude (Anthropic SDK), submits returned JSON-Patches
- Reports success/failure per hole, handles retry with diagnostics (max 3 attempts)
- Ships as a separate `pip` package with the compiler as a prerequisite

**Acceptance criteria:**

- ✅ `llmll holes --json --deps` returns annotated `depends_on` edges per hole entry; empty array for independent holes
- ✅ Pointers in `llmll holes --json` match RFC 6901 format compatible with `llmll checkout`
- ✅ `?proof-required` and contract-position holes excluded from dependency graph
- ✅ Dependency cycles detected via SCC, broken deterministically, flagged with `cycle_warning: true`
- ✅ `--deps-out FILE` writes the dependency graph to a file
- ☐ `llmll-orchestra` fills both `?delegate @crypto-agent` holes in the auth module exercise end-to-end
- ☐ A deliberately malformed patch triggers retry with diagnostics fed back to the agent
- ☐ Lock expiry (checkout TTL) is handled gracefully (re-queue, not crash)

**[CT]** ✅ M3 — Agent Prompt Semantic Reference (Phase A):

> **Source:** [`docs/design/agent-prompt-semantics-gap.md`](design/agent-prompt-semantics-gap.md) — reviewed and approved by Language Team and Professor.

Single-file edit to `llmll_orchestra/agent.py`. Adds ~950 tokens to the agent system prompt:

| # | Action | Status |
|---|--------|--------|
| A1 | Add `pair`/`first`/`second` signatures to prompt reference | ✅ Shipped |
| A2 | Fix comparison operators: `< > <= >=` are `int → int → bool`, not polymorphic | ✅ Shipped |
| A3 | Add `regex-match`, `seq-commands` to prompt reference | ✅ Shipped |
| A4 | `string-empty?` now in `builtinEnv` — added to prompt reference | ✅ Shipped |
| A5 | Add `pair` and `fn-type` type nodes | ✅ Shipped |
| A6 | Add ok/err vs Success/Error explicit callout block | ✅ Shipped |
| A7 | Add fixed-arity operator rule and parametricity note | ✅ Shipped |
| A9 | Add minimal `letrec` note (2 lines) | ✅ Shipped |
| A10 | Exclude `is-valid?` and `wasi.*` from reference | ✅ Shipped |

**[CT]** ✅ M3-pre — Pre-requisite compiler fixes for Phase A:

| # | Action | Location | Status |
|---|--------|----------|--------|
| A8a | Implement `string-empty?` in type checker | `TypeCheck.hs` `builtinEnv`: `("string-empty?", TFn [TString] TBool)` | ✅ Shipped |
| A8b | Implement `string-empty?` in runtime preamble | `CodegenHs.hs` `runtimePreamble`: `string_empty' s = null s` | ✅ Shipped |
| A8c | Document `string-empty?` in language spec | `LLMLL.md` §13.6 | ✅ Shipped |
| A11 | Remove `is-valid?` from `builtinEnv` | `TypeCheck.hs`: one-line delete | ✅ Shipped |
| A12 | Implement `regex-match` preamble | `CodegenHs.hs` `runtimePreamble`: `regex_match pattern subject = pattern \`isInfixOf\` subject` | ✅ Shipped |

**Open questions (from [`docs/design/agent-orchestration.md`](design/agent-orchestration.md) and [`docs/design/agent-prompt-semantics-gap.md`](design/agent-prompt-semantics-gap.md)):**

- Q2 resolved: `--json --deps` adds the annotated dependency graph (shipped)
- Q3 deferred: orchestration events reusing the Event Log format — decide in v0.3.4 or later
- Q5 deferred: MCP client/server dual role — Python v1 is CLI-only, MCP integration comes with self-hosted rewrite
- `domain_hints` deferred to v0.3.4: existing hole metadata sufficient for orchestrator routing
- `type-reference` edges deferred to v0.3.4: only `calls-hole-body` edges shipped
- `?delegate-async` fire-and-forget filtering deferred to v0.3.4: requires data-flow analysis

---

## v0.3.2 — Trust Hardening + WASM PoC ✅ (Shipped 2026-04-16)

**Theme:** Prove the compositionality story works (trust propagation) and de-risk v0.4 (WASM PoC).

> **Source:** [`docs/design/verification-debate-action-items.md`](design/verification-debate-action-items.md) — items surfaced by external formal methods review.

**[CT]** ☑ Cross-module trust propagation test:
- Write a multi-module test: Module A exports a function with `VLAsserted` contract, Module B imports it and calls it from a function with `VLProven` contract
- Verify that Module B's effective verification level is capped at `VLAsserted`, not `VLProven`
- Test the inverse: Module A has `VLProven`, Module B inherits `VLProven` correctly
- Test `(trust foo.bar :level asserted)` silences the downstream warning
- **Result:** 7 test cases covering asserted/tested/proven matrix, mixed levels, trust declaration suppression (181 → 188 tests)

**[CT]** ☑ `llmll verify --trust-report` flag:
- New output mode on `llmll verify` that prints a trust summary after verification
- Per-function: contract name, verification level (proven/tested/asserted)
- Transitive closure: which `proven` conclusions depend on `asserted` assumptions upstream
- Flags epistemic drift: "Function `withdraw` is proven, but depends on `auth.verify-token` which is asserted"
- JSON output with `--json` for tooling consumption
- **Result:** New `LLMLL.TrustReport` module + CLI integration + 6 tests (188 → 194 tests)

**[CT]** ☑ GHC WASM proof-of-concept:
- Analyzed generated `hangman_json_verifier` Haskell output for WASM compatibility
- Document all blockers: toolchain installation, Stack vs Cabal, QuickCheck/random shim
- Write up a go/no-go assessment for v0.4 WASM hardening
- **Result:** Conditional GO — see [`docs/wasm-poc-report.md`](wasm-poc-report.md). ~6-7 days engineering for v0.4.

**Acceptance criteria:**

- ☑ Multi-module trust propagation tests pass (7 test cases covering the matrix)
- ☑ `llmll verify --trust-report` on a multi-module program outputs the transitive trust graph
- ☑ WASM PoC report written with go/no-go recommendation for v0.4

---

## v0.3.1 — Event Log + Leanstral MCP ✅ (Shipped 2026-04-11)

**Theme:** Deterministic replay via JSONL event log and mock-first Leanstral proof integration.

> **Note:** The `?delegate` checkout/patch *compiler primitives* (`Checkout.hs`, `PatchApply.hs`, `JsonPointer.hs`, `llmll checkout`, `llmll patch`) shipped in v0.3. The agent orchestrator (`llmll-orchestra`) is scoped separately — see [`docs/design/agent-orchestration.md`](design/agent-orchestration.md).

**[CT]** ✅ Event Log — JSONL format with stdout capture:
- Generated `Main.hs` writes `.event-log.jsonl` (true JSONL, crash-safe)
- `captureStdout` via `hDuplicate`/`hDupTo` captures actual program output
- `llmll replay <source> <log>` builds program, feeds inputs step-by-step, compares outputs
- `Replay.hs` — line-by-line parser with crash tolerance + `runReplay` execution engine

**[CT]** ✅ Leanstral MCP integration (mock-only for v0.3.1):
- `LeanTranslate.hs` — LLMLL contract AST → Lean 4 `theorem` obligation
- `MCPClient.hs` — `--leanstral-mock` returns `ProofFound "by sorry"`
- `ProofCache.hs` — per-file `.proof-cache.json` sidecar (SHA-256 invalidation via `computeObligationHash`)
- `holeComplexity` field + `normalizeComplexity` in `HoleAnalysis.hs`
- `inferHole (HProofRequired)` added to `TypeCheck.hs`
- `--leanstral-mock` / `--leanstral-cmd` / `--leanstral-timeout` CLI flags on `llmll verify`
- `runLeanstralPipeline` — scans `[Statement]` directly for proof-required holes

**Acceptance criteria:** ✅ All met (mock mode)

- ✅ `?proof-required` holes classified with complexity hints (`:simple`/`:inductive`/`:unknown`)
- ✅ Mock proof pipeline: translate → mock-prove → cache → verify roundtrip works
- ✅ Console programs produce `.event-log.jsonl` with input **and** output
- ✅ `llmll replay` parses event logs and reports events
- ⏸ Real Leanstral integration deferred until `lean-lsp-mcp` available
- ⏸ NaN guard infrastructure present but NOOP (no float sources in v0.3.1)

**Tests:** 145 → 181 (36 new)

### v0.3 Verification (validates shipped checkout/patch infrastructure)

- Two-agent demo: Agent A writes a module with `?delegate`, Agent B submits a JSON-Patch via `llmll checkout` + `llmll patch`; compiler accepts the merge.



## v0.3 — Agent Coordination + Interactive Proofs ✅ Shipped

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

### ✅ Shipped: Pair Destructuring (PR 4)

**[CT]** Pair destructuring in `let` bindings — `(let [((pair s cmd) expr)] body)` pattern. `ELet` binding target extended from `Name` to `Pattern`. Shipped across Syntax, Parser, ParserJSON, TypeCheck, CodegenHs, AstEmit, and JSON schema. All 7 acceptance criteria verified; 69/69 tests pass.

---

### ✅ Shipped: Stratified Verification + Feature Completion (2026-04-11)

**[CT]** ~~`string-concat` parse-level variadic sugar~~ ✅ **Shipped (2026-04-11)** — In the S-expression parser, `(string-concat e1 e2 e3 …)` with 3+ arguments is desugared to `(string-concat-many [e1 e2 e3 …])` at parse time. `Parser.hs` L713-719. Type checker never sees a 3-arg `string-concat`. JSON-AST unaffected.

> **Decision record:** Type-checker variadic special-casing rejected (breaks fixed-arity invariant; JSON-AST complexity). Binary `string-concat` deprecation rejected (breaks partial application). Parse-level sugar is the minimal, correct resolution.

**Acceptance criteria (v0.3):**

- `(string-concat "a" "b" "c")` in S-expression compiles to the same Haskell as `(string-concat-many ["a" "b" "c"])`.
- `(string-concat prefix)` partial application still type-checks as `string → string`.
- JSON-AST `{"fn": "string-concat", "args": [a, b, c]}` produces a clear arity error (unchanged behavior — sugar is parse-time S-expression only).

**[CT]** ~~`?scaffold` CLI~~ ✅ **Shipped (2026-04-11)** — Hole kind fully implemented across Syntax, Lexer, Parser, ParserJSON, TypeCheck, CodegenHs, AstEmit, HoleAnalysis. CLI: `llmll hub scaffold <template> [--output DIR]` resolves from `~/.llmll/templates/`, copies scaffold file, parses and reports holes via `analyzeHoles`. `Hub.hs` adds `scaffoldCacheRoot`, `resolveScaffold`. Hub command upgraded to `fetch`/`scaffold` subcommand group.

**[CT]** ~~Stratified Verification (Item 7b)~~ ✅ **Shipped (2026-04-11)** — `VerificationLevel` ADT (`VLAsserted`, `VLTested n`, `VLProven prover`) with custom `Ord` instance. `ContractStatus` tracks per-function pre/post levels. Trust-gap warnings for cross-module unproven calls. `(trust ...)` declaration silences warnings.

**[CT]** ~~`--contracts` CLI flag (Item 8)~~ ✅ **Shipped (2026-04-11)** — `llmll build --contracts=full|unproven|none`. Strips contract clauses by mode.

**[CT]** ~~`.verified.json` sidecar write (Item 9)~~ ✅ **Shipped (2026-04-11)** — `llmll verify` writes per-function `ContractStatus` with `VLProven "liquid-fixpoint"` to sidecar. Subsequent builds read sidecar to strip proven assertions.

**[CT]** ~~`Promise[t]` upgrade: `IO t` → `Async t` (Item 14)~~ ✅ **Shipped (2026-04-11)** — `TPromise` emits `Async.Async`, `EAwait` emits `try (Async.wait ...)` with `SomeException` catch-all. Generated preamble imports `Control.Concurrent.Async` + `Control.Exception`. `package.yaml` includes `async` dependency. 10 regression tests.

**[CT]** ~~`do`-notation sugar~~ ✅ **Shipped (PRs 1–3)** — see "Shipped" section above.

---

## v0.2 — Module System + Compile-Time Verification ✅ Shipped

**Theme:** Make multi-file composition real and make contracts compile-time verified.

### Internal Ordering (design team requirement)

```text
Phase 2a: Module System  →  Phase 2b: liquid-fixpoint verification  →  Phase 2c: Type System Fixes + Sketch API
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

## v0.1.2 — Machine-First Foundation ✅ Shipped

**Theme:** Close the two highest-priority one-shot failure modes: structural invalidity (parentheses drift) and codegen semantic drift (Rust impedance mismatch). No new language semantics.

### Decision Record

| Decision | Resolution |
| -------- | ---------- |
| Primary AI interface | JSON-AST (S-expressions remain, human-facing only) |
| Codegen target | Switch from Rust to Haskell |
| Algebraic effects library | `effectful` — committed, not revisited |
| `Command` model | Move from opaque type to typed effect row (`Eff '[...]`) |
| Python FFI tier | Dropped from formal spec |
| Sandboxing | Docker + `seccomp-bpf` + `-XSafe` (WASM is a future direction, not version-pinned) |

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

**[CT]** JSON Schema versioning — introduce `"schemaVersion"` field to `llmll-ast.schema.json`. The compiler rejects `.ast.json` files with an unrecognized version.

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

> **One-shot impact:** Eliminates codegen semantic drift; makes v0.2 liquid-fixpoint verification a 2-week integration instead of a 3-month Z3 binding project.

**[DESIGN — COMMITTED]** Effects library: `effectful`. Effect rows are type-visible in function signatures — AI agents can inspect what capabilities a function requires. This is a direct one-shot correctness gain, not merely an implementation preference.

**[DESIGN — COMMITTED]** `Command` becomes a typed effect row. A function calling `wasi.http.response` without declaring the HTTP capability is a **type error** in generated Haskell, caught at compile time. This closes the v0.1.1 gap where missing capability declarations were silently accepted.

**[CT]** Rename `Codegen.hs` → `CodegenHs.hs` (new module `LLMLL.CodegenHs`). Public symbol `generateRust` → `generateHaskell`; `CodegenResult` fields renamed (`cgRustSource` → `cgHsSource`, `cgCargoToml` → `cgPackageYaml`, etc.). Old `Codegen.hs` deprecated re-export shim deleted.

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
| `(pre pred)` / `(post pred)` | liquid-fixpoint `.fq` constraints (v0.2); runtime `assert` wrappers (v0.1.2) |
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

**[CT]** WASM compatibility proof-of-concept — compile the Hangman and Todo service generated `.hs` files with `ghc --target=wasm32-wasi`. Resolve any blockers before shipping. This validates that WASM remains feasible as a future deployment target.

**[SPEC]** Update `LLMLL.md §7`, `§9`, `§10`, `§14` to reflect Haskell target, typed effect row, and Docker sandbox. Add explicit language to `§14`: *"WASM-WASI is the long-term deployment target. Docker + seccomp-bpf is the current sandbox. WASM is a confirmed future direction, not version-pinned."*

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

**[CT]** ~~Old `(let [[x 1] ...])` syntax emits a clear error with a migration message.~~ **Not implemented** — both `(x e)` and `[x e]` binding forms are accepted for backward compatibility (see `Parser.hs` `pLetBinding`).

---

</details>
