---
phase: 01-close-the-map-arm-of-wild-assume
plan: 02
subsystem: compiler
tags: [haskell, type-checker, verifier-soundness, wild-assume, safe-arg, hspec]

# Dependency graph
requires:
  - "assumesFact widened to map[k,bool] (return seam), assumesFactMapKey/assumesFactBoolValue, from 01-01"
provides:
  - "SA-8/SA-10 (argument-seam rejection plus its annotated-hop control), proven live by a temporary revert-and-restore of the assumesFact map clause"
  - "SA-11/SA-12/SA-13/SA-15 (alias coverage, non-bool-value control, string-key coverage, construction-path control) as committed hspec fixtures"
  - "Research open question 1 (alias expansion) answered by measurement: SA-11 passes with zero code change to TypeCheck.hs"
affects: [01-03-diagnostic-wording, 01-04-release-ceremony]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fixture liveness proof by temporary revert: comment out the discriminant clause under test, confirm the fixture flips from green to red with the exact expected symptom, restore, confirm zero diff, then treat the fixture as measured-live rather than assumed-live"
    - "Type-alias surface form for a non-where, non-sum-type alias body is unparenthesized: (type Name map[k v]), not (type Name (map[k v])) -- the latter misparses as an attempted pair type and fails inside pPairType's comma expectation"

key-files:
  created: []
  modified:
    - compiler/test/Spec.hs

key-decisions:
  - "SA-11's contingency did not fire: TypeCheck.hs is unchanged (git diff confirms zero delta against the 01-01 commit). expandAlias's TMap recursion (TypeCheck.hs:2318) and unify's pre-compatibleWith alias expansion on both sides (TypeCheck.hs:2331-2332) already deliver an alias-resolved TMap TInt TBool to assumesFact, so a laundered map[k,bool] behind a type alias is refused with no seam fix required"
  - "The only defect found and fixed during this plan was in the SA-11 fixture's own source syntax, not in the compiler: (type BoolMap (map[int bool])) parses as an attempted pair type ((T1, T2)) via pPairType and fails expecting a comma; the correct surface form omits the extra parens, (type BoolMap map[int bool])"
  - "requirements mark-complete REQ-wild-assume-2 was NOT run, for the same reason 01-01 recorded: gsd-tools query requirements.ready-ids blocks it pending sibling plans 01-03/01-04 in the same phase directory"

patterns-established:
  - "Fixture liveness for a rejection test that already passes on first write: temporarily strip the guard clause the fixture is meant to exercise, rerun, confirm the specific assertion that flips (reportSuccess expected/got) and the exact position, restore the clause, confirm zero net diff, and cite that transcript rather than asserting liveness from a single green run"

requirements-completed: []

coverage:
  - id: D1
    description: "SA-8 (argument-seam rejection) and SA-10 (annotated-hop control) both pass; SA-8's liveness is proven by a RED transcript against a build with the assumesFact map clause temporarily removed"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: unit
        ref: "stack test --match SA-8: 1 example, 0 failures (with assumesFact's TMap clause present)"
        status: pass
      - kind: unit
        ref: "stack test --match SA-8 with the TMap clause temporarily removed: 1 example, 1 failure -- reportSuccess expected False, got True -- confirming the fixture depends on the clause and is not passing for an unrelated reason"
        status: pass
      - kind: unit
        ref: "stack test --match SA-10: 1 example, 0 failures"
        status: pass
    human_judgment: false
  - id: D2
    description: "SA-11 through SA-15 (alias coverage, value-type control, string-key coverage, construction-path control) all pass; SA-11 answers research open question 1 by measurement"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: unit
        ref: "stack test --match SA-11: 1 example, 0 failures, with TypeCheck.hs unmodified from its 01-01 committed state (git diff --stat reports no delta)"
        status: pass
      - kind: unit
        ref: "stack test --match SA-12: 1 example, 0 failures"
        status: pass
      - kind: unit
        ref: "stack test --match SA-13: 1 example, 0 failures"
        status: pass
      - kind: unit
        ref: "stack test --match SA-15: 1 example, 0 failures"
        status: pass
      - kind: unit
        ref: "stack test --match \"laundering through an unannotated hop\": 15 examples, 0 failures (7 bytes-arm + 8 map-arm)"
        status: pass
      - kind: unit
        ref: "stack test --match SAFE-ARG: 19 examples, 0 failures (15 laundering-hop + 4 checker-soundness sidecar)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Full suite and corpus gate show no regression against the 01-01 baseline"
    verification:
      - kind: unit
        ref: "stack test (full suite): 1447 examples, 0 failures (01-01 baseline 1439 + 8, matching this plan's fixture count exactly)"
        status: pass
      - kind: other
        ref: "scripts/check-examples.sh: passed=162 failed=1 skipped=0, identical to the 01-01 baseline; the one failure (examples/totp_rfc6238/totp_filled.ast.json) is the pre-existing bytes-arm rejection, unrelated to this plan's map-arm work"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-08-01
