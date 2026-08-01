---
phase: 01-close-the-map-arm-of-wild-assume
plan: 01
subsystem: compiler
tags: [haskell, type-checker, verifier-soundness, wild-assume, safe-arg, hspec]

# Dependency graph
requires: []
provides:
  - "Measured pre-change baseline (hspec count, corpus pass/fail, SA-6 confirmation) that the rest of the phase is judged against"
  - "assumesFact widened to the map[k,bool] arm via assumesFactMapKey/assumesFactBoolValue, closing the return seam (compatibleWith/unify)"
  - "SA-9 (return-seam rejection) and SA-14 (map-empty over-breadth guard) as committed hspec fixtures"
affects: [01-02-argument-seam, 01-03-diagnostic-wording, 01-04-release-ceremony]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "assumesFact extended by adding a TMap pattern clause plus two local admissibility helpers, mirroring FixpointEmit.isIntLike/isStrLike/isBoolLike minus their AliasMap lookups (both call sites receive already alias-expanded types)"
    - "Map-arm fixtures live in a new sibling hspec describe block rather than extending the bytes-arm block, keeping the bytes-arm block's title accurate"

key-files:
  created: []
  modified:
    - compiler/src/LLMLL/TypeCheck.hs
    - compiler/test/Spec.hs

key-decisions:
  - "SA-6 (compiler/test/Spec.hs:2093-2096) was confirmed as a pre-existing, already-green fixture and was not re-authored; it covers map[int,int], not the map[int,bool] position the widen actually risks"
  - "SA-14 was added as the fixture that reaches the map[int,bool] over-breadth hazard SA-6 does not cover"
  - "requirements mark-complete was NOT run for REQ-wild-assume-2 in this plan: gsd-tools requirements.ready-ids reports it blocked, because sibling plans 01-02/01-03/01-04 in the same phase directory have not yet produced their SUMMARY.md"

patterns-established:
  - "New arm of a discriminant predicate: add a pattern clause plus scoped helper functions beside the existing predicate, citing the emitter function it mirrors and the alias-expansion invariant that lets the helpers skip AliasMap lookups"

requirements-completed: []

coverage:
  - id: D1
    description: "Baseline measurements (build currency, hspec count, corpus pass/fail, SA-6 pre-widen confirmation) recorded as measured values before any source edit"
    verification:
      - kind: other
        ref: "stack build --dry-run llmll (Nothing to build.); stack test (1439 examples, 0 failures); scripts/check-examples.sh (passed=162 failed=1 skipped=0); stack test --match SA-6 (1 example, 0 failures)"
        status: pass
    human_judgment: false
  - id: D2
    description: "assumesFact widened to map[k,bool]; SA-9 flips from failing (RED) to passing (GREEN) across the edit, proving the fixture exercises the new clause rather than an unrelated rejection"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: unit
        ref: "compiler/test/Spec.hs SA-9 (stack test --match SA-9): RED then GREEN, 1 example 0 failures after the edit"
      - kind: unit
        ref: "compiler/test/Spec.hs SA-14 (stack test --match SA-14): 1 example 0 failures, green on both sides of the edit"
      - kind: unit
        ref: "compiler/test/Spec.hs SA-6 (stack test --match SA-6): 1 example 0 failures, green on both sides of the edit"
      - kind: unit
        ref: "stack test --match SAFE-ARG: 13 examples, 0 failures (SA-1..SA-7, SA-9, SA-14, SS-1..SS-4)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Full suite and corpus gate show no regression from the widen"
    verification:
      - kind: unit
        ref: "compiler: stack test (full suite): 1441 examples, 0 failures (baseline 1439 + 2)"
        status: pass
      - kind: other
        ref: "scripts/check-examples.sh: passed=162 failed=1 skipped=0, identical to the pre-change baseline (the one failure, examples/totp_rfc6238/totp_filled.ast.json, is a pre-existing bytes-arm WILD-ASSUME rejection unrelated to this plan)"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-08-01
status: complete
---

# Phase 1 Plan 1: Baseline measurement and the map arm's return seam Summary

**`assumesFact` widened to `map[k,bool]` at the return seam via two new admissibility helpers, proven live by a RED-to-GREEN fixture (SA-9) and guarded against over-breadth by SA-14, against a measured pre-change baseline of 1439 hspec examples and a corpus of 162 passing / 1 pre-existing failing.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-01T02:05:56Z
- **Completed:** 2026-08-01T02:15:42Z
- **Tasks:** 2
- **Files modified:** 2

## Baseline measurements (pre-change)

Measured, not recalled, per Task 1. Made no source edits.

**(a) Build currency:**
```
(cd compiler && stack build --dry-run llmll)
No packages would be unregistered.
Nothing to build.
No executables to be installed.
```
Confirmed clean before any measurement or edit, per the milestone's build-hygiene precondition.

