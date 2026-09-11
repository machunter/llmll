---
name: clause-2-pre-registration
title: "DRIVER-LL acceptance clause 2: run plan and pre-registration"
status: "Rev 1, 2026-09-10. NOT RUN. Rev 0 put a replay-or-live choice to the user; language-team ADJUDICATED it as live against proposal section 2.3, so section 5 is rewritten and the choice is gone. The adjudication found the disagreement is WIDER than Rev 0 measured, five of six decision classes and not three, and proposal Rev 16 answers it by splitting thresholded from reported. Section 4.1, the missing MANIFEST.json, is RETIRED as a gap: stage status is clause 1a oracle. Sections 4.2 and 4.3 stand."
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

## 6. What must be built before the run

**No comparator exists in this repository today.** Measured: no script under `scripts/` or
`experiments/rfc-swarm/tools/` reads a run directory and a `MANIFEST.json` together.

The comparator is the deliverable that gates the run, not the run itself. It must:

1. Read the LLMLL driver's `MANIFEST.json` rows. Complete rows carry
   `{status, kind, seconds, outputs}`; halt rows carry `{status, detail, outcome}` plus
   `clause` (`tools/llmll-driver/manifest.llmll`, the row-schema comment).
2. Read the oracle artifacts in §3 and extract each recorded value.
3. Compare per decision class, and **report per class**, never as one score.
4. Report the §4.1 class as **NO ORACLE** rather than as agreement.
5. Apply artifact *shape* predicates only, per §2.4's last sentence. Never compare content.

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
- **The comparator.** Engineering, not compute, and it gates the run. Rev 16 shrinks it: a
  reported class needs recording beside the oracle, not diffing for equality.
- **The driver build.** About 30 seconds, measured today on this host after the SDK linker
  repair.

## 10. Status

**Nothing has run. No comparator is written. No roadmap row is filed.** The decision in
§5 belongs to the user and `language-team`; the comparator in §6 is `compiler-engineer`'s
slot once a reading is chosen.
