---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "CLOSURE RECORD, 2026-08-18. The porting phase is CLOSED at v0.16.1. All six gates have an LLMLL port and all six decide in CI. Four shell references are deleted (002, 003, 004, 005); two stay oracle by decision (001, 006). This file was a session restart record of 1030 lines while the campaign ran. The per-port narrative moved to the six RFCs, which stay in docs/design because scripts/tests/test_tool_rfc_standard.py reads them. What stays here is cross-port: the state and how to measure it (section 0 and 1), the three owed measurements (section 2), records that were incorrect (section 3), findings and gotchas not to rediscover (sections 8 and 9), and open debt (section 10). Section numbers are unchanged because tool-rfc-005-doc-path-lint.md cites section 3."
date: 2026-08-18
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

## 1. State, measured 2026-08-17, after the fourth retirement

**THIS SECTION WAS MEASURED AGAIN ON 2026-08-17.** The 2026-08-16 measurement
came before four retirements. Read the date and the commit count together, and
do not read the date alone.

**THE WORK IS ON `main`. IT IS PUSHED. CI HAS GRADED IT.** The 2026-08-16
version of the frontmatter said the opposite of all three.

| Item | Value | How it was measured |
|---|---|---|
| Branch | `main` | `git branch --show-current` |
| Commits ahead of `origin/main` | **0**, and all are pushed | `git rev-list --count origin/main..HEAD` |
| Last tag | **`v0.16.0`** | `git describe --tags --abbrev=0` |
| Unreleased commits | **8**, and the close-out commit makes it 9 | `git rev-list --count v0.16.0..HEAD` |
| Version banner | `v0.16.0` | `head -1 LLMLL.md` |
| Working tree | clean | `git status --porcelain` |
| CI on `main` | **run 32064879596, success** | `gh run list --branch main` |

**THE TAG DEBT IS ZERO.** The tag `v0.16.0` exists and it is pushed. The image
`ghcr.io/machunter/llmll:v0.16.0` answers HTTP 200 to a request with no
credentials. The condition for the tag was one CI run of the port cover. Run
31985443527 met the condition first, and the tag came after it.

**THE UNRELEASED COMMITS OWE NO RELEASE, and that is a measurement.** They
change `docs/`, `scripts/`, `tools/`, `.github/`, `examples/` and the
`Makefile`. They change no file under `compiler/`, and they change no banner.
Measure this again with `git diff --name-only v0.16.0..HEAD`. Do not read the
sentence alone.

**ONE MEASUREMENT IN THIS FILE IS NOW COMPLETE.** Section "Five measurements"
item 1 asked for one CI run of the branch. Run 31985443527 is that run. It
reports `NOT EXERCISED` zero times, so Linux decided every stage of
BUILD-GATE-1. The `LC_ALL=C` stage cannot be decided on macOS and it passed.

### The gates, each run on 2026-08-17

| Gate | Result | Command |
|---|---|---|
| Harness suite | 177 passed, 10 skipped | `python3 -m pytest scripts/tests/ -q` |
| Version gate | passes, `v0.16.0` on all five banners | `bash scripts/version_gate.sh` |
| Path lint | passes, 1116 citations in 177 files, all resolve | build `pathlint.llmll`, then feed it 900 lines |
| RFC standard | 13 passed | `python3 -m pytest scripts/tests/test_tool_rfc_standard.py -q` |

**THE HARNESS COUNTS MOVED AND THE TOTAL GREW.** On 2026-08-16 the suite gave
179 passed and 6 skipped. The four skips that are new belong to
`test_refute_crux_solver_preflight.py`. The second retirement retargeted that
file at the port, and it skips unless `REFUTE_CRUX_BIN` and `LLMLL_SUBJECT`
name a built binary. The `spec-roundtrip` job sets both names. **A local skip is
not a local pass.** Read the skip reasons with `-rs`.

**The RFC standard gate was FAILING before 2026-08-16 and nobody ran it.** A
gap row cell held two disposition words where the gate accepts one.

**Run a gate on its own line.** A pipe into `tail` gives you the exit status of
`tail`. This happened again on 2026-08-16 during a probe.

**The banner, the CHANGELOG and the last tag all agree at `v0.16.0`.** That was
false on 2026-08-16, when the tag lagged. Run `grep "^## " CHANGELOG.md` and
compare all three. The tag is the one that lagged before, so measure it first.

### History that is still true

**v0.14.98 shipped the two gaps that port 006's RFC raised**, before the port
was written. `PROC-STDIN-1` gave `wasi.proc.run` a stdin path and
`PROC-STDIN-SHARE-1` closed with it. It also removed the last four
`find | head -1` sites from `version-gate.yml`, so that idiom is now absent
from the repository.

