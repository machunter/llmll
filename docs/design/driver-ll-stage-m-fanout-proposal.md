---
name: driver-ll-stage-m-fanout-proposal
title: "DRIVER-LL stage M: the fan-out dimension, and the registry change it does not need"
status: "Rev 2, 2026-09-11. SHIPPED, and three of this proposal's specifics did not survive implementation. THE SHARPEST IS SECTION 11 OBLIGATION 1, WHICH RESTS ON A FALSE PREMISE. It states that `drv-status`'s `[EXIT-RANGE]` post discharges body-faithfully today and that a non-literal arm would break it, and it prescribes promoting the clamp into a proved `def`. MEASURED from `sequencer.llmll.verified.json`: that post sits at `display_level: asserted`, with no `body_faithful` key and no `verified_hash`. It has never been discharged, and this document's own closing paragraph in that section cites the sequencer header saying so. NO NEW PROVED `def` WAS NEEDED. What actually constrained the arm is different and the compiler said it: `drv-status` is a `def`, so strict-core ADMISSIBILITY applies to its arms, and `llmll check` rejected the call with `callee 'wave-status' is not body-faithful and not in the trusted prelude`. `isCoreBodySyntactic` admits an `EApp` syntactically; the admissibility check is a separate gate. The resolution is simpler than this proposal's: `fan-step` leaves through `Ending` for BOTH values of `k`, so a `Fan` state is never terminal and all three status arms stay integer literals. SECTION 3.2 WAS WRONG TO FILL `stage-prompt 13`: the reference renders `stage-M-fill.md` and the port does not, because `begin-attempt` hands the agent `brief.json` and an output path, which is the checkout-brief-is-the-sole-channel discipline, and cover cell W1 asserts exactly two arguments. The row stays empty and the registry comment now says why. SECTION 3.4 WAS WRONG TO SET `stage-provision-ref? 13` TRUE: a true row would claim a behaviour the code lacks, which is the defect class that section exists to repair. The row stays FALSE and the comment records the gap. Section 3.4 asked whether the omission was a decision or an oversight; MEASURED, it is an OVERSIGHT, because no document anywhere records it. WHAT HELD: section 1, section 2, section 4, section 6 including the code-4-is-`stopped` reading and all seven rows, section 7, and section 10 case 3. ONE THING THIS PROPOSAL DID NOT PREDICT: a second `Ctl` arm, `FanBoot`, carries the AST-emit guard, because re-emitting resets every hole a partial run had filled. Rev 1, 2026-09-11. Answers the design question the program-unification proposal Rev 5 section 4.10 scoped and deliberately did not write. MEASURED CORRECTION TO THAT SECTION: item 2 says stage M's artifact count is holes times attempts and therefore fits no registry entry. `stage-out-count` counts DECLARED outputs and stage M declares TWO, statically; the per-attempt directories are undeclared scratch, exactly as the reference's are. What varies at run time is how many times ONE delegation tag is executed, and NO registry column has ever carried that number for ANY stage. Stage H's probe rows and stage N's mutant rows are already that dimension and they live in the `Loop` payload. So the registry needs no new shape and item 2 overstates the gap; item 3 is correct as written and is what this proposal answers. The design is: one new registry KIND tag (`stage-fanout`), ONE new `Ctl` arm carrying the wave's own state pair, and an exit mapping read off the reference rather than chosen. FOUR OF THE WAVE'S SIX EXIT CODES MAP TO `Finished`, which is the clause a wrong port breaks: treating a non-zero code as a stage failure would halt the run where the reference continues and stage N would never run. Code 4 records `stopped` and not `failed`, because driver-spec section 10 defines the condition. TWO DRIFTS FOUND WHILE READING, both inside the driver tree: `stage-provision-ref?` returns false for M while the comment above it names M, and `wave.llmll` writes ONE of stage M's two declared outputs. The second is graded work and not tidiness: two of the clause 2 comparator's reported classes read `wave.json`. One payload widening is required and only one."
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

