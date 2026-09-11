# Pre-registration: RFC 826 wave (stage I)

> **Status:** written 2026-09-11, before any wave agent runs and before stage K authors a single
> contract clause. Once stage I completes, this file is frozen at the digest `MANIFEST.json`
> records for it. **The pre-registered text is never edited.** Outcomes go in Appendix A and
> amendments in Appendix B, each with a date, an argument, and a named human adjudicator.
>
> The point of writing it first is that the wave's outcome cannot then be graded on a moving
> target. A criterion that is only kept when it is flattering is not a criterion.

---

## 0. What this document is written against

### 0.1 Inputs, pinned and re-verified

Every digest below was recomputed from the file on disk while writing this document and matched
against `MANIFEST.json`. All nine match.

| Artifact | sha256 | What it fixes |
| --- | --- | --- |
| `00-source/rfc826.txt` (470 lines) | `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6` | the text, verbatim |
| `01-scope/scope.md` | `f1223f849a8c7761e8a0b981ee93eb8f86f03ed9f27ba76f5b1bd898a581cd6a` | the verification boundary |
| `02-rubric/rubric.md` | `f07609487895e46784439691ef10615b64e1a1fa100ac3a17fa01dad3fe388a7` | what counts as normative |
| `03-extraction/a/extraction.json` | `151f48143236021a5c51e28739b5fdeb21baab39f496c2399ec65296775da43b` | census A, 81 normative rows |
| `03-extraction/b/extraction.json` | `acc3c1ee824fd12ce1e0e9b8769c0126f29bc1ad70f9a77e3c900b65bc813bfb` | census B, 85 normative rows |
| `05-core/core.json` | `fd5f4de2bab475386852f743418e218cc66c8899b399bf06e8b14fbc834104e3` | the 21 characteristic-core rows |
| `06-disposition/inventory-dispositioned.json` | `2b846c4fc57617f04ca55546760ce96bc787bf2fba04d8166158d82ce31b1f6b` | the 81-row ledger |
| `07-feasibility/feasibility.json` | `7ecbdc7d8689629c437f6e2947ef40358fa97969167a87cce212c8f929e43f64` | 6 probes SAFE, 6 mutants refuted |
| `07-feasibility/probes.json` | `52de267b3065c2f62c8131a2b64779eef0a336175c570b14f47d40e832e75a75` | the probe intents |

Toolchain, from `RUN-PROVENANCE.json`, written before the run: `llmll 0.23.1`, agent model
`claude-opus-5`, driver commit `5f61836`.

### 0.2 The two facts from scope that cap every claim

Restated here because every criterion below inherits them, not as decoration.

**F1.** RFC 826 predates RFC 2119 and contains zero uppercase normative keywords. Normativity is
reconstructed, recorded as **M-NORM**, and the denominator is a judgment call made under a
written rubric rather than a keyword count.

**F2.** Line 199 offers the reception algorithm as one "similar to the following", and line 50
places the document outside the standards track. **Every claim this run makes is conditional on
the antecedent "any host implementing the algorithm of lines 203-225".** A criterion below that
appears to speak about ARP hosts in general is to be read with that antecedent supplied. The
writeup states it in full and does not drop it in the summary.

### 0.3 Instrument availability in this run, stated before the run needs it

This run is driven by the LLMLL port of the pipeline driver (`driver-ll`, commit `5f61836`), not
by the reference `scripts/rfc_to_implementation.py`. The port implements a subset of the fifteen
stages and writes a marker artifact for the rest. The subset is a literal in the port's source:
`stage_ported'` at `seqbuild/src/Lib.hs:838-840` returns true for stage indices
0, 1, 2, 3, 5, 6, 8, 9, 11, 14, 15 and false for the others. Mapped to stage letters:

| Stage | What it does | Ported in this driver |
| --- | --- | --- |
| A, B, C, D, F, G, H, I | intake, scope, rubric, dual extraction, core, disposition, probes, this file | **yes** |
| E | mechanical reconciliation of the two extractions | **no**, writes a stub |
| G2 | artifact audit | **no**, writes a stub |
| J | the gate (core invariant, closed barrier list) | **no**, writes a stub |
| K | root contract authoring | **yes** |
| L | coverage lint RFC-COV-1, then freeze | **no**, writes a stub |
| M | the swarm | **no**, writes a stub |
| N | kill matrix | **yes** |
| O | writeup | **yes** |

Two of those stubs are already on disk and confirm the mapping: `04-reconcile/SUMMARY.json` and
`06b-audit/audit.json` each contain `"driver-ll": "4a stub"` and no data.

Four consequences, fixed now so that none of them can be discovered later and reported as a
surprise or quietly absorbed:

1. **No wave agent will run under this driver.** Stage M writes a stub for
   `12-wave/wave.json` and `12-wave/roots.ast.json`. The fill criteria of section 1.1 are
   binding and will be unexercised. The report for such a run says "0 holes attempted, the swarm
   half of the claim is not demonstrated by this run". It does not say "no fill failures", and
   it does not report a fill rate over a denominator of zero.
2. **The gate does not run.** The stage-J conditions still hold as criteria; they are evaluated
   by hand and recorded (section 6). A gate that does not execute is not a gate that passed.
3. **The freeze does not run.** RFC-COV-1 is not mechanically checked in either direction, so
   stage K's surface is not frozen by a passing lint. Either the operator runs
   `scripts/rfc_coverage.py --inventory ... --roots ... --require-full-coverage` by hand and
   records the output, or the coverage measurement of section 2.5 is reported as not taken.
