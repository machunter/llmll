---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, 2026-08-12, after v0.14.99. FIVE ports of six are complete and PORT 006 IS THE ONLY WORK LEFT. PORT 005 IS RETIRED at v0.14.99, which is the campaign's FIRST retirement: the reference and its 22-cell differential cover are both deleted, and NO INSTRUMENT GRADES THE PORT NOW. The user accepted that cost on 2026-08-12 with the cost stated first. THE RETIREMENT PRODUCED A RULE AND PORT 006 MUST USE IT: move the subject script aside, run the gate, read the result, and do all three BEFORE you delete the subject. Deleting the 005 reference broke 13 prose citations in 6 files, which the RFC section 8 precondition list did not ask about, and the measurement was free. THE TAG DEBT IS ZERO: the banner, the last tag and the newest CHANGELOG entry agree, and the tag run published the image. Measure that anyway; section 0 gives the four commands and this line has been incorrect before. v0.14.98 SHIPPED THE TWO GAPS PORT 006 RAISED, before the port was written: PROC-STDIN-1 gave wasi.proc.run a stdin path, and PROC-STDIN-SHARE-1 closed with it. That is the campaign's FIRST gap closed by the compiler rather than worked around by a port. So DO NOT write a drive helper and DO NOT write /bin/sh -c; the port passes a path. THE RFC IS WRITTEN: read tool-rfc-006-build-smoke.md before any port code. NO QUESTION IS OPEN for port 006. The port projects to about 1,400 code lines, not the 2,500 an inherited 4.8x ratio gave; that ratio was the FIRST port's and the five decline to 2.23. v0.14.98 also removed the last four find | head -1 sites from version-gate.yml, so that idiom is absent from the repository. NOTHING NOW STOPS A BROKEN PATH CITATION FROM REACHING main: the user deleted the reference's pytest file on 2026-08-11, and the reference itself at v0.14.99. Both remaining checks report and do not decide. This file shows where the work is. llmll-tooling-campaign.md shows what the standard says. If the two disagree about the standard, use the campaign file. If they disagree about state, measure the state again."
date: 2026-08-12
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, experiment-lead, user]
style: "ASD-STE100 Simplified Technical English. Trial. See section 0."
---

# TOOL-LL: restart record

## 0. How to use this file

Read this file first. Then read
[`llmll-tooling-campaign.md`](llmll-tooling-campaign.md).

### The language of this file

This file uses Simplified Technical English (ASD-STE100). These rules apply:

- Write instructions with 20 words or fewer.
- Write descriptions with 25 words or fewer.
- Give one instruction in each sentence.
- Use the active voice.
- Use articles.
- Write six sentences or fewer in each paragraph.
- Give one meaning to each word.

Technical names keep their usual form. File paths, tag names such as
`TOOL-ENCODING-1`, and command names are technical names.

Approved word choices in this file: a gate *passes* or *fails*. It is not
"green" or "red". A record becomes *incorrect*. It does not "rot" or "go
stale". A defect *causes a failure*. It does not "bite".

### Measure the state before you use it

A record in this repository became incorrect at a handoff three times. Do these
four steps first. Do them before you read section 1.

1. Run `git describe --tags --abbrev=0`. This gives the last tag.
2. Run `git rev-list --count $(git describe --tags --abbrev=0)..HEAD`. This
   gives the count of unreleased commits.
3. Run `head -1 LLMLL.md`. This gives the version banner.
4. Run `gh run list --branch main --limit 3`. This gives the CI result.

Compare the four results with section 1. If one result disagrees, section 1 is
incorrect. Correct section 1 before you do other work.

---

## 1. State, measured 2026-08-12, after v0.14.98

| Item | Value | How it was measured |
|---|---|---|
| Last tag | `v0.14.99` | `git describe --tags --abbrev=0` |
| Unreleased commits | **0**, measured 2026-08-12 | `git rev-list --count v0.14.99..HEAD` |
| Version banner | `v0.14.99` | `head -1 LLMLL.md` |
| CI on `main` | measure it | `gh run list --branch main` |
| Newest CHANGELOG entry | `v0.14.99` | `grep "^## " CHANGELOG.md` |

The banner, the last tag and the newest CHANGELOG entry agree, and **the tag
debt is zero.** The tag run published `ghcr.io/machunter/llmll:v0.14.98` and
moved `:latest` to the same digest.

**v0.14.98 shipped the two gaps that port 006's RFC raised**, before the port
was written. `PROC-STDIN-1` gave `wasi.proc.run` a stdin path and
`PROC-STDIN-SHARE-1` closed with it. It also removed the last four
`find | head -1` sites from `version-gate.yml`, so that idiom is now absent
from the repository.

**v0.14.99 RETIRED port 005. This is the campaign's first retirement.** The
reference and its differential cover are deleted. The port is the only
DRIFT-DOC-4 now, and no instrument grades it. Section 2 gives the rule that
this retirement produced. Port 006 must use that rule.

