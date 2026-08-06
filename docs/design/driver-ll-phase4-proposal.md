---
name: driver-ll-phase4-proposal
title: "DRIVER-LL Phase 4: the agent-delegated stages, the serial wave, and the two oracles that can check them"
status: "Rev 10, SETTLED. Rev 10 folds the sub-phase 4c harness leg: three MEASUREMENTS at `d15b2ff` (v0.14.87), not predictions, and the first of them refutes this document's own 4c acceptance clause. F-18: SECTION 9's 4c CLAUSE IS UNSATISFIABLE UNDER BOTH READINGS, which is section 1.2's defect recurring at sub-phase granularity. Stage E's seven Phase 3 pins hold 7 for 7 over the COMMITTED pair and 0 for 7 over stub-D output (compared 43 against 2, unmatched (1,10) against (0,0), kappa 0.9378 against 1.0), and the two Jaccard pins are not merely wrong-valued but UNADDRESSABLE, the stub's source being `spec.txt` so the `line_coverage` key is `SPEC` and the RFC1350/RFC1123 projections return MISSING. A live reading is stochastic and cannot pin (1,10); the only reading that holds is over the committed pair, which is what Phase 3 already established and does not exercise D at all. The clause is REPLACED: downstream ported stages RUN over 4c's own output, rather than pinned values reproducing over it. F-19: SECTION 3.6'S ONE-DISAGREEING-SITE CLAIM IS MEASURED FALSE. There are at least two and they resolve in OPPOSITE directions. Stage D's `check_extraction` halt on loop iteration b is the second: extractor A's `extraction.json` is declared, present, and passes the driver's own validator, so section 4:146's 'wrote some of its artifacts' is satisfied by a valid SIBLING and the artifact-state axis says `stopped`, while the reference records failed/Errored. A discriminating test with two live outcomes ELIMINATED the artifact-state-wins reading: the rule fitting both sites is HOLD-THE-EXISTING-VALUE, and section 3.6 read as though artifact-state won at :866 on the merits. The site is also invisible to a per-site census, one source line carrying different artifact-state dispositions on its two iterations, which is the loop-granularity analogue of F-16's deferred row-granularity limit. F-20: the bare-list arm at F:713 and G:732 has NO producer in the tree (stub, sole committed artifact and the stage-F template's own example are all dicts), so it is dead in-tree though not unreachable, and the port narrows to the dict shape and REJECTS a bare list rather than accepting it silently. Section 9.2 is NEW and settles 4c in five items, of which the sharpest is that [V7-NO-PARTIAL] and [V7-ONLY-TWO] are SOUND FOR 4c UNCHANGED and need no widening, `verdict-of` taking no artifact set, so the sibling-state question belongs at the call site rather than inside the shared facility. ALSO RECORDED, a reference defect and not a port one: stage E's docstring says the script 'stops if they are unadjudicated' and it does not stop, `reconcile.py`'s only non-zero exit being a missing `source` field, and since F, G and G2 all read `extraction-a.json`, the B-side extraction has no downstream consumer beyond the reconciler's report, making the (1,10) disagreement this port PINS inert in the reference pipeline. DEFERRED, not repaired: section 3.6's table is line-keyed and its keys are stale at HEAD, and re-deriving it needs a fresh census rather than a renumbering, since :809 is now a `for` statement inside `_pinned_sources` and the two G2 requires it names fire BEFORE G2 writes anything. Rev 9, SETTLED. Rev 9 folds an AST call-site census of section 3.5 at HEAD (v0.14.86) that REFUTED REV 8'S OWN EPOCH STAMP, and settles the three things sub-phase 4b needed. THE STAMP WAS WRONG THREE WAYS AND IT IS THIS DOCUMENT'S ERROR: it said the halt-site set dropped from 46 to 39, and it never dropped, being 46 at aa08051~1, 46 at aa08051 and 46 at HEAD, with ten conditions RE-ENCODED and none added or removed. The 39 came from `grep -cF 'require('` returning 40 and subtracting only the definition, missing three DOCSTRING mentions; the real call-site count is 36. The raise count also did not rise at Task #8 but at c10081d. A grep produced a wrong count inside the correction of a wrong count, which is risk 3c at its most literal. A THIRD RAISING FORM EXISTS, `require_written` to `PartialHalt` to `PartialThenHalt`, which neither section 3.5 nor the stamp mentioned. THE SUBSTANTIVE RESULT UNDER THE ARITHMETIC: the rule survives intact and the shipped repair ENCODED it rather than replacing it, all nine spec-defined sites being `require_spec` at HEAD carrying the clauses section 3.5 names, 9 for 9, with the polarity guard holding. Section 3.5.1 is NEW and forbids keying on the nine line numbers: two of them now point at sites with the OPPOSITE disposition, live `require()` calls recording `failed` where the section files them as `stopped`, so a reader lands on a plausible-looking site and nothing signals the miss. Consumers key on condition text and clause, which the repair made stable by requiring a citation at every raise site. Section 9.1 is NEW and settles 4b: the two unguarded reads in stages B and I are ported as decisions recording `failed` rather than reproduced as crashes (the port has no host exception to fall through, and read_manifest set the precedent at 4a); stage I has NO VALIDATOR either, so section 6.2's claim that stage O is the only such delegated stage is false, and 4b discloses that rather than inventing one; and every reachable halt in B, C and I records `failed`, so a `stopped` anywhere in 4b is wrong by construction. Also filed as a null result: section 3.1's row 3 does not describe the reference, since AgentRunner.run raises on a non-zero exit BEFORE the output-existence check, so a stage producing a valid declared output and exiting non-zero records `failed`, not `complete`. DEFERRED, not settled: F-16, a row-granularity limit where two sites halt `stopped` on non-core rows because their halt-mandate binds the gate rather than the stage; it does not block 4b, neither site being in B, C or I. Rev 8: SUB-PHASE 4a IS SHIPPED (`2b82464`, v0.14.85) and the phase now runs at 4b. Rev 8 settles the four findings Rev 7 filed and deliberately held, three of which were predictions; the port executed them and ALL THREE ARE CONFIRMED. (1) `wasi.fs.sha256` collapses presence and digest, which is now the third statement under section 7's `skip.may-skip` bullet, and it was worse than a disclosure gap: it made the port's own T7 scenario NON-DISCRIMINATING, hardcoding `artifacts-present` left all fifteen scenarios green on the one cell that exists to witness driver-spec section 5's condition (b) alone. Repaired in the port. The reference does NOT share the defect, established by mutation rather than reading: it computes its digest loop under the guard `if recorded and artifacts:`, so on an absent artifact (c) is vacuously satisfied rather than falsified. (2) Section 4's sum encoding makes `:on-done` usable, retiring the RC-4 workaround. (3) The port decides all three corrupt-manifest shapes with one total constructor-decidable predicate where the reference discriminates by Python exception site, so the port is BETTER than the artifact clause 1b checks it against; recorded rather than suppressed, 1b being a conformance claim and not a fidelity claim. (4) Section 3.5's counts are stamped with their measurement epoch: 46 call sites at `aa08051~1`, 39 at HEAD, moved by the repair section 3.5 itself ordered, so the argument stands and the arithmetic does not; 4b must re-measure. TWO FINDINGS THE PROPOSAL DID NOT PREDICT: the eleven-cell cover is stronger than its count states, since mutating each conjunct separately shows T7 and T6 die to their own conjunct and survive the other's, so the cells are SEPARABLE and not merely both present; and a perturbation that crashes is not a perturbation that refutes, since hardcoding presence at its definition yields an unhandled FileNotFoundError rather than a wrong skip, so a mutation must sit where the decision is read and not where the value is produced. Sub-phase 4a shipped with NO SHIM: PROC-BOUNDARY-1 was closed first, so argv arrives as flags and the process exits through `:status`, and nothing sits between the assertions and the program under test. Rev 7 folded the harness leg and unblocked sub-phase 4a. Rev 7 folds the execution of Rev 6's five checkable predictions (harness findings F-9 through F-11, compiler v0.14.84): four held and one is refuted. HELD: T7 re-runs the stage and prints no reason line, executed rather than read, so the eleven-cell cover is now eleven of eleven covered; the sequencer does crash on a corrupt manifest; it is NOT a section 4 violation, which is the point Rev 6 argued against the fourth professor round; and T7's silence is conformant and deliberately not asserted by the test. REFUTED, and it was this proposal's own claim: the reference CANNOT reach T7 through its own write path, because AgentRunner.run raises StageFailure when a delegated agent exits 0 having written nothing, so 'silence is not success' is already enforced for the eleven agent-delegated stages. Rev 6 grepped `stage.outputs`, the declared list on the Stage record, and the check is written against `out_name` one call frame down. Section 2.3 finding 3 is struck and replaced; section 10 case 3 is annotated as already-implemented rather than divergent; the surviving residue is the two mechanical and three gate stages, which have no generic presence check and are unmeasured rather than closed. SHORT BY ONE: Rev 6 named two corrupt-manifest shapes and there are three, each surviving the guard that catches the one before it, the third being a well-formed object with a list at `stages` that dies at the resume gate's own indexing expression. Added as section 10 case 18 with the method lesson. Risk 3c is new and is the reason this revision exists: four refuted mechanism claims across this phase, all the same shape, a grep over the name the document uses where the code enforces the same obligation under a different name one frame away, and all four caught by executing rather than by re-reading. Rev 6 folds the fourth professor round and repairs the citation surface. Five substantive changes. (1) Clause 1a was UNSATISFIABLE as written: it claimed the manifest sequences are identical, and a complete row carries a wall-clock `seconds` field while the three halt rows carry Python exception text as `detail`, so the reference is not identical to itself. §2.1 gains an abstraction function alpha, per field, with the criterion that a field survives alpha when some specification obligation mentions it. (2) §2.3 is rewritten as a product over three axes rather than a hand-enumerated list, because the count moved at every revision. Eleven cells, not nine. Two were missing: T4 (a halt after writing output, whose PartialThenHalt constructor alpha retains, and which §9's own four-arm acceptance requires) and T7 (a complete record with a declared artifact absent, driver-spec §5's skip condition (b) failing alone). NOTHING TESTS T7, the reference runs the stage correctly and silently, and the cell is the only witness for `may-skip`'s presence conjunct. (3) The cover models the per-stage machine and 4a lands the sequencer above it: an unreadable or non-object MANIFEST.json tracebacks out of the reference before any stage runs. That is NOT a §4 violation, §4 being scoped to a stage that halts, and it is routed as a reference repair rather than a §3 divergence, since every avoidable divergence weakens the retirement argument. (4) `FS-STAT-1` is re-scoped: an mtime does not close it, because `advancing` takes an age in seconds and monotonic reports nanoseconds since an unspecified epoch. The row now proposes a clamped-age builtin, which discharges the first precondition conjunct by construction where the shell-side subtraction would let clock skew violate it. (5) `CLAUSE-INDEP-1` is filed: `[S5-PRESENCE]` follows propositionally from `[S5-SKIP]`, so no mutation refutes it alone. The machinery ships already (CDP vacuity gate v0.14.13, `LLMLL.Feasibility` v0.14.52) and the clause-side dual is the cheapest of the three. Also: seven stale line citations repaired, five into compiler/src/LLMLL/ and all four of §10 case 6's; `FS-ENCODING-1` and `FS-COPY-1` marked shipped at v0.14.84 with the former's mechanism claim corrected, the release having measured it false; the emitMatch hole tagged `MATCH-CATCHALL-1`; and the instruction that the port reproduce the reference's silence at T7 WITHDRAWN, it having contradicted §2.1's own definition of the clause-1a observable. Rev 5, SETTLED. Rev 5 folds the third professor round and a sweep of driver-spec §8 through §15.4, the sections the truncated heading grep had left unread. Four substantive changes. (1) §3.5's classification rule was two-way over a FOUR-constructor Outcome: it never referenced PartialThenHalt, which stage.llmll proves maps to Stopped under [S4-PARTIAL] citing §4:146-147, and which Phase 3 already constructs. Measured over the write-before-require ordering of every stage, exactly one of the 38 divergent sites fires after its stage wrote a DECLARED output: :866, stage H. It becomes PartialThenHalt and stays stopped, so the divergence set is 37. The same clause independently corroborates six of the nine spec-defined sites and contradicts one, which is the profile of an eliminative check rather than an agreement. (2) §6 gains driver-spec §8, §10, §12 and §13 conformance. Stage O is the ONLY delegated stage with no validator at all, and §13 is its specification; its eight MUSTs split on §15.1:512-515's enumeration rather than on decidability, one being mechanizable (§13:443-446, perturbation omission) and seven disclosure-only. (3) §14's Blocks column is corrected twice: FS-COPY-1 blocks driver-spec §8:336-337, which requires the checking copy to be the original unmodified subject, so it is conformance and not ergonomics; FS-STAT-1 blocks §12:405-428 via a §15.2:522-524 capability gap, the §15.1:511 proof obligation being already discharged. (4) One target-spec defect filed: §15.1:509's range sentence contradicts its own enumeration at :512-515, and §13's prose MUSTs consequently fit none of the three tiers §15.1:504-505 requires every obligation to occupy. driver-spec is pinned under §14:473-474, so this is recorded rather than repaired. §15 records two corrections to this proposal's own prior turns, both misreadings of a citation audit this proposal itself produced. Rev 4, SETTLED. Rev 4 is the first revision driven by EXECUTING the harness rather than reading it, and it closes the one item Rev 3 left un-implementable. §3.5 is new: the halt surface is 46 require() sites plus three AgentRunner raises, not the four conditions §3.4 described, and the disposition attaches to the CLAUSE rather than the stage or the validator, because check_dispositioned holds six checks of which exactly one (:355, the closed-barrier condition, driver-spec §6:229-231) is spec-defined. §3.5 gives the classification rule with a polarity guard (§14:484-491 states two checks that MUST be reported and MUST NOT halt), enumerates the nine spec-defined sites by clause, and resolves all three sites the harness could not classify -- :967, :866 and :1045 -- to failed, which unblocks the Python-side repair. Divergence set is 38, not 4. Three corrections to Rev 3, two of them to this proposal's own claims: §10 case 5 was WRONG (it derived 'no holes to fill -> stopped' from the driver's own source, and driver-spec has no clause about an empty hole set, so §4:129's residual gives failed -- the third instance of the error shape §3.3 records twice, and the first originating here); §2.3's coverage claim counted STUB_MODE values rather than tests, and the measured cover was six of eight with a ninth transition omitted; and the citation-resolution mandate is §14:479-483, not §7, which Rev 3 missed because a heading grep truncated at section 9 and §10 through §15.4 were never read. One finding PARTLY REFUTED: stage H is not unspecified, since §7:313-316's catalogue clause covers it; only its acceptance bar is driver-defined, which narrows what Phase 5 §15.4 owes. Rev 3, SETTLED. Revises `driver-in-llmll-campaign.md` §Phase 4 on two structural corrections: the phase's stage enumeration was short by one (stage G was assigned to no phase), and its acceptance clause ('a complete run reproduces a committed campaign's artifacts') is not satisfiable against this tree, measured. Replaced by two claims plus a derived transition-cover scenario set. Rev 3 settles the delegated-stage disposition on its THIRD derivation: Rev 1 argued from §4's residual clause, Rev 2 argued from §7's wording and was refuted on the specification's own use of 'fails' as a verb, and Rev 3 rests the conclusion on §4:132-136's verdict-versus-accident criterion, which neither prior derivation touched. The conclusion did not move; the argument did, twice. Rev 3 also reframes the finding against the Python driver from a wrong constant to a missing distinction: it has ONE halt channel where the specification defines TWO, and `stage.record-outcome`'s `Outcome` type already models both. Rev 2 folded the first professor round (serial wave makes the contention branch unreachable, so the Rev 1 positive witness was unsatisfiable; state is a sum over phases, not a flat product; `wasi.fs.copy` split out from the encoding fix). Rev 3 folds the second (the §7 lexical refutation, accepted; its replacement conclusion, rejected; the citation-clause over-reading, withdrawn; the abstraction-function disclosure, adopted). Both professor rounds were conversational; no standalone review file exists, and their findings are folded in §15."
date: 2026-08-04
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, professor, user]
---

# DRIVER-LL Phase 4: the agent-delegated stages and the serial wave

**One line.** Phase 4 ports the eleven agent-delegated stages and the wave, activates the three
proved cores that have had no caller since v0.14.70, and is the first phase whose acceptance cannot
be checked by comparing artifacts, because the artifacts are written by models.

**Prerequisite state.** Phases 0 through 3 are complete at v0.14.83.
[`tools/llmll-driver/spine.llmll`](../../tools/llmll-driver/spine.llmll) runs stages E, J, L and G2
end to end against the committed TFTP execution with nine body-faithful `def`s and zero FFI
declarations. Stage A is a filed STOP (`HTTP-GET-1`).

---

## 1. Two corrections to the campaign's §Phase 4

### 1.1 The stage enumeration is short by one

`STAGES` ([`scripts/rfc_to_implementation.py:1334-1376`](../../scripts/rfc_to_implementation.py))
has **sixteen** entries: fifteen letters A through O plus `G2`. Phase 3 took A, E, G2, J, L. The
campaign's Phase 4 list reads B, C, D, F, H, I, K, M, N, O, which is ten.
**Stage G (`stage_G_disposition`, kind `agent`, `:579-626`) is assigned to no phase.**

