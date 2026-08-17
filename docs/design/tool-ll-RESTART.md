---
name: tool-ll-restart
title: "TOOL-LL: session restart record"
status: "LIVE, 2026-08-16, after v0.16.0. PORT 006 IS COMPLETE: ALL SEVENTEEN STAGES ARE PORTED and the census is seventeen rows, not the fourteen this file said before. THE WORK IS ON BRANCH tool-006/proc-stdin-replay-boundary, 11 COMMITS AHEAD OF main, AND IT IS NOT PUSHED. NO CI RUN HAS SEEN ANY OF IT; every result here is local. THE TAG DEBT IS NOT ZERO AND THE 2026-08-12 LINE SAYING IT WAS IS INCORRECT: the banner says v0.16.0 and the last tag says v0.15.0, and the user DEFERRED the tag on 2026-08-16 until one green CI run of the cover. The port exits 0 and prints fifteen verdict lines against the reference's fifteen verdict-emitting sites; a bad --subject gives exit 1. adjudicate.llmll exists and verifies SAFE with both contracts body-faithful, proved by three refutation controls that each broke a different constraint. PROC-ENV-1 DID NOT BLOCK STAGE 5b: wasi.proc.run on /usr/bin/env sets a child environment and the stdin path survives the exec, so the row NARROWS and stays open. THE COVER RAN FOUR TIMES AND FOUND THREE DEFECTS IN ITSELF AND ONE IN THE PORT. 8 of 9 cells pass. CELL 6 IS A REAL PORT DEFECT AND IT IS NOT FIXED: the port carries the reference's "found no capproc-exec binary" text but tests whether stack returned an install root, so when the binary is truly absent the port reports NINE causes it never tested. That refutes the RFC section 5 LIST-KIND-1 claim that the design separates missing from not executable. LIST-RANGE-1 IS CLOSED AS REFUTED: range has been a builtin since v0.11 with fifteen call sites in five committed files, two of them this campaign's own ports, and the spec documented it. SPLIT-EMPTY-1 ASSERTS THE SAME FALSE ABSENCE and is not yet corrected. sha1 IS A MEASURED COMPILER DEFECT: check passes, verify reports SAFE and writes a sidecar, and GHC fails, because builtinEnv declares a name the preamble never defines. PLATFORM-1 and BYTES-WRITE-1 are filed. THREE DECISIONS ARE OPEN and section 2 lists them. tool_state STAYS blocked until a green CI run. Section 0 gives the commands; run them, because this line has been incorrect before and was incorrect about the tag debt today."
date: 2026-08-16
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

## 1. State, measured 2026-08-16, after v0.16.0 shipped

**THIS SECTION WAS MEASURED TWICE ON THE SAME DAY.** The first measurement came
before the release. Every row below changed after it. Read the date and the
release together, and do not read the date alone.

**THE WORK IS ON `main`. IT IS PUSHED. CI HAS GRADED IT.** The earlier version
of this section said the opposite of all three.

| Item | Value | How it was measured |
|---|---|---|
| Branch | `main` | `git branch --show-current` |
| Commits ahead of `main` | **0**, and all are pushed | `git rev-list --count main..HEAD` |
| Last tag | **`v0.16.0`** | `git describe --tags --abbrev=0` |
| Unreleased commits | **0** | `git rev-list --count v0.16.0..HEAD` |
| Version banner | `v0.16.0` | `head -1 LLMLL.md` |
| Working tree | clean | `git status --porcelain` |
| CI on `main` | **run 31985443527, success** | `gh run list --branch main` |

**THE TAG DEBT IS ZERO.** The tag `v0.16.0` exists and it is pushed. The image
`ghcr.io/machunter/llmll:v0.16.0` answers HTTP 200 to a request with no
credentials. The condition for the tag was one CI run of the port cover. Run
31985443527 met the condition first, and the tag came after it.

**ONE MEASUREMENT IN THIS FILE IS NOW COMPLETE.** Section "Five measurements"
item 1 asked for one CI run of the branch. Run 31985443527 is that run. It
reports `NOT EXERCISED` zero times, so Linux decided every stage of
BUILD-GATE-1. The `LC_ALL=C` stage cannot be decided on macOS and it passed.

### The gates, each run on 2026-08-16

| Gate | Result | Command |
|---|---|---|
| Harness suite | 179 passed, 6 skipped | `python3 -m pytest scripts/tests/ -q` |
| Version gate | passes, `v0.16.0` on all five banners | `bash scripts/version_gate.sh` |
| Path lint | passes, 1081 citations in 177 files | build `pathlint.llmll`, then feed it 900 lines |
| RFC standard | 13 passed | `python3 -m pytest scripts/tests/test_tool_rfc_standard.py -q` |

**The RFC standard gate was FAILING before 2026-08-16 and nobody ran it.** A
gap row cell held two disposition words where the gate accepts one.

