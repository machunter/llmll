---
gsd_state_version: '1.0'
status: ready-to-execute
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 4
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

Phase: 1 of 4 (Close the map arm of WILD-ASSUME)
Plan: 0 of 4 in current phase
Status: Ready to execute — `/gsd-execute-phase 1`
Last activity: 2026-07-31 — Phase 1 planned: 4 plans across 4 sequential waves, researched,
plan-checked, VALIDATION.md written. Build hygiene verified clean (binary v0.14.73,
`stack build --dry-run` reports "Nothing to build.").

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
- Integer semantics option (a); `MachineInt` recorded dormant, and the milestone now honors that:
  `REQ-int-3` was scoped out on 2026-07-31 and returned to the deferred backlog.
- Stale-binary detection uses `stack build --dry-run`, not the version string and not mtimes.

### Pending Todos

None yet.

### Blockers/Concerns

- ~~Acceptance criteria absent for three of five in-scope requirements.~~ **RESOLVED 2026-07-31.**
  `REQ-fact-ag`, `REQ-oblig-1-def-invariant`, and `REQ-contract-read-lint-residual` now carry
  acceptance authored on 2026-07-31 and ratified by the user; `.planning/REQUIREMENTS.md` is their
  authority, not `docs/compiler-team-roadmap.md`. Two scope calls came with it: FACT-AG measures the
  type-derived fact set and closes every class it finds, and the Dafny-style well-formedness
  side-obligation split out of Phase 4 into the deferred backlog.
- **Phase 1's criterion 1 was aiming at a hazard its own fixture does not reach.** SA-6 is committed
  and green, but it asserts `(def-shell m [k: int] -> map[int int] (map-empty))`, whose value
  component is `int`. `assumesFact` returns False for it both before and after the widen, so SA-6
  cannot exercise the widened clause. The `(map-empty)` position the widen actually risks is
  `map[int bool]`, which no committed fixture covered. Plan 01-01 adds SA-14 for it and keeps SA-6
  for criterion 1 as literally worded. Criterion 1 as written would have passed while leaving the
  real risk untested.
- **A wrong diagnostic would have shipped with the widen.** `tcWildAssumeError`
  (`TypeCheck.hs:405-406`) tells the user the value "carries a length", true for the bytes arm and
  false for maps. Plan 01-03 adds `wildAssumeFactNoun` and SA-16 to hold both arms to accurate
  wording.
- ~~Phase 1 has a hard prerequisite~~ **(superseded by the two items above; retained for context)**: the `(map-empty)` over-breadth fixture `SA-6` must be
  committed before the WILD-ASSUME discriminant widens, or every `(map-empty)` use breaks.
- **Phase 2 must not land before Phase 1.** The `resultLenFact` assumption-injection channel can
  turn a crash into `verified`.
- **Two deferred requirements have no backing roadmap row** (`REQ-do-1-discard-warn-or-error`,
  `REQ-rfc-swarm-harness-resubmit-protocol`). Confirm against the backlog of record before any
  future milestone schedules them.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Backlog | 41 requirements across 11 tracks | Tracked in REQUIREMENTS.md | 2026-07-31 (milestone scoping) |
| Requirement | `REQ-contract-read-wf-side-obligation` (Dafny-style WF side-obligation) | Split out of Phase 4; obligations track | 2026-07-31 (acceptance authoring) |
| Requirement | `REQ-int-3` (`MachineInt` QF-BV) | Scoped out of milestone; integer-semantics track | 2026-07-31 (promotion gate did not fire) |

## Session Continuity

Last session: 2026-07-31
Stopped at: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md written from ingest
Resume file: None