This is not bookkeeping. Stage G produces the dispositioned inventory, which is the input to stage
G2's audit and to both of gate J's disposition-reading conditions. Phase 3's spine already reads
that file from committed data (`spine.llmll` s=4, s=15). Until G is ported the LLMLL driver cannot
produce its own input for two stages it already runs.

**Phase 4 ports B, C, D, F, G, H, I, K, M, N, O.** Eleven stages.

G2 stays partial through Phase 4 for the reason `spine.llmll:28-31` gives: its citation half needs
source bytes this repository does not carry, which is stage A's STOP. Completing it is gated on
`HTTP-GET-1`, not on Phase 4.

### 1.2 The acceptance clause is not satisfiable as written

The campaign says "a complete run reproduces a committed campaign's artifacts." Two problems,
either sufficient.

**No committed run carries the full artifact set.** ARP
([`experiments/rfc-swarm/runs/rfc826/`](../../experiments/rfc-swarm/runs/rfc826/)) is the only run
that reached all fifteen stages ([`SUMMARY.md:21`](../../experiments/rfc-swarm/SUMMARY.md)). Its
committed directory holds fourteen files and is missing five stages' declared outputs: stage D's two
extractions, stage F's `core.json`, stage G2's `audit.json`, stage H's `feasibility.json`, and stage
L's `rfc-cov-1.txt` and `ROOTS.txt`. RFC 4648 carries `core.json` and `probes.json` and halted at J,
so it has nothing from K onward. TFTP's `data/` carries the extraction pair, for a different RFC.

**Agent output is not reproducible by construction.** Stage B writes prose, C a rubric, O a report.
Byte comparison against a committed `scope.md` is a claim about model determinism, which is not a
property of this system and is not what the campaign measures.

---

## 2. The oracle: two claims, one derived scenario set

### 2.1 Clause 1a, refinement

On the scenario set of §2.3 minus the §3 divergence inputs, the LLMLL driver's sequence of manifest
writes is identical to the Python driver's **under the abstraction function α defined below**.

The observable is the manifest file's successive contents, not either step machine's internal
states. `driver-spec.txt:154-157` requires the manifest to be written after every stage transition
in both implementations, so the granularity difference between a nineteen-state Python loop and a
sixty-state LLMLL step machine is quotiented by the specification rather than by the comparison.

**Rev 6 correction. The claim was unsatisfiable without α, and this is the fourth professor round's
leading finding.** Rev 5 said the sequences are *identical* and that "no refinement mapping needs
constructing and no auxiliary variable is needed." The second half stands; the first was false
against the reference and, worse, against the reference compared to itself. A complete row carries
`"seconds": round(time.monotonic() - started, 1)`
([`rfc_to_implementation.py:1953`](../../scripts/rfc_to_implementation.py)), so two runs of the
Python driver over the same inputs do not produce identical manifests. The three halt rows carry
`"detail": str(e)` (`:1911`) and `f"{type(e).__name__}: {e}"` (`:1928`, `:1945`), which serialize
Python exception text that no port reproduces and that §3.5's rule does not govern, §3.5 fixing the
**constructor** and not the message.

**α, per field:**

| Field | α | Why |
|---|---|---|
| `status`, `outcome`, `clause` | equality | The decision itself; `clause` is a structured spec-clause identifier fixed by §3.5's rule |
| `outputs` | key set and digest values, equality | Deterministic given the artifacts |
| `kind` | equality | Static per stage |
| `seconds` | **discarded** | Wall-clock; the reference is not identical to itself under it |
| `detail` | **non-empty predicate, not equality** | §4:129-131 requires a detail string *naming* the condition or the error; the naming is prose and the identity of that prose is not a specification obligation |

The criterion by which α keeps a field is: **some specification obligation mentions it.** That is why
`detail` survives as a predicate rather than being dropped, and why `seconds`, which no clause
mentions, is discarded outright.

Abadi and Lamport (*The Existence of Refinement Mappings*, TCS 82(2), 1991) separate the abstraction
function from the auxiliary history and prophecy variables that restore completeness when no mapping
exists. Rev 5 conflated the two. An abstraction function is required here, because the concrete
state carries components the abstract observation must forget; auxiliary variables are not, and the
granularity-quotient argument above is why.

### 2.2 Clause 1b, conformance where they differ

On the §3 divergence inputs the LLMLL driver conforms to driver-spec §4 and §7 and the Python driver
does not. This is a conformance claim against the specification, not a refinement claim against the
reference implementation, and it is the more important of the two: it is what the Python driver's
retirement rests on.

Stated as one clause with a carve-out, the carve-out is invisible and carries the whole exception.
They are two claims and they are proved differently.

**The residual α creates, and clause 1b must carry it.** driver-spec §4:139-143 requires a halting
stage to report the reason **on its output** as well as recording it, and adds that a halt reaching
the operator as an unhandled host-language error has reported neither. α cannot see standard output,
so that MUST is outside clause 1a by construction. Named here rather than left to fall between the
two clauses.

**Three oracles are in play, and Rev 5 read two of them as one.** Clause 1a checks α of the manifest.
Clause 1b checks conformance, including the §4:139-143 output obligation α cannot reach. The rig is
**strictly stronger than clause 1a**, because it asserts on stdout directly
([`test_rfc_pipeline_integration.py:458`](../../scripts/tests/test_rfc_pipeline_integration.py),
`:473`). A test written in the rig therefore pins more than clause 1a claims, and §2.3's cover must
say which oracle each cell is a cell of.

### 2.3 The scenario set is derived, not chosen

The harness exists.
[`scripts/tests/test_rfc_pipeline_integration.py`](../../scripts/tests/test_rfc_pipeline_integration.py)
drives the Python driver through all fifteen stages with a stub agent and a stub `llmll`,
hermetically, in seconds, and asserts the properties a port can actually break. Its four scenarios
(`ok`, `core-excluded`, `bad-barrier`, `coverage-gap`) are hand-picked.

Replace with a transition cover over the per-stage manifest state machine. **Rev 6 rewrites this
section as a product rather than a list, because the count has moved at every revision and a list
cannot be checked.** The state space has three axes: the manifest record (`absent`, `complete`,
`stopped`, `failed`), declared-artifact presence, and `--force`. driver-spec §5:174-205 partitions
the reachable cells into two families, and the count is derived from that partition rather than
enumerated by hand.

**Outcome transitions** (a stage runs; the manifest write it produces):

| | Cell | Manifest row | Rig coverage |
|---|---|---|---|
| T1 | → complete | `{status, kind, seconds, outputs}` (`:1950-1956`) | `test_pipeline_runs_through_both_gates` |
| T2 | → stopped, before writing output | `outcome: ConditionUnmet` (`:1913`) | `test_a_spec_defined_halt_records_stopped_and_names_its_clause` |
| T3 | → failed | `outcome: Errored` (`:1929`, `:1946`) | `test_a_delegated_output_defect_records_failed_not_stopped` |
| T4 | → stopped, after writing output | `outcome: PartialThenHalt` (`:1913`) | `test_stage_H_records_partial_then_halt_after_writing_its_output` |

**Resume decisions** (a stage carries a prior record):

| | Cell | §5 clause | Rig coverage |
|---|---|---|---|
| T5 | complete ∧ present ∧ match ∧ ¬force → skip | `:174-177` | `test_a_completed_stage_is_still_skipped_on_resume` |
| T6 | complete ∧ present ∧ mismatch → run, MUST report | `:182-183` | `test_a_modified_artifact_forces_a_rerun` |
| **T7** | **complete ∧ a declared artifact absent → run** | **`:174-177`, condition (b) alone** | `test_a_declared_artifact_deleted_from_a_complete_stage_forces_a_rerun` (**new, Rev 7**) |
| T8 | record absent ∧ artifacts present → run, SHOULD report | `:189-191` | `test_artifacts_without_a_completion_record_force_a_rerun` |
| T9 | stopped → run | `:193-194` | `test_a_failed_gate_is_not_bypassed_by_its_own_output_on_resume` |
| T10 | failed → run | `:193-194` | `test_a_failed_stage_is_re_run_on_resume` |
| T11 | `--force` → run | `:196-197` | `test_force_re_runs_a_stage_the_manifest_records_complete` |

**Eleven cells, and as of Rev 7 the rig covers all eleven.** The artifact axis does not multiply T9 and T10, because
§5:193-194 says a stopped or failed stage MUST be run "however many artifacts a previous attempt
left behind," which is the specification collapsing the product for us.

**T4 was missing from Rev 5's list and is a distinct clause-1a observable**, not a relabeling of T2:
the manifest row carries the constructor (`:1913`) and α retains `outcome`. A nine-cell cover
distinguishing three manifest halt states cannot satisfy §9's own 4a acceptance, which demands all
four `Outcome` arms.

**T7 was missing from Rev 5's list and nothing tested it until Rev 7.** Three findings. The first two
were measured at HEAD in Rev 6 and are confirmed by execution in Rev 7; **the third was derived from
three call sites, was not executed, and is refuted.**

1. *The reference runs the stage, correctly, and reports nothing.* `mismatched` is computed under
   `if recorded and artifacts` (`:1880`), so it is empty; `:1890`'s `if mismatched` is false and
   `:1894`'s `elif artifacts and not recorded` is false. The stage re-runs with no reason line, where
   T6 and T8 each print one. §5 attaches a MUST-report to T6 and a SHOULD to T8 and says nothing
   about T7, so the silence is conformant and the port is neither required nor forbidden to match it.
   **Executed at v0.14.84.** Per-stage grep of a resume after deleting stage B's declared output: B
   ran, printed no skip line, no digest line and no no-record line; A and C skipped normally. Harness
   findings F-9.
2. *`may-skip` already proves the cell over all inputs.* `[S5-SKIP]`
   ([`skip.llmll:19-21`](../../tools/llmll-driver/skip.llmll)) gives
   `result ⇒ (complete ∧ present ∧ match)`, whose contrapositive covers T7. The proof is not the gap.
   The gap is that the running program never supplies the input that distinguishes the branch, and as
   of Rev 7 one test supplies it.
3. ~~*The reference's own write path can reach the cell.*~~ **REFUTED in Rev 7, and the refutation is
   this proposal's own error to own.** Rev 6 argued that `stage.outputs` is consulted at exactly three
   sites (`:1877`, `:1881`, `:1955`), that none asserts presence before recording complete, and that a
   stage body returning normally without writing a declared output therefore records `complete` with a
   short `outputs` map. The grep is accurate; the conclusion does not follow. The obligation is
   enforced one level down, **per delegated call against `out_name` rather than per declared output
   against `Stage.outputs`**:
   [`rfc_to_implementation.py:331-334`](../../scripts/rfc_to_implementation.py) raises `StageFailure`
   when an agent exits 0 having written nothing. Measured: `rc=3`, status `failed`, outcome `Errored`,
   detail naming the missing file, and the following stage never attempted. Harness findings F-10.

   **What survives.** The check covers the **eleven agent-delegated stages**
   (B, C, D, F, G, H, I, K, M, N, O), every one of which routes its output through `AgentRunner.run`.
   The **two mechanical** (A, E) and **three gate** (G2, J, L) stages write their outputs in driver
   code and have no generic equivalent, so for those five the own-write-path route is **unmeasured
   rather than closed**. The harness cannot construct that case without editing a stage body, which
   would change the subject. After a green twelve-stage run, zero declared artifacts were missing and
   zero `outputs` maps were short.

   **Consequence for §10 case 3.** "Declared output absent, agent exit 0 → `failed`" describes
   behaviour the reference already has. It is not a divergence and must not be counted as one in §3.

   This is the third time in this phase a claim has been right about a defect and wrong about its
   mechanism, after §3.3's two and `FS-ENCODING-1`'s. The common shape is a grep over the name a
   design document uses for a thing, where the code enforces the same obligation under a different
   name one call frame away.

**T7 and §10 case 1 are the same phenomenon under different quantifiers, and the remedies are not
interchangeable.** Case 1's branch is unreachable for every execution of the system as configured, so
it needs a permanent fault injector that changes what the system does (§9 injects one at 4e). T7's
cell is reachable and merely unvisited, so it needs one scenario that changes only what is observed.
Filing them under one heading invites the wrong repair for whichever is met next.

**The cover models the per-stage machine only, and 4a lands the sequencer above it.** See §10 cases
15 and 16: an unreadable or non-object `MANIFEST.json` is handled by neither family, and the
reference crashes there. Those cells are not cover cells and not §3 divergences; they are a reference
defect with a repair, and §10 case 15 gives it.

**Rev 4 correction, retained.** Rev 3 said "the four existing ones cover three of the eight." That
counted `STUB_MODE` values (four) rather than tests (fifteen), and the mode selects only what the
stub *emits*; the resume, digest and force scenarios vary other axes of the rig. Measured at
`0ed395b`: six of Rev 3's eight had coverage, one of them (T3) only for a host-language crash rather
than for a delegated-output defect.

The criterion paid for itself three times: writing out the absent → failed transition is what sent
this proposal to §7 and produced §3, executing it is what produced §3.5, and deriving the cover as a
product rather than a list is what produced T4 and T7.

### 2.4 Clause 2, the live oracle

One real campaign run against a target already run in Python, judged on **decisions rather than
bytes**: each stage's recorded status, each gate's verdict and the condition it names, the
reconciliation figures stage E pins, the coverage exit status stage L pins, the wave's
filled-versus-finding partition and its retry-budget accounting. Artifact *shape* is checked by the
same predicates the Python driver applies; artifact *content* is not compared.

Carried forward unchanged from the campaign: zero FFI declarations, bounded authority end to end,
§15.1's seven obligations discharged by called proved cores, and the build-acceptance clause
(campaign §3a).

---

## 3. The delegated-stage disposition

This question was adjudicated three times in three turns and produced three derivations for two
conclusions. The table is the settled result; §3.2 is the derivation that holds; §3.3 records the two
that failed, so a fourth turn does not repeat them.

### 3.1 The table

| Condition | Status | Authority |
|---|---|---|
| Declared output absent | `failed` | §4:129 residual; §7:279 additionally removes exit status as evidence |
| Declared output present, fails validation | `failed` | §4:129 residual + §4:132-136 rationale; the declared shape is the stage contract's, not the specification's |
| Declared output present and valid, agent exit non-zero | `complete` | §7:279 makes the output the criterion; no halt occurs, so §4 is not reached |
| Agent wall-clock budget overrun | `failed` | §4:129 residual. No clause defines a per-invocation budget: §9 defines the two *retry* budgets, and §12's stall is a run-level reporting notion over artifact ages |
| Gate condition unmet (J, L, G2) | `stopped` | §6:220-231, §4:125-127. **Not divergent**; the Python driver is correct here |

**Rev 4 amendment to row 2.** "Fails validation → `failed`" holds *unless the failed clause is one
§3.5's rule identifies as spec-defined*, in which case `stopped`. The unit is the **clause**, not the
stage and not the validator function. `check_dispositioned` holds six checks of which one is
spec-defined and five are not, so no coarser unit is correct.

### 3.2 The derivation

`driver-spec.txt:132-136` states the criterion directly:

> The distinction is not cosmetic. A stopped stage is a **verdict the method reached**, and is a
> result of the run. A failed stage is an **accident**, and is not. An implementation that reports
> both as stopped permits a run killed by a network error to be read as a gate that fired, which is
> the one confusion this pipeline cannot afford.

An agent emitting an extraction row without a line span is an accident. Nothing about the target
document was learned. Recording it `stopped` files it beside gate J halting on a core-row exclusion,
which is a result, and that is the confusion the paragraph names.

The supporting observation is that §4:125-127's `stopped` branch requires "a condition **this
specification** defines." §7:283-286 mandates the *act* of validating; the *condition* is the
output's **declared shape**, and the declaration belongs to the stage contract, not to driver-spec.
Contrast §6:220-231, which enumerates its conditions (a characteristic-core row dispositioned out;
an exclusion citing no barrier from the closed list), and §11's RFC-COV-1. Those can be checked
against the specification text. "The extraction row carries `line_start`" cannot.

**§7:279's role.** Under this derivation an absent output is already `failed` through the residual,
so the sentence is not what establishes the status. What it adds is that **exit status is not
evidence of production**, which is what its own attached rationale says: "Silence is not success."
The rationale sentence names which default the override targets.

### 3.3 Two derivations that failed

Recorded because both are natural readings and both will be reached again.

**Rev 1 argued from §4:129's residual alone** and split the cases: absent → `failed`, malformed →
`stopped`. The split had no derivation behind it; it rested on an unstated intuition that a schema
violation is a defined condition.

**Rev 2 argued from §7:283-284's wording** ("Output that fails validation MUST fail the stage") and
concluded both cases are `failed`. The professor refuted this on the specification's own usage, and
the refutation holds: driver-spec uses *fails* and *failing* as ordinary verbs for outcomes it
records `stopped`. `:210` calls a gate that halts on its condition a "failing gate"; `:200-202` says
"a gate that **fails** after writing its report" of a case §4:146-147 records `stopped`. The spec
reserves *recorded* (`:129`) and *treated as* (`:279`) for status assignment. §7:284 carries no
recording language and cannot bear the weight Rev 2 put on it.

