---
name: tool-rfc-005-doc-path-lint
title: "TOOL-RFC-005: the prose path-citation lint, in LLMLL"
status: "Rev 5, PORTED, state RETIRED as of v0.14.99 on 2026-08-12, one release after the port landed at v0.14.97, which is the campaign's settled rule. `scripts/doc_path_lint.py` IS DELETED and so is `scripts/doc_path_lint_cover.py`: the cover pinned `REF = scripts/doc_path_lint.py` and diffed the two implementations, so it could not outlive its reference, and §6 said as much before the fact. THE PORT NOW RUNS UNGRADED, and that is the accepted trade rather than an oversight. THE DELETION BROKE 13 CITATIONS IN 6 FILES, measured by moving the reference aside and rerunning the lint BEFORE deleting anything, which is a step §8's precondition list did not ask for and should have. Two were present-tense and now name the port; five ALLOW entries carry the rest, all past-tense records of what the reference measured while it existed. THE LAST DIFFERENTIAL MEASUREMENT WAS TAKEN AT THE MOMENT OF DELETION: reference and port both report 977 citations in 173 living files, all resolve. ONE STALE RECORD FELL OUT OF THE RETIREMENT and is corrected here: `version-gate.yml` claimed in two places that `test_clean_on_live_repo` still guarded the fast job, and that test was deleted on 2026-08-11, so the workflow advertised a merge block that did not exist. Rev 4 and earlier, below, record how the port was graded while a grader existed. Rev 4, PORTED, state ORACLE. Both implementations ran as adjacent steps in spec-roundtrip and run 31439956284 is GREEN (18m12s), which is what made `oracle` a measurement rather than a claim. The port step costs 148s, against 14s for 004's port, because it verifies the core, builds, runs the 22-cell cover and then the live gate. THE COVER IS SHOWN TO DISCRIMINATE, not merely to pass: run against a port whose HIST_LINE uses the variant-list approximation, cell 9 FAILS while 7 and 8 pass; run against a port with no site/ filter, cell 13 FAILS on both the finding and the scanned-file count. Two cells are therefore known to fail; the other twenty are not individually shown to, and §6 says so. MEASURED END TO END: the port's output is BYTE-IDENTICAL to the reference's on the unmutated tree and on cell 1's mutant, from the first report line onward, and `--strict` exits 1 against findings where a plain run exits 0, matching STRICT=1. THE LIVE CORPUS EARNED ITS §7 ROW ON THE FIRST RUN: it reported 20 findings against the reference's 0, all twenty an S3 label case caused by handing the label lookup a body whose link targets had already been blanked, while the other 939 citations agreed exactly. A spot check would have passed. Two things the run established that no reading would have: console mode emits ONE BLANK LINE PER STEP, 177 of them before the report, so a cover cannot compare raw stdout; and computing the two expensive suppressors eagerly ran past two minutes, so the port defers them exactly as the reference's short-circuit `or` does. REV 1 CORRECTS THREE THINGS THE FIRST DRAFT GOT WRONG, all found by building rather than by re-reading. (i) §4 and §5 said a character-level scanner was forced; it is not. Splitting the body on the citation's own delimiter recovers what the capture group would have, and each segment is validated by one regex-match: measured exact against the reference at 955 citations over 172 files, zero disagreements. Two plausible parity-based versions of that split are WRONG and are tabled in §5. (ii) Cover cell 3 graded nothing, because it used an unbackticked link target, which is not a citation under PATH at all; it now uses a backticked target. (iii) §7 gains a second in-principle-invisible rule: the LINK substitution is a measured no-op on the live corpus, 955 citations with and without it. Written RFC-first, before any port code. THE SUBJECT IS ADVISORY AND EXITS 0 BY DESIGN, so a differential cover comparing exit codes grades nothing and §6 compares STDOUT TEXT instead. THE LIVE CORPUS IS NOT VACUOUS, and this RFC corrects the expectation it inherited from TOOL-RFC-004: measured 2026-08-10, all four exemption classes are live-exercised, each the SOLE rescuer of 13 to 19 citations, and the historical-file skip is worth 268; so the SUPPRESSION half has a live instrument and only the REPORTING half is fixture-only, because the corpus yields zero findings. THREE decisions settled by user adjudication 2026-08-10: D1 distribution, D2 existence by `git ls-files` membership, and D3 `regex-match` over a hand-rolled scanner. D3 REVERSES THE PRECEDENT SET BY `versiongate.llmll:25` AND `shape.llmll:26`, and it reverses it on a measurement: both recognizer shapes report `body-fallback`, a control reports `body-faithful`, so the verified tier those comments were protecting is not available to this function either way. `HIST_LINE` is written as per-letter bracket classes, which is exact case-insensitivity; the variant-list approximation is forbidden and cover cell 9 is what forbids it. The campaign's distribution sentence is AMENDED here rather than owed a third time. Three findings routed out: `shape.llmll:26` claims `^N\\d+$` ports verbatim and it does not, `llmll check` passes an unknown function at exit 0, and DONE-TYPE-1 fires on every console program built for this port."
date: 2026-08-10
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, language-team, user]
tool_state: retired
subject_script: scripts/doc_path_lint.py
port_module: tools/doc-path-lint/pathlint.llmll
---

# TOOL-RFC-005: the prose path-citation lint, in LLMLL

## 1. Subject

`scripts/doc_path_lint.py`, **132 code lines** of 180 total (excluding comments
and blanks, measured 2026-08-10, and agreeing with the campaign's §2 scope
table). It was DRIFT-DOC-4.

**The subject is DELETED as of v0.14.99**, per §8. It is cited throughout this
document in the past tense, because this document is the record of porting it,
and an `ALLOW` entry in the port records that judgement. Read it at
`git show v0.14.98:scripts/doc_path_lint.py`. DRIFT-DOC-4 is now
[`tools/doc-path-lint/pathlint.llmll`](../../tools/doc-path-lint/pathlint.llmll)
and nothing else.

**What it decides: nothing, and that is the defining fact of this port.** The
function ends `return 1 if os.environ.get('STRICT') else 0`, and the module
docstring argues at length that it must stay that way. One class of input has no
truth value for it:

> COUNTERFACTUAL PATHS. A rationale legitimately names a location that does not
> exist, and its non-existence is the point of the sentence.

A gate that can be wrong about correct input teaches people to write worse prose
to appease it, so this one reports and exits 0. Every other gate in the campaign
asserts something with a definite truth value; this one asserts a
recommendation. The consequence runs through §6 and §7: **a cover that compares
exit codes compares two constants**, and the port's obligation is to reproduce
*text*, not a verdict.

