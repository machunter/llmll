---
name: driver-ll-phase4f-implementation-plan
title: "DRIVER-LL sub-phase 4f: implementation plan and running record"
status: "IMPLEMENTED on branch driver-ll-4f/stage-o-writeup, 2026-09-10, at v0.23.0. Stage O is ported, report.llmll verifies SAFE and body-faithful, and its crux refutes. THE ACCEPTANCE COVER HAS NOT RUN: llmll build cannot link on this machine (the macOS SDK tbd files report unknown architecture, measured on a two-def program as well), so cells O1 to O4 are written and unexecuted and CI is the first place they run. Sections 12 to 15 are the running record, the Phase 4 close and the gap inventory. Program unification is next and is NOT in this file."
date: 2026-09-10
author: compiler-engineer
consumers: [compiler-engineer, language-team, experiment-lead, documentation-lead, user]
---

# DRIVER-LL sub-phase 4f: implementation plan and running record

Port stage O into [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll),
write the validator that driver-spec section 13 asks for and the reference does
not have, and close Phase 4 with its gap inventory. Read proposal
[section 6.2](driver-ll-phase4-proposal.md) and section 9.1 item 2 first.

## 1. Restatement

Stage O is registry index 15. It is the last unported stage in this program and
it is the only delegated stage in the reference with **zero** `require()` sites.
4f writes the validator that stage O has never had, decides one driver-spec
section 13 clause mechanically, lists the other seven as unchecked, and records
the Phase 4 gaps.

## 2. Context located

- `scripts/rfc_to_implementation.py`, `stage_O_writeup` and the registry row
  `Stage("O", "writeup", "agent", stage_O_writeup, ("REPORT.md",))`. The handler
  runs the agent in `14-report`, asks for `REPORT.md`, copies that file to the
  workdir root, and logs. It holds no `require`.
- `scripts/rfc_to_implementation.py`, `stage_N_killmatrix`. It writes
  `kill-matrix.json` as a JSON **array**. Each row carries `name`, `good_twin`,
  `verdict` (`unwritable`, `SAFE` or `refuted`) and `as_expected`. A survivor is
  a row that is not a good twin and whose verdict is neither `refuted` nor
  `unwritable`.
- `experiments/rfc-swarm/targets/driver-spec.txt` section 13. It carries eight
  MUSTs. One is mechanizable and seven are disclosure-only, which is the split
  proposal section 6.2 draws from section 15.1:512-515.
- [`registry.llmll`](../../tools/llmll-driver/registry.llmll). `stage-out 15` is
  already `REPORT.md` and `stage-out-dir 15` is already `.`. `stage-agent-out`
  has no row for 15, so it falls through to `stage-out` and gives the wrong
  file.
- [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) `pre-step`. A
  precondition artifact that is absent halts `Absent`. The reference's `maybe()`
  substitutes `(stage not run)` instead. Stage O has five prompt inputs and all
  five are optional in the reference.
- [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) `verify-safe?`.
  `string-contains` is already the driver's substring test, so the set
  difference needs no new builtin.
- [`oracle.llmll`](../../tools/llmll-driver/oracle.llmll) `matrix-complete?`.
  It is the idiom this plan copies: a biconditional post, plus a directional
  post that carries the spec sentence and is entailed by it.
- `docs/compiler-team-roadmap.md` row `DRIVER-LL` (G0). Its Next Action step (3)
  names 4f and program unification as what remains.

## 3. Plan summary

Add one proved module, six registry rows, one precondition mode and four `Ctl`
arms. The agent writes `14-report/REPORT.md`. The driver copies that file to the
declared output `REPORT.md`, then reads `13-kill-matrix/kill-matrix.json`, then
tests each row's `name` against the report text. A row whose name does not occur
is an omission. The decision is a proved `def` in a new module. The halt is
`PartialThenHalt` and records `stopped` at exit 2, because the declared write has
already happened. That is proposal section 3.6's axis and it is the second real
site of that constructor, not the first.

## 4. Affected surface

