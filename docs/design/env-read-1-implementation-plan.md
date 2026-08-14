---
name: env-read-1-implementation-plan
title: "ENV-READ-1: implementation plan for wasi.env.get"
status: "IMPLEMENTED on branch `env-read-1/wasi-env-get`, NOT COMMITTED, awaiting review. `stack test` 1688 to **1707 examples, 0 failures** (+19: 18 new `ER-*` assertions plus one from the WASI-RT per-name fold; the plan estimated 21 and the estimate was two high). `pytest scripts/tests/` 179 passed / 6 skipped, unchanged. `stack build` clean, no new warnings. All three side conditions were exercised against the built compiler and all three fire, each with its sibling that does not. The runtime was measured on a built console program: a set variable answers `RText`, a SET AND EMPTY variable answers `RText \"\"`, an unset one answers `RErr`, and a computed name containing `=` answers `RErr` indistinguishably from unset, which is the documented limit measured rather than asserted. ONE GATE FAILS AND IT IS THE RELEASE CEREMONY, NOT THE CODE: `compiler/package.yaml` and `compiler/llmll.cabal` moved to 0.15.0 while `LLMLL.md`, `README.md` and `CHANGELOG.md` still read v0.14.99, and those three are documentation-lead's. Measured both ways: with the version reverted the whole of `build_smoke.sh` passes including 14 of 14 DRIFT-CI-1 cover cells; with it bumped, C1 fails and three cover cells go vacuous because `version_gate_cover.py:80` derives its mutation pattern from the LLMLL.md banner. Written against `env-channel-proposal.md` Rev 2 (settled) at compiler v0.14.99, tag `v0.14.99`, 7 unreleased commits. THE PLAN SHIPS ALL THREE SETTLED SIDE CONDITIONS, AND ONE OF THE THREE RESTS ON A MECHANISM THAT DOES NOT EXIST YET. Measured: `capDeterministic` has exactly ONE consumer in the source tree (`AstEmit.hs:443`, which serialises it to JSON), the emitted event log's `captures` array is the LITERAL STRING `[]` in `CodegenHs.hs:1607`, `Replay.hs` never reads captures, and `ReplayStatus` has zero consumers outside `Syntax.hs`. A witness program was BUILT AND RUN with `:deterministic true` on a clock import: the log records `\"captures\":[]` on every event. So `LLMLL.md:1816` describes an unbuilt mechanism, the `:deterministic true` refusal is a FORWARD guard rather than a stop to a live leak, and the proposal's section 4 case 2 consequence clause is false at v0.14.99 while its type-error witness stays constructible. The effect label is the second delta: the proposal asks for a SEVENTH label `env.read`, and `ObligationAssembly.hs:392-398` predicts the opposite in a comment and says the catalog stays six-wide, pinned by three assertions. The plan ships the seventh label and corrects the comment in the same patch. Two smaller measurements: `checkStatement (SImport imp)` reads NO capability today, so the refusal is new machinery, and `build_smoke.sh:196` omits `wasi_fs_copy`, a name `smoke.llmll:78` calls, so that guard is already weaker than its comment claims."
date: 2026-08-14
author: compiler-engineer
consumers: [user, language-team, professor, documentation-lead]
---

# ENV-READ-1: implementation plan for `wasi.env.get`

## Restatement

Add one WASI builtin, `wasi.env.get : string -> Command`, in a new `wasi.env`
namespace. Add three fail-closed type-level side conditions. Add one effect
label. Ship no proof obligation and no schema change.

## Context located

1. [`docs/design/env-channel-proposal.md`](env-channel-proposal.md) Rev 2, the
   settled spec. Read in full.
2. [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs)`:158-241`.
   The 14 `wasi.*` entries in `builtinEnv`, and the insertion point.
3. `TypeCheck.hs:1878-1895`. `extractWasiNamespace` takes two segments.
   `checkWasiCapability` compares `importPath imp` to that namespace.
4. `TypeCheck.hs:1692-1697`. `checkStatement (SImport imp)` reads
   `importInterface` ONLY. It never reads `importCapability`.