4. **Stage N will be handed a stub where the implemented tree should be.** Its instruction under
   this pre-registration is in section 5.7: write the full register to `mutants.json` with every
   entry marked `not-authored: no implemented tree`, and author no mutant files. The kill matrix
   is then void, not empty. A void matrix is reported as void.

### 0.4 Where the denominator comes from, which is not where the design says

Stage E is stubbed, so the two extractions were never reconciled. Stage F and stage G were both
handed `04-reconcile/data/extraction-a.json`. **The canonical inventory of this run is extractor
A's census alone: 81 rows.** Extractor B's 85 rows were produced, are pinned, and were not used.

The consequence is specific and it is a weakening: the completeness of the denominator in this
run rests on one extraction, not on the dual-extraction defence the method claims. Adjudicated
disagreements, the Jaccard figure, and the kappa figure do not exist for this run and will not be
computed after the fact to fill the gap. Any statement of the form "the census is complete" is
downgraded to "the census is one extractor's, under a rubric written before extraction".

This costs nothing in the measurement set below, because agreement between two formalizations is
not evidence and was never going to be reported (section 2.11). It costs something real in the
completeness claim, and that is where it is booked.

### 0.5 What the author of this document read, and the contamination boundary

Recorded because a pre-registration that was written with the answers in view is worth less, and
the reader is entitled to know which.

**Read:** the pinned RFC; every artifact of this run listed in 0.1; the port's source
(`seqbuild/src/Lib.hs`) for the stage table and gate predicate; the reference driver
`scripts/rfc_to_implementation.py` for the wave mechanics of section 3 and 4; the stage prompts
for K, M, N and O; the TFTP pre-registration and its Amendment 1; and from the earlier ARP run,
`RESULTS.md`, `wave.json`, `gate.json`, and `kill-matrix.json`.

**Deliberately not opened:** that run's `roots.llmll`, `implementation.ast.json`, `mutants.json`,
and its report. Those are contracts and bodies for this same protocol. Stage K and the wave must
derive them.

**The exposure that matters, named rather than glossed:** the earlier ARP run's
`kill-matrix.json` lists the names and verdicts of 20 mutant entries. Section 5 was written from
this run's inventory, this run's `probes.json`, and the RFC text, and several of its entry names
nevertheless coincide with that list. Both derive from the same protocol, so convergence is
expected; influence cannot be ruled out. A reader who needs an uncontaminated register should
regenerate section 5 from the 81-row ledger and the RFC text without that exposure, and compare.

---

## 1. Acceptance criteria

### 1.1 A successful fill

One hole, one body. The fill is accepted only when **all six** hold. The first three are the
compiler's verdict and are mechanical. The last three are process conditions, and they are part
of the bar because a body that meets the first three but arrived some other way is not evidence
about a swarm.

1. `llmll verify <tree>` reports **SAFE**: the module is not refuted with this body in place.
2. The filled function appears in the verifier's `body-faithful:` list. Not `body-fallback`.
3. The function is **not** flagged `termination_unverified`.
4. The body arrived through the protocol: written by the filling agent to `body.json` in its own
   directory, and applied by `llmll patch` under a token issued for that pointer. A body that
   reached the tree any other way, including a human transcribing or repairing it, fails this
   condition **for that hole** and the hole is named in the report.
5. No `:source`-bearing clause was edited. The frozen contract surface is compared by digest
   before and after the wave; a difference is a failure of the run, not of the hole.
6. The agent saw only its checkout brief. Its directory contains no artifact from outside the
   brief and its transcript shows no attempt to read the rest of the tree, the inventory, or any
   committed prior run.

Conditions 1 to 3 are evaluated per function, deliberately not under `--strict-verified-core`:
during a wave every unfilled sibling falls back by construction, so that flag would reject a
correct body for its siblings' sake. The strict whole-tree check runs once, at the end, when it
means what it says (section 1.2, R5).

A hole that exhausts its semantic budget is a **finding**, routed to the compiler team or back to
the inventory as a scoping error. It is not an occasion for a hint, and the contract is not
weakened to accommodate it. A hole that never got an agent call because the harness failed
(`checkout-failed`) is **not** a finding: it is a harness fault, counted separately, and reported
as such (section 2.6).

### 1.2 A successful run

Eight requirements. A run is **PASS** only if all eight hold; **PARTIAL** if R1, R2, R4 hold and
each failing requirement is named with its scope; **FAIL** on any item in the failure list below.

| | Requirement | Evidence |
| --- | --- | --- |
| R1 | All 81 rows carry exactly one disposition, no silent drops | `inventory-dispositioned.json`, digest above |
| R2 | Every exclusion cites a barrier from the closed list B1-B8 | same file; currently 52/52 cite a listed barrier |
| R3 | Zero characteristic-core rows dispositioned out | `core.json` against the ledger; **currently 3, see section 6** |
| R4 | RFC-COV-1 both directions: every Encoded row cited by at least one `:source` clause, every `:source` tag naming an Encoded row | coverage lint output, run by hand if stage L is stubbed |
| R5 | Every hole filled to the 1.1 bar; whole tree SAFE under `--strict-verified-core`; zero `body-fallback` | `wave.json` plus a cold re-verify in a fresh directory with no `.verified.json` sidecar |
| R6 | Every pre-registered mutant entry executed and recorded with its verdict, survivors included; all four mandatory members present and matching their expected verdict | `kill-matrix.json` |
| R7 | Zero human interventions after freeze, or each one recorded with the rows it touched | Appendix A |
| R8 | The writeup carries the F2 antecedent and makes no claim scope section 9 excludes | `REPORT.md` |

