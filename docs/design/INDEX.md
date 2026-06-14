# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-06-06  
> **Purpose:** Index and orientation for all active design documents.

This directory contains design discussions, proposals, and reviews that inform the LLMLL language and system architecture. These are **living documents** — not specifications. The authoritative spec is [`LLMLL.md`](../../LLMLL.md); the engineering backlog is [`compiler-team-roadmap.md`](../compiler-team-roadmap.md).

Per **DOC-CONSOLIDATE M6** (settled 2026-05-24, shipped at `1a8733f`), entries below are one-liners: title, 8–12-word hook, status label. Full descriptions live in each proposal's own frontmatter and body. See [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) for the canonical-sources contract.

---

## Verification & Soundness

| Document | Summary | Status |
|---|---|---|
| [oblig-0-spec.md](oblig-0-spec.md) | Obligation report schema; three channels; EMatch branch obligations; benchmark suite | **Approved (Rev 8)** — OBLIG-1/MOD-1 unblocked |
| [verification-debate.md](verification-debate.md) | Formal-methods critique; "sound modulo trust" framing established | Active reference |
| [specification-sources.md](specification-sources.md) | Five sources of good specs: standards, back-translation, refinement, hub, synthesis | Active reference |
| [strategic-positioning.md](strategic-positioning.md) | What's genuinely novel vs borrowed; positioning guardrails | Active reference |
| [oblig-pbt-3-proposal.md](oblig-pbt-3-proposal.md) | PBT-to-trust-report write-back; singleton-head linkage; per-clause tier profiles | **Settled (Rev 2)** — awaiting engineer (professor review folded as Appendix) |
| [core-shell-inversion-direction.md](../archive/shipped-design-specs/core-shell-inversion-direction.md) | v0.11 direction memo: grammar inversion, CDP-0, predicate-carrying `?proof-required` | **Folded & archived (v0.11)** — direction folded into LT-INV proposal `## Background`; memo archived to `shipped-design-specs/` |
| [v0.12-direction.md](v0.12-direction.md) | v0.12 direction memo: REF-META-2..5, Bundle B, refinement-aliased non-int widening | **Direction memo (Rev 1)** — v0.12 planning |
| [critique-2026-05-23-triage.md](critique-2026-05-23-triage.md) | 2026-05-23 external-critique triage; four-turn convergence; 17 routing items | **Settled** — routing in progress |
| [core-shell-inversion-proposal.md](core-shell-inversion-proposal.md) | LT-INV: invert source grammar; `def` strict-core; `def-shell` permissive marked | **Settled (Rev 4)** — def-logic removed in v0.12 (no auto-rewrite); Rev 3: §8 gate PASS definitive (EL-5, PM-006, 2026-05-30) |
| [contract-discriminative-power-proposal.md](contract-discriminative-power-proposal.md) | LT-CDP: contract DP as v0.11 first-class evidence axis; two-axis assurance | **Settled (Rev 5)** — CE follow-up complete (commit `3af3c06`); §8 Outcome 0 recorded; LLMLL.md §4.4.6 updated (CDPScopeCoreOnly, 2026-05-29) |
| [proof-required-predicate-carrier-proposal.md](../archive/shipped-design-specs/proof-required-predicate-carrier-proposal.md) | LT-PPR: predicate-carrying `?proof-required`; def-shell only; runtime-assertion fallback | **Shipped & archived (v0.11)** — engineer build `3391713`; archived to `shipped-design-specs/` |
| [refinement-metatheory-of-record-proposal.md](refinement-metatheory-of-record-proposal.md) | REF-META-1: checking-mode-only metatheory; explicit non-goals; tier-aware soundness | **Settled (Rev 2)** — promoted to `LLMLL.md §3.4/§5` (doc-lead pass, 2026-05-27) |
| [ref-meta-2-solver-completeness-proposal.md](ref-meta-2-solver-completeness-proposal.md) | REF-META-2: auto-discharge boundary Σ_auto ⊊ Σ_ref; solver-completeness statement | **Settled (Rev 2)** — promoted to `LLMLL.md §5.3.3` (doc-lead pass, 2026-06-12) |
| [ref-meta-3-predicate-wf-proposal.md](ref-meta-3-predicate-wf-proposal.md) | REF-META-3: predicate well-formedness rule; Σ_ref catalog; measure discipline M1–M4 | **Settled (Rev 2)** — promoted to `LLMLL.md §3.4.4` (doc-lead pass, 2026-06-12) |
| [ref-meta-4-erasure-proposal.md](ref-meta-4-erasure-proposal.md) | REF-META-4: erasure theorem; phase-distinction + construction-side discipline; Σ_auto scope | **Settled (Rev 3)** — promoted to `LLMLL.md §3.4.5` (doc-lead pass, 2026-06-13) |
| [ref-meta-5-type-assignment-proposal.md](ref-meta-5-type-assignment-proposal.md) | REF-META-5: type-assignment judgment (local type inference) + hole-directed checking; completes 1–5 | **Settled (Rev 2)** — promoted to `LLMLL.md §3.4.6` (doc-lead pass, 2026-06-14) |
| [v0.11-cross-proposal-rollback-discipline.md](v0.11-cross-proposal-rollback-discipline.md) | v0.11 cross-proposal rollback discipline: three outcomes; LT-CDP/LT-PPR shipping conditions | **Settled (Rev 1)** — coordination artifact |
| [int-2-boundary-shims.md](int-2-boundary-shims.md) | LT-INT/INT-2: fifteen `Int`-touching preamble entries classified A/B/C | **Settled (Rev 4)** — §8/§4 reconciliation confirmed; `range-idx` deferred rationale recorded |
| [int-3-machine-int-sketch.md](int-3-machine-int-sketch.md) | INT-3 contingency: `machine-int` QF-BV alias; dormant unless INT-PRE escalates | **Contingency (Rev 0)** — dormant |
| [positioning-constraint-decay-proposal.md](positioning-constraint-decay-proposal.md) | Dente et al. (2026) external anchor; spec-source primary, mechanisms secondary; bounded-iteration framing | **Settled (Rev 1)** — promoted into 3 design docs; paper verified 2026-05-25 with two minor corrections applied |
| [verify-reporting-defects-2026-06-04-bug.md](verify-reporting-defects-2026-06-04-bug.md) | Three verify-path reporting defects: fail-open on UNSAFE; `--trust-report` cannot show `verified` | **Resolved** — VERIFY-RPT-1 shipped (`b914587`) |
| [verified-contract-refuted-status-proposal.md](verified-contract-refuted-status-proposal.md) | Solver-SAFE conjunct on `verified`/strict-core; `refuted` as orthogonal trust status | **Settled (Rev 2) → Shipped** (`b914587`); promoted to LLMLL.md §3.4.3/§5.3.4/§4.4/§5.3.5 |

