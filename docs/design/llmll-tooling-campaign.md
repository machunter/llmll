---
name: llmll-tooling-campaign
title: "TOOL-LL: this repository's CI gates, written in LLMLL and actually used"
status: "Rev 6, IN FLIGHT. THE RETIREMENT CALENDAR IS WITHDRAWN IN §4, by user adjudication 2026-08-17, and REPLACEMENT REMAINS THE GOAL. What changed is that a port leaves `oracle` on three stated conditions rather than when a release ships, and that each retirement must NAME the loss it accepts. TOOL-RFC-004 IS RETIRED 2026-08-17, the campaign's SECOND retirement: `scripts/doc_archive_gate.sh` deleted, its cover retargeted from the reference onto the port, six citations measured before the deletion with two repointed and three carried in the lint's ALLOW table. Rev 5 said keep each original one release and then delete it. THREE MEASUREMENTS REFUTE IT. The first was WRITTEN DOWN WRONG AND IS CORRECTED HERE, and the corrected form is weaker: a retirement does NOT destroy a cover. Every cover runs its reference through `subprocess.run`, so the reference is an INPUT and not a duplicate. But every cover also declares its own per-cell expectation as data (`expect`, `expect_fail`, a must-be-caught assertion), so a mechanical rewrite retargets the battery onto the port and the battery survives. What does NOT survive any rewrite is the cross-implementation disagreement check, which needs two implementations and is the check that caught `TOOL-ENCODING-1`, a defect NEITHER side had. `scripts/version_gate.sh` runs in TWO jobs with no Haskell toolchain, one of them the `ghcr.io` publish job at `docker-publish.yml` line 820, so TOOL-RFC-001 cannot retire until someone adds a toolchain to the release path. And the one retirement on record is a LOSS: TOOL-RFC-005 retired with no replacement oracle and its own §8 says nothing now stops a broken prose citation from reaching `main`. `retired` is now reached by argument and never by a calendar, under three stated conditions. The tri-state vocabulary is unchanged, so §7's gate stays passing. THE SIX RFC §8 SECTIONS STILL DESCRIBE THE OLD SCHEDULE and are deliberately not edited; §4 governs. THE PORTING WORK IS COMPLETE, six of six, with 006 at `tool_state: oracle` since 2026-08-16. Rev 5 follows.  Rev 5, IN FLIGHT. Scope and retirement SETTLED by user adjudication 2026-08-07; DISTRIBUTION AMENDED 2026-08-10 in §3, at the second port to meet the same constraint, and it now distinguishes shipping a COMPILER from shipping a COMPILED PORT and requires a wholesale relocation rather than a split. Six CI gates in scope (~900 code lines). SIX are ported. THE PORTING WORK IS COMPLETE as of 2026-08-16. DRIFT-CI-1 (TOOL-RFC-001, retroactive), the refute-crux gate (TOOL-RFC-002, the first written RFC-first), doc-claims (TOOL-RFC-003, released v0.14.92) and doc-archive (TOOL-RFC-004, released v0.14.95) run as oracles. 005 (doc-path-lint) is PORTED and `tool_state: oracle` (TOOL-RFC-005), green on run 31439956284; it was unblocked at v0.14.96 by `REGEX-LOWER-1`, a compiler fix that took the critical path through compiler work for the first time and whose census corrected its own row; 006 (build-smoke) is PORTED and `tool_state: oracle` as of 2026-08-16, released in v0.16.0. It is the last of the six and it runs the other five. Its differential cover passes 9 of 9 cells with 0 MISSING on CI run 31985443527. What remains is one release in state `oracle`, and then retirement. 005's subject is ADVISORY and exits 0 by design, so its cover compares stdout text rather than exit codes, and it raised FOUR owed gaps, the largest number any port has produced; ALL FOUR ARE FILED as of 2026-08-10, together with a fifth, `LIST-KIND-1`, that 004 had raised on 2026-08-09 and that NO census held, this one included. `FS-WALK-1` CLOSED COSMETIC 2026-08-10 on the measurement its own row asked for and nobody had run: 006's walk sites are twelve, not the nine the row claimed, and all twelve are one query at a fixed depth of 4, so nothing is owed to the compiler and 006 needs no builtin. That is the SECOND wrong count on that one gap, the first having over-stated its blast radius three-fold; see §5. THE STANDARD HAS NINE SECTIONS, not eight: `## 7. Verification` was added at v0.14.94 and asks what survives the reference's deletion, since §8 deletes the instrument §6 is checked against. Each of the last three ports found something its own feasibility read had declared absent: 002 found three defects, 003's cover found a COMPILER defect (TOOL-ENCODING-1, shipped v0.14.93) that neither implementation had, and 004's cover found three defects that its live green run could not reach."
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
| `doc_claims_gate.sh` (DELETED 2026-08-17) | 97 | the port only, `spec-roundtrip` | **RETIRED**, `tool_state: retired`, TOOL-RFC-003. The campaign's THIRD retirement |
| `doc_archive_gate.sh` (DELETED 2026-08-17) | 125 | the port only, `spec-roundtrip` | **RETIRED**, `tool_state: retired`, TOOL-RFC-004. The campaign's SECOND retirement |
| `doc_path_lint.py` (DELETED v0.14.99) | 132 | the port only, `spec-roundtrip` | **RETIRED**, `tool_state: retired`, TOOL-RFC-005. **The campaign's first retirement** |
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

