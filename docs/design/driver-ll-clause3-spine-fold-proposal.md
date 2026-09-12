---
name: driver-ll-clause3-spine-fold-proposal
title: "DRIVER-LL clause 3: stages E, G2, J and L into the stage loop, and the dispatch table that replaces two"
status: "Rev 1, 2026-09-12, SETTLED and NOT YET IMPLEMENTED. Answers unification completion-test clause 3, the last hard blocker on the G0 `DRIVER-LL` row. THE BRIEF ASKED WHICH REGISTRY ROWS THE FOUR STAGES NEED AND THE ANSWER IS NONE OF THEM: `stage-key`, `stage-name`, `stage-kind`, `stage-out`, `stage-out-count` and `stage-out-dir` have carried complete rows for E, G2, J and L since sub-phase 4a, because the stub injector needed them. The dimension the registry does not carry is WHICH MACHINE RUNS A STAGE, and `stage-ported?` has been standing in for it. TWO QUESTIONS THE REFERENCE SETTLED OUTRIGHT, so no design judgement was spent on them: all four stages read `ctx.workdir` and not the committed corpus, and the LLMLL driver has never had a `--self-test`. THE MEASUREMENT THAT CHANGES THE SIZE OF THE JOB: `spine-step` is ONE 18-state counter running four stages back to back (E at s=0..3, J at s=4..7, L at s=8..14, G2 at s=15..17), in an order that is not registry index order. It is a Phase-3 replay script, not four stage machines, and the stage loop needs a manifest row, an outcome and resume granularity per stage. So the counter splits into four. POSITIVE WITNESS, CONSTRUCTIBLE AT 1f5c3db: flip `stage-ported?` row 4 to true and change nothing else, and `started-step` sends stage E into `a-enter`, which is stage A's URL-fetch loop, because `stage-kind` answers `mechanical` for BOTH stage A and stage E. The false row is the only thing hiding that today. This is exactly the failure the unification proposal's section 2.5 warns of. USER DECISIONS FOLDED IN, 2026-09-12: `stage-fanout` folds into `stage-machine` rather than surviving beside it; stage G2's delegated half is filed as a roadmap row and does NOT ride in on this port; all four stages ship behind ONE version rather than four. NO PROOF OBLIGATION IS INTRODUCED: every function added is `def-shell`, and the nine proved cores in `spine.llmll` keep their contracts and their call sites. What changes is which bytes reach them."
date: 2026-09-12
author: language-team
consumers: [compiler-engineer, documentation-lead, experiment-lead, user]
---

# Clause 3: the spine fold

[`driver-ll-program-unification-proposal.md`](driver-ll-program-unification-proposal.md)
§2 requires `registry.stage-ported?` **deleted, not corrected**, and §2.5 adds the
clause that deletion alone does not satisfy: every stage writes a real artifact and
none writes a stub. [`driver-ll-stage-m-fanout-proposal.md`](driver-ll-stage-m-fanout-proposal.md)
answered the stage M half of that job and deferred this half in one line. This
proposal is the deferred half.

It is the last hard blocker on the G0 `DRIVER-LL` row. Behind it sit the clause 2
re-run, the Phase 4 close with its gap inventory, and the Phase 5 conformance claim.

## 1. The measurement that reframes the job

**The registry needs no new rows for the declared-artifact dimension.** Stages E (4),
G2 (7), J (10) and L (12) already carry complete rows in `stage-key`, `stage-name`,
`stage-kind`, `stage-out`, `stage-out-count` and `stage-out-dir`. They have carried
them since sub-phase 4a, because the stub injector wrote to declared paths and needed
to know them.

| Stage | `stage-kind` | Declared outputs |
|---|---|---|
| E | `mechanical` | `04-reconcile/SUMMARY.json` |
| G2 | `gate` | `06b-audit/audit.json` |
| J | `gate` | `09-gate/gate.json` |
| L | `gate` | `11-freeze/rfc-cov-1.txt`, `11-freeze/ROOTS.txt` |