> **CORRECTED at Rev 2: neither row is filled, and filling either would have been
> the defect this proposal warns about elsewhere.**
>
> **`stage-prompt 13` stays empty.** The reference renders `stage-M-fill.md`; the
> port renders no template for stage M. `begin-attempt` in
> [`wave.llmll`](../../tools/llmll-driver/wave.llmll) hands the agent two things,
> `brief.json` and an output path, which is the checkout-brief-is-the-sole-channel
> discipline this repository keeps everywhere else. Cover cell W1 in
> [`wave_cover.py`](../../scripts/wave_cover.py) asserts exactly those two
> arguments, off the `wd/h0-a0/argv.json` the stub agent records. **A filled row
> would state a delegation shape the code does not use.** This proposal read the
> reference for that row and did not read the port. The registry comment now
> carries the reason, and it also warns that `stage-prompt` and `stage-agent-label`
> are empty for stage M for two DIFFERENT reasons which a reader must not merge.
>
> **`stage-provision-ref? 13` stays false.** See the Rev 2 note in §3.4.

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

> **ANSWERED at Rev 2, and the row does not move.** The check ran and the answer is
> **oversight**: `_provision_reference` runs inside `stage_M_wave`'s per-hole
> closure, `wave.llmll` does not provision, and **no document anywhere records the
> omission**. Not `wave.llmll`'s header, not `wave_cover.py`, not
> [`driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md). A decision leaves
> a record and this one left none.
>
> **The row stays FALSE anyway, and §3.2 above prescribed the wrong move.** The port
> does not provision the language reference. Setting the row true would make the
> table claim a behaviour the code lacks, which is the defect class this section
> exists to repair rather than to commit in the other direction. The row now carries
> a comment naming the gap, the call site, and the three documents that are silent
> about it.
>
> **The fix is not blocked, and the comment says that too.** Cover cell W1 asserts
> the agent receives two ARGUMENTS; provisioning puts two files in a directory, so
> the cell does not forbid it. Closing the gap is a port change with its own cover
> row, and it is not (a2)'s.

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

> **SHIPPED at Rev 2, with one arm this section did not predict.** The decision held:
> one outer arm carrying the inner state, no flattening, the wave keeps its twelve
> arms. Two details moved.
>
> **`Fan` carries a start clock beside `k`.** The shipped arm is
> `(| Fan (int, (int, (Wv, WCtl))))`. The second `int` is the stage's start time,
> which `fan-exit` needs to hand `to-summed` and which the wave does not track.
>
> **`Ctl` gained a SECOND arm, `FanBoot`, and it exists for a guard.**
> `stage_M_wave` emits the AST tree only when the tree is absent or `--force` is set.
> **Re-emitting would reset every hole a partial run had already filled**, which
> would destroy the property §10 case 2 makes the argument for: a halted stage M
> leaves no manifest row, re-runs, and re-derives the hole list from the tree, so a
> filled hole is no longer a hole. Resume at hole granularity is free only while the
> tree survives. The guard needs the tree's own hash before the wave seeds, and a
> `Command` result cannot be inspected inside the arm that issues it, so the probe
> needs a state of its own. `FanBoot (int, int)` carries `k` and the start clock,
> `started-step` issues `wasi.fs.sha256` on the declared tree path, and
> `fanboot-step` prepends the emit only when the hash is empty and `--force` is
> absent. **This proposal named the guard in §5 and did not notice it needed an
> arm.** The §4.3 reasoning it rests on is unchanged; the arm count is two.

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

> **SHIPPED at Rev 2, with three corrections to this section.**
>
> **The split named the wrong survivor.** `wave-init` does not keep the argv path
> under its own name. It splits into `wave-seed [c: WaveCfg]`, which the stage arm
> enters past the argv parse, and `wave-boot-args [as: list[string]]`, which the
> `wave` sub-command takes. No `wave-init` remains. **No wave arm changed**, which is
> what this section claimed and what the fold had to achieve.
>
> **`err0` and `proto0` now have a sequencer source, so the last table row is
> closed.** `--error-budget` and `--protocol-budget` shipped on the sequencer with
> the same must-be-at-least-1 guard the wave carries, and `fan-cfg [c: Cfg i: int]`
> reads them off `Cfg`. Risk 1 is resolved rather than carried.
>
> **The emit is not a command issued ahead of `wave-seed`. It is `FanBoot`'s step.**
> The guard needs the tree's hash first, which needs a state; see the Rev 2 note in
> §4. The copy and the emit are one sequenced `Command` in `fanboot-step`, ahead of
> the seed's own. **A failed emit is still `failed`**, and the fold reaches it
> through the same terminal code 2 as an empty tree, because the emit's response is
> consumed by the holes read that follows it. The reference separates the two causes
> in its message text and the port's detail names both rather than guessing which
> one fired.

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

> **SHIPPED at Rev 2. The payload widening is exactly the one named here; the write
> site is one step later than this section states.** `Wv` gained `fills: Json` and
> the two per-hole terminal arms append a row. The write lands in **`sealing-step`**,
> not in `seal`. `seal` issues the verify command and returns a `Sealing` state;
> `sealing-step` consumes that transcript and returns `WEnding`. **`WEnding` is not
> terminal, so the command `sealing-step` returns IS performed**, while the command
> the `WEnding` arm returns on the way to `WDone` is the one RC-4 drops. Writing from
> the terminal arm would construct the file and never put it on disk. That is the
> failure the sequencer's own halt path records, and this section's "before
> `WEnding`" is one arm too early to be safe.
>
> **Cover cells W8 and W9 were added for the file**, so `wave_cover.py` is nine cells
> and not seven. W9 also refuted an off-by-one this design did not reach: `at-next`
> increments `n` when an attempt has FINISHED, so a hole closing at a budget of 2
> records `n = 2` after two attempts, and the accept path names the attempt that
> succeeded instead. The `fills` rows carry the corrected field.

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

> **MEASURED at Rev 2, clause by clause.**
>
> **Clause 1 is not met and stage M is not why.** `stage-ported?` is **not deleted**.
> Clause 3 of the unification proposal's completion test needs E, G2, J and L out of
> `spine.llmll` as well, and those four are still a seventeen-arm counter there. Row
> 13 is now **dead and unread**, because `started-step` consults `stage-fanout`
> before it consults this table. The row is recorded as dead in the table's own
> comment rather than flipped, because flipping is cosmetic and the clause asks for
> deletion. **Stage M's share of clause 1 is discharged; the clause is not.**
>
> **Clause 2 is met.** Both declared outputs are real. `12-wave/wave.json` carries
> one `fills` row per hole and cells W8 and W9 assert it.
>
> **Clause 3 reads nine cells now, not seven.** All seven original cells are
> unchanged in what they assert, which is what the fold had to achieve rather than a
> convenience; W8 and W9 are additions for the record file.
>
> **Clause 4 is met and the orphan set was re-measured, not deduced.** `_programs()`
> returns `{"sequencer"}` and the orphan set is unchanged at `{liveness, shell}`.
> `fill` and `token` now reach a program through the sequencer's import of `wave`:
> one link longer, same answer.
>
> **Clause 5 shipped and no cell drives it end to end.** `fan-join` maps codes 0, 1,
> 3 and 5 to `to-summed`, which is the completing path, and the mapping site carries
> the reason as a comment. What grades it is split: M1 in
> [`driver_ll_cover.py`](../../scripts/driver_ll_cover.py) is the only cell that
> drives stage M through the stage loop and it exercises the **failed** path, while
> W2 and W9 grade a finding at the wave level. **A findings run that continues into
> stage N is asserted at the source and not at the seam**, and that is worth knowing
> before anyone reads clause 5 as covered.

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

> **CORRECTED at Rev 2. Obligation 1 rests on a false premise, and the paragraph
> directly above is the evidence against the two paragraphs above it.** This
> obligation says the `[EXIT-RANGE]` post discharges body-faithfully today, that a
> non-literal arm would break that, and that the remedy is a new proved `def`
> carrying the same post. The first claim is false, so the second does not follow and
> the third was never needed.
>
> **MEASURED from the sequencer's `.verified.json` sidecar**, which is generated and
> is not in the index, so it is named and not linked.
> `drv-status`'s post sits at `display_level: asserted`. It carries **no
> `body_faithful` key and no `verified_hash`**. It has never been discharged. The
> contrast in the same sidecar is `exit-code`, whose `[EXIT-NOVACUOUS]` post carries
> `body_faithful: true`, `display_level: verified` by liquid-fixpoint, and a
> `verified_hash`. **No new proved `def` was added and none was needed.** The
> sentence "every existing arm returns an int literal" is also wrong: the `Done` arm
> already held the inline clamp `(if (< c 0) 1 (if (> c 255) 255 c))` before the fold.
>
> **What actually constrained the arm is a different gate, and the compiler named
> it.** `drv-status` is a `def`, so **strict-core admissibility** applies to its arms
> and forbids a call to a callee that is not body-faithful. `llmll check` rejected
> `((Fan f) (wave-status (fn-ws f)))` with `callee 'wave-status' is not body-faithful
> and not in the trusted prelude`, emitted from
> [`Diagnostic.hs`](../../compiler/src/LLMLL/Diagnostic.hs). `wave-status` is a
> `def-shell`. **The two gates are separate and this proposal merged them.**
> `isCoreBodySyntactic` in [`Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs) admits
> `EApp` syntactically, so the shape passes the syntactic leg; admissibility is the
> leg that rejected it. A design that reasons only about VC discharge will keep
> missing this, because the rejection happens at `check`, before verification runs.
>
> **The shipped resolution is simpler than the remedy above.** `fan-step` leaves
> through `Ending` for **both** values of `k`: the standalone run (`k < 0`) goes to
> `Ending code` and the folded run goes to `fan-exit`. A `Fan` state is therefore
> **never terminal**, `drv-status` reads the code off `Done` with the clamp it already
> had, and the `Fan` and `FanBoot` arms stay integer literals like every other
> non-terminal arm. `Ending` and not `Done` for a second reason: `drv-done?` reports
> `Ending` as not terminal, so the command handed over is performed, and on the
> ending step that command carries the `12-wave/wave.json` write. Going straight to
> `Done` would drop it (RC-4).
>
> **Nothing about the post changed, and that is the point.** The post is still
> `asserted`, still clamped by construction, and still fails in the safe direction.
> `[EXIT-NOVACUOUS]` on `exit-code` still carries the weight. **The `Fan` arm weakens
> neither, and it weakens neither by not participating.**

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

