---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, 2026-08-10. Four ports of six are complete and released at v0.14.95. REGEX-LOWER-1 shipped at v0.14.96 and unblocked port 005. THE RFC FOR PORT 005 IS NOW WRITTEN and the port is not built; building it is the next work. ALL THREE OF ITS DECISIONS ARE SETTLED (D1 distribution, D2 existence by git ls-files, D3 use regex-match). D3 reverses the precedent in versiongate.llmll:25 and shape.llmll:26, on a measurement that the verified tier those comments protect is not available to this function either way. See section 2. This file shows where the work is. The file llmll-tooling-campaign.md shows what the standard says. If the two files disagree about the standard, use the campaign file. If the two files disagree about state, measure the state again."
date: 2026-08-10
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

## 1. State, measured 2026-08-10, after v0.14.96

| Item | Value | How it was measured |
|---|---|---|
| Last tag | `v0.14.96` | `git describe --tags --abbrev=0` |
| Unreleased commits | **1**, this record's own update | `git rev-list --count v0.14.96..HEAD` |
| Version banner | `v0.14.96` | `head -1 LLMLL.md` |
| CI on `main` | **all three runs passed** at `3924bb3` | `gh run list --branch main` |
| Newest CHANGELOG entry | `v0.14.96` | `grep "^## " CHANGELOG.md` |

The banner, the last tag and the newest CHANGELOG entry agree. **The repository
owes no release.**

Two releases went out on 2026-08-10. v0.14.95 released the fourth port and the
record corrections of section 3. v0.14.96 released `REGEX-LOWER-1`, which
unblocked port 005. The release notes are in `CHANGELOG.md`.

**A warning about the table above.** The count of unreleased commits is 1 because
this record's update is the commit. That number increases with the next commit.
Measure it again. Do not read it from this table.

The CI row covers three runs: `version-gate` on `main`, and `docker-publish` on
`main` and on the tag. A tag push starts the image publish. Look at all three.

---

## 2. The next work: finish port 005

**The RFC is written and the port is started.** Read
[`tool-rfc-005-doc-path-lint.md`](tool-rfc-005-doc-path-lint.md), at Rev 1. Its
`tool_state` is `blocked`, which means "no program yet", not "a roadmap row
stops it".

**Two files exist. The port BUILDS and RUNS.**

| File | State |
|---|---|
| `tools/doc-path-lint/adjudicate.llmll` | **DONE.** `reports?`, `tally` and `status-of` are body-faithful and SAFE. Each one has a refuting case |
| `tools/doc-path-lint/pathlint.llmll` | **DONE and MEASURED.** It agrees with the reference byte for byte |

**The port agrees with the reference.** These runs are the measurement:

- The clean tree: byte-identical, from the first report line.
- A tree with one bad citation: byte-identical, same file, line and path.
- `--strict` gives exit 1 with findings. A plain run gives 0. This agrees with
  `STRICT=1`.

**Two parts are owed before the port is an oracle.**

1. Write the cover. Section 6 of the RFC gives 19 cells and 3 negative controls.
2. Wire both implementations into `spec-roundtrip`, as one commit. Decision D1
   gives the reason.

**The job must verify `adjudicate.llmll` BEFORE `pathlint.llmll`.** The sidecar
is not in git. Without it the port drops to `asserted` for `reports?`.

### Three things the run showed. No reading gives them

1. **Console mode writes one blank line for each step.** The run gave 177 blank
   lines before the report. The cover must start at the first `DRIFT-DOC-4`
   line. Do not compare raw output.
2. **The report text must not end with a line end.** The harness adds one.
3. **Do not compute suppressor S3 for each citation.** That took more than two
   minutes. Compute the four cheap suppressors first. The reference does the
   same. The run then takes 34 seconds.

**Rev 1 corrected three errors. Build to Rev 1, not to Rev 0.** The first draft
said a character scanner was necessary. It is not. A split on the backtick gives
the same citations. One `regex-match` then tests each part. This is measured
against the reference: 955 citations, 172 files, no disagreement.

**Two other split models look correct and are wrong.** Do not use them. Section
5 of the RFC gives the measurements.

