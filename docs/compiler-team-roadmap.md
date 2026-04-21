# LLMLL Compiler Team Implementation Roadmap

> **Status:** Active — v0.5.0 shipped (U-Full soundness); 264 Haskell + 37 Python tests passing  
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

# Upcoming Releases

## v0.6 — Specification Quality + Training

**Theme:** Attack the acknowledged bottleneck — specification coverage and quality.

> *"LLMLL does not require models to produce complete formal specifications. The remaining challenge is specification coverage — what gets specified at all."* — [strategic-positioning.md](design/strategic-positioning.md)
>
> **External review (2026-04-21):** Five items added to v0.6 based on reviewer feedback. Items 1–2 (spec coverage gate, frozen benchmark) are P0 — they close the gap between "interesting compiler" and "credible system." Items 3–5 (provenance, hub query, Leanstral claim) are P1/P2. Total added effort: ~15 days across 6 weeks, parallelizable with existing v0.6 research items.

### Spec Coverage Gate (P0, ~2.5 days) — NEW

> **Source:** External reviewer feedback item 1 (2026-04-21). `--spec-coverage` was designed in [spec-adequacy-closure.md §1b](design/spec-adequacy-closure.md) and planned for v0.4 but never shipped. The Lead Agent's quality heuristics are advisory, not blocking — a skeleton with no contracts can proceed to hole-filling.
>
> **Rationale:** The project's thesis — "verification is the coordination protocol" — requires that unspecified functions cannot progress to filling without explicit acknowledgment.

| # | Action | Effort | Status |
|---|--------|--------|--------|
| SC-1 | Implement `llmll verify --spec-coverage` per spec-adequacy-closure.md §1b. Walk `[Statement]`, count `SDefLogic` with/without `pre`/`post`, cross-reference `.verified.json`. Emit coverage report with per-function breakdown. | 1 day | ☐ |
| SC-2 | Add `effective_coverage` metric to `quality.py` heuristics. Formula: `(contracted + weakness_ok) / total_functions`. | 0.5 day | ☐ |
| SC-3 | Make coverage threshold a parameter in `--mode lead` / `--mode auto` (default: 80%, overridable via `--min-spec-coverage`). | 0.5 day | ☐ |
| SC-4 | Blocking behavior: `--mode auto` fails if effective coverage < threshold. `--mode lead` emits structured warning with list of unspecified functions. | 0.5 day | ☐ |

**Acceptance criteria:**

- `llmll verify --spec-coverage` on a program with 7 functions (4 contracted, 1 `weakness-ok`, 2 unspecified) reports `effective_coverage: 71%`
- `llmll-orchestra --mode auto` with `--min-spec-coverage 80` fails on the above program
- `llmll-orchestra --mode auto` with `--min-spec-coverage 70` succeeds
- Unspecified functions are listed by name in the coverage report

### Frozen ERC-20 Benchmark (P0, ~5 days) — NEW

> **Source:** External reviewer feedback item 2 (2026-04-21). The ERC-20 benchmark was fully designed in [spec-adequacy-closure.md §Track 2](design/spec-adequacy-closure.md) and planned for v0.4 but silently dropped. The project needs at least one stable benchmark with external ground truth, deliberately weakened specs, false-positive checks, and published pass criteria.

| # | Action | Effort | Status |
|---|--------|--------|--------|
| BM-1 | Implement `examples/erc20_token/erc20.ast.json` — full ERC-20 skeleton with `?delegate` holes, types, and contracts derived from ERC-20 standard | 1.5 days | ☐ |
| BM-2 | Implement `examples/erc20_token/erc20_filled.ast.json` — filled version with verified contracts | 1 day | ☐ |
| BM-3 | Add `examples/erc20_token/EXPECTED_RESULTS.json` — frozen ground truth for all 7 success criteria from spec-adequacy-closure.md §7 | 0.5 day | ☐ |
| BM-4 | Add CI gate: `make benchmark-erc20` runs `--weakness-check`, `--spec-coverage`, `--trust-report`, compares against frozen expected output | 1 day | ☐ |
| BM-5 | Write `examples/erc20_token/WALKTHROUGH.md` — end-to-end: external spec → LLMLL contracts → verified code → weakness detection → downstream obligation → strengthened contract → re-verification | 1 day | ☐ |

**Verification scoping (honest labeling per spec-adequacy-closure.md §Risk 2):**