> **CORRECTED at Rev 2, against what the fold touched.** Item 8 held exactly: **no
> file under `compiler/` changed.** Five items moved.
>
> - **Item 1**, `registry.llmll`: one new `def-shell` and **zero filled rows**. Both
>   rows this proposal would have filled stay as they were, each with a comment
>   saying why. See §3.2 and §3.4.
> - **Item 2**, `sequencer.llmll`: **two** `Ctl` arms, not one, and **no proved clamp
>   `def`**. See §4 and §11.
> - **Item 3**, `wave.llmll`: the split is `wave-seed` and `wave-boot-args`, and the
>   `wave.json` write is in `sealing-step`. See §5 and §7.
> - **Item 5**: nine cells, not seven, and
>   [`build_smoke.sh`](../../scripts/build_smoke.sh) stage 9 builds the **sequencer**,
>   there being no wave binary.
> - **Item 7 is done.**
>   [`driver-ll-program-unification-proposal.md`](driver-ll-program-unification-proposal.md)
>   Rev 6 folds the §4.10 item 2 correction, records item 3 as the item this design
>   answered, and takes the stubbed-stage count to four.
>
> **One surface this list missed entirely.** `sequencer.llmll` grew `--error-budget`
> and `--protocol-budget`, which risk 1 named as an unresolved source and did not
> place on this list. `common.llmll` also gained `jset`, collapsed out of
> `manifest.llmll` and `wave.llmll` when the sequencer opened both.
>
> **A consequence outside the driver tree, found after the fold and recorded here so
> the list is complete.** Stage 9 of the build gate has a reference half and an LLMLL
> port half. The fold changed the reference and not
> [`buildsmoke.llmll`](../../tools/build-smoke/buildsmoke.llmll), which kept building
> `wave.llmll`; that now emits a library and no binary, so the port rejected an
> unmutated tree and `main` went red. **Every TOOL-LL gate is three artifacts**: a
> reference, a port, and a differential cover that runs both. This list traced the
> driver's covers and not the build gate's.