**What it lints.** Bare-backtick path citations in prose, `docs/design/foo.md`,
which ordinary Markdown link checkers do not follow because they are not links.
Measured on the live tree: 947 citations across 171 living files, all resolving.

**Where CI invoked it, and where it runs now.**
[`version-gate.yml`](../../.github/workflows/version-gate.yml). It ran in the
fast banner job, which was then named `C1-C4 banner / schema + DRIFT-DOC-4 +
pytest`. **As of this port both implementations run in `spec-roundtrip`**, per
§3, and the banner job was renamed in the same commit: a display name
advertising a gate the job does not run is the stale record TOOL-RFC-004 filed
against this very file.

**The job is the whole of §3 and naming it wrong is TOOL-RFC-001's recorded
mistake.** The banner job has **no Haskell toolchain by design**, stated in the
workflow's own header ("No Stack: no gate in this job has a compiler
dependency"), and its budget is "fast (<1 min)". That is why the port could not
stay there.

**What kind of gate it is, because it bounds what §7 can claim.** Unlike
DRIFT-CI-1 and DRIFT-DOC-3, which compare two records maintained inside the
repository, this gate compares prose against the **filesystem**, which is an
oracle neither record controls. It can therefore detect a citation that both the
author and the reviewer believed correct. What it cannot do is decide the
counterfactual class, and that is a property of the question rather than of the
implementation.

## 2. Criteria

**The reference has no failure order, because it has no failures.** It has one
scan, one summary line, and two mutually exclusive tails. What it does have is a
**per-citation suppression order**, which is short-circuit (`or`-chained at
`:153-157`, then a separate check at `:159-161`) and which the port owes exactly,
because two suppressors firing on one citation are indistinguishable in the
output while their absence is not.

**Stage 1, file selection.** `git ls-files '*.md'` (`:133`), then:

| # | Rule | Source |
|---|---|---|
| F1 | drop paths starting `site/` or `node_modules/` | `:135` |
| F2 | drop `CHANGELOG.md`, any path containing `/runs/` or `/findings/`, any path matching `/postmortem-`, any path starting `docs/archive/` | `historical_file`, `:124-129` |

F2 is the exclusion the docstring calls "the big one: it is the difference
between a ~450-item problem and a ~50-item one".

**Stage 2, per file.** Strip fenced code blocks (`FENCE`, `:63`). Build the
resolving-label set: every `[`p`](target)` whose **target** resolves relative to
the file's directory contributes `p` (`LABEL`, `:146-147`). Then substitute every
`](...)` with `]()` before scanning (`LINK`, `:148`), so a link's target is never
itself read as a citation.

**Stage 3, per candidate.** `PATH` (`:61`) matches a backticked path ending in
one of `md hs llmll json sh yaml yml py cabal txt`. A candidate with no `/` is
skipped **before** it is counted (`:149-150`), so the reported citation count
excludes bare filenames. Everything else increments `cites`, then runs the
suppression order:

| # | Suppressor | Source |
|---|---|---|
| S1 | `os.path.exists(p)`, from the repo root | `:153` |
| S2 | `os.path.exists(normpath(join(dirname(f), p)))`, relative to the citing file | `:154` |
| S3 | `p` is in the resolving-label set | `:155` |
| S4 | `PLACEHOLDER` matches: `NN`, `<`, `\bfoo\b`, `Mylib`, `cell_`, `turn_`, `...` | `:156`, `:65` |
| S5 | `(f, p)` is in `ALLOW`, 14 entries, each carrying a stated reason | `:157`, `:73-121` |
| S6 | the **first** line of the file containing `` `p` `` matches `HIST_LINE`, case-insensitively: `**DONE**`, `moved to`, `relocat`, `formerly`, `previously`, `old path`, `archived to`, `removed 20`, `deleted 20`, `migrated from` | `:159-161`, `:66-68` |

**Message text**, quoted because a cover that compares output needs it written
somewhere that is not the reference:

```
DRIFT-DOC-4 (advisory): {cites} prose path citations in {scanned} living files
DRIFT-DOC-4: all resolve.
```

and, on the reporting tail:

```
DRIFT-DOC-4: {n} do not resolve, in {k} file(s).

  {file}:{line}  `{path}`

Each is one of: a stale citation to fix, or a case ALLOW should record with a reason.
This lint does not fail the build; see the module docstring for why it must not.
```

Findings are grouped by file and the files are sorted (`:170`). All output is
**stdout**; nothing goes to stderr.

**Two properties of S6 that are easy to lose and are reproduced rather than
fixed.** The line lookup takes the **first** line containing the citation, so a
path cited twice in one file yields two findings that both report the first
line's number, and a historical marker on that first line suppresses **both**.
And the lookup runs over the **unstripped** lines, so it can land on a line
inside a fenced block. Neither is reachable on the live corpus, which reports
zero findings; both are §6 fixture territory and §9 records the decision to copy
them.

## 3. Distribution

**The campaign's distribution sentence is amended here.** This is the second port
to meet the same constraint, TOOL-RFC-004 §3 recorded that an amendment was owed
to `language-team`, and the user adjudicated on 2026-08-10 that it be written now
rather than owed a third time.

**The measurement, re-confirmed for this port.** Read off
[`Dockerfile`](../../Dockerfile): the runtime stage is `debian:bookworm-slim`
installing only `z3 libgmp10 zlib1g ca-certificates`, and it copies exactly two
executables, `llmll` and `fixpoint`. There is no GHC and no Stack. `llmll build`
emits a Haskell package and shells out to `stack build`, so inside the image it
has nothing to build with.

**The amendment.** Campaign §3 says "Jobs pull a published release image". That
sentence conflates two artifacts, and the conflation is what made TOOL-RFC-001
predict that its deviation would resolve when P1 cleared. It did not. The
amended form distinguishes them:

> The published release image delivers the **compiler**. It does not deliver a
> **compiled port**, and no mechanism publishes port binaries today. Until one
> does, a port runs only in a **toolchain-bearing job**. A gate whose reference
> lives in a toolchain-free job therefore relocates **wholesale**, reference and
> port together, rather than splitting across two jobs.

The wholesale clause is the part that carries consequence. Splitting is what
TOOL-RFC-001 did, and §8 cannot delete a reference that is the only thing running
in the job that matters.

**Placement for this port: relocate DRIFT-DOC-4 wholesale into
`spec-roundtrip`**, both implementations as adjacent steps. That is 003's and
004's arrangement, and it is what the amended sentence licenses.