**FAIL, regardless of anything else.** These are failures of the experiment, not of the protocol
work, and they are the only conditions under which the run is reported as a failure:

- a fill accepted below the 1.1 bar, or a bar relaxed mid-wave;
- a `:source` clause edited after freeze, by anyone, for any reason;
- a mutant survivor removed from the matrix rather than reported and resolved;
- a number reported without the denominator this document fixes for it;
- a claim in the writeup that scope section 9 lists as undeliverable;
- an instrument reinterpreted after seeing the data without an Appendix B amendment.

Note what is not in the list. The protocol turning out to be less verifiable than hoped, holes
that cannot be filled, and mutants that survive are all results. They are reported and they do
not make the run a failure.

### 1.3 Obligations from scope that no clause row carries

Three obligations exist in `scope.md` but correspond to no row in the 81-row ledger, so nothing
in the pipeline will force them. They are acceptance criteria anyway, and they are listed here
because an obligation with no mechanical enforcement is exactly the kind that quietly lapses.

**O1. The worked example as a falsifier.** Scope section 7 commits the model to exhibiting the
trace of lines 367-410: X broadcasts a request, Y merges and replies unicast, X merges and
discards. No extracted row covers lines 367-410 (extractor A's last row ends at line 364), so no
contract clause will carry it. The run must either exhibit the trace, as a test or as a witness
function instantiating the worked example at concrete values, or record that it could not and
why. If the fragment cannot express a two-host multi-step trace, that is a finding about the
fragment and it is reported as one. Stage H did not probe this (`FINDINGS.md` section 5), so
nothing so far establishes it is possible.

**O2. M-OPTCHECK, both settings.** Scope section 7 requires every property to hold for both
settings of the optional length checks of lines 205 and 208. Stage H folded both into a single
guard and did not separate them (`FINDINGS.md` section 5). The run reports, per property, whether
it was proved for both settings or for one.

**O3. S4 gates nothing.** Scope pre-commitment 4: the link-layer frame source is an observable,
never a precondition. Mechanically checkable in the shape stage H used, by confirming `frame-src`
appears in a signature and nowhere in a body. The check is run and its result recorded. A
receiver that branches on the frame source is a bug in the model.

### 1.4 What is not an acceptance criterion

- **No exclusion-ratio ceiling.** None is registered here, in any form, for any denominator.
  Amendment 1 of the TFTP run retired one because every clause in the timing and transport class
  is excluded by the definition of the class, so such a ratio measures the genre composition of
  the document rather than the reach of the verifier. This run's numbers show the same shape: all
  11 C6 rows are excluded, and 22 of 38 C3 rows are excluded under B5 because RFC 826's address
  fields are length-driven and the model has no bytes. A ceiling would fire on arithmetic that
  was settled before any scoping judgment was made.
- **No concordance measure.** Not extraction agreement, not agreement between two
  formalizations, not "the two extractors matched N% of the time". Both can be wrong the same
  way, and shared training makes that likely. A metric that rises as contracts get weaker is
  worse than no metric.
- **Absence of failure is not a result.** "No mutant survived", "no fill failed", "the verifier
  reported nothing" are not achievements unless the instrument was capable of reporting
  otherwise, and the report must say what would have shown up.
- **Satisfiability is not success.** 22 of 22 holes filled says the contracts are satisfiable. A
  contract set that excludes nothing is satisfiable too. The eliminative evidence is the kill
  matrix, and it is the number that leads.

---

## 2. The measurement set

Every number reported by this run, its denominator, and the artifact it is computed from.
Anything not on this list is not reported as a measurement. Where a figure is already determined
by artifacts on disk, it is stated now, so that a later restatement can be checked against it.

| | Measurement | Denominator | Source | Value now |
| --- | --- | --- | --- | --- |
| 2.1 | Ledger: Encoded / Deployment-modeled / Vectored / Dispositioned out | 81 canonical rows | `inventory-dispositioned.json` | 25 / 4 / 0 / 52 |
| 2.2 | Rows carried within verifiable subject matter (C1 + C2 + C3) | 70 rows of those classes | same | 29/70 = 41.4%, **reported, never thresholded** |
| 2.3 | Rows carried under the evidence rule of 2.3a | 70 | same, plus the kill matrix | computed after stage N |
| 2.4 | Characteristic-core rows Encoded | 21 core rows | `core.json` against the ledger | 18/21, three out |
| 2.5 | RFC-COV-1: Encoded rows cited by a clause; `:source` tags naming a non-Encoded row | 25 Encoded rows; all tags | coverage lint | after stage K |
| 2.6 | Fill outcomes: `filled` / `finding` / `checkout-failed` | holes emitted by stage K | `wave.json` | not run, see 0.3 |
| 2.7 | Semantic attempts per hole: mean, max, distribution | holes attempted | `wave.json` `attempts` | not run |
| 2.8 | CAS retries per successful apply: mean, max | successful applies | see 3.2 and 3.3 | not instrumented, see 3.5 |
| 2.9 | Whole tree under `--strict-verified-core`: SAFE, and body-faithful count | functions in the tree | cold re-verify | not run |
| 2.10 | Kill matrix: killed / kill-required; good twins SAFE / good twins; survivors by name; unwritable by name | the closed register of section 5 | `kill-matrix.json` | after stage N |
| 2.11 | Detection yield: defects found and fixed, each with a witness | **no denominator, it is a count** | Appendix A | after the run |
| 2.12 | Human interventions after freeze | count, each described | Appendix A | 0 so far |
| 2.13 | Barrier histogram over exclusions; exclusions citing an unlisted barrier | 52 exclusions | ledger | B1 1, B2 9, B5 22, B7 12, B8 8; **0 unlisted** |

**2.3a. The evidence rule for Deployment-modeled rows.** A row counts as *carried* only if its
model constrains at least one transition, and the evidence for that is a mutant in the register
that the model decides. A row whose model note says the content is not represented carries no
verification evidence and is counted as excluded, whatever its disposition label says. This rule
is adopted from the correction the earlier ARP run's reading forced on the TFTP figures, where 14
format rows counted as carried under `Deployment-modeled` while their own model notes said the
content was dropped. Both figures, 2.2 and 2.3, are reported side by side. **Neither is selected
after seeing which is larger.**

This run has four Deployment-modeled rows and each is adjudicated in advance: A47 and A49
(M-OPTCHECK) are carried if a clause makes the per-host mode flag decide a guard; A41 (ar$tha
assigned nondeterministically) and A62 (HwType left uninterpreted) are permissive models that no
kill-required mutant can violate, so under this rule they count as **not carried**, and each gets
a good twin instead (section 5.4). The expected value of 2.3 is therefore 27/70 = 38.6%, and it
is written down now so that it cannot be discovered later and presented as an adjustment.

**2.11a. The detection-yield ledger format.** One row per defect, and a defect with no witness is
not reported:

| field | meaning |
| --- | --- |
| where | contract, body, inventory or disposition, harness or driver, prompt |
| observed | what was seen, quoted from the transcript or artifact that shows it |
| witness | file and line, or the verifier transcript, or the failing verdict |
| resolution | what changed, and in which artifact |
| counterfactual | what would have shipped had it not been caught |

This is the headline of the writeup, ahead of any ratio. "Found N defects, each with a witness,
each adjudicated against the source text" is a claim a reader can check. An agreement rate is
not.

**2.14. Numbers this run does not report.** Extraction agreement in any form; any percentage of
"the RFC verified"; any ratio used as a pass or fail threshold; wall-clock speedup unless the
sequential baseline was actually measured rather than estimated after the fact.

---

## 3. Process budgets

### 3.1 Semantic retries

**Three per hole.** A semantic retry is an agent re-invocation after its body failed the 1.1 bar.
The agent receives the compiler's error text and nothing else added: no hint, no example, no
pointer to a sibling, no relaxation of the contract. Three failed attempts exhausts the hole, and
exhaustion is a finding under 1.1, routed and recorded.

The budget is three because that is the reference driver's default (`--semantic-retries 3`) and
because a larger budget starts to measure how long an agent takes to stumble onto a body rather
than whether it can derive one.

### 3.2 Protocol retries, counted separately

**Five per submission** (`--protocol-retries 5`). A protocol retry is a `patch` rejected because
the tree moved under the agent's brief: the compare-and-swap on the brief's source hash fails and
the compiler answers `PatchAuthError: obligation context is stale`. The same body is re-applied
against a fresh checkout. **No agent call is involved**, which is the entire reason the budget is
separate: contention is a property of the coordination protocol, and charging it to an agent's
error budget would let the harness's design consume the measurement of the agent's competence.

Protocol retries are reported as their own number (2.8) and never folded into 2.7.

### 3.3 Two defects in the retry instrument, recorded before the run rather than after

Both were found by reading the reference driver, not by running it. Recording them now is what
stops a later reader from taking the numbers at face value, and what stops the analyst from
reinterpreting them once the data is in.

**Defect 1: a protocol exhaustion still consumes a semantic attempt.** In `_apply`, when the CAS
loop runs out of protocol retries it returns failure to the semantic loop, which sets `errors`
and continues to the next attempt, re-invoking the agent. So a hole that lost five times to
contention is charged one semantic attempt even though the body may have been correct. The
separation the budget design claims is therefore not complete in the implementation.

*The rule, fixed now:* a semantic attempt whose recorded error text contains `stale` or
`PatchAuthError` is re-counted out of the 2.7 numerator. If the error text is not recoverable,
the hole is reported as **unclassifiable** and counted against neither budget. It is not assigned
to whichever side reads better.

**Defect 2: per-attempt evidence is overwritten.** The agent runner writes `PROMPT.md`,
`agent.stdout.log`, and `agent.stderr.log` into the hole's directory under fixed names, and
`_checkout` overwrites `BRIEF.json` on every re-checkout. Attempt two overwrites attempt one. So
for any hole with more than one attempt, only the last attempt's prompt and transcript survive,
and the earlier failures exist only as the `attempts` integer in `wave.json`.

*The consequence, accepted now:* the per-attempt failure taxonomy that would explain **why** fills
fail cannot be reconstructed after the fact for multi-attempt holes. If that taxonomy is wanted,
the preflight of 3.5 must capture it before the wave runs. It is not reconstructed later from
memory or inference.

### 3.4 Human interventions after freeze

**Budget: zero.** The freeze is the point at which the contract surface is digested and the wave
begins. After it, no human edits a contract, a body, a brief, or the tree.

If an intervention happens anyway, it is recorded in Appendix A with: what was touched, the
digest before and after, why, and which rows lose their provenance chain. The affected rows are
named in the report and excluded from any statement about agent-derived work. The precedent is
the earlier ARP run, where one body was lost by the harness and recovered out of band: 21 of 22
rows had an unbroken chain and one did not, and the run said so rather than rounding to 22.

An intervention does not retroactively become acceptable because the outcome was fine.

### 3.5 Preflight: what must be instrumented before stage M runs

The numbers of 2.7, 2.8 and any wall-clock figure do not exist unless these are recorded while
the wave runs. If the preflight is not done, those measurements are reported as **not measured**.
They are never estimated after the fact.

1. Per hole, per attempt: a timestamped copy of the prompt, the transcript, and the verdict,
   under attempt-distinct names (defect 2 above).
2. Per submission: the count of CAS rejections and the text of each, so 2.8 has a source.
3. Per agent call: start and end timestamps, so a sequential baseline exists for the wall-clock
   comparison of 4.4.
4. A digest of the frozen contract surface taken immediately before the first checkout and
   immediately after the last apply (criterion 1.1.5).
5. A record of `--wave-agents`, `--semantic-retries` and `--protocol-retries` as actually passed,
   so the budgets above can be checked against what ran rather than against what was intended.

---

## 4. The numeric concurrency trigger

### 4.1 How many agents

**N = 5 concurrent agents**, or `min(5, holes)` if stage K emits fewer than five holes. The
intra-tree concurrency claim requires **N ≥ 4 in flight at once**. The earlier ARP run used 5 and
produced 22 holes, so 5 is expected to be achievable here.

If stage K emits fewer than four holes, the concurrency half of the claim is **not demonstrated**
and is reported as not demonstrated. Holes are not split, and contracts are not decomposed into
smaller functions, to manufacture a number. Reshaping the specification to reach a concurrency
threshold would be measuring the shape of the work against the instrument instead of the other
way around.

### 4.2 What counts as a conflict

A **conflict** is one `llmll patch` invocation rejected with `PatchAuthError` or with a message
containing `stale`, meaning the brief predates the current tree. Rejections for any other reason
are the fill being wrong and are semantic, not protocol.

**Conflict rate** = conflicts / successful applies, over the whole wave. Reported as a mean and a
max per hole.

### 4.3 The triggers, in numbers fixed now

| Trigger | Threshold | Consequence, fixed in advance |
| --- | --- | --- |
| T1 | **Any** conflict occurs | A finding about the coordination protocol. Expected count is zero (4.4), so one rejection means something mutated the tree outside the submission lock. Investigated and reported; does not by itself change the design. |
| T2 | Mean conflicts per successful apply **> 3.0**, or any hole reaching the protocol ceiling of 5 | The wave is re-run serialized, as parallel-per-module cascades. The intra-tree concurrency claim is dropped. The completeness and verification claims are unaffected and are not re-graded. |
| T3 | Concurrent wall clock **≥ 1.0×** the measured sequential baseline | Concurrency bought nothing. Reported as a finding. No speedup is claimed, in any form, including informally. |
| T4 | **Any** `checkout-failed` hole | A harness fault, reported as such. The hole is not counted as an agent failure and does not consume a semantic budget. The earlier ARP run lost one hole exactly this way. |

### 4.4 The pre-registered expectation, so a confirmed prediction is not sold as a discovery

The compare-and-swap is **per file**, not per hole: the first patch to land invalidates every
outstanding brief on the tree, however unrelated the holes. That alone would drive the conflict
rate toward one invalidation per concurrent apply at N = 5.

The reference driver already anticipates this and serializes submissions behind a mutex: inside
the lock it releases the stale token, takes a fresh checkout of the same pointer, and patches
immediately. Nothing else can move the tree in that window, because revert takes the same lock.

**So the prediction is: conflicts ≈ 0, and it means almost nothing.** The conflicts were removed
by serializing the patch point, not by the optimistic protocol working. Reporting "zero CAS
conflicts at N = 5" as evidence for optimistic concurrency would be reporting an artifact of the
mutex. What the run may legitimately claim is that **agents think in parallel and patches
serialize**, and the number that would support it is the fraction of wave wall clock spent
holding the submission lock, which is why 3.5 item 3 asks for the timestamps.

If conflicts are **not** near zero, T1 fires and the finding is about `_apply`'s lock discipline,
not about the agents.

---

## 5. The mutant-class taxonomy

### 5.1 What a mutant is here, and the polarity rule

A mutant is one change, to one thing, in one place, expressing one specific wrong behavior named
in advance. Each entry below carries its **expected verdict**, so that "as expected" is decidable
without judgment after the fact:

- **kill-required**: expected `refuted`. A SAFE verdict is a **survivor**, meaning the contract is
  weak or the row is mis-dispositioned. Survivors are reported and resolved, never dropped.
- **good twin**: expected `SAFE`. A refuted good twin means the contract set is over-strong, which
  is as much a defect as a weak one, and it is reported with the same weight.

One refuted mutant per clause shows that the contract excludes **one** wrong behavior. That is
eliminative evidence. It does not corroborate that the contract says what RFC 826 says, because
one side of that question is English prose and has no formal answer. Nothing in this run is to be
described as the contracts having been validated.

### 5.2 Mutation operators, per clause class

The 81 rows fall in three classes: C1 state transition (32), C3 length or format (38), C6 timing,
liveness, transport, trace-level (11). There are no C2, C4 or C5 rows.

**C1, state transition.** 24 Encoded rows, one Deployment-modeled. Operators:

| Operator | What it changes |
| --- | --- |
| guard-omission | a test of lines 203, 206, 214 or 219 dropped, so the branch runs unconditionally |
| guard-inversion | a test negated |
| branch-retarget | the merge branch's effect executed on the add branch or the reverse |
| effect-omission | a post-state update dropped: the table not written, `Merge_flag` not set |
| effect-addition | an extra post-state update: a row installed that no clause licenses (frame violation) |
| field-substitution | an emitted field filled from the wrong source field |
| tag-substitution | an enumerated tag swapped, REQUEST for REPLY |
| destination-substitution | broadcast for unicast, or the reverse |
| sequencing | a post-state effect made to depend on a value the algorithm reads later |

**C3, length or format.** One Encoded row (A36), three Deployment-modeled (A47, A49, A62), 34
excluded, 22 of them under B5 because the obligation is about byte extents and the model has no
bytes. Operators: **length-source substitution** (an emitted length taken from the packet rather
than from the host's local expectation) and **check-constant substitution** (the optional check of
line 205 or 208 compared against the wrong `Len` element).

Declared in advance: **boundary ±1 is not available in this class.** `Len` carries equality and
nothing else, there is no arithmetic and no order on any data sort (scope sections 3 and 6), so
the off-by-one operator that would be mandatory for a length class elsewhere cannot be written
here. Its absence is a property of the scope decision, not an oversight, and it is not to be read
later as a gap in the taxonomy.

**C6, timing, liveness, transport, trace-level.** All 11 rows are excluded (B2 ×9, B1 ×1, B8 ×1)
and no clause carries any of them. **No mutants.** A mutant needs a clause to violate, and there
is none. Stating this in advance is what stops a later reader counting zero C6 mutants as a miss.

**Deployment-modeled rows, as a cross-cut.** Each of the four gets at least one entry, so that no
modeled row ships with zero evidence that its model constrains anything. Two of them (A41, A62)
are permissive models that nothing can violate, so their entry is a good twin and is booked as
weaker evidence under the rule of 2.3a rather than counted as a kill.

### 5.3 The register, closed: 23 kill-required entries

Stage N authors exactly these, no more and no fewer. Every one of the 25 Encoded rows is targeted
by at least one entry, which is a property of this table a reader can check against the ledger.

| # | name | targets | the mutation | expected |
| --- | --- | --- | --- | --- |
| K1 | `merge-after-opcode` | A61, A51, A52 | the table effects are made to depend on `ar$op`, so a REQUEST is answered and not merged | refuted |
| K2 | `promiscuous-add` | A54, A56 | the add of line 216 runs without the target test of line 214 | refuted |
| K3 | `old-address-wins` | A52 | the merge branch keeps the existing hardware address instead of superseding it | refuted |
| K4 | `spoof-binding` (contract mutant) | the S4 observable clause | the post asserts the installed address is the frame's actual transmitter | refuted |
| K5 | `merge-key-substituted` | A51 | the merge is keyed on `<ar$pro, ar$tpa>` instead of `<ar$pro, ar$spa>` | refuted |
| K6 | `merge-flag-not-set` | A53 | the merge branch does not set `Merge_flag`, so the add also runs | refuted |
| K7 | `merge-flag-leaks` | A50 | `Merge_flag` is true on entry, so it is not local to one reception | refuted |
| K8 | `discard-suppressed` | A45, A46, A48 | a failing guard still mutates the table or emits a frame | refuted |
| K9 | `tha-harvest` | A52, A56 frame conjuncts | the receive step additionally installs `<ar$tpa, ar$tha>` | refuted |
| K10 | `reply-fields-not-swapped` | A58 | the reply is emitted without the swap of line 221 | refuted |
| K11 | `reply-op-request` | A59 | the reply carries `ar$op = REQUEST` | refuted |
| K12 | `reply-broadcast` | A60 | the reply is broadcast instead of unicast to `ar$sha` | refuted |
| K13 | `reply-to-reply` | A57 | the opcode guard is inverted, so a REPLY provokes a reply | refuted |
| K14 | `request-unicast` | A43 | the generated request goes to a unicast destination | refuted |
| K15 | `spa-tpa-transposed` | A39, A40 | the request's `ar$spa` is filled with the target protocol address | refuted |
| K16 | `lookup-key-partial` | A27, A28 | the generation lookup matches on protocol address alone, ignoring protocol type | refuted |
| K17 | `hit-returns-other` | A28 | the hit branch yields a hardware address not bound to the key | refuted |
| K18 | `miss-emits-nothing` | A32 | the miss branch emits no request | refuted |
| K19 | `request-op-reply` | A37 | the generated request is marked REPLY | refuted |
| K20 | `sha-foreign` | A38 | the request's `ar$sha` is not the sender's own hardware address | refuted |
| K21 | `pro-substituted-on-emit` | A34 | the request's `ar$pro` differs from the protocol type that keyed the lookup | refuted |
| K22 | `hrd-substituted-on-emit` | A33 | the request's `ar$hrd` is a hardware type other than the interface's | refuted |
| K23 | `pln-from-packet` | A36 | the emitted `ar$pln` is taken from a received packet rather than the host's local expectation | refuted |

Row-to-entry map, for the check: A27 K16, A28 K16 and K17, A32 K18, A33 K22, A34 K21, A36 K23,
A37 K19, A38 K20, A39 K15, A40 K15, A43 K14, A45 K8, A46 K8, A48 K8, A50 K7, A51 K1 and K5,
A52 K1, K3 and K9, A53 K6, A54 K2, A56 K2 and K9, A57 K13, A58 K10, A59 K11, A60 K12, A61 K1.

Under M-ONELINK `HwType` may have only one inhabited element in the model, in which case K22 has
no distinct value to substitute. That is the `unwritable` case of rule 5.7.3: it is recorded with
that reason and stays in the denominator, and it is not replaced by a different mutation.

### 5.4 Good twins, six entries, expected SAFE

| # | name | why it must survive |
| --- | --- | --- |
| G1 | `unsolicited-reply-merges` | a body that merges the sender triplet from a REPLY no request solicited. RFC 826 does exactly this: the merge at lines 210-213 precedes the opcode test at line 219. This twin is the pre-registered demonstration that **the protocol permits cache poisoning by unsolicited reply**, and a refutation here would mean the contracts forbid conforming behavior |
| G2 | `tha-arbitrary` | the generation step fills `ar$tha` with the broadcast address. Lines 184-186 leave it unspecified. Evidence for A41 |
| G3 | `optional-checks-omitted` | the M-OPTCHECK flag clear, both length checks absent. "Optionally" means both behaviors conform. Evidence for A47 and A49, and for obligation O2 |
| G4 | `multi-owner-target` | a host owning two protocol addresses under one protocol type replies for both. M-MULTIADDR makes `own_pa` a relation |
| G5 | `structural-variant` | a correct body written differently: branch order swapped, nested conditionals for a match. Guards against contracts that pin the shape rather than the behavior |
| G6 | `hw-type-agnostic` | a body that never inspects which `HwType` element it holds beyond `own_hw_type`. Evidence for A62 |

### 5.5 The mandatory members

Four entries are mandatory. If any is absent from the executed matrix, the run does not meet R6,
whatever the other verdicts say.

1. **K1 `merge-after-opcode`.** The error RFC 826 itself shouts at: line 219 carries the only
   double exclamation in the document, "(NOW look at the opcode!!)", and lines 227-234 spend a
   paragraph restating it. Merging before the opcode is read is the characteristic rule of this
   protocol, and an implementation that merges afterward has implemented a different one.
2. **K4 `spoof-binding`, the ARP spoofing result.** ARP cache poisoning by forged sender fields is
   the attested bug of this protocol, described in the public literature since Bellovin's 1989
   "Security Problems in the TCP/IP Protocol Suite" and mechanized in on-path tooling ever since.
   The contract mutant asserts the strong binding most people believe ARP provides, that the
   installed hardware address is the one that actually transmitted the frame. RFC 826's algorithm
   reads `ar$sha` out of the packet body and never compares it to the link-layer source, so the
   claim is false of any faithful implementation. **Its refutation is the intended negative
   result P-SPOOF, not a defect in anyone's work**, and the report says so in those terms.
3. **K2 `promiscuous-add`.** Caching from any observed packet rather than only when this station
   is the target. RFC 826 confines that behavior to the monitor of lines 337-339; implementations
   have done it in the core, and it is the amplification step that turns one forged broadcast
   REQUEST into a poisoned entry on every station on the cable instead of one.
4. **K3 `old-address-wins`.** Refusing to supersede. Lines 231-234 and 443-447 exist because a
   host that moves must be reachable again; with M-CLOCK not taken, the model has no aging, so a
   non-superseding entry is wrong forever.

G1 is mandatory as well, as the twin of K4: the run must show both that the strong binding is
refutable and that merging an unsolicited reply is conforming. One without the other misstates
what the protocol does.

### 5.6 Obligations with no refutation pressure, declared in advance

Named now so that their absence from the kill column is not read later as weak contracts:

- All 11 C6 rows: excluded, carried by no clause, nothing to violate.
- A41 and A62: permissive models. Anything a mutant could do is licensed, so only good twins
  apply (G2, G6), and 2.3a books them as not carried.
- The 22 C3 rows excluded under B5: their obligation is about byte extents, and the model has no
  bytes. A mutant would have to be written in a language the model does not contain.
- A2, A8, A9: the three characteristic-core rows dispositioned out (section 6). No clause carries
  them, so no mutant targets them. This is the material fact of section 6 and not a taxonomy gap.

### 5.7 Booking rules

1. **Catalogue first.** `mutants.json` is written before any solver time is spent. Two earlier
   runs of this stage were lost to an agent burning its budget on verification and never writing
   the catalogue, so the mutants existed and nothing could score them.
2. **Confirm the mutation landed.** Each mutant's body must differ from the original body, and
   the difference must be the named change. A string replacement that hit a comment or a type
   declaration produces a survivor that looks like a weak contract and is a broken instrument.
3. **Unwritable entries stay in the denominator.** If no clause in the frozen surface can be
   violated by an entry, it is recorded `unwritable` with the reason, and it remains in the
   kill-required count. Globbing for the mutant files that happen to exist is the accounting that
   makes a register look complete when it is not.
4. **Not-authored entries stay in the denominator too.** If stage N runs out of budget, or if it
   is handed a stub instead of an implemented tree as 0.3 predicts for this run, it writes the
   full register with the unwritten entries marked `not-authored`, with the reason. A kill matrix
   with no implemented tree behind it is **void**, and void is reported as void, not as zero
   survivors.
5. **Survivors are resolved, not removed.** A survivor is reported in the matrix, and the
   resolution (contract strengthened, row re-dispositioned, mutant found invalid) is recorded
   with its witness in the detection-yield ledger.
6. **The register is closed.** 23 kill-required entries and 6 good twins, fixed before stage K
   authors a clause. Entries are not added after seeing the contracts. If the contracts turn out
   to need an entry this register lacks, that gap is reported as a finding about this
   pre-registration and the entry is added by an Appendix B amendment, dated, so a reader can
   see it was not in the original set.

---

## 6. Known before the wave: the core-row condition is already met, and is not retired here

This is recorded in the pre-registration rather than discovered in the appendix, because it is
already visible in artifacts that were written and hashed before this document.

**The facts.** Stage F fixed 21 characteristic-core rows. Stage G dispositioned three of them out:

| Row | Class | Barrier | Obligation |
| --- | --- | --- | --- |
| A2 | C3 | B5 | multi-byte numeric fields are transmitted high byte first |
| A8 | C3 | B5 | `ares_op$REQUEST` is the value 1 on the wire |
| A9 | C3 | B5 | `ares_op$REPLY` is the value 2 on the wire |

Stage G labeled each of the three "STOP CONDITION" in its own reason text and declined to
re-classify them to pass the gate, noting that filing them under B7 on the ground that REQUEST and
REPLY are distinct elements of a declared sort would substitute a weaker statement for the row's
actual obligation, which is an interoperability constant.

**The condition this meets.** The characteristic-core invariant, inherited from Amendment 1 of the
TFTP pre-registration and implemented in this driver as `gate_halts`, halts when
`core_out > 0 || bad_barrier > 0`. Here `core_out = 3` and `bad_barrier = 0`. **The condition is
met and the correct reading is a halt.** Stage J is stubbed in this driver (0.3), so no mechanical
halt will occur. A gate that did not run is not a gate that passed, and R3 is failed by this run
on the arithmetic above.

**What I am not doing.** I am not retiring the condition, not re-scoring the three rows, and not
redefining the characteristic core so that the number comes out at zero. Redefining the core after
seeing which rows fail is the exact move pre-registration exists to prevent, and it would be worse
here than a ratio ceiling, because the core list is the qualitative criterion that Amendment 1
kept precisely when it retired the quantitative one.

**The argument a human may want to weigh, stated and not adopted.** Two pre-wave instruments
conflict, and neither was written with reference to the other:

- *Reading A, the core list is over-inclusive.* Stage F selected the core from the whole RFC
  without reference to stage B's boundary. A2, A8 and A9 are wire-encoding obligations that scope
  section 2 named OUT in advance, and scope pre-commitment 2 forbids recovering them. Under this
  reading the defect is in the core list, and the remedy is an amended core list that states
  which obligations it is selecting over, authorized by a human, with the original list left
  intact.
- *Reading B, the boundary is too narrow for this protocol's core.* If three of the 21 rows that
  define ARP cannot be stated inside the A-PARSE boundary, the boundary excludes part of what
  makes this protocol what it is, and the remedy is to re-scope the target rather than re-grade
  it. Scope section 2 concedes the shape of this when it calls the wire-format gap the largest
  distance between the model and any deployed implementation.

**The number that does not move under either reading.** Three of 21 characteristic-core
obligations are not carried by any contract, and the report says which three and why. No writeup
from this run may state "the protocol core is verified body-faithfully" without that
qualification, whichever reading a human adopts. The qualification is not a footnote.

**Adjudication is the project owner's, not the analyst's.** Recorded here, referred, and left
open.

---

## 7. Amendment procedure

1. An amendment is appended to Appendix B. Nothing above section 7 is edited, reworded, or
   deleted, including anything this run proves wrong.
2. An amendment states: the instrument, the defect, the argument with its evidence, the
   replacement if any, the date, and the human who authorized it. An amendment without a named
   authorizer is a proposal, not an amendment.
3. An instrument may be replaced, never silently reinterpreted. "The threshold did not really
   mean that" is a reinterpretation. "The threshold measured the wrong property, here is why, and
   here is what replaces it" is an amendment.
4. Analysis does not resume on the criterion under amendment until it is adjudicated.
5. No ratio ceiling may be introduced by amendment. That instrument was retired with an argument
   that does not depend on the target, and re-introducing it would repeat a settled error.

---

## Appendix A: outcomes

Empty at freeze. Every measurement of section 2 is recorded here after the run, including the
ones that go against the plan, and especially those.

## Appendix B: amendments

None at freeze.

## Appendix C: what the reader should check first

For anyone auditing this run rather than reading the report:

1. That this file's digest in `MANIFEST.json` matches the file, and that its modification time
   precedes every stage-K, stage-M and stage-N artifact. A pre-registration edited after the fact
   is worth nothing, and this is the cheapest way to detect it.
2. That section 2's values computed from the pinned ledger still hold: 81 rows, 25 / 4 / 0 / 52,
   29 of 70 carried, 18 of 21 core rows Encoded, 52 of 52 exclusions citing a listed barrier.
3. That section 6 is reflected in the report, in the report's own summary and not only in a
   section near the end.
