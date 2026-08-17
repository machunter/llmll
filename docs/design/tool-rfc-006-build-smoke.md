---
name: tool-rfc-006-build-smoke
title: "TOOL-RFC-006: BUILD-GATE-1, the build smoke harness, in LLMLL"
status: "Rev 7, THE STATE IS `oracle` AND THIS FIELD ARGUED FOR `blocked` FOR A DAY. `tool_state` flipped from `blocked` to `oracle` at `073ae4b` on 2026-08-16, and that commit changed exactly ONE line of this file, the field itself. Everything below it still argued the other way, twice in the words `tool_state` STAYS `blocked`, so the frontmatter contradicted its own status prose. Found 2026-08-17 by measuring the six-gate census rather than reading it. NO GATE COMPARES THE TWO: `scripts/tests/test_tool_rfc_standard.py` asserts the FIELD against the filesystem and never reads this string, which is why a self-contradicting record passed green. It is the neighbour of `FRONTMATTER-GATE-1` and not that row: that one is about YAML nothing can parse, and this one is about YAML that parses and is wrong. THE FLIP WAS CORRECT AND THE Rev 5 REASON HAD EXPIRED. `blocked` rested on this port running in NO CI job, checked against `.github/` on 2026-08-15. It now has THREE steps in `spec-roundtrip`: verify the adjudicator, run the 1,166-line differential cover, and run the port end to end beside `scripts/build_smoke.sh`. Stage 5b `FS-ENCODING-1` was the last unwritten row and it landed, setting `LC_ALL=C` through one exec of `/usr/bin/env` and no shell, so SEVENTEEN OF SEVENTEEN stage rows are ported and the count in the sentences below is superseded. WHERE THE CAMPAIGN STANDS, measured 2026-08-17: FOUR of six gates are `retired`, 005 on 2026-08-11 and then 004, 003 and 002 on 2026-08-17, and the two at `oracle` are this one and TOOL-RFC-001. 001 is mechanically blocked, its reference running in `docker-publish.yml` in a job that sets up no Haskell toolchain, and `test_version_gate_ll.py` asserting the shell invocation string appears in that workflow. THIS ONE IS AT `oracle` BY CHOICE AND NOT BY OBSTACLE: its cover has the campaign's highest defect yield, cell 6 having hidden behind two implementations that failed with the same exit code and two different causes, which is the argument campaign section 4 makes for a port staying longer. Rev 6 follows. `LIST-RANGE-1` IS REFUTED AND NOT MERELY NARROWED, AND THE HALF THIS FILE KEPT OPEN WAS NEVER TRUE. Rev 6 withdrew the `awk` prediction and wrote that the row stays open on N DISTINCT elements from a count. `range` has been a builtin since v0.11, typed `int int -> list[int]`: `builtinEnv` carries it at line 133 of `compiler/src/LLMLL/TypeCheck.hs`, line 313 of `compiler/src/LLMLL/CodegenHs.hs` emits a real body, `LLMLL.md` documents it in the builtin table with a worked example covering the empty and the inverted case, and FIFTEEN call sites across five committed `.llmll` files already use it, SEVEN of them passing a `range` straight into `list-map`, `list-filter` or `list-fold`, which is the shape the row called absent. One of the five files is this campaign's own port 003. PROBED 2026-08-16 against `llmll 0.16.0` on aarch64-osx, executed rather than read: `range 1 6` answers 1 through 5, so the interval is half-open; `range 1 61` answers 60 elements ending 58, 59, 60; `range 3 3` answers 0 elements; the inverted `range 9 4` answers 0 elements and does not crash; and `list-map (range 1 13) int-to-string` answers 12 DISTINCT strings. The witness the row was moved onto, `v-feed-text`, now reads `(range 1 61)`, and the row is CLOSED as REFUTED in `docs/compiler-team-roadmap.md`. A grep of `builtinEnv` before filing would have answered every part of it, which is the rule `llmll-tooling-campaign.md` section 5 prints a few paragraphs from where it discusses this very row. THAT ROW ALSO REDDENED THE STANDARD GATE AND NOBODY RAN IT: its disposition cell held COSMETIC and SHAPES at once, where `scripts/tests/test_tool_rfc_standard.py` requires exactly one of the three. Measured red on 2026-08-16 before this correction and green after it. ONE NEW GAP ROW IS RAISED AND FILED, `BYTES-WRITE-1`, dispositioned SHAPES, 2026-08-16, by the port's own stage 5b. Nothing in the language writes bytes that are not text: `wasi.fs.write` takes a string and encodes UTF-8, and the stage's `bin.dat` fixture carries a lone 0xFF that no `.llmll` literal can hold. The port spawns `/usr/bin/printf` with octal escapes, and the file that lands is `62 69 6e 61 72 79 20 ff fe 00 20 72 61 77 0a`, matching `scripts/build_smoke.sh` byte for byte. It is the OPPOSITE DIRECTION of `BYTES-READ-1` in one namespace, so it is a separate row on the `ENV-READ-1` versus `PROC-ENV-1` precedent. How it was found is the finding: the port's code NAMED the tag while the roadmap held no row for it, which is `LIST-KIND-1` recurring with its halves swapped, the gap there having had no tag where here the tag had no row. THE SPAWN CENSUS IS RE-MEASURED IN THE WORKING TREE ON 2026-08-16, AFTER STAGE 5b LANDED: 60 `wasi.proc.run` call sites, 24 naming a constant executable and 36 computing one, against the 55, 20 and 35 measured at `cdd6438`, and class (b) is FOUR sites rather than one, being `od`, `/usr/bin/env`, `/usr/bin/uname` and `/usr/bin/printf`. THAT LANDING ALSO DATES THE SENTENCE THAT FOLLOWS: stage 5b is in the working tree and uncommitted as of 2026-08-16, and nothing here re-runs the port, so section 2 keeps its `9806b78` stamp rather than gaining a count it did not earn. PORT NEARLY COMPLETE, AND THE LAST STAGE IS UNWRITTEN RATHER THAN BLOCKED. `tool_state` STAYS `blocked`, because the port still runs in no CI job and `oracle` asserts that both implementations decide over the same tree in one job. THE Rev 5 CLAIM THAT 5b FS-ENCODING-1 IS BLOCKED ON `PROC-ENV-1` IS REFUTED BY MEASUREMENT, taken 2026-08-16 against `llmll 0.16.0` on aarch64-osx: `wasi.proc.run` on `/usr/bin/env`, with `LC_ALL=C` first in the argv vector, SETS the child's environment, and a stdin path passed to that same call reaches the child through the exec. Five cells. `env` with no assignment answers `code:0` and the inherited environment holds no LC_ALL, 4719 bytes. `env LC_ALL=C env` answers `code:0` and the child's environment holds LC_ALL=C, 4728 bytes, a delta of exactly 9. `env LC_ALL=C LANG=C /bin/echo child-ran` answers `text:child-ran`, so two assignments and an argument-bearing child both work. `env LC_ALL=C /bin/cat` fed from a stdin path returned both fed lines, so THE STDIN PATH SURVIVES THE EXEC. `env /bin/echo no-assignment` works, so one helper also covers a site that sets nothing. So `PROC-ENV-1` NARROWS rather than closes, and what stays open is the cost: setting one variable costs one extra process and one executable outside the language. D6 IS TAKEN, by user adjudication 2026-08-16, and it FILES A NEW ROW. `env` does not supply stage 5b's `FSENC_LOCALE_HONOURED` flag, because GHC on macOS resolves UTF-8 whatever `LC_ALL` says, so the encoding claim is untestable there whoever sets the variable. Two compositions were checked BEFORE filing and both fail: `wasi.env.get` reads any variable and no EXPORTED variable names the platform portably; and `stack path --local-install-root` answers a string the port already holds, but a test on it must default to NOT EXERCISED for the safe direction, which INVERTS the subject's polarity and diverges on any third platform. So the port spawns `/usr/bin/uname` with `-s`, one new spawn site, and files `PLATFORM-1`, dispositioned SHAPES, 2026-08-16. SECTION 4'S ARGV-SPLIT ARGUMENT DOES NOT HOLD FOR THIS PORT, measured at `cdd6438`: `tools/build-smoke/buildsmoke.llmll` holds 55 `wasi.proc.run` call sites, of which 20 name a constant executable and 35 compute one from state, so 64 percent of the sites already run an executable no reader can enumerate from the module header. D1's outcome does not change, because D1 is superseded, but a later reader citing §4 would be citing a property this port does not meet. What `env` DOES preserve, and what `sh -c` would have lost, is that no metacharacter is interpreted: a path holding a space or a semicolon stays one argv member. `tools/build-smoke/buildsmoke.llmll` EXISTS and `adjudicate.llmll` is being written now, so §7's 'neither exists yet' is false and the reason it gave for `blocked` was never the operative one. FIVE STALE COUNTS ARE REPOINTED to the seventeen-row census, in §3, in §4 twice, in §5's `MODE-CLI-1` row and in D4; D1's option list KEEPS its fourteen, because a past-tense record of a superseded decision gets an exemption rather than a repoint. Rev 5 follows. SIXTEEN OF SEVENTEEN STAGE ROWS ARE PORTED at `9806b78`, and the seventeenth row did not exist until this revision: the section 2 table OMITTED the PROC-STDIN-1 stage, so every count in this file was taken over a census that was missing a member. The counts are now seventeen rows and 539 stage code lines. Only 5b FS-ENCODING-1 remains, and Rev 5 called it BLOCKED on `PROC-ENV-1` rather than unwritten, which the probe above refutes. `tool_state` STAYS `blocked` AND THE REASON IS NEW: `oracle` asserts that both implementations decide over the same tree in one job, and this port is in NO job, which was checked against `.github/` and `scripts/` on 2026-08-15. THE TRI-STATE VOCABULARY GAP IS NOW A FILED ROW rather than a paragraph, in `llmll-tooling-campaign.md` section 5. Rev 2 and Rev 4 each spent prose arguing that `blocked` has no value for 'started and incomplete'; a third argument would be a record that describes a problem three times and fixes it never. THE LIST-RANGE-1 PREDICTION IS WITHDRAWN: the PROC-STDIN-1 stage spawns no `awk`, because a repeated string composes from `string-concat` doubling and the fixture never reads its own input. The row stays open on N distinct elements from a count. THE PORT PRINTED FAIL AND EXITED 0 until `9806b78`, across all of its stages and since it was written, because it declared no `:status`. Rev 4 follows.  The RFC was written before any port code, which is the campaign's order. State stays `blocked`, and that is now an APPROXIMATION rather than a fact: the tri-state is blocked, oracle, retired, and it has NO VALUE FOR 'started and incomplete'. `tools/build-smoke/buildsmoke.llmll` exists and holds the spine plus stage 1 of fourteen, so the earlier gloss 'blocked means the port module does not exist yet' is false as of 2026-08-12. (Rev 5 note: 'stage 1 of fourteen' was true on 2026-08-12 and both of its numbers are now wrong; the port holds sixteen of seventeen.) `blocked` is the only state the RFC standard gate accepts here, because `oracle` asserts both implementations decide over the same tree in one job and this port decides nothing yet. THE VOCABULARY GAP IS FILED IN THIS LINE RATHER THAN LEFT FOR A READER TO INFER. NO DECISION IS OPEN, and §9's opening line said otherwise until 2026-08-12: it still read 'one decision is open and it blocks the port', which was true at Rev 1 and false from the moment `PROC-STDIN-1` shipped. The frontmatter was corrected at Rev 2 and the section body was not, which is the campaign's own stale-record class. D3 IS NOW DISCHARGED: the two capability rows this RFC deliberately refused to assume were PROBED on 2026-08-12 against `llmll 0.14.99`, by one program that exercised both and printed what the runtime answers. `wasi.fs.sha256` gives `RText` lowercase hex matching `shasum -a 256` byte for byte, so it is a real SHA-256 and not the polynomial stub `LLMLL.md` §13 records for the sibling SHA-1, and the byte-compare row stays COSMETIC. A failed exec answers `RErr`, the step machine SURVIVES it, and the message separates *missing* from *present but not executable*, so at this call site `LIST-KIND-1` is a GAIN over the subject's one-bit `-perm -111` test rather than a loss; the row does not close, because nothing answers 'is this executable' without attempting the run. THE TWO GAPS THIS RFC RAISED AGAINST THE COMPILER ARE SHIPPED, at v0.14.98 on 2026-08-12, BEFORE the port was written, and that reorders the campaign: normally a port works around a gap and files it. `PROC-STDIN-1` gave `wasi.proc.run` a seventh parameter, a stdin path. `PROC-STDIN-SHARE-1` was a COMPILER DEFECT: `std_in` was unset, so `createProcess` inherited and a child could read a TORN fragment of the parent's own step input above the 8 KiB handle buffer, with three runs taking three different victims. It was latent in all five shipped ports, because `git ls-files` and `llmll version` do not read stdin. `PROC-ENV-1` stays open and no port needs it yet. THE PORT THEREFORE PASSES A PATH AND WRITES NO SHELL STRING. D1 is SUPERSEDED: it had bounded the `sh -c` cost to one `drive` helper, and no `drive` helper will be written. Section 4 and D1 are KEPT rather than deleted, because the census counts the gap the port surfaced, not the workaround it avoided; a reader who wants the current mechanism reads `LLMLL.md` section 13. The port is FEASIBLE: one complete stage was written in LLMLL, built, and run against a good fixture and a broken one, and it discriminates. A negative control caught that stage reporting PASS against a build that exited 1, by reading a stale artifact. THE SIZE PROJECTION THIS RFC INHERITED WAS WRONG BY 1.8 TIMES: 4.8 is the FIRST port's ratio, the five ratios decline to 2.23, and the measured one-stage ratio is 2.6, so the port projects to about 1,400 code lines and not 2,500."
date: 2026-08-11
author: experiment-lead
tool_state: oracle
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
| - | PROC-STDIN-1 | 35 | a child reads the stdin path its parent named, and a `/dev/null` child reads nothing while the parent holds 147456 bytes |
| 6 | REPLAY-FRAME | 59 | recorded runs replay clean, and tampered logs are refuted |
| 7 | PROC-BOUNDARY-1 | 59 | argv arrives on `RList`, `:done?` exits 42, a starved program exits 70 |
| 8 | DRIVER-LL 4a-4c | 24 | the sequencer cover, 11 transition cells and 3 manifest shapes |
| 9 | DRIVER-LL 4e | 26 | the wave cover, 7 cells |
| 10 | DRIFT-CI-1 | 34 | `versiongate.llmll` decides the version gate, 14 cover cells |

