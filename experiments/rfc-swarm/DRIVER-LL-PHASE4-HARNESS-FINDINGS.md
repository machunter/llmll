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

---

# Session 2026-08-05: the sub-phase 4a harness leg

> Harness at `c4c07f5` (`main`), compiler **v0.14.84**.
> Brief: [`../../docs/design/driver-ll-phase4-proposal.md`](../../docs/design/driver-ll-phase4-proposal.md)
> **Rev 6**, §2.3 (the eleven-cell cover) and §10 cases 15 through 17. Task #9 of the restart record.
> Surface: the same two files.

## Headline finding

Rev 6 predicted five things about sub-phase 4a's cover and **four held**. T7 (a complete record with
one declared artifact deleted) re-runs the stage and prints no reason line for it, both measured.
The sequencer crashes on a corrupt manifest, measured on two shapes and on **a third Rev 6 did not
name**. The one prediction that failed is Rev 6's account of *why* T7 matters: it claimed the
reference can reach the cell through its own write path, and it cannot, because
`AgentRunner.run` asserts the declared output exists on every delegated call. Rev 6's derivation
grepped `stage.outputs`, the declared list on the `Stage` record, and the check is written against
`out_name` one level down. **T7 is reachable by deletion and not by the reference recording complete
over a missing artifact**, at least for the eleven of sixteen stages that check covers.

Suite goes 23 to 28 tests in this file, 115 to 120 across `scripts/tests/`, all passing.

## Sample composition

| | Before | After |
|---|---|---|
| Tests in `test_rfc_pipeline_integration.py` | 23 | 28 |
| Tests across `scripts/tests/` | 115 | 120 |
| Passing | all | all |
| Wall clock, this file | 15.6 s | 17.8 s |
| Transition-cover cells with a test | 10 of 11 | **11 of 11** |
| `STUB_MODE` values | 6 | 7 (`silent-scope` added) |

Compiler v0.14.84 (`llmll version`). Hermetic: `file://` source, stub agent, stub `llmll`. Every
measurement below is deterministic and was reproduced by a standalone probe script before any test
was written, so the assertions are chosen from observed behaviour rather than predicted behaviour.

## Verified findings

### F-9. T7 is real, re-runs the stage, and reports nothing

**Priority:** High
**Consumer:** language-team (confirms Rev 6 §2.3), compiler-engineer (4a acceptance)

#### Evidence

Probe: run stages `A,B,C` to completion, `unlink` stage B's `scope.md` under its `01-scope`
directory, resume with the same workdir
and no `--force`. Per-stage grep of the resume's stdout:

| Stage | ran | skip line | digest line | no-record line |
|---|---|---|---|---|
| A | no | yes | no | no |
| **B** | **yes** | **no** | **no** | **no** |
| C | no | yes | no | no |

`scope.md` restored, `B` re-recorded `complete`. The only stdout lines naming B are its own stage
line, `agent[scope] -> …`, and `agent[scope] ok`. Now pinned by
`test_a_declared_artifact_deleted_from_a_complete_stage_forces_a_rerun`.

#### Why we saw what we saw

`mismatched` is computed under `if recorded and artifacts` (`rfc_to_implementation.py:1880`), so with
`artifacts` false it stays empty and the `if mismatched` reason branch (`:1890`) does not fire; the
`elif artifacts and not recorded` branch (`:1894`) is false for the other half of the conjunction.
The skip test at `:1887` still fails on `artifacts`, so the stage runs. Detection works; reporting
was never written for this cell.

#### Implication

Implication for language-team: Rev 6 §2.3's T7 row stands as written, and the eleven-cell count is
now a measured cover rather than a derived one. §5 attaches a MUST-report to T6 and a SHOULD to T8
and nothing to T7, so the silence is conformant and the test does not pin it. Rev 6's instruction to
the port to *reproduce* the silence was already withdrawn; nothing here reopens it.

#### Acceptance

Closed. The cell has a test and the test asserts the decision.

### F-10. Rev 6's T7-reachability derivation is refuted: the reference already enforces §7:279

**Priority:** High
**Consumer:** language-team

#### Evidence

Rev 6 §2.3 finding 3: "`stage.outputs` is consulted at exactly three sites (`:1877`, `:1881`,
`:1955`) and none asserts presence before recording complete." The grep is accurate and the
conclusion does not follow. `AgentRunner.run` (`rfc_to_implementation.py:274-277`):

```
if not out_path.exists():
    raise StageFailure(f"agent[{label}] exited 0 but wrote no {out_name}; "
                       f"the stage contract was not met …")
```

Probe with a stub agent that exits 0 without writing `scope.md`: `rc=3`, `B.status = failed`,
`B.outcome = Errored`, detail `agent[scope] exited 0 but wrote no scope.md`. Stage C never attempted.
Now pinned by `test_an_agent_that_exits_zero_without_writing_records_failed`.

Coverage of the check, by stage kind (measured from the registry): **11 agent** stages
(B, C, D, F, G, H, I, K, M, N, O) route every delegated output through `AgentRunner.run` and reach
it; **2 mechanical** (A, E) and **3 gate** (G2, J, L) write their outputs in driver code and have no
generic equivalent. After a green twelve-stage run, zero declared artifacts were missing and zero
`outputs` maps were short.

#### Why we saw what we saw

The obligation is enforced per delegated *call*, against `out_name`, rather than per declared
*output*, against `Stage.outputs`. Both are the same requirement; only one is reachable by grepping
the registry field. This is the third time in this phase that a claim was right about a defect and
wrong about its mechanism.

#### Implication

