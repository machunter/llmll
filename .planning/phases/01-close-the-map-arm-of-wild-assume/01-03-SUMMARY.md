---
phase: 01-close-the-map-arm-of-wild-assume
plan: 03
subsystem: compiler
tags: [haskell, type-checker, verifier-soundness, wild-assume, safe-arg, hspec, diagnostics]

# Dependency graph
requires:
  - "assumesFact widened to map[k,bool] at both seams (structuralUnify, compatibleWith/unify), from 01-01 and 01-02"
provides:
  - "wildAssumeFactNoun: the per-class noun phrase tcWildAssumeError interpolates, so the map arm's rejection names a per-key value range instead of the bytes-only length wording"
  - "SA-16, asserting the map arm and the bytes arm each carry an accurate noun phrase in one committed example"
  - "A measured corpus and suite comparison against the 01-01 baseline: 1448 hspec examples (baseline + 9), corpus passed=162 failed=1 skipped=0, unchanged"
  - "The checkerSoundnessVersion epoch decision, settled on a cited reading of the verify entry path plus the zero-delta corpus comparison: do not bump"
affects: [01-04-release-ceremony]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A discriminant-driven diagnostic's message text is itself a per-class function (wildAssumeFactNoun), not a hardcoded string, so widening the discriminant's class coverage and widening the message's accuracy are the same edit rather than two"
    - "Diagnostic-wording liveness probe: revert the wording function to its pre-change form (not the type-checker clause it describes), rebuild, confirm the specific assertion goes RED, restore, confirm zero net diff -- distinct from a clause-liveness probe because the code path being tested never rejects or accepts differently, only what it SAYS changes"

key-files:
  created: []
  modified:
    - compiler/src/LLMLL/TypeCheck.hs
    - compiler/test/Spec.hs

key-decisions:
  - "checkerSoundnessVersion is NOT bumped. Evidence: (a) Main.hs's doVerify loads the entry sidecar (loadVerified, :1194) BEFORE the type-check gate (:1200-1204, unless (reportSuccess tcReport) $ ... exitFailure), and every sidecar-consuming branch (--trust-report :1214+, --spec-coverage :1258+, the no-solver --obligation-report :1381+, and the full solver path that runs after) sits AFTER that gate in the same function body, so a program the widened checker newly rejects can never reach a branch that renders a cached verdict -- doVerify exits failure first. (b) Module.hs's loadFromFile also merges a module's own sidecar into its env unconditionally (:194-198) but only RETURNS that merged env if the module's own hardErrors list is empty (:202-205); a module that newly fails to type-check returns Left and the merge is discarded by every importer. (c) Task 2's corpus comparison is a zero-delta: passed=162 failed=1 skipped=0, identical to the 01-01 baseline, and the one failure (examples/totp_rfc6238/totp_filled.ast.json) is the same pre-existing bytes-arm case as every prior plan in this phase, not a newly-failing example. Neither of the rule's two bump conditions holds, so the code state (VerifiedCache.hs untouched, no SS-5) matches a not-bump decision measured against both a cited code reading and a corpus re-run, not against the research doc's assumed reasoning."
  - "requirements mark-complete REQ-wild-assume-2 was not run, for the same reason 01-01 and 01-02 recorded: gsd-tools query requirements.ready-ids blocks it pending sibling plan 01-04's SUMMARY in the same phase directory."

patterns-established:
  - "wildAssumeFactNoun :: Type -> Text is total (a neutral 'a fact' fallback), mirroring assumesFact's own totality, so a future assumesFact arm cannot silently produce an unhandled-pattern crash in the diagnostic path even before its noun phrase is written."

requirements-completed: []

