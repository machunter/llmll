# RFC 826: specification, coverage, and what this run did not do

**Run status, before any number.** This run was driven by `driver-ll` (commit `5f61836`), a port
that implements 10 of the 15 pipeline stages and writes a marker stub for the other five. Stages
E (reconciliation), G2 (audit), J (the gate), L (coverage lint and freeze), and M (the swarm) did
not execute. **No implementation was produced.** Every coverage number below describes the
specification half of the pipeline: the ledger, the dispositions, and the root contracts. The
implementation half, and the kill matrix that scores it, is absent. This was predicted in the
pre-registration (section 0.3) before the run needed it, not discovered afterward.

**The antecedent that caps every claim (F2).** RFC 826 line 199 offers its reception algorithm as
one "similar to the following", and line 50 places the document outside the standards track. Every
claim here is conditional on **"any host implementing the algorithm of lines 203-225"**. Where a
sentence below appears to speak about ARP hosts in general, that antecedent is to be supplied.

---

## 1. The numbers that lead

### 1.1 Class-stratified coverage

The ledger holds 81 normative rows, each in exactly one verifiability class. Coverage is reported
within each class, because the classes have different relationships to a body-level verifier.

| Class | Meaning | Rows | Encoded | Deployment-modeled | Dispositioned out |
| --- | --- | --- | --- | --- | --- |
| **C1** | state transition | 32 | **24** | 1 | 7 |
| **C3** | length or format | 38 | 1 | 3 | 34 |
| **C6** | timing, liveness, transport, trace-level | 11 | 0 | 0 | 11 |
| | **total** | **81** | **25** | **4** | **52** |

There are no C2 (arithmetic invariant), C4 (opaque primitive), or C5 (test vector) rows in RFC 826.

**C1, the class a body-level verifier actually reaches: 24 of 32 rows encoded (75.0%).** The
remaining eight are each dispositioned with a cited barrier:

- 1 Deployment-modeled: A41 (`ar$tha` assigned nondeterministically, which is how "not required"
  reads in a transition relation).
- 2 excluded under B7, entailed by a named sibling: A55 (entailed by A52 plus the S2 functionality
  axiom), A69 (entailed by A58 together with A38).
- 5 excluded under B8, outside any tool: A72, A73, A75, A76, A77, all monitor-role rows. Scope
  refuses the monitor as a principal (R4), so no modeled transition carries them.

**C3: 1 of 38 encoded.** 22 of the 34 exclusions are B5 (string structure): RFC 826's address
fields are length-driven, and the A-PARSE boundary hands the core a decoded record instead of a
byte stream, so "high byte first" and "the value 1 on the wire" have no bytes to be stated over.
10 more are B7 (entailed), 2 are B8.

**C6: 0 of 11 encoded**, all excluded by the definition of the class (B2 transport ×9, B1 timing
×1, B8 ×1).

### 1.2 The characteristic core

**18 of 21 characteristic-core rows are encoded, and each of the 18 is cited by a `:source` clause
in `10-roots/roots.llmll`.** Three exited.

| Row | Class | Barrier | Obligation |
| --- | --- | --- | --- |
| A2 | C3 | B5 | multi-byte numeric fields are transmitted high byte first |
| A8 | C3 | B5 | `ares_op$REQUEST` is the value 1 on the wire |
| A9 | C3 | B5 | `ares_op$REPLY` is the value 2 on the wire |

Stage G labeled each of the three "STOP CONDITION" in its own reason text and declined to
re-classify them to pass the gate. Filing them under B7, on the ground that REQUEST and REPLY are
distinct elements of a declared sort, would substitute a weaker statement for the row's actual
obligation, which is an interoperability constant.

This meets the characteristic-core halt condition (`core_out = 3`, `bad_barrier = 0`). Stage J is
stubbed in this driver, so no mechanical halt occurred, and **a gate that did not run is not a gate
that passed.** Requirement R3 is failed by this run on that arithmetic. The pre-registration
(section 6) recorded this before stage K authored a clause, declined to retire the condition or
redefine the core, and referred the adjudication to the project owner. It remains open.

### 1.3 The ratio this report does not lead with

The raw ledger ratio is 29 carried of 81 rows (35.8%), or 25 encoded of 81 (30.9%). It is stated
once, here, and not used. Its denominator counts obligations of every genre, including 11 timing
and transport rows that no body-level verifier of any language carries and 22 byte-layout rows
removed by a scope boundary fixed in advance. A ratio over that denominator measures the genre
composition of RFC 826, not the reach of the verifier. No ratio in this report is used as a pass
or fail threshold; the pre-registration registers no exclusion-ratio ceiling in any form.

