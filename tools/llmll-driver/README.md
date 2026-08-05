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

**Section 10 is proved per step, not per trace.** `token-during` says what the token's state is
in each phase. The closure to "no token is ever held while any agent works, across a whole wave"
is an induction over an unbounded sequence of fills, and is not claimed here.

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
(Phase 4, sub-phases 4a and 4b): the sixteen-stage registry, the resume gate over
`skip.may-skip`, the manifest row schema, two halt channels over `stage.record-outcome`, and
the delegated-output validation of `validate.verdict-of` / `validate.verdict-outcome`. It
receives its flags through `wasi.proc.args` and exits 0, 2 or 3 through the `:status`
projection, so no shell sits between the acceptance criterion and the program.

**Three of the sixteen stage bodies are real.** B (scope), C (rubric) and I (pre-registration)
read their inputs, render their prompt, spawn the agent through `wasi.proc.run`, and validate
the declared output. The other thirteen write a stub to each artifact they declare, which is
enough for every resume and outcome transition to be decided over real digests and a real
completion record; `registry.stage-ported?` is the switch and carries the retirement schedule.

The agent channel is `--agent-exe` plus repeatable `--agent-arg`, with `{prompt}`, `{out}` and
`{workdir}` substituted per argument. It is deliberately **not** a shell template: passing the
operator's string to `/bin/sh -c` would restore shell semantics through a granted binary and
void the auditability `wasi.proc.run`'s exec/argv split delivers. There is no environment
channel, `wasi.proc.run` having no env parameter, so the two paths reach the agent through argv.

The acceptance cover is [`scripts/driver_ll_cover.py`](../../scripts/driver_ll_cover.py), run by
`scripts/build_smoke.sh`; the checks that need no toolchain are in
[`scripts/tests/test_driver_ll_4a_cover.py`](../../scripts/tests/test_driver_ll_4a_cover.py) and
[`scripts/tests/test_driver_ll_4b.py`](../../scripts/tests/test_driver_ll_4b.py).

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

## The cruxes

[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) freezes 27 cases at v0.14.86: **thirteen**
refuting mutants, one capability rejection, and thirteen `safe` verdicts of which one is the
good twin. **Six of the thirteen mutants are not invented.** They are defects that shipped in
the Python driver, or behaviour it still has, or behaviour every LLMLL console program had:

(The counts above were taken from the file rather than incremented from the previous sentence,
which said ten and was already short by one before sub-phase 4b touched it. A count stated
without its epoch reads as current, and this is the third instance the DRIVER-LL line has
recorded of exactly that.)

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

The good twin, `twin-skip-reassociated`, is the same skip decision with its conjunction
reassociated. It guards against a contract so strong that only one phrasing satisfies it.

## Running it

```bash
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
llmll version                                    # 0.14.67 or later

llmll verify tools/llmll-driver/skip.llmll --strict-verified-core   # SAFE, exit 0
llmll verify tools/llmll-driver/crux-skip-presence-only.llmll       # refuted, exit 1
```

This suite is wired into `make refute-crux-gate` as `tools/llmll-driver`. Two changes to
`scripts/refute-crux-gate.sh` were needed and both are worth knowing:

- Suites are addressed by **repo-relative path** rather than by a bare name under `examples/`,
  since this one is not in `examples/`.
- Each case is verified against a copy of the **whole suite directory** rather than of the single
  case file. `shell.llmll` imports sibling modules and cannot resolve them otherwise. `verify`
  still checks only the named file, so the extra siblings change no verdict, and the existing
  eleven families produce the same 41 results before and after.

The verdict vocabulary now has a third kind, `capability`, and
`crux-shell-undeclared-authority` is graded under it. It was previously filed as `refuted`
because the script greps for `error:`, though it fails at type-check rather than at the solver:
both print `error:` and exit 1, so a program the type checker rejected stood in for one the
solver disproved. `capability` matches the missing-capability diagnostic instead, and `refuted`
now rejects that diagnostic explicitly, so the two cannot drift back together. Relabelling the
case `refuted` fails the gate, which is how the distinction was checked rather than assumed.
