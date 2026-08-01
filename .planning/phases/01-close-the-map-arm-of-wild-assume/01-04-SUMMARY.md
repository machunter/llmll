---
phase: 01-close-the-map-arm-of-wild-assume
plan: 04
subsystem: docs
tags: [changelog, release-ceremony, versioning, wild-assume, safe-arg, roadmap]

# Dependency graph
requires:
  - "assumesFact widened to map[k,bool] at both seams, from 01-01/01-02"
  - "wildAssumeFactNoun and the checkerSoundnessVersion decision, from 01-03"
provides:
  - "v0.14.74 CHANGELOG entry carrying the three required evidence-limit sentences verbatim"
  - "Five agreeing version anchors (README.md, LLMLL.md x2, compiler/package.yaml, compiler/llmll.cabal)"
  - "WILD-ASSUME-2 row moved from docs/compiler-team-roadmap.md Active Items to Shipped Releases"
  - "LLMLL.md §3.4.6 and §5.3.5 spec-prose corrections closing the 'not yet shipped' false statements"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Release ceremony as a documentation-lead-role pass: CHANGELOG first, then version anchors, then roadmap row move, with a hand-off recorded before any edit"
    - "Evidence-limit language pinned as required verbatim sentences must each occupy a single un-wrapped physical line in CHANGELOG.md, since the acceptance grep is line-based and a soft line-wrap mid-sentence defeats it"

key-files:
  created: []
  modified:
    - CHANGELOG.md
    - README.md
    - LLMLL.md
    - compiler/package.yaml
    - compiler/llmll.cabal
    - docs/compiler-team-roadmap.md

key-decisions:
  - "Version set to 0.14.74 across all five anchors: README.md:1, LLMLL.md:1 and :5, CHANGELOG.md top heading, compiler/package.yaml:2, compiler/llmll.cabal:8"
  - "WILD-ASSUME-2's Active Items row deleted outright (not left in place with a SHIPPED label the way the pre-existing SAFE-ARG row was); a compact Shipped Releases row added instead, per the plan's explicit 'moved out of Active Items' instruction and documentation-lead's 'moved, not deleted' convention (moved to a different section, not removed from the document)"
  - "LLMLL.md:403 and :958 corrected despite the plan's own prohibition #2 ('do not expand LLMLL.md beyond the version banner'), see Deviations. The orchestrator's baseline_context course-correction explicitly named these two lines as now-false statements the release must fix, and the correction made is narrow (updating an existing true/false claim about shipped status), not the deferred REQ-wildcard-semantics-spec content the prohibition was written to keep out"
  - "docs/design/finding-arg-position-false-safe.md Rev 2's status line was NOT edited. Its 'Stage 1 is bytes-only; the map[k,bool] arm is roadmap row WILD-ASSUME-2' framing is now stale (the arm shipped), but design-doc bodies are out of documentation-lead's scope per the skill's hard constraints (only INDEX labels and review-fold appendices are editable); this is surfaced as a finding below, not silently fixed"
  - "checkerSoundnessVersion carried forward as NOT bumped, per 01-03's cited evidence (doVerify's type-check gate precedes every sidecar-render branch; Module.hs discards a per-module sidecar merge on non-empty hardErrors); VerifiedCache.hs carries no diff in this plan either"

patterns-established: []

requirements-completed: []

