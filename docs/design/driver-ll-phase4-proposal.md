---
name: driver-ll-phase4-proposal
title: "DRIVER-LL Phase 4: the agent-delegated stages, the serial wave, and the two oracles that can check them"
status: "Rev 4, SETTLED, READY FOR ENGINEER. Rev 4 is the first revision driven by EXECUTING the harness rather than reading it, and it closes the one item Rev 3 left un-implementable. §3.5 is new: the halt surface is 46 require() sites plus three AgentRunner raises, not the four conditions §3.4 described, and the disposition attaches to the CLAUSE rather than the stage or the validator, because check_dispositioned holds six checks of which exactly one (:355, the closed-barrier condition, driver-spec §6:229-231) is spec-defined. §3.5 gives the classification rule with a polarity guard (§14:484-491 states two checks that MUST be reported and MUST NOT halt), enumerates the nine spec-defined sites by clause, and resolves all three sites the harness could not classify -- :967, :866 and :1045 -- to failed, which unblocks the Python-side repair. Divergence set is 38, not 4. Three corrections to Rev 3, two of them to this proposal's own claims: §10 case 5 was WRONG (it derived 'no holes to fill -> stopped' from the driver's own source, and driver-spec has no clause about an empty hole set, so §4:129's residual gives failed -- the third instance of the error shape §3.3 records twice, and the first originating here); §2.3's coverage claim counted STUB_MODE values rather than tests, and the measured cover was six of eight with a ninth transition omitted; and the citation-resolution mandate is §14:479-483, not §7, which Rev 3 missed because a heading grep truncated at section 9 and §10 through §15.4 were never read. One finding PARTLY REFUTED: stage H is not unspecified, since §7:313-316's catalogue clause covers it; only its acceptance bar is driver-defined, which narrows what Phase 5 §15.4 owes. Rev 3, SETTLED. Revises `driver-in-llmll-campaign.md` §Phase 4 on two structural corrections: the phase's stage enumeration was short by one (stage G was assigned to no phase), and its acceptance clause ('a complete run reproduces a committed campaign's artifacts') is not satisfiable against this tree, measured. Replaced by two claims plus a derived transition-cover scenario set. Rev 3 settles the delegated-stage disposition on its THIRD derivation: Rev 1 argued from §4's residual clause, Rev 2 argued from §7's wording and was refuted on the specification's own use of 'fails' as a verb, and Rev 3 rests the conclusion on §4:132-136's verdict-versus-accident criterion, which neither prior derivation touched. The conclusion did not move; the argument did, twice. Rev 3 also reframes the finding against the Python driver from a wrong constant to a missing distinction: it has ONE halt channel where the specification defines TWO, and `stage.record-outcome`'s `Outcome` type already models both. Rev 2 folded the first professor round (serial wave makes the contention branch unreachable, so the Rev 1 positive witness was unsatisfiable; state is a sum over phases, not a flat product; `wasi.fs.copy` split out from the encoding fix). Rev 3 folds the second (the §7 lexical refutation, accepted; its replacement conclusion, rejected; the citation-clause over-reading, withdrawn; the abstraction-function disclosure, adopted). Both professor rounds were conversational; no standalone review file exists, and their findings are folded in §15."
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
writes is identical to the Python driver's.

The observable is the manifest file's successive contents, not either step machine's internal
states. `driver-spec.txt:154-157` requires the manifest to be written after every stage transition
in both implementations, so the granularity difference between a nineteen-state Python loop and a
sixty-state LLMLL step machine is quotiented by the specification rather than by the comparison.
No refinement mapping needs constructing and no auxiliary variable is needed.

### 2.2 Clause 1b, conformance where they differ

On the §3 divergence inputs the LLMLL driver conforms to driver-spec §4 and §7 and the Python driver
does not. This is a conformance claim against the specification, not a refinement claim against the
reference implementation, and it is the more important of the two: it is what the Python driver's
retirement rests on.

Stated as one clause with a carve-out, the carve-out is load-bearing and invisible. They are two
claims and they are proved differently.

### 2.3 The scenario set is derived, not chosen

The harness exists.
[`scripts/tests/test_rfc_pipeline_integration.py`](../../scripts/tests/test_rfc_pipeline_integration.py)
drives the Python driver through all fifteen stages with a stub agent and a stub `llmll`,
hermetically, in seconds, and asserts the properties a port can actually break. Its four scenarios
(`ok`, `core-excluded`, `bad-barrier`, `coverage-gap`) are hand-picked.

