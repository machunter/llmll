---
name: driver-ll-phase4a-implementation-plan
title: "DRIVER-LL Phase 4, sub-phase 4a: implementation plan"
status: "IMPLEMENTED. Written against proposal Rev 7 (SETTLED) at v0.14.84; executed against v0.14.85 after PROC-BOUNDARY-1 shipped. Findings A and B are CLOSED by that capability and the shim this plan recommended was NOT built: the port receives its flags through wasi.proc.args and exits 0, 2 or 3 through the :status projection, so nothing sits between the rig's assertions and the program. Three modules, two cruxes, a fifteen-scenario cover and three static tests landed; the eleven-cell cover passes with T7 included, the three corrupt-manifest shapes are decisions, and section 4's row asymmetry is reproduced. Four new findings, two of which are disagreements with a settled document: PROC-BOUNDARY-1 section 4.4's range refinement is provable only where :status takes a SCALAR state, and T7 did not discriminate its own conjunct until the digests-match boolean was gated the way the reference gates it."
date: 2026-08-05
author: compiler-engineer
consumers: [user, language-team, experiment-lead, documentation-lead, professor]
---

# DRIVER-LL sub-phase 4a: implementation plan

## Implementation record

Everything below the horizontal rule is the plan as written before
`PROC-BOUNDARY-1` shipped. This section records what was built against it, what
was measured, and where the port disagreed with a settled document. Read it
first; the plan's findings A, B and C and its shim recommendation are superseded
here and are annotated in place.

### What landed

| Artifact | What it is |
|---|---|
| `tools/llmll-driver/registry.llmll` | the sixteen-stage table as five `if`-chains over an index |
| `tools/llmll-driver/manifest.llmll` | the row schema carrying section 4's asymmetry, and the one-predicate corrupt-manifest guard |
| `tools/llmll-driver/sequencer.llmll` | section 4's `Phase` sum, the step machine, the resume gate, the two halt channels, argv parsing, and `exit-code` |
| `tools/llmll-driver/crux-skip-digest-dropped.llmll` | section 10 case 19's second mutant |
| `tools/llmll-driver/crux-exit-code-halt-as-zero.llmll` | `Stopped` mapped to exit 0 |
| `scripts/driver_ll_cover.py` | the acceptance cover: eleven cells, three manifest shapes, one registry-drift scenario |
| `scripts/tests/test_driver_ll_4a_cover.py` | the three checks that need no toolchain, plus the cover behind a skip |

Modified: `tools/llmll-driver/EXPECTED_VERDICTS.json` (five cases, and the
shipped-defect count moves from five to six), `scripts/build_smoke.sh` (stage 8),
`tools/llmll-driver/README.md` (crux counts and a "what the driver does today"
section). **No compiler source was touched**, so section 12's last line holds
without the shim it was read as needing.

### The shim was not built, and that is the whole difference

The plan's finding B concluded that `returncode == 2` could not be met by an
LLMLL program and recommended twenty lines of shell. `PROC-BOUNDARY-1` closed
both halves before this was executed. `:init` issues `wasi.proc.args` and the
argument vector arrives as `r0` on the existing `RList` arm; `:status` names a
projection from the final state and the process exits with its result. The
cover therefore invokes the binary directly with `--workdir`, `--only`,
`--force`, `--halt-at` and `--halt-kind`, and asserts on the returncode.

Two consequences the plan's risk 1 and open question 1 asked about are settled
rather than mitigated: the exit status is the program's, not a shim's, and there
is no unverified shell mediating an acceptance result.

### Acceptance, clause by clause, with how each was measured

| Clause (proposal section 9) | Measured |
|---|---|
| the eleven-cell cover passes, T7 included | `scripts/driver_ll_cover.py`, **15 passed, 0 failed** against the built binary, one scenario per cell plus the three shapes plus a registry check. Every scenario carries the name of the Python-side test whose decision it reproduces |
| section 10 cases 16, 17, 18 handled as decisions | three scenarios; each asserts **exit 2**, the reason substring, `STOP:` on stdout, that no stage ran, and that `MANIFEST.json` is byte-identical to the corrupt bytes written |
| section 4's manifest-row asymmetry reproduced | `want_complete_row` asserts `outcome`, `detail` and `clause` are ABSENT from a complete row; `want_halt_row` asserts `kind` and `seconds` are absent from a halt row. **Refuted:** adding `"outcome": "Finished"` to `complete-row`, rebuilding, and re-running turned **T1, T8, T9 and T10 red** and left the other eleven green |
| section 7's two 4a statements written | both are in the sequencer header behind the anchors `[DISCLOSURE skip.may-skip]` and `[DISCLOSURE stage.record-outcome]`; `test_the_sequencer_carries_both_section_7_disclosures` fails if either is dropped. **Refuted:** renaming one anchor turned that test red |
| both proved cores acquire a caller | `may-skip` is called once per stage from `decide`; `record-outcome` is called from `halt-now`. `llmll verify sequencer.llmll` is **SAFE**, `exit-code` body-faithful, and the verdict is frozen in `EXPECTED_VERDICTS.json` |

The `skip.may-skip` statement grew from the three items the plan predicted to
**four**: a response arm that is neither `RText` nor `RErr` is also read as
absent, and that branch is unreachable rather than merely untaken.

### Refute-crux measurements

Five perturbations were built and run rather than argued. Each names what went
red and, as much to the point, what stayed green.

| Perturbation | Result |
|---|---|
| `complete-row` gains `"outcome": "Finished"` | T1, T8, T9, T10 red; 11 green. This is section 4's stated decision, measured |
| `manifest-fault` drops the `stages`-is-an-object arm | **case18 alone** red, exit 0 where 2 is owed, and the run proceeded into stage A |
| the call site drops the digest conjunct, `(and (not forced) (and recorded present))` | **T6 alone** red; T5 stayed green, so the mutation did not simply disable resumption |
| `artifacts-present` hardcoded `true` at the call site, BEFORE the repair below | **nothing red, 15 of 15 green.** See the finding |
| the same, AFTER the repair | **T7 alone** red |
| `registry.llmll` `ROOTS.txt` renamed to `roots.txt` | `test_the_llmll_registry_agrees_with_the_python_registry` red, naming stage L |