**What it costs, stated here rather than discovered later.**

1. **The fast job loses its last doc gate.** After 004 moved DRIFT-DOC-3 out, the
   banner job carries C1-C4, DRIFT-DOC-4 and the pytest suite. After this move it
   carries C1-C4 and pytest, and answers no documentation question at all.
2. **Time-to-signal goes from about 25 seconds to about 17 minutes**, on 004's
   measurement of run `31332324160`.
3. **A gate needing only Python acquires a Haskell build as a dependency**, which
   is `SKIP-SILENT-1`'s neighbourhood. The mitigation is that the job fails
   loudly rather than reporting green, so the step must not be made conditional.

**Point 2 costs less here than it did at 004, and the reason is worth stating
plainly.** DRIFT-DOC-3 blocks a merge, so delaying it delays a decision.
DRIFT-DOC-4 decides nothing. Delaying an advisory report moves *when a reader
sees a suggestion*, and the docstring's claim for its value ("at review time, in
the diff") survives in the job log. Nobody is blocked either way, before or
after.

**The option 004 rejected does not fail here for 004's reason, and it still
fails.** Option C left the reference deciding in the fast job, which made
retirement incoherent. That objection is vacuous for an advisory gate: this
reference decides nothing, so leaving it in place leaves nothing deciding. C
fails on the amended sentence instead, which forbids the split, and on §8, which
would delete the fast job's only prose-path report as a side effect of retiring a
port that runs elsewhere.

## 4. Feasibility

Worked from the reference's behaviour and, wherever the answer was not obvious,
from **building and running a probe** rather than reading the capability table.
Every row marked *measured* below was executed against `llmll 0.14.96` at
`3924bb3`, built from the tree rather than taken from `stack exec` (a stale
0.14.95 binary was on `PATH` at the start of this session and was rebuilt first).

| Needs | LLMLL | Note |
|---|---|---|
| Enumerate tracked Markdown files | **available**, `wasi.proc.run` | The reference already shells to `git ls-files '*.md'`, so the port inherits the invocation rather than inventing one |
| Filter by path prefix and by substring | **available**, `string-contains` and `string-slice` | F1 and F2 are prefix and substring tests over the file list |
| Read a file's text | **available**, `wasi.fs.read` | **Measured**: `RText` on a present path |
| Decide whether a cited path EXISTS | **gap** | `os.path.exists` has no equivalent. Two mechanisms measured, see §5 and D2. **Measured**: `wasi.fs.read` on a missing path answers `RErr` with `openFile: does not exist`, so existence-by-attempt works; it costs a full READ where the reference costs a stat, and the live corpus would move **77.0 MB across ~1900 calls** in a job budgeted under a minute |
| Test membership in a list | **available**, `list-contains` | The mechanism D2 settled on |
| Normalize `a/b/../c` | **gap, hand-rolled** | No `normpath`. **Measured**: 58 of 947 live citations contain `..`, so this is exercised on every real run and cannot be deferred |
| Extract every backticked path from a document | **gap, and it costs one `string-split`** | `regex-match : (string, string) -> bool` returns a **bool** and captures nothing, so it cannot locate a citation whatever D3 decides. **Corrected after building it**: this does NOT force a character-level scanner. A citation is backtick-delimited by construction, so splitting the body on a backtick recovers exactly the set the capture would have returned, and each segment is then validated by one `regex-match`. **Measured against the reference over the whole live corpus: 955 citations, 172 files, ZERO disagreements** |
| Test a candidate against `PLACEHOLDER` | **available**, `regex-match`, verbatim | **Measured, built and run**: `"NN|<|\\bfoo\\b|Mylib|cell_|turn_|\\.\\.\\."` gives T on `postmortem-NNN.md`, T on `design/foo.md`, T on `a/turn_3/x.json`, and F on a fourth path carrying no placeholder token. The LLMLL string literal carries the backslash through to TDFA, and TDFA supports `\b` |
| Test a line against `HIST_LINE`, case-insensitively | **gap** | **Measured**: `regex-match` lowers to `Text.Regex.TDFA`, which rejects inline `(?i)` (returns False), and there is no lowercase builtin. Exact case-insensitivity IS expressible as per-letter bracket classes (`[Pp][Rr]...`, measured working). Live relevance measured: one alternative genuinely needs the fold, `previously` matching `Previously` twice |
| Split content into lines | **available**, `string-split` on `"\n"` | Empty-separator decomposition is absent (`SPLIT-EMPTY-1`) and is not needed |
| Index a string by character | **available and NOT needed** | **Measured, built and run**: `string-char-at "abc" 1` is `"b"`, `string-slice "abcdef" 1 3` is `"bc"` (end-exclusive). Recorded because the first design assumed a character fold like `versiongate.llmll`'s `leading-run`, and the split-plus-`regex-match` scanner removed the need for one. `string-slice` is still used, for the prefix tests in F1 |
| Sort findings by file | **available by construction** | `git ls-files` emits sorted output and findings accumulate in file order, so no sort builtin is needed |
| Adjudicate the suppression order | **available AND provable** | **Measured**: a `def` over six bools verifies `body-faithful` and SAFE, and dropping one clause is **REFUTED at constraint #0**. This is §7's third instrument |
| Recognize which bytes are a citation | **available, not contractable** | A bool-valued body over string comparison falls back (`STRLIT-BODY-1`). **Measured**: the `string-contains` recognizer and the `regex-match` recognizer BOTH report `body-fallback`, while a control (`(def double [x: int] -> int (post (= result (+ x x))) (+ x x))`) reports `body-faithful`, so the instrument discriminates and the fallback is a finding rather than an artifact |
| Read `STRICT` from the environment | **gap** | No `wasi.env.*` exists; the sixteen `wasi.*` names were enumerated from the compiler. **Measured**: `wasi.proc.args` delivers `--strict extra` as `argc=2` to a built binary with no `--` separator, so argv carries the flag |
| Exit with a distinct status | **available**, `console` mode | `:mode cli` performs no `Command` (`MODE-CLI-1`), so the port is a stdin-driven step machine like every other in this campaign |

**The split scanner had two plausible wrong versions and both were caught by
measurement rather than by reading.** The obvious implementation of "split on the
delimiter" is to keep the segments that are *inside* backticks, and that is
exactly the one that fails:

| Model | Result against the reference |
|---|---|
| Odd-index segments, per line | Wrong. A backtick span may cross a newline, which desyncs the parity for the rest of that line. Missed one citation in `docs/design/finding-arg-position-false-safe.md` |
| Odd-index segments, whole body | Much worse. A single unbalanced backtick desyncs everything after it: **16 citations where the reference finds 94**, in `docs/compiler-team-roadmap.md` |
| **Every segment, no parity** | **Exact: 955 citations, 172 files, zero disagreements** |

