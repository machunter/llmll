---
name: clause-2-pre-registration
title: "DRIVER-LL acceptance clause 2: run plan and pre-registration"
status: "Rev 5, 2026-09-11. RUNNING, AND THE RUN IS BOUNDED. Rev 5 adds section 6.3 BEFORE the run, not after: registry.stage-ported? still answers false for E, G2, J, L and M, so five stages write STUBS, and EVERY reported class that has an oracle reads one of them. Divergence in R2 to R6 is a KNOWN CONFOUND reported as STUBBED STAGE, never as disagreement. The thresholded half is unaffected because stubs record complete and the only byte floors, B at 200 and C at 400, are both ported. THIS RUN CLAIMS live evidence for the 11 PORTED stages and the thresholded set, against a real agent for the first time. It does NOT claim a full clause 2 result: section 8 Success needs every deterministic class to agree and five read stubs. A PASS here is a pass over 11 of 16 stages and the record says so. A full clause 2 run waits on job (a2) of driver-ll-program-unification-proposal.md. Rev 4, 2026-09-11: Rev 4 amends section 10 ONLY: the G0 roadmap row named neither this document nor clause2_compare.py until dd5b4fb, and it names both now, so Rev 2's 'the roadmap names neither' sentence is retired as CLOSED rather than left standing. The documentation-lead pass that made that sentence false named it as owed BEFORE committing, which is the first time this campaign caught RECORD-FRESH-1 in front of a commit instead of behind one. Rev 3, 2026-09-11: Rev 3 amends 6.2 ONLY, on a compiler-engineer finding that 6.2 was not implementable as Rev 2 wrote it: RUN-PROVENANCE.json now declares `model` as its own required field, six fields in all, because a checker without it must search argv for a model name and that needs a catalog, which is the [V7-NO-HARDCODE] failure. The pin check is stated as a decidable rule over argv ELEMENTS, never over the joined string. Rev 3 also records what Rev 2 omitted and an operator would have found during the expensive run: argv is the ONLY channel to the agent, because wasi.proc.run has no env parameter (PROC-ENV-1), so an environment-variable pin does not satisfy the obligation. Rev 2, 2026-09-10: Rev 1 said no comparator existed; clause2_compare.py merged at 0b0a024 the same day and never touched this file, which is the RECORD-FRESH-1 defect; the second record in this campaign MEASURED to show it, beside driver-ll-phase4-RESTART.md. Section 6 is now 6.1, the comparator as built, and 6.2, a NEW obligation: the live run pins its model in the agent invocation and records the invocation in an operator-written RUN-PROVENANCE.json. Section 6.2 does NOT repair section 4.2, which is a statement about the oracle and stands. Section 9 marks the comparator cost SPENT, because a cost section that lists paid work makes a reader budget it twice, and names the one piece of engineering 6.2 leaves open. The driver does not change for 6.2, BY DECISION: the program under test at its own acceptance run must be the program 4f shipped at e49e968. Two comparator cells are NOT CHECKED and neither holds the run: T5 (no committed run carries a per-stage MANIFEST.json) and T2b (no artifact defines the check). Rev 1's five requirements are kept VERBATIM and the built tool differs from them in both directions; the 6.1 table records both. Rev 0 put a replay-or-live choice to the user; language-team ADJUDICATED it as live against proposal section 2.3, so section 5 is rewritten and the choice is gone. The adjudication found the disagreement is WIDER than Rev 0 measured, five of six decision classes and not three, and proposal Rev 16 answers it by splitting thresholded from reported. Section 4.1, the missing MANIFEST.json, is RETIRED as a gap: stage status is clause 1a oracle. Sections 4.2 and 4.3 stand."
date: 2026-09-10
author: experiment-lead
consumers: [user, language-team, compiler-engineer]
---

# Acceptance clause 2: run plan and pre-registration

## 1. What clause 2 asks for

Proposal §2.4: one real campaign run against a target already run in Python, judged on
**decisions rather than bytes**. Six decision classes are named. Artifact *shape* is
checked by the same predicates the Python driver applies; artifact *content* is not
compared.

§8.1 sets this as the gate for retiring `scripts/rfc_to_implementation.py` (2032 lines).
It rejects `self_test()` for the purpose, because `self_test()` replays the mechanical
stages only, A, E, G2, J and L, which is five of fifteen.

## 2. The target: RFC 826, and the reason is not richness

Two committed runs exist. **`runs/rfc826/` is the only valid oracle, and the deciding
fact is not its file count.**

