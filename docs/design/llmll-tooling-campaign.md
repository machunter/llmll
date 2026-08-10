---
name: llmll-tooling-campaign
title: "TOOL-LL: this repository's CI gates, written in LLMLL and actually used"
status: "Rev 4, IN FLIGHT. Scope and retirement SETTLED by user adjudication 2026-08-07; DISTRIBUTION AMENDED 2026-08-10 in §3, at the second port to meet the same constraint, and it now distinguishes shipping a COMPILER from shipping a COMPILED PORT and requires a wholesale relocation rather than a split. Six CI gates in scope (~900 code lines). FOUR are ported and running as oracles: DRIFT-CI-1 (TOOL-RFC-001, retroactive), the refute-crux gate (TOOL-RFC-002, the first written RFC-first), doc-claims (TOOL-RFC-003, released v0.14.92) and doc-archive (TOOL-RFC-004, released v0.14.95). 005 (doc-path-lint) has its RFC WRITTEN (TOOL-RFC-005) and no port yet, `tool_state: blocked`; it was unblocked at v0.14.96 by `REGEX-LOWER-1`, a compiler fix that took the critical path through compiler work for the first time and whose census corrected its own row; 006 stays last. 005's subject is ADVISORY and exits 0 by design, so its cover compares stdout text rather than exit codes, and it raised FOUR owed gaps, the largest number any port has produced. THE STANDARD HAS NINE SECTIONS, not eight: `## 7. Verification` was added at v0.14.94 and asks what survives the reference's deletion, since §8 deletes the instrument §6 is checked against. Each of the last three ports found something its own feasibility read had declared absent: 002 found three defects, 003's cover found a COMPILER defect (TOOL-ENCODING-1, shipped v0.14.93) that neither implementation had, and 004's cover found three defects that its live green run could not reach."
date: 2026-08-07
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, experiment-lead, professor, user]
---

# TOOL-LL: the CI gates in LLMLL

**Goal, as set by the user.** Every tool in this repository is written in LLMLL
and is *actually used*, replacing the Python and shell scripts, each with an
accompanying RFC. Every gap that stops real code from running is evaluated as a
language question rather than worked around.

This document is the standard. [`TOOL-RFC-TEMPLATE.md`](TOOL-RFC-TEMPLATE.md)
is what you copy; [`scripts/tests/test_tool_rfc_standard.py`](../../scripts/tests/test_tool_rfc_standard.py)
is what enforces it, because a standard no gate reads is a preference. §9 says
whose decision each finding is.

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

