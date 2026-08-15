---
name: tool-rfc-006-build-smoke
title: "TOOL-RFC-006: BUILD-GATE-1, the build smoke harness, in LLMLL"
status: "Rev 4, PORT STARTED. The RFC was written before any port code, which is the campaign's order. State stays `blocked`, and that is now an APPROXIMATION rather than a fact: the tri-state is blocked, oracle, retired, and it has NO VALUE FOR 'started and incomplete'. `tools/build-smoke/buildsmoke.llmll` exists and holds the spine plus stage 1 of fourteen, so the earlier gloss 'blocked means the port module does not exist yet' is false as of 2026-08-12. `blocked` is the only state the RFC standard gate accepts here, because `oracle` asserts both implementations decide over the same tree in one job and this port decides nothing yet. THE VOCABULARY GAP IS FILED IN THIS LINE RATHER THAN LEFT FOR A READER TO INFER. NO DECISION IS OPEN, and §9's opening line said otherwise until 2026-08-12: it still read 'one decision is open and it blocks the port', which was true at Rev 1 and false from the moment `PROC-STDIN-1` shipped. The frontmatter was corrected at Rev 2 and the section body was not, which is the campaign's own stale-record class. D3 IS NOW DISCHARGED: the two capability rows this RFC deliberately refused to assume were PROBED on 2026-08-12 against `llmll 0.14.99`, by one program that exercised both and printed what the runtime answers. `wasi.fs.sha256` gives `RText` lowercase hex matching `shasum -a 256` byte for byte, so it is a real SHA-256 and not the polynomial stub `LLMLL.md` §13 records for the sibling SHA-1, and the byte-compare row stays COSMETIC. A failed exec answers `RErr`, the step machine SURVIVES it, and the message separates *missing* from *present but not executable*, so at this call site `LIST-KIND-1` is a GAIN over the subject's one-bit `-perm -111` test rather than a loss; the row does not close, because nothing answers 'is this executable' without attempting the run. THE TWO GAPS THIS RFC RAISED AGAINST THE COMPILER ARE SHIPPED, at v0.14.98 on 2026-08-12, BEFORE the port was written, and that reorders the campaign: normally a port works around a gap and files it. `PROC-STDIN-1` gave `wasi.proc.run` a seventh parameter, a stdin path. `PROC-STDIN-SHARE-1` was a COMPILER DEFECT: `std_in` was unset, so `createProcess` inherited and a child could read a TORN fragment of the parent's own step input above the 8 KiB handle buffer, with three runs taking three different victims. It was latent in all five shipped ports, because `git ls-files` and `llmll version` do not read stdin. `PROC-ENV-1` stays open and no port needs it yet. THE PORT THEREFORE PASSES A PATH AND WRITES NO SHELL STRING. D1 is SUPERSEDED: it had bounded the `sh -c` cost to one `drive` helper, and no `drive` helper will be written. Section 4 and D1 are KEPT rather than deleted, because the census counts the gap the port surfaced, not the workaround it avoided; a reader who wants the current mechanism reads `LLMLL.md` section 13. The port is FEASIBLE: one complete stage was written in LLMLL, built, and run against a good fixture and a broken one, and it discriminates. A negative control caught that stage reporting PASS against a build that exited 1, by reading a stale artifact. THE SIZE PROJECTION THIS RFC INHERITED WAS WRONG BY 1.8 TIMES: 4.8 is the FIRST port's ratio, the five ratios decline to 2.23, and the measured one-stage ratio is 2.6, so the port projects to about 1,400 code lines and not 2,500."
date: 2026-08-11
author: experiment-lead
tool_state: blocked
subject_script: scripts/build_smoke.sh
port_module: tools/build-smoke/buildsmoke.llmll
---

# TOOL-RFC-006: BUILD-GATE-1, the build smoke harness, in LLMLL

## 1. Subject