Implication for language-team: Rev 6 §2.3's third T7 finding should be struck and replaced. T7's
reachability rests on deletion, not on the reference's own write path, and the argument that the
cell is "reachable without operator interference" does not survive for the eleven agent stages. The
residue is narrower and worth stating precisely: the five mechanical and gate stages have no generic
presence check, so for those the own-write-path route is **unmeasured** rather than closed. This
harness cannot construct that case without editing a stage body, which would change the subject.

Also: §10 case 3 ("declared output absent, agent exit 0 → failed") describes behaviour the reference
already has. It is not a divergence and should not be counted as one.

#### Acceptance

Closed on the agent side by the new test. The mechanical and gate residue closes if and when a
generic post-stage presence assertion is added, which is a driver change nobody has asked for.

### F-11. The sequencer crashes on three manifest shapes, at three sites, and Rev 6 named two

**Priority:** High
**Consumer:** language-team, compiler-engineer (4a must handle all three)

#### Evidence

Measured before the guard, all three exiting **1** with a traceback and writing nothing:

| Manifest content | Exception | Site |
|---|---|---|
| `{"stages": {"A": ` | `json.decoder.JSONDecodeError` | `read_json`, `:208-209`, called at `:1856` |
| `[]` | `AttributeError: 'list' object has no attribute 'setdefault'` | `:1857`, the line after the read |
| `{"stages": [], "rfc_url": "x"}` | `AttributeError: 'list' object has no attribute 'get'` | **`:1875`, inside the stage loop** |

Rev 6 §10 named the first two. The third survives both a JSON-decode guard and an object-type guard,
because `{"stages": []}` is an object and `setdefault` on it succeeds; it crashes later, on the first
stage's resume check, which is the shape the resume gate actually indexes.

#### Why we saw what we saw

`read_json` is a bare `json.loads` and the top-level handler catches `Halt` only (`:1969-1976`), so
anything that is not a deliberate halt escapes. The three shapes fail at three different depths
because each survives the previous guard.

#### Implication

Implication for language-team: Rev 6 §10 cases 16 and 17 are confirmed and a **third case is owed**,
`stages` present but not an object. Rev 6's classification is upheld on the point it argued against
the professor: this is **not** a §4 violation, §4's MUSTs being scoped to "a stage that halts"
(`driver-spec.txt:125-143`) and this read preceding every stage. The reference-repair routing is the
one taken here.

Implication for compiler-engineer: the port needs a defined transition for all three, not two. The
LLMLL side reaches the first through `RErr` on `wasi.fs.read`; the second and third are shape checks
after a successful read and need a decision each.

#### Acceptance

Closed by `read_manifest` and three tests. Positive witness recorded below.

## Withdrawn items

- **"The reference can record `complete` over a missing declared output."** Rev 6 §2.3 finding 3.
  Refuted by F-10 for the eleven agent stages; unmeasured for the five mechanical and gate stages.
  The claim as stated is withdrawn, not narrowed by the author's own choice: the probe disconfirmed
  it on the first stage tried.
- **F-5's "the cover is complete at nine"** (2026-08-04 session, this file) is superseded. Nine was
  right about what §2.3 then listed and wrong as a claim about the state space: T4 and T7 were both
  missing. The count is eleven and every cell now has a test.

## Null results

- **Hypothesis: T7's silence is a §5 violation.** No support. §5:182-183 attaches a MUST-report to
  the digest case and §5:189-191 a SHOULD to the no-record case; the text imposes nothing on skip
  condition (b) failing alone. n = 1 spec reading, and the required evidence would have been a
  reporting clause covering the cell. There is none, so the silence is conformant and the test does
  not assert it.
- **Hypothesis: a green twelve-stage run leaves at least one short `outputs` map**, via `:1955`'s
  existence filter. No support: zero missing artifacts and zero short maps across 12 recorded stages.
  The filter is reachable in principle and unreached in practice under the stub configuration.

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---|---|---|---|
| F-9 | T7 re-runs, silently; cell now covered | language-team, engineer | High | done |
| F-10 | §7:279 already enforced at `AgentRunner.run`; Rev 6 derivation refuted | language-team | High | Rev 7 text |
| F-11 | Three corrupt-manifest shapes, not two | language-team, engineer | High | done + Rev 7 text |

## Changes made this session

- `scripts/rfc_to_implementation.py`: `read_manifest()` added beside `read_json()` and called at the
  resume read. Guards all three shapes, raises `StageFailure`, and names a remedy in the message
  (deleting the manifest is not data loss, since §5:189-191 re-runs any stage whose artifacts are
  gone). `StageFailure` rather than `StopCondition` because a corrupt manifest is not a condition
  driver-spec defines; the top-level handler collapses both to exit 2 regardless.