coverage:
  - id: D1
    description: "Hand-off to documentation-lead recorded before any release-surface document was edited (six items: ticket tag, user-visible behavior, schema delta, test-count delta, checker_soundness_version decision, finding-doc status-line question)"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: other
        ref: "This SUMMARY's '## Hand-off to documentation-lead' section, written before the '## Release ceremony' section"
        status: pass
    human_judgment: false
  - id: D2
    description: "v0.14.74 CHANGELOG entry carries the three required evidence-limit sentences verbatim and none of the v0.14.73 entry's exploit vocabulary in its own section"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: other
        ref: "grep -c for each of the three sentences against CHANGELOG.md: 1, 1, 1; awk region-scoped grep -c for 'did not fail closed' and 'reads past the end' between the v0.14.74 and v0.14.73 headings: 0, 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "All five version anchors agree at 0.14.74 and scripts/version_gate.sh exits 0"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: other
        ref: "scripts/version_gate.sh: DRIFT-CI-1 PASS, banner v0.14.74 across README/LLMLL.md/CHANGELOG/package.yaml/llmll.cabal, exit 0"
        status: pass
    human_judgment: false
  - id: D4
    description: "WILD-ASSUME-2 row moved out of Active Items into Shipped Releases"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: other
        ref: "docs/compiler-team-roadmap.md: WILD-ASSUME-2's Active Items row deleted; a new v0.14.74 row added to the Shipped Releases table above v0.14.73"
        status: pass
    human_judgment: false
  - id: D5
    description: "Definition of Done gate run end to end with the corrected build-hygiene ordering; suite and corpus measured against the 01-01 baseline"
    requirement: "REQ-wild-assume-2"
    verification:
      - kind: other
        ref: "stack build llmll then a full stack test (twice, see Deviations) then stack build --dry-run llmll reporting Nothing to build, then scripts/check-examples.sh: 1448 examples/0 failures (baseline 1439 + 9), passed=162 failed=1 skipped=0 (unchanged from baseline)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Human read of the release notes against the evidence limit"
    human_judgment: true
    rationale: "This is 01-04 Task 3, a deliberate blocking checkpoint per the plan's own frontmatter (type=\"checkpoint:human-verify\", gate=\"blocking\"). The executor does not self-approve it; see the CHECKPOINT REACHED section of this turn's response."

duration: ~55min
completed: 2026-08-01
status: complete
---

# Phase 1 Plan 4: Compiler-engineer hand-off and the v0.14.74 release ceremony Summary

**The `map[k,bool]` arm of WILD-ASSUME ships as v0.14.74: CHANGELOG entry carrying the required evidence-limit sentences verbatim, all five version anchors agreeing, the WILD-ASSUME-2 roadmap row moved to Shipped Releases, two now-false LLMLL.md spec statements corrected, and a green Definition of Done (1448 examples / 0 failures, corpus unchanged at passed=162 failed=1 skipped=0), and Task 3's blocking human-verify checkpoint approved by the human on 2026-08-01.**

## Performance

- **Duration:** ~55 min
- **Completed:** 2026-08-01T03:44:11Z (Tasks 1-2); Task 3 approved 2026-08-01
- **Tasks:** 3 of 3 (Task 3 approved at the blocking checkpoint)
- **Files modified:** 6

## Hand-off to documentation-lead

Written before any of the six release-surface documents was edited, per the compiler-engineer skill's step-4 hand-off contents and this plan's explicit ordering requirement.

1. **Ticket tag:** WILD-ASSUME-2 (`docs/compiler-team-roadmap.md` Active Items, now moved to Shipped Releases as part of this plan).
2. **User-visible behavior change:** A `map[k,bool]` value reaching its binder through an unannotated return (or argument, or alias, or string-keyed position) is now refused at both the argument seam (`structuralUnify`) and the return seam (`compatibleWith`/`unify`), with a diagnostic naming the per-key value-range fact ("a per-key value range") instead of the bytes-only "a length" wording. This mirrors the SAFE-ARG bytes-arm restriction shipped in v0.14.73, extended to the map class.
3. **Schema delta:** None. `docs/llmll-ast.schema.json` and `compiler/src/LLMLL/ParserJSON.hs`'s `expectedSchemaVersion` are untouched by this phase (confirmed by `scripts/version_gate.sh`'s C3/C4 checks passing unchanged: schemaVersion `0.9.0`, `$id` still `/schemas/v0.9/`).
4. **Measured test-count delta (from 01-03-SUMMARY.md):** 1439 (01-01 pre-change baseline) → 1448 (post-01-03, +9: SA-8 through SA-16). This plan's own Definition of Done gate re-measures the same figure against a freshly rebuilt binary (see Definition of Done, below): 1448 examples, 0 failures, matching exactly.
5. **`checker_soundness_version` decision (from 01-03-SUMMARY.md):** NOT bumped. `VerifiedCache.hs`'s `checkerSoundnessVersion` stays `"1"`. Evidence, carried forward: `app/Main.hs`'s `doVerify` loads the entry sidecar before the type-check gate (`:1194`), but every sidecar-consuming render branch (`--trust-report`, `--spec-coverage`, `--obligation-report`, the full solver path) sits after that gate in the same function body, so a program the widened checker newly rejects `exitFailure`s before any branch renders a cached verdict. `Module.hs`'s `loadFromFile` merges a per-module sidecar unconditionally but only returns the merged env when that module's own `hardErrors` are empty, so a module that newly fails to type-check discards the merge. The corpus comparison (Task 2 of this plan) is a zero-delta against the 01-01 baseline (`passed=162 failed=1 skipped=0`, same single pre-existing failure), consistent with neither of the rule's two bump conditions firing.
6. **`docs/design/finding-arg-position-false-safe.md` Rev 2's status line:** It should change, its current text ("Stage 1 is bytes-only; the map[k,bool] arm is roadmap row WILD-ASSUME-2") is now stale, since that arm has shipped in this release, but the edit is **not made in this plan**. Editing a design-doc body (beyond an INDEX status label or a review-fold appendix) is outside documentation-lead's scope per the skill's hard constraints ("Never touches: … design-doc bodies (only INDEX labels and review-fold appendices)"). This is surfaced as a finding for the user to route to `language-team` or a follow-on doc pass, not silently fixed here.