The professor's replacement conclusion (validation failure → `stopped`) is rejected on §3.2: it
requires validation to be a condition the specification defines, and the declared shape is not.

### 3.4 The finding against the Python driver, reframed

`stage_J_gate` halts through `require()`
([`rfc_to_implementation.py:938-943`](../../scripts/rfc_to_implementation.py)), and so does every
delegated-output validation (`:245`). `main()` maps that single channel to `stopped`
unconditionally (`:1784-1788`).

**The Python driver has one halt channel where the specification defines two.** The divergence is
not a wrong constant in one place; it is a missing distinction.

The proved core already carries the distinction the reference implementation lost.
[`stage.llmll:8-10`](../../tools/llmll-driver/stage.llmll) declares `Outcome` with four
constructors, `record-outcome` maps `ConditionUnmet` and `PartialThenHalt` to `Stopped` and `Errored`
to `Failed`, and `[S4-NOT-STOPPED]` proves the two cannot collapse. Phase 3 only ever constructs
`ConditionUnmet` and `PartialThenHalt`. **Phase 4 is where `Errored` acquires its first construction
site in the campaign**, and the port must raise two halt channels to reach it.

**Divergence set: four conditions.** Every `require()` that validates a delegated output, plus the
three `AgentRunner` conditions at `:221` (timeout), `:227` (non-zero exit) and `:230` (no output).
Gate halts are correct and are outside the set. The `require_durable_workdir` case at `:146` is not
adjudicated here: §5:193-196 makes the refusal a specification-defined obligation, but it fires
before any stage is attempted, so no stage status is assigned and §4 is not reached.

Route the Python-side repair to experiment-lead alongside the campaign's §6 item
(`crux-gate-single-remedy`). This is the second live divergence of that family.

### 3.5 The classification rule, and the enumeration

Added in Rev 4, after the harness leg measured the halt surface and found the four-condition framing
of §3.4 too coarse to implement against. The halt surface is **46 `require()` call sites** plus three
`AgentRunner` raises, and the disposition is a property of the call site rather than of the
mechanism; nine of the 46 are correct as they stand.

