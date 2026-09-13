---
name: driver-ll-campaign-close
title: "DRIVER-LL: the campaign close, and what it measured"
status: "Rev 1, 2026-09-12. CLOSES the G0 campaign lane at the end of Phase 4. Phase 5 is NOT ATTEMPTED and job (b) is NOT DONE, both by decision rather than by block, and this document states the reason: the campaign's remaining work is the part the campaign itself classified as teaching nothing. WHAT IT MEASURED IS THE DELIVERABLE, and it is stated here at the size actually achieved rather than at the size the phase names suggest. 8522 lines of LLMLL across 39 modules, ZERO FFI declarations, sixteen stages each writing a real artifact, and 581 `def-shell` against 55 proved `def`. Ninety-one percent of this driver carries no proof BY CONSTRUCTION, and section 5.4 of the campaign document said so before Phase 0 began."
date: 2026-09-12
author: compiler-engineer
consumers: [language-team, experiment-lead, documentation-lead, user]
---

# DRIVER-LL: the close

The campaign ported `scripts/rfc_to_implementation.py`, a sixteen-stage RFC
implementation driver, into LLMLL. This document closes it. It states what was
measured, what the campaign yielded, and what is deliberately left undone.

## 1. The expressiveness result, at the size actually achieved

**Measured 2026-09-12 over `tools/llmll-driver/`:**

| | |
|---|---|
| LLMLL source | **8522 lines**, 39 modules |
| FFI declarations | **zero**, the campaign's standing bar from Phase 3 onward |
| Stages | **sixteen of sixteen**, each writing a real artifact, no stub path |
| Proved `def` | **55** |
| `def-shell` | **581** |

**Ninety-one percent of this driver carries no proof, by construction, and that
is the result rather than a shortfall.** Orchestration is effects: spawning a
process, reading a file, fetching over HTTP, driving an agent. None of it is
provable in this language and none of it was ever going to be. The campaign
document's section 5.4 states the conclusion in advance: *"the verified driver
replaced the unverified one" would be false in the way that matters: what was
demonstrated is that the language can express the program, not that the program
carries more proof than its predecessor.*

**What the proved 9% is.** Scalar decision logic at the points where the driver
DECIDES: `gate.gate-halts` takes four counts and returns whether the gate halts;
`stage.record-outcome` maps an `Outcome` to a `Status` and proves the two halt
channels cannot collapse; `validate.verdict-of` takes `bool int int` and no
string, so no subject's conventions are in scope; `skip.may-skip` decides
resumption. The shape the campaign demonstrates is **a proved centre with an
unproved shell around it**, and the shell calls the centre rather than
re-implementing it.

**That shape is the transferable claim.** Not "the driver is verified", which is
false, but "the decisions a driver makes can be proved and the effects it
performs can call them".

## 2. What the campaign actually yielded

**Ten language rows, filed into the roadmap because a real program demanded
capabilities the language did not have.** `HTTP-GET-1`, `PROC-BOUNDARY-1`,
`PROC-TIMEOUT-1`, `STRLIT-BODY-1`, `FS-COPY-1`, `MATCH-CATCHALL-1`,
`RESERVED-NAME-1`, `CAP-1-REAL`, `TYPE-SHADOW-1`, `CONSOLE-INIT-1`.

**This is the campaign's real value and it is an instrument's value, not a
product's.** A demo written to succeed finds nothing. A port of a program someone
actually runs finds ten defects, because it cannot route around what is missing.
Two of the ten shipped as new builtins (`wasi.http.get`, `wasi.fs.copy`) and one
as a whole capability boundary (`PROC-BOUNDARY-1`, the exit-status channel every
LLMLL console program now uses).

## 3. The RFC 826 finding, which is the sharpest thing the campaign produced

**On 2026-09-12 the driver refused to certify RFC 826, and the refusal is a
measurement of where LLMLL's verifiable fragment ends.**

