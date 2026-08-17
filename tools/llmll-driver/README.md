# `llmll-driver`: the RFC-SWARM driver's proved tier, in LLMLL

The pipeline driver is specified as an Internet-Draft at
[`experiments/rfc-swarm/targets/driver-spec.txt`](../../experiments/rfc-swarm/targets/driver-spec.txt),
deliberately, so that it can be read by the same pipeline it describes. Section 15 of that
document splits its own obligations into three tiers. This directory implements the first one.

**What is here is not the driver.** It is the driver's decision logic, verified. The driver that
runs is still [`scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py).
Section 15.4 is explicit that an implementation whose effectful surface lives in another language
does not conform, "since nothing then bounds its authority or enforces its contracts," so this is
a partial artifact by the spec's own terms and is labelled as one.

## What is proved

Section 15.1 enumerates seven obligations and requires them discharged "by proof over all inputs,
not by testing." All seven verify body-faithfully and clear `--strict-verified-core`, which is
the acceptance bar section 9 defines for a fill.

| Spec section | Module | Obligation |
|---|---|---|
| 4 | [`stage.llmll`](stage.llmll) | the four stage statuses, and that an error is never recorded as stopped |
| 5 | [`skip.llmll`](skip.llmll) | a stage is skipped only on manifest, presence and digest together |
| 6 | [`gate.llmll`](gate.llmll) | the halt decision, and the remedy implied by a barrier's class |
| 9 | [`fill.llmll`](fill.llmll) | fill acceptance, the separated retry budgets, and what counts as a finding |
| 10 | [`token.llmll`](token.llmll) | a token is not held while an agent is working |
| 12 | [`liveness.llmll`](liveness.llmll) | advancement judged from any artifact, not from the log |

Nine functions, 26 contract clauses, every clause carrying a `:source` citation to the spec
section it discharges, which is what section 11 requires of a carried clause.

Two notes on how the properties are stated, because both are easy to misread.

**"Coverage MUST NOT be thresholded" is stated as a total specification.** `gate-halts` pins its
result entirely to the two enforced conditions, so any body that consulted the coverage counts
would have to disagree with the post on some input. A non-interference property becomes an
ordinary refinement obligation by fully determining the result from the permitted inputs.

**Section 10 is proved per step and single-threaded, not per trace.** `token-during` says what the
token's state is in each phase, and that is a phase-indexed invariant rather than an ordering: the
body is a three-case match over a nullary phase and both posts are guarded implications over one arm
each. Nothing in the module expresses a sequence, a transition, or a pair of phases.

The closure to "no token is ever held while any agent works, across a whole wave" is therefore **not
an induction over an unbounded sequence of fills**, which is what this file claimed until 4e. A
memoryless function of the current phase gives the whole-wave property pointwise once the labelling
is granted. What is unproved is the labelling itself: a refinement mapping from the driver's states
onto this phase, which is a fact about the port rather than a theorem about the module, and is not
Lean-dischargeable. Single-threaded is part of the claim and not a throughput note, because the
labelling is a function only while at most one hole is live.

## What is asserted, not proved

Section 15.2 is [`shell.llmll`](shell.llmll). It is the tier the spec says cannot be proved and
must still be part of the program: "effectful operations cannot be proved, but they MUST NOT be
exiled from the program in order to say so."

Every effect is reached through a declared capability (`wasi.io`, `wasi.fs`) or through the
`Host` interface declared in the module, which is what section 15.2 permits for operations no
shipped capability names: fetching the source document, reading a clock, and spawning and
awaiting agent processes.

The section's hardest requirement is that an implementation "MUST be able to report, for any
function, an over-approximation of the capabilities reachable through its call graph." Bundle
B0's `effect_summary` is exactly that, and `verify --obligation-report --json` gives:

| function | authority |
|---|---|
| `status-line` | `[]` |
| `announce-halt` | `[stdout]` |
| `report-liveness` | `[stdout]` |
| `record-transition` | `[fs.write]` |
| `load-artifact` | `[fs.read]` |
| `finish-stage` | `[fs.write, stdout]` |

`finish-stage` performs no effect of its own. Its authority is entirely inherited from the two
shells it calls, which is the call-graph closure rather than a tally of direct effects. Nothing
reaches `unbounded`.

Two further clauses of the section hold by construction rather than by our care. **Authority is
enforced, not declared:** [`crux-shell-undeclared-authority.llmll`](crux-shell-undeclared-authority.llmll)
writes the filesystem while importing only `wasi.io` and fails at type-check, not at the solver.
And **a runtime-enforced obligation is not presented as a proved one:** every function in the
shell falls back from body-faithful verification and carries no proved level, while the core
functions it calls report `verified (liquid-fixpoint)`.

Section 15.3 disclaims three things outright: the content of any prompt given to a delegated
agent, that agent's internal behaviour, and the guarantees of the operating system.

**This still is not the driver.** Section 15.2 is satisfied in shape rather than in coverage: the
shell demonstrates the tier's discipline over a handful of operations.

## What the driver does today

[`spine.llmll`](spine.llmll) ports stages E, J, L and G2 over the committed TFTP data
(DRIVER-LL Phase 3), and [`sequencer.llmll`](sequencer.llmll) ports the stage loop above them
(Phase 4, sub-phases 4a, 4b and 4c): the sixteen-stage registry, the resume gate over
`skip.may-skip`, the manifest row schema, two halt channels over `stage.record-outcome`, the
delegated-output validation of `validate.verdict-of` / `validate.verdict-outcome`, and the
content-shape validation of `shape.llmll`. It receives its flags through `wasi.proc.args` and
exits 0, 2 or 3 through the `:status` projection, so no shell sits between the acceptance
criterion and the program.

**Six of the sixteen stage bodies are real**, measured off `registry.stage-ported?`, which
returns true for exactly six indices. B (scope), C (rubric) and I (pre-registration) landed at
4b; D (extraction), F (core) and G (dispositions) at 4c. All six read their inputs, render their
prompt, spawn the agent through `wasi.proc.run`, and validate the declared output. The other ten
write a stub to each artifact they declare, which is enough for every resume and outcome
transition to be decided over real digests and a real completion record;
`registry.stage-ported?` is the switch and carries the retirement schedule.

**Stage D is the first stage that delegates more than once**, which is why the registry tables
take an invocation index and the run state grew a tag. It declares two outputs and runs two blind
extractors over an identical isolated input set. The blindness is a driver-spec section 8 MUST
and `audit_blindness` is what checks it, so provisioning that quietly differs between the two
invocations defeats the obligation without failing anything. It did, twice, in this port, and
neither `llmll check` nor `llmll verify` nor the cover as it stood could see either one. Only
running the built driver did.

**A third `Outcome` arm appears at 4c, and it is not a widening.** `check_dispositioned`'s
barrier check is `require_spec` where its five siblings are `require`, so that halt is
spec-defined and records `stopped` rather than `failed`. It routes through the sequencer's
`halt-with … ConditionUnmet` channel and deliberately **not** through `validate.verdict-outcome`,
which `[V7-NO-STOP]` forbids for the stages 4b ported, none of which has a spec-defined halt.
`[V7-ONLY-TWO]` is a statement about `verdict-outcome`'s codomain rather than an invariant of the
port, so it stays true as written and no proved post moved.

**Three more budget-overrun halts are written and unreachable.** D, F and G each invoke an agent,
and `wasi.proc.run`'s timeout does not fire in a built program (`PROC-TIMEOUT-1`, open). No cover
cell claims to exercise them, which is the disclosure rather than the fix.

The agent channel is `--agent-exe` plus repeatable `--agent-arg`, with `{prompt}`, `{out}` and
`{workdir}` substituted per argument. It is deliberately **not** a shell template: passing the
operator's string to `/bin/sh -c` would restore shell semantics through a granted binary and
void the auditability `wasi.proc.run`'s exec/argv split delivers. There is no environment
channel, `wasi.proc.run` having no env parameter, so the two paths reach the agent through argv.

The acceptance cover is [`scripts/driver_ll_cover.py`](../../scripts/driver_ll_cover.py), run by
`scripts/build_smoke.sh` **stage 8** against the **built** sequencer: **39 cells** at 4c, from 31,
the eight new ones being the content-shape family C1 through C7 plus C6b. The checks that need no
toolchain are in
[`scripts/tests/test_driver_ll_4a_cover.py`](../../scripts/tests/test_driver_ll_4a_cover.py) and
[`scripts/tests/test_driver_ll_4b.py`](../../scripts/tests/test_driver_ll_4b.py).

**4c added nothing to the no-toolchain tier, and that is disclosed rather than explained.** Its
plan listed a `test_driver_ll_4c.py`; no such file exists and the Python suite is unchanged at
132. Every check 4c added therefore needs a toolchain and a built binary, so on a machine without
one, or while CI is unavailable, 4c has no automated coverage at all. The two provisioning
defects above are cover cells C1 and C2, which is the same tier: the things only a run can catch
are checked only by a run.

## The validation facility

[`validate.llmll`](validate.llmll) is where driver-spec section 7:283-291 lives, and it is one
module rather than three copies of an `if` because three stages owe the same two obligations.

- **Mandatory, non-downgradable, non-skippable.** `verdict-outcome` is the single mapping from
  what the driver learned about a delegated output to the `Outcome` its stage records.
  `[V7-MANDATORY]` refutes the warning downgrade; `[V7-ONLY-TWO]` proves the sub-phase
  constructs exactly two of `Outcome`'s four constructors, so a `stopped` here is wrong by
  construction rather than merely unexpected.
- **No hardcoding of one subject's conventions.** `verdict-of` takes `bool int int` and no
  string, so no byte of any subject is in scope, and `[V7-NO-HARDCODE]` says every output above
  the declared floor passes, so a body fitted to the sizes one run produced is refuted. The
  floor is a registry constant a reader can check against the reference's own `require` call,
  and `test_driver_ll_4b.py` relates the two by AST.

Stage I gets a **negative** floor, meaning its stage contract declares none. That is measured:
`stage_I_prereg` holds zero halt calls, and a 0-byte `PRE-REGISTRATION.md` records `complete`.
A validator where the reference has none is new behaviour and does not ride in on a port; stage
I joins stage O and lands at 4f. `[V7-PRESENCE]` is what keeps "no floor" from becoming "no
validation": an absent output is a rejection whatever the floor.

## The content-shape channel

[`shape.llmll`](shape.llmll) is 4c's proved module and the other half of the delegated-output
obligation: `validate.llmll` decides presence and a declared byte floor, and this one decides
whether the content has the shape the stage contract names, plus the barrier condition stage G
enforces. Four defs, `extraction-conforms?`, `core-conforms?`, `dispositions-conform?` and
`barrier-condition-met?`, all four body-faithful and SAFE on the first attempt.

**Every parameter is a bool or an int, and that is the design rather than an accident of what was
convenient.** `verdict-of` earns subject-neutrality structurally by taking no string; a content
validator taking `Json` would forfeit it, since every row of every census would be in scope and
nothing but review would stop a body from reading one. Passing facts instead of documents keeps
the subject's bytes out of the proved core and keeps that core in QF-LIA. The extraction happens
in the `def-shell` caller, where it is asserted rather than proved, and the split is the point.

**`-1` in the floor table now means two different things and a reader must not collapse them.**
For I and O it means the reference declares no validator at all, which is why neither gets one
here. For D, F and G it means the stage contract declares a **shape** instead of a byte floor,
carried through `stage-shape` rather than through the floor. 4c adds no floors, and that absence
is measured off the reference rather than assumed from the pattern the earlier stages set.

**`regex-match` is not used, and the reason is a compiler defect rather than a style choice.**
`check_extraction`'s `^N\d+$` and `check_dispositioned`'s `^C[1-6]$` would port verbatim:
`regex-match` exists, is typed, is documented, and its preamble implementation is emitted. A
program calling it passes `check` and `verify` and then does not build. Both patterns are
hand-rolled from `string-char-at` instead, exactly equivalent on their domains and using only
Σ_auto-safe builtins, and the disclosure sits at the call site rather than in a commit message.
Filed as `REGEX-LOWER-1`, whose roadmap row records that the affected population is larger than
the one name and that only that one has been executed.

## The cruxes

[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) freezes **31** cases: **sixteen** refuting
mutants, one capability rejection, and fourteen `safe` verdicts of which one is the good twin.
**Six of the sixteen mutants are not invented.** They are defects that shipped in the Python
driver, or behaviour it still has, or behaviour every LLMLL console program had:

(The counts above were taken from the file rather than incremented from the previous sentence,
which said ten and was already short by one before sub-phase 4b touched it, then said
twenty-seven and was short by four once 4c added `shape.llmll` and its three cruxes. A count
stated without its epoch reads as current, and this is the **fourth** instance the DRIVER-LL line
has recorded of exactly that. The file's own `frozen_at` field is the same defect one level in:
it reads `v0.14.86` while four cases were added after that release, and it cannot be corrected
until 4c has a release of its own.)

- `crux-skip-presence-only`: a stage was skipped whenever its outputs existed, so a failed
  freeze gate was bypassed by its own report.
- `crux-token-held-across-call`: the checkout token held across the whole agent call, which
  wedged fourteen holes and lost one fill on the first wave.
- `crux-liveness-log-only`: `--status` judged advancement from `run.log`, which cannot move
  while a delegated stage is running, so a healthy run read as stalled.
- `crux-gate-coverage-threshold`: the exclusion-ratio ceiling, retired as a defective instrument
  by [`rfc-swarm-coverage-review.md`](../../docs/design/rfc-swarm-coverage-review.md) F-1.
- `crux-gate-single-remedy`: what the driver does **today**: one remedy string for every barrier
  class. This crux refutes the shipped implementation, which is the spec being ahead of the code.
- `crux-exit-code-halt-as-zero`: what **every** LLMLL console program did before
  PROC-BOUNDARY-1, since the harness had no status channel: exit 0 on the `:done?` path
  whatever the run decided, so a driver that halted at a gate and one that finished every stage
  were indistinguishable to a shell.

The two 4b cruxes are invented, and the second is worth its file for what it does **not**
refute:

- `crux-validate-downgrade`: an output that failed validation let through as though it had
  passed. Measured: it refutes `[V7-MANDATORY]` **alone**, the same body carrying every other
  post being SAFE, because `Finished` is one of the two constructors `[V7-ONLY-TWO]` admits.
- `crux-validate-subject-hardcoded`: a validator accepting exactly the one size a committed run
  produced. Its `(> size floor)` guard is what makes it discriminating: with the guard it
  satisfies `[V7-PRESENCE]` and `[V7-FLOOR]` and refutes `[V7-NO-HARDCODE]`; without it, it also
  refutes `[V7-FLOOR]` and would be a mutant about floors wearing an anti-hardcoding label.
  Both directions measured.

The three 4c cruxes guard the content-shape channel, and the first is the one worth the file:

- `crux-shape-row-count-fitted`: a validator fitted to the census size one extractor produced.
  Measured: four forward posts **SAFE**, `[D7-NO-HARDCODE]` **alone** refutes. **It needs no
  second run to fail**, which is what distinguishes it from its `validate` cousin. Stage D runs
  two blind extractors and the committed pair disagrees on census size, 119 normative rows
  against 125, so a validator fitted to A rejects B inside the **same run**, on the stage whose
  whole point is that neither extractor can see the other. Section 7:288-291's "the next run"
  arrives one loop iteration later.
- `crux-shape-accepts-malformed`: the converse direction, and the pair is why both exist. All
  posts **SAFE** including the converse, `[D7-ROWS]` alone refutes. No forward post catches a
  validator that rejects conforming input, and no converse post catches one that accepts too
  much, so neither mutant alone would have shown the gap.
- `crux-shape-barrier-vacuous`: refutes through **both** its posts and **does not claim to
  discriminate**, `[G6-CLOSED]` being an equality between two booleans and so determining the
  result entirely. `[G6-NOVACUOUS]` is a named consequence in the sense `[V7-NO-FLOOR]` is one,
  stated separately for findability rather than as an independent obligation.

The good twin, `twin-skip-reassociated`, is the same skip decision with its conjunction
reassociated. It guards against a contract so strong that only one phrasing satisfies it.

## Running it

```bash
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
llmll version                                    # 0.14.67 or later

llmll verify tools/llmll-driver/skip.llmll --strict-verified-core   # SAFE, exit 0
llmll verify tools/llmll-driver/crux-skip-presence-only.llmll       # refuted, exit 1
```

This suite is wired into `make refute-crux-gate` as `tools/llmll-driver`. Two changes to the
gate were needed and both are worth knowing. They were made to the shell reference that
TOOL-RFC-002 has since retired, and
[`tools/refute-crux/refutecrux.llmll`](../refute-crux/refutecrux.llmll) inherited both:

- Suites are addressed by **repo-relative path** rather than by a bare name under `examples/`,
  since this one is not in `examples/`.
- Each case is verified against a copy of the **whole suite directory** rather than of the single
  case file. `shell.llmll` imports sibling modules and cannot resolve them otherwise. `verify`
  still checks only the named file, so the extra siblings change no verdict, and the existing
  eleven families produce the same 41 results before and after.

The verdict vocabulary now has a third kind, `capability`, and
`crux-shell-undeclared-authority` is graded under it. It was previously filed as `refuted`
because the gate greps for `error:`, though it fails at type-check rather than at the solver:
both print `error:` and exit 1, so a program the type checker rejected stood in for one the
solver disproved. `capability` matches the missing-capability diagnostic instead, and `refuted`
now rejects that diagnostic explicitly, so the two cannot drift back together. Relabelling the
case `refuted` fails the gate, which is how the distinction was checked rather than assumed.
