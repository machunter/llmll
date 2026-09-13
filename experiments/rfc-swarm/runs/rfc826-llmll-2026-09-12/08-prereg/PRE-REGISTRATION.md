# Pre-registration: RFC 826, clause-2 re-run of 2026-09-12 (stage I)

> **Status:** written 2026-09-12, before stage J runs, before stage K authors a single contract
> clause, and before any wave agent runs. Once stage I completes, this file is frozen at the
> digest `MANIFEST.json` records for it. **The pre-registered text is never edited.** Outcomes go
> in Appendix A, amendments in Appendix B, each with a date, an argument, and a named human
> adjudicator.
>
> Writing it first is what stops the wave's outcome from being graded on a moving target. A
> criterion that is kept only when it flatters the run is not a criterion.
>
> **Read section 6 first if you read only one section.** The stage-J gate condition is already
> met by artifacts hashed before this document: ten of the twenty-six characteristic-core rows
> are dispositioned out, so the next stage halts. Every criterion below is registered in full
> anyway, because the point of this stage is to fix the bar before anyone sees a fill, and
> because a successor run that resolves the halt must inherit a bar it did not choose.

---

## 0. What this document is written against

### 0.1 Inputs, pinned and re-verified

Every digest below was recomputed from the file on disk while writing this document and matched
against `MANIFEST.json`. All match.

| Artifact | sha256 | What it fixes |
| --- | --- | --- |
| `00-source/rfc826.txt` (470 lines) | `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6` | the text, verbatim |
| `01-scope/scope.md` | `e592daca75b0a9c31fe48ea1f47dc6abb5ff8654f89cf6002b876cdaf26fcc85` | the verification boundary |
| `02-rubric/rubric.md` | `2cfca26a05290fab453fa9451e2dd4b284708423428f47962f05a84c7095fc28` | what counts as normative (rules N1 to N9) |
| `03-extraction/a/extraction.json` | `14969327c5489ca7315d468367933d69ca41f7928f0274e86b43d082a4a456d7` | census A, 90 normative rows, 56 excluded |
| `03-extraction/b/extraction.json` | `129e865829c6dc6be0fb8433b00455cd84608a69077387fd223c834cfb261b6f` | census B, 83 normative rows |
| `04-reconcile/SUMMARY.json` | `fcb02e6ee53be4d6eab1d193c5d7979b707df035d3bf26a7efd65f7b9eeaddb2` | the mechanical reconciliation, which this run does **not** report as evidence (0.4) |
| `05-core/core.json` | `a6136962f6cc6584ae035d1050864a4bc532473d18f1d80c06d3bff0571c5444` | the 26 characteristic-core rows |
| `06-disposition/inventory-dispositioned.json` | `bdb011eead00ed1b30b3137805a6bf964ee9489228eeb6d0ceb62440b2e53370` | the 90-row ledger |
| `06b-audit/audit.json` | `113166d3ad5436846b6e03e07b2036b6707112d1f32fe23a354fa2172250faab` | 90 of 90 rows cited; 7 rows whose declared strength is absent from their own quote |
| `07-feasibility/feasibility.json` | `8f7e1e86793d4bf8c58c4f5a45339cb552dce9d1d6178231e563298a2ffae9d5` | 6 probes SAFE and body-faithful, 6 mutants refuted |
| `07-feasibility/probes.json` | `0cf0984429c33c8241fd0330b7d7743b4ddcc18b2e5216acdd2ef858f4e0ed70` | the probe intents |

Toolchain, from `RUN-PROVENANCE.json`, written before the run: `llmll 0.23.4`, agent model
`claude-opus-5`, driver commit `991d293`, agent timeout 1800 s (driver default, not overridden on
the command line).

`04-reconcile/data/extraction-a.json` is byte-identical to `03-extraction/a/extraction.json`
(same digest), which is the mechanical fact behind 0.4.

### 0.2 The two facts from the source that cap every claim

Restated here because every criterion below inherits them.

**F1.** RFC 826 predates RFC 2119 and contains zero uppercase normative keywords. A count of
`MUST|SHOULD|SHALL|REQUIRED|MAY` over the pinned text returns 0. Normativity is reconstructed
under `02-rubric/rubric.md`, so the denominator of every ratio in section 2 is a judgment made
under a written rubric rather than a keyword count.

**F2.** Line 199 offers the reception algorithm as one "similar to the following", and line 50
says "This is not the specification of a Internet Standard." **Every claim this run makes is
conditional on the antecedent "any host implementing the algorithm of lines 203 to 225".** A
criterion below that appears to speak about ARP hosts in general is read with that antecedent
supplied, and the writeup states it in full rather than only in a closing caveat.

### 0.3 Instrument availability in this run, stated before the run needs it

This run is driven by the LLMLL sequencer at driver commit `991d293`. Unlike the run of
2026-09-11, **no stage writes a stub**: stages E, G2, J, L and M are implemented in this build.
Verified two ways, by reading `seqbuild/src/Lib.hs` and by reading the artifacts already on disk:
`04-reconcile/SUMMARY.json` carries real reconciliation counts and `06b-audit/audit.json` carries
a real 90-row citation audit, where the predecessor run had `"driver-ll": "4a stub"` in both.

What each of the remaining stages actually does in this build, because the criteria below depend
on it:

| Stage | Mechanism in this build | Consequence for this document |
| --- | --- | --- |
| J, the gate | reads the ledger, writes `09-gate/gate.json`, then halts the run when `core_out > 0` or `bad_barrier > 0`, citing clause `driver-spec sec 6:224-227` | it will fire (section 6). There is no flag that bypasses it: `--force` re-does completed stages and `--halt-at`/`--halt-kind` inject a halt rather than suppress one |
| K, contracts | agent stage, writes `10-roots/roots.llmll`, one `:source`-bearing clause per Encoded row | the register of section 5 is closed before this stage runs |
| L, freeze | `llmll verify --trust-report --json`, then `scripts/rfc_coverage.py --require-full-coverage` from `--reference-dir`; a nonzero exit halts the run | RFC-COV-1 is mechanically checked in both directions, so criterion R4 is enforced rather than asserted |
| M, the swarm | driven **in process** by the driver's fan machine over one wave state machine: holes in index order, one agent in flight, checkout token released before each agent call and re-taken to submit, tree reverted from `tree.bak` on a rejected fill | N = 1 (section 4). The intra-tree concurrency claim is not demonstrable by this build |
| N, kill matrix | the driver runs `llmll verify` on every catalogue entry and scores it, supporting the verdicts `refuted`, `SAFE` and `unwritable`, and naming survivors on stdout | the booking rules of 5.7 are enforced by the driver, not only by convention |
| O, writeup | checks that every survivor named in the matrix is named in the report | criterion R8 has a mechanical half |

