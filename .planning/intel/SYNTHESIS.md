# Synthesis

Entry point for downstream consumers. Produced by `gsd-doc-synthesizer` from 18 per-doc
classifications in `.planning/intel/classifications/`. Mode: `new`. No pre-existing
`PROJECT.md` / `REQUIREMENTS.md` / `ROADMAP.md` / `STATE.md` to merge against.

**Status: READY.** Zero blockers, zero competing variants. The prior run's 1 blocker and 2 warnings
are all resolved upstream and are recorded as INFO so each stays traceable and reversible. See
`.planning/INGEST-CONFLICTS.md`.

---

## Doc counts by type

| Type | Count | Docs |
|---|---|---|
| SPEC | 12 | compiler-team-roadmap, data-scope-extension, incremental-reverify-r8-proposal, leanstral-integration-scope, oblig-0-spec, ret-branch-pref-proposal, ret-resolve-proposal, rfc-swarm-playbook, rfc-swarm-roadmap-proposal, rfc-swarm-target-selection, spec-agreement-proposal, spec-from-rfc-pipeline |
| DOC | 6 | critique-2026-05-23-triage, finding-arg-position-false-safe, finding-fq-result-sort-default-review, ret-branch-pref-proposal-review, ret-resolve-proposal-review, spec-agreement-review |
| ADR | 0 | — |
| PRD | 0 | — |
| UNKNOWN | 0 | — |

All 18 classifications carry `confidence: high` and `manifest_override: true`. **All 18 docs were
synthesized**; nothing was withheld.

## Precedence applied

- 0 — `docs/compiler-team-roadmap.md` (backlog of record; outranks every proposal)
- 1 — the 10 open/parked design proposals plus `docs/design/rfc-swarm-playbook.md`
- 2 — `docs/design/spec-from-rfc-pipeline.md`, the 5 companion reviews/findings, and the triage table

Lower integer wins. Default `ADR > SPEC > PRD > DOC` was never reached: every doc carries a manifest
integer. The playbook/pipeline split at 1 and 2 transcribes the ordering both docs declare about
themselves (`spec-from-rfc-pipeline.md:7`, `rfc-swarm-playbook.md:22`).

## Decisions

**Locked: 0.** No ADR-typed doc and no `Accepted`/locked status anywhere in the set, so the
LOCKED-vs-LOCKED check did not fire and no decision can be auto-overridden.