[`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) is the sixth and last
gate in this campaign. It holds 1,074 lines, of which 529 are code. The five
shipped ports read a tree, decide, and print. This subject does not. It compiles
LLMLL programs, runs the binaries, and reads what they printed.

**The subject is the harness that tests the other ports.** Stage 10 builds and
runs `versiongate.llmll`, which is the port from TOOL-RFC-001. Stages 8 and 9
build and run the DRIVER-LL programs. So a port of this subject is an LLMLL
program that tests LLMLL programs.

**Fourteen stages, each with its own verdict line.** Every stage prints
`BUILD-GATE-1 PASS` or fails the job. The stages are numbered 1, 2, 2a, 3, 4,
4b, 5, 5b, 5b, 6, 7, 8, 9 and 10 in the subject's own banners. **Two stages
carry the label `5b`**, at line 368 and line 493. That is a defect in the
subject and D5 says what the port does about it.

**Thirteen sites call `llmll build`.** A count of nine appears in the record
that opened this work. The count is thirteen call sites, measured 2026-08-11 at
`75facb0`. One of the thirteen sits inside `replay_case`, which is called more
than once, so the number of executions is higher than the number of sites.

**The subject changed on 2026-08-11 and the port inherits the new form.** Twelve
sites used to search a directory tree for a built executable. The search was the
defect: a tree can hold more than one install root, and neither the old pick nor
a sorted pick is correct. The subject now asks `stack path --local-install-root`
through one `exe_path` helper at line 86. **Do not port a tree walk.** There is
none left to port.

## 2. Criteria

The port must reproduce each stage's verdict. The stages, with the code line
count of each, measured 2026-08-11:

| # | Stage | Code lines | What it decides |
|---|---|---|---|
| 1 | toolchain | 6 | GHC and Stack are present. It fails closed and never skips |
| 2 | compiler | 10 | an `llmll` binary exists |
| 2a | anchor | 26 | the compiler path is absolute before any step changes directory |
| 3 | build | 7 | `llmll build` exits 0 on `smoke.llmll` |
| 4 | corroboration | 25 | the generated Haskell exists and names the fixture's definitions |
| 4b | REGEX-LOWER-1 | 26 | the generated `Lib.hs` binds a `regex_match` prefix |
| 5 | CAP-PROC | 38 | the built binary executes a child and matches known answers |
| 5b | FS-ENCODING-1 | 56 | a UTF-8 round trip survives `LC_ALL=C`, and `wasi.fs.copy` is byte-faithful |
| 5b | CAPTURE-ENCODING-1 | 35 | non-ASCII literals survive `captureStdout` as UTF-8 |
| - | JSON-SCALAR-1 | 37 | scalar JSON array elements project to values, and mis-typed reads refuse |
| - | PROC-MERGE-1 | 36 | equal `wasi.proc.run` paths merge both streams, and unequal paths do not |
| 6 | REPLAY-FRAME | 59 | recorded runs replay clean, and tampered logs are refuted |
| 7 | PROC-BOUNDARY-1 | 59 | argv arrives on `RList`, `:done?` exits 42, a starved program exits 70 |
| 8 | DRIVER-LL 4a-4c | 24 | the sequencer cover, 11 transition cells and 3 manifest shapes |
| 9 | DRIVER-LL 4e | 26 | the wave cover, 7 cells |
| 10 | DRIFT-CI-1 | 34 | `versiongate.llmll` decides the version gate, 14 cover cells |

**Two stages have no number in the subject.** JSON-SCALAR-1 at line 561 and
PROC-MERGE-1 at line 619 sit under a bare rule of dashes. The port gives each a
name, because a stage with no name cannot be cited in a failure report.

## 3. Distribution

**This port costs nothing to place, and it is the first one that does not.**
The subject already runs in the `spec-roundtrip` job, at
[`version-gate.yml`](../../.github/workflows/version-gate.yml) line 516. That
job carries a toolchain, because the subject needs one to call `llmll build`.

The campaign's amended rule at §3 says a port runs only in a toolchain-bearing
job. It also says that a gate whose reference sits in a toolchain-free job must
relocate wholesale. **No relocation applies here.** The reference is already in the
correct job. The port becomes a step adjacent to it, which is what states
`oracle` requires.

**The cost that does apply is time.** The port compiles fourteen fixtures with
GHC, as the reference does. One warm `llmll build` of the smallest fixture took
18.13 seconds, measured 2026-08-11 on aarch64-osx. Running both implementations
adjacent therefore doubles the most expensive step in the job. D4 records that.

## 4. Feasibility

**Measured by probe, not read from a table.** Port 005's feasibility read was
wrong twice in the same direction. So every row below that says *measured* was
executed against `llmll 0.14.97`, built from the tree at `75facb0`. A binary
reporting `0.14.96` was on `PATH` at the start of this work. It was rebuilt
first; see F6.

### The scope question is answered by building one stage

**One complete stage of the subject was written in LLMLL, built, and run.** The
stage is 4b, REGEX-LOWER-1, the smallest of the fourteen. It creates a
directory, calls `llmll build` on a fixture, keeps the exit status, reads the
generated `Lib.hs`, and prints the subject's exact PASS line.

It discriminates. Two cells were run:

| Cell | Input | Result |
|---|---|---|
| positive | the real `regex_lower.llmll` fixture | `BUILD-GATE-1 PASS: REGEX-LOWER-1 fixture compiled and binds regex_match prefix` |
| negative | a fixture that fails to compile, with a STALE `Lib.hs` left in place | `BUILD-GATE-1 FAIL: fixture did not compile, status=code:1` |

**The negative cell earned its place.** The first version of the stage printed
PASS against a build that exited 1. It read the artifact in a later step than
the one the status arrived in, and it never branched on the status. The stale
`Lib.hs` from the previous run satisfied the assertion. In shell the check is
structural, because `if ! llmll build ...; then fail; fi` puts it first. In a
console step machine the status is a `Response` in step N and the read is step
N+1. The order is therefore a hand-written control state, and nothing checks it.

### The line cost, measured rather than projected

| Quantity | Value |
|---|---|
| stage 4b in shell | 26 code lines |
| stage 4b in LLMLL, working, both cells | 68 code lines |
| ratio | 2.6 |

**The 4.8 times figure this work inherited is the FIRST port's ratio, not the
campaign's.** The five shipped ports expand their subjects by 4.79, 3.24, 3.13,
2.75 and 2.23. The series declines monotonically, and the aggregate is 3.01 over
552 subject code lines. The 2.6 measured here sits inside that series.

So the port projects to about **1,400 code lines**, not the 2,500 the 4.8 figure
gives. At the comment density of `pathlint.llmll`, which is 47 percent, that is
about 2,600 total lines.

**That size is large and it is not unprecedented.** The largest LLMLL program in
the tree is [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) at 954
code lines and 1,784 total lines. It builds and it runs in this same job. The
largest program in this campaign is
[`refutecrux.llmll`](../../tools/refute-crux/refutecrux.llmll) at 369 code lines.

### The capability rows

| Needs | LLMLL | Note |
|---|---|---|
| Run `llmll build` and keep its exit status | **available**, `wasi.proc.run` | **Measured**: `RCode 0` on success and `RCode c` on failure, from `CodegenHs.hs:752`. The stage probe read `code:0` and `code:1` and branched on both |
| Locate a built binary | **available**, `wasi.proc.run` with a cwd | The subject's own `exe_path` helper runs `stack path --local-install-root`. The port calls the same command with the same cwd. **Do not use an mtime**; no `wasi.fs.stat` exists, per `FS-STAT-1` |
| Create the output directory | **available**, `wasi.fs.mkdir` | **Measured** in the stage probe. `registry.llmll:373` records that it creates parents and answers `RNone` |
| Capture a child's stdout and stderr | **available**, `wasi.proc.run` | The two path arguments. Equal paths merge, which is the property stage PROC-MERGE-1 itself tests |
| Read the captured text | **available**, `wasi.fs.read` | **Measured** in the stage probe |
| Assert on the text | **available**, `string-contains` and `regex-match` | The subject's assertions are substring tests and one prefix test |
| **Feed a child on stdin** | **gap** | See below. This is the finding of this RFC |
| Set `LC_ALL=C` for a child | **gap** | `wasi.proc.run` takes six parameters and none is an environment. **Measured**: the child INHERITS the parent's environment, so `LC_ALL=C` set outside the port reaches the child, but the port cannot set it. One site, at line 443 |
| Compare two files byte for byte | **available**, `wasi.fs.sha256` | The subject uses `cmp` at three sites and `od` at one. A hash of each file answers the same question. Not yet exercised by a probe; D3 records that |
| Exit with a distinct status | **available**, `console` mode | `:mode cli` performs no `Command`, per `MODE-CLI-1`, so this port is a stdin-driven step machine like the other five |

### The finding: thirteen sites feed a child on stdin

`wasi.proc.run` sets `std_out` and `std_err` and does not set `std_in`
(`CodegenHs.hs:740-744`). **Thirteen sites in the subject pipe input into the
binary they just built**, at lines 327, 443, 535, 594, 655, 837, 843, 850, 858,
865, 892, 894 and 1065.

**That is not an accident of style.** A console-mode LLMLL program takes one
line of stdin per step. Driving one therefore IS feeding it stdin. The subject
exists to run console-mode programs, so the idiom is the subject's whole job.

Seven of the sixteen stages contain such a site:

| Stage | Sites | Also needs |
|---|---|---|
| 5 CAP-PROC | 1 | - |
| 5b FS-ENCODING-1 | 1 | `LC_ALL=C`, and a byte compare |
| 5b CAPTURE-ENCODING-1 | 1 | a byte compare |
| JSON-SCALAR-1 | 1 | - |
| PROC-MERGE-1 | 1 | - |
| 7 PROC-BOUNDARY-1 | 7 | - |
| 10 DRIFT-CI-1 | 1 | - |

Those seven stages hold 295 code lines. The nine stages with no such site hold
209 code lines. **So the gap reaches 56 percent of the subject's stage code.**

### `/bin/sh -c` supplies the stdin, so the disposition is SHAPES

A third probe measured whether `wasi.proc.run` can spawn `/bin/sh` and let the
shell build the pipe. Two cells, both **measured**:

| Cell | Command | Result |
|---|---|---|
| A | `sh -c "printf 'ALPHA\nBETA\n' \| head -2 \| tr '\n' ','"` | `ALPHA,BETA,` |
| B | `sh -c "printf 'R1..R8' \| ./stdinprobe"` | the grandchild ran its whole console loop and read `R1` through `R6` |

Cell B is the shape stages 5, 7 and 10 need: a real console-mode LLMLL binary,
driven by input the port chose. It works. The port's own stdin was not
disturbed.

**So the port is not blocked, and the cost is precise.** `wasi.proc.run` splits
the executable from its argument vector on purpose. `TypeCheck.hs:190-196`
states the reason: the executable becomes a syntactic constant that a reader can
enumerate from the module header, and shell metacharacter interpretation stops
being a category. **Routing thirteen sites through `sh -c` puts the whole
command back into one shell string.** The property the split exists to give is
lost at exactly the sites that matter most, which are the sites that run the
other ports.

D1 puts that cost to the user.

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| `wasi.proc.run` cannot supply a child's stdin, and driving a console-mode LLMLL program is feeding it stdin | **SHAPES** | `PROC-STDIN-1`, filed 2026-08-11, shipped v0.14.98 | A seventh parameter, a stdin path, symmetric with the stdout and stderr paths the builtin already takes. Instead thirteen sites route through `/bin/sh -c` and rebuild the shell string that the argv split removes. **Measured**: `sh -c` does deliver the input, and a real console binary driven that way completes its loop, so this SHAPES the port rather than blocking it. The gap reaches 295 of 504 stage code lines |
| A child spawned by `wasi.proc.run` SHARES the parent's stdin, and above the 8 KiB buffer it reads a torn fragment of the parent's own input | **SHAPES** | `PROC-STDIN-SHARE-1`, filed 2026-08-11, shipped v0.14.98 | `std_in` bound to an empty handle, or to the stdin path `PROC-STDIN-1` asks for. Instead the port must keep its own stdin under 8 KiB, which is a constraint nothing states or checks. **Measured**, and the numbers are in F2 below. This is a compiler defect as well as a gap, and it is routed to the compiler-engineer |
| No environment channel: `wasi.proc.run` takes no environment and no `wasi.env.*` name exists | **SHAPES** | `PROC-ENV-1`, filed 2026-08-11, open | `LC_ALL=C cmd`, as the subject writes it at line 443. Instead the site goes through `sh -c`, which sets the variable in the shell string. **Measured**: a child INHERITS the parent's environment, so the campaign's older "no env access" row is about READING and this is about SETTING. The two are not the same row, and folding them is the mistake that made `FS-STAT-1` and `FS-EXISTS-1` need splitting |
| A program cannot READ its own environment, so the subject's `$HOME/.local/bin/llmll` branch is unreachable | **SHAPES** | `ENV-READ-1`, filed 2026-08-12 | An env read, `wasi.env.get` answering a `Result` so unset and empty differ. Instead the port takes `--subject` and drops the branch, which is a BEHAVIOUR difference rather than an invocation one. **Found by building stage 2**, not by reading: the campaign census carried this COSMETIC on the rationale "argv carries it", tested at 005 where it held. Argv carries what a caller passes, and `$HOME` is not passed. `sh -c 'echo $HOME'` works and is refused under D1 |
| `:mode cli` performs no `Command` and yields no exit status | **SHAPES** | `MODE-CLI-1` | A straight-line program: build, run, assert, exit. Instead the port is a stdin-driven step machine with an explicit control state. This is the campaign's largest line-count multiplier and it applies here fourteen times over, once per stage |
| A listing carries no entry kind, so nothing answers "is this file executable" | **SHAPES** | `LIST-KIND-1` | The subject's `-perm -111` test inside `exe_path`. Instead the port asks `stack path` for the directory and attempts the run, letting a failed exec answer. **PROBED 2026-08-12 and the design holds**: a failed exec answers `RErr`, the step machine survives it, and the message separates *missing* from *not executable*, which the subject's one-bit `-perm -111` test cannot. See D3 |
| No recursive directory walk | **COSMETIC** | `FS-WALK-1` | Nothing follows. The twelve walk sites were deleted from the subject on 2026-08-11 and replaced by `stack path --local-install-root`. The row closed on 2026-08-10 and this port confirms the close |
| No file-age predicate | **COSMETIC** | `FS-STAT-1` | Nothing follows. The subject reads no mtime, and the port must not introduce one |
| Comparing two files byte for byte | **COSMETIC** | `wasi.fs.sha256` exists | Nothing follows. The subject uses `cmp` and `od`; a hash of each file answers the same question. **PROBED 2026-08-12**: the digest is `RText`, lowercase hex, and matches `shasum -a 256` byte for byte, so it is a real SHA-256 and not the polynomial stub `LLMLL.md` §13 records for the sibling SHA-1. See D3 |

**Three gaps were named and unfiled when this RFC was written. All three are
now filed, and TWO ARE SHIPPED.** `PROC-STDIN-1` and `PROC-STDIN-SHARE-1`
closed at v0.14.98, on 2026-08-12, before the port was written.
[`compiler-team-roadmap.md`](../compiler-team-roadmap.md) holds all three;
the two closed rows sit in its closed-rows section and `PROC-ENV-1` stays open
in Active Items.

**That reorders the campaign, and the reordering is the finding.** A port
normally works around a gap and files it. Here the compiler closed the gap
first, so §4's `sh -c` analysis and D1's `drive` helper describe a cost the
port never paid. **Both are kept rather than deleted**, because the census in
campaign §5 counts the gap the port surfaced, not the workaround it avoided.
A reader who needs the current mechanism should read `LLMLL.md` §13, not §4
here.

The campaign's §5 records why the name comes first. `LIST-KIND-1` sat in no
census for a release, because port 004 recorded it with no tag. A search for
tag names cannot find a gap that has no tag.

## 6. Differential plan

The cover compares the port's stdout against the reference's, per stage, on a
mutated tree. It follows 005's shape, because 005's subject also exits 0 in
places and a cover on exit codes alone would grade little.

**The negative controls come first and their unreached assertions are read
off.** Ports 003 and 004 both found real defects only through their negative
controls. Port 005's cover then passed 22 of 22 on its first run. Two of those
cells were later shown to be able to fail.

Planned cells, per stage that the port covers:

| Cell | Mutation | Expected |
|---|---|---|
| 1 | control: an unmutated tree | both implementations PASS every stage, **except the `LC_ALL=C` encoding claim on Linux; see the note below the table** |
| 2 | control: a fixture that does not compile | both FAIL stage 3, and name the fixture |
| 3 | control: a stale artifact present under a failing build | both FAIL. **This cell exists because the stage probe passed it wrongly**; see §4 |
| 4 | delete a definition the corroboration stage names | both FAIL stage 4 |
| 5 | remove the `regex_match` prefix from the generated `Lib.hs` | both FAIL stage 4b |
| 6 | make `llmll build` succeed while the binary is absent | both FAIL, and neither reports PASS from a stale binary |
| 7 | a build that exceeds the timeout | the port answers `RErr` and FAILS. The reference has no timeout, so this cell grades the PORT only, and it is labelled as such |
| 8 | grep the port for a `/bin/sh` call site outside `drive` | zero hits. **D1 bounds the shell strings to one helper, and this cell is what keeps them there** |

**The `LC_ALL=C` encoding claim is REFERENCE-ONLY on Linux, and cell 1 is
labelled for it on cell 7's precedent.** `scripts/build_smoke.sh` sets
`LC_ALL=C` for one child in the FS-ENCODING-1 stage. The port cannot set a
child's environment: `PROC-ENV-1` is open, and `ENV-READ-1` does not close it,
the two being opposite directions of one namespace. **On Darwin the two agree**,
because GHC there resolves UTF-8 whatever `LC_ALL` says, so the reference prints
`BUILD-GATE-1 NOT EXERCISED: the LC_ALL=C encoding claim (FS-ENCODING-1)` and
the port reproduces that branch faithfully. **On Linux they diverge**: the
reference settles the claim and the port still prints NOT EXERCISED. So cell 1's
"both PASS every stage" does not hold for that one stage on Linux, and the cover
must not read the divergence as a port defect. The asymmetry is the mirror of
cell 7's: there the port can do something the shell cannot, and here the shell
can do something the port cannot. **A cover that hid either would claim an
agreement it did not measure.** The label comes off when `PROC-ENV-1` ships.

**Cell 7 is not a differential cell and the plan says so.** `wasi.proc.run`
takes a timeout and the shell does not. A cover that hides that asymmetry would
claim an agreement it did not measure.

## 7. Verification

**What the port can prove is narrow, and naming it is the point.** The
adjudication of a stage's verdict is a function over booleans. Port 005 measured
that shape: a `def` over six bools verifies `body-faithful` and SAFE, and
dropping one clause is refuted.

The port therefore splits, as 005 does:

- `adjudicate.llmll` holds the verdict logic and carries a contract. It is
  verified in the job BEFORE the harness module is checked.
- `buildsmoke.llmll` holds the effects. It cannot carry a proof, because its
  results are `Command` values and its recognizers compare strings, which falls
  back per `STRLIT-BODY-1`.

Both files sit under `tools/build-smoke/`. Neither exists yet, and that is why
this RFC's `tool_state` is `blocked`. The two names are written without a
directory on purpose. A full path would make the prose citation lint report two
files that the port has not written.

**The ordering is a constraint and not a preference.** Port 005 measured this
with no sidecar present. `llmll check` on the port warns that the core has an
unproven contract. The warning disappears once the core is verified. The sidecar
is gitignored. So the trust comes from running verify in the job.

**What no instrument here reaches.** The port asserts that fourteen stages
print what the reference prints. It does not assert that the compiler behaviours
those stages test are correct. That is the subject's job and it stays the
subject's job.

## 8. Retirement

`scripts/build_smoke.sh` is deleted one release after the port lands, in the
same commit that moves `tool_state` to `retired`. Before that, all of:

- the §6 cover green, with its negative controls run FIRST;
- both implementations running adjacent in `spec-roundtrip`;
- one release elapsed in state `oracle`;
- the three unfiled gaps of §5 filed in the roadmap with their names;
- `adjudicate.llmll` verified in the job BEFORE `buildsmoke.llmll` is checked.

**A condition this port adds, which no previous port needed.** The subject is
the harness that builds and runs the other five ports. **Deleting it deletes the
only thing that runs them.** So retirement here is not the removal of a
duplicate; it is a handover of the job that tests the whole campaign. The port
must run all fourteen stages, or the stages it drops must be reassigned to a
named owner in the same commit.

**The 005 precedent applies and it is a warning.** The user deleted
`test_doc_path_lint.py` on 2026-08-11 and accepted the loss.
Nothing now blocks a broken prose citation from reaching `main`, because both
remaining checks exit 0 when they find one. That was a decision and RFC-005 §8
holds the reason. **The lesson this port takes from it**: name what the deletion
removes before the deletion, not after CI reddens.

## 9. Decisions taken

**NO DECISION IS OPEN. All five are taken, and D1 was taken twice.** This
paragraph said "one decision is open and it blocks the port" until 2026-08-12,
which was true when Rev 1 was written and false from the moment `PROC-STDIN-1`
shipped at v0.14.98. The frontmatter was corrected at Rev 2 and this line was
not, which is the stale-record class the campaign keeps finding: a change
recorded in one place and not in the places that advertise it. The RFC-first
order exists because TOOL-RFC-001 made three of its four calls at the keyboard
and reported them afterwards.

**D1. SUPERSEDED 2026-08-11, later the same day, and the supersession is the
better outcome.** The user first chose option 2, "bound it", and then chose to
fix the compiler before the port. `PROC-STDIN-1` shipped a seventh parameter on
`wasi.proc.run`, a stdin path. **So the port needs no `sh -c` and no `drive`
helper, and none will be written.** The thirteen sites pass a path, exactly as
they pass a stdout path. The record below is kept because it shows what the port
would have cost had the compiler not moved, and because the campaign's §5 census
counts the gap the port surfaced rather than the workaround it avoided.

**D1, as first settled. SETTLED by user adjudication 2026-08-11: BOUND IT,
option 2 below.** Thirteen sites need a child's stdin, and `/bin/sh -c` is the
only mechanism that supplies it today. Measured working. The cost is that those
thirteen sites carry a shell string, which removes the auditability property
`wasi.proc.run`'s argv split exists to give. Three answers were available:

1. **Accept it.** The port covers all fourteen stages and thirteen sites carry a
   shell string. `PROC-STDIN-1` is filed and stays open.
2. **Bound it.** One helper builds every shell string from an executable and a
   fixed input. The strings then come from one place, and a reader audits that
   place. The port still covers all fourteen stages.
3. **Refuse it.** The port covers the nine stages that spawn no stdin-fed child,
   which is 209 of 504 stage code lines. `PROC-STDIN-1` becomes BLOCKS for the
   rest, and the compiler ships the parameter before the port completes.

**The user chose option 2 on 2026-08-11.** It keeps the census complete, which
is the campaign's deliverable, and it puts the shell strings where an auditor
can read them all at once. **It does not restore the property; it localizes the
loss.** `PROC-STDIN-1` stays open, and closing it deletes the helper.

**The helper was BUILT AND RUN before this decision was written down, not
sketched.** A design offered in a decision is not evidence that it works.

```
(def-shell drive [exe: string input: string out: string] -> Command
  (wasi.proc.run "/bin/sh"
    ["-c" (string-concat-many ["printf '" input "' | " exe " 2>&1"])]
    "." out out 600))
```

**Measured**: `drive "./stdinprobe" "D1\nD2\n...D8\n"` delivered `D1` through
`D6` in order to a real console-mode LLMLL binary, which ran its whole step loop
and exited. Three things survive that the sketch does not show: `string-concat-many`
yields one argv member; the newline escapes reach `printf` as newlines through
an LLMLL literal and a single-quoted shell string; and the driven binary
finishes rather than starving.

**The rule this puts on the port.** No site calls `wasi.proc.run` with
`/bin/sh` except `drive`. A reader who audits `drive` has audited every command
the port hands to a shell. A second shell call site is a defect, and the cover
in §6 gains a cell that greps the port for one.

**D2. Scope. TAKEN: the full subject, subject to D1.** The size projection that
suggested otherwise was wrong by 1.8 times, and the measurement is in §4. A
partial port would leave the harness split between two implementations.
Section 8 of the 005 RFC found that arrangement hiding a decider in an
unexpected place.

**D3. Two capability rows were NOT probed when this RFC was written, and this
RFC said so rather than assuming them.** The byte compare through
`wasi.fs.sha256` and the executable test under `LIST-KIND-1` were read from the
compiler's builtin table and from an existing call site. Port 005's feasibility
read was wrong twice by doing exactly that.

**BOTH ARE NOW PROBED, 2026-08-12, against `llmll 0.14.99`. Both hold, and the
second is better than the design assumed.** One program exercised both rows and
printed what the runtime answers.

| Row | Probe | Answer |
|---|---|---|
| byte compare | `wasi.fs.sha256` over two identical files and one differing file | `RText` with a lowercase hex digest. Identical bytes gave identical digests; differing bytes differed |
| `LIST-KIND-1`, missing | `wasi.proc.run "./no-such-binary"` | `RErr "./no-such-binary: createProcess: execvp: does not exist (No such file or directory)"` |
| `LIST-KIND-1`, not executable | `wasi.proc.run` on a file written with no execute bit | `RErr "./plain.txt: createProcess: execvp: permission denied (Permission denied)"` |
| survival | a line printed after both failures | It printed. Neither failure ended the step machine |

**The digest is faithful, and that needed checking rather than assuming.**
`LLMLL.md` §13 records that the preamble's SHA-1 is a simplified polynomial
stub, so a sibling hash being real is not implied by its existence. Both digests
match `shasum -a 256` byte for byte: `5891b5b5…be03` for `hello\n` and
`e258d248…b317` for `world\n`. So the §5 COSMETIC disposition holds.

**The failed-exec answer is STRICTLY MORE INFORMATIVE than the test it
replaces, which reverses the direction the gap row implied.** The subject's
`-perm -111` answers one bit, executable or not, and cannot say why a lookup
failed. `RErr` separates *missing* from *present but not executable* in the
message text. A `LIST-KIND-1` row phrased as a loss is, at this call site, a
gain. **This does not close the row**: nothing here answers "is this file
executable" without attempting to run it, which is a different question and the
one the row states.

**D4. The job's time budget doubles at the most expensive step. TAKEN:
accepted, and measured before the port lands.** One warm build of the smallest
fixture is 18.13 seconds. Fourteen fixtures run twice is the cost of state
`oracle`, and that state lasts one release. If the job exceeds its limit, the
port drops to a nightly step and this RFC gains a revision saying so.

**D5. The subject's two stages labelled `5b`. TAKEN: the port gives every stage
a distinct name.** The subject also leaves two stages with no number at all, at
line 561 and line 619. A stage with no unique name cannot be cited in a failure
report, and the cover in §6 needs one cell per stage.

---

## Findings routed out of this RFC

**F1. `PROC-STDIN-1`. To the language-team.** `wasi.proc.run` cannot supply a
child's stdin. A seventh parameter, a stdin path, would be symmetric with the
two path parameters it already takes.

**F2. `PROC-STDIN-SHARE-1`. To the compiler-engineer. This is a defect, not
only a gap.** A child spawned by `wasi.proc.run` inherits the parent's stdin,
because `CodegenHs.hs:740-744` sets `std_out` and `std_err` and leaves `std_in`
unset. Measured 2026-08-11 on aarch64-osx, with a console-mode parent and a
child that reads one line:

| Parent stdin | Bytes | Child read | Parent's step sequence |
|---|---|---|---|
| pipe, 8 lines | 55 | nothing | intact |
| pipe, 1,000 lines | 7,893 | nothing | intact |
| pipe, 1,200 lines | 9,693 | `NE1034` | intact |
| pipe, 20,000 lines, run 1 | 138,893 | `NE1034` | intact |
| pipe, 20,000 lines, run 2 | 138,893 | `LINE18` | intact |
| pipe, 20,000 lines, run 3 | 138,893 | `LINE4` | **skipped one line** |
| file, 20,000 lines | 138,893 | nothing | intact |

Three properties follow. **The threshold is the 8 KiB handle buffer**, between
7,893 and 9,693 bytes. **The child reads a TORN value**: `NE1034` is the tail of
`LINE1034`, cut where the parent's buffer ended. **The outcome is a race**, and
run 3 shows the parent losing a step input to the child.

**The defect needs TWO conditions at once.** The child must read stdin, and the
parent must hold more than 8,192 bytes on its own stdin.

**A first census of this asked the wrong question, and it is corrected here.**
The first version said the shipped ports are safe because `git ls-files` and
`llmll version` do not read stdin. That is true and it is too narrow. The
population is **16 `wasi.proc.run` call sites across 8 committed programs**,
counted 2026-08-11, and it includes programs that spawn an AI agent CLI:
`sequencer.llmll:1248` and `wave.llmll:623`. An agent CLI may read stdin, so
condition one is not ruled out for them.

**What protects the tree today is condition TWO, not condition one.** Measured
in the covers that drive those programs in CI:

| Program | Fed by | Stdin bytes | Against 8,192 |
|---|---|---|---|
| `sequencer.llmll` | `driver_ll_cover.py`, `BUDGET = 800` | 1,600 | under |
| `wave.llmll` | `wave_cover.py`, `BUDGET = 400` | 800 | under |
| `versiongate.llmll` | `build_smoke.sh` line 1064 | 120 | under |

**So the defect does not fire today, and the margin is a number nobody chose
for this reason.** Raising `BUDGET` in `driver_ll_cover.py` from 800 to 4,097
crosses the threshold. No comment states the constraint, and no gate checks it.
**A green run is therefore not evidence that the tree is safe from this.** It is
evidence that three stdin volumes are small.

**F3. `RC-4` swallows a verdict, and nothing warns.** A state may print or
finish, never both. The stage probe returned its PASS line and its terminal
state in one step. The command was discarded, and **the program exited 0 having
printed nothing**. The rule is known and `proc_merge.llmll:76` states it. The
finding is the failure mode: a silently swallowed verdict and a zero exit read
as a pass.

**F4. The response in a state belongs to the command the PREVIOUS state
issued.** The stage probe branched on `:init`'s `wasi.fs.mkdir` result while
believing it held the build's exit status, and reported a compile failure that
had not happened. Both F3 and F4 were caught by the negative control and neither
was caught by reading.

**F5. `llmll check` passes an unknown function call at exit 0, where
`llmll build` exits 1.** Measured: a module calling
`this-function-does-not-exist` gives `OK (4 statements, 1 warning)` and exit 0
from `check`, and `error: call to unknown function` with exit 1 from `build`.
**This is a rediscovery, not a new finding.** RFC-005 already routed it. It is
recorded here because it is the second port to meet it.

**F6. Nothing compares the BUILT compiler's version to the banner.** At the
start of this work the binary under `stack path --local-install-root` reported
`llmll 0.14.96` while `LLMLL.md`, `compiler/package.yaml` and
`compiler/llmll.cabal` all said `0.14.97`. The version gate compares the five
banners with each other and with no binary. So a stale binary passes every gate.
This is the class the restart record's own warning names, met again.

**F7. Two counts of the `wasi.*` builtin set disagree, and this RFC does not
reconcile them.** `builtinEnv` in `compiler/src/LLMLL/TypeCheck.hs` carries
FOURTEEN `wasi.*` names, counted 2026-08-11 at `75facb0`. TOOL-RFC-005 §4
records sixteen, on 2026-08-10. **Neither count is corrected here.** The set may
have changed between the two dates, and this RFC did not measure that history.
It is recorded so that the next port measures the number rather than inheriting
either one. Two wrong counts on one gap is already this campaign's finding at
`FS-WALK-1`.