**The dimension the registry does not carry is which machine runs a stage.**
`stage-ported?` has been standing in for it, which is why deleting it is not a
subtraction.

## 2. The four stages read the run workdir, and the reference settles it

Every one of the four reference handlers reads `ctx.workdir`. `stage_E_reconcile`
reads `04-reconcile/data` and writes `SUMMARY.json` beside it. `stage_G2_audit` reads
`04-reconcile/data/extraction-a.json` and `06-disposition/inventory-dispositioned.json`.
`stage_J_gate` reads the dispositioned inventory and writes `09-gate/gate.json`.
`stage_L_coverage` reads `10-roots/roots.llmll` and the same inventory, and writes
three files under `11-freeze`.

`spine.llmll`'s 22 hardcoded paths point instead at `experiments/rfc-swarm/data`,
which is the frozen Phase-3 corpus, with every intermediate under `/tmp/llmll-spine-*`.

**These are not the same artifacts under different names.** Stage D stages its two
extractions into `04-reconcile/data` at run time, and `registry.stage-stage-dest`
already declares that destination. Stage E's input is produced upstream in the same
run. Reading the committed corpus instead would make four stages independent of the
run they are part of, which is the opposite of what a campaign driver does.

**Two paths stay repository-relative and must not be workdir-derived.** `reconcile.py`
and the RFC-coverage script are tools, not artifacts. The reference resolves both from
its `REPO` constant and the port resolves them the same way. Confusing a tool path
with an artifact path is the error this paragraph exists to prevent.

## 3. Spine's counter does not survive, and this is the largest item

`spine-step` is one counter of 18 states running four stages in sequence: **E at
s=0..3, J at s=4..7, L at s=8..14, G2 at s=15..17**. The order is not registry index
order. It was written as a Phase-3 replay demonstration and that is the shape it has.

The stage loop needs what a single counter cannot give: **a manifest row per stage, an
outcome per stage, and resume at stage granularity.** `may-skip` decides per stage and
`to-summed` records per stage. A run that halts inside L must leave E and J recorded
`complete` and must re-enter at L, not at the reconciler.

**So the counter splits into four machines, each with its own counter starting at
zero.** The nine proved `def`s move nowhere and keep their call sites; what changes is
the shell around them. This is the operation the stage M fold performed on
`wave.llmll`, and it is why clause 3 is a sub-phase rather than a wiring ticket. The
closest sizing precedent is sub-phase 4d, which ported three stages and was its own
release.

## 4. `stage-machine` replaces `stage-ported?` **and** `stage-fanout`

### 4.1 The defect that deleting the table alone would expose

`started-step` dispatches, in order: `stage-fanout` non-zero to the wave; then
`stage-ported?`; then `stage-kind` equal to `mechanical` to `a-enter`, else
`begin-body`; else write a stub.

`a-enter` is stage A's entry. It loops over `a-urls` and fetches over
`wasi.http.get`. **`stage-kind` answers `mechanical` for both stage A and stage E.**
So the `mechanical` branch is keyed on a label two stages carry and implemented for
exactly one, and the false `stage-ported?` row is the only thing hiding it.

The other branch is wrong too. G2, J and L are `gate`, and `gate` has never been
dispatched anywhere, because all three stages are unported. Ported under today's code
they would reach `begin-body`, the delegated path, which reads a prompt template. A
gate delegates nothing.

### 4.2 One table, four values, no default

```
stage-machine : [i: int] -> string

  0                          -> "intake"    ; the URL fetch loop
  4, 7, 10, 12               -> "spine"     ; the four machines this proposal lands
  13                         -> "wave"      ; stage M
  1,2,3,5,6,8,9,11,14,15     -> "delegate"  ; the ten agent-delegated stages
```

`started-step` then reads one table and takes one of four arms. This satisfies clause
3 as written, removes the stage E defect, and keeps the discipline
`test_driver_ll_a2.py` pins: `started-step` routes on the registry and never on an
index test.