## Release ceremony

Acted in the documentation-lead role for the six edits below, in the update order the skill specifies (CHANGELOG first, then version anchors, then roadmap).

### 1. `CHANGELOG.md`, new `## v0.14.74` entry

Added immediately below the `Latest` anchor, above the existing `## v0.14.73` heading. States what changed (`assumesFact` extended to the map class with the same key/value admissibility `FixpointEmit.boolValuedMapTy` uses, reaching both seams through one predicate), the two liveness-proving fixtures (SA-8 argument seam, SA-9 return seam, both laundering through an unannotated hop against the freshened `?$N` form), the four over-breadth guards (SA-6/SA-14 for `(map-empty)`, SA-10, SA-12, SA-15) plus SA-11's alias-coverage answer by measurement, the diagnostic wording change (`wildAssumeFactNoun`), the measured example-count delta, the corpus result, and the `checker_soundness_version` decision. Carries the three required sentences verbatim (see below).

**The three required sentences, verbatim, as they appear in `CHANGELOG.md`:**

> This closes a measured member of the SAFE-ARG class with no reaching-SAFE witness.
> The phase closes a class member; it does not refute a demonstrated exploit.
> The corpus run is recorded as a regression check, not as evidence the fix works.

### 2. Five version anchors set to `0.14.74`

`README.md:1`, `LLMLL.md:1` and `:5`, the new `CHANGELOG.md` top heading, `compiler/package.yaml:2`, `compiler/llmll.cabal:8`. `scripts/version_gate.sh` confirms all five agree (`DRIFT-CI-1 PASS: banner v0.14.74`).

### 3. `docs/compiler-team-roadmap.md`, WILD-ASSUME-2 row moved

The Active Items row (a `[CT]`-tagged row with the full "OPEN, stage 1 shipped v0.14.73, bytes-only" description) was deleted from the Active Items table. A new compact row was added to the Shipped Releases table, above the existing `v0.14.73` row, recording the shipping version, the headline, the fixture list, the `checker_soundness_version` decision, and the evidence-limit language. RET-RESOLVE and FACT-AG rows were left untouched, per the plan's explicit instruction (they are Phase 2 and Phase 3 scope).

### 4. `LLMLL.md` §3.4.6 and §5.3.5 spec-prose corrections