**Recorded (status `proposed`): 24.** New this run: the if-join adjudication (RET-RESOLVE SC3');
the SPEC-AGREE-1 scoping rule at Rev 1; the constructor-capable backend in scope with no Lever A
dependency; agreement reporting as detection yield; gate J's retired exclusion-ratio ceiling; the
`B7` already-entailed rewrite; the scoped clause-carrying freeze; stale-binary detection via
`stack build --dry-run`; and pipeline gap G3 accepted.

→ `.planning/intel/decisions.md`

## Requirements

**45 extracted**, all from the open/unshipped remainder (no PRDs; provenance rule in the file header).

- Compiler backlog (roadmap, precedence 0): `REQ-wild-assume-2`, `REQ-ret-resolve`, `REQ-fact-ag`, `REQ-oblig-1-def-invariant`, `REQ-contract-read-lint-residual`, `REQ-int-3`
- Module system codegen: `REQ-mod-2-per-module-emission`, `REQ-mod-3-qualified-access`, `REQ-mod-4-strict-typecheck-migration`, `REQ-mod-5-interface-mismatch`
- Sandboxing: `REQ-wasm-build-target`
- Data scope: `REQ-lever-a-residue-a3x`, `REQ-lever-b-dependent-lengths`, `REQ-lever-c-induction`
- Lean tier: `REQ-lean-ga-layer1-translator`, `REQ-lean-ga-layer2-routing`, `REQ-lean-ga-layer3-transport`, `REQ-lean-ga-anti-laundering-guard`
- Obligations / spec text: `REQ-oblig-2`, `REQ-wildcard-semantics-spec`
- Patch/refine slicing: `REQ-r8-latency-benchmark`, `REQ-refine-slice`
- RFC-SWARM: `REQ-rfc-cov-1`, `REQ-ext-agent-1`, `REQ-swarm-1-concurrency-protocol`, `REQ-rfc-swarm-phase3-wave`, `REQ-rfc-swarm-phase4-refute-freeze`, `REQ-rfc-fourth-run-screening`, `REQ-rfc-swarm-barrier-field-backfill`, `REQ-rfc-swarm-harness-resubmit-protocol`
- SPEC-AGREE-1 (Rev 1, build order a–e plus open work): `REQ-spec-agree-1a-constructor-backend`, `REQ-spec-agree-1-effective-contract-and-verdicts`, `REQ-spec-agree-1-comparison-cli`, `REQ-spec-agree-1-gloss-experiment`, `REQ-spec-agree-1-nway-adversarial`, `REQ-spec-agree-1-stage-k-amendment`, `REQ-spec-agree-1-unrendered-defeater-question`, `REQ-spec-agree-1-basesorttext-feasibility`, `REQ-spec-agree-1-remeasure-comparable-fraction`
- Research track / other: `REQ-r1-indexed-dependent-types`, `REQ-r2-self-hosted-orchestrator`, `REQ-r4-synthetic-training-corpus`, `REQ-cascading-refinement-gating-question`, `REQ-mcp-integration`, `REQ-do-1-discard-warn-or-error`

Delta against the prior run (32): withdrew `REQ-ret-branch-pref-stage2` (folded into `REQ-ret-resolve`)
and the three Rev 0 `REQ-spec-agree-*` entries; added nine Rev 1 SPEC-AGREE-1 requirements and two
from the newly-synthesized playbook.

Seventeen requirements carry `acceptance: (absent)` because the source states none. Marked absent, not
inferred.

→ `.planning/intel/requirements.md`

## Constraints

**51 extracted** from the 12 SPEC docs. Type breakdown:

| Type | Count |
|---|---|
| nfr | 26 |
| protocol | 16 |
| api-contract | 5 |
| schema | 4 |

Entries a planner should read first: the `Sigma_auto` decidability boundary and the lever-by-lever
decidability table; the SAFE-ARG defect class and the WILD-ASSUME fix seam; the R8 soundness premises
P1/P2; the RFC-SWARM acceptance criterion, its per-phase STOP conditions, and the stage A–O
procedure with stage G2's token-not-substring rule and stage M's per-hole-lock / per-FILE-CAS
asymmetry; the six-clause RFC target admissibility criterion; the S0–S5 pipeline stages with the
C1–C6 clause taxonomy; and the three nested fragments (`Sigma_auto` ⊃ `Sigma_subsume` ⊃
`Sigma_witness`) that bound the agreement instrument at a measured 10.6%.

→ `.planning/intel/constraints.md`

## Context topics

**6 topics**, one per DOC-typed source: external critique triage and the routing table; SAFE-ARG (the
first non-fail-closed defect); the FQ-RESULT-SORT-1 two-round review; the RET-BRANCH-PREF
adjudication; the RET-RESOLVE four-round review; the SPEC-AGREE-1 review, now annotated with the
three figures Rev 1 supersedes by measurement.

→ `.planning/intel/context.md`

## Conflicts

| Bucket | Count |
|---|---|
| Blockers | 0 |
| Competing variants | 0 |
| Auto-resolved / informational | 20 |

Resolutions carried forward as INFO so they stay reversible:

- **INFO-1** — the prior BLOCKER-1 cross-reference cycle is resolved by manifest precedence (playbook 1, pipeline 2), transcribing what both docs declare. Not re-raised.
- **INFO-2 / INFO-3** — the prior WARNING-1 if-join fork is adjudicated to RET-RESOLVE SC3', authority `ret-resolve-proposal-review.md` Round 1 finding 1 (lines 19-27). The type-channel Stage 2 variant is withdrawn; Stage 1 (v0.14.72, self-recursion only) is not re-emitted.
- **INFO-4 through INFO-8** — the prior WARNING-2 SPEC-AGREE-1 scope contest is settled at Rev 1: domain `Sigma_subsume` per contract, `not-comparable` stays in the `Encoded` denominator, 10.6% measured as an upper bound, constructor backend in scope ahead of the harness with no Lever A dependency, `Sigma_witness` routed to compiler-engineer, effort corrected to medium-to-large, reporting as detection yield.
- **INFO-11 / INFO-12 / INFO-13 / INFO-18** — preserved from the prior run: the roadmap (precedence 0) supersedes stale status in `oblig-0-spec.md` and `critique-2026-05-23-triage.md`; the FQ-RESULT-SORT-1 "residual closed" phrasing reconciles; and two requirements have no backing roadmap row and need confirming before scheduling.
- **INFO-14 / INFO-15 / INFO-16 / INFO-17** — new precedence resolutions: proposal Rev 1 over the review on three measured points; the playbook over the pipeline doc on extraction discipline and stage vocabulary; the pipeline doc yields zero forward requirements (G1/G2/G4 closed, G3 accepted); and the unlanded stage K amendment does not displace the playbook's current text.

→ `.planning/INGEST-CONFLICTS.md` for the full report with sources per claim.

## Files

- `.planning/intel/decisions.md`
- `.planning/intel/requirements.md`
- `.planning/intel/constraints.md`
- `.planning/intel/context.md`
- `.planning/INGEST-CONFLICTS.md`
