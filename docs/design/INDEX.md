# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-06-23  
> **Purpose:** Index and orientation for all active design documents.

This directory contains design discussions, proposals, and reviews that inform the LLMLL language and system architecture. These are **living documents** — not specifications. The authoritative spec is [`LLMLL.md`](../../LLMLL.md); the engineering backlog is [`compiler-team-roadmap.md`](../compiler-team-roadmap.md).

Per **DOC-CONSOLIDATE M6** (settled 2026-05-24, shipped at `1a8733f`), entries below are one-liners: title, 8–12-word hook, status label. Full descriptions live in each proposal's own frontmatter and body. See [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) for the canonical-sources contract. Settled-and-shipped proposals are folded and moved to [`../archive/`](../archive/) — see **Archived Material** below.

---

## Verification & Soundness

| Document | Summary | Status |
|---|---|---|
| [oblig-0-spec.md](oblig-0-spec.md) | Obligation report schema; three channels; EMatch branch obligations; benchmark suite | **Approved (Rev 8)** — residual obligation work open |
| [verification-debate.md](verification-debate.md) | Formal-methods critique; "sound modulo trust" framing | Active reference |
| [specification-sources.md](specification-sources.md) | Five sources of good specs: standards, back-translation, refinement, hub, synthesis | Active reference |
| [strategic-positioning.md](strategic-positioning.md) | What's genuinely novel vs borrowed; positioning guardrails | Active reference |
| [oblig-pbt-3-proposal.md](oblig-pbt-3-proposal.md) | PBT-to-trust-report write-back; per-clause tier profiles | **Settled (Rev 2)** — awaiting engineer (review folded) |
| [proof-artifact-proposal.md](proof-artifact-proposal.md) | PROOF-ARTIFACT: unified reproducible verification artifact (trust/obligation/`.fq`/sidecar) | **Proposed (Rev 2)** — review folded ([proof-artifact-review.md](proof-artifact-review.md)); awaiting settlement |
| [comp-4-payload-sums-proposal.md](comp-4-payload-sums-proposal.md) | COMP-4 payload-bearing sum types: refined elimination, construction, totality | **Shipped — all slices** (d-elim/b/a/c, v0.13.7–v0.13.9); COMP-4 line complete |
| [cross-module-composition-finding.md](cross-module-composition-finding.md) | XMOD-COMP: cross-module verified composition is a 5-layer gap; same-module works | **Finding — partially fixed** — body-VC-emission + callee_tier open |
| [critique-2026-05-23-triage.md](critique-2026-05-23-triage.md) | 2026-05-23 external-critique triage; four-turn convergence; 17 routing items | **Settled** — routing in progress |
| [int-3-machine-int-sketch.md](int-3-machine-int-sketch.md) | INT-3 contingency: `machine-int` QF-BV alias; dormant unless INT-PRE escalates | **Contingency (Rev 0)** — dormant |

---

## Invariant Discovery

| Document | Summary | Status |
|---|---|---|
| [invariant-discovery-proposal.md](invariant-discovery-proposal.md) | Nine ranked mechanisms; specification pressure and contract entropy concepts | Active reference (review folded as Appendix per M2) |

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

Historical design documents from shipped or superseded sources are in [`../archive/`](../archive/). Settled-and-shipped proposals are folded (professor reviews → `## Appendix`) and moved here; version lineage lives in [`../compiler-team-roadmap.md`](../compiler-team-roadmap.md) `## Shipped Releases` and [`../../CHANGELOG.md`](../../CHANGELOG.md).

| Directory / file | Contents | Origin |
|---|---|---|
| `shipped-design-specs/` | Shipped/superseded design specs. v0.6.2–v0.9.0: BODY-VC-0, EVID-0, COMP-0, interface-laws, spec-adequacy-closure, agent-prompt-semantics-gap, Algorithm W resolution, contract-clause-refactor, invariant-discovery (base), verification-debate-action-items, proof-required-predicate-carrier (+proposal), lead-agent, core-shell-inversion-direction. v0.11–v0.13 settled/shipped: REF-META 1–5, Bundle B0 (+cross-module addendum), DEF-RET (def-return-annotation), ADMIT-VERIFIED, TRUST-PRE (precondition-tier), CDP (contract-discriminative-power), LT-INV (core-shell-inversion), INT-2 (boundary-shims), positioning-constraint-decay, v0.11-rollback-discipline, verified-contract-refuted-status, verify-reporting-defects (VERIFY-RPT-1), v0.12-direction memo, compositional-trust-closure (DEMO-COMP — **superseded**: §10 realized by `examples/payments-core/`, DEFECT-1 resolved by TRUST-PRE) | v0.6.2–v0.13 (shipped or superseded) |
| `professor-reviews/` | Standalone reviews folded into proposal appendices: `oblig-pbt-3-review`, `invariant-discovery-review`, `contract-discriminative-power-review`, `core-shell-inversion-review`, `positioning-constraint-decay-review`, `refinement-metatheory-of-record-review`, `proof-required-predicate-carrier-review`, `def-ret-staleness-hash-review` | Post-DOC-CONSOLIDATE M2 |
| `wasm-investigations/` | `effectful-wasm-spike.md`, `wasm-poc-report.md` | Pre-roadmap-reorganization |
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped) |
| `older_discussions_and_plans/` | `SMT_Lean_Analysis.md`, `unicode_decision.md` | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `research-track.md` (file) | Original research-track doc, **frozen-historical**; live items are R1–R7 in `compiler-team-roadmap.md` | Post-DOC-CONSOLIDATE M4 |
| `roadmap-shipped-history.md` (file) | Detailed per-version shipped history (v0.1.2 → v0.12) split out of `compiler-team-roadmap.md`; live roadmap keeps a compact `## Shipped Releases` summary | Post-DOC-CONSOLIDATE M5 (2026-06-21) |