Two now-false statements were corrected (see Deviations for why this goes beyond the plan's literal prohibition #2):

- **§3.4.6** (`WILD-ASSUME` paragraph): "Today that class is `bytes[n]`…" → now states the class is `bytes[n]` **and** `map[k,bool]` together, with the evidence-limit sentence stated inline for the map arm.
- **§5.3.5** (array-class completeness argument): "…that arm of the restriction is not yet shipped." → now states it ships in v0.14.74, with the same evidence-limit framing (measured class member, not a demonstrated exploit).

## Definition of Done

Run in the corrected ordering per the orchestrator's build-gate correction (`scripts/version_gate.sh`, then a rebuild, then a full `stack test`, then the dry-run assertion, then the corpus gate), not the plan's as-written ordering (dry-run immediately after `stack build llmll`, which 01-02/01-03 already measured cannot pass once a build-config file changes).

1. **CHANGELOG entry exists under a new heading with a dated title.** `## v0.14.74: the map[k,bool] arm of WILD-ASSUME, with no reaching-SAFE witness (2026-07-31)`. Confirmed: `grep -c '^## v0.14.74' CHANGELOG.md` → 1.
2. **Version agrees across the five anchors.** Confirmed by `scripts/version_gate.sh`'s C1/C2 checks, both passing.
3. **`scripts/version_gate.sh` exits 0.** Ran twice (before and after the rebuild below); both runs: `DRIFT-CI-1 PASS: banner v0.14.74 (README, LLMLL.md, CHANGELOG, package.yaml, llmll.cabal); schemaVer 0.9.0; $id https://llmll.dev/schemas/v0.9/ast.schema.json`. C1 (banner agreement across five files), C2 (LLMLL.md banner == CHANGELOG top heading), C3 (schema `schemaVersion` == `ParserJSON.expectedSchemaVersion`), C4 (schema `$id` URL matches derived major.minor) all pass; exit 0 both times.
4. **Rebuild, dry-run settle, full test, corpus gate.**
   - `(cd compiler && stack build llmll)`: succeeded, `Registering library for llmll-0.14.74` (confirms the version bump reached the built binary, not a stale one).
   - `(cd compiler && stack test)`: **1448 examples, 0 failures.**
   - `(cd compiler && stack build --dry-run llmll)` **immediately after that test run: still reported `Would build:`** (autogen `Paths_llmll.hs` still flagged dirty). This is a variant on 01-02's build-hygiene finding: 01-02/01-03 measured that one full `stack test` settles the package after a *source* edit; this plan's edit is to `compiler/package.yaml` and `compiler/llmll.cabal` (the version fields the autogen module derives from), and one `stack test` cycle was not sufficient to settle it here. Ran a **second** full `(cd compiler && stack test)` (also 1448 examples, 0 failures), then re-ran the dry-run: **`Nothing to build.`**, stable.
   - `scripts/check-examples.sh`, run immediately after that stable dry-run: `passed=162 failed=1 skipped=0`, identical to the 01-01 baseline. The one failure is `examples/totp_rfc6238/totp_filled.ast.json`, the same pre-existing bytes-arm rejection every prior plan in this phase recorded, confirmed by name, not just by count.
   - **Test-count arithmetic:** 1439 (01-01 baseline) + 9 (SA-8 through SA-16, landed across 01-01/01-02/01-03) = 1448, exactly matching this plan's re-measurement. No SS-5 was added in 01-03, so the "+9" branch of the acceptance criterion applies, not "+10".
   - **`scripts/check-examples.sh`'s own exit code is 1, not 0** (see Deviations, this is the script's inherent behavior whenever `failed > 0`, which has been true of every plan's baseline measurement in this phase, not a regression introduced here). The criterion actually satisfied, and the one that matters per ROADMAP's Definition of Done ("reports no new failures"), is that `failed=` is unchanged from the 01-01 baseline: it is.
5. **Pre-run of Task 3's verification commands**, so the checkpoint has real numbers rather than a promise to run them: `(cd compiler && stack test --test-arguments '--match "laundering through an unannotated hop"')` → **16 examples, 0 failures**, matching the checkpoint's stated expectation exactly.

## Files Created/Modified

- `CHANGELOG.md`, new `## v0.14.74` entry (55 lines) above the existing `## v0.14.73` heading.
- `README.md:1`, version banner `v0.14.73` → `v0.14.74`.
- `LLMLL.md:1`, version banner `(v0.14.73)` → `(v0.14.74)`.
- `LLMLL.md:5`, "Current version" callout `v0.14.73` → `v0.14.74`.
- `LLMLL.md:403`, §3.4.6 WILD-ASSUME paragraph corrected to name both classes (`bytes[n]` and `map[k,bool]`) instead of only `bytes[n]`.
- `LLMLL.md:958`, §5.3.5 array-class bullet corrected from "not yet shipped" to a shipped-in-v0.14.74 statement with the evidence limit stated inline.
- `compiler/package.yaml:2`, `version: 0.14.73` → `0.14.74`.
- `compiler/llmll.cabal:8`, `version: 0.14.73` → `0.14.74` (this file is hpack-generated from `package.yaml`; both were edited directly since no `hpack` regen step was run, see Issues Encountered).
- `docs/compiler-team-roadmap.md`, WILD-ASSUME-2's Active Items row deleted; a new Shipped Releases row added for v0.14.74, above the v0.14.73 row.

## Decisions Made

See `key-decisions` in frontmatter for the full list. The one worth restating in prose: the WILD-ASSUME-2 Active Items row was **deleted** rather than left in place with a "SHIPPED" status label the way the pre-existing SAFE-ARG row currently reads. The plan's own action text says "Move the WILD-ASSUME-2 row … out of Active Items," which this executor read as an instruction to remove the row from that table (not merely relabel it in place), consistent with the documentation-lead skill's "moved … not deleted" language, where "moved" means relocated to a different section of the same document, not left in both places. This creates an intentional asymmetry against the current SAFE-ARG row (which still appears in both tables); that pre-existing asymmetry is not this plan's to fix.

## Deviations from Plan

### 1. [Rule 1, line-wrap defeats a line-based grep] The three required CHANGELOG sentences had to be reformatted onto un-wrapped lines

**Found during:** Task 1, self-verification of the acceptance criteria immediately after drafting the CHANGELOG entry.
**Issue:** The first draft wrote the three required sentences as flowing prose wrapped at ~80 columns, matching the file's existing paragraph style. Two of the three sentences (sentence 1 and sentence 3) each spanned a soft line-wrap in the raw file, so `grep -c '<exact sentence>' CHANGELOG.md` returned 0 for both, even though the sentence was present verbatim when read as continuous prose.
**Fix:** Reformatted the intro paragraph and the corpus bullet so each of the three required sentences occupies its own complete physical line (still renders as a normal paragraph in Markdown, since consecutive non-blank lines join in rendering; only the raw-file line breaks changed).
**Files modified:** `CHANGELOG.md`.
**Verification:** Re-ran the three `grep -c` checks: 1, 1, 1.

### 2. [Orchestrator course-correction, applied as instructed] LLMLL.md:403 and :958 corrected despite the plan's stated prohibition #2

**Found during:** Task 1, reading the plan's prohibitions section against the orchestrator's `<baseline_context>`.
**Issue:** The plan's own text says "Do not expand `LLMLL.md` beyond the version banner on lines 1 and 5," reasoning that the bare wildcard's general denotation is `REQ-wildcard-semantics-spec`, a deferred requirement. Read literally, this would forbid touching lines 403 and 958. But the orchestrator's `<baseline_context>` for this turn explicitly named these two lines as containing spec prose that "becomes false with this release and are part of the ceremony surface," and instructed treating them as part of the ceremony.
**Resolution:** Followed the orchestrator's explicit, more specific correction (per this agent's operating rules, a course-correction from the launching agent directs the work) rather than the plan's general prohibition. The edits made are narrow: correcting an existing true/false claim about shipped status ("today that class is bytes[n]" / "not yet shipped" → both classes, shipped in v0.14.74), not writing new content about what the bare wildcard denotes in general, which is what the prohibition's stated rationale (`REQ-wildcard-semantics-spec`) was actually protecting against.
**Files modified:** `LLMLL.md` (lines 403, 958).
**Verification:** `sed -n '1p;5p' LLMLL.md | grep -c 'v0\.14\.74'` → 2 (unaffected by this deviation, confirming the banner-only acceptance criterion still holds); manual read of both corrected paragraphs against the evidence-limit language used in the CHANGELOG entry, for consistency.

