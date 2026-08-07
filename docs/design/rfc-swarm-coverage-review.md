---
name: rfc-swarm-coverage-review
title: "Professor review: Phase 0 STOP verdict and the fragment-widening question"
status: "standalone review (not folded)"
consumers: [user, language-team, experiment-lead]
date: 2026-07-24
reviewer: professor
---

# Professor review: Phase 0 STOP verdict and the fragment-widening question

Reviewing the RFC-SWARM Phase 0 output: `examples/tftp_rfc1350/VERIFICATION_SCOPE.md` (124-row census),
`experiments/rfc-swarm/PRE-REGISTRATION.md` Appendix A (the fired STOP and its defect analysis), the owner's question (B) about widening
`Σ_auto`, and the follow-on question about Leanstral's role (F-13 to F-16).

## Restatement

(A) The pre-registered quantitative STOP fired at 46.8% dispositioned out against a 30% ceiling while the qualitative STOP passed 15/15 on
the characteristic core; the project asks whether the threshold was defective or the target failed. (B) Whether more of the 58 exclusions
are recoverable by extending the fragment, which re-opens the standing rule at `rfc-swarm-roadmap-proposal.md:633-638`. (C) Whether the
Lean tier has a role here.

Verdicts. (A) The threshold is defective in the technical sense that its value is fixed by a property of the target document rather than by
the property the STOP was written to test, and I can show that arithmetically rather than argue it. (B) The fragment is not the barrier for
55 of the 58 rows, and the two rows where a sound decidable extension exists are not worth buying. (C) Leanstral recovers zero rows on this
target and should stay parked.

## Context located

1. `examples/tftp_rfc1350/VERIFICATION_SCOPE.md:107-128` (disposition and class tables), `:130-139` (STOP), `:141-161` (characteristic
   core), `:167-292` (the 124 rows), `:295-323` (scope matrix), `:325-344` (trusted composition schema).
2. `experiments/rfc-swarm/PRE-REGISTRATION.md:66-81` (acceptance bars and the STOP), `:90-95` (process budgets), `:193-253` (Appendix A);
   `docs/design/rfc-swarm-roadmap-proposal.md:129-138` (the descope boundary I shaped in F-1), `:212-224` (mutation adequacy), `:524-528`
   (weaker-model appendix arm), `:602-604` (Phase 3 STOP), `:631-663` (§5).
3. `docs/design/spec-from-rfc-pipeline.md` §1.2: the C1-C6 taxonomy declares C4 (opaque primitive) and C6 (SHOULD-prose, liveness, timing,
   concurrency, security arguments) untranslatable. Written in Rev 0, evaluated on RFC 1982 on 2026-07-12, before RFC 1350 was selected.
   This pre-dating is the pivot of F-1.
4. `LLMLL.md:943` (`Σ_auto`), `:947-952` (completeness facts and citations), `:213,263` (refinement predicates are quantifier-free), `:280`
   (codegen faithfulness), `:1056` (LCF anti-laundering smart constructor); `docs/design/data-scope-extension.md:312-317` (buy exactly as
   much undecidability as a bug class needs), `:319-371` (Levers A, B, C), `:405` (the checkout brief is the sole channel).
5. `docs/design/leanstral-integration-scope.md` §1-§6 (three-layer rebuild; layer 1 structurally unfaithful; T-B model-proposes /
   kernel-checks; the `sanitizeProof` guard); `docs/compiler-team-roadmap.md:79,150` (LEAN-GA row; Lever C gated on it).
6. I recomputed the class-by-disposition and rule-by-disposition cross-tabs from the §7 table rather than taking §4 on trust. They reconcile
   at 124 rows, 40/21/5/58, and are the evidence for most of what follows.

## Gaps and hazards

### F-1 (BLOCKER, measurement validity). The 30% ceiling measures the RFC's genre composition, not the verifier's reach.

Disposition against the C1-C6 class, recomputed from `VERIFICATION_SCOPE.md:167-292`:

| Class | Encoded | Deployment-modeled | Vectored | Dispositioned out | Total |
|---|---:|---:|---:|---:|---:|
| C1 state transition | 20 | 4 | 0 | 0 | 24 |
| C2 arithmetic invariant | 9 | 0 | 0 | 1 | 10 |
| C3 length / format | 10 | 14 | 0 | 2 | 26 |
| C4 opaque primitive | 1 | 3 | 0 | 10 | 14 |
| C5 test vector | 0 | 0 | 5 | 0 | 5 |
| C6 timing / liveness / transport / trace | 0 | 0 | 0 | 45 | 45 |
| **Total** | **40** | **21** | **5** | **58** | **124** |

