# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-07-11  
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
| [critique-2026-05-23-triage.md](critique-2026-05-23-triage.md) | 2026-05-23 external-critique triage; four-turn convergence; 17 routing items | **Settled** — routing in progress |
| [int-3-machine-int-sketch.md](int-3-machine-int-sketch.md) | INT-3 contingency: `machine-int` QF-BV alias; dormant unless INT-PRE escalates | **Contingency (Rev 0)** — dormant |
| [data-scope-extension.md](data-scope-extension.md) | Didactic multi-post: the data verification boundary (`Σ_auto`) and the array/dependent-length/induction extension levers | **Design / roadmap** — reconciled to shipped state (`75778b2`): Posts 1–5 (decidable core) + Lever A (arrays, shipped `LLMLL.md §5.3.3`) current; Levers B/C forward-looking |
| [contract-position-reads-disposition.md](contract-position-reads-disposition.md) | Contract reads are total selects — sound both directions (verified can't be silently unsound, refuted can't contradict a runtime-satisfiable contract); scoped lint routed (CONTRACT-READ-LINT) | Settled — 2026-07-12 |
| [strict-sibling-disposition.md](strict-sibling-disposition.md) | Strict-core bottom-up staging is the design; same-run admission declined + scoped with a reopening trigger | Settled — 2026-07-12 |
| [cascading-refinement-proposal.md](cascading-refinement-proposal.md) | Agent-driven recursive hole decomposition: `refine` op + growing tree + CDP/feasibility gates + Option-3 cycles | **Rev 5 — Stages 1–3 SHIPPED v0.14.13, Stage-4 REFINE-REUSE SHIPPED v0.14.29, feasibility (no-miracle) gate SHIPPED v0.14.52, decomposition-trust meet SHIPPED v0.14.53 — line complete**; Option-3 cycles reconciled to REC-PARTIAL-MARK's `termination_unverified` marker (2026-07-10) |
| [spec-from-rfc-pipeline.md](spec-from-rfc-pipeline.md) | R3 pipeline: RFC clauses → classified, `:source`-traced, adequacy-checked contracts | **Rev 1** — §4 evaluation executed (RFC 1982, all six criteria pass; G1+G4 closed; F-1982-3/-4/-5 folded); remaining gaps = G2 (deferred schema delta), G3 (accepted) |
| [leanstral-integration-scope.md](leanstral-integration-scope.md) | Leanstral/Lean-tier scoping: anti-laundering guard, C-property, three-layer LEAN-GA rebuild | **Parked (LEAN-GA)** — demo subset shipped v0.14.8; production rebuild deferred, cited by the roadmap parking lot |

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

## Archived Material

Historical design documents from shipped or superseded sources are in [`../archive/`](../archive/). Settled-and-shipped proposals are folded (professor reviews → `## Appendix`) and moved here; version lineage lives in [`../compiler-team-roadmap.md`](../compiler-team-roadmap.md) `## Shipped Releases` and [`../../CHANGELOG.md`](../../CHANGELOG.md).

| Directory / file | Contents | Origin |
|---|---|---|
| `shipped-design-specs/` | Shipped/superseded design specs. v0.6.2–v0.9.0: BODY-VC-0, EVID-0, COMP-0, interface-laws, spec-adequacy-closure, agent-prompt-semantics-gap, Algorithm W resolution, contract-clause-refactor, invariant-discovery (base), verification-debate-action-items, proof-required-predicate-carrier (+proposal), lead-agent, core-shell-inversion-direction, oblig-pbt-3-proposal (OBLIG-PBT-3, v0.10.5). v0.11–v0.13 settled/shipped: REF-META 1–5, Bundle B0 (+cross-module addendum), DEF-RET (def-return-annotation), ADMIT-VERIFIED, TRUST-PRE (precondition-tier), CDP (contract-discriminative-power), LT-INV (core-shell-inversion), INT-2 (boundary-shims), positioning-constraint-decay, v0.11-rollback-discipline, verified-contract-refuted-status, verify-reporting-defects (VERIFY-RPT-1), v0.12-direction memo, compositional-trust-closure (DEMO-COMP — **superseded**: §10 realized by `examples/payments-core/`, DEFECT-1 resolved by TRUST-PRE), doc-consolidation-2026-05-24-proposal (DOC-CONSOLIDATE, `1a8733f`). v0.13.7–v0.14.17 shipped: COMP-4 (comp-4-payload-sums), MATCH-WIDEN (match-fragment-widening +engineer-plan), PROOF-ARTIFACT (proof-artifact), cross-module assume-guarantee (cross-module-assume-guarantee). 2026-07-09 sweep: R5/DIP (differential-implementation-pressure, v0.14.7), Leanstral demo spec (v0.14.8), flagship secure-channel (BUILT v0.14.11; superseded by `examples/secure-channel-emergent/`), MATCH-WIDEN spikes (match-widen-r1-tester-spike, match-widen-slice1-impl; v0.14.12), cascading-refinement spike + engineer plan (Stages 1–3, v0.14.13), cycle-verification-finding (resolved v0.14.13 §0.1), cross-module-composition-finding (CLOSED v0.14.18), F-002 terminal pair (spec-entropy-reason-string — terminal Rev 0.2; expiring-intentional — abandoned Rev 0.3, cautionary record). 2026-07-11 sweep: REC-BODY-VC (rec-body-vc-proposal; shipped v0.14.22–25 + lex k>1 v0.14.27), MATCH-WIDEN-2 (match-widen-stretch-plan; v0.14.26/27), REFINE-REUSE (refine-reuse-gate-proposal; v0.14.29). 2026-07-18 sweep: Data-Scope Lever A (data-scope-lever-a-arrays-proposal + data-scope-lever-a-feasibility; A0–A4 + string keys, v0.14.33–51), STRLIT (string-literal-distinctness-proposal; v0.14.44–48), A2.2-string (string-valued-maps-proposal; v0.14.46–47), A4 flagship (a4-flagship-token-revocation-plan; v0.14.47) | v0.6.2–v0.14 (shipped or superseded) |
| `professor-reviews/` | Standalone reviews folded into proposal appendices: `oblig-pbt-3-review`, `invariant-discovery-review`, `contract-discriminative-power-review`, `core-shell-inversion-review`, `positioning-constraint-decay-review`, `refinement-metatheory-of-record-review`, `proof-required-predicate-carrier-review`, `def-ret-staleness-hash-review`, `proof-artifact-review`, `refine-reuse-gate-review`, `rec-body-vc-review`, `data-scope-lever-a-arrays-review` | Post-DOC-CONSOLIDATE M2 |
| `wasm-investigations/` | `effectful-wasm-spike.md`, `wasm-poc-report.md` | Pre-roadmap-reorganization |
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped) |
| `older_discussions_and_plans/` | `SMT_Lean_Analysis.md`, `unicode_decision.md` | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `research-track.md` (file) | Original research-track doc, **frozen-historical**; live items are R1–R7 in `compiler-team-roadmap.md` | Post-DOC-CONSOLIDATE M4 |