coverage:
  - id: D1
    description: "wildAssumeFactNoun added: per-class noun phrase (length for bytes[n], per-key value range for map[k,bool], neutral fallback otherwise), interpolated into tcWildAssumeError's message in place of the hardcoded length wording"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: unit
        ref: "stack test --match SA-16: 1 example, 0 failures"
        status: pass
      - kind: unit
        ref: "stack test --match \"laundering through an unannotated hop\": 16 examples, 0 failures (7 bytes-arm + 9 map-arm)"
        status: pass
      - kind: unit
        ref: "SA-16 liveness: reverted wildAssumeFactNoun to a single case returning \"a length\" for every type, rebuilt, reran SA-16: 1 example, 1 failure at test/Spec.hs:2235:13, first assertion (any (isInfixOf \"per-key value range\") ... shouldBe True) reporting expected True, got False -- confirms the example depends on the per-class wording, not on an unrelated pass. Restored the two-clause version; git diff against the staged index reported zero output (byte-identical); rebuilt and reran: 16 examples, 0 failures."
        status: pass
      - kind: unit
        ref: "stack test --match SA-3: 1 example, 0 failures -- an ordinary mismatch still does not report the WILD-ASSUME text"
        status: pass
    human_judgment: false
  - id: D2
    description: "Corpus and suite re-measured against a rebuilt binary and compared to the 01-01 baseline"
    verification:
      - kind: other
        ref: "(cd compiler && stack build llmll) then a full (cd compiler && stack test): 1448 examples, 0 failures, then (cd compiler && stack build --dry-run llmll) reported Nothing to build."
        status: pass
      - kind: other
        ref: "scripts/check-examples.sh: passed=162 failed=1 skipped=0, identical to the 01-01 baseline; the one failure (examples/totp_rfc6238/totp_filled.ast.json) is the same pre-existing bytes-arm rejection every prior plan recorded, now rendering the updated \"carries a length\" wording (confirming the message change reached a real corpus program, not only the hspec fixtures)"
        status: pass
    human_judgment: false
  - id: D3
    description: "checkerSoundnessVersion epoch question settled on a cited reading of the verify entry path plus the corpus comparison"
    verification:
      - kind: other
        ref: "app/Main.hs:1194-1385 (doVerify: entry sidecar load, type-check gate, and every sidecar-consuming render branch) and src/LLMLL/Module.hs:190-205 (loadFromFile: per-module sidecar merge gated by that module's own hardErrors), cited above under key-decisions"
        status: pass
      - kind: unit
        ref: "stack test --match checker_soundness_version: 4 examples, 0 failures (SS-1..SS-4, unchanged; no SS-5 added)"
        status: pass
    human_judgment: false

duration: ~50min
completed: 2026-07-31
status: complete
---

# Phase 1 Plan 3: The diagnostic names the fact, the corpus and epoch are measured Summary