### 0.4 Where the denominator comes from, which is not where the design says

Stage E ran for real this time and produced a reconciliation: 90 A-rows against 83 B-rows, 39
one-to-one matches, 3 A-rows unmatched, 2 B-rows unmatched, line-level Jaccard 0.8606, rule
agreement 0.9231 with Cohen's kappa 0.9014.

**None of that is reported as evidence** (see 1.4 and 2.14). It is recorded for one purpose: the
five unmatched rows name places where the two extractors saw different obligations, and those are
completeness caveats a reader can check. A69, A70 and A71 (the opcode's request/reply role, the
necessity of the sender fields, the necessity of `ar$tpa` in a request) appear in A and not in B;
B7 (the packet format must be the one given, not one of the implementation's choosing) and B71
(table aging is permitted) appear in B and not in A.

**The canonical inventory of this run is extractor A's census alone: 90 rows.** The driver hands
`04-reconcile/data/extraction-a.json` to stage F and to stage G; extractor B's 83 rows were
produced, are pinned, and were not used downstream. So the completeness of the denominator rests
on one extraction, and any sentence of the form "the census is complete" is downgraded to "the
census is one extractor's, produced under a rubric written before extraction, with five known
points of disagreement named above".

### 0.5 What the author of this document read, and the contamination boundary

Recorded because a pre-registration written with the answers in view is worth less, and the
reader is entitled to know which parts were exposed.

**Read:** the pinned RFC; every artifact of this run listed in 0.1, including stage G's per-row
reasons, which contain contract sketches for the Encoded rows; the driver source
(`seqbuild/src/Lib.hs`) for the gate predicate, the wave state machine, the budget arithmetic and
the stage-L and stage-N mechanics; the stage prompts for K, M, N and O; the reference
`PRE-REGISTRATION.md` at the experiment root (searched, not read in full); and **in full, the
predecessor run's `runs/rfc826-llmll-2026-09-11/08-prereg/PRE-REGISTRATION.md`**.

**Deliberately not opened:** the predecessor run's `10-roots/roots.llmll`, `12-wave/`,
`13-kill-matrix/` and `14-report/`; the earlier `runs/rfc826/` run's `roots.llmll`,
`implementation.ast.json`, `mutants.json`, `kill-matrix.json` and report; and this run's own
probe bodies in `07-feasibility/*.llmll`. Those are contracts and bodies for this same protocol.
Stage K and the wave must derive them.

**The exposure that matters, named rather than glossed:** reading the predecessor's section 5 in
full means the register in section 5 below was written with a prior register in view. Several
entry names coincide. Both registers derive from the same protocol and the same six feasibility
probes, so convergence is expected; influence cannot be ruled out. A reader who needs an
uncontaminated register should regenerate section 5 from the 90-row ledger, `probes.json` and the
RFC text without that exposure, and compare.

---

## 1. Acceptance criteria

### 1.1 A successful fill

One hole, one body. The fill is accepted only when **all six** hold. The first three are the
compiler's verdict and are what the driver actually tests (`fill_accepted` = applied and verifies
and body-faithful and termination proved). The last three are process conditions, and they belong
on the bar because a body that meets the first three but arrived some other way is not evidence
about a swarm.

1. `llmll verify <tree>` reports **SAFE** with this body in place.
2. The filled function appears in the verifier's `body-faithful:` list. Not `body-fallback`.
3. The function is **not** flagged `termination_unverified`.
4. The body arrived through the protocol: written by the filling agent to `body.json` in its own
   attempt directory, and applied by `llmll patch` under a token issued for that pointer. A body
   that reached the tree any other way, including a human transcribing or repairing it, fails this
   condition **for that hole**, and the hole is named in the report.
5. No `:source`-bearing clause was edited. The frozen contract surface is digested immediately
   before the first checkout and immediately after the last apply; a difference is a failure of the
   run, not of the hole.
6. The agent saw only what the driver provisions: the rendered `PROMPT.md` brief, `scratch.llmll`
   (the pristine module with every hole still unfilled), `LLMLL.md`, and
   `llmll-ast.schema.json`. Its directory contains no other artifact and its transcript shows no
   attempt to read the patched tree, the inventory, or any committed prior run.

Conditions 1 to 3 are evaluated per function and deliberately **not** under
`--strict-verified-core`: during a wave every unfilled sibling falls back by construction, so that
flag would reject a correct body for its siblings' sake. The strict whole-tree check runs once, at
the end, where it means what it says (R5).

A hole that exhausts its **semantic** budget is a **finding**: routed to the compiler team or back
to the inventory as a scoping error. It is not an occasion for a hint, and the contract is not
weakened to accommodate it. A hole that exhausts its **protocol** budget is booked
`protocol-failure`, is not a finding against the agent, and is counted separately (3.2). The
driver already separates the two, and section 3.3 records where the separation is incomplete.

### 1.2 A successful run

Eight requirements. **PASS** only if all eight hold; **PARTIAL** if R1, R2 and R4 hold and each
failing requirement is named with its scope; **FAIL** on any item in the failure list.

| | Requirement | Evidence | Value now |
| --- | --- | --- | --- |
| R1 | All 90 rows carry exactly one disposition from the closed four, no silent drops | `inventory-dispositioned.json` | holds: 23 Encoded, 5 Deployment-modeled, 0 Vectored, 62 Dispositioned out |
| R2 | Every exclusion cites a barrier from the closed list B1 to B8 | same file | holds: 62 of 62 |
| R3 | Zero characteristic-core rows dispositioned out | `core.json` against the ledger | **failed now: 10 of 26, see section 6** |
| R4 | RFC-COV-1 in both directions: every Encoded row cited by at least one `:source` clause, every `:source` tag naming an Encoded row | stage L exit status and `11-freeze/rfc-cov-1.txt` | not reached |
| R5 | Every hole filled to the 1.1 bar; whole tree SAFE under `--strict-verified-core` on a cold re-verify in a fresh directory with no `.verified.json` sidecar; zero `body-fallback` | `12-wave/wave.json` plus the cold re-verify transcript | not reached |
| R6 | Every register entry of section 5 executed and recorded with its verdict, survivors included; every mandatory member present and matching its expected verdict | `13-kill-matrix/kill-matrix.json` | not reached |
| R7 | Zero human interventions after freeze, or each one recorded with the rows it touches | Appendix A | 0 so far |
| R8 | The writeup carries the F2 antecedent, names every survivor, and makes no claim `scope.md` section 8 excludes | `REPORT.md` | not reached |