`runs/rfc4648/` stopped at gate J, so it never reached the wave or the mutation stages.
`runs/tftp` (in `examples/tftp_rfc1350/`) is disqualified by its own record: RESULTS.md:9-10
says its inventory, dispositions and root contracts "were authored by hand across earlier
sessions and by me; only the fill wave was agent-driven."

`runs/rfc826/` states the opposite at RESULTS.md:13-16: "This run put a fresh RFC through
all fifteen stages with no human authoring at any step. **I wrote none of these
contracts.**"

**Pinned by the oracle:** 2026-07-25, compiler v0.14.67, driver
`scripts/rfc_to_implementation.py`, stages A to O, source
`https://www.rfc-editor.org/rfc/rfc826.txt`, sha256 `01bc62fe…c8a6`, 470 lines.

**A figure in that file is known incorrect.** Its comparison column cites TFTP coverage at
62/65 = 95.4%. That figure was later re-derived as 78.5%. The ARP column (42/76 = 55.3%)
is not affected. Do not cite the TFTP column from this file.

## 3. What the oracle actually records

Read from the committed artifacts, not from prose.

| Decision class (§2.4) | Oracle artifact | Recorded value |
|---|---|---|
| Each stage's recorded status | **none** | see §4.1 |
| Gate verdict and the condition it names | `gate.json` | `characteristic_core.dispositioned_out: []`, `exclusions_outside_barrier_list: []`; gate J PASS |
| Reconciliation figures stage E pins | `reconciliation-summary.json` | `a_only 5`, `b_only 1`, jaccard `0.8551`, Cohen's kappa `0.824`, compared 26, identical 22 |
| Coverage exit status stage L pins | `RESULTS.md` | RFC-COV-1 PASS, 39/39 Encoded, 19/19 core |
| Wave filled-versus-finding partition | `wave.json` | 22 fills: **21 `filled`, 1 `checkout-failed`** |
| Retry-budget accounting | `wave.json` | `attempts: 1` on 21 fills, `null` on the `checkout-failed` one |

## 4. Three gaps found at Rev 0. One is RETIRED by the Rev 5 adjudication; two stand

### 4.1 One decision class of six has no oracle. RETIRED, see §5

**Neither committed run carries `MANIFEST.json`.** The Python driver writes it
(`scripts/rfc_to_implementation.py:1731`, `:1911`) into the run workdir, and the workdir
was not committed. `MANIFEST.json` is where stage status lives.

So "each stage's recorded status", the first class §2.4 names, cannot be compared against
either committed run.

**RETIRED as a gap by §5.** Stage status is clause 1a's oracle, checked hermetically as α of
the manifest over the full transition cover. Clause 2 never owned the class, so its absence
from the committed runs is not a defect in clause 2. The paragraph is kept because the
measurement is correct and the inference from it was not.

### 4.2 The model behind the oracle is not pinned

The agent command appears once, at `RESULTS.md:175`:

```
--agent-cmd 'claude -p "$(cat {prompt})" --allowedTools "Read,Write,Bash" --permission-mode acceptEdits'
```

The **binary** is named. The **model** is not, and `claude -p` resolves to whatever the
default was on 2026-07-25. `PROVENANCE.json` records the RFC source only: url, file,
sha256, lines. No artifact in the run directory carries a model identifier.

So the oracle's agent cannot be reproduced. It can only be re-sampled with a different
model, which confounds port fidelity with model change.

### 4.3 n is 1, and the agent's decisions are stochastic

`runs/rfc826/` is one run. Its wave partition is 21 filled and 1 checkout-failed at one
attempt each. Nothing in the campaign establishes that a second run reproduces that
partition, and the one `checkout-failed` is a contention event rather than a property of
the RFC.

**A strict decision-equality test therefore fails by construction**, for reasons that have
nothing to do with whether the LLMLL port is correct.

### 4.4 The finding

**Clause 2 as worded is not satisfiable against the committed oracle.** This conclusion
SURVIVES the §5 adjudication, and its reasons changed.

Rev 0 rested it on three gaps. §4.1 is retired: that class belongs to clause 1a. §4.2 and
§4.3 stand. The adjudication then found a fourth reason, larger than all three: agreement is
unobtainable for **five** of the six classes, because gate J and stage L compute their
verdicts from agent-produced inputs that a live run re-samples.

The defect was repaired by proposal **Rev 16**, which splits thresholded from reported.

## 5. ADJUDICATED: clause 2 is live, and Rev 0 put a false choice

**Rev 0 of this document asked whether clause 2 means a replay of the committed artifacts or a
live run. `language-team` settled it against §2.3, and the answer removes the question.**

