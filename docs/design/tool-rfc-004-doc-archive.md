---
name: tool-rfc-004-doc-archive
title: "TOOL-RFC-004: the archive-disposition drift gate, in LLMLL"
status: "Rev 3, PORTED, state ORACLE, RELEASED at v0.14.95. Both implementations run adjacent in spec-roundtrip; DRIFT-DOC-3 left the banner job in the same commit as the port, which section 8 requires. Both policy decisions were closed BEFORE any code existed (D1 distribution option D, D2 the port carries the fixture counts). THE COVER IS 17 CELLS, 14 mutations and 3 negative controls, and NOT the six cells this line recorded until v0.14.95: every mutation is asserted to fail under BOTH implementations before their answers are compared, and the controls require both to PASS an unmutated tree. IT FOUND THREE DEFECTS that a live green run and six hand-run cells had already survived: criterion 1 was not implemented at all, criterion 7 printed no remedy epilogue, and two cover cells were wrong by construction. THE CAMPAIGN-LEVEL FINDING STANDS: the published release image cannot build a port (no GHC, no Stack in its runtime stage), so P1 clearing did not resolve TOOL-RFC-001's deviation and the campaign's distribution sentence is owed an amendment. Section 7 reports that the live corpus gates exactly ONE file, so the fixtures carry all discriminative power."
date: 2026-08-10
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, user]
tool_state: oracle
subject_script: scripts/doc_archive_gate.sh
port_module: tools/doc-archive/docarchive.llmll
---

# TOOL-RFC-004: the archive-disposition drift gate, in LLMLL

## 1. Subject

[`scripts/doc_archive_gate.sh`](../../scripts/doc_archive_gate.sh), **125 code
lines** of 218 total (excluding comments and blanks, measured 2026-08-09). It is
DRIFT-DOC-3.

**What it decides.** Every archived design doc that DECLARES an
`archive-disposition` frontmatter field must sit in the directory that field's
side names: `shipped|superseded` in `shipped-design-specs/`, `dropped|deferred`
in `dormant-explorations/`. Files without the field are not gated; the count of
them is asserted against a bound that may shrink and never grows silently.

**Where CI invoked it, and where it runs now.** It ran in
[`version-gate.yml`](../../.github/workflows/version-gate.yml)'s banner job
**`C1-C4 banner / schema + DRIFT-DOC-3 / DOC-4`**. **As of this port it runs in
`spec-roundtrip`, adjacent to the LLMLL port**, per §3's settled option D; the
move landed in the same commit as the port because §8 requires it.

