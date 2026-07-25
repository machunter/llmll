# RFC-SWARM: pre-registration

> **Status:** Phase 0, written before any wave agent runs. Date: 2026-07-24.
> Roadmap: [`docs/design/rfc-swarm-roadmap-proposal.md`](../../docs/design/rfc-swarm-roadmap-proposal.md) (Rev 1.1).
> Everything below is fixed **in advance**. Numbers chosen after the fact are not evidence, and
> the reason this file exists is so that the wave's outcome cannot be graded on a moving target.

The demonstration: a swarm of LLM agents implements the TFTP protocol (RFC 1350 plus the RFC
1123 §4.2.3.1 amendment) in LLMLL, coordinating only through the compiler's checkout/patch/refine
protocol, and the artifact is machine-checkable. What that claim does and does not assert is
§1 of the roadmap proposal; this file fixes the measurements.

---

## 1. Target provenance

Extraction reads verbatim RFC text only. The exact bytes used are pinned by hash so the
inventory can be re-derived:

| Source | URL | SHA-256 |
|---|---|---|
| RFC 1350 (TFTP Revision 2, July 1992), 618 lines | `https://www.rfc-editor.org/rfc/rfc1350.txt` | `39c9534e5fa6fecd3ac083ffd6256c2cc9a58f9f1058cb2e472d1782040231f9` |
| RFC 1123 (October 1989), 5782 lines | `https://www.rfc-editor.org/rfc/rfc1123.txt` | `3d019cc4777d1ead76c212711d56768bde9361312cd209846b62d2e41dd0301d` |
| RFC 1123 §4.2 excerpt (lines 2544-2760), the TFTP amendments | derived from the above | `f276196f9bb7885770014a64e316fcf84445908092999cd423b0bd5ccdf87bcf` |

## 2. Extraction procedure and the dual-extraction record

