# RFC-SWARM: what has actually been demonstrated

> Three runs, 2026-07-24, 2026-07-25 and 2026-07-27, against compiler v0.14.65 and v0.14.67.
> This is the cross-run summary. Per-run detail: [`runs/rfc4648/RESULTS.md`](runs/rfc4648/RESULTS.md),
> [`runs/rfc826/RESULTS.md`](runs/rfc826/RESULTS.md)
> and [`../../examples/tftp_rfc1350/`](../../examples/tftp_rfc1350/). Procedure:
> [`../../docs/design/rfc-swarm-playbook.md`](../../docs/design/rfc-swarm-playbook.md).

## The claim

> Given an RFC, an orchestrating agent builds a formal specification traceable clause by
> clause to the source text, and a swarm of blind agents produces an implementation the
> compiler proves satisfies it. Every normative clause is dispositioned: verified, modeled,
> tested, or excluded with a cited reason.

## The three runs

| | **TFTP** (RFC 1350 + 1123) | **ARP** (RFC 826) | **Base-N** (RFC 4648) |
|---|---|---|---|
| who wrote the contracts | **a human (me)** | **agents, unaided** | agents; never reached |
| stages run by the driver | the wave only | **all fifteen** | **A-I, then halted** |
| dual-extraction Jaccard | 0.8655 / 0.725 | 0.8551 | **0.9732** |
| rule agreement (kappa) | 0.9378 | 0.824 | 0.8057 |
| inventory rows | 124 | 91 | 64 |
| Encoded / modeled / vectored / out | 46 / 20 / 5 / 53 | 39 / 3 / 1 / 48 | 39 / 5 / 0 / 20 |
| characteristic core | 15, none out | 19, none out | **23, one out** |
| coverage of C1+C2+C3, as published | 62/65 = 95.4% | 42/76 = 55.3% | 44/52 = 84.6% |
| coverage, corrected (see below) | **51/65 = 78.5%** | **42/76 = 55.3%** | **44/52 = 84.6%** |
| gate J | PASS | PASS | **STOP** |
| RFC-COV-1 at freeze | PASS 46/46, 15/15 | PASS 39/39, 19/19 | never reached |
| feasibility probes | 4/4 | 6/6 | 6/6 |
| implementation | 23/23 verified | 22/22 verified | never reached |
| whole tree | SAFE, body-faithful | SAFE, body-faithful | never reached |
| kill matrix | 8/8 refuted, 1/1 good twin | **14/14 refuted, 5/5 good twins** | never reached |
| survivors | none | none | n/a |

## The third run stopped, and that is the result

RFC 4648 was chosen because **no stop condition had ever fired for a real reason**. Gate J had
passed twice; gate L had failed once, on ARP, and only because of a hardcoded tag prefix in our
own lint, which the resume bug then bypassed. A method whose stop conditions have never stopped
anything has not shown that it has working stop conditions.

It halted at gate J on the characteristic-core condition, after 76 minutes, having spent stages
A through I and never reached the wave. The committed prediction
([`runs/rfc4648-PREDICTION.md`](runs/rfc4648-PREDICTION.md), written before launch) called that
outcome first and called the reason wrong. It expected the bit-regrouping core to hit the same
B5 string-structure wall that took ARP's `8 + 2*ar$hln + ar$pln`. Bit regrouping verified fine.
What halted the run was **line wrapping**, RFC 4648 L161-163, a clause about inserting characters
into the output stream. The prediction also forecast carried C1+C2+C3 below 20%; the ledger
recorded 84.6%, the highest of the three runs.

**So RFC 4648 is not the bad-fit target it was chosen to be.** It fits the fragment better than
either protocol, and it stopped on a single clause. That is a fact about the method's reach that
two passing runs could not have produced.

Two things make the halt meaningful rather than circular. Stage F, which names the characteristic
core, is **structurally blind to the fragment**: its prompt contains the inventory and the RFC
text and zero occurrences of `scope.md`, "decidable fragment", or `LLMLL`, and instructs the
agent "you do not yet know what will verify, and that is deliberate." And the halt was cheap,
exactly as the prediction said a working gate would make it.

Using the barrier list also broke it. `B7` was defined as "true by construction: the model admits
no constructor for the forbidden thing, so no mutant can exercise the row." A probe refuted that
claim on the very row that fired the gate: a mutant *can* place a line feed, because the
constructor is a table entry. The row's exclusion stands under `B5`, string structure, and the
`B7` criterion has been rewritten. Both are recorded in
[`runs/rfc4648/AMENDMENT-1.md`](runs/rfc4648/AMENDMENT-1.md), dated, with the STOP left as fired.

An audit of all 64 rows against the pinned source bytes found citations sound 64/64, normativity
strengths uninflated 64/64, and **one disposition reason that misreads its own quote**, moving a
positional qualifier out of an `unless` exception and into the prohibition. Found by reading
three lines of the file stage A exists to pin.

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

**Three runs is not a trend either.** The two that completed are small, stateful,
enum-and-integer protocols chosen to fit the shipped fragment. The third is not a state machine
at all, and it halted. Nothing here says anything about an RFC with substantial cryptography or
timing content, and the playbook's own rule is to choose the RFC to fit the fragment rather than
widen the language to rescue a target.

**Two of the three runs produced a defect in the instrument that only running it could find.**
The second found five driver defects; the third found that the `B7` barrier's definition was
undecidable as written and false in its first consequential use. Neither was visible from reading
the code or the playbook.

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
scripts/rfc_to_implementation.py --rfc-url <url> --workdir ~/rfc-swarm-runs/<name> \
  --agent-cmd 'claude -p "$(cat {prompt})" --allowedTools "Read,Write,Bash" --permission-mode acceptEdits'