Read the C6 row first. Forty-five rows, 36.3% of the census, sit in a class the pipeline document declared untranslatable by any channel
before this target existed. C6 alone exceeds the ceiling. No disposition judgment made during the census, however conservative, could have
brought the total under 30%: the ceiling was breached by class assignment before the disposition pass began. Fifty-five of the 58 exclusions
are C4 or C6; the remaining three are T027 (TID range), T053 (NUL-terminated filename), T080 (NUL-terminated ErrMsg). That is the entire
discretionary surface of the exclusion set: three rows, 2.4%.

So the validity statement is arithmetic, not rhetorical. `dispositioned-out / total` equals `(C4 + C6) / total` to within 2.4%, and that is
a statistic about how much of the target document is transport binding, timers, character-set translation, and deployment prose. It is
nearly independent of how the encoder behaved. A metric whose value is fixed by the object under measurement rather than by the behavior
under test does not test that behavior.

**Disposition:** record the trigger as FIRED and the threshold as DEFECTIVE, with this cross-tab as evidence. Do not re-target. Replace the
quantitative condition per F-3 before Phase 1.

### F-2 (MAJOR, satisfiability). No complete protocol RFC passes a 30% out-ceiling under an obligation rubric.

An IETF protocol specification generically contains, beyond its protocol logic: a transport binding, timer and retransmission behavior,
security considerations, and operational guidance. None of the four is a property of a function, so none is reachable by any function-body
verifier in any language. Under a rubric counting obligations with a "when in doubt, mark normative" tie-break
(`VERIFICATION_SCOPE.md:61-62`), all four add denominator and none can add numerator.

RFC 1350 is near the smallest complete protocol specification available, 11 pages and five packet types, and its C6 mass is still 36.3%. Any
larger or more operational document is strictly worse, and §2.4 of the roadmap already rejected RFC 5905 on precisely this ground
(`rfc-swarm-roadmap-proposal.md:360-364`), which shows the ceiling was already doing target selection by a proxy tracking page count and
operational-prose density. The documents that pass are those with no transport binding and no timers: pure-algorithm RFCs. RFC 1982 (9/9
dispositioned, 7 contracted) and RFC 4226/6238 are exactly that class, and exactly what the project already did. Honoring the STOP as
written sends the track back to the class it was created to leave. Note also that the two prior anchors are not comparable denominators:
A4's nine clauses are a hand-selected *core*, so its 22% out-rate measures the selection, not the coverage, while RFC 1350's 124 rows are
the first complete census this project has produced. A reader who sees "A4: 22% out, TFTP: 47% out" draws the wrong conclusion.

### F-3 (MAJOR, replacement instrument). Retire the ratio; keep the core condition; add a closed barrier list and a class-stratified report.

A coverage ratio is the wrong instrument for the reason F-1 gives. The right instrument tests what the STOP was meant to test: that no
obligation was excluded for the encoder's convenience. Three conditions, all fixable now.

**(i) The characteristic-core condition, unchanged.** It already dominates by design, it passed 15/15, and it is the condition that would
fire if the target were wrong. Keep it verbatim for later phases.

**(ii) A closed barrier list, with a STOP on any exclusion outside it.** Declare the admissible barriers before Phase 1: transport binding
and encapsulation; timing and liveness; opaque character-set or cryptographic transform; trace-level or implementation-corpus scope;
deployment and procurement policy; open-world extension permission; bounded quantification over buffer contents. Any row whose reason does
not resolve to a listed barrier halts the phase. This fires in the direction that matters: when a row is excluded because encoding it would
be inconvenient.

**(iii) A class-stratified report, published as a statistic and not as a threshold.** Within C1+C2+C3, the 60 rows stating a property of the
protocol automaton or its packet formats: 39 Encoded (65.0%), 18 Deployment-modeled (30.0%), 3 out (5.0%). Ninety-five percent carried. Each
of the three exclusions must state what a verifier would need to carry it (T027: nothing, it is in-fragment today and excluded on model
grounds, F-6; T053 and T080: a bounded universal quantifier over array indices, F-8). Condition (iii) must be labeled post-hoc: it is a
legitimate *reported* figure because the C1-C6 classes pre-date the target, and not a legitimate *threshold*, because its value is now known.

### F-4 (MAJOR, literature). 32.3% Encoded is not damning and is not comparable to anything, because nobody in this lineage reports the number at all.