5. `TypeCheck.hs:2068-2076`. `inferExpr (EApp func args)` calls
   `checkWasiCapability` for every `wasi.` name. This is the side-condition site.
6. [`compiler/src/LLMLL/ObligationAssembly.hs`](../../compiler/src/LLMLL/ObligationAssembly.hs)`:390-511`.
   `EffectLabel` is six-wide. `primEffect` maps names to labels. The `wasi.`
   fallthrough at `:509` returns the lattice top.
7. [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs)`:601-671`.
   The unary preamble body shape, and the `wasi_clock_monotonic` sibling.
8. `CodegenHs.hs:167-212`. The emitted `Lib.hs` import list. `:207` carries
   `import System.Environment (getArgs)`.
9. `CodegenHs.hs:1597-1610`. `emitEventLogPreamble`. The `captures` array is a
   literal `[]`.
10. [`compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs)`:868-911`.
    `capDeterministic` and `ReplayStatus`.
11. [`compiler/src/LLMLL/Diagnostic.hs`](../../compiler/src/LLMLL/Diagnostic.hs)`:312-323`.
    `mkMissingCapability`, the model for a structured capability diagnostic.
12. [`compiler/test/Spec.hs`](../../compiler/test/Spec.hs)`:15065-15093`. The
    WASI-RT fold. It asserts the name count and generates one example per name.
13. `Spec.hs:14746`, `:15451`, `:15528`. Three assertions pin the catalog at six.
14. [`scripts/build-smoke/smoke.llmll`](../../scripts/build-smoke/smoke.llmll)`:10`.
    The fixture's stated contract calls every name that has a preamble body.
15. [`scripts/build_smoke.sh`](../../scripts/build_smoke.sh)`:196-205`. The
    emitted-preamble name list.
16. [`docs/design/proc-boundary-1-implementation-plan.md`](proc-boundary-1-implementation-plan.md).
    The convention this document follows.

No `[CT]` roadmap row for `ENV-READ-1` exists yet. The absence is information:
`documentation-lead` owes the row.

## Measured findings, and two of them change the plan

### F1. The capture mechanism does not exist at v0.14.99

The proposal's whole section 3 rests on this sentence in `LLMLL.md:1816`: "When
`:deterministic true` is set, the runtime captures the return value of every
call and appends it to the Event Log."

**The compiler does not do that.** Four static measurements agree.

| Measurement | Result |
|---|---|
| `grep -rn capDeterministic compiler/src/ compiler/test/` | Two hits. `Syntax.hs:874` defines it. `AstEmit.hs:443` serialises it to JSON. No third consumer. |
| `CodegenHs.hs:1602-1607`, `eventJsonL` | The `captures` array is the literal string `[]`. The function takes five parameters and none is a capture. |
| `grep -n captures Replay.hs` | No hit. Replay never reads a capture. |
| `grep -rn "Replayable\|BestEffortReplay\|ReplayStatus" compiler/src/` | No hit outside `Syntax.hs`. |

**A static argument is not a witness, so the witness was built and run.** The
program below type-checks, builds, and runs. It sets `:deterministic true` on a
clock import and issues the clock command on every step.

```lisp
(import wasi.io    (capability stdout :deterministic false))
(import wasi.clock (capability monotonic-read :deterministic true))
(def-shell tick [state: string input: string _r: Response]
  (pair state (seq-commands wasi.clock.monotonic (wasi.io.stdout input))))
(def-main :mode console :step tick)
```

Its event log, for two input lines:

```
{"type":"header","version":"0.3.1","module":"detcap"}
{"type":"event","seq":0,"input":{"kind":"stdin","value":"alpha"},"result":{"kind":"stdout","value":"alpha"},"captures":[]}
{"type":"event","seq":1,"input":{"kind":"stdin","value":"beta"},"result":{"kind":"stdout","value":"beta"},"captures":[]}
```

**Three consequences, and none of them stops the rule shipping.**

1. **Ship the refusal.** It is fail-closed, it costs about ten lines, and it is
   correct on the day the capture lands. A guard written after the mechanism is
   a guard written after the leak.
2. **The diagnostic must not claim a live leak.** A message that says the flag
   writes a secret to disk today is false today. The plan's wording in section
   "Diagnostics" below states the forward condition instead.
3. **The proposal's section 4 case 2 has a false consequence clause.** It reads
   "Without the refusal this module compiles, and it writes the secret to
   `leak.event-log.jsonl`." The module does compile. It writes no such thing.
   **The witness the gate needs survives**, because the gate asserts the type
   error and not the file: the module is illegal with the flag and legal without
   it, and the two cases differ by exactly the flag.

Routed to `language-team` and `documentation-lead`. `LLMLL.md` section 10a owed
an amendment already. That amendment is now larger than the proposal states: the
enumeration needs its scope, AND `:1816` describes an unbuilt mechanism.

### F2. The proposal asks for a seventh effect label, and the code predicts a sixth

`ObligationAssembly.hs:392-398` says the `ENonDet` class covers "a PRNG, a
clock, and later a PID or an environment read", and that the catalog "stays
SIX-wide". Three assertions pin the width. `Spec.hs:11046` encodes the full
label set into expected JSON.

The proposal says `env.read`, beside the six. **The plan ships the seventh
label** and corrects the comment in the same patch. Three reasons.

1. **The spec is settled and the label is not on the do-not-reopen list.**
2. **Soundness is not at stake.** `ObligationAssembly.hs:385-387` records that
   the summary is informational, and that it never feeds the trust meet, the
   `EvidenceRecord`, or verified admissibility.
3. **A merged label erases the distinction the proposal exists to serve.** A
   report that says `nondet` cannot separate a clock read from a credential read.

**One point of care, because it looks like a departure and is not.** The
catalog's stated principle is operation occurrence, and `:433-441` and `:455-458`
both record that the catalog cannot express a property of a returned value.
`env.read` denotes an OPERATION, exactly as `fs.read` does. Only the MOTIVE for
naming it separately comes from the value. So the principle holds.

A comment that predicts the opposite of what the code does is drift. Correcting
it is part of this patch, not a later tidy.

### F3. The import check is new machinery

`checkStatement (SImport imp)` at `TypeCheck.hs:1692-1697` reads
`importInterface` and nothing else. The `:deterministic` refusal is the first
check in the compiler to read `importCapability`. Budget it as new code, not as
one more clause on an existing check.

### F4. The smoke guard already misses a name

`build_smoke.sh:196-205` lists the preamble names it requires. `wasi_fs_copy` is
absent. `smoke.llmll:78` calls `wasi.fs.copy`. So the guard does not cover a name
the fixture calls, and its comment at `:189` claims it does. One word fixes it,
and the plan fixes it beside the `wasi_env_get` addition.

## Plan summary

Add one `builtinEnv` entry, one `primEffect` clause, one `EffectLabel`
constructor, one codegen preamble body, one emitted import, two structured
diagnostics, and three side conditions. Two side conditions sit at the
application site in `inferExpr`, where a literal argument is visible. The third
sits at the import statement. Nothing enters the refinement logic, so no
constraint is emitted and no solver time moves. The catalog widens from six to
seven, which rewrites four existing assertions and changes one expected JSON
string. The end-to-end gate gains an environment read in `smoke.llmll` and a
matching runtime assertion, because that fixture's stated contract calls every
name that has a preamble body.

## Affected surface

**`compiler/src/LLMLL/TypeCheck.hs`**

- `:230` area, `builtinEnv`. One entry,
  `("wasi.env.get", TFn [TString] (TCustom "Command"))`. Unary, so it binds as a
  function and always appears as an `EApp`. `checkWasiCapability` therefore
  reaches it, and `CAP-NULLARY-1` does not apply.
- `:1692`, `checkStatement (SImport imp)`. New clause. It reads `importPath` and
  `importCapability`. It refuses `capDeterministic == True` when the path is
  `wasi.env`.
- `:2072` area, `inferExpr (EApp func args)`. New clause, placed directly after
  the `checkWasiCapability` call. It fires only for `func == "wasi.env.get"` with
  a single `ELit (LitString s)` argument. It refuses `T.null s`. It refuses
  `"=" \`T.isInfixOf\` s`.

**`compiler/src/LLMLL/ObligationAssembly.hs`**

- `:399`, `EffectLabel`. One constructor, `EEnvRead`.
- `:408` area, `effectLabelText`. One line, `EEnvRead -> "env.read"`.
- `:482` area, `primEffect`. One clause,
  `| n == "wasi.env.get" = one EEnvRead`. **It must sit ABOVE the `wasi.`
  fallthrough at `:509`.** Below it the name reports the lattice top, and every
  transitive caller's `effect_summary` goes vacuous. `PROC-BOUNDARY-1` records
  the same trap.
- `:392-398`, the catalog comment. Correct the prediction and the width.

**`compiler/src/LLMLL/CodegenHs.hs`**

- `:207`. `import System.Environment (getArgs)` becomes
  `(getArgs, lookupEnv)`. `:1721` is the emitted `Main.hs` import and does NOT
  change; the preamble lives in `Lib.hs`.
- `:660` area, `runtimePreamble`. One body, next to `wasi_clock_monotonic`.

**`compiler/src/LLMLL/Diagnostic.hs`** (a delta from the proposal's section 7,
which does not name this file)

- Two constructors on the `mkMissingCapability` model at `:312-323`.
  `mkEnvDeterministicRefused` carries `diagKind "env-deterministic-refused"`.
  `mkEnvNameMalformed` carries `diagKind "env-name-malformed"`.

**`compiler/test/Spec.hs`**

- New `describe` block beside the CAP-PROC and WASI-RT blocks.
- `:15082` area. The WASI-RT count assertion moves 14 to 15.
- `:14746`, `:15451`, `:15528`. Three width assertions move 6 to 7.
- `:11046`. The expected JSON for the full label set gains `env.read`.

**`scripts/build-smoke/smoke.llmll`** and **`scripts/build_smoke.sh`**

- One import, one `def-shell`, one call. One name added to the list at `:196`,
  and `wasi_fs_copy` added beside it (F4).

**Not touched.** `docs/llmll-ast.schema.json`, and no schema version change. A
builtin is an `EApp` with a name, and it adds no node shape. `Replay.hs` needs no
entry: `runReplay` at `:236` spawns the built executable and feeds inputs, and it
has no per-builtin dispatch.

**Doc-lead's, not touched here.** `LLMLL.md` sections 13 and 10a,
[`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md), `CHANGELOG.md`,
`README.md`, [`docs/design/INDEX.md`](INDEX.md).

## Diagnostics

The refusal message must be true on the day it ships. F1 measured that the
capture does not run yet, so the message states the rule and the reason, and it
names the deferred redaction work. Draft text, illustrative:

```
error: :deterministic true is refused on a wasi.env import
  The event log records a command's return value for a deterministic
  capability (LLMLL.md 10a). The environment carries credentials by
  convention, so a capture of an environment read would write a secret to
  <module>.event-log.jsonl in plaintext.
  This is refused rather than defaulted: a default that fails open writes a
  secret whenever a clock import is copied.
  Redaction is a separate proposal. Use :deterministic false, or omit the flag.
```

The malformed-name message names which rule fired and states the reason:

```
error: a literal environment variable name cannot contain "="
  An unset name, a name containing "=", and the empty name all answer RErr,
  so this call can never succeed and its failure is indistinguishable from
  an unset variable.
```

## The codegen body

Illustrative, not implementation:

```haskell
wasi_env_get :: String -> IO ()
wasi_env_get name = llmll_publish_io $ do
  mv <- lookupEnv name
  case mv of
    Nothing -> return (RErr ("wasi.env.get: " ++ name ++ " is not set"))
    Just v  -> do
      _ <- evaluate (length v)
      return (RText v)
```

`lookupEnv` distinguishes unset from set-and-empty, which is the whole point of
the `RErr` shape. `evaluate` forces inside `llmll_publish_io`, on the
`wasi_fs_list` and `wasi_proc_args` rule: a failure must arrive as a value and
not as a thunk the program forces later.

**One wording decision.** The `RErr` payload names the variable. For a literal
name that reveals nothing, because the name is already in the source. For a
computed name it puts the computed name in an error string. The alternative
loses the only diagnostic a caller gets. The plan keeps the name and records the
trade here.

## Verification impact

- **Solver time delta: zero.** No constraint is emitted. A `Command` result is
  not a value in the refinement logic.
- **New obligations: zero.** All three side conditions are type decisions.
- **Fragment: unchanged.** The change stays outside QF-LIA rather than inside it.
  Nothing escapes to nonlinear arithmetic and nothing escapes to Lean. See
  `LLMLL.md` sections 5.3.3 and 5.3.5.
- **Trust model.** Every caller takes the `asserted` tier, as for every other
  `wasi.*` builtin. No weakness suppression changes.
- **Strict-verified-core: no function newly falls back.** A `def` cannot call a
  `wasi.*` name and stay body-faithful today, so the population that could
  regress is empty.
- **`effect_summary` output changes.** A function that reads the environment
  reports `env.read` instead of the lattice top. That is a strict improvement:
  before this patch the name would hit the `wasi.` fallthrough and report top.

## Performance budget

- **GHC rebuild fan-out.** `Syntax.hs` is NOT touched, which is what keeps the
  fan-out small. `ObligationAssembly.hs`, `TypeCheck.hs`, `CodegenHs.hs` and
  `Diagnostic.hs` recompile, plus their dependents. Estimate 3 to 6 minutes on a
  cold `stack build`, in line with `PROC-BOUNDARY-1`.
- **Test-suite runtime.** Baseline 12.24 seconds for 1688 examples. About 21 new
  examples, all pure. Estimate under 0.2 seconds added.
- **Compiler runtime on `llmll check`.** Two new string tests per `wasi.env.get`
  call site, and one per import statement. Unmeasurable against parse time.
- **`llmll verify`: no change.** No constraint is emitted.
- **ProofCache and VerifiedCache hit rate: no change.** No `.fq` content moves.
- **Binary size:** one preamble string. Negligible.

## Contract plan

**This change lands nothing in the provable fragment, and that is the
deliverable rather than an omission.** `wasi.env.get` returns a `Command`, which
is not a value in the refinement logic, so no `pre` or `post` clause can speak
about it. No new `def` is written. The three side conditions are decisions in the
type checker, so they have no contract, and their discriminating power is
demonstrated by the witness pairs in the test plan rather than by a refuting
body. The module-placement rule does not apply, because no `def` is added.

## Test plan

Baseline measured on this tree: **`stack test` 1688 examples, 0 failures**;
**`python3 -m pytest scripts/tests/ -q` 179 passed, 6 skipped**.

New `ER-*` assertions in `compiler/test/Spec.hs`. Each side condition gets a
firing witness AND a sibling that does not fire, because a gate that cannot fail
grades nothing.

**Surface, 4 assertions.** `builtinEnv` types the name as
`TFn [TString] (TCustom "Command")`; `extractWasiNamespace "wasi.env.get"` is
`"wasi.env"`; a call with no `wasi.env` import reports `missing-capability`; a
call with the import type-checks clean.

**The capture refusal, 5 assertions, written as contrasts.** The proposal's
section 4 case 2 module is illegal. **The same module with the flag deleted is
legal**, so the two differ by exactly the flag. `:deterministic true` on a
`wasi.clock` import stays legal, which pins the refusal to one namespace.
`:deterministic false` on `wasi.env` is legal. The diagnostic carries
`diagKind "env-deterministic-refused"` and names the deferred redaction rule.

**The literal side conditions, 4 assertions.** `(wasi.env.get "A=B")` is an
error. `(wasi.env.get "")` is an error. `(wasi.env.get "HOME")` is clean.
`(wasi.env.get (string-concat k "=v"))` is NOT an error, which pins the stated
limit: a literal rule cannot reach a computed argument.

**The effect label, 4 assertions.** `primEffect "wasi.env.get"` is
`Just (Caps {EEnvRead})`. It is NOT `Just Unbounded`, which pins the clause above
the `wasi.` fallthrough. `effectLabelText EEnvRead` is `"env.read"`. A caller's
`effect_summary` carries `env.read` transitively.

**Codegen, 4 assertions.** The preamble defines `wasi_env_get`. The emitted
import list carries `lookupEnv`. The body publishes through `llmll_publish_io`.
The unset path returns `RErr` and NOT `RText ""`, which is the `JSON-SCALAR-1`
defect the shape exists to avoid.

**Rewritten in place, so they add no examples.** The WASI-RT count assertion 14
to 15. Three width assertions 6 to 7. One expected JSON string at `:11046`.

**Generated, so it adds exactly one example.** The WASI-RT per-name fold grows by
one when a name lands.

**Test-count target: at least 1709 examples, 0 failures.** Measure the exact
figure at implementation. Do not assume it.

**Measured after implementation: 1707 examples, 0 failures.** The target was two
high. 18 `ER-*` assertions landed, not the 20 the list above implies, because two
planned assertions merged into one: `ER-12` pins the positive and the negative of
the `primEffect` clause in a single example, and the namespace derivation is
tested through `ER-2` and `ER-3` rather than as a unit, `extractWasiNamespace`
not being exported. The WASI-RT fold added the nineteenth.

**End-to-end**, `scripts/build_smoke.sh`. The fixture reads a variable the
harness sets, and the stage asserts the value round-trips. The stage also reads
an unset name and asserts the `RErr` arm, because the positive assertion alone
passes for a body that returns the empty string on absence.

**Gates, each on its own line.** Piping into `tail` takes `tail`'s exit status.

```
stack build
stack test
bash scripts/build_smoke.sh
python3 -m pytest scripts/tests/ -q
bash scripts/version_gate.sh
```

DRIFT-DOC-4 is `tools/doc-path-lint/pathlint.llmll` and must be built before it
runs. **It reads `git ls-files`, so it cannot see an untracked file.** A pass on
a file it never scanned grades nothing.

## Measured at implementation

### The runtime, on a built program

A console program reads the variable named on stdin and prints the arm it got.
Built and run, four cases:

| Input | Response | Printed |
|---|---|---|
| `ENVPROBE=hello` | `RText "hello"` | `text=[hello]` |
| `ENVPROBE=` (set and EMPTY) | `RText ""` | `text=[]` |
| a name that is not set | `RErr` | `err` |
| the name `A=B`, computed | `RErr` | `err` |

Row 2 is why the unset arm is `RErr`. A variable that is set and empty stays
distinguishable from one that is unset. Row 4 is the documented limit, measured
rather than asserted.

### The type rules, on the built compiler

Eight modules were checked. Each refusal has a sibling that differs by exactly
one thing and is accepted.

| Module | Result |
|---|---|
| import plus a literal read | accepted |
| `:deterministic true` on `wasi.env` | **refused** |
| the same module with the flag deleted | accepted |
| `:deterministic true` on `wasi.clock` | accepted |
| `(wasi.env.get "A=B")` | **refused** |
| `(wasi.env.get "")` | **refused** |
| `(wasi.env.get (string-concat k "=v"))` | accepted |
| a read with no capability import | **refused**, `missing-capability` |

Row 4 pins the refusal to one namespace. Row 7 pins the stated limit. Row 8
confirms `extractWasiNamespace` derives `wasi.env` with no change to it.

### Gates

| Gate | Before | After |
|---|---|---|
| `stack build` | clean | clean, no new warnings |
| `stack test` | 1688 examples, 0 failures | **1707 examples, 0 failures** |
| `python3 -m pytest scripts/tests/ -q` | 179 passed, 6 skipped | 179 passed, 6 skipped |
| `bash scripts/build_smoke.sh` | PASS | PASS at 0.14.99; **FAILS at 0.15.0** |
| `bash scripts/version_gate.sh` | PASS | PASS at 0.14.99; **FAILS at 0.15.0** |
| DRIFT-DOC-4 | 1001 citations / 174 files | 1024 citations / 175 files, all resolve |

**The two failures are the release ceremony and not the code.** This branch moved
`compiler/package.yaml` and `compiler/llmll.cabal` to 0.15.0. `LLMLL.md`,
`README.md` and `CHANGELOG.md` still read v0.14.99 and are documentation-lead's.
C1 compares the five, so it fails until all five move together.

**Measured both ways, because a failing gate must be attributed and not
excused.** With the two version lines reverted, `build_smoke.sh` passes in full,
including 14 of 14 DRIFT-CI-1 cover cells. With them bumped, C1 fails and three
cover cells report that they now test nothing: `version_gate_cover.py:80` derives
its mutation pattern from the LLMLL.md banner, so a compiler version ahead of the
banner makes those cells vacuous. That is a transient state of a half-finished
release and it closes when the banners move.

### One finding fixed in passing

`build_smoke.sh` required a hand-maintained list of preamble names.
`wasi_fs_copy` was absent from it and `smoke.llmll` has called `wasi.fs.copy`
since FS-COPY-1, so the guard did not cover a name the fixture calls. Both
`wasi_env_get` and `wasi_fs_copy` are in the list now. The list is
hand-maintained and will drift again; Spec.hs's WASI-RT fold derives its names
from `builtinEnv` and cannot.

## Rollback

Single revert. No schema version moved, so no document written by a new emitter
can reach an old reader. No `.verified.json` migration, because no evidence
record changed. No `.fq` migration, because no constraint was emitted. A cached
`.fq` from before the patch stays valid.

**One thing a revert does not undo.** A program that started calling
`wasi.env.get` stops type-checking. That population is empty on the day this
ships, and it grows from the moment it does. Worst-case unwind cost is one
revert plus one rebuild.

## Risks and unknowns

1. **The refusal guards an unbuilt mechanism.** Classify: spec drift. Cite: F1
   above, `LLMLL.md:1816` against `CodegenHs.hs:1607`. Bite: it complicates the
   diagnostic wording and it does not block. The rule is still correct, and it is
   correct EARLIER than the leak. The risk is that a reader takes the message as
   a description of current runtime behaviour.
2. **The seventh label changes a published report field.** Classify: DX and
   consumer surface. Cite: F2, `Spec.hs:11046`. Bite: complicates. Any consumer
   that enumerates `effect_summary` values sees a new one. Soundness is
   untouched, per `ObligationAssembly.hs:385-387`.
3. **The granted capability target is not enforced.** Classify: soundness of the
   access-control model. Cite: proposal section 4 case 4, `CAP-1-REAL`,
   `TypeCheck.hs:1894`, which compares the path and never reads
   `importCapability`. Bite: pre-existing, and it matters more here than
   elsewhere, because this namespace holds credentials by convention. This patch
   neither fixes it nor deepens it.
4. **A computed name conflates two failures.** Classify: spec gap, documented.
   Cite: proposal section 4 case 3. Bite: complicates. The literal rule cannot
   reach a computed argument, and the test suite pins that limit rather than
   hiding it.
5. **A module that reads the environment is not replayable in that value.**
   Classify: verification ergonomics. Cite: proposal section 3. Bite: accepted
   deliberately. F1 narrows this further: no `wasi.*` value is replayable today,
   because no capture runs.

## Open questions for the professor

1. F1 measured that `:deterministic` reaches no consumer except JSON
   serialisation, so no `wasi.*` return value is captured or injected at
   v0.14.99. `LLMLL.md:1789` item 8 claims replay is bitwise deterministic for
   modules that set the flag on clock and PRNG imports. **Does that claim hold
   for any module today, or is the whole sentence owed a correction rather than
   the scope amendment the proposal proposes?**

2. `env.read` is the first label in Σ_eff whose separate existence is motivated
   by the confidentiality of a returned value rather than by the authority the
   operation exercises. The label still denotes an operation, so the catalog's
   principle survives. **Does adding a label on that motive commit the catalog to
   a distinction it cannot sustain, given that
   `ObligationAssembly.hs:433-441` already records that Σ_eff cannot express
   authority amplification?**