## 4. Retirement. AMENDED 2026-08-17. The CALENDAR is withdrawn, not the goal

**The tri-state vocabulary does not change.** A tool is in exactly one of
`blocked`, `oracle` and `retired`. The gate in §7 asserts the state against the
filesystem, so a document that claims `retired` while the script is present
fails.

| State | The original | CI runs | The port's oracle |
|---|---|---|---|
| `oracle` | present | both | the original, over a mutation battery |
| `retired` | deleted | the port | the port's own cover |
| `blocked` | present | the original | the port does not exist |

**WHAT IS WITHDRAWN IS THE TIMER, AND NOT THE GOAL.** Rev 5 said this: keep the
original for one release, then delete it. Replacement is still what this campaign
is for. But a port no longer leaves `oracle` when a release ships. A port leaves
when the three conditions below hold, and a commit states each one.

### Why the schedule was wrong. Measured 2026-08-17

Three measurements refute it. They appear in order of what they cost.

**1. A deletion costs the DISAGREEMENT CHECK, and it does not cost the cover.**
This measurement was first written down wrong, and the corrected form is the
weaker claim. Every cover holds its reference as a path constant and runs it with
`subprocess.run`. So the reference is an INPUT to the instrument and not a
duplicate of the port, which is what Rev 5 assumed.

But every cover ALSO declares its own per-cell expectation, as data in the cover
file. `doc_archive_cover.py` uses `expect`. `doc_claims_cover.py` uses
`expect_fail`. `version_gate_cover.py` asserts that a mutant must be caught.
`refute_crux_cover.py` compares a per-cell `expect`. **None of those values is
read off the reference.** So a cover survives a retirement by a mechanical
rewrite that retargets the expectation from the reference to the port. The
mutation battery does not die.

**What dies is the cross-implementation disagreement check, and no rewrite
recovers it.** That check needs two implementations. It is also the check with
the highest yield in this campaign. `doc_archive_cover.py` says so in its own
docstring: at `TOOL-ENCODING-1` every mutation cell AGREED while both sides
failed identically, and only two implementations plus controls could separate
"these agree" from "neither works". A second property dies with it. After a
retirement the port is graded against expectations that this campaign wrote,
where `doc_archive_cover.py` records that the expectation "is checked on the
REFERENCE, which defines the correct behaviour".

**2. Two jobs cannot run a port.** `scripts/version_gate.sh` runs in
`.github/workflows/version-gate.yml` at line 77, in a job with no Haskell
toolchain on purpose. It also runs in `.github/workflows/docker-publish.yml` at
line 820, in the job that pushes an image to `ghcr.io`. That file sets up no
Stack and no GHC. An LLMLL port needs a build. So TOOL-RFC-001 cannot retire
until someone adds a toolchain to the release path.

**3. The one retirement we have is recorded as a loss.** TOOL-RFC-005 retired on
2026-08-11 with NO replacement oracle. No `doc_path_lint_cover.py` exists. Its
own §8 says that nothing now stops a broken prose citation from reaching `main`,
because both remaining checks exit 0 when they find one. That is one loss in one
retirement.

### The three conditions for `retired`

A port leaves `oracle` only when all three conditions hold. State each condition
in the commit that flips the state.

1. The port's cover does not execute the reference. Either someone rewrote the
   cover to grade the port alone, or this campaign accepts the loss of the cover
   IN WRITING and names what stops deciding.
2. Every CI job that runs the reference can run the port. A job with no Haskell
   toolchain cannot run a port. Adding a toolchain to a fast job is a cost to
   state, and it is not a detail.
3. The deletion breaks no prose citation. Measure this the way the 005
   retirement taught. Move the file aside. Run the lint. Restore the file.

### Retirement proceeds. Each one accepts a NAMED loss

Replacement is still the goal. Rev 5 was approximately right about that, and it
was wrong only about the timing and about what a deletion costs.

