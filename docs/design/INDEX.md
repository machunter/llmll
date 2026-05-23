# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-05-23  
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
| [proof-required-predicate-carrier.md](proof-required-predicate-carrier.md) | Deferred exploration: extending `?proof-required` from a leaf reason-tag hole to a predicate-carrying form. Would let the intended-but-unverifiable property be machine-readable in the AST instead of buried in adjacent prose. Out of scope under feature freeze; revisit conditions specified. Captured from LT-B Risk #4 after recurrent agent ambiguity (5/12 attempts) on the broken LT-A D3 example. | Deferred exploration (post-v0.10 candidate) |
| [oblig-pbt-3-proposal.md](oblig-pbt-3-proposal.md) | PBT-to-trust-report write-back (F-033 / OBLIG-PBT-3): singleton-head-position linkage rule, `DLTested n` lift on `csPost`, per-clause `tier_profile_pre`/`tier_profile_post` aggregates (bumps `trust_report_version` 1.0.0 → 1.1.0), property-body SHA-256 provenance with read-side staleness downgrade, explicit `evaluatedSamples` semantics disclosure, design-divergence statement vs Liquid Haskell. `:subject` metadata + coverage instrumentation sequenced to OBLIG-PBT-4. | **Settled** (Rev 2) — awaiting compiler-engineer hand-off |
| [oblig-pbt-3-review.md](oblig-pbt-3-review.md) | Professor review of OBLIG-PBT-3. Seven gaps + two open questions, all resolved in Rev 2. Recommends approval for compiler-engineer hand-off. | Active reference |
| [core-shell-inversion-direction.md](core-shell-inversion-direction.md) | v0.11 direction memo from the professor channel: invert the source grammar so the verified-core form is canonical and the mixed regime is explicitly marked; promote contract discriminative power to a first-class evidence axis; re-open predicate-carrying `?proof-required`; reclassify `Command` effect rows as Bundle B (post-v0.11), separate from the indexed-types research track. Consolidates external critique (2026-05-23) with prior professor turn including a backward-compat-hedge self-correction. Pre-stable project — v0.11 breaks syntax deliberately. Rev 2 adds §8 empirical validation gate via `experiments/minimal-agent/` harness; the inversion ships only if the pre/post comparison on `001-two-agent-auth` and post-DL-B batches confirms the architectural bet. §§2–3 are gate-independent. | **Direction memo (Rev 2)** — awaiting `language-team` LT-proposal(s) |
| [critique-2026-05-23-triage.md](critique-2026-05-23-triage.md) | Triage record of the 2026-05-23 external critique: four-turn convergence across original critic → language-team → professor → amended critic. 14 of 16 rows settled directly; two framing adjudications recorded (refinement-metatheory checking-mode framing; narrower DP-as-valuation-on-subobject-lattice unification). Seventeen tagged routing items (DRIFT-, TC-EOP-, OBLIG-PBT-5, INT-, REF-META-, TRUST-DP-, DP-FORM-, TERM-, DO-, CRYPTO-, STRICT-CORE-) with priority/owner/status columns. Companion to the core-shell-inversion-direction memo, which supersedes parts of the triage routing for v0.11 architectural work. | **Settled** — routing in progress (see [`compiler-team-roadmap.md`](../compiler-team-roadmap.md) Active Items) |

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
| [language-comparison-experiments.md](language-comparison-experiments.md) | Cross-language agent benchmark design. Separates product correctness from assurance evidence when comparing LLMLL against Python, Go, TypeScript, Rust, and similar targets. | Design note |
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
