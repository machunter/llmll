---
name: driver-ll-stage-m-fanout-proposal
title: "DRIVER-LL stage M: the fan-out dimension, and the registry change it does not need"
status: "Rev 1, 2026-09-11. Answers the design question the program-unification proposal Rev 5 section 4.10 scoped and deliberately did not write. MEASURED CORRECTION TO THAT SECTION: item 2 says stage M's artifact count is holes times attempts and therefore fits no registry entry. `stage-out-count` counts DECLARED outputs and stage M declares TWO, statically; the per-attempt directories are undeclared scratch, exactly as the reference's are. What varies at run time is how many times ONE delegation tag is executed, and NO registry column has ever carried that number for ANY stage. Stage H's probe rows and stage N's mutant rows are already that dimension and they live in the `Loop` payload. So the registry needs no new shape and item 2 overstates the gap; item 3 is correct as written and is what this proposal answers. The design is: one new registry KIND tag (`stage-fanout`), ONE new `Ctl` arm carrying the wave's own state pair, and an exit mapping read off the reference rather than chosen. FOUR OF THE WAVE'S SIX EXIT CODES MAP TO `Finished`, which is the clause a wrong port breaks: treating a non-zero code as a stage failure would halt the run where the reference continues and stage N would never run. Code 4 records `stopped` and not `failed`, because driver-spec section 10 defines the condition. TWO DRIFTS FOUND WHILE READING, both inside the driver tree: `stage-provision-ref?` returns false for M while the comment above it names M, and `wave.llmll` writes ONE of stage M's two declared outputs. The second is graded work and not tidiness: two of the clause 2 comparator's reported classes read `wave.json`. One payload widening is required and only one."
date: 2026-09-11
author: language-team
consumers: [compiler-engineer, user, documentation-lead, experiment-lead]
---

# DRIVER-LL stage M: the fan-out dimension

[`driver-ll-program-unification-proposal.md`](driver-ll-program-unification-proposal.md)
Rev 5 splits job (a) in two and scopes (a2), the retirement of the stub table. It
then stops at one question it names as a `language-team` question and refuses to
answer inside a revision about job (a)'s shape:

> A design for stage M's multiplicity: either the registry admits a run-time
> artifact count, or stage M is accounted for differently from the other fifteen
> and the difference is written down.

This proposal answers it. The answer is the second of the two, and the difference is
smaller than §4.10 states, because one of that section's three measurements reads the
wrong registry column.

## 1. The measurement that changes the question

§4.10 item 2 states that stage M's artifact count is holes times attempts, that it is
settled at run time, and that stage M therefore fits no registry entry.