**Every retirement gives up the cross-implementation disagreement check for that
gate.** State that loss in the commit. Do not describe a retirement as the
removal of a duplicate, because the measurement above shows it is not one.

**The loss is real and it is not a regression against the baseline.** That
distinction decides whether a retirement is defensible. Before this campaign,
`doc_claims_gate.sh` and `doc_archive_gate.sh` had NO pytest file and no cover,
so nothing tested them. After a retirement each port keeps a mutation battery of
12 to 19 cells. So a retired port is better tested than the gate was before the
campaign started, and worse tested than it was during the campaign. Both halves
of that sentence are true and a commit should say so.

**What the campaign learned about where the yield is.** The covers found more
defects than the ports did. `TOOL-ENCODING-1` was a defect that NEITHER
implementation had. The cover for 004 found three defects that its live run
could not reach. Cell 6 of the cover for 006 hid behind two implementations that
failed with the same exit code and two different causes. That is one argument for
keeping a gate at `oracle` longer, and it is not an argument for never
retiring one.

**So `retired` is reached by argument and never by a calendar.** A port stays at
`oracle` for as long as the three conditions are unmet, and no longer.

**THE SIX RFC §8 SECTIONS STILL DESCRIBE THE SCHEDULE.** This amendment does not
edit them, and §4 governs. A reader who finds "deleted one release after the
port lands" in an RFC must read it as the Rev 5 rule. Apply the three conditions
above instead.

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

### A spawned utility is a workaround, and the FFI bar does not catch it

**Amended 2026-08-15, after port 006 spawned `od` and no census held it.**

The campaign's standing rule counts `haskell.*` and `c.*` declarations, and the
bar from Phase 3 onward is zero. Port 006 meets that bar. It still reached
outside the language, because `wasi.proc.run` takes an executable and an argv
vector, and spawning a program is not an FFI declaration.

**So the rule as written did not fire.** `od -An -tx1` went in with a code
comment and no row. That is exactly the failure the SHAPES disposition above
describes: skipping it is how a language limitation becomes an unexamined house
style. A spawned utility is a more comfortable workaround than an FFI
declaration, which is precisely why a rule written against FFI misses it.

**The test is what the spawned program is for, not that a spawn happened.**

- **Not a gap.** The port spawns because the SUBJECT spawns, and the two run the
  same program at the same point. `stack`, the `llmll` compiler, `python3` over
  a cover script, and a fixture the gate just built are all this. A gate whose
  job is to build things and run them cannot port to a program that spawns
  nothing.
- **A gap, dispositioned SHAPES, and it owes a row.** The spawned program does
  work the LANGUAGE should do, and the subject reaches for it because it is a
  shell script rather than because the task requires a process. `od` for a hex
  dump is this, and it is filed as `BYTES-READ-1`. `/usr/bin/printf` writing a
  byte no string literal can hold is the same thing in the other direction, and
  it is raised below as `BYTES-WRITE-1`.

**A SECOND EXAMPLE STOOD HERE AND WAS WITHDRAWN ON 2026-08-15. The withdrawal
is kept, and on 2026-08-16 it got worse rather than smaller.** The amendment
first cited `awk` generating a repeated string, filed as `LIST-RANGE-1`. Port
006 then wrote that fixture with no `awk` at all: `string-concat` doubles a
literal fourteen times and gives 147456 bytes, against the 108894 the subject's
`seq` pipeline produces. That withdrew the prediction and left the row open on
the half said not to compose, N DISTINCT elements from the count N.