Testing every segment has no parity to lose, and it is what the reference's regex
effectively does: on a failed match the regex advances one character and may
re-enter at a backtick a parity model has already spent. **All three models agree
on almost every file**, which is why the instrument was a corpus-wide comparison
and why a spot check would have passed.

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| `os.path.exists` has no equivalent; nothing answers "is there a file here" without moving its bytes | **SHAPES** | `FS-EXISTS-1`, filed 2026-08-10 | A direct existence predicate per citation, as the reference writes it. Instead the port enumerates the tree ONCE with `git ls-files` and tests `list-contains`, per D2. Deliberately **not** folded into `FS-STAT-1`, which is about an artifact's AGE for `liveness.advancing` and would answer a different question; collapsing two causes into one row is what produced a row that was wrong for a release at `ALIAS-LOWER-1` |
| `regex-match` returns `bool`, so no capture and no scan | **SHAPES** | `REGEX-CAPTURE-1`, filed 2026-08-10 | `PATH` and `LABEL` as two `finditer` calls, the way the reference writes them. Instead the port splits the body on the citation's own delimiter and validates each segment with one `regex-match`. **The gap is real and its cost is one `string-split`, not a character scanner**, which is a correction to this row's first revision: the delimiter recovers what the capture group would have. The cost that remains is that the split model had to be **measured** against the reference rather than read off the regex, and two plausible versions of it are wrong (see the note below) |
| No case-insensitive matching: TDFA rejects `(?i)` and no lowercase builtin exists | **SHAPES** | `REGEX-CASE-1`, filed 2026-08-10 | `HIST_LINE` as one `re.I` call. Instead the port writes **per-letter bracket classes** (`[Pp][Rr]...`), settled at D3: exact rather than approximate, and verbose. Measured live relevance: `previously` matches `Previously` twice on the current tree, so the gap fires on real prose rather than only on a fixture |
| No path normalization for `..` | **SHAPES** | `PATH-NORM-1`, filed 2026-08-10 | `os.path.normpath`. Instead the port folds the segment list, dropping a segment per `..`. Measured: 58 of 947 live citations need it, so it is on the main path and not an edge case |
| `:mode cli` performs no `Command` and yields no exit status | **SHAPES** | `MODE-CLI-1` | A straight-line program: scan, print, exit. Instead the port is a stdin-driven step machine with an explicit control state, which is the campaign's single largest line-count multiplier |
| A bool-valued body whose result is a string comparison falls back, so the citation recognizer carries no proof | **SHAPES** | `STRLIT-BODY-1` | The recognizer and the adjudicator would both be verified. Instead only the adjudicator is contractable, which is what forces §7's instrument split. **Measured here**: the fallback is identical for a hand-rolled and a regex recognizer, which is what makes D3's tier cost zero |
| `string-split` with an empty separator does not terminate | **COSMETIC** | `SPLIT-EMPTY-1` | Nothing follows: this gate splits on `"\n"`, and per-character work goes through `string-char-at`, which is measured working |
| No recursive directory walk | **COSMETIC** | `FS-WALK-1` | Nothing follows: `git ls-files` supplies the whole file list flat, which is the reference's own mechanism |
| No environment access | **COSMETIC** | unfiled, and the campaign's census already carries this row | **The campaign's disposition was tested here and it HOLDS.** `wasi.proc.args` delivers a flag-shaped argument intact, measured on a built binary. Nothing is lost and the row does not move. The *invocation* changes, `STRICT=1 cmd` becoming `cmd --strict`, and that is a porting decision recorded at D4 with a §6 cell, not a language gap |

**Four gaps are marked unfiled and owed.** That is a larger number than any
previous port has produced, and it is the census this campaign exists to
generate rather than a reason to defer. The campaign's §5 table carries them.

**The split scanner's two wrong versions are tabled at the end of §4**, with the
rest of the feasibility measurements. They are not repeated here because this
section's tables are parsed as gap rows by
[`test_tool_rfc_standard.py`](../../scripts/tests/test_tool_rfc_standard.py),
which reads every row under this heading as a gap and rejects a two-column one.

## 6. Differential plan

A cover in the shape of [`doc_archive_cover.py`](../../scripts/doc_archive_cover.py),
taking `--gate` (the port binary) and running the reference from a scratch copy,
**both implementations in the same scrubbed environment**, because 003's cover
found an `llmll` on `PATH` that its reference could not see and was then
comparing two worlds rather than two implementations.

**Exit codes grade nothing here and the cover must not compare them.** The
reference exits 0 on every input that is not both STRICT-enabled and
finding-bearing, and measured on the live tree even `STRICT=1` exits 0, because
the zero-findings tail returns at `:168` before `STRICT` is ever read. **The
cover compares stdout text**: the summary line, the finding lines with their
`file:line  \`path\`` shape, and the epilogue.

**Mutations must ADD findings, not remove them**, since the corpus reports none.
Every mutant is asserted to produce the SAME non-empty finding set under both
implementations before their answers are compared, and every negative control
requires both to report **zero findings** and the **same counts**.