RFC 1350 predates RFC 2119, so normativity on it is interpretive. A written **normativity
rubric** (rules N1-N5 normative, X1-X5 non-normative, five tie-breaks, including "when in doubt
mark normative" so the denominator errs conservative) was authored **before** any extraction and
applied by both extractors. It is reproduced in the inventory document.

The denominator's completeness is defended by **dual extraction**: two agents extracted the
clause census independently and blind to each other from the same pinned bytes under the same
rubric. Reconciliation was mechanical (line-span overlap), then the disagreements were
adjudicated and recorded.

| Statistic | Value |
|---|---|
| Extractor A rows / Extractor B rows | 119 / 125 |
| Line-coverage Jaccard, RFC 1350 | **0.866** (238 lines both, 275 union) |
| Line-coverage Jaccard, RFC 1123 §4.2 | **0.725** (29 both, 40 union) |
| Rows matched 1:1 | 43 |
| Rows differing only in granularity (one A row spanning several B rows) | 64 |
| Genuine coverage disagreements (rows one extractor marked, the other did not cover at all) | **11** (1 A-only, 10 B-only) |
| Rule agreement (N1-N5) on 1:1 matched rows | 95.4% raw, **Cohen's kappa 0.938** |
| Canonical inventory after adjudication | **124 rows** (113 RFC 1350, 11 RFC 1123) |

Reading: the two extractions agree closely on *what the RFC requires*. The dominant difference
is **granularity** (how finely a sentence is split into rows), not coverage. Of the 11 genuine
disagreements, 6 were adopted into the canonical inventory and 5 were rejected as RFC 1123
§4.2.4 requirements-summary rows that restate prose rows already counted, which would have
double-counted the denominator. Every adjudication is recorded in the inventory document.

The roadmap estimated 20-30 normative clauses. The census found 124. That gap is itself a
finding: the estimate counted protocol-core concepts, while the rubric counts obligations
(one row per error code, per packet-format field constraint, and so on), and the conservative
tie-break inflates rather than deflates. A larger denominator can only *lower* the Encoded
fraction, so it is the safe direction for a completeness claim.

## 3. Acceptance criteria (fixed in advance)

**Completeness.** Every one of the 124 canonical rows carries exactly one disposition:
`Encoded`, `Deployment-modeled`, `Vectored`, or `Dispositioned out` with an RFC-cited reason.
No silent drops. The **Encoded fraction is reported as the first number** in any writeup.

**Verification, per clause class.** Encoded C1/C2/C3 rows are carried by contract clauses whose
functions verify `verified`, body-faithful, under `--strict-verified-core`, and are not flagged
`termination_unverified`. Deployment-modeled rows record their model. Vectored rows execute
under `llmll test`. The whole artifact is SAFE under `--strict-verified-core` including the
import-linked spine.

**Per fill.** The secure-channel bar verbatim: verify SAFE, the filled function in the
body-faithful set, not flagged `termination_unverified`.

**Descope / STOP (Phase 0).** Two conditions, the qualitative one dominating:
(a) if more than ~30% of the 124 rows disposition out, the claim is not supportable and the
target changes; (b) **no characteristic-core row may disposition out**, whatever the percentage
says. The characteristic core is fixed in advance as the clauses stating: the lock-step
transfer discipline; block-number sequencing including the initial block number; the 512-byte
short-block termination rule; the error latch; the RFC 1123 duplicate-ACK rule.

## 4. Measurement set

Falsifiable measurements, given that the benchmark is saturated and a demo premised on catching
agent error would be unfalsifiable at the frontier tier
(`experiments/minimal-agent/SUMMARY.md`).

1. **Mutation kill matrix** (§5), frozen in `EXPECTED_VERDICTS.json` under `make refute-crux-gate`,
   reported in full **including survivors**.
2. **Process integrity**: semantic retries per hole **≤ 3**; protocol (CAS) retries counted
   **separately** so concurrency cannot consume the agent's error budget; human interventions
   after the contract freeze **= 0**; every fill derived from brief-only input, with the full
   prompt/reply/verdict trail published.
3. **Swarm concurrency**: N **≥ 4** agents operating concurrently on one module tree, with
   conflict rate, CAS retries, and wall clock recorded against the numeric trigger in §6.
4. **Contract tightness via divergence**: `checkout --multi` + `diverge-report` on selected
   high-value holes. Semantically distinct fills that all verify measure the slack the contracts
   leave. Reported as a measured axis, **not** an acceptance criterion.

## 5. Mutant-class taxonomy (fixed before the wave)

One refuted mutant per clause is an existential criterion: it shows a contract excludes *one*
wrong behavior, not the wrong behaviors that matter. Therefore the classes below are fixed in
advance, and a clause's refute evidence is the taxonomy applied to it, not a mutant chosen after
seeing the contract.

| Clause class | Mandatory mutant classes |
|---|---|
| C1 state transition | transition-retarget (arm returns another state's outcome); arm-omission (a legal transition falls through to the default); guard-inversion |
| C2 arithmetic invariant | comparison-flip; off-by-one; wrap-omission |
| C3 length / format | boundary ±1 on the declared bound |
| Deployment-modeled rows | at least one mutant each, so a modeled clause cannot ship with zero evidence its model constrains anything |

**Historically attested mutants are mandatory members**, not optional extras:

- **Sorcerer's Apprentice** (RFC 1123 §4.2.3.1): the sender resends the current DATA packet on a
  duplicate ACK. Already demonstrated refuting in the Phase 0 probe (§7).
- **Short-block boundary**: terminating on `len <= 512` instead of `len < 512`.
- **Initial block number**: first DATA block numbered 0 instead of 1.

**Good twins are retained** (the A4 gate composition, 5 refutes plus 4 good twins expected SAFE):
a mutant that refutes proves the contract is not vacuous; a good twin that stays SAFE proves it
is not over-strong. Both failure modes are checked.

**Survivors are findings.** An authored mutant that verifies SAFE means the contract is weak or
the row is mis-dispositioned. It is reported in the kill matrix and resolved, never dropped.

## 6. Numeric triggers (fixed in advance)

| Trigger | Threshold | Consequence |
|---|---|---|
| Phase 0 descope, quantitative | > 30% of the 124 rows disposition out | halt, re-target |
| Phase 0 descope, qualitative | any characteristic-core row dispositions out | halt, re-target (dominates the percentage) |
| Phase 2 concurrency fallback | concurrent wall clock ≥ 1.0× the sequential baseline, **or** mean CAS retries per successful apply > 3.0 | ship the swarm as parallel-per-module cascades; the intra-tree half of the claim is sacrificed, the completeness and verified halves are not |
| Phase 3 wave halt | ≥ 3 holes exhaust their semantic retry budget | pause and adjudicate; never lower the bar mid-wave |

**Pre-registered expectation on concurrency.** The compare-and-swap token is tree-global today:
any structural commit invalidates outstanding tokens, so at N ≥ 4 the conflict rate approaches
one invalidation per apply and "optimistic checkout" degenerates toward serialize-with-recheckout.
Wall clock should still win because model inference dominates. Recording this expectation now is
the point: if it holds, it is not a surprise, and if it does not, the trigger above decides.

## 7. Phase 0 feasibility probes (executed 2026-07-24)

Two probes tested the roadmap's premise that the protocol core needs no language work. Both were
run against the shipped compiler at v0.14.65.

| Probe | Result |
|---|---|
| **Sender step**: enum states, block numbers by equality and disequality only, 512-byte termination rule, int-payload constructors, six contract clauses each with its own `:source` | **SAFE, body-faithful, `--strict-verified-core`** |
| **Sorcerer's Apprentice twin**: identical but resends the current DATA on a duplicate ACK | **REFUTED**, localized to that branch, exit 1 |
| **Ghost spine**: sender/receiver product step carrying the joint lock-step invariant, event alphabet **including duplicate delivery** of DATA and ACK | **SAFE, body-faithful, `--strict-verified-core`** |
| **Spine mutant**: sender advances on a duplicate ACK | **REFUTED** |

Consequences, recorded now so they are not re-litigated later:

1. The protocol core is expressible in the shipped fragment. Lever B is not a prerequisite.
2. The duplicate-ACK rule stated in **disequality** form (on an ACK whose block number differs
   from the block awaited, emit no DATA) is discriminative: the historically famous bug is what
   the solver catches. No ordering on block numbers is imported, and RFC 1350 defines none.
3. The spine's coupling invariant is proved over a fault model that **includes** duplicate
   delivery, so the duplicate-ACK crux is not decorative.
4. Not re-probed, because they are shipped surfaces already exercised by existing examples:
   `bytes[512]` buffers with an int length field, and the `"octet"` mode tag as a string literal.

**Contamination control.** The probe *bodies* are working implementations of functions the swarm
is meant to invent. They are deliberately **not committed**: they live outside the repository,
and no reference solution for any wave-authored function exists in the tree. What carries forward
is the probe *contracts* (the extraction role's output, which Phase 1 freezes anyway) and the
verdicts above.

## 8. What this demonstration does not claim

- Not that the agents would have failed without verification. The benchmark is saturated; that
  claim is unfalsifiable here and is not made.
- Not that `:source` provenance proves fidelity to the RFC. It is a traceability pointer;
  fidelity rests on the human audit and the refute layer.
- Not the trace-level property the duplicate-ACK fix exists to secure (absence of the
  retransmission-doubling cascade). That is quantitative and trace-level, outside the decidable
  fragment; it is its own inventory row and is carried, if at all, as a recorded informal
  derivation.
- Not that the spine's per-step invariant has been closed into an all-traces theorem. The
  closure from per-step preservation to "holds on every reachable trace" is a trace induction
  outside the fragment, disclosed as the **trusted composition schema** (the IronFleet shape:
  the lemmas are proved, the temporal closure is a small trusted step). It is never silently
  absorbed into "verified".
- Not that contract quality in the middle of the refinement tree is certified. The spawn gates
  remove the emptiest failure modes; the root contracts and the refute layer carry the ends.

---

## Appendix A: Phase 0 outcome and amendment record (2026-07-24)

Appended after execution. **The pre-registered text above is left unedited**; recording an
outcome that went against the plan is the reason the plan was written down first.

### A.1 Measured result

| Quantity | Value |
|---|---|
| Canonical normative rows | 124 |
| Encoded | 40 (**32.3%**) |
| Deployment-modeled | 21 (16.9%) |
| Vectored | 5 (4.0%) |
| Dispositioned out | 58 (**46.8%**) |
| Characteristic-core rows | 15, **all Encoded** |

### A.2 STOP conditions

- **Quantitative (§3): FIRED.** 46.8% dispositioned out against a ≤ 30% ceiling.
- **Qualitative (§3): PASSED.** Zero characteristic-core rows dispositioned out; all 15 are
  Encoded.

Per the pre-registered text, a fired quantitative STOP means "the claim is not supportable for
that RFC and the target must change". That disposition is **not** taken unilaterally here: it is
recorded and referred for adjudication, because §A.3 identifies a defect in how the threshold
was constructed, and silently re-interpreting a threshold after seeing the data is precisely
what pre-registration exists to prevent.

### A.3 Defect found in the pre-registered threshold

The 30% ceiling and the extraction rubric were calibrated against **different populations**, and
the conflict was not visible until the census existed.

- The roadmap estimated 20-30 normative clauses, counting *protocol-core concepts*.
- The rubric counts *obligations*, one row per error code, per packet-format constraint, per
  transport rule, and its tie-break 5 ("when in doubt, mark normative") deliberately
  over-includes.

The pre-registered text (§2 above) states that a larger denominator "can only *lower* the
Encoded fraction, so it is the safe direction". That reasoning is correct for the Encoded
fraction and **wrong for the quantity the STOP condition actually keys on**: the
dispositioned-out fraction. A conservative rubric systematically adds rows that then disposition
out (transport, timing, translation), so rubric and threshold push in opposite directions. This
is an error in the pre-registration, discovered by the data it was written to judge.

Audit of the 58 excluded rows shows the exclusions are subject-matter faithful, not an
over-aggressive pass. Binned by **clause class**, which is recorded data rather than a keyword
heuristic:

| Class | Excluded | Of class total |
|---|---:|---:|
| C6 timing, liveness, transport, trace-level | 45 | 45 (all) |
| C4 opaque primitive (netascii translation) | 10 | 14 |
| C3 length / format (NUL-terminated wire fields) | 2 | 26 |
| C2 arithmetic (TID range, unmodeled state) | 1 | 10 |

Subject-matter gloss of the C6 block: transport and TID mechanics, retransmission timing,
deprecated mail mode, trace-level properties, and a residue verifiable by no tool at all
(lower-layer header encapsulation, deployment file-system rights, vendor procurement guidance).

> **Correction (supersedes an earlier line in this appendix).** A first pass binned these 58 by
> keyword and reported slightly different group sizes (32/9/6/3/3/2/3). Keyword precedence, not
> the data, produced the difference: broad terms such as "port" captured rows whose actual
> barrier was mail mode or trace-level. The class-based table above is authoritative. Flagged by
> the professor review as F-10.

**The threshold was unreachable before the disposition pass ran.** C6 is 45 rows, **36.3% of the
124-row census, and every C6 row is excluded by the definition of the class**. The C1-C6 taxonomy
was fixed in `spec-from-rfc-pipeline.md` §1.2 before RFC 1350 was selected. So the ≤ 30% ceiling
was breached by *class assignment alone*, independent of any scoping judgment made later. The
ratio `dispositioned-out / total` tracks `(C4 + C6) / total` to within a few points, which means
it measures **the genre composition of the document**, not the reach of the verifier. RFC 1350 is
a complete protocol specification including its transport binding, timers, and deployment
guidance; every such RFC adds denominator in classes that can never add numerator. The only
targets that could pass a 30% out-ceiling are pure-algorithm RFCs of the kind the project has
already done (RFC 1982, RFC 6238). The threshold was testing the wrong property.

**The instrument that does work** (professor review, adopted): report the **class-stratified**
figure. Within the verifiable subject matter (C1 + C2 + C3, 60 rows): **57 carried, 95.0%**
(39 Encoded, 18 Deployment-modeled, 3 out). Retain the characteristic-core condition, and
replace the ratio ceiling with a **closed barrier list**: a STOP fires if any row is excluded for
a reason outside the pre-declared barrier classes.

### A.4 Status

Two independent consultations were run on the fired STOP and on whether new language features
could recover the excluded rows. Both are recorded:
[`docs/design/rfc-swarm-coverage-review.md`](../../docs/design/rfc-swarm-coverage-review.md)
(professor) and
[`docs/design/rfc-swarm-coverage-widening.md`](../../docs/design/rfc-swarm-coverage-widening.md)
(language-team). Their convergent findings: the threshold is defective rather than the target
failing (§A.3); **Leanstral recovers zero of the 58 rows** and stays parked; new language
features recover at most three rows and are declined.

They diverge on the transport and TID block, and the divergence is the live question: the
language-team would recover 34 rows by modeling more state, which clears the old ceiling
outright, while the professor accepts only the 6-row source-TID subset (which carries a real
injection attack and therefore a real mutant) and rejects the remaining UDP-binding rows as
scope inflation that buys a number without buying assurance. The professor's narrower position
is adopted pending user adjudication, because the wider one is structurally the metric-gaming
move this review existed to catch.

Amending a pre-registered criterion is the user's decision, not the analyst's. No Phase 1 work
proceeds until it is made.

### A.5 Amendment 1 (2026-07-24, authorized by the project owner)

The quantitative ratio ceiling of §3 is **retired** and replaced. The original text stays above,
unedited; this is the amendment record.

**Retired.** "More than ~30% of rows disposition out" as a STOP condition. Reason: every C6 row
is excluded by the definition of the class, and C6 alone was 45/124 = 36.3% of the census as
first classified, so the ceiling was breached by class assignment before any scoping judgment
was made. The C1-C6 taxonomy was fixed before RFC 1350 was selected. The ratio measures the
genre composition of the target document, not the reach of the verifier, and is unsatisfiable by
any complete protocol specification.

**In force from now on**, three conditions:

1. **Coverage of verifiable subject matter**, reported and not thresholded: rows carried within
   C1 + C2 + C3. Currently **62/65 = 95.4%**.
2. **The characteristic-core invariant**, unchanged from §3: no core row may disposition out.
   Currently 15/15 Encoded.
3. **The closed barrier list** (B1 timing/liveness, B2 transport binding, B3 trace-level,
   B4 opaque transform, B5 string structure, B6 superseded/deprecated, B7 true-by-construction,
   B8 outside any tool). **A STOP fires if any row is excluded for a reason outside this list.**
   Currently zero unclassified exclusions.

The raw ledger ratios continue to be reported (Encoded 46/124 = 37.1%, out 53/124 = 42.7%), and
the Encoded fraction is still stated first. They are reported, not graded.

**Scope changes folded in with the amendment:**

- **Source-TID validation admitted** (6 rows: T022, T023, T027, T046, T047, T048). A TID pair
  enters the modeled state. The line is drawn at *defends against something an attacker can do*
  rather than at *is expressible*: these rows carry off-path packet injection, so they admit real
  mutants (accepting a wrong-TID packet is the vulnerability; terminating the transfer on one is
  a denial of service). The remaining transport rows stay excluded under B2. This adopts the
  professor's narrow reading over the language-team's wider one, which would have admitted 34
  rows and cleared the retired ceiling outright; the wider reading is declined as the
  metric-gaming shape this review existed to catch.
- **F-5 consistency fix**: T002 ("no directory listing, no authentication") was
  `Deployment-modeled` while the identically-shaped T006/T058/T111 were excluded. Resolved
  toward the **stricter** treatment: a row true by construction admits no mutant, therefore
  carries no verification evidence, and is excluded under B7.

**No language work is authorized by this amendment.** Both consultations agree: new features
recover at most 3 rows, SMT string theory is declined (word equations with length is open), a
temporal tier is declined (category error), and **LEAN-GA stays parked, recovering zero of the
excluded rows**. The roadmap's standing rule (choose the RFC to fit the shipped fragment, do not
widen the fragment to fit the RFC) is **retained**, amended only so that "outside the modeled
state" is a re-openable disposition evaluated before the STOP check rather than a permanent
exclusion.