**FAIL, regardless of anything else.** These are failures of the experiment rather than results
about the protocol, and they are the only conditions under which the run is reported as a failure:

- a fill accepted below the 1.1 bar, or a bar relaxed mid-wave;
- a `:source` clause edited after freeze, by anyone, for any reason;
- a mutant survivor removed from the matrix rather than reported and resolved;
- a number reported without the denominator this document fixes for it;
- a claim in the writeup that `scope.md` lists as undeliverable (G-1 through G-5);
- an instrument reinterpreted after seeing the data without an Appendix B amendment.

What is **not** in that list: the protocol turning out to be less verifiable than hoped, holes
that cannot be filled, mutants that survive, and the stage-J halt of section 6. Those are results.
They are reported, and they do not make the run a failure.

### 1.3 Obligations from scope that no clause row carries

Four obligations exist in `scope.md` but correspond to no row in the 90-row ledger, so nothing in
the pipeline forces them. They are acceptance criteria anyway, listed here because an obligation
with no mechanical enforcement is the kind that quietly lapses.

**O1. The worked example as a falsifier.** `scope.md` section 7 commits the model to reproducing
the trace of lines 367 to 410: X broadcasts a request, Y merges and replies unicast, X merges and
the reply is consumed. Extraction stopped at line 364, so no row and no contract clause covers it.
The run must either exhibit the trace (as a test, or as a witness function instantiating the
example at concrete values) or record that it could not, and why. If the fragment cannot express a
two-host multi-step trace, that is a finding about the fragment and it is reported as one.

**O2. Both settings of the optional length checks.** `scope.md` section 4 item 4 requires every
obligation to be discharged for both settings of `checkHln` and `checkPln`. Stage H folded both
into a single `gated` boolean and did not separate them. The run reports, per property, whether it
was proved for both settings or for one. Good twins G4 and G5 exist to give this teeth.

**O3. No frame-header observable anywhere.** `scope.md` section 5 item 2 excludes the Ethernet
frame header entirely, and gap G-1 records the consequence. The mechanical check is that no
signature and no body in `roots.llmll` mentions a frame source, destination or type field. It is
run and its result recorded. A receiver that branches on the frame source is a bug in the model,
not a strengthening of it.

**O4. k-induction was never exercised.** `scope.md` section 1 anticipates k-induction for
invariant-shaped clauses. Stage H's `FINDINGS.md` section 4 records that `supersede-two` composes
exactly two steps and is a bounded trace, not an induction, so whether the architecture can state
a genuine inductive table invariant is still open. If stage K authors an invariant-shaped clause,
the trace-induction step is disclosed as a trusted schema in the report and is not allowed to hide
inside the word "verified".

### 1.4 What is not an acceptance criterion

- **No exclusion-ratio ceiling. None is registered here, in any form, for any denominator.** The
  TFTP run's Amendment 1 retired one because every clause in the timing and transport class is
  excluded by the definition of that class, so the ratio measured the genre composition of the
  document rather than the reach of the verifier. This run has the same shape and would breach any
  such ceiling by class assignment alone: all 24 C6 rows and all 8 C4 rows are excluded before any
  scoping judgment is made, and 15 of the 26 C3 rows are excluded under B5 because RFC 826's
  address fields are length-driven and the model has no bytes. Re-introducing a ratio ceiling would
  repeat a settled error, and rule 7.5 forbids introducing one by amendment.
- **No concordance measure.** Not extraction agreement, not agreement between two formalizations,
  not the kappa of 0.4. Both formalizations can be wrong the same way, and shared training makes
  that likely. A metric that rises as contracts get weaker is worse than no metric.
- **Absence of failure is not a result.** "No mutant survived", "no fill failed", "the verifier
  reported nothing" are not achievements unless the instrument could have reported otherwise, and
  the report must say what would have shown up.
- **Satisfiability is not success.** "Every hole filled" says the contracts are satisfiable, and a
  contract set that excludes nothing is satisfiable too. The eliminative evidence is the kill
  matrix, and that is the number that leads.

---

## 2. The measurement set

Every number this run reports, its denominator, and the artifact it is computed from. Anything not
on this list is not reported as a measurement. Where a figure is already determined by artifacts on
disk, it is stated now, so a later restatement can be checked against it.

| | Measurement | Denominator | Source | Value now |
| --- | --- | --- | --- | --- |
| 2.1 | Ledger: Encoded / Deployment-modeled / Vectored / Dispositioned out | 90 canonical rows | `inventory-dispositioned.json` | 23 / 5 / 0 / 62 |
| 2.2 | Rows carried within verifiable subject matter (C1 + C2 + C3) | 58 rows of those classes | same | 28 of 58 = 48.3%, **reported, never thresholded** |
| 2.3 | Rows carried under the evidence rule of 2.3a | 58 | same, plus the kill matrix | expected 25 of 58 = 43.1%, see 2.3a |
| 2.4 | Characteristic-core rows Encoded | 26 core rows | `core.json` against the ledger | **16 of 26, ten out** |
| 2.5 | RFC-COV-1: Encoded rows cited by a clause, and `:source` tags naming a non-Encoded row | 23 Encoded rows; all tags | stage L | after stage K |
| 2.6 | Fill outcomes: `filled` / `finding` / `protocol-failure` | holes emitted by stage K, count unknown at freeze | `12-wave/wave.json` | not reached |
| 2.7 | Semantic attempts per hole: mean, max, distribution, corrected per 3.3 | holes attempted | `wave.json` `attempts` plus the wave stdout | not reached |
| 2.8 | Contention rejections per successful apply: mean, max | successful applies | wave stdout reject lines naming `contention` | not reached |
| 2.9 | Cold re-verify: whole tree SAFE under `--strict-verified-core`, and body-faithful count | functions in the tree | re-verify transcript | not reached |
| 2.10 | Kill matrix: killed / 27 kill-required; good twins SAFE / 7; survivors by name; `unwritable` by name; `not-authored` by name | the closed register of section 5 | `kill-matrix.json` | not reached |
| 2.11 | Detection yield: defects found and fixed, each with a witness | **no denominator, it is a count** | Appendix A | after the run |
| 2.12 | Human interventions after freeze | a count, each described | Appendix A | 0 |
| 2.13 | Barrier histogram over exclusions, and exclusions citing an unlisted barrier | 62 exclusions | ledger | B1 10, B2 7, B3 2, B4 8, B5 16, B6 1, B7 10, B8 8; **0 unlisted** |
| 2.14 | Stage-J counts as the gate computes them | the ledger | `09-gate/gate.json` | rows 90, encoded 23, core 26, core-out 10, carried 28 of 58, excluded 62, bad-barrier 0 |
| 2.15 | Class distribution of the census | 90 rows | ledger | C1 31, C2 1, C3 26, C4 8, C5 0, C6 24 |
| 2.16 | Citation audit: rows whose declared strength is absent from their own quote | 90 rows | `06b-audit/audit.json` | 7 (A3, A27, A38, A70, A71, A79, A90), **reported and not thresholded** |

