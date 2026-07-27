# RFC 826 (ARP): the second run, end to end

> **Status:** 2026-07-25, compiler v0.14.67. Driver:
> [`scripts/rfc_to_implementation.py`](../../../../scripts/rfc_to_implementation.py), stages A-O.
> First run (TFTP) for comparison: [`examples/tftp_rfc1350/`](../../../../examples/tftp_rfc1350/).

## Why this run exists

TFTP demonstrated the *last* stage. Its clause inventory, dispositions, and root contracts
were authored by hand across earlier sessions and by me; only the fill wave was agent-driven.
So the pipeline's headline claim, "given an RFC URL, produce its implementation", was
demonstrated for one stage and assumed for the other eleven.

This run put a fresh RFC through all fifteen stages with no human authoring at any step. **I
wrote none of these contracts.** Everything from the scope decision to the finished
implementation came from agents reading the RFC text and the language reference.

## Result

| | RFC 826 (ARP) | TFTP, for reference |
|---|---|---|
| dual-extraction line-coverage Jaccard | **0.8551** | 0.8655 |
| rule agreement (Cohen's kappa) | **0.824** | 0.9378 |
| inventory | **91 rows** | 124 |
| Encoded / modeled / vectored / out | **39 / 3 / 1 / 48** | 46 / 20 / 5 / 53 |
| characteristic core | **19**, none dispositioned out | 15, none out |
| coverage of verifiable subject matter (C1+C2+C3) | **42/76 = 55.3%** | 62/65 = 95.4% |
| gate J | **PASS** | PASS |
| RFC-COV-1 at freeze | **PASS** 39/39 Encoded, 19/19 core | PASS 46/46, 15/15 |
| feasibility probes | **6/6** verify, 6/6 mutants refute | 4/4 |
| implementation | **22/22 verified**, whole tree SAFE | 23/23 |
| kill matrix | **14/14 refuted, 5/5 good twins SAFE, 1 unwritable, no survivors** | 8/8, 1/1 |

## The number that matters most

Not the 22/22. That is satisfiability, and satisfiability is consistent with contracts that
exclude nothing.

**14 of 14 mutants refuted against the agents' own bodies, with all 5 good twins surviving.**
The good twins are what stop this being a trivial result: a contract set that refuted
everything, correct variants included, would be as useless as one that refuted nothing. The
mutants are the ARP-specific bug classes an agent chose from the RFC, including
`promiscuous-cache` (caching from any observed packet rather than only when already a target),
`old-address-wins` (ignoring the merge rule's update), `reply-to-reply`, and `unicast-request`.

Read it correctly: a killed mutant proves the contract **excludes one specific behaviour**.
That is eliminative evidence. It does not corroborate that the contract says what RFC 826 says,
because one side of that question is English prose and has no formal answer.

## Where this run is weaker than TFTP, stated plainly

**Coverage of verifiable subject matter fell from 95.4% to 55.3%.** The gate passes because
coverage is reported and never thresholded, which is the correct design, but a swing that large
is the honest bound on what "repeatable" currently means. Either ARP genuinely fits the shipped
fragment worse than TFTP, or this disposition agent was more conservative than the human pass
that dispositioned TFTP. The 48 exclusions each carry a barrier and a reason, so it is
answerable by reading them, and it has **not** been answered here.

**Rule agreement was lower** (kappa 0.824 against 0.938). The two extractors agreed less about
which rubric rule applies. Line coverage, which is the statistic that speaks to the
completeness of the denominator, held up well at 0.8551.

## One provenance caveat, on the record

`arp-add` was lost by the harness during the wave and recovered by me out of band. The stage-N
agent caught this unprompted: it noticed `roots.ast.json` was modified 50 minutes after
`wave.json`, swept all 22 agent directories, confirmed every body in the tree is identical to
its own agent's submitted `body.json` (`arp-add` included), and then drew the line correctly:

> What has no recorded evidence is F3 for that row (the body arriving through `llmll patch`
> under a token issued for that pointer). That is an adjudication for a human, not something
> I resolve.

That is right. The body is the agent's own work, with only two JSON key names corrected
(`then`/`else` to the schema's `then_branch`/`else_branch`), but the provenance chain for that
one row contains a human edit. 21 of 22 rows have an unbroken chain; `arp-add` does not.

The stage-N agent also found rows A90, A40 and A41 are cited by no clause in the frozen
surface, making one pre-registered mutant unwritable. Recorded as pre-registered rather than
reinterpreted.

## What the run cost, and what it found

Five defects in the driver, none of which were visible from reading it:

| Defect | Failure mode |
|---|---|
| `reconcile.py` hardcoded `RFC1350`/`RFC1123` source names | **silent** zeros, run continued |
| `rfc_coverage.py` hardcoded the `T\d{3,}` tag prefix | loud STOP, 0/39 covered |
| fill prompt's worked example used `then`/`else`, not `then_branch`/`else_branch` | agent's valid body rejected on apply |
| checkout token held across the whole agent call, then stale | hole wedged, one fill lost |
| **a stage was skipped whenever its outputs existed** | **a FAILED freeze gate was bypassed by its own output file** |

The last one is the serious one. On the relaunch, stage L logged
`STOP … RFC-COV-1 failed` and then `already complete, skipping`, and the wave proceeded. The
outcome here was fine because the coverage failure was itself caused by the tag bug and the
surface genuinely passes. Had it been a real failure, 22 agents would have built against an
unfrozen surface with nothing stopping them. A stage is now skipped only when the manifest
**records** it complete, not merely when its files exist.

The first two are the same mistake twice: a tool written during the first run hardcoding that
target's incidental conventions. That is the clearest argument that the repeatability claim
could not have been trusted before a second RFC was actually run through it.

## Stages N and O, completed afterwards

The first pass left two stages unfinished: stage N produced its mutants but never wrote the
catalogue, and stage O never ran. Both prompts were corrected and re-run, so all fifteen stages
have now completed under the driver.

**The agent's kill matrix cross-checks the hand scoring exactly: 19 overlapping entries, zero
disagreements.** It also carries one entry the hand pass dropped, `vector-reply-mismatch`,
marked `unwritable` because no clause in the frozen surface cites A90 and there is therefore
nothing for the perturbation to violate. Keeping it in the denominator rather than globbing
only for mutant files is the more honest accounting, and the agent did it unprompted.

The agent-written report is [`REPORT-agent-written.md`](REPORT-agent-written.md). It holds the
claim discipline its prompt demands, on every point: class-stratified coverage rather than the
raw ledger ratio, 19/19 core, survivors reported, the unwritable entry left visible, the
trusted step disclosed, what is not claimed stated, evidence named as eliminative, the
saturated benchmark acknowledged, and no framing of the result as verification catching agents
out.

Three things it does that the prompt did not ask for: it recomputed every figure from the
artifacts rather than copying stage output and said so; it re-verified the tree cold in a fresh
directory with no `.verified.json` sidecar, which is exactly the stale-cache trap this project
has hit before; and it pinned the pre-registration by hash and confirmed it had not been edited
after the run.

## Reproducing

```bash
scripts/rfc_to_implementation.py --rfc-url https://www.rfc-editor.org/rfc/rfc826.txt \
  --workdir <dir outside this repo> --wave-agents 5 \
  --agent-cmd 'claude -p "$(cat {prompt})" --allowedTools "Read,Write,Bash" --permission-mode acceptEdits'

scripts/rfc_to_implementation.py --status --workdir <dir>          # is it alive, advancing, how far
scripts/rfc_to_implementation.py --audit-blindness --workdir <dir> # were the extractors isolated
```

The workdir must be outside this repository and the agents must not have access to it: the
committed runs contain inventories and contracts an agent could retrieve instead of deriving,
which would make the blindness claim worthless.