**Three stages have no number in the subject.** JSON-SCALAR-1 at line 561,
PROC-MERGE-1 at line 619 and PROC-STDIN-1 at line 686 sit under a bare rule of
dashes. The port gives each a name, because a stage with no name cannot be
cited in a failure report. **PROC-STDIN-1 was missing from this table until
2026-08-15**, which is the same defect one level up: a stage absent from the
census cannot be counted, and its absence is why the counts below were wrong.

**Seventeen rows, 539 code lines, and ALL SEVENTEEN ARE PORTED as of
2026-08-16.** 5b FS-ENCODING-1 was the last, and it was written once the
`PROC-ENV-1` block below was refuted by measurement.

**The port was RUN END TO END rather than only compiled**, on aarch64-osx
against `llmll 0.16.0`, using the invocation the CI step carries. It exited 0
and printed FIFTEEN verdict lines: fourteen PASS and one NOT EXERCISED, that
last being the LC_ALL half of 5b which Darwin cannot settle. **The reference has
fifteen verdict-emitting sites, so the two counts agree.** Stage 5b was also run
with three separate negative cells, each naming a different assertion and each
exiting 1, so the stage's five assertion flags are independent rather than one
flag wearing five names.

**Rev 5 said the stage was BLOCKED on `PROC-ENV-1`, and that is REFUTED BY
MEASUREMENT**, taken 2026-08-16 against `llmll 0.16.0` on aarch64-osx.
`wasi.proc.run` on `/usr/bin/env`, with the assignment first in the argv vector
and the real executable after it, sets the child's environment. Five cells:

| Cell | Probe | Answer |
|---|---|---|
| A | `env` with no assignment | `code:0`, and the inherited environment holds no LC_ALL. 4719 bytes |
| B | `env LC_ALL=C env` | `code:0`, and the child's environment holds LC_ALL=C. 4728 bytes, a delta of exactly 9 |
| C | `env LC_ALL=C LANG=C /bin/echo child-ran` | `text:child-ran`. Two assignments and an argument-bearing child both work |
| D | `env LC_ALL=C /bin/cat`, fed from the stdin path `feed.txt` | both fed lines came back. **The stdin path survives the exec**, so setting a variable does not cost the port its stdin channel |
| E | `env /bin/echo no-assignment` | it works, so ONE helper covers a site that sets nothing as well as a site that sets one |

**The block was a claim about a mechanism nobody had run.** The stage needs
`LC_ALL=C` for one child, and the port can set it today. What the gap still
costs is in §5's `PROC-ENV-1` row, and what the stage still lacks is the
platform test D6 takes.

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

**The cost that does apply is time.** The port compiles seventeen fixtures with
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
stage is 4b, REGEX-LOWER-1, the smallest of the seventeen. It creates a
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
| Set `LC_ALL=C` for a child | **gap**, and NARROWED 2026-08-16 | `wasi.proc.run` takes seven parameters, since `PROC-STDIN-1` added the stdin path, and none is an environment. **Measured**: the child INHERITS the parent's environment, so `LC_ALL=C` set outside the port reaches the child. **This row read "the port cannot set it" until 2026-08-16, and that is refuted**: the port sets it by spawning `/usr/bin/env`, at the cost of one extra process. See §2 for the five cells. One site, at line 443 |
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