| ERC-20 property | Verification level | Why |
|---|---|---|
| `total-supply` conservation | **Proven** (QF-LIA) | Integer arithmetic |
| Balance debit/credit | **Proven** (QF-LIA) | Integer arithmetic |
| Allowance deduction | **Proven** (QF-LIA) | Integer arithmetic |
| Non-negative balance | **Proven** (QF-LIA) | Simple comparison |
| Map key membership / absence | **Asserted** | Outside decidable fragment |
| Transfer-to-self edge case | **Tested** (QuickCheck) | Conditional logic |

**Acceptance criteria (from spec-adequacy-closure.md §7, promoted to roadmap):**

- SC-1: `--weakness-check` detects money-printing when conservation invariant is removed from `transfer`
- SC-2: `--spec-coverage` reports 100% contract coverage with all arithmetic contracts proven
- SC-3: At least one downstream obligation suggestion demonstrated
- SC-4: `balance-of` (pure accessor) not falsely flagged by `--weakness-check`
- SC-6: Walkthrough documents the full pipeline end-to-end
- SC-7: `--weakness-check` completes in under 30 seconds

### Clause-Level Provenance for Spec-from-RFC (P1, ~3 days) — NEW

> **Source:** External reviewer feedback item 3 (2026-04-21). In the target domains (financial compliance, protocol implementation, cryptographic standards), auditors require per-clause traceability to the originating standard. Without provenance, the Spec-from-RFC pipeline produces contracts that are plausibly correct but not auditable.

**[SPEC]** Add `:source` annotation to `pre`/`post` contracts — pure metadata, no effect on type checking or verification:

```lisp
(def-logic handshake-key-schedule [psk: bytes[32] ecdhe: bytes[32]]
  (pre  (>= (bytes-length psk) 32)
    :source "RFC 8446 §7.1 — PSK must be at least HashLen bytes")
  (post (= (bytes-length result) 32)
    :source "RFC 8446 §7.1 — HKDF-Expand-Label output length = HashLen")
  (hkdf-expand-label (hkdf-extract psk ecdhe) "derived" "" 32))
```

| # | Action | Effort | Status |
|---|--------|--------|--------|
| PROV-1 | Add `sourceRef :: Maybe Text` field to contract representation in `Syntax.hs` | 0.5 day | ☐ |
| PROV-2 | Parse `:source "..."` annotation in `Parser.hs` and `ParserJSON.hs` | 1 day | ☐ |
| PROV-3 | Thread `sourceRef` through `--trust-report` output and `.verified.json` sidecar | 1 day | ☐ |
| PROV-4 | Document `:source` annotation in `LLMLL.md §4.1` and `getting-started.md` | 0.5 day | ☐ |

**Design decision:** v0.6 uses free-form text (`:source "RFC 8446 §7.1"`). Structured references (`{standard, section, clause}`) deferred to v0.7.

**Acceptance criteria:**

- `:source` annotation accepted on `pre` and `post` in both S-expression and JSON-AST
- `--trust-report` output includes source references when present
- `.verified.json` sidecar includes `sourceRef` field per contract
- `:source` has no effect on type checking, verification, or codegen

### Spec-from-RFC Pipeline

> **Source:** [specification-sources.md §1](design/specification-sources.md)

For LLMLL's target domains (financial, protocol, encryption), specs already exist as RFCs. Build a pipeline that translates structured external specs into LLMLL contracts. **v0.6 addition:** generated contracts must include `:source` annotations (PROV-1..4) linking each clause to the originating standard.

### Hub Query-by-Signature (P2, ~3.5 days) — NEW

> **Source:** External reviewer feedback item 4 (2026-04-21). [specification-sources.md §4](design/specification-sources.md) and [component-hub.md](design/component-hub.md) describe query-by-signature as a roadmap item, but it was not scheduled. Without reuse, each new project pays the full cost of spec generation from scratch.

| # | Action | Effort | Status |
|---|--------|--------|--------|
| HUB-1 | `llmll hub query --signature "<type>"` — exact structural type match against hub cache (`~/.llmll/modules/`) | 2 days | ☐ |
| HUB-2 | Output includes function name, contract summary, verification level, source module | 0.5 day | ☐ |
| HUB-3 | Integrate with `llmll checkout` — when a hole's type matches a hub component, emit suggestion in checkout response | 1 day | ☐ |

**Explicitly deferred to v0.7:** Contract-aware matching (subsumption, equivalence), fuzzy `TDependent` compatibility.

**Acceptance criteria:**