scripts/rfc_to_implementation.py --status          --workdir <dir>   # alive? advancing? how far?
scripts/rfc_to_implementation.py --audit-blindness --workdir <dir>   # were the extractors isolated?
scripts/rfc_to_implementation.py --self-test                         # mechanical stages vs the TFTP run
```

The workdir must be outside this repository and agents must not have access to it. All three runs
are committed here, inventories and contracts included, so an agent with repo access could
retrieve rather than derive and the blindness claim would be worthless.

It must also be somewhere the operating system will not reclaim. A reboot destroyed an
eight-stage RFC 4648 run whose workdir was under `/private/tmp`; the driver now refuses such a
location outright. The two constraints pull against each other, and `~/rfc-swarm-runs/<name>`
is the shape that satisfies both.

## What the third run answered, and what a fourth should test

The third run settled two of the three items the second run left open, and left the third
untouched.

1. **The coverage question, answered.** The drop to 55.3% on ARP is the target, not the
   dispositioner. The three runs now read 78.5%, 55.3% and 84.6%, and the ordering tracks wire
   format rather than method: ARP's length-driven fields need arithmetic over a byte sequence
   the fragment does not reach, while TFTP's fixed-length fields and RFC 4648's fixed-width
   quanta do not. **Carried fraction is a property of the target's format, and this method
   carries roughly 55-85% of verifiable subject matter depending on it.**
2. **A target outside the comfortable shape, and gate J answered.** RFC 4648 is not a state
   machine and it halted, so a stop condition fired for the first time in three runs. Gate J's
   characteristic-core condition is binary, and its truth table is now complete: no core row
   excluded on TFTP and on ARP, both pass; one core row excluded on RFC 4648, stop. **Nothing
   further about that condition is learned from a target that fails harder**, since five core
   exclusions would reach the same verdict by the same path. What the run did **not** settle is
   whether the gate's *inputs* can be trusted. It fired on an exclusion whose stated reasoning
   did not survive a probe, and a person caught that, not the pipeline.
3. **No human in the loop at all. Still not achieved,** and the third run moved backwards on it.
   ARP needed one out-of-band recovery; RFC 4648 needed a human to read three lines of the RFC to
   catch a misread clause, and a human to write four probes to settle a barrier.

What a fourth run should test:

- **A run that reaches the wave.** Gate L and the per-fill acceptance bar in stage M have still
  never fired for a real reason: ARP's gate L failure was our own hardcoded tag prefix, and RFC
  4648 halted at J without reaching either. So the next target should be chosen to **pass** gate
  J, which is the opposite of this run's heuristic.
- **Not another bad-fit target.** RFC 4648 was selected as bad-fit and carried the most of the
  three, and its predicted failure mechanism was wrong as well. Fit prediction is a thing this
  method has now been shown to do poorly, and a target obviously beyond the fragment makes a
  refusal meaningless, so the useful band is narrow and we have missed it once.
- **A `B7` row under the corrected criterion.** Six of RFC 4648's eight `B7` rows named what
  entails them unprompted. Whether that holds when the rule requires it is untested. A second
  unprompted sample now exists without a fourth run: re-reading ARP's four retired-phrasing `B7`
  rows on 2026-07-28 gives **3 of 4**, and the one that fails
  ([`runs/rfc826/RESULTS.md`](runs/rfc826/RESULTS.md), A63) fails in a way the question did not
  anticipate. It names an entailment, but from a **modeling decision** rather than from the
  declared types or a sibling row, which the corrected criterion does not admit. So a prompt that
  merely demands an entailment would not catch it, and the fourth run should test the *kind* of
  ground a `B7` row rests on, not whether it names one.
- **The artifact audit, now stage G2, and it found the misreading on its own.** It exists as of
  2026-07-28, between the disposition pass and the probes. Building it settled the design
  empirically rather than by argument: a substring test for "the quote appears in its cited span"
  fires on **22 of the 113 real RFC 1350 rows**, because a census abbreviates long clauses and
  flattens packet diagrams. Token coverage separates cleanly instead: every true citation scores
  ≥ 0.875, and the same quotes against 6655 wrong spans reach 0.500 at the 99th percentile.

  **Run against the surviving RFC 4648 workdir it halts on A1**, the row a person needed a manual
  pass to catch. The mechanical half resolves 64/64 citations with no near-miss; the delegated
  half returns 42 verdicts, one per subject, and flags exactly one. Its stated ground matches
  Amendment 1's independent human analysis: *"'after a specific number of characters' belongs to
  the unless-exception ... so the reason states as forbidden exactly the case the clause carves
  out."* The agent ran **prompt-only, with every filesystem tool disabled**, because A1's answer
  is committed in this repository and an agent that could read it would retrieve rather than
  derive.

  **This took three attempts and the first two are why the result is worth anything.** Attempt
  one used a worked example in the prompt drawn from A1 itself, handing the agent the clause, the
  reason, the verdict and both evidence strings; it returned them verbatim, which measured the
  example and not the ledger. That is the same defect as the fill prompt whose worked example
  carried the wrong AST keys. Attempt two replaced it with an invented example of the same error
  class. Attempt three teaches a **quantifier** error instead, so neither the row nor its failure
  mode is exemplified, and A1 is still the only row flagged.

  **What is not established.** One target and one model. The 41 `matches` verdicts have no oracle,
  so the false-negative rate is unmeasured and this says nothing about whether the ledger holds
  other misreadings. The prompt still names exception-attachment as one of five classes worth
  checking, so the class is named even though it is not exemplified.