Seven of the seventeen stages contain such a site:

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
the executable from its argument vector on purpose.
[`TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) lines 199-200 state the
reason: the executable becomes a syntactic constant that a reader can enumerate
from the module header, and shell metacharacter interpretation stops being a
category. **Routing thirteen sites through `sh -c` puts the whole command back
into one shell string.** The property the split exists to give is lost at
exactly the sites that matter most, which are the sites that run the other
ports.

D1 puts that cost to the user.

**THIS PORT DOES NOT HOLD THE PROPERTY THAT ARGUMENT RESTS ON, measured at
`cdd6438`.** [`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll)
holds 55 `wasi.proc.run` call sites. Twenty name a constant executable and
thirty-five compute one from state, `(get-s b "subject")` among them, so **64
percent of the sites already run an executable that no reader enumerates from
the module header.** The port acquired that shape by porting a subject whose
compiler path is chosen at run time, not by reaching for a shell.

**This does not change D1's outcome**, because D1 is superseded and no shell
string is written. It changes what §4 may be CITED for: a later reader quoting
this section for the auditability property would be quoting a property this port
meets at one site in three. The argument stands as a statement about
`wasi.proc.run`, and it does not stand as a statement about `buildsmoke.llmll`.

**What the split still gives this port, and what `sh -c` would still have taken,
is a different property and it survives a computed executable.** No
metacharacter is interpreted, so a path holding a space or a semicolon stays one
argv member. That is what the `/usr/bin/env` spawn in §5's `PROC-ENV-1` row
preserves: `env` prepends an assignment to an argv vector and reads none of it
as syntax.

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| `wasi.proc.run` cannot supply a child's stdin, and driving a console-mode LLMLL program is feeding it stdin | **SHAPES** | `PROC-STDIN-1`, filed 2026-08-11, shipped v0.14.98 | A seventh parameter, a stdin path, symmetric with the stdout and stderr paths the builtin already takes. Instead thirteen sites route through `/bin/sh -c` and rebuild the shell string that the argv split removes. **Measured**: `sh -c` does deliver the input, and a real console binary driven that way completes its loop, so this SHAPES the port rather than blocking it. The gap reaches 295 of 504 stage code lines |
| A child spawned by `wasi.proc.run` SHARES the parent's stdin, and above the 8 KiB buffer it reads a torn fragment of the parent's own input | **SHAPES** | `PROC-STDIN-SHARE-1`, filed 2026-08-11, shipped v0.14.98 | `std_in` bound to an empty handle, or to the stdin path `PROC-STDIN-1` asks for. Instead the port must keep its own stdin under 8 KiB, which is a constraint nothing states or checks. **Measured**, and the numbers are in F2 below. This is a compiler defect as well as a gap, and it is routed to the compiler-engineer |
| No environment channel on `wasi.proc.run`: the builtin takes no environment, and `wasi.env.get` reads one variable while nothing sets one | **SHAPES**, and the row NARROWS rather than closes | `PROC-ENV-1`, filed 2026-08-11, **narrowed 2026-08-16**, open | `LC_ALL=C cmd`, as the subject writes it at line 443. Instead the port spawns `/usr/bin/env` with the assignment first in the argv vector and the real executable after it. **This column said the site goes through `sh -c`, which sets the variable in the shell string, and that was wrong twice**: D1 is superseded so no `sh -c` is written, and `env` sets the variable with no shell string at all. **Measured 2026-08-16 against `llmll 0.16.0` on aarch64-osx**, five cells in §2: the child's environment holds `LC_ALL=C`, a stdin path passed to the same call still reaches the child, two assignments work, an argument-bearing child works, and a site that sets nothing runs through the same helper. **What stays open is the price**: setting one variable costs one extra process and one executable outside the language, at every site that needs one, and the language still has no way to say it. **Measured earlier**: a child INHERITS the parent's environment, so the campaign's older "no env access" row is about READING and this is about SETTING. The two are not the same row, and folding them is the mistake that made `FS-STAT-1` and `FS-EXISTS-1` need splitting |
| Nothing names the host platform, so a stage cannot decide whether the claim it is about to make is exercisable here | **SHAPES** | `PLATFORM-1`, filed 2026-08-16, raised by TOOL-RFC-006 | A platform or host name available in the language, on the `wasi.env.get` precedent of one name answering one question. Instead the port spawns `/usr/bin/uname` with `["-s"]` and tests the answer for `Darwin`, which is what [`build_smoke.sh`](../../scripts/build_smoke.sh) line 445 does, so the two agree by construction on every platform. **The campaign's rule is to check whether an operation COMPOSES from existing builtins before filing an absence, so two compositions were checked and BOTH FAIL.** `wasi.env.get` ships and reads any variable, and no EXPORTED variable names the platform portably. `stack path --local-install-root` answers `aarch64-osx` or `x86_64-linux`, a string the port already holds for free, but a test on that string must default to NOT EXERCISED for the safe direction, which INVERTS the subject's polarity and creates a divergence on any third platform. So the platform does not compose and it owes a row. D6 records the adjudication and the option that was refused. A sibling filing carries the same tag in [`compiler-team-roadmap.md`](../compiler-team-roadmap.md) |
| A program cannot READ its own environment, so the subject's `$HOME/.local/bin/llmll` branch is unreachable | **SHAPES**, now closed | `ENV-READ-1`, filed 2026-08-12, **shipped v0.15.0** | An env read, `wasi.env.get` answering a `Result` so unset and empty differ. **The shipped name answers on the response channel instead, `RText` for set and `RErr` for unset, which keeps the property the row wanted.** The dropped branch is now ported: [`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll) imports `wasi.env` and calls `(wasi.env.get "HOME")` in its `Home2` phase, so the port reproduces all three of the subject's compiler sources. **The record of what it cost while the gap was open is kept, because that is what the census counts.** Before v0.15.0 the port took `--subject` and dropped the branch, which is a BEHAVIOUR difference rather than an invocation one. **Found by building stage 2**, not by reading: the campaign census carried this COSMETIC on the rationale "argv carries it", tested at 005 where it held. Argv carries what a caller passes, and `$HOME` is not passed. `sh -c 'echo $HOME'` works and is refused under D1 |
| `:mode cli` performs no `Command` and yields no exit status | **SHAPES** | `MODE-CLI-1` | A straight-line program: build, run, assert, exit. Instead the port is a stdin-driven step machine with an explicit control state. This is the campaign's largest line-count multiplier and it applies here seventeen times over, once per stage |
| A listing carries no entry kind, so nothing answers "is this file executable" | **SHAPES** | `LIST-KIND-1` | The subject's `-perm -111` test inside `exe_path`. Instead the port asks `stack path` for the directory and attempts the run, letting a failed exec answer. **PROBED 2026-08-12 and the design holds**: a failed exec answers `RErr`, the step machine survives it, and the message separates *missing* from *not executable*, which the subject's one-bit `-perm -111` test cannot. See D3 |
| No recursive directory walk | **COSMETIC** | `FS-WALK-1` | Nothing follows. The twelve walk sites were deleted from the subject on 2026-08-11 and replaced by `stack path --local-install-root`. The row closed on 2026-08-10 and this port confirms the close |
| Nothing removes a DIRECTORY, so stage 5 cannot clear the state it is about to measure | **BLOCKS**, now closed | `FS-RMDIR-1`, filed 2026-08-12, **shipped v0.16.0** | The subject's `rm -rf "$EXEC_SCRATCH"` before the fixture runs. Without it a directory left by an earlier run satisfies the `mkdir` assertion whatever this run's `mkdir` did, so the port measured whether it pre-existed and printed `NOT GRADED: wasi.fs.mkdir`. **`wasi.fs.rmdir` now ships and the port clears the directory**: three idempotent `wasi.fs.delete` calls, then one `rmdir`. It is **empty-only**, so recursion is not available and is not wanted here; the fixture writes three flat files and no subdirectory, measured. **The NOT-GRADED path stays and its trigger changed** to "the clear did not succeed", which fires when an unexpected fourth entry leaves the directory non-empty. Both cells were run and differ only by that entry. **The row also found a live compiler defect**: `wasi.fs.delete` published `RNone` for a directory and removed nothing, fixed in the same release |
| Nothing gets a file's BYTES into the language, so the port spawns `od` to hex-dump a program's stdout | **SHAPES** | `BYTES-READ-1`, filed 2026-08-15 | A byte-level read, or a hex-text read on the `wasi.fs.sha256` precedent. Instead stage 5c runs `od -An -tx1` through `wasi.proc.run` and strips the whitespace in-language. **`wasi.fs.read` answers `RText` decoded as UTF-8**, so a file that is not valid UTF-8 cannot be read at all and a valid one cannot be inspected byte-wise. Caught by the amended discipline in the campaign's §gap discipline, not by the zero-FFI bar, which this port meets |
| Nothing writes bytes that are not text, so a fixture carrying a lone `0xFF` cannot be authored in the language | **SHAPES** | `BYTES-WRITE-1`, raised and filed 2026-08-16 | A byte-level write, or an escape-expanding one, whichever mirror `BYTES-READ-1` settles on. `wasi.fs.write` takes a string and encodes it as UTF-8, so no route runs from a `.llmll` literal to a byte outside that encoding. Stage 5b must CREATE the fixture input `bin.dat`, which carries a lone `0xFF`, so the port spawns `/usr/bin/printf` with octal escapes and lets the redirect be the write. **MEASURED 2026-08-16**: the file that lands is `62 69 6e 61 72 79 20 ff fe 00 20 72 61 77 0a`, which is [`build_smoke.sh`](../../scripts/build_smoke.sh)'s own `printf` output byte for byte. **This is the OPPOSITE DIRECTION of `BYTES-READ-1` and is deliberately NOT folded into it**, on the `ENV-READ-1` versus `PROC-ENV-1` precedent: one namespace, two directions, and one row cannot carry both. **How it was found is the finding.** The port's code NAMED the tag while the roadmap held no row for it, which is `LIST-KIND-1` recurring with its halves swapped: there a recorded gap had no tag, so a search for tags could not see it, and here the tag existed with nothing in the roadmap for a search of the roadmap to find. The row was filed the same day, so the window was hours rather than the release `LIST-KIND-1` sat through, and the mechanism is the same either way. Raised by the whole-port spawn census in [`llmll-tooling-campaign.md`](llmll-tooling-campaign.md) §5, which counts it as the fourth class (b) site |
| Nothing constructs a list from a count, so N DISTINCT elements cannot be built from the number N. **THE ABSENCE THIS ROW NAMED DOES NOT EXIST, AND HAS NOT SINCE v0.11** | **COSMETIC**, and the row is REFUTED rather than narrowed | `LIST-RANGE-1`, filed 2026-08-15, **REFUTED 2026-08-16** | `range : int int -> list[int]`, which already ships and needed no design. **THIS ROW WAS WRONG IN BOTH HALVES, AND THE SECOND HALF WAS WRONG ON THE DAY IT WAS FILED.** Rev 6 recorded the first correction and it stands: the row predicted that the PROC-STDIN-1 stage would generate its fixture with one `awk BEGIN` program through `wasi.proc.run`, marked itself "Predicted rather than measured", and the ported stage spawns no `awk`, because the subject's `printf 'LINE%s\n' $(seq 12000)` is 108894 bytes and the port doubles a 9-byte literal fourteen times to 147456. Rev 6 then kept the row open on N distinct elements from a count. **That half is refuted too, and by reading rather than by a design round.** `builtinEnv` carries `range` at [`TypeCheck.hs:133`](../../compiler/src/LLMLL/TypeCheck.hs) typed `TFn [TInt, TInt] (TList TInt)`, [`CodegenHs.hs:313`](../../compiler/src/LLMLL/CodegenHs.hs) emits `range from to = [from .. to - 1]` under a `LT-INT (v0.11)` marker, and [`LLMLL.md`](../../LLMLL.md) documents it in the builtin table with a worked example covering the empty and the inverted case. **Fifteen call sites across five committed `.llmll` files already use it**, and seven of the fifteen pass a `range` straight into `list-map`, `list-filter` or `list-fold`, which is exactly the shape the row called absent; one of the five files is this campaign's own port 003, [`docclaims.llmll`](../../tools/doc-claims/docclaims.llmll). **PROBED 2026-08-16 against `llmll 0.16.0` on aarch64-osx, executed rather than read**: `range 1 6` answers 1 through 5, so the interval is half-open; `range 1 61` answers 60 elements ending 58, 59, 60; `range 3 3` answers 0 elements; the inverted `range 9 4` answers 0 elements and does not crash; and `list-map (range 1 13) int-to-string` answers 12 distinct strings. **The witness Rev 6 moved the row onto was removed rather than defended**: `v-feed-text` in [`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll) built 60 stdin lines from a LITERAL 60-element int list, and it now reads `(list-map (range 1 61) ...)`, measured in the working tree on 2026-08-16. [`proc_stdin.llmll`](../../scripts/build-smoke/proc_stdin.llmll) never inspects its own step input, which is why only the byte count was ever owed at the other site. **A grep of `builtinEnv` before filing would have answered all of it.** The row failed the composition rule that [`llmll-tooling-campaign.md`](llmll-tooling-campaign.md) §5 prints a few paragraphs from where it discusses this row, and failed it inside the section that states it. Closed as REFUTED in [`compiler-team-roadmap.md`](../compiler-team-roadmap.md); the narrowing mirrored there at `af102d7` is superseded |
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
| 1 | control: an unmutated tree | both implementations PASS every stage, **including the `LC_ALL=C` encoding claim on BOTH platforms as of 2026-08-16, where this cell carried a Linux exception until then; see the note below the table** |
| 2 | control: a fixture that does not compile | both FAIL stage 3, and name the fixture |
| 3 | control: a stale artifact present under a failing build | both FAIL. **This cell exists because the stage probe passed it wrongly**; see §4 |
| 4 | delete a definition the corroboration stage names | both FAIL stage 4 |
| 5 | remove the `regex_match` prefix from the generated `Lib.hs` | both FAIL stage 4b |
| 6 | make `llmll build` succeed while the binary is absent | both FAIL, and neither reports PASS from a stale binary |
| 7 | a build that exceeds the timeout | the port answers `RErr` and FAILS. The reference has no timeout, so this cell grades the PORT only, and it is labelled as such |
| 8 | grep the port for `/bin/sh` call sites, and for `/usr/bin/env` call sites outside `bs-env` | zero `/bin/sh` sites AT ALL, and every `/usr/bin/env` site inside the single `bs-env` helper |

**Cell 8's target CHANGED on 2026-08-16, and the old target can no longer be
met by accident.** It read "a `/bin/sh` call site outside `drive`", which bounds
shell strings to one helper. **No `drive` helper will ever be written**, because
D1 is superseded, so a cell phrased around it grades nothing and passes forever.
The new target asserts two things: that the port hands NO string to a shell, and
that the one spawn which sets an environment variable comes from one place a
reader can audit at once, which is the bound D1 wanted applied to the mechanism
the port actually uses. Measured at `cdd6438`, the port holds zero of each and
`bs-env` is not yet written, so this cell first grades something when stage 5b
lands.

**The `LC_ALL=C` encoding claim WAS REFERENCE-ONLY on Linux, and cell 1 was
labelled for it on cell 7's precedent. THE LABEL COMES OFF, and the trigger this
paragraph named was the wrong one.** `scripts/build_smoke.sh` sets `LC_ALL=C`
for one child in the FS-ENCODING-1 stage. Rev 5 wrote "the label comes off when
`PROC-ENV-1` ships". The row is still open and the label comes off anyway,
because the trigger is whether the PORT can set the variable, and it can: it
spawns `/usr/bin/env`, measured 2026-08-16 and recorded with its five cells in
§2. **A trigger written as "when the gap closes" was a guess about the only
possible repair, and the repair came from somewhere else.**

**So the port and the reference now agree on BOTH arms.** On Darwin both print
`BUILD-GATE-1 NOT EXERCISED: the LC_ALL=C encoding claim (FS-ENCODING-1)`,
because GHC there resolves UTF-8 whatever `LC_ALL` says and no implementation
can test the claim. On Linux both settle the claim, because the port sets the
variable the same way the reference does. Cell 1's "both PASS every stage"
therefore holds on both platforms, and the divergence this paragraph existed to
label is gone. **What replaced it is a smaller problem and it is D6's**: agreeing
on both arms requires knowing which arm you are on, and nothing in the language
names the platform. Cell 7's asymmetry stands and is untouched: there the port
can do something the shell cannot. **A cover that hid either would claim an
agreement it did not measure.**

**`/usr/bin/env` was measured on Darwin ONLY, on aarch64-osx, and this campaign
treats a one-platform measurement as a measurement of that platform.** The path
is POSIX and the mechanism is not platform-specific, which is a reason to expect
the Linux arm to hold and not evidence that it does. **So a cover cell settles
the Linux arm on the first CI run and nothing settles it before then.** If
`/usr/bin/env` is missing or behaves differently there, stage 5b fails on that
run and the cover reports it as a port defect, which is the correct reading:
the port made a claim about a platform it had not run on.

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

Both files sit under `tools/build-smoke/`. **BOTH NOW EXIST.**
`buildsmoke.llmll` held sixteen of seventeen stages and 55 `wasi.proc.run` call
sites at `cdd6438`, and holds all seventeen stages and 60 call sites in the
working tree on 2026-08-16 once stage 5b landed. **`adjudicate.llmll` verifies
SAFE and its two contracts are PROVED rather than fallen back**: `llmll verify`
names `fsenc-verdict` and `status-of` on the `body-faithful` line. Three
refutation controls were run against copies, and each bit a DIFFERENT
constraint, so neither post is vacuous: a body returning 2 unconditionally, a
body returning 2 when the platform cannot test the claim, and a constant
`status-of`. **Both figures are stamped on purpose.**
§4's fifty-five and this line's sixty are the same measurement over two trees,
and a count with no commit beside it reads as a standing fact when it is not. **"Neither exists yet" was this
section's stated reason for `tool_state: blocked`, and it stopped being true on
2026-08-12 without this line moving.** The operative reason was §3's: the port
ran in no job, and `oracle` asserts that both implementations decide over the
same tree in one job.

**AND THAT SECOND REASON HAS NOW EXPIRED TOO, WHICH MAKES THIS PARAGRAPH THE SAME
DEFECT TWICE.** The port runs in three `spec-roundtrip` steps, `tool_state` is
`oracle` since `073ae4b`, and this paragraph went on naming a reason for `blocked`
for a day after that. It is kept rather than deleted because a paragraph that
recorded one expired reason and then acquired another is the better warning; see
the Rev 7 note in the frontmatter for the state, which is the only place in this
file that a reader should trust for it.

`adjudicate.llmll` is still written without a directory on
purpose. A full path would make the prose citation lint report a file the port
has not written.

**The ordering is a constraint and not a preference.** Port 005 measured this
with no sidecar present. `llmll check` on the port warns that the core has an
unproven contract. The warning disappears once the core is verified. The sidecar
is gitignored. So the trust comes from running verify in the job.

**What no instrument here reaches.** The port asserts that seventeen stages
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

**THE THIRD ITEM IS WITHDRAWN AND THE LIST IS NOT REWRITTEN.** Campaign §4 was
amended on 2026-08-17 and the amendment withdraws elapsed time as a retirement
condition in every RFC at once: a port leaves `oracle` when three stated
conditions hold, and a release count is not one of them. The four retirements
that have happened all read §4 rather than their own §8 list, and the four RFC
§8 sections still carry the Rev 5 schedule. A reader who finds a calendar in this
list should apply §4's three conditions instead.

**One thing §4's list does not yet ask, added by the fourth retirement.** Ask
condition 2 of the pytest suite and not only of the gate step. TOOL-RFC-002's
reference had its gate step in `spec-roundtrip` and its pytest in the
toolchain-free job, so it satisfied condition 2 by inspection and failed it in
fact. This subject is the harness that runs the other five ports, so the same
question is worth asking here before anything is deleted.

The script is named by its RFC and not by its path on purpose. It is deleted, so
a path here would be one more entry in the lint's ALLOW table, and this sentence
adding one would be the FIFTH time in a row that prose about a retirement cited
the file the retirement removed.

**A condition this port adds, which no previous port needed.** The subject is
the harness that builds and runs the other five ports. **Deleting it deletes the
only thing that runs them.** So retirement here is not the removal of a
duplicate; it is a handover of the job that tests the whole campaign. The port
must run all seventeen stages, or the stages it drops must be reassigned to a
named owner in the same commit.

**The 005 precedent applies and it is a warning.** The user deleted
`test_doc_path_lint.py` on 2026-08-11 and accepted the loss.
Nothing now blocks a broken prose citation from reaching `main`, because both
remaining checks exit 0 when they find one. That was a decision and RFC-005 §8
holds the reason. **The lesson this port takes from it**: name what the deletion
removes before the deletion, not after CI reddens.

## 9. Decisions taken

**NO DECISION IS OPEN. All SIX are taken, and D1 was taken twice.** This
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
fixture is 18.13 seconds. Seventeen fixtures run twice is the cost of state
`oracle`, and that state lasts one release. If the job exceeds its limit, the
port drops to a nightly step and this RFC gains a revision saying so.

**D5. The subject's two stages labelled `5b`. TAKEN: the port gives every stage
a distinct name.** The subject also leaves two stages with no number at all, at
line 561 and line 619. A stage with no unique name cannot be cited in a failure
report, and the cover in §6 needs one cell per stage.

**D6. How stage 5b learns which platform it is on. TAKEN by user adjudication
2026-08-16: spawn `/usr/bin/uname` with `["-s"]`.** The stage prints the
subject's `FSENC_LOCALE_HONOURED` verdict, and setting `LC_ALL=C` does not
supply it. GHC on macOS resolves UTF-8 whatever `LC_ALL` says, so the encoding
claim is untestable there whoever sets the variable, and the subject answers
this by asking `uname -s` at [`build_smoke.sh`](../../scripts/build_smoke.sh)
line 445. **So `PROC-ENV-1`'s repair does not finish the stage**, which is the
part of this that was easy to miss: the variable and the platform are two
requirements and only one of them was in the census.

**The negative test ran BEFORE the row was filed, which is the campaign's rule,
and two compositions were checked. Both fail:**

| Composition | Why it fails |
|---|---|
| `wasi.env.get` | It ships and reads any variable. **No EXPORTED variable names the platform portably**, so there is nothing to read |
| `stack path --local-install-root` | It answers `aarch64-osx` or `x86_64-linux`, a string the port already holds and pays nothing for. **A test on it must default to NOT EXERCISED for the safe direction**, because an unrecognised string must not be read as "the claim is testable here". That INVERTS the subject's polarity, which defaults to exercised, and the two diverge on any third platform |

So the platform does not compose from what exists, and it owes a row. Two
answers were put to the user:

1. **Spawn `/usr/bin/uname` with `["-s"]`.** One new spawn site. It agrees with
   the subject on every platform, because it asks the same program the same
   question. It files a new row, `PLATFORM-1`, dispositioned SHAPES.
2. **Test the `stack path` string the port already holds.** No new spawn. It
   files nothing, and it carries a labelled divergence on any platform that is
   neither Darwin nor Linux.

**The user chose option 1 on 2026-08-16.** The campaign's deliverable is the gap
census, and option 2 buys one saved process at the price of an uncounted gap and
a divergence the cover would have to be told to ignore. **A port that avoids a
spawn by hiding a gap has spent the thing the campaign exists to produce.** The
spawn is classified under the campaign's spawned-utility amendment, in
[`llmll-tooling-campaign.md`](llmll-tooling-campaign.md) §5: `uname` does work
the LANGUAGE should do, so it owes a row, where `stack` and the compiler are the
subject of the test and owe none.

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