**This table was incorrect twice in two days, and both times a measurement
caught it.** On 2026-08-11 it claimed one unreleased commit against a measured
two. It then claimed two against v0.14.97 while the tree had moved to v0.14.98.
Do not read this table. Run the four commands in section 0.

**A warning that stays true.** The version gate cannot find an owed release. It
compares the five banners with each other. It compares them with no git tag. So
the gate passes while a whole port sits on `main` with no release note. That
happened at v0.14.97: ten commits and zero CHANGELOG lines about TOOL-005.

**Do this before you release.** Change the version number in
`compiler/package.yaml` and in `compiler/llmll.cabal`. The documentation-lead
writes the release note after that change. The documentation-lead must not
change the version number.

**A warning about the table above.** Each count changes with the next commit.
Measure it again. Do not read it from this table.

The CI row covers three runs: `version-gate` on `main`, and `docker-publish` on
`main` and on the tag. A tag push starts the image publish. Look at all three.

---

## 2. The next work: port 006

**Port 005 is complete.** It is `tool_state: oracle`. Run `31439956284` passed.
Both implementations run in `spec-roundtrip`, as adjacent steps.

Port 006 (`build_smoke.sh`) is the last port. **IT IS NOT BLOCKED.**
`FS-WALK-1` closed as COSMETIC on 2026-08-10. The roadmap holds that row in its
closed-rows section.

### Port 006 is STARTED. Read this before you write a stage

