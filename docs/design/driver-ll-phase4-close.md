---
name: driver-ll-phase4-close
title: "DRIVER-LL Phase 4: the phase close and its gap inventory"
status: "Rev 1, 2026-09-12. CLOSES Phase 4. Sub-phase 4f's acceptance in `driver-ll-phase4-proposal.md` section 9 requires clauses 1a, 1b and 2, the perturbation-omission check firing on an omitted survivor, and the seven disclosure-only section 13 clauses listed as unchecked in a phase close. That close did not exist until this document; a grep over docs/ and CHANGELOG.md found neither it nor a gap inventory. CLAUSE 2 IS A FAIL AND THIS DOCUMENT DOES NOT SOFTEN IT: the 2026-09-12 re-run halted at gate J on a characteristic core partly outside the verifiable fragment, which is the gate working and a finding about the language's reach. The phase closes with that result recorded rather than with a pass manufactured on a narrower target."
date: 2026-09-12
author: compiler-engineer
consumers: [language-team, experiment-lead, documentation-lead, user]
---

# Phase 4: the close

Phase 4 ported the sixteen-stage driver of `scripts/rfc_to_implementation.py`
into LLMLL. This document is its close. It states what landed, what the
acceptance clauses returned, and what the phase leaves open.

## 1. What landed

| | Lands | Shipped |
|---|---|---|
| 4a | sequencer, manifest, resume gate, both halt channels | v0.14.85 |
| 4b | B, C, I, and the validation facility | v0.14.87 |
| 4c | D, F, G | v0.14.88 |
| 4d | H, K, N over `oracle.llmll` | v0.21.1 |
| 4e | M, the serial wave | v0.14.88 |
| stage A | intake over `wasi.http.get`, once `HTTP-GET-1` lifted its STOP | v0.21.2 |
| 4f | O, `report.llmll` and the section 13 validator | v0.23.1 |
| unification (a1) | one binary, every name collision collapsed | v0.23.2 |
| unification (a2) | stage M folds into the stage loop | v0.23.2 |
| stage M agent contract | the four declared inputs 4e did not port | v0.23.3 |
| unification clause 3 | E, G2, J, L, and the stub path deleted | v0.23.4 |

**Sixteen of sixteen stages write a real artifact.** No stage writes a stub, and
the machinery that wrote them is deleted rather than disabled.

## 2. The acceptance clauses

**Clause 1a, manifest-level agreement, MET.** The driver cover
(`scripts/driver_ll_cover.py`, 80 cells) and the no-toolchain pytest tier decide
it. Every cell names the oracle it is a cell of, per the proposal section 2.3.

**Clause 1b, conformance on the divergence inputs, MET.** The three guarded reads
the reference tracebacks out of record `failed` at exit 3 and report the reason on
standard output, which is the driver-spec section 4:139-143 obligation clause 1a
cannot reach. Cover cells carry each.

**Clause 2, the live campaign run, FAIL.** Executed 2026-09-12 at v0.23.4 against
RFC 826, recorded at `experiments/rfc-swarm/CLAUSE-2-PRE-REGISTRATION.md` section
6.5 with artifacts at `experiments/rfc-swarm/runs/rfc826-llmll-2026-09-12/`. One
thresholded item unmet (`T1`), six met, two disclosed `NOT CHECKED` (`T2b`, `T5`).

**`T1` fails because gate J halted the run, and the gate was right.** Stage G
dispositioned ten of twenty-six characteristic-core rows out, every one an ARP
packet octet-layout obligation, under barriers B4 and B5 which are both on the
closed list. Driver-spec section 6:224-227 requires a halt. Stages K, L, M, N and
O were therefore never attempted.

**It reproduces.** An earlier attempt the same day drew twenty-two core rows and
excluded six of the same family. Two independent runs agree with each other and
disagree with the July 2026 oracle, which drew nineteen behavioural core rows from
ninety-one and excluded none.

**THE PHASE CLOSES ON A FAIL AND THAT IS THE RESULT, not a blocker to route
around.** What the run establishes is the campaign's own question: on RFC 826 the
characteristic core, as two frontier agents draw it, contains obligations about
packet byte layout, and those are outside LLMLL's verifiable fragment. A pass
obtained by choosing a target whose core fits would have measured less.

**The perturbation-omission check.** It fires on an omitted survivor and records
`PartialThenHalt`, pinned by cover cell O2. It did not fire in the 2026-09-12 run,
stage O never having been attempted.

## 3. The seven disclosure-only section 13 clauses are UNCHECKED

Section 4f's acceptance requires this list, and requires that it not be reported
as met. One of section 13's eight clauses is mechanizable and seven are not; the
split is drawn by driver-spec section 15.1:512-515, whose proved tier covers
sequencing and state and does not mention reporting.

**Checked:** a report MUST include the full result of the perturbation exercise,
including perturbations that were not detected. `report.omission-free?` decides it
as a set difference over stage N's `kill-matrix.json`.

