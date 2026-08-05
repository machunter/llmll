# DRIVER-LL Phase 4: what extending the harness found

> Session 2026-08-04, harness at `0ed395b` (`main`), compiler v0.14.83.
> Brief: [`../../docs/design/driver-ll-phase4-proposal.md`](../../docs/design/driver-ll-phase4-proposal.md)
> (Rev 3, SETTLED) items (a) through (d).
> Surface: [`../../scripts/tests/test_rfc_pipeline_integration.py`](../../scripts/tests/test_rfc_pipeline_integration.py),
> [`../../scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py).

## Headline finding

Items (a), (b) and (c) are done and the suite goes 15 to 19 tests, all passing. **Item (d) is
blocked and should not be attempted as briefed.** The brief describes "four conditions" recorded
`stopped` that must be `failed`. The driver's actual halt surface is **46 `require()` call sites**,
and the disposition is a property of the *call site*, not of the mechanism: nine of them halt on
conditions driver-spec defines and are correct as they stand, twenty-six validate delegated-output
shape, nine are driver-internal or tool failures, and two fire before any stage exists. Three sites
cannot be classified from the proposal's §3.1 table at all. Rewriting the halt channel on a
four-condition premise would move nine correct sites to the wrong status.

Two further corrections to the proposal are below (F-2, F-5), and both are the same error shape the
proposal itself diagnosed twice: a disposition derived from the driver's implementation rather than
from driver-spec §4's criterion.

## Sample composition

| | Before | After |
|---|---|---|
| Tests in `test_rfc_pipeline_integration.py` | 15 | 19 |
| Passing | 15 | 19 |
| Wall clock | 9.4 s | 12.0 s |
| Stages ever executed by a test | 14 of 16 | 15 of 16 |
| `STUB_MODE` values | 4 | 5 |

Harness SHA `0ed395b`. No compiler invocation: the suite runs against a stub `llmll`, by design
(`test_rfc_pipeline_integration.py:20-21`, hermetic).

## Verified findings

### F-1. The delegated-stage disposition is per-call-site, and item (d) is blocked on it

**Priority:** Blocker (for item (d) only; (a)-(c) are unaffected)
**Consumer:** language-team

#### Evidence

46 `require()` call sites in `scripts/rfc_to_implementation.py`, classified against proposal §3.2's
criterion (is the condition one *driver-spec* defines, or one the *stage contract* defines):

| Class | n | Disposition today | Disposition under §3.1 | Divergent? |
|---|---|---|---|---|
| Spec-defined gate and citation conditions | 9 | `stopped` | `stopped` | **No** |
| Delegated-output shape validation | 26 | `stopped` | `failed` | Yes |
| Driver-internal invariants and tool failures | 9 | `stopped` | `failed` | Yes, different reason class |
| Pre-stage argument validation | 2 | n/a | n/a | No stage status assigned |

The nine correct-today sites: `:355` (barrier not in the closed list, driver-spec §6:229-231),
`:782` and `:788` (quoted words must occur in the artifacts, §7:305-309), `:811`, `:815`, `:821`
(stage G2's citation resolution, §7:296-303), `:936` and `:939` (gate J's two conditions,
§6:222-231), `:1003` (gate L, §11).

`:355` is the one that matters most, because it sits **inside `check_dispositioned`** alongside five
shape checks. The same function halts on both a spec-defined condition and stage-contract shape, so
"validation failed" does not determine the status. `test_exclusion_outside_the_barrier_list_halts_the_run:192-204`
already asserts `m["G"]["status"] == "stopped"` for exactly this case, and it is right.

#### Three sites §3.1 cannot classify

- **`:866`**, stage H, "feasibility not established". `grep -n "feasibilit\|probe"` over
  `targets/driver-spec.txt` returns **zero hits**. See F-3.
- **`:1045`**, stage M, "no holes to fill". See F-2.
- **`:967`**, stage K, "authored roots do not typecheck". A delegated output failing a check the
  driver defines, or the §7 shape validation of a `.llmll` artifact. §3.1 admits both readings.

#### Implication

Implication for language-team: §3.1's row "Declared output present, fails validation → `failed`" is
under-determined. The discriminator §3.2 gives (spec-defined versus stage-contract-defined) is the
right one and it cuts *within* a single validator function, so the disposition attaches to the
clause, not to the stage or to the validator. A revision that lists the nine spec-defined conditions
by citation would make item (d) mechanical.

#### Acceptance

Item (d) closes when each of the 46 sites carries a disposition traceable to a driver-spec clause or
to §3.1's residual, and the suite asserts the status at a site of each class.

---

### F-2. Proposal §10 case 5 derives its disposition from the driver, not from the specification

**Priority:** High
**Consumer:** language-team

#### Evidence

Proposal §10 case 5 states that an empty hole set halts as `ConditionUnmet` and records `stopped`,
"'no holes to fill' being a condition the pipeline defines (`:1047`)". `:1047` is
`rfc_to_implementation.py`, the driver's own source.

`grep -n "hole\|fill"` over `targets/driver-spec.txt` returns 12 hits, all in §9 and §10, and none
of them says what happens when the subject presents no holes. §9 defines the fill protocol per hole;
§10 defines token lifetime. The condition is not in the specification.

#### Why we saw what we saw

§4:125-127 assigns `stopped` only to conditions *the specification* defines. An undefined condition
falls to §4:129's residual, which is `failed`. So §10 case 5's expected behaviour is the opposite of
what it states, on the proposal's own §3.2 derivation.

#### Implication

Implication for language-team: this is the third instance in this proposal's history of a
disposition derived from the implementation rather than from §4's criterion, and the proposal
diagnosed the first two itself (§3.3). §10 case 5 needs re-deriving or the condition needs adding to
the specification.

#### Acceptance

§10 case 5 cites a driver-spec clause, or states `failed`.

---

### F-3. Stage H is a stage driver-spec does not describe

**Priority:** Medium
**Consumer:** language-team

#### Evidence

`grep -n "feasibilit\|probe"` over `experiments/rfc-swarm/targets/driver-spec.txt`: **0 hits**. The
stage registry carries `Stage("H", "feasibility probes", "agent", stage_H_feasibility,
("07-feasibility/feasibility.json",))` (`:1350-1351`), and `:833-869` implements a probe-and-mutant
acceptance bar that halts the run.

#### Implication

Implication for language-team: Phase 5's §15.4 conformance claim enumerates the driver's stages
against the specification. One of the fifteen has no clause to conform to, so the claim needs a
sentence about it rather than a row. This also bears on F-1: `:866`'s disposition cannot be derived
until stage H's status in the specification is settled.

---

### F-4. Two of sixteen stages had never been executed by any test; one still has not

**Priority:** High
**Consumer:** compiler-engineer, experiment-lead

#### Evidence

Before this session, `grep -n "stage M\|\"M\"" test_rfc_pipeline_integration.py` returned three
hits: `:231` (M in a stage list for a run that halts at L), `:246` (`assert "M" not in m`), and
`:354` (an artifact-declaration check). **No test executed the wave.** The default stage list every
test used is `"A,B,C,D,E,F,G,H,I,J,K,L"`, which also omits **G2**.

The wave carries the fill protocol, the two separated retry budgets and the token discipline, which
are §9 and §10 in full and three of the six proved cores in `tools/llmll-driver/`. This is the same
shape as the `llmll replay` root cause at v0.14.83: a subsystem with unit tests over mock fixtures
and no gate that ran it end to end.

Stage M now runs (F-5's two new tests). **G2 still does not.** Driving it surfaces why: with G2 in
the stage list the run reaches it and reports `unresolved: 2` before stopping, because the stub's
rows quote `"q"` against SPEC lines that do not contain it, so `_span_coverage` scores every
citation below `CITATION_RESOLVES_AT` (`:634-646`). Making G2 runnable needs stub rows whose quotes
are drawn from the pinned bytes.

#### Implication

Implication for compiler-engineer: sub-phase 4e's acceptance now has a reference execution to
compare against. Implication for experiment-lead (this role): G2's stub fixtures are the next
harness item and are not bundled here.

---

### F-5. The transition cover was better than the proposal measured, and is now complete

**Priority:** Medium
**Consumer:** language-team

#### Evidence

Proposal §2.3 states that "the four existing ones cover three of the eight" transitions. Measured
against the 15 tests present at `0ed395b`:

| # | Transition | Covered before | By |
|---|---|---|---|
| 1 | absent → complete | yes | `test_pipeline_runs_through_both_gates` |
| 2 | absent → stopped (gate) | yes | three tests (J twice, L once) |
| 3 | absent → failed | **partially** | `test_a_crashing_stage_...` covers a host-language crash, not a delegated-output defect |
| 4 | complete → skipped | yes | `test_a_completed_stage_is_still_skipped_on_resume`, `test_an_untouched_run_...` |
| 5 | complete → re-run (digest mismatch) | yes | `test_a_modified_artifact_...`, `test_a_manifest_without_digests_...` |
| 6 | stopped → re-run | yes | `test_a_failed_gate_is_not_bypassed_...` |
| 7 | failed → re-run | **no** | added this session |
| 8 | complete → re-run under `--force` | **no** | added this session |
| 9 | artifacts present, no record → re-run | yes | `test_artifacts_without_a_completion_record_...`; **omitted from §2.3's list** |

Six of eight had coverage, one only for a different reason class, and a ninth transition exists that
§2.3 does not list.

#### Why we saw what we saw

§2.3 counted `STUB_MODE` values (four: `ok`, `core-excluded`, `bad-barrier`, `coverage-gap`) rather
than tests (fifteen). The mode selects what the stub *emits*; the resume, digest and force scenarios
vary other axes of the rig (workdir reuse, manifest edits, artifact edits) and do not need a mode of
their own.

#### Implication

Implication for language-team: §2.3's coverage claim should be corrected before it is quoted as a
gap. Transition 3 remains partial and closes with item (d), since a delegated-output defect does not
produce `failed` today.

---

### F-6. The contention branch fires, and the test that proves it can fail

**Priority:** High (this is proposal §10 case 1's witness)
**Consumer:** compiler-engineer

#### Evidence

`STUB_MODE=wave` injects one stale `patch` and one unfaithful tree verify. Measured outcome:
`wave.json` records `{"status": "filled", "attempts": 2}` and the stub's own counter records three
`patch` invocations (one stale, one accepted-then-reverted, one accepted).

Two attempts against three patches is the separation: the contention retry re-submitted the same
body against a fresh checkout without consulting the agent, and spent nothing.

**Mutation check, because a passing assertion is not evidence.** Replacing `_apply`'s retry
predicate at `:1192-1194` with an unconditional `return False, err` (contention treated as ordinary
error) produces `attempts: 3` and fails the test with its own predicted message. Reverted; suite
green at 19.

| Run | `_apply` predicate | `attempts` | Test |
|---|---|---|---|
| baseline | as shipped | 2 | pass |
| mutant | contention spends the budget | 3 | fail |
| premise (`STUB_MODE=ok`) | as shipped | 1 | pass, and unaffected by the mutant |

#### Implication

Implication for compiler-engineer: this is the reference execution for sub-phase 4e. An LLMLL wave
driven by the same stub must produce the same three-patch, two-attempt trace. The premise run
(`attempts == 1`, no injection) is what distinguishes a wave that works from a wave that is merely
not crashing.

## Withdrawn items

None from this session's own analysis. F-2 and F-5 withdraw claims made in
`driver-ll-phase4-proposal.md`; they are routed to language-team rather than recorded here as
withdrawals, since this role does not own that document.

## Null results

**Hypothesis:** the `RFC_PIPELINE_*` environment channel would have live consumers beyond the test
stub, making item (a) a breaking change for operators. **Null.** Counting *consumers* (code that
reads the variables) separately from the *producer*: before this session the repository held two
consumers, both inside the stub agent in `test_rfc_pipeline_integration.py`, and one producer,
`AgentRunner.run` at `rfc_to_implementation.py:203-205`. After the change there are zero consumers
in the repository.

**The producer is deliberately left in place.** An operator's own runner may read the variables, and
nothing in this session measured that population, so removing the export would be a breaking change
made on no evidence. The LLMLL driver simply will not have the export, which is the asymmetry item
(a) exists to absorb: a runner that works against both drivers must take its paths from argv.

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---|---|---|---|
| F-1 | Disposition is per-call-site; item (d) blocked | language-team | Blocker | 1 turn to enumerate the nine |
| F-4 | Two stages never executed; G2 still is not | compiler-engineer, experiment-lead | High | G2 fixtures, ~1 session |
| F-6 | Contention witness, mutation-checked | compiler-engineer | High | done |
| F-2 | §10 case 5 derived from the driver, not the spec | language-team | High | small |
| F-5 | Transition cover mis-measured; now complete | language-team | Medium | small |
| F-3 | Stage H unspecified | language-team | Medium | bears on Phase 5 |

## Changes made this session

- `scripts/tests/test_rfc_pipeline_integration.py`: stub agent reads argv rather than
  `RFC_PIPELINE_*`; rig passes `{out} {prompt}`; stub `llmll` gains `build --emit`, `checkout`,
  `patch` and a tree-aware `verify` so stage M can run; `STUB_MODE=wave` injects contention and one
  unfaithful verify; four tests added (wave premise, contention witness, failed → re-run, `--force`).
- `scripts/rfc_to_implementation.py`: **unchanged.** Item (d) is blocked on F-1.

---

# Second session: the halt-channel repair, and two findings the sweep produced

F-1 closed as proposal §3.5 and §3.6, which unblocked item (d). This session executed it. Two new
findings came out of the language-team sweep of driver-spec §8 through §15.4 rather than out of the
harness, and are recorded here because both are findings about the campaign's own target and product.

## F-7. Stage O is the only delegated stage with no validator, and driver-spec §13 is its spec

**Priority:** High  **Consumer:** compiler-engineer (sub-phase 4f), language-team (settled)

### Evidence

`stage_O_writeup` (`scripts/rfc_to_implementation.py`, kind `agent`, declared output `REPORT.md`)
has **zero** `require()` call sites. Measured across the stage registry, every other delegated stage
has at least one. Three of driver-spec §13's eight MUSTs are restated inside the function's own
docstring, which reaches the model as prompt text and is checked by nothing.

### Why we saw what we saw

The harness leg exercised **transitions**, not stage bodies, so a stage whose body validates nothing
produces no transition anomaly. The transition cover (F-5) is complete at nine and still cannot see
this: stage O either completes or is never reached.

### Implication

Implication for compiler-engineer: sub-phase 4f gains a validator. Proposal §6.2 settles the split,
one mechanizable clause (§13:443-446, perturbation omission, checkable as a set difference over the
`name` key of stage N's kill matrix) and seven disclosure-only. Implication for experiment-lead: the
transition cover is the wrong instrument for stage-body obligations, and a body-obligation cover is
a separate instrument this harness does not have.

### Acceptance

A test in which stage N reports a survivor, stage O omits it, and the run records `stopped` with
`outcome: PartialThenHalt`. Not written this session: stage O is not yet ported and the Python
driver's stage O is out of scope for the disposition repair.

## F-8. `SPEC-TIER-1`: driver-spec's tiering clause cannot classify its own §13

**Priority:** Medium  **Consumer:** language-team (filed), Phase 5

### Evidence

§15.1:509 asserts that "the obligations of sections 4 through 13 are properties of sequencing and
state over enumerated statuses and bounded counters." That is false of §13:433-435 and §13:448-454,
which constrain the framing of natural-language prose. §15.1's own enumeration at `:512-515` omits
reporting. §15.1:504-505 requires every obligation to sit in exactly one of three tiers, and §13's
prose MUSTs fit none: not proved (not properties of enumerated statuses), not §15.2 (not effectful
operations reached through a capability), not §15.3 (whose list is prompt content, agent-internal
behaviour, and OS guarantees).

### Implication

This is a defect in the **target**, which is the campaign's product rather than its input. driver-spec
is pinned under §14:473-474, so it is recorded and not repaired. It constrains what Phase 5's §15.4
conformance claim may assert. No tier is manufactured for the orphaned obligations.

## Changes made this session

- `scripts/rfc_to_implementation.py`: **the halt-channel repair.** A `Halt` base with three
  subclasses replaces the single `StopCondition`. `require()` now raises `StageFailure` (recorded
  `failed`), which makes the **safe** direction the default per §4:135-137; `require_spec(…, clause)`
  raises `StopCondition` (recorded `stopped`) and takes the driver-spec clause as a **required**
  argument, so a stage-contract check cannot claim to be a gate without naming one;
  `require_written(…, clause)` raises `PartialHalt` for the single §4:146-147 site. The main loop
  gains a third handler and every manifest row now carries `outcome`, naming the LLMLL constructor
  the port maps to (`tools/llmll-driver/stage.llmll`).
- `scripts/tests/test_rfc_to_implementation.py`: 18 assertions moved from `StopCondition` to
  `StageFailure`; 9 kept, and those 9 are exactly the spec-defined sites.
- `scripts/tests/test_rfc_pipeline_integration.py`: two `STUB_MODE` values added
  (`bad-extraction`, `probe-survives`, plus `agent-flaky`); four tests added.

### Measured

| | Before | After |
|---|---|---|
| Tests, whole suite | 111 | 115 |
| Passing | 111 | 115 |
| `require`-family call sites | 46, one form | 46, three forms |
| Sites recording `stopped` | 46 | 10 |
| Divergence set closed | 0 of 37 | 37 of 37 |

Classification audit, reproducing proposal §3.5 and §3.6 from the tree rather than from the document:
9 `require_spec`, 1 `require_written`, 36 `require` of which 2 are pre-stage, giving 34 stage-level
sites plus the three `AgentRunner` raises. **37.**

### Mutation checks

A guard that never fires is decorative, so each change was reverted and the suite re-run.

| Mutant | Killed by | Result |
|---|---|---|
| `require()` reverts to `StopCondition` (the original defect) | 10 tests | killed |
| Stage H uses `require_spec` rather than `require_written` | `test_stage_H_records_partial_then_halt_after_writing_its_output` | killed |
| Wave fill loop catches `StopCondition` rather than `Halt` | `test_an_agent_failure_inside_the_wave_retries_the_hole_and_never_halts` | **survived at first, then killed** |

The third is the finding inside the repair. Splitting the channels made the three `AgentRunner`
raises `StageFailure`, and the wave's per-hole retry handler named only `StopCondition`. Left that
way, one agent timeout would have propagated out of the per-hole worker and recorded the whole of
stage M `failed`, discarding every sibling hole's completed work. The first mutation run showed 114
passing with the handler reverted, so **nothing in the suite covered it**. The test named above was
written to close that, and it now kills the mutant.

### Null result

`:546` (stage E) was checked against §4:146-147's artifact-state axis and does **not** move. It fires
after `reconcile.stdout.txt` is written, but the stage registry declares only `SUMMARY.json`, and
proposal §3.6 settles "its artifacts" as declared outputs. Under an any-file-written reading it would
have moved. Recorded because the two readings differ on exactly this site and on no other, which is
what makes the reading checkable rather than stipulated.
