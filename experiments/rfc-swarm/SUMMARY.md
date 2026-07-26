# RFC-SWARM: what has actually been demonstrated

> Two runs, 2026-07-24 and 2026-07-25, against compiler v0.14.65 and v0.14.67.
> This is the cross-run summary. Per-run detail: [`runs/rfc826/RESULTS.md`](runs/rfc826/RESULTS.md)
> and [`../../examples/tftp_rfc1350/`](../../examples/tftp_rfc1350/). Procedure:
> [`../../docs/design/rfc-swarm-playbook.md`](../../docs/design/rfc-swarm-playbook.md).

## The claim

> Given an RFC, an orchestrating agent builds a formal specification traceable clause by
> clause to the source text, and a swarm of blind agents produces an implementation the
> compiler proves satisfies it. Every normative clause is dispositioned: verified, modeled,
> tested, or excluded with a cited reason.

## The two runs

| | **TFTP** (RFC 1350 + 1123) | **ARP** (RFC 826) |
|---|---|---|
| who wrote the contracts | **a human (me)** | **agents, unaided** |
| stages run by the driver | the wave only | **all fifteen** |
| dual-extraction Jaccard | 0.8655 / 0.725 | 0.8551 |
| rule agreement (kappa) | 0.9378 | 0.824 |
| inventory rows | 124 | 91 |
| Encoded / modeled / vectored / out | 46 / 20 / 5 / 53 | 39 / 3 / 1 / 48 |
| characteristic core | 15, none out | 19, none out |
| coverage of C1+C2+C3, as published | 62/65 = 95.4% | 42/76 = 55.3% |
| coverage, corrected (see below) | **51/65 = 78.5%** | **42/76 = 55.3%** |
| gate J | PASS | PASS |
| RFC-COV-1 at freeze | PASS 46/46, 15/15 | PASS 39/39, 19/19 |
| feasibility probes | 4/4 | 6/6 |
| implementation | 23/23 verified | 22/22 verified |
| whole tree | SAFE, body-faithful | SAFE, body-faithful |
| kill matrix | 8/8 refuted, 1/1 good twin | **14/14 refuted, 5/5 good twins** |
| survivors | none | none |

## What this does and does not establish

**Established.** The procedure runs end to end on an RFC nobody had prepared for it, and
produces a traceable specification and a verified implementation. Agents can author the
contracts, not only fill them: ARP's 22 roots carrying 39 cited clauses were written by an
agent from the RFC text and `LLMLL.md` alone. Both runs' contracts are discriminative, which
is the only claim the kill matrices support: **22 of 22 mutants refuted across both runs, with
all 6 good twins surviving.**

**Not established, and not claimed.**

- **not** that either RFC is "verified". The ledger says which clauses are Encoded, modeled,
  vectored, or excluded with a cited barrier. TFTP carries 46 of 124; ARP 39 of 91.
- **not** that `:source` proves fidelity to the RFC. It is a traceability pointer. Whether a
  contract *means* what the English says has no formal answer and is not tested anywhere here.
- **not** that verification caught agents out. On TFTP the verifier rejected 6 fills across 4
  functions, each with a solver-level reason, and each agent repaired its own body from
  compiler output with no hint. That is real detection yield. But 19 of 23 were right first
  time and this benchmark is saturated, so it demonstrates auditability of a swarm-built
  artifact, not that the swarm would have shipped bugs without it.
- **not** that trace-level or timing properties hold. TFTP's spine proves its coupling
  invariant is preserved by every single step; the closure to all reachable traces is a trace
  induction, disclosed as a trusted schema.

## The honest weaknesses

**Coverage is not stable across targets, and about half of that instability was our own
measurement error.** The published figures were 95.4% (TFTP) and 55.3% (ARP). Reading ARP's 48
exclusions to find out which explanation held produced an answer that corrects TFTP rather
than ARP.

TFTP counted 14 of its 26 format rows as carried under `Deployment-modeled`. Their own model
notes say what the model does with the asserted content: *"the 2-byte field width is not
represented"*, *"byte widths are not represented"*, *"ErrMsg and its zero byte are dropped"*,
*"the NUL-terminated wire layout stays in the decoder"*. The playbook's own rule is that a row
the model cannot exercise carries no verification evidence and must be excluded rather than
counted. No mutant can get *"the opcode field is 2 bytes"* wrong in a model with no byte
widths. **ARP's agent classified the identical row shape as excluded under B5, and applied our
rule more faithfully than the human pass did.**

Correcting TFTP on the 11 unambiguous cases (3 more are borderline, pinning a value while
dropping the layout):

| | carried / verifiable | |
|---|---|---|
| TFTP as published | 62/65 | **95.4%** |
| TFTP, 11 pure drops removed | 51/65 | **78.5%** |
| TFTP, 3 borderline also removed | 48/65 | 73.8% |
| ARP, as the agent ruled | 42/76 | **55.3%** |