| Cell | Mutation | Criterion | Expect |
|---|---|---|---|
| 1 | add a doc citing a path that does not exist | S1, S2 | both report 1 finding, same file, line and path |
| 2 | cite the same missing path inside a fenced code block | stage 2, FENCE | both report 0; a port that forgets fence stripping reports 1 |
| 3 | put a missing path in a link target **wrapped in backticks**, ``](`missing/x.md`)`` | stage 2, LINK | both report 0. **Corrected: the first version of this cell used an unbackticked target and graded nothing**, because an unbackticked path is not a citation under `PATH` at all, so a port with no LINK handling passes it too. Measured: the live corpus contains **zero** links with a backticked target, so this rule is invisible on the tree and this cell is its only instrument |
| 4 | add [`old/x.md`](INDEX.md), a label whose target resolves | S3 | both report 0 |
| 5 | the same label with a target that does NOT resolve | S3 | both report 1; the label set requires a RESOLVING target and this is the cell that proves it |
| 6 | cite `postmortem-NNN.md` | S4 | both report 0 |
| 7 | cite a missing path on a line reading "moved to" | S6 | both report 0 |
| 8 | same line, "Previously" | S6 | both report 0; **this cell fails a port with no case handling at all** |
| 9 | same line, "PREVIOUSLY" | S6 | both report 0; **this cell fails a port that matches only a literal-plus-capitalized variant list**, which is the approximation D3 forbids. It is the cell that holds the per-letter bracket classes honest |
| 10 | add a missing citation to `CHANGELOG.md` | F2 | both report 0 |
| 11 | add one to a new file under `docs/archive/` | F2 | both report 0 |
| 12 | add one to a new file under a `/runs/` directory | F2 | both report 0 |
| 13 | add one to `site/index.md` | F1 | both report 0 **and the scanned-file count is unchanged**; this is the ONLY cell that can see F1, because the six filtered files contain zero citations between them |
| 14 | cite `../compiler-team-roadmap.md` from a file in `docs/design/` | S2 | both report 0; resolves only relative to the citing file |
| 15 | cite a `../`-prefixed path that does not exist, from a file in `docs/design/` | S2 | both report 1; the `..` fold must resolve and then fail, not fail to parse |
| 16 | remove one entry from `ALLOW` in **both** implementations | S5 | both report 1 |
| 17 | cell 1's tree, with STRICT enabled on both | exit | both exit **1**; the only cell in which the exit code carries information |
| 18 | cell 1's tree, STRICT absent | exit | both exit **0** while reporting 1 finding |
| 19 | cite a missing path TWICE in one file, second occurrence 40 lines later | S6 quirk | both report 2 findings **both carrying the FIRST line number**; the reference quirk is reproduced, not fixed |
| **NC-1** | unmutated tree | all | **both PASS**, `all resolve.`, exit 0, and **the same two counts as each other**. The counts are compared between implementations, never pinned to a literal: they rise with every document added, and a literal here would be a stale record by the next commit |
| **NC-2** | add a doc citing a path that DOES resolve | S1 | **both PASS**, citation count rises by exactly 1, findings stay 0 |
| **NC-3** | add a living `.md` with no citations at all | stage 1 | **both PASS**, scanned count rises by exactly 1, citation count unchanged |

**The cover cannot compare raw stdout, and this is a property of `console` mode
rather than of either implementation.** Measured on the first end-to-end run: the
port emitted **177 blank lines before its report**, one per step of the
stdin-driven loop, where the reference emits none. The cover therefore compares
from the first `DRIFT-DOC-4` line onward. Two runs have been checked that way and
both are **byte-identical** to the reference: the unmutated tree (NC-1) and cell
1's mutant. The port's own report text carries no trailing newline, because the
harness supplies one and an unadjusted port ends a line short of matching.

Cells 8, 9, 13 and 19 are the ones that matter most, and each of them is
invisible on the live corpus. TOOL-ENCODING-1 is why the three negative controls
are written as counts rather than as "both pass": there, every mutation cell
agreed while both implementations failed identically, and only a control
requiring both to succeed on an unmutated tree could tell "the two agree" from
"neither can read the corpus".

**Run the negative control first, then read which assertions it never reached.**
Two cover cells have been found wrong by construction this way, at 004 and again
at `REGEX-LOWER-1`, in both cases because the gate failed early and left later
assertions unexecuted.

### The cover's own negative control

**The battery passed 22 of 22 on its first run, which is exactly the state this
campaign has twice been wrong in.** A battery that has never been shown to fail
is not evidence. So the cover was run against two deliberately broken ports, each
built to defeat one cell that no corpus state can reach. `--only` exists for
this.

| Broken port | Result |
|---|---|
| `HIST_LINE` written as the literal-plus-capitalized variant list D3 forbids | **Cell 9 FAILS** (port reports 1 finding, reference 0). Cells 7 and 8 still pass, which is correct: the variant list handles `moved to` and `Previously`, and only all-caps exposes it. So cell 9 is not redundant with its neighbours and D3's claim that it forbids the shortcut is measured |
| The `site/` and `node_modules/` filter removed | **Cell 13 FAILS** on two axes at once: a finding reported against the file the cell adds under `site/`, and the scanned-file count moving from 172 to 179 |

Both mutants are one-line changes to a copy of the port, built and run through
the real cover. Neither is committed. **What this establishes is narrow and worth
stating as such**: two cells are now known to discriminate. The other twenty are
not individually shown to fail, and a cell that cannot fail is the defect this
subsection exists to catch.

## 7. Verification

**This section corrects an expectation carried over from TOOL-RFC-004.** At 004
the live corpus declared one disposition of four and contained none of the four
violation classes, so a live green run graded about a twentieth of the specified
behaviour and the fixtures carried everything. The expectation for 005 was that
zero findings meant the same thing here. **Measured 2026-08-10, it does not.**

| Class | Citations it is the SOLE rescuer of |
|---|---|
| S3 resolving labels | 19 |
| S4 `PLACEHOLDER` | 13 |
| S5 `ALLOW` | 13 |
| S6 `HIST_LINE` | 13 |
| F2 historical files | 268 |
| F1 `site/`, `node_modules/` | **0** |
| The LINK substitution | **0** |

Of 947 citations, 737 resolve from the repo root, 151 resolve **only** relative
to the citing file, 58 contain `..`, and 59 do not resolve by path at all and are
carried by the four exemption classes. So a port that drops any one of S3 to S6
turns "all resolve" into 13 to 19 findings **on the unmutated tree**, and a port
that drops F2 reports 268. The suppression half has a live instrument.

What the live corpus cannot reach is the **reporting** half. Zero findings means
the finding loop, the line-number lookup, the file grouping, the epilogue and the
`STRICT` branch never execute on a real run.

**Two rules are invisible in principle, not merely today, and each has exactly
one instrument.** F1's six filtered files contain **zero** citations between
them, so omitting the filter changes only the scanned-file count in the summary
line; cell 13 is its only instrument. The LINK substitution is a **measured
no-op**: 955 citations with it and 955 without, because a link target is not
backticked and therefore is not a citation under `PATH` in the first place. It
fires only on a backticked target, of which the corpus has none; cell 3 is its
only instrument, and the first version of that cell would not have caught its
absence either.