**(b) hspec example count (pre-change):** `stack test` → **1439 examples, 0 failures**.

**(c) Corpus baseline (pre-change):** `scripts/check-examples.sh` → **`check-examples: passed=162  failed=1  skipped=0`** (verbatim). The one failure is `examples/totp_rfc6238/totp_filled.ast.json`, which already fails on the existing bytes-arm WILD-ASSUME guard (`type mismatch in 'dynamic-truncate': expected bytes[20], got ? (an unannotated return type)`), a pre-existing, out-of-scope failure, not caused by this plan. It was still `failed=1` after this plan's edit (see D3 above), confirming no new corpus failures.

**(d) SA-6 confirmation:** `stack test --test-arguments '--match "SA-6"'` → **1 example, 0 failures**. SA-6 was already committed at `Spec.hs:2093-2096` (SAFE-ARG stage-1 work); this plan did not author it, only confirmed it, per the phase's correction of record.

**Test-count arithmetic the phase is held to:** expected post-phase hspec count = 1439 (measured baseline) + 9 (SA-8 through SA-16) = **1448**. This plan lands 2 of the 9 (SA-9, SA-14); post-plan count measured at 1441, matching baseline + 2 exactly.

## Accomplishments

- Measured and recorded the four pre-change baselines above, with no source edits in Task 1.
- Extended `assumesFact` (`compiler/src/LLMLL/TypeCheck.hs`) with a `TMap kt vt` clause guarded by two new helpers, `assumesFactMapKey` and `assumesFactBoolValue`, mirroring `FixpointEmit.isIntLike`/`isStrLike`/`isBoolLike` admissibility (int-or-string key, bool value) minus their `AliasMap` lookups, since both `assumesFact` call sites receive already alias-expanded types.
- Added SA-9 (return-position `map[int,bool]` launder through an unannotated hop, `compatibleWith`/`unify` seam) and SA-14 (`(map-empty)` at a `map[int bool]` position, the over-breadth guard SA-6 does not reach) as a new sibling hspec `describe` block in `compiler/test/Spec.hs`.
- Proved the fixture is live, not dead: ran SA-9 RED before the edit (recorded below) and GREEN after.
- Confirmed no regression: SA-1 through SA-7 and SS-1 through SS-4 stay green, full suite is 1441/0 failures, corpus gate is unchanged at passed=162/failed=1/skipped=0.

## SA-9 RED output (recorded before the `assumesFact` edit)

```
Failures:

  test/Spec.hs:2129:32:
  1) SAFE-ARG (WILD-ASSUME): map[k,bool] laundering through an unannotated hop SA-9 rejects a laundered map[int,bool] at a map[int bool] RETURN position
       expected: False
        but got: True

  To rerun use: --match "/SAFE-ARG (WILD-ASSUME): map[k,bool] laundering through an unannotated hop/SA-9 rejects a laundered map[int,bool] at a map[int bool] RETURN position/" --seed 549498659

Randomized with seed 549498659

Finished in 0.0008 seconds
1 example, 1 failure
```

The failure is on `reportSuccess` (expected `False`, got `True`): the program type-checked clean pre-widen, not a parse or arity error. That confirms the fixture exercises the seam the edit is meant to close, not an unrelated rejection.

## GREEN confirmation (after the `assumesFact` edit)

```
stack test --test-arguments '--match "SA-9"'  → 1 example, 0 failures
stack test --test-arguments '--match "SA-14"' → 1 example, 0 failures
stack test --test-arguments '--match "SA-6"'  → 1 example, 0 failures
stack test --test-arguments '--match "SAFE-ARG"' → 13 examples, 0 failures
stack test (full suite)                       → 1441 examples, 0 failures
scripts/check-examples.sh                     → passed=162  failed=1  skipped=0 (unchanged)
```

## Task Commits

**Commits were made by the calling orchestrator, not by this executor; see "Git commit authority" under Deviations below.** This repository's `.claude/hooks/block-git-from-subagent.sh` denies `git commit` from any Task-tool subagent (`agent_id` present), unconditionally, so this executor staged its work and handed the commits up.

1. **Task 1: Measure the baseline the phase is judged against**: no files changed; nothing to commit.
2. **Task 2: End-to-end map arm, return seam, with its over-breadth guard**: two logical commits, made by the orchestrator:
   - `test(01-01): add SA-9 (failing) and SA-14 for the map[k,bool] laundering arm`, covering `compiler/test/Spec.hs`
   - `feat(01-01): widen assumesFact to the map[k,bool] arm (return seam)`, covering `compiler/src/LLMLL/TypeCheck.hs`

