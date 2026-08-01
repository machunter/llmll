---
gsd_state_version: 1.0
milestone: v0.15
milestone_name: milestone
current_phase: 01
current_phase_name: close-the-map-arm-of-wild-assume
status: verifying
stopped_at: Completed 01-03-PLAN.md (version-control step pending, blocked by subagent write hook)
last_updated: "2026-08-01T05:00:47.671Z"
last_activity: 2026-07-31
last_activity_desc: Phase 01 execution started
progress:
  total_phases: 1
  completed_phases: 1
  total_plans: 4
  completed_plans: 4
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-31)

**Core value:** A `verified` verdict means what it says; where the compiler cannot discharge an
obligation it names the gap rather than absorbing it.
**Current focus:** Phase 01 — close-the-map-arm-of-wild-assume

## Current Position

Phase: 01 (close-the-map-arm-of-wild-assume) — EXECUTING
Plan: 4 of 4
Status: Phase complete — ready for verification
Last activity: 2026-07-31 — Phase 01 execution started
plan-checked, VALIDATION.md written. Build hygiene verified clean (binary v0.14.73,
`stack build --dry-run` reports "Nothing to build.").

Progress: [████████░░] 75%

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
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 10min | 2 tasks | 2 files |
| Phase 01 P02 | 25min | 2 tasks | 1 files |
| Phase 01 P03 | 50min | 3 tasks | 2 files |

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
- [Phase ?]: SA-6 confirmed pre-existing/green (map[int,int]); SA-14 added as the fixture that actually reaches the map[int,bool] over-breadth hazard SA-6 does not cover
- [Phase ?]: Map-arm fixtures (SA-9, SA-14) live in a new sibling hspec describe block, not an extension of the bytes-arm block, keeping the bytes-arm block's title accurate
- [Phase ?]: requirements mark-complete REQ-wild-assume-2 skipped this plan: gsd-tools requirements.ready-ids reports it blocked pending sibling plans 01-02/01-03/01-04 SUMMARYs in the same phase
- [Phase ?]: SA-11's contingency did not fire: expandAlias/unify already alias-expand before assumesFact, so a laundered map[k,bool] behind a type alias is refused with zero TypeCheck.hs change; research open question 1 answered by measurement
- [Phase ?]: Type-alias surface form for a plain (non-where, non-sum) alias body is unparenthesized: (type Name map[k v]), not (type Name (map[k v])) -- the latter misparses via pType's pPairType alternative
- [Phase ?]: SA-8's liveness on the argument seam was proven by temporarily removing assumesFact's TMap clause (RED: reportSuccess expected False got True), then restoring it (zero net diff), not assumed from a single passing run
- [Phase ?]: checkerSoundnessVersion is NOT bumped: doVerify's type-check gate (Main.hs:1200-1204) runs before every sidecar-consuming render branch, and loadFromFile (Module.hs:190-205) discards the sidecar-merged env when a module's own type check fails, so a program the widened checker newly rejects can never surface a cached verdict; corroborated by a zero-delta corpus comparison against the 01-01 baseline
- [Phase ?]: wildAssumeFactNoun makes the WILD-ASSUME rejection message per-class (a length for bytes[n], a per-key value range for map[k,bool]), proven live by reverting the wording function (not the assumesFact clause) and confirming SA-16 goes RED

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

- Repo hook block-git-from-subagent.sh denies git-write subcommands from any Task-tool subagent; 01-01's changes (Spec.hs, TypeCheck.hs, SUMMARY.md, STATE.md) are staged/written on disk but need the calling agent to record them into version control

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Backlog | 41 requirements across 11 tracks | Tracked in REQUIREMENTS.md | 2026-07-31 (milestone scoping) |
| Requirement | `REQ-contract-read-wf-side-obligation` (Dafny-style WF side-obligation) | Split out of Phase 4; obligations track | 2026-07-31 (acceptance authoring) |
| Requirement | `REQ-int-3` (`MachineInt` QF-BV) | Scoped out of milestone; integer-semantics track | 2026-07-31 (promotion gate did not fire) |

## Session Continuity

Last session: 2026-08-01T03:20:44.598Z
Stopped at: Completed 01-03-PLAN.md (version-control step pending, blocked by subagent write hook)
Resume file: None