Separately, and this is what makes `crux-skip-digest-dropped` worth its file:
the same digest-dropped body carrying **only** `[S5-PRESENCE]` verifies **SAFE**.
So the new crux refutes through `[S5-SKIP]` and not through `[S5-PRESENCE]`,
where `crux-skip-presence-only` refutes through both. The entailment section 11
records is now observable in the gate rather than argued, which is what
`CLAUSE-INDEP-1` is filed against.

### Where the port disagreed with a settled document

**1. `PROC-BOUNDARY-1` section 4.4's range refinement is provable only for a
scalar state.** The proposal puts `{v : int | 0 <= v && v <= 255}` on "the
declared contract of whatever function `:status` names" and its verification
mapping calls it "QF-LIA, auto-discharged". **Executed:** a `def` whose body
applies `first` to a pair falls back from body-faithful verification, measured
on `[s: (int, int)]` as much as on this driver's state type, while the same
arithmetic over a bare `int` parameter is body-faithful. Since `:status` is
applied to the state and every driver's state is a product, its range post is
**contract-checked, not proved**, for any program that is not the fixture. The
fixture `scripts/build-smoke/proc_boundary.llmll` takes `[s: int]`, which is the
provable case, so the fixture cannot exhibit the limit.

The port carries the weight elsewhere instead: `exit-code : Status -> int` is
body-faithful and carries the range plus three per-constructor mappings plus
`[EXIT-NOVACUOUS]`, and `drv-status` clamps, so a state carrying 256 exits 255
rather than exiting 0 and reporting success. Routed to language-team as a
correction to section 4.4 and to section 5's mapping row, not repaired here.

**2. T7 was not discriminating its own conjunct.** Proposal section 2.3 defines
T7 as "condition (b) alone", and the reference makes that true by computing
`mismatched` under `if recorded and artifacts` (`:1934`), so when an artifact is
absent the mismatch list is empty and only presence prevents the skip. The
port's probe collapses presence and digest into one `wasi.fs.sha256` (finding D),
so an absent artifact answers `RErr`, its hex is `""`, and `""` differs from the
recorded digest: **(b) and (c) failed together and (c) masked (b)**. Measured by
hardcoding `artifacts-present = true` at the call site, which left all fifteen
scenarios green including T7.

Repaired in the port rather than filed: `digests-match` is now
`(if (and recorded present) matched true)`, which is exactly the reference's
`not mismatched` rather than an approximation of it. The same perturbation now
turns T7 red alone. The decision was never wrong under either form, `[S5-SKIP]`
holding in both; what changed is what the cover can observe.

**3. `:866` is not reached at 4a.** The restart record asks the port to report a
disagreement if it finds one. 4a lands no stage bodies, so it constructs no halt
at a stage-H acceptance bar and has nothing to say about the site. Recorded so
its absence reads as scope rather than as agreement.

### Two compiler-surface findings, neither a defect

**`string-split` takes the SEPARATOR first.** `LLMLL.md:2433` gives the type as
`string string -> list[string]` with no argument names and the note "Split on
delimiter"; the generated body is `string_split sep str`
(`CodegenHs.hs:359-366`); and there is **not one call site in the tree** to read
the order off. Getting it backwards splits the separator by the subject and
yields `[","]`, which type-checks and passes every check-time gate. Measured,
and the sequencer wraps it as `split-on` with the order stated at the wrapper.
This is a documentation gap in `LLMLL.md`, doc-lead's slot, not a compiler bug.

**A `def` cannot call a same-module `def` on a cold check.**
`checkCalleeAdmissibility` admits a non-builtin callee only on a persisted,
hash-valid, fully-verified `EvidenceRecord` (`TypeCheck.hs:893-921`), and on a
first `llmll check` of a new file there is no sidecar, so
`(def a … (b …))` with `b` defined two lines above is rejected cold with
"not body-faithful and not in the trusted prelude". The port has one proved
`def` calling nothing and one calling only builtins, so nothing is blocked;
recorded because the diagnostic's own remedy ("verify `b` first") is not
reachable in a single command for a new module.

### Two syntax gotchas that cost a cycle each

- A `match` arm inside a `def` must **bind** its payload. `isCoreBodySyntactic`'s
  payload-constructor leg (`Syntax.hs:810`) admits only
  `PConstructor n [PVar _]`, so a `_` wildcard payload makes the whole match
  non-core and the `def` is rejected at `check` with "unrestricted match". Eight
  arms of `drv-status` bind a name they never use for exactly this reason.
- `wasi.fs.mkdir` creates parents and is `RNone` on a directory that already
  exists, and `wasi.fs.write` does **not** create parents. Every artifact write
  in the port is `(seq-commands (mkdir dir) (write path body))`, which also
  confirms RC-2 in a running program: the composite delivers the write's
  response and drops the mkdir's.

### Gates, measured at v0.14.85

The version pin moved from 0.14.84 to 0.14.85 under this session, doc-lead's
slot. The two toolchain gates were re-run against the rebuilt binary.

| Gate | Baseline | After |
|---|---|---|
| `stack build` | clean | **clean**, no new warnings |
| `stack test` | 1638 examples | **1638 examples, 0 failures** (no Haskell added) |
| `bash scripts/build_smoke.sh` | 5 PASS | **6 PASS**, the new one being the 4a cover at 15 of 15 |
| `python3 -m pytest scripts/tests/ -q` | 120 passed | **123 passed, 1 skipped** |
| `python3 scripts/doc_path_lint.py` | 796 in 159 files | **824 in 160 files, all resolve** |
| `bash scripts/refute-crux-gate.sh` | 63 passed | **68 passed, 0 failed** |