Replace with a transition cover over the per-stage manifest state machine, which is small and
enumerable: absent → complete; absent → stopped (gate condition); absent → failed (delegated-output
defect); complete → skipped (all three §5 conditions hold); complete → re-run (digest mismatch);
stopped → re-run; failed → re-run; complete → re-run under `--force`. Eight scenarios.

**Rev 4 correction, measured.** Rev 3 said "the four existing ones cover three of the eight." That
counted `STUB_MODE` values (four) rather than tests (fifteen), and the mode selects only what the
stub *emits*; the resume, digest and force scenarios vary other axes of the rig. Measured at
`0ed395b`: **six of the eight had coverage**, one of them (absent → failed) only for a host-language
crash rather than for a delegated-output defect, and a **ninth transition exists that the list above
omits** — artifacts present with no completion record, which §5:196-197 makes a separate clause from
the digest mismatch. The cover is complete at nine as of the harness session, with the
delegated-output half of transition 3 landing with the §3.5 work.

The criterion paid for itself twice: writing out the absent → failed transition is what sent this
proposal to §7 and produced §3, and executing it is what produced §3.5.

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

**The rule.** A halt records `stopped` iff the failed condition is one **driver-spec states as a MUST
over artifact content, identifiable by clause**, and driver-spec either mandates the halt or makes it
a §6 gate condition. Every other halt records `failed`.

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

**The three sites the harness could not classify. All resolve, and all to `failed`.**

- **`:967`** (stage K, authored roots do not typecheck). §7:283-286 requires validating a delegated
  output "against its declared shape." For a `.llmll` artifact, well-formedness under `llmll check`
  *is* that validation. Stage-contract-defined.
- **`:866`** (stage H, feasibility not established). See §6's stage-H note: §7 covers the stage, not
  the acceptance bar.
- **`:1045`** (no holes to fill). §9 defines the fill protocol per hole and states nothing about an
  empty hole set, so §4:129's residual applies. This is the correction §10 case 5 carries.

**Counts.** Of the 46 `require()` sites: 9 spec-defined (`stopped`, correct today); 26
delegated-output shape validation; 9 driver-internal invariants and tool failures; 2 pre-stage
argument validation, which fire before any stage exists and assign no stage status.

**The divergence set is 38**: the middle two classes (35 sites, all of which must become `failed`)
plus the three `AgentRunner` raises, which are not `require()` calls — `:221` timeout, `:227`
non-zero exit, `:230` declared output absent. §3.1's table disposes of the last three; §3.5's rule
disposes of the 35.

---

## 4. The run state is a sum over phases

The driver's state shape varies by stage: the wave carries a hole queue and two budgets that stage B
has no use for; stage B carries a prompt path the wave does not. Modelling that as one product
carrying every field is what forces a deep pair chain and makes a wrong-projection read typecheck.

The console `:step` state type S is unconstrained
([`TypeCheck.hs:2161-2183`](../../compiler/src/LLMLL/TypeCheck.hs) unifies it across steps and
imposes nothing else), so this is a data-modelling choice, not a harness limit.

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
`XMOD-CTOR-1` is fixed at v0.14.82 ([`CHANGELOG.md:151-157`](../../CHANGELOG.md)), so an imported
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

## 6. driver-spec §7 conformance

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
stage-contract-defined and records `failed`. **Consequence for Phase 5 §15.4:** no special sentence
is owed for stage H, which conforms to §7 as a delegated catalogue stage. The disclosure owed is
narrower: its acceptance bar is driver-defined and is not a conformance claim.

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

Three statements are owed at sub-phase 4e:

- **`fill.next-error-budget` / `fill.is-finding`.** `contention` is a substring test over
  `llmll patch`'s stderr. Unproved, and the wording is a compiler-internal string with no stability
  contract.
- **`fill.fill-accepted`.** `verifies`, `body-faithful` and `termination-proved` are substring and
  set-membership tests over `llmll verify`'s stdout, mirroring `_faithful` (`:1241-1244`) and
  `_fallbacks` (`:884-887`). Unproved. `--strict-verified-core` is deliberately not used, per §9's
  own instruction that the criterion be evaluated for the function being filled.
- **`stage.record-outcome`.** The `Outcome` constructor is chosen by the shell from §3.1's four-way
  disposition. Unproved, and it is the discrimination the Python driver lost.

These belong in the phase's gap inventory, in the same category as the FFI count and the effect
authority report.