**v0.14.99 RETIRED port 005. This was the campaign's first retirement.** The
reference and its differential cover are deleted. The port is the only
DRIFT-DOC-4 now, and a rebuilt cover grades it since 2026-08-17. Section 2
gives the rule that this retirement produced. Ports 004, 003 and 002 used that
rule.

**THREE MORE RETIREMENTS FOLLOWED ON 2026-08-17, in this order: 004, 003, 002.**
Each one deleted a reference and kept a cover for the port alone. Each one names
its loss in its commit. The campaign amended its own retirement rule twice
during that day. Campaign section 4 governs, and it withdrew the calendar.

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


## 2. THE PORTING IS CLOSED. THIS SECTION IS A POINTER

All six gates have an LLMLL port. All six decide in CI. The porting phase closed
at v0.16.1. The per-port record moved to the six RFCs, which stay in
`docs/design/` because `scripts/tests/test_tool_rfc_standard.py` reads them:

| Port | RFC | State |
|---|---|---|
| 001 version gate | `docs/design/tool-rfc-001-version-gate.md` | `oracle` |
| 002 refute crux | `docs/design/tool-rfc-002-refute-crux.md` | `retired` |
| 003 doc claims | `docs/design/tool-rfc-003-doc-claims.md` | `retired` |
| 004 doc archive | `docs/design/tool-rfc-004-doc-archive.md` | `retired` |
| 005 doc path lint | `docs/design/tool-rfc-005-doc-path-lint.md` | `retired` |
| 006 build smoke | `docs/design/tool-rfc-006-build-smoke.md` | `oracle` |

Each RFC carries its own cover result, its gap table and its decisions. Read the
RFC for a port. Do not look for that record here.

### THREE MEASUREMENTS ARE STILL OWED

The porting closed with three measurements unrun. They are the only port work
that is open. Items 1 and 3 are complete and stay here because they say what the

1. One CI run. COMPLETE on 2026-08-16. Run 31985443527 on `main` reports
   success, and run 31985443538 for `docker-publish` also reports success.
2. Cell 7, with `--slow`.
3. `P-C1`. MEASURED on 2026-08-16, before the cell 6 fix was written.
   `wasi.fs.list` gives the NAMES of the files in a directory. It does not give
   their paths. So `list-contains` on the name decides existence. The probe
   agreed with the shell on the count and on the membership. The runtime is
   `listDirectory` and then `sort`. This measurement is complete.
4. The runtime halves of `P-A1`, `P-B1` and `P-B2`. Each one emits today.
5. The job's real time cost. `D4` in the RFC rests on a stage count of
   fourteen and the census is seventeen.

The probe report is at `builtin-sweep.md` in the session scratchpad. It is not
in the repository. Its probes are written but four are unrun, and the first
probe that WAS run refuted its own prediction.

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
- **Retirement. AMENDED 2026-08-17, and the amendment WITHDREW the calendar.**
  The 2026-08-07 decision said that the original stays for one release, and then
  one commit deletes it and sets `tool_state` to `retired`. Campaign section 4
  now governs and it asks for three conditions instead: the cover does not run
  the reference, every CI job that runs the reference can run the port, and the
  deletion breaks no prose citation. **Ask the pytest suite the second question
  too.** The fourth retirement found a reference test that the port did not
  have. A retirement is reached by argument and never by a calendar.
- **The gap discipline.** Each gap takes one of BLOCKS, SHAPES or COSMETIC. A
  SHAPES row must state the intended design and cite a roadmap tag.

The user made these decisions on 2026-08-08. Do not discuss them again.

- The port copies the reference's two SKIP paths. The silent success became
  `SKIP-SILENT-1`. A port copies its reference. A port does not improve it.
- The `@expect` grammar is implemented in full. The retirement rule requires
  this.

---

## 5. Campaign status

**Six ports of six are complete. Two are oracles. Four are retired.** All six
decide in CI. Measure the states with
`rg -n "^tool_state:" docs/design/tool-rfc-00*.md`. Do not read this table on
its own.