### 4.3 `stage-fanout` folds in, by user decision 2026-09-12

`stage-fanout` returns a non-zero int for stage M alone and exists to route stage M
ahead of the kind test. Once `stage-machine` answers `wave`, the two tables answer the
same question. Keeping both is two dispatch tables where one will do, and the second
is the kind of row that becomes incorrect quietly.

**The cost is named rather than discovered.** `test_driver_ll_a2.py` asserts that
`stage-fanout` is non-zero for exactly stage M and that `started-step` reads it before
`stage-kind`. Both assertions move to `stage-machine`. The property they protect is
unchanged: stage M is routed by a table, before any kind test.

## 5. `stage-kind` stops deciding control flow

After this change `stage-kind` is read at two sites, the stage banner line and
`complete-row`'s manifest field. Both are reporting.

That is the honest state. `mechanical`, `agent` and `gate` describe what a stage **is**;
`stage-machine` decides what **runs** it. Conflating the two is what produced the
stage E defect in §4.1, and the comment above `stage-kind` should say so.

## 6. `--self-test` is out of scope

**Measured: the LLMLL driver has never had a `--self-test`.** A grep over
`tools/llmll-driver/` finds the string only inside a crux file's `:source` text.
`self_test()` belongs to the Python driver, and campaign §5.3 lists `--self-test`
among the operator CLI surface that job (b) ports. The user scoped job (b) out of G0
on 2026-09-12, so clause 3 does not touch it.

**What does change is that the guarantee becomes unreachable in the meantime.**
`spine.llmll` is the only thing in the tree that replays the committed corpus, and
re-targeting it at the workdir ends that. This proposal does not preserve it, because
preserving it means two code paths for four stages. The loss is named here so it is a
decision, and **Phase 4's gap inventory owes it an entry**.

## 7. Stage G2's delegated half is a roadmap row, by user decision 2026-09-12

`stage_G2_audit` splits its work three ways in its own docstring: mechanical-and-STOP,
mechanical-and-reported, and **delegated** — whether a stated reason matches the clause
it cites, which "is a reading, so an agent does it". `spine.llmll` ports the strength
half only, the pinned RFCs being deliberately absent from this repository.

**Fold G2 as it stands.** Landing the delegated half inside clause 3 would be a new
agent-delegated stage arriving under a port, which the registry refused at stage I and
at stage O, and which the stage M agent contract refused for `wasi.proc.run`'s missing
confinement parameter.

**The consequence changes what the next milestone means, and must reach the clause 2
pre-registration before the run rather than after it.** After clause 3, a clause 2 run
will still carry a disclosed G2 divergence. "Full clause 2" then means all sixteen
stages running real bodies, not all sixteen agreeing with the reference on every
decision class. `clause2_compare.py` already reports rather than thresholds five of
six classes, so the shape exists.

## 8. Edge cases

1. **Stage E runs with `04-reconcile/data` absent or holding no extractions.**
   Upstream stage D staged nothing, or a resumed run lost the directory. `reconcile.py`
   exits non-zero and the stage records **failed**. The reference's guard is a plain
   `require`, so driver-spec §4 makes it `failed` and never `stopped`. Channel:
   contract, through `stage-e-outcome`; `stage.record-outcome` proves the two halt
   channels cannot collapse.

2. **Stage J's gate fires: a characteristic-core row is dispositioned out.** J writes
   `09-gate/gate.json` **and then** halts `stopped`. The reference uses `require_spec`,
   so driver-spec §4:125-127 makes it spec-defined. The ordering is the sharp part and
   `spine.llmll` already records it: the report is written before the halt is reported.
   A port that halted first would lose a declared artifact, which is the defect cover
   cell H1 exists for. Channel: contract, through `stage-j-outcome`.