Gate J halted on its characteristic-core condition. Stage G had dispositioned ten
of twenty-six characteristic-core rows out, every one an ARP packet octet-layout
obligation: field position and width, `ar$sha` occupying exactly `ar$hln` bytes,
`ar$tpa` as the final field at `ar$pln` bytes. Each cited barrier B4 or B5, both
on the closed list. Driver-spec section 6:224-227 requires a halt when any clause
named as characteristic is excluded.

**It reproduces.** An earlier run the same day drew twenty-two core rows and
excluded six of the same family.

**It disagrees with the July 2026 Python oracle**, which drew nineteen
behavioural core rows from ninety-one, dispositioned none out, and passed. Its
core is the protocol's resolve and request semantics. The disagreement is at stage
F, where the core is named, and not at the gate.

**The sharper reading cuts toward the oracle and is recorded rather than
softened: a narrower core passes this gate more easily.** Nineteen of ninety-one
rows, all `Encoded`, is the shape `spine.stage-j-pins`'s own comment names, where
a gate stays green through its own blind spot. A run that names more
characteristic clauses and then finds some outside the fragment has measured
something. A run that names fewer has measured less.

**The claim this supports**, and it is stronger than the port itself: *LLMLL's
verifiable fragment does not reach packet field-layout obligations, measured by a
gate that refused to certify a real protocol rather than by an argument about the
fragment's boundary.* Artifacts at
[`../../experiments/rfc-swarm/runs/rfc826-llmll-2026-09-12/`](../../experiments/rfc-swarm/runs/rfc826-llmll-2026-09-12/);
the run record is `CLAUSE-2-PRE-REGISTRATION.md` section 6.5.

## 4. What is left undone, and why

**Job (b), the section 5.3 plumbing port and the retirement of
`rfc_to_implementation.py`. NOT DONE, by decision.** It is argparse, `copytree`,
tempdir handling and path juggling. **Section 5.3 excluded exactly that work as
teaching-free and section 8.1 lifts the exclusion only at the retirement step,
where it is "reported as utility and not as a language result."** The campaign
classified its own remaining work as the part that teaches nothing, and this close
takes that classification at its word. The Python driver stays.

**Phase 5's conformance claim. NOT ATTEMPTED, by decision.** It would be bounded
by `SPEC-TIER-1`, a defect in the target specification that cannot be repaired
here, by `FS-ISOLATION-1`, whose isolation audit is unimplemented, and by
`PROC-TIMEOUT-1`, under which a hanging child hangs the driver with no budget. A
conformance claim with three asterisks of that size is weaker than the
measurements in sections 1 and 3, which need no claim at all.

**THE RETIREMENT GATE WAS NEVER OPERATIONALIZED, and that is a finding about the
campaign rather than about the driver.** Section 8.1's criterion is *"a complete
run reproduces a committed campaign's artifacts, with zero FFI declarations and
bounded authority end to end."* Four conjuncts. Zero FFI is MET and measured. A
complete run FAILED, on the gate halt in section 3. The other two have no test:
"reproduces a committed campaign's artifacts" cannot be met by any run, because
the artifacts are agent-authored and the pre-registration replaced it with a
thresholded/reported split precisely for that reason (sections 4.2 and 4.3, n=1
and the oracle's model unrecoverable); and "bounded authority end to end" is
`T2b`, which the comparator reports as `NOT CHECKED` because no artifact defines
a check for it. **A gate half of which was never given a test cannot be cleared by
running anything**, and this close records that rather than picking a reading of
it.

## 5. What follows

The ten rows in section 2 are the campaign's output and they are where the
remaining value is. `PROC-TIMEOUT-1` is first among them: it is the one that makes
this driver unsafe to run unattended, independently of anything the campaign
claims.

Nothing in this close blocks a later Phase 5 or a later job (b). Both are
reopenable by decision, and neither is waiting on a measurement.