**New.** `tools/llmll-driver/report.llmll`, one `def`, the proved core of
section 7 below. A new module rather than a widening of
[`shape.llmll`](../../tools/llmll-driver/shape.llmll) or
[`oracle.llmll`](../../tools/llmll-driver/oracle.llmll), on
`oracle.llmll`'s own argument: `validate` decides an artifact's presence and
size, `shape` decides its content shape, `oracle` decides what a compiler run
means, and this decides whether a report names what a previous stage found.
Four subjects, four modules. It declares no type, so `TYPE-SHADOW-1` does not
reach it.

**`registry.llmll`.**

- `stage-ported?`: 15 becomes true. Ten stages become eleven.
- `stage-agent-out`: a row for 15, `14-report/REPORT.md`. The agent's file is
  not the declared output, which is the third instance of the inversion the
  restart record's section 6 item 6 names, after H and N.
- `stage-prompt`: 15 is `stage-O-writeup.md`.
- `stage-agent-label`: 15 is `writeup`.
- `stage-pre-count` and `stage-pre-path`: 15 takes five inputs, in the
  reference's keyword order: `09-gate/gate.json`, `11-freeze/rfc-cov-1.txt`,
  `13-kill-matrix/kill-matrix.json`, `12-wave/wave.json`,
  `04-reconcile/SUMMARY.json`.
- `stage-pre-mode`: all five are the new mode **4 OPTIONAL** (section 5).
- `stage-provision-ref?` stays false. Stage O runs no compiler and reads no
  LLMLL source.

**`sequencer.llmll`.**

- Four `Ctl` arms: `OCopy` (the declared write), `OMat` (the kill-matrix read),
  `ORow` (the per-row name test) and `OWrote` (the bar). The row loop reuses the
  `Loop` payload that H, N and A already use.
- `(import report) (open report)`. The sibling imports go from seven to eight.
- One forwarding `def-shell` per proved def, the 4d and 4e pattern:
  `omission-free?` is called once.
- `survivor?` already exists in this module for stage N's survivors line. 4f
  reuses it and does not write a second copy.
- A `SECTION 7 STATEMENT [DISCLOSURE report.omission-free?]` block in the
  header. Proposal Rev 5 owes a fifth statement at 4f and names why: the
  identifiers are read as strings from an agent-authored artifact, so the
  counting is shell-side and outside Sigma_auto. **The statement must also
  disclose that the test is a substring test** (section 9 risk 2).
- Correct the retirement schedule at `sequencer.llmll:181-182`. It says 4f
  retires `PartialThenHalt`. Measured: `hwrote-step` already constructs a real
  `PartialThenHalt` at 4d, and the comment 100 lines below it already says so.
  4f adds the second site; it does not retire the constructor.

**`tools/llmll-driver/EXPECTED_VERDICTS.json`.** Two cases: `report.llmll`
expects `safe`, and the new crux expects `refuted`.

**`tools/llmll-driver/crux-report-omits-survivor.llmll`.** The refuting body of
section 7.

**`scripts/driver_ll_cover.py`.** Four cells, `O1` to `O4` (section 8).

**`scripts/tests/test_driver_ll_4f.py`.** New, no toolchain.

**`scripts/tests/test_driver_ll_callers.py`.** The census loses its stage O row.

**`scripts/build_smoke.sh`.** Its comment at `:1026` says the sequencer imports
five sibling modules. It imports seven today and eight after 4f. The echo one
line below names the `4a+4b+4c+4d` cover and stage A is already missing from it.
Both are comments, and a `build_smoke.sh` edit is graded only by CI job C5.

**Not touched.** No file under `compiler/`. No schema change. No
`LLMLL.md` change. The roadmap row and the CHANGELOG are documentation-lead's.

## 5. The five optional inputs, and why they need a new mode

The reference's `maybe()` reads each of stage O's five prompt inputs and
substitutes `(stage not run)` when the file is absent. `pre-step` halts `Absent`
on that same condition today, for every mode. So a faithful port needs a mode
where absence is a value rather than a halt.

