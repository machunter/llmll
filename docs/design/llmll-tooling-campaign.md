---
name: llmll-tooling-campaign
title: "TOOL-LL: this repository's CI gates, written in LLMLL and actually used"
status: "Rev 1, IN FLIGHT. Scope, distribution and retirement SETTLED by user adjudication 2026-08-07. Six CI gates in scope (~900 code lines). One is ported and running (DRIFT-CI-1, TOOL-RFC-001, filed retroactively because it shipped before this standard existed). The campaign is BLOCKED at its distribution step until the tag debt clears: the chosen mechanism is a published release image and the newest tag is v0.14.83 against banners reading 0.14.87, so the image four releases of tooling would pull does not exist."
date: 2026-08-07
author: language-team
consumers: [compiler-engineer, documentation-lead, experiment-lead, professor, user]
---

# TOOL-LL: the CI gates in LLMLL

**Goal, as set by the user.** Every tool in this repository is written in LLMLL
and is *actually used*, replacing the Python and shell scripts, each with an
accompanying RFC. Every gap that stops real code from running is evaluated as a
language question rather than worked around.

This document is the standard. [`TOOL-RFC-TEMPLATE.md`](TOOL-RFC-TEMPLATE.md)
is what you copy; [`scripts/tests/test_tool_rfc_standard.py`](../../scripts/tests/test_tool_rfc_standard.py)
is what enforces it, because a standard no gate reads is a preference.

---

## 1. Why this and not more DRIVER-LL

DRIVER-LL answered "can LLMLL reach the OS": 3,938 driver lines across nine
releases produced exactly two genuine expressiveness complaints, and eight of
the remaining costs became releases. What it did not answer is whether an LLMLL
program does work anyone needs done. Every one of the thirteen LLMLL programs
with an entry point exists to exercise the compiler.

A CI gate is the smallest artifact for which that stops being true. It decides
whether a change may merge. When it is wrong, someone is blocked; when it is
absent, a defect ships. That is the property the campaign is buying, and it is
why the scope is gates rather than the larger and more impressive number.

## 2. Scope, settled

**The six CI gates, and nothing else.** Measured at 2026-08-07, code lines
excluding comments and blanks:

| Gate | Code | Status |
|---|---|---|
| [`version_gate.sh`](../../scripts/version_gate.sh) | 58 | **PORTED**, TOOL-RFC-001 |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 124 | next |
| [`doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh) | 97 | |
| [`doc_archive_gate.sh`](../../scripts/doc_archive_gate.sh) | 125 | |
| [`doc_path_lint.py`](../../scripts/doc_path_lint.py) | 132 | blocked, `REGEX-LOWER-1` |
| [`build_smoke.sh`](../../scripts/build_smoke.sh) | 381 | last, it runs the others |

**Deliberately out of scope**, each for a stated reason rather than by omission:

- **The covers** (`driver_ll_cover.py`, `wave_cover.py`, `version_gate_cover.py`,
  ~1,200 lines). They are the oracles the ports are checked against. Porting an
  oracle to the language under test makes it an oracle about itself.
- **`rfc_to_implementation.py`** (1,489 lines). It is already DRIVER-LL's port
  target; counting it here would double-count Phases 4 and 5.
- **`scripts/tests/*.py`.** They are tests, not tools, and the no-toolchain tier
  exists precisely so some checks run where no compiler does.

## 3. Distribution, settled

**Jobs pull a published release image.** Chosen over building once per run and
sharing artifacts, over giving every job a toolchain, and over keeping a shell
fallback per gate. The last of those is what DRIFT-CI-1 does today and it is
explicitly a transitional state, not the pattern.

**This blocks the campaign at its second port and the block is not technical.**
[`docker-publish.yml`](../../.github/workflows/docker-publish.yml) builds and
publishes on a `vX.Y.Z` tag push, and the newest tag on origin is `v0.14.83`
while the five banner sites read `0.14.87`. Four releases have no image. Until
that clears, a job that pulls an image pulls one that predates every tool in
this campaign.

**Prerequisite P1: clear the tag debt.** Targets are derived and recorded in
[`driver-ll-phase4-RESTART.md`](driver-ll-phase4-RESTART.md) §10. This is the
first thing the campaign needs and it is release hygiene, not language work.

## 4. Retirement, settled

**Keep the original as a differential oracle for one release, then delete it.**
Concretely, three states, and a tool is in exactly one:

| State | The original | CI runs | The port's oracle |
|---|---|---|---|
| `oracle` | present | both | the original, over a mutation battery |
| `retired` | deleted | the port | the port's own cover |
| `blocked` | present | the original | the port does not exist |

A port enters `oracle` when its differential cover is green, and leaves for
`retired` at the next release, at which point the original is deleted **in the
same commit** that flips the state. The gate in §7 asserts the tri-state against
the filesystem, so a doc that claims `retired` while the script is still there
reddens.

**Why one release and not immediately.** The differential cover is the only
oracle a port has that its author did not also write. Deleting the reference on
merge trades that for nothing; keeping it forever doubles maintenance and means
the scripts are never retired, which is the goal.

## 5. The gap discipline

This is the campaign's fourth clause and its most important one: *every gap that
stops real code from running is evaluated as a language question.*

Every gap a port meets takes **exactly one of three dispositions**, and each
carries a different evidential burden:

- **BLOCKS.** The port cannot proceed. The language work ships first, as its own
  roadmap row. The port's RFC records the row and stops.
- **SHAPES.** The port proceeds, and the language forced a design it would not
  otherwise have. The RFC **must state what the design would have been** and
  cite a roadmap row for the gap. This is the disposition that gets skipped, and
  skipping it is how a language limitation becomes an unexamined house style.
- **COSMETIC.** The port is unchanged; the gap is noted and nothing follows.

**A gap may never be silently worked around.** The version-gate port met four
and all four are recorded at their sites; two of them were previously unknown
defects. That is the yield this discipline is for, and it is the reason the
ports are worth doing even where the shell script was fine.

**Known gaps, at v0.14.87.** Leverage order for the six gates in scope:

| Gap | Disposition | Blocks | Status |
|---|---|---|---|
| `REGEX-LOWER-1` | BLOCKS | `doc_path_lint`, 4 others touch it | filed, open |
| no recursive directory walk | BLOCKS | 3 of 6 gates | **not filed** |
| `string-split` with an empty separator diverges | SHAPES | any scanner | **not filed** |
| `:mode cli` is a stub (`print (step args)`, no IO, no exit status) | SHAPES | every tool | **not filed** |
| no character decomposition, no ranges | SHAPES | every scanner | see above |
| no env access (`wasi.proc.args` exists, no env builtin) | SHAPES | 4 scripts, all config argv can carry | **not filed** |
| `CAP-NULLARY-1` | COSMETIC here | nothing in scope | filed 2026-08-07 |
| `FS-STAT-1` | BLOCKS | nothing in scope | filed, open |

Three of these have no roadmap row and the discipline above says they must, so
**filing them is prerequisite P2.** The `:mode cli` one is the largest: it is
why an 89-line straight-line script became a nine-arm console state machine, and
it is a language-surface question rather than a bug.

## 6. The workflow

One port is one RFC and one merge sequence:

1. **RFC first.** Copy [`TOOL-RFC-TEMPLATE.md`](TOOL-RFC-TEMPLATE.md) to
   `docs/design/tool-rfc-NNN-<slug>.md`. It is not a formality: §3 (distribution)
   and §8 (decisions taken) are the sections that record choices which are
   *policy rather than implementation*, and those are the ones an author
   otherwise makes silently at the keyboard. DRIFT-CI-1 is the worked example of
   that failure mode; see TOOL-RFC-001 §8.
2. **Feasibility read against the language**, RFC §4 and §5. Every needed
   feature marked available or a gap, every gap given a disposition.
3. **Implement** under `tools/<tool>/`.
4. **Differential cover** under `scripts/`, comparing port to reference over a
   mutation battery. Every mutant asserted to fail under **both** before their
   answers are compared: a battery where everything passes agrees perfectly and
   detects nothing.
5. **Wire it in**, and record which job and how the binary arrives.
6. **State `oracle`.** Both run.
7. **Retire at the next release**: delete the reference and flip the state in
   one commit.

## 7. What the gate enforces

[`test_tool_rfc_standard.py`](../../scripts/tests/test_tool_rfc_standard.py),
no toolchain required:

- every LLMLL program under `tools/` that CI invokes has an RFC;
- every RFC carries the required frontmatter and all eight sections;
- every RFC names a subject script that exists, or declares `retired`;
- the tri-state of §4 agrees with the filesystem;
- every gap row carries one of the three dispositions, and every BLOCKS or
  SHAPES row cites a roadmap tag;
- the campaign's own scope table agrees with the RFCs that exist.

## 8. Sequence

- **P1** clear the tag debt (§3). Blocks every port's distribution step.
- **P2** file the three unfiled gaps (§5). Blocks nothing; owed by the discipline.
- **001** DRIFT-CI-1 version gate. **Ported, state `oracle`.**
- **002** refute-crux gate. Next, and the first port to be written RFC-first.
- **003** doc-claims gate.
- **004** doc-archive gate.
- **005** doc-path lint. Gated on `REGEX-LOWER-1`.
- **006** build-smoke. Last: it is the harness that runs the others, so porting
  it is an LLMLL program orchestrating LLMLL programs, and it should inherit
  five ports' worth of settled pattern rather than invent it.

## 9. What would make this campaign a failure

Recorded now, while it is cheap to say:

- **Ports that are never used.** A tool that ships beside a shell script that
  still decides is a demo. The tri-state in §4 exists to make that visible.
- **Gaps worked around silently.** The census in §5 is the deliverable; the
  ports are the instrument that produces it. A port that meets no gaps and files
  nothing has probably not been examined.
- **A line count read as progress.** 58 lines of shell became 278 of LLMLL. The
  campaign's claim is that the gates are *decided by LLMLL programs*, never that
  the result is smaller.