**`wildAssumeFactNoun` makes the WILD-ASSUME rejection name a per-key value range for the map arm and a length for the bytes arm (previously a hardcoded length wording for both), proven live by reverting the wording function rather than the type-checker clause; the corpus and suite are re-measured at 1448 examples / passed=162 failed=1 skipped=0 (both unchanged from the 01-01 baseline's shape, the suite up by exactly 9); and `checkerSoundnessVersion` is NOT bumped, on a cited reading of `doVerify`'s type-check gate plus the zero-delta corpus comparison.**

## Performance

- **Duration:** approximately 50 min
- **Completed:** 2026-07-31
- **Tasks:** 3
- **Files modified:** 2 (`compiler/src/LLMLL/TypeCheck.hs`, `compiler/test/Spec.hs`); `compiler/src/LLMLL/VerifiedCache.hs` read but not modified, per the epoch decision

## Accomplishments

- **Task 1.** Added `wildAssumeFactNoun :: Type -> Text` directly above `tcWildAssumeError`: `TBytes _` returns `"a length"`, a type meeting the same admissibility `assumesFact`'s map clause already uses (`assumesFactMapKey`/`assumesFactBoolValue`) returns `"a per-key value range"`, and a neutral `"a fact"` fallback keeps the function total. Rewrote `tcWildAssumeError`'s `msg` binding to interpolate `wildAssumeFactNoun expected` in place of the hardcoded `"a length"` clause, leaving the opening clause, the `got ? (an unannotated return type)` parenthetical, and the closing remedy sentence unchanged. Added SA-16 to the map-arm `describe` block, asserting on `diagMessage` that the map arm's rejection contains `"per-key value range"` and, on the existing SA-2 bytes-arm source, that its rejection still contains `"a length"`, one example holding both arms to accurate wording.
- **Task 2.** Rebuilt (`stack build llmll`), ran the full suite (`stack test`: 1448 examples, 0 failures), then confirmed `stack build --dry-run llmll` reported `Nothing to build.`, then ran `scripts/check-examples.sh` (`passed=162 failed=1 skipped=0`). Both counts match the 01-01 baseline's shape exactly: the suite is baseline (1439) + 9, and the corpus's single failure is the same pre-existing `totp_rfc6238/totp_filled.ast.json` case every prior plan in this phase recorded, its `llmll check` output now reads `... value carries a length that the verifier asserts ...`, confirming Task 1's wording reached a real corpus program, not only the new hspec fixtures.
- **Task 3.** Read `app/Main.hs`'s `doVerify` (`:1170-1385` region) and `src/LLMLL/Module.hs`'s `loadFromFile` (`:166-205`) to answer whether a cached `verified` sidecar can be reported for a program the widened checker now rejects. It cannot, in both entry paths measured. Neither of the plan's two bump conditions holds (no corpus example flipped pass→fail; the sidecar read is gated by a successful type check, not unguarded), so `checkerSoundnessVersion` is not bumped and `VerifiedCache.hs` carries no diff.
- Ran the SA-16 liveness probe: temporarily collapsed `wildAssumeFactNoun` to a single case returning `"a length"` for every type (reverting the wording, not the `assumesFact` type-checker clause, since SA-16 tests a diagnostic message), rebuilt, and confirmed SA-16 went RED (recorded below). Restored the two-clause version, confirmed `git diff` against the staged index was empty, rebuilt, and confirmed the map-arm block returned to `16 examples, 0 failures`.

## SA-16 liveness: RED transcript (wording reverted, not the type-checker clause)

```
test/Spec.hs:2235:13:
  1) SAFE-ARG (WILD-ASSUME): map[k,bool] laundering through an unannotated hop SA-16 names the value-range fact for the map arm and the length fact for the bytes arm
       expected: True
        but got: False

  To rerun use: --match "/SAFE-ARG (WILD-ASSUME): map[k,bool] laundering through an unannotated hop/SA-16 names the value-range fact for the map arm and the length fact for the bytes arm/" --seed 1681687116

1 example, 1 failure
```

The failing assertion is the first one in SA-16's body: `any (T.isInfixOf "per-key value range" . diagMessage) (reportDiagnostics report) \`shouldBe\` True`, expected `True`, got `False`. With `wildAssumeFactNoun` collapsed to always return `"a length"`, the map-arm rejection's message no longer contains the phrase SA-16's map-arm assertion depends on, confirming the example is exercising the per-class wording rather than passing for an unrelated reason. After restoring `wildAssumeFactNoun`'s two-clause form, `git diff` against the staged index (`compiler/src/LLMLL/TypeCheck.hs`) reported no output, and a rebuild plus rerun returned the combined match to `16 examples, 0 failures`.

## Post-change measurements

| Measurement | 01-01 baseline | This plan (post-change) | Delta |
|---|---|---|---|
| `stack build --dry-run llmll`, after a full `stack test` | `Nothing to build.` | `Nothing to build.` | none (stable, confirmed after the rebuild the source edits required) |
| `stack test` (full suite) | 1439 examples, 0 failures | 1448 examples, 0 failures | +9 (SA-8 through SA-16, matching the phase's held arithmetic exactly) |
| `scripts/check-examples.sh` | `passed=162 failed=1 skipped=0` | `passed=162 failed=1 skipped=0` | none |
| Corpus verdict-flip check (per example) | `examples/totp_rfc6238/totp_filled.ast.json` fails (bytes-arm, pre-existing) | same single example fails, same cause | none; no example moved from passed to failed |

Framed per ROADMAP criterion 4: this is a regression check, not evidence the map-arm fix works on its own terms. There is no known-exploitable corpus program for it to have fixed, and none was found. It shows the widen and the wording change introduced no new corpus failure and no suite regression, nothing more.

## checker_soundness_version decision

**Decision: do NOT bump.** `checkerSoundnessVersion` in `compiler/src/LLMLL/VerifiedCache.hs:326` stays `"1"`; the file carries no diff from this plan.

**The question.** Can a `verified` verdict written by a pre-this-plan binary still be reported by this binary for a program that this binary's widened type checker now rejects?

**Evidence, the verify entry path (`app/Main.hs`).** `doVerify` loads the entry file's own `.verified.json` sidecar at `:1194` (`entrySidecarRaw <- loadVerified fp`), before the type-check gate. The gate itself runs at `:1200-1204`:

```haskell
let (tcReport, retTypes) =
      typeCheckStrictWithCacheAndStatusRet gm _cache entrySidecar emptyEnv stmts
unless (reportSuccess tcReport) $ do
  mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics tcReport)
  exitFailure
```

Every branch of `doVerify` that renders a cached verdict to a consumer sits AFTER this gate in the same function body: `--trust-report` at `:1214` onward, `--spec-coverage` at `:1258` onward, the no-solver-found `--obligation-report` degradation at `:1381`, and the full solver path (constraint emission, `.fq` write, `--strict-verified-core`, and the liquid-fixpoint run itself) that follows. A program the widened `assumesFact` newly rejects fails `reportSuccess tcReport` and `exitFailure`s at `:1204`, before any of those branches runs; the cached sidecar is loaded into memory but never reaches a rendering path.

**Evidence, the module-import path (`src/LLMLL/Module.hs`).** `loadFromFile` merges a module's own sidecar into its `ModuleEnv` unconditionally (`:194-198`, `sidecar <- loadVerified fp; ... meContractStatus = Map.unionWith mergeCS sidecar ...`), but that merged env is only returned to the caller when the module's own hard errors are empty:

```haskell
hardErrors = filter ((== SevError) . diagSeverity) (reportDiagnostics report)
if null hardErrors
  then pure $ Right (cache2, order2, env)
  else pure $ Left hardErrors
```

A module that newly fails to type-check under the widened checker returns `Left hardErrors`; the sidecar-merged `env` is built but discarded, and `loadOneImport`/`loadModule` propagate the `Left` to every importer. Each module in a dependency chain is independently type-checked by the current binary when loaded (`loadFromFile` is called per module), so a laundering program surfaces its own `hardErrors` at its own file, not only at the entry point.

**Corpus evidence (Task 2).** Zero-delta: `passed=162 failed=1 skipped=0`, identical to the 01-01 baseline, and the one failure is the same pre-existing example as every prior plan in this phase recorded; no corpus program's `llmll check` verdict moved from pass to fail.

**Applying the rule.** Bump if either (a) Task 2 recorded a pass-to-fail verdict change, or (b) the reading shows a cached `verified` sidecar can be reported without a successful type check gating it. (a) is false (zero-delta, cited above). (b) is false at both entry paths read: the sidecar is loaded before the gate in each case, but only reaches a consumer-visible render when the gate has already succeeded. Neither condition holds, so this replaces the research doc's assumed reasoning (`01-RESEARCH.md`, "Security Domain" section, tagged `[ASSUMED]`) with a measured finding: no previously-`verified` sidecar becomes newly reportable-as-stale-true as a result of this phase's widen, because loading the program at all is the precondition for reporting it, and loading now fails for exactly the programs the widen targets.

**What would reopen this.** Any later phase that WIDENS what the checker accepts (rather than narrows it) would need to re-ask this question, because the gate's soundness here rests on the change only removing acceptances, never adding one. A future narrowing phase can likely re-cite this same gate structure rather than re-deriving it, provided the gate's shape (sidecar loaded before, consumed only after, type-check success) is unchanged at that point.

## Task Commits

**Staged by this executor, not committed.** Per this repository's `.claude/hooks/block-git-from-subagent.sh`, `git commit` is denied from any Task-tool subagent; the calling orchestrator holds commit authority and must run the commits below after independently verifying the staged diffs and this SUMMARY's claims.

1. **Task 1: The diagnostic names the fact it refused**: `compiler/src/LLMLL/TypeCheck.hs` and `compiler/test/Spec.hs` staged together (the wording function and the fixture that pins it are one change; splitting them would leave an intermediate commit where SA-16 exists but does not yet exercise the described behavior, or vice versa).
   - Proposed commit: `feat(01-03): add wildAssumeFactNoun and SA-16 so the map arm names a value range, not a length`
2. **Tasks 2 and 3: measurement and the epoch decision**: no source files changed (Task 2 is measurement-only; Task 3's decision is not to bump, so `VerifiedCache.hs` carries no diff). Nothing to stage beyond this SUMMARY.

**Plan metadata commit** (also to be made by the orchestrator, same reason):
```
git add .planning/phases/01-close-the-map-arm-of-wild-assume/01-03-SUMMARY.md .planning/STATE.md .planning/ROADMAP.md .planning/REQUIREMENTS.md
git commit -m "docs(01-03): complete diagnostic-wording-and-epoch-decision plan"
```

## Files Created/Modified

- `compiler/src/LLMLL/TypeCheck.hs`: `wildAssumeFactNoun` added directly above `tcWildAssumeError`; `tcWildAssumeError`'s `msg` binding rewritten to interpolate it. `diagKind`, `diagExpected`, and `diagGot` are unchanged, so JSON consumers still see a normal type mismatch.
- `compiler/test/Spec.hs`: SA-16 added to the map-arm `describe` block, immediately after SA-15.
- `compiler/src/LLMLL/VerifiedCache.hs`: read (`sidecarNeedsRevalidation`, `checkerSoundnessVersion`, `saveVerifiedWith`), not modified.

## Decisions Made

- `wildAssumeFactNoun`'s fallback case (`"a fact"`) is deliberately neutral rather than absent, keeping the function total the same way `assumesFact` itself is total; a future `assumesFact` arm that is not yet taught to `wildAssumeFactNoun` degrades to a vague-but-not-wrong noun instead of an unhandled-pattern crash in the diagnostic path.
- SA-16 lives in the map-arm `describe` block (not a third sibling block), since it asserts on both arms' sources and the map-arm block already has the fixtures and `tcOf` binding it needs; the bytes-arm source it reuses is SA-2's, quoted inline rather than imported across blocks (hspec `describe` blocks do not share `let` bindings).
- `checkerSoundnessVersion` is not bumped; full reasoning and citations under "checker_soundness_version decision" above.
- `requirements mark-complete REQ-wild-assume-2` was not run, for the same reason 01-01 and 01-02 recorded: it is blocked pending 01-04's SUMMARY in the same phase directory.

## Deviations from Plan

### Command-ordering correction (documented in advance by the orchestrator, applied as instructed)

The plan's Task 2 acceptance gate, as written, asserts `stack build --dry-run llmll` reports `Nothing to build.` immediately after `stack build llmll` and before `stack test`. Per 01-02's build-hygiene finding, that ordering cannot pass once source has changed: only a full `stack test` settles the package (clears the autogenerated `Paths_llmll.hs` dirty flag `stack build` alone leaves behind). Ran the corrected ordering instead: `stack build llmll`, then a full `stack test`, then the dry-run assertion, then `scripts/check-examples.sh`. The gate's intent (confirm the binary `check-examples.sh` shells out to is current, not stale) is preserved; only the command ordering changed. Verified the dry-run assertion held (`Nothing to build.`) at the moment immediately preceding the `check-examples.sh` run recorded in "Post-change measurements" above.

### Git commit authority (environment constraint, not a plan deviation)

Same constraint 01-01 and 01-02 documented: `.claude/hooks/block-git-from-subagent.sh` denies `git commit` from any Task-tool subagent, unconditionally. This executor staged Task 1's files and hands the commits to the calling orchestrator, per the task-commit protocol.

No Rule 4 (architectural) deviations occurred. No code, test, or verification content differs from the plan as written beyond the command-ordering correction above, which the orchestrator specified in advance.

## Issues Encountered

None beyond the git-commit-authority constraint and the command-ordering correction, both documented above.

## User Setup Required

None. No external service configuration required.

## Next Phase Readiness

- Both `assumesFact` seams now carry an accurate, per-class diagnostic message, proven live by a wording-revert probe distinct from the clause-liveness probes 01-01 and 01-02 ran.
- The corpus and suite deltas for this plan are measured against the 01-01 baseline, not asserted: 1448 examples (+9), corpus unchanged at `passed=162 failed=1 skipped=0`.
- The `checkerSoundnessVersion` epoch question is settled on a cited reading plus a zero-delta corpus comparison, replacing the research doc's assumed reasoning; the decision (no bump) and its full evidence are recorded above for 01-04's release notes to carry forward, including the "what would reopen this" condition.
- Test-count arithmetic complete for this phase's Hspec additions: 1439 (01-01 pre-change baseline) → 1441 (01-01, +2) → 1447 (01-02, +6) → 1448 (01-03, +1, SA-16) = 1439 + 9, exactly the phase target.
- 01-04 (release ceremony) can proceed: it inherits this plan's corpus comparison, example-count delta, and the epoch decision with evidence, to state accurately in the CHANGELOG per the research doc's Pitfall 3 (this phase closes a measured class member with no reaching-SAFE witness, not a demonstrated exploit).

---
*Phase: 01-close-the-map-arm-of-wild-assume*
*Completed: 2026-07-31*

## Self-Check: PASSED (files) / N/A (commits)

- FOUND: `compiler/src/LLMLL/TypeCheck.hs` (`wildAssumeFactNoun` present, definition plus interpolation site plus doc-comment references)
- FOUND: `compiler/test/Spec.hs` (SA-16 present in the map-arm `describe` block)
- FOUND: `.planning/phases/01-close-the-map-arm-of-wild-assume/01-03-SUMMARY.md`
- CONFIRMED: `compiler/src/LLMLL/VerifiedCache.hs` carries zero diff (`git diff` empty), matching the claim that the epoch decision required no code change
- Commit-hash check is not applicable this run: no commits exist yet for this plan's work, per the git-commit-authority deviation documented above. The calling agent must run the commits proposed in "Task Commits" before this claim can be verified against actual hashes.