Mode **4 OPTIONAL**: the text verbatim when the file reads, and the constant
`(stage not run)` when it does not. The mode number is per input already
(`stage-pre-mode [i j]`), so no table changes shape. `pre-step` gains one arm
that tests the mode before it halts.

This is reachable and is not a theoretical case. `--only O` runs stage O against
a workdir where nothing upstream ran, which is what `maybe()` exists for.

## 6. The absent kill matrix, and the clause that must not go vacuous

If `13-kill-matrix/kill-matrix.json` is absent, the omission check has no
reference set and decides nothing. The stage must then record `complete` **and
say in its manifest row detail that the check did not run**. A run with no kill
matrix must not read as a checked run.

That is the risk proposal Rev 15 records three times under a different name: a
one-hole fixture made 4e's contention clause vacuous, and the same clause had
already been lost twice by two other mechanisms. So the acceptance clause for
4f is written to be unsatisfiable by the absent case alone: cell `O2` holds a
present matrix with an omitted survivor, and it is the cell that must fire.

## 7. Contract plan

One `def` lands in the provable fragment. **The clauses below are not a
sketch. They were written, checked and verified at v0.23.0 before this plan was
filed.**

```
(def omission-free? [row-count: int
                     named-count: int
                     survivor-count: int
                     survivors-unnamed: int] -> bool

  (pre (and (>= row-count 0)
            (and (>= named-count 0)
                 (and (<= named-count row-count)
                      (and (>= survivor-count 0)
                           (and (<= survivor-count row-count)
                                (and (>= survivors-unnamed 0)
                                     (<= survivors-unnamed (- row-count named-count))))))))
    :source "[O13-DOM] every count is over the rows of kill-matrix.json, so all are non-negative; a named row is one of the rows, and an unnamed survivor is one of the unnamed rows")

  (post (= result (= named-count row-count))
    :source "[O13-FULL] driver-spec.txt sec 13 - a report MUST include the full result of the perturbation exercise, so every row of the kill matrix is named in it")

  (post (=> (> survivors-unnamed 0) (not result))
    :source "[O13-UNDETECTED] driver-spec.txt sec 13 - the clause names undetected perturbations explicitly, and a survivor the report does not mention is the omission it forbids")

  (post (=> (< named-count row-count) (not result))
    :source "[O13-NO-OMIT] a validator that passes on a partial mention lets the omission through, which is the failure this check exists to catch")

  (= named-count row-count))
```

**Measured, not predicted.** `llmll check` reports OK, 1 statement.
`llmll verify --strict-verified-core` reports `body-faithful: omission-free?`
and then SAFE (liquid-fixpoint), with no flags beyond the strict one.

**The refuting bodies.** Three plausible wrong implementations, all measured
`refuted: omission-free?` against the same contract:

| Body | What a reader would have meant |
|---|---|
| `(> named-count 0)` | the report mentions the matrix |
| `(>= named-count survivor-count)` | the report names at least as many rows as there are survivors |
| `(= survivors-unnamed 0)` | every survivor is named, and the other rows do not matter |

The third is the crux to commit. It is the discriminating half: it satisfies
`[O13-UNDETECTED]` and refutes through `[O13-FULL]` alone, which is the same
shape as `crux-validate-subject-hardcoded.llmll`.

**`survivors-unnamed <= row-count - named-count` is a precondition, not a
discovered fact.** The unnamed survivors are counted among the unnamed rows,
which is the same reasoning `probe-rows-conform?` states for
`rows-conforming <= row-count`.

**Module placement.** One `def` in its own module, so no intra-module `def` to
`def` call exists and the admissibility check cannot fire.

**What stays unproved.** The counting. `named-count` comes from
`string-contains` over the report text, and `survivor-count` from `survivor?`
over parsed JSON. Both are string structure and both are outside Sigma_auto
(`LLMLL.md` section 5.3.5). That is the fifth section 7 statement, and proposal
Rev 5 already forbids the escape route: **do not intern the identifiers as a
nullary enum to move the check into QF-LIA**, because the identifier set is
authored by an agent per run and is not a closed vocabulary.