**The port module exists.** It is
[`tools/build-smoke/buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll).
It holds the spine and **stage 1 of fourteen**. It builds and it runs.

**`tool_state` stays `blocked` and that word is now approximate.** The tri-state
is `blocked`, `oracle` and `retired`. It has NO value for "started and
incomplete". `blocked` is the only state the RFC gate accepts here, because
`oracle` asserts that both implementations decide over one tree in one job.
**Give this vocabulary gap to the user.** Do not invent a fourth state.

**Two facts the spine settled. Copy them; do not re-derive them.**

1. The state is `((Bs, Ctl), Command)`. `Bs` holds a `Json`. `sequencer.llmll`
   and `pathlint.llmll` use this shape. A positional tuple grows one field for
   each stage. Then it renumbers each call site.
2. `:done?` needs a `Done` phase after an `Ending` phase. The `Ending` phase
   prints. The `Done` phase stops.

**D3 IS DISCHARGED, 2026-08-12.** The RFC told you to probe two rows before you
write the stages that use them. Both are probed. The probe is
[`scripts/build-smoke/d3_probe.llmll`](../../scripts/build-smoke/d3_probe.llmll).

- `wasi.fs.sha256` gives `RText`. The digest is lowercase hex. It agrees with
  `shasum -a 256` for each byte. **This needed a measurement.** `LLMLL.md` §13
  says the SHA-1 in the preamble is a simplified stub.
- A failed run gives `RErr`. **The step machine continues after it.** The
  message shows `does not exist` for an absent file. It shows
  `permission denied` for a file with no execute permission. The subject's
  `-perm -111` test gives one bit. Thus the port can say more than the subject.

**Stage 1 is done and it FAILS correctly.** Give the program a `PATH` with no
`stack` and no `ghc`. It prints `BUILD-GATE-1 FAIL`. This control uses a real
environment. It does not use a changed source file.

**Stage 2 is next, and stage 2 needs a decision that stage 1 did not.** The
subject reads the `LLMLL_BIN` environment variable. **No builtin reads an
environment variable.** The campaign disposed that row COSMETIC because "argv
carries it". So the port must take the compiler path as an argument. **Write
that contract before you write stage 2.** Stage 2a then makes the path
absolute, with `stack path --local-install-root`, first from the current
directory and then from `compiler/`. Subject line 118 gives the full rule.

**THE RFC IS WRITTEN and it is Rev 4.** Read
[`tool-rfc-006-build-smoke.md`](tool-rfc-006-build-smoke.md) before you write
any port code. Four things it settled, each by a probe:

1. **The port is feasible.** One complete stage was written in LLMLL, built and
   run. It passes on a good fixture and fails on a broken one.
2. **The size fear was wrong.** The port projects to about 1,400 code lines, not
   2,500. The 4.8 ratio is the FIRST port's; the five decline to 2.23.
3. **The real scope question was stdin, and the compiler answered it.**
   Thirteen sites feed a child on stdin and `wasi.proc.run` could not.
   **`PROC-STDIN-1` SHIPPED a seventh parameter, a stdin path, at v0.14.98 on
   2026-08-12.**
   The port passes a path, as it passes a stdout path. **Do not write a `drive`
   helper and do not write `/bin/sh -c`.** D1 chose that workaround before the
   compiler moved, and the RFC records it as superseded.
4. **Three gaps are filed and TWO ARE SHIPPED at v0.14.98**: `PROC-STDIN-1`,
   `PROC-STDIN-SHARE-1` and
   `PROC-ENV-1`. The second was a compiler defect. It was latent in all five
   shipped ports and it is now fixed.

**A rule the RFC's own probe proved again.** Its first stage printed PASS
against a build that exited 1, because it read a stale artifact. The negative
control caught it. Write the negative control first.

**The row asked for a measurement. Nobody ran it for three days. The answer
closed the row.** These were the figures. `build_smoke.sh` had **twelve** walk
sites, and the row said nine. Each of the twelve was the same query. Each one
found one executable file by name below a `.stack-work/install` directory. That
directory is **four levels deep on both platforms**. macOS gives
`aarch64-osx/<hash>/9.6.6/bin`. Linux gives
`x86_64-linux-tinfo6/<hash>/9.6.6/bin`, read from the log of run
`31441364939`, which passed.

**THE TWELVE WALK SITES ARE GONE. Do not port them.** A later measurement showed
the search was the defect. `build_smoke.sh` now calls
`stack path --local-install-root` through one `exe_path` helper, changed
2026-08-11. Stack gives the exact path. Thus the reference does no search, and
no ambiguity exists.

**Port 006 must copy the new mechanism.** `wasi.proc.run` takes a cwd, so the
port calls `stack path` in the same way. Port 005 reaches `git ls-files` by that
same method. **Do not use an mtime.** No `wasi.fs.stat` exists; see `FS-STAT-1`.

**Caution 1. SETTLED 2026-08-11. Read this before you write a search.** A search
had no defined answer, because a tree can hold more than one install root. Two
measurements decided it. The repository's compiler tree holds two roots. `find`
gives the 2026-08-10 build, which is `llmll 0.14.96`. A sorted pick gives the
2026-06-19 build, which is `llmll 0.13.0`. **A sorted pick is deterministic and
two months stale.** Thus neither pick was correct.

Stack keeps an old install root on purpose. The directory name is a hash of the
build config. Stack keeps the old root as a cache. Stack has no command that
removes all roots except the newest.

**Caution 2. This no longer applies to port 006, and it stays on `LIST-KIND-1`.**
A symlink cycle makes a recursive walk continue forever. `wasi.fs.list` cannot
see a symlink. Port 006 does no walk now, so port 006 cannot meet this. Any
future recursive walk must answer it first.

### Port 005 is RETIRED at v0.14.99. Read this before you retire port 006

**A retirement rule that this retirement produced. Use it for port 006.** Move
the subject script aside. Then run the gate. Then read the result. Do this
BEFORE you delete the subject.

Deleting `scripts/doc_path_lint.py` broke **13 prose citations in 6 files**. The
measurement took one minute and it was free. The RFC section 8 precondition list
did not ask for it. Two citations now name the port. Five `ALLOW` entries in the
port carry the others. Each of the five is a past-tense record.

**Do not rewrite a past-tense record to name the port.** The port did not take
that measurement. A rewrite makes the record false.

**The differential cover died with the reference.** `doc_path_lint_cover.py`
holds `REF = "scripts/doc_path_lint.py"`. It compares the two implementations.
So it cannot work without the reference. The 22 cells are deleted.

**No instrument grades the port now.** The live corpus gives zero findings. Thus
the reporting half of the gate does not execute. **A live run that passes is not
evidence that the port is correct.** The user accepted this cost on 2026-08-12.
RFC section 6 records that cells 9 and 13 discriminate. Start there if you build
a new grader.

**One record was incorrect and the retirement found it.** `version-gate.yml`
said in two places that `test_clean_on_live_repo` keeps the fast job
fail-closed. That test was deleted on 2026-08-11. So the workflow advertised a
merge block for one day that did not exist. `docs/UPDATE-PROTOCOL.md` said the
same. Both are corrected.

### Port 005 left two items. Both are DONE

1. **The retirement question. ANSWERED 2026-08-11. This item is DONE.** The user
   chose to delete the test and to accept the loss.
   The test file `test_doc_path_lint.py` is deleted. The test count goes from
   197 to 179.

   **Know what the repository lost.** That test ran `scripts/doc_path_lint.py`
   over the tree and failed if one file path was broken. CI then failed. Thus a
   broken path could not go into `main`. **Nothing stops a broken path now.**
   The two remaining checks report and do not decide. Each one exits 0 when it
   finds a broken path, by design.

   **Do not report this as a defect.** It is a decision, and section 8 of the
   005 RFC holds the reason.

   **One door stays open.** Make the port's CI step fail when it finds a broken
   path. The merge block then lives in the LLMLL port. A person must choose
   that; it changes when CI fails.
2. **The gap rows. This item is DONE.** The roadmap holds five rows as of
   2026-08-10: `FS-EXISTS-1`, `REGEX-CAPTURE-1`, `REGEX-CASE-1`, `PATH-NORM-1`
   and `LIST-KIND-1`.

   **There were five rows and not four.** Port 004 raised `LIST-KIND-1` on
   2026-08-09. It gave the gap no tag name. Thus no census held it, and this
   record did not hold it. A search for tag names cannot find a gap that has no
   tag. **Give each new gap a name when you record it.**

### What port 005 measured. Keep these

- **Console mode writes one blank line for each step.** A cover must start at
  the first `DRIFT-DOC-4` line. Do not compare raw output.
- **A report text must not end with a line end.** The harness adds one.
- **`:done?` is read on the state a step RETURNS.** That step's Command does not
  run. Thus a phase must not print AND finish. Use two phases.
- **`llmll verify` needs the solver.** Put a step that verifies BELOW the
  toolchain assertion. Port 005 is the first port to verify in CI.
- **TDFA is not Python.** `regex-match` gives POSIX ERE. It has `\b`. It has no
  `\d`. It refuses `(?i)`. Measure each new pattern.
- **A first-run pass is not evidence.** The cover passed 22 of 22 at once. Two
  broken ports then showed that cell 9 and cell 13 can fail. Do this for each
  new cover.

---

## 3. Five records that were incorrect. All are corrected

All five are corrected at v0.14.95.

| File | What it claimed | What is true |
|---|---|---|
| `docs/design/tool-ll-RESTART.md` | three ports, 004 is next | four ports, 005 is next and is blocked |
| `docs/design/llmll-tooling-campaign.md` | three ports | four ports, and it is Rev 3 |
| `.github/workflows/version-gate.yml` | the fast job runs DRIFT-DOC-3 | the `spec-roundtrip` job runs it |
| `docs/design/INDEX.md` | Rev 2, three ports, nothing blocked, and no row for the 004 RFC | Rev 3, four ports, 005 blocked, and the row is present |
| `docs/design/tool-rfc-004-doc-archive.md` | six differential cells and one negative control | 17 cells: 14 mutations and 3 negative controls |

**The five records failed in the same way.** A person recorded a change in a
comment next to the code. The person did not change the places that advertise the
change. Finding 13 records this class first.

The CI record is the most severe of the five. Line 54 of the workflow is the
job's display name. Thus the CI checks list showed a gate that the job does not
run.

**The search for these records found three, then four, then five.** The first
search on 2026-08-09 found three. `INDEX.md` was found on 2026-08-10. The 004
RFC's own status line was found after that, because the previous revision of this
section told the reader to look for a fifth place.

**A count of incorrect records is a measurement and not a total.** Search again
before you trust this table. The 004 RFC shows why: a document can record its own
instrument incorrectly while the instrument passes.

---

## 4. Settled decisions

The user made these decisions on 2026-08-07. Do not discuss them again.

- **Scope.** The campaign ports the six CI gates. It ports nothing else. The
  covers, `rfc_to_implementation.py` and `scripts/tests/` stay out. Campaign
  section 2 gives a reason for each.
- **Distribution.** Jobs pull a published release image.
- **Retirement.** The original stays for one release as a differential oracle.
  Then one commit deletes it and sets the RFC `tool_state` to `retired`.
- **The gap discipline.** Each gap takes one of BLOCKS, SHAPES or COSMETIC. A
  SHAPES row must state the intended design and cite a roadmap tag.

The user made these decisions on 2026-08-08. Do not discuss them again.

- The port copies the reference's two SKIP paths. The silent success became
  `SKIP-SILENT-1`. A port copies its reference. A port does not improve it.
- The `@expect` grammar is implemented in full. The retirement rule requires
  this.

---

## 5. Campaign status

Five ports of six are complete. Four are oracles. One is retired.

| Port | State |
|---|---|
| **001** DRIFT-CI-1 version gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-001](tool-rfc-001-version-gate.md) |
| **002** refute-crux gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-002](tool-rfc-002-refute-crux.md). It found four defects. All four are fixed |
| **003** doc-claims | **PORTED**, `tool_state: oracle`, [TOOL-RFC-003](tool-rfc-003-doc-claims.md). Released at v0.14.92. It filed `SKIP-SILENT-1`. It found `TOOL-ENCODING-1` in the compiler |
| **004** doc-archive | **PORTED**, `tool_state: oracle`, [TOOL-RFC-004](tool-rfc-004-doc-archive.md). **Released at v0.14.95.** See section 6 |
| **005** doc-path-lint | **RETIRED at v0.14.99**, `tool_state: retired`, [TOOL-RFC-005](tool-rfc-005-doc-path-lint.md). The reference and the cover are deleted. **The campaign's first retirement.** Section 2 gives its rule |
| **006** build-smoke | Last. It runs the other gates. **STARTED 2026-08-12**: the RFC is Rev 4, D3 is discharged by probe, and `buildsmoke.llmll` holds the spine and stage 1 of 14. `tool_state: blocked`, which is approximate. Section 2 gives what stage 2 needs first |
| **P1** tag debt | **DONE.** Four tags pushed. Four images published |
| **P2** file the gaps | **DONE**: `MODE-CLI-1`, `SPLIT-EMPTY-1`, `FS-WALK-1` |
| **P3** wire refute-crux into CI | **DONE** |

Open roadmap rows that this campaign filed or needs:

| Row | Status | Line |
|---|---|---|
| `REGEX-LOWER-1` | **SHIPPED v0.14.96.** It unblocked port 005 | roadmap, closed-rows section |
| `ALIAS-LOWER-1` | OPEN. The six glyphs are now its full scope | roadmap :63 |
| `RUN-STDIN-1` | OPEN. Filed by a 004 feasibility probe | roadmap :70 |
| `SKIP-SILENT-1` | OPEN | roadmap :62 |
| `FS-WALK-1` | **CLOSED COSMETIC 2026-08-10.** Port 006 does not need it | roadmap, closed-rows section |
| `MATCH-TERM-EQ-1` | OPEN. The 004 core is written around it | roadmap, search the tag |
| `STRLIT-BODY-1` | OPEN. It is the absence that 004 section 7 records | roadmap, search the tag |
| `TOOL-ENCODING-1` | SHIPPED v0.14.93 | roadmap :486 |
| `CI-BUILD-TEST-1` | SHIPPED v0.14.94 | roadmap :498 |
| `FS-EXISTS-1` | **FILED 2026-08-10.** OPEN. Raised by 005 | roadmap, Active Items |
| `REGEX-CAPTURE-1` | **FILED 2026-08-10.** OPEN. Raised by 005 | roadmap, Active Items |
| `REGEX-CASE-1` | **FILED 2026-08-10.** OPEN. Raised by 005 | roadmap, Active Items |
| `PATH-NORM-1` | **FILED 2026-08-10.** OPEN. Raised by 005 | roadmap, Active Items |
| `LIST-KIND-1` | **FILED 2026-08-10.** OPEN. Raised by **004**, not by 005. It had no tag, so no census held it | roadmap, Active Items |

**All five gap rows are filed.** The roadmap Active Items table holds them as of
2026-08-10. Port 005 proposed four of the five. Port 004 raised the fifth,
`LIST-KIND-1`, and gave it no tag, so no census found it for a release.

**The line numbers above move.** Search for the tag name. Do not trust the
number.

---

## 6. Port 004, and the three defects its cover found

Port 004 is complete. These are its parts:

| Part | Path |
|---|---|
| The port | [`tools/doc-archive/docarchive.llmll`](../../tools/doc-archive/docarchive.llmll) |
| The verified core | [`tools/doc-archive/adjudicate.llmll`](../../tools/doc-archive/adjudicate.llmll) |
| The reference | [`scripts/doc_archive_gate.sh`](../../scripts/doc_archive_gate.sh) |
| The cover | [`scripts/doc_archive_cover.py`](../../scripts/doc_archive_cover.py) |

The cover has **17 cells: 14 mutations and 3 negative controls.** All 17 pass.
The count was measured from the `CELLS` list on 2026-08-09.

Both implementations run in the `spec-roundtrip` job. They run next to each
other. This is what `tool_state: oracle` means: both decide over the same tree
in the same run, and a reader compares them in one job log.

### The cover found three defects that the live run did not

The live corpus declares exactly one disposition. So a live run exercises one
of four vocabulary values and none of the four violation classes. **A live run
that passes is not evidence that the port is correct.**

| Defect | Description |
|---|---|
| 1 | Criterion 1 was not implemented in the port |
| 2 | Criterion 7 did not print the remedy epilogue |
| 3 | Two cover cells were incorrect when they were written |

Defect 3 is the useful one. A cover can be wrong in the same way as the thing
it grades. Cells that agree by accident prove nothing.

---

## 7. Gate measurements

**Warning: each row below is a separate claim. Each row becomes incorrect on
its own schedule.** Finding 13 records two rows that were false for two days
while section 1 was correct. Measure this section again. Do not measure only
section 1.

Every figure below was measured at v0.14.92 unless the row says otherwise.
Every figure is from macOS and aarch64 unless the row says otherwise.

| Gate | Figure |
|---|---|
| `stack test` | **1683 examples, 0 failures.** Measured 2026-08-10 at v0.14.96 on macOS. **This gate now runs in CI**, since `CI-BUILD-TEST-1` at v0.14.94, in the `spec-roundtrip` job with `--fail-on=pending`. CI measured about 4m07s |
| `pytest scripts/tests/` | **197 passed, 6 skipped.** Measured 2026-08-10 at v0.14.95 |
| [`refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) | 80 passed, 0 failed on macOS with a solver on `PATH`. On Linux it scored 2 passed and 78 failed until the job built a solver. See finding 12 |
| [`refutecrux.llmll`](../../tools/refute-crux/refutecrux.llmll) | 80 passed, 0 failed, 71s. **It has never run on Linux** |
| [`refute_crux_cover.py`](../../scripts/refute_crux_cover.py) | 16 cells and 3 negative controls, all pass at v0.14.91. CI runs the 16 cells in 324s. The figure is 6 to 10 minutes |
| [`doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh) | 16 doc-claims match, exit 0. **It needs no solver** |
| [`docclaims.llmll`](../../tools/doc-claims/docclaims.llmll) | 16 match, exit 0, about 40s. **It passes on Linux** |
| [`doc_claims_cover.py`](../../scripts/doc_claims_cover.py) | 17 cells and 3 negative controls, all pass. About 2 minutes |
| [`doc_archive_gate.sh`](../../scripts/doc_archive_gate.sh) | PASS. It runs in `spec-roundtrip` since TOOL-RFC-004 |
| [`docarchive.llmll`](../../tools/doc-archive/docarchive.llmll) | PASS. Output identical to the reference. **It passes on Linux** |
| [`doc_archive_cover.py`](../../scripts/doc_archive_cover.py) | **17 cells: 14 mutations and 3 negative controls. All pass.** Measured on macOS and on Linux CI at `e5459c3` and again at `c4e7901`. **The cover is not its own CI step.** It runs inside the port's step, before the live run. Look in the step named `Run archive-disposition drift gate (LLMLL port, TOOL-RFC-004)` |
| [`pathlint.llmll`](../../tools/doc-path-lint/pathlint.llmll) | **986 citations in 173 files, all resolve.** Measured 2026-08-12 after the retirement commit. It reads `git ls-files '*.md'`, so it cannot see an untracked file. **This is the only DRIFT-DOC-4.** The last differential measurement was earlier in the same commit, at 977 citations, where the reference gave the same two numbers. The retirement's own prose added the other nine, and two of them needed `ALLOW` entries |
| [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | 39 passed. Needs a rebuilt sequencer through `--driver` |
| [`wave_cover.py`](../../scripts/wave_cover.py) | 7 passed. Needs `--wave` |
| [`version_gate_cover.py`](../../scripts/version_gate_cover.py) | 14 passed. Needs `--gate` |
| [`version_gate.sh`](../../scripts/version_gate.sh) | **PASS at 0.14.95** across all five banner sites. Measured 2026-08-10 |
| [`build_smoke.sh`](../../scripts/build_smoke.sh) | PASS, all stages. **It gained the `REGEX-LOWER-1` stage at v0.14.96.** That stage is the only gate that can see a builtin which checks, verifies and then does not build |

### How to rebuild a port

Several rows above need a rebuilt port. Use these commands:

```
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
cd tools/<tool> && llmll build <tool>.llmll -o <outdir>
```

Run the port from a scratch directory. Give it an absolute `--root`. A console
program writes `<module>.event-log.jsonl` into its working directory.

```
python3 -c "import sys; sys.stdout.write('x\n'*4000)" \
  | <outdir>/.../<tool> --root <repo>
```

---

## 8. Findings

Do not discover these again. The numbers are stable. Other sections cite them.

1. **`MODE-CLI-1` makes the ports large.** `:mode cli` emits
   `print (step args)`. It performs no `Command`. It gives no exit status. It
   has no users in the tree. So `console` is the only usable entry mode. Every
   LLMLL tool is a stdin-driven step machine that exits **70** on EOF. 58 lines
   of shell became 278 lines of LLMLL.

2. **`SPLIT-EMPTY-1`: `string-split ""` does not terminate.** It type-checks
   and it verifies. LLMLL decomposes no characters. A scan must be a fold over
   a literal index list with a hand-written bound.

3. **`CAP-NULLARY-1`: nullary `wasi.*` builtins bypass capability
   enforcement.** `inferExpr (EApp ...)` is the only caller of
   `checkWasiCapability`. So argv and the wall clock need no capability import.

4. **The per-fill bar is not redundant with `patch`.** A body of
   `(+ n (string-length "x"))` satisfies its postcondition. It answers
   `PatchSuccess`. It verifies SAFE. It lands in `body-fallback`. Only
   `[S9-FAITHFUL]` rejects it.

5. **`checkout` and `patch` take a `.ast.json` file, not a `.llmll` file.**
   `--emit` is a bare flag. A refused patch leaves the lock held. A successful
   patch clears the lock.
   [`driver-ll-phase4-RESTART.md`](driver-ll-phase4-RESTART.md) section 4 has
   the full list.

6. **A gate that is not wired in decides nothing.** Sub-phase 4c shipped a
   cover that nothing invoked. `refute-crux-gate.sh` was in that state until P3
   wired it. The standard's section 1 exists to catch this before anyone writes
   code.

7. **TOOL-RFC-002's feasibility read was wrong. This is the campaign's most
   useful result.** Revision 0 concluded that nothing was BLOCKS and that it
   found no new gap. The build found four defects. **A feasibility table lists
   what the language has. The defects are in what the language does.** Treat a
   future RFC section 4 as a list of things to try. Do not treat it as a
   clearance.

8. **Two of those four defects fail silently, and that cost the time.**
   `JSON-SCALAR-1`: `(json-get-string x "")` on a scalar answers `""`. The port
   ran its corpus with the flags dropped. It reported 30 passed and 50 failed,
   and 50 is the count of flagged cases. It type-checks. It verifies. No gate
   sees it. `CAPTURE-ENCODING-1` is silent in the other direction: the output
   looks present, but the bytes are wrong.

9. **This repository separates a bug from a language gap with roadmap tags.**
   The legend is at roadmap lines 13 and 14. `[SPEC]` means that a fix changes
   what the language is. `FD-CAPTURE-1` and `CAPTURE-ENCODING-1` are `[CT]`
   bugs. `JSON-SCALAR-1` and `PROC-MERGE-1` are `[CT][SPEC]` gaps. Campaign
   section 9 gives their shape to the language team. **Do not settle a
   `[SPEC]` shape at the keyboard.**

10. **Every encoding measurement in this record is from macOS only.** macOS GHC
    resolves UTF-8 under every `LC_ALL`. So a gate could not fail where it ran,
    and `main` failed for two days at v0.14.86.

11. **The workarounds for two gaps were marked for removal, and all are now
    removed.** The pre-marking worked as intended. Each row closed with a small
    edit at sites that named themselves. An audit was not necessary.

    **One deleted helper was also wrong, and the removal found it.** It
    stripped the outer quotes from `json-serialize`. The emitted `jsonQuote`
    escapes each character above `~` as `\uXXXX`. So a flag with a non-ASCII
    character came back as six literal characters. **A workaround is not a
    smaller version of the fix.**

12. **The `spec-roundtrip` job had no solver. Nothing noticed, because no gate
    in it had ever needed one.** `llmll verify` proves nothing by itself. It
    calls `fixpoint`, which calls z3. Without either, it exits **3**:
    "solver unavailable (proof did not run)",
    [`Main.hs:1386`](../../compiler/app/Main.hs). The refute-crux gate is the
    first gate in that job that needs a solver. Its first Linux run scored 2
    passed and 78 failed. Each failure exited 3.

    **The two passes identify the cause.** Both reach a verdict before the
    solver runs: one is a capability refusal, one is a coverage threshold. So
    this was an absent toolchain. It was not a verification regression.

    **This is finding 6, one step further on.** A gate that is not wired in
    decides nothing. **A gate wired into a job that cannot run it also decides
    nothing, and it reports that it decided.** The gate printed
    `78 frozen verdict(s) diverged` when zero had diverged.

    **Generalise finding 10 here.** Every measurement that needs a proof is
    from macOS only, for the same reason.

13. **A cover that pins a literal version fails at the next release.**
    `version_gate_cover.py` hardcoded `v0.14.87` in five cells. The banner moved
    at `d6e9f01` and again at `c7c057a`. From `d6e9f01`, those cells could not
    find their anchor. `build_smoke.sh` runs that cover as its last stage, so
    it failed too.

    **Section 7 claimed that both passed at `268df95`. Neither passed.** Those
    figures were copied from an earlier measurement. They were not taken at the
    commit they name. **Measuring section 1 again is not enough. Section 7 is a
    table of separate claims.**

    **Keep the one thing that worked.** The cells did not pass without effect.
    The `want` field reports "this cell would test nothing" and it FAILS. **A
    mutation harness that cannot find its anchor must fail. It must not skip.**

14. **A new gate is a claim, and the claim is that the gate can fail.** Both
    v0.14.91 fixtures were mutation-checked. One check changed what the fixture
    asserts. The cheap method is to mutate the generated Haskell in a built
    fixture project. Then rebuild that project alone. Do not mutate the
    compiler and pay for a full rebuild for each probe.

    `json_scalar.llmll`: a mutation flipped exactly the two refusal cells. All
    three value cells stayed correct. **So the three value cells alone would
    have caught neither mutation.**

15. **`TOOL-ENCODING-1` caused a total failure, and the negative controls
    caught it.** 003's cover failed on its first Linux run. The defect is in
    the subject. `llmll` decodes `.llmll` source through `TIO.readFile`, which
    takes the ambient locale. The cover scrubs the environment, so the compiler
    got no locale. On Linux that is POSIX, and all 15 fixtures failed.

    **Cells 1 to 13 all reported `ok`.** Both implementations failed, and they
    failed identically, so each mutation cell still agreed. The three negative
    controls failed, because they require both sides to pass an unmutated tree.
    **A set of mutation cells alone would have passed while the compiler could
    not read one fixture.**

    **The census is taken, and the question it asked was the wrong one.** 142
    of 259 committed `.llmll` files hold non-ASCII bytes. Until v0.14.93,
    exactly zero held one in token position. So ask "is the population where
    something checks", not "is the population empty".

16. **The 004 cover found three defects that a live run cannot find.** See
    section 6. The live corpus declares one disposition of four. It contains
    none of the four violation classes. A live run that passes grades one
    twentieth of the specified behaviour.

17. **A record in this repository became incorrect at the handoff boundary
    three times.** This is a property of the process, not of the practice. The
    handoff is the moment when a record is copied rather than measured. Section
    0 exists to make the first act of a session a measurement.

---

## 9. Gotchas

### Shell and process

- **zsh does not word-split an unquoted parameter.** `set -- $pair` in a loop
  puts the full string in `$1`. So `git show "$sha:F"` became `git show ":F"`,
  which reads the index. Use Python when the command contains quoting.
- **zsh removes `^` and `{}`.** An unquoted `git cat-file -e $sha^{commit}`
  reports each commit as missing.
- **`yes x | head -n N | prog` reports 141 under `set -o pipefail`.** `yes`
  dies of SIGPIPE by design. Use
  `python3 -c "import sys; sys.stdout.write('x\n'*N)"` instead.
- **A console program with no stdin stops and waits.** It also writes
  `<module>.event-log.jsonl` into its working directory. Run a tool from a
  scratch directory with an absolute `--root`.
- **The binary at the repository root is old.** Always run
  `export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH`.
  Then check `llmll version`.
- **`stack exec` outside a stack project silently uses the global project.**
  `tools/refute-crux` has no `stack.yaml`. On Linux CI this installed GHC
  9.10.3 before it answered "Executable named llmll not found on path". Use the
  absolute path from `stack path --local-install-root`.
- **Run `doc_path_lint.py` on its own line.** A pipe to `tail` takes `tail`'s
  exit status.
- **`fd 1 == PIPE` on a generated console program is normal.** It is not
  evidence of a problem. Every `console` program redirects its own stdout into
  a `captureStdout` pipe. Read the full fd table, not one row. **A stopped
  process shows CPU time that does not increase.** Use `ps -o time=` over 90
  seconds. `%cpu` alone is not the signal.
- **`pgrep -f` that returns nothing is not proof of absence.** A 0-byte log is
  not proof of death. Python block-buffers stdout to a file. Wait, then use
  `ps`.

### Cover arguments

- **Every cover in this campaign takes `--gate` as the PORT BINARY and
  `--llmll` as the COMPILER.** The names read as the opposite assignment. The
  shell reference is not an argument at all. A wrong assignment type-checks as
  far as the filesystem is concerned, and then it stops and waits. This cost a
  ten-minute timeout once. Read
  [`version-gate.yml`](../../.github/workflows/version-gate.yml) to see the
  correct invocation.

### The LLMLL language

The 004 port found these. **They were observed during debugging on 2026-08-09.
They are not re-verified. Test one before you depend on it.**

- **`string-split` takes the separator first, then the string.** A reversed
  call type-checks and returns a malformed result. This cost five call sites.
- **A command in a state with no successor does not execute.** Add an `Ending`
  state, or the final output command never runs.
- **These helpers do not exist and must be written locally**: `sets`, `seti`,
  `flag-or`, `flag-value`.
- **`check` exits 0 on a call to an unknown function.** So a type check that
  passes does not prove that each callee exists.
- **A `def` cannot call a sibling `def`.**
- **There is no `starts-with` builtin.**
- **`json-object` is the empty object value.** It is not a constructor.
- **The `:done?` warning is benign on a shipped program.**

---

## 10. Debt, deferred and unrelated

- **The published image ships no compiler.** This is why DRIFT-DOC-3 moved out
  of the fast job. The settled distribution says that jobs pull a published
  release image. The image has no GHC and no Stack, so it cannot build a port.
  **This deviation from the settled distribution is unresolved.** RFC section 8
  cannot delete a reference while the reference decides in a job that the port
  cannot reach.
- **`llmll run` does not work for a console program.** Filed as `RUN-STDIN-1`,
  roadmap line 70.
- **A CI toolchain image is proposed and not built.** Measured: jq and z3 cost
  about fifteen seconds together. The `fixpoint` build is already solved by the
  cache. The port step is solver time, not build time, so a baked snapshot
  database would not change it. **Do not argue for the image on speed.** Argue
  for it on determinism: a cache entry evicts after 7 days, and the Stack key
  is `hashFiles(compiler/stack.yaml)`, so a resolver change restores the
  six-minute tail. **It cannot be the published release image**: RFC section 8
  decision 2 requires a subject built from source.
- **The pre-fix refute-crux port deadlocks without a solver.** Measured five
  times, always at 1882 bytes of output, with CPU time that stopped increasing.
  A 300-step run completes normally. So the deadlock is near step 1882 of about
  1997. The solver preflight makes this unreachable. The deadlock itself is
  unexplained and unfixed.
- **No parse gate covers design-document frontmatter.**
- **`HDelegate`, `HDelegateAsync`, `HDelegatePending` and
  `HConflictResolution` reach the HOLE-STATUS-SIBLING catch-all with no test.**
- **DRIVER-LL 4d is parked.** Sub-phase 4f, program unification and stage A
  stay deferred. Five of the eight remaining callerless rows belong to 4d.