**UNCHECKED, and not reported as met:**

1. the lead-with-coverage pair, first clause;
2. the lead-with-coverage pair, second clause;
3. state what is not claimed;
4. disclose every assumed step;
5. MUST be resolved rather than omitted;
6. the MUST NOT about validating contracts;
7. the MUST NOT about verification preventing an error.

**Passing the omission check does not discharge section 13:446.** A report that
lists a survivor and then dismisses it passes the set difference while violating
"MUST be resolved rather than omitted". `report.llmll`'s own header states this and
this close must not contradict it.

## 4. The gap inventory

Each entry is a gap the phase leaves open, with where it is filed.

1. **`PROC-TIMEOUT-1`.** `wasi.proc.run`'s timeout does not fire in a built
   program. Measured: a one-second timeout against a thirty-second child exits 0
   reporting thirty seconds. Stages D, F, G, E and L each spawn a child, and no
   cover cell may claim a budget-overrun halt. The reference carries no timeout at
   all, so the port reproduces rather than hardens. Filed in roadmap group G2.

2. **`SPEC-TIER-1`.** Driver-spec section 15.1:504-505 requires every obligation
   to occupy exactly one of three tiers, and section 15.1:509's range sentence
   contradicts both its own characterisation and its enumeration, so section 13's
   prose MUSTs fit none of the three. It is a target-spec defect and driver-spec is
   pinned, so it cannot be repaired here. It bounds what a Phase 5 conformance
   claim may assert.

3. **`FS-ISOLATION-1`.** `audit_blindness` implements driver-spec section 8:330-332
   and the port defers it. `wasi.proc.run` takes no confinement parameter, so a
   confining spawn is a language change and not a port decision, recorded as `Q-008`
   in `docs/design/theory-questions.md`. The port reproduces the reference's
   isolation posture exactly and hardens nothing.

4. **The committed-corpus replay is unreachable, by decision.** `spine.llmll` was
   the only artifact in the tree that replayed the frozen TFTP corpus. Clause 3
   re-targeted stages E, G2, J and L at the run workdir, which ends that. The clause
   3 proposal section 6 records it as a deliberate loss, taken because preserving it
   means two code paths for four stages.

5. **`spine.llmll`'s replay harness is superseded and not deleted.** `spine-step`,
   `spine-init` and `spine-done?` are the eighteen-state counter those four stages
   ran under. All four now run in the stage loop, so the harness has no caller and
   no prospect of one. Clause 3's acceptance item 6 forbade touching the file, so
   the deletion is owed and unscheduled.

6. **Three pin cores are proved and callerless.** `stage-e-passes`, `stage-j-pins`
   and `stage-g2-pins` pin the committed TFTP corpus, and their `NOVACUOUS`
   postconditions prove a divergent count fails. They are `self_test()`'s pins, not
   the stages', so the live stages cannot call them. `gate.remedy-for` is a fourth,
   filed at Phase 3 for its own reason.

7. **No cover cell catches a failed declared write.** Measured by mutation control
   at clause 3: testing a stage's halt before its write-failure check passes the
   whole cover. Inducing one needs an unwritable path mid-run and the cover has no
   mechanism for it. The 4d and 4f ports carry the same gap.

8. **Stage G2's citation half and delegated half are unported.** The citation half
   needs a token-coverage ratio and LLMLL has no floats. The delegated half is a
   reading, so an agent does it, filed as its own roadmap row so that a new
   agent-delegated stage does not arrive under a port. A clause 2 run therefore
   carries a disclosed G2 divergence, and "full clause 2" means all sixteen stages
   running real bodies rather than all sixteen agreeing on every decision class.

9. **`T2b` and `T5` are `NOT CHECKED` by pre-registration.** `T2b`, bounded
   authority, has no artifact defining a check. `T5`, stopped-for-failed, compares
   against the reference's recorded status, which lives in a `MANIFEST.json` no
   committed run carries.

10. **The stage F disagreement is unadjudicated.** Two 2026-09-12 runs drew
    characteristic cores including packet-layout clauses; the oracle drew a
    behavioural core of nineteen rows from ninety-one and excluded none. A narrower
    core passes gate J more easily, which is the shape `spine.stage-j-pins`'s own
    comment warns about. Whether the prompt invites the divergence or the oracle
    under-drew its core is a judgement about RFC 826 and is not settled here.

## 5. What Phase 4 does not close

Job (b), the campaign section 5.3 plumbing port and the retirement of
`scripts/rfc_to_implementation.py`, has no plan. Its retirement gate is Phase 4
acceptance, and clause 2 returned a FAIL, so the gate is not met on the reading
section 8.1 states. Whether a spec-mandated gate halt satisfies that gate is a
decision this document raises and does not take.

The Phase 5 conformance claim follows, bounded by entries 2 and 3 above.