## 8. Test plan

**Cover cells** in `scripts/driver_ll_cover.py`, four:

- `O1` the report names every row. Records `complete`, exit 0.
- `O2` the report omits a survivor. Records `stopped`, `PartialThenHalt`, exit
  2, and the row's clause names driver-spec section 13. **This is the firing
  witness and the acceptance clause rests on it.**
- `O3` the kill matrix is absent. Records `complete`, exit 0, and the detail
  says the check did not run (section 6).
- `O4` the kill matrix is not a JSON array. Records `failed` and `Errored`,
  proposal section 9.1 item 1's disposition for a guarded read.

**Python tier** `scripts/tests/test_driver_ll_4f.py`, about eight tests, no
toolchain: the five precondition rows against the reference's keyword order, the
`stage-agent-out` row against the reference's `out_name` argument, mode 4's
substitution constant, and the eight section 13 MUSTs counted from the spec text
rather than from the proposal's five line ranges.

**Baselines, measured at v0.23.0 on 2026-09-10.**

| Gate | Baseline |
|---|---|
| `pytest scripts/tests/` | 218 passed, 23 skipped, 26 s |
| `scripts/driver_ll_cover.py` | 57 cells declared, counted by decorator; the last recorded RUN figure is 52 at 4d, before stage A's six cells |
| `stack test` | not re-measured; 4f touches no Haskell, so the hspec count must not move. Measure on the branch point before implementing |

Target after 4f: pytest 226 passed, cover 61 cells.

## 9. Risks and unknowns

1. **The substring test admits a false pass.** Classification: verification of
   the abstraction, not of the code. `string-contains` matches a name inside a
   longer word, so a matrix row named `x` is "named" by a report that says
   `xyz`. The direction of the error is toward passing. LLMLL has
   `regex-match` but POSIX ERE carries no word boundary, so no in-language fix
   is available today. The mitigation is disclosure in the section 7 statement,
   not machinery. Bite: it complicates the claim, and the phase close must not
   say the check is exact.
2. **Mode 4 touches `pre-step`, which every ported stage uses.** Classification:
   regression. Eleven stages reach that function. Bite: it complicates the
   patch; the 4b, 4c and 4d cover cells are the regression net and they run in
   the same cover.
3. **`wasi.fs.copy` against `shutil.copy2`.** Classification: divergence,
   disclosed. `copy2` preserves metadata and `wasi.fs.copy` is byte-faithful
   (`FS-COPY-1`, shipped v0.14.84). No section 13 obligation mentions the
   report's mtime. Bite: only a disclosure line.
4. **The phase close is prose and can overclaim.** Classification: spec drift.
   Passing the set difference does not discharge section 13's "MUST be resolved
   rather than omitted", and the proposal says so twice. Bite: it blocks nothing
   and it is the sentence most likely to be written wrong.
5. **`FS-ISOLATION-1` carries a disclosure obligation at phase close** under
   driver-spec section 15.1:504-505, and `SPEC-TIER-1` bounds what the close may
   assert. Both are filed in proposal section 14. Bite: they belong in the gap
   inventory, not in the code.

## 10. Rollback

A single revert. 4f adds one module, one crux, four cover cells and one test
file, and it changes no schema and no compiler. `report.llmll.verified.json` is
a new sidecar and no existing sidecar changes. Worst case is one commit
reverted; the only shared surface is `pre-step`, and reverting mode 4 restores
the halting behaviour every other stage already relies on.

## 11. Routing

- **language-team**: proposal section 9's 4f row says "Proved cores activated:
  none new". This plan lands one, `report.omission-free?`, which is the same
  discrepancy the 4d plan reported for `oracle.llmll`. Rev 16 should either
  correct the row or state why a new core does not count as an activation.
- **documentation-lead**: this file needs an `INDEX.md` row. 4f, when it ships,
  needs a CHANGELOG entry and a version, and so do 4a and 4c, which have never
  had one.
