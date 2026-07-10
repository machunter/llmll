# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-07-10  
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
| [data-scope-extension.md](data-scope-extension.md) | Didactic multi-post: the data verification boundary (`Σ_auto`) and the array/dependent-length/induction extension levers | **Design / roadmap** — forward-looking; current-state posts describe shipped caps |
| [cascading-refinement-proposal.md](cascading-refinement-proposal.md) | Agent-driven recursive hole decomposition: `refine` op + growing tree + CDP/feasibility gates + Option-3 cycles | **Rev 3 — Stages 1–3 SHIPPED v0.14.13** (`refine` op + spawn-time CDP vacuity gate); Option-3 cycles reconciled to REC-PARTIAL-MARK's `termination_unverified` marker (2026-07-10); feasibility gate + Stage-4 REFINE-REUSE open |
| [rec-body-vc-proposal.md](rec-body-vc-proposal.md) | Recursive own-body VC: partiality marker + def-form hash integrity (closes probe E) + `(decreases …)` call-site strict descent (step-indexed A-G) | **Rev 1 (professor-folded)** — increments 1–2 ready to hand off; increment 3 (REC-DESCENT) awaits a freeze-exception sign-off |
| [rec-body-vc-review.md](rec-body-vc-review.md) | Professor review of REC-BODY-VC Rev 0: hash-not-guard fix for probe E, `measure-not-decreasing` rename, step-index framing, list-shaped `decreases` surface | **Folded into proposal Rev 1** — ready for archive on settlement |
| [refine-reuse-gate-proposal.md](refine-reuse-gate-proposal.md) | REFINE-REUSE: reuse-retrieval for `refine` — advisory `reuse_suggestions` + non-blocking `W-REUSE` when a spawned sub-contract is subsumed by an existing def (contract-implication, not name/syntax) | **Settled (Rev 1)** — professor review folded (Appendix); awaiting compiler-engineer feasibility read |
| [match-widen-stretch-plan.md](match-widen-stretch-plan.md) | MATCH-WIDEN staged plan: scrutinee-constructor posts via int-tag discrimination | **Partially shipped (v0.14.12)** — S0–S3 landed; §S4 (>2-arm + sequential) is the active MATCH-WIDEN-2 row |
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
| `shipped-design-specs/` | Shipped/superseded design specs. v0.6.2–v0.9.0: BODY-VC-0, EVID-0, COMP-0, interface-laws, spec-adequacy-closure, agent-prompt-semantics-gap, Algorithm W resolution, contract-clause-refactor, invariant-discovery (base), verification-debate-action-items, proof-required-predicate-carrier (+proposal), lead-agent, core-shell-inversion-direction, oblig-pbt-3-proposal (OBLIG-PBT-3, v0.10.5). v0.11–v0.13 settled/shipped: REF-META 1–5, Bundle B0 (+cross-module addendum), DEF-RET (def-return-annotation), ADMIT-VERIFIED, TRUST-PRE (precondition-tier), CDP (contract-discriminative-power), LT-INV (core-shell-inversion), INT-2 (boundary-shims), positioning-constraint-decay, v0.11-rollback-discipline, verified-contract-refuted-status, verify-reporting-defects (VERIFY-RPT-1), v0.12-direction memo, compositional-trust-closure (DEMO-COMP — **superseded**: §10 realized by `examples/payments-core/`, DEFECT-1 resolved by TRUST-PRE), doc-consolidation-2026-05-24-proposal (DOC-CONSOLIDATE, `1a8733f`). v0.13.7–v0.14.17 shipped: COMP-4 (comp-4-payload-sums), MATCH-WIDEN (match-fragment-widening +engineer-plan), PROOF-ARTIFACT (proof-artifact), cross-module assume-guarantee (cross-module-assume-guarantee). 2026-07-09 sweep: R5/DIP (differential-implementation-pressure, v0.14.7), Leanstral demo spec (v0.14.8), flagship secure-channel (BUILT v0.14.11; superseded by `examples/secure-channel-emergent/`), MATCH-WIDEN spikes (match-widen-r1-tester-spike, match-widen-slice1-impl; v0.14.12), cascading-refinement spike + engineer plan (Stages 1–3, v0.14.13), cycle-verification-finding (resolved v0.14.13 §0.1), cross-module-composition-finding (CLOSED v0.14.18), F-002 terminal pair (spec-entropy-reason-string — terminal Rev 0.2; expiring-intentional — abandoned Rev 0.3, cautionary record) | v0.6.2–v0.14 (shipped or superseded) |
| `professor-reviews/` | Standalone reviews folded into proposal appendices: `oblig-pbt-3-review`, `invariant-discovery-review`, `contract-discriminative-power-review`, `core-shell-inversion-review`, `positioning-constraint-decay-review`, `refinement-metatheory-of-record-review`, `proof-required-predicate-carrier-review`, `def-ret-staleness-hash-review`, `proof-artifact-review`, `refine-reuse-gate-review` | Post-DOC-CONSOLIDATE M2 |
| `wasm-investigations/` | `effectful-wasm-spike.md`, `wasm-poc-report.md` | Pre-roadmap-reorganization |
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped) |
| `older_discussions_and_plans/` | `SMT_Lean_Analysis.md`, `unicode_decision.md` | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `research-track.md` (file) | Original research-track doc, **frozen-historical**; live items are R1–R7 in `compiler-team-roadmap.md` | Post-DOC-CONSOLIDATE M4 |
| `roadmap-shipped-history.md` (file) | Detailed per-version shipped history (v0.1.2 → v0.12) split out of `compiler-team-roadmap.md`; live roadmap keeps a compact `## Shipped Releases` summary | Post-DOC-CONSOLIDATE M5 (2026-06-21) |
