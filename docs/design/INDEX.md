# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-05-01  
> **Purpose:** Index and orientation for all active design documents.

This directory contains design discussions, proposals, and reviews that inform the LLMLL language and system architecture. These are **living documents** — not specifications. The authoritative spec is [`LLMLL.md`](../../LLMLL.md); the engineering backlog is [`compiler-team-roadmap.md`](../compiler-team-roadmap.md).

---

## Verification & Soundness

Documents addressing the formal-methods foundations: what LLMLL guarantees, what it doesn't, and where the trust boundaries are.

| Document | Summary | Status |
|---|---|---|
| [oblig-0-spec.md](oblig-0-spec.md) | OBLIG-0 design spec: obligation report JSON schema, three obligation channels (type/contract/trust), enriched typed holes, EMatch branch obligations, repair suggestions, benchmark suite. Prerequisite for v0.10 implementation. | **Approved** (Rev 8) — OBLIG-1/MOD-1 unblocked |
| [verification-debate.md](verification-debate.md) | Archive of a formal methods critique. Answers 5 Socratic questions (TCB, logic authority, unproven contracts, totality, cross-agent assumptions). Establishes "sound modulo trust" as the defensible position. | Active reference |
| [specification-sources.md](specification-sources.md) | Where do good specifications come from? Identifies 5 sources: external standards, Haskell back-translation, progressive refinement, hub retrieval, synthetic corpus generation. | Active reference |
| [strategic-positioning.md](strategic-positioning.md) | What's genuinely novel (verification as coordination, typed holes as work allocation, trust propagation). What's borrowed. What to stop overclaiming. | Active reference |

---

## Invariant Discovery

Documents addressing the specification-coverage gap: how can the system create pressure to discover invariants that are missing entirely?

| Document | Summary | Status |
|---|---|---|
| [invariant-discovery-proposal.md](invariant-discovery-proposal.md) | External team's full proposal. 9 mechanisms, ranked. Key concepts: "specification pressure" and "contract entropy." Includes a concrete architecture sketch (6 phases per hole). | Active reference |
| [invariant-discovery-review.md](invariant-discovery-review.md) | Professor's mechanism-by-mechanism critique. Recommends differential implementation pressure (Phase A), CEGIS-style strengthening (Phase B), adversarial search (Phase C). Defines "contract discriminative power." | Active reference |

---

## Future Infrastructure

Designs for system components beyond the current compiler — orchestration, component reuse, and type-system evolution.

| Document | Summary | Status |
|---|---|---|
| [agent-orchestration.md](agent-orchestration.md) | Orchestrator design: compiler↔orchestrator boundary, agent registry, context assembly, scheduling strategies, error recovery, self-hosted LLMLL endgame. | Design draft |
| [lead-agent.md](lead-agent.md) | Automated skeleton generation from natural-language intent. Two-step prompt (architecture plan → JSON-AST), compiler-in-the-loop validation, structural quality heuristics. | Design draft |
| [component-hub.md](component-hub.md) | Per-project and global component registry. Query by type signature + contract, not by name. Addresses reuse, progressive accumulation, and cross-project publishing. | Design draft |
| [type-driven-development.md](type-driven-development.md) | Idris-style indexed types for agent hole-filling. The obligation-guided part (structured hole obligations, repair suggestions) was **promoted to v0.10** on the compiler roadmap. What remains here is the indexed-type extension (`Vect n a`, GADTs, type-level arithmetic). | Design exploration (partially promoted) |

---

## Archived Material

Historical design documents from shipped versions are in [`../archive/`](../archive/):

| Directory | Contents | Version |
|---|---|---|
| `shipped-design-specs/` | BODY-VC-0, EVID-0, COMP-0, interface-laws, spec-adequacy-closure, agent-prompt-semantics-gap, Algorithm W resolution, contract-clause-refactor, invariant-discovery (base), verification-debate-action-items | v0.6.2–v0.9.0 (all shipped or superseded) |
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped) |
| `older_discussions_and_plans/` | SMT/Lean analysis, language analysis, feedback, unicode decision | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `v0.3-plan/` | Delegate lifecycle, stratified verification briefs | v0.3 (shipped) |
| `v0.3.1-plan/` | Compiler + professor implementation plans | v0.3.1 (shipped) |