**THAT HALF IS ALSO FALSE, AND HAS BEEN SINCE v0.11.** `range` is a builtin.
`builtinEnv` carries it at
[`TypeCheck.hs:133`](../../compiler/src/LLMLL/TypeCheck.hs), typed
`int int -> list[int]`;
[`CodegenHs.hs:313`](../../compiler/src/LLMLL/CodegenHs.hs) emits
`range from to = [from .. to - 1]`; and [`LLMLL.md`](../../LLMLL.md) documents it
in the builtin table with a worked example covering the empty and the inverted
case. **Fifteen call sites across five committed `.llmll` files already use it**,
seven of them passing a `range` straight into `list-map`, `list-filter` or
`list-fold`, which is the shape the row called absent. One of the five files is
this campaign's own port 003,
[`docclaims.llmll`](../../tools/doc-claims/docclaims.llmll). **PROBED 2026-08-16
against `llmll 0.16.0` on aarch64-osx, executed rather than read**: `range 1 6`
answers 1 through 5, so the interval is half-open; `range 1 61` answers 60
elements; `range 3 3` and the inverted `range 9 4` each answer 0 elements and
neither crashes; and `list-map (range 1 13) int-to-string` answers 12 distinct
strings. The witness the row was moved onto, `v-feed-text` in
[`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll), now reads
`(list-map (range 1 61) ...)`, measured in the working tree on 2026-08-16, and
the row is closed as REFUTED in
[`compiler-team-roadmap.md`](../compiler-team-roadmap.md).

**So the example was not merely unmeasured: the absence it named never
existed.** That sharpens the lesson rather than softening it. The illustration
was reached for, and the operation it called missing was already in the builtin
table, already in the spec with a worked example, and already called by a
sibling port in this same campaign. **The row broke the rule printed a few
paragraphs below it**, which says to read the builtin list and check whether the
operation COMPOSES before filing an absence, and it broke it while sitting in
the section that states the rule.

**The general shape is worth more than either example.** An amendment written
to catch workarounds will itself reach for the nearest illustration, and the
nearest illustration is the one nobody has checked. Prefer an example the
campaign has already MEASURED over the one that reads best. **One grep was the
whole cost**: `builtinEnv` is one list in one file, and reading it would have
stopped this filing twice over.

**Count the spawn sites by class in each RFC's section 5.** A count of zero FFI
declarations beside an uncounted spawn is a measurement of the wrong thing.

**One correction rides along, because the amendment was over-broad when first
drafted.** `sed` for a replace-all is **not** a gap: `string-split` gives the
pieces and `list-fold` rejoins them with the replacement, so the operation
composes today in about four lines. The lesson generalises. Read the builtin
list, then check whether the operation COMPOSES from what is there, before
filing an absence.

### A gap costs a capability, and the census has only ever counted lines

**Written 2026-08-16, after the `BYTES-READ-1` site was measured a second way.**

Every gap row in this campaign is scored on one axis, which is what the
workaround costs the port in code lines. That axis is real and it is not the
only one. A workaround also decides **which capability the program must
declare**, and no census has recorded that.

**The capabilities are not equal, and two of the three take a scope.** A
filesystem import names a root, as `(capability read-write ".")`. An environment
import names one variable, as `(capability read "HOME")` in
[`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll). **The process
import names nothing.** `(capability exec)` admits any executable on the host: a
compiler, a shell, a hex dumper, an agent CLI. It is the widest authority the
language grants and it is the only one with no scope parameter.

**The compiler already says the argv split does not narrow it.**
`compiler/src/LLMLL/TypeCheck.hs` states that the split gives auditability and
not authority bounding, that the argument vector is unconstrained, and that no
capability check is enforced at that site. The missing enforcement is tracked as
`CAP-1-REAL`.

**So a spawn-shaped workaround does not only cost lines. It makes the program
hold the widest capability in the language, and filling the gap gives that
capability back.** A row scored on line count alone reports a gap as cheap when
its workaround has widened what the program may do.

**The rule.** Every row dispositioned SHAPES whose workaround spawns a process
names two more things: the capability that workaround forces the program to
declare, and whether the program would have needed that capability anyway.

**The worked example.** `BYTES-READ-1` is filed because nothing gets a file's
bytes into the language, so the port spawns `od -An -tx1`. Measured 2026-08-16:
the language HAS a first-class `bytes` type, with construction, indexed read,
indexed write and length, and **no `wasi.*` builtin carries a bytes type in its
signature at all**. The gap is a missing pair of signatures rather than a
missing type. Scored on lines the row is small. Scored on authority, a program
that wants to inspect a file's bytes must be able to execute arbitrary
binaries, which is the whole of `(capability exec)` bought to read a file the
program can already open.

**The counter-example, which keeps the axis narrow.** At port 006 this costs
nothing. `buildsmoke.llmll` builds programs and runs them, so it declares
`(capability exec)` whatever the language ships, and filling `BYTES-READ-1`
would remove no capability from it. **The axis discriminates between programs
and not within one.** It states what a gap costs the NEXT program, which is the
population this campaign exists to serve. A row whose workaround forces `exec`
on a port that already holds it scores zero here, and saying so is part of
applying the rule.

**What this does to the existing rows is nothing automatic.** The axis is
recorded so the next RFC's section 5 carries it, and so a re-score is a
measurement someone runs rather than an argument someone has. `BYTES-READ-1` and
`BYTES-WRITE-1` move first, and both move for the same reason.

### The rule applied to the whole port, and four sites owe a row