| Port | State |
|---|---|
| **001** DRIFT-CI-1 version gate | **PORTED**, `tool_state: oracle`, [TOOL-RFC-001](tool-rfc-001-version-gate.md). The port runs from `build_smoke.sh`, with a 14-cell cover. **Its retirement is DECIDED, 2026-08-17: it STAYS `oracle`.** `version_gate.sh` also runs in `docker-publish.yml`, and that job carries no Haskell toolchain, so condition 2 fails. Campaign section 4 holds the reason and the measured price |
| **002** refute-crux gate | **RETIRED 2026-08-17**, `tool_state: retired`, [TOOL-RFC-002](tool-rfc-002-refute-crux.md). It found four defects. All four are fixed. The reference is deleted, the cover grades the port alone with 16 cells, and the port's solver-preflight test moved into `spec-roundtrip` because it ran the reference from the toolchain-free job |
| **003** doc-claims | **RETIRED 2026-08-17**, `tool_state: retired`, [TOOL-RFC-003](tool-rfc-003-doc-claims.md). Released at v0.14.92. It filed `SKIP-SILENT-1`. It found `TOOL-ENCODING-1` in the compiler. The cover keeps 17 cells and 3 negative controls |
| **004** doc-archive | **RETIRED 2026-08-17**, `tool_state: retired`, [TOOL-RFC-004](tool-rfc-004-doc-archive.md). Released at v0.14.95. The cover keeps 17 cells: 14 mutations and 3 negative controls. See section 6 |
| **005** doc-path-lint | **RETIRED at v0.14.99**, `tool_state: retired`, [TOOL-RFC-005](tool-rfc-005-doc-path-lint.md). The reference and the original 22-cell differential cover are deleted. **The campaign's first retirement.** Its cover was REBUILT on 2026-08-17 as a 24-cell self-cover after five days with no grader. Section 2 gives its rule |
| **006** build-smoke | It runs the other gates. **ALL SEVENTEEN STAGES PORTED 2026-08-16**, with `adjudicate.llmll` verified SAFE. `tool_state: oracle` since `073ae4b`, after run 31985443527. The cover holds 10 cells and cell 6 is FIXED. **Its retirement is DECIDED, 2026-08-17: it STAYS `oracle`**, on defect yield |
| **P1** tag debt | **DONE for v0.14.84 to v0.14.87.** Four tags pushed. Four images published. **DONE again at v0.16.0**: on 2026-08-17 the banner, the CHANGELOG and the last tag all read `v0.16.0`. Six commits sit after the tag and they owe no release. See section 1 |
| **P2** file the gaps | **DONE**: `MODE-CLI-1`, `SPLIT-EMPTY-1`, `FS-WALK-1` |
| **P3** wire refute-crux into CI | **DONE** |

**THE CAMPAIGN'S FINDING, measured 2026-08-17 after the porting goal was met.**
The census counted lines and gaps. It never counted proof.

| Port | LLMLL lines | in a module CI verifies |
|---|---|---|
| build-smoke | 2574 | 105 |
| doc-path-lint | 776 | 98 |
| doc-archive | 577 | 65 |
| refute-crux | 652 | **none** |
| doc-claims | 543 | **none** |
| version-gate | 470 | **none** |
| **total** | **5592** | **268** |

**268 of 5592 lines, and that number is an upper bound.** It counts each line of
a module that `llmll verify` runs over. It does not count the functions that
reach `body-faithful`. Three of the six gates hold no proved core.

**Two rows explain the shape, and neither is a tooling problem.** `RESP-FACT-1`:
`RCode` carries a bare `TInt`, and `FixpointEmit.hs` holds no occurrence of
`Response`. Thus an effect cannot give a proved property to its caller. Each
port's IO spine is unprovable by construction. `STRLIT-BODY-1`: a string
recognizer reports `body-fallback` where an int control reports `body-faithful`.
Thus gate logic leaves the verified fragment.

**`RESP-FACT-1` IS THE NEXT WORK.** Read `fs-capability-trio-proposal.md`
section 5 first. Six ports went around this row and none filed it, because a
runtime guard looks like ordinary code. Campaign section 10 calls that a way to
fail.

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
| `FS-RMDIR-1` | **SHIPPED v0.16.0** 2026-08-15. Raised by 006, and it BLOCKED stage 5. `wasi.fs.rmdir` is empty-only and idempotent. Stage 5 now grades instead of printing `NOT GRADED`. The same release fixes `wasi.fs.delete` publishing `RNone` for a directory it did not remove | roadmap, Active Items |
| `RESP-FACT-1` | **FILED 2026-08-15.** OPEN. A `Command` result carries no proved property to its caller. Found by the `FS-STAT-1` design work; six ports routed around it and none filed it | roadmap, Active Items |
| `FS-EXISTS-1` | **FILED 2026-08-10.** OPEN. Raised by 005. **Its Rev 1 authority argument was REFUTED by measurement 2026-08-15** and it is held, not shipped | roadmap, Active Items |
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

Moved to `docs/design/tool-rfc-004-doc-archive.md`, sections 6 and 9. That RFC is
`retired`, so it is the only record of a shell reference this repository deleted.

---

## 7. Gate measurements

Each port measures its own gate. Read section 6 of that port's RFC. The campaign
totals are in `docs/design/llmll-tooling-campaign.md` section 5.

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
