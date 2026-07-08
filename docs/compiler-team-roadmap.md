# LLMLL Compiler Team Implementation Roadmap

> **Status:** Active — see [`../CHANGELOG.md § Latest`](../CHANGELOG.md#Latest) for shipped version (canonical per DOC-CONSOLIDATE P1; this header no longer version-stamps).  
> **Source documents:** `LLMLL.md` · `consolidated-proposals.md` · `proposal-haskell-target.md` · `analysis-leanstral.md` · `design-team-assessment.md` · `proposal-review-compiler-team.md` · Professor's five-round review (2026-04-30)
>
> **Governing design criterion:** Every compiler deliverable is evaluated against *progress toward one-shot correctness* — does this release reduce the iteration burden, increase obligation completeness, or shorten the repair distance for an AI agent producing LLMLL code? The intended terminal state is that an agent writes a program once, the compiler accepts it, contracts verify.
>
> We measure progress toward that state empirically, including via repair-loop experiments where the verification surface's iteration aid is the dependent variable. First-round measurement is one such empirical regime; it is not the only one, and it is not load-bearing for every feature. See [`experiments/methodology.md`](../experiments/methodology.md) for the diagnosis and rationale.
>
> **Relationship to `LLMLL.md §14`:** The two documents are **complementary, not competing**. `LLMLL.md §14` is the *language-visible feature list* (what users and AI agents see). This document is the *engineering backlog* — implementation tickets, acceptance criteria, decision records, and bug tracking. When a feature ships it is marked complete here and the user-visible description is kept in `LLMLL.md §14`.

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
- [Feature Freeze Policy](#feature-freeze-policy)
- [What's NOT on this Roadmap](#whats-not-on-this-roadmap-and-why)

**History (append-only):**
- [Shipped Releases](#shipped-releases) — compact one-line-per-version summary; detail in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md)
- [Resolved cross-cutting items](#resolved-cross-cutting-items)

> Skills deep-link into these anchors per `docs/UPDATE-PROTOCOL.md` §3.1. The detailed per-version implementation history (v0.2 → v0.12, plus the verbose v0.11/v0.10 planning detail and the historical v0.8–v0.10 critical-path diagram) was split out to [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md) under DOC-CONSOLIDATE M5 (large-cut, 2026-06-21). The `#shipped-releases` anchor below remains live and is the stable entry point other docs link to.

---

# Active & Next Work

## Active Items

> **Routing:** items below are the genuinely-open work. Tags follow the `XXX-N` pattern; full triage record at [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) §4. The v0.10.x patch lane and the v0.11/v0.12 architectural lanes have fully shipped — their rows are retired to the [Resolved cross-cutting items](#resolved-cross-cutting-items) block, with full provenance in [Shipped Releases](#shipped-releases), [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md), and `CHANGELOG.md`.

> **Near-term adoption work (off-roadmap).** Zero-install/Docker packaging shipped in **v0.14.6** (`ghcr.io/machunter/llmll`; `Dockerfile` + `.github/workflows/docker-publish.yml`; verify-capable image bundling `llmll` + `fixpoint` + `z3`). The README rewrite, the payments-core + TCP-793 demos, and version-embed also shipped. **No off-roadmap adoption item is currently open.** Do not read the items below as the current priority order.

### Open work (v0.12+ post-freeze lane)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **XMOD-STALE** (persistent ModuleCache coherence under LSP/Serve/watch) | **Tracked — build-driver obligation, not trust-logic** | The CLI (recompute-per-build) is sound. Residual hazard: a long-lived `ModuleCache` (`Serve.hs`/LSP/watch) that fails to evict a callee `ModuleEnv` on a callee source/sidecar mtime change — confirm any long-lived-cache consumer exists before building. Per [`def-ret-staleness-hash-review.md`](archive/professor-reviews/def-ret-staleness-hash-review.md) §G2. |
| **CDP default-on** (promote `--cdp` / `--weakness-check` / `--spec-coverage` into the default serious-verify path) | **DEFERRED (nice-to-have) — decision input now available, default-flip not pursued** | Currently opt-in. Preconditions (a)/(b)/(c) all closed as of v0.14.4 (see prior updates below). **Update (`experiments/cdp-perf-0/`, v0.14.5-era):** the previously-missing wall-clock characterization now exists — `overhead_ms ≈ 27.32 + 43.47 × candidate_count` (R²=0.9995, primary corpus), i.e. `--cdp` roughly doubles-to-triples verify wall-clock on any module with candidates. Flipping the default was explicitly considered against this data and **deferred** — kept as an opt-in via `--strict-verify` rather than promoted, on cost/UX grounds independent of the wall-clock number itself (every `verify` call would gain unprompted diagnostic surface; `--strict-verify` would become redundant with bare `verify`; a new fast-path opt-out flag would be needed; the self-attestation-gaming dilution floor from `experiments/adv-spec-weaken-0/` F-002 becomes more load-bearing if quiet-by-default becomes the norm agents optimize toward). Revisit if a concrete need emerges; not actively pursued. **Prior updates (CDP deep-dive, v0.14.2, `c2b4d57`):** (a) and (b) substantively closed — the candidate-basis fix + `erBodyFallback` body-faithfulness gate close two independent false-positive mechanisms (the TResult mechanism and a broader body-VC-translation-coverage class), and the flag-first CLI/JSON restructuring is the `§4.4.6` headline caveat. Residual, separate limitation surfaced by the same patch: string-payload `Result` construction (`(err "...")`) still falls back in body-VC translation (`bodyToPredM` has no case for string literal values; `Str` is an opaque measure-only carrier) — safely excluded, not mis-scored, but a real future capability question if `Result[_, string]` contracts are to get real CDP scores. **(v0.14.4, `ea0fba0`):** (c) closed — `(spec-entropy :intentional | :unknown)` suppression was implemented (it had been inert since v0.11: the annotation was parsed and fed the module-level over-annotation ratio but never gated the per-function `WarnIdentitySatisfiesPost`/`WarnConstSatisfiesPost` diagnostics). |
| **OBLIG-1-FOLLOWON** (populate reserved obligation-report fields) | **PARTIAL** — only the `assumptions` field remains | Wire the `assumptions` field (returns-absent, `LLMLL.md:1823-1824`); may want a short language-team semantics pin first; no schema bump expected. (`expected_return_type` + `available_functions` paths shipped — see Shipped Releases.) |
| **INT-3** (`MachineInt` QF-BV alias) | **P3 — open** | LT design when freeze lifts again; promote to P1 if INT-PRE shows TOTP regression > 5× (cleared at 1.015×, so dormant) |
| **OBLIG-PBT-5b** (clean `EvidenceRecord.scope`) | **P2 — open** | engineer post-freeze; `trust_report_version` 1.1.0 → 1.2.0; new `tested-joint` display level |
| **R3 — Spec-from-RFC pipeline** (RFC → LLMLL contracts with `:source` clause provenance) | **PROMOTED (research → Active)** | Worked-example criterion now met: `examples/totp_rfc6238/` + the TCP-793 state-machine demo + shipped `:source` provenance (`LLMLL.md §13.11`). Owed: a generalizable RFC→contract pipeline design doc. |
| **REFINE-REUSE** (reuse retrieval for `refine`: surface existing defs that subsume a spawned sub-contract) | **DESIGN SETTLED (Rev 1) — deferred for later implementation** `[LT→CT]` | Professor-folded settled design [`refine-reuse-gate-proposal.md`](design/refine-reuse-gate-proposal.md) (+ `-review.md`): reclassified gate→**retrieval facility**, *never rejects* — a well-formed duplicate is not a defect (the blocking framing was a category error). Ships an advisory `reuse_suggestions` brief channel (solver-backed subsumption, α-normalized, QF-LIA-or-abstain) + a non-blocking `W-REUSE` warning (canonical-contract key, no solver). **New code:** α-normalized contract key + query-by-contract on `HubQuery.structuralMatch`; `reuse_suggestions` in `Checkout.hs` (briefVersion bump); non-blocking `W-REUSE` in `PatchApply.hs` (no new `PatchApplyError`); implication reuses COMP-4(b) (`FixpointEmit.hs:826–854`; the `:849` fast-path normalizes only the refinement binder, so free-param α-normalization is the real new load). **Next:** compiler-engineer feasibility read when picked up. Stage 4 of the Cascading Refinement track. |

> **Retired (shipped v0.12.0):** REF-META-2..5 (metatheory of record complete), Bundle B0 (per-function `effect_summary` + cross-module propagation), Non-int refinement widening Phase 1 (NIW intro+elim), and F-NIW-2/3/4/4b moved to the [Resolved cross-cutting items](#resolved-cross-cutting-items) block; full per-item provenance retained in the [Shipped Releases](#shipped-releases) v0.12.0 line and `CHANGELOG.md`. Bundle B1 (explicit `Command {stdout} a` annotations) was the gated follow-on; its B0-experiment gate was retired (F-B0-3, commit `049a294`) and B1 now awaits a B1-native experiment. NIW Phase 2 (ADT-field refinements) and B2/B3 remain future.

> **Retired (shipped v0.13.x–v0.14.x; full provenance in [Shipped Releases](#shipped-releases) + `CHANGELOG.md`):** PROOF-ARTIFACT (v0.14.0), COMP-3b-general / COMP-4 (v0.13.5–v0.13.9, line complete), PAIR-RET (v0.13.11–v0.13.14, line complete), and R5 differential-implementation-pressure (v0.14.7 + hardening v0.14.9/v0.14.10 — the forced-diversity experimental follow-on is experiment-lead-owned, tracked in `experiments/minimal-agent/r5-campaign/`). Cross-module assume-guarantee shipped v0.14.17 from the former Future section.

### Adversarial benchmark (experiment-lead-owned)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **Adversarial spec-weakening benchmark** (spec-adequacy under adversarial pressure) | **MEASURED (v0.14.5) — follow-on F-002 now settled** — origin: round-2 external critique ask 3; **Owner: experiment-lead** | Measured whether CDP / `--weakness-check` / `--spec-coverage` flag an agent that *deliberately* weakens a contract until bad code verifies (spec laundering), via the new `experiments/adv-spec-weaken-0/` harness (8 fixtures × 4 CLI configs, two mechanisms: self-attestation gaming via `(spec-entropy :intentional)`, and the closed-candidate-set Ω observational-vs-semantic blind spot per [`LLMLL.md §4.4.6`](../LLMLL.md) — the PREREQ caveat this row cited was already foregrounded at v0.14.2). **Three findings** ([`experiments/adv-spec-weaken-0/findings.md`](../experiments/adv-spec-weaken-0/findings.md)): F-001 (the module-level `over-annotation-warning` guardrail was computed but unreachable via any `--json` output) **shipped in v0.14.5**; F-002 (the 30%-ratio guardrail has a dilution floor a single laundered function clears for free in any module of ≥4 honestly-contracted functions) is **settled** as a design-scope limitation, not a defect — adjudicated jointly by language-team and compiler-engineer: no automated per-instance oracle exists on a self-attestation channel (CDP proposal §10 Risk #3 Rev 2, professor review Gap #5), so `LLMLL.md §4.4.6` was clarified with the abuse-rate-vs-per-instance framing plus the external-policy path F-001 enables (per-function `discriminative_axis` score + `spec_entropy_annotation` are machine-readable, so CI can gate per instance), with no compiler change; an optional mandatory-reason-string on `(spec-entropy :intentional)` is a separate user-elected defense-in-depth proposal, not a detection fix; F-003 (Ω's blind spot confirmed on two type-classes) is descriptive, no action implied. Distinct from OBLIG-B (obligation *completeness*) and from the shipped non-adversarial ERC-20 / TOTP adequacy benchmarks. |

---

## Upcoming Releases

> **Roadmap reorganization (2026-04-30):** Professor's five-round review identified that the old v0.8.1 was entirely blocked on external availability (`lean-lsp-mcp`). Replaced with three actionable milestones: v0.8.1a (documentation boundary clarity), v0.8.1b (evidence model refactor), v0.9 (compositional verification). Those, and everything through v0.14.11 (PROOF-ARTIFACT staged MVP + a checkout-lock sum-type fix + the CDP deep-dive candidate-basis/body-faithfulness fix + a 15-bug pass surfaced by a full documentation + examples audit + the CDP spec-entropy suppression fix + the trust-report over-annotation-warning JSON gap fix + the zero-install Docker image + R5 differential-implementation-pressure with the anti-laundering guard + the experimental Leanstral `verified-lean` demo slice + the R5 sibling-call classification fix + the R5 diverge-report concurrency fix + body-VC A-normalization), have shipped — see [Shipped Releases](#shipped-releases). No version is currently in flight; the next release will be cut from the [Active Items](#active-items) above. LEAN-GA, TRUST-2b, MCP remain in the [Externally-Blocked Parking Lot](#externally-blocked-parking-lot). Research items in [`docs/archive/research-track.md`](archive/research-track.md).

---

## Externally-Blocked Parking Lot

Items from the old v0.8.1 that depend on external availability. Tracked but not on the critical path.

| ID | Description | Trigger |
|-----|-------------|---------|
| **LEAN-GA** | Real Leanstral integration (non-mock proofs) → `verified-lean` evidence kind. **Experimental demo slice SHIPS (v0.14.8):** the opt-in `--leanstral` path translates a *faithfully-translatable* (nonlinear-arithmetic) obligation to a body-faithful Lean theorem, has `labs-leanstral-1-5` prove it, kernel-checks it with `lake env lean` + Mathlib, and records `verified-lean` (`DLVerifiedLean`, a peer of SMT `verified`) + a re-checkable `.lean` certificate — live-verified end-to-end (`examples/leanstral-demo/square.llmll`; see `CHANGELOG.md §v0.14.8`, [`docs/design/leanstral-demo-spec.md`](design/leanstral-demo-spec.md)). **Deferred remainder = the three-layer PRODUCTION rebuild:** (1) `LeanTranslate.hs` faithful across *all* escape classes (the demo covers only nonlinear `*`; `/`/`mod` still need `Int.fdiv`/`Int.fmod`, lists/inductive need the retry loop), (2) the full nonlinear/inductive worklist routing (the demo adds one targeted route, not the whole rework), (3) the retry-with-error loop + hash-revalidated Lean staleness. External availability partly cleared by Leanstral 1.5 (open weights + free API); see [`docs/design/leanstral-integration-scope.md`](design/leanstral-integration-scope.md) §8. | Production three-layer rebuild (demo slice shipped v0.14.8; external availability partly cleared) |
| **TRUST-2b** | `verified-lean` evidence kind. **Partially realized (v0.14.8):** the `DLVerifiedLean` display level ships as a peer of SMT `verified` (`Syntax.hs`), carrying a Lean-kernel-checked certificate; the original `VLProvenLean` constructor is superseded by this evidence-record model. Full realization (across all escape classes, per the trust-report/sidecar/proof-cache threading) follows LEAN-GA's production rebuild. | LEAN-GA |
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

> MOD-PBT-1, OBLIG-PBT-2/3/4, and F-033/F-034 (formerly tracked in this section) all shipped in the v0.10.x patch lane; their per-item provenance is retained in [Shipped Releases](#shipped-releases) and [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md).

**Trigger criteria:** v0.10 shipped, or any production use case requiring true namespace isolation.

---

## Future — WASM Sandboxing (unversioned)

**Theme:** Replace Docker with WASM-WASI as the primary sandbox.

> **Source:** [`docs/archive/wasm-investigations/wasm-poc-report.md`](archive/wasm-investigations/wasm-poc-report.md) — conditional GO (v0.3.2 assessment).
>
> **Decision (2026-04-21):** WASM is a confirmed future direction but not pinned to a release version. Docker + CAP-1 provide two functional enforcement layers (compile-time capability gating + OS-level container isolation). WASM adds a third layer (hardware-enforced capability boundary) and becomes a priority when there are real users running untrusted agent code in production. The v0.3.2 PoC confirmed feasibility; the `effectful` compatibility spike (v0.5) confirmed GO.

### WASM Build Target (~7 days)

| Phase | Work | Effort | Status |
|-------|------|--------|--------|
| Phase 0 | Install `ghc-wasm-meta` + `wasmtime`, manual compile of hangman | 1 day | ☐ |
| Phase 1 | `--target wasm` flag, generate `.cabal` file, invoke `wasm32-wasi-cabal` | 2–3 days | ☐ |
| Phase 2 | Strip check blocks for WASM, WASI capability import mapping | 2 days | ☐ |
| Phase 3 | CI integration, setup script, docs | 1 day | ☐ |

> [!WARNING]
> **`effectful` library compatibility with GHC WASM backend was untested at PoC time but cleared by the v0.5 spike.** The v0.3.2 PoC compiled `hangman_json_verifier` which doesn't use `effectful`. The v0.5 `effectful` WASM compatibility spike returned **GO** (no C shims, no linker errors) — see [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md) §v0.5.

**Acceptance criteria:**

- `llmll build --target wasm examples/hangman_sexp/hangman.llmll` produces a `.wasm` binary
- `wasmtime hangman.wasm` runs the game correctly
- WASI capability imports align with LLMLL capability declarations
- Typed effect rows (`effectful`) integrate with WASI enforcement

**Risk:** `ghc-wasm-meta` toolchain maintenance is low-bus-factor. If it falls behind GHC releases, this work slips without affecting anything else.

**Trigger criteria — when to schedule this:**

- Real users running untrusted agent code outside development environments
- Docker proving insufficient as a sandbox (capability granularity, startup latency, distribution)
- `effectful` WASM compatibility spike (v0.5) returned GO ✅

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
| **A** | **Theory of arrays** for `bytes[n]` / `map[k,v]` | QF theory of arrays (`select`/`store` + extensionality) — **decidable**, polite-combines with QF-LIA; **stays in `Σ_auto`** | array index-in-bounds (real memory-safety, not a length proxy); map get-after-put / key-presence | **Proposed — recommended first**; enabling purchase for the first honest data-structure example |
| **B** | **Dependent lengths** (`list[t]{len=n}`) + widened measure catalog | QF-LIA + EUF (+ arrays) — **decidable** | safe list indexing (bridge from "count a list" to "index a list") | **Proposed**; depends on Lever A; **overlaps R1** (dependent types, `Vect n a`, below) |
| **C** | **Inductive datatypes + induction** (recursive ADTs, measure unfolding, PLE / refinement reflection) | inductive datatype theory — **undecidable in general**; **leaves `Σ_auto`** → new weaker tier *or* route to the Lean tier | list / tree / stack structural invariants (sortedness, balance, acyclicity, use-after-free) | **Research frontier**; gated on **LEAN-GA** (`verified-lean` discharge) + **R7** (strict descent / termination) |

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
> [`docs/design/cascading-refinement-proposal.md`](design/cascading-refinement-proposal.md) (Rev 2);
> engineer feasibility in progress. **Not shipped.** The control- and data-side fragment-wideners ship the
> *bodies*; this ships the *decomposition* — the project's own stated differentiator
> (`docs/design/strategic-positioning.md:22`), currently only half-built.

| Layer | What | Status |
|---|---|---|
| **1 — substrate** | per-step verification = existing assume-guarantee (`cvPreObligation`/`cvPostAssumption`); no new fragment | reuse |
| **2 — protocol** | a `refine` op (dual of `patch`: install body + spawn sub-holes atomically), growing refinement-tree hole model, compare-and-swap resync | new — **R2/R8**-adjacent |
| **3 — contract quality** | spawn-time **CDP** vacuity gate + **feasibility** (no-miracle) gate + decomposition-trust **meet** (floored on contract-only cycle members) | new — extends **CDP** (`:224`) |
| **4 — reuse retrieval (REFINE-REUSE)** | spawn-time **reuse retrieval** (*not a gate — never rejects*): surface existing in-scope defs that *subsume* a spawned sub-contract (contract-implication `preₛ⇒pre_D ∧ post_D⇒postₛ`, α-normalized, not name/syntax). Advisory `reuse_suggestions` brief channel + non-blocking `W-REUSE` warning on an exact-equivalent; reuses **COMP-4(b)** subtyping-Horn (`:70`) | **SETTLED (Rev 1) — deferred; tracked for later implementation as the REFINE-REUSE ticket in the Open work lane above**; the open follow-on now that stages 1–3 shipped (v0.14.13); design [`refine-reuse-gate-proposal.md`](design/refine-reuse-gate-proposal.md) |

> **Acyclicity policy — DECIDED (Option 3):** `refine` admits a cycle-creating spawn, detects the cycle,
> and honestly degrades its members to contract-only (trust meet floored so nothing is laundered) — the
> `letrec` partial-correctness treatment (`LLMLL.md §5.3.5`). R7 strict-descent is the follow-up
> total-correctness upgrade. One open design question (per-contract vs composed gating). **Depends-on:**
> MATCH-WIDEN (shipped v0.14.12 — gives the cascade non-trivial verified leaves), R2 (self-hosted
> orchestrator), R8 (incremental re-verify). Standing rule: the `checkout` brief is the sole information
> channel to a hole-filling agent (no forced failures, no hints).

## Cross-Module Assume-Guarantee — SHIPPED v0.14.17

> Body-faithful verification across `import` boundaries. A function calling an **imported**
> contracted function now verifies body-faithful (assume-guarantee against the imported contract;
> the imported *body* is never re-verified) and stays `verified` under `--strict-verified-core`,
> instead of falling back to contract-only — the prerequisite for a *modular flagship*. Shipped by
> seeding the body-VC `ContractEnv` from the module cache (`emitFixpointWithCache`, dual-keyed bare
> + qualified, desugared against one merged alias map for cross-boundary ctor-tag coherence). The
> cross-module tier meet and the transitive imported-sidecar staleness check were already in place
> (XMOD-TIER, v0.10-era); this added only the body-VC side. Import cycles are a hard error, so the
> composition is acyclic (topological, no fixpoint argument). Design of record:
> [`cross-module-assume-guarantee-proposal.md`](design/cross-module-assume-guarantee-proposal.md)
> (Rev 1, settled + shipped); see [`CHANGELOG.md §v0.14.17`](../CHANGELOG.md).
>
> **Follow-ons (not blockers):** the refinement-aliased-param case (`xmod-alias`, edge case 5 —
> the alias map must also seed refinement aliases from imports) is a fail-closed completeness
> follow-on; cross-module ADT identity is nominal-by-name (inherited **MOD-5** limitation — the
> structural interface check remains unshipped).

## Research track (no v0.x targets, no Active Items rows)

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **Contract discriminative power formalization** | ~~Proposed by Professor / Research track~~ → **Promoted to v0.11 CDP-0** (LT-CDP, shipped v0.11) | See [Shipped Releases](#shipped-releases) v0.11 line; [`docs/archive/research-track.md`](archive/research-track.md) §6 is the archived source |
| **Full categorical unification** (fibrations / graded monads / patch-merge derivation) | **Declined** | Disproportionate per professor adjudication; amended critic did not re-propose. See [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) §5 |
| **Path B mechanized soundness theorem** | **Declined** | Inherited Path A stance from [`docs/design/verification-debate.md`](design/verification-debate.md) |

### Research track (migrated from `docs/research-track.md`, 2026-05-25)

> Per DOC-CONSOLIDATE M4, `docs/research-track.md` is archived to [`docs/archive/research-track.md`](archive/research-track.md) (frozen-historical). R1–R8 below are the live index; **R3 and R5 promoted to [Active Items](#active-items) (2026-06-23)**, R6 (CDP) shipped v0.11. The R1–R7 overlap audit (2026-05-25) found no R-item subsumed by an existing roadmap row.

| # | Item | Original promotion criterion | Cross-reference (per R1–R7 audit, 2026-05-25) | Archive source |
|---|------|------------------------------|------------------------------------------------|----------------|
| **R1** | **Indexed / Dependent Types** (`Vect n a`, GADTs, type-level arithmetic, bidirectional typechecking) | Design spec with typing rules, bidirectional migration plan, erasure strategy | Source design exploration: [`docs/design/type-driven-development.md`](design/type-driven-development.md) (partially promoted — obligation-guided part shipped in v0.10). Consistent with "What's NOT on this Roadmap" row Indexed/dependent types — Research track. | [`docs/archive/research-track.md §1`](archive/research-track.md) |
| **R2** | **Self-Hosted Orchestrator** (rewrite `llmll-orchestra` as LLMLL `def-main :mode cli`) | Agent accuracy ≥80% on auth module exercise when filling LLMLL-source holes | Source design draft: [`docs/design/agent-orchestration.md`](design/agent-orchestration.md) §Option B (Future Infrastructure category in INDEX). No competing roadmap row. | [`docs/archive/research-track.md §2`](archive/research-track.md) |
| **R3** | **Spec-from-RFC Pipeline** (RFC text → LLMLL contracts with clause provenance traceability) | ~~Concrete pipeline design doc with at least one worked example~~ → **Promoted to [Active Items](#active-items)** (2026-06-23): worked-example criterion met by `examples/totp_rfc6238/` + the TCP-793 demo + shipped `:source` provenance | [`docs/archive/research-track.md §3`](archive/research-track.md) |
| **R4** | **Synthetic Training Corpus** (Hackage back-translation; transpiler + spec lifting + benchmark) | Research proposal with measurable hypothesis and evaluation methodology | No competing roadmap row; independent. | [`docs/archive/research-track.md §4`](archive/research-track.md) |
| **R5** | **Differential Implementation Pressure** (`llmll checkout --multi`; N agents fill same `?delegate`; divergence analysis as new module `DivergenceCheck.hs`) | ~~Agent accuracy baseline established~~ → **Surfaced to [Active Items](#active-items)** (2026-06-23). Distinct from single-agent repair-loop and the `OBLIG-*` family. | [`docs/archive/research-track.md §5`](archive/research-track.md) |
| **R7** | **Call-Site Strict Descent** (`measure(args') < measure(args)` constraint at each recursive call site; independent of BODY-VC per consultant correction 2026-04-28) | Independent design spec for descent constraint generation | Complementary (not overlapping) with TERM-1 from [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) row 7: TERM-1 is documentation-side (partiality disclaimer); R7 is implementation-side (descent constraint emission). Sequence: TERM-1 ships first as honest-documentation-now; R7 is the eventual implementation that retires TERM-1's disclaimer. | [`docs/archive/research-track.md §7`](archive/research-track.md) |
| **R8** | **Incremental Patch Re-Verification** (dependency-slice re-verify for `llmll patch` instead of whole-module) | Design spec proving the slice is sound — that node-VC + fill-induced callee slice + staleness-recheck captures every obligation the whole-module re-verify emits — plus a demonstrated repair-loop latency pain point | Surfaced by language-team, 2026-07. Current behavior: `PatchApply.applyPatch` re-parses + typechecks + Fixpoint-emits the whole merged module on every patch (`PatchApply.hs:291-303`). The checkout brief already snapshots most of a sound slice's inputs — enclosing pre, path condition, callee `fePre`/`fePost` (`Checkout.hs:186-197`). Wall-clock basis: `experiments/cdp-perf-0/`. Distinct from CDP default-on. | New (no archive source) |

> **External Consultant Review (2026-04-28)** and **Impact Analysis (2026-05-01)** preserved in archive at [`docs/archive/research-track.md §§Impact-Analysis,External-Consultant-Review`](archive/research-track.md). Near-term recommendations 1–4 closed; items 5 (R5) and 6 (R3) remain open.

---

# Policy & Scope

## Feature Freeze Policy

> [!IMPORTANT]
> **Original freeze (v0.8.1a through v0.10) — concluded with v0.10.6 ship.** Preserved as historical record. The freeze constrained the project to narrowing the verification boundary and deepening the obligation-feedback architecture rather than expanding the language surface, on the rationale that each unverified feature is a semantic escape hatch. Source: Professor's five-round review (2026-04-30), extended 2026-05-01.

> [!IMPORTANT]
> **Freeze lifted for v0.11 (architectural correction).** The freeze-exception soundness argument: v0.11's core/shell grammar inversion *narrows* the verification surface by making the verified-core fragment syntactically canonical rather than reachable through a CLI flag; CDP-0 (contract discriminative power as first-class evidence axis) and predicate-carrying `?proof-required` are evidence-channel enrichments without new escape hatches; LT-INT (`int` = mathematical integer, `Integer` backend) closes the documented Z3-Int-vs-Haskell-Int64 misalignment rather than introducing a new surface. See [`docs/archive/shipped-design-specs/core-shell-inversion-direction.md`](archive/shipped-design-specs/core-shell-inversion-direction.md) §Background for the full rationale and the no-backward-compat-shim position (memo folded into the LT-INV proposal `## Background` and archived under M2 case 3); [`docs/design/critique-2026-05-23-triage.md`](design/critique-2026-05-23-triage.md) for the underlying external-critique adjudication.
>
> **Source:** Professor direction memo (2026-05-23) consolidating external critique (2026-05-23) into v0.11 routing; consensus of language team and professor. Original freeze (v0.8.1a–v0.10) preserved above as historical record.

---

## What's NOT on this Roadmap (and why)

| Item | Reason |
|------|--------|
| Rust codegen backend | Dropped in v0.1.2; Haskell is the permanent target |
| Python FFI tier | Breaks WASM compatibility; dynamically typed |
| Full Lean 4 proof agent from scratch | Replaced by Leanstral MCP integration |
| UI/web frontend | LLMLL's target domains are backend, not UI |
| IDE plugins (VS Code, etc.) | Premature — stabilize the CLI/HTTP interface first |
| Lean integration | Externally blocked (parking lot) |
| Indexed/dependent types | Research track — explicitly excluded from v0.10 (professor consensus, 2026-05-01) |

> The freeze-era "feature freeze" exclusions (new builtins, new syntax constructs, broader FFI, more WASI surface, compiler-side orchestration, typeclass law machinery) were enforced through v0.10 and are no longer blanket-excluded post-freeze; any addition still requires explicit team consensus with a written soundness argument per the [Feature Freeze Policy](#feature-freeze-policy) freeze-exception discipline.

---

# History

## Shipped Releases

> Compact summary, newest-first. One line per version: headline — ship date — test count — link to the detailed implementation section in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md). Canonical release narrative is [`../CHANGELOG.md`](../CHANGELOG.md). This `#shipped-releases` anchor is stable and is the entry point other docs link to.

| Version | Headline | Date | Tests | Detail |
|---------|----------|------|-------|--------|
| **v0.14.17** | Body-faithful cross-module assume-guarantee (XMOD-AG) — a caller of an `import`-ed contracted function verifies body-faithful (assume-guarantee against the imported contract; the imported body is never re-verified) instead of falling back to contract-only, so a program can be split into `import`-linked modules and stay `verified` under `--strict-verified-core`. Body-VC `ContractEnv` seeded from the module cache (`emitFixpointWithCache`, dual-keyed bare + qualified; imported contracts desugared against one merged local-wins alias map so nullary-ctor tags stay coherent across the boundary — retires dead `buildContractEnvWithImports`). The cross-module tier meet + transitive imported-sidecar staleness were already in place (XMOD-TIER, v0.10-era); this adds only the body-VC side. MOD-5 nominal ADT identity inherited (unshipped structural check); `xmod-alias` refinement-param case a fail-closed follow-on; no schema change | 2026-07-08 | 1084 H + 45 Py | `CHANGELOG.md §v0.14.17` |
| **v0.14.16** | Implication sugar `=>` / `<=>` — symbolic binary `bool → bool → bool` implication and biconditional, desugared at VC emission to the `or`/`not` form (byte-identical `.fq`, zero verification change); first-class in both S-expr and JSON-AST surfaces with round-trip preservation; schema op enum extended additively, `schemaVersion` stays 0.7.0 | 2026-07-07 | 1073 H + 45 Py | `CHANGELOG.md §v0.14.16` |
| **v0.14.15** | Fix: `(not b)` / any `not` on a `bool` value in a body/return position no longer crashes liquid-fixpoint (a v0.14.14 regression — `not` is predicate-only in the fixpoint grammar); `emitPred` rewrites `X = ¬Y` to `X ≠ Y`, qualifier params carry real sorts; `not`-value bodies and two-bool-variable equality now verify body-faithful | 2026-07-07 | 1073 H + 45 Py | `CHANGELOG.md §v0.14.15` |
| **v0.14.14** | `bool` admitted to the body-faithful fragment `Σ_auto` — a `bool` param / result / refinement atom / `if`-condition now verifies body-faithful instead of dropping to contract-only (`isScalarLike = isIntLike ∨ isBoolLike` at the sort-env sites); the `FQBool` / `emitSort` / `typeToSort TBool` infrastructure already existed | 2026-07-07 | 1071 H + 45 Py | `CHANGELOG.md §v0.14.14` |
| **v0.14.13** | Cascading `refine` op + CDP vacuity gate; cycle-verification spec reconciliation — `refine` installs a hole body and spawns contracted sub-holes atomically (emergent decomposition); a spawn-time CDP vacuity gate rejects a trivially-satisfiable sub-contract; the `letrec` / `def-shell` cycle partial-correctness treatment reconciled with the spec | 2026-07-06 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.13` |
| **v0.14.12** | MATCH-WIDEN — mixed nullary/payload two-arm sums, **nested** matches, and **scrutinee-constructor** postconditions now verify body-faithful. The arm discriminant changed from a free boolean guard to a free int-tag equality `(= <scrut>$tag k)` + range fact — a *conservative extension* (every existing sum-match verdict unchanged; stays QF-LIA, no datatype testers) — with a `desugarScrutCtor` pass rewriting `sig = Continue` → `sig$tag = k`, arm-declaration tags threaded so reordered arms don't false-refute, and a constructor post over an un-matched scrutinee falling back (no solver crash). Enables the flagship goto-fail (CVE-2014-1266) verification pipeline as **one body-faithful function** with real `Step`/`Verdict` sum types (`examples/gotofail/`). Remaining: sequential matches (two top-level matches in one body) still fall back — a self-contained follow-on; no schema change | 2026-07-06 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.12` |
| **v0.14.11** | Body-VC A-normalization — new `aNormalizeBody` pass lifts contracted calls out of argument / pair-component / if-condition positions into fresh `let` bindings before `bodyToPredM`, so nested/argument-position calls verify (`post: verified`) instead of silently falling back to `asserted` (or erroring under `--strict-verified-core`); identity on call-free-argument expressions (no perturbation of already-verified functions); DEMO-COMP §10 withdraw-twice fixture now surfaces its two call-pre origins; unblocks natural agent-written multi-function code for the flagship (`docs/design/flagship-secure-channel-proposal.md`); no schema/`trust_report_version` change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.11` |
| **v0.14.10** | R5 concurrency-safe `diverge-report` — per-fill classification writes its fixpoint query to a unique `openTempFile` path instead of a fixed `/tmp/llmll-diverge-<fname>.fq`, closing a race when concurrent `diverge-report` processes classify a fill for the same function name (surfaced by the R5-at-scale campaign running cells in parallel; validated via the harness — 10 holes × 4 repeats × concurrency 6 → 100% stable); no schema/`trust_report_version` change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.10` |
| **v0.14.9** | R5 sibling-call classification fix (`diverge-report`) — per-fill classification now verifies each fill in the **shared program's context** (hole-fn body substituted, sibling defs kept + pinned to the trusted shared definitions, property `check`s dropped) instead of isolated synthetic emission, so a `def-shell` fill calling a verified sibling helper verifies its post **modularly** through the call rather than being dropped as `type-error`. Closes the witness-suppression false-negative channel (proposal Rev 4 / findings Case 5): the negative branch now has one false-negative channel (common-mode) not two. Strict-`def` sibling calls stay `type-error` (conservative residual, no leaf-verification pre-pass). Makes helper-composing corpora usable with R5; re-validated end-to-end (`(maxi x lo)` vs `lo` → `under-constraint-witness`); no schema/`trust_report_version` change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.9` |
| **v0.14.8** | Experimental Leanstral `verified-lean` demo slice (**demo-only**) — opt-in `--leanstral` translates a faithfully-translatable nonlinear-arithmetic obligation to a body-faithful Lean 4 theorem, has `labs-leanstral-1-5` prove it, kernel-checks it with `lake env lean` + Mathlib, and records the new `verified-lean` tier (`DLVerifiedLean`, a peer of SMT `verified`) + a re-checkable `.lean` certificate threaded through the trust report / `.verified.json` sidecar / proof cache; needs `LLMLL_LEANSTRAL_API_KEY` + a local Lean 4 + Mathlib project (fails closed otherwise); the three-layer PRODUCTION `LEAN-GA` rebuild remains deferred; no schema/`trust_report_version` change | 2026-07-05 | 1064 H + 45 Py | `CHANGELOG.md §v0.14.8` |
| **v0.14.7** | R5 differential-implementation-pressure (observational stages 1-2) — `checkout --multi N` fills one hole with N agents and `diverge-report` classifies observational divergence over a probe set Ω among the fills that all verify as an `under-constraint-witness` (the *contract*, not either implementation, is under-specified), `no-divergence-observed` on agreement, or `suppressed-intentional`; plus the anti-laundering guard — new `MCPClient.sanitizeProof` chokepoint rejects an empty / `sorry` / `admit` proof term (word-boundary aware) so a degenerate proof cannot launder a proof hole to a verified tier (PROOF-ARTIFACT §4.1 LCF invariant); no schema/`trust_report_version` change | 2026-07-04 | 1040 H + 45 Py | `CHANGELOG.md §v0.14.7` |
| **v0.14.6** | Zero-install Docker image — slim (~229 MB) verify-capable `ghcr.io/machunter/llmll` (bundles `llmll` + `fixpoint` + `z3` + demos; `Dockerfile` two-stage `haskell:9.6.6` → `debian:bookworm-slim`) so a no-toolchain user can `docker run … llmll verify` and see the SMT refutation; `docker-publish.yml` pushes on a `vX.Y.Z` tag (gated on `version_gate.sh` + tag==banner); off-roadmap adoption work, no `compiler/src`/schema change | 2026-07-03 | 1024 H + 45 Py | `CHANGELOG.md §v0.14.6` |
| **v0.14.5** | Trust-report `over-annotation-warning` JSON gap — the module-level self-attestation guardrail (CDP proposal §10 Risk #3) was computed correctly but unreachable via any `--json` output at any ratio, found by the new `experiments/adv-spec-weaken-0/` adversarial benchmark; new top-level `over_annotation` object in `--trust-report --json`; no schema/`trust_report_version` change | 2026-07-03 | 1024 H + 45 Py | `CHANGELOG.md §v0.14.5` |
| **v0.14.4** | CDP spec-entropy suppression fix — `(spec-entropy :intentional \| :unknown)` now actually suppresses `identity-satisfies-post`/`const-satisfies-post` (inert since v0.11); new `--strict-verify` flag bundles the recommended serious-verify path; closes CDP default-on precondition (c); no schema change | 2026-07-02 | 1019 H + 45 Py | `CHANGELOG.md §v0.14.4` |
| **v0.14.3** | 15-bug pass surfaced by a full documentation + examples audit — parser (`get-bytes`, `def-invariant` S-expr, occurs-check false positive), codegen (`def-main` uncompilable + precondition/postcondition dead-under-laziness + underscore-filename Cabal bug), trust-report/JSON (`pre_source`/`post_source` threading, UTF-8 double-encoding, doubled `@`), CLI (`llmll replay` non-functional, `hub fetch` path bug), orchestrator (checkout-TTL key mismatch, dead context-enrichment); plus fixture-level fixes across `examples/` (see `CHANGELOG.md §v0.14.3`'s Examples section for per-fixture coverage notes); no schema change | 2026-07-02 | 1014 H + 45 Py | `CHANGELOG.md §v0.14.3` |
| **v0.14.2** | CDP deep-dive — candidate basis emits real `ok`/`err` (not raw internal names); `erBodyFallback` body-faithfulness gate closes a broader unvalidated-candidate class; `--strict-verified-core --trust-report --cdp --json` now actually populates `discriminative_axis`; `spec-inconsistent` → `spec-inconsistent-or-unproven` (claim-accuracy rename); no schema change | 2026-07-01 | 978 H + 62 Py | `CHANGELOG.md §v0.14.2` |
| **v0.14.1** | Checkout-lock sum-type fix — a sum-type `TypeDefEntry` now round-trips through the checkout lock (fixes `patch` rejecting valid tokens for any program with a `data`/sum type in scope); `withdraw-demo` integrates `withdraw-outcome` as a third fillable hole | 2026-06-30 | 966 H + 62 Py | `CHANGELOG.md §v0.14.1` |
| **v0.14.0** | PROOF-ARTIFACT (staged MVP) — `verify --proof-artifact` emits a unified, replayable verification record; `replay-artifact` re-derives it fail-closed; §4.1 LCF anti-laundering invariant enforced on emit and parse; `unsat_core` deferred | 2026-06-30 | 965 H + 62 Py | `CHANGELOG.md §v0.14.0` |
| **v0.13.14** | datatype-tail — admissibility recurses over the acyclic composition, so pair-of-`Result` components and nested/composed-datatype payloads verify; the only remaining boundary is `list`-carrier + recursive payloads (a deliberate firewall). Completes the PAIR-RET line. No schema change | 2026-06-29 | 961 H + 62 Py | `CHANGELOG.md §v0.13.14` |
| **v0.13.13** | COMP-4-RESULT — `(ok e)`/`(err e)` construction is body-faithful (`Result` promoted to the polymorphic `data Result 2`), closing the COMP-4 (a) construction drift. No schema change | 2026-06-29 | 958 H + 62 Py | `CHANGELOG.md §v0.13.13` |
| **v0.13.12** | PAIR-RET-2 — pair components extended to nested / list / admissible sum-or-ADT (`(int, Box)` → `(Pair2 int Box)`, alias-aware `typeToSortA`); a recursive-sum component falls back cleanly via the §5.3.3 firewall (previously crashed the solver). No schema change | 2026-06-29 | 952 H + 62 Py | `CHANGELOG.md §v0.13.12` |
| **v0.13.11** | PAIR-RET — refinement predicates over pair/tuple returns: `first`/`second` reflect to datatype selectors and `(pair a b)` to the constructor (polymorphic `data Pair2 2`), so a post like `(= (+ (first r) (second r)) k)` discharges (`verified`/`refuted`) instead of `asserted`; unblocks two-account conservation (`examples/payments-core/conserve.llmll`). No schema change | 2026-06-29 | 946 H + 62 Py | `CHANGELOG.md §v0.13.11` |
| **v0.13.10** | COMP-4 polish — nullary-variant construction `(Empty)` types as its sum (typecheck fix); tcp_rfc793/session-pay reshaped to real outcome sums (int sentinel dropped, full totality posts); LLMLL.md verification matrix reconciled to the shipped sum-type surface (`Σ_auto` + acyclic datatype theory). No schema change | 2026-06-28 | 939 H + 62 Py | `CHANGELOG.md §v0.13.10` |
| **v0.13.9** | COMP-4 (a)/(c): native datatype construction — a constructor application over an admissible two-arm sum reflects into a native FQData term (result binds at the datatype sort); construction + payload-carrying totality posts discharge by constructor equality, refute by injectivity. Provenance-partitioned (nullary→int-tag, opaque→skolem, constructed→FQData); recursive datatypes firewalled. First verification beyond pure QF-LIA (+ SMT datatype theory). Completes the COMP-4 line. New `examples/outcome-totality/`; no schema change | 2026-06-28 | 938 H + 62 Py | `CHANGELOG.md §v0.13.9` |
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

> Detailed per-item implementation history (IDs, acceptance criteria, commit SHAs, design-doc links, the historical v0.8–v0.10 critical-path ASCII diagram, the "What Changed from LLMLL.md §14" table, and the "Items Removed from Scope" table) lives in [`docs/archive/roadmap-shipped-history.md`](archive/roadmap-shipped-history.md). Current shipped version is the top row of this table — canonical source is [`../CHANGELOG.md § Latest`](../CHANGELOG.md#Latest), per this doc's own no-version-stamp policy above.

---

## Resolved cross-cutting items

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

> **Known gap (XMOD-COMP — tracked, NOT shipped):** cross-module *verified composition* is a five-layer gap — layers 1–3 fixed in v0.13.0 (admission/type-alias/tier-edge), layers 4–5 open (the caller's body-VC emission `ContractEnv` lacks the imported callee's contract; `consumed_guarantees.callee_tier` shares the bare/qualified miss). Recommended as one dedicated effort gated by a binary-level end-to-end test; see [`docs/design/cross-module-composition-finding.md`](design/cross-module-composition-finding.md). (This is downstream of the v0.13.0 ship; raise into Active Items if scheduled.)