- **compiler-engineer**: program unification is next after 4f and is not in this
  plan. The 4a fault injector still has all three arms while every stopped
  constructor now has a real producer; measure what deleting it breaks before
  deleting it, because cover cell T4 and the `--halt-kind` flag both read it.

---

## 12. What landed, and three places the plan above was wrong

**Two `Ctl` arms, not four.** Section 4 planned `OCopy`, `OMat`, `ORow` and
`OWrote`, which assumed the driver would read `kill-matrix.json` itself and walk
its rows one command at a time. It needs neither. The kill matrix is already
precondition value 2, which the Pre loop read before the stage delegated, and
the name test is pure computation over a parsed list, so no command per row
exists to sequence. The arms are `OWrote` (the check runs) and `OSkip` (there is
no matrix to check against). The plan reached for stage N's shape because stage
N is the nearest neighbour, and stage N walks rows because each row costs a
`verify`.

**The census had no stage O row to lose.** Section 4 said
`test_driver_ll_callers.py` would lose one. Measured: `report.omission-free?`
arrives with its caller already written, and the module is imported, so it joins
neither the orphan set nor the unreferenced set. 4f is the first sub-phase whose
landing moves no row in that file, and the file now records that.

**One registry table was missing from the plan.** `stage-agent-dir` had to be
added beside `stage-agent-out`. The plan noticed that the agent's FILE differs
from the declared output and not that the agent's DIRECTORY does; `agent-dir`
was `art-dir`, so stage O's agent would have run in the workdir root beside
`MANIFEST.json`. This is the same conflation the 4d cover caught at run time
between `stage-out` and `stage-agent-out`, one level up, and this time a read of
`agent-dir`'s callers caught it before a run did.

**Everything else landed as planned**, including the contract, which was
written and verified before the plan was filed and did not change.

## 13. Gates at the checkpoint