**Run a gate on its own line.** A pipe into `tail` gives you the exit status of
`tail`. This happened again on 2026-08-16 during a probe.

**The banner and the CHANGELOG agree at `v0.16.0`. The last tag does not.** Run
`grep "^## " CHANGELOG.md` and compare all three. The tag is the one that lags.

### History that is still true

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

### Port 006 is COMPLETE. Read this before you do anything else

**ALL SEVENTEEN STAGES ARE PORTED**, on 2026-08-16. The census is seventeen
rows and not fourteen. Earlier text in this file says fourteen. That text is
incorrect and section 2's table in the RFC is the count to use.

Measured end to end with the CI invocation. The port exits 0 and prints
fifteen verdict lines: fourteen PASS and one NOT EXERCISED. The reference has
fifteen verdict-emitting sites, so the two counts agree. A negative control
with a bad `--subject` gives exit 1 and a named FAIL line.

[`tools/build-smoke/adjudicate.llmll`](../../tools/build-smoke/adjudicate.llmll)
now exists. `llmll verify` reports SAFE. It puts `fsenc-verdict` and
`status-of` on the `body-faithful` line, so both contracts are proved. Three
refutation controls each broke a different constraint.

**The last stage used `env(1)` and `PROC-ENV-1` did not block it.**
`wasi.proc.run "/usr/bin/env" ["LC_ALL=C" exe]` sets a child's environment.
A stdin path on the same call reaches the child. `env` runs `exec` in place.
The row stays open, because the assignment needs one more process.

### The cover: 8 of 9 cells pass. Cell 6 found a REAL port defect

`scripts/build_smoke_cover.py` exists and runs in `spec-roundtrip`. The step
blocks the job.

**Run the cover before you push.** It ran four times on 2026-08-16. It found
THREE defects in itself and ONE in the port. Section 0's rule applies to
instruments too: a cover that never ran measures nothing.

**Cell 6 was the port defect. It is FIXED on 2026-08-16.** The text below is
the record of the defect. The port held the reference's failure text and tested
a different condition:

- The reference asks whether the BINARY exists.
- The port asked whether `stack path` returned an install ROOT.

So the port's message "found no capproc-exec binary" operated only when `stack`
itself failed. When the binary was truly absent, the port ran a path that was
not there. Then it reported SEVEN assertion failures that it never tested.

**The count was wrong here and the correction is a lesson.** This section said
NINE. Seven is the length of the port's `x-miss` list. Two of the seven
messages hold a semicolon of their own, and the joined output puts a semicolon
between messages. So a count of the semicolons gives nine. Count the source
list, not the output.

**This refutes a claim in the RFC.** Section 5's `LIST-KIND-1` row says the
design "separates missing from not executable". The probe measured that `RErr`
carries that difference. The port did not use it at this call site.

**The fix is applied.** `wasi.fs.list` on the parent directory plus
`list-contains` decides existence at one listing. The builtin sweep found this
composition and `P-C1` measured it. `FS-EXISTS-1` records the row.

**Cell 7 has never run.** It needs `--slow`. Its cost is the port's own 900
second build timeout.

### Three defects the cover had, and what they teach

1. The cause assertions read only a verdict's FIRST line. The reference wraps
   its `fail` prose. So two cells died before they graded the port at all.
2. A first fix normalised whitespace at the comparison and left the extraction
   truncated. The re-run failed in the same way. Fix the layer that drops the
   data.
3. `open(lib,"w").write(open(lib).read()...)` truncates before it reads. Cell 5
   emptied `Lib.hs` rather than renaming a call. The reference's `-f` test
   accepts an empty file, so the cell failed for the correct-looking reason by
   accident.

**All three were invisible in a passing run.** The cover prints its unreached
assertions. That output is what showed the cells measured nothing.

### THREE DECISIONS WERE OPEN. ALL THREE ARE CLOSED

All three closed on 2026-08-16. Read the text below. Do not act on the
recommendations that the earlier version of this section gave.

1. **The cell 6 port defect. CLOSED.** The port makes the existence check now.
   A new phase lists the install root's `bin/`. It looks for the name in that
   list. The message is the reference's message. The cover gives PASS for cell
   6, and the two assertions in that cell that measured nothing now operate.
   **`-x` is not part of the check.** A listing decides existence only. It says
   nothing about the permission bit. `FS-STAT-1` is the row for that.
2. **`sha1`. CLOSED, and NOT in the direction this section recommended.**
   Codegen maps the name to `sha1_hash`. The recommendation was to remove the
   builtin. A measurement of the call sites refuted it: a frozen benchmark
   calls `sha1` two times, and `LLMLL.md` settled the name. Do not use section
   8's recommendation. Row `BUILTIN-BODY-1` has the record.