- Keep the parts INSIDE backticks, per line. A backtick pair can cross a line
  end. Then the count is wrong for the remainder of that line.
- Keep the parts INSIDE backticks, whole file. One unbalanced backtick makes
  the remainder of the file wrong. This gives 16 citations where the reference
  gives 94.

Test EVERY part between two backticks. Do not count backticks.

### All three decisions are settled

The user made D1, D2 and D3 on 2026-08-10. Do not discuss them again. Section 9
of the RFC gives each one.

- **D1, distribution.** Amend the campaign rule first. Then move the gate.
- **D2, existence.** Use one `git ls-files`. Then use `list-contains`.
- **D3, the regexes.** Use `regex-match`.

**D3 reverses a precedent. Build the port to the reversal.** Two comments in the
tree avoid `regex-match`: `versiongate.llmll:25` and `shape.llmll:26`. They give
the verified tier as the reason. A probe measured that reason to be absent here.
Both recognizer shapes report `body-fallback`. A control reports
`body-faithful`. Thus the probe discriminates, and the tier cost is zero.

Three rules come with D3:

1. Write `PLACEHOLDER` as the reference writes it. Do not change a character.
2. Write `HIST_LINE` as per-letter bracket classes, like `[Pp][Rr]`. This gives
   exact case-insensitive matching. **Do not use a list of case variants.** That
   is an approximation, and cover cell 9 rejects it.
3. Hand-roll the two SCANNERS. `regex-match` returns a bool and captures
   nothing. Thus the port holds two mechanisms. This is correct.

**TDFA is not Python.** `regex-match` uses POSIX ERE. It has `\b`. It has no
`\d`. Measure each new pattern before you use it.

### What the RFC found that the roadmap did not say

Four facts were given to this campaign. Three are correct. One is wrong.

- **Correct.** The gate is advisory. It exits 0. A cover must compare the text
  on stdout. It must not compare exit codes.
- **Correct.** No environment access exists. The port reads `--strict` from
  argv. A probe measured that argv carries the flag. **The campaign disposition
  holds. The row does not move.**
- **Correct.** The gate runs in the fast job. That job has no toolchain. This is
  the second occurrence. **The user told the campaign to amend the rule now.**
  The amendment is at campaign section 3.
- **WRONG.** The fourth fact said that a live green run grades almost nothing.
  **Measure it again before you trust it.** All four exemption classes are live.
  Each one alone rescues 13 to 19 citations. The historical-file rule rescues
  268. Thus the suppression half has a live instrument. Only the reporting half
  needs fixtures, because the corpus gives zero findings.

**One filter is invisible.** The `site/` and `node_modules/` rule removes six
files. Those six files hold zero citations. Thus no corpus can exercise that
rule. Only cell 13 can see it.

### Three items go to other teams

The RFC found these. None of them stops port 005.

1. `shape.llmll:26` says that `^N\d+$` ports word for word. **This is wrong.**
   TDFA has no `\d`. Use `^N[0-9]+$`. Corrected.
2. `llmll check` gives exit 0 for an unknown function. It gives a warning only.
   This is the `REGEX-LOWER-1` shape.
3. `DONE-TYPE-1` gives a warning for each console program.
4. **`REGEX-LOWER-1` shipped at v0.14.96. Six sites still say it did not.** The
   v0.14.96 release corrected the documents. It did not correct the code
   comments. This session corrected `versiongate.llmll:25`, because D3 rests on
   it. Five sites stay: `sequencer.llmll:1327` and `:1334`,
   `docclaims.llmll:174`, and `test_driver_ll_4c.py:39`, `:419` and `:432`.

**One of the five sites is a test, and it is the one to look at first.**
`test_the_driver_calls_regex_match_nowhere` gives "does not build" as its reason.
It says "Until that row ships" in its failure message. The row shipped. The test
passes today, because no module calls `regex-match`. But it will stop a correct
change and give a false reason. DRIVER-LL owns that decision.

### Why the campaign did not choose port 006

The earlier version of this section offered port 006 as the other option. **That
option was incorrect. Port 006 is also blocked.** It needs `FS-WALK-1`, at
roadmap line 73. Port 006 does not avoid compiler work.