**HOL-TCP** (Bishop, Fairbairn, Norrish, Sewell, Smith, Wansbrough, SIGCOMM 2005; "Engineering with Logic", J. ACM 66(1), 2019) reports
trace-validation pass rates against real implementations, thousands of tests at per-stack rates in the low-to-mid 90 percents, and no
fraction of RFC 793's clauses; its authors argue the RFCs are too ambiguous to serve as a denominator at all. **seL4** (Klein et al., SOSP
2009; TOCS 2014) reports an *assumption list*: compiler and linker (the compiler later closed by Sewell, Myreen, Klein, PLDI 2013),
hand-written assembly, boot code, hardware, DMA, with liveness and timing excluded wholesale as here. **IronFleet** (Hawblitzel et al., SOSP
2015) reports trusted-spec size and proof-to-code ratio; the Paxos literature is nobody's denominator. **CompCert** (Leroy, CACM 2009)
reports a named subset (Clight) plus a named list of unverified components, and Yang et al. (PLDI 2011) found bugs only in that unverified
front-end, which is the payoff of naming a boundary rather than scoring it. In protocol formalization specifically, McMillan and Zuck's Ivy
specification of QUIC (SIGCOMM 2019) covers wire format and transport state machine and explicitly excludes loss recovery, congestion
control, and the crypto handshake, the same three classes excluded here; the TLS 1.3 symbolic analyses (Cremers et al., CCS 2017) report
modes and properties of a Dolev-Yao model. Certification is the only lineage requiring per-requirement disposition, and it is the one this
ledger imitates: DO-178C demands bidirectional traceability with every requirement dispositioned, and DO-333 permits formal analysis to
substitute for verification activities while imposing **no minimum formally-proved fraction**.

So the reading of 32.3% is: a number nobody else publishes, in a form nobody else publishes it, with no baseline making it high or low. What
the writeup can defend is the composite: 32.3% Encoded, 53.2% carried by some mechanized channel, 95.0% of protocol-automaton and
packet-format rows carried, 100% dispositioned, zero silent drops. A hostile reviewer will not attack the value; the two available attacks
are that the denominator is self-produced and the numerator self-selected. Against the first the defenses are strong: dual blind extraction,
Jaccard 0.866, Cohen's kappa 0.938 (`VERIFICATION_SCOPE.md:73-82`), "almost perfect" on Landis-Koch (Biometrics, 1977) and better than most
published systematic reviews report. Against the second: the pre-registered characteristic core and the kill matrix with survivors. Both
belong in the same paragraph as the percentage, or the percentage will be read alone.

### F-5 (MAJOR, inventory consistency defect). T002 and T006/T111 have the same logical shape and opposite dispositions.

`VERIFICATION_SCOPE.md:170` dispositions T002 (no directory listing, no authentication) as **Deployment-modeled**, reason "the request ADT
has exactly two constructors (RRQ, WRQ), so no directory or authentication operation exists by construction". `:174` dispositions T006 (must
not implement mail mode) as **Dispositioned out**, reason "no mail constructor exists to verify"; `:279` does the same for T111. Same
argument, a negative obligation discharged by constructor absence, opposite dispositions.

T002's treatment is correct, and it is not a loophole: a refute crux is constructible. A twin whose mode enum carries a Mail arm that the
request-accept step admits violates a post stating the accepted mode set, the same refute shape already used for T118's `"octet"` literal
gate. T104 (error code 7) is downstream and follows T006. This moves two rows, possibly three. It does not rescue the ceiling and must not be
presented as trying to; it is a correctness defect, and fixing it applies a rule the census already contains.

### F-6 (MAJOR, question B, transport/TID). The largest exclusion class is a model-boundary question with zero language work in it. Split it.

Twenty-nine rows are excluded for transport reasons and no language work would recover any of them; everything they need is int equality.
T027's own reason concedes this: "the 0 to 65535 bound is arithmetic the fragment could state, but TIDs are transport identity and are not
carried in the modeled state" (`VERIFICATION_SCOPE.md:195`). The barrier is the S0 model boundary, not `Σ_auto`.

**Recoverable and worth recovering (6 rows): the source-TID mismatch discipline.** T022, T023, T046, T047, T102, T121. Two int fields in the
connection state (own TID, peer TID) make each a single-transition safety property in the Alpern-Schneider sense: on a packet whose source
TID differs from the recorded peer TID, the transition emits ERROR code 5 and leaves the transfer state unchanged. Equality and disequality
on ints, QF-LIA, the shape the Phase 0 probes already verified for block numbers (`PRE-REGISTRATION.md:151-153`). The crux is not decorative:
the source-TID check is TFTP's only defense against blind off-path injection into an established transfer, so a mutant accepting a mismatched
source TID is a real attack, in the same register as the Sorcerer's Apprentice crux.

**Not recoverable, and modeling it would be scope inflation (23 rows).** T001, T024-T026, T029, T036, T038-T044, T105-T108, T112, T116,
T122, T123 state properties of the UDP binding: which port carries the initial request, how TIDs become port numbers, what the datagram
length field counts, checksum computation, wire header order. LLMLL would model a network stack it does not have and then verify the model
agrees with itself, producing a ledger entry and nothing else. T037 (choose TIDs randomly) is additionally probabilistic and out by nature.