### 3. [Environment finding, not a plan defect] The build-hygiene dry-run assertion needed two full `stack test` cycles to settle, not one

**Found during:** Task 2, Definition of Done item 4.
**Issue:** 01-02/01-03 measured that a source-code edit needs exactly one full `stack test` to clear the `stack build --dry-run llmll` dirty flag (the autogen `Paths_llmll.hs` file). This plan's only compiler-adjacent edits are the version fields in `compiler/package.yaml` and `compiler/llmll.cabal` (no source files touched, confirmed by `git diff --name-only | grep -E 'compiler/(src|test)/'` returning 0 lines). After `stack build llmll` then one full `stack test`, the dry-run still reported `Would build:`. A second full `stack test` (also 1448/0 failures) settled it: the following dry-run reported `Nothing to build.`, stable on a repeat check.
**Resolution:** Treated as a build-tooling characteristic of this plan's specific edit shape (a version bump touching both the hpack source and its generated cabal file, rather than a Haskell source edit), not a defect to fix. Did not adjust any fixture or test to force a green result; simply ran the settle step until the assertion held, then immediately ran the corpus gate while it held, per the plan's own instruction to verify the assertion holds "at the moment `check-examples.sh` ran."
**Files modified:** None (build-directory artifacts only, not tracked).
**Verification:** Recorded transcript in "Definition of Done" item 4 above.