- `llmll hub query --signature "list[int] -> list[int]"` returns matching components from the hub cache
- Query results include verification level and contract summary
- `llmll checkout` response includes `hub_suggestions` field when matches exist

### Synthetic Training Corpus (Hackage Back-Translation)

> **Source:** [specification-sources.md §5](design/specification-sources.md)

| Phase | Work |
|-------|------|
| 1 | Haskell-to-LLMLL transpiler for a subset of Hackage (type sigs, QuickCheck props, LH annotations) |
| 2 | Spec lifting: infer contracts from implementations + tests |
| 3 | Benchmark: measure agent hole-fill accuracy before/after fine-tuning |

### Differential Implementation Pressure

> **Source:** [invariant-discovery-review.md §3](design/invariant-discovery-review.md)

`llmll checkout --multi` allows N agents to independently fill the same hole. Divergence analysis generates distinguishing inputs.

### `def-interface :laws`

> **Source:** [invariant-discovery-review.md §10](design/invariant-discovery-review.md)

```lisp
(def-interface Codec
  [encode (fn [a] → string)]
  [decode (fn [string] → Result[a, string])]
  :laws [(for-all [x: a] (= (decode (encode x)) (ok x)))])
```

Algebraic law enforcement as a first-class language feature.

### Leanstral Claim Narrowing (P1, ~1 day) — NEW

> **Source:** External reviewer feedback item 5 (2026-04-21). The one-pager presents SMT + Leanstral as two working verification paths. In reality, Leanstral is mock-only since v0.3.1 and blocked on `lean-lsp-mcp`. This is misleading and should be corrected immediately.

| # | Action | Effort | Status |
|---|--------|--------|--------|
| CLAIM-1 | Revise `one-pager.md` to distinguish shipped verification (SMT/Z3) from designed-but-mock (Leanstral/Lean 4) | 0.5 day | ☐ |
| CLAIM-2 | Add `Verification Scope` subsection to `LLMLL.md §5.3` that precisely defines what is proven vs. what is asserted outside the SMT fragment | 0.5 day | ☐ |

**Decision:** Narrow the product claim now (Option B). Schedule real Leanstral integration (Option A) when `lean-lsp-mcp` becomes available. If `lean-lsp-mcp` is more than 3 months out, move Leanstral from "blocked" to "deferred to v0.8" and adjust documentation.

---

## v0.7 — Type-Driven + Self-Hosted (Research)

**Theme:** Explore whether richer types fundamentally improve agent accuracy, and whether LLMLL can build itself.

### Type-Driven Development (Minimal Experiment)

> **Source:** [type-driven-development.md](design/type-driven-development.md)

| Step | Work |
|------|------|
| 1 | Add `Vect n a` as a built-in indexed type |
| 2 | Add `llmll split ?hole <variable>` CLI command |
| 3 | Run an agent through 3-step type-driven fill of `safe-head` |
| 4 | Compare accuracy vs contract-based approach |

### Self-Hosted Orchestrator

> **Source:** [agent-orchestration.md §Option B](design/agent-orchestration.md)

Write the orchestrator as an LLMLL program with `def-main :mode cli`. Prerequisites: JSON parsing (v0.4), stable orchestration protocol, sufficient agent accuracy.

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

# Cross-Cutting Concerns

### Items Tracked Across Versions