For the record, the pre-registered figure 2.2 (rows carried within the verifiable subject matter,
C1 + C2 + C3) is **29/70 = 41.4%**. Figure 2.3, the same ratio under the stricter evidence rule,
**cannot be computed for this run**: that rule counts a Deployment-modeled row as carried only if
a mutant in the register decides it, and the register was never authored. Its pre-registered
expectation was 27/70 = 38.6%. A hand check finds that none of the four Deployment-modeled rows
(A41, A47, A49, A62) is cited by any clause in `roots.llmll`, which would put the figure at 25/70
= 35.7%; that is a by-hand lower bound, not the mechanical measurement.

---

## 2. The claim, stated precisely

The claim this pipeline is built to support is:

> Given an RFC, an orchestrating agent built a formal specification traceable clause by clause to
> the source text, and a swarm of blind agents produced an implementation the compiler proves
> satisfies it. Every normative clause is dispositioned: verified, modeled, tested, or excluded
> with a cited reason. The protocol core is verified body-faithfully.

**What this run supports of it:**

- *Traceable clause by clause*: yes. `roots.llmll` typechecks (`llmll check`, 13 statements, OK)
  and carries 27 `:source` tags. The set of clause IDs cited is exactly the set of 25 Encoded rows,
  with no tag naming a non-Encoded row and no Encoded row uncited.
- *Every normative clause is dispositioned*: yes. All 81 rows carry exactly one disposition, no
  silent drops, and all 52 exclusions cite a barrier from the closed list B1-B8, with zero
  citations of an unlisted barrier.
- *A swarm of blind agents produced an implementation*: **no.** Stage M did not run. Zero holes
  attempted. This half of the claim is not demonstrated by this run. There is no fill rate,
  because there is no denominator to compute one over.
- *The compiler proves it satisfies the specification*: **no.** There is no implementation to
  verify. `llmll check` typechecks the contract surface; it is not a proof of anything against a
  body.
- *The protocol core is verified body-faithfully*: **no, and not in the qualified form either.**
  Three of the 21 core obligations are carried by no contract, and the other 18 were never verified
  against an implementation. The pre-registration forbids any writeup from this run stating that
  sentence without the three-row qualification; here the sentence does not apply at all.

The specification half of the claim holds for this run. The implementation half was not exercised.

---

## 3. What is not claimed

- **Not** that RFC 826 as a whole is "verified". 52 of 81 normative rows are excluded with cited
  reasons, and no percentage of "the RFC verified" is reported.
- **Not** that the agents would have failed without verification. No agent wrote an implementation
  here, so the comparison has no data on either side. Even in a complete run it would be
  unfalsifiable on a saturated benchmark, and it is not what this pipeline measures.
- **Not** that `:source` provenance proves fidelity to the RFC. A `:source` tag is a traceability
  pointer: it says which clause an author intended a contract to carry, and it lets a reader check
  the contract against the quoted line. It is not evidence that the contract says what the line
  says. That adjudication is human, and the coverage lint checks pointer bookkeeping, not meaning.
- **Not** that trace-level or timing properties hold. All 11 C6 rows are excluded. No liveness, no
  recovery-time bound, no staleness bound (M-CLOCK not taken).
- **Not** parser correctness, and no memory-safety claim. The A-PARSE boundary assumes a decoded
  record.
- **Not** anything about multi-interface or bridged topologies (R1), or about monitors (R4).
- **Not** that verification caught agent error. Nothing in this run is framed that way, and nothing
  in it could be: the only defects found were in the specification instruments themselves, listed
  in section 5 with their witnesses.

---

## 4. Trusted steps, disclosed

Each item below is a step the pipeline relies on that is not discharged by the solver. None of them
hides inside the word "verified".