| Gate | Code | In CI? | Status |
|---|---|---|---|
| [`version_gate.sh`](../../scripts/version_gate.sh) | 58 | yes, 2 jobs | **PORTED**, TOOL-RFC-001 |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 124 | yes, since P3 | **PORTED**, `tool_state: oracle`, TOOL-RFC-002 |
| [`doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh) | 97 | yes | **PORTED**, `tool_state: oracle`, TOOL-RFC-003 |
| [`doc_archive_gate.sh`](../../scripts/doc_archive_gate.sh) | 125 | yes, `spec-roundtrip` since 004 | **PORTED**, `tool_state: oracle`, TOOL-RFC-004 |
| [`doc_path_lint.py`](../../scripts/doc_path_lint.py) | 132 | yes | **RFC WRITTEN**, TOOL-RFC-005, `tool_state: blocked` (no port yet) |
| [`build_smoke.sh`](../../scripts/build_smoke.sh) | 381 | yes | last, it runs the others |

**`refute-crux-gate.sh` was not invoked by any workflow.** It was a `make`
target only, despite its own header calling itself a CI gate. It freezes 80
verify verdicts, including every driver refute crux and the wave's, and it ran
only when a human typed `make`.

That matters to this campaign more than to the gate. Porting a gate CI does not
run produces an LLMLL program CI does not run, which is exactly the §10 failure
mode. **So prerequisite P3: wire it into a workflow first, in shell.** Only then
is porting it a port of something that decides. Found by applying this
standard's §1 to it, before any code was written, which is what the RFC-first
order is for.

**P3 is done, 2026-08-07.** It runs in `version-gate.yml`'s `spec-roundtrip`
job, which is the Stack-bearing one: the gate shells out to
`stack exec llmll --` and the other job is deliberately toolchain-free. Placed
after the cheap doc-claims gate and before `build_smoke.sh`, so the job still
orders its gates cheap to expensive. It adds ~3 min, and the jq the script
requires is now asserted rather than assumed. The port, 002, now has a wired
gate to port.

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

**AMENDED 2026-08-10, by user adjudication, at the second port to meet the same
constraint.** The sentence above conflates two artifacts, and the conflation is
what made TOOL-RFC-001 predict that its deviation would resolve when P1 cleared.
It did not, and TOOL-RFC-004 recorded that an amendment was owed. The amended
form:

> The published release image delivers the **compiler**. It does not deliver a
> **compiled port**, and no mechanism publishes port binaries today. Until one
> does, a port runs only in a **toolchain-bearing job**. A gate whose reference
> lives in a toolchain-free job therefore relocates **wholesale**, reference and
> port together, rather than splitting across two jobs.

Measured off [`Dockerfile`](../../Dockerfile) and re-confirmed at 005: the
runtime stage is `debian:bookworm-slim` installing only
`z3 libgmp10 zlib1g ca-certificates`, and it copies exactly two executables,
`llmll` and `fixpoint`. There is no GHC and no Stack, and `llmll build` shells
out to `stack build`.

**The wholesale clause is the part that carries consequence.** Splitting is what
TOOL-RFC-001 did, and §4's retirement cannot delete a reference that is the only
thing running in the job that matters. Both DRIFT-DOC-3 (004) and DRIFT-DOC-4
(005) relocate under this rule.

**This blocked the campaign at its second port until 2026-08-07, and the block
was never technical.** [`docker-publish.yml`](../../.github/workflows/docker-publish.yml)
builds and publishes on a `vX.Y.Z` tag push, and four releases had shipped with
no tag, so the newest image predated every tool in this campaign. **Cleared:**
`v0.14.84` through `v0.14.87` are tagged and published, and `:latest` is
v0.14.87.

**Prerequisite P1: clear the tag debt. DONE 2026-08-07.** Targets were derived
in [`driver-ll-phase4-RESTART.md`](driver-ll-phase4-RESTART.md) §10 and
re-verified before each push. This was the first thing the campaign needed and
it was release hygiene, not language work.

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

| Gap | Disposition | Blocks, of the six in scope | Status |
|---|---|---|---|
| `MODE-CLI-1` | SHAPES | **every tool** | filed 2026-08-07 |
| `SPLIT-EMPTY-1` (with the no-character-decomposition half) | SHAPES | every scanner | filed 2026-08-07 |
| `REGEX-LOWER-1` | BLOCKS | `doc_path_lint` (005) | **SHIPPED v0.14.96**, and its census corrected its own row |
| `FS-WALK-1` | BLOCKS | `build_smoke` (006) only | filed 2026-08-07, **not urgent** |
| no env access (`wasi.proc.args` exists, no env builtin) | COSMETIC | none; argv carries it | unfiled, nothing lost. **TESTED at 005 and the disposition HOLDS**: `wasi.proc.args` delivers `--strict extra` as `argc=2` to a built binary with no `--` separator. The row does not move; only the invocation changes, which is a porting decision |
| `CAP-NULLARY-1` | COSMETIC | none | filed 2026-08-07 |
| `FS-STAT-1` | BLOCKS | none in scope | filed, open |
| `FS-EXISTS-1` (proposed): nothing answers "is there a file here" without moving its bytes | SHAPES | `doc_path_lint` (005) | **unfiled, owed**, raised by 005. Deliberately NOT folded into `FS-STAT-1`, which answers about an artifact's AGE |
| `REGEX-CAPTURE-1` (proposed): `regex-match` returns `bool`, so no capture and no scan | SHAPES | every scanner | **unfiled, owed**, raised by 005. Independent of `REGEX-LOWER-1`, which was about lowering and shipped |
| `REGEX-CASE-1` (proposed): no case-insensitive matching; TDFA rejects `(?i)` and no lowercase builtin exists | SHAPES | `doc_path_lint` (005) | **unfiled, owed**, raised by 005 and firing on real prose, not only on a fixture |
| `PATH-NORM-1` (proposed): no path normalization for `..` | SHAPES | `doc_path_lint` (005) | **unfiled, owed**, raised by 005; 58 of 947 live citations need it |

**`MODE-CLI-1` is the largest and it was invisible before a port existed.**
`:mode cli` emits `print (step args)`: a pure function, no `Command` performed,
no exit status, and zero in-tree users. So `console` is the only usable entry
mode for a program that touches the world, every LLMLL tool is a stdin-driven
step machine, and that is the single largest reason 58 code lines of shell
became 278 of LLMLL. It is a language-surface question, not a bug.

**A first count of `FS-WALK-1` said three of six and was wrong.** It measured
`scripts/` generally rather than the six gates in scope. Exactly one gate needs
a true recursive walk and it is the one scheduled last; `doc_archive_gate.sh`
needs a two-level enumeration that composes from flat lists. Recorded because
the census is the deliverable, and a census that inflates its own blast radius
is the failure this campaign's §10 warns about in the other direction.

## 6. The workflow

One port is one RFC and one merge sequence:

1. **RFC first.** Copy [`TOOL-RFC-TEMPLATE.md`](TOOL-RFC-TEMPLATE.md) to
   `docs/design/tool-rfc-NNN-<slug>.md`. It is not a formality: §3 (distribution)
   and §9 (decisions taken) are the sections that record choices which are
   *policy rather than implementation*, and those are the ones an author
   otherwise makes silently at the keyboard. DRIFT-CI-1 is the worked example of
   that failure mode; see TOOL-RFC-001 §9.
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
- every RFC carries the required frontmatter and all nine sections;
- every RFC names a subject script that exists, or declares `retired`;
- the tri-state of §4 agrees with the filesystem;
- every gap row carries one of the three dispositions, and every BLOCKS or
  SHAPES row cites a roadmap tag;
- the campaign's own scope table agrees with the RFCs that exist.

## 8. Sequence

- **P1** clear the tag debt (§3). **Done 2026-08-07**: `v0.14.84` to `v0.14.87`
  tagged and published. It blocked every port's distribution step.
- **P2** file the unfiled gaps (§5). **Done 2026-08-07**: `MODE-CLI-1`,
  `SPLIT-EMPTY-1`, `FS-WALK-1`.
- **P3** wire `refute-crux-gate.sh` into a workflow, in shell (§2). **Done
  2026-08-07**: `version-gate.yml`, `spec-roundtrip` job. It had to precede 002,
  or 002 would have ported something CI does not run.
- **001** DRIFT-CI-1 version gate. **Ported, state `oracle`.**
- **002** refute-crux gate. **PORTED 2026-08-07**,
  [TOOL-RFC-002](tool-rfc-002-refute-crux.md), state `oracle`: the first port
  written RFC-first, its three policy calls asked before the code rather than
  reported after. All 80 verdicts reproduced, agreeing with the reference.
  **Its feasibility read concluded "no BLOCKS gap and no new gap" and was wrong
  on both counts**, which is the campaign's own premise landing on the campaign:
  building it found `FD-CAPTURE-1` (BLOCKS, fixed in the same change),
  `JSON-SCALAR-1` and `PROC-MERGE-1`. §5 keeps the wrong conclusion quoted
  above the correction rather than amending it.
- **003** doc-claims gate. **PORTED 2026-08-08**,
  [TOOL-RFC-003](tool-rfc-003-doc-claims.md), state `oracle`, released v0.14.92.
  Filed `SKIP-SILENT-1`. Its differential cover found `TOOL-ENCODING-1` in the
  COMPILER, and the three NEGATIVE CONTROLS are what caught it: every mutation
  cell agreed while both implementations failed identically.
- **004** doc-archive gate. **PORTED 2026-08-09**,
  [TOOL-RFC-004](tool-rfc-004-doc-archive.md), state `oracle`, unreleased.
  Port at [`tools/doc-archive/docarchive.llmll`](../../tools/doc-archive/docarchive.llmll)
  with its verified core in
  [`adjudicate.llmll`](../../tools/doc-archive/adjudicate.llmll); cover at
  [`doc_archive_cover.py`](../../scripts/doc_archive_cover.py), **17 cells: 14
  mutations and 3 negative controls, all ok**. **DRIFT-DOC-3 moved out of the
  fast `version-gate` job into `spec-roundtrip`**, because the port needs a
  compiler to build and the published image ships none: a knowing deviation
  from the settled distribution, recorded in §8 of the RFC.
  **The cover found three defects the live run could not reach**: criterion 1
  unimplemented, criterion 7 missing its remedy epilogue, and two cover cells
  wrong by construction. The live corpus declares one disposition of four and
  contains none of the four violation classes, so a live green run grades about
  a twentieth of the specified behaviour.
- **005** doc-path lint. **RFC WRITTEN 2026-08-10**,
  [TOOL-RFC-005](tool-rfc-005-doc-path-lint.md), `tool_state: blocked`: the RFC
  exists and the port does not, which is the RFC-first order working as intended.
  It was gated on `REGEX-LOWER-1`, and **this is where the campaign first stopped
  being port work**: that row was a compiler fix, so the critical path ran
  through the compiler team for one release and is now back on ports. The fix's
  census corrected the row it closed, `regex-match` and `is-valid?` proving to be
  two classes rather than the one unmeasured pair the row recorded.
  **The subject is ADVISORY and exits 0 by design**, so §6 compares stdout text
  rather than exit codes, and §8's "wired into a job that decides" condition is
  restated for a gate that decides nothing.
  **It corrects an expectation inherited from 004.** 004's live corpus graded
  about a twentieth of the behaviour, and 005's was assumed to be the same. It is
  not: all four exemption classes are live-exercised, each the SOLE rescuer of 13
  to 19 citations, and the historical-file skip is worth 268, so the SUPPRESSION
  half has a live instrument and only the REPORTING half is fixture-only. One
  filter, `site/` and `node_modules/`, is worth exactly ZERO and can never be
  exercised by any corpus state, because the six files it removes contain no
  citations at all.
  It raised **four owed gaps**, the largest number any port has produced, and its
  distribution finding is what the §3 amendment above answers.
- **006** build-smoke. Last: it is the harness that runs the others, so porting
  it is an LLMLL program orchestrating LLMLL programs, and it should inherit
  five ports' worth of settled pattern rather than invent it.

## 9. Roles: who decides what

**This campaign is experiment-lead work, and the distinction is not
bookkeeping.** It runs a loop (port a gate, observe what the language cannot do,
file the gap) and its analytical authority ends at surfacing. It offers two
shapes for `MODE-CLI-1` and picks neither. Deciding is downstream, and the
routing is:

| Work | Whose | Note |
|---|---|---|
| the campaign, the RFCs, the ports | **nobody's role skill** | plain engineering; the RFC author is whoever ports |
| `MODE-CLI-1`: complete `:mode cli` or withdraw it | **language-team**, then compiler-engineer | a language-surface question; a fixture is owed before either fix |
| `SPLIT-EMPTY-1`: what `string-split ""` answers | **language-team** first | the value chosen decides whether the no-decomposition half closes with it, so the order matters |
| `SPLIT-EMPTY-1`: the divergence itself | **compiler-engineer** | one equation |
| `FS-WALK-1` | **language-team**, held | an unbounded walk in a bounded idiom is a design question |
| `CAP-NULLARY-1` | **compiler-engineer** | sits under `CAP-1-REAL` |
| P1 (tags, images) | **the user** | outward-facing |

**The first version of this document was stamped `author: language-team`** by
copying the DRIVER-LL campaign's frontmatter rather than deciding it. That
implied the campaign had authority over the spec questions it raises, which is
exactly what it must not have: a loop that both finds gaps and rules on them has
no independent check on either.

## 10. What would make this campaign a failure

Recorded now, while it is cheap to say:

- **Ports that are never used.** A tool that ships beside a shell script that
  still decides is a demo. The tri-state in §4 exists to make that visible.
- **Gaps worked around silently.** The census in §5 is the deliverable; the
  ports are the instrument that produces it. A port that meets no gaps and files
  nothing has probably not been examined.
- **A line count read as progress.** 58 lines of shell became 278 of LLMLL. The
  campaign's claim is that the gates are *decided by LLMLL programs*, never that
  the result is smaller.