| Instrument | Catches | Blind to | Survives §8? |
|---|---|---|---|
| The §6 differential cover | Any divergence from the reference under mutation, including message text, the finding-line shape and the suppression order | A defect the port and the reference SHARE, which is the likely class when the port is written by reading the reference; and it cannot run at all once the reference is gone | **No** |
| The live corpus, as a suppression oracle. **The assertion is `findings == 0`, not a pinned citation count** | A dropped or over-broad exemption class, immediately and without any fixture: S3 to S6 each move the finding count off zero and F2 moves it by 268, so the zero is doing real work rather than describing an empty scan | The entire reporting half, which never executes; F1, which no corpus state can exercise; and any defect that suppresses MORE rather than less, since over-suppression also reports zero | **Yes**, it reads the tree, not the reference |
| A contract on the adjudicator (`six evidence flags -> report?`) with a refuting case | A misrouted suppression rule, referencing neither implementation. **Measured**: the body verifies `body-faithful` and SAFE, and dropping the `HIST_LINE` clause is **REFUTED at constraint #0** | The recognizer half entirely: which bytes are a citation, the regex dialect, the `..` fold. `STRLIT-BODY-1` makes that half uncontractable today | **Yes** |
| Fixtures for the reporting half | Output shape, line numbers, grouping, sorting, the epilogue, the `STRICT` exit, and cells 8, 9, 13 and 19 | Anything about the live corpus, which it never reads | **Yes**, a separate directory from the subject script |

**Row 2 was predicted to be a real instrument and then immediately was one.**
This section argued, before the port existed, that the live corpus grades the
suppression half rather than nothing. The first end-to-end run reported **20
findings where the reference reports 0**, and every one of the twenty was an S3
label case: the port had been handing its label lookup the body with link targets
already blanked, so no target could resolve. The other 939 citations agreed
exactly. That defect is invisible to a spot check, invisible to the citation
count, and invisible to any fixture that does not carry a link whose label is
also cited elsewhere; the live corpus caught it on the first run at zero
authoring cost. It is also the defect class §6 exists for, since the reference
and a from-scratch port would not plausibly share it.

**The four fail differently and that is the point.** The cover compares two
implementations. The live corpus compares one implementation to a pinned count.
The contract compares a function to a specification. The fixtures compare output
to expected text. A defect shared by both implementations passes row 1 and is
caught by row 3 if it is in the adjudicator. A dropped exemption passes row 3 and
is caught by row 2 on the next CI run. A wrong finding format passes rows 2 and 3
and is caught only by row 4.

**Three things this section does NOT claim.** Row 2 is blind to
over-suppression, which reports zero exactly as correctness does, so it is a
one-directional instrument and cells 1, 5, 15 and 16 are what cover the other
direction. The contract covers the adjudicator only, so the **recognizer half has
exactly one instrument** (row 4), which is the absence §7 permits a row to
record, tagged `STRLIT-BODY-1`. And `--strict-verified-core` is **not** listed:
`versiongate.llmll` passes it today with zero body-faithful functions, so the
pass is vacuous, and this port's recognizer is measured to fall back under D3's
settled choice exactly as it would have under the alternative.

**The debt this section creates.** The 14-entry `ALLOW` table and row 4's
expected fixture text must live **in the port**, not in the reference, because §8
deletes the reference and takes both with it. `ALLOW` in particular is not
derivable: each entry is a human judgement that one specific citation is correct
despite not resolving, and regenerating it from the tree would make every
unresolved citation self-justifying. Settled at D5.

**Row 2 is deliberately NOT a pinned count.** Asserting "947 citations in 171
files" in the port would redden CI on the next document anyone writes, and the
number would be a stale record within a commit. The assertion is that findings
are **zero**, which is stable under document addition and is exactly as strong,
because the table above measures that zero to be the product of six live
suppression classes rather than an empty scan.

## 8. Retirement

**EXECUTED at v0.14.99 on 2026-08-12.** The port landed at v0.14.97, v0.14.98
shipped, so one release elapsed and the rule was satisfied.
`scripts/doc_path_lint.py` and `scripts/doc_path_lint_cover.py` are deleted, the
reference's CI step is gone, and `tool_state` is `retired`, all in one commit.
Every precondition below was met before the deletion.

**The precondition list was incomplete, and the retirement found the gap rather
than suffering it.** Nothing here asked what deleting the subject does to the
prose that cites it, which is the one question THIS gate is the instrument for.
Measured first, by moving the reference aside and rerunning the lint: **13
citations in 6 files stopped resolving.** Two were present tense and were
repointed at the port; five `ALLOW` entries carry the rest, each a past-tense
record of a measurement the reference took while it existed, which is the case
the table is for. Rewriting those to name the port would falsify them, because
the port did not take those measurements.

**A retirement rule for the campaign, and port 006 should carry it.** Before you
delete a subject, move it aside and run the gate. The citation breakage is
measurable in advance and free; discovering it from a red board afterwards is
neither.

**THE LAST DIFFERENTIAL MEASUREMENT WAS TAKEN AT THE MOMENT OF DELETION.**
Reference and port were run against the same tree with the `ALLOW` additions in
both, and both reported **977 prose path citations in 173 living files, all
resolve**. That is the final evidence the two agree, and it is the last one
obtainable, because the next paragraph is why.

**WHAT RETIREMENT COST, stated because §6 saw it coming.**
`doc_path_lint_cover.py` pinned `REF = "scripts/doc_path_lint.py"` at line 45
and diffed the two implementations under mutation. It could not outlive its
reference, so the 22-cell cover died with it. The port is now graded by nothing:
the live corpus reports zero findings, so the whole REPORTING half never
executes, and four cover cells tested rules no corpus state can reach. **A live
green run is not evidence that this port is correct.** §6 records that cells 9
and 13 were measured to discriminate, which is where a rebuilt grader starts.
The user took this trade knowingly on 2026-08-12, with the cost stated first.

**One stale record fell out of the work and is fixed in the same commit.**
`version-gate.yml` claimed in two places that `test_clean_on_live_repo` still
ran in the fast job and still kept it fail-closed. That test was deleted on
2026-08-11 with `test_doc_path_lint.py`. So the workflow advertised a merge
block that had not existed for a day. `docs/UPDATE-PROTOCOL.md` made the same
claim and is corrected too.

**This workflow file has now carried a claim about itself that stopped being
true twice.** TOOL-RFC-004 filed the first against its job display name, and
[`tool-ll-RESTART.md`](tool-ll-RESTART.md) §3 lists it among five such records. The pattern is stable enough to name: a person records a change in a
comment beside the code and does not change the places that advertise it. A
comment beside the code is not a record.

The preconditions, all met before the deletion:

- the §6 differential cover green, including the three negative controls, and its
  negative control run FIRST with the unreached assertions read off;
- the port wired into a job that runs it, satisfied by §3: both implementations
  as adjacent steps in `spec-roundtrip`, with DRIFT-DOC-4's own step leaving the
  banner job **in the same commit as the port**, not later;
- one release elapsed in state `oracle`, both implementations running adjacent;
- the `ALLOW` table carried in the port rather than in the reference, per D5,
  since deleting the reference otherwise deletes fourteen human judgements that
  nothing in the tree can regenerate;