Clauses 1a and 1b already exercise all fifteen stages hermetically, over a stub agent and a
stub `llmll` (`scripts/tests/test_rfc_pipeline_integration.py`, and the 62-cell transition
cover). **A replay of committed artifacts is clause 1a's oracle, not clause 2's.** Adopting
it would delete clause 2's content and leave the campaign with no live evidence. §2.4's own
title, "Clause 2, the live oracle", says so, and Rev 0 did not read it.

§8.1's phrase "a complete run reproduces a committed campaign's artifacts" reads as replay
language and is what misled Rev 0. Read against §2.3, "complete" contrasts with
`self_test()`'s five of fifteen, not with "live".

**The adjudication also found a defect Rev 0 missed, and it is larger than the three gaps in
§4.** Agreement is unobtainable for five of the six decision classes, not three. Gate J
computes its verdict from the inventory the agent produced, and stage L from the frozen set
the agent produced. A live run re-samples the agent, so those inputs differ and the verdicts
are incomparable **even when the port is exact**.

Proposal Rev 16 amends §2.4 accordingly: a **thresholded** set that clause 2 fails on, and a
**reported, NOT thresholded** set covering all six classes. §4.1's missing-`MANIFEST.json`
finding is thereby retired as a gap: stage status is clause 1a's oracle and was never clause
2's to own. §4.2 and §4.3 stand, and are now the stated reason the agent-determined classes
are reported rather than thresholded.

## 6. What must exist before the run

### 6.1 The comparator. BUILT, and the gate is down

**Rev 1 said no comparator existed. That measurement is now out of date.** The comparator
is `experiments/rfc-swarm/tools/clause2_compare.py`, 382 lines, merged at `0b0a024` on
2026-09-10. `scripts/tests/test_clause2_compare.py` carries 17 tests and three negative
controls: gate-removed, empty-population and floor-drift.

The comparator is the deliverable that gates the run, not the run itself. It must:

1. Read the LLMLL driver's `MANIFEST.json` rows. Complete rows carry
   `{status, kind, seconds, outputs}`; halt rows carry `{status, detail, outcome}` plus
   `clause` (`tools/llmll-driver/manifest.llmll`, the row-schema comment).
2. Read the oracle artifacts in §3 and extract each recorded value.
3. Compare per decision class, and **report per class**, never as one score.
4. Report the §4.1 class as **NO ORACLE** rather than as agreement.
5. Apply artifact *shape* predicates only, per §2.4's last sentence. Never compare content.

**The five requirements above are the Rev 1 list, kept verbatim. The built tool does not
match that list in either direction, and the table records both differences.** Two cells
implement checks this section never asked for. Two cells are `NOT CHECKED`.

| Requirement | Cell | State |
|---|---|---|
| 1. Read `MANIFEST.json` rows | `T1` | implemented |
| 2. Read the §3 oracle artifacts | reported set, `R1` and after | implemented |
| 3. Report per class, never one score | `Report`, one line per cell | implemented |
| 4. Report the §4.1 class as NO ORACLE | `R1` | implemented |
| 5. Shape predicates only, never content | `T4`, with `T0` guarding its floor table | implemented |
| not in the Rev 1 list | `T0`, drift guard that re-reads the reference's byte floors | implemented |
| not in the Rev 1 list | `T2`, FFI declaration count against the campaign bar of zero | implemented |
| not in the Rev 1 list | `T2b`, bounded authority | **NOT CHECKED**; no artifact defines the check |
| implied by §7 row 3 | `T5`, stopped-for-failed | **NOT CHECKED**; see below |

**`T5` does not hold the run.** It compares against the reference's recorded status, which
lives in `MANIFEST.json`, and no committed run carries one. §8 makes success "Clause 2
passes with its coverage disclosed", so a disclosed `NOT CHECKED` satisfies that sentence.
Record `T5` as disclosed coverage. Do not substitute a different reading for it, and do not
wait for a proposal revision before running.

**Independence is the property to protect.** The comparator re-derives the reference's
predicates and calls no part of the LLMLL driver. A comparator that asks the driver whether
the driver was right restates an opinion instead of checking it.

### 6.2 The run pins its model, and records its invocation

Pre-registered. Both obligations hold before any stage starts.

**§4.2 is not repaired by this section, and cannot be.** §4.2 is a statement about the
oracle, whose model is unrecoverable. This section adds an obligation on the live run so
that the run does not repeat the defect. §4.2 stands as written.

**The defect in §4.2 is a missing pin, not a missing record.** `claude -p` resolved to
whatever the default was on 2026-07-25. A run that writes down the default it happened to
get repeats the defect and adds a note about it.

