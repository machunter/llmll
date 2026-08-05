---
name: driver-ll-phase4b-implementation-plan
title: "DRIVER-LL Phase 4, sub-phase 4b: implementation plan"
status: "IMPLEMENTED. Written and executed against proposal Rev 9 (SETTLED, d271a16) at v0.14.86, building directly on sub-phase 4a (2b82464). Stages B, C and I have real bodies; driver-spec section 7:283-291 lands as one proved module, `validate.llmll`, with two functions and eight postconditions, reached from every 4b halt site. The acceptance clause is measured by sixteen new cover cells and five perturbations, every one of which reddens the cell it claims to check. Two proposal statements were refuted by execution (section 3.1 row 3 and section 10 case 4 both describe behaviour the reference does not have) and one enumeration was found short (section 9.1 names two unguarded reads; there are four). One COMPILER DEFECT is reported and NOT fixed, per the sub-phase's scope: `wasi.proc.run`'s timeout does not fire in a built binary, so the budget-overrun halt is written and unreachable through that route."
date: 2026-08-05
author: compiler-engineer
consumers: [user, language-team, experiment-lead, documentation-lead, professor]
---

# DRIVER-LL sub-phase 4b: implementation plan

## Restatement

Land the bodies of the three delegated stages proposal §9's 4b row names (B
scope, C rubric, I pre-registration) on top of 4a's sequencer, and land
driver-spec §7:283-291 as a **shared facility** rather than as three copies of
the same check. Acceptance: a delegated output that is absent, malformed or
subject-hardcoded fails the stage and is never skipped, every reachable halt in
those three stages records `failed`/`Errored`, the two unguarded reads §9.1 item
1 names become decisions, and stage I's absent validator is disclosed rather
than invented.

## What landed

| Artifact | What it is |
|---|---|
| [`tools/llmll-driver/validate.llmll`](../../tools/llmll-driver/validate.llmll) | **NEW.** The validation facility: `Verdict`, `verdict-of` and `verdict-outcome`, both body-faithful, eight postconditions |
| [`tools/llmll-driver/crux-validate-downgrade.llmll`](../../tools/llmll-driver/crux-validate-downgrade.llmll) | **NEW.** The warning downgrade §7:283-286 forbids |
| [`tools/llmll-driver/crux-validate-subject-hardcoded.llmll`](../../tools/llmll-driver/crux-validate-subject-hardcoded.llmll) | **NEW.** The validator §7:288-291 warns about |
| [`scripts/tests/test_driver_ll_4b.py`](../../scripts/tests/test_driver_ll_4b.py) | **NEW.** Eight checks that need no toolchain, every claim about the reference made by AST |
| [`tools/llmll-driver/registry.llmll`](../../tools/llmll-driver/registry.llmll) | eight new tables: which stages are ported, the declared floor, the prompt, the agent label, the precondition artifact and its three properties |
| [`tools/llmll-driver/sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) | six new `Phase` arms over one `Body` payload, the agent-invocation contract of §5, the ported bodies, and one halt site every channel reaches |
| [`scripts/driver_ll_cover.py`](../../scripts/driver_ll_cover.py) | sixteen new cells, a stub agent, and `prepare()` for what stage A would have left |
| [`scripts/tests/test_driver_ll_4a_cover.py`](../../scripts/tests/test_driver_ll_4a_cover.py) | the mirror count moves 14 to 15 |
| [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) | stage 8's scope and PASS line |
| [`tools/llmll-driver/EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json) | three cases, and the frozen-at moves to v0.14.86 |
| [`tools/llmll-driver/README.md`](../../tools/llmll-driver/README.md) | a section on the facility; the crux count moves ten to twelve |

**No compiler source was touched.** One compiler defect was found and is
reported below rather than repaired, per this sub-phase's scope constraint.

## The shared validation facility

Three stages owe §7:283-291 and the failure mode the 4b row names is three
near-copies of the same check. The facility is one module, two proved
functions, and one shell-side halt channel that reaches them.