3. **POSITIVE WITNESS for the dispatch defect, constructible at `1f5c3db`.** Flip
   `stage-ported?` row 4 to `true` and change nothing else. Run with `--only E`.
   `started-step` reads `stage-fanout 4` (zero), `stage-ported? 4` (now true),
   `stage-kind 4` (`mechanical`), and enters `a-enter`, stage A's URL-fetch loop, for
   the reconciliation stage. With no `--rfc-url` the loop is empty and stage E
   completes having reconciled nothing. Under this proposal `stage-machine 4` answers
   `spine` and the stage runs the reconciler. Channel: **spec is silent (gap)** today,
   and the new dispatch after.

4. **A resumed run halted inside stage L.** L declares two outputs and writes three
   files; `trust-report.json` is undeclared scratch. E and J stay `complete` and are
   skipped; L re-runs from its own counter zero; `--force` re-runs all. Channel: trust,
   through `may-skip` and the digest sweep, both already generic. This case is why the
   counter must split: one counter would restart E.

5. **Stage G2 reads an inventory whose rows cite no `cid` present in the extraction.**
   The reference computes an uncited list and reports it. The port reports the same and
   does not halt. Channel: **spec is silent (intentional)** — driver-spec §7 attaches
   validation to a delegated output's shape, and an uncited row is a finding about
   content. Inventing a halt here would be new behaviour on a port.

## 9. Verification mapping

**No proof obligation is introduced.** Every function added is `def-shell`: dispatch,
path construction, artifact reads, process spawns, JSON assembly. Per `LLMLL.md`
§5.3.3 nothing enters or leaves QF-LIA, and nothing escapes to Lean.

The nine proved `def`s in `spine.llmll` — `stage-e-passes`, `stage-e-outcome`,
`stage-j-pins`, `bad-barrier-count`, `stage-j-outcome`, `stage-l-passes`,
`stage-l-outcome`, `stage-g2-pins`, `stage-g2-outcome` — keep their contracts and
their call sites. The re-targeting changes which bytes reach them, not what they
decide. **`spine.llmll`'s frozen `safe` verdict in `EXPECTED_VERDICTS.json` must hold,
and a changed `.verified.json` sidecar is the signal that something moved that should
not have.** That is the measurement the stage M agent contract used.

**What changes is trust.** Four proved cores acquire their first **live** caller;
until now they have been called only from a replay against frozen data. This is the
disclosure `wave.llmll`'s header carries for its abstraction functions, and it carries
no proposition for a prover.

## 10. Affected surface

1. `registry.llmll`: `stage-ported?` deleted; `stage-fanout` deleted; `stage-machine`
   added; the `stage-kind` comment rewritten to say it no longer decides control flow.
2. `spine.llmll`: the 18-state counter splits into four machines; the 22 hardcoded
   paths become workdir-derived; `reconcile.py` and the coverage script stay
   repository-relative.
3. `sequencer.llmll`: `started-step` dispatches on `stage-machine`; one new `Ctl` arm
   carries the spine state; the three exhaustive `Ctl` matches each gain an arm.
   **`drv-status`'s new arm must be an integer literal**, because `:status` is a
   strict-core `def` and its arms may not call a `def-shell`; `llmll check` rejected an
   earlier `Fan` arm with exactly that message.
4. `scripts/driver_ll_cover.py`: cells for all four stages. The cover has none today,
   and none of the four has ever been driven through the stage loop.
5. `scripts/tests/test_driver_ll_a2.py`: the `stage-fanout` assertions move to
   `stage-machine`.
6. `scripts/tests/test_driver_ll_4a_cover.py`: reads the `stage-kind` table.
7. `tools/llmll-driver/README.md`: the "Four stages still write a stub" paragraph and
   the "`stage-ported?` is the switch" sentence both die with the table.
8. **Not affected:** `compiler/src/LLMLL/`, `LLMLL.md`, `docs/llmll-ast.schema.json`.
   No compiler change, no builtin, no schema change.

## 11. What rides in the same release, by user decision 2026-09-12

**All four stages ship behind ONE version, not four.** Precedent supports it: 4c landed
D, F and G together and 4d landed H, K and N together. The four are four ports, and
four release ceremonies for one clause is the avoidable cost.