The generalizing criterion, which I recommend adopting: **a row is modelable when the obligation is a property of the protocol automaton
whose violation is a single transition, regardless of whether the state variable is conventionally called transport; it is not modelable when
the obligation is a property of a layer the artifact does not implement.** That is stated independently of any number it produces, which is
what makes applying it now legitimate under F-9.

### F-7 (MAJOR, question B, timing and liveness). Do not put a temporal fragment in `Σ_auto`.

Nine rows (T014, T015, T020, T084-T086, T088, T091, T114) are timing or liveness. Three points, by weight.

**It is a category error before it is a decidability problem.** LLMLL's unit of verification is a function and its contract; a liveness
property is a property of a set of behaviors. There is no postcondition on `step` whose meaning is "eventually acknowledged". Per-event
consequences of timing rules are already carved out and Encoded where they exist (`rfc-swarm-roadmap-proposal.md:243-248`), which is the
correct treatment and is done.

**The theories exist, are decidable, and live in other tools.** Finite-state LTL/CTL model checking is decidable and cheap, and TFTP's
control state is finite. Real-time obligations (T114's adaptive RTO, T084's dally) are timed automata, reachability PSPACE-complete (Alur and
Dill, TCS 126(2), 1994), which UPPAAL decides in practice. The retransmission-doubling property the duplicate-ACK fix prevents is
quantitative and needs probabilistic model checking. None of these is a refinement predicate. If the project ever wants the liveness half,
the route is an export path from `step` to Ivy, TLA+, or NuSMV as a separate artifact with a disclosed relationship to the LLMLL code, in the
tool lane: what McMillan and Zuck did for QUIC and what Newcombe et al. (CACM 2015) describe at AWS.

**Doing it inside the fragment costs the trust story.** `LLMLL.md:947` states that over `Σ_auto` symbols the solver is a sound and complete
decision procedure and SAFE is a decidable side condition, not a quantifier over solver runs. Temporal operators or quantification over
traces end that sentence, and `data-scope-extension.md:312-317` already gives the governing rule. Zero is the right purchase here.

**One writeup repair.** §9 discloses the per-step-to-all-traces closure as a trusted schema. Right to exist, undersold: the closure is the
invariance rule (`Init ⟹ Inv`, `Inv ∧ Next ⟹ Inv'`, therefore `□Inv`), a theorem of temporal logic (Manna and Pnueli, *Temporal Verification
of Reactive Systems: Safety*, 1995). What is actually trusted is the *modeling* claim that iterating `step` is the deployed system's behavior
set. Say that instead: same disclosure, correctly located, and it stops reading as an induction principle waved through.

### F-8 (MAJOR, question B, string structure). Sound and decidable for two rows, mis-named in the census, still not worth buying.

**T053 and T080 are not word-equation problems.** Over a fixed-length `bytes[512]`, "terminated by a single zero byte at index k" is
`select(b,k) = 0 ∧ ∀j. (0 ≤ j < k) → select(b,j) ≠ 0`. That is the **array property fragment** (Bradley, Manna, Sipma, *What's Decidable
About Arrays?*, VMCAI 2006): universally quantified index variables, index guards restricted to comparisons among index terms, no nested
`select` on a quantified index. Decidable, and it combines with the QF array theory and QF-LIA that Lever A already ships (`LLMLL.md:952`).
The extension is sound and decidable, and I want that recorded accurately rather than filed under an impossibility that does not apply.

**It is still the wrong purchase.** The cost is a bounded universal quantifier in a refinement surface that `LLMLL.md:213,263` excludes by
design, plus a syntactic guard on the guard shape. The second half is the expensive half: leave the array-property restrictions and
decidability leaves silently, with no signal at the surface, which is the failure mode `--strict-verified-core` exists to prevent. The
benefit is two rows, 1.6%. For the record on the general theory, so it is not re-derived: word equations alone are decidable (Makanin 1977;
PSPACE per Plandowski, JACM 2004), word equations *with linear length constraints* are a long-standing open problem (Ganesh, Minnes,
Solar-Lezama, Rinard, HVC 2012), transducers or `replaceAll` give undecidability (Lin and Barceló, POPL 2016), and practical solvers (cvc5,
Liang et al., CAV 2014; Norn, Abdulla et al., CAV 2015) are complete only on straight-line or acyclic fragments. A general string theory in
`Σ_auto` would break the completeness sentence at `LLMLL.md:947`, a stronger and different reason than the one applying to T053 and T080.

