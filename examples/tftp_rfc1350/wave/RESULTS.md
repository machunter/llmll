# TFTP wave: what a swarm of blind agents produced

> **Status:** RFC-SWARM Phase 2, 2026-07-25, against compiler v0.14.67. Driver:
> [`scripts/rfc_to_implementation.py`](../../../scripts/rfc_to_implementation.py) stage M.
> Frozen surface: [`../roots/FREEZE.md`](../roots/FREEZE.md).

## The result

**23 of 23 holes filled; whole tree SAFE, body-faithful, under `--strict-verified-core`;
trust report `verified: 23, asserted: 0`.**

Six concurrent agents, each a fresh session seeing **only** its checkout brief and a pristine
scratch copy of the module. No reference solution exists in this tree, and the agent that wrote
each body had no access to the repository, to another agent's attempt, or to the Phase 0
feasibility probes (which were deliberately never committed).

| Attempts to acceptance | Functions |
|---|---|
| 1 | 19 |
| 2 | 2 (`opcode-of`, `spine-implicit-ack`) |
| 3 | 2 (`request-next-state`, `request-reply`) |
| exhausted budget | **0** |

## The freeze held

The clause surface is byte-identical before and after the wave. Every `pre`, `post`,
`:source`, parameter list, and return type across all 23 roots is unchanged; no function was
added or removed. Agents changed exactly what they were allowed to change, which is the body
of their own hole.

`RFC-COV-1` still passes at freeze strength against the **filled** tree: 46/46 Encoded rows
cited, 15/15 characteristic-core rows cited, no citation of an excluded row, provenance
confined to the 23 roots.

## Detection yield

The number worth reporting is not the 23. It is that **the verifier rejected 6 fills across 4
functions**, each rejection a specific solver-level failure against a `:source`-carrying clause,
and each agent then repaired its own body with no hint beyond the compiler's output. Nobody
told an agent what was wrong; the contract did.

Also worth stating plainly: that is **not** evidence the agents would have shipped bugs without
verification. 19 of 23 were right first time, and this benchmark is saturated. What the run
demonstrates is auditability of a swarm-built artifact, not verification catching agents out.

## Kill matrix, against the agents' own bodies

Satisfiability is consistent with decorative contracts, so each core obligation was mutated in
the **agent-authored** code and re-verified. Frozen in
[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json).

| Mutant | Rows | Verdict |
|---|---|---|
| `sorcerers-apprentice` (resend current DATA on a duplicate ACK) | T113 | refuted |
| `block-off-by-one` (`acked + 2`) | T033 / T063 / T045 / T011 | refuted |
| `ack-block-skew` (ACK echoes `datablk + 1`) | T032 / T073 / T082 | refuted |
| `short-block-inverted` (512 ends, short continues) | T013 / T065 / T066 / T081 | refuted |
| `wrong-tid-terminates` (injected packet kills the transfer) | T022 / T047 / T048 | refuted |
| `error-latch-open` (ERROR leaves the state unchanged) | T016 / T077 | refuted |
| `wrq-ack-block-one` (WRQ answered with ACK block 1) | T034 / T074 | refuted |
| `tid-range-wrong` (TID upper bound 65536) | T027 | refuted |
| `good-twin-tid-valid` (correct variant, written differently) | — | **SAFE**, as required |

**8 of 8 refuted, no survivors; the good twin survived.** The good twin matters as much as the
kills: a contract set that refutes everything, correct implementations included, would be as
useless as one that refutes nothing.

Read the kills correctly. A killed mutant proves the contract **excludes one specific
behavior**. That is eliminative evidence. It does not corroborate that the contract says what
RFC 1350 says, because one side of that question is English prose and has no formal answer.

## The headline body

`sender-reply`, written blind from the T012 and T113 clauses:

```lisp
(if (= ackblk acked) (DataPkt (+ acked 1)) NoPacket)
```

On a duplicate ACK it emits **nothing**. That is the RFC 1123 §4.2.3.1 Sorcerer's Apprentice
fix, which exists precisely because the natural implementation retransmits and produces a
packet-doubling cascade. The agent was never shown that bug, and the mutant that reinstates it
is refuted.

## What this does not claim

- **not** that TFTP is "verified". The ledger says which of 124 normative clauses are Encoded
  (46), modeled (20), vectored (5), or excluded with a cited barrier (53).
- **not** that `:source` proves fidelity to the RFC. It is a traceability pointer.
- **not** that trace-level or timing properties hold. The spine proves the coupling invariant is
  preserved by every single step; the closure to "on every reachable trace" is a trace
  induction, disclosed as a trusted schema (`../VERIFICATION_SCOPE.md` §9).
- **not** that verification caught agent error. See Detection yield above.

## On the concurrency behaviour

The wave's re-derivation of the whole-file compare-and-swap is not a new finding.
`docs/blog/post-4-who-writes-the-decomposition.md` had already stated it plainly, and the
harness was built without reading it. What this run adds is an independent confirmation and a
measured cost: the first wave wedged fourteen holes and discarded at least one correct body
because of it.

## One unconfirmed report

`request-next-state`'s agent reported a malformed constraint line during an intermediate build
(`(len =opacket )))))`), diagnosed it as belonging to a different hole, and correctly routed it
without touching any frozen clause. **I could not reproduce it.** The obvious trigger, a body
comparing the int `len` against a `Packet` constructor, is rejected by the typechecker with no
`.fq` emitted at all. Given the unbalanced parentheses in the quoted text, the likeliest reading
is that the agent quoted an elided liquid-fixpoint error snippet as though it were file content.
Recorded here because the agent's routing behaviour was exactly right, and because an
unreproduced report should be visible rather than dropped, but it is **not** a confirmed
compiler finding.

## Reproducing

```bash
scripts/rfc_to_implementation.py --rfc-url https://www.rfc-editor.org/rfc/rfc1350.txt \
  --workdir <dir> --only M --wave-agents 6 --semantic-retries 3 \
  --agent-cmd 'claude -p "$(cat {prompt})" --allowedTools "Read,Write,Bash" --permission-mode acceptEdits'
```

The workdir must be **outside this repository** and the agent must not be given access to it.
Phase 0 and Phase 1 artifacts are committed here, so an agent with repo access could retrieve
the inventory and the contracts instead of working from its brief, and the blindness claim would
be worthless.