- `scripts/tests/test_rfc_pipeline_integration.py`: one `STUB_MODE` added (`silent-scope`, the
  stage-level sibling of `agent-flaky`'s per-hole behaviour) and five tests.

### Measured

| | Before | After |
|---|---|---|
| Tests, whole `scripts/tests/` | 115 | 120 |
| Passing | 115 | 120 |
| Cover cells with a test | 10 of 11 | 11 of 11 |
| Corrupt-manifest shapes handled as decisions | 0 of 3 | 3 of 3 |

### Positive witness

Required by the project's positive-witness discipline: a guard green on both sides of its patch has
not been shown to observe anything. The driver change was stashed and the four sequencer-level tests
re-run against the unguarded tree.

| Test | Guard removed | Guard restored |
|---|---|---|
| `…truncated_manifest_halts_as_a_decision_not_a_traceback` | **FAILED** (`assert 1 == 2`) | passed |
| `…manifest_that_is_not_an_object_halts_as_a_decision` | **FAILED** (`assert 1 == 2`) | passed |
| `…manifest_whose_stages_key_is_not_an_object_halts` | **FAILED** (`AttributeError … 'get'` at `:1875`) | passed |
| `…agent_that_exits_zero_without_writing_records_failed` | passed | passed |

The fourth passing on both sides is correct and is the point of F-10: it pins behaviour that already
existed, so no patch of this session's should be able to change it. The other three are the guard's
witness.

### Gates

`pytest scripts/tests/` 120 passed; `scripts/doc_path_lint.py` 754 citations all resolve;
`rfc_to_implementation.py --self-test` PASS (RFC-COV-1: 46/46 Encoded rows cited, 15/15 core rows).

# Session 2026-08-05, second leg: the T7 mutation check

> Harness at `2b82464` (`main`), compiler **v0.14.85**.
> Question put to this leg: the port's T7 scenario did not discriminate, and was repaired
> (`sequencer.llmll:485-496`). **Does the Python-side T7 have the same masking defect?**
> Read-only on the reference except for three mutations, each reverted before the next. No driver
> change survives this leg; `git diff -- scripts/rfc_to_implementation.py` is empty.

## Headline finding

**No. The Python-side T7 is sound, and this is a confirmation rather than a defect.** Under
mutation, `test_a_declared_artifact_deleted_from_a_complete_stage_forces_a_rerun` dies to the
removal of skip condition (b) and survives the removal of condition (c); the T6 test
(`test_a_modified_artifact_forces_a_rerun`) does the exact opposite. The two cells are therefore
independently discriminating and separable from each other, which is the stronger of the two
properties the check was asked for. n = 3 mutations over 5 tests, 15 test-mutant cells plus a
5-cell baseline, all deterministic under the hermetic stub configuration.

The port's defect does not carry over, and F-13 gives the mechanism: the reference evaluates
condition (c) *under a guard* that already requires (b), so (c) is never computed on an absent
artifact and cannot mask (b). The port derived both conditions from one `wasi.fs.sha256`, whose
`RErr` on a missing path made (c) fail alongside (b).

## Sample composition

Reference under test: `scripts/rfc_to_implementation.py:1931-1952`, the resume gate. Test file:
`scripts/tests/test_rfc_pipeline_integration.py`. Five tests selected, one per §5 skip-decision
cell reachable from this gate. Compiler v0.14.85 (`llmll version`), Python 3.9.6. Wall clock 4.2 s
to 4.4 s per mutant, so the whole matrix cost under 30 s.

| Mutation | Edit applied | Reading |
|---|---|---|
| baseline | none | HEAD |
| **M2** | `:1933` `artifacts = all(...exists())` → `artifacts = True` | (b) hardcoded true at its definition, the port's own perturbation |
| **M1** | `:1943` `recorded and artifacts and not mismatched` → `recorded and True and not mismatched` | (b) dropped from the DECISION, (c) left exactly as written |
| **D** | `:1943` `recorded and artifacts and not mismatched` → `recorded and artifacts and True` | (c) dropped from the DECISION, (b) left exactly as written |

M1 and D mutate the same expression, one conjunct each, which is what makes the pair a clean
discrimination test rather than two unrelated perturbations.

## Verified findings

### F-12. T7 and T6 each die to their own conjunct and survive the other's

**Priority:** High
**Consumer:** language-team (Rev 7 §2.3 cover claim), experiment-lead

#### Evidence

| Test | cell | baseline | M2 (b) at def | M1 (b) at decision | D (c) at decision |
|---|---|---|---|---|---|
| `…declared_artifact_deleted_from_a_complete_stage…` | **T7** | pass | **FAILED** (crash) | **FAILED** (decision) | pass |
| `…a_modified_artifact_forces_a_rerun` | **T6** | pass | pass | pass | **FAILED** |
| `…artifacts_without_a_completion_record…` | T8 | pass | pass | pass | pass |
| `…an_untouched_run_still_skips_everything` | skip-still-works | pass | pass | pass | pass |
| `…a_manifest_without_digests_is_not_trusted` | (c) via absent digest | pass | pass | pass | **FAILED** |

Under M1 the T7 failure is on the decision assertion at
`test_rfc_pipeline_integration.py:571-572`, "the stage whose artifact is gone must RUN", and the
resume's stdout contains the line the test pins as must-not-appear:

```
stage A (intake and provenance pinning): already complete, skipping
stage B (scope decision): already complete, skipping      <- artifact deleted, skipped anyway
stage C (normativity rubric): already complete, skipping
```

Exit code stayed 0 and `mismatched` stayed empty, so condition (c) contributed nothing to the
decision. That is the whole question answered: with (b) removed, nothing else refuses the skip.

Under D the T6 failure comes with no reason line at all, because the skip `continue` at `:1944`
precedes the `if mismatched` diagnostic at `:1946`, so the stage is skipped before the report is
reached. The `without_digests` test fails for the same reason.

#### Why we saw what we saw

The gate computes `mismatched` under `if recorded and artifacts:` (`:1936`). With an artifact
deleted, `artifacts` is false, the loop does not run, and `mismatched` is `[]`. Condition (c) is
therefore *vacuously satisfied* on a missing artifact, and the only conjunct that can refuse the
skip is (b). This is the opposite of the port's pre-repair arrangement, where (c) was *falsified*
by a missing artifact.

#### Implication

Implication for language-team: the Rev 7 claim that the cover is eleven of eleven covered survives
this check for T7, and the cover is stronger than a cell count suggests, since T6 and T7 are
mutually distinguishable rather than merely both green. The T7 docstring's account of the mechanism
(`:553-559`, "`mismatched` is computed under `if recorded and artifacts` and is therefore empty")
is confirmed by execution and not only by reading.

#### Acceptance

Closed. Re-running the M1/D pair after any change to the resume gate reproduces the 2x2; a future
gate where T7 survives M1, or where T6 and T7 die to the same mutation, would reopen it.

### F-13. The port's masking mechanism does not transfer, because the reference guards (c) behind (b)

**Priority:** Medium, and Defence-in-depth for its second half
**Consumer:** compiler-engineer, language-team

#### Evidence

Port, `tools/llmll-driver/sequencer.llmll:29-38` and `:485-496`, both read-only this leg:
`artifacts-present` and `digests-match` are BOTH derived from one `wasi.fs.sha256` per declared
artifact, `RErr` on a missing path is read as absent, hex is `""`, and `""` differs from the
recorded digest, so "presence and match fail TOGETHER and (c) masks (b)". The port records the same
perturbation this leg applied: a hardcoded `true` for `artifacts-present` left all fifteen cover
scenarios green until the gate was added.

Reference, `scripts/rfc_to_implementation.py:1936-1942`: presence is a separate
`Path.exists()` sweep at `:1933`, and the digest loop is guarded by it. The two conditions are
computed by two different operations against two different failure modes, so hardcoding one does
not satisfy the other. M2 and M1 confirm this by execution.

#### Why we saw what we saw

The difference is error-as-value versus guarded evaluation. `wasi.fs.sha256` is total and returns a
constructor that the port must interpret, and interpreting `RErr` as "absent" is what folded the
two conditions into one. `sha256_file` (`:157-159`) is partial: it opens the path with no existence
check and raises `FileNotFoundError` on a missing one. The reference is correct today only because
`:1936`'s guard makes that call total at this site.

M2 is the demonstration: hardcoding presence at its definition does not produce a wrong skip, it
produces an unhandled traceback out of `sha256_file`, exit 1, with the run dead at stage B. That is
the reason M2 alone could not answer the question and M1 was needed.

#### Implication

Implication for compiler-engineer, defence-in-depth and not a defect at HEAD: the resume gate's
correctness on a missing artifact rests on the ORDER of two lines, `:1936`'s guard before `:1941`'s
digest. Any refactor that computes digests before or independently of the presence sweep turns a
deleted artifact from a clean re-run into an unhandled `FileNotFoundError`. By this file's own
standard at `:589-603`, a halt reaching the operator as a host-language traceback is
indistinguishable from a crash of the driver, so the failure mode would land as a §4:141-143 defect
rather than a wrong decision. A one-line existence check inside `sha256_file`, or a digest loop
written to treat a missing file as a mismatch, would make the gate robust to the reordering. Not
undertaken this leg: the tree is at a released version and no defect is reachable at HEAD.

Implication for language-team: none for the cover. The cell is covered and the witness is real.

#### Acceptance

Closed as a finding. Would reopen if the resume gate is refactored such that M2 stops crashing and
starts skipping, which is the signature of the port's pre-repair arrangement appearing on the
Python side.

## Withdrawn items

None. The hypothesis under test was that the Python T7 shares the port's defect, and it was
disconfirmed rather than narrowed.

## Null results

- **Hypothesis: the Python T7 passes because condition (c) independently fails on a missing file,
  as it did in the port.** No support. Required evidence would have been T7 staying green under a
  mutation that removes (b); T7 went red under both such mutations (M2 by crash, M1 by decision),
  and `mismatched` was measured empty on the deleted-artifact path. n = 2 mutations, 1 test each.
- **Hypothesis: T6 and T7 are decided by the same conjunct and therefore indistinguishable.** No
  support. T6 survived both (b)-removing mutations and died only to D; T7 did the reverse. n = 3
  mutations, 2 tests each.

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---|---|---|---|
| F-12 | T7 and T6 are separately discriminating; cover claim survives | language-team | High | none, confirmation |
| F-13 | Reference guards (c) behind (b); `sha256_file` is partial | compiler-engineer | Defence-in-depth | 1 line, deferred |

## Changes made this session

**None to any executable file.** Three mutations were applied to
`scripts/rfc_to_implementation.py` and each was reverted before the next; the file is byte-identical
to `2b82464`. No test was added or repaired, because no defect was established. This findings
section is the only write.

### Gates

`pytest scripts/tests/` 123 passed, 1 skipped, unchanged from the pre-leg baseline;
`scripts/doc_path_lint.py` 837 prose path citations in 160 living files before this write and 840
after, all resolve; `git status` shows this file and nothing else.

---

# Session 2026-08-05, third leg: re-measuring §3.5 against HEAD

> Harness and reference at `6e92dd0` (`main`), compiler v0.14.86 (built and confirmed; no CLI
> result is consumed below).
> Brief: re-measure [`../../docs/design/driver-ll-phase4-proposal.md`](../../docs/design/driver-ll-phase4-proposal.md)
> §3.5 against HEAD, because Rev 8 stamped the section with a measurement epoch rather than
> renumbering it and sub-phase 4b reads the numbers.
> Surface: [`../../scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py),
> [`../../scripts/tests/test_rfc_to_implementation.py`](../../scripts/tests/test_rfc_to_implementation.py),
> [`../../scripts/tests/test_rfc_pipeline_integration.py`](../../scripts/tests/test_rfc_pipeline_integration.py),
> [`targets/driver-spec.txt`](targets/driver-spec.txt).

## Headline finding

**The halt-site set did not move. Only the raising form did.** At the measurement epoch
(`aa08051~1`) there were 46 halt-helper call sites, all `require()`. At HEAD there are still
**exactly 46**, distributed as **36 `require()`, 9 `require_spec()`, 1 `require_written()`**, and
every one of the 46 conditions matches an epoch site argument-for-argument. Task #8 changed no
condition, added none and removed none; it re-encoded ten of them.

**The shipped split agrees with §3.5's classification nine times out of nine, clause for clause**,
and the polarity guard holds: §14:484-491's two must-not-halt checks are collected, logged and
written to the report at `:942-943` with no `require*` call on either. The section's argument
survives its re-measurement intact.

Rev 8's arithmetic does not. **"46 call sites before, 39 after" is wrong in both directions**: the
total is 46 at both epochs, and 39 matches no AST census of any revision (F-14). Three further
items are filed against 4b's port rather than against §3.5's rule: a line-number collision that
makes §3.5's table actively misleading at HEAD (F-15), one site whose disposition is row-granular
where the rule is clause-granular (F-16), and two of 4b's three stages reaching `failed` through an
unguarded host-language exception that the port has no way to construct (F-17).

## Sample composition

Census by AST call-site walk (`ast.Call` with `func.id` in the helper set, definitions excluded),
not by grep. Every disposition claim below was executed, not read.

| Revision | `require` | `require_spec` | `require_written` | total sites | raw `raise` (outside helpers) |
|---|---|---|---|---|---|
| `aa08051~1` (Rev 8's "before") | 46 | 0 | 0 | **46** | 4 |
| `aa08051` (Task #8, v0.14.84) | 36 | 9 | 1 | **46** | 4 |
| `6e92dd0` (HEAD, v0.14.86) | 36 | 9 | 1 | **46** | 7 |

Executed probes: 3 in-process helper-to-exception assertions; 7 end-to-end driver runs recording a
MANIFEST.json disposition; 4 upstream-input runs against stages B, C and I; the 3 shipped stage-G2
flag tests re-run individually. `pytest scripts/tests/` 123 passed, 1 skipped.

## The census at HEAD

**53 halt sites total**, of which 46 are helper call sites and 7 are raw `raise` statements outside
the helper definitions. The two `raise` statements inside `require` (`:355`) and `require_spec`
(`:370`), and the one inside `require_written` (`:383`), are definitions and are not call sites.

| Form | n | Exception | Recorded | `outcome` | Exit |
|---|---|---|---|---|---|
| `require()` | 36 | `StageFailure` | `failed` | `Errored` | 3 |
| `require_spec()` | 9 | `StopCondition` | `stopped` | `ConditionUnmet` | 2 |
| `require_written()` | 1 | `PartialHalt` | `stopped` | `PartialThenHalt` | 2 |
| `raise StageFailure` | 6 | | `failed` | `Errored` | 3 |
| `raise StopCondition` | 1 | | no stage row assigned | | 2 |

The mapping is `:1962-1988`, and the handler order is load-bearing: `PartialHalt` is a
`StopCondition`, `StopCondition` is not a `StageFailure`, and both precede the bare `except
Exception` at `:1989`, which records `failed`/`Errored` **and prints a traceback**.

The 7 raw raises: `:192` (`require_durable_workdir`, `StopCondition`, fires before the stage loop
and is caught by `:2026`, which assigns no stage row and exits 2); `:251`, `:256`, `:262`
(`read_manifest`, `StageFailure`, added at `c10081d`, after Task #8); `:323`, `:329`, `:332`
(`AgentRunner.run`, `StageFailure`: budget overrun, non-zero exit, no declared output).

## The partition, re-derived at HEAD

`require_spec` sites, with the epoch line each came from and the clause each carries in code:

| HEAD | epoch | Function | Condition | Clause in code | §3.5's clause |
|---|---|---|---|---|---|
| `:493` | `:355` | `check_dispositioned` | exclusion cites a barrier outside the closed list | §6:229-231 | §6:229-231 |
| `:921` | `:782` | `stage_G2_audit` | a flag's quoted phrase absent from the pinned quote | §7:305-309 | §7:305-309 |
| `:928` | `:788` | `stage_G2_audit` | a flag's reason phrase absent from the recorded reason | §7:305-309 | §7:305-309 |
| `:956` | `:811` | `stage_G2_audit` | a dispositioned row citing no census row | §14:479-483 + §6:255-258 (by entailment) | same |
| `:966` | `:815` | `stage_G2_audit` | a citation that does not resolve to the pinned bytes | §14:479-483 | §14:479-483 |
| `:974` | `:821` | `stage_G2_audit` | a core row whose stated reason misreads its clause | §14:494-499 | §14:494-499 |
| `:1100` | `:936` | `stage_J_gate` | a characteristic-core row dispositioned out | §6:222-224 | §6:222-224 |
| `:1104` | `:939` | `stage_J_gate` | the `:493` condition, re-checked at the gate | §6:229-231 | §6:229-231 |
| `:1170` | `:1003` | `stage_L_coverage` | RFC-COV-1 fails at freeze strength | §11:386-397 | §11:386-397 + §6 |

Nine for nine. The one wording difference is `:1170`, where §3.5's table adds "+ §6" for gate L and
the code cites §11 alone; both name gate L's condition and the disposition is unaffected.

The three sites §3.5 could not classify all agree with the resolutions it recorded: epoch `:967`
(stage K, authored roots do not typecheck) is HEAD `:1134`, `require`, `failed`; epoch `:1045` (no
holes to fill) is HEAD `:1213`, `require`, `failed`; epoch `:866` (stage H) is HEAD `:1028`,
`require_written`, `stopped`/`PartialThenHalt`, carrying §4:146-147, which is §3.6's conservative
action taken exactly.

The remaining 36 `require()` sites all record `failed`, as §3.5's rule gives. Descriptive buckets,
re-derived (the bucket boundary is a judgement, and it changes no disposition):

- **Delegated-output shape validation, 27**: `:394 :398 :400 :403 :405 :407 :410 :422` (extraction),
  `:457 :460 :462 :464 :465 :470 :475` (audit catalogue), `:483 :486 :487 :490 :499` (dispositions),
  `:579` (B), `:593` (C), `:714` (F), `:1006 :1010` (H), `:1134` (K), `:1453` (N).
- **Driver-internal invariants and tool failures, 7**: `:540` (unfilled prompt placeholder), `:629`
  (no pinned RFC text), `:685` (`reconcile.py` failed), `:811 :815` (`_pinned_sources`), `:1211`
  (could not emit the AST), `:1213` (no holes to fill).
- **Pre-stage argument validation, 2**: `:1883 :1886`.

This is 27/7/2 where §3.5 recorded 26/9/2 over its 46. The difference is bucket assignment, not
disposition: `:866` left the set into `require_written`, and one site sits on the boundary between
"validates a delegated output" and "a tool that had to succeed". Both readings give `failed`.

### The polarity guard holds

§14:484-491 states two checks that MUST be reported and MUST NOT halt. At HEAD `near_miss` and
`strength_absent` are accumulated at `:884-892`, logged at `:896-897`, and written to `audit.json`
at `:942-943` under a note that names them as not thresholded. No `require`, `require_spec` or
`require_written` reads either list. `test_audit_reports_a_near_miss_span_and_an_absent_strength_without_stopping`
(`test_rfc_to_implementation.py:417`) pins it, and it passes.

One thing the guard does not settle, recorded because 4b must encode it: the boundary between
§14:481-482's halt ("a citation that does not resolve") and §14:484-485's must-not-halt ("a span
that supplies the quoted words only in part") is drawn at `CITATION_RESOLVES_AT = 0.5` (`:763`).
That constant is measured against the TFTP census rather than derived from a clause, and its
rationale at `:755-762` says so. driver-spec names no threshold, so the port inherits the constant
as a pinned datum, not as a derivation.

## Verified findings

### F-14. The site set did not shrink, and Rev 8's "39" is a grep artefact

**Priority:** High
**Consumer:** language-team

#### Evidence

AST census over three revisions is in the sample-composition table above: 46 helper call sites at
`aa08051~1`, 46 at `aa08051`, 46 at HEAD. The 46 conditions match argument-for-argument across the
epoch: matching each call's source segment with the callee name stripped pairs 36 sites exactly,
leaves 10 unmatched on the old side and 9 on the new, and the 10 are precisely §3.5's nine
spec-defined sites plus `:866`, whose message text was rewrapped when it became `require_written`.
No condition was added and none was removed.

At HEAD, `grep -cF 'require('` returns **40**: 36 call sites, one definition at `:343`, and three
docstring mentions of `` `require()` `` at `:113`, `:150` and `:152`. Subtracting only the
definition gives **39**.

Rev 8's third claim, that "the raise count rose correspondingly", does not hold either. The raise
count was 4 both before and after Task #8. It rose to 7 at `c10081d`, a later commit, which added
`read_manifest`'s three `StageFailure` raises. Nothing about the `require`/`require_spec` split
produced a raise: both splits happen inside the helper bodies.

#### Why we saw what we saw

The stamp was written to retire a stale count and reached for the same instrument that produced the
stale one. A grep over `require(` cannot separate a call site from a definition or from prose, and
this file's own §3.5 measurement a session earlier had already been corrected once for the same
reason. The count that is stable across the repair is the one the code itself still states: the
comment at `:1026` says "the two axes disagree on this one site out of 46", written by Task #8,
after the repair.

#### Implication

Implication for language-team: Rev 9 should replace the epoch stamp with the census rather than
re-date it. The sentence that needs changing is not the number but the claim behind it: the section
reads as though the repair reduced a halt surface, and what it did was partition one. The
"of the 46: 9 spec-defined, 26 ..." partition is not "over an encoding that no longer exists"; it
is over a set that is unchanged, and 9 of its 4 buckets are now carried by the type system instead
of by the table.

#### Acceptance

Closed when §3.5 states 46/36/9/1 with the AST-census method named, and when the raise-count
sentence attributes the rise to `c10081d`.

### F-15. §3.5's `:811` and `:815` name live sites at HEAD with a different disposition

**Priority:** High
**Consumer:** language-team, compiler-engineer

#### Evidence

§3.5's table lists epoch `:811` (a dispositioned row citing no census row, `stopped`) and epoch
`:815` (a citation that does not resolve to the pinned bytes, `stopped`). Those conditions are at
HEAD `:956` and `:966`.

HEAD `:811` and `:815` both exist and are both `require()`, both inside `_pinned_sources`:

- `:811` `require(key not in out, "stage G2: two pinned files normalise to ...")` — `failed`
- `:815` `require(out, "stage G2: no pinned RFC text under 00-source; run stage A first")` — `failed`

Same file, same stage prefix in the message, both in the `require`/`stopped` neighbourhood a reader
of §3.5 would expect, and both carrying the opposite disposition to the row §3.5 files under that
number.

#### Why we saw what we saw

Task #8 inserted roughly 145 lines above `stage_G2_audit`, and `_pinned_sources` moved into the
vacated range. A collision of this shape is invisible to any check that verifies a line number
resolves to a line.

#### Implication

Implication for compiler-engineer: sub-phase 4b must not resolve §3.5's table against HEAD line
numbers. Use the epoch-to-HEAD map in this section, or re-derive from the condition text. Two of
the nine rows silently land on a live site of the opposite disposition, which is the single
highest-probability way for the port to invert a status.

Implication for language-team: Rev 9's table should carry the condition text as the key and the
line number as a convenience, since the line number is the part that rots.

#### Acceptance

Closed when §3.5's table is keyed on condition rather than on line, or when the numbers are
refreshed to HEAD with the collision noted.

### F-16. `:921`/`:928` halt `stopped` on non-core rows, and §3.5's rule cannot express the scope

**Priority:** High
**Consumer:** language-team

#### Evidence

`:974` filters to core rows before halting (`flagged_core = [v["cid"] for v in misread if
v.get("core")]`, `:973`), and cites §14:494-499, which scopes its halt explicitly: "A reason found
to misread the clause carrying **a characteristic requirement** MUST halt the run, because the gate
of section 6 decides the target from exactly those rows."

`:921` and `:928` sit inside `for v in misread:` at `:919` with no core filter, and cite §7:305-309,
whose halt-mandate is supplied by its own closing sentence: "A finding the driver cannot locate is
an assertion, and section 6 forbids a gate to rest on one."

Two shipped tests pin the consequence on one and the same non-core row:

| Test | Flag on a non-core row | Result |
|---|---|---|
| `test_rfc_to_implementation.py:431` | `misreads`, evidence phrase **not** in the quote | `StopCondition`, run halts `stopped` |
| `test_rfc_to_implementation.py:461` | `misreads`, evidence phrases **present** | no halt; recorded in `reasons_flagged` |

Both re-run individually this leg and both pass. The driver's own log line at `:981-983` reads
"reasons flagged (none core, recorded not fatal)".

#### Why we saw what we saw

The severity ordering is inverted, and the inversion is a consequence of the halt-mandate route,
not of the check. A substantiated misread on a row no gate rules on is correctly non-fatal. An
unsubstantiated one on that same row halts the run as a verdict the method reached. The clause that
supplies `:921`/`:928` their halt-mandate under §3.5's second conjunct is §6:252-258, reached
through §7:309-310, and §6:252-258 binds **the gate**. Where no gate rests on the row, the second
conjunct is not satisfied and the rule gives `failed`.

#### Implication

Implication for language-team: this is a limit of the rule's granularity, not a defect in the
repair. §3.1's Rev 4 amendment already moved the unit from the stage to the clause because
`check_dispositioned` holds six checks of which one is spec-defined. `:921`/`:928` push once more:
the same clause, at the same call site, is spec-defined for a core row and not for a non-core one,
because the clause that mandates the halt is scoped to what the gate reads. The rule as written
assigns one disposition per site and cannot say this. Three ways out, none of which is
experiment-lead's to pick: scope the sites to core rows and match `:974`; state that §7:306-309's
"MUST require" is itself the halt-mandate independently of §6, which makes the current code right
and drops the entailment; or add a scope column to §3.5's table and accept that a site's
disposition can depend on the row.

Note that `:956` is already flagged in §3.5 as "the only row resting on entailment rather than
quotation". On the reading above it is not the only one: `:921` and `:928` rest on the same
entailment through §6, and the code marks `:956` with "(by entailment)" while marking those two
plainly.

#### Acceptance

Closed when §3.5 either scopes the two sites or records the halt-mandate as §7-internal. Empirically,
the finding would not resurface if `:921`/`:928` acquired the `:974` core filter and
`test_rfc_to_implementation.py:431` were rewritten against a core row.

### F-17. Two of 4b's three stages reach `failed` through an unguarded host-language exception

**Priority:** High
**Consumer:** compiler-engineer

#### Evidence

Four runs against a workdir whose upstream inputs are absent or malformed, `--only` on the stage
under test:

| Stage | Input state | Manifest | Traceback | Halt line |
|---|---|---|---|---|
| B | no stage A, `00-source` empty | `failed`/`Errored` | **yes** | `FileNotFoundError` on `PROVENANCE.json` |
| B | `00-source` present, `PROVENANCE.json` malformed | `failed`/`Errored` | **yes** | `JSONDecodeError` |
| C | no stage A, `00-source` empty | `failed`/`Errored` | no | `require(:629)` "no pinned RFC text found; run stage A first" |
| I | no stage B, the run's `scope.md` absent | `failed`/`Errored` | **yes** | `FileNotFoundError` on `scope.md` |

Stage B reads `PROVENANCE.json` through `read_json` (`:208-209`, a bare `json.loads(p.read_text())`
with no guard) at `:573`. Stage I reads `scope.md` through `.read_text()` at `:1062-1063`. Stage C
reads only through `_sources_text`, which guards at `:629`. The three arrive at the same recorded
disposition through two different mechanisms, and the traceback column is the difference: `:1989`'s
bare handler, not a deliberate halt.

Separately, **stage I validates nothing**. It is the only one of the three with no `require*` call
at all (`stage_I_prereg`, `:1053-1065`, zero halt calls, zero raises). A zero-byte
`PRE-REGISTRATION.md` and a 28-byte non-pre-registration were both recorded `complete`, exit 0.
Stages B and C each carry one size check (`:579` > 200 bytes, `:593` > 400 bytes).

#### Why we saw what we saw

`:1989`'s handler exists precisely to keep these cases out of the operator's face, and it does its
job on the Python side: the manifest row is written and the status is right. The problem is that it
has no analogue in the port. LLMLL has no host-language exception to fall through to, so a
`FileNotFoundError` path is not something the port can reproduce; it has to become an explicit
`Errored` construction at the read site, or the read has to be total.

#### Implication

Implication for compiler-engineer, and this is the list 4b ports against. The **complete** halt
surface reachable from stages B, C and I:

| Site | Form | Stage(s) | Condition | Records |
|---|---|---|---|---|
| `:323` | `raise StageFailure` | B, C, I | agent exceeded its budget | `failed`/`Errored` |
| `:329` | `raise StageFailure` | B, C, I | agent exited non-zero | `failed`/`Errored` |
| `:332` | `raise StageFailure` | B, C, I | agent exited 0 and wrote no declared output | `failed`/`Errored` |
| `:540` | `require` | B, C, I | prompt template has unfilled placeholders | `failed`/`Errored` |
| `:629` | `require` | B, C | no pinned RFC text under `00-source` | `failed`/`Errored` |
| `:579` | `require` | B | `scope.md` at or under 200 bytes | `failed`/`Errored` |
| `:593` | `require` | C | `rubric.md` at or under 400 bytes | `failed`/`Errored` |
| `:573` | *unguarded* `read_json` | B | `PROVENANCE.json` absent or malformed | `failed`/`Errored` **+ traceback** |
| `:1062` | *unguarded* `read_text` | I | stage B's `scope.md` absent | `failed`/`Errored` **+ traceback** |

Every one of the nine records `failed`/`Errored`. **No halt reachable from stages B, C or I records
`stopped` under any input.** That is the single most useful fact for 4b: the three stages it ports
construct `Errored` and nothing else, so the port needs no `ConditionUnmet` or `PartialThenHalt`
site in this sub-phase, and any B/C/I site that ends up `stopped` in the port is wrong by
construction.

The two unguarded rows are the ones needing a decision before the port is written, since they have
no direct encoding. Whether stage I should validate its declared output at all is a separate
question and belongs to language-team, not to the port: driver-spec §7:282-285 requires validating a
delegated output against its declared shape, and stage I declares `PRE-REGISTRATION.md` and checks
only that the agent wrote something.

#### Acceptance

Closed for the port when the nine sites above are encoded and B/C/I construct only `Errored`.
Reopened if any input is found that makes a B, C or I halt record `stopped`.

## Withdrawn items

- **"The repair moved sites that §3.5 classified as spec-defined into a second form, and the
  partition must be re-derived from scratch."** Withdrawn as framed. The partition needed
  re-measuring, and it came back identical: 9 for 9 by clause, with the three unclassifiable sites
  resolving as §3.5 and §3.6 recorded. The re-derivation was necessary and it changed nothing, which
  is a corroboration rather than a correction.

## Null results

- **Hypothesis: sites added to the driver after the epoch would need classifying under §3.5's
  rule.** No support. Argument-level matching across `aa08051~1` and HEAD pairs all 46 conditions;
  zero halt-helper call sites were added or removed in either direction. n = 46 sites, 2 revisions.
- **Hypothesis: the repair broke the polarity guard by pattern-matching MUST without reading
  polarity.** No support. Neither §14:484-491 check is read by any halt helper; both are report-only
  and one shipped test pins it. Required evidence would have been a `require*` call over `near_miss`
  or `strength_absent`; there is none. n = 46 sites inspected.
- **Hypothesis: §3.1's row 3 ("declared output present and valid, agent exit non-zero →
  `complete`") describes the reference.** No support, and this is a divergence rather than a null:
  `AgentRunner.run` raises `StageFailure` at `:329` on `rc != 0` **before** the output-existence
  check at `:331`, so a stage that produced a valid declared output and exited non-zero records
  `failed`. Measured: a stage-B run whose agent wrote a valid 1200-byte `scope.md` and exited 7
  recorded `failed`/`Errored`, exit 3. §3.1 cites §7:279 for that row, and §7:279 governs a stage
  that "terminates without producing its declared output", which is not this case. Routed to
  language-team as a §3.1 question, not repaired. n = 1 run.

## Priority matrix

| # | Finding | Consumer | Priority | Effort |
|---|---|---|---|---|
| F-14 | Site set unchanged at 46; Rev 8's 39 is a grep artefact | language-team | High | Rev 9 edit |
| F-15 | §3.5's `:811`/`:815` collide with live HEAD sites of opposite disposition | language-team, compiler-engineer | High | Rev 9 edit; 4b must use the map |
| F-16 | `:921`/`:928` are row-granular where the rule is clause-granular | language-team | High | design decision, three options |
| F-17 | B and I halt through unguarded host exceptions; I validates nothing | compiler-engineer | High | 4b port input |
| — | §3.1 row 3 does not describe `AgentRunner.run` | language-team | Medium | filed as a null result |

## Changes made this session

**None to any executable file.** `scripts/rfc_to_implementation.py` and both test files are
byte-identical to `6e92dd0`; no mutation was applied at any point, and every probe ran from the
scratchpad against the unmodified reference. This findings section is the only write.

### Gates

`pytest scripts/tests/` 123 passed, 1 skipped, unchanged from the pre-leg baseline;
`scripts/doc_path_lint.py` 841 prose path citations in 160 living files before this write and 848
after, all resolve; `llmll version` 0.14.86, matching the tree, though no CLI result is consumed by
any claim above.

### Environment note

`git diff` at the end of this leg reports three modified files under `compiler/` (`CodegenHs.hs`,
`ParserJSON.hs`, and the compiler test spec) that were clean when the leg started and were not
touched by it.
Their mtimes fall inside this session's window, so a second writer was active in the same working
tree. Recorded because `stack build` ran against that tree; nothing above depends on the build.
