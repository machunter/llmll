---
name: tool-rfc-001-version-gate
title: "TOOL-RFC-001: DRIFT-CI-1, the version gate, in LLMLL"
status: "Rev 1, RETROACTIVE. The port shipped at 7d1de03 BEFORE this standard existed, so this document records decisions already taken rather than proposing them. That is a defect in the sequence and §8 says which decisions it cost. State: oracle."
date: 2026-08-07
author: language-team
consumers: [compiler-engineer, documentation-lead, user]
tool_state: oracle
subject_script: scripts/version_gate.sh
port_module: tools/version-gate/versiongate.llmll
---

# TOOL-RFC-001: DRIFT-CI-1, the version gate, in LLMLL

**Retroactive.** The port was built and merged before
[`llmll-tooling-campaign.md`](llmll-tooling-campaign.md) existed. Everything
below was true of the work; §8 is the part that would have changed had it been
written first.

## 1. Subject

[`scripts/version_gate.sh`](../../scripts/version_gate.sh), 58 code lines
(89 with comments). Criteria C1..C4 of
[`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) row `:111`.

Invoked from **two** jobs:

- [`version-gate.yml`](../../.github/workflows/version-gate.yml), job
  `version-gate`. Checkout, install `jq`, run. **No Stack and no GHC**,
  deliberately: the workflow's own header says it does not run `stack test`, and
  it is named `version-gate.yml` rather than `ci.yml` to avoid implying a
  broader signal.
- [`docker-publish.yml`](../../.github/workflows/docker-publish.yml), job
  `publish`, on a `vX.Y.Z` tag push.

## 2. Criteria

Four, and the reference **exits on the first failure**, so the order is part of
the behaviour and the port reproduces it.

| # | Decides | Reference message |
|---|---|---|
| C1 | `README.md` line 1 banner == `LLMLL.md` line 1 banner | `C1 README.md banner ($a) != LLMLL.md banner ($b)` |
| C1 | banner == `compiler/package.yaml` `version:` | `C1 LLMLL.md banner ($a) != compiler/package.yaml version ($b)` |
| C1 | banner == `compiler/llmll.cabal` `version:` | `C1 LLMLL.md banner ($a) != compiler/llmll.cabal version ($b)` |
| C2 | banner == `CHANGELOG.md` top `## vX.Y.Z` | `C2 LLMLL.md banner ($a) != CHANGELOG.md top heading ($b)` |
| C3 | schema `schemaVersion.const` == `ParserJSON.expectedSchemaVersion` | `C3 schema schemaVersion ($a) != ParserJSON.expectedSchemaVersion ($b)` |
| C4 | schema `$id` contains `/schemas/v<MAJOR>.<MINOR>/` derived from C3 | `C4 schema $id URL ($id) lacks /schemas/$mm/ (derived from schemaVersion $sv)` |

Plus five extraction failures (`C1 could not extract vX.Y.Z from README.md line
1` and its four siblings). A missing file reaches those rather than a separate
arm, in both implementations.

## 3. Distribution

**Not settled the campaign's way, and this is the port's one open deviation.**
The campaign says jobs pull a published release image. This port instead leaves
the shell script running in `version-gate.yml` and runs the LLMLL binary from
[`build_smoke.sh`](../../scripts/build_smoke.sh) stage 10, inside
`spec-roundtrip`, where Stack is already warm.

The constraint that forced it: `version-gate.yml` has no toolchain by design,
and at the time of the port no mechanism existed to get a binary into it. The
image mechanism exists but is stale (campaign §3, prerequisite P1).

Consequence, stated plainly: **the shell script still decides in the fast job.**
This is the transitional state, not the pattern. It resolves when P1 clears.

## 4. Feasibility

| Needs | LLMLL | Note |
|---|---|---|
| read 7 files | `wasi.fs.read` | one console arm each |
| first line of a file | `string-split "\n"` | separator first |
| extract `vX.Y.Z` from a line | **gap** | `grep -oE` has no counterpart |
| a leading run of digits | **gap** | no character list, no ranges |
| JSON field access | `json-get`, `json-get-string` | `$defs` etc. are ordinary keys |
| compare strings | `=` | |
| exit 0 / 1 | `:status` | |
| a straight-line program | **gap** | `:mode cli` is a stub |
| config without env | `wasi.proc.args` + `--root` | argv carries what `REPO_ROOT` did |

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| `regex-match` typechecks, verifies, does not build | SHAPES | `REGEX-LOWER-1` | Three `grep -oE` equivalents. Instead: a hand-rolled scanner. |
| `string-split ""` does not terminate | SHAPES | `SPLIT-EMPTY-1` | A fold over the string's characters. Instead: a fold over a *literal index list* bounded at 24, with a saturation check so the bound cannot fail silently. |
| no character decomposition, no ranges | SHAPES | `SPLIT-EMPTY-1` (one row with the entry above) | A character fold. Instead: the same bounded index-list fold. Filed as one row because a `string-split ""` that terminated would also be the decomposition. |
| `:mode cli` emits `print (step args)`: no IO, no exit status, zero in-tree users | SHAPES | `MODE-CLI-1` | A straight-line program: read seven files, decide, exit. Instead: a nine-arm console state machine driven by stdin. This is the single largest contributor to 58 code lines becoming 278. |
| nullary `wasi.*` builtins bypass capability enforcement | COSMETIC | `CAP-NULLARY-1` | Found by tripping over it: the module typechecked while using `wasi.proc.args` with no `wasi.proc` import. Filed 2f38d3a. Import added anyway. |
| no env access | COSMETIC | **unfiled** | `REPO_ROOT` became `--root`. All four env uses in scope are config argv can carry, so nothing was lost. |

**Two of these were previously unknown**, and one is a divergent stdlib function
that typechecks and verifies. That is the yield the gap discipline exists for.
Both were filed as roadmap rows on 2026-08-07 (campaign prerequisite P2), so
this table cites tags rather than admissions; the gate that reads it caught the
staleness the moment the rows landed.

## 6. Differential plan

[`scripts/version_gate_cover.py`](../../scripts/version_gate_cover.py), fourteen
trees. Both implementations run over each; every mutant asserted to fail under
**both** before their answers are compared.

| Cell | Mutation | Criterion | Expect |
|---|---|---|---|
| V0 | none | all | pass |
| V1 | README banner to v0.14.86 | C1 | fail |
| V2 | README line 1 loses its version | C1 extract | fail |
| V3 | README absent | C1 extract | fail |
| V4 | CHANGELOG heading to v0.14.86 | C2 | fail |
| V5 | CHANGELOG loses its `## v` heading | C2 extract | fail |
| V6 | package.yaml to 0.14.86 | C1 | fail |
| V7 | package.yaml loses `version:` | C1 extract | fail |
| V8 | llmll.cabal to 0.14.86 | C1 | fail |
| V9 | schema const to 0.12.0 | C3 | fail |
| V10 | ParserJSON to 0.12.0 | C3 | fail |
| V11 | schema `$id` to `/schemas/v0.10/` | C4 | fail |
| V12 | schema is not JSON | C3, C4 | fail |
| V13 | **negative control**: all five sites move to v0.99.0 together | all | **pass** |

V13 is the one that matters: it pins the gate to *the sites agreeing* rather
than to a literal version, which is the anti-hardcoding property
`crux-validate-subject-hardcoded` exists for one directory over.

**One deliberate narrowing.** The comparison is over the gate's own
`DRIFT-CI-1` lines, not raw output. The shell gate leaks its tools' stderr
(`head: No such file or directory`, `jq: parse error`) ahead of its message; the
port emits neither, because a failed `wasi.fs.read` answers `RErr` and a failed
`json-parse` answers `Error`. Same decision, same exit code; the chatter is not
part of it.

## 7. Retirement

`scripts/version_gate.sh` is deleted, and this document flips to `retired`, when
all of:

- **P1 is clear** (campaign §3): tags and images exist for the current release,
  so `version-gate.yml` can pull a binary;
- `version-gate.yml` and `docker-publish.yml` both invoke the port;
- one release has elapsed with both running.

Until then the state is `oracle` and the shell script stays.

## 8. Decisions taken

Four, and **three were made at the keyboard and reported afterwards.** That is
the failure this campaign's RFC-first workflow exists to prevent, recorded here
rather than smoothed over.

1. **The port does not replace the shell script.** A CI policy call, not an
   implementation detail. Should have been asked before the code existed. It was
   the right call for the reason in §3, and being right does not make the
   sequence right.
2. **It runs from `build_smoke.sh` stage 10 rather than its own workflow step.**
   Chosen because stage 8 and 9 already have the build-and-find-binary idiom, so
   this adds less new shell than a new step plus a new script. Reasonable;
   unasked.
3. **The `git describe` tag check was dropped.** It was advertised as a reason to
   pick this gate first: the reference compares banners to each other and to no
   tag, which is exactly why four releases went untagged. Adding it would have
   reddened CI immediately, since the debt is live. Dropping it silently was
   wrong; it belongs in §7 of the RFC as a follow-on, and it is now campaign
   prerequisite P1.
4. **Facts travel as a `Json` object rather than a nine-deep pair chain.**
   Implementation, correctly decided at the keyboard. A wrong key answers `""`
   and the criterion fails by name; nine positional fields would have given nine
   chances to read the cabal version out of the changelog slot and typecheck.