**`verdict-of : bool int int -> Verdict`.** The decision, over presence, a
measured length, and the floor the **stage contract** declares. Its two useful
properties are structural rather than incidental:

- It takes **no string**. No byte of the subject document, of the agent's
  output, or of any run's conventions is in scope, so none can be read. That is
  the port's answer to §7:288-291 ("a validator that hardcodes the values seen
  in one run will silently report emptiness on the next"), and
  `test_the_validation_decision_takes_no_subject_content` pins the parameter
  list so a widening is red rather than silent.
- `[V7-NO-HARDCODE]` says **every** present output above the declared floor
  passes. A body fitted to the sizes one committed run produced satisfies every
  other post here and is refuted by this one;
  `crux-validate-subject-hardcoded.llmll` is that body.

**`verdict-outcome : Verdict -> Outcome`.** The single mapping, and the reason
the module is a module. `[V7-MANDATORY]` makes "non-downgradable" false if
violated; `[V7-ONLY-TWO]` proves the sub-phase constructs exactly two of
`Outcome`'s four constructors, with `[V7-NO-STOP]` and `[V7-NO-PARTIAL]` naming
the two it does not, so §9.1 item 3's "a site that comes out `stopped` is wrong
by construction" is a proof over this path rather than a convention.

**The shell seam is one function.** `halt-verdict` in the sequencer takes a
`Verdict`, hands it to `verdict-outcome`, and hands that to
`stage.record-outcome`. Nine of the eleven 4b halt sites go through it. It
passes `""` for the clause, and it does so because `[V7-NO-STOP]` and
`[V7-NO-PARTIAL]` prove there is no stopped constructor to cite, not because
nothing was found to write there.

**Two sites deliberately do not go through a `Verdict`**: `AgentRunner`'s budget
overrun and its non-zero exit. A budget overrun is not a fact about an output's
shape, and forcing it into a `Verdict` would be a category error. Those two
construct `Errored` and reach `stage.record-outcome` directly, whose
`[S4-FAILED]` and `[S4-NOT-STOPPED]` are the proved mapping. The **third**
`AgentRunner` condition, an absent declared output, does go through
`verdict-of` as `Absent`, because it is a fact about the output.

**The floor is a registry constant, not a measured value.** That is the
distinction §7:288-291 draws: a declared bar is the contract, an observed value
is the fitting. `test_the_port_floors_are_the_references_floors` relates
`registry.stage-floor` to the integer literals inside the reference's own
`require(out.stat().st_size > N)` calls **by AST**, not by grep.

**What the facility does not cover at 4b.** Only presence and a declared byte
floor. `check_extraction` (`rfc_to_implementation.py:386`),
`check_dispositioned` (`:481`) and `check_audit` (`:447`) decide over strings
and belong to stages D, G and G2 at 4c. They will need a second channel into
this module rather than a widening of `verdict-of`, whose whole property is that
it takes no string. Recorded so the absence reads as scope.

## The port list, site by site

The nine conditions the task enumerated, plus two the port must decide because
its host has no exception to fall through. Every one records `failed`/`Errored`
at exit 3 and writes **no** `clause`.

| Condition | Reference | Port | Cover cell |
|---|---|---|---|
| budget overrun | `AgentRunner.run:317-326` | `delegate-step`, `RErr` arm | **unreachable, see the compiler defect below**; the arm is exercised through spawn failure at **B12** |
| non-zero exit | `:328-330` | `delegate-step`, `RCode c != 0` | **B4** |
| no declared output | `:331-334` | `outp-step` to `verdict-of` as `Absent` | **B0** |
| unfilled prompt placeholder | `Ctx.prompt:540` | `tmpl-step`, `Malformed` | **B11** |
| no pinned RFC text | `_sources_text:629` | `srcs-step`, `Absent` | **B7** |
| `scope.md` at or under 200 bytes | `stage_B_scope:579` | `verdict-of`, floor 200 | **B2** |
| `rubric.md` at or under 400 bytes | `stage_C_rubric:593` | `verdict-of`, floor 400 | **B3** |
| `PROVENANCE.json` absent or malformed | `:573`, **unguarded** | `pre-step`, `Absent` / `Malformed` | **B5**, **B6** |
| stage B's `scope.md` absent, in stage I | `:1062`, **unguarded** | `pre-step`, `Absent` | **B8** |
| prompt template unreadable | `Ctx.prompt:536`, **unguarded, and §9.1 does not name it** | `tmpl-step`, `Absent` | **B10** |
| a pinned source unreadable | `_sources_text:625`, **unguarded and unreachable there** | `src-step`, `Absent` | none; see the disagreement below |