---

## Invariant Discovery

| Document | Summary | Status |
|---|---|---|
| [invariant-discovery-proposal.md](invariant-discovery-proposal.md) | Nine ranked mechanisms; specification pressure and contract entropy concepts | Active reference (professor review folded as Appendix per M2) |

---

## Future Infrastructure

| Document | Summary | Status |
|---|---|---|
| [agent-orchestration.md](agent-orchestration.md) | Orchestrator design: agent registry, context, scheduling, self-hosted endgame | **Dormant** — R2 source |
| [component-hub.md](component-hub.md) | Per-project + global component registry; query by type signature and contract | **Dormant** — future discussion retained |
| [language-comparison-experiments.md](language-comparison-experiments.md) | Cross-language benchmark: correctness vs assurance on independent axes | Design note |
| [type-driven-development.md](type-driven-development.md) | Indexed types (`Vect n a`, GADTs, type-level arithmetic); obligation part promoted | **Dormant** — partially promoted, R1 residual |

---

## Documentation & Process

| Document | Summary | Status |
|---|---|---|
| [doc-consolidation-2026-05-24-proposal.md](doc-consolidation-2026-05-24-proposal.md) | DOC-CONSOLIDATE: P1, M1–M6, D1, per-role SOPs; eliminates three-source status drift | **Shipped at `1a8733f`** — M6 landed; R1–R7 audit settled at `e6eb4b6` |

---

## Archived Material

Historical design documents from shipped or superseded sources are in [`../archive/`](../archive/):

| Directory / file | Contents | Origin |
|---|---|---|
| `shipped-design-specs/` | BODY-VC-0, EVID-0, COMP-0, interface-laws, spec-adequacy-closure, agent-prompt-semantics-gap, Algorithm W resolution, contract-clause-refactor, invariant-discovery (base), verification-debate-action-items, `proof-required-predicate-carrier.md` (superseded seed), `lead-agent.md` (v0.4 Lead Agent design, shipped) | v0.6.2–v0.9.0 (shipped or superseded) |
| `professor-reviews/` | Standalone professor reviews folded into proposal appendices: `oblig-pbt-3-review.md`, `invariant-discovery-review.md` | Post-DOC-CONSOLIDATE M2 |
| `wasm-investigations/` | `effectful-wasm-spike.md`, `wasm-poc-report.md` | Pre-roadmap-reorganization |
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped) |
| `older_discussions_and_plans/` | SMT/Lean analysis, language analysis, feedback, unicode decision | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `v0.3-plan/` | Delegate lifecycle, stratified verification briefs | v0.3 (shipped) |
| `v0.3.1-plan/` | Compiler + professor implementation plans | v0.3.1 (shipped) |
| `research-track.md` (file) | Original research-track doc; R1–R7 migrated into roadmap research-track section | Post-DOC-CONSOLIDATE M4 |
