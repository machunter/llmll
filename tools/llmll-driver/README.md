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
shell demonstrates the tier's discipline over a handful of operations, and the orchestration that
would actually run fifteen stages is not written.

## The cruxes

[`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) freezes eight refuting mutants and one good
twin. **Five of the eight are not invented.** They are defects that shipped in the Python driver,
or behaviour it still has:

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

One gap remains, recorded in the suite's `note`. The script's verdict vocabulary is `safe` and
`refuted` only, and a capability violation is neither. `crux-shell-undeclared-authority` is
recorded as `refuted` because the script greps for `error:`, though it fails at type-check rather
than at the solver. Conflating the two is the sort of category error this pipeline is otherwise
careful about, and a third expect kind would fix it.