| Gate | Figure |
|---|---|
| `llmll check` / `verify` `report.llmll` | OK, 1 statement; SAFE, `body-faithful: omission-free?` |
| `llmll verify` `crux-report-omits-survivor.llmll` | refuted, localized to `omission-free?`, exit 1 |
| per-post discrimination, measured one post at a time | `[O13-FULL]` refutes, `[O13-NO-OMIT]` refutes, `[O13-UNDETECTED]` survives |
| `llmll check` `sequencer.llmll` | OK, 312 statements, 21 warnings (was 20; the new one is `omission-free?`'s trust gap, the same class as every other imported proved def) |
| `llmll verify` `sequencer.llmll`, `registry.llmll` | SAFE, no flags, as frozen |
| frozen-verdict sweep, all 38 cases by hand | 36 agree; the two that do not are classifier artifacts on files 4f does not touch (`crux-gate-coverage-threshold` refutes through a check-time error rather than a solver verdict, and `crux-shell-undeclared-authority`'s capability message does not quote its localized name) |
| `pytest scripts/tests/` | 229 passed, 23 skipped (was 218 / 23; +11 from the 4f tier) |
| `scripts/driver_ll_cover.py` | **NOT RUN.** 61 cells declared, was 57 |
| `stack test` | **NOT RUN.** No Haskell was touched, so the hspec count cannot move |

**Why the cover did not run, measured rather than assumed.** `llmll build` fails
at the LINK step on this machine: `ld` reports `tapi error: malformed file` and
`unknown architecture` against `MacOSX27.0.sdk`'s `libSystem`, `libm`, `libz`,
`libiconv` and `libffi` stubs. A two-`def` program with one `wasi.io.stdout`
call fails identically, so the cause is the local toolchain and not this patch.
The cover needs a built `sequencer`, so cells O1 to O4 are written and
unexecuted. CI's `build_smoke.sh` stage builds the sequencer on Linux and runs
the cover there, and that is the first place these four cells execute.

`stack test` was not run for a second reason beside the first: a rebuild
overwrites the install root, and the working `llmll` binary in it is the only
one on this machine that the broken linker cannot replace.

**Two test pins moved, both deliberately.** `test_driver_ll_4c.py`'s ported-stage
census goes from ten to eleven, and `test_driver_ll_4d.py`'s `PartialThenHalt`
site set goes from one to two. Both assertions are rewritten with the reason at
the site, not widened.

## 14. Phase 4 close

**What 4f discharges.** The perturbation-omission check exists, it is proved, it
fires on an omitted survivor (cover cell O2, written and not yet executed), and
it records `stopped` through `PartialThenHalt` with driver-spec sec 13 as its
clause. Stage I's absent validator is disclosed and not invented: proposal
section 9.1 item 2 settled that at 4b and 4f keeps it, so stage I still records
`complete` over a 0-byte `PRE-REGISTRATION.md`.

**What the phase close must NOT say.** Seven of driver-spec section 13's eight
MUSTs are disclosure-only and are listed here as **unchecked**: the
lead-with-coverage pair, "state what is not claimed", "disclose every assumed
step", "MUST be resolved rather than omitted", the prohibition on characterising
perturbation as validating contracts, and the prohibition on claiming
verification prevented an error. Passing the set difference does not discharge
"MUST be resolved rather than omitted", and a report that lists a survivor and
dismisses it passes this check while violating that sentence.

**What the phase still owes.** Acceptance clause 2 is a live campaign run
against a target already run in Python, judged on decisions rather than bytes
(proposal section 2.4). No cover cell is that run and 4f does not make it one.
Clauses 1a and 1b now have stage O rows to range over and have not been
re-derived over them.

## 15. Gap inventory at the Phase 4 close

Filed and carried, none repaired here. Proposal section 14 is the authority on
the first four.

| Tag | Bearing on Phase 5 |
|---|---|
| `SPEC-TIER-1` | Target-spec defect. Section 13's prose MUSTs fit none of section 15's three tiers, so the section 15.4 conformance claim cannot tier them. No tier is manufactured |
| `FS-ISOLATION-1` | `audit_blindness` is deferred as operator surface and carries a disclosure obligation at phase close under section 15.1:504-505 |
| `PROC-TIMEOUT-1` | Bounds the tier claim; it now reaches stage O's agent run like every other delegated stage |
| `CLAUSE-INDEP-1` | `[O13-UNDETECTED]` and `[O13-NO-OMIT]` are entailed by `[O13-FULL]`. Recorded in their `:source` text and witnessed by the crux, which is the in-scope move section 14 names |
| `FS-STAT-1` | Unchanged by 4f; `liveness.advancing` still has no data source |
| `CAP-1-REAL`, `CONSOLE-INIT-1`, `MATCH-CATCHALL-1`, `STRLIT-BODY-1`, `RESERVED-NAME-1` | Filed by earlier sub-phases, all still open in their groups |

**New at 4f, and it is a disclosure rather than a row.** The membership test is
`string-contains`, so a matrix row named `x` counts as named by a report that
says `xyz`, and the error direction is toward passing. `regex-match` is POSIX
ERE and carries no word boundary, so no in-language tightening exists today.
Whether that is worth a roadmap row is the user's call and documentation-lead's
to file; the port discloses it in the section 7 statement either way.

## 16. Routing

- **language-team**: proposal section 9's 4f row says "Proved cores activated:
  none new" and 4f lands one, `report.omission-free?`. That is the second
  sub-phase where the row and the landing disagree; 4d was the first. Rev 16
  should correct the column or say why a new core is not an activation.
- **documentation-lead**: the G0 row's step (3) can name 4f as done once the
  cover runs in CI; 4f needs a CHANGELOG entry and a version, and so do 4a and
  4c, which have never had one; this file needs an `INDEX.md` row.
- **compiler-engineer**: program unification is next. The 4a fault injector is
  now redundant for its stated purpose, every stopped constructor having a real
  producer, and what deleting it breaks is measured before it is deleted: cover
  cell T4 and the `--halt-kind` flag both read it.