## 13. Risks

**1. The two retry budgets have no sequencer source.** Classify: scope. The
sequencer's `Cfg` carries no `--error-budget` and no `--protocol-budget`. The wave's
cover pins both flag names. The reference has one knob, `semantic_retries`, and the
port has two, which 4e settled and this proposal does not reopen. **Bite: complicates
(a2), does not block it.** Two flags on the sequencer mirror the wave's. Note the
consequence for the unification proposal: §3 assigns the operator CLI surface to job
(b) and lists four flags, and these two belong to (a2), so that list is short by two.

> **RESOLVED at Rev 2, by the move this risk proposed.** `--error-budget` and
> `--protocol-budget` shipped on the sequencer, with the identical "must be at least
> 1" guard the wave already carried, and `fan-cfg` reads them off `Cfg`. The
> consequence this risk named was correct and the unification proposal's Rev 6 folds
> it into its §3.

**2. Deleting the wave's `def-main` moves the 4e acceptance cover.** Classify:
verification-ergonomics. The sub-command keeps every cell and changes how they are
invoked. **Bite: complicates.** The cover must be re-run and seen to pass before (a2)
claims clause 1. A cover that is edited and not re-run proves nothing.

**3. `drv-status` is contract-checked and not proved.** Classify:
verification-ergonomics. **Bite: complicates.** The §11 obligation 1 remedy keeps the
post discharging. Skipping it leaves the arm's return value unconstrained while the
post still reads as if it were checked, which is worse than an unchecked arm.