**Pin.** The live run passes an explicit model identifier in the agent invocation. The port
takes `--agent-exe` plus repeatable `--agent-arg`
(`tools/llmll-driver/sequencer.llmll`, the `AgentCfg` flag comment), so the identifier is one
argument and not a shell string. A run that lets the agent resolve a default model is not a
valid clause 2 run.

**Record.** The operator writes `RUN-PROVENANCE.json` at the run root before the run starts.
It carries six required fields: `agent_exe`, the verbatim executable; `agent_args`, the
verbatim argument list; `model`, the declared model identifier; `llmll_version`, from
`llmll version`; `driver_commit`; and `date`, in ISO form.

**`model` is declared as its own field, because the alternative does not work.** Without the
field, a checker must find a model identifier somewhere inside `agent_args`, and that needs a
list of known model names. Such a list is a rule fitted to the values one run produced, which
is the failure `[V7-NO-HARDCODE]` exists to refute (`tools/llmll-driver/validate.llmll`, the
postcondition comment). A declared field needs no list and does not go out of date.

**The pin check, stated so it is decidable.** The declared `model` is a non-empty string. It
equals an element of `agent_args`, or it equals the part after the first `=` in an element.
Both invocation styles pass: `["--model", "claude-opus-5"]` and `["--model=claude-opus-5"]`.
The test is over elements and never over the joined string. A substring test over the joined
string would accept `model` of `opus` against a `--workdir` argument whose value merely
contains the letters "opus", which pins nothing.

**argv is the only channel, so the Pin obligation is forced rather than chosen.**
`wasi.proc.run` has no env parameter (`PROC-ENV-1`), and the port records that the agent's
paths reach it through argv (`tools/llmll-driver/sequencer.llmll`, the NO ENV CHANNEL
comment). An operator who pins a model through an environment variable does NOT meet the Pin
obligation, and the run is not a valid clause 2 run. Read this before the run, not after it.

**The driver does not change for this.** `00-source/PROVENANCE.json` is stage A's output,
and stage A shipped at v0.21.2. Its only declared predicate is that it must PARSE
(`tools/llmll-driver/registry.llmll`, the stage B precondition comment), so an added key
would not fail `T4`. The reason to keep the model out of it is different: the program under
test at its own acceptance run must be the program that 4f shipped at `e49e968`. An operator
sidecar keeps that true.

**The record is falsifiable, which is why it is worth writing.** The port writes
`agent.stdout.log` and `agent.stderr.log` in each agent directory
(`tools/llmll-driver/sequencer.llmll`, `agent-dir`). A recorded argument list can be read
against those logs after the run.

**One limit, stated rather than implied.** Pinning the invocation pins what the run asked
for. It does not pin what served the request. The claim this record supports is "this model
was requested", not "this model produced these decisions".

### 6.3 FIVE STAGES STILL WRITE STUBS, and this bounds what the run can claim

Pre-registered before the run, because reading these divergences after seeing them
is the failure pre-registration exists to prevent.

`registry.stage-ported?` answers false for **E, G2, J, L and M**. An unported stage
writes a stub byte-string to each artifact it declares and nothing else
(`tools/llmll-driver/sequencer.llmll`, the `started-step` branch and `write-cmd`).
Retiring that table is job (a2) of
[`../../docs/design/driver-ll-program-unification-proposal.md`](../../docs/design/driver-ll-program-unification-proposal.md),
which is not done.

**Every reported class that has an oracle reads a stubbed stage.**

| Class | Artifact | Stage |
|---|---|---|
| R2 gate J | `09-gate/gate.json` | J, stubbed |
| R3 stage E | `reconciliation-summary.json` | E, stubbed |
| R4 stage L | inventory | L, stubbed |
| R5 wave partition | `wave.json` | M, stubbed |
| R6 retry budget | `wave.json` | M, stubbed |

R1 is `NO ORACLE` by design and R7 is the operator sidecar, so the oracle-bearing
reported set is five for five.

**Divergence in R2 to R6 is therefore a KNOWN CONFOUND and not a port-fidelity
signal.** It is reported as `STUBBED STAGE` and never as disagreement. Registering
this in advance is what keeps a stub divergence from being read either way after the
fact.

**The thresholded half is unaffected, and that is why the run is still worth its
cost.** Stubs record `complete`, and the only byte floors are B at 200 and C at 400,
both ported. T1 through T4 decide over the real 11-stage execution.

