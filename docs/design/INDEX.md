# LLMLL Design Documents — Reading Guide

> **Last updated:** 2026-08-05  
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
| [cascading-refinement-proposal.md](cascading-refinement-proposal.md) | Agent-driven recursive hole decomposition: `refine` op + growing tree + CDP/feasibility gates + Option-3 cycles | **Rev 8 — Stages 1–3 SHIPPED v0.14.13, Stage-4 REFINE-REUSE SHIPPED v0.14.29, feasibility (no-miracle) gate SHIPPED v0.14.52, decomposition-trust meet SHIPPED v0.14.53 — line complete**; Option-3 cycles reconciled to REC-PARTIAL-MARK's `termination_unverified` marker (2026-07-10) |
| [spec-from-rfc-pipeline.md](spec-from-rfc-pipeline.md) | R3 pipeline: RFC clauses → classified, `:source`-traced, adequacy-checked contracts | **Rev 1** — §4 evaluation executed (RFC 1982, all six criteria pass; G1+G4 closed; F-1982-3/-4/-5 folded); G2 CLOSED v0.14.65 (SRC-CONJ-1); G3 accepted |
| [rfc-swarm-playbook.md](rfc-swarm-playbook.md) | Executable procedure: agent turns an RFC into a spec, then spawns a swarm to implement it | **Rev 0** — derived from the first full run (TFTP Phase 0, 2026-07-24); operational authority over the pipeline doc's stages |
| [rfc-swarm-roadmap-proposal.md](rfc-swarm-roadmap-proposal.md) | RFC-SWARM target selection, acceptance criteria, phases 0-4; TFTP ratified | **Rev 1.1** — professor review folded; Phase 0 COMPLETE (`ada0f6e`), SRC-CONJ-1 shipped v0.14.65 |
| [rfc-swarm-coverage-review.md](rfc-swarm-coverage-review.md) | Professor: the fired STOP was a defective instrument; per-barrier ruling on widening | **Rev 0** — adopted; ratio ceiling retired by PRE-REGISTRATION Amendment 1 |
| [rfc-swarm-coverage-widening.md](rfc-swarm-coverage-widening.md) | Language-team triage of the 58 excluded clauses; what features could recover them | **Rev 0** — build nothing; LEAN-GA stays parked (recovers zero rows) |
| [rfc-swarm-target-selection.md](rfc-swarm-target-selection.md) | What makes an RFC likely to pass gate J, and whether a cheap screen for it exists | **Rev 1** — criterion stands; the two-call pre-flight rejected 7/7 targets including both that passed gate J, and is **retired**. Screen with `--only A..G,G2,J` instead |
| [finding-match-nullary-ctor-unsound.md](finding-match-nullary-ctor-unsound.md) | Bare nullary constructor in a match arm parses as a catch-all binder; verifier proves what codegen violates | **FIXED v0.14.66** (MATCH-NULLARY-1); blast radius was zero in-tree; unblocked the RFC-SWARM wave |
| [finding-fq-ctor-name-collision.md](finding-fq-ctor-name-collision.md) | Binder named like a lowercased ADT constructor collides in the `.fq` namespace and crashes the solver | **FIXED v0.14.67** (FQ-CTOR-COLLIDE-1); failed closed throughout, so no verdict was affected |
| [finding-arg-position-false-safe.md](finding-arg-position-false-safe.md) | A `bytes[n]` length asserted from an unvalidated declaration proved an out-of-bounds read safe | **FIXED** — bytes arm v0.14.73, `map[k,bool]` arm v0.14.74, ADMIT-SHARED v0.14.75; affected v0.14.34..v0.14.73 |
| [fact-ag-proposal.md](fact-ag-proposal.md) | Earn the `bytes[n]` length as an obligation instead of asserting it from a declaration | **Rev 4, SETTLED and COMPLETE**: all three stages SHIPPED (v0.14.76 / v0.14.77 / v0.14.78), line closed |
| [fact-ag-proposal-review.md](../archive/professor-reviews/fact-ag-proposal-review.md) | Professor review of FACT-AG-LEN, two rounds; round 1 conceded the sort/gate rejection | **Folded and archived** (M2, v0.14.78); redirect stub at the old path for one cycle |
| [ret-resolve-proposal.md](ret-resolve-proposal.md) | Resolve a wildcard `τ_ret` transitively in a verification-facing pass | **Rev 2, SETTLED** — queued third, behind SAFE-ARG and WILD-ASSUME |
| [ret-resolve-proposal-review.md](ret-resolve-proposal-review.md) | Professor review of RET-RESOLVE, four rounds; rounds 3-4 produced SAFE-ARG | **Standalone**, not folded |
| [finding-fq-result-sort-default.md](finding-fq-result-sort-default.md) | The `result` binder's sort defaults to `int` when the return type is unannotated; bool, string, and pair returns crash | **FIXED v0.14.72** (FQ-RESULT-SORT-1, alias FQ-BOOL-SORT-1); Rev 3 withdrew HOLE-RET; residual closed by RET-BRANCH-PREF |
| [finding-fq-result-sort-default-review.md](finding-fq-result-sort-default-review.md) | Professor review of FQ-RESULT-SORT-1, Rev 0 and Rev 1 | **Two rounds**, standalone, ready for fold-and-archive (M2) |
| [ret-branch-pref-proposal.md](ret-branch-pref-proposal.md) | Prefer the concrete branch at an `if` join when the other synthesizes the `?` wildcard | **Rev 0**, Stage 1 SHIPPED v0.14.72 (self-recursive only); Stage 2 recorded, gated on measurement |
| [ret-branch-pref-proposal-review.md](ret-branch-pref-proposal-review.md) | Professor adjudication: build it, narrowed to self-recursion | **Rev 0**, standalone, not yet folded |
| [leanstral-integration-scope.md](leanstral-integration-scope.md) | Leanstral/Lean-tier scoping: anti-laundering guard, C-property, three-layer LEAN-GA rebuild | **Parked (LEAN-GA)** — demo subset shipped v0.14.8; production rebuild deferred, cited by the roadmap parking lot |
| [critique-2026-07-19-triage.md](critique-2026-07-19-triage.md) | 2026-07-19 external-critique triage of `v0.14.53`; dispositions recorded inline | **Settled** — no design adjudication required; §2 is the routing table |
| [spec-agreement-proposal.md](spec-agreement-proposal.md) | SPEC-AGREE-1: independent formalization with mechanical agreement | **Rev 0, DRAFT** — awaiting professor review |
| [spec-agreement-review.md](spec-agreement-review.md) | Professor review of SPEC-AGREE-1 Rev 0 | **Rev 0** — standalone, not yet folded |
| [incremental-reverify-r8-proposal.md](incremental-reverify-r8-proposal.md) | R8: dependency-scoped `patch` re-verification replacing the whole-module re-verify | **Rev 0** — both soundness premises code-verified; ready for engineer feasibility read |
| [examples-audit-2026-07-20-compiler-followups.md](examples-audit-2026-07-20-compiler-followups.md) | Two compiler/CI defects from the full `examples/` audit (R1 sort synthesis, R2 benchmark ordering) | **BOTH RESOLVED** (R1 v0.14.62, R2 2026-07-21) — archive-eligible |
| [archive-organization-proposal.md](archive-organization-proposal.md) | DRIFT-DOC-3: retire version buckets, gate the archive invariant that is groundable | **Rev 2, SETTLED**: FLAT adjudicated 2026-07-26; professor review folded; P1/P2 applied, P3 gate shipped |
| [archive-organization-review.md](archive-organization-review.md) | Professor: the gate is consistency-class, not correctness-class; both routed questions answered | **Rev 1**: standalone, folded into Rev 2, ready for M2 archive |
| [effect-response-channel-proposal.md](effect-response-channel-proposal.md) | A response channel, plus DISCARD-1, the `do`-step discard marker | **Rev 5, SETTLED AND SHIPPED v0.14.80**: arm set closed under a four-part admissibility rule |
| [event-log-scope-proposal.md](event-log-scope-proposal.md) | The event log is an I/O-trace divergence oracle; `§10a` specifies a different mechanism | **Rev 0, PROPOSED**: §10a narrows (EVENT-LOG-2); injection preserved as REPLAY-INJECT |

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
| [native-json-proposal.md](native-json-proposal.md) | Fourteen JSON builtins for the driver, and the native-JSON work deferred | **Rev 3, SETTLED**; shipped as JSON-1 at v0.14.82 |
| [native-json-review.md](native-json-review.md) | Professor review of an earlier JSON draft; six findings folded | **Rev 0, standalone**; reviews a superseded draft, see proposal §10 |
| [driver-in-llmll-campaign.md](driver-in-llmll-campaign.md) | Five phases to a working RFC-SWARM driver in LLMLL, and the language work it needs | **Rev 4, IN FLIGHT**: Phases 0 and 1 shipped v0.14.80; CAP-PROC shipped v0.14.81, leaving JSON-1 as Phase 2's last item |
| [driver-ll-phase01-implementation-plan.md](driver-ll-phase01-implementation-plan.md) | Engineer plan for WASI-RT, EFFECT-RESP RC-1..RC-4, and DISCARD-1 | **IMPLEMENTED, shipped v0.14.80**; two of its path citations are stale (see the open-work record, R-5) |
| [driver-ll-open-work.md](driver-ll-open-work.md) | What the v0.14.80 and v0.14.81 line shipped, and the work it deliberately left open | **ACTIVE ROUTING RECORD**: both releases done; two blockers filed as `CAP-1-REAL` and `CONSOLE-INIT-1`; R-11 promoted to `HTTP-GET-1` and R-13 closed at v0.14.81 |
| [driver-ll-phase4-proposal.md](driver-ll-phase4-proposal.md) | Eleven agent-delegated stages, the serial wave, and two checkable oracles | **Rev 11, SETTLED**: 4a (`2b82464`, v0.14.85) and 4b (`ba2f93d`, v0.14.87) shipped, 4c merged with its release ceremony held, 4d-4f open; Rev 11 folds two amendments the 4c port earned, neither touching a proved post |
| [driver-ll-phase4-RESTART.md](driver-ll-phase4-RESTART.md) | Session restart record for Phase 4: branch, task queue, next actions, gotchas | **LIVE**; delete when Phase 4 closes |
| [driver-ll-phase4a-implementation-plan.md](driver-ll-phase4a-implementation-plan.md) | Engineer plan and record for sub-phase 4a: three modules, two cruxes, a fifteen-scenario cover | **IMPLEMENTED** (`2b82464`, v0.14.85); the recommended shim was not built, and four findings came back, two disagreeing with a settled document |
| [driver-ll-phase4b-implementation-plan.md](driver-ll-phase4b-implementation-plan.md) | Engineer plan and record for sub-phase 4b: stages B, C, I and one shared validation facility | **IMPLEMENTED** (`ba2f93d`, v0.14.87); cover 15 to 31 cells, and it found `PROC-TIMEOUT-1` |
| [driver-ll-phase4c-implementation-plan.md](driver-ll-phase4c-implementation-plan.md) | Engineer plan and record for sub-phase 4c: stages D, F, G and a proved content-shape channel | **IMPLEMENTED and MERGED**, release ceremony held; cover 31 to 39 cells, and it found `REGEX-LOWER-1` plus two defects only running the built driver could reach |
| [proc-boundary-1-proposal.md](proc-boundary-1-proposal.md) | argv as `wasi.proc.args`, terminal status as a `def-main` projection; no catalog growth | **Rev 4, SETTLED, shipped v0.14.85**: Rev 4's §5.1 records that the range obligation is body-proved only for a scalar state; §6.3's `tcWarn` is still owed, so roadmap row `PROC-BOUNDARY-1` stays open |
| [proc-boundary-1-implementation-plan.md](proc-boundary-1-implementation-plan.md) | Engineer plan and measurements for `wasi.proc.args` and `def-main :status` | **IMPLEMENTED, shipped v0.14.85**; its finding 1 became roadmap row `DONE-TYPE-1` |
| [component-hub.md](component-hub.md) | Per-project + global component registry; query by type signature and contract | **Dormant** — future discussion retained |
| [language-comparison-experiments.md](language-comparison-experiments.md) | Cross-language benchmark: correctness vs assurance on independent axes | Design note |
| [type-driven-development.md](type-driven-development.md) | Indexed types (`Vect n a`, GADTs, type-level arithmetic); obligation part promoted | **Dormant** — partially promoted, R1 residual |