3. **A completeness test for builtin bodies. CLOSED.** The test is in
   `Spec.hs`. It operates on all 101 names in `builtinEnv`. Before this it
   operated on 16 names. **The test cannot see 12 of the names.** Those 12 have
   a hand-written equation in `emitApp`. The fix for `sha1` moved `sha1` into
   that set. Only a build can grade those names. The fixture calls four of
   them.

### Five measurements. THREE are owed. Items 1 and 3 are complete

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

### `tool_state` is still `blocked` and that was deliberate

State `oracle` asserts that both implementations decide over the same tree in
one job. The CI wiring now says that. No run has proved it. Move the state
after a green run and not before.

**Nine controls run against it and six are negative.** Two of the six matter
more than the others.

- A fixture that does not compile, with a complete generated `Lib.hs` left in
  the work directory by an earlier good run. That is the scenario that defeated
  the RFC's own first probe. The port reports the status. It does not read the
  stale file.
- A `regex_lower` fixture that COMPILES and calls nothing. This fires stage
  4b's second assertion, which the subject says does not decay. The preamble
  defines `regex_match` and no code calls it. Only an assertion on the CALL
  SITE sees that state.

**One assertion is NOT shown to fire, and this record says so.** Stage 4b also
asserts that the hyphenated spelling appears zero times in the emitted Haskell.
That state needs a compiler regression and not a changed input. No control
reaches it.

**`seq-commands` gives the LAST command's Response to the next step.**
`LLMLL.md` section 9.3 gives the order of execution. It does not give this.
Stage 4 prints and starts 4b's build in one step, so stage 4b showed it.

**The argument contract is settled. Use it.** The port takes `--subject` for the
compiler, `--root` for the repository and `--work` for a scratch directory.
`refutecrux.llmll` takes the same three names. Do not invent a fourth spelling.

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

**Stages 2 and 2a are DONE, and building them found a gap.** The subject reads
`$LLMLL_BIN`, then `PATH`, then `$HOME/.local/bin/llmll`. The port did the
first two. **It could not do the third**, because nothing read the environment
and `$HOME` is not in argv. This was filed as `ENV-READ-1`.

**`ENV-READ-1` SHIPPED at v0.15.0 and the third source is PORTED.** The port
gains two phases in stage 2, `Home2` and `Comp2b`. It gains no stage number,
because the subject puts the third source inside its own section 2. Five cells
were run on the built binary. The third source fires when the first two fail.
It does NOT fire when the subject works, which is the ordering control. An
unset `HOME` forms `/.local/bin/llmll`, which is what the reference's own
`"$HOME/.local/bin/llmll"` expands to, so the two agree on that input.

**The campaign census was wrong here, and this is the lesson to carry.** That
row said "no env access" is COSMETIC because "argv carries it". Port 005 tested
it and it held. **It failed at its second use.** A disposition tested against
one port measures that port. It does not measure the language.

**TWO PORTING DEFECTS were found by running the controls, not by reading.**

1. `wasi.proc.run` answers the child's EXIT STATUS. It does not answer the
   child's output. The output goes to the path in the call. So a command and a
   read of what it printed are TWO steps. Stage 2a needs five phases.
2. The subject's fallback test is a DISJUNCTION:
   `[ -z "$_SIR" ] || [ ! -x "$_SIR/bin/llmll" ]`. A root that resolves but
   holds no compiler must still fall through to `<root>/compiler`. One shared
   execute-check cannot do this, because it does not know which source it
   checks. The first version reported FAIL against a tree whose compiler was
   built and present.

**A THIRD porting defect, and the compiler found it.** `llmll check` gave OK
with two warnings: `call to unknown function 'list-empty?'` and
`call to unknown function 'string-join'`. Neither name exists. **The old gotcha
said `check` passes an unknown callee at exit 0, and it still does**, but it now
prints a warning that names each one. Read the warnings. Use `list-length` and
`string-concat-many` instead.

**Stage 5 is next**, CAP-PROC, at 38 subject code lines. It is the first stage
that BUILDS a fixture and then RUNS the binary, and it matches the output
against known answers. Stages 1 to 4b only build. Expect the run to need the
`exe_path` mechanism: ask `stack path` for the install root of the fixture's
own output directory, then execute the binary under its `bin/`. Stage 2a
already does this for the compiler, so copy that five-phase shape.

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
| **006** build-smoke | Last. It runs the other gates. **ALL SEVENTEEN STAGES PORTED 2026-08-16**, with `adjudicate.llmll` verified SAFE and a cover at 8 of 9 cells. `tool_state: blocked` on purpose: the branch is unpushed and no CI run has graded it. Cell 6 holds an unfixed port defect. Section 2 gives the three open decisions |
| **P1** tag debt | **DONE for v0.14.84 to v0.14.87.** Four tags pushed. Four images published. **This row is history and not the current state**: on 2026-08-16 the banner reads `v0.16.0` and the last tag reads `v0.15.0`. See section 1 |
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