**The job is the whole of §3 and naming it wrong is TOOL-RFC-001's recorded
mistake.** This job has **no Haskell toolchain by design**. The workflow header
says so in its own words ("No Stack: no gate in this job has a compiler
dependency") and the job's budget is "fast (<1 min)". The step's own comment
states the rationale: "No compiler dependency, so it belongs in the fast job and
fails closed rather than skipping."

**What kind of gate it is, because it bounds what §7 can claim.** A *consistency*
gate, sibling of [`version_gate.sh`](../../scripts/version_gate.sh) (DRIFT-CI-1):
it asserts agreement between two records maintained inside this repository. It
has **no oracle outside the repo**, unlike DRIFT-CT-2, which executes the
compiler. It therefore cannot detect both records being wrong, and the project
already adjudicated that limit as structural for a self-attestation channel
(F-002, `LLMLL.md` §4.4.6).

## 2. Criteria

The reference **exits on first failure**, so the order below is part of the
behaviour and the port owes the same order. Messages are quoted from the
reference because a cover that compares them needs them written somewhere that
is not the reference.

**Failure order, first to last.**

| # | Criterion | Message on failure |
|---|---|---|
| 1 | self-test fixtures present | `self-test fixtures missing under scripts/doc-archive-fixtures (expected pass/ and fail/)` |
| 2 | `pass/` produces zero violations | `self-test: pass/ fixtures reported N violation(s), gate over-fires:` |
| 3 | `pass/` gated count is exactly 4 | `self-test: pass/ scanned N gated file(s), expected 4 (one per vocabulary value)` |
| 4 | `fail/` produces exactly 4 violations | `self-test: fail/ fixtures produced N violation(s), expected 4 (mis-filed shipped-side, mis-filed dormant-side, unknown value, stray declaration outside the governed dirs). Gate under-fires:` |
| 5 | real run scanned more than 0 files | `scanned 0 files under docs/archive/{shipped-design-specs,dormant-explorations}, the governed directories are missing or renamed` |
| 6 | real run has zero violations | `DRIFT-DOC-3 FAIL: N archived doc(s) sit in a directory their declared disposition contradicts` |
| 7 | ungated count within bound | `DRIFT-DOC-3 FAIL: N archived doc(s) declare no archive-disposition, above the bound of B` |

All failures are prefixed `DRIFT-DOC-3 FAIL: ` by `fail()` and go to **stderr**;
criteria 6 and 7 print their headline to stderr and a bare newline to stdout
first, which the port owes as well.

**The three violation strings**, emitted per offending file and rendered with a
`  ✘ ` prefix under criterion 6:

- `<file>: archive-disposition '<v>' is not one of shipped|superseded|dropped|deferred`
- `<file>: archive-disposition '<v>' belongs in <want>/, found in <got>/`
- `<file>: declares archive-disposition '<v>' outside the governed directories (shipped-design-specs/, dormant-explorations/); the field does not apply here`

**Success output**, three lines across two stages:

```
DRIFT-DOC-3 self-test OK: pass/ clean over 4 values, fail/ caught 4 of 4
DRIFT-DOC-3 PASS: <gated> declared disposition(s) agree with their directory
DRIFT-DOC-3 NOTE: <ungated> ungated file(s), at the bound.
```

The NOTE line has a second form when the count is under the bound:
`DRIFT-DOC-3 NOTE: <n> ungated file(s) against a bound of <B>, lower UNGATED_BOUND to <n>.`
Both forms are behaviour, and a port that emits only one of them diverges on a
tree where the debt has been paid down.

**Two scoping rules that are easy to lose in a port.** `README.md` and
`INDEX.md` are skipped as index files rather than archived documents. The
disposition is read **only inside the frontmatter block**, which is what rules
out a whole-file scan: the reference records that "superseded" appears in body
prose in four different files.

## 3. Distribution

**This section is a finding, not a choice the port could make, and it is why
this RFC sat at `blocked` until the question was adjudicated.**

The campaign settled that jobs pull a published release image. TOOL-RFC-001
deviated from that, leaving the shell deciding in the fast job and running its
LLMLL binary from `build_smoke.sh` inside `spec-roundtrip`, and recorded the
deviation as transitional: *"It resolves when P1 clears."* **P1 has cleared.**
Tags v0.14.84 to v0.14.94 are published and v0.14.94's digest was verified at the
registry with `:latest` resolving to it.

**It does not resolve, and the prediction was wrong for a reason nobody had
checked.** The published image cannot produce a port binary. Read off
[`Dockerfile`](../../Dockerfile): the runtime stage is `debian:bookworm-slim`
installing only `z3 libgmp10 zlib1g ca-certificates`, and it copies exactly two
executables, `llmll` and `fixpoint`. There is **no GHC and no Stack**. `llmll
build` emits a Haskell package and shells out to `stack build` to compile it, so
inside the image it has nothing to build with. The image delivers a *compiler*,
and a port is a *compiled program*; those are different artifacts and the
campaign's distribution sentence does not distinguish them.

So the constraint stands exactly as TOOL-RFC-001 found it: **the banner job has
no toolchain, and no mechanism yet puts a compiled port into it.** The options,
none of which the porter should pick alone:

| Option | Cost |
|---|---|
| **A.** Ship prebuilt tool binaries in the image | Dockerfile change, so a campaign change. Chicken-and-egg: the image is built per tag, so a port fix is untestable in CI until it is released |
| **B.** Build in `spec-roundtrip`, pass to the banner job as a workflow artifact | Serializes two jobs that run in parallel today; the banner job's "fast (<1 min)" budget becomes "after the 17-minute job" |
| **C.** Repeat 001's deviation: port runs in `spec-roundtrip`, shell keeps deciding in the banner job | Consistent with precedent, and leaves the reference deciding, which §8 then cannot delete |
| **D.** Relocate DRIFT-DOC-3 wholesale into `spec-roundtrip` | Both implementations adjacent, 003's arrangement; costs the fast job one of its four gates and slows the signal a contributor sees first |

**Option C is what 001 did and it is the one that makes §8 incoherent**, because
retirement deletes the reference and the reference is the thing still deciding in
the job that matters.

**SETTLED: option D, by user adjudication 2026-08-09.** DRIFT-DOC-3 moves
wholesale into `spec-roundtrip`, both implementations as adjacent steps, which is
003's arrangement and for 003's reason: `tool_state: oracle` means both run and a
reader compares their answers in one job log rather than across two jobs. It is
the only option that leaves §8 coherent without a Dockerfile change, because after
the move the reference is no longer the thing deciding in a job the port cannot
reach.

**What it costs, stated here rather than discovered later.** Three things get
worse and none of them is fatal:

1. **The fast job loses one of its four gates.** `version-gate.yml`'s banner job
   is budgeted "fast (<1 min)" and is the signal a contributor sees first. After
   the move it carries C1-C4, DRIFT-DOC-4 and the pytest suite, and no longer
   answers the archive-disposition question at all.
2. **Time-to-signal goes from under a minute to roughly seventeen.** An
   archive-disposition error is a one-line frontmatter mistake, and it will now
   surface behind a Haskell build. Measured on run `31332324160`: the
   `spec-roundtrip` job took 17m17s while the banner job took 25s.
3. **A gate with no dependencies acquires one.** DRIFT-DOC-3 needs bash and awk
   and nothing else, which is why its step comment says it "belongs in the fast
   job and fails closed rather than skipping". In `spec-roundtrip` it sits behind
   `Build llmll`, so a compiler build failure now means the archive gate does not
   run **at all**. It does not skip silently, since the job fails, but the
   distinction between "the archive is consistent" and "we never checked" stops
   being visible in a green banner job.

Point 3 is the one to watch: it is `SKIP-SILENT-1`'s neighbourhood, and the
mitigation is that the job fails loudly rather than reporting green. The step
must therefore be ordered so that it runs even when later solver-dependent steps
would fail, and it must not be made conditional on anything.

**The campaign's distribution sentence still needs amending** and this RFC does
not do it: "jobs pull a published release image" does not distinguish shipping a
compiler from shipping a compiled port, and that is the sentence which made 001
predict a resolution that measurement contradicts. Owed to `language-team`.

## 4. Feasibility

Worked from the reference's actual behaviour and, where the answer was not
obvious, from **executing a probe** rather than reading the capability table.
The campaign's own lesson is that a feasibility table enumerates what the
language HAS while the defects are in what it DOES: TOOL-RFC-002's read
concluded "nothing here is BLOCKS" and "no new gap" and both were false.

| Needs | LLMLL | Note |
|---|---|---|
| List a directory's entries | **available**, `wasi.fs.list` | Returns `RList [String]`, sorted; an empty directory is `RList []` and not `RNone` |
| Tell a DIRECTORY from a FILE in that listing | **gap, works by attempt** | `RList` carries no kind field. **Probed and executed**: listing a directory answers `RList`, listing a file answers `RErr`. So the stray-declaration branch is portable at one IO call per entry, riding the error path |
| Enumerate two known subdirectories | **available** | Composes from flat `wasi.fs.list` on each name; no recursion needed |
| Enumerate subdirectories of UNKNOWN name | **available via the row above** | Needed by criterion 6's stray-declaration branch (`for dir in "$root"/*/`), which the `fail/` fixture exercises, so it cannot be skipped |
| Read a file's text | **available**, `wasi.fs.read` | |
| Split content into lines | **available**, `string-split` | Empty-separator decomposition is absent (`SPLIT-EMPTY-1`), but a `"\n"` separator is all this gate needs |
| Recognize a frontmatter delimiter and an `archive-disposition:` prefix | **available, not contractable** | String comparison in a bool-valued body falls back (`STRLIT-BODY-1`), so the recognizer half carries no proof. This is the §7 constraint, not a §5 blocker |
| Strip surrounding whitespace and quotes | **available** | |
| Classify a value to a side | **available AND provable** | The adjudicator half. Measured: an input-side contract of the `classify.llmll` shape verifies body-faithful SAFE and misrouting one arm is refuted at constraint #1 |
| Integer counters and comparison | **available** | gated/ungated counts, the bound test |
| Exit with a distinct status | **available**, `console` mode | `:mode cli` emits a pure `print (step args)` with no Command and no exit status (`MODE-CLI-1`), so a gate must be a stdin-driven step machine |
| Write to stderr | **needs confirming** | Criteria 1 to 7 all write failures to stderr and the port owes the same channel. `wasi.io.stdout` is used by the shipped ports; whether a stderr sink exists is UNMEASURED and is the one row here not yet probed |

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| A listing carries no entry KIND, so a file and a directory are indistinguishable without a second call | **SHAPES** | unfiled, owed | One `wasi.fs.list` per root, partitioned by kind in a single pass. Instead the stray-declaration branch calls `wasi.fs.list` on every entry and reads `RErr` as "this is a file", which is a control-flow use of an error channel and costs one IO call per entry |
| `:mode cli` performs no Command and yields no exit status | **SHAPES** | `MODE-CLI-1` | A straight-line program: scan, print, exit. Instead every port in this campaign is a stdin-driven step machine with an explicit `Ctl` state type, which is the single largest reason a shell gate triples in line count |
| A bool-valued body whose result is a string comparison falls back, so the frontmatter recognizer carries no proof | **SHAPES** | `STRLIT-BODY-1` | The recognizer and the adjudicator would both be verified. Instead only the adjudicator half is contractable, which is what forces §7's instrument split rather than a single proof covering the gate |
| `string-split` with an empty separator does not terminate and there is no character decomposition | **COSMETIC** | `SPLIT-EMPTY-1` | Nothing follows: this gate splits on `"\n"` and never needs character-level decomposition |
| No recursive directory walk | **COSMETIC** | `FS-WALK-1` | Nothing follows: the archive is two levels and composes from flat lists, which is the census claim and it holds for this gate |

**The first row is owed a roadmap row and is deliberately not folded into
`FS-WALK-1`.** That row is "`wasi.fs.list` is flat; there is no recursive
directory walk", which is about **recursion**; this is about the listing carrying
no **kind**. They share a cause, the shape of the listing result, and not a
symptom. That is the same distinction the repository drew between
`ALIAS-LOWER-1` and `REGEX-LOWER-1`, where collapsing the two produced a row
that was wrong for a release.

## 6. Differential plan

A cover in the shape of [`doc_claims_cover.py`](../../scripts/doc_claims_cover.py),
taking `--gate` (the port binary) and running the reference from a scratch copy.
**Both implementations get the same scrubbed environment**, because 003's cover
found an `llmll` on `PATH` that its reference could not see and was then
comparing two worlds rather than two implementations.

Every mutant is asserted to fail under **both** implementations before their
answers are compared. Agreement on a passing tree is not evidence, and this gate
makes that concrete: its live corpus passes with one gated file, so a cover that
only ran the live tree would agree on almost nothing.

| Cell | Mutation | Criterion | Expect |
|---|---|---|---|
| 1 | delete `scripts/doc-archive-fixtures/pass/` | 1 | both FAIL, fixtures missing |
| 2 | delete `scripts/doc-archive-fixtures/fail/` | 1 | both FAIL, fixtures missing |
| 3 | add a conformant 5th file to `pass/` | 3 | both FAIL, gated count 5 not 4 |
| 4 | remove one file from `pass/` | 3 | both FAIL, gated count 3 not 4 |
| 5 | move `pass/` `conformant-shipped.md` into `dormant-explorations/` | 2 | both FAIL, pass/ over-fires |
| 6 | correct `fail/` `misfiled-shipped.md` onto its right side | 4 | both FAIL, 3 violations not 4 |
| 7 | correct `fail/` `unknown-value.md` to `shipped` | 4 | both FAIL, 3 violations not 4 |
| 8 | delete `fail/` `stray-declaration.md` | 4 | both FAIL, 3 violations not 4; this is the cell that proves the subdirectory branch is implemented |
| 9 | move the live gated file to `shipped-design-specs/` | 6 | both FAIL, disposition contradicts directory |
| 10 | set the live gated file's value to `probably-shipped?` | 6 | both FAIL, value not in vocabulary |
| 11 | add `archive-disposition: shipped` to a file in `professor-reviews/` | 6 | both FAIL, declared outside governed dirs |
| 12 | rename `docs/archive/shipped-design-specs/` | 5 | both FAIL, scanned 0 files |
| 13 | strip the field from the one live gated file | 7 | both FAIL, ungated 59 above bound 58 |
| 14 | add `archive-disposition:` inside a file's BODY prose, not frontmatter | 6 | both PASS, the frontmatter scoping holds |
| **NC-1** | unmutated tree | all | **both PASS**, exit 0 |
| **NC-2** | add a conformant new file to `dormant-explorations/` with a correct `deferred` | 6, 7 | **both PASS**, gated count rises by one |
| **NC-3** | add an `INDEX.md` to a governed directory | 2, 3 | **both PASS**, index files are skipped |

Cell 14 and the three negative controls are the ones that matter most here. In
TOOL-ENCODING-1 every mutation cell AGREED while both implementations failed
identically, and the negative controls, which require both sides to PASS an
unmutated tree, were the only cells that could tell "the two agree" from "neither
can read the corpus".

## 7. Verification

**The live corpus is nearly vacuous and this section exists to say so.** Measured
2026-08-09 across `docs/archive/`: of 59 scanned files, **exactly ONE declares
`archive-disposition`** (`docs/archive/dormant-explorations/contract-clause-refactor.md`,
value `deferred`) and 58 are ungated at the bound. So the live run exercises
**one of four vocabulary values and zero of the four violation classes**. A port
that agreed with the reference on the live tree forever would have demonstrated
almost nothing.

All discriminative power lives in `scripts/doc-archive-fixtures/`: 8 files
carrying all four vocabulary values in `pass/` and all four violation classes in
`fail/`.

| Instrument | Catches | Blind to | Survives §8? |
|---|---|---|---|
| The §6 differential cover | Any divergence from the reference under mutation, including the message text and the failure ORDER | A defect the port and reference SHARE, which is the likely class when the port is written by reading the reference; and it cannot run at all once the reference is gone | **No** |
| The fixture self-test, with its expected counts carried **in the port** | Over-firing and under-firing independently: `pass/` must be clean over 4 values, `fail/` must produce 4 violations, so a recognizer that stops recognizing shows up as an under-fire | A wrong answer that is wrong the same way in both directions, and anything about the LIVE corpus, which it never reads | **Yes**, the fixtures are a separate directory from the subject script |
| A contract on the adjudicator (`disposition -> side`) with at least one refuting case | A misrouted arm, referencing neither implementation. Measured: the input-side contract verifies body-faithful SAFE and misrouting one arm is refuted at constraint #1 | The RECOGNIZER half entirely: which bytes count as a declaration, frontmatter scoping, index-file skipping. `STRLIT-BODY-1` makes that half uncontractable today | **Yes** |

**The three fail differently and that is the point.** The cover compares two
implementations; the self-test compares one implementation to a fixed expected
count; the contract compares a function to a specification. A defect shared by
both implementations passes row 1 and is caught by row 3 if it is in the
adjudicator. A recognizer regression passes row 3 and is caught by row 2.

**Two things this section does NOT claim.** The contract covers the adjudicator
only, so the recognizer half has exactly one instrument (row 2), which is the
absence §7 permits a row to record, tagged `STRLIT-BODY-1`. And
`--strict-verified-core` is **not** listed as an instrument: `versiongate.llmll`
passes it today with zero body-faithful functions, so the pass is vacuous, which
is the precise failure this section exists to name.

**The one item of debt this section created is now closed.** The fixture
self-test's expected counts (4 and 4) currently live inside the reference script,
which §8 deletes, so row 2 would not have survived its own retirement. Settled at
§9 D2: the port carries them as its own assertions. Row 2's "survives §8" is
therefore a claim about the port's code and not only about where the fixture
files sit, and it is false until that code exists.

## 8. Retirement

`scripts/doc_archive_gate.sh` is deleted one release after the port lands, in the
same commit that moves `tool_state` to `retired`.

Before that, all of:

- the §6 differential cover green, including the three negative controls;
- the port wired into a job that **decides**, satisfied by §3's settled option D:
  both implementations run as adjacent steps in `spec-roundtrip`, and the
  relocation of the reference's own step out of the banner job lands in the same
  commit as the port, not later. A port wired in beside a reference that still
  decides somewhere else is the state that made retirement incoherent;
- one release elapsed in state `oracle`, both implementations running adjacent;
- the §7 row-2 assertions carried in the port rather than in the reference, since
  deleting the reference otherwise deletes the instrument;
- `TOOL-ORACLE-1` satisfied for this port.

**Retirement is coherent under option D and would not have been under C.** Under
C the reference stays in the banner job, so deleting it removes the gate rather
than the duplicate; under D both implementations sit in one job and deleting the
reference leaves the port deciding in the same place. The precondition that
carries this is the relocation, so if the relocation is ever reverted, retirement
must be reconsidered rather than assumed.

## 9. Decisions taken

**One was put to the user and is settled; one remains open.** The RFC-first
workflow exists because TOOL-RFC-001 made three of its four calls at the keyboard
and reported them afterwards, and D1 is exactly the class of call that would have
been made that way.

**D1. Distribution. SETTLED as option D, user adjudication 2026-08-09.** §3
measures that the published image cannot build a port (no GHC, no Stack in the
runtime stage), so P1 clearing did not resolve 001's deviation as 001 predicted.
DRIFT-DOC-3 relocates wholesale into `spec-roundtrip` with both implementations
adjacent. The cost is accepted knowingly and is enumerated in §3: the fast job
drops from four gates to three, time-to-signal for a one-line frontmatter mistake
goes from about 25 seconds to about 17 minutes, and a gate that needed only bash
and awk now sits behind a Haskell build. The alternative that preserved the fast
signal (option C) was rejected because it makes §8 unreachable, and the campaign
does not get to keep a port whose reference can never be deleted. The campaign's
distribution sentence still needs amending to distinguish shipping a compiler
from shipping a compiled port; that is `language-team`'s call and is owed.

**D2. Where the fixture expected counts live after retirement. SETTLED as "the
port carries them", user adjudication 2026-08-09.** The port hardcodes `4` and
`4` as its own assertions rather than deriving them by counting the fixture
directory. Deriving them would make the self-test agree with whatever the
fixtures happen to be, so deleting a fixture would lower both the expected and
the actual count together and the cell would stay green: that is cell 8's whole
point, and a self-test that cannot notice its own corpus shrinking is the
vacuous-pass shape §7 exists to reject.

**The consequence is a forcing function and it is deliberate.** Adding a
legitimate fifth fixture now requires editing the port, so the count cannot grow
silently and a reviewer sees the change in the diff. That is the same bargain the
reference already makes with `UNGATED_BOUND`, which "may shrink and never grows
silently", so the port inherits the reference's own discipline rather than
inventing one. The cost is that the two numbers live in two places until
retirement, and they are asserted against each other by §6 cells 3, 4, 6, 7 and 8
for as long as both implementations run.

**Settled by the porter, and a reader could reasonably differ.** The stray-
declaration branch is implemented via the `RErr` probe rather than skipped:
`scripts/doc-archive-fixtures/fail/professor-reviews/stray-declaration.md`
exercises it, so skipping it would fail criterion 4
and produce a port that is not the reference. Both NOTE-line forms are
implemented rather than only the at-the-bound one, because the under-bound form
fires the moment anyone pays down the debt and a port missing it diverges on the
next tree, not on this one.

**Deliberately not built.** No change to the ungated bound, the vocabulary, or
the opt-in design: a port reproduces its reference, and all three are the
reference's policy. No fix to the reference's blind spot for a `.md` sitting
directly under `docs/archive/` rather than in a subdirectory (`research-track.md`
today, which declares nothing): the shell's `"$root"/*/` glob matches directories
only, so such a file is never scanned. The port reproduces that blind spot rather
than improving on it, and improving on it is a change to DRIFT-DOC-3 that belongs
in its own commit against the reference first.

**Found while probing §4 and routed OUT of this RFC**, because it is compiler-side
and not the port's: `llmll run` cannot run a `:mode console` program at all. It
exits 1, produces zero stdout, writes no diagnostic, and records only an event-log
header with no steps, while the identical program built to a binary exits 0 and
works. Confirmed on two independent programs. Separately, its advertised
"Arguments passed through to the program" intercepts flag-shaped arguments
and answers ``Invalid option `--root'`` unless a `--` separator is used. Both want a
roadmap row of their own and neither blocks this port, which builds to a binary
like every other port in the campaign.