So the 40-point gap is really **19 to 23 points**, and the remainder is genuinely the target.
The mechanism is specific and worth stating, because it predicts which RFCs suit this method:
**TFTP's wire fields are fixed-length; ARP's are length-driven.** ARP's `ar$hln`/`ar$pln` set
the widths and offsets of the four address fields, so locating them needs the arithmetic
`8 + 2*ar$hln + ar$pln` over a byte sequence, which the fragment does not reach. That single
structural fact accounts for 22 of ARP's 34 excluded C1-C3 rows.

The agent was also more honest than the headline. Its reason for excluding A89 reads: *"The
classic length-confusion failure lives here and no result may claim resistance to it."* That is
the Heartbleed class, in the one protocol where it genuinely applies, explicitly disclaimed
rather than quietly counted.

A small effect runs the other way: ARP excluded three rows (A4, A6, A7) binding opcode names to
their numerals, modelling opcodes as distinct uninterpreted constants instead. TFTP pinned those
numerals and counted them. Under TFTP's choice ARP would reach 45/76 = 59.2%. That is a
legitimate modelling difference, not an error on either side.

**Consequence for the claim.** The corrected reading is that this method carries roughly
55-80% of verifiable subject matter depending on whether the target's wire format is
fixed-length, and that the earlier 95.4% overstated it. The TFTP inventory is left as
published, per the pre-registration discipline of recording outcomes rather than editing prior
artifacts; this section is the correction.

**Agreement fell too** (kappa 0.938 to 0.824). The extractors agreed less about which rubric
rule applies. Line coverage, the statistic that speaks to the completeness of the denominator,
held (0.8655 to 0.8551).

**One provenance chain is broken.** ARP's `arp-add` was lost by the harness and recovered out
of band by a human. Its body is the agent's own work with two JSON key names corrected, but
that row did not arrive through `llmll patch` under a token issued for it. 21 of 22 ARP rows
have an unbroken chain; that one does not. The stage-N agent caught this unprompted and
correctly refused to adjudicate it.

**Two runs is not a trend.** Both targets are small, stateful, enum-and-integer protocols
chosen to fit the shipped fragment. Nothing here says anything about an RFC with substantial
string structure, cryptography, or timing content, and the playbook's own rule is to choose
the RFC to fit the fragment rather than widen the language to rescue a target.

## What the second run cost, and why that is a result

Running a second RFC found **five defects in the driver**, none visible from reading it:

| Defect | How it failed |
|---|---|
| `reconcile.py` hardcoded the first run's source names | **silently** emitted zeros; run continued |
| `rfc_coverage.py` hardcoded the first run's tag prefix | loud STOP, 0/39 rows covered |
| fill prompt's worked example had the wrong AST keys | agent's valid body rejected on apply |
| checkout token held across the whole agent call | one hole wedged, one fill lost |
| **a stage was skipped whenever its outputs existed** | **a failed freeze gate was bypassed by its own output** |

The first two are the same mistake twice: a tool written during run one hardcoding that
target's incidental conventions as though they were the format. That is the clearest possible
evidence that "a second RFC reproduces the shape without re-deciding the method" could not
have been trusted before a second RFC was actually run.

The last is the one to remember. Stage L logged `STOP: RFC-COV-1 failed` and then
`already complete, skipping`, and the wave proceeded. It was harmless only because that
coverage failure was itself the tag bug. A gate whose own failure output disables it is not a
gate. Stages are now skipped only when the manifest **records** completion.

Design point worth keeping: the silent failure was far more dangerous than the loud one. A
gate that stops the run costs minutes; a statistic that quietly returns zeros can ship a false
completeness claim.

## Running it

```bash
scripts/rfc_to_implementation.py --rfc-url <url> --workdir <dir outside this repo> \
  --agent-cmd 'claude -p "$(cat {prompt})" --allowedTools "Read,Write,Bash" --permission-mode acceptEdits'

scripts/rfc_to_implementation.py --status          --workdir <dir>   # alive? advancing? how far?
scripts/rfc_to_implementation.py --audit-blindness --workdir <dir>   # were the extractors isolated?
scripts/rfc_to_implementation.py --self-test                         # mechanical stages vs the TFTP run
```

The workdir must be outside this repository and agents must not have access to it. Both runs
are committed here, inventories and contracts included, so an agent with repo access could
retrieve rather than derive and the blindness claim would be worthless.

## What a third run should test

1. **Answer the coverage question.** Read ARP's 48 exclusions and decide whether the drop to
   55.3% is the target or the dispositioner. Until then the yield claim is unbounded.
2. **A target outside the comfortable shape.** Both runs were enum-and-integer state machines.
   The interesting failure is an RFC where the fragment genuinely does not reach.
3. **No human in the loop at all.** ARP needed one out-of-band recovery. A run with an
   unbroken provenance chain on every row has not happened yet.
