---
name: rfc-swarm-target-selection
title: "Choosing the next RFC: a criterion, and a cheap screen that turned out not to exist"
status: "Rev 1, 2026-07-28. Criterion stands; the two-call pre-flight failed its controls and is retired"
date: 2026-07-28
author: main-agent
consumers: [orchestrating agent, user, experiment-lead]
---

# Choosing the next RFC: a criterion, and a pre-flight that measures it

**Why this document exists.** Target selection has been done twice by reading an RFC and forming
an impression, and it has been wrong twice. RFC 4648 was chosen as a deliberately bad fit, carried
**84.6%** of verifiable subject matter (the highest of three runs), and halted on a mechanism the
prediction never considered. An impression is not a procedure. This replaces it with a criterion
stated as checkable properties and a **pre-flight** that measures them for a few minutes per
candidate instead of guessing.

## 1. What the fourth run is for, and why screening is now legitimate

Gate J's characteristic-core condition has a complete truth table across three runs: no core row
dispositioned out on TFTP and on ARP, both pass; one out on RFC 4648, stop. **Nothing further is
learned by firing it again**, and a target that fails harder reaches the same verdict by the same
path.

What has never fired for a real reason is **gate L**, the **per-fill acceptance bar in stage M**,
and now **stage G2** on a run it was not built from. ARP's gate L failure was a hardcoded tag
prefix in our own lint; RFC 4648 halted at J without reaching either.

So gate J is no longer the experiment. It is infrastructure the run has to get past, and
**screening a candidate so that it passes J is the correct move rather than a thumb on the
scale**. Screening for a condition still under test would be circular; screening for a settled one
is just not wasting 76 minutes.

## 2. The criterion

Every core row must sit inside the shipped fragment. Across three runs, everything that put a row
out was `B5` (string structure) or `B4` (opaque transform), so the criterion is stated as the
absence of those in the **core**, not in the document.

A candidate is admissible when all of these hold of the clauses that make the protocol *that
protocol*:

1. **The core is state transitions and fixed-width field values**, not the layout of a byte
   stream.
2. **No core obligation requires locating a field whose offset depends on another field's value.**
   Fixed offsets carry. Computed ones are ARP's `8 + 2*ar$hln + ar$pln`, which accounts for 22 of
   its 34 excluded C1-C3 rows.
3. **No core obligation concerns position within, or insertion into, an output sequence.** This is
   what halted RFC 4648: an encoder must not *add* line feeds, adding is a stream operation, and
   no per-quantum model carries insertion between quanta.
4. **No core obligation rests on an opaque transform**: checksums, cryptography, character-set
   translation. These are `B4` and carry no arithmetic or enum content.
5. **Timing and liveness clauses may exist but must not be characteristic.** Every protocol has
   them. TFTP's timeouts were `B1` and excluded while its lock-step discipline was core and
   carried, which is the shape to look for.
6. **Roughly 20 to 25 roots**, so the wave is affordable and comparable to the two that ran.

Criterion 6 cuts both ways, and the failure mode is undershooting. A document whose core is five
clauses cannot exercise a wave.

## 3. The pre-flight that was tried, and did not work

> **Retired the same day it was written.** Section 5 has the evidence: it rejected seven targets
> out of seven, including both that actually reached the wave. The `--preflight` mode and its two
> prompts were removed rather than shipped. This section is left as the description of what was
> built, because the failure is only legible against the design.

The idea was to run a miniature stage F and stage G over the **core only**, before committing to a
target. Twenty or so rows rather than a full census, two agent calls rather than nine stages.

**Step 1, blind.** An agent names the characteristic core from the pinned RFC text alone. Its
prompt contains no `scope.md`, no description of the fragment, and no occurrence of `LLMLL`, for
the same reason stage F does not: a core drawn around what happens to verify decides nothing.

**Step 2, fragment-aware.** A second agent, which never sees the first agent's reasoning beyond
its output rows, rules each core row carried or excluded against the closed barrier list.

**Step 3, mechanical.** Any core row excluded means the candidate would STOP at gate J. The
driver prints the verdict and does not decide it in the agent.

This is exactly what would have caught RFC 4648. A1's line-wrapping clause is core, it is `B5`,
and it would have surfaced before stage A of the real run.

**A free second measurable.** The pre-flight core and the real run's stage-F core are two
independent namings of the same set by agents that cannot see each other. Their agreement is worth
reporting alongside the extraction Jaccard.

**What the pre-flight does not do.** It does not estimate coverage, which is a property of the
whole census and not of the core, and it does not rule on any non-core row. A candidate can pass
the pre-flight and still carry 55% like ARP. Passing means "will probably reach the wave", which
is the only thing the fourth run needs.

## 4. Candidates, and the hypotheses, recorded before screening

Stated here **before any candidate was screened**, so the pre-flight is itself scored rather than
narrated afterwards. Two are expected to pass and two to be rejected, for different reasons, which
is what tests that the pre-flight discriminates rather than just agrees.