> **MEASUREMENT EPOCH, added at Rev 8 and CORRECTED at Rev 9 by an AST census that refuted the
> Rev 8 stamp itself.** Read the corrected version; the Rev 8 text is preserved only in §15.
>
> **The site set never shrank.** There are **46 halt conditions at `aa08051~1`, 46 at `aa08051`,
> and 46 at HEAD.** Matching call arguments across the epoch pairs all 46: none added, none
> removed, **ten re-encoded**. Rev 8 claimed a drop from 46 to 39 and there was no drop. The
> encoding split; the population did not move.
>
> **At HEAD the 46 helper call sites are:** 36 `require()` (`StageFailure`, records `failed`,
> `Errored`, exit 3), 9 `require_spec()` (`StopCondition`, `stopped`, `ConditionUnmet`, exit 2),
> and 1 `require_written()` (`PartialHalt`, `stopped`, `PartialThenHalt`, exit 2). **A third
> raising form exists and neither §3.5 nor the Rev 8 stamp mentioned it.** Plus 7 raw raises, for
> 53 halt sites in total; the raise count rose at `c10081d`, not at Task #8 as Rev 8 asserted.
>
> **Rev 8's 39 came from a grep, and the grep was wrong three ways.** `grep -cF 'require('`
> returns 40 at HEAD: 36 calls, 1 definition, and **three docstring mentions**. Rev 8 subtracted
> the definition and not the docstrings. This document recorded the rule that a count stated
> without its epoch reads as current, and then produced a wrong count while applying it. Risk 3c,
> and the instance is this section's own stamp.
>
> **The rule and the partition survive intact, and that is the substantive result.** The repair
> ENCODED §3.5's rule rather than replacing it: `require_spec`'s docstring restates both
> conjuncts and `StopCondition.__init__` makes the clause citation mandatory. **All nine
> spec-defined sites are `require_spec` at HEAD, carrying the clauses §3.5 names, 9 for 9.** The
> polarity guard holds: `near_miss` and `strength_absent` are accumulated and reported, and no
> halt helper reads either.
>
> **The line numbers, however, must not be used.** See §3.5.1.

**The rule.** A halt records `stopped` iff the failed condition is one **driver-spec states as a MUST
over artifact content, identifiable by clause**, and driver-spec either mandates the halt or makes it
a §6 gate condition. Every other halt records `failed`.

### 3.5.1 Cite these sites by condition, never by line

*(Added at Rev 9, after a census measured the failure this section was already vulnerable to.)*

**Two of the nine spec-defined line numbers now point at sites with the opposite disposition.**
`:811` and `:815` are live lines at HEAD, and both are `require()` calls in `_pinned_sources`
recording `failed`, where §3.5 files those numbers as `stopped`. A reader keying on the number lands
on an inverted site and finds a plausible-looking `require` call there, so nothing signals the miss.
The conditions themselves moved to `:956` and `:966`.

The full epoch-to-HEAD mapping for the nine is `:355`→`:493`, `:782`→`:921`, `:788`→`:928`,
`:811`→`:956`, `:815`→`:966`, `:821`→`:974`, `:936`→`:1100`, `:939`→`:1104`, `:1003`→`:1170`.
**It is recorded so the mapping is reconstructible, and not so it can be used.** Any consumer of
§3.5, sub-phase 4b first among them, keys on the **condition text and its clause**, which the repair
made stable by requiring a citation at every `require_spec` raise site.

This is the same defect this line repaired in prose citations on 2026-08-05 and wrote into
`docs/UPDATE-PROTOCOL.md`: a bare number reads as current and rots silently, and a line number is
strictly worse than a version number because nothing checks it and the tree renumbers on every edit.

Polarity matters and the rule must read it. §14:484-491 states two checks that **MUST be reported and
MUST NOT halt** (a span supplying the quoted words only in part; a declared strength absent from the
quoted text), on the stated ground that both "occur in correct censuses." A rule applied by
pattern-matching on "MUST" without reading polarity would convert those into halts and demand that a
correct entry be falsified in order to pass.

**The nine spec-defined sites.**

| Site | Condition | Clause | Halt mandated by |
|---|---|---|---|
| `:355` | exclusion cites a barrier outside the closed list | §6:229-231 | explicit MUST-halt |
| `:936` | a characteristic-core row dispositioned out | §6:222-224 | explicit, gate J |
| `:939` | the `:355` condition, re-checked at the gate | §6:229-231 | explicit, gate J |
| `:815` | a citation that does not resolve to the pinned bytes | §14:479-483 | explicit MUST-halt |
| `:821` | a core row whose stated reason misreads its clause | §14:494-499 | explicit MUST-halt |
| `:811` | a dispositioned row citing no census row | §14:479-483 + §6:255-258 | **by entailment**, see below |
| `:782` | a flag's quoted phrase absent from the pinned quote | §7:305-309 | explicit: the words must occur in the artifacts |
| `:788` | a flag's reason phrase absent from the recorded reason | §7:305-309 | same |
| `:1003` | RFC-COV-1 fails at freeze strength | §11:386-397 + §6 | gate L |

`:811` is the only row resting on entailment rather than quotation: a citation that does not exist
cannot be checked against the pinned bytes, and §6:255-258 forbids a gate condition to rest on an
input carrying no evidence. Read strictly it moves to `failed`. Flagged rather than smoothed over.

**Attribution correction.** Rev 3 and the harness findings both placed the citation-resolution
mandate in §7. It is **§14:479-483**, and the driver's own STOP message says so
(`rfc_to_implementation.py:815`, "Section 14 pins the source"). §7 carries the *delegation* of the
reading (§14:493-495); §14 carries the *check* and the halt.

**The three sites the harness could not classify. All resolve.**

- **`:967`** (stage K, authored roots do not typecheck). §7:283-286 requires validating a delegated
  output "against its declared shape." For a `.llmll` artifact, well-formedness under `llmll check`
  *is* that validation. Stage-contract-defined, `failed`.
- **`:866`** (stage H, feasibility not established). Stage-contract-defined per §6's stage-H note:
  §7 covers the stage, not the acceptance bar. Rev 4 concluded `failed` from that alone.
  **Corrected in Rev 5 to `stopped`** on a second axis §3.6 introduces; the clause-source reasoning
  is unchanged and is not what decides it.
- **`:1045`** (no holes to fill). §9 defines the fill protocol per hole and states nothing about an
  empty hole set, so §4:129's residual applies, `failed`. This is the correction §10 case 5 carries.

**Counts.** Of the 46 `require()` sites: 9 spec-defined (`stopped`, correct today); 26
delegated-output shape validation; 9 driver-internal invariants and tool failures; 2 pre-stage
argument validation, which fire before any stage exists and assign no stage status.

### 3.6 The second axis: `PartialThenHalt`, and the site it moves

Added in Rev 5. §3.5's rule classifies by **which clause defines the failed condition**, and it sorts
every halt into two of `Outcome`'s four constructors. The type has a third halt constructor, and it
is not decorative.

[`stage.llmll:10`](../../tools/llmll-driver/stage.llmll) declares
`(type Outcome (| ConditionUnmet) (| Errored) (| PartialThenHalt) (| Finished))`, and `record-outcome`
carries `[S4-PARTIAL]`, proving `PartialThenHalt → Stopped` with the source string
"driver-spec.txt sec 4 - wrote some artifacts then halted MUST be stopped". §4:146-147 is the clause.
§3.4 already records that Phase 3 constructs `ConditionUnmet` and `PartialThenHalt`, and §3.3 already
cites §4:146-147, so neither the clause nor the constructor is new to this proposal. What is new is
applying them to the 46-site classification, which §3.5 did not.

**The second axis.** §4:146-147 classifies by **what the stage had already written** when it halted,
independently of which clause defined the condition. The two axes are orthogonal and §3.5 carried
only the first.

**Measured**, over the write-before-`require()` ordering of every stage in
[`rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py):

| Post-write site | Clause-source axis | §4:146-147 axis | Agree |
|---|---|---|---|
| `:811`, `:815`, `:821` (G2, after the write at `:809`) | `stopped` | `stopped` | yes |
| `:936`, `:939` (J, after `:932`) | `stopped` | `stopped` | yes |
| `:1003` (L, after `:999`) | `stopped` | `stopped` | yes |
| `:866` (H, after `:864`) | **`failed`** | **`stopped`** | **no** |
| `:546` (E, after `:544`) | `failed` | not triggered | yes |

Six of the nine spec-defined sites are corroborated by a clause that played no part in selecting
them, and exactly one site is contradicted. That is the profile of an eliminative check rather than
of an agreement between two readings of the same evidence.

**Rev 10: this table's keys are STALE at HEAD, and it is not renumbered here.** The keys are line
numbers, which §3.5.1 forbids for §3.5's sites and which this table was left carrying. At `d15b2ff`,
`:809` is a `for` statement inside `_pinned_sources` rather than a write, and the two G2 conditions
the first row names (a colliding source key, and no pinned RFC text under the source directory) fire
**inside `_pinned_sources`, which G2 calls before writing anything of its own**. So the first row's
"post-write" premise does not hold at HEAD under its own citation. Re-deriving the table needs a
fresh census rather than a renumbering, and the census is owed work rather than a Rev 10 edit,
because guessing which sites moved is how the Rev 8 stamp went wrong. **What survives unrevised is
the argument**, not the arithmetic: two axes exist, they are orthogonal, and they disagree somewhere.

### 3.6.1 The second disagreeing site, and the rule that fits both

*(Added at Rev 10, measured. Finding F-18's sibling, F-19.)*

§3.6 claimed exactly one site of 46 has the axes disagreeing. **There are at least two, and they
resolve in opposite directions.** The second is stage D's `check_extraction` halt on **loop iteration
`b`**, and it is in sub-phase 4c's port surface.

Stage D is the **only agent-delegated stage declaring two outputs** (`:1513`), and it runs its
extractors in order (`:645`). `AgentRunner.run` returns only once the declared output exists
(`:331-334`), so on iteration `b` the halt lands with extractor A's `extraction.json` present
**and past `check_extraction`**, having been validated and rewritten at `:658`. §4:146's "wrote some
of its artifacts" is therefore satisfied by a **valid sibling**, which is a stronger condition than
the one §3.6:488-492 worried about: the presence-versus-validity ambiguity does not arise, because
under either reading a contract-meeting declared artifact exists.

**Measured at `d15b2ff`:** the reference records `failed` / `Errored`, detail naming `extraction-b`,
no clause field, exit 3, no traceback. The artifact-state axis says `stopped`. **The axes disagree
and the reference resolves to `failed`.**

This was a discriminating test with two live outcomes, so it eliminates rather than corroborates:
**the artifact-state-wins reading is refuted.** The rule that fits both sites is
**hold-the-existing-value**, which gives `stopped` at `:866` and `failed` at D, and §3.6 above reads
as though the artifact-state axis won at `:866` on the merits. It did not; it agreed with that site's
existing value, and at D the same axis disagrees with it.

**Why no census would have found this.** `:656` is **one source line with two artifact-state
dispositions**, depending on which iteration of `for tag in ("a", "b")` is executing. A per-site
census cannot represent that, which makes this the loop-granularity analogue of F-16's deferred
row-granularity limit. The cell is now pinned permanently by
`test_stage_D_records_failed_when_the_valid_sibling_is_already_written` and rig mode
`bad-extraction-b`; before Rev 10 nothing reached it, because `bad-extraction` corrupts whichever tag
runs first and tag `a` always runs first.

**`:546` is the discriminating case for the reading of "its artifacts."** Stage E writes
`reconcile.stdout.txt` at `:544` and then halts at `:546`, but the registry (`:1341-1342`) declares
only `SUMMARY.json` as its output. Under a **declared-output** reading the axis does not fire and
`:546` stays `failed`. Under an any-file-written reading it fires. **Settled: declared outputs**,
because that reading makes the rule computable from the registry rather than from filesystem
observation, and because a diagnostic dump is not an artifact the stage owes.

**Named ambiguity, not resolved by fiat.** §4:146 says "wrote **some** of its artifacts." Every
affected site wrote *all* of its declared outputs and then failed validation, which is not literally
"some." The reading that makes the clause operative is that "some" means "not none," and it is the
reading the driver already follows in six places. Recorded as a reading of a pinned source
(§14:473-474) rather than as a derivation.

**The divergence set is 37**, not 38: the two middle classes (35 sites) plus the three `AgentRunner`
raises, which are not `require()` calls (`:221` timeout, `:227` non-zero exit, `:230` declared output
absent), **minus `:866`**, which stays `stopped` and changes constructor rather than status. §3.1's
table disposes of the three raises; §3.5's rule disposes of 34; §3.6 disposes of `:866`.

**Recorded uncertainty.** `:866` now has two derivations pointing opposite ways: §3.5's clause-source
axis gives `failed`, §3.6's artifact-state axis gives `stopped`. driver-spec never states which
governs when they disagree, and §4:146-147 presents itself as an instance ("In particular") of
§4:145, which is about `complete` rather than about `stopped`, so it widens rather than instantiates
what it is attached to. The disjunctive reading is taken here. **The conservative action for the
Python-side repair is the same under both readings**: hold `:866` at `stopped`, which is its value
today, and move the other 37. If the disjunctive reading is later rejected, one site moves.

---

## 4. The run state is a sum over phases

The driver's state shape varies by stage: the wave carries a hole queue and two budgets that stage B
has no use for; stage B carries a prompt path the wave does not. Modelling that as one product
carrying every field is what forces a deep pair chain and makes a wrong-projection read typecheck.

The console `:step` state type S is unconstrained. `checkStepArity`
([`TypeCheck.hs:1712-1745`](../../compiler/src/LLMLL/TypeCheck.hs)) constrains the **parameter list
only**, and says so in its own docstring at `:1722-1727`; nothing imposes a shape on S. So this is a
data-modelling choice, not a harness limit. (Rev 6 citation repair: Rev 5 cited `:2161-2183`, which
at HEAD is an unrelated predicate check.)

**Settled encoding.** A pair whose first component is the run-common record (workdir, manifest path,
forced flag) and whose second is an n-arm sum over stage phases, each arm carrying only its own
components. Illustrative, not spec text:

```
(type Phase
  (| Sequencing int)                       ;; stage index
  (| Delegating (string, int))              ;; out-path, attempt
  (| Waving ((list string), (int, int))))   ;; queue, (semantic budget, protocol budget)
```

Maximum projection depth is two. `pSumArm`
([`Parser.hs:328-333`](../../compiler/src/LLMLL/Parser.hs)) parses `optional pType`, so a
constructor carries at most one payload; that costs a pair per arm, not a chain per field.
`XMOD-CTOR-1` is fixed at v0.14.82 ([`CHANGELOG.md:221`](../../CHANGELOG.md)), so an imported
sum constructor is constructible cross-module and a per-stage module split is viable.

**`STATE-PROD-1` is filed and its motivation is narrow.** N-ary constructor payloads
(`(| DS int (list string) int string)`) would carry the run-common record directly. It is an
ergonomics item, not a Phase 4 enabler, and Phase 4 does not wait on it. The strict-core question is
deliberately deferred: `LLMLL.md:963` already reflects a single-constructor product to
`(Pair2 s0 s1)` and an n-ary product is the same theory at wider arity, but Phase 4 needs the
construct only in `def-shell`.

**Dispatch.** `spine.llmll:760` closes its nineteen-state chain with nineteen parens. Flattening to
a literal-pattern `match` is available and is a hazard rather than a win; see §10 case 6. If taken,
the wildcard arm must produce a defined state transition, as a specified side condition rather than
engineer discretion.

**The manifest row schema is not uniform across outcomes, and 4a must reproduce the asymmetry.**
Measured at the four write sites. A complete row is `{status, kind, seconds, outputs}` with **no
`outcome` field** (`rfc_to_implementation.py:1950-1956`). The three halt rows are
`{status, detail, outcome}` plus `clause` on the stop path, with **no `kind` and no `seconds`**
(`:1909-1914`, `:1926-1930`, `:1942-1947`). The `Finished` arm of `Outcome` has no manifest string at
all, even though `stage.llmll:36` maps it to `Complete` alongside the other three.

The natural port emits `"outcome": "Finished"` on the complete row for uniformity, and that **breaks
clause 1a on T1**, the most frequent transition in any run, because α retains `outcome`. Stated here
as a specified decision rather than left as an accident for the engineer to rediscover: the
serialization of `Outcome` into a manifest row is total, and `Finished` maps to the absence of the
field.

---

## 5. The agent-invocation contract

`AgentRunner` (`rfc_to_implementation.py:171-239`) takes an operator-written shell template with
`{prompt}`, `{out}`, `{workdir}` under `shell=True`, and exports `LLMLL_CMD`,
`RFC_PIPELINE_PROMPT`, `RFC_PIPELINE_OUT` into the child environment. `wasi.proc.run` takes
`(executable, argv, cwd, stdout-path, stderr-path, timeout)` and is deliberately not a shell string:
the split makes the executable a syntactic constant a reader can enumerate
([`TypeCheck.hs:182-193`](../../compiler/src/LLMLL/TypeCheck.hs)). There is no env parameter.

1. **The template channel is not carried across.** Passing the operator's string to `/bin/sh -c`
   restores shell semantics through a granted binary and voids the auditability property
   `wasi.proc.run` was shaped to deliver. **Settled: `--agent-exe` plus repeatable `--agent-arg`,
   with `{prompt}`/`{out}`/`{workdir}` substituted per argument.** This changes the operator CLI, so
   it is a §8.1 retirement concern and belongs in the retirement note rather than in an operator's
   surprise.
2. **The env channel has one real consumer**, the stub agent at
   `test_rfc_pipeline_integration.py:57` and `:67`, which clause 1a puts on the critical path.
   **Settled: rewrite the stub to read argv; file `PROC-ENV-1` as named-not-scheduled.** An env
   parameter is authority-shaped surface (it is how `PATH` and credentials reach a child) and should
   not be added to satisfy a fixture.
3. **The timeout is already a value rather than a hang** (`TypeCheck.hs:189-191`, delivered as
   `RErr`), which is what makes §3's timeout disposition expressible.

---

## 6. driver-spec conformance: §7, and the four sections a truncated grep hid

§6.1 is §7, settled since Rev 2. §6.2 through §6.5 are new in Rev 5 and come from sweeping §8
through §15.4, the sections `grep -nE "^[0-9]*\.  [A-Z]"` never returned because §10 and up use a
single space after the numeral.

### 6.1 §7, the delegated-stage contract

§7 specifies what a delegated stage owes independently of how the Python driver implements it. Three
of its obligations are Phase 4 work and were not in the campaign's §Phase 4.

1. **Validation is mandatory, non-downgradable, non-skippable** (`:283-286`). `check_extraction` and
   `check_dispositioned` exist; §7 makes them a specification obligation rather than defensive
   coding and forbids the warning downgrade.
2. **Validators must not hardcode one subject's conventions** (`:288-291`): "a validator that
   hardcodes the values seen in one run will silently report emptiness on the next." This is a
   constraint on the port specifically. A validator written against the two committed runs is the
   shape §7 warns about, and it is the item most likely to be lost.
3. **Catalogue non-evaluation and the unrealisable entry** (`:313-322`). The agent produces the
   catalogue; the driver evaluates it. An entry declaring itself unrealisable stays in the
   denominator and counts as neither success nor failure. Stage N implements this
   (`rfc_to_implementation.py:1270-1277`); stage D's "extraction assigns NO disposition" is the same
   rule at a different stage and must be preserved rather than treated as an implementation accident.

**The citation clause is not a Phase 4 widening.** §7:296-303 requires the driver to check citations
against the pinned bytes, with an explicit non-contiguity rule. The obligation is on *the driver*,
and the driver discharges it in one place: `_audit_tokens`, `_span_coverage`, `_pinned_sources` and
`CITATION_RESOLVES_AT` all sit inside stage G2 (`:627-832`), placed before H by the registry comment
so a citation failure stops the run early, and §6:265-271 endorses that producer-plus-gate
architecture explicitly. The citing set is D and K in any case: `check_dispositioned` (`:343-361`)
requires `cid`, `disposition`, `class`, `barrier` and `reason` and requires no quote and no span, so
stage G's output does not cite the source document. Nothing widens `HTTP-GET-1` beyond the G2
limitation `spine.llmll:28-31` already records.

The non-contiguity rule is independently confirmed by measurement: a substring citation check fails
22 of 113 correct rows on the committed census. Phase 4 must not reintroduce a substring check.

**Stage H is specified; its acceptance bar is not (Rev 4).** `grep` over `driver-spec.txt` returns
zero hits for "feasibility" and "probe", and the harness leg concluded from that grep that stage H is
a stage the specification does not describe. The grep is right and the conclusion is too strong.
§7:313-316 covers it: "Where a delegated stage produces a catalogue of items for the driver to
evaluate, the agent MUST NOT perform that evaluation itself. The catalogue is the deliverable."
Stage H's agent writes `probes.json`, a catalogue, and the driver evaluates each entry by running
`verify` (`rfc_to_implementation.py:853-863`). That is the clause exactly, and it is the same clause
that covers stage N's mutant taxonomy including the unrealisable-entry rule.

What driver-spec does **not** define is stage H's acceptance condition (the probe verifies
body-faithfully **and** its mutant refutes). That bar is the driver's own, so `:866` is
stage-contract-defined on the clause-source axis. **Rev 5:** that settles which clause defines the
condition and no longer settles the status, which §3.6 decides on artifact state. **Consequence for
Phase 5 §15.4:** no special sentence is owed for stage H, which conforms to §7 as a delegated
catalogue stage. The disclosure owed is narrower: its acceptance bar is driver-defined and is not a
conformance claim.

### 6.2 §13 is stage O's specification, and stage O has no validator

Stage O (`stage_O_writeup`, kind `agent`, declared output `REPORT.md`, registry `:1370`) is the
**only delegated stage in the driver with zero `require()` sites**. Measured: `:1298-1305` is a
docstring and a body that runs the agent. §7:283-286 makes validating a delegated output mandatory,
non-downgradable and non-skippable, which is §6.1 item 1, and for this one stage there is nothing to
downgrade because nothing exists. Neither this proposal through Rev 4 nor the harness findings named
it; the harness leg exercised transitions rather than stage bodies.

driver-spec §13 carries eight MUSTs over the report. Three of them are already restated inside
`stage_O_writeup`'s docstring, which reaches the agent as prompt text and is checked by nothing.

**The split is drawn by §15.1:512-515, not by decidability.** §15.1 characterises its tier as
"properties of sequencing and state over enumerated statuses and bounded counters" and enumerates
what it covers; reporting is absent from that enumeration. That is the specification drawing the
line itself, which is firmer ground than an argument about what a validator could decide.

- **Mechanizable, one clause.** §13:443-446, the full perturbation result including undetected
  perturbations. Stage N holds the reference set: `kill-matrix.json` is written at `:1291` and keyed
  by `name`, with `unwritable` rows retained and survivors logged rather than dropped
  (`:1273-1277`, `:1292-1295`). The check is a set difference over that key.
- **Disclosure-only, seven clauses.** §13:433-435 (lead with coverage and the core count, not the
  raw carried/total ratio), §13:437 (state what is not claimed), §13:439-441 (disclose every assumed
  step), §13:448-450 (MUST NOT characterise perturbation as validating contracts), §13:452-454
  (MUST NOT claim verification prevented an error absent a comparison capable of showing it).

**The check is named for what it decides.** It is the **perturbation-omission check**, not a §13:446
conformance check. A report that lists a survivor and dismisses it passes the set difference while
violating "MUST be resolved rather than omitted." §13:448-450 states this asymmetry about
perturbation evidence generally, and the same discipline applies to the oracle that checks the
report. Passing it does not discharge §13:446 and the phase close must not say that it does.

**§13:439-441 is a trust-channel disclosure, not a completeness check.** It names "any inference
from a per-step property to a property of all executions," which is the induction step over the
transition relation, and `stage_O_writeup:1301-1303` already identifies it as "a trace induction
outside the decidable fragment." There is no set for the driver to difference against: the statements
§7 owes live in this document and in the phase gap inventory, both design-doc artifacts. Grepped:
the driver holds no assumed-step inventory.

**Disposition.** Stage O writes its declared output, then the validator runs, then a halt occurs.
That is the house ordering of all five stages that validate after writing, so §3.6's axis applies
and the halt records `stopped` as `PartialThenHalt`. It does **not** qualify under §3.5's rule:
§13:446 mandates *resolution*, not halting, and §13 is not a §6 gate, so the second conjunct fails.
The nine-site table is unaffected; sub-phase 4f adds one construction site on §3.6's axis.

### 6.3 §12: `--status` is a specification section, not operator plumbing

`show_status` (`:1541-1640`) already distinguishes all four §4 statuses at `:1613-1632`, with
§4:133-137's rationale quoted in the comment. §12:405-428 is therefore satisfied by the Python
reference, and the LLMLL port currently plans to drop it.

**§12:428 corroborates §3 by entailment.** "The report MUST distinguish the four stage statuses of
section 4 from one another" reaches the recording only by entailment: a report that can never emit
`failed` for a deliberate halt does not operatively distinguish four statuses. The renderer conforms;
what does not is the recording, under §4:129-131. Flagged as entailment rather than quotation, on the
same standard §3.5 applies to `:811`.

**§12:419-420 is what `FS-STAT-1` blocks**, since it requires advancement to be judged from change to
any artifact under the workdir and not from the driver's log. That needs a file mtime.

### 6.4 §8: isolation is a MUST, and its re-check facility is a spec obligation

§8:330-332 requires the driver to "re-check isolation after a run and report any file in an agent's
directory that was not among its declared inputs." `audit_blindness` (`:1644-1668`) implements it.
Like `--status`, it is a specification obligation the port defers as operator surface.

§8:336-337 is the one that changes a gap's severity: where an agent needs a copy of the subject to
check its own work, "the copy MUST be the original, unmodified subject." A copy that cannot
round-trip non-UTF-8 bytes is not the original. `FS-COPY-1` is therefore conformance, not the
ergonomics §14 recorded through Rev 4.

### 6.5 §10: the ordering is a shell obligation, and the contention refutation does not reach it

§10:371-373 requires that the token not be held while the agent works, that the driver release once
the agent has what it needs, and that it obtain a **fresh** token at submission. `_apply:1176-1186`
implements exactly that under one lock; the rebind at `:1181` is what makes the request at `:1182`
carry the fresh token rather than the released one. §10:381 requires that an unreleasable token not
leave the hole permanently unavailable, and `_release:1149-1153` names that failure mode.

The first professor round refuted the contention witness as unreachable under a serial wave. That
refutation is correct and **confined to §10:375-379**. §10:371-373 and §10:381 are reachable
serially and this proposal's §10 case 1 addresses neither.

**Open for the engineer, not settled here.** `token.llmll:9` declares
`(def token-during [p: Phase] -> TokenState)`, a total function from phase to token state. That
shape proves a phase-indexed invariant and does not obviously prove an *ordering*. If it does not,
§10:371-373's ordering is a shell obligation and §7 owes a fourth statement. Confirm against the
module body and `crux-token-held-across-call.llmll` before 4e.

---

## 7. The abstraction function per activated proved core

`fill.next-error-budget` is proved over an abstract `contention: bool`. In the port that bool is
produced by reading `llmll patch`'s stderr from a file and testing it for a substring, mirroring
`_apply`'s `if "stale" not in err and "PatchAuthError" not in err` (`:1192-1194`). The theorem is
about the abstraction; the classification is the abstraction function; and if the compiler's
rejection wording changes, contention is reclassified as error and spends a budget §9 says
contention must not spend, with every proof still green and every crux still refuting.

LLMLL has no channel for this obligation and this proposal does not add one. String structure is
outside Σ_auto (`LLMLL.md §5.3.5`) and that is a settled scope decision. What Phase 4 owes is the
statement, per activated core, of what the shell computes and hands across the seam. The precedent
is `spine.llmll:71-80`, which discloses that stage E's four lexeme comparisons arrive as booleans the
shell computed and are not proved there.

**Two statements are owed at sub-phase 4a**, and Rev 5 scheduled one of them two sub-phases late.

- **`skip.may-skip`.** `artifacts-present` and `digests-match` are booleans the shell computes
  (`rfc_to_implementation.py:1877`, `:1880-1886`). One decision inside them is unproved and invisible
  at the proved boundary: a **recorded digest of `None` is treated as a mismatch** (`:1885`, with the
  reason at `:1883-1884`), so an artifact whose integrity was never recorded arrives at `may-skip`
  indistinguishable from one that changed. A second: an unknown `status` string parses to
  `manifest-complete = false` (`:1876`), which is conformant with §5:189-191 but is a shell reading
  of a spec sentence rather than a proved mapping. Rev 5 owed no statement for this core at all.
  **A third, added at Rev 8 and measured by the 4a port rather than predicted: in the LLMLL port the
  two booleans are not independent.** `wasi.fs.sha256` collapses presence and digest into one
  command, returning `RErr` for an absent path and `RText` for a present one, so an absent artifact
  falsifies `digests-match` as well as `artifacts-present`. `may-skip` is proved over two independent
  conjuncts and the shell hands it two that are not. **This was not a disclosure gap only; it was a
  live defect in the port's own test cover.** Hardcoding `artifacts-present` to true left all fifteen
  4a scenarios green, because condition (c) masked condition (b) on the one cell that exists to
  witness (b) alone. The port now gates `digests-match` the way the reference does and the same
  perturbation reddens T7 alone. **The reference does not share the defect**, and that was
  established by mutation rather than by reading: it computes its digest loop under the guard
  `if recorded and artifacts:` (`rfc_to_implementation.py:1936`), so on an absent artifact (c) is
  vacuously satisfied rather than falsified. The two implementations reach the same decision through
  opposite mechanisms, which is exactly the kind of difference clause 1b exists to catch.
- **`stage.record-outcome`.** The `Outcome` constructor is chosen by the shell from §3.1's four-way
  disposition. Unproved, and it is the discrimination the Python driver lost. **Rev 6 moves this from
  4e to 4a**, because §9 activates the core at 4a and a disclosure that lags its own activation
  understates the gap inventory at the moment it is first read.

**Two statements are owed at sub-phase 4e:**

- **`fill.next-error-budget` / `fill.is-finding`.** `contention` is a substring test over
  `llmll patch`'s stderr. Unproved, and the wording is a compiler-internal string with no stability
  contract.
- **`fill.fill-accepted`.** `verifies`, `body-faithful` and `termination-proved` are substring and
  set-membership tests over `llmll verify`'s stdout, mirroring `_faithful` (`:1241-1244`) and
  `_fallbacks` (`:884-887`). Unproved. `--strict-verified-core` is deliberately not used, per §9's
  own instruction that the criterion be evaluated for the function being filled.

These belong in the phase's gap inventory, in the same category as the FFI count and the effect
authority report.

**Rev 4 tightening.** §3.5 makes the third of these **enumerable rather than open**. Before it, "the
shell chooses the `Outcome` constructor" was an unbounded disclosure. Now it is a 46-row table plus a
rule that classifies a site the table does not list. The abstraction function is still unproved and
still outside Σ_auto, but it is auditable, and a reviewer can check a call site against the rule
rather than against an intention. The first two statements (contention, and the fill-acceptance
triple) remain open: both are substring tests over compiler output whose wording carries no
stability contract.

**Rev 5 corrections and additions.**

- The `stage.record-outcome` statement now covers **three** halt constructors rather than two:
  nine `ConditionUnmet`, one `PartialThenHalt` (`:866`, plus stage O's site at 4f), and the rest
  `Errored`. §3.6 gives the second axis and the measurement behind it.
- **A fifth statement is owed at 4f**, for the perturbation-omission check of §6.2. The set
  difference runs over identifiers read as strings from stage N's output, so it is shell-side and
  outside Σ_auto for the same reason the other four are. Phase 4 must **not** intern those
  identifiers as a nullary enum to move the check into QF-LIA: the identifier set is authored by an
  agent per run and is not a closed vocabulary.
- **A further statement may be owed at 4e**, for §10:371-373's token ordering, conditional on the
  `token.llmll` read §6.5 routes to the engineer. Named here so its absence is a decision rather
  than an omission.

**Rev 6 addition, from the fourth professor round.** A statement is owed for
`liveness.advancing`'s **second** precondition conjunct, `log-age >= newest-artifact-age`
([`liveness.llmll:7-9`](../../tools/llmll-driver/liveness.llmll)), whenever `FS-STAT-1` lands. It
relates two separate builtin calls, so no builtin signature can discharge it and the clamped-age
construction §14 now proposes reaches only the first conjunct. It is shell-side for the same reason
the others are, and it is the one owed statement whose failure mode is a **precondition violation**
rather than a wrong answer.

---

## 8. `wasi.fs.copy`

Pinning UTF-8 on `wasi.fs.read` stops the crash of §10 case 7; it does not make a read-then-write
copy byte-faithful, because a file that is not valid UTF-8 still cannot round-trip through `RText`
and `Response` has no bytes arm by design. These are two findings and the fold loses the better fix.

**Signature:** `wasi.fs.copy : string -> string -> Command`, delivering `RNone`.

**Against the four-part admissibility rule**
([`effect-response-channel-proposal.md:433-441`](effect-response-channel-proposal.md)):
non-redundant as an operation while requiring no new arm; no fragment widening, `RNone` being
nullary; rule 3 satisfied maximally, since the payload never leaves the filesystem; and it names no
capability in an arm, adding none.

**Label mapping:** `Caps {EFsRead, EFsWrite}`, on the precedent of
`wasi.fs.sha256 → Caps {EFsRead, ECrypto}`
([`ObligationAssembly.hs:448`](../../compiler/src/LLMLL/ObligationAssembly.hs)). No seventh label,
so the closed six-label catalog is untouched, matching how `wasi.fs.list` was absorbed.

**Freeze:** lifted at v0.11 ([`compiler-team-roadmap.md:261`](../compiler-team-roadmap.md)). The
soundness argument required by the lifted-exclusions note is the rule check above: the operation
grants no authority the existing read-and-write pair does not already grant.

---

## 9. Sub-phases

| | Lands | Proved cores activated | Acceptance |
|---|---|---|---|
| **4a** | Sequencer, manifest, resume gate, **two halt channels**. No stage bodies. | `skip.may-skip`, `stage.record-outcome` (all four `Outcome` arms) | The **eleven-cell** cover of §2.3 passes, T7 included; §10 cases 16, 17 and 18, the three corrupt-manifest shapes, are handled as decisions rather than crashes; §4's manifest-row asymmetry is reproduced; §7's two 4a statements are written. **All eleven cells and all three manifest shapes have a Python-side test as of Rev 7**, so the port has a red/green target rather than a description |
| **4b** | B, C, I, and §6's validation obligations as a shared facility | none new | A delegated output that is absent, malformed, or subject-hardcoded fails the stage and is never skipped. **Every reachable halt in B, C and I records `failed`/`Errored`; a `stopped` anywhere in 4b is wrong by construction.** Two unguarded reads are ported as decisions per §9.1, and stage I's absent validator is disclosed, not invented |
| **4c** | D, F, G | none new | **Replaced at Rev 10; the prior clause was measured unsatisfiable (§9.2 item 3).** The already-ported downstream stages **run** over 4c's own output rather than reproducing pinned values over it: stage E completes over D's two staged extractions, and G2 and gate J complete over G's own dispositioned inventory. D's two declared outputs both exist and satisfy their stage contract; a defect in the second extractor records `failed` with the first's output intact (§3.6.1) |
| **4d** | H, K, N | none new | Probe-verifies / mutant-refutes polarity reproduces; stage N retains unrealisable entries in the denominator |
| **4e** | M, serial, **with contention injected under clause 1a** | `fill.fill-accepted`, `fill.next-error-budget`, `fill.is-finding`, `token.token-during` | Both retry budgets fire and are separately counted; a hole exhausting its semantic budget is a finding and never hinted; §7's statements are written, and §6.5's `token.llmll` read is resolved either way |
| **4f** | O **with its §13 validator**, phase close, gap inventory | none new | Clauses 1a, 1b and 2; the perturbation-omission check of §6.2 fires on an omitted survivor and records `PartialThenHalt`; the seven disclosure-only §13 clauses are listed as unchecked in the phase close |

### 9.1 Three settlements sub-phase 4b needed and Rev 8 did not have

*(Added at Rev 9, from the census that re-measured §3.5. All three are decisions, not observations.)*

**1. The two unguarded reads are ported as decisions, not reproduced as crashes.** `read_json` on
`PROVENANCE.json` in stage B and `read_text` on stage B's `scope.md` in stage I are both unguarded
in the reference, so an absent or malformed file tracebacks out at exit 1. **The port has no host
exception to fall through**, so it cannot reproduce the behaviour even if that were wanted. Both are
guarded and record `failed`/`Errored` at exit 3: neither is a MUST over artifact content identifiable
by clause, so §3.5's rule gives `failed` directly. **This is a §3 divergence in the improving
direction and the precedent is already set**, `read_manifest` having taken exactly this route at 4a
(§10 cases 16 through 18). A crash is not a decision, and §4:141-143 is the clause that says so.

**2. Stage I has no validator either, so §6.2's "stage O is the ONLY delegated stage with no
validator" is false.** Measured: stage I holds zero halt calls, and a 0-byte and a 28-byte
`PRE-REGISTRATION.md` both record `complete` at exit 0. **4b ports that faithfully and discloses
it; it does not invent a validator.** The reasoning is §12's, applied to a second stage: a validator
where the reference has none is new behaviour and must not ride in on a port. Stage I joins stage O
in the F-7 disposition and lands at 4f.

**3. 4b needs no `stopped` site at all.** Every reachable halt in B, C and I records
`failed`/`Errored`. The port needs no `ConditionUnmet` and no `PartialThenHalt` construction in this
sub-phase, and a site that comes out `stopped` is wrong by construction rather than merely
suspicious. That is a sharper acceptance check than §9's row alone provides.

### 9.2 Five settlements sub-phase 4c needs

*(Added at Rev 10. Items 1, 3 and 4 rest on measurements at `d15b2ff`; item 2 is a reading of a
proved postcondition; item 5 is a disclosure.)*

**1. Stage D's iteration-`b` halt records `failed`, and 4c is not 4b.** §9.1 item 3 held that a
`stopped` anywhere in 4b is wrong by construction. **That does not carry into 4c as a general rule**,
because its premise was that each of B, C and I declares exactly one output, so a failing verdict
implies no valid declared artifact exists. D declares two (`:1513`) and breaks the premise. The
disposition is nonetheless `failed`, measured, per §3.6.1, so **4c constructs no `PartialThenHalt`
either**; the conclusion survives while the reason for it changes. An engineer must not re-derive
"single output" from 4b and must not read the shared conclusion as licence to skip the sibling case.

**2. `[V7-NO-PARTIAL]` and `[V7-ONLY-TWO]` are sound for 4c unchanged, and 4c must not widen them.**
`verdict-outcome` proves `(=> (not (= v Passed)) (not (= result PartialThenHalt)))`
([`validate.llmll:108-109`](../../tools/llmll-driver/validate.llmll)) and
`(or (= result Errored) (= result Finished))` (`:111-112`), both sourced to §9.1 item 3. The natural
worry is that D's second declared output invalidates them. It does not: **`verdict-of` takes no
artifact set** (`:129`), so the sibling-state question is not a fact about the output under
validation and lies outside what these posts quantify over. Where a sibling-sensitive disposition is
ever needed it belongs in a per-stage wrapper at the call site, never inside the shared facility, on
exactly the reasoning that put the facility there. F-19 confirms this empirically rather than
leaving it as an argument: the reference records `Errored`, which is what `[V7-MANDATORY]` maps a
failing verdict to, so 4c extends the facility with **no change to any proved post**.

**3. The 4c acceptance clause is replaced, its predecessor having been measured unsatisfiable.**
"Stage E's Phase 3 pins reproduce over D's own output" fails under both available readings, which is
§1.2's defect at sub-phase granularity. Over the **committed** pair at
`experiments/rfc-swarm/data/` the seven pins hold 7 for 7
([`spine.llmll:88-98`](../../tools/llmll-driver/spine.llmll)); over **stub-D** output they hold 0 for
7, and the two Jaccard pins are unaddressable rather than wrong-valued, the stub's source being
`spec.txt` so the `line_coverage` key is `SPEC` while `jaccard-of` projects `RFC1350` and `RFC1123`
(`:328`, `:331`) and gets `MISSING`. Over **live** output the pins are agreement statistics between
two stochastic extractions and cannot be pinned at all. The surviving reading, over the committed
pair, is what Phase 3 established and does not exercise D. **The replacement inverts the direction of
the check**: rather than pinned values reproducing over 4c's output, the already-ported downstream
stages **run to completion** over it. That is satisfiable under stub and live alike, and the rig
already demonstrates the shape end to end for the Python driver.

**The pins themselves are not weakened and not moved.** They remain a Phase 3 check over the
committed pair, and `[E-NOVACUOUS]` still refutes a stage E that passes on a divergent row count.
What changes is only that they stop being asked to serve as 4c's acceptance.

**4. Five unguarded reads, and one of them already has a guarded reader.** §9.1 item 1 settled the
rule for two; the population at HEAD is five: `:642` (`rubric.md`, stage D), `:710`
(`read_json(merged)["normative"]`, stage F, an unguarded read **and** an unguarded key index),
`:731` (`core.json`, stage G), `:737-739` (`extraction-a.json`, stage G) and `:742` (`scope.md`,
stage G). None is a MUST over artifact content identifiable by clause, so §3.5's rule gives `failed`
directly and the `read_manifest` precedent applies unchanged. **`:742` reads the same `scope.md`
stage I reads, which 4b already guards**, so 4c reuses that reader; a second one would be the
near-copy §9 asked the shared facility to prevent.

Also settled here, from F-20: the tolerant `core["core_ids"] if isinstance(core, dict) else core` at
`:713` and `:732` has **no producer in the tree**. The stub emits a dict, the sole committed artifact
`experiments/rfc-swarm/runs/rfc4648/core.json` is a dict, and the stage-F prompt template's own
worked example is a dict. The arm is **dead in-tree, which is not the same as unreachable**, a live
agent being shown an example rather than constrained by a schema. The port narrows to the dict shape
as a total predicate over what the reader indexes and **rejects a bare list with `failed`** rather
than accepting it silently, on 4a's corrupt-manifest precedent. Whether a live agent ever emits a
bare list is a null result at n=0 live runs.

**5. The B-side extraction has no downstream consumer, and the port reproduces that.** A reference
finding, recorded rather than repaired. Stage E's docstring says the script "reports them and stops
if they are unadjudicated" (`:676-678`) and **it does not stop**: `reconcile.py`'s only non-zero exit
is a missing `source` field on every row
([`reconcile.py:93`](../../experiments/rfc-swarm/tools/reconcile.py)), and unmatched rows are
reported and printed (`:160-165`). Stage E's own guard is `require(rc.returncode == 0)` (`:685`),
which any volume of disagreement passes. Downstream, F (`:706`), G (`:739`) and G2 (`:852`) all read
`extraction-a.json`, so **the B-side inventory is written, copied, reconciled, counted, and then read
by nothing**. The `(1, 10)` disagreement this port pins is inert in the pipeline that produces it.

The port's disposition is §9.1's: **reproduce, disclose, invent no merge.** A port that fed the
reconciled inventory to F would be new behaviour riding in on a port, the same category as a
validator where the reference has none. One naming consequence: stage F's local `merged` (`:706`)
points at extractor A's unmerged output, and **the port must not carry that name into a `def`**, or
the identifier will assert something the data does not support.

---

**4e is the phase.** It is where three of the six proved modules acquire their first caller.

**`liveness.advancing` gets no caller, and the reason is a filed gap.** Its precondition is over
artifact ages in seconds and there is no `wasi.fs.stat`: `wasi.clock.monotonic` reports nanoseconds
since an unspecified epoch and nothing exposes a file mtime. **Rev 6, fourth professor round: an
mtime would not close this, and Rev 5's routing note said it would.** `advancing` takes
`newest-artifact-age: int` in seconds (`liveness.llmll:6`), and producing an age from an mtime needs
a wall clock on the mtime's epoch, which `monotonic` explicitly is not. The re-scoped capability is
in §14. Filed as `FS-STAT-1`. It does not block
Phase 4, the campaign's §5 item 3 deferring the operator surface to the retirement step, but the
phase reports that one of the six proved modules has no callable data source rather than leaving a
reader to infer it was forgotten.

**Rev 5 correction to that paragraph's framing.** "Operator plumbing" is the wrong category. §12 is
a specification section and §8:330-332 is a MUST, so deferring `--status` and `audit_blindness`
defers **conformance**, and both are implemented and conformant in the Python reference. The
deferral is a scope decision the campaign is entitled to make; what it is not entitled to do is
leave it undisclosed. §15.1:504-505 is the governing clause: "An implementation MUST place every
obligation in exactly one of three tiers, and MUST be able to report which." *Every* obligation, not
every claimed one, so a deferred §12 obligation must still be tiered and reportable. Neither
§15:547 (which constrains obligations a claim "claims to meet") nor §13:437 (which governs the run's
report rather than the phase's conformance claim) reaches this.

The gap is also not where it first appears. §15.1:511 requires the proved-tier obligations to be
discharged by proof over all inputs; `liveness.llmll.verified.json` exists, so **that obligation is
discharged**. What is missing is the effectful surface that would feed the proved predicate, and
§15.2:522-524 requires effectful operations to be reached "only through a declared capability or a
named interface declared in the program itself." A capability that does not exist cannot be
declared. So: §15.1:511 satisfied, §15.2:522-524 is where the gap sits, §12:405-428 is what
consequently cannot be met.

---

## 10. Edge cases and degenerate inputs

**1. Contention followed by a wrong body.** *(This case was unsatisfiable in Rev 1 and is the
reason §9 injects contention.)*

Under a serial wave there is one writer, `_apply` re-checkouts under the lock immediately before
patching, and nothing can invalidate the brief in between, so `contention = true` never fires. The
campaign's claim that "a serial wave exercises the token discipline `token.llmll` proves just as
well" (§Phase 4) is **refuted, not qualified**: the proofs are unaffected and hold over all inputs,
but the running program never supplies the input that distinguishes the branches.

**Injection, minimal and without concurrency.** The stub `llmll` under clause 1a rejects the *n*th
`patch` with `PatchAuthError: obligation context is stale`, which drives `_apply`'s retry predicate
directly (`:1192-1194`). No second writer, no tree mutation.
Concrete: budget 3; patch 1 rejected stale, so `(next-error-budget 3 true) = 3`; patch 2 accepted and
`_verify_fn` fails, so `(next-error-budget 3 false) = 2`; `(is-finding 2 true) = false`.
Other polarity: `(next-error-budget 1 false) = 0`; `(is-finding 0 true) = true`, recorded a finding,
routed, never hinted.
Channel: **contract, proved**, `[S9-SEPARATE]` and `[S9-NOT-FINDING]`
([`fill.llmll:20-22`, `:31-32`](../../tools/llmll-driver/fill.llmll)).
**Under clause 2 the branch stays unreachable**, and the live run's gap inventory says so.

**2. A delegated output present but malformed.** Stage D returns `extraction.json` with a row
missing `line_start`. Validation rejects; the shell constructs `Errored`; `record-outcome` yields
`Failed`; the stage re-runs on resume per §5:196-197.
Channel: **contract, proved for the mapping; unproved for the constructor choice** (§7).

**3. Declared output absent, agent exit 0.** `failed`, per §3.1 and §7:279's "Silence is not
success," independent of exit status.
Channel: **contract.**
**Rev 7: the reference already does this, measured.**
[`rfc_to_implementation.py:331-334`](../../scripts/rfc_to_implementation.py) raises `StageFailure`
inside `AgentRunner.run`, so the port is matching existing behaviour rather than diverging from it.
Pinned by `test_an_agent_that_exits_zero_without_writing_records_failed`, which passes with and
without this session's changes and is there to keep it that way. Covers the eleven agent-delegated
stages; the two mechanical and three gate stages have no generic equivalent (§2.3 finding 3).

**4. Declared output present and valid, agent exit non-zero.** The stage is **complete**; the exit
code is recorded as manifest detail; no halt occurs and §4 is not reached.
Channel: **spec-directed**, §7:279.

**5. Zero holes in `roots.ast.json`. CORRECTED in Rev 4; the Rev 3 disposition was wrong.**
Rev 3 said the stage halts as `ConditionUnmet` and records `stopped`, "'no holes to fill' being a
condition the pipeline defines (`:1047`)". That citation is `rfc_to_implementation.py`, the driver's
own source, and §3.2's criterion requires the authority to be driver-spec. §9 defines the fill
protocol per hole and carries no clause about an empty hole set, so §4:129's residual applies.
Expected: the shell constructs `Errored` and the stage records **`failed`**, detail naming the empty
hole set.
Channel: **contract, proved for the mapping** (`[S4-FAILED]`, `[S4-NOT-STOPPED]`); the constructor
choice is unproved per §7.
This is the third instance of the error shape §3.3 records twice, and the first that originated in
this proposal rather than being inherited. Reachable as a witness today: the stub `llmll`'s
`build --emit` emits one hole, so emitting zero is a one-line fixture change.

**6. A `match` mixing a constructor arm with literal arms and no wildcard.**
`emitMatch` inserts `; _ -> error "non-exhaustive match"` when no arm is a wildcard or variable and
no arm is a constructor pattern ([`CodegenHs.hs:1347-1349`](../../compiler/src/LLMLL/CodegenHs.hs)),
so a pure literal match fails through an emitter-inserted `error` call rather than through GHC's
pattern-match exception. Either way the exception is raised inside a `Command`, which is the
crash-freedom hazard `CodegenHs.hs:178` names for `wasi.fs.delete`, so the remedy is not "add a
wildcard" but "the wildcard arm must produce a defined state transition."
A narrower hole sits beside it: `isAdtExhaustive = not (null ctorNames)` (`:1344`) suppresses the
catch-all whenever any arm is a constructor pattern, and that ground fails when a literal arm is
present. `checkExhaustive`
([`TypeCheck.hs:2255-2281`](../../compiler/src/LLMLL/TypeCheck.hs)) fires for `TSumType`, `TResult`
and `TBool` only, and its own docstring at `:2256-2257` says so. **Precondition:** a literal arm
against a sum-typed or `Result`-typed scrutinee is type-incompatible and draws `tcWarn`
(`TypeCheck.hs:2326-2332`), so the entry condition is a program that ships past a warning.
Channel: **spec is silent (gap, flag).** File with the precondition in the row text; it is a general
crash-freedom hole and should not be discovered by Phase 4. Tagged `MATCH-CATCHALL-1` in §14.
**Rev 6 citation repair: all four of this case's Rev 5 citations were stale at HEAD**, and two of
them landed in unrelated functions. This case is the sole evidence for the row §14 asks doc-lead to
file, so the row would have inherited them.

**7. `roots.ast.json` carrying a non-ASCII byte under a C locale.** The wave reads and rewrites this
file on every attempt, so the exposure is per-attempt.
Channel: **spec is silent (gap, flag).** `FS-ENCODING-1`, **shipped v0.14.84** (`82a0772`).
**Rev 6 correction: this case stated the mechanism wrong, and the release that fixed it measured the
error.** Rev 5 said `wasi.fs.read` is `readFile`, locale-decoded, "and throws," citing
`CodegenHs.hs:533-535`, which at HEAD is the `FS-COPY-1` preamble. Nothing threw:
`llmll_publish_io`'s `try` plus the existing `evaluate` already made the failure a value, so the
defect was **availability rather than crash-freedom**, and a gate asserting the absence of a
traceback would have passed before and after. The bodies now pin `utf8` on an explicit handle
(`CodegenHs.hs:577-590`). This is the second time a case in this section has been wrong about a
mechanism while right about the defect; §3.3 records the pattern.

**8. A delegated output citing a span with an elided quote.** An extraction row quoting `"A ... B"`
against a span containing both resolves. A contiguous-substring test rejects it.
Channel: **contract on the validator, unproved** (string structure outside Σ_auto). §7's
non-contiguity clause is normative and the measurement confirms it independently.

**9. A `patch` rejection whose stderr wording changed.** The shell classifies `contention = false`,
`next-error-budget` spends an attempt, and after three such rejections `is-finding` reports a finding
for a hole no agent got wrong.
Channel: **spec is silent, intentionally.** Every contract clause discharges correctly; the defect
is entirely in the abstraction function. This is §7's witness and it is invisible to every channel
the project has.

**10. Positive witness for §3.6's axis.** Stage H's agent writes a catalogue of three probes. The
driver evaluates each, appends to `results`, writes its declared output `feasibility.json` at `:864`,
computes `bad = ["probe-2"]`, and halts at `:866`. Expected: the shell constructs `PartialThenHalt`;
`record-outcome` yields `Stopped`; detail names §4:146-147. Under Rev 4's rule it would have
constructed `Errored` and recorded `failed`. This is the one site in the divergence set where the
two axes disagree, and it is the concrete firing input for the new axis rather than a description of
when it would fire.
Channel: **contract, proved for the mapping** (`[S4-PARTIAL]`); the constructor choice is unproved
per §7. Citation: registry `:1351-1352`; `rfc_to_implementation.py:864-869`.

**11. Negative witness, guarding §3.6 against over-fire.** Stage M halts at `:1045` on an empty hole
set. Its declared outputs are written at `:1099`, which has not run. Expected: §3.6's axis does not
fire; `Errored`; `failed`; unchanged from case 5. Without this case the axis reads as converting
every stage-contract failure to `stopped`.
Channel: **contract.** Citation: registry `:1366-1367`; `rfc_to_implementation.py:1045`, `:1099`.

**12. The discriminating case for "its artifacts."** Stage E writes `reconcile.stdout.txt` at `:544`,
then halts at `:546`. The registry declares only `SUMMARY.json` (`:1341-1342`). Expected under the
settled declared-output reading: the axis does not fire and `:546` stays `failed`. Under an
any-file-written reading it would fire and the site would move. Stated because the two readings
differ on exactly this site and the choice is otherwise invisible.
Channel: **contract.** Citation: registry `:1341-1342`.

**13. Positive witness for the perturbation-omission check.** Stage N's kill matrix holds a row
`mut-07` with `verdict: SAFE` and `good_twin: false`, which `:1292-1293` classifies a survivor. Stage
O's agent writes a report whose perturbation table lists `mut-01` through `mut-06`. The set
difference over the `name` key is `{mut-07}`, non-empty; the run halts after the report is on disk;
`PartialThenHalt`; `stopped`; detail naming §13:443-446. The guard is satisfiable because an omitted
undetected perturbation is the exact failure §13:444-446 was written against.
Channel: **contract for the mapping, shell-side for the predicate** (§7's fifth statement).
Citation: `rfc_to_implementation.py:1291-1295`; driver-spec §13:443-446.

**14. The omission check passes on a dismissive report.** The kill matrix holds `mut-07` as a
survivor; the report lists `mut-07` and calls it out of scope. The set difference is empty and the
check passes, while §13:446's "resolved rather than omitted" is violated.
Channel: **spec is silent (intentional).** The check decides omission and is strictly weaker than the
clause it is named after, which is why §6.2 names it for what it decides. driver-spec states the same
asymmetry about perturbation evidence at §13:448-450, and it applies to the oracle as much as to the
contracts.

**15. Positive witness for T7, and the cell 4a's acceptance turns on. EXECUTED in Rev 7.** Run stages
`A,B,C` to completion; delete stage B's declared output; resume with the same workdir and no
`--force`. `may-skip` receives `manifest-complete = true`, `artifacts-present = false`, so
`[S5-SKIP]`'s contrapositive forces `result = false` and B runs.
**Measured:** B ran and rewrote its output, printed no reason line of any kind, and A and C skipped
normally, so the check did not disable resumption. Harness findings F-9.
**Assert the decision, not the silence.** The rig's established idiom for "this stage re-ran" is its
own log line, `stage {key} [{kind}] {name}` (`rfc_to_implementation.py:1897`), which
`test_a_completed_stage_is_still_skipped_on_resume:458` already asserts in the negative for the skip
case. T7's test asserts the positive of that same line. It does **not** assert that no reason line
appears: pinning the absence of prose that does not yet exist breaks on the next diagnostic anyone
adds, and §5 neither requires nor forbids a report here.
Channel: **contract, proved** (`[S5-SKIP]`, `skip.llmll:19-21`). The reason-line question is **spec is
silent (intentional)**, §5 attaching a report obligation to T6 and T8 only.
*Rev 5 instructed the port to reproduce the reference's silence. **Withdrawn in Rev 6.*** The argument
was that a reason line is a clause-1a divergence, and §2.1 defines clause 1a's observable as the
manifest, which does not include standard output. The instruction contradicted the section it cited.

**16. A truncated `MANIFEST.json` on resume.** Zero-length or half-written JSON in the workdir.
Before Rev 7's repair: `read_json` was a bare `json.loads` called before the stage loop, and the
top-level handler catches `Halt` only, so the driver exited **1** on a
`json.decoder.JSONDecodeError` traceback with nothing written and no stage attempted. Measured.
Guarded at [`rfc_to_implementation.py:212`](../../scripts/rfc_to_implementation.py) (`read_manifest`).
Expected under the proposed spec: a `Halt`, logged as a decision, exit 2, no manifest write. The port
reaches the same behaviour through `RErr` on `wasi.fs.read` and a defined step transition, because
LLMLL has no unhandled-exception channel and **cannot** reproduce a traceback even if the port wanted
to.
Channel: **spec is silent (gap, flag).** *This is not a §4 violation, and the fourth professor round
classified it as one.* §4's MUSTs are scoped to "a stage that halts"
(`driver-spec.txt:125-143`) and this read precedes every stage; the reference's own comment at
`:1964-1967` makes the same point, that outside a stage the stopped/failed distinction has nothing to
attach to. Calling it §4 asserts an obligation §4 does not state, which is the over-reading this
proposal has been refuted on twice and which §14's `SPEC-TIER-1` row exists to record.
**Consequent routing: repair the reference, do not file a divergence.** `rfc_to_implementation.py` is
ours and has been repaired twice this phase already; `driver-spec.txt` is what is pinned. After a
guarded read the cell sits inside clause 1a. Every avoidable entry in §3's divergence set weakens
§2.2, which is the argument the Python driver's retirement rests on.

**17. A valid `MANIFEST.json` that is not an object.** `[]` or `"x"` parses, and then
`manifest.setdefault("rfc_url", ...)` raises `AttributeError`. Same class as case 16 and the same
repair, which is why the guard belongs on the read rather than around the JSON decode.
**Measured before the guard:** exit 1 on `AttributeError: 'list' object has no attribute
'setdefault'`, at the line after the read.
Channel: **spec is silent (gap, flag).** Guarded at
[`rfc_to_implementation.py:212`](../../scripts/rfc_to_implementation.py) as of Rev 7.

**18. An object whose `stages` member is not an object. NEW in Rev 7, and Rev 6 did not have it.**
`{"stages": [], "rfc_url": "x"}` survives both prior guards: it is well-formed JSON *and* an object,
so `setdefault` succeeds. It crashes later, at the resume gate's own indexing expression
(`manifest["stages"].get(stage.key)`, `:1931`), on `AttributeError: 'list' object has no attribute
'get'`, which is a **third site at a third depth**. Each of the three shapes fails past the guard
that catches the one before it.
Expected: the same `Halt`, exit 2, no manifest write. The shape the resume gate indexes is an object
at `stages`, and a well-formed manifest that lacks one is unusable however valid it is.
Channel: **spec is silent (gap, flag).** Harness findings F-11.
*Lesson recorded rather than the case alone:* two guards written from a two-case enumeration left a
third case live. The enumeration was over *how the file is malformed*; the guard has to be over *what
the reader indexes*.

**19. Refute-crux witness for `[S5-PRESENCE]`'s redundancy.** Mutate `may-skip`'s body to
`(and manifest-complete digests-match)`, dropping the presence conjunct: `[S5-PRESENCE]` refutes, and
so does `[S5-SKIP]`. Mutate instead to `(and (not forced) (and manifest-complete artifacts-present))`,
dropping the digest conjunct: `[S5-SKIP]` refutes and `[S5-PRESENCE]` does not. **No mutation refutes
`[S5-PRESENCE]` alone**, which is the observable consequence of the entailment §11 records, and it is
checkable today with the existing crux machinery.
Channel: **contract.** The concrete instance `CLAUSE-INDEP-1` (§14) would generalize.

---

## 11. Verification mapping

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| Retry-budget separation, finding condition, fill acceptance (`fill.llmll`, three `def`s, six posts) | contract | **QF-LIA, auto-discharged.** Ints and bools only; body-faithful at HEAD | `FixpointEmit.hs`; `LLMLL.md §5.3.3` arithmetic class |
| Token phase discipline (`token.token-during`) | contract | **QF-LIA** via the nullary-enum int-tag discriminant | `LLMLL.md §5.3.5`, n-arm sum `EMatch`, nullary enums stay pure QF-LIA |
| Stage outcome classification, all four arms (`stage.record-outcome`) | contract | **QF-LIA.** Discharged at HEAD; Phase 4 adds the `Errored` construction site, and 4f adds a second `PartialThenHalt` site per §6.2 | `LLMLL.md §5.3.5`; `[S4-PARTIAL]` |
| Skip decision over the manifest (`skip.may-skip`) | contract | **QF-LIA.** Discharged at HEAD | `LLMLL.md §5.3.3` |
| **`[S5-SKIP]` ⊨ `[S5-PRESENCE]`** (clause independence) | contract | **QF-LIA, and propositional in this instance.** `SAT(⋀_{j≠i} Pⱼ ∧ ¬Pᵢ)` has no quantifier alternation and is **strictly weaker** than the query [`Feasibility.hs:203-208`](../../compiler/src/LLMLL/Feasibility.hs) already discharges under z3's `qsat` tactic. No Lean escape | `LLMLL.md §5.3.3`; `CLAUSE-INDEP-1` in §14 |
| Clause 1a under α (§2.1) | trust | **Neither.** Trace equality of a *projection*, checked by execution. α is an abstraction function, not a refinement mapping with auxiliary variables (Abadi and Lamport, TCS 82(2), 1991) | §2.1; no SMT obligation |
| driver-spec §4:139-143's output obligation | trust, **clause 1b only** | **Neither**, and outside α by construction: α cannot see standard output | §2.2; named so it does not fall between the clauses |
| `advancing`'s `newest-artifact-age >= 0` under a clamped age | contract | **QF-LIA, discharged by construction** at the builtin boundary rather than by the solver | `liveness.llmll:7`; `FS-STAT-1` in §14 |
| `advancing`'s `log-age >= newest-artifact-age` | **none.** Shell-side | Outside Σ_auto. A relation between two builtin calls; no signature can carry it | §7's Rev 6 addition |
| Phase 4's own pins as new strict-core `def`s (wave partition counts, per-stage status counts) | contract | **QF-LIA for the count conjuncts; lexeme comparisons fall back** (`STRLIT-BODY-1`) | roadmap `STRLIT-BODY-1`; `spine.llmll:71-80` states the same limit for stage E |
| §6 validation, citation resolution, catalogue rules | **none.** Shell-side | Outside Σ_auto (string and JSON structure) | `LLMLL.md §5.3.5`; no `?proof-required` proposed |
| `Outcome` constructor choice across §3.5's and §3.6's two axes | **none.** Shell-side | Outside Σ_auto | §7; `stage.llmll:10` proves the mapping, not the choice |
| The abstraction functions of §7 | **none.** Shell-side substring tests | Outside Σ_auto | Disclosed, not discharged |
| §3.6's "wrote a declared output before halting" predicate | contract | **QF-LIA.** A written-count comparison against a declared-output list fixed statically by the registry. No string structure: the predicate is an integer comparison, and the list is not read from an artifact | `LLMLL.md §5.3.3` arithmetic class |
| Perturbation-omission set difference (§6.2) | **none.** Shell-side | Outside Σ_auto. Identifiers arrive as strings from stage N's output; **deliberately not interned**, the identifier set being agent-authored per run rather than a closed vocabulary | `LLMLL.md §5.3.5`; §7's fifth statement |
| §13's seven disclosure-only clauses | trust | **Not dischargeable, and not attempted.** Prose constraints on a natural-language artifact | driver-spec §15.1:512-515 excludes reporting from the proved tier |
| §15.1:504-505 tier placement for the deferred §8 and §12 obligations | trust | **No SMT obligation.** Discharged by the phase-close gap inventory | driver-spec §15.1:504-505 |
| Artifact digest match | trust | The digest comes from a sealed builtin (`wasi.fs.sha256`); the driver compares hex strings | `LLMLL.md §13.11` |
| `wasi.fs.copy`'s effect summary | trust (informational) | Not a proof obligation. `Caps {EFsRead, EFsWrite}` under may-over-approximation | `ObligationAssembly.hs:399-448`; `LLMLL.md:1860` |
| `STATE-PROD-1`, if it ships | type | **QF-LIA plus the datatype theory, no widening.** An n-ary product is `Pairn` at the theory `LLMLL.md:963` already runs | `FixpointEmit.hs` `typeToSortA` |

**Nothing escapes to Lean, and that is a statement about what Phase 4 declines to verify.** The
orchestration is `def-shell` throughout and adds no proved obligation (campaign §5 item 4). The
phase close states that the activated cores gain **callers**, which is a coverage fact about the
cores, and that the orchestration gains no proof, and does not let the two sit adjacent without the
distinction drawn.

---

## 12. Affected surface

**Design docs**

- [`driver-in-llmll-campaign.md`](driver-in-llmll-campaign.md) §Phase 4 — Rev 5: eleven stages,
  §2's acceptance clauses, §5's operator-surface change, §3's disposition table, and the correction
  of the "exercises the token discipline just as well" sentence at §Phase 4.
- [`driver-in-llmll-campaign.md`](driver-in-llmll-campaign.md), proved-core roster: add the
  §15.1:512-515 citation. The roster's seven obligations are already counted at §2.4 of this file;
  what is missing is the citation at the point where the roster is introduced, so a reader sees it
  as specified rather than chosen.
- [`driver-ll-open-work.md`](driver-ll-open-work.md): new rows per §14, plus the §8 and §12
  conformance deferrals, which need a home before Phase 5 can write its §15.1:504-505 tier statement.
- `INDEX.md` — one-liner for this file (doc-lead's slot).

**Driver artifacts** ([`tools/llmll-driver/`](../../tools/llmll-driver/))

- New per-stage modules rather than growth of `spine.llmll`, which is 768 lines for four stages.
- `EXPECTED_VERDICTS.json` — new refute-crux cases for the Phase 4 pins, on the
  `crux-stage-j-coverage-pin.llmll` pattern.
- `README.md:99` — add the §3.4 divergence beside `crux-gate-single-remedy` under "what the driver
  does today."

**Compiler** ([`compiler/src/LLMLL/`](../../compiler/src/LLMLL/))

- `CodegenHs.hs:577-590` — `FS-ENCODING-1`, **shipped v0.14.84** (`82a0772`). Availability fix, not
  the crash-freedom fix Rev 5 described; see §10 case 7.
- `TypeCheck.hs` `builtinEnv`, `ObligationAssembly.hs:442-448`, `CodegenHs.hs:523-543` —
  `wasi.fs.copy`, **shipped v0.14.84** (`0f2c22f`): one signature, one `primEffect` clause, one
  codegen case, no new label, no new arm, as predicted.
- `CodegenHs.hs:1344`, `:1347-1349` — the mixed-match catch-all suppression, filed as
  `MATCH-CATCHALL-1` per §10 case 6. **Not Phase 4 work.**
- `Parser.hs:328-333` and downstream — `STATE-PROD-1`, only if taken.
- **Nothing else.** Sub-phase 4a needs no compiler change; it is driver-artifact and harness work.

**Harness** ([`scripts/`](../../scripts/))

- `scripts/tests/test_rfc_pipeline_integration.py` — the stub agent moves from env to argv; the stub `llmll`
  gains the §10 case 1 contention injection, which lands at 4e; **the scenario set is eleven cells
  (T4 and T7 were new to Rev 6), plus the three manifest shapes of §10 cases 16, 17 and 18. All
  eleven cells and all three shapes carry a test as of Rev 7**, so what remains here is the stub-side
  work above and a second driver coming under test, not the cover itself.
- [`rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py), **DONE at Rev 7**:
  `read_manifest` at `:212` guards all three shapes of §10 cases 16, 17 and 18 and raises
  `StageFailure`, which the top-level `except Halt` renders as a decision at exit 2. Five tests
  added; three of them go red against the unguarded tree and green against the guarded one, which is
  the positive witness the guard owed.
- `build_smoke.sh` — the Phase 4 artifact enters the build gate per campaign §3a.
- [`rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py): the §3.5 and §3.6 repair,
  experiment-lead's slot. **37 sites, not 38.** `:866` is held at `stopped` and changes constructor
  rather than status, per §3.6's recorded uncertainty. `require()` needs a second raising form so the
  disposition rides the clause rather than the validator, and
  `test_exclusion_outside_the_barrier_list_halts_the_run` must keep asserting `stopped` as the
  witness that the rule does not over-fire. A stage-O validator is **new behaviour** and must not be
  bundled into that repair.
- [`DRIVER-LL-PHASE4-HARNESS-FINDINGS.md`](../../experiments/rfc-swarm/DRIVER-LL-PHASE4-HARNESS-FINDINGS.md)
  carries §6.2's stage-O finding and §14's target-spec defect as new rows. The defect is a finding
  about the campaign's target document, which is the campaign's own product, so it does not belong
  only in a design proposal.

---

## 13. Risks

1. **The live run cannot exercise contention.** Scope. Clause 1a injects it; clause 2 cannot. Bite:
   **does not block**; requires the §10 case 1 disclosure and the campaign-sentence correction.
2. **The abstraction functions are unchecked and one of them decides verdict-versus-accident.**
   Scope, claim-discipline. §7. Bite: **complicates**; the disclosure is cheap and the alternative is
   an overclaim in the phase close.
3. **`FS-ENCODING-1` was an availability hazard, not a crash-freedom one, and shipped at v0.14.84.**
   Soundness of the effect runtime. Bite: **closed**, with one residual: macOS GHC ignores `LC_ALL`,
   so `build_smoke.sh` stage 5b is a no-op locally and **no Linux run has confirmed the fix**.
3a. **α is a design decision no test can validate.** Soundness of the oracle. §2.1. Choosing to
   discard `seconds` and weaken `detail` to non-emptiness is a judgment about what the refinement
   claim means, and a wrong α passes clause 1a while the port diverges where it matters. Bite:
   **complicates**; the mitigation is that α is now written down and reviewable, which it was not.
3b. **Repairing the reference at the sequencer moves the comparison target mid-phase.** Spec-drift.
   §10 cases 16 through 18, and it is the third such repair after §3.5 and §3.6. **Realized at Rev 7**
   (`read_manifest`, `rfc_to_implementation.py:212`). Bite: **complicates**; each repair must be dated
   and the clause-1a runs re-based, or an old green is evidence about a driver that no longer exists.
3c. **A design-document grep is not a code audit, and this proposal has now been wrong that way four
   times.** Spec-drift, method. §2.3 finding 3 (refuted at Rev 7), §3.3's two, and `FS-ENCODING-1`'s
   mechanism. The shape is constant: a grep over the name the document uses, where the code enforces
   the same obligation under a different name one call frame away. Bite: **complicates every
   revision**; the mitigation that has worked is executing the claim, and it has worked four times
   out of four.
4. **Validators ported against two committed runs are the shape §7:288-291 warns about.**
   Verification-ergonomics. The transition cover uses synthetic stub rows, which is some protection
   and not a subject-independence test. Bite: **complicates.**
5. **Clause 1b compares against a known-wrong reference on four inputs.** Spec-drift. Bite:
   **complicates**; §3.4 states it so a reader does not read it as a port defect.
6. **The state encoding remains the phase's silent-failure surface**, reduced but not removed by the
   sum encoding. Verification-ergonomics. Bite: **complicates**; per-component accessors written once
   and reviewed once.
7. **The operator CLI change collides with the "replaces" decision.** Scope. Campaign §8.1, §5 item
   3. Bite: **only matters at retirement**, and must be written into the retirement note rather than
   discovered by an operator.
8. **The mixed-match hole.** Totality. Bite: **only matters at scale**; the precondition is a
   warning-bearing program.
9. **§7's citation half is unreachable in this repository.** Scope. Bite: **already recorded**; it is
   the G2 limitation and widens nothing.
10. **§3.6 changes a site the Python repair was handed as mechanical.** Spec-drift, timing. `:866` is
    in the list the restart record gives experiment-lead. Bite: **blocks the mechanical framing by
    one site**; the conservative action (hold `:866`, move 37) is the same under both readings of
    §4:146-147, so it does not block the work itself.
11. **"Some of its artifacts" is a reading, not a derivation.** Scope. §4:146 does not settle the
    wrote-all-then-failed-validation case, and the driver's six-site precedent is behaviour rather
    than authority. Bite: **complicates**; it is the fourth under-specified clause this proposal has
    had to read, and §3.6 records it as a reading rather than presenting it as settled.
12. **§14's target-spec defect has no repair path.** Spec-drift. driver-spec is pinned under
    §14:473-474, and §13's prose MUSTs fit none of §15's three tiers while §15.1:504-505 requires
    every obligation to occupy one. Bite: **does not block Phase 4**; it constrains what Phase 5's
    conformance claim can assert, and it must be recorded before that claim is written.
13. **The perturbation-omission check is necessary and not sufficient.** Claim discipline. Bite:
    **complicates 4f**; the mitigation is naming, not machinery, and §10 case 14 is the witness.

---

## 14. Gaps filed by this proposal

| Tag | What | Blocks |
|---|---|---|
| `FS-ENCODING-1` | **SHIPPED v0.14.84** (`82a0772`). `wasi.fs.read` / `write` inherited the ambient locale, so a POSIX locale could not read a **valid** UTF-8 file or write any non-ASCII string. **Rev 6 corrects Rev 5's mechanism**, which said a decode failure "throws inside a `Command`": nothing threw, because `llmll_publish_io`'s `try` plus the existing `evaluate` already made the failure a value. The defect was availability, not crash-freedom | Closed. Residual: macOS GHC ignores `LC_ALL`, so no Linux run has confirmed the fix |
| `FS-COPY-1` | **SHIPPED v0.14.84** (`0f2c22f`). No byte-faithful copy; `wasi.fs.copy` as proposed in §8, `Caps {EFsRead, EFsWrite}`, no new arm | Closed. Was **driver-spec §8:336-337**, which requires the checking copy to be the original unmodified subject. Conformance, not the ergonomics Rev 4 recorded |
| `FS-STAT-1` | **Re-scoped in Rev 6.** `liveness.advancing` has no callable data source. **An mtime does not close this**, and Rev 5's routing note said it would: `advancing` takes an **age in seconds** (`liveness.llmll:6`) and monotonic reports nanoseconds since an *unspecified* epoch, so no subtraction is defined. Proposed shape: `wasi.fs.stat` returns the artifact's **age in seconds, clamped at zero**, as `RCode`, carrying `Caps {EFsRead, ENonDet}`, both labels already in the closed catalog (`ObligationAssembly.hs:399`), so CAP-PROC's admissibility rule holds with no new `Response` arm. The clamp discharges `[S12-DOM]`'s first conjunct **by construction**; the rejected alternative (epoch mtime plus a new `wasi.clock.realtime`, subtracted shell-side) lets clock skew drive the age negative, turning a stale-liveness read into a precondition violation. Two consequences for the row: `[S12-DOM]`'s second conjunct stays shell-side (§7), and an age-returning builtin is a **candidate** first firing site for `W-REPLAY-INERT` (roadmap `:51`), whose in-tree firing population is recorded as zero. Also: `RCode` now carries exit statuses, monotonic nanoseconds and clamped ages, with the unit nowhere in the type. That is a scope boundary LLMLL has chosen (no dimension-indexed numerics; cf. Kennedy, POPL 1997), and the in-scope move is to name the unit in the declared contract | **driver-spec §12:405-428, via a §15.2:522-524 capability gap.** The §15.1:511 proof obligation is discharged; the capability that would feed the proved predicate does not exist. Deferral must be tiered under §15.1:504-505 |
| `FS-ISOLATION-1` | `audit_blindness` (`:1644-1668`) implements driver-spec §8:330-332 and the port defers it | Nothing in Phase 4; like `--status`, a spec obligation deferred as operator surface, and disclosed under §15.1:504-505 rather than dropped |
| `SPEC-TIER-1` | **Target-spec defect.** §15.1:509's range ("sections 4 through 13") contradicts its own characterisation at `:509-510` and its enumeration at `:512-515`, neither of which covers reporting. §13's prose MUSTs consequently fit none of §15's three tiers, while §15.1:504-505 requires every obligation to occupy exactly one | Nothing in Phase 4. driver-spec is pinned (§14:473-474) so it cannot be repaired here; it constrains what Phase 5's §15.4 conformance claim may assert. No tier is manufactured for them: stretching §15.2's scope sentence past "effectful operations" is the over-reading this proposal has been refuted on twice |
| `PROC-ENV-1` | `wasi.proc.run` has no env parameter | Nothing; named-not-scheduled, and deliberately so |
| `STATE-PROD-1` | At most one payload per constructor; no n-ary product | Nothing; ergonomics. §4 gives the worked encoding and its cost, one pair per arm rather than a chain per field |
| `MATCH-CATCHALL-1` | `emitMatch` suppresses its catch-all on any constructor arm, including in a mixed match with literal arms (`CodegenHs.hs:1344`, `:1347-1349`). **The row text must carry the precondition**, which is what makes it non-obvious: the entry condition is a program that ships past a `tcWarn` (`TypeCheck.hs:2326-2332`), a literal arm against a sum-typed or `Result`-typed scrutinee being type-incompatible. Correct one detail from §10 case 6 when filing: `checkExhaustive` fires for `TSumType`, `TResult` **and `TBool`** (`:2255-2257`), not for known sum types alone | Nothing in Phase 4; general crash-freedom hole. Rev 6 gives it a tag; the row is doc-lead's to file |
| `CLAUSE-INDEP-1` | **New in Rev 6, from the fourth professor round.** A `post` clause entailed by its siblings contributes no eliminative power while occupying a §15.1 tier. Confirmed instance: `[S5-PRESENCE]` follows propositionally from `[S5-SKIP]` (`skip.llmll:19-27`), so its refute-crux set is a **subset** of `[S5-SKIP]`'s and no mutation refutes it alone (§10 case 18). **The machinery for this ships**: the CDP vacuity gate is body-side and Ω-relative (v0.14.13, roadmap `:199`, `:210`; `CDP.hs:142-149` distinguishes genuine vacuity from tightness-for-Ω), and `LLMLL.Feasibility` is the Ω-independent one (v0.14.52). The clause-side dual is the **cheapest of the three**: `SAT(⋀_{j≠i} Pⱼ ∧ ¬Pᵢ)`, no quantifier alternation. Per the tracked-concept discipline, this **extends** CDP on the axis CDP's own Ω-relativity comment names as its limit; it does not approximate or sidestep it | Nothing in Phase 4. **The in-scope move needs no compiler change**: record the entailment in `[S5-PRESENCE]`'s `:source` text so the clause keeps its traceability to a distinct driver-spec sentence while a reader sees it is derived, and let §15.1's tiering report count three obligations of which one is marked derived. File as a third item in the layer-3 contract-quality row (`:210`), not as a standalone row |

---

## 15. Revision history and professor review log

All four professor rounds were conversational. No standalone `driver-ll-phase4-review.md` exists, so
there is no M2 fold-and-archive to trigger; the findings are recorded here.

**Rev 9 → Rev 10, the 4c harness leg.** Not a professor round. Three measurements at `d15b2ff`
(v0.14.87), findings F-18 through F-20, and the first of them refuted this document's own acceptance
clause for the sub-phase it was written to gate.

- **F-18 refuted §9's 4c clause, and the refutation was of a distinction rather than a value.** The
  leg was commissioned to decide **which** of two readings of "stage E's Phase 3 pins reproduce over
  D's own output" was satisfiable. Neither is: 7 for 7 over the committed pair, 0 for 7 over stub-D,
  and unpinnable in principle over live output. The framing that sent the measurement out was itself
  wrong, which is recorded here rather than quietly replaced, because a brief that presupposes a
  false dichotomy is the same error shape as a grep-derived count. §9.2 item 3 replaces the clause by
  inverting its direction: downstream ported stages **run** over 4c's output rather than pinned
  values reproducing over it.

- **F-19 eliminated a reading this document had settled.** §3.6 took the artifact-state axis at
  `:866` and stated one disagreeing site in 46. Stage D's iteration-`b` halt is a second, and it
  resolves the other way, so the operative rule is hold-the-existing-value rather than
  artifact-state-wins. **The test had two live outcomes before it ran**, which is what makes this
  eliminative rather than a concordance check. Recorded as §3.6.1.

- **A site invisible to every census this phase has run.** `:656` is one source line with two
  artifact-state dispositions, one per loop iteration, so no per-site enumeration could have
  represented it. Phase 4 has now found this granularity failure twice, at row level (F-16, deferred)
  and at loop level. Both were found by executing, neither by reading.

- **§3.6's table is left stale on purpose.** Its keys are line numbers, `:809` is no longer a write,
  and two conditions it files as post-write fire before their stage writes anything. Renumbering by
  inspection is what produced the Rev 8 stamp, so the re-census is filed as owed rather than
  performed inside the revision that found the staleness.

- **F-20 is a null result with an actionable half.** The bare-list arm at `:713` and `:732` has no
  producer in the tree, so the port's narrowing is measured rather than assumed; whether a live agent
  can emit that shape is unmeasured at n=0 live runs, and the narrowing therefore rejects rather than
  tolerates.

**Rev 8 → Rev 9, the §3.5 census.** Not a professor round. Rev 8 stamped §3.5 as measured at
`aa08051~1` rather than renumbering it, and then stated a wrong number in the stamp. An AST
call-site census at HEAD (`6e92dd0`, v0.14.86) refuted it. Findings F-14 through F-17.

- **Rev 8's stamp was wrong three ways, and it is this document's own error.** It said the site set
  dropped from 46 to 39. **It never dropped: 46 at `aa08051~1`, 46 at `aa08051`, 46 at HEAD**, with
  ten conditions re-encoded and none added or removed. The 39 came from `grep -cF 'require('`
  returning 40 and subtracting the definition, missing **three docstring mentions**; the real
  call-site count is 36. And the raise count did not rise at Task #8 as claimed, it rose at
  `c10081d`. **A grep produced a wrong count inside the correction of a wrong count**, which is
  risk 3c at its most literal.
- **A third raising form exists**, `require_written` → `PartialHalt` → `PartialThenHalt`, and
  neither §3.5 nor Rev 8's stamp mentioned it.
- **The rule survives intact and the repair ENCODED it**, which is the substantive result under the
  arithmetic. `require_spec`'s docstring restates both conjuncts, `StopCondition.__init__` makes the
  clause citation mandatory, and **all nine spec-defined sites are `require_spec` at HEAD carrying
  the clauses §3.5 names, 9 for 9**. The polarity guard holds.
- **Two of the nine line numbers now point at inverted sites.** §3.5.1 is new and forbids keying on
  them. This is the line-citation defect the phase has recorded twice and had not yet applied to its
  own §3.5.
- **§3.1's row 3 does not describe the reference**, filed as a null result rather than a finding.
  `AgentRunner.run` raises on a non-zero exit **before** the output-existence check, so a stage that
  produced a valid declared output and exited non-zero records `failed`, not `complete`. §7:279
  governs a stage terminating *without* producing its output, which is a different case. Measured
  with a stage-B run writing a valid 1200-byte `scope.md` and exiting 7. All of B, C and I take that
  path.
- **§6.2 is wrong that stage O is the only delegated stage with no validator.** Stage I has none
  either. §9.1 settles the consequence.

**Deferred, not settled: F-16, the row-granularity limit.** Two sites halt `stopped` on non-core
rows where their sibling core-filters, because the clause supplying their halt-mandate binds *the
gate* rather than the stage, and two shipped tests pin the current behaviour. §3.5's rule assigns
**one disposition per site** and these are **row-granular**; §3.1's Rev 4 amendment already moved the
unit from stage to clause, and this would push it once more. Three exits exist: core-filter the two
sites, declare §7:306-309's "MUST require" self-sufficient as a halt-mandate, or give §3.5's table a
scope column. **It does not block 4b**, neither site being in B, C or I, so it is filed rather than
rushed.

**Rev 7 → Rev 8, sub-phase 4a executed.** Not a professor round. Rev 7 filed four findings and held
them deliberately unsettled, three being predictions about behaviour the port had not yet exhibited,
on the ground that every revision of this proposal which predicted was wrong in a checkable way.
The port ran (`2b82464`, at v0.14.85). **All three predictions are confirmed, one measured item
stands, and the port produced two findings the proposal did not anticipate.**

- *`wasi.fs.sha256` collapses presence and digest.* **Confirmed, and it was worse than a disclosure
  gap.** It is now the third statement under §7's `skip.may-skip` bullet. The collapse made the
  port's own T7 scenario non-discriminating: hardcoding `artifacts-present` left **all fifteen
  scenarios green**, on the one cell that exists to witness driver-spec §5's condition (b) alone.
  A cover that cannot fail proves nothing, and on the cell this phase spent two revisions adding, it
  could not. Repaired in the port.
- *§4's sum encoding makes `:on-done` usable.* **Confirmed**, retiring the RC-4 workaround
  `spine.llmll:673-679` documents.
- *The port decides all three corrupt-manifest shapes with one total predicate.* **Confirmed.**
  `json-set` is constructor-decidable over all seven JSON shapes, so `is-object?` is total and needs
  no substring test, where the reference discriminates by Python exception site. **This is the
  clause-1b case the proposal flagged as the interesting one: the port is better than the artifact
  1b checks it against.** 1b is a conformance claim, not a fidelity claim, and §2.2 already scopes it
  to where they differ; the port's superiority on this axis is recorded rather than suppressed.
- *§3.5 states a measurement with no epoch.* **Confirmed by measurement** and stamped in place. No
  bite for 4a; 4b must re-measure.

Two findings the proposal did not predict:

- **The eleven-cell cover is stronger than its count states, and this was established by mutating
  each conjunct separately.** T7 dies to the presence mutation and survives the digest one; T6 does
  the reverse. The cells are **separable**, not merely both present. The count "eleven of eleven"
  says nothing about discrimination, and two of the eleven now have it demonstrated.
- **A perturbation that crashes is not a perturbation that refutes.** Hardcoding presence at its
  *definition* in the reference yields an unhandled `FileNotFoundError` and exit 1, not a wrong
  skip. Killing at the decision level required the mutation to sit in the decision expression. Any
  future mutation work on this cover must place the mutation where the decision is read, not where
  the value is produced.

Risk 3c is not incremented by this round. The port disagreed with the proposal twice and both
disagreements were executed before being written, which is the discipline the risk asks for.

**Rev 6 → Rev 7, the sub-phase 4a harness leg.** Not a professor round. Rev 6 made five checkable
predictions about the cover and the sequencer, the harness executed all five, and **four held and one
was refuted.** Source: `experiments/rfc-swarm/DRIVER-LL-PHASE4-HARNESS-FINDINGS.md`, session
2026-08-05, F-9 through F-11, at compiler v0.14.84.

- *T7 re-runs the stage and reports nothing.* **Confirmed by execution.** Per-stage grep of a resume
  after deleting stage B's declared output: B ran, no reason line of any kind; A and C skipped. §2.3
  finding 1 and §10 case 15 upgraded from measured-by-reading to executed, and the cover's T7 row now
  names a test. **The cover is eleven of eleven covered**, where Rev 6 left it ten of eleven.
- *The reference can reach T7 through its own write path.* **REFUTED**, and it was this proposal's
  own claim rather than an inherited one. `AgentRunner.run` (`rfc_to_implementation.py:331-334`)
  raises `StageFailure` when a delegated agent exits 0 having written nothing, so §7:279 is already
  enforced for the eleven agent-delegated stages. Rev 6 grepped `stage.outputs`, the declared list on
  the `Stage` record; the check is written against `out_name` one call frame down. §2.3 finding 3 is
  struck and replaced, §10 case 3 is annotated as already-implemented rather than divergent, and the
  surviving residue is narrower and stated: the two mechanical and three gate stages have no generic
  presence check, so for those five the route is unmeasured rather than closed.
- *The sequencer crashes on a corrupt manifest.* **Confirmed, and short by one.** Rev 6 named two
  shapes; there are three, at three sites, each surviving the guard that catches the one before it.
  `{"stages": [], "rfc_url": "x"}` is well-formed JSON *and* an object, so it passes both prior
  guards and dies at the resume gate's own indexing expression (`:1931`). Added as §10 case 18, with
  the method lesson: the enumeration was over how the file is malformed, and the guard has to be over
  what the reader indexes.
- *Not a §4 violation.* **Upheld.** This is the point Rev 6 argued against the fourth professor round,
  and nothing in the execution disturbs it: §4's MUSTs are scoped to a stage that halts. The repair
  landed on the reference, and §3's divergence set did not grow.
- *T7's silence is conformant.* **Upheld and deliberately not asserted.** The test pins the decision,
  that the stage ran, and not the absence of prose. §5 attaches a report obligation to T6 and T8 and
  nothing to T7.

Risk 3c is added on the strength of this round: four refuted mechanism claims, all of them the same
shape, all of them caught by executing rather than by re-reading.

**Rev 5 → Rev 6, fourth professor round.** Eight findings: six accepted, one accepted with a changed
remedy, one refuted from the inward direction.

- *Clause 1a is unsatisfiable: `seconds` is wall-clock and `detail` is Python exception text.*
  **Accepted in full**, and it is the round's leading finding. §2.1 gains the abstraction function α
  and the criterion by which α keeps a field. The Abadi-Lamport distinction between an abstraction
  function and auxiliary history and prophecy variables is the citation Rev 5 needed; Rev 5's "no
  refinement mapping needs constructing and no auxiliary variable is needed" was right on the second
  half and wrong on the first. **Changed remedy on one point**: the professor discards `detail`, and
  §2.1 keeps it as a non-emptiness predicate instead, because discarding it leaves an `Errored` row's
  whole content unchecked while §4:129-131 requires a detail string naming the error.
- *The corrupt-manifest cell: the reference tracebacks at the sequencer, in violation of §4.*
  **Defect accepted, classification refuted, remedy changed.** The crash is confirmed at `:208-209`,
  `:1856`, `:1969-1976`. It is **not** a §4 violation: §4's MUSTs are scoped to "a stage that halts"
  (`driver-spec.txt:125-143`), the read precedes every stage, and the reference's own comment at
  `:1964-1967` says the stopped/failed distinction has nothing to attach to outside a stage. Naming
  it §4 asserts an obligation §4 does not state, which is the over-reading recorded in this file's
  own `SPEC-TIER-1` row. Routed as a **reference repair** rather than into §3's divergence set, since
  every avoidable divergence weakens §2.2. §10 cases 16 and 17.
- *`FS-STAT-1` cannot produce an age.* **Accepted in full**, and it refutes this proposal's own Rev 6
  draft routing note. §14's row is re-scoped to a clamped-age builtin with the precondition argument
  that decides between the two shapes.
- *`[S5-PRESENCE]` is entailed by `[S5-SKIP]`, and the project has no vacuity check.* **Entailment
  accepted; the second half refuted inward.** Two gates in this family ship: the CDP vacuity gate at
  v0.14.13 and `LLMLL.Feasibility` at v0.14.52. What is missing is the clause-side dual, which is the
  cheapest of the three rather than a new research program. Filed as `CLAUSE-INDEP-1`, extending CDP.
- *"The port must reproduce the silence" is unsound.* **Accepted in full.** The instruction
  contradicted §2.1's own definition of clause 1a's observable. Withdrawn; §10 case 15 asserts the
  decision instead, in the rig's existing idiom.
- *T7 and §10 case 1 differ in quantifier.* Accepted; §2.3 states the difference and why the remedies
  are not interchangeable.
- *`RCode` is overloaded a third time.* Accepted as a note in `FS-STAT-1`'s row; a scope boundary
  rather than a soundness complaint, LLMLL having declined dimension-indexed numerics.
- *Citation form: name the binding, not the line.* Accepted, with the sharper framing that a rename
  is grep-detectable while a line shift is silent. **A third instance was found while folding**: the
  roadmap's layer-3 row at `:210` cross-references CDP at `:224`, which is now a table header inside
  the Research track section. Routed to doc-lead with the other two.

**Two convergences.** The professor and this proposal reached the run-the-harness-before-4a
sequencing from opposite directions, and the citation-drift finding independently, the professor by
following §10 case 6's evidence into `emitApp` and this side by extracting all forty line citations
mechanically. Seven were stale, five of them into `compiler/src/LLMLL/`, and all four of case 6's
were wrong.

**Rev 1 → Rev 2, first professor round.**

- *Serial wave makes the contention branch unreachable; the Rev 1 positive witness was unsatisfiable.*
  **Accepted in full.** §10 case 1 replaced; the campaign claim is refuted rather than qualified.
- *§7 supersedes the §4-residual derivation.* **Accepted**, and it sent this proposal to §7 in full,
  which produced §6.
- *Mapping a non-zero exit to `failed` imports a condition the specification does not define.*
  **Rejected.** §4's dichotomy is exhaustive over halts that occur; it does not restrict when a
  driver may halt. The **ordering** change was adopted on §7:279's grounds.
- *Clause 1 is a refinement claim without a mapping, asserted modulo an exception set; the scenario
  set is hand-picked.* **Accepted** as to the two claims and the transition cover. The stuttering
  half was declined and the professor withdrew it in round two: `driver-spec.txt:154-157` imposes the
  quotient.
- *The state is a sum over phases, not a flat product.* **Accepted in full**; §4 rewritten and
  `STATE-PROD-1`'s motivation narrowed.
- *Split `FS-COPY-1` from `FS-ENCODING-1`; `wasi.fs.copy` is the principled fix.* **Accepted in
  full**; §8.

**Rev 2 → Rev 3, second professor round.**

- *§7:284's "MUST fail the stage" is verb usage, not status assignment.* **Accepted**; Rev 2's
  derivation withdrawn. The replacement conclusion (validation failure → `stopped`) is **rejected**
  on §3.2, the declared shape not being a condition the specification defines. Conclusion unchanged,
  derivation replaced a second time.
- *The proved core's guarantee is conditional on an unverified abstraction function.* **Accepted in
  full**; §7 added, §10 case 9 added as its witness.
- *The §7 citation clause over-reading widens `HTTP-GET-1` wrongly.* **Accepted in full**; §6 item
  3 withdrawn, the citing set corrected to D and K.
- *The mixed-match hole is narrower than stated.* **Accepted in full**; §10 case 6 carries its
  precondition.
- *Re-ground the §6 overlap on its own stated reason.* **Accepted**: §6:267-271 gives a reason that
  does not depend on statuses at all, which is that the two checks fail at different times against
  different threat models.

**Rev 3 → Rev 4, harness leg** (`experiments/rfc-swarm/DRIVER-LL-PHASE4-HARNESS-FINDINGS.md`). The
first revision driven by executing something rather than by reading it.

- *F-1: §3.1's validation row is under-determined; the discriminator cuts within a single validator.*
  **Accepted in full.** §3.5 added: the rule, the nine spec-defined sites by clause, the polarity
  guard, and the counts. All three sites the harness could not classify now resolve, all to `failed`,
  so item (d) is unblocked.
- *F-2: §10 case 5 derives its disposition from the driver's own source.* **Accepted; the error was
  this proposal's own.** Corrected to `failed`.
- *F-3: stage H is a stage driver-spec does not describe.* **Partly refuted.** The grep is right and
  the conclusion is too strong: §7:313-316's catalogue clause covers the stage; only its acceptance
  bar is driver-defined. Recorded in §6, and it decides `:866`.
- *§2.3's coverage claim counted `STUB_MODE` values rather than tests.* **Accepted**; corrected to
  six of eight with a ninth transition the list omitted.
- **Attribution correction found while checking F-1**: Rev 3 and the findings both placed the
  citation-resolution mandate in §7. It is §14:479-483, and the driver's own STOP message says so.
  A heading grep that truncated at section 9 is why Rev 3 never read §10 through §15.4.

**Rev 4 → Rev 5, third professor round, plus a sweep of §8 through §15.4.**

The round was prompted by a residue of the Rev 4 attribution correction: the truncated grep meant
§10 through §15.4 had been read only where Rev 4 went looking, and a targeted lookup finds the clause
you sought rather than the ones you did not know to seek. The sweep extracted every RFC 2119 keyword
in §8 through §15.4 and matched each against this proposal's citation set.

- *Stage O is the only delegated stage with no validator, and §13 is its specification.* **Accepted
  in full**, and confirmed independently by the professor. §6.2 added. Measured: `stage_O_writeup`
  has zero `require()` sites and restates three §13 MUSTs in a docstring that reaches the agent as
  prompt text.
- *The tenth-spec-defined-site claim fails §3.5's own second conjunct.* **Accepted.** §13:446
  mandates resolution, not halting, and §13 is not a §6 gate. The first draft of §6.2 substituted
  "resolution mandate" for "halt mandate," which is the same elision that got Rev 2's §7 derivation
  refuted. Withdrawn.
- *Ground the stage-O disposition on §14:484-491's report-without-halting polarity instead.*
  **Refuted, ground and conclusion.** §14's stated ground is that both its checks "occur in correct
  censuses"; a report omitting a survivor is not a correct artifact, so the rationale does not
  transfer, and applying the wording without the ground would be a fourth instance of the shape
  §3.3 records. The accompanying artifact-destruction premise is refuted by measurement: all five
  stages that validate after writing write the declared output first, so a halt leaves the artifact
  on disk. Refuting it is what produced §3.6.
- *§13:439-441 is misclassified twice: the driver holds no assumed-step set, and the obligation is
  the inductive-invariant-to-trace-property disclosure.* **Accepted in full.** §6.2 routes it to the
  trust channel. The first draft's claim that the driver "already holds this set" was asserted
  without grepping for it.
- *§15:547 is the wrong citation for the deferrals.* **Accepted, and the replacement is also
  wrong.** §15:547 constrains obligations a claim "claims to meet." The professor's substitute
  §13:437 governs the run's report rather than the phase's conformance claim. The clause is
  **§15.1:504-505**, which binds *every* obligation.
- *§12:428 is overstated as violated today.* **Accepted.** The renderer conforms; the recording does
  not. §6.3 flags it as entailment on the standard §3.5 applies to `:811`.
- *The omission check is necessary and not sufficient.* **Accepted.** Renamed in §6.2 for what it
  decides; §10 case 14 is the witness.
- *§15.1's range contradicts its enumeration and §13's prose MUSTs fit no tier.* **Accepted**, filed
  as `SPEC-TIER-1` against the target rather than resolved.

**Two corrections to this proposal's own prior turn, both self-inflicted.** The Rev 5 sweep produced
a citation audit and then misread it twice.

- *"§15.1 is unread; the campaign never cited the clause specifying its proved-core roster."*
  **False.** §2.4 cites §15.1 and counts its seven obligations. The audit reported "§15.1: 1x, line
  119" and the reading passed over it. The roster cross-check against `tools/llmll-driver/` was real
  and the one-to-one correspondence holds; the conclusion hung on it did not. What survives is
  narrow: the citation belongs at the point where the roster is introduced in the campaign doc, and
  `FS-STAT-1`'s Blocks column was wrong.
- *"§4:146-147 is used by neither turn."* **False.** §3.3 cites it, as evidence about the
  specification's use of *fails* as an ordinary verb. It appeared in the audit under §4's spans. What
  survives is narrower and is §3.6: the clause is cited for its vocabulary and never applied to the
  46-site classification, and `PartialThenHalt` was proved and constructed in Phase 3 while §3.5's
  rule sorted every halt into the other two constructors.

Both errors share a cause worth recording: the audit was run, its output was correct, and the reading
of it was not. A citation audit is evidence about what a document cites, and it is not evidence about
what the reader noticed.

**Standing note.** The delegated-stage disposition produced three derivations in three turns, a
fourth turn made it operational, and a fifth found that the rule sorted a four-constructor type into
two constructors. §3.1 is the settled table, §3.2 the derivation it rests on, §3.5 the clause-source
rule that applies it per call site, and §3.6 the artifact-state axis that overrides it at one site. A
sixth challenge has to engage §4:132-136's verdict-versus-accident criterion directly, and separately
say which axis governs when §3.5 and §3.6 disagree; driver-spec does not.