`FS-WALK-1` is also the more difficult row. Its roadmap disposition is **Hold**.
A recursive walk with no depth bound is the first unbounded loop in this
language. The other scanning code is bounded by construction. That makes
`FS-WALK-1` a design question. `REGEX-LOWER-1` is a known defect in codegen, and
it has two proposed shapes.

Port 006 comes last for a second reason. It runs the other five gates. It must
inherit the pattern of five ports.

### What `REGEX-LOWER-1` found, and the two lessons to keep

The row asked for a census before a fix. The census **corrected the row**.

1. **The row grouped two names that behave differently.** It said `regex-match`
   and `is-valid?` were one unmeasured pair. They are two classes. The
   discriminator is `builtinEnv` membership. The row already stated that fact
   for the six Unicode aliases. It did not apply the fact to `is-valid?`.
2. **`is-valid?` was a phantom.** The compiler named it in one list and nowhere
   else. It had no type, no implementation, no spec entry and no callers.
3. **The gate caught a cell that was wrong by construction.** The negative
   control ran the gate against a reverted compiler. The gate failed at its
   build step. Thus two of its checks did not run. One of those checks could
   never fire. It matched an identifier before the operator, and the fixture
   passes a string literal there.

**Keep lesson 3.** `TOOL-RFC-004` found the same class one release before. A
battery can be wrong in the same way as the thing it grades. Run the negative
control. Then read which checks it did not reach.

`ALIAS-LOWER-1` is at roadmap line 63. v0.14.96 did not change it, and a test
pins that. The six glyphs are now its full scope.

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

Four ports of six are complete. Each of the four is an oracle.

| Port | State |
|---|---|
| **001** DRIFT-CI-1 version gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-001](tool-rfc-001-version-gate.md) |
| **002** refute-crux gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-002](tool-rfc-002-refute-crux.md). It found four defects. All four are fixed |
| **003** doc-claims | **PORTED**, `tool_state: oracle`, [TOOL-RFC-003](tool-rfc-003-doc-claims.md). Released at v0.14.92. It filed `SKIP-SILENT-1`. It found `TOOL-ENCODING-1` in the compiler |
| **004** doc-archive | **PORTED**, `tool_state: oracle`, [TOOL-RFC-004](tool-rfc-004-doc-archive.md). **Released at v0.14.95.** See section 6 |
| **005** doc-path-lint | **RFC WRITTEN**, `tool_state: blocked`, [TOOL-RFC-005](tool-rfc-005-doc-path-lint.md). The port does not exist. **Build it next.** One decision is open. See section 2 |
| **006** build-smoke | Last. It runs the other gates. **It is also BLOCKED**, on `FS-WALK-1` |
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
| `FS-WALK-1` | OPEN, disposition **Hold**. Port 006 needs it | roadmap :73 |
| `MATCH-TERM-EQ-1` | OPEN. The 004 core is written around it | roadmap, search the tag |
| `STRLIT-BODY-1` | OPEN. It is the absence that 004 section 7 records | roadmap, search the tag |
| `TOOL-ENCODING-1` | SHIPPED v0.14.93 | roadmap :486 |
| `CI-BUILD-TEST-1` | SHIPPED v0.14.94 | roadmap :498 |
| `FS-EXISTS-1` | **OWED**, proposed by 005. No roadmap row exists | campaign section 5 |
| `REGEX-CAPTURE-1` | **OWED**, proposed by 005. No roadmap row exists | campaign section 5 |
| `REGEX-CASE-1` | **OWED**, proposed by 005. No roadmap row exists | campaign section 5 |
| `PATH-NORM-1` | **OWED**, proposed by 005. No roadmap row exists | campaign section 5 |

**Port 005 proposed four gap names. No roadmap row holds them.** The campaign
section 5 table carries them. File the four rows before the port ships.

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
| [`doc_path_lint.py`](../../scripts/doc_path_lint.py) | **946 citations in 171 files, all resolve.** Measured 2026-08-10. It reads `git ls-files '*.md'`, so it cannot see an untracked file |
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