**Measured 2026-08-16 in the working tree, over the whole of
[`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll), after stage 5b
landed and while it is still uncommitted.** Sixty `wasi.proc.run` call sites.
Twenty-four name a CONSTANT executable and thirty-six COMPUTE one from state,
almost always `(get-s b "subject")`, the compiler the gate was pointed at.
Fifty-six are not a gap. Four are; three of those rows were already filed and
the fourth is filed by this census.

| What the site spawns | Sites | Executable | Class |
|---|---|---|---|
| the `llmll` under test: `build` 13, `version` 5, `replay` 4 | 22 | computed | not a gap |
| `stack`: `path --local-install-root` 15, `--version` 1 | 16 | constant | not a gap |
| a binary this gate itself just built (nine distinct executables) | 14 | computed | not a gap |
| `python3` over a differential cover script | 3 | constant | not a gap |
| `ghc --version` | 1 | constant | not a gap |
| `od -An -tx1` over a captured stdout | 1 | constant | **SHAPES, `BYTES-READ-1`** |
| `/usr/bin/env`, prefixing an assignment to an argv vector | 1 | constant | **SHAPES, `PROC-ENV-1`** |
| `/usr/bin/uname -s`, reading the host platform | 1 | constant | **SHAPES, `PLATFORM-1`** |
| `/usr/bin/printf`, expanding octal escapes into a binary fixture | 1 | constant | **SHAPES, `BYTES-WRITE-1`** |

**Class (b) is FOUR sites carrying four tags, where the census taken earlier the
same day found one.** Stage 5c hex-dumps a program's captured output with `od`
because `wasi.fs.read` answers UTF-8 text and nothing in the language looks at
bytes; `BYTES-READ-1` was filed off exactly that site on 2026-08-15. Stage 5b
brings the other three. `/usr/bin/env` sets a child's environment, which is
`PROC-ENV-1`, filed 2026-08-11 and open in the table above. `/usr/bin/uname -s`
reads the host platform, which is `PLATFORM-1`, filed 2026-08-16.
`/usr/bin/printf` writes a lone `0xFF` into the stage's `bin.dat` fixture,
because `wasi.fs.write` takes a string and encodes it as UTF-8 and no `.llmll`
literal can carry that byte. **Nothing in this section, in TOOL-RFC-006, or in
the roadmap had named that last one.** It is raised here as `BYTES-WRITE-1`,
dispositioned SHAPES, and it was filed in the roadmap the same day. Measured
2026-08-16: the file that lands is
`62 69 6e 61 72 79 20 ff fe 00 20 72 61 77 0a`, matching
[`build_smoke.sh`](../../scripts/build_smoke.sh)'s own `printf` byte for byte.
It is the opposite direction of `BYTES-READ-1` in one namespace, so it is a
separate row on the `ENV-READ-1` versus `PROC-ENV-1` precedent rather than a
second use of that one.

**How `BYTES-WRITE-1` was found is `LIST-KIND-1` recurring with its halves
swapped.** There, port 004 recorded a gap with NO TAG, so a search for tags
could not see it, and it sat for a release. Here the port's own code NAMED the
tag while no roadmap row existed for a search of the roadmap to find, and it was
filed within hours rather than within a release. **The shorter window is luck
about who looked, not a difference in mechanism.** The repair is the same in
both directions: a tag and a row are owed at the moment a gap is recorded, and
either one alone is invisible to whichever instrument looks for the other.

**The two PENDING sites are discharged, and the third was never on the list.**
The earlier census held `PLATFORM-1` and `PROC-ENV-1` out of its total because
stage 5b was unported, and named them so that the next census would count them.
It counts them. It did not name `BYTES-WRITE-1`, because a pending list can only
hold gaps someone has already thought of. **A pending list is a forecast, and
this one was two thirds right**, which is a better result than it sounds and is
still not a census.

**A CENSUS WAS MEASURED, PUBLISHED, AND INVALIDATED BY WORK LANDING THE SAME
AFTERNOON.** The figures above replace fifty-five sites, twenty constant and
thirty-five computed, measured at `cdd6438` and written into this section on
2026-08-16. Stage 5b landed hours later and moved every one of them. The earlier
count was not wrong; it was a measurement of a tree, and the tree moved.
**That is why a census states its commit and its date rather than reading as a
standing fact**, and it is why the paragraph above says which tree these sixty
sites were counted in and that the code carrying them is not yet committed.

**The earlier census counted a different thing over a fraction of the port, and
both halves of that matter.** It reported twenty-four spawn sites over the
PROC-STDIN-1, REPLAY-FRAME and PROC-BOUNDARY-1 stages at `9806b78`. Those three
stages hold NINETEEN `wasi.proc.run` call sites; twenty-four is their RUNTIME
spawn count, because REPLAY-FRAME loops over two modules and five of its sites
therefore fire twice. The two figures are not two answers to one question. The
earlier finding still stands over what it covered: none of those nineteen sites
owes a row, and `od` is absent from them because `od` is in stage 5c.

**The defect is this campaign's own recurring class.** A census over three
stages was reported in a section whose subject is the port, and correcting the
population moved the count from twenty-four to fifty-five.

**Nine shell utilities the subject uses were composed instead of spawned, two
more than the three-stage census found.**

| [`build_smoke.sh`](../../scripts/build_smoke.sh) spawns | The port composes |
|---|---|
| `cp` | `wasi.fs.copy` |
| `mkdir -p` | `wasi.fs.mkdir` |
| `rm -f` | `wasi.fs.delete` |
| `cmp -s` | string equality, at the replay tamper crux |
| `grep -Fq`, `grep -Fqx`, `grep -qE` | `string-contains`, the port's whole-line `has-line?`, and `regex-match` |
| `sed` replace-all | `string-split` plus a fold-join |
| `printf 'LINE%s\n' $(seq 12000)` | `string-concat` doubling, fourteen times |
| `tr -d ' \n'` | two `string-split` passes, one separator each |
| `python3 -c` writing sixty lines | `list-map` over `(range 1 61)`, which was a literal sixty-element list until `LIST-RANGE-1` was refuted |

**`python3` and `printf` each land in BOTH classes, and that is the test
working.** Three `python3` sites spawn it over a cover script, which is what the
subject does at the same point, and one use of it as a line generator composed
away to nothing. `printf` composes away where it repeats a text line, in the row
above, and it is spawned where it must emit a byte no string literal can hold,
which is the `BYTES-WRITE-1` site. The rule asks what the spawned program is
FOR at each site; it does not keep a list of forbidden names, and one name can
answer differently at two sites in the same file.

**One subject utility falls in neither class.** `mktemp -d` makes the scratch
directory, which reaches the port on argv instead, so there is nothing to spawn
and nothing to compose. It is named here so a later reader does not read its
absence from both tables as an omission.

**A discipline that fires is a result whichever way it comes out, and both
outcomes are recorded for that reason.** Fifty-six sites cleared, four owed a
row, and nine utilities never became a site at all. Silence reads as "not
checked", and the campaign cannot tell those two apart a month later. The COUNT
carries a claim the verdict does not: it says the rule was applied to the whole
population, and not to whichever part of it happened to be in front of someone.

### A port can be complete and still not gate

**`buildsmoke.llmll` printed `BUILD-GATE-1 FAIL:` and exited 0, across every
one of its stages, from the day it was written until `9806b78`.** It declared
no `:status`. Measured on three negative controls: each printed its failure
line and each answered 0. The two sibling ports
[`pathlint.llmll`](../../tools/doc-path-lint/pathlint.llmll) and
[`versiongate.llmll`](../../tools/version-gate/versiongate.llmll) both declare
`:status`, so this port was the outlier and nothing in this campaign asked.

**The omission is INVISIBLE in any port whose stages all pass**, which is why
it needs a checklist line rather than a paragraph. **Every port declares
`:status`, and one negative control proves a failing run exits non-zero.** A
port that only ever passes has not shown that it can fail.

The repair writes the pass mark on the SUCCESS path and not on the thirty-nine
failure paths. A stage appended later therefore inherits failure rather than an
inherited pass, and the next author cannot make this mistake by omission.

**One smaller item rides along and does not earn a row.** The port writes
`bs_stack.txt` and `bs_ver.txt` into its own working directory on every run,
from the two stages that use relative output paths under cwd `"."`. It is the
same class as the port's own note about not running the version gate from
inside the tree.

### The tri-state has no value for "started and incomplete"

**Filed here 2026-08-15 so that no further revision argues it in prose.**
`tool_state` takes `blocked`, `oracle` or `retired`. A port that is written,
building and deciding, but not yet in a job and not yet complete, is none of
these. `blocked` is the only value the RFC standard gate accepts, so every such
port carries a value that understates it.

TOOL-RFC-006 spent a paragraph on this at Rev 2 and again at Rev 4. A record
that describes the same gap three times and repairs it never is the shape this
campaign exists to catch. **The row is the repair; a fourth paragraph is not.**

**Known gaps, at v0.14.87.** Leverage order for the six gates in scope:

| Gap | Disposition | Blocks, of the six in scope | Status |
|---|---|---|---|
| `MODE-CLI-1` | SHAPES | **every tool** | filed 2026-08-07 |
| `SPLIT-EMPTY-1` (with the no-character-decomposition half) | SHAPES | every scanner | filed 2026-08-07 |
| `REGEX-LOWER-1` | BLOCKS | `doc_path_lint` (005) | **SHIPPED v0.14.96**, and its census corrected its own row |
| `FS-WALK-1` | **COSMETIC** | **none** | **CLOSED 2026-08-10** on the measurement the row itself asked for. It read BLOCKS against 006 from 2026-08-07 until then. Measured: 006's walk sites are **twelve**, not the nine the row claimed, all one query, and the tree is **depth 4 on both platforms in scope**, so the requirement would have composed from flat `wasi.fs.list` calls and no builtin is owed. **SUPERSEDED IN PART 2026-08-11: the twelve sites are gone.** Measuring the selection showed the search itself was the defect, not its depth, so `build_smoke.sh` now asks `stack path --local-install-root` and port 006 copies that through `wasi.proc.run`'s `cwd`. Roadmap closed-rows section |
| no env access (`wasi.proc.args` exists, no env builtin) | **SHAPES at 006**, was COSMETIC | `ENV-READ-1`, owed | **The "nothing lost" clause is FALSE at port 006, and 006 is the port that found it.** It held at 005: `wasi.proc.args` delivers `--strict extra` as `argc=2` to a built binary with no `--` separator, and only the invocation changed. It fails at 006 because `scripts/build_smoke.sh:118` tries THREE sources for the compiler and the third is `$HOME/.local/bin/llmll`. **argv carries what a CALLER passes, and `$HOME` is not passed.** So the port reproduces two of the subject's three branches and drops the third, which is a behaviour difference and not an invocation difference. Reading `$HOME` through `sh -c 'echo $HOME'` is available and REFUSED, because TOOL-RFC-006 D1 forbids this port handing any string to a shell. **This is the "argv carries it" escape hatch failing on its second use**, which is the general lesson: a disposition tested against one port is a measurement of that port, not of the language |
| `CAP-NULLARY-1` | COSMETIC | none | filed 2026-08-07 |
| `FS-STAT-1` | BLOCKS | none in scope | filed, open |
| `FS-EXISTS-1`: nothing answers "is there a file here" without moving its bytes | SHAPES | `doc_path_lint` (005) | **FILED 2026-08-10**, raised by 005. Deliberately NOT folded into `FS-STAT-1`, which answers about an artifact's AGE |
| `LIST-KIND-1`: a listing carries no entry kind, and no listing can see a symlink | SHAPES | `doc_archive` (004) | **FILED 2026-08-10**, raised by **004** and not by 005. **This row was owed for a release and sat in no census, including this one**; it was found by sweeping the records at `FS-WALK-1`'s close, not by the discipline that is supposed to catch it. See the note below. Deliberately NOT folded into `FS-WALK-1`, which asked about recursion where this asks about the shape of the listing result |
| `REGEX-CAPTURE-1`: `regex-match` returns `bool`, so no capture and no scan | SHAPES | every scanner | **FILED 2026-08-10**, raised by 005. Independent of `REGEX-LOWER-1`, which was about lowering and shipped |
| `REGEX-CASE-1`: no case-insensitive matching; TDFA rejects `(?i)` and no lowercase builtin exists | SHAPES | `doc_path_lint` (005) | **FILED 2026-08-10**, raised by 005 and firing on real prose, not only on a fixture |
| `PATH-NORM-1`: no path normalization for `..` | SHAPES | `doc_path_lint` (005) | **FILED 2026-08-10**, raised by 005; 58 of 947 live citations need it |
| `PROC-STDIN-1`: `wasi.proc.run` could not supply a child's stdin | SHAPES | `build_smoke` (006) | **SHIPPED v0.14.98, 2026-08-12, BEFORE the port was written.** `wasi.proc.run` now takes a seventh parameter, a stdin path, so the port passes a path and writes no shell string. **This is the campaign's FIRST gap closed by the compiler rather than worked around by a port**, and the second time the critical path ran through the compiler team, after `REGEX-LOWER-1` at 005. Filed 2026-08-11, raised by 006, and **the largest gap any port has produced**. A console-mode LLMLL program takes one line of stdin per step, so DRIVING one IS feeding it stdin, and 006 exists to drive them. Thirteen sites, holding **295 of 504 stage code lines**. SHAPES rather than BLOCKS **on a measurement**: `/bin/sh -c` supplies the input and a real console binary driven that way completes its loop. The cost is that thirteen sites rebuild the shell string that `wasi.proc.run`'s argv split exists to remove, at the sites that run the other five ports. Distinct from `RUN-STDIN-1`, which is `llmll run`'s driver rather than the builtin |
| `PROC-STDIN-SHARE-1`: a child shared the parent's stdin and stole a torn fragment above 8 KiB | SHAPES | `build_smoke` (006) | **SHIPPED v0.14.98, 2026-08-12.** `std_in` is bound, so no child reads the parent's input. Filed 2026-08-11, raised by 006. **A defect and not only a gap.** Measured: at 9,693 bytes the child reads `NE1034`, the tail of `LINE1034` cut at the buffer edge; three runs at 138,893 bytes took three different victims and one made the parent skip a step input. **The five shipped ports do not trip it** because their children do not read stdin, so it is latent, and no existing cover could have found it |
| `PROC-ENV-1`: nothing SETS an environment variable for a child | SHAPES | `build_smoke` (006) | **FILED 2026-08-11**, raised by 006. One site, `LC_ALL=C` at line 443. **Deliberately NOT folded into the "no env access" row above**, which is about a program READING its own environment and was tested at 005 and held. Reading and setting are two directions and one row cannot carry both |

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

**A SECOND count of `FS-WALK-1` was also wrong, in the other direction, and it
sat in the roadmap for three days.** The corrected row said `build_smoke.sh` has
**nine** walk sites. It has **twelve**. The row asked for that measurement in its
own text and nobody ran it until 2026-08-10, at which point the answer closed the
row outright: all twelve are one query at a fixed depth of 4. **Two wrong counts
on one gap is the finding.** The first over-stated the blast radius, the second
under-stated the population, and neither was caught by re-reading. Only running
the count caught either.

**`LIST-KIND-1` was owed for a release and appeared in NO census, including this
one.** [`TOOL-RFC-004`](tool-rfc-004-doc-archive.md) §5 recorded it on 2026-08-09
as SHAPES, unfiled, owed, with no tag name, and §5 here never gained a row for
it. It was found on 2026-08-10 by grepping the records during an unrelated close,
not by this section's discipline. **A gap with no tag is invisible to a search for
tags**, which is the mechanism, and the repair is that a row is owed a NAME at the
moment it is recorded, not at the moment someone decides to file it. This is
§10's "gaps worked around silently" reaching the census itself rather than a port.

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
- **005** doc-path lint. **PORTED 2026-08-10, RETIRED 2026-08-12 at v0.14.99**,
  [TOOL-RFC-005](tool-rfc-005-doc-path-lint.md), `tool_state: retired`. It was
  green on run `31439956284` while it was an oracle. **This is the campaign's
  first retirement, and it is where retirement stopped being a rule and became a
  measurement.** The cover held `REF = "scripts/doc_path_lint.py"` and compared
  the two implementations, so it could not outlive the reference: **22 cells, 19
  mutations and 3 negative controls, all deleted**, after having been SHOWN TO
  FAIL against two deliberately broken ports rather than merely to pass. The
  port is now ungraded. **Deleting the subject broke 13 prose citations in 6
  files**, measured before the deletion rather than after it, which is the rule
  port 006 inherits: move the subject aside, run the gate, then delete.
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
  **RFC WRITTEN 2026-08-11**, [TOOL-RFC-006](tool-rfc-006-build-smoke.md),
  `tool_state: blocked`, meaning the port module does not exist yet. **The port is
  feasible and it is not blocked on the compiler**: one complete stage was
  written in LLMLL, built, and run against a good fixture and a broken one, and
  it discriminates. **The scope question turned out not to be size.** Thirteen
  sites feed a child on stdin and `wasi.proc.run` cannot, so the port reaches
  them only through `/bin/sh -c`, which rebuilds the shell string the argv split
  removes. **D1 is SUPERSEDED and the port is better for it.** The user chose to
  fix the compiler first, so `PROC-STDIN-1` shipped a seventh parameter on
  `wasi.proc.run`, a stdin path. The port passes a path and writes no shell
  string. **This is the campaign's first gap closed by the compiler rather than
  worked around by a port**, and it is the second time the critical path ran
  through the compiler team, after `REGEX-LOWER-1` at port 005.
  **It raised three gaps and one is a compiler defect**, `PROC-STDIN-SHARE-1`,
  latent in every shipped port. **The size projection it inherited was wrong by
  1.8 times**: 4.8 is the FIRST port's ratio, the five decline to 2.23, the
  measured one-stage ratio is 2.6, and the port projects to about 1,400 code
  lines rather than 2,500. **A negative control caught the RFC's own stage
  printing PASS on a build that exited 1**, by reading a stale artifact, which
  is the campaign premise landing on the campaign for the third time.

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
| `FS-WALK-1` | **language-team**, **SETTLED 2026-08-10** | an unbounded walk in a bounded idiom was a design question, and the measurement dissolved it: 006 needs no walk. The residue, what bounds an unbounded worklist, went to `MODE-CLI-1` rather than becoming a row, because that row is the cause and `PROC-BOUNDARY-1` §4.5 already discloses the diagnostic half |
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