**T1. Trace induction is outside the fragment.** The LLMLL soundness statement is per-function: if
all obligations are discharged at solver-backed evidence level, codegen is faithful, and no trusted
FFI or opaque primitive is used, then the erased program preserves the declared refinement
predicates **at checked introduction and elimination sites**. Any closure from that per-step
preservation to an all-traces property ("no stale binding ever persists", "the table is consistent
in every reachable state", "every request is eventually answered") is a **trace induction**, and it
is a trusted schema, not a machine-checked fact. The toolchain says so directly: general inductive
properties are not shipped and remain `asserted` with explicit `?proof-required` holes. This run
proves no all-traces property and states none.

**T2. Cross-function composition is untested.** Every stage-H probe is a single `def`. The
assume-guarantee reasoning that would connect the reception step to the reply step was never
exercised (`FINDINGS.md` section 5). A whole-tree result would depend on it.

**T3. The frame condition is a proof device.** The fragment has no `forall k` in a contract. The
`table-frame` probe carries the frame condition with a **witness key** parameter, relying on the
argument that a parameter of a body-faithful function is universally quantified at the VC's outer
level. That argument is sound as stated, and it is an argument, made by a human, about what the
proof obligation means. The alternative shape (a relation over a before-table and an after-table)
is untested.

**T4. The A-PARSE boundary.** The model begins from a decoded record. The parser that produces it
is unverified and out of scope. Scope section 2 concedes this is the largest distance between the
model and any deployed implementation, and rows A2, A8, and A9 exit through exactly this boundary.

**T5. The canonical census rests on one extractor.** Stage E was stubbed, so the two extractions
were never reconciled. Stages F and G were both handed extractor A's census: **81 rows**. Extractor
B's 85 rows exist, are pinned, and were not used. The dual-extraction defence the method claims was
not applied. "The census is complete" is therefore downgraded to "the census is one extractor's,
under a rubric written before extraction". No Jaccard or kappa figure exists, and none will be
computed after the fact to fill the gap.

**T6. Normativity is reconstructed (M-NORM).** RFC 826 predates RFC 2119 and contains zero
uppercase normative keywords. The 81-row denominator is a judgment made under a written rubric, not
a keyword count. The rubric deliberately over-includes on ties, which systematically adds rows that
later disposition out.

**T7. The gate was evaluated by hand.** Stage J is stubbed. The R3 arithmetic in section 1.2 was
computed by reading `core.json` against the ledger, not by running `gate_halts`.

**T8. RFC-COV-1 was checked by hand.** Stage L is stubbed, so the mechanical lint did not run in
either direction, and stage K's surface is not frozen by a passing lint. The set equality reported
in section 2 was computed directly from `inventory-dispositioned.json` and the `[A…]` tags in
`roots.llmll`. It agrees in both directions, and it is a hand check.

---

## 5. Detection yield

Defects found, each with a witness, each adjudicated against the source text or the artifact that
shows it. This is a count, not a rate. No agreement or concordance figure is reported anywhere in
this run: two formalizations can be wrong the same way, shared training makes that likely, and a
metric that rises as contracts get weaker is worse than no metric.

**Four defects found. Two fixed, one referred, one reported here.**

---

**D1. A contract that no implementation could satisfy (fixed).**

- *Where*: contract, `07-feasibility/resolve-out.llmll`.
- *Observed*: the first draft carried
  `(post (=> (not (map-has tbl tpa)) (not (= result (BroadcastRequest (pair (pair own-hw tpa) tpa))))))`
  and was **refuted** by the verifier.
- *Witness*: the refutation verdict, plus the concrete case. When a station resolves its own
  protocol address, `own-pa = tpa`, and the transposed packet and the correct packet are the same
  value. No contract can separate them. RFC 826 never rules that case out.
- *Resolution*: the clause is guarded with `(not (= own-pa tpa))`, rather than constraining callers
  with a `pre` the RFC does not license. The corresponding mutant stays refuted by this clause and
  independently by `[A32]`.
- *Counterfactual*: an unsatisfiable clause shipped into the frozen surface. Every downstream agent
  would have failed that hole, and the failure would have read as an implementation defect rather
  than a specification defect.
- *Pattern carried forward*: a "field X is not field Y" clause is false wherever the two fields can
  coincide, and in this protocol they often can.

**D2. The table cannot be keyed as the scope says (fixed, by narrowing, with the narrowing booked).**

- *Where*: contract shape, stage H.
- *Observed*: scope section 4's S2 names a four-place relation `tbl(ProtoType, ProtoAddr) -> HwAddr`.
  The fragment's map key class is `{int, string}`, so the pair cannot be a key.
- *Witness*: `FINDINGS.md` section 2; the probes key on protocol address and carry the protocol type
  as a separate `proto-ok` guard.
- *Resolution*: recorded as a real narrowing that stage D must either accept or resolve by splitting
  the table per protocol type. Not papered over.
- *Counterfactual*: contracts written against a key shape the fragment cannot express, discovered
  mid-wave by agents with no authority to change the specification.

**D3. The characteristic core and the scope boundary are in direct conflict (referred, open).**

- *Where*: inventory and disposition, against scope.
- *Observed*: 3 of the 21 characteristic-core rows (A2, A8, A9) cannot be stated inside the A-PARSE
  boundary at all. The gate condition `core_out > 0` is met.
- *Witness*: the three disposition reasons in `inventory-dispositioned.json`, each self-labeled
  "STOP CONDITION"; `core.json` against the ledger.
- *Resolution*: **none adopted.** Two readings are recorded in the pre-registration and neither is
  taken: either the core list is over-inclusive (stage F selected the core without reference to
  stage B's boundary), or the boundary is too narrow for this protocol's core (if 3 of the 21 rows
  that define ARP fall outside it). Adjudication is the project owner's. The pre-registration
  declines to re-score the rows or redefine the core, which is the move pre-registration exists to
  prevent.
- *Counterfactual*: a report claiming "the protocol core is verified body-faithfully" while three
  interoperability constants, the ones that decide whether any peer recognizes a packet, are carried
  by nothing.

**D4. The kill matrix records the wrong verdict value (found here, reported, not silently fixed).**

- *Where*: harness output, `13-kill-matrix/kill-matrix.json`.
- *Observed*: all 29 entries carry `"verdict": "unwritable"`. Booking rule 5.7.4 requires
  not-authored entries to be marked `not-authored`, which is a different category from `unwritable`
  (5.7.3): `unwritable` means no clause in a frozen surface can be violated by the entry, which is
  information about the contracts; `not-authored` means nothing was attempted.
- *Witness*: the entries' own `reason` strings, all 29 of which open
  `"not-authored (NOT unwritable): no implemented tree"`, contradicting the `verdict` field beside
  them. The companion register `13-kill-matrix/mutants.json` gets it right, carrying
  `"not-authored": true` on all 29.
- *Resolution*: reported, not edited. Amending a frozen stage-N artifact after the fact is the kind
  of change Appendix B exists to record.
- *Counterfactual*: a consumer reading the `verdict` field alone would score this run as 29 entries
  legitimately unwritable against a real frozen surface, which is a statement about contract
  strength, instead of a void matrix with no tree behind it.

**Also recorded, not counted as defects:** the instrument gap itself (five stubbed stages) was
disclosed in advance rather than discovered, and one entry (`hrd-substituted-on-emit`) carries a
separate M-ONELINK unwritable question that is **undetermined, not resolved**.

---

## 6. Kill matrix: VOID

The register was closed before stage K authored a clause: **23 kill-required entries and 6 good
twins, 29 total.** Stage N ran, was handed a stub where the implemented tree should be, and wrote
the full register unauthored, as booking rule 5.7.4 requires.

| | Count |
| --- | --- |
| Kill-required entries in the closed register | 23 |
| Mutants authored | **0** |
| Killed | **0** |
| **Survivors** | **0 observed, and this means nothing** |
| Genuinely unwritable against a frozen surface | 0 |
| Not authored (no implemented tree) | 29 |
| Good twins in the register | 6 |
| Good twins returning SAFE | **0** |
| Mandatory members executed | 0 of 5 (4 kill-required: `merge-after-opcode`, `promiscuous-add`, `old-address-wins`, `spoof-binding`; 1 good twin: `unsolicited-reply-merges`) |

**The matrix is void, not zero-survivors.** Zero survivors out of zero authored mutants is not a
result. A killed mutant is eliminative evidence that the contract excludes one behavior; an unkilled
register proves nothing about contract strength in either direction. All 29 entries stay in their
denominators, by the booking rule, precisely so that the register cannot be made to look complete by
counting only the files that happen to exist.

**What the six good twins would have guarded, and did not.** Each good twin is a correct variant
expected to return SAFE, and its purpose is to catch a contract that is too strong rather than too
weak. None returned SAFE, because none was written, so **the over-strong-contract guard was not
exercised at all in this run**. That matters concretely for obligation O2 (`optional-checks-omitted`
was its only evidence) and for O1 and O3, which no clause row carries.

The stage-H probe set is the only eliminative evidence this run actually holds, and it is evidence
about the fragment's expressiveness, not about an implementation: **6 probes, 6 mutants, 12 verdicts
as required.** Every probe `SAFE (liquid-fixpoint)`, `body_faithful: true`, `display_level:
verified`; every mutant refuted with a `.fq` constraint index naming the branch; no mutant wrote a
`.verified.json` sidecar, which is correct, since a refuted function writes none. The probes are
`recv-table`, `merge-before-opcode`, `recv-reply`, `resolve-out`, `table-frame`, and `spoof-binding`.

One of those six is a **negative result about the protocol**, and it is an intended deliverable
rather than a failure: `spoof-binding` proves the weak, true binding (the table holds what the
packet *asserted* in `ar$sha`) and its twin shows the strong claim (the table holds the address that
*actually transmitted*) is refuted. The suggested algorithm does not establish that binding.

---

## 7. Run scorecard

Against the eight pre-registered requirements. A run is PASS only if all eight hold, PARTIAL if R1,
R2, and R4 hold and each failing requirement is named with its scope.

| | Requirement | Result |
| --- | --- | --- |
| R1 | All 81 rows carry exactly one disposition, no silent drops | **holds** (25 + 4 + 52 = 81) |
| R2 | Every exclusion cites a barrier from B1-B8 | **holds** (52/52; B1 1, B2 9, B5 22, B7 12, B8 8; 0 unlisted) |
| R3 | Zero characteristic-core rows dispositioned out | **fails** (3: A2, A8, A9; section 1.2) |
| R4 | RFC-COV-1 both directions | **holds under a hand check** (T8); the mechanical lint did not run |
| R5 | Every hole filled, whole tree SAFE, zero `body-fallback` | **fails, not exercised** (stage M stubbed; 0 holes attempted) |
| R6 | Every register entry executed and recorded, survivors included | **fails, not exercised** (0 of 29 authored) |
| R7 | Zero human interventions after freeze, or each recorded | **holds** (0 recorded) |
| R8 | The writeup carries the F2 antecedent and claims nothing scope section 9 excludes | **holds** (stated at the top; section 3) |

**Verdict: PARTIAL.** R1, R2, and R4 hold; R3, R5, and R6 fail and are each named above with scope.

None of the FAIL conditions occurred: no fill was accepted below the bar and no bar was relaxed
(there was no fill); no `:source` clause was edited after freeze; no survivor was removed from the
matrix; no number appears here without the denominator the pre-registration fixes for it; no claim
is made that scope section 9 lists as undeliverable; no instrument was reinterpreted after seeing
the data.

A protocol turning out to be less verifiable than hoped, holes that cannot be filled, and surviving
mutants are all results, and none of them makes a run a failure. What this run cannot report is the
part that never ran.

---

## 8. What a complete run would add

In order of what is missing most:

1. **Stage M, the swarm.** The implementation half of the claim, and with it R5, measurements 2.6
   through 2.9, and any statement about what blind agents can do against these contracts.
2. **Stage N against a real tree.** 23 kill-required mutants and 6 good twins, scored, survivors
   reported and resolved rather than removed. This is the eliminative evidence, and it is the number
   that should lead a complete run's report.
3. **An adjudication of D3.** Either an amended core list that states which obligations it selects
   over, authorized by a human with the original left intact, or a re-scoped target that brings the
   wire constants inside the boundary. Not a re-grading of the three rows.
4. **Stage E, reconciliation.** Extractor B's 85 rows exist and are pinned. Reconciling them against
   A's 81 would replace T5 with the dual-extraction defence the method claims.
5. **Stages J and L mechanically.** A gate that runs, and a freeze backed by a passing lint.
6. **O1**, the worked example of lines 367-410 exhibited as a trace or recorded as a limitation of
   the fragment, which would itself be a finding.

---

## Artifact index

| Stage | Artifact | Status |
| --- | --- | --- |
| A | `00-source/PROVENANCE.json` | complete |
| B | `01-scope/scope.md` | complete |
| C | `02-rubric/rubric.md` | complete |
| D | `03-extraction/{a,b}/extraction.json` | complete (A: 81 rows used; B: 85 rows unused) |
| E | `04-reconcile/SUMMARY.json` | **stub** |
| F | `05-core/core.json` | complete (21 core rows) |
| G | `06-disposition/inventory-dispositioned.json` | complete (81 rows) |
| G2 | `06b-audit/audit.json` | **stub** |
| H | `07-feasibility/feasibility.json`, `FINDINGS.md` | complete (6 probes, 6 mutants, 12 verdicts) |
| I | `08-prereg/PRE-REGISTRATION.md` | complete (frozen before K) |
| J | `09-gate/gate.json` | **stub** |
| K | `10-roots/roots.llmll` | complete (13 statements, 6 `def`s, 27 `:source` tags, typechecks) |
| L | `11-freeze/rfc-cov-1.txt`, `ROOTS.txt` | **stub** |
| M | `12-wave/wave.json`, `roots.ast.json` | **stub** (agent stage, 0 seconds, never ran) |
| N | `13-kill-matrix/kill-matrix.json`, `mutants.json` | complete as a register, **void** as a matrix |
| O | `14-report/REPORT.md` | this file |

`MANIFEST.json` marks every stage `"complete"`, including the five stubbed ones. That status field
records that the driver finished the step it was going to take, not that the stage did its work; the
stub artifacts and stage M's `"seconds": 0` are the discriminator.