---

## Archived Material

Historical design documents from shipped or superseded sources are in [`../archive/`](../archive/). Settled-and-shipped proposals are folded (professor reviews → `## Appendix`) and moved here; version lineage lives in [`../compiler-team-roadmap.md`](../compiler-team-roadmap.md) `## Shipped Releases` and [`../../CHANGELOG.md`](../../CHANGELOG.md).

| Directory / file | Contents | Origin |
|---|---|---|
| `shipped-design-specs/` | Shipped/superseded design specs. v0.6.2–v0.9.0: BODY-VC-0, EVID-0, COMP-0, interface-laws, spec-adequacy-closure, agent-prompt-semantics-gap, Algorithm W resolution, invariant-discovery (base), verification-debate-action-items, proof-required-predicate-carrier (+proposal), lead-agent, core-shell-inversion-direction, oblig-pbt-3-proposal (OBLIG-PBT-3, v0.10.5). v0.11–v0.13 settled/shipped: REF-META 1–5, Bundle B0 (+cross-module addendum), DEF-RET (def-return-annotation), ADMIT-VERIFIED, TRUST-PRE (precondition-tier), CDP (contract-discriminative-power), LT-INV (core-shell-inversion), INT-2 (boundary-shims), positioning-constraint-decay, v0.11-rollback-discipline, verified-contract-refuted-status, verify-reporting-defects (VERIFY-RPT-1), v0.12-direction memo, compositional-trust-closure (DEMO-COMP — **superseded**: §10 realized by `examples/payments-core/`, DEFECT-1 resolved by TRUST-PRE), doc-consolidation-2026-05-24-proposal (DOC-CONSOLIDATE, `1a8733f`). v0.13.7–v0.14.17 shipped: COMP-4 (comp-4-payload-sums), MATCH-WIDEN (match-fragment-widening +engineer-plan), PROOF-ARTIFACT (proof-artifact), cross-module assume-guarantee (cross-module-assume-guarantee). 2026-07-09 sweep: R5/DIP (differential-implementation-pressure, v0.14.7), Leanstral demo spec (v0.14.8), flagship secure-channel (BUILT v0.14.11; superseded by `examples/secure-channel-emergent/`), MATCH-WIDEN spikes (match-widen-r1-tester-spike, match-widen-slice1-impl; v0.14.12), cascading-refinement spike + engineer plan (Stages 1–3, v0.14.13), cycle-verification-finding (resolved v0.14.13 §0.1), cross-module-composition-finding (CLOSED v0.14.18), F-002 terminal pair — **moved 2026-07-26 to `dormant-explorations/`** (neither shipped); `contract-clause-refactor` — **moved 2026-07-26 to `dormant-explorations/`** (deferred, never shipped). 2026-07-11 sweep: REC-BODY-VC (rec-body-vc-proposal; shipped v0.14.22–25 + lex k>1 v0.14.27), MATCH-WIDEN-2 (match-widen-stretch-plan; v0.14.26/27), REFINE-REUSE (refine-reuse-gate-proposal; v0.14.29). 2026-07-18 sweep: Data-Scope Lever A (data-scope-lever-a-arrays-proposal + data-scope-lever-a-feasibility; A0–A4 + string keys, v0.14.33–51), STRLIT (string-literal-distinctness-proposal; v0.14.44–48), A2.2-string (string-valued-maps-proposal; v0.14.46–47), A4 flagship (a4-flagship-token-revocation-plan; v0.14.47) | Flat by decision; version lineage is queried from `CHANGELOG.md`, not encoded in the path (DRIFT-DOC-3) |
| `dormant-explorations/` | Docs whose feature did **not** ship, whether `dropped` or `deferred`, as distinct from shipped-and-archived; admission test and the four-valued vocabulary in the directory's `README.md`. The F-002 terminal pair (`expiring-intentional-proposal`, `spec-entropy-reason-string-proposal`) plus `contract-clause-refactor` (deferred) | 2026-07-26 |
| `professor-reviews/` | Standalone reviews folded into proposal appendices: `oblig-pbt-3-review`, `invariant-discovery-review`, `contract-discriminative-power-review`, `core-shell-inversion-review`, `positioning-constraint-decay-review`, `refinement-metatheory-of-record-review`, `proof-required-predicate-carrier-review`, `def-ret-staleness-hash-review`, `proof-artifact-review`, `refine-reuse-gate-review`, `rec-body-vc-review`, `data-scope-lever-a-arrays-review` | Post-DOC-CONSOLIDATE M2 |
| `wasm-investigations/` | `effectful-wasm-spike.md`, `wasm-poc-report.md` | Pre-roadmap-reorganization |
| `do_notation/` | Do-notation design and two implementation plans | v0.3 (shipped); design §2.4 (command accumulation) **superseded 2026-08-02** by `LLMLL.md` §9.6 |
| `older_discussions_and_plans/` | `SMT_Lean_Analysis.md`, `unicode_decision.md` | Pre-v0.2 |
| `sketch/` | Compiler handoff sketch, implementation guide | Pre-v0.2 |
| `research-track.md` (file) | Original research-track doc, **frozen-historical**; live items are R1–R7 in `compiler-team-roadmap.md` | Post-DOC-CONSOLIDATE M4 |
