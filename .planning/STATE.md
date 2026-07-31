---
gsd_state_version: '1.0'
status: planning
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-31)

**Core value:** A `verified` verdict means what it says; where the compiler cannot discharge an
obligation it names the gap rather than absorbing it.
**Current focus:** Phase 1, Close the map arm of WILD-ASSUME

## Current Position

Phase: 1 of 5 (Close the map arm of WILD-ASSUME)
Plan: 0 of 0 in current phase
Status: Ready to plan
Last activity: 2026-07-31 — Roadmap created from ingest of 18 design documents (45 requirements
extracted, 6 scoped into this milestone)

Progress: [░░░░░░░░░░] 0%

## Milestone

Compiler backlog, targeting v0.15. Released version at start: v0.14.73.
Every phase completes on a shipped release: CHANGELOG entry, version bump, `scripts/version_gate.sh`
exits 0.

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: n/a
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

## Accumulated Context

### Decisions

Zero decisions are LOCKED. The ingest set contained no ADR-typed document, so all 24 recorded
decisions sit at `status: proposed` (see PROJECT.md Key Decisions and
`.planning/intel/decisions.md`). Ones that bear on near-term work:

- The if-join wildcard preference ships as RET-RESOLVE SC3' (same-SCC conditioned); the
  RET-BRANCH-PREF Stage 2 type-channel variant is withdrawn. Reversible; INFO-2 / INFO-3.
- Contract-position reads are total selects; disposition is status quo plus a scoped non-blocking
  lint.
- Integer semantics option (a); `MachineInt` recorded dormant, scheduled anyway in Phase 5.
- Stale-binary detection uses `stack build --dry-run`, not the version string and not mtimes.

### Pending Todos

None yet.

### Blockers/Concerns

- **Acceptance criteria absent for three of six in-scope requirements** (`REQ-fact-ag`,
  `REQ-oblig-1-def-invariant`, `REQ-contract-read-lint-residual`). Their sources state none;
  nothing was invented. Author acceptance before planning Phases 3 and 4.
- **`REQ-int-3` is recorded dormant** by its own source (INT-PRE cleared the promotion gate at
  1.015x against a 5x threshold). Phase 5 overrides that; it is sequenced last as the drop
  candidate.
- **Phase 1 has a hard prerequisite**: the `(map-empty)` over-breadth fixture `SA-6` must be
  committed before the WILD-ASSUME discriminant widens, or every `(map-empty)` use breaks.
- **Phase 2 must not land before Phase 1.** The `resultLenFact` assumption-injection channel can
  turn a crash into `verified`.
- **Two deferred requirements have no backing roadmap row** (`REQ-do-1-discard-warn-or-error`,
  `REQ-rfc-swarm-harness-resubmit-protocol`). Confirm against the backlog of record before any
  future milestone schedules them.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Backlog | 39 requirements across 10 tracks | Tracked in REQUIREMENTS.md | 2026-07-31 (milestone scoping) |

## Session Continuity

Last session: 2026-07-31
Stopped at: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md written from ingest
Resume file: None