**The current boundary is recommended practice, not a shortfall.** Format parsing gets its own verified artifact in the modern literature:
EverParse (Ramananandro et al., USENIX Security 2019) and EverParse3D (Swamy et al., PLDI 2022) generate verified zero-copy parsers for
binary formats, and protocol logic is verified over the decoded type, which is exactly the decoded-ADT boundary at
`VERIFICATION_SCOPE.md:297-303`. Cite it, and the boundary reads as an architecture choice with a reference. The other four rows are
recoverable by nothing: T007 and T060 (extra modes by bilateral agreement) are open-world obligations over an unspecified set of future
strings, T059 is mail mode, T115 is deployment policy over a file system. **Disposition:** no fragment change; record the array-property
route in the roadmap as the named path *if* a future target is parsing-heavy, and relabel T053/T080's barrier as "bounded quantification over
buffer indices, outside the quantifier-free surface". The relabel is accuracy; the rows stay excluded.

### F-9 (MAJOR, the trap). Chasing clause coverage is a Goodhart failure, and the project controls all three levers.

Say this in the writeup before a reviewer says it. Three levers move the ratio and none is visible in it. **Denominator pruning:**
re-adjudicate borderline rows as non-normative under X1/X4; the four trace-level rows (T008, T057, T119, T124) and several N3 permissions are
arguable either way, and moving them changes the ratio and nothing else. **Numerator inflation:** add modeled state and write contracts over
it; F-6's 23 rejected transport rows are all reachable this way and would take the out-fraction from 46.8% to roughly 28%, under the ceiling,
with no additional assurance. **Granularity:** dual extraction already found 64 rows differing only in granularity
(`VERIFICATION_SCOPE.md:78-79`), so splitting Encoded rows and merging excluded ones moves the ratio at will. Coverage-as-target degrades
elsewhere too: Inozemtseva and Holmes (ICSE 2014) found code coverage weakly correlated with suite effectiveness once suite size is
controlled, the same structure. Goodhart's law in Strathern's formulation covers the rest.

