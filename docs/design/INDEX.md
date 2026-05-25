# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-05-25  
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
| [core-shell-inversion-direction.md](core-shell-inversion-direction.md) | v0.11 direction memo: grammar inversion, CDP-0, predicate-carrying `?proof-required` | **Direction memo (Rev 2)** — awaiting LT proposals |
| [critique-2026-05-23-triage.md](critique-2026-05-23-triage.md) | 2026-05-23 external-critique triage; four-turn convergence; 17 routing items | **Settled** — routing in progress |
| [core-shell-inversion-proposal.md](core-shell-inversion-proposal.md) | LT-INV: invert source grammar; `def` strict-core; `def-shell` permissive marked | **Settled (Rev 1)** — pending professor review |
| [contract-discriminative-power-proposal.md](contract-discriminative-power-proposal.md) | LT-CDP: contract DP as v0.11 first-class evidence axis; two-axis assurance | **Settled (Rev 1)** — pending professor review |
| [proof-required-predicate-carrier-proposal.md](proof-required-predicate-carrier-proposal.md) | LT-PPR: predicate-carrying `?proof-required`; def-shell only; runtime-assertion fallback | **Settled (Rev 1)** — pending professor review |
| [refinement-metatheory-of-record-proposal.md](refinement-metatheory-of-record-proposal.md) | REF-META-1: checking-mode-only metatheory; explicit non-goals; tier-aware soundness | **Settled (Rev 1)** — pending professor review |
| [int-2-boundary-shims.md](int-2-boundary-shims.md) | LT-INT/INT-2: fifteen `Int`-touching preamble entries classified A/B/C | **Settled (Rev 1)** — awaiting INT-PRE adjudication |
| [int-3-machine-int-sketch.md](int-3-machine-int-sketch.md) | INT-3 contingency: `machine-int` QF-BV alias; dormant unless INT-PRE escalates | **Contingency (Rev 0)** — dormant |

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
