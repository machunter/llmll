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
| coverage of C1+C2+C3 | **62/65 = 95.4%** | **42/76 = 55.3%** |
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

**Coverage is not stable across targets: 95.4% then 55.3%.** This is the most important
number in the table and it is the one that bounds the repeatability claim. The gate passes in
both cases because coverage is *reported and never thresholded*, which remains the right
design, but a swing of forty points means "the process reproduces" is a claim about shape, not
about yield. Whether ARP genuinely fits the shipped fragment worse, or its disposition agent
was simply more conservative than the human pass on TFTP, is answerable from the 48 recorded
barriers and **has not been answered**.

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