## Acceptance, clause by clause, with how each was measured

| Clause (proposal §9's 4b row) | Measured |
|---|---|
| a delegated output that is **absent** fails the stage | **B0**: the stub agent exits 0 having written nothing; exit 3, `B` is `failed`/`Errored` with detail "wrote no scope.md", `C` is never attempted. Mirrors `test_an_agent_that_exits_zero_without_writing_records_failed` |
| a delegated output that is **malformed** fails the stage | **B2** (10-byte `scope.md`) and **B3** (300-byte `rubric.md`). B3 is the discriminating one: the same size clears stage B's floor and fails stage C's, so a driver holding one global floor, or reading stage B's floor while validating stage C, passes every other cell and fails this one |
| a **subject-hardcoded** validator is refused | two channels. At the proof: `crux-validate-subject-hardcoded.llmll` refutes `[V7-NO-HARDCODE]`, and the gate reproduces it. At run time: **B14** drives the same binary over two subjects differing in filename, byte count, line count, provenance and output size, and requires the same three verdicts |
| **and is never skipped** | **B13**: a stage whose output failed validation left the artifact behind, and the next run re-runs it rather than skipping on that artifact's presence; a third run then does skip it, so the cell is not passing by disabling resumption |
| **every reachable halt records `failed`/`Errored`** | eleven cells assert status `failed`, outcome `Errored`, **and `clause` absent**. `clause` is written on the stopped path and nowhere else, so its absence is §9.1 item 3 observable at the manifest. `[V7-ONLY-TWO]` is the same statement proved |
| **the two unguarded reads are decisions** | **B5**, **B6**, **B8**. Each exits 3 with the reason on stdout as well as in the manifest, which is §4:139-143's second half and the one α cannot see |
| **stage I's absent validator is disclosed, not invented** | **B9**: a 0-byte `PRE-REGISTRATION.md` records `complete` at exit 0. `test_stage_I_has_no_validator_in_the_reference` asserts by AST that `stage_I_prereg` still holds zero halt sites, so a validator added there makes the port's negative floor a red test rather than a silent under-check |

Full cover: **31 passed, 0 failed** (the eleven 4a transition cells, the three
corrupt-manifest shapes, sixteen 4b cells, and the registry drift guard).

## Refute-crux measurements

Six perturbations, each built and run rather than argued. Each names what went
red and what stayed green.

| Perturbation | Result |
|---|---|
| P1: `outp-decide`'s `Absent` arm takes the success branch (the warning downgrade) | **B0 alone** red; 30 green |
| P2: the floor is read from stage B for every stage | **B3 and B9** red; 29 green. B9 is stage I, whose 0-byte output fails a floor of 200, so the cell that documents the absent validator is doing work as well |
| P3: the floor is fitted to the size the run produced, `(- size 1)` | **B2, B3 and B13** red; 28 green. B13's premise is a failing validation, so it falls with them |
| P4: the `PROVENANCE.json` parse guard is dropped | **B6 alone** red; 30 green |
| P5: the unfilled-placeholder check is dropped | **B11 alone** red; 30 green |
| P6: `validate.verdict-outcome` maps `Absent` to `Finished` in the **real** module | the refute-crux gate goes **70 passed, 1 failed**, naming `validate.llmll`'s frozen `safe` verdict |

P6 is the check 4a's own T7 scenario failed: a frozen `safe` verdict that could
not go red would prove nothing about the module it names.

Separately, and this is what makes `crux-validate-subject-hardcoded` worth its
file: the same body **without** its `(> size floor)` guard also refutes
`[V7-FLOOR]`, because 1638 sits below some floors. Measured over the guarded
body at v0.14.86:

| posts carried | verdict |
|---|---|
| `[V7-PRESENCE]` + `[V7-FLOOR]` | **SAFE** |
| `[V7-NO-HARDCODE]` alone | **REFUTED** |
| `[V7-NO-FLOOR]` alone | **REFUTED** |

So the mutant refutes through the anti-hardcoding post and not through a post
about floors. `[V7-NO-FLOOR]` is a **named consequence** of `[V7-NO-HARDCODE]`
rather than an independent obligation, and no body can break one and keep the
other; it is stated separately because it is the stage-I disposition of §9.1
item 2 and a reader should be able to find it by name.

`crux-validate-downgrade` refutes `[V7-MANDATORY]` **alone**: the same body
carrying `[V7-PASS]` plus `[V7-ONLY-TWO]` and neither stopped-constructor post
is SAFE, because `Finished` is one of the two constructors `[V7-ONLY-TWO]`
admits. Nothing but the mandatory clause catches the downgrade.

## Where the port disagreed with a settled document

### 1. §3.1's row 3 and §10 case 4 both describe behaviour the reference does not have

Rev 9 settles this and the task passed it on as settled; it is executed here
anyway, because the port reproduces the reference rather than the table and a
reader is entitled to the measurement.

**Executed.** A stage whose agent writes a 900-byte `scope.md`, clearing the
200-byte floor, and then exits 7:

```
returncode: 3
manifest B: {"status": "failed", "outcome": "Errored",
             "detail": "agent[scope] exited 7 after 0.0s; see .../agent.stderr.log"}
scope.md exists: True   size: 900
```

`AgentRunner.run` raises on the exit status at `:328-330` **before** the
output-existence check at `:331-334`, so the output being present and valid
never enters the decision. §3.1's row 3 says `complete`; §10 case 4 says "The
stage is **complete**; the exit code is recorded as manifest detail; no halt
occurs and §4 is not reached". Neither is true of the reference. §10 case 4 was
**not** amended at Rev 9 and still carries the wrong disposition; §3.1's row 3
likewise. Routed to language-team as two corrections, not repaired here.

The measurement is committed as
`test_a_valid_output_with_a_nonzero_exit_records_failed_in_the_reference`, and
cover cell **B4** is the port-side half.

### 2. §9.1 item 1 names two unguarded reads. There are four.

The two it names are `read_json` on `PROVENANCE.json` in stage B (`:573`) and
`read_text` on stage B's `scope.md` in stage I (`:1062`). Two more are in the
same class:

- **`Ctx.prompt:536`**, `(PROMPTS / name).read_text(encoding="utf-8")`. Shared
  by every delegated stage rather than owned by one, which is likely why a
  per-stage census missed it. Same disposition, same reasoning: guarded, and
  records `failed`/`Errored` at exit 3. Cover cell **B10**.
- **`_sources_text:625`**, `f.read_text(encoding="utf-8", errors="replace")`.
  Unguarded, and **unreachable in the reference**, because the replace means a
  decode error cannot raise. The port's `wasi.fs.read` has no replace channel
  and yields `RErr` on undecodable bytes, so the port records `failed` where the
  reference substitutes replacement characters and continues. This is a
  divergence rather than a repair, it fails toward re-running, and it has no
  cover cell because constructing it needs a non-UTF-8 pinned source, which is
  `FS-ENCODING-1` territory rather than 4b's.

### 3. §6.2's "stage O is the only delegated stage with no validator" and its scope

§9.1 item 2 already records that stage I is a second. The port measures both by
AST and pins both: `test_stage_I_has_no_validator_in_the_reference` and
`test_stage_O_also_has_no_validator_so_the_pair_is_the_finding`. Neither gets a
validator at 4b. The AST census is not vacuous: the same function reports
exactly one `require` in each of `stage_B_scope` and `stage_C_rubric`, which is
asserted in the same test so a parser that found nothing anywhere would fail.

### 4. §9's 4b row says "none new" under proved cores activated

`validate.llmll` is a **new** proved module with two body-faithful functions,
so 4b activates a proved core the table does not list, and §7 consequently owes
a **third** disclosure statement, which the sequencer header carries under
`[DISCLOSURE validate.verdict-of]`. The row is right that no *existing*
Phase 3 core acquires its first caller here; it is not right that the sub-phase
adds no proved surface. A facility that carried its obligations in comments
would have satisfied the row as written and would have been the worse port.

## The compiler defect, reported and not fixed

**`wasi.proc.run`'s timeout does not fire in a built LLMLL program.**

`TypeCheck.hs:189-191` states the contract in its own comment: "The timeout is
in the signature because a budget overrun must be a value (`RErr`), not a hang."
The emitted runtime body implements it with `System.Timeout.timeout` around
`P.waitForProcess`. It does not fire.

**Measured, four ways:**

1. The driver, `--timeout 1`, against an agent that sleeps 30s: exit 0, stage
   `complete`, `seconds: 30` in the manifest. The stage recorded success on a
   run that overran its budget by 29 seconds.
2. A minimal LLMLL console program issuing
   `(wasi.proc.run "/bin/sleep" ["20"] ... 1)`: 20.9 seconds elapsed.
3. The generated `package.yaml` carries **no** `ghc-options`, and the built
   executable reports `("RTS way", "rts_v")` under `+RTS --info`, which is the
   vanilla (non-threaded) RTS.
4. The same `timeout`/`waitForProcess` shape compiled directly: `stack ghc --`
   takes **20.4s**, `stack ghc -- -threaded` takes **1.5s** and returns
   `Nothing`. Under `runghc`, whose RTS is threaded, it also fires.

So the timeout needs the threaded RTS and the generated project does not link
it. **The remedy is not a one-line `emitPackageYaml` change**, and that was
established rather than assumed: adding `ghc-options: -threaded` to the
generated `package.yaml`, confirming it reached `tp.cabal`, and rebuilding left
the RTS way at `rts_v` and the elapsed time at 20 seconds. Where the flag is
dropped between the cabal stanza and the link is for the compiler team; this
sub-phase reports it rather than guessing.

**Consequence for 4b, disclosed rather than smoothed over.** The budget-overrun
halt site is written, is on the `RErr` arm of `delegate-step`, and is not
reachable through the timeout. The arm itself is not dead: a spawn that fails
also yields `RErr`, and cover cell **B12** exercises it with a nonexistent
`--agent-exe`, so the arm's decision is measured even though one of its two
producers is broken. The detail string names both causes for that reason.

Routed as a defect against `wasi.proc.run`, severity: an agent that hangs hangs
the run, and the driver records the stage `complete` afterwards rather than
`failed`. That second half is the worse one.

## Two compiler-surface findings, neither a defect

**An enum postcondition with a negated antecedent is provable only when the arm
that falsifies it is tested first.** Measured at v0.14.86:

| shape | verdict |
|---|---|
| 3-constructor enum, `(=> (not (= v Passed)) ...)`, `Passed` arm **last** | **refuted**, "else-branch does not satisfy postcondition" |
| the same three arms with `Passed` **first** | **SAFE** |
| 2-constructor enum, either order | **SAFE** |

The else-branch of the lowered nested-`if` carries only the disequalities of the
arms above it and no exhaustiveness fact, so with three constructors the solver
cannot conclude `v = Passed` there. With two, one disequality determines the
value. This decided `verdict-outcome`'s arm order and the order is documented at
the function. It is the same family as `ENUM-EQ-FALLBACK` and is worth a
language-team read: the obligation is true and the body satisfies it, and only
the lowering's branch order decides whether it is provable.

**`string-slice`'s convention was confirmed from the spec, not guessed.**
`LLMLL.md:2440` gives `(string-slice s start end)` as the half-open `[start,
end)` window with the string first, and `CodegenHs.hs:364-368` agrees. This is
the builtin whose sibling `string-split` cost 4a a cycle for having no
documented argument order; that gap is now closed on both. `pad5` is
nevertheless written by cases rather than with `string-slice`, so the numbering
that reaches every agent prompt does not rest on a second builtin's convention.

## A change to 4a's stub that 4b required

`stub-body` now emits **JSON** for an artifact whose path ends `.json`, and flat
text otherwise. Stage B is real and reads stage A's `PROVENANCE.json` through
`json-parse`; stage A is not ported (it needs `HTTP-GET-1`) and is not listed in
any of §9's sub-phase rows, so its stub is what a run selecting `A,B` hands to
stage B. With the flat-text stub every such run halted at B on "does not parse
as JSON", which is a correct decision over a wrong input rather than a decision
about the pipeline: cover cells T8, T9 and T10 went red on it, which is how it
was found. The distinctness property 4a's comment states is unchanged, the stage
key and the artifact path both still being in the body, so no two stubs share a
digest.

The alternative was to move the 4a cover's cells off stages A, B and C onto
three stages that remain stubs. That was rejected: every stage becomes real
eventually, so the cover would move again at 4c, 4d and 4f, and the eleven cells
would drift away from the assertions the campaign accepted.

## Divergences from the reference, disclosed

Each is in the sequencer header under `[DISCLOSURE validate.verdict-of]` or
beside the code, and each is here so a reader does not have to find them.

1. **`size` is code points, not bytes.** The reference tests
   `out.stat().st_size`; the port tests `string-length` of the decoded text.
   They agree on ASCII and disagree on any multi-byte character, in the
   direction of the port measuring smaller. There is no `wasi.fs.stat`;
   `FS-STAT-1` is filed for the mtime half of the same gap and a size accessor
   would close this one.
2. **Presence and decodability are collapsed.** `wasi.fs.read` yields `RErr`
   both for a path that does not exist and for one whose bytes are not valid
   UTF-8, so an output that exists and cannot be decoded records the "wrote no
   `<file>`" detail. The status is the same under both, which is what
   §7:283-286 wants of an output not meeting its declared shape, so this costs
   the reason string and not the decision.
3. **The placeholder check tests for `{{`**, where the reference's regex is
   `\{\{(\w+)\}\}`. The port is stricter and its detail does not list the
   placeholder names.
4. **The non-zero-exit detail carries no duration.** The reference writes
   "exited 7 after 0.0s"; the port has no second clock reading at that point and
   writes "exited 7". α compares `detail` as a non-empty predicate (§2.1), so
   this is outside clause 1a either way.
5. **`--prompts-dir` has no reference counterpart.** `PROMPTS` is a module
   constant the reference derives from `__file__` (`:81`) and a compiled binary
   has no `__file__`. It is required for the same reason `--agent-cmd` is
   required, and the flag is disclosed rather than defaulted to a guess about
   the tree.
6. **`--rfc-url` is not taken.** The reference requires it; the port has no use
   for it until stage A lands, which needs `HTTP-GET-1`.
7. **`BARRIERS` is embedded as the string `json.dumps(BARRIERS, indent=1)`
   produces**, rather than rebuilt through `json-serialize`. The reference's
   dict is a module constant in insertion order and LLMLL's serializer neither
   guarantees that order nor writes `indent=1`. It reaches the prompt and no
   abstraction-function field.
8. **The provenance reaching stage B's prompt is the file's raw text**, where
   the reference re-serializes through `read_json` then
   `json.dumps(..., indent=1)`. For a `PROVENANCE.json` that `write_json` wrote,
   the two agree modulo a trailing newline.

Against this, one thing is byte-identical and was checked rather than assumed:
`_sources_text`'s numbering. The port's rendered `{{rfc_text}}` equals
`"\n".join(f"{i:5d}| {ln}" for i, ln in enumerate(raw.split("\n"), start=1))`
exactly, including the trailing empty line a file ending in a newline produces.
That is the one piece of prompt formatting that carries a downstream obligation:
extraction rows cite line spans and reconciliation matches on them.

## Gates

Baselines are at `d271a16`; the `stack test` figure moved under a **concurrent
commit by another agent**, `1e33d69`, and not under this change.

| Gate | Baseline (`d271a16`) | After | Note |
|---|---|---|---|
| `stack build` | clean | **clean**, no new warnings | |
| `stack test` | 1642 examples | **1651 examples, 0 failures** | +9 from `1e33d69`; this change adds **no Haskell**, so its own delta is 0 |
| `bash scripts/build_smoke.sh` | 6 stages | **6 stages** | stage 8 now runs 31 cells rather than 15; the `LC_ALL=C` half still reports NOT EXERCISED on macOS, which is not a failure |
| `python3 -m pytest scripts/tests/` | 123 passed 1 skipped | **131 passed, 1 skipped** | +8, all in `test_driver_ll_4b.py` |
| `python3 scripts/doc_path_lint.py` | 848 in 160 files | **863 in 161 files**, all resolve | the lint enumerates through `git ls-files`, so the 849/160 reading it gives on an untracked tree omits this document; 863/161 is the figure with this document visible to git |
| `bash scripts/refute-crux-gate.sh` | 68 passed | **71 passed, 0 failed** | +1 safe (`validate.llmll`), +2 refuted; the file now freezes 27 cases, 13 refuting mutants, 1 capability rejection, 13 `safe` of which one is the good twin |
| `scripts/driver_ll_cover.py` | 15 passed | **31 passed, 0 failed** | |

**One count in `tools/llmll-driver/README.md` was already wrong before this
change and is repaired here.** It said the suite freezes "ten refuting mutants";
the file held eleven, sub-phase 4a having added two without moving the sentence.
The repair was to **count the file**, not to add two to the stale number, which
would have produced twelve. Risk 3c again, and the third instance the DRIVER-LL
line has recorded.

## Not done

- **Stage G2 under the stub** stays broken (harness finding F-4) and was not
  touched. It does not reach 4b: no gate stage is ported here.
- **The budget-overrun path** is written and unreachable through the timeout.
  See the compiler defect above. It is not worked around, and no cover cell
  claims to exercise it.
- **`rfc_url` is still not written into the manifest.** The reference does
  `manifest.setdefault("rfc_url", a.rfc_url)`; the port takes no `--rfc-url`.
- **Content-shape validation** (`check_extraction`, `check_dispositioned`,
  `check_audit`) is 4c's, and the facility will need a second channel for it
  rather than a widening of `verdict-of`.
- **`--status` and `audit_blindness`** (§6.3, §6.4) remain deferred, and remain
  specification obligations rather than operator plumbing.
- **A cover cell for the unreadable pinned source** (divergence 2 in the
  disagreement section) needs a non-UTF-8 artifact and belongs with
  `FS-ENCODING-1`.

## Routing

- **language-team**: §3.1 row 3 and §10 case 4 both need correcting to `failed`;
  §9.1 item 1's enumeration of unguarded reads is short by two; §9's 4b row
  "proved cores activated: none new" is wrong, `validate.llmll` being new
  proved surface and owing a §7 statement.
- **compiler-engineer (a different slot from this one)**: `wasi.proc.run`'s
  timeout does not fire in a built program, and `-threaded` on the generated
  package does not fix it.
- **professor**: the negated-antecedent-over-an-enum result. The obligation is
  true and the body satisfies it; only the lowering's branch order decides
  whether liquid-fixpoint can see it. Worth knowing whether that is a
  fundamental limit of the encoding or a missing exhaustiveness axiom.
- **documentation-lead**: no user-visible CLI change to a **shipped** surface;
  the driver's own flags are described in
  [`tools/llmll-driver/README.md`](../../tools/llmll-driver/README.md), which is
  updated here. No schema delta. Test-count delta: +8 Python, 0 Haskell.