The doc-lint delta is not all this change: the concurrent doc-lead pass moved it
too. The one file this change adds to the lint's population is
`tools/llmll-driver/README.md`, which was already in it.

### Not done

- **Stage G2 under the stub** stays broken (harness finding F-4) and was not
  touched. It does not reach 4a: the cover runs no stage bodies.
- **`rfc_url`** is not written into the manifest. The reference does
  `manifest.setdefault("rfc_url", a.rfc_url)`; the port has no RFC URL until
  stage A lands at 4b, and it preserves any existing top-level member because
  every write is a `json-set` into the parsed manifest.
- **`seconds` is an integer**, from two real `wasi.clock.monotonic` readings.
  `json-of-int` is the only numeric injection, so the reference's one-decimal
  float is not expressible. The abstraction function discards the field.

---

## Restatement

Land the sequencer, the manifest reader and writer, the resume gate and the two halt
channels in `tools/llmll-driver/` as `def-shell` orchestration around `skip.may-skip` and
`stage.record-outcome`, with no stage bodies, such that the eleven-cell transition cover of
proposal §2.3 and the three corrupt-manifest shapes of §10 cases 16 through 18 are decided by
the LLMLL program rather than crashed through it, and such that the manifest row schema
reproduces the asymmetry §4 records.

## Context located

1. [`docs/design/driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md) §2.1, §2.3, §3.5,
   §3.6, §4, §7, §9, §10 cases 15 to 18, §11, §12: the settled spec input. §12's last line
   asserts 4a needs no compiler change; §9's acceptance cell is the red/green target.
2. [`docs/design/driver-ll-phase4-RESTART.md`](driver-ll-phase4-RESTART.md) §4: five settled
   facts taken as given, not re-derived.
3. [`tools/llmll-driver/spine.llmll`](../../tools/llmll-driver/spine.llmll): the Phase 3
   console-harness idiom this extends: `def-main :mode console`, an `int` state, one command
   per step, and at `:673-679` the RC-4 note that the terminating step's command is dropped
   and that `:on-done` was not usable for an `int` state.
4. [`tools/llmll-driver/skip.llmll`](../../tools/llmll-driver/skip.llmll) and
   [`tools/llmll-driver/stage.llmll`](../../tools/llmll-driver/stage.llmll): the two cores 4a
   activates. `may-skip` takes four bools; `record-outcome` takes a four-arm `Outcome`.
5. [`scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py): the
   comparison target. `read_manifest` at `:212`; the resume gate at `:1931-1953`; the four
   manifest write sites at `:1965-1971`, `:1982-1987`, `:1999-2004`, `:2006-2013`; the three
   raising forms `require` / `require_spec` / `require_written` at `:343`, `:358`, `:373`.
6. [`scripts/tests/test_rfc_pipeline_integration.py`](../../scripts/tests/test_rfc_pipeline_integration.py):
   fourteen tests carry the eleven cells and the three shapes. The rig at `:271-291` passes
   `--workdir`, `--only`, `--allow-volatile-workdir` and asserts on `returncode`.
7. [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs) `emitMainBody`:
   the console Mealy loop, its stdin drive, and its `main :: IO ()` with no `exitWith`.
8. [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) `builtinEnv`:
   the closed builtin surface. Fourteen `wasi.*` names, no argv, no environment, no exit.
9. [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh) `:152-153` and `:158-160`: the
   in-tree statements that the console harness consumes one stdin line per step and that
   "LLMLL has no way to read an environment variable". Corroborates finding A independently.
10. [`tools/llmll-driver/EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json)
    and [`scripts/refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh) `:49`: the frozen
    verify verdicts for this directory. Any new module must enter this file.
11. `docs/compiler-team-roadmap.md` DRIVER-LL row: read, not edited. Doc-lead's slot.

## Measured baseline

Taken at `main`. The restart record's six uncommitted files landed during this session as
`766be6e` (proposal Rev 7) and `c10081d` (the harness leg), so HEAD is **`c10081d`** and the
content measured is identical to the tree the measurements ran against. `llmll version`
reports **0.14.84**.

| Gate | Baseline |
|---|---|
| `stack test` | **1616 examples, 0 failures** (5.36s) |
| `python3 -m pytest scripts/tests/ -q` | **120 passed** (18.34s) |
| `python3 scripts/doc_path_lint.py` | **768 citations in 157 files, all resolve** |
| `python3 scripts/rfc_to_implementation.py --self-test` | not re-run; no compiler source changes |

## Findings, each with what was executed

Proposal risk 3c is the standing instruction: a grep over a design document's vocabulary is
not a code audit. Every claim below was executed. Probe sources are in the session scratchpad
and are not proposed for the tree.

### A. There is no argv channel and no environment channel

**CLOSED by `PROC-BOUNDARY-1`, shipped at `4e5ff29`.** `wasi.proc.args` delivers
the argument vector on the existing `RList` arm through RC-3. The environment
half is untouched and stays filed as `PROC-ENV-1`, blocking nothing: the port
needs no environment variable, `--workdir`, `--only` and `--force` all being
flags. Everything below is the measurement as taken at v0.14.84 and is retained
because the argument for the capability rests on it.

`builtinEnv` declares fourteen `wasi.*` names
([`TypeCheck.hs:158-215`](../../compiler/src/LLMLL/TypeCheck.hs)) and none of them reads a
command line or an environment variable. **Executed** rather than grepped, because the grep is
exactly the shape risk 3c names: five candidate names were compiled. `llmll check` reports
**OK with a warning** for all five (`warning: unbound variable 'wasi.proc.args' (may be in
scope at runtime)`), and `llmll build` reports **error** for all five. The gap is therefore
invisible to `check` and appears only at build.

`ModeCli` exists and does read argv
([`CodegenHs.hs:1659-1663`](../../compiler/src/LLMLL/CodegenHs.hs), `args <- getArgs`), but its
body is `print (step args)`: it performs no `Command` and receives no `Response`, so it cannot
run the driver's effects. Console is the only usable mode and it has no argv.

