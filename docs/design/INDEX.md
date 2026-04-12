# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-04-12  
> **Purpose:** Index and orientation for all active design documents.

This directory contains design discussions, proposals, and reviews that inform the LLMLL language and system architecture. These are **living documents** — not specifications. The authoritative spec is [`LLMLL.md`](../../LLMLL.md); the engineering backlog is [`compiler-team-roadmap.md`](../compiler-team-roadmap.md).

---

## Verification & Soundness

Documents addressing the formal-methods foundations: what LLMLL guarantees, what it doesn't, and where the trust boundaries are.

| Document | Summary | Status |
|---|---|---|
| [verification-debate.md](verification-debate.md) | Archive of a formal methods critique. Answers 5 Socratic questions (TCB, logic authority, unproven contracts, totality, cross-agent assumptions). Establishes "sound modulo trust" as the defensible position. | Active reference |
| [verification-debate-action-items.md](verification-debate-action-items.md) | Concrete tickets from the debate: TCB hardening, trust propagation tests, semantic anchor decision, effect system spec, `(trust ...)` elevation. | Active — items tracked |
| [specification-sources.md](specification-sources.md) | Where do good specifications come from? Identifies 5 sources: external standards, Haskell back-translation, progressive refinement, hub retrieval, synthetic corpus generation. | Active reference |
| [strategic-positioning.md](strategic-positioning.md) | What's genuinely novel (verification as coordination, typed holes as work allocation, trust propagation). What's borrowed. What to stop overclaiming. | Active reference |

---

## Invariant Discovery

Documents addressing the specification-coverage gap: how can the system create pressure to discover invariants that are missing entirely?

| Document | Summary | Status |
|---|---|---|
| [invariant-discovery.md](invariant-discovery.md) | Distilled design discussion. 6 mechanisms: adversarial red-team, mutation testing on specs, property mining, spec coverage metric, hub-driven suggestions, counter-example display. | Active reference |
| [invariant-discovery-proposal.md](invariant-discovery-proposal.md) | External team's full proposal. 9 mechanisms, ranked. Key concepts: "specification pressure" and "contract entropy." Includes a concrete architecture sketch (6 phases per hole). | Under review |
| [invariant-discovery-review.md](invariant-discovery-review.md) | Professor's mechanism-by-mechanism critique. Recommends differential implementation pressure (Phase A), CEGIS-style strengthening (Phase B), adversarial search (Phase C). Defines "contract discriminative power." | Under review |

---

## Future Infrastructure

Designs for system components beyond the current compiler — orchestration, component reuse, and type-system evolution.

| Document | Summary | Status |
|---|---|---|
| [agent-orchestration.md](agent-orchestration.md) | Orchestrator design: compiler↔orchestrator boundary, agent registry, context assembly, scheduling strategies, error recovery, self-hosted LLMLL endgame. | Design draft |
| [component-hub.md](component-hub.md) | Per-project and global component registry. Query by type signature + contract, not by name. Addresses reuse, progressive accumulation, and cross-project publishing. | Design draft |
| [type-driven-development.md](type-driven-development.md) | Idris-style indexed types for agent hole-filling. Hypothesis: step-by-step type-guided deduction improves LLM accuracy. Minimal experiment: `Vect n a` + `llmll split`. Deferred to v0.5+. | Design exploration |

---

## Archived Material

Historical design documents from shipped versions are in [`../archive/`](../archive/):

| Directory | Contents | Version |
|---|---|---|
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped) |
| `older_discussions_and_plans/` | SMT/Lean analysis, language analysis, feedback, unicode decision | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `v0.3-plan/` | Delegate lifecycle, stratified verification briefs | v0.3 (shipped) |
| `v0.3.1-plan/` | Compiler + professor implementation plans | v0.3.1 (shipped) |