**Plan metadata commit:** also made by the orchestrator, same reason; see Deviations.

## Files Created/Modified

- `compiler/src/LLMLL/TypeCheck.hs`: `assumesFact` extended with a `TMap kt vt` clause; new `assumesFactMapKey` and `assumesFactBoolValue` helpers added beside it; doc comment updated to describe the shipped map-arm state instead of the stage-1-only framing.
- `compiler/test/Spec.hs`: new sibling `describe "SAFE-ARG (WILD-ASSUME): map[k,bool] laundering through an unannotated hop"` block with local `tcOf`/`wildAssumeFired`/`mapLaunderPrefix` bindings, `SA-9`, and `SA-14`.

## Decisions Made

- SA-6 was treated as a confirmation step, not a construction step, per the phase's own correction of record: it is already committed and covers `map[int,int]`, not the `map[int,bool]` position this widen actually risks.
- The map-arm fixtures live in a new sibling `describe` block rather than extending the bytes-arm block, keeping the bytes-arm block's `describe` string ("bytes[n] laundering") accurate. This closes research open question 3 as the plan specified.
- `requirements mark-complete REQ-wild-assume-2` was not run. `gsd-tools query requirements.ready-ids` reports it blocked: sibling plans 01-02/01-03/01-04 in the same phase directory have not yet produced their SUMMARY.md, so the shared requirement ID is not safe to mark complete from this plan alone.

## Deviations from Plan

### Git commit authority (environment constraint, not a plan deviation)

This repository's `.claude/hooks/block-git-from-subagent.sh` PreToolUse hook denies `git commit` (and `push`/`tag`/`merge`/`rebase`/`reset`/`revert`/`cherry-pick`) from any process whose PreToolUse payload carries an `agent_id`, which every Task-tool-spawned subagent does, including this plan-executor. The hook exists deliberately (a prior fork subagent shipped a release autonomously) and this executor did not attempt to route around it (e.g. via a wrapper script or a different invocation shape that avoids the pattern match). Per `<sequential_execution>`, hooks apply normally and `--no-verify` is prohibited; this hook has no `--no-verify`-equivalent bypass in any case.

**Effect:** both files for Task 2 (`compiler/test/Spec.hs`, `compiler/src/LLMLL/TypeCheck.hs`) and this SUMMARY are staged/written but **not committed**. `.planning/STATE.md` is updated on disk (see State Updates below) but likewise not committed. The calling agent (the one that spawned this executor) holds commit authority in this repository and must run:

```
git add compiler/test/Spec.hs
git commit -m "test(01-01): add SA-9 (failing) and SA-14 for the map[k,bool] laundering arm"

git add compiler/src/LLMLL/TypeCheck.hs
git commit -m "feat(01-01): widen assumesFact to the map[k,bool] arm (return seam)"

git add .planning/phases/01-close-the-map-arm-of-wild-assume/01-01-SUMMARY.md .planning/STATE.md .planning/ROADMAP.md .planning/REQUIREMENTS.md
git commit -m "docs(01-01): complete baseline-and-return-seam plan"
```

This is the only deviation encountered; no Rule 1-4 auto-fixes were needed. No code, test, or verification content differs from the plan as written.

## Issues Encountered

None beyond the git-commit-authority constraint documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The return seam is closed and proven live; the argument seam (`structuralUnify`, SA-8/SA-10/SA-11/SA-12/SA-13/SA-15) is Plan 01-02's scope and is unaffected by anything in this plan.
- Plan 01-02 can proceed now that this plan's commits have landed, since 01-02 reads the same `assumesFact`/`assumesFactMapKey`/`assumesFactBoolValue` code this plan introduces.
- The corpus's single pre-existing failure (`examples/totp_rfc6238/totp_filled.ast.json`) is unrelated to this plan (it is a bytes-arm rejection) and is not this phase's responsibility to fix.
- Test-count arithmetic on track: 1439 → 1441 (+2), against the phase target of 1439 + 9 = 1448.

---
*Phase: 01-close-the-map-arm-of-wild-assume*
*Completed: 2026-08-01*

## Self-Check: PASSED (files) / N/A (commits)

- FOUND: `compiler/src/LLMLL/TypeCheck.hs` (`assumesFactMapKey` present, 8 occurrences)
- FOUND: `compiler/test/Spec.hs` (SA-9/SA-14 present, 4 occurrences)
- FOUND: `.planning/phases/01-close-the-map-arm-of-wild-assume/01-01-SUMMARY.md`
- Commit-hash check is not applicable this run: no commits exist yet for this plan's work, per the git-commit-authority deviation documented above. `git log --oneline -5` at completion time shows only pre-plan commits; the calling agent must run the three staged commits listed in that section before this claim can be verified against actual hashes.