**Rev 4 tightening.** §3.5 makes the third of these **enumerable rather than open**. Before it, "the
shell chooses the `Outcome` constructor" was an unbounded disclosure. Now it is a 46-row table with
nine `ConditionUnmet` and the rest `Errored`, plus a rule that classifies a site the table does not
list. The abstraction function is still unproved and still outside Σ_auto, but it is auditable, and
a reviewer can check a call site against the rule rather than against an intention. The first two
statements (contention, and the fill-acceptance triple) remain open: both are substring tests over
compiler output whose wording carries no stability contract.

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
| **4a** | Sequencer, manifest, resume gate, **two halt channels**. No stage bodies. | `skip.may-skip`, `stage.record-outcome` (all four `Outcome` arms) | The eight-transition cover of §2.3 passes |
| **4b** | B, C, I, and §6's validation obligations as a shared facility | none new | A delegated output that is absent, malformed, or subject-hardcoded fails the stage and is never skipped |
| **4c** | D, F, G | none new | Stage E's Phase 3 pins reproduce over D's own output |
| **4d** | H, K, N | none new | Probe-verifies / mutant-refutes polarity reproduces; stage N retains unrealisable entries in the denominator |
| **4e** | M, serial, **with contention injected under clause 1a** | `fill.fill-accepted`, `fill.next-error-budget`, `fill.is-finding`, `token.token-during` | Both retry budgets fire and are separately counted; a hole exhausting its semantic budget is a finding and never hinted; §7's three statements are written |
| **4f** | O, phase close, gap inventory | none new | Clauses 1a, 1b and 2 |

**4e is the phase.** It is where three of the six proved modules acquire their first caller.

**`liveness.advancing` gets no caller, and the reason is a filed gap.** Its precondition is over
artifact ages in seconds and there is no `wasi.fs.stat`: `wasi.clock.monotonic` reports nanoseconds
since an unspecified epoch and nothing exposes a file mtime. Filed as `FS-STAT-1`. It does not block
Phase 4, `--status` being operator plumbing the campaign's §5 item 3 defers to the retirement step,
but the phase reports that one of the six proved modules has no callable data source rather than
leaving a reader to infer it was forgotten.

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
no arm is a constructor pattern ([`CodegenHs.hs:1290-1298`](../../compiler/src/LLMLL/CodegenHs.hs)),
so a pure literal match fails through an emitter-inserted `error` call rather than through GHC's
pattern-match exception. Either way the exception is raised inside a `Command`, which is the
crash-freedom hazard `CodegenHs.hs:178` names for `wasi.fs.delete`, so the remedy is not "add a
wildcard" but "the wildcard arm must produce a defined state transition."
A narrower hole sits beside it: `isAdtExhaustive = not (null ctorNames)` (`:1283`) suppresses the
catch-all whenever any arm is a constructor pattern, and that ground fails when a literal arm is
present, exhaustiveness being checked only for known sum types
([`TypeCheck.hs:2247-2265`](../../compiler/src/LLMLL/TypeCheck.hs)). **Precondition:** a literal arm
against a sum-typed or `Result`-typed scrutinee is type-incompatible and draws `tcWarn`
(`TypeCheck.hs:2318-2324`), so the entry condition is a program that ships past a warning.
Channel: **spec is silent (gap, flag).** File with the precondition in the row text; it is a general
crash-freedom hole and should not be discovered by Phase 4.

**7. `roots.ast.json` carrying a non-ASCII byte under a C locale.** `wasi.fs.read` is `readFile`
(`CodegenHs.hs:533-535`), locale-decoded, and throws. The wave reads and rewrites this file on every
attempt, so the exposure is per-attempt.
Channel: **spec is silent (gap, flag).** `FS-ENCODING-1`: pin UTF-8 and return `RErr` on a decode
failure rather than throwing.

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

---

