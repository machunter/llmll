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
| [core-shell-inversion-proposal.md](core-shell-inversion-proposal.md) | LT-INV proposal: invert source-grammar polarity for v0.11 — `def-logic` retired, `def` becomes canonical strict-core form, `def-shell` becomes permissive marked form. Whitelist grammar production for core bodies (only constructs admitted; everything else parse-errors inside `def`). Five settled adjudications: keyword choice (Option 2 — rename), whitelist grammar, `letrec` routing (shell-only in v0.11), `EApp` callee restriction (strict transitive body-faithful closure), hole-form admission (`?hole` admitted, `?proof-required` forbidden). Schema bump 0.5.0 → 0.6.0. Migration scope: 12 example directories via mechanical syntactic classifier with `--migration-conservative` opt-in. Empirical validation gate per direction memo §8 — ships behind `--grammar=core-inversion` opt-in first; default flips only on gate pass. Subsumes STRICT-CORE-1 triage row. | **Settled** (Rev 1) — awaiting professor review at `core-shell-inversion-review.md`, then compiler-engineer hand-off |
| [contract-discriminative-power-proposal.md](contract-discriminative-power-proposal.md) | LT-CDP proposal: promote contract discriminative power from research-track formalization to v0.11 first-class evidence axis (CDP-0). Two-axis assurance report — paired `(evidence, DP)` per function rather than collapsed scalar. Normalized DP score on subobject lattice over finite observational behavior space (narrower lattice-valuation framing from amended critic via triage §3.2); ` DP = 1 - log(satisfying) / log(total)` with edge cases for vacuous / single-behavior / inconsistent contracts. Optional `(spec-entropy :strict \| :intentional \| :unknown)` annotation honors the healthy-diversity-vs-underspecification tension. Builds on `WeaknessCheck.hs` trivial-body enumeration. `trust_report_version 1.1.0 → 1.2.0` (additive). Subsumes DP-FORM-1 + TRUST-DP-1 triage rows; supersedes [research-track.md](../research-track.md) §6 (already retired in catch-up Pass 3 with cross-reference). | **Settled** (Rev 1) — awaiting professor review at `contract-discriminative-power-review.md`, then compiler-engineer hand-off |
| [proof-required-predicate-carrier-proposal.md](proof-required-predicate-carrier-proposal.md) | LT-PPR proposal: extend `?proof-required` from leaf reason-tag hole to optionally predicate-carrying form. Re-opens the deferred-exploration doc; revisit conditions met by LT-INV freeze-lift (condition 1) and core/shell escape-hatch downstream-consumer benefit (condition 2b). Two settled adjudications: trust label stays `asserted` (no new fifth tier; runtime-assertion is a runtime artifact, not a tier promotion); predicate-carrying form forbidden inside `def` per LT-INV §1.4 (`def-shell`-only). Schema delta: `HoleKind.HProofRequired Text → Text (Maybe Expr)`; bundled with LT-INV schemaVersion 0.5.0 → 0.6.0 bump. Codegen emits runtime-assertion fallback over the predicate; trust-report gains `predicate_form` / `predicate_text` / `runtime_check_emitted` fields. Supersedes [proof-required-predicate-carrier.md](proof-required-predicate-carrier.md) (deferred-exploration seed, status flipped in catch-up Pass 4). | **Settled** (Rev 1) — awaiting professor review at `proof-required-predicate-carrier-review.md`, then compiler-engineer hand-off |
| [int-2-boundary-shims.md](int-2-boundary-shims.md) | LT-INT / INT-2 boundary-shim catalog: classifies the fifteen `Int`-touching preamble entries at [`CodegenHs.hs:232-360`](../../compiler/src/LLMLL/CodegenHs.hs) into Class A (stays `Int`, indexing — 6 entries), Class B (becomes `Integer`, semantic-arithmetic — 6 entries), Class C (`random_int`, stays `Int` with explicit ill-formedness-under-unbounded-measure justification — 1 entry). Ratifies the `range` value-shape / `range-idx` index-shape split with codegen-side pattern detection. Documents the `fromIntegral` boundary trust closure as a sub-case of the FFI-builtin trust model. Settles the INT-1 / INT-2 interaction: `overflow_tainted` dormant on `int` post-INT-2, armed for `machine-int` per INT-3. Zero new proof obligations; constraint vocabulary at `FixpointEmit.hs:188-194` and Lean translation at `LeanTranslate.hs:60` unchanged. Authored from language-team review of experiment-lead INT-PRE plan, finding F1 (boundary-shim catalog underspecification blocks Variant B fidelity). | **Settled** (Rev 1) — awaiting v0.10.7 ship + INT-PRE adjudication, then compiler-engineer hand-off |
| [int-3-machine-int-sketch.md](int-3-machine-int-sketch.md) | INT-3 contingency sketch for `machine-int` QF-BV alias. Dormant unless INT-PRE shows TOTP regression ≥ 5×; promotes to Rev 1 settled proposal IFF the gate fires. Settles the type name (`machine-int`, four alternatives rejected) and the primitive-type-vs-refinement-aliased axis (primitive, on three grounds: verification-fragment cleanliness, constraint-vocabulary uniformity hazard, Liquid Haskell idiomatic alignment). Commits to opt-in-only per-declaration migration (no `--bounded-int-default` switch); explicit conversion primitives `int->machine-int` / `machine-int->int`; QF-BV constraint emitter via new `FQBV` constructor parallel to `FQInt`. Hosts two dormant outside-PL professor questions (refinement-aliased vs primitive precedent in Liquid Haskell; bit-twiddling operator admission strategy). Authored from language-team review of experiment-lead INT-PRE plan, finding F5 (INT-3 design lag could block freeze-exception escalation). | **Contingency sketch (Rev 0)** — dormant unless INT-PRE escalates |

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
