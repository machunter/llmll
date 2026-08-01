---
phase: 01-close-the-map-arm-of-wild-assume
verified: 2026-08-01T14:16:28Z
status: passed
score: 5/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 1: Close the map arm of WILD-ASSUME Verification Report

**Phase Goal:** A `map[k,bool]` value that reached its binder through a bare inference wildcard can
no longer contribute a value-range fact that no obligation discharges.
**Verified:** 2026-08-01T14:16:28Z
**Status:** passed
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (ROADMAP.md Success Criteria, Phase 1)

| # | Truth (ROADMAP criterion) | Status | Evidence |
|---|---|---|---|
| 1 | SA-6 committed before the widen and `(map-empty)` still type-checks at every position it did today, including the `map[int bool]` position the widen actually risks (SA-14) | VERIFIED | Re-ran `stack test --match "SA-6"` → `1 example, 0 failures` and `--match "SA-14"` (inside the laundering-hop block) → passes. Both fixtures present at `compiler/test/Spec.hs`. `compiler/src/LLMLL/TypeCheck.hs` `assumesFactMapKey`/`assumesFactBoolValue` match on the value component, not the outer `TMap` constructor, which is what keeps `map-empty`'s polymorphic `TVar "k"`/`TVar "v"` absorbing. |
| 2 | `assumesFact` covers the map class; discriminant recognizes bare `TVar "?"` and its `freshenFnType` `?$N` instances; a fixture exercises the `?$N` form directly | VERIFIED | `assumesFact (TMap kt vt) = assumesFactMapKey kt && assumesFactBoolValue vt` at `TypeCheck.hs:369`, guarded via `isBareWildcard` (unchanged shipped discriminant, handles both `?` and `?$N`). SA-8/SA-9/SA-11/SA-13/SA-16/SA-17 all launder through an unannotated hop (`mapLaunderPrefix`), so the value the guard sees is `TVar "?$N"` post-`freshenFnType`, not the bare form. Independently reproduced: I disabled the `TMap` clause (`assumesFact (TMap _ _) = False`), rebuilt, and re-ran the laundering-hop block: exactly SA-8, SA-9, SA-11, SA-13, SA-16, SA-17 went RED (6 failures out of 17), while SA-10, SA-12, SA-14, SA-15 stayed green, the same clean partition the orchestrator's probe recorded, extended to cover SA-16/SA-17 directly. Restored the file to a byte-identical diff (`diff` empty), rebuilt, suite back to 1449/0 failures. |
| 3 | A fixture exhibits the rejection: a `map[k,bool]` value laundered through an unannotated hop is refused at the seam instead of injecting the VC antecedent fact | VERIFIED | SA-8 (argument seam), SA-9 (return seam), SA-11 (aliased), SA-13 (string key), SA-17 (`where`-wrapped, both arms) all assert `reportSuccess` False and `wildAssumeFired` True. Re-ran `stack test --match "laundering through an unannotated hop"` → `17 examples, 0 failures` (7 bytes-arm + 10 map-arm: SA-8 through SA-17). The mid-phase code review (CR-01) found and closed a real gap here, a `TDependent`-wrapped (`where`-aliased) map/bytes type evaded the restriction because `assumesFact` matched only the outermost constructor. Fixed in commit `4c8a270` (`assumesFact (TDependent _ b _) = assumesFact b`), covered live by SA-17, confirmed present and correctly wired in `TypeCheck.hs:369` and in `unify`'s `assumesFact expected'` call against the alias-expanded-but-`TDependent`-preserving type at `TypeCheck.hs:2405-2409`. |
| 4 | Release notes state the evidence limit rather than overclaiming: measured class member with no reaching-SAFE witness, not a refuted exploit; corpus run framed as a regression check | VERIFIED | `CHANGELOG.md` `## v0.14.74` section contains, verbatim and each exactly once: "This closes a measured member of the SAFE-ARG class with no reaching-SAFE witness.", "The phase closes a class member; it does not refute a demonstrated exploit.", "The corpus run is recorded as a regression check, not as evidence the fix works." Region-scoped check (`awk` between the v0.14.74 and v0.14.73 headings) confirms 0 occurrences of the v0.14.73 entry's exploit vocabulary ("did not fail closed", "reads past the end") in the new section. |
| 5 | Shipped per the Definition of Done: CHANGELOG heading, five version anchors agree, `version_gate.sh` exits 0, `stack test` green, examples gate reports no new failures | VERIFIED | `grep -c '^## v0.14.74' CHANGELOG.md` = 1. `README.md:1`, `LLMLL.md:1`/`:5`, `compiler/package.yaml`, `compiler/llmll.cabal` all read `0.14.74`. Re-ran `scripts/version_gate.sh` → exit 0 (`DRIFT-CI-1 PASS`, banner v0.14.74, schemaVer/`$id` unchanged). Re-ran `(cd compiler && stack build --dry-run llmll)` (clean before measurement), then `stack test` twice (build-hygiene: one `stack test` cycle after a source change did not settle the dry-run flag, a second did, matches the phase's own documented finding) → **1449 examples, 0 failures**, matching the orchestrator's reported baseline-1439-plus-10. Re-ran `scripts/check-examples.sh` → `passed=162 failed=1 skipped=0`, identical to the pre-phase baseline; the one failure (`totp_rfc6238`) is the pre-existing, out-of-scope bytes-arm case. `docs/compiler-team-roadmap.md`'s WILD-ASSUME-2 row is present only in the Shipped Releases table (v0.14.74 row); the Active Items table no longer carries it (confirmed by `grep -n`, only the RET-RESOLVE row's cross-reference and the shipped row remain). |