### 4. [Documented finding, not fixed] `scripts/check-examples.sh` exits 1, not 0, at both the 01-01 baseline and post-this-plan

**Found during:** Task 2, Definition of Done item 4.
**Issue:** The plan's acceptance criteria state "`scripts/check-examples.sh` exits 0 and its `failed=` value equals the plan 01-01 baseline `failed=` value." Reading the script (`scripts/check-examples.sh`, its final `if [[ "$FAILED" -gt 0 ]]; then … exit 1; fi`), it exits 1 whenever any corpus file fails, and the 01-01 baseline itself already has `failed=1` (the pre-existing `totp_rfc6238` case). So "exits 0" was never achievable at the baseline this plan is held to, and is not achievable now either, through no fault of this plan's changes.
**Resolution:** Not a scope-in-bounds fix (nothing in this plan's diff touches the totp fixture or the script's exit logic, and doing so would be exactly the "fixture adjusted to make a red gate green" pattern Task 2's own instructions forbid). Verified the criterion that actually matters and is stated in ROADMAP.md's Definition of Done ("reports no new failures") holds: `failed=1`, identical to baseline, same named example. Recorded here as a finding so the discrepancy between the plan's literal acceptance-criteria wording and the script's actual, baseline-established behavior is visible rather than silently glossed over.
**Files modified:** None.
**Verification:** `scripts/check-examples.sh` run twice; both times `passed=162 failed=1 skipped=0`, exit code 1, failing example named `examples/totp_rfc6238/totp_filled.ast.json` both times.

---

**Total deviations:** 4 (1 self-caught formatting fix, 1 orchestrator-directed scope correction, 2 documented findings about pre-existing tooling behavior, neither fixed nor masked).
**Impact on plan:** None affect the substance of the release; all four are either corrections that make the acceptance criteria actually verifiable, or accurate documentation of environment behavior that predates this plan.

## Issues Encountered

- `compiler/llmll.cabal` is hpack-generated from `compiler/package.yaml` (its header states "This file has been generated from package.yaml by hpack"). This plan edited both files' `version:` fields directly rather than running `hpack` to regenerate the `.cabal` file from the edited `package.yaml`, since only the version line changed and regenerating risked incidental reformatting of the rest of the generated file. `scripts/version_gate.sh` (which checks both files independently, not their consistency-by-generation) passed against the direct edit. Flagged here in case a later plan expects `hpack`-regeneration parity.

## User Setup Required

None, no external service configuration required.

## Next Phase Readiness

## Task 3 checkpoint outcome (human-verify, blocking)

**Approved by the human on 2026-08-01.** Two judgments were recorded:

1. **Release notes are within the evidence limit.** The three required sentences are present verbatim, the corpus run is framed as a regression check rather than as evidence the fix works, and a region-scoped check of the v0.14.74 section found none of the v0.14.73 entry's exploit vocabulary except inside the disclaiming sentences themselves.
2. **The `LLMLL.md` correction is kept.** This plan's prohibition 2 said not to expand `LLMLL.md` beyond the version banner, on the grounds that what a bare `?` denotes in §3.4.6 is `REQ-wildcard-semantics-spec`, a deferred backlog item. The staged edit does not write that: it corrects two statements about class membership and ship status that this release makes false (§3.4.6 said the class was `bytes[n]` alone, §5.3.5 said the map arm was not yet shipped), and it carries the evidence limit inline in both places. The human's call was that a normative spec asserting "not yet shipped" about something shipped in the same commit is the worse outcome. The deviation originated in the orchestrator's briefing, not in executor drift.

Orchestrator re-verification behind the approval: `scripts/version_gate.sh` exit 0; full suite 1448 examples, 0 failures; `stack build --dry-run llmll` reported `Nothing to build.` at the moment `scripts/check-examples.sh` ran; corpus `passed=162 failed=1 skipped=0`, unchanged from the 01-01 baseline; `git diff --cached --name-only` contains no path under `compiler/src/` or `compiler/test/`.
- This plan's Tasks 1 and 2 are complete and staged; **Task 3 (the blocking human-verify checkpoint) is pending**, see the CHECKPOINT REACHED section of this turn's response for the structured hand-off.
- No commit, tag, or push has been made. Per this repository's `.claude/hooks/block-git-from-subagent.sh`, this executor cannot commit; the calling orchestrator holds commit authority (as it did for 01-01/01-02/01-03), and the user separately decides on tag and push.
- On approval of Task 3, a continuation agent (or the orchestrator directly) should: commit the six staged files with the message `docs(01-04): ship v0.14.74, close the map arm of WILD-ASSUME`; run the state-update steps (`state advance-plan`, `state update-progress`, `state record-metric`, `state add-decision`, `state record-session`); run `roadmap update-plan-progress 1`; run `requirements mark-complete REQ-wild-assume-2` (this is the first plan in the phase where this is unblocked, all four sibling plans now have SUMMARY.md files, once this one lands); and make the final metadata commit. None of those steps were run by this executor, since the plan is not yet complete.
- If Task 3 is rejected (the human finds the release notes claim more than the evidence supports), the CHANGELOG entry, the two LLMLL.md corrections, and/or the roadmap row would need revision before re-requesting approval; none of the currently staged changes have been committed, so a revision is a plain edit-and-restage, not a revert.

---
*Phase: 01-close-the-map-arm-of-wild-assume*
*Completed: 2026-08-01 (Tasks 1-2); Task 3 approved 2026-08-01*

## Self-Check: PASSED (Tasks 1-2 verified by the executor and re-verified by the orchestrator; Task 3 approved by the human)

- FOUND: `CHANGELOG.md` contains `## v0.14.74` (1 occurrence) and all three required sentences (1 occurrence each, verified by `grep -c` after the line-wrap fix)
- FOUND: `README.md:1`, `LLMLL.md:1`, `LLMLL.md:5` all contain `v0.14.74`
- FOUND: `compiler/package.yaml` and `compiler/llmll.cabal` both contain `0.14.74`
- FOUND: `docs/compiler-team-roadmap.md` contains `WILD-ASSUME-2` (2 occurrences: the RET-RESOLVE row's cross-reference, left untouched per instruction, and the new Shipped Releases row); 0 occurrences within the Active Items section
- CONFIRMED: `scripts/version_gate.sh` exits 0
- CONFIRMED: `(cd compiler && stack test)` reports 1448 examples, 0 failures (run twice, both times)
- CONFIRMED: `scripts/check-examples.sh` reports `passed=162 failed=1 skipped=0`, identical to the 01-01 baseline, same named failure
- CONFIRMED: `git diff --name-only` contains no path under `compiler/src/` or `compiler/test/`
- Commit-hash check is not applicable: no commits exist yet for this plan's work (staged, not committed, per the git-commit-authority constraint every prior plan in this phase also documented). `git log --oneline -3` at this point shows only the 01-01/01-02/01-03 commits already landed by the orchestrator.