Three items already in the routing queue belong in the same pass, because clause 3
forces the files open anyway:

- `tools/llmll-driver/README.md`'s three edits owed from v0.23.3 — the missing test
  file in its no-toolchain tier list, the `wave` sub-command's two new required flags,
  and stage M's declared inputs — land beside the `stage-ported?` paragraph this
  proposal deletes.
- The roadmap bookkeeping the scope decision created: **job (b) as its own row**,
  **stage G2's delegated half as a row**, and the G0 row's Next Action, which still
  sequences (b) before Phase 5.
- The v0.23.2 Shipped Releases row says `272 pytest` where `CHANGELOG.md` and commit
  `0c90cfa` both say 274.

**Recommended commit order inside the one branch.** The shared risk is the
`stage-machine` dispatch, not any individual stage. Land the dispatch **plus stage J**
first: J is the cheapest probe, with one artifact read, one proved computation, one
JSON write and one spec-defined halt, and no process spawn. Then E, then G2, then L.
A wrong dispatch shape is then discovered on the first stage rather than the fourth.

## 12. Risks

1. **The four machines are four ports, not one.** Classify: scope. They share no
   control flow; the counter's arms are stage-specific throughout. **Bite: this is the
   size of the job.** A plan that treats it as one unit will underestimate it.

2. **`PROC-TIMEOUT-1` reaches two of the four stages.** Classify: verification. E spawns
   `reconcile.py`; L spawns `llmll verify --trust-report` and then the coverage script.
   `spine.llmll` already passes a 120-second timeout to the reconciler and **that
   timeout is inert in a built program**: measured, a one-second timeout against a
   thirty-second child exits 0 reporting thirty seconds. A hanging tool hangs the
   driver with no budget-overrun halt. The reference's `subprocess.run` carries no
   timeout at all, so the port reproduces rather than hardens. **Bite: complicates**,
   and Phase 4's gap inventory owes it an entry. Do not repair it inside clause 3.

3. **`reconcile.py` and the coverage script remain a permanent Python dependency.**
   Classify: scope. **Bite: complicates the Phase 5 claim**, which must say that "the
   LLMLL driver replaced the Python driver" is true of `rfc_to_implementation.py` and
   false of these two tools.

4. **Replaying the committed TFTP corpus becomes unreachable.** Classify:
   verification-ergonomics. See §6. **Bite: complicates**, and it is a deliberate loss
   the gap inventory should record.

5. **G2's delegated half is a disclosed divergence that survives into clause 2.**
   Classify: spec-drift. **Bite: complicates the next milestone**, and "full clause 2"
   needs defining before the run rather than after it.

6. **Two registry comments are already incorrect and this proposal does not repair
   them separately.** Classify: spec-drift. `registry.llmll` says "E waits on a
   reconcile.py invocation" while `spine-step` already invokes it; what E waits on is a
   **workdir-parameterized** invocation. **Bite: does not block**, and both comments die
   with `stage-ported?`.

## 13. Acceptance

1. `registry.stage-ported?` and `registry.stage-fanout` are **deleted**, and
   `stage-machine` is exhaustive over the sixteen stages with no default arm.
2. `started-step` reads `stage-machine` and no other table to choose a machine, and no
   arm tests a stage index.
3. Stages E, G2, J and L each write their declared outputs from the run workdir, each
   record their own manifest row, and none writes a stub.
4. A run halted inside stage L leaves E and J recorded `complete` on resume, and
   re-enters at L.
5. Stage J's gate writes `09-gate/gate.json` **before** it halts, and records `stopped`
   rather than `failed`.
6. `spine.llmll`'s frozen `safe` verdict holds and no `.verified.json` sidecar changes.
7. `scripts/driver_ll_cover.py` gains cells for all four stages, and the existing 63
   pass unchanged.
8. Unification completion-test clause 3 and the every-stage-writes-a-real-artifact
   clause both close. **G0 does not close here**: the clause 2 re-run, the Phase 4
   close with its gap inventory, and the Phase 5 claim all follow.