| Candidate | Why it is a candidate | Hypothesis | Expected ground |
|---|---|---|---|
| **RFC 2453**, RIP v2 | route-table state machine, fixed 20-byte entries, metric arithmetic with infinity at 16, split horizon | **PASS** | core is transitions plus integer arithmetic; timers exist but are not characteristic |
| **RFC 6298**, computing TCP's RTO | pure integer arithmetic over SRTT and RTTVAR, crisp invariants, a hard floor | **PASS on the fragment, likely REJECT on size** | criterion 6, not criterion 1 to 5 |
| **RFC 6455**, WebSocket framing | a real state machine, but payload length is 7, 7+16 or 7+64 bits and every offset after it is computed | **REJECT** | criterion 2, `B5` |
| **RFC 792**, ICMP | small, fixed-layout messages, well-bounded | **REJECT** | criterion 4, the checksum, `B4` |

Outcomes are recorded in section 5, which is empty until the screening runs. A hypothesis that
turns out wrong is left as written; the pre-flight's whole purpose is that our reading is not
reliable, so its own record has to survive being wrong.

## 5. Screening outcomes: the pre-flight does not work, and it is retired

Run 2026-07-28 over the four candidates and then over three **controls** whose gate-J outcome is
already known. The controls are why this section says what it says.

| Target | Known gate J | Pre-flight | core | carried | fraction | real stage-F core |
|---|---|---|---:|---:|---:|---:|
| RFC 1350, TFTP | **PASS** | REJECT | 26 | 16 | 62% | 15 |
| RFC 826, ARP | **PASS** | REJECT | 21 | 11 | 52% | 19 |
| RFC 4648, Base-N | **STOP** | REJECT | 22 | 17 | 77% | 23 |
| RFC 2453, RIP v2 | - | REJECT | 26 | 18 | 69% | |
| RFC 6298, TCP RTO | - | REJECT | 18 | 13 | 72% | |
| RFC 6455, WebSocket | - | REJECT | 30 | 20 | 67% | |
| RFC 792, ICMP | - | REJECT | 28 | 21 | 75% | |

**Seven of seven rejected, including both targets that actually reached the wave.** It agrees with
RFC 4648 only in the way a stopped clock agrees. The instrument has no discriminating power, so
**the four candidate verdicts above carry no information and none of them is disqualified.** The
hypotheses in section 4 are left as written and are unscored, because the screen that was supposed
to score them does not work.

The carried fraction inverts the thing it would need to track: **77% for the target known to stop,
52% for one known to pass**. That mirrors the real runs, where RFC 4648 carried the most of three
at 84.6% and was the one that halted. Coverage does not predict gate J at the census level and it
does not predict it at the core level either.

### Why it failed, which is structural rather than a tuning problem

Stage F **selects** a core from a reconciled census: 124 adjudicated rows go in, 15 come out. The
pre-flight's step 1 **generates** a core from prose, with no census to select from. Those are
different operations and they produce different sets. Generation from prose pulls in wire-format
and transport clauses, because in a plain reading of the document the packet layout obviously is
characteristic; selection from a census leaves them as ordinary non-core rows among a hundred
others. TFTP is the clearest case: 26 rows generated against 15 selected, and the extra rows are
what got excluded.

The tempting repair is to tell the core-naming agent not to call format rows characteristic. That
is exactly the circularity blindness exists to prevent: a core drawn around what the fragment
reaches makes the screen self-fulfilling and the later gate meaningless. **The repair is not
available.**

Reproducing stage F faithfully requires the census, and the census is stages D and E, at which
point the screen is most of a run.

### What replaces it

Gate J needs no separate instrument, because **the pipeline already is one and its cost is
bounded**. Screen a candidate by running the real stages up to the gate and stopping:

    scripts/rfc_to_implementation.py --only A,B,C,D,E,F,G,G2,J \
        --rfc-url <url> --workdir ~/rfc-swarm-runs/<name> --agent-cmd '<cmd>'

**Stage H is the one to skip, and it is where the time goes.** The RFC 4648 run cost 4565s in
total and stage H alone accounted for roughly 45 minutes of it, exceeding its budget while
verifying probe and mutant pairs. Gate J reads only the disposition ledger, so H and I are not
inputs to it. That puts a faithful screen at roughly half an hour, against 76 minutes for the run
that discovered the same thing the expensive way.

This is worth stating plainly: **the RFC 4648 run was already the screen.** What it cost is what
finding out costs, and the only saving available is not paying for the probes before the gate has
ruled.

### Consequence for section 2

The criterion stands as a description of what put rows out across three runs, and it is useful for
choosing what to screen. It is **not** something we can evaluate without running the pipeline, and
this section is the evidence for that. Selection therefore looks like: pick a candidate the
criterion favours, screen it through gate J for about thirty minutes, and move to the next if it
stops. The `--preflight` mode written for this document is retired, following the exclusion-ratio
ceiling, which was also a plausible-looking instrument that measured something other than what it
claimed.