`build_smoke.sh:158-160` states the same fact in-tree, in a comment explaining why a fixture
hardcodes `/tmp`. The finding is not new to this plan; what is new is that it blocks the
rig-substitution reading of §12's harness line.

**Consequence.** The port is not argv-compatible with the reference. `--workdir`, `--only`,
`--force` cannot arrive as flags. §12's "a second driver coming under test" understates this:
the rig cannot be parameterized over `DRIVER` alone.

### B. There is no process exit-status channel

**CLOSED by `PROC-BOUNDARY-1`, and this section's recommendation is WITHDRAWN.**
`def-main` takes an optional `:status`, a total projection from the state type to
`int`, applied when `:done?` holds. The shim recommended below was not built and
must not be. `PROC-EXIT-1` was never filed and is not owed. One residue, and it
is a finding against the capability rather than against this plan: the range
refinement is provable only where `:status` takes a scalar state, which no driver
does; see the implementation record. Everything below is the measurement as taken
at v0.14.84.

`emitMainBody` for `ModeConsole` emits `main :: IO ()`
([`CodegenHs.hs:1574-1580`](../../compiler/src/LLMLL/CodegenHs.hs)) and `System.Exit` is
imported at `:202` only so that `wasi.proc.run` can *read* a child's status into `RCode`
(`:687`). **Executed:** a console program whose step constructs a halt line exits **0**, and so
does the same program run with a starved stdin. There is no expression in the language whose
evaluation sets the process status.

**Consequence.** The rig's `returncode == 2` (three manifest-shape tests) and `returncode == 3`
(the silent-agent test, which is 4b) cannot be met by the LLMLL program. This is the single
place where §12:1102's "sub-phase 4a needs no compiler change" holds only with a shim, and §12
does not name the shim. **Recommendation: shim, not compiler change.** File the capability gap
as `PROC-EXIT-1`, unscheduled, on the `PROC-ENV-1` precedent
([`driver-ll-open-work.md`](driver-ll-open-work.md) R-14): it blocks nothing once the shim
exists, and a gap with no blocker dilutes the roadmap's Active Items table.

### C. A starved stdin budget is a silent success

**CLOSED by `PROC-BOUNDARY-1`.** With `:done?` DECLARED, exhaustion exits 70 and
`:status` is not consulted, so the terminal-marker check this section demanded is
no longer the whole mitigation. The port keeps a terminal marker anyway,
`[driver-ll] end status=N` through `:on-done`, and the cover reports 70 as a
budget error rather than as a decision. Everything below is the measurement as
taken at v0.14.84.

The loop reads `eof <- hIsEOF stdin; if eof then return () else …`
([`CodegenHs.hs:1585-1587`](../../compiler/src/LLMLL/CodegenHs.hs)). **Executed:** the same
binary given four stdin lines printed its terminal line, and given two lines printed a prefix,
performed a partial sequence of commands, and exited **0** with no diagnostic on either
channel. A run truncated at stage nine is byte-indistinguishable from a run that finished, by
exit status.

**Consequence.** Every LLMLL console driver needs a terminal marker and a caller that requires
it. Without one, an under-budgeted invocation reports a green run over a manifest missing seven
stages. This is a hazard the campaign has not met yet because `spine.llmll` is nineteen fixed
states and 4a's step count is data-dependent.

### D. `wasi.fs.sha256` collapses presence and digest into one command

**Executed** against a workdir holding one file:

| Call | Result |
|---|---|
| `wasi.fs.sha256` on a missing path | `RErr "…: withBinaryFile: does not exist (No such file or directory)"` |
| `wasi.fs.sha256` on a present path | `RText "14bca160…b508db"` |
| `wasi.fs.read` on a missing path | `RErr "…: openFile: does not exist"` |
| `wasi.fs.list` on a missing directory | `RErr "…: getDirectoryContents:openDirStream: does not exist"` |
| `wasi.fs.write` to a path whose parent is absent | `RErr "…: openFile: does not exist"` |
| `wasi.fs.mkdir "aa/bb/cc"` from nothing | `RNone`, and the three levels exist afterwards |

So `artifacts-present` and `digests-match` cost **one command per declared artifact**, not two,
and are distinguished by *constructor* rather than by parsing the error text. The reference
computes the two separately, `.exists()` at `:1933` and `sha256_file` at `:1941`.

The collapse is conservative in the correct direction: any `RErr` yields
`artifacts-present = false`, which by `[S5-SKIP]`'s contrapositive forces a re-run and can
never cause a skip. That is driver-spec §4:150-153's safe direction. It also means a
permission error and an absent file are indistinguishable to the port, which is a new
shell-side decision and belongs in §7's `skip.may-skip` statement as a third item.

`wasi.fs.mkdir` creating parents matters because `wasi.fs.write` does not, where the reference's
`write_json` does `p.parent.mkdir(parents=True, exist_ok=True)` (`:204`).

### E. The three corrupt-manifest shapes are constructor-decidable, and the port improves on the reference here

**Executed** over all seven JSON shapes:

| Probe | `{}` | `{"A":1}` | `[]` | `"x"` | `5` | `true` | `null` |
|---|---|---|---|---|---|---|---|
| `json-set j "__probe__" (json-of-int 0)` | Success | Success | Error | Error | Error | Error | Error |

`json-set` is therefore a **total, constructor-decidable `is-object?`**. Combined with
`json-parse`'s own `Result`, the guard is

```
manifest-usable?(j) = is-object?(j)
                    ∧ json-get(j, "stages") = Success sj
                    ∧ is-object?(sj)
```

and the three shapes fall out with no substring test anywhere:

| §10 case | Input | Where it is decided |
|---|---|---|
| 16 truncated | `{"stages": {"A": ` | `json-parse` returns `Error "json-parse: unexpected end of input"` |
| 17 not an object | `[]` | `is-object?(j)` is false |
| 18 `stages` not an object | `{"stages": [], "rfc_url": "x"}` | `is-object?(sj)` is false |