**Score:** 5/5 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `compiler/src/LLMLL/TypeCheck.hs` `assumesFact` map clause + `assumesFactMapKey`/`assumesFactBoolValue` | Map-class discriminant, mirroring `FixpointEmit.boolValuedMapTy` admissibility | VERIFIED | Present at `:369-389`, correctly wired into both seams (`structuralUnify` argument seam, `compatibleWith`/`unify` return seam), confirmed live by disable-clause probe |
| `compiler/src/LLMLL/TypeCheck.hs` `wildAssumeFactNoun` | Per-class diagnostic noun phrase | VERIFIED | Present at `:440-445`; `tcWildAssumeError` interpolates it (`:461-471`); both call sites (`:2262`, `:2409`) pass the correctly-expanded type after the WR-01 fix |
| `compiler/test/Spec.hs` map-arm `describe` block, SA-8 through SA-17 | 10 new hspec examples proving the class live and its boundary | VERIFIED | All present; re-ran the full block, `17 examples, 0 failures` (7 bytes + 10 map); clause-disable probe partitions correctly (6 rejection fixtures RED, 4 acceptance fixtures green when the clause is disabled) |
| `compiler/src/LLMLL/VerifiedCache.hs` | Checked, not modified, `checkerSoundnessVersion` epoch decision was "do not bump" | VERIFIED | `git diff 6edee37..688f144 --name-only` does not list this file; decision cited in `01-03-SUMMARY.md` against `doVerify`'s type-check gate and `Module.hs`'s per-module sidecar merge |
| `CHANGELOG.md` `## v0.14.74` | Evidence-limit release entry | VERIFIED | Present, all three required sentences verbatim, no v0.14.73 exploit vocabulary borrowed |
| `README.md`, `LLMLL.md`, `compiler/package.yaml`, `compiler/llmll.cabal` version anchors | `0.14.74` agreement | VERIFIED | All five anchors read `0.14.74`; `scripts/version_gate.sh` exits 0 |
| `docs/compiler-team-roadmap.md` WILD-ASSUME-2 row | Moved out of Active Items | VERIFIED | Only appears in Shipped Releases table plus one cross-reference from the RET-RESOLVE row |
| `compiler/src/LLMLL/FixpointEmit.hs` | Must NOT appear in the phase diff (prohibition) | VERIFIED absent | `git diff 6edee37..688f144 --name-only` confirms it is not touched anywhere in the phase |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `compiler/test/Spec.hs` SA-9/SA-8/SA-11/SA-13/SA-17 | `compiler/src/LLMLL/TypeCheck.hs` `assumesFact` map clause | `wildAssumeFired` substring assertion, plus a live clause-disable probe | WIRED (eliminative) | Independently re-ran the disable-clause probe myself (not just accepted the orchestrator's prior claim): SA-8, SA-9, SA-11, SA-13, SA-16, SA-17 all flip to failing when the `TMap` clause is neutered; SA-10, SA-12, SA-14, SA-15 are unaffected. Restored to zero net diff, rebuilt, suite returned to 1449/0. |
| `compiler/src/LLMLL/TypeCheck.hs` `assumesFact` | `compiler/src/LLMLL/FixpointEmit.hs boolValuedMapTy` | Admissibility mirrored (int-or-string key, bool value), no code shared, reasoning cited in doc comments | WIRED | Confirmed by reading both functions; `assumesFactMapKey`/`assumesFactBoolValue` match `isIntLike`/`isStrLike`/`isBoolLike`'s classes minus the `AliasMap` lookup, with the alias-expansion invariant justified inline |
| `unify` / `compatibleWith` | `tcWildAssumeError` / `wildAssumeFactNoun` | `assumesFact expected'` gates the call; `wildAssumeFactNoun` reads the same expanded type (WR-01 fix) | WIRED | Confirmed at `TypeCheck.hs:2405-2409`: `tcWildAssumeError ctx expected expected'`, `expected'` being the alias-expanded-but-`TDependent`-preserving type that `assumesFact` (post-CR-01) now correctly classifies |

### Behavioral Spot-Checks / Independent Re-Runs

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Build currency before measuring | `(cd compiler && stack build --dry-run llmll)` | `Nothing to build.` (pre-check) | PASS |
| Full laundering-hop block | `stack test --match "laundering through an unannotated hop"` | `17 examples, 0 failures` | PASS |
| `(map-empty)` over-breadth (SA-6, `map[int,int]`) | `stack test --match "SA-6"` | `1 example, 0 failures` | PASS |
| Full suite | `stack test` (rebuilt, run twice to settle build-hygiene flag per the phase's own documented finding) | `1449 examples, 0 failures` | PASS |
| Corpus gate | `scripts/check-examples.sh` | `passed=162 failed=1 skipped=0` (unchanged from baseline; one pre-existing, out-of-scope failure) | PASS |
| Release gate | `scripts/version_gate.sh` | exit 0, `DRIFT-CI-1 PASS`, banner `v0.14.74` | PASS |
| SAFE-ARG regression (bytes arm SA-1..SA-7 + map arm + SS-1..SS-4) | `stack test --match "SAFE-ARG"` | `21 examples, 0 failures` | PASS |
| Ordinary mismatch does not fire WILD-ASSUME | `stack test --match "SA-3"` | `1 example, 0 failures` | PASS |
| **Eliminative clause-dependence probe (independent re-run)** | Disabled `assumesFact`'s `TMap` clause, rebuilt, re-ran the laundering-hop block, restored | `17 examples, 6 failures` with the clause disabled, exactly SA-8, SA-9, SA-11, SA-13, SA-16, SA-17 (the rejection-asserting fixtures); SA-10, SA-12, SA-14, SA-15 (acceptance controls) unaffected. Restored to zero net diff (`diff` empty against the committed file), rebuilt, suite back to 1449/0. | PASS, confirms liveness is not a stale claim |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
| ----------- | ------------ | ----------- | ------ | -------- |
| `REQ-wild-assume-2` | 01-01, 01-02, 01-03, 01-04 (all four) | Extend WILD-ASSUME from `bytes[n]` to `map[k,bool]` | SATISFIED | All acceptance clauses (map clause added, SA-6 prerequisite confirmed, evidence-limit writeup) verified above. `REQUIREMENTS.md` line 309 records it `Complete (v0.14.74, 2026-08-01)`, consistent with the codebase state. No orphaned requirements: this is the only `REQ-*` ID declared across the phase's four plans, and it is the only requirement the roadmap maps to Phase 1. |

### Anti-Patterns Found

None. `git diff 6edee37..688f144 -- compiler/src/LLMLL/TypeCheck.hs` contains no `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers. No stub returns, no hardcoded empty-data patterns in the modified code (`assumesFact`, `assumesFactMapKey`, `assumesFactBoolValue`, `wildAssumeFactNoun` are all total, non-trivial functions confirmed exercised by passing and clause-disable-probed tests).

### Human Verification Required

None. All five ROADMAP success criteria are either directly re-measured by this verifier (build/test/corpus/version-gate commands) or backed by a live hspec fixture I independently re-ran, including an eliminative clause-disable probe I ran myself rather than accepting the orchestrator's prior probe result at face value. Criterion 4 (evidence-limit release-note language) was already the subject of a blocking human-verify checkpoint in plan 01-04 (approved 2026-08-01 per `01-04-SUMMARY.md`), and this verifier's independent grep/awk re-check of the exact required sentences and the region-scoped absence check corroborate that approval against the current committed text, not just the staged draft it was approved against.

### Gaps Summary

None. All five ROADMAP.md Phase 1 success criteria hold against a freshly re-measured build, and the mid-phase code review's two real findings (CR-01 critical, WR-01 warning) were reproduced against the built binary and are now closed with committed fixtures (SA-17) rather than left as a residual gap. `checker_soundness_version` remains unbumped on cited, re-legible evidence (`doVerify`'s type-check gate precedes every sidecar-render branch; a per-module sidecar merge is discarded on non-empty `hardErrors`), and `FixpointEmit.hs` is untouched throughout, honoring the phase's own prohibition.

---

_Verified: 2026-08-01T14:16:28Z_
_Verifier: Claude (gsd-verifier)_