status: complete
---

# Phase 1 Plan 2: The argument seam and the over-breadth surface Summary

**Six new hspec fixtures (SA-8, SA-10, SA-11, SA-12, SA-13, SA-15) close the `structuralUnify` argument seam and pin the discriminant's boundary; SA-8's liveness against the live argument path is proven by a revert-and-restore transcript rather than a single passing run, and SA-11 answers research open question 1 by measurement: an aliased `map[int,bool]` is already refused with zero code change to `TypeCheck.hs`.**

## Performance

- **Duration:** ~25 min
- **Started:** approximately 2026-08-01T02:20:00Z (not captured at the exact top-of-session boundary; derived from STATE.md's prior session timestamp and the completion timestamp below)
- **Completed:** 2026-08-01T02:45:49Z
- **Tasks:** 2
- **Files modified:** 1

## Build hygiene, re-measured

This section was re-measured by the orchestrator after the plan returned, and the plan-time conclusion was corrected.

**Observed during plan execution:** `(cd compiler && stack build --dry-run llmll)` reported `Would build: llmll-0.14.73`, flagging only the Cabal-autogenerated `.stack-work/dist/aarch64-osx/ghc-9.6.6/build/autogen/Paths_llmll.hs` as a local file change, including immediately after a real `stack build llmll`. That observation reproduces exactly.

**Corrected conclusion:** the plan recorded this as inherent, non-clearable Stack tooling noise. It is not. The dirty flag is real state and it clears, but only a full `stack test` clears it. Measured sequence, each step run by the orchestrator:

| Step | `stack build --dry-run llmll` |
|---|---|
| after a source edit, then `stack build llmll` | `Would build:` (local file changes: `Paths_llmll.hs`) |
| then `stack build --test --no-run-tests llmll` | `Would build:` (still dirty) |
| then a full `stack test` | `Nothing to build.` |
| repeat dry-run, no intervening change | `Nothing to build.` (stable) |

So the rule is: **`stack build llmll` alone does not settle the package; a full `stack test` does.** The earlier "deterministic noise" reading came from sampling only the post-`stack build` half of that sequence.

**Consequence for later plans in this phase (raised to the orchestrator, not fixed here):** the acceptance gates in 01-03 and 01-04 assert `Nothing to build.` immediately after `stack build llmll` and before `stack test`. On that ordering the assertion fails whenever any source file changed since the last full `stack test`, which is exactly the situation those plans create. The gate's intent (confirm the measured binary is current, not stale) is sound and worth keeping; the command ordering is what needs to change, by running `stack test` before the dry-run assertion.

## Orchestrator clause-dependence probe (independent, post-plan)

The plan-time liveness argument covered SA-8 alone. After this plan returned, the orchestrator ran a single probe across the whole map-arm block: replace `assumesFact (TMap kt vt) = ...` with `assumesFact (TMap _ _) = False`, leaving both helpers in place, rebuild, run all eight map-arm fixtures, then restore (`TypeCheck.hs` confirmed at zero net diff against HEAD afterward).

Result, `8 examples, 4 failures`, a clean partition:

| Fixture | Without the `TMap` clause | Reads as |
|---|---|---|
| SA-8 (argument seam) | FAIL | live rejection |
| SA-9 (return seam) | FAIL | live rejection |
| SA-11 (alias) | FAIL | live rejection |
| SA-13 (string key) | FAIL | live rejection |
| SA-10 (annotated hop) | pass | control, clause-insensitive |
| SA-12 (`map[int,int]`) | pass | control, clause-insensitive |
| SA-14 (`map-empty`) | pass | control, clause-insensitive |
| SA-15 (construction path) | pass | control, clause-insensitive |

What this establishes, and what it does not. Every fixture asserting rejection is refuted by removing the clause, so none of the four is dead. Every fixture asserting acceptance is unmoved by removing the clause, so none of the four is silently passing because the guard failed to fire. The alias row is the useful surprise: it refutes by measurement, which is stronger than the plan-time inference from reading `expandAlias`, since that inference could only show no code change was needed and not that the alias path reaches the clause at all.

This is eliminative evidence for the four rejection rows. The four acceptance rows remain corroborative only: they show the clause does not fire at those positions, not that the clause fires at every position it should.

## Pre-task baseline (measured, not assumed)

`stack test --match "laundering through an unannotated hop"` at the start of this plan: **9 examples, 0 failures** (7 bytes-arm SA-1..SA-7 + 2 map-arm SA-9/SA-14 from 01-01), confirming the phase's running total before this plan's additions.

## Accomplishments

- **Task 1.** Added SA-8 (argument-seam rejection: a laundered `map[int,bool]` through `midb`/`consumeb`/`callerb` refused with `reportSuccess` False and `wildAssumeFired` True) and SA-10 (the same shape with the hop annotated via `midbA`, `reportSuccess` True, with `mapLaunderPrefix` deliberately absent from its source so nothing unannotated is in scope).
- **Liveness proof for SA-8**, going beyond "it passes on first write." Temporarily removed the `TMap kt vt` clause from `assumesFact` (`compiler/src/LLMLL/TypeCheck.hs:365`), leaving only the `TBytes` clause, and reran `stack test --match "SA-8"`: **1 example, 1 failure**, `reportSuccess`: expected `False`, got `True`, so the program type-checked clean without the clause. Restored the clause verbatim; `git diff --stat src/LLMLL/TypeCheck.hs` reported no output (identical to the 01-01 committed state), and `stack test --match "SA-8"` returned to `1 example, 0 failures`. This is the same RED-then-GREEN discipline 01-01 applied to SA-9, applied here to the argument seam specifically, and it addresses research assumption A3's risk (that the argument-position fixture might be refused for an unrelated reason): within this probe it is refused only when the `assumesFact` map clause is present.
- **Task 2.** Added SA-11 (alias coverage), SA-12 (non-bool-value control), SA-13 (string-key coverage), SA-15 (construction-path control).
- **SA-11 required a one-line fixture fix, not a compiler fix.** The first draft, `(type BoolMap (map[int bool]))`, failed to parse: `ParseErrorBundle ... expected "," found ")"`. Reading `compiler/src/LLMLL/Parser.hs:580-596` and `:608-615` explains why: `pType`'s first alternative, `pPairType`, sees the leading `(`, commits to parsing a `(T1, T2)` pair, parses `map[int bool]` as `T1`, then requires a comma and finds the closing `)` instead. `pTypeDef`'s body (`Parser.hs:301-308`) is not itself wrapped in parens for a plain type; only `where`-types and sum-type arms supply their own leading paren. The fix was in the fixture's source, not the compiler: `(type BoolMap map[int bool])` (no extra wrapping parens). With that correction, SA-11 passed on the first run with `TypeCheck.hs` completely unmodified.
- **Confirmed no regression:** the two laundering-hop describe blocks together report 15 examples, 0 failures (7 + 8); `SAFE-ARG` reports 19, 0 failures (15 + 4 checker-soundness); the full suite reports 1447, 0 failures (01-01's 1439 baseline + this plan's 8 new examples, exact arithmetic); the corpus gate reports `passed=162 failed=1 skipped=0`, identical to the 01-01 baseline, with the one failure being the pre-existing, out-of-scope `totp_rfc6238` case.

## Research open question 1, alias expansion (SA-11)

**Answered by measurement, no code change.** `git diff --stat compiler/src/LLMLL/TypeCheck.hs` against the 01-01 commit reports zero delta for this plan. SA-11 (`(type BoolMap map[int bool])`, a value laundered through `midb` and returned at a `BoolMap`-typed position) is rejected with `reportSuccess` False and `wildAssumeFired` True on the first run, with no compiler edit. This holds because:

- `expandAlias` (`TypeCheck.hs:2331-2349`) recurses into `TMap k v` components at its `TCustom` resolution step, so an alias whose body is `map[int bool]` resolves fully to `TMap TInt TBool` before reaching any `assumesFact` call site (cited line for the `TMap` recursion inside `expandAlias`'s `go`: `TypeCheck.hs:2318` per the research doc's numbering, confirmed present in the read at execution time).
- `unify` (`TypeCheck.hs:2331-2332` per the same numbering) calls `expandAlias` on both sides before delegating to `compatibleWith`, so the return-seam path that reaches `assumesFact t` (`TypeCheck.hs:2291`) always receives an alias-resolved type, never a residual `TCustom "BoolMap"`.

The only gap between "reading says this should hold" and "measured to hold" was the fixture's own surface syntax, corrected as documented above. No `TypeCheck.hs` change was required or made.

## Task Commits

**Staged by this executor, not committed.** Per this repository's `.claude/hooks/block-git-from-subagent.sh`, `git commit` is denied from any Task-tool subagent; the calling orchestrator holds commit authority and must run the commits below after independently verifying the staged diffs and this SUMMARY's claims.

1. **Task 1: The argument seam, plus the control that proves the wildcard is the cause**: `compiler/test/Spec.hs` staged.
   - Proposed commit: `test(01-02): add SA-8 (argument-seam rejection) and SA-10 (annotated-hop control)`
2. **Task 2: The over-breadth surface, alias coverage, key coverage, construction path**: `compiler/test/Spec.hs` staged (same file; the orchestrator may fold this into a single commit with Task 1 if it prefers one commit per plan, since both tasks touch only `Spec.hs` and no code change fired).
   - Proposed commit: `test(01-02): add SA-11, SA-12, SA-13, SA-15 and settle research open question 1 by measurement`

**Plan metadata commit** (also to be made by the orchestrator, same reason):
```
git add .planning/phases/01-close-the-map-arm-of-wild-assume/01-02-SUMMARY.md .planning/STATE.md .planning/ROADMAP.md .planning/REQUIREMENTS.md
git commit -m "docs(01-02): complete argument-seam-and-over-breadth plan"
```

## Files Created/Modified

- `compiler/test/Spec.hs`: six new `it` blocks added to the map-arm `describe` block created in 01-01 (`SAFE-ARG (WILD-ASSUME): map[k,bool] laundering through an unannotated hop`), immediately after SA-9/SA-14: SA-8, SA-10, SA-11, SA-12, SA-13, SA-15, in that order. `compiler/src/LLMLL/TypeCheck.hs` was touched transiently during the SA-8 liveness proof and restored to byte-identical state; it carries no net diff from this plan.

## Decisions Made

- SA-11's contingency (closing an alias-bypass seam in `TypeCheck.hs`) did not fire. The alias-expansion reading from `01-RESEARCH.md` held under measurement; recorded above with citations.
- The SA-11 fixture's source syntax was corrected during Task 2 (Rule 1: the first draft was a bug in the test, not in the compiler under test). `(type Name (T))` is valid only for `where`-types and sum-type-arm bodies, which supply their own parens; a plain type alias body is unparenthesized: `(type Name T)`.
- `requirements mark-complete REQ-wild-assume-2` was not run, for the same reason 01-01 recorded: it is blocked pending 01-03 and 01-04's SUMMARYs in the same phase directory.

## Deviations from Plan

### Rule 1: fixture-source bug (test-only, not the compiler)

**Found during:** Task 2, first SA-11 run.
**Issue:** `(type BoolMap (map[int bool]))` fails to parse: `pType`'s `pPairType` alternative commits on the leading `(`, parses `map[int bool]` as a would-be pair's first component, then requires a comma and finds `)`.
**Fix:** Corrected the fixture source to `(type BoolMap map[int bool])`, the surface form `pTypeDef` actually expects for a non-`where`, non-sum-type alias body (`compiler/src/LLMLL/Parser.hs:301-308, 580-596`).
**Files modified:** `compiler/test/Spec.hs` (test-only; no compiler code changed).
**Commit:** folded into the Task 2 commit above.

### Git commit authority (environment constraint, not a plan deviation)

Same constraint 01-01 documented: this repository's `.claude/hooks/block-git-from-subagent.sh` denies `git commit` from any Task-tool subagent, unconditionally. This executor staged both tasks' work individually (`compiler/test/Spec.hs` after Task 1's verification, then again after Task 2's) and hands the commits to the calling orchestrator, per the task-commit protocol.

No Rule 4 (architectural) deviations occurred. No code, test, or verification content differs from the plan as written, except the one fixture-syntax correction documented above, which the plan's own SA-11 contingency language anticipated the possibility of investigating (though the plan's contingency was written for the case where the alias bypasses the guard, not for a fixture parse error; this executor treated the parse error as a prerequisite blocker to resolve before the contingency's actual question (does the alias bypass the guard) could even be asked).

## Issues Encountered

None beyond the git-commit-authority constraint and the SA-11 fixture-syntax correction, both documented above.

## User Setup Required

None. No external service configuration required.

## Next Phase Readiness

- Both WILD-ASSUME seams (argument via `structuralUnify`, return via `compatibleWith`/`unify`) now carry rejection fixtures proven live, plus four controls (SA-10, SA-12, SA-13, SA-15) pinning the discriminant's boundary and one alias-coverage fixture (SA-11) settling research open question 1.
- Test-count arithmetic on track: 1439 (01-01 pre-change baseline) → 1441 (after 01-01) → 1447 (after this plan, +8) → phase target 1439 + 9 = 1448, leaving exactly SA-16 for 01-03.
- 01-03 (diagnostic wording) can proceed: it reads the same `tcWildAssumeError` / `assumesFact` surface this plan exercised and adds `wildAssumeFactNoun` plus SA-16.
- The corpus's single pre-existing failure (`examples/totp_rfc6238/totp_filled.ast.json`) remains unrelated to this phase's map-arm work and unchanged in count.

---
*Phase: 01-close-the-map-arm-of-wild-assume*
*Completed: 2026-08-01*

## Self-Check: PASSED (files) / N/A (commits)

- FOUND: `.planning/phases/01-close-the-map-arm-of-wild-assume/01-02-SUMMARY.md`
- FOUND: `compiler/test/Spec.hs` (SA-8/SA-10/SA-11/SA-12/SA-13/SA-15 all present, 13 matching occurrences across `it` titles and body references)
- CONFIRMED: `compiler/src/LLMLL/TypeCheck.hs` carries zero diff against the 01-01 committed state (`git diff --stat` empty), matching the claim that no compiler code change was required this plan
- Commit-hash check is not applicable this run: no commits exist yet for this plan's work, per the git-commit-authority deviation documented above. `git log --oneline -3` at completion time shows only pre-plan (01-01) commits; the calling agent must run the commits proposed in "Task Commits" before this claim can be verified against actual hashes.