Two things follow. First, the port owes **no §7 disclosure** for this guard, where a message
substring test would have owed one: `json-get`'s two failure messages (`json-get: no member
'A'` on a legitimately empty object, `json-get: not an object (looking for 'A')` on a corrupt
one) share the `Error` constructor, so discriminating on them would be exactly the unproved
abstraction §7 is about. `json-set` avoids it.

Second, the guard is **over what the reader indexes**, expressed positively, which is the
lesson §10 case 18 records after two guards written from a two-case enumeration left a third
case live. The reference's guard discriminates by Python exception site, so a fourth shape
would find a fourth site; the port's cannot, because there is exactly one predicate and it is
total. This is a place where the port is stronger than the reference and the plan says so
rather than presenting it as parity.

### F. §4's sum encoding makes `:on-done` usable, which retires the RC-4 workaround

**Executed:** a state of `((Json, (list[string], bool)), Phase)` with a five-arm `Phase` sum
carrying pair payloads compiles, builds and runs. `json-serialize` round-trips through
`wasi.fs.write`. Then, twice in this session, a terminal-step command was **constructed and
dropped**: RC-4 ([`CodegenHs.hs:1550`](../../compiler/src/LLMLL/CodegenHs.hs), the `done?`
branch that binds `cmd` and does not perform it). Adding `:on-done` over the same sum-typed
state printed the halt line.

`spine.llmll:673-679` records `:on-done` as not usable, and is correct for an `int` state,
because `:on-done` is `State -> Command` and an `int` carries no reason to render. §4's sum
carries the reason, so `:on-done` becomes available. The proposal does not draw this
consequence and the port needs it: without `:on-done` every halt report is the terminating
step's command and is dropped, which fails driver-spec §4:139-143's requirement that a halting
stage report the reason on its output, and fails it silently.

### G. The proposal's line citations into the reference are stale, and §3.5's count is wrong at HEAD

**Executed** by locating each cited condition by its own text:

| Proposal cites | Resolves at HEAD | Offset |
|---|---|---|
| §2.3 `:1877` `artifacts` | `:1933` | +56 |
| §2.3 `:1890` `if mismatched` | `:1946` | +56 |
| §2.3 `:1913` `outcome` | `:1969` | +56 |
| §2.3 `:1950-1956` complete row | `:2006-2012` | +56 |
| §3.5 `:355` closed barrier | `:495` | +140 |
| §3.5 `:815` citation resolution | `:967` | +152 |
| §3.5 `:936` core row excluded | `:1101` | +165 |
| §3.5 `:1045` no holes | `:1213` | +168 |

§3.5 states "46 `require()` call sites plus three `AgentRunner` raises". At HEAD there are
**39** `require(` call sites (one definition excluded) and **ten** explicit raises. §10 case 18
is the exception: it cites `:1931` and `:1931` is correct, having been written after the
`read_manifest` insertion.

This is the restart record's own "line-bearing citations are unlintable and drift silently"
gotcha, realized. **Bite for 4a: none.** 4a lands no stage bodies and touches none of those
sites. **Bite for 4b through 4f: the site table they port against does not resolve.** Routed to
language-team as a citation repair on the proposal, not fixed here (the proposal is settled
language-team output and this plan does not edit it).

The reference's own docstring at `:377` carries the same stale `:866`.

### H. Incidental: an LLMLL binding named `show` passes `check` and fails at GHC

**Executed:** `(def-shell show [r: Response] -> string …)` gives
`OK` from `llmll check` and then four `Ambiguous occurrence 'show'` errors from GHC against
`Prelude.show`, from generated prelude code (`list_nth`, `bytes-get`) rather than from the
user's own call sites. Same class as the known reserved-name gotchas. Not 4a work; file it as
a name-capture row for `toHsIdent`.

## Plan summary

Land three new LLMLL modules and one invocation shim in `tools/llmll-driver/`, plus a
cover harness under `scripts/`. The decomposition is **by concern rather than by stage**,
because at 4a there are no stage bodies: a manifest module owning the JSON row schema and the
corrupt-shape guard, a registry module holding the sixteen-stage static table, and a sequencer
module holding §4's `Phase` sum, the step machine, the resume gate over `skip.may-skip`, and
the two halt channels over `stage.record-outcome`. The shim supplies the three things the
language does not have: configuration (a JSON file the program reads, since there is no argv),
a step budget (stdin lines, with a terminal-marker check so a starved run is not a silent
success), and a process exit status (mapped from the program's own decision line). The cover
harness drives the built binary through the eleven cells and the three manifest shapes, one
scenario per Python-side test, asserting the same decisions.

The cost is one build-gate stage, roughly seventy console steps on a full run, and a shim whose
existence must be disclosed because the exit status is not the program's.

## Affected surface

New files, listed inside a fence because they do not exist yet and the prose citation lint
resolves backticked paths that contain a slash:

```
tools/llmll-driver/manifest.llmll        row schema (§4 asymmetry) + corrupt-shape guard
tools/llmll-driver/registry.llmll        the sixteen-stage static table
tools/llmll-driver/sequencer.llmll       Phase sum, step machine, resume gate, halt channels
tools/llmll-driver/crux-skip-digest-dropped.llmll   §10 case 19's second mutant
tools/llmll-driver/crux-exit-code-halt-as-zero.llmll  Stopped mapped to exit 0
scripts/driver_ll_cover.py               the eleven-cell + three-shape cover
scripts/tests/test_driver_ll_4a_cover.py pytest wrapper, skips when the binary is absent
```

`run-4a.sh` appeared in this list and was NOT built: `PROC-BOUNDARY-1` retired
it. `crux-exit-code-halt-as-zero.llmll` was added in its place, freezing the
behaviour that capability closed.

Modified:

- [`tools/llmll-driver/EXPECTED_VERDICTS.json`](../../tools/llmll-driver/EXPECTED_VERDICTS.json):
  four new cases, three `safe` entries for the new modules under `--strict-verified-core`
  and one `refuted` entry for the new crux. The file's `note` gains one sentence naming the
  Phase 4a extension, on the pattern the v0.14.82 spine extension already set.
- [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh): one new stage after the existing
  execution stage, building the sequencer and running the cover. Campaign §3a requires the
  Phase 4 artifact to enter the build gate.
- `tools/llmll-driver/README.md` `:99`: one line under "what the driver does today". Per §12.

Unchanged, and stated because the reader will ask:

- `compiler/src/LLMLL/**`: **no compiler change.** §12:1102 holds. Findings A, B and C are
  absorbed by the shim; findings G and H are routed, not fixed.
- `docs/llmll-ast.schema.json`: no schema bump. No node shapes change.
- `docs/compiler-team-roadmap.md`, `docs/design/INDEX.md`, `LLMLL.md`, `CHANGELOG.md`,
  `README.md`: doc-lead's slot, not touched.
- [`docs/design/driver-ll-phase4-proposal.md`](driver-ll-phase4-proposal.md): settled
  language-team output, not edited. Finding G is routed to it as a request.

### Module contents

**manifest module.** `is-object?` (the `json-set` probe of finding E), `manifest-usable?`,
`complete-row`, `halt-row`, `outputs-map`, `status-word`, `outcome-word`. The row constructors
carry §4's asymmetry as their shape rather than as a runtime condition:
`complete-row` sets `status`, `kind`, `seconds`, `outputs` and **never** `outcome`; `halt-row`
sets `status`, `detail`, `outcome`, and `clause` only when the clause string is non-empty, and
**never** `kind` or `seconds`. Measured working: a `ConditionUnmet` halt serialized to
`{"status": "stopped", "detail": …, "outcome": "ConditionUnmet", "clause": …}` and a complete
row to `{"status": "complete", "kind": "agent", "seconds": 3, "outputs": {}}`, both through
`record-outcome`.

`outputs-map` reproduces the reference's filter at `:2010-2011`: only artifacts that exist get
a key. A missing artifact yields a **short map**, not a null, because α compares "key set and
digest values, equality" (§2.1).

**registry module.** `stage-count -> int` (16), and `stage-key`, `stage-kind`, `stage-name`,
`stage-outputs` as `if`-chains over an index. An `if`-chain rather than data read from a file,
on the same auditability ground `wasi.proc.run`'s argv split rests on
([`TypeCheck.hs:190-196`](../../compiler/src/LLMLL/TypeCheck.hs)): the table is then a
syntactic constant a reader enumerates from the source.

**sequencer module.** §4's encoding, concretely:

```
(type Phase
  (| Booting int)
  (| Probing (int, (int, (bool, bool))))   ;; stage, (artifact, (present, match))
  (| Deciding (int, (bool, bool)))
  (| Running int)
  (| Recording int)
  (| Halting (Outcome, (string, string)))  ;; outcome, (detail, clause)
  (| Reporting (Outcome, (string, string)))
  (| Ended))
```

paired with a run-common `(Json, (list[string], bool))` carrying the manifest, the selected
stage keys, and the forced flag. Measured working, including an imported `Outcome` riding in a
`Phase` payload cross-module (`XMOD-CTOR-1` at v0.14.82, §4).

`Halting` and `Reporting` are two arms and not one because of RC-4: `Halting` performs the
manifest write, `Reporting` performs the stdout report, and `done?` fires on `Reporting`'s
successor so `:on-done` renders the terminal marker. Collapsing them drops one of the two, and
which one it drops depends on ordering rather than on intent.

The resume gate is one `may-skip` call per stage over four bools the shell computed:
`manifest-complete` from the recorded `status` string, `artifacts-present` and `digests-match`
from the accumulated `Probing` pair, and `forced` from the config. Nothing about the decision
is re-implemented, per Phase 3's standing rule (`spine.llmll:12-16`).

**The fault injector, and why 4a needs one.** §9 says "no stage bodies" and also demands all
four `Outcome` arms. With no stage bodies there is no producer for `ConditionUnmet`, `Errored`
or `PartialThenHalt`; only `Finished` has one. 4a therefore needs a declared injector, which is
the port's counterpart to the rig's `STUB_MODE`: two config fields, `halt_at` naming a stage
key and `halt_kind` naming an `Outcome` constructor, consumed in the `Running` arm. It is
**4a-only scaffolding** and its retirement is scheduled: 4b retires `Errored` (a delegated
output that is absent or malformed), 4c through 4e retire `ConditionUnmet` at the gates, and 4f
retires `PartialThenHalt` at stage O's perturbation-omission check per §6.2. That schedule goes
in the module header, so a later reader sees an injector with an owner rather than a leftover.

**The shim.** Roughly twenty lines of shell. It writes a config JSON into the workdir, changes
directory into it so every path the program uses is workdir-relative and no workdir plumbing is
needed, feeds a fixed stdin budget, requires the terminal marker on stdout, and maps the
program's own final decision line to a process status: `0` complete, `2` stopped or an
out-of-stage halt, `3` failed, matching `:1972`, `:1988`, `:2005`, `:2016` and `:2032`.

The `only` selection travels as a **comma-separated string**, not a JSON array, because
`json-get-string` takes an object and a key and there is no projection from a bare JSON string
inside an array; `string-split ","` recovers the list. The spine's own idiom confirms the
limit: `cid-strings` (`spine.llmll:570-571`) extracts strings from array elements only because
those elements are objects.

## Verification impact

- **Solver-time delta: zero on the activated cores.** `skip.llmll` and `stage.llmll` are
  unchanged and their `.verified.json` sidecars are unchanged. 4a adds callers, not clauses.
- **New obligations: zero in the strict core.** All three new modules are `def-shell` end to
  end. This is the campaign's own rule (`spine.llmll:18-24`): everything touching JSON, the
  filesystem or a subprocess is `def-shell` and unverified, and the decision is a `def` over
  scalars the shell extracted. §11's row for the orchestration says the same, and the phase
  close must keep the distinction that the cores gain callers while the orchestration gains no
  proof (§11:1061-1065).
- **Verification fragment: unchanged.** Nothing escapes QF-LIA because nothing new enters
  Σ_auto. `may-skip` is four bools; `record-outcome` is a four-arm nullary enum, which
  `LLMLL.md §5.3.5` keeps in pure QF-LIA via the int-tag discriminant.
- **Strict-verified-core impact: none.** No existing `def` newly falls back. Note the standing
  reason no new `def` should be written to compare digest strings: a `def` whose body performs a
  string-literal comparison falls back to contract-checked whatever its contract says
  (`STRLIT-BODY-1`, stated at `spine.llmll:76-83`). `digests-match` is therefore computed
  shell-side and handed in as a bool, which is the same shape stage E's four lexeme comparisons
  already have.
- **Trust closure.** The three new modules import `stage` and `skip`, whose contracts are
  proved and whose sidecars sit in the same directory. A module built outside that directory
  raises `Function record-outcome has an unproven contract (level: asserted)`, measured during
  this plan's probes: the sidecar is resolved relative to the source, so the new modules must
  live beside `stage.llmll`, not in a subdirectory.

### §7's two 4a statements

Both are owed at 4a and both are written into the sequencer module's header, in the form
`spine.llmll:71-80` set for stage E.

**`skip.may-skip`.** Three shell-side decisions, one more than Rev 6 named:

1. A recorded digest of `None` is treated as a mismatch, mirroring the reference at `:1941`.
2. An unknown `status` string parses to `manifest-complete = false`, conformant with
   §5:189-191 but a shell reading of a spec sentence rather than a proved mapping.
3. **New, from finding D.** `artifacts-present` and `digests-match` are both derived from one
   `wasi.fs.sha256` per declared artifact. Every `RErr` is read as "absent", so an unreadable
   but present artifact is indistinguishable from a missing one at the proved boundary. The
   collapse is conservative: it can only force a re-run, never permit a skip, so it cannot
   violate `[S5-SKIP]`. It can violate no clause and can still be wrong, which is why it is
   disclosed rather than argued away.

**`stage.record-outcome`.** The `Outcome` constructor is chosen by the shell from §3.1's
four-way disposition and, at 4a, from the injector's `halt_kind` field. Unproved, and it is the
discrimination the Python driver lost. At 4a the injector makes the choice **fully enumerable**:
four constructors, one config field, no site table. That is narrower than the disclosure 4b
onward will owe, and the header says so, so the gap inventory does not read as if 4a had closed
something it deferred.

## Performance budget

- **GHC build delta: zero.** No compiler module is touched, so there is no recompilation
  fan-out and `stack build` is unchanged.
- **`stack test` delta: zero.** 1616 examples, unchanged. 4a adds no Haskell.
- **`python -m pytest scripts/tests/` delta: +1 test, under one second.** The pytest wrapper
  skips when the binary is absent, on the `self_test()` skip precedent the roadmap's v0.14.79
  entry records. The cover itself runs in the build gate.
- **`build_smoke.sh` delta: one `llmll build` plus fourteen binary invocations.** The build
  dominates. Against the existing execution stage's single fixture build this roughly doubles
  that stage; the fourteen runs are milliseconds each because 4a has no stage bodies.
- **Console step budget, measured from the registry:** 16 stages, 19 declared outputs, at most
  2 on any stage. Worst case is 3 boot steps + 19 digest probes + 16 decisions + 16 stub bodies
  + 16 manifest writes + 1 terminal = **71 steps**. A full-skip resume is 39. Budget **128**
  stdin lines, with the terminal-marker check of finding C as the guard against under-budgeting.
- **ProofCache and VerifiedCache: unaffected.** No `.fq` file changes.

## Test plan

Acceptance is §9's cell, and each clause is measured rather than described.

| Acceptance clause | How it is measured | Where |
|---|---|---|
| Eleven-cell cover passes, T7 included | Fourteen scenarios against the built binary, one per Python-side test, asserting the manifest decision and the stage-ran / stage-skipped log line. Names mirror the Python tests so the correspondence is checkable by `diff` of the two name lists | cover harness |
| §10 cases 16, 17, 18 handled as decisions | Three scenarios writing the three corrupt shapes; assert shim exit 2, the reason substring, and that no stage ran | cover harness |
| §4's manifest-row asymmetry reproduced | Assert `"outcome" not in complete_row` and `"kind" not in halt_row and "seconds" not in halt_row`, over a run producing both | cover harness |
| §7's two 4a statements written | Assert the sequencer header contains both `:source`-style disclosure blocks, by a text check, so a header rewrite that drops one goes red | pytest wrapper |
| Both proved cores acquire a caller | `llmll verify` the sequencer under `--strict-verified-core` and assert `safe`; the crux gate freezes the verdict | `EXPECTED_VERDICTS.json` |

**Cell-by-cell mapping.** Each row names the Python test whose decision the LLMLL scenario must
reproduce.

| Cell | Python-side test | LLMLL-side setup |
|---|---|---|
| T1 → complete | `test_pipeline_runs_through_both_gates` | clean workdir, no injector |
| T2 → stopped pre-write | `test_a_spec_defined_halt_records_stopped_and_names_its_clause` | `halt_kind=ConditionUnmet` |
| T3 → failed | `test_a_delegated_output_defect_records_failed_not_stopped` | `halt_kind=Errored` |
| T4 → stopped post-write | `test_stage_H_records_partial_then_halt_after_writing_its_output` | `halt_kind=PartialThenHalt` |
| T5 skip | `test_a_completed_stage_is_still_skipped_on_resume` | resume, intact |
| T6 digest mismatch | `test_a_modified_artifact_forces_a_rerun` | resume, edit an artifact |
| **T7 artifact absent** | `test_a_declared_artifact_deleted_from_a_complete_stage_forces_a_rerun` | resume, delete one declared artifact |
| T8 no record | `test_artifacts_without_a_completion_record_force_a_rerun` | resume, delete one manifest row |
| T9 stopped → run | `test_a_failed_gate_is_not_bypassed_by_its_own_output_on_resume` | resume after a `ConditionUnmet` halt |
| T10 failed → run | `test_a_failed_stage_is_re_run_on_resume` | resume after an `Errored` halt |
| T11 force | `test_force_re_runs_a_stage_the_manifest_records_complete` | resume with `force=true` |

T7 asserts the decision, not the silence, per §10 case 15's withdrawal of the Rev 5
instruction: the port is free to print a reason line and the test must not pin its absence.

**Refute-crux additions.** §10 case 19's first mutant already ships as
`crux-skip-presence-only.llmll`, which drops the presence conjunct. The second is missing and is
the discriminating one: a body of `(and (not forced) (and manifest-complete artifacts-present))`
drops the digest conjunct, `[S5-SKIP]` refutes and `[S5-PRESENCE]` does not. Adding it makes
the entailment §11 records observable in the gate rather than only argued, which is what
`CLAUSE-INDEP-1` is filed against.

**Test-count target.** 1616 Haskell → **1616** (no Haskell added). 120 Python → **121**. The
fourteen cover scenarios are not pytest cases; they run in the build gate, where the toolchain
exists.

## Rollback

Single revert, cleanly. Every artifact is new except three edits: four appended cases in
`EXPECTED_VERDICTS.json`, one appended stage in `build_smoke.sh`, one line in the driver's
README. No schema version is pinned, no `.verified.json` is regenerated, no `.fq` file changes,
so no user environment carries a stale cache of anything this touches. Worst-case unwind is
deleting seven files and reverting three hunks.

The shim is the one thing that should not be reverted piecemeal: reverting the sequencer while
leaving the build-gate stage leaves the gate building a file that is gone, which fails closed
and is the correct direction.

## Risks and unknowns

1. **The exit status is the shim's, not the program's.** Scope, claim discipline. Finding B.
   Clause 1a's observable is the manifest (§2.1), so this does not touch the refinement claim;
   clause 1b's §4:139-143 output obligation is discharged by the program printing the reason,
   which it does. What the shim supplies is only the status byte. **Bite: complicates.** The
   mitigation is disclosure in the phase gap inventory plus `PROC-EXIT-1`, and the failure mode
   if it is not disclosed is a conformance claim resting on twenty lines of shell nobody read.

2. **The fault injector is scaffolding inside the acceptance criterion.** Scope. §9 demands all
   four `Outcome` arms with no stage bodies, and three of the four have no other producer at
   4a. **Bite: complicates.** The mitigation is the retirement schedule above, written into the
   module header rather than into this plan, since the header is what a later reader opens.

3. **A starved step budget reports green.** Verification of the harness itself. Finding C.
   **Bite: blocks, if unmitigated.** The terminal-marker check is the whole mitigation and it
   must be in the shim before the first cover run, or the cover's own greens are uninterpretable.

4. **The proposal's site table does not resolve at HEAD.** Spec drift. Finding G. **Bite: none
   for 4a, blocks 4b's mechanical framing.** Routed to language-team.

5. **The cover is a mirror, not the rig.** Verification ergonomics. Findings A and B mean the
   port cannot be substituted into `rig()`, so the two covers are two programs asserting the
   same decisions rather than one program run twice. A divergence between the mirrors is
   possible and invisible. **Bite: complicates.** The mitigation is the name correspondence: the
   two test-name lists must match, and a check that they do is cheaper than any structural
   sharing, which would need the argv gap closed first.

6. **The state encoding is the phase's silent-failure surface**, carried forward from §13 risk
   6 and reduced but not removed by the sum. A wrong projection over `(int, (int, (bool,
   bool)))` typechecks. **Bite: complicates.** Per-component accessors written once and reviewed
   once, and never a bare `first (second (first s))` at a use site.

7. **`seconds` cannot be a float.** Spec drift, minor. `json-of-int` is the only numeric
   injection ([`TypeCheck.hs:333`](../../compiler/src/LLMLL/TypeCheck.hs)) and the reference
   writes `round(…, 1)`. α discards `seconds` (§2.1), so clause 1a is unaffected and the port
   emits an integer. **Bite: only matters if α is ever revised** to retain the field.

8. **Two `wasi.clock.monotonic` readings per stage would cost 32 steps** to produce `seconds` at
   all. Performance. Since α discards the field, the alternative of omitting it entirely is
   available and cheaper. **Recommendation: emit it**, at 32 extra steps inside a 128-line
   budget, because a row schema that differs from the reference's in a field α happens to
   discard is a difference someone will have to re-derive later. **Bite: only matters at scale**,
   and there is no scale here.

## Open questions for the professor

1. ~~**Does the shim's exit-status mapping fall inside clause 1b or outside it?**~~
   **MOOT.** There is no shim. The status byte is the program's own, produced by
   a `:status` projection over the state, so nothing unverified mediates it. What
   survives is narrower and is question 3 below.

2. **Is finding E's `is-object?` construction admissible as a total predicate, given that it is
   built from a partial operation's success?** `json-set` is `Json -> string -> Json -> Result`,
   and the port reads `Success` as "the argument was an object". Measured true over all seven
   JSON shapes, but it is a claim about the builtin's error discipline rather than about its
   type, and it is the predicate the whole corrupt-manifest guard rests on.

3. **Where does the exit-status obligation sit, now that its range post is
   contract-checked rather than proved?** `PROC-BOUNDARY-1` §5 places
   `0 <= status <= 255` in the contract channel, "QF-LIA, auto-discharged". For
   any `:status` over a product state it is not discharged, `first` sending the
   body to fallback; the port makes it true by clamping instead. Is a clamped
   projection over an unproved component the right discharge for a §15.1 tier
   statement, or does the obligation belong on `exit-code`, where it IS proved,
   with the projection disclosed as asserted? The two readings assign the same
   behaviour and different tiers, and §15.1:504-505 requires every obligation to
   sit in exactly one.