> **CORRECTED at Rev 2. The risk is real and its second sentence contradicts its
> first.** A post that is contract-checked and not proved is not "discharging", so
> there was nothing for the §11 remedy to keep. The post is at `asserted` in the
> sidecar and always has been. **Bite: none, as shipped.** The `Fan` arm returns a
> literal and never reaches the post with a wave code, because a `Fan` state is never
> terminal; the code reaches the post through `Done`, where the clamp that already
> existed makes the declared range true by construction. The reading worth keeping is
> the one this risk states last: **a post that reads as if it were checked is worse
> than an unchecked arm**, which is why the sidecar and not the `post` form is the
> thing to read before designing against it.

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

> **ANSWERED at Rev 2: omission.** No document records the gap, and a decision leaves
> a record. **The risk survives its own answer in a changed form**: the row stays
> false, so the registry now records an unrepaired port gap rather than an
> unexplained one. **Bite: only matters at scale**, and the remedy is a port change
> with its own cover row rather than a table edit. See the Rev 2 note in §3.4.

## 14. What (a2) still owes after this design

Stage M is one of the five stubbed stages. E, J, L and G2 remain, and §4.10 item 1
measures them as a seventeen-arm linear counter in
[`spine.llmll`](../../tools/llmll-driver/spine.llmll) rather than a set of callable
functions. Porting them means mapping seventeen steps onto `Ctl` arms, and this
proposal does not touch that.

**(a2) is unblocked for stage M. It is not unblocked as a whole.** The spine's four
stages need their own scoping turn, and job (b) still waits behind all five.

> **MEASURED at Rev 2: stage M has landed, so the count is FOUR.** E, G2, J and L
> remain, and job (b) waits behind those four rather than behind five. §4.10 item 1
> of the unification proposal is untouched by this work and is where clause 3 of its
> completion test now sits. The sentence above is the last place in this document
> that says five; do not read the count off it.

## 15. Deferred theory questions

None. Three candidates were raised and all three failed the negative test, because
reading the tree answered them. The refinement-mapping question was answered by
`driver-ll-phase4-proposal.md` §6 and the sequencer's step loop. The exit-range
question was answered by `drv-status`. The outcome mapping was answered by the
reference's `require` family. Nothing is appended to
[`theory-questions.md`](theory-questions.md).

> **RE-RUN at Rev 2, and nothing is appended.** Rev 2's own three corrections each
> failed the negative test, and each failed it the same way: reading the tree
> answered them. The sidecar answered the discharge question, `Diagnostic.hs` and
> `Syntax.hs` answered the admissibility question, and `wave.llmll` with
> `wave_cover.py` answered both registry rows. **The Rev 1 exit-range entry is worth
> re-reading as a warning rather than as a closed item**: it was answered by reading
> the `post` form and not the sidecar, which is the wrong artifact for that question
> and is how §11's false premise got in. A candidate that a grep answers is homework,
> and a candidate answered by the WRONG grep is homework that has not been done.
