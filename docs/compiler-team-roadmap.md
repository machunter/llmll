# LLMLL Compiler Team Implementation Roadmap

> **Status:** Active — see [`../CHANGELOG.md § Latest`](../CHANGELOG.md#Latest) for the shipped version (this header does not version-stamp).
>
> **Governing criterion:** every deliverable is measured against *progress toward one-shot correctness* — does it reduce the iteration burden, increase obligation completeness, or shorten the repair distance for an agent writing LLMLL? The terminal state: an agent writes a program once, the compiler accepts it, contracts verify.
>
> **Relationship to `LLMLL.md §14`:** complementary. §14 is the language-visible feature list; this doc is the engineering backlog (open tickets, acceptance criteria, decisions). Shipped features move to Shipped Releases here and stay described in §14.

---

## Versioning Conventions

- Items marked **[CT]** are compiler team implementation tasks.
- Items marked **[SPEC]** are language specification changes that must land in `LLMLL.md` before or alongside the implementation.
- Items marked **[DESIGN]** are design decisions resolved by the joint team, recorded here as implementation constraints.

---

## Table of contents

**Active & next work (read this first):**
- [Active Items](#active-items) — genuinely-open work, newest concern first
- [Upcoming Releases](#upcoming-releases)
- [Externally-Blocked Parking Lot](#externally-blocked-parking-lot)
- [Future — Module System Codegen](#future--module-system-codegen-unversioned)
- [Future — WASM Sandboxing](#future--wasm-sandboxing-unversioned)
- [Research track](#research-track-no-v0x-targets-no-active-items-rows)

**Policy & scope:**
- [What's NOT on this Roadmap](#whats-not-on-this-roadmap-and-why)

**History (append-only):**
- [Shipped Releases](#shipped-releases) — compact one-line-per-version summary; detail in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md)
- [Resolved cross-cutting items](#resolved-cross-cutting-items)

> Skills deep-link into these anchors (`docs/UPDATE-PROTOCOL.md` §3.1). Detailed per-version implementation history lives in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md).

---

# Active & Next Work

## Active Items

> Items below are the genuinely-open work (tags follow the `XXX-N` pattern); they are **not** in priority order. Shipped and settled items live in [Shipped Releases](#shipped-releases) / [Resolved cross-cutting items](#resolved-cross-cutting-items). Off-roadmap adoption work (Docker image, README, demos) has shipped; none is currently open.

### Open work (v0.12+ lane)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **CDP default-on** (promote `--cdp` / `--weakness-check` / `--spec-coverage` into the default serious-verify path) | **DEFERRED (nice-to-have) — not pursued** | Available opt-in via `--strict-verify`. All preconditions closed by v0.14.4; wall-clock characterized (`experiments/cdp-perf-0/`: `--cdp` roughly 2–3× verify time on modules with candidates). Flipping the default was considered and deferred on cost/UX grounds (unprompted diagnostic surface on every `verify`; the `--strict-verify` opt-in is preferred). Revisit if a concrete need emerges. |
| **OBLIG-1-FOLLOWON** (populate reserved obligation-report fields) | **v1 + v2a + v2b SHIPPED — residual one province deferred** | The `assumptions` field carries: (v1, v0.14.29) refinement predicates of in-scope refinement-typed **params**, α-renamed to the binder; (v2a, v0.14.31) **let-definitional equalities `(= y e)`** for in-scope let-bindings with a QF-LIA RHS (`ScopeBinding.sbDef` + `tcDefs`); (v2b, v0.14.32) **match-scrutinee case hypotheses `(= s (Ctor x))`** (nullary: `(= s Ctor)`), accumulated per-path across nested/sequential matches, shadow-guarded (`SketchHole.shHyps` + `matchHypothesis`/`withHyp`). **Deferred province**: `def-invariant` axioms (needs provenance tagging → schema bump, an unverified invariant being a TCB assumption). All value paths (`expected_return_type`, `available_functions`, `assumptions`) populated. |
| **SCRUT-PTR** (scrutinee-position hole records its parent match node's pointer) `[CT]` | **Open — low** | Surfaced by the v2b implementation pass: a hole in scrutinee position (`(match ?h …)`) gets no `"scrutinee"` segment pushed (the LET-PTR defect class, `TypeCheck.hs` EMatch traversal), so `checkout` mis-targets it. Rare (a scrutinee hole can't drive exhaustiveness); fix is a `withSegment "scrutinee"` analog. |
| **STRICT-SIBLING** (same-run sibling evidence for strict-core admission) `[CT/LT]` | **Open — design question** | Strict-core admission requires prior sidecar evidence per callee, so an all-`def` call chain in one file cannot verify in a single command (must stage sidecars bottom-up; `callee 'withdraw' is not body-faithful` on the banking_ledger promotion attempt). Surfaced independently by the examples-modernization and ENUM-EQ-FALLBACK sweeps (v0.14.32 session). Decide: intended staging discipline (document it) vs. same-run admission of body-faithful siblings. |
| **INT-3** (`MachineInt` QF-BV alias) | **P3 — open** | LT design when scheduled; promote to P1 if INT-PRE shows TOTP regression > 5× (cleared at 1.015×, so dormant) |
| **OBLIG-PBT-5b** (clean `EvidenceRecord.scope`) | **P2 — open** | engineer when scheduled; `trust_report_version` 1.1.0 → 1.2.0; new `tested-joint` display level |
| **R3 — Spec-from-RFC pipeline** (RFC → LLMLL contracts with `:source` clause provenance) | **Active — design doc at Rev 0** | Worked examples exist (`examples/totp_rfc6238/`, TCP-793 demo, `:source` provenance); the generalizable pipeline design doc landed as [`spec-from-rfc-pipeline.md`](design/spec-from-rfc-pipeline.md) (Rev 0). Remaining: execute the doc's §4 evaluation plan — one unseen RFC, experiment-lead-owned (gap G4). |

> **Recently retired (shipped):** REF-META, Bundle B0, NIW Phase 1 (v0.12.0); COMP-4 / PAIR-RET lines (v0.13.x); PROOF-ARTIFACT, R5 differential-implementation-pressure (v0.14.x); **REC-BODY-VC — the whole line: (b0) hash integrity v0.14.22, (a) partiality marker v0.14.23, (c) REC-DESCENT surface v0.14.24 + discharge/admission v0.14.25 + lexicographic k>1 v0.14.27 (design [`rec-body-vc-proposal.md`](archive/shipped-design-specs/rec-body-vc-proposal.md); R7 single-slice descent promoted, TERM-1 disclaimer retired for discharged recursion).** **MATCH-WIDEN-2 (n-arm sums + sequential matches, v0.14.26)** — the body-faithful match fragment widened from two arms to any arity + sequential composition ([`match-widen-stretch-plan.md`](archive/shipped-design-specs/match-widen-stretch-plan.md) §S4). **REFINE-REUSE (v0.14.29)** — `refine`'s advisory reuse retrieval (`reuse_suggestions` + non-blocking `W-REUSE`; design [`refine-reuse-gate-proposal.md`](archive/shipped-design-specs/refine-reuse-gate-proposal.md)); Stage 4 of Cascading Refinement. **CLASSIFY-EOP (v0.14.30)** — `isQfLia`/`classifyContractFragment` recognize the `EOp` operator form (classification/reporting fix, not soundness). Provenance in [Shipped Releases](#shipped-releases) + `CHANGELOG.md`. Still future: Bundle B1 (awaits a B1-native experiment), NIW Phase 2, B2/B3; R5's forced-diversity follow-on is experiment-lead-owned.

### Adversarial benchmark (experiment-lead-owned)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **Adversarial spec-weakening benchmark** (spec-adequacy under adversarial pressure) | **MEASURED (v0.14.5) — settled; Owner: experiment-lead** | Measured whether CDP / `--weakness-check` / `--spec-coverage` catch an agent that deliberately weakens a contract until bad code verifies ([`experiments/adv-spec-weaken-0/findings.md`](../experiments/adv-spec-weaken-0/findings.md)). Outcomes: F-001 (guardrail JSON gap) shipped v0.14.5; F-002 (self-attestation dilution floor) settled as a design-scope limitation — no per-instance oracle possible on a self-attestation channel, so `LLMLL.md §4.4.6` was clarified, no compiler change; F-003 descriptive. |

---

## Upcoming Releases

> **No version is currently in flight** — the next release is cut from [Active Items](#active-items) above. Shipped milestones are in [Shipped Releases](#shipped-releases); LEAN-GA (subsuming TRUST-2b) and MCP are in the [Externally-Blocked Parking Lot](#externally-blocked-parking-lot).

---

## Externally-Blocked Parking Lot

Tracked but off the critical path — gated on external availability or a concrete external request.

| ID | Description | Trigger |
|-----|-------------|---------|
| **LEAN-GA** (subsumes TRUST-2b) | Real (non-mock) Leanstral integration → `verified-lean` evidence. **Demo slice shipped v0.14.8:** `--leanstral` proves a faithfully-translatable nonlinear obligation in Lean 4 + Mathlib and records `verified-lean` (`DLVerifiedLean`, a peer of SMT `verified`, superseding the original `VLProvenLean`) + a re-checkable `.lean` certificate (`examples/leanstral-demo/`). **Deferred = the three-layer production rebuild:** `LeanTranslate.hs` faithful across all escape classes, full nonlinear/inductive worklist routing, and the retry-with-error loop + Lean-staleness revalidation. Design: [`leanstral-integration-scope.md`](design/leanstral-integration-scope.md). | Production three-layer rebuild (external availability partly cleared by Leanstral 1.5) |
| **MCP** | MCP integration for the compiler CLI | Concrete external integration request |

> **STRIP-GA resolved** — absorbed into the shipped evidence model (v0.8.1b) + stripping regression tests (v0.9); it was never Lean-blocked, so it leaves the parking lot.

---

## Future — Module System Codegen (unversioned)

**Theme:** Complete the module system's codegen-level guarantees.

> The module system is compile-time correct; codegen-level enforcement (export hiding, qualified imports, interface checks) is absent.

| # | ID | Description | Prerequisite | Status |
|---|-----|-------------|-------------|--------|
| 1 | **MOD-2** | **[CT]** Per-module Haskell file emission: instead of concatenating all module statements into a single `Lib.hs`, emit one `.hs` file per module with Haskell `module` export lists. Enables true codegen-level export hiding and qualified access. | None | ☐ |
| 2 | **MOD-3** | **[CT]** Qualified access at codegen: with per-module `.hs` files, translate `module.function` to Haskell qualified imports. Makes §8.5.1 "Qualified Access" operational. | MOD-2 | ☐ |
| 3 | **MOD-4** | **[CT]** `loadFromFile` strict typecheck migration: switch the DFS module loader from permissive `typeCheck` to strict `typeCheckStrictWithCache`. Requires all examples and library modules to have correct `(open ...)` declarations. | MOD-1 | ☐ |
| 4 | **MOD-5** | **[CT]** `checkInterfaceMismatch` wiring: add `interfaceName` field to `Import` AST in `Syntax.hs`, parse `(interface ...)` clause in `Parser.hs`, expand `meAliasMap` types before comparison in `Module.hs`. **Now also motivated by XMOD-AG (v0.14.17):** cross-module assume-guarantee inherits nominal-by-name ADT identity (same-named imported ADTs compared by constructor names, not structure); MOD-5's structural check would close that limitation. | MOD-2 | ☐ |

**Trigger:** a production use case requiring true namespace isolation.

---

## Future — WASM Sandboxing (unversioned)

**Theme:** Replace Docker with WASM-WASI as the primary sandbox.

> A confirmed future direction, not pinned to a version. Docker + CAP-1 already provide two enforcement layers (compile-time capability gating + container isolation); WASM adds a hardware-enforced third layer, prioritized when real users run untrusted agent code in production. Feasibility confirmed (v0.3.2 PoC; `effectful` compatibility spike GO). Design: [`wasm-poc-report.md`](archive/wasm-investigations/wasm-poc-report.md).

### WASM Build Target (~7 days)

| Phase | Work | Effort | Status |
|-------|------|--------|--------|
| Phase 0 | Install `ghc-wasm-meta` + `wasmtime`, manual compile of hangman | 1 day | ☐ |
| Phase 1 | `--target wasm` flag, generate `.cabal` file, invoke `wasm32-wasi-cabal` | 2–3 days | ☐ |
| Phase 2 | Strip check blocks for WASM, WASI capability import mapping | 2 days | ☐ |
| Phase 3 | CI integration, setup script, docs | 1 day | ☐ |

**Acceptance criteria:**

- `llmll build --target wasm examples/hangman_sexp/hangman.llmll` produces a `.wasm` binary
- `wasmtime hangman.wasm` runs the game correctly
- WASI capability imports align with LLMLL capability declarations
- Typed effect rows (`effectful`) integrate with WASI enforcement

**Risk:** `ghc-wasm-meta` toolchain maintenance is low-bus-factor. If it falls behind GHC releases, this work slips without affecting anything else.

**Trigger — when to schedule this:**

- Real users running untrusted agent code outside development environments
- Docker proving insufficient as a sandbox (capability granularity, startup latency, distribution)

---

## Future — Data Scope Extension (unversioned)

> Widening the verification surface (`Σ_auto`) from *integers + non-recursive ADTs + length-measures*
> to **complex data structures** (lists, arrays, maps, recursive types). Didactic reference and full
> rationale: [`docs/design/data-scope-extension.md`](design/data-scope-extension.md). **Nothing
> shipped** — this is the track behind "can LLMLL verify lists / arrays / maps / recursive data?"
> Today the answer is *no, deliberately*: the boundary is **decidability** (the guarantee that
> "SAFE" is a decidable predicate on a fixed VC). Motivated by the flagship-example goal — an example
> where *the data structure itself is the risk* (the data-axis sequel to the Heartbleed length story).

| Lever | Item | Theory / decidability | Unlocks | Status / dependency |
|---|---|---|---|---|
| **A** | **Theory of arrays** for `bytes[n]` / `map[k,v]` | QF theory of arrays (`select`/`store` + extensionality) — **decidable**, polite-combines with QF-LIA; **stays in `Σ_auto`** | array index-in-bounds (real memory-safety, not a length proxy); map get-after-put / key-presence | **Proposed — recommended first**; enabling purchase for the first genuine data-structure example (the structure verified, not a length proxy) |
| **B** | **Dependent lengths** (`list[t]{len=n}`) + widened measure catalog | QF-LIA + EUF (+ arrays) — **decidable** | safe list indexing (bridge from "count a list" to "index a list") | **Proposed**; depends on Lever A; **overlaps R1** (dependent types, `Vect n a`, below) |
| **C** | **Inductive datatypes + induction** (recursive ADTs, measure unfolding, PLE / refinement reflection) | inductive datatype theory — **undecidable in general**; **leaves `Σ_auto`** → new weaker tier *or* route to the Lean tier | list / tree / stack structural invariants (sortedness, balance, acyclicity, use-after-free) | **Research frontier**; gated on **LEAN-GA** (`verified-lean` discharge); the R7 strict-descent gate cleared (shipped v0.14.25/27) |

> **Evaluation-integrity rule** (standing, for every example built on this track): the `checkout`
> brief is the *sole* information channel to a hole-filling agent — we neither force a failure nor
> leak hints beyond the returned contract (pre/post goal, expected return type, in-scope bindings,
> callable contracts). See [`data-scope-extension.md`](design/data-scope-extension.md) Post 8. This
> is *why* the extension matters: a hint-free data-structure hole is only fillable-and-checkable if
> the contract alone is expressive enough — which requires a richer data theory (Lever A first).

---

## Future — Cascading Refinement (unversioned)

> Agent-driven **recursive hole decomposition** — the "third track" of the north star. Today a scaffold's
> decomposition is authored up front (holed out of a full solution); cascading refinement makes it
> *emergent* — a `refine` op installs a hole's body **and spawns new contracted sub-holes** (new functions
> with their own contracts), recursively, growing a refinement tree. Design (professor-folded):
> [`docs/design/cascading-refinement-proposal.md`](design/cascading-refinement-proposal.md) (Rev 3).
> **Layers 1, 2, and 4 shipped, plus layer 3's vacuity gate** (v0.14.13 `refine` op + CDP vacuity gate,
> exercised end-to-end by `examples/secure-channel-emergent/`; v0.14.29 reuse retrieval). **Open:** the
> feasibility (no-miracle) gate and the decomposition-trust meet. The control- and data-side
> fragment-wideners ship the *bodies*; this ships the *decomposition* — the project's own stated
> differentiator (`docs/design/strategic-positioning.md:22`).

| Layer | What | Status |
|---|---|---|
| **1 — substrate** | per-step verification = existing assume-guarantee (`cvPreObligation`/`cvPostAssumption`); no new fragment | reuse |
| **2 — protocol** | a `refine` op (dual of `patch`: install body + spawn sub-holes atomically, scope-relaxation safety predicate — fresh, body-referenced, hole-bodied spawns only), reusing the `applyPatch` lifecycle (compare-and-swap resync + assume-guarantee re-verify) | **✅ SHIPPED v0.14.13** (`examples/refine-demo/`) |
| **3 — contract quality** | spawn-time **CDP** vacuity gate (rejects a trivially-satisfiable sub-contract) + **feasibility** (no-miracle) gate + decomposition-trust **meet** (floored on contract-only cycle members) | vacuity gate **✅ SHIPPED v0.14.13**; feasibility gate + trust meet **open** — extends **CDP** (`:224`) |
| **4 — reuse retrieval (REFINE-REUSE)** | spawn-time **reuse retrieval** (*not a gate — never rejects*): surface existing in-scope defs that *subsume* a spawned sub-contract (contract-implication `preₛ⇒pre_D ∧ post_D⇒postₛ`, α-normalized, not name/syntax). Advisory `reuse_suggestions` brief channel + non-blocking `W-REUSE` warning on an exact-equivalent; reuses **COMP-4(b)** subtyping-Horn (`:70`) | **✅ SHIPPED v0.14.29** (`LLMLL.RefineReuse`; a NEW whole-contract subsumption driver — two standalone Horn constraints, not the call-site COMP-4(b) payload driver); design [`refine-reuse-gate-proposal.md`](archive/shipped-design-specs/refine-reuse-gate-proposal.md) |

> **Acyclicity policy — DECIDED (Option 3):** `refine` admits a cycle-creating spawn, detects the cycle,
> and degrades its members to contract-only (trust meet floored so nothing is laundered) — the
> `letrec` partial-correctness treatment (`LLMLL.md §5.3.5`). The R7 strict-descent total-correctness
> upgrade shipped (v0.14.25/27): a discharging `(decreases …)` measure on the cycle members upgrades the
> cycle to total. One open design question (per-contract vs composed gating). **Depends-on:**
> MATCH-WIDEN (shipped v0.14.12 — gives the cascade non-trivial verified leaves), R2 (self-hosted
> orchestrator), R8 (incremental re-verify). Standing rule: the `checkout` brief is the sole information
> channel to a hole-filling agent (no forced failures, no hints).

## Research track (no v0.x targets, no Active Items rows)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **Full categorical unification** (fibrations / graded monads / patch-merge derivation) | **Declined** | Disproportionate per professor adjudication. See [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) §5 |
| **Path B mechanized soundness theorem** | **Declined** | Inherited Path A stance from [`docs/design/verification-debate.md`](design/verification-debate.md) |

### Research track (migrated from `docs/research-track.md`, 2026-05-25)

> R1–R8 below are the live research index (archived source: [`docs/archive/research-track.md`](archive/research-track.md)). R3 promoted to Active; R5 and R6/CDP shipped.

| # | Item | Original promotion criterion | Cross-reference (per R1–R7 audit, 2026-05-25) | Archive source |
|---|------|------------------------------|------------------------------------------------|----------------|
| **R1** | **Indexed / Dependent Types** (`Vect n a`, GADTs, type-level arithmetic, bidirectional typechecking) | Design spec with typing rules, bidirectional migration plan, erasure strategy | Source design exploration: [`docs/design/type-driven-development.md`](design/type-driven-development.md) (partially promoted — obligation-guided part shipped in v0.10). Consistent with "What's NOT on this Roadmap" row Indexed/dependent types — Research track. | [`docs/archive/research-track.md §1`](archive/research-track.md) |
| **R2** | **Self-Hosted Orchestrator** (rewrite `llmll-orchestra` as LLMLL `def-main :mode cli`) | Agent accuracy ≥80% on auth module exercise when filling LLMLL-source holes | Source design draft: [`docs/design/agent-orchestration.md`](design/agent-orchestration.md) §Option B (Future Infrastructure category in INDEX). No competing roadmap row. | [`docs/archive/research-track.md §2`](archive/research-track.md) |
| **R3** | **Spec-from-RFC Pipeline** (RFC text → LLMLL contracts with clause provenance traceability) | ~~Concrete pipeline design doc with at least one worked example~~ → **Promoted to [Active Items](#active-items)** (2026-06-23): worked-example criterion met by `examples/totp_rfc6238/` + the TCP-793 demo + shipped `:source` provenance | [`docs/archive/research-track.md §3`](archive/research-track.md) |
| **R4** | **Synthetic Training Corpus** (Hackage back-translation; transpiler + spec lifting + benchmark) | Research proposal with measurable hypothesis and evaluation methodology | No competing roadmap row; independent. | [`docs/archive/research-track.md §4`](archive/research-track.md) |
| **R5** | **Differential Implementation Pressure** (`llmll checkout --multi`; N agents fill same `?delegate`; divergence analysis as new module `DivergenceCheck.hs`) | ~~Agent accuracy baseline established~~ → **Surfaced to [Active Items](#active-items)** (2026-06-23). Distinct from single-agent repair-loop and the `OBLIG-*` family. | [`docs/archive/research-track.md §5`](archive/research-track.md) |
| **R7** | **Call-Site Strict Descent** (`measure(args') < measure(args)` constraint at each recursive call site; independent of BODY-VC per consultant correction 2026-04-28) | ~~Independent design spec for descent constraint generation~~ → **SHIPPED via REC-DESCENT** (v0.14.25 single-measure discharge + strict-core admission; v0.14.27 lexicographic k>1; design [`rec-body-vc-proposal.md`](archive/shipped-design-specs/rec-body-vc-proposal.md)) | TERM-1's partiality disclaimer is retired for descent-discharged recursion; an undischarged (measureless / mixed-arity / non-QF-LIA-measure) cycle stays partial and keeps the `termination_unverified` marker. | [`docs/archive/research-track.md §7`](archive/research-track.md) |
| **R8** | **Incremental Patch Re-Verification** (dependency-slice re-verify for `llmll patch` instead of whole-module) | Design spec proving the slice is sound — that node-VC + fill-induced callee slice + staleness-recheck captures every obligation the whole-module re-verify emits — plus a demonstrated repair-loop latency pain point | Surfaced by language-team, 2026-07. Current behavior: `PatchApply.applyPatch` re-parses + typechecks + Fixpoint-emits the whole merged module on every patch (`PatchApply.hs:291-303`). The checkout brief already snapshots most of a sound slice's inputs — enclosing pre, path condition, callee `fePre`/`fePost` (`Checkout.hs:186-197`). Wall-clock basis: `experiments/cdp-perf-0/`. Distinct from CDP default-on. | New (no archive source) |

---

# Policy & Scope

## What's NOT on this Roadmap (and why)

| Item | Reason |
|------|--------|
| Rust codegen backend | Dropped in v0.1.2; Haskell is the permanent target |
| Python FFI tier | Breaks WASM compatibility; dynamically typed |
| Full Lean 4 proof agent built from scratch | Lean discharge goes through Leanstral (LEAN-GA — `--leanstral` demo slice shipped v0.14.8, production rebuild parking-lotted), not a hand-built prover |
| UI/web frontend | LLMLL's target domains are backend, not UI |
| IDE plugins (VS Code, etc.) | Premature — stabilize the CLI/HTTP interface first |
| Indexed/dependent types | Research track (R1) — deferred by professor consensus (2026-05-01), not a v0.x target |
| `ELambda` higher-order body VCs | Out of `Σ_auto` by design — higher-order refinements (defunctionalization / abstract-refinement machinery) are a research axis with no target-domain demand; lambdas lower to runtime contracts. Revisit only with a concrete verified-HOF use case. |
| `EDo` / effectful bodies in `Σ_auto` | Effects verify on the capability / effect-row axis (Bundle B; B0 shipped v0.12.0, B2/B3 future), not via SMT posts — `EDo` bodies keep runtime contracts + effect summaries by design. |
| Uncontracted-callee body VCs (bounded inlining / contract inference) | The agent workflow (scaffold/checkout) mandates contracts, so uncontracted callees barely occur in the target flow; contract inference was deliberately kept local (REF-META-5, professor consensus). Bounded inlining is possible but low-value; the contract-only fallback is the recorded decision. |

> The former freeze-era exclusions (new builtins, new syntax constructs, broader FFI, more WASI surface, compiler-side orchestration, typeclass law machinery) are no longer blanket-excluded. A proposed addition goes through the normal design → review → ship pipeline — language-team design, professor critique, compiler-engineer implementation — and lands with a written soundness argument as part of its design record. The original v0.8.1a–v0.10 feature freeze was lifted at v0.11; historical rationale: [`core-shell-inversion-direction.md`](archive/shipped-design-specs/core-shell-inversion-direction.md).

---

# History

## Shipped Releases

> Compact summary, newest-first. One line per version: headline — ship date — test count — link to the detailed implementation section in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md). Canonical release narrative is [`../CHANGELOG.md`](../CHANGELOG.md). This `#shipped-releases` anchor is stable and is the entry point other docs link to.

| Version | Headline | Date | Tests | Detail |
|---------|----------|------|-------|--------|
| **v0.14.32** | **OBLIG-1 v2b + ENUM-EQ-FALLBACK** — checkout brief `assumptions` also surfaces match-scrutinee case hypotheses `(= s (Ctor x))` (nullary: bare `(= s Ctor)`; accumulated outermost-first across nested/sequential matches; shadow-guarded — a rebound name drops its hypothesis; `SketchHole.shHyps` + `matchHypothesis`/`withHyp`; residual province = `def-invariant` axioms only). **ENUM-EQ-FALLBACK** (pre-existing fix): the v0.14.12 `clauseOverOpaqueSumParam` guard matched *any* sum-typed param incl. int-tag-desugared all-nullary enums, so every enum-atom contract fell back and wrong twins verified SAFE (refutation silently lost v0.14.12–31 on tcp_rfc793/session-pay); guard now fires only for payload-bearing sums; 85-file sweep = exactly 4 intended SAFE→refuted flips + 3 fallback→body-faithful, rest line-identical. Examples modernized (`=>` posts, nary `def`), doc review wave (refine documented, termination rows current, XMOD-STALE closed, 4 design docs archived), design docs: Lever A arrays Rev 0 + spec-from-RFC pipeline Rev 0. +10 tests | 2026-07-11 | 1181 H + 45 Py | `CHANGELOG.md §v0.14.32` |
| **v0.14.31** | **OBLIG-1 v2a** — checkout brief `assumptions` also surfaces let-definitional equalities `(= y e)` for in-scope let-bindings with a QF-LIA RHS (`ScopeBinding.sbDef` + `tcDefs` threaded via `withDefs`); professor's named v2 province, sound (body VC assumes it); no schema bump. **LET-PTR** (pre-existing bug fixed): a hole in a `let` body recorded sketch pointer `/statements/N/body` while its AST node is `.../body/body` (the body traversal didn't push the `body` segment like fn/if/match do), so `checkout` returned null `in_scope` AND `assumptions` for *every* let-nested hole — fixed with `withSegment "body"`, repairing the full context surface for all let-nested holes. +4 tests. Residual OBLIG-1 v2 = match-scrutinee + def-invariant | 2026-07-11 | 1171 H + 45 Py | `CHANGELOG.md §v0.14.31` |
| **v0.14.30** | **CLASSIFY-EOP** — `isQfLia`/`classifyContractFragment` now recognize the `EOp` operator form (both parsers emit `EOp` for operators, not just `EApp`). Previously *every* operator-bearing contract mislabeled `contract_fragment: non_qf_lia` and its obligation tier downgraded to Advisory; the verifier was never affected (`FixpointEmit` normalizes `EOp→EApp`), so a reporting/classification fix, not soundness. One-line central fix; REFINE-REUSE's `normContractOps` workaround removed. +4 `EOp`-faithful regression tests (the prior tests built `EApp` directly, bypassing the parser) | 2026-07-11 | 1167 H + 45 Py | `CHANGELOG.md §v0.14.30` |
| **v0.14.29** | **OBLIG-1** — the checkout brief's reserved `assumptions` field is wired: refinement predicates of in-scope refinement-typed **params**, α-renamed to the binder (`x: (where [v:int] (> v 0))` → `["(> x 0)"]`), resolved through same-file aliases; type-check cost, no solver; v1 is params-only (sound-but-incomplete, professor-scoped — let/match/def-invariant provinces deferred); no schema bump. **REFINE-REUSE** — `refine` surfaces in-scope defs whose contract subsumes a spawned sub-contract as advisory `reuse_suggestions` + non-blocking `W-REUSE` on an exact contract-equivalent; subsumption = contract subtyping (`preₛ⟹pre_D ∧ post_D⟹postₛ`, α-normalized) via two standalone liquid-fixpoint Horn constraints (`LLMLL.RefineReuse`); signature pre-filter + QF-LIA gate; non-rejecting; graceful no-solver skip; no AST schema bump. Incidental: `EOp`/`EApp` QF-LIA-classifier blind spot worked around locally (`normContractOps`), tracked as CLASSIFY-EOP | 2026-07-11 | 1163 H + 45 Py | `CHANGELOG.md §v0.14.29` |
| **v0.14.28** | OBLIG-HOLE-TYPE — `verify --obligation-report` per-hole `expected_type` now prefers the checkout brief's `runSketch` inference where the structural `analyzeHoles` pass leaves the hole untyped. `assembleReport` runs the same sketch the brief uses (type-check cost, no solver), joins holes by RFC-6901 pointer, and takes the sketch type **only where the structural type is absent** (structural still wins when present; un-inferable holes stay `unknown`). Fixes over-broad OBLIG-VOCAB-GATE vocabulary for value-position holes that read `unknown` in the report but a concrete type in the brief. Closes the OBLIG-HOLE-TYPE row (surfaced by v0.14.20). No schema bump | 2026-07-11 | 1150 H + 45 Py | `CHANGELOG.md §v0.14.28` |
| **v0.14.27** | Lexicographic descent (k>1) + n-arm matches in strict-core `def`. **Lex descent** (REC-DESCENT/R7 follow-on): a k>1 `(decreases e₁…eₖ)` discharges via the lexicographic order on ℕᵏ — the per-call-site descent becomes the QF-LIA disjunction `⋁ᵢ(e₁'=e₁ ∧ … ∧ eᵢ'<eᵢ)`, `eⱼ≥0` per component; `lexLess [g] [f]` = bare `<` (k=1 byte-identical); self + equal-arity mutual discharge (common-ℕᵏ Floyd), bad tuple → `measure-not-decreasing`. **Load-bearing soundness fix:** the discharge gate now requires **uniform tuple arity across the whole SCC** (`ObligationAssembly.descentDischargedFns`) — else a mixed-arity mutual SCC (mismatched-arity edges emit no descent constraint) would verify vacuously-SAFE and be stamped total, claiming termination for a divergent function; mixed-arity stays partial (refuse-not-pad, professor-confirmed). **n-arm strict-core** (MATCH-WIDEN-2 follow-on): `isCoreBodySyntactic` admits >2-arm payload matches in `def` bodies (grammar catches up to the verifier; exhaustiveness/body restrictions unchanged). No schema/hash change | 2026-07-11 | 1148 H + 45 Py | `CHANGELOG.md §v0.14.27` |
| **v0.14.26** | MATCH-WIDEN-2 — n-arm sums + sequential matches verify body-faithful. **Commit A:** a match on an admissible sum of any arity (mixed nullary/payload) discharges via an n-way int-tag chain (`classifyNArmAdtArms` + `buildOpaqueSumBranchN`; n=2 byte-identical, no shipped 2-arm sidecar invalidates); exhaustiveness enforced upstream by the type checker; recursive-payload firewall unchanged. **Commit B:** sequential matches (a multi-path `let`-bound match threaded into a following match) discharge (§S4 per-path fresh graft; refutation preserved; single-match byte-identical). Same QF-LIA int-tag theory as v0.14.12; no schema change. Flips the one-pager `EMatch` (>2 arms / sequential) boundary rows | 2026-07-10 | 1137 H + 45 Py | `CHANGELOG.md §v0.14.26` |
| **v0.14.25** | REC-DESCENT Phase 2+3 (completes REC-BODY-VC) — a discharging single-measure `(decreases e)` on `def-shell` verifies **total** correctness: well-foundedness (`pre ⟹ e≥0`) + per-call-site strict descent (`pre ∧ path ⟹ e[args']<e`), QF-LIA over `<` on ℕ; a discharged SCC drops `termination_unverified` and becomes strict-core admissible (the b1 lift); a bad measure is `measure-not-decreasing` (hard exit-1, distinct from `refuted`, surfaced in trust + obligation reports); admission tightened so a measureless recursive callee is refused from strict-core (gap closure); measure folds into `canonicalDefEvidenceHash` (byte-inert empty). Different-measure mutual recursion admitted (Floyd common-ℕ); k>1/nonlinear/distributed-decrease stay partial. `EvidenceRecord.erTerminationVerified`; obligation-report schema 0.12.1→0.12.2; no AST schema change | 2026-07-10 | 1126 H + 45 Py | `CHANGELOG.md §v0.14.25` |
| **v0.14.24** | REC-DESCENT Phase 1 (increment 3 of REC-BODY-VC) — optional list-shaped `(decreases e₁…eₖ)` measure clause on `def-shell` (new `defShellDecreases` AST field, S-expr + JSON-AST parse/emit, int-typed measure scope check, `result` rejected). **Verification-inert:** no obligation emitted, `canonicalDefEvidenceHash` untouched, a `decreases`-carrying recursive `def-shell` verifies unchanged (still `termination_unverified`). Well-foundedness + strict descent + `measure-not-decreasing` verdict + measure-in-hash + admission lift are Phase 2/3. `schemaVersion` 0.7.0→0.8.0 (`$id` /schemas/v0.8/); ~82 `SDefShell` sites migrated | 2026-07-10 | 1113 H + 45 Py | `CHANGELOG.md §v0.14.24` |
| **v0.14.23** | REC-PARTIAL-MARK (increment 2/(a) of REC-BODY-VC) — every recursive call-cycle member carries a derived `termination_unverified` per-entry flag + top-level `partial_fns` list in `--trust-report`; informational (off the trust-meet axis, like `refuted`/`overflow_tainted`), derived-not-persisted (survives a solver-less render), so a recursive `def-shell` keeps its partial-correctness `verified` post AND is flagged. Makes the §4.2 partiality-flag claim true; D1/D2 recursion spec reconciliation; cascading-refinement Option-3 → Rev 3. `trust_report_version` 1.4.0→1.5.0; no AST schema change | 2026-07-10 | 1107 H + 45 Py | `CHANGELOG.md §v0.14.23` |
| **v0.14.22** | REC-HASH-FORM (increment 1/b0 of REC-BODY-VC) — `canonicalDefEvidenceHash` folds the def-form into its preimage (`Syntax.defFormTag`) and bumps `admitVerifiedSemanticsTag` `av1`→`av2`, so a `def-shell`→`def` rename over an intact `.verified.json` drifts the hash → the existing staleness path downgrades it → the self-callee is rejected at strict-core admission instead of laundering partial-correctness recursion into the `verified` tier (probe E). One-time sidecar re-verify (av2). No schema change | 2026-07-10 | 1102 H + 45 Py | `CHANGELOG.md §v0.14.22` |
| **v0.14.21** | Checkout brief marks the enclosing function `"hole"` (HOLE-STATUS) — the brief presented the hole's own function as an available `"filled"` callable, and a blind fill agent answered with a degenerate self-call that patches and verifies SAFE at partial correctness (R7 gap); the documented `"hole"` enum value is now emitted; `available_functions` construction extracted to testable `Checkout.buildCheckoutFuncs`. Found live by the secure-channel-emergent blind-fill run. No schema change | 2026-07-09 | 1098 H + 45 Py | `CHANGELOG.md §v0.14.21` |
| **v0.14.20** | Obligation-report vocabulary gate fix (OBLIG-VOCAB-GATE) — an unknown-typed hole's `contracted_functions` / `available_functions` no longer silently empty (the missing type defaulted to `TUnit`, dropping every `-> T`-annotated function and every monomorphic-return builtin); unknown now yields the full capped vocabulary, unannotated functions display `return_type: "?"`, known types still gate. Root-cause follow-on tracked as OBLIG-HOLE-TYPE. No schema change | 2026-07-09 | 1097 H + 45 Py | `CHANGELOG.md §v0.14.20` |
| **v0.14.19** | Imported names in brief scope/function channels (XMOD-SCOPE-BRIEF) — `available_functions` lists imported exported contracted functions under their callable names (`status: "imported"`; bare when opened, qualified otherwise, local shadow honored); `in_scope` carries imported names via a seeded sketch env (`seedCacheEnv`, bare aliases labeled `open-import`); the obligation report's per-hole `contracted_functions` gains the same vocabulary. `brief_version` 0.12.1 → 0.12.2; no AST schema change | 2026-07-09 | 1094 H + 45 Py | `CHANGELOG.md §v0.14.19` |
| **v0.14.18** | Cache-aware checkout brief (XMOD-CG-BRIEF) — the brief's `consumed_guarantees` includes imported callees (checkout `ContractEnv` seeded from the module cache via the verify path's exact recipe, `cacheAwareAliasMap`/`cacheAwareContractEnv`); `callee_tier` resolves through the qualified trust entry (generalized `injectOpenedAliases`), never the `"builtin"` fallthrough. Closes XMOD-COMP layer 5; residual → XMOD-SCOPE-BRIEF. No schema change | 2026-07-09 | 1088 H + 45 Py | `CHANGELOG.md §v0.14.18` |
| **v0.14.17** | Body-faithful cross-module assume-guarantee (XMOD-AG) — a caller of an `import`-ed contracted function verifies body-faithful instead of falling back, so programs can split into `import`-linked modules and stay `verified` under `--strict-verified-core` (body-VC `ContractEnv` seeded from the module cache). No schema change | 2026-07-08 | 1084 H + 45 Py | `CHANGELOG.md §v0.14.17` |
| **v0.14.16** | Implication sugar `=>` / `<=>` — symbolic binary `bool → bool → bool` implication and biconditional, desugared at VC emission to the `or`/`not` form (byte-identical `.fq`, zero verification change); first-class in both S-expr and JSON-AST surfaces with round-trip preservation; schema op enum extended additively, `schemaVersion` stays 0.7.0 | 2026-07-07 | 1073 H + 45 Py | `CHANGELOG.md §v0.14.16` |
| **v0.14.15** | Fix: `(not b)` / any `not` on a `bool` value in a body/return position no longer crashes liquid-fixpoint (a v0.14.14 regression — `not` is predicate-only in the fixpoint grammar); `emitPred` rewrites `X = ¬Y` to `X ≠ Y`, qualifier params carry real sorts; `not`-value bodies and two-bool-variable equality now verify body-faithful | 2026-07-07 | 1073 H + 45 Py | `CHANGELOG.md §v0.14.15` |
| **v0.14.14** | `bool` admitted to the body-faithful fragment `Σ_auto` — a `bool` param / result / refinement atom / `if`-condition now verifies body-faithful instead of dropping to contract-only (`isScalarLike = isIntLike ∨ isBoolLike` at the sort-env sites); the `FQBool` / `emitSort` / `typeToSort TBool` infrastructure already existed | 2026-07-07 | 1071 H + 45 Py | `CHANGELOG.md §v0.14.14` |
| **v0.14.13** | Cascading `refine` op + CDP vacuity gate; cycle-verification spec reconciliation — `refine` installs a hole body and spawns contracted sub-holes atomically (emergent decomposition); a spawn-time CDP vacuity gate rejects a trivially-satisfiable sub-contract; the `letrec` / `def-shell` cycle partial-correctness treatment reconciled with the spec | 2026-07-06 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.13` |
| **v0.14.12** | MATCH-WIDEN — mixed nullary/payload two-arm sums, nested matches, and scrutinee-constructor postconditions verify body-faithful (int-tag discriminant, QF-LIA, conservative); enables the flagship goto-fail pipeline (`examples/gotofail/`). Sequential matches still fall back. No schema change | 2026-07-06 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.12` |
| **v0.14.11** | Body-VC A-normalization — `aNormalizeBody` lifts contracted calls out of argument / pair-component / if-condition positions so nested/argument-position calls verify instead of falling back; identity on call-free arguments. No schema change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.11` |
| **v0.14.10** | R5 concurrency-safe `diverge-report` — per-fill classification writes to a unique temp path, closing a race under parallel classification. No schema change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.10` |
| **v0.14.9** | R5 sibling-call classification fix — a `def-shell` fill calling a verified sibling verifies modularly through the call instead of being dropped as `type-error`; strict-`def` sibling calls stay conservative. No schema change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.9` |
| **v0.14.8** | Experimental Leanstral `verified-lean` demo slice (demo-only) — opt-in `--leanstral` proves a faithfully-translatable nonlinear obligation in Lean 4 + Mathlib and records `verified-lean` + a re-checkable `.lean` certificate; production LEAN-GA rebuild deferred. No schema change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.8` |
| **v0.14.7** | R5 differential-implementation-pressure (observational stages 1-2) — `checkout --multi N` + `diverge-report` classify observational divergence among verifying fills; plus the `sanitizeProof` anti-laundering guard (rejects empty/`sorry`/`admit`). No schema change | 2026-07-04 | 1040 H + 45 Py | `CHANGELOG.md §v0.14.7` |
| **v0.14.6** | Zero-install Docker image — slim (~229 MB) verify-capable `ghcr.io/machunter/llmll` (bundles `llmll` + `fixpoint` + `z3` + demos; `Dockerfile` two-stage `haskell:9.6.6` → `debian:bookworm-slim`) so a no-toolchain user can `docker run … llmll verify` and see the SMT refutation; `docker-publish.yml` pushes on a `vX.Y.Z` tag (gated on `version_gate.sh` + tag==banner); off-roadmap adoption work, no `compiler/src`/schema change | 2026-07-03 | 1024 H + 45 Py | `CHANGELOG.md §v0.14.6` |
| **v0.14.5** | Trust-report `over-annotation-warning` JSON gap — the module-level self-attestation guardrail (CDP proposal §10 Risk #3) was computed correctly but unreachable via any `--json` output at any ratio, found by the new `experiments/adv-spec-weaken-0/` adversarial benchmark; new top-level `over_annotation` object in `--trust-report --json`; no schema/`trust_report_version` change | 2026-07-03 | 1024 H + 45 Py | `CHANGELOG.md §v0.14.5` |
| **v0.14.4** | CDP spec-entropy suppression fix — `(spec-entropy :intentional \| :unknown)` now actually suppresses `identity-satisfies-post`/`const-satisfies-post` (inert since v0.11); new `--strict-verify` flag bundles the recommended serious-verify path; closes CDP default-on precondition (c); no schema change | 2026-07-02 | 1019 H + 45 Py | `CHANGELOG.md §v0.14.4` |
| **v0.14.3** | 15-bug pass from a full documentation + examples audit — parser, codegen, trust-report/JSON, CLI, and orchestrator fixes plus fixture-level example fixes. No schema change | 2026-07-02 | 1014 H + 45 Py | `CHANGELOG.md §v0.14.3` |
| **v0.14.2** | CDP deep-dive — candidate basis emits real `ok`/`err` (not raw internal names); `erBodyFallback` body-faithfulness gate closes a broader unvalidated-candidate class; `--strict-verified-core --trust-report --cdp --json` now actually populates `discriminative_axis`; `spec-inconsistent` → `spec-inconsistent-or-unproven` (claim-accuracy rename); no schema change | 2026-07-01 | 978 H + 62 Py | `CHANGELOG.md §v0.14.2` |
| **v0.14.1** | Checkout-lock sum-type fix — a sum-type `TypeDefEntry` now round-trips through the checkout lock (fixes `patch` rejecting valid tokens for any program with a `data`/sum type in scope); `withdraw-demo` integrates `withdraw-outcome` as a third fillable hole | 2026-06-30 | 966 H + 62 Py | `CHANGELOG.md §v0.14.1` |
| **v0.14.0** | PROOF-ARTIFACT (staged MVP) — `verify --proof-artifact` emits a unified, replayable verification record; `replay-artifact` re-derives it fail-closed; §4.1 LCF anti-laundering invariant enforced on emit and parse; `unsat_core` deferred | 2026-06-30 | 965 H + 62 Py | `CHANGELOG.md §v0.14.0` |
| **v0.13.14** | datatype-tail — admissibility recurses over the acyclic composition, so pair-of-`Result` components and nested/composed-datatype payloads verify; the only remaining boundary is `list`-carrier + recursive payloads (a deliberate firewall). Completes the PAIR-RET line. No schema change | 2026-06-29 | 961 H + 62 Py | `CHANGELOG.md §v0.13.14` |
| **v0.13.13** | COMP-4-RESULT — `(ok e)`/`(err e)` construction is body-faithful (`Result` promoted to the polymorphic `data Result 2`), closing the COMP-4 (a) construction drift. No schema change | 2026-06-29 | 958 H + 62 Py | `CHANGELOG.md §v0.13.13` |
| **v0.13.12** | PAIR-RET-2 — pair components extended to nested / list / admissible sum-or-ADT (`(int, Box)` → `(Pair2 int Box)`, alias-aware `typeToSortA`); a recursive-sum component falls back cleanly via the §5.3.3 firewall (previously crashed the solver). No schema change | 2026-06-29 | 952 H + 62 Py | `CHANGELOG.md §v0.13.12` |
| **v0.13.11** | PAIR-RET — refinement predicates over pair/tuple returns: `first`/`second` reflect to datatype selectors and `(pair a b)` to the constructor (polymorphic `data Pair2 2`), so a post like `(= (+ (first r) (second r)) k)` discharges (`verified`/`refuted`) instead of `asserted`; unblocks two-account conservation (`examples/payments-core/conserve.llmll`). No schema change | 2026-06-29 | 946 H + 62 Py | `CHANGELOG.md §v0.13.11` |
| **v0.13.10** | COMP-4 polish — nullary-variant construction `(Empty)` types as its sum (typecheck fix); tcp_rfc793/session-pay reshaped to real outcome sums (int sentinel dropped, full totality posts); LLMLL.md verification matrix reconciled to the shipped sum-type surface (`Σ_auto` + acyclic datatype theory). No schema change | 2026-06-28 | 939 H + 62 Py | `CHANGELOG.md §v0.13.10` |
| **v0.13.9** | COMP-4 (a)/(c): native datatype construction — a constructor over an admissible two-arm sum reflects into a native FQData term; construction + totality posts discharge by constructor equality, refute by injectivity; recursive datatypes firewalled. First verification beyond pure QF-LIA. Completes the COMP-4 line. No schema change | 2026-06-28 | 938 H + 62 Py | `CHANGELOG.md §v0.13.9` |
| **v0.13.8** | COMP-4 (b): refined sum payloads — a matched two-arm-sum payload carries its declared refinement (elimination, via a `ReaderT` refinement-env + `FQPred` binder field), enforced by a declaration-driven call-site payload-subtyping obligation (introduction, a refinement-subtyping Horn constraint with a syntactic-reflexivity fast-path); new `examples/refined-payload/`; no schema change | 2026-06-28 | 936 H + 62 Py | `CHANGELOG.md §v0.13.8` |
| **v0.13.7** | COMP-4 (d-elim) + ContractEnv enum-desugar fix — two-arm user-ADT matches verify body-faithfully (opaque-sum elimination beyond `Result`; QF-LIA scalars, firewall on sum payloads); fix: contracts desugar nullary-enum ctors in the ContractEnv (compositional call-edge crash); new `examples/nested-result/`; no schema change | 2026-06-27 | 932 H + 62 Py | `CHANGELOG.md §v0.13.7` |
| **v0.13.6** | COMP-3b-general: opaque-sum elimination at any nesting depth — a `Result`-typed *variable* match reaches body-faithful `verified` at any nesting depth (not just the top-level body) via a binder-carrying `BranchVC` + `collectBranchBinders` + derived `SortEnv` payload-sort keys; the v0.13.3 top-level flat-`Result` special-case is subsumed; refuted-arm localization fixed (structural branch provenance); no schema change | 2026-06-27 | 928 H + 62 Py | `CHANGELOG.md §v0.13.6` |
| **v0.13.5** | Nullary-enum verification (COMP-3b-general Phase 1) + connected session demo — idiomatic nullary-enum types matched and used as values in a `def` body reach body-faithful `verified` via a pre-translation desugar (`desugarCtorValues`), retiring the int-encoding workaround; `examples/tcp_rfc793/` re-typed to real enums; new `examples/session-pay/`; no schema change | 2026-06-27 | 924 H + 62 Py | `CHANGELOG.md §v0.13.5` |
| **v0.13.4** | Loud verify + protocol & payments demos — `verify` prints a SOLVER-NOT-FOUND banner and exits 3 (≠ 1=refuted) when no SMT solver is on PATH; new `examples/payments-core/` (verified transfer + COMP-3b settle) and `examples/tcp_rfc793/` (RFC 793 state machine → `verified`); no schema change | 2026-06-23 | 914 H + 62 Py | `CHANGELOG.md §v0.13.4` |
| **v0.13.3** | Sum-Type Verification Fixes (ADT emission + COMP-3b) — `.fq` ADT `data` declarations emit with source-case type names and valid constructor syntax (user sum types no longer crash liquid-fixpoint); COMP-3b — a refinement-aliased return over a flat two-arm `Result`-variable match now produces a body-faithful VC; `schemaVersion` `0.7.0` | 2026-06-23 | 914 H + 62 Py | `CHANGELOG.md §v0.13.3` |
| **v0.13.2** | Return-Refinement Discharge (DEF-RET Unit 2) — a refinement-aliased return discharges via the body-VC and is exported as a caller-assumable guarantee; `schemaVersion` `0.7.0` | 2026-06-21 | 908 H + 62 Py | `CHANGELOG.md §v0.13.2` |
| **v0.13.1** | Optional Return-Type Annotation (DEF-RET Unit 1 / OBLIG-1-FOLLOWON) — optional `-> RetType` on `def`/`def-shell`; populates `expected_return_type`; schema `0.6.0 → 0.7.0` | 2026-06-21 | (see v0.13.2) | `CHANGELOG.md §v0.13.1` |
| **v0.13.0** | Caller-Obligation Axis + Verified Composition — TRUST-PRE (a precondition no longer floors the trust tier; first-class `caller_obligations` axis), ADMIT-VERIFIED strict-core composition admission, DEMO-COMP; `trust_report_version` `1.4.0` | 2026-06-19 | 900 H + 62 Py | `CHANGELOG.md §v0.13.0` |
| **v0.12.1** | def-logic Removal + def-invariant Node — `def-logic` is a hard parse error under all grammar modes; `def-invariant` promoted to its own `SDefInvariant` AST node; `schemaVersion` `0.6.0` | 2026-06-17 | 862 H + 62 Py | `CHANGELOG.md §v0.12.1` |
| **v0.12.0** | Refinement Metatheory of Record + Effect/Authority Summaries — REF-META 1–5; Bundle B0 `effect_summary` + cross-module propagation; NIW Phase 1; `trust_report_version` `1.3.0` | 2026-06-15 | 855 H + 62 Py | `CHANGELOG.md §v0.12.0` |
| **v0.11** | Core/Shell Inversion + Evidence-Axis Enrichment — LT-INV (`def`/`def-shell` canonical, `GrammarCoreInversion` default), LT-INT, LT-CDP `--cdp`, LT-PPR, VERIFY-RPT-1; schema `0.5.0 → 0.6.0` | 2026-05–06 (v0.11.0–v0.11.2) | 811 H + 62 Py | [archive §v0.11](archive/roadmap-shipped-history.md#v011--coreshell-inversion--evidence-axis-enrichment--shipped) |
| **v0.10** | Obligation-Guided Agent Coding — structured obligation reports (3 channels: type/contract/trust), `EMatch` branch obligations, repair suggestions, benchmark suite | 2026-05-03 | 556 H + 37 Py | [archive §v0.10](archive/roadmap-shipped-history.md#v010--obligation-guided-agent-coding--shipped) |
| **v0.10.1–v0.10.8** | Patch lane (in-freeze, narrowing): version cmd, alias resolution, soundness blockers, schema bumps `0.3.0 → 0.5.0`, PBT generators + trust write-back, TC-EOP-1, OBLIG-PBT-5a, INT-1 overflow taint | 2026-05-10 → 2026-05-24 | up to 672 H + 37 Py | [archive §Per-version digests](archive/roadmap-shipped-history.md#per-version-result-digests-v07--v0108) |
| **v0.9** | Compositional Verification — assume-guarantee `EApp` encoding, `EMatch` on `Result`, SCC fallback, `--strict-verified-core`. v0.9.1: module system hardening | 2026-05-01 | 452 → 474 H + 37 Py | [archive §v0.9](archive/roadmap-shipped-history.md#v09--compositional-verification--shipped) |
| **v0.8.1b** | Evidence Model Refactor — four-tier `DisplayLevel` partial order replaces `VerificationLevel` total order; hard break for `.verified.json` | 2026-05-01 | 322 H + 37 Py | [archive §v0.8.1b](archive/roadmap-shipped-history.md#v081b--evidence-model-refactor--shipped) |
| **v0.8.1a** | Documentation Boundary Clarity — verification matrix in LLMLL.md/README/one-pager; integer overflow gap documented; docs-only | 2026-04-30 | 320 H + 37 Py | [archive §v0.8.1a](archive/roadmap-shipped-history.md#v081a--documentation-boundary-clarity--shipped) |
| **v0.8.0** | Faithfulness Core — BODY-VC (body-faithful verification conditions), SUPP-DEBT, EVENT-LOG, SPEC-FOUNDATION | 2026-04-29 | 320 H + 37 Py | [archive §v0.8.0](archive/roadmap-shipped-history.md#v080--faithfulness-core--shipped) |
| **v0.7** | Hardening — BUILTIN-1/2 (total builtins), DO-1 (discarded command warning), TRUST-2a (`VLProvenSMT`, `Ord` removal) | 2026-04-29 | 294 H + 37 Py | [archive §v0.7](archive/roadmap-shipped-history.md#v07--hardening--shipped) |
| **v0.6.3** | Trust Model Fixes — 7 critical bugs (BUG-1..7): `tcStrictMode` gate, transitive trust closure, proof-laundering protection | 2026-04-26 | 289 H + 37 Py | [archive §v0.6.3](archive/roadmap-shipped-history.md#v063--trust-model-fixes--shipped) |
| **v0.6.2** | Algebraic Interface Laws — `def-interface :laws` with `for-all` + QuickCheck codegen + VSM-1 backfill | 2026-04-24 | 289 H + 37 Py | [archive §v0.6.2](archive/roadmap-shipped-history.md#v062--algebraic-interface-laws--shipped) |
| **v0.6.1** | TOTP Benchmark & Hub Query — RFC 6238 TOTP frozen benchmark, hub query-by-signature, crypto builtins (§13.11) | 2026-04-23 | 289 H + 37 Py | [archive §v0.6.1](archive/roadmap-shipped-history.md#v061--totp-benchmark--hub-query--shipped) |
| **v0.6.0** | Specification Quality — spec coverage gate, frozen ERC-20 benchmark, suppression governance, clause-level provenance | 2026-04-22 | (see v0.6.1) | [archive §v0.6.0](archive/roadmap-shipped-history.md#v060--specification-quality--shipped) |
| **v0.5** | U-Full Soundness — complete Algorithm W (occurs check + let-generalization); `effectful` WASM compat spike (GO) | 2026-04-21 | 264 H | [archive §v0.5](archive/roadmap-shipped-history.md#v05--u-full-soundness--shipped) |
| **v0.4** | Lead Agent + U-Lite Soundness — automated skeleton generation, concrete-type unification, CAP-1 capability enforcement, invariant registry | 2026-04-19 | 225 H + 12 Py | [archive §v0.4](archive/roadmap-shipped-history.md#v04--lead-agent--u-lite-soundness--shipped) |
| **v0.3.5** | Agent Effectiveness — orchestrator end-to-end fill, context-aware checkout (Phase C), weak-spec counter-examples | 2026-04-19 | 225 H + 12 Py | [archive §v0.3.5](archive/roadmap-shipped-history.md#v035--agent-effectiveness--shipped-2026-04-19) |
| **v0.3.4** | Agent Spec + Orchestrator Hardening — compiler-emitted `llmll spec` (Phase B) + faithfulness property tests | 2026-04-19 | 211 H | [archive §v0.3.4](archive/roadmap-shipped-history.md#v034--agent-spec--orchestrator-hardening--shipped-2026-04-19) |
| **v0.3.3** | Agent Orchestration — `llmll holes --json --deps`, Python orchestrator v0.1, agent prompt semantic reference (Phase A) | 2026-04-16 | (see v0.3.4) | [archive §v0.3.3](archive/roadmap-shipped-history.md#v033--agent-orchestration--shipped-2026-04-16) |
| **v0.3.2** | Trust Hardening + WASM PoC — `--trust-report` flag, cross-module trust propagation tests, GHC WASM proof-of-concept | 2026-04-16 | 194 H | [archive §v0.3.2](archive/roadmap-shipped-history.md#v032--trust-hardening--wasm-poc--shipped-2026-04-16) |
| **v0.3.1** | Event Log + Leanstral MCP — JSONL event log + deterministic replay; mock-first Leanstral proof integration | 2026-04-11 | 181 H | [archive §v0.3.1](archive/roadmap-shipped-history.md#v031--event-log--leanstral-mcp--shipped-2026-04-11) |
| **v0.3** | Agent Coordination + Interactive Proofs — do-notation, pair destructuring, stratified verification, `?scaffold`, async codegen, checkout/patch | 2026-04-05 → 2026-04-11 | (see v0.3.1) | [archive §v0.3](archive/roadmap-shipped-history.md#v03--agent-coordination--interactive-proofs--shipped) |
| **v0.2** | Module System + Compile-Time Verification — multi-file resolution, decoupled liquid-fixpoint `.fq` backend, `--sketch` API | 2026-03-27 → 2026-03-28 | 47 H | [archive §v0.2](archive/roadmap-shipped-history.md#v02--module-system--compile-time-verification--shipped) |
| **v0.1.3** | Type Alias Expansion — structural type-alias resolution, where-clause binding scope, post-ship bug fixes | 2026-03-21 | 25 H | [archive §v0.1.3](archive/roadmap-shipped-history.md#v013--type-alias-expansion--shipped-2026-03-21) |
| **v0.1.2** | Machine-First Foundation — JSON-AST parser + schema, Haskell codegen target, minimal surface syntax fixes | 2026-03 | — | [archive §v0.1.2](archive/roadmap-shipped-history.md#v012--machine-first-foundation--shipped) |

> Detailed per-item history (commit SHAs, design-doc links, acceptance criteria) lives in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md). Canonical release narrative: [`../CHANGELOG.md`](../CHANGELOG.md).

---

## Resolved cross-cutting items

<details><summary><strong>Resolved cross-cutting items (click to expand)</strong></summary>

| Item | Resolution |
|------|------------|
| **XMOD-STALE** (persistent ModuleCache coherence under LSP/Serve/watch) | **Closed — no consumer exists (2026-07-11).** The hypothesized long-lived-cache consumer does not exist: `ModuleCache` appears only on the per-invocation CLI path; `Serve.hs` is stateless per request by recorded design (no `IORef`/`MVar`/`TVar`, source re-read per request; professor + language-team decision 2026-03-28), and no LSP server or watch mode exists in `compiler/`. Nothing to build. **Standing constraint:** any *future* long-lived `ModuleCache` consumer (Serve/LSP/watch) must evict a callee `ModuleEnv` on a callee source/sidecar mtime change, per [`def-ret-staleness-hash-review.md`](archive/professor-reviews/def-ret-staleness-hash-review.md) §G2. |
| Orchestration event log format (Q3 from v0.3.3) | **Shipped** (v0.8.0, EVENT-LOG) |
| MCP integration (Q5 from v0.3.3) | Moved to v0.8.1 |
| Real Leanstral integration | Moved to v0.8.1 as LEAN-GA. Product claim narrowed (v0.6 CLAIM-1..2). |
| Spec coverage metric (`--spec-coverage`) | **Shipped** (v0.6.0, SC-1..SC-4) |
| Spec-adequacy benchmark (ERC-20) | **Shipped** (v0.6.0 BM-1..3/5, v0.6.1 BM-4) |
| Spec-adequacy benchmark (TOTP) | **Shipped** (v0.6.1, BM2-1..BM2-5) |
| Verification-scope matrix policy | **Shipped** (VSM-2 policy, VSM-1 backfill in v0.6.2) |
| Suppression governance (`weakness-ok`) | **Shipped** (v0.6.0); JSON-AST schema gap closed (v0.11.1, commit `6af4975`, 2026-06-06): `WeaknessOkDecl` added to `docs/llmll-ast.schema.json` `$defs` and `Statement.oneOf`; empty-reason guard added to `parseWeaknessOkDecl` (`ParserJSON.hs:397`); 804 → 807 Haskell tests. |
| Claim-to-evidence appendix | **Shipped** in one-pager (2026-04-23) |
| Contract clause-level provenance | **Shipped** (v0.6.0 PROV-1/2/4, v0.6.1 PROV-3) |
| Hub query-by-signature | **Shipped** (v0.6.1, HUB-1..HUB-3) |
| Algorithm W `TDependent` interaction | **Resolved** (Strip-then-Unify, Option A, 2026-04-19) |
| `TSumType` wildcarding in `compatibleWith` | **Fixed** in U-Lite (v0.4, U7-lite) |
| Cross-module `ContractEnv` (MOD-1) | **Shipped** with v0.10 (v0.10 prerequisite); see [Shipped Releases](#shipped-releases) v0.10 line. |
| Evidence model design (EVID-0) | **Approved** (Rev 2) — **shipped** via v0.8.1b (commit `bf98797`); see [Shipped Releases](#shipped-releases). |
| Obligation-guided agent coding (v0.10) | **Shipped** (2026-05-03; final patch v0.10.6 on 2026-05-14). 640 Haskell + 37 Python tests. |
| Module system hardening (v0.9.1) | **Shipped** (2026-05-01). |
| MOD-PBT-1 / OBLIG-PBT-2/3/4 (cross-module PBT visibility, complex-type generators, trust write-back, `:subject` linkage) | **All shipped** (v0.10.3–v0.10.6). Per-item provenance in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md) and `CHANGELOG.md`. |
| v0.10.x patch lane (DRIFT-1, TC-EOP-1, OBLIG-PBT-5a, INT-1, DRIFT-CI-1, F-GATE-8, VERIFY-RPT-1) | **All shipped** (v0.10.7–v0.11.1). Per-item provenance in [Shipped Releases](#shipped-releases) and `CHANGELOG.md`. |
| v0.11 LT items (LT-INV, LT-CDP, LT-PPR, LT-INT/INT-2, INT-PRE, REF-META-1) | **All shipped** (v0.11). LT-INV's def-logic removal completed in v0.12.1. Per-item provenance (design-doc links, professor-review folds, SHAs) in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md) §v0.11 and `CHANGELOG.md`. |
| REF-META-2..5 (solver-completeness, predicate WF, erasure, type-assignment) | **All promoted / shipped** v0.12.0; metatheory of record (1–5) complete. `LLMLL.md §5.3.3 / §3.4.4 / §3.4.5 / §3.4.6`; see [Shipped Releases](#shipped-releases) v0.12.0 line. |
| Bundle B0 (per-function `effect_summary`) | **Shipped** v0.12.0 (commit `b2d9c1a`) + cross-module propagation (commit `85d2a7d`). B1 follow-on awaits a B1-native experiment (B0 gate retired, F-B0-3 commit `049a294`). |
| Non-int refinement widening Phase 1 + F-NIW-2/3/4/4b | **Shipped** v0.12.0 (commits `0b05916`/`25c489d`/`a801112`/`3b74d24`); measure-refined params get full intro+elim. Phase 2 (ADT-field refinements) future. |
| DEF-RET (optional return-type annotation + return-refinement discharge) | **Shipped** — Unit 1 v0.13.1 (commit `a948deb`), Unit 2 v0.13.2 (commits `0b27be5`/`12210b0`). Closed the `expected_return_type` OBLIG-1-FOLLOWON value path; schema `0.6.0 → 0.7.0` (Unit 1). See [Shipped Releases](#shipped-releases) v0.13.1/v0.13.2 lines. |

</details>

> **XMOD-COMP (cross-module verified composition) — closed, all five layers plus the sibling brief channels.** Layers 1–3 shipped earlier (admission / type-alias type-check / trust-tier edge); layer 4 (body-VC emission) by **XMOD-AG (v0.14.17)**; layer 5 (checkout `consumed_guarantees`) by **XMOD-CG-BRIEF (v0.14.18)**; the sibling brief channels (`available_functions` / `in_scope` / obligation-report `contracted_functions`) by **XMOD-SCOPE-BRIEF (v0.14.19)**. A cross-module program now verifies body-faithful AND presents its imported callables through every agent-facing channel. See [`cross-module-composition-finding.md`](archive/shipped-design-specs/cross-module-composition-finding.md).