## 11. Verification mapping

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| Retry-budget separation, finding condition, fill acceptance (`fill.llmll`, three `def`s, six posts) | contract | **QF-LIA, auto-discharged.** Ints and bools only; body-faithful at HEAD | `FixpointEmit.hs`; `LLMLL.md §5.3.3` arithmetic class |
| Token phase discipline (`token.token-during`) | contract | **QF-LIA** via the nullary-enum int-tag discriminant | `LLMLL.md §5.3.5`, n-arm sum `EMatch`, nullary enums stay pure QF-LIA |
| Stage outcome classification, all four arms (`stage.record-outcome`) | contract | **QF-LIA.** Discharged at HEAD; Phase 4 adds the `Errored` construction site | `LLMLL.md §5.3.5` |
| Skip decision over the manifest (`skip.may-skip`) | contract | **QF-LIA.** Discharged at HEAD | `LLMLL.md §5.3.3` |
| Phase 4's own pins as new strict-core `def`s (wave partition counts, per-stage status counts) | contract | **QF-LIA for the count conjuncts; lexeme comparisons fall back** (`STRLIT-BODY-1`) | roadmap `STRLIT-BODY-1`; `spine.llmll:71-80` states the same limit for stage E |
| §6 validation, citation resolution, catalogue rules | **none.** Shell-side | Outside Σ_auto (string and JSON structure) | `LLMLL.md §5.3.5`; no `?proof-required` proposed |
| `Outcome` constructor choice at §3.1's four-way disposition | **none.** Shell-side | Outside Σ_auto | §7; `stage.llmll:8-10` proves the mapping, not the choice |
| The three abstraction functions of §7 | **none.** Shell-side substring tests | Outside Σ_auto | Disclosed, not discharged |
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
- [`driver-ll-open-work.md`](driver-ll-open-work.md) — new rows per §14.
- `INDEX.md` — one-liner for this file (doc-lead's slot).

**Driver artifacts** ([`tools/llmll-driver/`](../../tools/llmll-driver/))

- New per-stage modules rather than growth of `spine.llmll`, which is 768 lines for four stages.
- `EXPECTED_VERDICTS.json` — new refute-crux cases for the Phase 4 pins, on the
  `crux-stage-j-coverage-pin.llmll` pattern.
- `README.md:99` — add the §3.4 divergence beside `crux-gate-single-remedy` under "what the driver
  does today."

**Compiler** ([`compiler/src/LLMLL/`](../../compiler/src/LLMLL/))

- `CodegenHs.hs:506-508`, `:533-535` — `FS-ENCODING-1`. Crash-freedom fix, small, wanted before 4e.
- `TypeCheck.hs` `builtinEnv`, `ObligationAssembly.hs:442-448`, `CodegenHs` preamble —
  `wasi.fs.copy`: one signature, one `primEffect` clause, one codegen case, no new label, no new arm.
- `CodegenHs.hs:1283` — the mixed-match catch-all suppression, filed separately per §10 case 6.
- `Parser.hs:328-333` and downstream — `STATE-PROD-1`, only if taken.

**Harness** ([`scripts/`](../../scripts/))

- `tests/test_rfc_pipeline_integration.py` — the stub agent moves from env to argv; the stub `llmll`
  gains the §10 case 1 contention injection; the scenario set grows to eight; a second driver comes
  under test.
- `build_smoke.sh` — the Phase 4 artifact enters the build gate per campaign §3a.

---

## 13. Risks

1. **The live run cannot exercise contention.** Scope. Clause 1a injects it; clause 2 cannot. Bite:
   **does not block**; requires the §10 case 1 disclosure and the campaign-sentence correction.
2. **The abstraction functions are unchecked and one of them decides verdict-versus-accident.**
   Scope, claim-discipline. §7. Bite: **complicates**; the disclosure is cheap and the alternative is
   an overclaim in the phase close.
3. **`FS-ENCODING-1` is a crash-freedom hazard.** Soundness of the effect runtime. Bite: **blocks 4e
   on any non-UTF-8 locale, which includes a default CI runner.**
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

---

## 14. Gaps filed by this proposal

| Tag | What | Blocks |
|---|---|---|
| `FS-ENCODING-1` | `wasi.fs.read` / `write` inherit the locale; a decode failure throws inside a `Command` | Sub-phase 4e on a non-UTF-8 locale |
| `FS-COPY-1` | No byte-faithful copy; `wasi.fs.copy` proposed in §8 | Nothing; stage D's blindness argument is weaker without it |
| `FS-STAT-1` | No file mtime, so `liveness.advancing` has no callable data source | Nothing in Phase 4; `--status` at the retirement step |
| `PROC-ENV-1` | `wasi.proc.run` has no env parameter | Nothing; named-not-scheduled, and deliberately so |
| `STATE-PROD-1` | At most one payload per constructor; no n-ary product | Nothing; ergonomics |
| (unnamed) | `emitMatch` suppresses its catch-all on any constructor arm, including in a mixed match with literal arms | Nothing; general crash-freedom hole, needs a row |

---

## 15. Revision history and professor review log

Both professor rounds were conversational. No standalone `driver-ll-phase4-review.md` exists, so
there is no M2 fold-and-archive to trigger; the findings are recorded here.

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

**Standing note.** The delegated-stage disposition produced three derivations in three turns and a
fourth turn made it operational. §3.1 is the settled table, §3.2 the derivation it rests on, and
§3.5 the rule that applies it per call site. A fifth challenge has to engage §4:132-136's
verdict-versus-accident criterion directly; none of the failed derivations touched it.