- ~~an answer for the reference's pytest file~~ **ANSWERED and DONE
  2026-08-11: the user chose to delete the test, accepting the loss.** The file
  is gone, 18 tests with it, ahead of the reference's own deletion; see below
  for what that costs;
- **the job verifying `adjudicate.llmll` BEFORE `pathlint.llmll`**, which is an
  ordering constraint rather than a preference. Measured: with no sidecar
  present, `llmll check` on the port warns "Function `reports?` has an unproven
  contract (level: asserted). Your module inherits this trust gap", and the
  warning disappears once the core is verified. The sidecar is gitignored, as it
  is for the other three ports, so the trust is established by running verify in
  the job and not by anything in the repository. A port checked without that
  step silently drops to `asserted` on the one function §7 counts as proved;
- the reporting-half fixtures in place, since §6 dies with the reference and row
  4 is the only instrument that reaches that half at all.

**The word "decides" in the campaign's retirement rule does not apply to this
gate, and pretending otherwise would be the error.** The campaign requires a port
"wired into a job that decides". DRIFT-DOC-4 decides nothing and never will; its
docstring forbids promoting it. The condition this port satisfies instead is that
its output is **produced and readable in a job that runs on every push**, which
is what an advisory gate has in place of a verdict. Retiring a reference whose
port only ever ran locally would be the §10 failure mode, and that is the
property the condition is protecting.

**SOMETHING DOES DECIDE, AND IT IS NOT THE GATE. Found while wiring, and it is
the sharpest thing this RFC has to say about retirement.**
`test_doc_path_lint.py`, which lived under `scripts/tests/` until 2026-08-11,
runs the reference over the live tree and asserts `all resolve`. It is
**fail-closed**: move a file without updating the prose that names it and CI goes
red. So the merge-blocking property of DRIFT-DOC-4 has never lived in
DRIFT-DOC-4. It lives in a pytest test, in `scripts/tests/`, which campaign §2
deliberately places OUT of scope.

Three consequences, none of which were visible before the port was wired:

1. **§8 breaks that file.** All three of its tests bind to
   `scripts/doc_path_lint.py`, two of them by importing it as a module for its
   predicates. Deleting the reference deletes the only fail-closed check that
   prose citations resolve, and it does so as a side effect.
2. **The obvious repair does not fit the job.** Repointing the test at the port
   needs a built binary, and the test runs in the toolchain-free job by design.
   So the choice is to move the test, to drop it, or to keep a Python remnant of
   a retired reference, and each is a different answer to what the campaign is
   for.
3. **§1's "it decides nothing" is true of the script and false of the
   arrangement.** The RFC states it about the script throughout and that stays
   correct, but a reader deciding what may be deleted needs the arrangement.

**This is therefore a retirement precondition and not a footnote**: before
`scripts/doc_path_lint.py` is deleted, `test_doc_path_lint.py` must have an
answer, decided rather than discovered when CI reddens. It is routed to the user
because it is a scope question the campaign settled in the abstract and this is
its first concrete instance.

### The answer, taken 2026-08-11: delete the test

The user chose the second of three options: move the test to a job that has a
compiler, **delete it and accept the loss**, or keep a Python remnant of a
retired reference. The file `test_doc_path_lint.py` is deleted. The suite
goes from 197 to 179 passing.

**State plainly what that costs, because the point of this section was to make
it a decision instead of a surprise.** Nothing now blocks a broken prose
citation from reaching `main`. Both remaining checks are advisory by design and
exit 0 with findings: the reference at its own step, and the port at the step
after it. The `doc_path_lint.py` run in CI reports and does not decide, which is
what §1 said about the gate all along; the difference is that the arrangement no
longer has a decider hidden in `scripts/tests/`.

**Three smaller losses that were not the headline and are worth naming.** The
18 tests included the only automated check that every entry in the `ALLOW`
table carries a comment, which is the guard on the fourteen human judgements D5
requires the port to carry. They included the assertion that the reference exits
0, which is the advisory contract itself. And they included the unit coverage of
`historical_file`, `PLACEHOLDER` and the historical-line predicates, so the
reference now ships untested until it is deleted.

**The door that stays open.** The property can be restored without a Python
remnant by making the port's CI step fail on findings, which would put the
merge-block in the LLMLL implementation rather than beside it. That is a change
to when CI reddens and was not taken here.

## 9. Decisions taken

**Two settled by the user before any code exists, one open, and two taken by the
porter.** The RFC-first order exists because TOOL-RFC-001 made three of its four
calls at the keyboard and reported them afterwards.

**D1. Distribution. SETTLED by user adjudication 2026-08-10: amend the campaign
sentence now, then choose.** The amendment is written in §3 and distinguishes
shipping a compiler from shipping a compiled port. The placement it licenses is
the wholesale relocation of DRIFT-DOC-4 into `spec-roundtrip`, and the cost is
accepted knowingly: the fast job drops to C1-C4 plus pytest and answers no
documentation question, and an advisory report moves from about 25 seconds to
about 17 minutes. The cost is lower than 004's because a delayed suggestion
blocks nobody, and §3 says so rather than leaving the two cases to look alike.

**D2. The existence check. SETTLED by user adjudication 2026-08-10: one
`git ls-files` plus `list-contains`.** One IO call, against roughly 1900 calls
and 77.0 MB for existence-by-attempt in a job budgeted under a minute.

**The divergence this buys is measured, not assumed.** `git ls-files` answers
about the INDEX and `os.path.exists` answers about the FILESYSTEM. Measured on
this working tree, exactly **two** resolved paths differ, and **both are already
in the reference's `ALLOW` table**, carried there precisely because they exist in
a working tree and not in a fresh clone: a gitignored `.verified.json` and an
uncommitted run directory. On CI, which checks out fresh, the divergence is zero.

The residual risk is an untracked-but-present file that `ALLOW` does not carry:
the reference suppresses it and the port reports it. That is a real behavioural
difference, it is the port not being its reference, and §6 owes it a cell. It is
also the direction that fails safe, since the port over-reports in a gate that
cannot fail a build. **The asymmetry this removes is the reference's own**: it
already takes its file LIST from git and its RESOLUTION from the filesystem, so
D2 makes one mechanism answer both questions.

**D3. `regex-match` versus a hand-rolled scanner. SETTLED as `regex-match`, by
user adjudication 2026-08-10**, after the cost was measured rather than argued:

| | Hand-rolled | `regex-match` |
|---|---|---|
| `PATH` and `LABEL` extraction | hand-rolled | **hand-rolled either way**: `regex-match` returns `bool` and captures nothing |
| `PLACEHOLDER` | 6 `string-contains` plus a hand-rolled `\bfoo\b` boundary | ports **verbatim**, measured T/T/F/T on four real paths |
| `HIST_LINE` | a `to-lower` fold with no lowercase builtin, so 26 comparisons per character via `string-char-at`; or a variant list, which **cell 9 fails** | per-letter bracket classes, exact and verbose, measured working |
| Verified tier | `body-fallback` | `body-fallback` |
| Verified core | unaffected: `reports?` is `body-faithful` + SAFE either way | unaffected |

**The tier cost is zero and that is the measurement, not a prediction.** Both
recognizer shapes were built and verified; both report `body-fallback` under
`STRLIT-BODY-1`, while a control reports `body-faithful`, so the probe
discriminates. `LLMLL.md:326` puts `regex-match` in the boolean-builtin class and
`versiongate.llmll:25` and `shape.llmll:26` avoided it on that ground; the
measurement says the class costs nothing **here**, because the function that
would carry it is one the language already declines to prove.

**This decision reverses a precedent, and it reverses it on evidence rather than
on taste.** Two modules avoided `regex-match` and said so at the site, and **they
gave two different reasons, only one of which was ever about the tier.**

- `shape.llmll:26` cites the tier, and that reason is measured absent for a
  string recognizer: both shapes report `body-fallback`. Its narrower claim,
  that `validate.llmll`'s own proved functions would lose something, is not
  re-measured here and stands.
- `versiongate.llmll:25` cites `REGEX-LOWER-1`: a program calling `regex-match`
  did not build. **That reason expired at v0.14.96**, one release before this
  RFC, and the comment still asserted it in the present tense until this change
  corrected it. The scanner stays regardless, because rewriting a shipped
  oracle's scanner is a behaviour change owed its own cover run.

So the avoidance rested on one reason that is now false and one that does not
reach this port's recognizer. A third tool no longer inherits it by default.

**What the port commits to, stated so it can be checked.**

1. `PLACEHOLDER` is written as the reference's alternation, character for
   character, and cell 6 pins that it still fires.
2. `HIST_LINE` is written as **per-letter bracket classes**, which is exact
   case-insensitivity and not an approximation. The variant-list shortcut is
   forbidden, and cell 9 is what forbids it: a port matching only
   `previously|Previously` reports a finding on `PREVIOUSLY` where the reference
   reports none.
3. `PATH` and `LABEL` are still hand-rolled, since `regex-match` cannot capture.
   The port therefore carries **both** mechanisms, and that is a consequence of
   the decision rather than an inconsistency in it.

**The residual cost, accepted knowingly.** The port acquires a standing coupling
to TDFA's dialect agreeing with Python's `re`. It is measured for the two
patterns in use today and is **not** guaranteed for a pattern someone adds later:
this session found `\d` silently absent from TDFA while `\b` is present, and
found a comment in the tree that had assumed otherwise for a release. The
mitigation is that any new pattern is a diff to the port, and §6 owes a cell for
each alternation branch it adds.

**D4. `STRICT` moves from the environment to argv. Porter's call.** No `wasi.env.*`
exists, and `wasi.proc.args` was measured to deliver `--strict` intact to a built
binary. So `STRICT=1 python3 scripts/doc_path_lint.py` becomes
`pathlint --strict`. The port is not its reference at the invocation boundary and
cells 17 and 18 pin both halves. The campaign's "no env access is COSMETIC
because argv carries it" disposition is **tested and holds**; the row does not
move.

**D5. The `ALLOW` table and the fixture expectations are carried in the port.** Fourteen
entries, each with its stated reason, copied rather than derived, on 004's D2
precedent: deriving a self-test's expectations from the corpus makes it agree
with whatever the corpus becomes, and a self-test that cannot notice its own
table shrinking is the vacuous pass §7 rejects. The consequence is a forcing
function and it is deliberate: adding an `ALLOW` entry requires editing the port,
so a reviewer sees it in the diff. Both copies are asserted against each other by
cell 16 for as long as both implementations run.

**Deliberately not built.** No promotion to fail-closed: the docstring forbids it
until the counterfactual class is solved, and that is a language problem rather
than a scripting one. No change to `ALLOW`, to `PLACEHOLDER`, or to the extension
list; a port reproduces its reference. No fix to the two S6 quirks in §2 (the
first-line lookup and its unstripped-line search); both are reproduced, and cell
19 pins the first so that reproducing it stays a decision rather than an
accident.

**Found while probing §4 and routed OUT of this RFC**, because none of it is the
port's:

1. **`shape.llmll:26` is incorrect.** It states that `^C[1-6]$` and `^N\d+$`
   "port verbatim with no narrowing" because `regex-match` is a compiler builtin.
   **Measured against TDFA**: `^C[1-6]$` matches `C3`, but `^N\d+$` does **not**
   match `N123`. TDFA has no `\d`; `^N[0-9]+$` works. The comment is a
   feasibility claim recorded next to the code and never executed, which is the
   class the campaign has now found five times.
2. **`llmll check` passes an unknown function at exit 0.** A call to a
   nonexistent `list` builtin produced `warning: call to unknown function 'list'`
   and exit 0. That is `REGEX-LOWER-1`'s shape, a program that checks and would
   not build, and it wants its own row.
3. **`DONE-TYPE-1` fires on every console program written for this port**,
   confirming the roadmap row's claim that it carries no information.
4. **`REGEX-LOWER-1` shipped at v0.14.96 and SIX in-tree sites still say it did
   not.** Found by grepping for records that advertise the state D3 turns on.
   `versiongate.llmll:25` is corrected here because D3 rests on it. The other
   five are DRIVER-LL and doc-claims scope and are deliberately **not** touched:
   `sequencer.llmll:1327` and `:1334`, `docclaims.llmll:174`, and
   `test_driver_ll_4c.py:39`, `:419` and `:432`.
   **One of the five is worse than a stale comment.**
   `test_the_driver_calls_regex_match_nowhere` asserts that no driver module
   calls `regex-match`, on the stated ground that it "does not build", and its
   failure message reads "Until that row ships". The row has shipped. The test
   still passes, because nobody has added a call, so nothing is red; but a future
   maintainer who legitimately simplified a hand-rolled check back to the builtin
   would be stopped by a test citing a reason that no longer exists. Whether that
   test should be deleted or re-grounded on a different reason is a DRIVER-LL
   call, and this RFC does not make it.

None of the four blocks this port.