**2.3a. The evidence rule for Deployment-modeled rows.** A row counts as *carried* only if its
model constrains at least one transition, and the evidence for that is a register entry the model
decides. A row whose model is permissive, so that nothing a mutant could do would violate it,
carries no verification evidence and is counted as excluded whatever its disposition label says.
This run's five Deployment-modeled rows are adjudicated in advance:

- **A43 and A45** (the optional checks of lines 205 and 208): carried if a clause makes the free
  per-host flag decide a guard. Evidence is good twins G4 and G5, which must both stay SAFE.
- **A37 and A38** (`ar$tha` unconstrained in a generated request, and permitted to be the
  broadcast address) and **A60** (`ar$pro` may hold non-Ethernet values on other hardware): these
  are permissive models that no kill-required entry can violate, so under this rule they count as
  **not carried**, and each gets a good twin instead (G3, G6).

Expected value of 2.3 is therefore 25 of 58 = 43.1%. It is written down now so that it cannot be
discovered later and presented as an adjustment. **2.2 and 2.3 are reported side by side, and
neither is selected after seeing which is larger.**

**2.11a. The detection-yield ledger format.** One row per defect; a defect with no witness is not
reported.

| field | meaning |
| --- | --- |
| where | contract, body, inventory or disposition, harness or driver, prompt |
| observed | what was seen, quoted from the transcript or artifact that shows it |
| witness | file and line, or the verifier transcript, or the failing verdict |
| resolution | what changed, and in which artifact |
| counterfactual | what would have shipped had it not been caught |

This is the headline of the writeup, ahead of any ratio. "Found N defects, each with a witness,
each adjudicated against the source text" is a claim a reader can check. An agreement rate is not.

**2.17. Numbers this run does not report.** Extraction agreement in any form, including the kappa
of 0.4; any percentage described as "the RFC verified"; any ratio used as a pass or fail
threshold; wall-clock speedup, since with N = 1 there is no concurrent measurement to compare
against a sequential baseline (section 4).

---

## 3. Process budgets

### 3.1 Semantic retries

**Three per hole.** That is `--error-budget`, whose default in this build is 3, and the launch
command passes no override. A semantic retry is an agent re-invocation after its body failed the
1.1 bar. The agent receives the compiler's error text and nothing else added: no hint, no example,
no pointer to a sibling, no relaxation of the contract. Three failed attempts exhausts the hole,
and exhaustion is a finding under 1.1.

Three is the budget because a larger one starts to measure how long an agent takes to stumble onto
a body rather than whether it can derive one.

### 3.2 Protocol retries, counted separately

**Three per hole**, `--protocol-budget`, default 3 in this build and not overridden. A protocol
retry is spent when `llmll patch` is rejected because the tree moved under the agent's brief. The
driver's test is exact and worth quoting, because 2.8 is defined by it: the patch output contains
both `PatchAuthError` and `stale`. Any other rejection is semantic and is charged to the error
budget.

The separation is implemented, not merely intended: on a contention rejection the driver leaves
the error budget untouched (`next_error_budget err contention = if contention then err else err -
1`) and decrements the protocol budget. A hole that dies with error budget remaining is booked
`protocol-failure`; a hole that dies with the error budget at zero is booked `finding`
(`is_finding err_remaining _ = err_remaining == 0`). Contention therefore cannot consume an
agent's error budget, and cannot be reported as an agent failure.

### 3.3 What the retry instrument does and does not record in this build

Recorded before the run rather than after, from reading the driver.

**Two defects of the predecessor's instrument are fixed here, and the fix is verified.**

1. Attempt evidence is no longer overwritten. Every attempt gets its own directory
   `h<k>-a<n>` holding that attempt's `PROMPT.md`, `brief.json`, `body.json`, `agent.out`,
   `agent.err`, `patch.out` and `verify.out`. The per-attempt failure taxonomy of 2.7 is therefore
   reconstructable after the fact, which it was not in the predecessor run.
2. Protocol exhaustion no longer consumes a semantic attempt in the accounting: it produces
   `protocol-failure`, not `finding` (3.2).

**One property of the instrument that is not a fix, and that the numbers must be read against.** A
contention rejection does not re-apply the same body. The driver reverts the tree from `tree.bak`,
releases the token, and begins a **fresh attempt**, which re-invokes the agent and may produce a
different body. So a contention loss costs an agent call and a wall-clock unit even though it
costs no error budget, and `wave.json`'s `attempts` field counts contention attempts alongside
semantic ones.

*The rule, fixed now:* 2.7 is computed by subtracting attempts whose recorded rejection reason is
`contention` from each hole's `attempts`, using the wave stdout reject lines, which print the
reason and both remaining budgets. If the wave's stdout was not captured, 2.7 and 2.8 are reported
as **not measured**. They are never estimated after the fact, and an attempt whose reason is not
recoverable is reported as **unclassifiable** and counted against neither budget rather than
assigned to whichever side reads better.

### 3.4 Human interventions after freeze

**Budget: zero.** The freeze is stage L, where the contract surface is digested and the wave
begins. After it, no human edits a contract, a body, a brief, or the tree.

If an intervention happens anyway it is recorded in Appendix A with: what was touched, the digest
before and after, why, and which rows lose their provenance chain. Those rows are named in the
report and excluded from any statement about agent-derived work. An intervention does not
retroactively become acceptable because the outcome was fine.

**Adjudicating the stage-J halt is not an intervention on artifacts, and it is not covered by this
budget.** It is a decision, recorded in Appendix B under rule 7. What it may not do is edit a
pinned artifact in place. Section 6 states what a continuation means.

### 3.5 Preflight: what must be instrumented before stage M runs

The numbers of 2.6 through 2.9 do not exist unless these are recorded while the wave runs.