**What this run claims.** Live evidence for the **11 ported stages** and the whole
thresholded set, against a real agent rather than the stub agent clauses 1a and 1b
use. That is new: no live agent has driven this port before.

**What it does NOT claim, and no wording will make it.** A full clause 2 result. §8's
`Success` requires every deterministic decision class to agree, and five of them read
stubs. **A PASS from this run is a pass over 11 of 16 stages and the record says so.**
A full clause 2 run waits on (a2).

## 7. Divergence semantics, pre-registered

Registered before any run, so a disagreement is a result and not an argument.

| Observation | Reading | Reported as |
|---|---|---|
| Same decision, same named condition | The port reproduces the reference | agreement |
| Same decision, different named condition | The port reaches the right answer by a different route | **divergence, reportable**; the condition is the finding |
| `stopped` where the reference recorded `failed`, or the reverse | driver-spec §4:132-136 calls this the one confusion the pipeline cannot afford | **blocking divergence**; clause 2 does not pass |
| Divergence in an agent-determined class (§4.3) | Confounded with agent variation at n=1 | **null**, not evidence either way |
| The LLMLL driver halts where the reference completed | A real difference in the port | divergence; the halt's `clause` member names the cause |
| The LLMLL driver completes where the reference halted | The port is **weaker**, which is the dangerous direction | **blocking divergence** |

**The asymmetry in the last two rows is deliberate.** A port that halts more is
conservative and reportable. A port that halts less has lost a check, and that is the
failure mode §8.1's retirement decision rests on.

## 8. Success, failure, null

- **Success.** Every deterministic decision class agrees, the §4.1 class is reported as
  NO ORACLE, and no blocking divergence appears. Clause 2 passes with its coverage
  disclosed.
- **Failure.** Any blocking divergence from §7.
- **Null.** Divergence confined to agent-determined classes. Clause 2 neither passes nor
  fails, and the run says so rather than picking one.

## 9. Cost

- **The run.** One full fifteen-stage campaign with a live agent over a 470-line RFC. The
  reference run produced 91 inventory rows, 22 holes and 14 mutants. Budget an agent session
  per delegated stage; `PROC-TIMEOUT-1` bounds each one.
- **The comparator. SPENT at Rev 2, and it is not a cost of the run.** It was engineering
  rather than compute, and it gated the run. It merged at `0b0a024`; see §6.1. Rev 16 had
  shrunk the estimate, because a reported class needs recording beside the oracle rather
  than diffing for equality. Do not budget it again.
- **The one piece of engineering that remains.** §6.2 adds one reported cell, which reads
  `RUN-PROVENANCE.json` and reports it unchecked when the record is absent. It needs one
  test and one negative control with the record absent. This is small, and it is
  `compiler-engineer`'s slot.
- **The driver build.** About 30 seconds, measured on 2026-09-10 on the author's host after
  the SDK linker repair. The figure is one measurement on one machine, not a budget.

## 10. Status

**Nothing has run.** That sentence is unchanged from Rev 1 and is still true. The other two
sentences it stood beside were both out of date, and each is corrected separately below.

**The comparator is written.** §6.1 carries the measurement: `clause2_compare.py`, merged
`0b0a024`. Rev 1 said the opposite, and the commit that made it untrue never touched this
file. This is the `RECORD-FRESH-1` defect. Two records in this campaign are now known to
show it: this one, and `docs/design/driver-ll-phase4-RESTART.md`, whose status field has
been corrected three times. That count is what has been measured, not a survey of every
record.

**No dedicated roadmap row exists, and the G0 row carries the clause.** `DRIVER-LL` is the
only row in G0. Its Next Action step (3) states that acceptance clause 2 has never been
executed, which is still true.

**The row named neither artifact until `dd5b4fb`, and it names both now.** Step (3) carries
the comparator, its cover, `T5`'s reason for staying `NOT CHECKED`, this document at Rev 3,
§6.2's pin obligation and the `P1` and `P2` commits. Rev 2 of this section said the row was
incomplete rather than incorrect. That was true when Rev 2 was written and the
`documentation-lead` pass at `dd5b4fb` closed it.

**This sentence was written before the commit that would have falsified it.** Rev 2 of this
document was falsified by a commit that never touched it, which is `RECORD-FRESH-1`. The
`documentation-lead` pass predicted the same failure here, named this paragraph as the one
its own change would falsify, and routed the repair before committing. That is the first
time in this campaign the defect was caught in front of the commit rather than behind it.

**What is now open.** The run. §5's adjudication is settled, the §6.1 gate is down, and
§6.2 states the two obligations the run carries. The decision to spend §9's cost belongs to
the user.
