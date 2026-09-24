# Experiments

These experiments test whether agent-written LLMLL code can be trusted, and what the verifier's report is worth. The evidence is for assurance: code written by an agent, proved against a contract the agent did not write. It is weak evidence that the verifier catches agents' bugs: in the minimal-agent runs no agent wrote a wrong fill, and in the RFC-SWARM TFTP run the verifier rejected 6 fills that the agents then repaired, on a benchmark that summary calls saturated.

Two summaries answer the main questions. Read them first:

- [`minimal-agent/SUMMARY.md`](minimal-agent/SUMMARY.md): can a frontier agent write correct LLMLL on the first try?
- [`rfc-swarm/SUMMARY.md`](rfc-swarm/SUMMARY.md): can agents turn an RFC into a traceable spec and a verified implementation?

## Headline results

**First-try correctness** ([`minimal-agent/SUMMARY.md`](minimal-agent/SUMMARY.md)):

- On the two fixtures built to induce a plausible subtle error (a transfer that must conserve money, a byte operation that must saturate): "**30/30 grade B (verified-correct) across three frontier models**" and "**0/54 wrong fills across the whole solver-catches campaign**".
- Agents avoided a network-reaching helper they were told about only in prose, 18 of 18 times.
- The safety net "was never triggered by a real agent fill, because the agents did not produce wrong fills." Every hand-written wrong fill was refuted, so "the value of verification *under agent error* is therefore established by construction, not by an observed agent mistake." A follow-up built to elicit a subtly wrong fill produced none in 69 attempts.

**RFC to verified implementation** ([`rfc-swarm/SUMMARY.md`](rfc-swarm/SUMMARY.md)):

- Three runs: TFTP (RFC 1350), ARP (RFC 826) and Base-N (RFC 4648). The two that reached implementation verified 23 of 23 and 22 of 22 functions. ARP's contracts were written by an agent from the RFC text and `LLMLL.md` alone.
- The contracts are discriminative: "**22 of 22 mutants refuted across both runs, with all 6 good twins surviving.**"
- The summary corrects itself. TFTP's published coverage of 95.4% counted rows the model cannot exercise; removing them gives **78.5%**, and "the earlier 95.4% overstated it." The corrected range across targets is roughly 55 to 85 percent, depending on whether the wire format is fixed-length.
- The third run stopped. RFC 4648 "halted at gate J on the characteristic-core condition, after 76 minutes", the first time a stop condition fired for a real reason. The pre-registered prediction called the stop but gave the wrong reason.
- It lists what is not established, for example that either RFC is "verified" (the ledger dispositions each clause; TFTP carries 46 of 124) or that verification caught agents out.

## Every experiment

| Directory | What it asked | Status |
|---|---|---|
| [`minimal-agent/`](minimal-agent/README.md) | Can an agent write a correct program or hole fill on the first round, from the spec, the schema and a problem statement? | Complete; answer in [`SUMMARY.md`](minimal-agent/SUMMARY.md) |
| [`rfc-swarm/`](rfc-swarm/README.md) | Can agents go from an RFC to a clause-traceable spec and a verified implementation? | Three runs; answer in [`SUMMARY.md`](rfc-swarm/SUMMARY.md) |
| [`repair-loop/`](repair-loop/README.md) | Does iterating on verifier feedback drive an agent to a terminal state, compared with Python and Go at the same budget? | Phase 3 partly run (57 of 81 cells, [postmortem-004](repair-loop/findings/postmortem-004-phase3-launch.md)). LLMLL took more turns than Python, which the postmortem attributes to LLMLL's stricter terminal condition; within Claude, LLMLL reached it in 5 of 18 cells and Python in 18 of 18 ([postmortem-005](repair-loop/findings/postmortem-005-claude-deepening.md)) |
| [`rfc1982-eval/`](rfc1982-eval/findings.md) | Does the spec-from-RFC pipeline meet its six success criteria on RFC 1982 (serial number arithmetic)? | Complete: six of six pass, three of three functions verified |
| [`r5-validation/`](r5-validation/findings.md) | When two fills both verify but behave differently, does the divergence check report the under-constrained contract? | Complete: yes, soundly; "no divergence observed" is not evidence that a contract is tight |
| [`adv-spec-weaken-0/`](adv-spec-weaken-0/README.md) | Do the weakness checks catch a contract weakened on purpose until a wrong body verifies? | First run complete; one laundering case is undetected by design ([`findings.md`](adv-spec-weaken-0/findings.md), F-002) |
| [`cdp-0/`](cdp-0/README.md) | What is the baseline distribution of contract discriminative power over the existing corpus? | Complete: `cdp-discriminating-weak` ([`findings.md`](cdp-0/findings.md)) |
| [`cdp-perf-0/`](cdp-perf-0/README.md) | What does `--cdp` cost in wall-clock time? | Complete: about 27 ms plus 43 ms per candidate ([`findings.md`](cdp-perf-0/findings.md)) |
| [`int-pre/`](int-pre/README.md) | Does unbounded `Integer` code generation slow generated programs down? | Complete: no measurable regression, factor 1.015 on TOTP ([postmortem-001](int-pre/findings/postmortem-001.md)) |
| [`spec-agree-1/`](spec-agree-1/README.md) | What fraction of the RFC-SWARM corpus can the contract-subsumption gate decide? | Complete: 10.6% |

Also here: [`methodology.md`](methodology.md) (why first-round and repair-loop measurement are both valid regimes) and [`language-comparison-backlog.md`](language-comparison-backlog.md) (the cross-language harness backlog).

Each directory's `findings.md` routes issues to the compiler, language and documentation roles; `findings/postmortem-*.md` files hold the evidence. Several READMEs carry a status line older than their findings; where they disagree, the findings are more recent.