1. The wave's stdout, captured to a file, so the reject lines behind 2.7 and 2.8 survive.
2. Per agent call, start and end timestamps.
3. A digest of `10-roots/roots.llmll` and of `12-wave/roots.ast.json` immediately before the first
   checkout and immediately after the last apply (criterion 1.1.5).
4. The values of `--error-budget`, `--protocol-budget` and `--timeout` as actually passed, so the
   budgets above can be checked against what ran rather than against what was intended.
5. The hole list emitted by `llmll holes`, so the denominator of 2.6 is fixed before any fill lands
   rather than inferred from the fills that succeeded.

---

## 4. The numeric concurrency trigger

### 4.1 How many agents

**N = 1.** This is a property of the build, not a choice made here: the driver has no
`--wave-agents` flag, and stage M is driven in process by a single wave state machine that walks
holes in index order, one attempt at a time. Concurrency is available only if an operator launches
additional `sequencer wave` processes against the same tree by hand.

**The consequence, fixed now: the intra-tree concurrency half of the claim is not demonstrated by
this run, and the report says so in those words.** Holes are not split and contracts are not
decomposed into smaller functions to manufacture a number: reshaping the specification to reach a
concurrency threshold would measure the shape of the work against the instrument instead of the
other way around.

### 4.2 What counts as a conflict

A **conflict** is one `llmll patch` invocation whose output contains both `PatchAuthError` and
`stale`, meaning the brief predates the current tree. Rejections for any other reason are the fill
being wrong and are semantic, not protocol. **Conflict rate** = conflicts divided by successful
applies over the whole wave, reported as a mean and a max per hole.

### 4.3 The triggers, in numbers fixed now

| Trigger | Threshold | Consequence, fixed in advance |
| --- | --- | --- |
| T1 | **Any** conflict at N = 1 | A finding about the coordination protocol. With one worker nothing else should be able to move the tree, so one rejection means either an external mutation or a token-lifetime bug. Investigated and reported. |
| T2 | If and only if a human authorizes N >= 4 by launching extra wave processes: mean conflicts per successful apply **> 3.0**, or any hole reaching the protocol ceiling of 3 | The wave is re-run serialized, as parallel-per-module cascades. The intra-tree concurrency claim is dropped. The completeness and verification claims are unaffected and are not re-graded. |
| T3 | Concurrent wall clock **>= 1.0x** a measured sequential baseline | Concurrency bought nothing. Reported as a finding. No speedup is claimed in any form, including informally. Not applicable at N = 1, where no such comparison exists. |
| T4 | **Any** hole ending `protocol-failure` | A harness fault. Reported as such, not counted as an agent failure, and it does not consume a semantic budget (3.2). |
| T5 | Driver exit code 4, "a token was held while an agent was working" | The wave stops rather than submit against a held token. The run is reported as stopped at that point, with the hole named. |

### 4.4 The pre-registered expectation, so a confirmed prediction is not sold as a discovery

At N = 1 the expected conflict count is **exactly zero**, and a zero would mean nothing about
optimistic concurrency. There is one worker, the driver releases the token before the agent works
and re-takes it to submit, and nothing else touches the tree in that window. Reporting "zero CAS
conflicts" from this run as evidence that the compare-and-swap protocol works under contention
would be reporting an artifact of having one worker.

What this run may legitimately report about the protocol is narrower and is stated in advance: the
token discipline held (no exit code 4), the revert-on-failure path restored the tree, and the
per-file compare-and-swap was exercised once per attempt. Whether it survives four agents is a
question this build cannot ask.

---

## 5. The mutant-class taxonomy

### 5.1 What a mutant is here, and the polarity rule

A mutant is one change, to one thing, in one place, expressing one specific wrong behavior named
in advance. Each entry carries its **expected verdict**, so "as expected" is decidable without
judgment after the fact:

- **kill-required**: expected `refuted`. A SAFE verdict is a **survivor**, meaning the contract is
  weak or the row is mis-dispositioned. Survivors are reported and resolved, never dropped.
- **good twin**: expected `SAFE`. A refuted good twin means the contract set is over-strong, which
  is as much a defect as a weak one and is reported with the same weight.

One refuted mutant per clause shows that the contract excludes **one** wrong behavior. That is
eliminative evidence. It does not corroborate that the contract says what RFC 826 says, because one
side of that question is English prose and has no formal answer. Nothing in this run is to be
described as the contracts having been validated.

### 5.2 Mutation operators, per clause class

The 90 rows fall into five classes: C1 state transition (31), C2 arithmetic invariant (1), C3
length or format (26), C4 opaque primitive (8), C6 timing, liveness, transport, trace-level (24).
There are no C5 rows.

**C1, state transition. 21 Encoded rows, 2 Deployment-modeled, 8 excluded (B7 x7, B8 x1).**

| Operator | What it changes |
| --- | --- |
| guard-omission | a test of lines 203, 206, 214 or 219 dropped, so the branch runs unconditionally |
| guard-inversion | a test negated, so the opposite packets are acted on |
| guard-addition | an effect conditioned on something no clause conditions it on, which is the merge-after-opcode operator |
| effect-omission | a post-state update dropped: the table not written, no emission where one is required |
| effect-addition | a post-state update no clause licenses: a second key installed, a frame condition violated |
| key-substitution | a `store` or `select` keyed on the wrong pair |
| value-substitution | the right key written with the wrong value |
| field-substitution | an emitted field filled from the wrong source |
| tag-substitution | an opcode enumeration value swapped |
| destination-substitution | broadcast for unicast, or the reverse |