**The line, as a gate.** A disposition change is legitimate if and only if (a) it applies a rule stated before the change and fixed
independently of the number it produces (F-6's automaton-locality criterion qualifies; "this row would help the ratio" does not); (b) every
newly Encoded or Deployment-modeled row carries a mutant from the pre-registered taxonomy that actually refutes, plus a good twin that stays
SAFE; (c) both totals are published; (d) the pre-registered text stays unedited and the change is a dated amendment. Condition (b) is the
strongest and already exists in the design (`rfc-swarm-roadmap-proposal.md:222-224`). Promote it from a Phase 4 deliverable to a **gate on
any coverage change**: no row moves into Encoded or Deployment-modeled until its refuting mutant exists and refutes. Under that gate, raising
the number requires buying assurance, which is the property a coverage metric is meant to have and does not have on its own.

One rhetorical point. The strongest evidence in this Phase 0 record is that a pre-registered trigger fired against the project's interest and
was recorded rather than quietly re-interpreted (`PRE-REGISTRATION.md:214-219`). That is worth more to a skeptical reader than any
percentage, it is spendable exactly once, and it is spent if the number moves without the ledger showing why.

### F-10 (MINOR, cross-artifact inconsistency). The 58 exclusions are binned two different ways in two published documents.

`PRE-REGISTRATION.md:238-243` bins them 32 transport / 9 timing / 6 string / 3 netascii / 3 trace / 2 mail / 3 unverifiable. The Phase 0
exclusion brief bins the same rows 29 / 9 / 6 / 4 mail / 4 trace / 3 netascii / 3 other. Both sum to 58; transport, mail, and trace-level
disagree. A reviewer who recounts finds two groupings and treats the discrepancy as evidence the census is not mechanical. Derive one
canonical grouping from the Reason column, publish it once, cite it from both.

### F-11 (MINOR, denominator diagnostics). Publish the rule-by-disposition table; the exclusion mass sits where the rubric declared itself interpretive.

| Rule | Encoded | Deployment-modeled | Vectored | Dispositioned out | Total |
|---|---:|---:|---:|---:|---:|
| N1 imperative behavior | 0 | 1 | 0 | 10 | 11 |
| N2 packet format | 11 | 16 | 0 | 13 | 40 |
| N3 lowercase must/should/may | 3 | 3 | 0 | 24 | 30 |
| N4 state-machine transition | 18 | 0 | 0 | 5 | 23 |
| N5 error/exception behavior | 8 | 1 | 5 | 6 | 20 |

N3, the rule the rubric flags as most interpretive on pre-2119 prose (`VERIFICATION_SCOPE.md:31-35`), supplies 24 of the 58 exclusions (41%).
N4 supplies 5, and 18 of its 23 rows are Encoded. The exclusion mass sits in rows whose normativity the rubric admits is a judgment, and the
transition structure is almost entirely carried. Add one sub-tally: **three rows are not verifiable by any formal method whatsoever** (T024
header encapsulation, T109 deployment file-system rights, T110 vendor procurement guidance). They consume 2.4% of a 30% budget by themselves,
which makes the ceiling's unsatisfiability concrete for a reader who will not follow the C6 argument.

### F-12 (OBSERVATION). The Deployment-modeled channel carries 21 rows and no reader currently knows what it is worth.

Sixteen point nine percent of the census sits in a channel whose evidence is "a model stands in for the clause", and 14 of the 21 are C3
format rows whose model is "the decoded ADT stands in for the wire layout". The composite "53.2% carried" leans on it. The roadmap already
requires refute cruxes for modeled rows; report them as a **separate block** in the kill matrix so a reader can judge that channel
independently. A modeled row whose only constructible mutant is refuted by the type checker is not evidence, and a separate block makes that
visible if true.

### F-13 (MAJOR, Leanstral). Lean is the wrong instrument for the 13 timing and trace-level rows; a model checker is the right one.

The nine timing/liveness rows and the four trace-level rows are not proof-search-hard, they are *modeling*-hard. A Lean proof of "the sender
retransmits until acknowledged or times out" (T086) presupposes a formal model of time, message loss, and scheduling; building that model is
the entire content, and once it exists the discharge is cheap in a finite-state or timed model checker and expensive in an interactive
prover. The obligation is also not a function-body obligation, so the target shape a sound `LeanTranslate.hs` must emit
(`pre ∧ result = ⟦body⟧ ⇒ post`, `leanstral-integration-scope.md` §2) does not even name it.

Lean's comparative advantage is elsewhere: the nonlinear-arithmetic and inductive/recursive-datatype tail that leaves `Σ_auto`
(`compiler-team-roadmap.md:150`, Lever C explicitly gated on LEAN-GA). TFTP has no such tail, by construction, since the target was selected
at `rfc-swarm-roadmap-proposal.md:286-290` precisely because nothing in `Σ_auto` needs to move. Lean therefore recovers zero rows here. That
is not a criticism of the Lean tier; it is what choosing the RFC to fit the fragment produces.

### F-14 (MAJOR, Leanstral). I still hold that the trace closure is a *later* Lean candidate, and discharging it in Lean today would be a net trust loss.

Compare trusted bases directly. The disclosure at `VERIFICATION_SCOPE.md:325-344` rests on one modeling claim (iterating `step` is the
behavior set) plus the invariance rule, which is a theorem (F-7). A Lean-discharged closure rests on the same modeling claim, **plus** the
LLMLL-to-Lean translation, **plus** the Lean kernel and whichever Mathlib development the proof invokes, **plus** a hand-authored theorem
statement, because no LLMLL function corresponds to "all traces" and so nothing generates the proposition from the artifact. The scope
document is explicit that translation faithfulness is the trust root and that layer 1 is structurally unfaithful today: the body is never
passed to `translateObligation`, `result` and the parameters are free variables, and the one end-to-end example emits a universally
quantified false claim (`leanstral-integration-scope.md` §2). Swapping a one-line disclosed schema for a three-part trust dependency, one
part known-broken, is a downgrade.

Make the comparison the writeup would otherwise avoid: IronFleet proves its Init and Next lemmas in Dafny and treats the temporal closure as
a small trusted step. It did not export that step to a foundational prover either. Doing better than IronFleet on this specific point is not
this demonstration's job, and claiming to would invite a reviewer to check. **Disposition:** keep the disclosure, and record the closure in
the roadmap as a *post-rebuild* Lean candidate so it has a named future home without becoming a dependency.

### F-15 (MAJOR, Leanstral, disclosure). A `verified-lean` row carries a different trusted base, and mixed-evidence artifacts are labeled per obligation, never by a single headline tier.

`DLVerifiedLean` is a peer of SMT `verified`, not a tier above it (`compiler-team-roadmap.md:79`). That lattice placement is correct and is
also why the distinction is easy to lose in a summary table. What differs is what must be trusted. **SMT `verified`** trusts the VC
generator, the encoding into `Σ_auto`, and liquid-fixpoint/Z3, with the decidability claim at `LLMLL.md:947` making SAFE a decidable side
condition rather than a quantifier over solver runs, plus the codegen faithfulness statement at `LLMLL.md:280`. **`verified-lean`** trusts
all the modeling above, plus the LLMLL-to-Lean translation, plus the Lean kernel and the Mathlib lemmas invoked. It does **not** trust the AI
prover: the durable artifact is the kernel-checked proof term, and `sanitizeProof` rejects `sorry`, `admit`, and empty terms before a
`ProofFound` can mint a tier (`leanstral-integration-scope.md` §5), under the LCF smart-constructor discipline at `LLMLL.md:1056` (Milner,
*Edinburgh LCF*, 1979). State that plainly, because a reader's first objection to "an AI proved it" is answered by the kernel, not the model.

The literature's convention is exactly this enumeration: seL4 publishes an assumption list and the community treats the list, not the
theorem, as the interesting artifact; CompCert names its unverified frontier; IronFleet names its trusted temporal step and its trusted-spec
size. So if any `verified-lean` row ever exists in this artifact, the trust report must carry a prover column, the writeup must carry both
assumption lists side by side, and a characteristic-core row discharged only by Lean must be flagged in §6 of the scope document. The core's
pre-registered bar is body-faithful SMT `verified` under `--strict-verified-core` (`PRE-REGISTRATION.md:66-70`); a Lean discharge is a
**different** bar, not a higher one, and substituting it silently would be a bar change disguised as an upgrade.

### F-16 (MAJOR, Leanstral, integrity). Lean lemmas inside the wave break the process claim; sequenced outside it, they are cleanly separable.

The pre-registered budget is human interventions after the contract freeze = 0, with every fill derived from brief-only input
(`PRE-REGISTRATION.md:90-95`), and the checkout brief is the sole information channel to a filling agent (`data-scope-extension.md:405`).
Swarm agents author LLMLL; no Lean channel exists in the checkout/patch/refine protocol. Three consequences. (1) A Lean lemma authored
mid-wave by a human or a second AI is a post-freeze intervention **by the pre-registration's own definition**; that the lemma is
kernel-checked is irrelevant, because the measured quantity is process, not correctness. (2) It is cleanly separable if and only if it is
sequenced after Phase 3 closes, reported in a separate appendix arm with its own authorship trail, and excluded from the swarm claim's
numerator, which is the containment already precedented by the weaker-model appendix arm (`rfc-swarm-roadmap-proposal.md:524-528`): a
different population, reported separately, off the headline. (3) A subtler laundering risk to pre-empt: if a Lean lemma discharges an
obligation a fill agent could not, the wave's retry-budget statistic silently improves. Rule to pre-register now: a hole that exhausts its
semantic retry budget is a finding routed per the Phase 3 STOP (`rfc-swarm-roadmap-proposal.md:602-604`), and a Lean discharge must never be
the resolution of an exhausted hole during the wave.

## Recommendation

Ranked. Items 1-3 are mutually exclusive dispositions of the fired STOP; 4-8 apply under any of them.

**1. Amend and disclose: keep the target, retire the ratio ceiling, adopt F-3's replacement conditions before Phase 1.** The argument is
F-1: the ceiling's value is fixed to within 2.4% by the class composition of the target document, so it never tested what it was written to
test. Retiring a metric for a demonstrated construct-validity defect, with the original preserved, the analysis published, and a stronger
replacement fixed before the next phase, is standard practice and more defensible than either alternative.

**2. Re-express the pre-registered test in its own population.** The ceiling was calibrated against 20-30 protocol-core concepts
(`rfc-swarm-roadmap-proposal.md:275-278`); grouping the 124 rows back into those units and evaluating the original test there is the most
faithful possible repair. Second only because the grouping rule is a degree of freedom exercised after seeing the data, so F-9 applies.
Acceptable as a secondary figure labeled post-hoc, not as the headline.

**3. Honor the STOP and re-target. Reject.** F-2 is the reason: the only passing targets are pure-algorithm RFCs the project has already
done twice. Pre-registration protects against moving a threshold *because you dislike the result*; it does not require honoring a threshold
shown to measure the wrong quantity, provided the demonstration is public and the original preserved.

**4. Take the two census corrections now or not at all, under the F-9 gate.** F-5 (mail-mode consistency, 2-3 rows) and F-6 (the 6-row
source-TID model amendment). Both dated, rule stated before result, refuting mutants required, both totals published. Combined effect is
roughly 58 down to 49 or 50 out, about 40%: still over the retired ceiling, which is the point. If either fails condition (b), drop it.

**5. Do not widen the fragment.** Per barrier: transport/TID involves no language work and is a model-boundary question (F-6); timing and
liveness are a category error inside a function-contract verifier and a decidability disaster in `Σ_auto`, correctly routed to a separate
model in a separate tool if ever wanted (F-7); string structure is sound and decidable for exactly two rows via the array property fragment
and not worth a quantifier surface plus a syntactic guard (F-8); netascii, mail mode, trace-level, and procurement are out under every
formalism. The standing rule at `rfc-swarm-roadmap-proposal.md:633-638` survives intact, and this census is evidence *for* it: the fragment
carried 95% of the protocol-automaton rows without moving.

**6. Keep Leanstral parked for this demonstration.** Decisive reason: it buys zero rows on this target (F-13). The 13 timing/trace rows need
a model, not a prover; the two string rows need a bounded quantifier in a decidable array fragment; the transport rows need a model-boundary
decision; and the inductive and nonlinear tail that is Lean's actual advantage does not exist in TFTP by construction of the target
selection. Against zero benefit sits a real cost: layer 1 is known structurally unfaithful, so using it on a characteristic-core row would
put a known-broken translator on the critical path (F-14). Two Lean-adjacent actions remain worth taking, both off this critical path: land
the `sanitizeProof` anti-laundering guard if it is not yet merged (recorded as built and uncommitted at `leanstral-integration-scope.md` §5),
and record the trace-induction closure as a post-rebuild Lean candidate. If Leanstral is ever activated for this artifact, F-15's disclosure
rules and F-16's sequencing rule apply without exception.

**7. Fix the two presentation defects.** One canonical grouping of the 58 (F-10); the modeled-row crux block reported separately (F-12).

**8. Correct the §9 framing.** The trace closure is the invariance rule, a theorem; the trusted part is the modeling claim that iterating
`step` is the deployed system's behavior set (F-7).

### What must appear in the writeup under any disposition

- The Encoded fraction first, per the pre-registered discipline, immediately followed by the composite (53.2% carried, 95.0% of C1+C2+C3
  carried, 100% dispositioned, zero silent drops) and by the statement that no comparable artifact publishes a clause-coverage fraction at
  all, with the F-4 comparison. Both cross-tabs (F-1 class, F-11 rule), with the three-row "not verifiable by any formal method" sub-tally.
- The full STOP record: unedited pre-registered text, the fact that it fired against the project's interest, the construct-validity analysis,
  the replacement conditions, the date. Never a silently corrected number. If any correction under item 4 is taken, both totals, the rule,
  the date, and the refuting mutants.
- The dual-extraction statistics beside the percentage (Jaccard 0.866, kappa 0.938, "almost perfect" on Landis-Koch); the disclosure that
  A4's 22% and RFC 1982's 0% are core selections rather than censuses (F-2); the decoded-ADT boundary as an architecture choice with the
  EverParse citation (F-8); the invariance-rule framing of the trusted composition schema (F-7).
- One sentence on the Lean tier even though it is unused: *no obligation in this artifact is discharged by the Lean tier; every Encoded row
  is SMT body-faithful under `--strict-verified-core`.* A reader who knows `verified-lean` exists will otherwise wonder about it.

## Open questions for the language-team

1. **State the F-6 model-amendment criterion before applying it, and confirm its extension.** Confirm in one paragraph that "a property of
   the protocol automaton whose violation is a single transition" admits T022, T023, T046, T047, T102, T121 and rejects T026, T039, T041,
   T106, T108, T112, T123, or revise it until it does. A criterion that admits the whole transport class is not a criterion.
2. **Decide whether all 21 Deployment-modeled rows can carry a non-trivial refuting mutant, and say what happens to one that cannot.**
   Fourteen are "the decoded ADT stands in for the wire layout", and a mutant against a layout the model does not represent may be
   unconstructible. If some cannot, "53.2% carried" needs a footnote, better written now than discovered in Phase 4.

## Bottom line

The threshold was defective and the target did not fail: cross-tabulating the census against the C1-C6 taxonomy, fixed before this RFC was
chosen, shows 55 of the 58 exclusions are C4 or C6 and C6 alone is 36.3% of the document, so the out-fraction is determined to within 2.4% by
the target's genre composition rather than by anything the encoder did, and no complete protocol RFC carrying a transport binding and timers
can pass a 30% ceiling under an obligation-level rubric, which means honoring the STOP literally would send the track back to the
pure-algorithm RFCs it has already done twice. Keep the target, retire the ratio, replace it with the characteristic-core condition plus a
closed barrier list plus the class-stratified report, where the number carrying the claim is that 95.0% of the 60 protocol-automaton and
packet-format rows are carried and exactly three are excluded. On widening: the fragment is not the barrier for 55 of the 58 rows; the
transport class is a model-boundary question with zero compiler work in it, of which a 6-row subset is worth taking because the source-TID
check is a real attack surface with a real refuting mutant; timing and liveness belong in a timed-automaton or model-checker artifact rather
than in `Σ_auto`; the only sound decidable extension available, bounded universal quantification over buffer indices in the array property
fragment, buys two rows for a quantifier surface plus a syntactic decidability guard and should be declined; and Leanstral stays parked,
because it recovers none of those rows, its advantage is the inductive and nonlinear tail this target was chosen not to have, and putting a
known-unfaithful translator between a characteristic-core row and its verdict would trade a one-line disclosed schema for a three-part trust
dependency. The trap is that the project controls the denominator, the model boundary, and the row granularity, so the ratio can be moved
three ways that buy no assurance; the defense is to gate every disposition change on a rule stated in advance and a mutant that actually
refutes, and to keep publishing the number that fired against the project's own interest, which is the most persuasive artifact this Phase 0
produced.