`stage-out-count` in [`registry.llmll`](../../tools/llmll-driver/registry.llmll)
counts **declared** outputs. Stage M declares two: `12-wave/wave.json` and
`12-wave/roots.ast.json`. Both are constants. The per-attempt directories the wave
creates are undeclared scratch, and so are the reference's: `stage_M_wave` in
[`rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py) works in
`12-wave/agent-NN-fn` directories that no stage declares and no cover asserts.

The registry's own header already draws this line. The comment above
`stage-tag-count` says stage M "declares two while delegating once per HOLE, which is
neither one nor two", and gives that as the reason the invocation dimension is a
separate table from the declared-output dimension.

**So the count that varies is not an artifact count.** It is the number of times one
delegation tag is executed. No registry column has ever held that number for any
stage, and two ported stages already have one.

Item 3 of §4.10 is correct and is the real gap: the sequencer's `Ctl` carries one
`Delegate Body` arm per stage, and stage M is many delegations with many exit
statuses. §4 below answers that.

## 2. Three dimensions, and stage M sits in the third

| Dimension | Where it lives today | Stage M |
|---|---|---|
| D1, declared outputs | `stage-out-count`, static per stage | 2, static |
| D2, delegation tags | `stage-tag-count`, static per stage | 1, static |
| D3, run-time work items | the `Loop` payload, never the registry | holes, then attempts per hole |

**D3 has no registry column for any stage, and it must not acquire one.** Stage H
loops over the probe rows its agent catalogued. Stage N loops over the mutant rows.
Both counts come from `lp-count`, which is `list-length` over a JSON array the stage
read at run time. `h-enter` in [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll)
seeds that array from the agent's own output. Stage M is D3 with two nested indices
instead of one.

**Do not widen `stage-tag-count`.** Stage D's two tags are two different delegations:
two prompt substitution values, two provisioned input sets, two declared outputs and
two agent labels. Stage M's holes are repetitions of one tag. The registry header
refuses that collapse already, and the reason it gives ("the correspondence is a
coincidence at D and a separate table is what keeps it from being read as a law")
applies unchanged here.

## 3. Registry delta

### 3.1 One new column

A kind tag, not a count. The shape is `stage-shape`'s and `stage-oracle`'s: 0 means
none, and each non-zero value names which mechanism applies.

```
;; Which run-time work-item source the stage delegates over. 0 is none: the
;; stage delegates each of its stage-tag-count tags exactly once, and the
;; static tables above give every invocation its label and its directory.
;;
;;   1  M  one delegation per HOLE in the AST at declared output 1, retried
;;         under two budgets. The count is data and is never a function of i.
;;
;; SEPARATE FROM stage-tag-count for the reason that table's header gives: D's
;; two tags are two different extractors, and M's holes are one tag run many
;; times. SEPARATE FROM stage-oracle because that table is the compiler loop
;; that FOLLOWS a delegation and this one is the loop that CONTAINS it.
(def-shell stage-fanout [i: int] -> int
  (if (= i 13) 1 0))
```

**A table and not an index test in the stage loop.** The registry's header states the
rule this rests on: a table written as syntax is a constant a reader enumerates from
the source. A bare `(= i 13)` inside `started-step` puts the fact where no reader of
the registry finds it.

### 3.2 Filled rows

`stage-prompt 13` becomes `"stage-M-fill.md"`, which is the template
`stage_M_wave` names.

`stage-provision-ref? 13` becomes true. See §3.4.

`stage-agent-dir 13 j` is already `12-wave` through `stage-out-dir`, and does not
move.

### 3.3 `stage-agent-label` stays empty for stage M, and the comment must say why

The reference's label is `fill-{fn}#{attempt}`, a function of the hole's function
name and the attempt number. No `[i: int j: int] -> string` entry can hold it, so the
label is composed inside the fan-out machine, which knows both.

**An empty cell in that column currently means the stage delegates to no agent.**
Stage M would make it mean two things. The registry has met this failure once already
and records the remedy: `stage-floor`'s `-1` means two different things, and the
header says "a reader must not collapse them" and names `stage-shape` as what
separates the two. `stage-fanout` is that separating table here, and the comment above
`stage-agent-label` must point at it.

### 3.4 Drift found: `stage-provision-ref?` and its own comment disagree

The comment above `stage-provision-ref?` says `_provision_reference` is "called by H,
K, M and N". The table returns true for 8, 11 and 14. **Stage M is absent.** The
reference does call it, inside the per-hole fill closure, before the first attempt.

The row is probably false because stage M was stubbed when the column was written.
It may instead be false by a decision nobody recorded. **The engineer reads the call
site before flipping the row, and records which of the two it was.** Flipping it
without reading would be the class of move this repository keeps catching.

## 4. Control shape: `Ctl` gains one arm, not twelve

```
(| Fan (int, (Wv, WCtl)))
```

The `int` is the sequencer's stage-loop index `k`. The pair is the wave's own state,
unchanged. `drv-step`'s `Fan` arm calls `wave-step` and re-wraps the result with the
same `k`.

**This applies §4.3's decision at the arm level rather than at the program level.**
§4.3 rejected flattening `Ctl` and `WCtl` into one 46-arm control type, because they
collide on `Boot`, `Ending` and `Done` by construction, and §4.4 measured what a
collision costs: a colliding `open` warns per name, exits 0, is not escalated by
`--strict`, and the imported binding wins. One outer arm carrying the inner state has
no collision and no flattening. The wave keeps its twelve arms in
[`wave.llmll`](../../tools/llmll-driver/wave.llmll).

**`k` travels beside the wave state** because the sequencer's post-stage path
(`Summed`, `Stamped`, `Recorded`) is keyed on `k` and the wave does not know it.

**`k = -1` is the standalone wave run.** The unified program's `Boot 0` arm already
receives argv. When argv starts with `wave`, it enters `Fan (-1, ...)` and the wave's
own flag parse runs unchanged. §8 is why this matters.

## 5. The entry seam

`started-step` gains one branch, ahead of the `stage-kind` test:

```
(if (> (stage-fanout (idx-at rn k)) 0)
    (fan-enter rn k)
    ...)
```

`fan-enter` builds a `WaveCfg` from the sequencer's `Cfg` and the registry, then
enters the wave past its argv parse. `wave-init` splits in two. `wave-init` keeps the
argv path for the standalone run. A new `wave-seed [c: WaveCfg] -> ((Wv, WCtl), Command)`
issues `llmll holes --json` and enters `WBoot 1`. **No wave arm changes.**

| `WaveCfg` slot | Source |
|---|---|
| tree | `art-path c 13 1`, which is `12-wave/roots.ast.json` |
| workdir | `art-dir c 13 0`, which is `12-wave` |
| compiler | `cfg-llmll c`, the flag 4d added |
| agent, agent-args, timeout | `cfg-agent c`, the existing `AgentCfg` |
| err0, proto0 | **no sequencer source exists today**, see risk 1 |

**The AST tree must exist before the wave enters.** `stage_M_wave` emits it with
`llmll build 12-wave/roots.llmll --emit -o 12-wave`, guarded by a `tree.exists()`
test that `--force` overrides. The port needs the same copy and the same emit ahead of
`wave-seed`. A failed emit is a `require` in the reference, so it records `failed`.

## 6. The exit seam: the wave's exit code is not the stage's outcome

The wave's `WDone` carries an int. `record-outcome` in
[`stage.llmll`](../../tools/llmll-driver/stage.llmll) takes one of four `Outcome`
arms. The mapping below is read off `stage_M_wave` and is not chosen.

| Wave code | Condition | What the reference does | Outcome | Status |
|---|---|---|---|---|
| 0 | every hole accepted, tree sealed | returns normally | `Finished` | complete |
| 1 | at least one finding | logs the routing line, returns | `Finished` | complete |
| 3 | at least one protocol failure | logs "NOT a finding", returns | `Finished` | complete |
| 5 | every hole accepted, tree not sealed | logs "NOT SAFE", returns | `Finished` | complete |
| 2 | no holes in the tree | a `require`, so a `StageFailure` | `Errored` | failed |
| 2 | a missing flag | unreachable inside the sequencer | none | none |
| 4 | a token held while an agent works | no counterpart | `ConditionUnmet` | stopped |

**Four of six codes map to `Finished`, and this is the clause a wrong port breaks.**
`stage_M_wave` holds two `require` calls and neither fires on a finding, on a protocol
fault, or on an unsealed tree. It logs all three and returns. A port that treated any
non-zero code as a stage failure would halt the run where the reference continues.
Stage N would then never run, and the campaign would lose the kill matrix for a reason
that is not a defect in the fill wave.

**Code 4 records `stopped` and not `failed`, and driver-spec decides it.**
[`token.llmll`](../../tools/llmll-driver/token.llmll) cites `[S10-NOTHELD]` to
driver-spec section 10, which says a token MUST NOT be held while an agent is working.
A halt on a condition the specification defines is `stopped` per section 4:125-127.
Recording it `failed` would report a gate that fired as an accident, and section
4:135-137 names that as the dangerous direction.

**The two `2` rows are one code with two conditions, and only one survives the fold.**
Inside the sequencer the flags come from `Cfg` and the wave's missing-flag arm is
unreachable. It stays in the module for the standalone run. The engineer must not
delete it and must not map it.

## 7. The declared output the wave does not write

`12-wave/wave.json` is a declared output of stage M. `wave.llmll` never writes it.
The tally exists only as `summary-line` on stdout.

Three consequences make this graded work rather than tidiness.

1. The sequencer's `Summed` sweep digests every declared output. An absent one halts
   the stage.
2. [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) asserts every declared
   output appears under the workdir after a run.
3. [`CLAUSE-2-PRE-REGISTRATION.md`](../../experiments/rfc-swarm/CLAUSE-2-PRE-REGISTRATION.md)
   §6.3 registers R5 (wave partition) and R6 (retry budget) as reported comparator
   classes, and **both read `wave.json`**. Both diverged in the live run because stage
   M was stubbed. Neither can stop diverging until the file is real.

**One payload widening, and it is the only one this design requires.** `Wv` carries
three counters and no rows. The reference's file is `{"fills": [...], "whole_tree": v}`
with one row per hole carrying hole, pointer, status and attempts. `Wv` gains a fourth
slot, `fills: Json`, appended at each hole's terminal arm. The write lands in `seal`,
after the seal transcript is read and before `WEnding`.

`12-wave/roots.ast.json` needs no new write. `llmll patch` rewrites it in place, which
is why the wave takes a backup per attempt.

## 8. How the 4e cover survives

[`test_driver_ll_callers.py`](../../scripts/tests/test_driver_ll_callers.py) records
the constraint in its own docstring: `wave` keeps its `def-main` at (a1) because
[`build_smoke.sh`](../../scripts/build_smoke.sh) stage 9 builds and runs the wave
binary, and [`wave_cover.py`](../../scripts/wave_cover.py) drives it through seven
cells. Deleting that entry point would retire the acceptance cover of a shipped
sub-phase.

**The `wave` sub-command keeps every cell.** `wave_cover.py` invokes the unified binary
with `wave` as a prefix argument instead of invoking a separate binary. Its seven
cells assert on the transcript, on `wd/h0-a0/argv.json`, and on exit codes. All three
are unchanged by the prefix, because `Fan (-1, ...)` runs the same machine and exits
through the same clamp.

**This is stronger evidence than the cover has today**, because the cells then run
against the binary the campaign ships rather than against a second one.

`_programs()` returns one name once the wave's `def-main` is deleted, and §2 clause 1
of the unification proposal closes. **The orphan assertion must be re-measured and not
trusted.** `fill` and `token` currently reach a program through the wave's own
`def-main`; after the fold they reach it through the sequencer's import of `wave`. The
set is expected to be unchanged at `{liveness, shell}` and that expectation is a
measurement, not a deduction.

## 9. Acceptance

Stage M's share of (a2)'s two clauses.

1. `stage-ported? 13` is deleted with the rest of the table, not flipped.
2. **Stage M writes both declared outputs and neither is a stub.**
   `12-wave/wave.json` parses and carries one `fills` row per hole.
   `12-wave/roots.ast.json` is an AST the compiler accepts.
3. The seven cells of `wave_cover.py` pass against the unified binary.
4. `_programs()` returns exactly one name, and the orphan set is re-measured.
5. A stage M that reports findings records **complete**, and the run continues into
   stage N.

Clause 5 is the one a plausible implementation gets wrong, and §10 case 3 is the
witness that shows what it costs.

## 10. Edge cases

**1. A tree with zero holes.** `wave-boot-step` already reaches `WEnding 2` with a
STOP line that names the tree. Inside the sequencer this maps to `Errored` and records
`failed`, matching the reference's `require(holes, ...)`. Channel: contract, through
`record-outcome`'s `[S4-FAILED]`.

**2. A run resumed after stage M halted part-way.** No manifest row was written, so
`may-skip` in [`skip.llmll`](../../tools/llmll-driver/skip.llmll) is false and the
stage re-runs. `[S5-PRESENCE]` is the clause: the presence of an artifact MUST NOT on
its own cause a skip. On re-entry the hole list is re-derived by `llmll holes --json`,
and every hole the previous run filled is no longer a hole. **Resume at hole
granularity is free and needs no per-hole manifest row.** Channel: contract. This is
the property that makes D3 safe to keep out of the manifest, and it is why §2's rule
costs nothing.

**3. POSITIVE WITNESS, and it is a measured event rather than a construction.** Run
`rfc826-llmll-2026-09-11`. Stage M is stubbed, so `write-cmd` writes `stub-body 13 1`
to `12-wave/roots.ast.json`, which is the literal text
`{"driver-ll": "4a stub", "stage": "M", "artifact": "12-wave/roots.ast.json"}`. Stage
N reads that path as its `stage-pre-path` input, authors 0 mutants, and correctly
reports the kill matrix VOID. Stage O's section 13 validator then halts the run.
Under this design the same input is a real AST, stage N receives an implementation
tree, and the cascade does not start. Channel: trust, through the run's own artifacts.
The run's `13-kill-matrix` report and the pre-registration's halt analysis are the
record.

**4. Every hole accepted and the whole tree not sealed.** The wave reaches
`WEnding 5`. `seal`'s comment says the seal can only condemn a run and never rescue
one, and that code 5 is reserved for the case the per-fill bar cannot see. Stage M
still records complete, because the reference writes `whole_tree` into `wave.json` and
returns. **The unsealed verdict reaches the campaign through the artifact and not
through the stage status.** Channel: spec is silent and that is intentional.

**5. A standalone wave run under `k = -1`.** `drv-status` must return the wave's code
and must keep its `[EXIT-RANGE]` post. See §11 obligation 1.

## 11. Verification mapping

**1. `drv-status`'s `[EXIT-RANGE]` post over the new `Fan` arm.** Channel: contract.
`drv-status` is a proved `def` with post `(and (>= result 0) (<= result 255))`, cited
to PROC-BOUNDARY-1 §4.4. Every existing arm returns an int literal, so the post is
trivial today. The `Fan` arm returns the wave's code, which is not a literal.
`wave-status` holds the clamp and is a `def-shell`, so its body is not available to
the call site's VC and the post would not discharge body-faithfully.

**Remedy: promote the clamp into a proved `def` carrying the same post, and call it
from the `Fan` arm.** The obligation then discharges from the callee's contract.
Fragment: **QF-LIA, auto-discharged by liquid-fixpoint.** Two comparisons over one
integer variable, no product and no quantifier. [`LLMLL.md`](../../LLMLL.md) §5.3.3
closes the QF-LIA core over `+ - = != < <= > >=` plus integer and boolean literals and
variables, which covers this without widening anything.

The sequencer's own header records that `drv-status` is contract-checked rather than
proved, because no driver with a product state is provable there, and that
`exit-code`'s `[EXIT-NOVACUOUS]` post carries the weight instead. **The `Fan` arm must
not weaken either.**

**2. The code-to-`Outcome` mapping of §6.** Channel: contract, through
`record-outcome`'s four posts. `record-outcome` is already proved and does not move.
The new obligation is that the mapping is total over the wave's terminal codes, and
that its catch-all fails toward `Errored`. Fragment: **QF-LIA, auto-discharged.** An
if-chain over integer equalities.

**3. The `token-during` abstraction under the sequencer's loop.** Channel: **trust,
not contract.** [`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) §6
records that the labelling is a refinement mapping in Abadi and Lamport's sense, that
it is a property of the port and not of the module, and that it is a function only
while at most one hole is live. It also records that no proof assistant can discharge
it, because it quantifies over the driver's states rather than over a `def`'s inputs.

The sequencer's console loop is a single-threaded step machine and `Fan` is one arm of
it, so the precondition is preserved and is not weakened. **No new obligation and no
Lean candidate.** This is a disclosure, and it belongs in the `Fan` arm's comment
beside the four abstraction functions `wave.llmll`'s header already inventories.

**4. The `fills` accumulator in `Wv`.** Channel: **type**, and the finding is that the
type does not catch the failure. Both modules record that a wrong projection over a
pair chain typechecks, and both answer it the same way: every projection sits in one
written-once accessor and no use site writes a bare nested `second`. The fourth slot
follows that rule. **No verification obligation**, so the discipline is the only thing
that catches a wrong projection here.

Nothing in this design escapes to Lean. Nothing is nonlinear or quantified. No new
sort, no uninterpreted function and no axiom.

## 12. Affected surface

1. [`registry.llmll`](../../tools/llmll-driver/registry.llmll) — one new `def-shell`
   (`stage-fanout`); two filled rows (`stage-prompt`, `stage-provision-ref?`); one new
   comment above `stage-agent-label` explaining the empty cell and pointing at
   `stage-fanout`.
2. [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) — one `Ctl` arm; one
   case each in `drv-step`, `drv-done?` and `drv-status`; one branch in
   `started-step`; `fan-enter`; the pre-stage copy and emit; the terminal-code
   mapping; one proved clamp `def`.
3. [`wave.llmll`](../../tools/llmll-driver/wave.llmll) — delete `def-main`; split
   `wave-init` into `wave-init` and `wave-seed`; widen `Wv` by one slot; write
   `wave.json` in `seal`.
4. [`test_driver_ll_callers.py`](../../scripts/tests/test_driver_ll_callers.py) —
   `_programs()` becomes one name; the orphan assertion is re-measured; the docstring
   that records why the wave kept its entry point is rewritten to record that it lost
   it.
5. [`wave_cover.py`](../../scripts/wave_cover.py) and
   [`build_smoke.sh`](../../scripts/build_smoke.sh) stage 9 — drive the unified binary
   with the `wave` prefix argument. Seven cells keep their assertions.
6. [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) — stage M's two declared
   outputs become assertable for the first time.
7. [`driver-ll-program-unification-proposal.md`](driver-ll-program-unification-proposal.md)
   §4.10 — item 2 needs correcting per §1 above. Item 3 stands unchanged. That is a
   revision of that proposal and is not this document's to make.
8. **Not affected: [`compiler/src/LLMLL/`](../../compiler/src/LLMLL/).** No compiler
   change, no new builtin, no schema change and no new WASI surface. The v0.8.1a to
   v0.10 feature freeze was lifted at v0.11, so no exception arises either way.

## 13. Risks

**1. The two retry budgets have no sequencer source.** Classify: scope. The
sequencer's `Cfg` carries no `--error-budget` and no `--protocol-budget`. The wave's
cover pins both flag names. The reference has one knob, `semantic_retries`, and the
port has two, which 4e settled and this proposal does not reopen. **Bite: complicates
(a2), does not block it.** Two flags on the sequencer mirror the wave's. Note the
consequence for the unification proposal: §3 assigns the operator CLI surface to job
(b) and lists four flags, and these two belong to (a2), so that list is short by two.

**2. Deleting the wave's `def-main` moves the 4e acceptance cover.** Classify:
verification-ergonomics. The sub-command keeps every cell and changes how they are
invoked. **Bite: complicates.** The cover must be re-run and seen to pass before (a2)
claims clause 1. A cover that is edited and not re-run proves nothing.

**3. `drv-status` is contract-checked and not proved.** Classify:
verification-ergonomics. **Bite: complicates.** The §11 obligation 1 remedy keeps the
post discharging. Skipping it leaves the arm's return value unconstrained while the
post still reads as if it were checked, which is worse than an unchecked arm.

**4. Stage M records complete on four of the wave's six codes.** Classify:
spec-drift risk against a reader, not against the code. A reader meeting `stage M
complete` beside a findings line may read the stage as having succeeded. The reference
behaves the same way and the artifact carries the verdict. **Bite: only matters at
scale.** The remedy is a comment at the mapping site, not a behaviour change.

**5. The per-attempt directory naming diverges from the reference.** Classify: scope.
The reference uses one directory per hole, reused across attempts. The port uses one
per hole per attempt, and `wave.llmll` gives the reason: an absent stdout file must be
distinguishable from a stale one. Cover cell W1 pins `wd/h0-a0/argv.json`. **Bite:
only matters at scale.** Both are undeclared scratch, so neither the cover nor the
comparator reads them.

**6. `stage-provision-ref?` may be false by decision rather than by omission.**
Classify: spec-drift. **Bite: complicates.** §3.4 states the check the engineer runs
before flipping it.

## 14. What (a2) still owes after this design

Stage M is one of the five stubbed stages. E, J, L and G2 remain, and §4.10 item 1
measures them as a seventeen-arm linear counter in
[`spine.llmll`](../../tools/llmll-driver/spine.llmll) rather than a set of callable
functions. Porting them means mapping seventeen steps onto `Ctl` arms, and this
proposal does not touch that.

**(a2) is unblocked for stage M. It is not unblocked as a whole.** The spine's four
stages need their own scoping turn, and job (b) still waits behind all five.

## 15. Deferred theory questions

None. Three candidates were raised and all three failed the negative test, because
reading the tree answered them. The refinement-mapping question was answered by
`driver-ll-phase4-proposal.md` §6 and the sequencer's step loop. The exit-range
question was answered by `drv-status`. The outcome mapping was answered by the
reference's `require` family. Nothing is appended to
[`theory-questions.md`](theory-questions.md).