**C3, length or format. 2 Encoded rows (A31, A32), 3 Deployment-modeled (A43, A45, A60), 21
excluded (B5 x15, B6 x1, B7 x3, B8 x2).** Operators: **length-source substitution** (an emitted
length taken from somewhere other than the host's local expectation for the type) and
**check-constant substitution** (an optional check compared against the wrong `Len` element).

Declared in advance: **boundary plus-or-minus one is not available in this class.** `Len` carries
equality and nothing else; there is no arithmetic and no order on any data sort
(`scope.md` sections 1 and 3), so the off-by-one operator that would be mandatory for a length
class elsewhere cannot be written here. Its absence is a property of the scope decision, not an
oversight, and it is not to be read later as a gap in the taxonomy.

**C2, arithmetic invariant. One row (A3), excluded under B5.** It relates a 48-bit physical
address width to a six-byte length, which is arithmetic over widths. No clause carries it, so no
mutant targets it.

**C4, opaque primitive. Eight rows, all excluded under B4**, the encode and decode transform. No
clause carries any of them. **No mutants.**

**C6, timing, liveness, transport, trace-level. Twenty-four rows, all excluded (B1 x10, B2 x7,
B3 x2, B8 x5).** No clause carries any of them. **No mutants.** A mutant needs a clause to
violate. Stating this in advance is what stops a later reader from counting zero C4 and C6 mutants
as a miss.

### 5.3 The register, closed: 27 kill-required entries

Stage N authors exactly these, no more and no fewer. Every one of the 23 Encoded rows is targeted
by at least one entry, which is a property of this table a reader can check against the ledger.
Each mutation is stated against the contract shape stage G recorded for the row, so an entry that
turns out to be unwritable is unwritable for a reason that can be named (rule 5.7.3).

| # | name | targets | the mutation | expected |
| --- | --- | --- | --- | --- |
| K1 | `merge-after-opcode` | A52, A47, A50 | the table effects are conditioned on `p.op`, so a packet with `op = OTHER` is discarded without touching the table | refuted |
| K2 | `promiscuous-add` | A49, A50 | the add runs without the target test `p.tpa = myPa(p.pro)` | refuted |
| K3 | `old-address-wins` | A47 | the merge branch keeps the stored hardware address instead of superseding it | refuted |
| K4 | `merge-key-substituted` | A47 | the merge stores at `(p.pro, p.tpa)` instead of `(p.pro, p.spa)` | refuted |
| K5 | `merge-value-substituted` | A47 | the merge stores `p.tha` instead of `p.sha` at the right key | refuted |
| K6 | `add-frame-violation` | A50 | the add also writes a key unrelated to the packet, breaking the `store` frame | refuted |
| K7 | `tha-harvest` | A50, A47 | the receive step additionally installs `(p.pro, p.tpa) -> p.tha` | refuted |
| K8 | `hw-gate-dropped` | A42 | the table write is not conditioned on `haveHw(p.hrd)` | refuted |
| K9 | `proto-gate-dropped` | A44 | the table write is not conditioned on `speaks(p.pro)` | refuted |
| K10 | `discard-emits` | A41 | a failing guard still yields an emission, or a table write beyond the merge already performed | refuted |
| K11 | `reply-literal-swap` | A53 | the reply sets `sha = req.tha` and `spa = req.tpa` rather than the local addresses | refuted |
| K12 | `reply-op-request` | A54 | the reply carries `op = REQUEST` | refuted |
| K13 | `reply-broadcast` | A55 | the reply's destination is `bcast(req.hrd)` instead of `req.sha` | refuted |
| K14 | `reply-to-nonrequest` | A51 | an emission is produced when `p.op` is REPLY or OTHER | refuted |
| K15 | `request-unicast` | A39 | the generated request's destination is a unicast address instead of `bcast(emitted.hrd)` | refuted |
| K16 | `spa-is-sought-address` | A35 | the request's `spa` is the protocol address being resolved rather than `myPa(pro)` | refuted |
| K17 | `sha-foreign` | A34 | the request's `sha` is a value other than `myHw` | refuted |
| K18 | `tpa-substituted` | A36 | the request's `tpa` is not the `ProtoAddr` of the key whose lookup missed | refuted |
| K19 | `request-op-reply` | A33 | the generated request carries `op = REPLY` | refuted |
| K20 | `hrd-substituted-on-emit` | A29 | the request names a hardware type other than the one it is generated on | refuted |
| K21 | `pro-substituted-on-emit` | A30 | the request's `pro` differs from the `ProtoType` that keyed the lookup | refuted |
| K22 | `hln-mismatched` | A31 | the emitted `hln` is a `Len` other than `hlen(emitted.hrd)` | refuted |
| K23 | `pln-from-hardware` | A32 | the emitted `pln` is taken from the hardware type rather than `plen(emitted.pro)` | refuted |
| K24 | `hit-returns-foreign` | A24 | the hit branch returns a hardware address not stored under the queried key | refuted |
| K25 | `hit-also-emits` | A24 | the hit branch emits a REQUEST for a key already present | refuted |
| K26 | `miss-resolves-anyway` | A26 | the miss branch yields a resolved address to the caller | refuted |
| K27 | `miss-emits-nothing` | A28 | the miss branch produces no emission | refuted |

Row-to-entry map, for the check: A24 K24 and K25; A26 K26; A28 K27; A29 K20; A30 K21; A31 K22;
A32 K23; A33 K19; A34 K17; A35 K16; A36 K18; A39 K15; A41 K10; A42 K8; A44 K9; A47 K1, K3, K4 and
K5; A49 K2; A50 K1, K2, K6 and K7; A51 K14; A52 K1; A53 K11; A54 K12; A55 K13.

Three entries may turn out unwritable for a reason already visible: K20 needs a second inhabited
`HwType`, and K22 and K23 need a second `Len` constant. If the frozen surface admits only one, the
entry is recorded `unwritable` with that reason, stays in the denominator of 2.10, and is not
replaced by a different mutation.

### 5.4 Good twins, seven entries, expected SAFE

| # | name | why it must survive |
| --- | --- | --- |
| G1 | `unsolicited-reply-merges` | a body that merges the sender triplet from a REPLY no request solicited. RFC 826 does exactly this: the merge at lines 210 to 213 precedes the opcode test at line 219. This twin is the pre-registered demonstration that **the protocol permits cache poisoning by unsolicited reply**, and a refutation here would mean the contracts forbid conforming behavior |
| G2 | `other-opcode-merges` | a body that merges on `op = OTHER` and then emits nothing. Required by A52 read together with A51, and the behavior `scope.md` section 6 names as in-scope |
| G3 | `tha-arbitrary` | the generated request fills `ar$tha` with the broadcast address. Lines 184 to 188 leave it unspecified. Evidence for A37 and A38 |
| G4 | `optional-checks-on` | both optional length checks present. Evidence for A43 and A45, and half of obligation O2 |
| G5 | `optional-checks-off` | both optional length checks absent. "Optionally" means both behaviors conform, and this is the other half of O2 |
| G6 | `non-ethernet-pro` | on hardware other than Ethernet, `ar$pro` holds a value outside the Ethernet protocol type field values. Evidence for A60 |
| G7 | `structural-variant` | a correct body written differently: branch order swapped, nested conditionals where the original matched. Guards against contracts that pin the shape rather than the behavior |

### 5.5 The mandatory members

Five kill-required entries, one good twin, and one declared negative result are mandatory. If any
is absent from the executed matrix, the run does not meet R6 whatever the other verdicts say.

1. **K1 `merge-after-opcode`.** The error RFC 826 itself shouts at: line 219 carries the only
   double exclamation in the document, "(NOW look at the opcode!!)", and lines 227 to 234 spend a
   paragraph restating it. Merging before the opcode is read is the characteristic rule of this
   protocol, and an implementation that merges afterward has implemented a different one. Attested
   as feasible by stage H probe `merge-before-opcode`.
2. **K2 `promiscuous-add`.** Caching from any observed packet rather than only when this station is
   the target. RFC 826 confines that behavior to the monitor of lines 337 to 348; implementations
   have done it in the core, and it is the amplification step that turns one forged broadcast
   REQUEST into a poisoned entry on every station on the cable instead of one. Attested as feasible
   by stage H probe `recv-table`, whose mutant note names it "the ARP cache-poisoning enabler".
3. **K3 `old-address-wins`.** Refusing to supersede, which is the common anti-spoofing bolt-on.
   Lines 231 to 234 and 443 to 447 exist because a host that moves must be reachable again, and
   with no aging in the model (`scope.md` section 3) a non-superseding entry is wrong forever.
   Attested by stage H probe `supersede-two`.
4. **K7 `tha-harvest`.** Learning both ends of the packet, entering a binding the sender was never
   asked to fill in (line 312, `ar$tha` "has no meaning in the request form") and that no clause in
   lines 209 to 218 authorises. Attested by stage H probe `learn-sender-only`.
5. **K11 `reply-literal-swap`.** The literal reading of "swap" at lines 221 to 222, which the
   worked example at lines 396 to 401 disambiguates against. A reply built this way advertises the
   requester's own binding back at it and reads a field the RFC says has no meaning. Attested by
   stage H probe `reply-emit`.
6. **G1 `unsolicited-reply-merges`, mandatory as a twin.** The run must show both that wrong
   behaviors are refutable and that merging an unsolicited reply is conforming. One without the
   other misstates what the protocol does.
7. **N-SPOOF, the declared negative result, below.**

**N-SPOOF: the attested bug of this protocol, and why it is not a mutant.** ARP cache poisoning by
forged sender fields is the historically attested defect of RFC 826, described in the public
literature since Bellovin's 1989 "Security Problems in the TCP/IP Protocol Suite" and mechanized in
on-path tooling ever since. The natural mutant would assert the strong binding most people believe
ARP provides, that the installed hardware address is the one that actually transmitted the frame.
**That mutant cannot be written in this model**, because `scope.md` section 5 item 2 excludes the
Ethernet frame header entirely and gap G-1 records the consequence: there is no frame source in
any signature, so there is nothing to compare `ar$sha` against.

What replaces it is a negative result stated as a property and refuted by the **correct**
implementation, which stage H's `FINDINGS.md` section 4 already records as unprobeable in the
probe-and-mutant shape, since a property the protocol does not have gives `refuted` on both
polarities:

> **N-SPOOF.** "Every binding in the translation table corresponds to the station that actually
> sent the packet that installed it" is false of any faithful implementation of lines 203 to 225,
> because the algorithm reads `ar$sha` out of the packet body and the attacker model of
> `scope.md` section 6 lets the environment choose it.

Its witness is a two-step trace from a correct body: a forged packet installs a binding, and the
table afterward holds a mapping no real station owns. **Its refutation is the intended result, not
a defect in anyone's work**, and the report says so in those terms. It is recorded in the kill
matrix as a named entry with verdict `unwritable` and this reason, so its absence from the kill
column cannot later be read as an oversight.

### 5.6 Obligations with no refutation pressure, declared in advance

Named now so that their absence from the kill column is not read later as weak contracts:

- All 24 C6 rows, all 8 C4 rows, and the single C2 row: excluded, carried by no clause, nothing to
  violate.
- The 21 excluded C3 rows, 15 of them under B5: their obligation is about byte extents, and the
  model has no bytes. A mutant would have to be written in a language the model does not contain.
- The 8 excluded C1 rows, 7 of them under B7: each is entailed by a named sibling row, so a mutant
  targeting it would be a mutant against the sibling.
- A37, A38 and A60: permissive models. Anything a mutant could do is licensed, so only good twins
  apply (G3, G6), and 2.3a books them as not carried.
- **Stated partial carries, from stage G's own reasons.** A28's conjunct about the Ethernet type
  field `ether_type$ADDRESS_RESOLUTION` is not carried, because the frame header is not in the
  modeled state; K27 targets the emission trigger only. A31's parenthetical, that six is the byte
  count of a 48-bit address, is not carried, because it is arithmetic over widths; K22 targets the
  equality against the named constant only. A55's disequality against the broadcast address is not
  claimed, because an attacker may place the broadcast address in `ar$sha`; K13 targets the
  equality only. Each is a place where a row is carried in part, and the report says which part.
- **The ten characteristic-core rows dispositioned out** (section 6). No clause carries them, so no
  entry targets them. That is the material fact of section 6, not a taxonomy gap.

### 5.7 Booking rules

1. **Catalogue first.** `mutants.json` is written before any solver time is spent. Two earlier runs
   of this stage were lost to an agent spending its budget on verification and never writing the
   catalogue, so the mutants existed and nothing could score them.
2. **Confirm the mutation landed.** Each mutant's body must differ from the original, and the
   difference must be the named change. A string replacement that hit a comment or a type
   declaration produces a survivor that looks like a weak contract and is a broken instrument.
3. **Unwritable entries stay in the denominator.** If no clause in the frozen surface can be
   violated by an entry, it is recorded `unwritable` with the reason and remains in the
   kill-required count of 2.10. The driver supports this verdict directly.
4. **Not-authored entries stay in the denominator too.** If stage N runs out of budget, or is handed
   no implemented tree, it writes the full register with the unwritten entries marked
   `not-authored` and the reason. A kill matrix with no implemented tree behind it is **void**, and
   void is reported as void, not as zero survivors.
5. **Survivors are resolved, not removed.** A survivor is reported in the matrix, and the
   resolution (contract strengthened, row re-dispositioned, mutant found invalid) is recorded with
   its witness in the detection-yield ledger of 2.11a.
6. **The register is closed.** Twenty-seven kill-required entries, seven good twins, one declared
   negative result, fixed before stage K authors a clause. Entries are not added after seeing the
   contracts. If the contracts turn out to need an entry this register lacks, that gap is reported
   as a finding about this pre-registration and the entry is added by an Appendix B amendment,
   dated, so a reader can see it was not in the original set.

---

## 6. Known before the wave: the stage-J core-row condition is already met, and is not retired here

Recorded in the pre-registration rather than discovered in the appendix, because it is already
visible in artifacts written and hashed before this document.

**The facts.** Stage F fixed 26 characteristic-core rows. Stage G dispositioned ten of them out:

| Row | Class | Barrier | Lines | Obligation |
| --- | --- | --- | --- | --- |
| A2 | C4 | B4 | 65-66 | on a low-byte-first machine, `ar$op` is encoded and decoded high byte first |
| A11 | C3 | B5 | 141-142 | the first field of the packet data is a 16-bit `ar$hrd` |
| A12 | C3 | B5 | 143 | the second field is a 16-bit `ar$pro` |
| A14 | C3 | B5 | 146 | the third field is an 8-bit `ar$hln` giving the byte length of each hardware address |
| A15 | C3 | B5 | 147 | the fourth field is an 8-bit `ar$pln` giving the byte length of each protocol address |
| A16 | C3 | B5 | 148 | the fifth field is a 16-bit `ar$op` holding REQUEST or REPLY |
| A17 | C3 | B5 | 149-150 | `ar$sha` occupies exactly `ar$hln` bytes |
| A18 | C3 | B5 | 151-152 | `ar$spa` occupies exactly `ar$pln` bytes |
| A19 | C3 | B5 | 153-154 | `ar$tha` occupies exactly `ar$hln` bytes |
| A20 | C3 | B5 | 155 | `ar$tpa` occupies exactly `ar$pln` bytes |

Stage G wrote "CORE ROW DISPOSITIONED OUT" and "STOP" into each of the ten reason fields and
declined to re-classify any of them to pass the gate. Its stated ground for declining is worth
keeping: the expressible residue of A11, that the decoded record has an `hrd` field of sort
`HwType`, is the datatype declaration and constrains no implementation, so retiring the row under
B7 would substitute a weaker statement for the row's actual obligation.

**The condition this meets.** The gate predicate in this build is
`gate_halts core_out bad_barrier _ _ = core_out > 0 || bad_barrier > 0`. Here `core_out = 10` and
`bad_barrier = 0`. **The condition is met, and the correct reading is a halt.** Unlike the
predecessor run, stage J is implemented here and there is no flag that suppresses it: the driver
writes `09-gate/gate.json` naming the ten rows under `characteristic_core.dispositioned_out`, then
halts the run citing `driver-spec sec 6:224-227`. Stages K through O will not run.

**What I am not doing.** I am not retiring the condition, not re-scoring the ten rows, and not
redefining the characteristic core so the number comes out at zero. Redefining the core after
seeing which rows fail is the exact move pre-registration exists to prevent, and it would be worse
here than a ratio ceiling, because the core list is the qualitative criterion that Amendment 1 of
the TFTP run kept precisely when it retired the quantitative one.

**The argument a human may want to weigh, stated and not adopted.** Two pre-extraction instruments
conflict, and neither was written with reference to the other:

- *Reading A, the core list is over-inclusive.* Stage F selects "what makes this protocol this
  protocol" from the whole RFC without reference to stage B's boundary. Nine of the ten rows are
  the packet format at lines 141 to 155, which `scope.md` section 2 named OUT in advance, and the
  tenth is byte order, which section 2 also named OUT. Under this reading the defect is in the core
  list, and the remedy is an amended core list that states which obligations it is selecting over,
  authorized by a human, with the original list left intact.
- *Reading B, the boundary is too narrow for this protocol's core.* If ten of the 26 rows that
  define ARP cannot be stated inside the decode boundary, then the boundary excludes part of what
  makes this protocol what it is, and the remedy is to re-scope the target rather than re-grade it.
  `scope.md` section 2 concedes the shape of this when it calls parsing the largest single gap by
  attack surface, and gap G-5 says so directly.

**A third observation, offered as a candidate finding rather than a reading.** The conflict is not
accidental and is not specific to this run: stage F's question and stage B's boundary will collide
on any protocol whose identity is carried by its wire format, and the predecessor run hit the same
condition at 3 of 21. That is a property of the pipeline's stage design, and if a human adjudicates
it as such, the remedy belongs in the prompts for stages B and F, not in this run's numbers.

**The number that does not move under any reading.** Ten of 26 characteristic-core obligations are
carried by no contract, and the report names which ten and why. No writeup from this run, or from
any successor run that inherits this ledger, may state "the protocol core is verified
body-faithfully" without that qualification, and the qualification is not a footnote.

**What a continuation would mean.** There is no flag that resumes past this gate. Any fix changes
an upstream artifact, which changes its digest, which makes the result a different derivation.
So: a successor run re-runs the amended stage and re-derives every downstream artifact, writes its
own pre-registration citing this one, and does not inherit this run's digests. Sections 1 through 5
of this document bind that successor, because they were fixed before any fill was seen and that is
the only property that makes them worth anything. What the successor may not do is edit this file.

**Adjudication is the project owner's, not the analyst's.** Recorded here, referred, and left open.

---

## 7. Amendment procedure

1. An amendment is appended to Appendix B. Nothing above section 7 is edited, reworded, or
   deleted, including anything this run proves wrong.
2. An amendment states: the instrument, the defect, the argument with its evidence, the replacement
   if any, the date, and the human who authorized it. An amendment without a named authorizer is a
   proposal, not an amendment.
3. An instrument may be replaced, never silently reinterpreted. "The threshold did not really mean
   that" is a reinterpretation. "The threshold measured the wrong property, here is why, and here
   is what replaces it" is an amendment.
4. Analysis does not resume on the criterion under amendment until it is adjudicated.
5. No ratio ceiling may be introduced by amendment. That instrument was retired with an argument
   that does not depend on the target, and re-introducing it would repeat a settled error.

---

## Appendix A: outcomes

Empty at freeze. Every measurement of section 2 is recorded here after the run, including the ones
that go against the plan, and especially those.

## Appendix B: amendments

None at freeze.

## Appendix C: what the reader should check first

For anyone auditing this run rather than reading the report:

1. That this file's digest in `MANIFEST.json` matches the file, and that its modification time
   precedes every stage-J, stage-K and stage-N artifact. A pre-registration edited after the fact is
   worth nothing, and this is the cheapest way to detect it.
2. That section 2's values still hold when recomputed from the pinned ledger: 90 rows, 23 / 5 / 0 /
   62, 28 of 58 carried, 16 of 26 core rows Encoded, 62 of 62 exclusions citing a listed barrier.
3. That `09-gate/gate.json` names the same ten rows section 6 names, and that the run's transcript
   shows the halt rather than a continuation.
4. That section 6 appears in any report this run or a successor produces, in the summary and not
   only in a section near the end.