| Item | Current Status | Next Action |
|------|---------------|-------------|
| Orchestration event log format (Q3 from v0.3.3) | Deferred from v0.3.5 | Deferred to v0.4.1 or v0.5 — let orchestrator stabilize before formalizing schema (compiler + language team, 2026-04-20) |
| MCP integration (Q5 from v0.3.3) | Deferred | Python v1 is CLI-only; MCP with self-hosted rewrite |
| Real Leanstral integration | Mock-only since v0.3.1. **Product claim narrowed (v0.6 CLAIM-1..2, 2026-04-21)** — one-pager and LLMLL.md now distinguish shipped SMT verification from designed-but-mock Lean 4 path. | Blocked on `lean-lsp-mcp` availability. If >3 months, move to deferred-v0.8. |
| `effectful` typed effect rows in codegen | Designed but codegen emits plain Haskell `IO` | v0.4: CAP-1 (capability presence check in `inferExpr`; non-transitive module-local propagation). v0.5: `effectful` WASM compat spike (binary test, **GO**). Full WASI enforcement deferred to WASM build target (unversioned future). |
| Spec coverage metric (`--spec-coverage`) | Designed in spec-adequacy-closure.md §1b but **never shipped** (planned for v0.4, dropped) | **Promoted to v0.6 P0** (SC-1..SC-4, 2026-04-21). Blocking gate in `--mode lead` / `--mode auto`. |
| Spec-adequacy benchmark (ERC-20) | Fully designed in spec-adequacy-closure.md §Track 2, planned for v0.4, **never shipped** | **Promoted to v0.6 P0** (BM-1..BM-5, 2026-04-21). Frozen benchmark with CI gate. |
| Contract clause-level provenance | Not previously tracked | **Added to v0.6 P1** (PROV-1..PROV-4, 2026-04-21). `:source` annotation on pre/post contracts. |
| Hub query-by-signature | Designed in specification-sources.md §4 and component-hub.md | **Added to v0.6 P2** (HUB-1..HUB-3, 2026-04-21). Exact structural match, no contract matching. |
| Contract discriminative power formalization | Proposed by Professor | Research track for v0.6 |
| Algorithm W `TDependent` interaction | **Resolved** (Strip-then-Unify, Option A, 2026-04-19) | No blocker — U-full shipped. Revisit if v0.6 type-driven development changes architecture. |
| `TSumType` wildcarding in `compatibleWith` | **Fixed** in U-Lite (v0.4, U7-lite) | Resolved. |

### What's NOT on this Roadmap (and why)

| Item | Reason |
|------|--------|
| Rust codegen backend | Dropped in v0.1.2; Haskell is the permanent target |
| Python FFI tier | Breaks WASM compatibility; dynamically typed |
| Full Lean 4 proof agent from scratch | Replaced by Leanstral MCP integration |
| UI/web frontend | LLMLL's target domains are backend, not UI |
| IDE plugins (VS Code, etc.) | Premature — stabilize the CLI/HTTP interface first |

---

# Summary: Version Plan and Critical Path

```
v0.3.5 (SHIPPED)   v0.4 (SHIPPED)      v0.5 (SHIPPED)    v0.6 (~3 mo)                Future
──────────────     ──────────────      ──────────────    ──────────────────          ──────
Context-aware      Lead Agent          U-full            P0: Spec coverage gate      WASM build
checkout (C1-C6)   (skeleton gen)      (Algorithm W)     P0: ERC-20 frozen benchmark target
                                                         P1: Clause-level provenance
Orchestrator       U-lite              effectful         P1: Leanstral claim narrow  WASI capability
end-to-end         (concrete type      WASM compat       P2: Hub query-by-signature  enforcement
                   unification)        spike (GO)          + Synthetic corpus
Weak-spec                                                   + Differential impl.
counter-examples   CAP-1 (capability                       + def-interface :laws
                   enforcement)                             + Spec-from-RFC

C5 (monomorphize)  Invariant registry
                   Obligation mining
                   JSON parsing
```

The critical path through v0.5 is complete: **context-aware checkout → working orchestrator → Lead Agent → U-Full → shipped**. v0.6 shifts focus from compiler correctness to specification quality. The two P0 items — spec coverage gate and frozen benchmark — are the shortest path from "interesting compiler" to "credible system." WASM is a confirmed future direction, not pinned to a version.

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
| **v0.6** | *(revised 2026-04-21)* | Spec quality: **spec coverage gate (P0)** + **frozen ERC-20 benchmark (P0)** + clause-level provenance (P1) + Leanstral claim narrowing (P1) + hub query-by-signature (P2) + synthetic corpus + differential impl. + `def-interface :laws` + Spec-from-RFC — **planned (~15 days new + existing research)** |
| **v0.7** | *(new)* | Type-driven development + self-hosted orchestrator + contract-aware hub matching — **research** |
| **Future** | *(unversioned, 2026-04-21)* | WASM build target + WASI capability enforcement — **confirmed direction, not version-pinned** |

### Items Removed from Scope

| Item | Reason |
| ---- | ------ |
| Rust FFI stdlib (`serde_json`, `clap`, etc.) | Replaced by native Hackage imports |
| Z3 binding layer (build from scratch) | Replaced by decoupled liquid-fixpoint backend (no GHC plugin) |
| Lean 4 proof agent (build from scratch) | Replaced by Leanstral MCP integration |
| Python FFI tier | Breaks WASM compatibility; dynamically typed; dropped from spec |
| Opaque `Command` type | Replaced by typed effect row (`Eff '[...]`) |

# Shipped Releases

<details><summary><strong>Click to expand shipped release details (v0.1.1 → v0.5.0)</strong></summary>


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
